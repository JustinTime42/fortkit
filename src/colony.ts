import type {
  Bead,
  ColonyBench,
  ColonyCitizen,
  ColonyProjection,
  ColonySession,
  ColonyWorkType,
  EventDetail,
} from "./types.ts";

export type ColonySources = {
  beads: Bead[] | null;
  worktrees: string[] | null;
  events: EventDetail[] | null;
  citizens: ColonyCitizen[] | null;
};

const workTypes: ColonyWorkType[] = ["implementation", "spec", "test", "infra"];

function eventTime(event: EventDetail): number {
  const time = Date.parse(event.ts);
  return Number.isNaN(time) ? Number.NEGATIVE_INFINITY : time;
}

function sessionKey(event: EventDetail): string {
  return event.target ?? event.seat ?? event.actor;
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
    if (previous === undefined || eventTime(event) > eventTime(previous)) {
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
      sessions.find((session) => worktreeForBead(worktree, session.beadId)) ??
      null,
  };
}

function hasWorkType(bead: Bead): boolean {
  return (
    bead.labels?.some((label) => workTypes.includes(label as ColonyWorkType)) ??
    false
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

  const beads = sources.beads ?? [];
  const sessions = activeSessions(sources.events ?? []);
  return {
    workshops: workTypes.map((type) => ({
      type,
      beads: beads.filter((bead) => bead.labels?.includes(type) ?? false),
    })),
    benches: (sources.worktrees ?? [])
      .slice()
      .sort((left, right) => left.localeCompare(right))
      .map((worktree) => benchFor(worktree, sessions)),
    dungeon: beads.filter(
      (bead) => bead.status === "open" && bead.issueType === "bug",
    ),
    citizens: (sources.citizens ?? []).slice(),
    // Never disappear a bead merely because its workflow label is absent or unknown.
    unassigned: beads.filter((bead) => !hasWorkType(bead)),
    gaps,
  };
}
