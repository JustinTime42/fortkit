import { access } from "node:fs/promises";
import { join } from "node:path";

import { readBeadRecords } from "./readers/beads.ts";
import { readEventFeed } from "./readers/events.ts";
import { readGitState } from "./readers/git.ts";
import { readRegistry } from "./readers/registry.ts";
import type { Bead, EventDetail, GitState } from "./types.ts";

export type WorldFort = {
  name: string;
  path: string;
  present: boolean;
  git: GitState;
  beads: { ready: number; malformed: number } | null;
  inProgress: Array<Bead & { seat: string | null; model: string | null }>;
  announcements: string[];
  watcherAlerts: Array<{ detail: string; ts: string }>;
  gaps: string[];
};

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

function modelFor(bead: Bead, events: EventDetail[]): string | null {
  const event = events.find(
    (candidate) =>
      candidate.target === bead.id &&
      typeof candidate.payload === "object" &&
      candidate.payload !== null &&
      typeof (candidate.payload as Record<string, unknown>).model === "string",
  );
  if (typeof event?.payload !== "object" || event.payload === null) {
    return null;
  }
  const model = (event.payload as Record<string, unknown>).model;
  return typeof model === "string" ? model : null;
}

function seatFor(bead: Bead, events: EventDetail[]): string | null {
  return (
    events.find((event) => event.target === bead.id && event.seat !== null)
      ?.seat ?? null
  );
}

export async function readWorld(registryPath: string): Promise<WorldFort[]> {
  const forts = await readRegistry(registryPath);
  return Promise.all(
    forts.map(async ({ name, path }) => {
      if (!(await exists(path))) {
        return {
          name,
          path,
          present: false,
          git: {
            branch: null,
            ahead: null,
            behind: null,
            dirty: null,
            worktrees: null,
          },
          beads: null,
          inProgress: [],
          announcements: [],
          watcherAlerts: [],
          gaps: ["fort directory is absent"],
        };
      }
      const [beadRecords, eventFeed, git] = await Promise.all([
        readBeadRecords(join(path, ".beads", "issues.jsonl")),
        readEventFeed(join(path, "fort", "events")),
        readGitState(path),
      ]);
      const events = eventFeed?.events ?? [];
      const gaps: string[] = [];
      if (beadRecords === null) gaps.push("Beads export ABSENT");
      if (eventFeed === null) gaps.push("event stream ABSENT");
      if (beadRecords !== null && beadRecords.counts.malformed > 0) {
        gaps.push(`${beadRecords.counts.malformed} malformed Beads record(s)`);
      }
      if (eventFeed !== null && eventFeed.malformed > 0) {
        gaps.push(`${eventFeed.malformed} malformed event line(s)`);
      }
      if (git.dirty === null) gaps.push("git state unavailable");
      return {
        name,
        path,
        present: true,
        git,
        beads:
          beadRecords === null
            ? null
            : {
                ready: beadRecords.counts.open,
                malformed: beadRecords.counts.malformed,
              },
        inProgress:
          beadRecords?.inProgress.map((bead) => ({
            ...bead,
            seat: seatFor(bead, events),
            model: modelFor(bead, events),
          })) ?? [],
        announcements: events
          .flatMap((event) => (event.detail === null ? [] : [event.detail]))
          .slice(0, 5),
        watcherAlerts: events
          .flatMap((event) =>
            event.category === "watcher.alert" && event.detail !== null
              ? [{ detail: event.detail, ts: event.ts }]
              : [],
          )
          .slice(0, 5),
        gaps,
      };
    }),
  );
}
