/** Clockwork off-duty life. All schedule calculations use UTC, never host time. */
export type AmbientActivity =
  | "sleeping"
  | "breakfasting"
  | "lunching"
  | "dining"
  | "socializing"
  | "reading"
  | "walking"
  | "fishing"
  | "tinkering";

/** Places present in the colony's fixed layout; homes are one per citizen. */
export type AmbientPlace = `home:${string}` | "tavern" | "archive" | "walls";

export type AmbientState = {
  activity: AmbientActivity;
  place: AmbientPlace;
};

export type AmbientTimestamp = Date | number | string;

const dayMilliseconds = 24 * 60 * 60 * 1000;
const quarterHourMilliseconds = 15 * 60 * 1000;

// Keep fishing last: Kethra's identity hash selects it as her favourite.
const pursuits: ReadonlyArray<readonly [AmbientActivity, AmbientPlace]> = [
  ["reading", "archive"],
  ["walking", "walls"],
  ["tinkering", "archive"],
  ["fishing", "walls"],
];

function hash(value: string): number {
  let result = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    result ^= value.charCodeAt(index);
    result = Math.imul(result, 0x01000193);
  }
  return result >>> 0;
}

function millisecondsAt(timestamp: AmbientTimestamp): number {
  const value =
    timestamp instanceof Date
      ? timestamp.getTime()
      : typeof timestamp === "number"
        ? timestamp
        : Date.parse(timestamp);
  if (!Number.isFinite(value)) {
    throw new RangeError(`Invalid ambient timestamp: ${String(timestamp)}`);
  }
  return value;
}

function utcMinute(timestamp: number): number {
  const date = new Date(timestamp);
  return date.getUTCHours() * 60 + date.getUTCMinutes();
}

function minuteInWindow(minute: number, start: number, end: number): boolean {
  return start <= end
    ? minute >= start && minute < end
    : minute >= start || minute < end;
}

function home(citizenId: string): AmbientPlace {
  return `home:${citizenId}`;
}

function sharedWindow(
  minute: number,
  identity: string,
  name: string,
  coreStart: number,
  coreEnd: number,
): boolean {
  // Everyone shares the core; deterministic approach/departure jitter gives
  // the Tavern arrivals and exits without ever making a citizen eat alone.
  const approach = hash(`${identity}\u0000${name}\u0000arrival`) % 2;
  const departure = hash(`${identity}\u0000${name}\u0000departure`) % 2;
  return (
    minute >= coreStart - 15 * (approach + 1) &&
    minute < coreEnd + 15 * (departure + 1)
  );
}

/** A stable numeric seed derived from a fort name for callers that need one. */
export function fortSeedFor(fortName: string): number {
  return hash(fortName);
}

/**
 * Return a citizen's off-duty state at an instant.
 *
 * Shared Tavern cores deliberately take precedence over personal variation:
 * citizens are guaranteed company at meals and the evening social.
 */
export function activity(
  citizenId: string,
  timestamp: AmbientTimestamp,
  fortSeed: number,
): AmbientState {
  const instant = millisecondsAt(timestamp);
  const minute = utcMinute(instant);
  const identity = `${fortSeed}\u0000${citizenId}`;
  // Keep personal variation aligned with the summary's quarter-hour resolution.
  const sleepStart = 21 * 60 + (hash(identity) % 5) * 30;
  if (minuteInWindow(minute, sleepStart, (sleepStart + 8 * 60) % 1440)) {
    return { activity: "sleeping", place: home(citizenId) };
  }

  if (sharedWindow(minute, identity, "breakfast", 7 * 60 + 15, 7 * 60 + 45)) {
    return { activity: "breakfasting", place: "tavern" };
  }
  if (sharedWindow(minute, identity, "lunch", 12 * 60 + 15, 12 * 60 + 45)) {
    return { activity: "lunching", place: "tavern" };
  }
  if (sharedWindow(minute, identity, "dinner", 18 * 60 + 15, 18 * 60 + 45)) {
    return { activity: "dining", place: "tavern" };
  }
  if (sharedWindow(minute, identity, "social", 19 * 60 + 30, 20 * 60 + 30)) {
    return { activity: "socializing", place: "tavern" };
  }

  const day = Math.floor(instant / dayMilliseconds);
  const block = Math.floor(minute / 180);
  const favourite = pursuits[hash(identity) % pursuits.length];
  const pursuit =
    hash(`${identity}\u0000${day}\u0000${block}\u0000pursuit`) % 8 < 6
      ? favourite
      : pursuits[
          hash(`${identity}\u0000${day}\u0000${block}\u0000variety`) %
            pursuits.length
        ];
  // The indices are bounded by modulo above; retain the fallback for totality.
  return pursuit === undefined
    ? { activity: "reading", place: "archive" }
    : { activity: pursuit[0], place: pursuit[1] };
}

function clock(timestamp: number): string {
  const date = new Date(timestamp);
  return `${String(date.getUTCHours()).padStart(2, "0")}:${String(date.getUTCMinutes()).padStart(2, "0")}`;
}

function formatAmbientWindow(
  citizenId: string,
  start: number,
  end: number,
  fortSeed: number,
): string[] {
  if (start >= end)
    throw new RangeError("Ambient interval must have a positive duration");
  const spans: Array<{ start: number; end: number; state: AmbientState }> = [];
  for (let cursor = start; cursor < end; ) {
    const next = Math.min(
      end,
      (Math.floor(cursor / quarterHourMilliseconds) + 1) *
        quarterHourMilliseconds,
    );
    const state = activity(citizenId, cursor, fortSeed);
    const previous = spans.at(-1);
    if (
      previous !== undefined &&
      previous.state.activity === state.activity &&
      previous.state.place === state.place
    ) {
      previous.end = next;
    } else {
      spans.push({ start: cursor, end: next, state });
    }
    cursor = next;
  }
  return spans.map(
    ({ start: spanStart, end: spanEnd, state }) =>
      `${clock(spanStart)}–${clock(spanEnd)} ${state.activity} at ${state.place}`,
  );
}

/** Render the UTC day containing timestamp as contiguous, human-readable spans. */
export function formatAmbientDay(
  citizenId: string,
  timestamp: AmbientTimestamp,
  fortSeed: number,
): string {
  const instant = millisecondsAt(timestamp);
  const dayStart = Math.floor(instant / dayMilliseconds) * dayMilliseconds;
  const date = new Date(dayStart).toISOString().slice(0, 10);
  return [
    `Ambient schedule for ${citizenId} — ${date} UTC`,
    ...formatAmbientWindow(
      citizenId,
      dayStart,
      dayStart + dayMilliseconds,
      fortSeed,
    ),
  ].join("\n");
}

/**
 * Render only the lived interval since `since`, through `until` (now by
 * default). This is the launcher-facing --since semantics; --on renders a
 * whole containing UTC day instead.
 */
export function formatAmbientSince(
  citizenId: string,
  since: AmbientTimestamp,
  fortSeed: number,
  until: AmbientTimestamp = Date.now(),
): string {
  const start = millisecondsAt(since);
  const end = millisecondsAt(until);
  return [
    `Ambient schedule for ${citizenId} — since ${new Date(start).toISOString()} through ${new Date(end).toISOString()} UTC`,
    ...formatAmbientWindow(citizenId, start, end, fortSeed),
  ].join("\n");
}
