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

export type AmbientState = {
  activity: AmbientActivity;
  place: string;
};

export type AmbientTimestamp = Date | number | string;

const dayMilliseconds = 24 * 60 * 60 * 1000;
const pursuits: ReadonlyArray<readonly [AmbientActivity, string]> = [
  ["reading", "archive"],
  ["walking", "walls"],
  ["fishing", "river"],
  ["tinkering", "tinker-bench"],
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
  return Number.isFinite(value) ? value : 0;
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

function home(citizenId: string): string {
  return `home:${citizenId}`;
}

/** A stable numeric seed derived from a fort name for callers that need one. */
export function fortSeedFor(fortName: string): number {
  return hash(fortName);
}

/**
 * Return a citizen's off-duty state at an instant.
 *
 * Shared Tavern windows deliberately take precedence over personal variation:
 * citizens are guaranteed company at lunch, dinner, and the evening social.
 */
export function activity(
  citizenId: string,
  timestamp: AmbientTimestamp,
  fortSeed: string | number,
): AmbientState {
  const instant = millisecondsAt(timestamp);
  const minute = utcMinute(instant);
  const identity = `${fortSeed}\u0000${citizenId}`;
  // Keep personal variation aligned with the summary's half-hour resolution.
  const sleepStart = 21 * 60 + (hash(identity) % 5) * 30;
  if (minuteInWindow(minute, sleepStart, (sleepStart + 8 * 60) % 1440)) {
    return { activity: "sleeping", place: home(citizenId) };
  }

  // These communal windows are intentionally not offset per citizen.
  if (minute >= 7 * 60 && minute < 8 * 60) {
    return { activity: "breakfasting", place: "tavern" };
  }
  if (minute >= 12 * 60 && minute < 13 * 60) {
    return { activity: "lunching", place: "tavern" };
  }
  if (minute >= 18 * 60 && minute < 19 * 60) {
    return { activity: "dining", place: "tavern" };
  }
  if (minute >= 19 * 60 && minute < 21 * 60) {
    return { activity: "socializing", place: "tavern" };
  }

  const day = Math.floor(instant / dayMilliseconds);
  const pursuit =
    pursuits[
      hash(`${identity}\u0000${day}\u0000${Math.floor(minute / 180)}`) %
        pursuits.length
    ];
  // The index is bounded by the modulo above; retain the fallback for totality.
  return pursuit === undefined
    ? { activity: "reading", place: "archive" }
    : { activity: pursuit[0], place: pursuit[1] };
}

function clock(minute: number): string {
  return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
}

/** Render the UTC day containing timestamp as contiguous, human-readable spans. */
export function formatAmbientDay(
  citizenId: string,
  timestamp: AmbientTimestamp,
  fortSeed: string | number,
): string {
  const instant = millisecondsAt(timestamp);
  const dayStart = Math.floor(instant / dayMilliseconds) * dayMilliseconds;
  const spans: Array<{ start: number; end: number; state: AmbientState }> = [];
  for (let minute = 0; minute < 1440; minute += 30) {
    const state = activity(citizenId, dayStart + minute * 60_000, fortSeed);
    const previous = spans.at(-1);
    if (
      previous !== undefined &&
      previous.state.activity === state.activity &&
      previous.state.place === state.place
    ) {
      previous.end = minute + 30;
    } else {
      spans.push({ start: minute, end: minute + 30, state });
    }
  }
  const date = new Date(dayStart).toISOString().slice(0, 10);
  return [
    `Ambient schedule for ${citizenId} — ${date} UTC`,
    ...spans.map(
      ({ start, end, state }) =>
        `${clock(start)}–${clock(end % 1440)} ${state.activity} at ${state.place}`,
    ),
  ].join("\n");
}
