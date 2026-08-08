import type {
  Bead,
  ColonyBench,
  ColonyCitizen,
  ColonyProjection,
  ColonySession,
  ColonyWorkType,
} from "./page-types.ts";
import type { EventDetail } from "./types.ts";

export type ColonySources = {
  beads: Bead[] | null;
  worktrees: string[] | null;
  events: EventDetail[] | null;
  citizens: ColonyCitizen[] | null;
};

const workTypes: ColonyWorkType[] = ["implementation", "spec", "test", "infra"];

// A bench represents a git worktree, not every seat that emits session events.
// Today only Forge sessions create the per-bead worktrees that can occupy one;
// review sessions run in scratch copies and must never decorate a Forge bench.
const worktreeHoldingSeats = new Set(["forge"]);

function eventTime(event: EventDetail): number {
  const time = Date.parse(event.ts);
  return Number.isNaN(time) ? Number.NEGATIVE_INFINITY : time;
}

function sessionKey(event: EventDetail): string {
  const seatOrActor = event.seat ?? event.actor;
  return `${seatOrActor}\u0000${event.target ?? ""}`;
}

function modelFor(event: EventDetail): string | null {
  if (typeof event.payload !== "object" || event.payload === null) {
    return null;
  }
  const model = (event.payload as Record<string, unknown>).model;
  return typeof model === "string" ? model : null;
}

function activeSessions(events: EventDetail[]): ColonySession[] {
  const latest = new Map<string, EventDetail>();
  for (const event of events) {
    if (
      event.category !== "session.start" &&
      event.category !== "session.end"
    ) {
      continue;
    }
    const key = sessionKey(event);
    const previous = latest.get(key);
    // Event files are append-only, so later records settle equal (including
    // unparseable) timestamps. An end event must therefore clear its start.
    if (previous === undefined || eventTime(event) >= eventTime(previous)) {
      latest.set(key, event);
    }
  }
  return [...latest.values()]
    .filter((event) => event.category === "session.start")
    .map((event) => ({
      actor: event.actor,
      seat: event.seat,
      beadId: event.target,
      model: modelFor(event),
      startedAt: event.ts,
    }))
    .sort((left, right) => right.startedAt.localeCompare(left.startedAt));
}

function worktreeForBead(worktree: string, beadId: string | null): boolean {
  if (beadId === null) return false;
  const shortId = beadId.replace(/^[^-]+-/, "");
  return worktree.endsWith(`/${shortId}`) || worktree.endsWith(`\\${shortId}`);
}

function benchFor(worktree: string, sessions: ColonySession[]): ColonyBench {
  return {
    worktree,
    session:
      sessions.find(
        (session) =>
          session.seat !== null &&
          worktreeHoldingSeats.has(session.seat) &&
          worktreeForBead(worktree, session.beadId),
      ) ?? null,
  };
}

function hasWorkType(bead: Bead): boolean {
  return (
    bead.labels?.some((label) => workTypes.includes(label as ColonyWorkType)) ??
    false
  );
}

function isLive(bead: Bead): boolean {
  return bead.status !== "closed";
}

function comparePaths(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function citizensWithActivity(
  citizens: ColonyCitizen[],
  sessions: ColonySession[],
): ColonyCitizen[] {
  return citizens.map((citizen) => {
    const session = sessions.find(
      (candidate) =>
        candidate.seat?.toLocaleLowerCase() ===
        citizen.seat.toLocaleLowerCase(),
    );
    return {
      ...citizen,
      currentBead: session?.beadId ?? null,
      session: session ?? null,
    };
  });
}

function eventQueue(
  beads: Bead[],
  events: EventDetail[],
  category: string,
): Bead[] {
  const byId = new Map(beads.map((bead) => [bead.id, bead]));
  const targets = new Set(
    events
      .filter((event) => event.category === category && event.target !== null)
      .map((event) => event.target as string),
  );
  return [...targets].flatMap((target) => {
    const bead = byId.get(target);
    return bead === undefined ? [] : [bead];
  });
}

/** A review remains at the depot until a later merge records its departure. */
function depotQueue(beads: Bead[], events: EventDetail[]): Bead[] {
  const latest = new Map<string, EventDetail>();
  for (const event of events) {
    if (
      event.target === null ||
      (event.category !== "review.verdict" && event.category !== "merge")
    )
      continue;
    const previous = latest.get(event.target);
    if (previous === undefined || eventTime(event) >= eventTime(previous)) {
      latest.set(event.target, event);
    }
  }
  const byId = new Map(beads.map((bead) => [bead.id, bead]));
  return [...latest.entries()].flatMap(([target, event]) =>
    event.category === "review.verdict" && byId.has(target)
      ? [byId.get(target) as Bead]
      : [],
  );
}

/**
 * Projects read-only fort data into colony entities. Beads supply present state;
 * events only decorate active benches and their absence never changes that state.
 */
export function projectColony(sources: ColonySources): ColonyProjection {
  const gaps: string[] = [];
  if (sources.beads === null) gaps.push("Beads export ABSENT");
  if (sources.worktrees === null) gaps.push("git worktree list ABSENT");
  if (sources.events === null) gaps.push("event stream ABSENT");
  if (sources.citizens === null) gaps.push("seats roster ABSENT");
  if (sources.citizens?.length === 0) {
    gaps.push("seats roster present, nothing parsed");
  }

  // Closed beads belong to the replay/history view, rather than the live
  // colony. Keep every other workflow state visible: an in-progress or
  // blocked bug is still in rehabilitation until it is closed.
  const beads = (sources.beads ?? []).filter(isLive);
  const sessions = activeSessions(sources.events ?? []);
  const events = sources.events ?? [];
  return {
    beads,
    intake: eventQueue(beads, events, "bead.filed"),
    jobBoard: beads.filter(
      (bead) => bead.status === "open" || bead.status === "blocked",
    ),
    depot: depotQueue(beads, events),
    workshops: workTypes.map((type) => ({
      type,
      beads: beads.filter((bead) => bead.labels?.includes(type) ?? false),
    })),
    benches: (sources.worktrees ?? [])
      .slice()
      .sort(comparePaths)
      .map((worktree) => benchFor(worktree, sessions)),
    dungeon: beads.filter((bead) => bead.issueType === "bug"),
    citizens: citizensWithActivity((sources.citizens ?? []).slice(), sessions),
    // Never disappear a bead merely because its workflow label is absent or unknown.
    unassigned: beads.filter((bead) => !hasWorkType(bead)),
    announcements: (sources.events ?? [])
      .flatMap((event) => (event.detail === null ? [] : [event.detail]))
      .slice(0, 8),
    gaps,
  };
}
