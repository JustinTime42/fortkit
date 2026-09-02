import { access } from "node:fs/promises";
import { join } from "node:path";
import type { ClosedBeadSource } from "./readers/beads.ts";
import { readClosedBeads } from "./readers/beads.ts";
import { readEventFeed } from "./readers/events.ts";
import type { UncorrelatedConstitutionDiff } from "./readers/git.ts";
import { readConstitutionDiffs, readGitLog } from "./readers/git.ts";
import type {
  HandoffSection,
  HandoffSectionIndex,
} from "./readers/handoffs.ts";
import {
  indexHandoffSections,
  readHandoffSections,
} from "./readers/handoffs.ts";
import { readRegistryEntries } from "./readers/registry.ts";
import type { TelemetryCounts } from "./readers/telemetry.ts";
import { readTelemetryCounts } from "./readers/telemetry.ts";
import type {
  ConstitutionDiff,
  EventDetail,
  EventShardHealth,
} from "./types.ts";

const defaultMaxEventsPerFort = 1_000;
const maxHandoffSectionsPerFort = 50;

export type EventTruncationComposition = {
  category: string | null;
  day: string;
  count: number;
};

export type DigestOptions = {
  maxEventsPerFort?: number;
};

type DigestFort = {
  name: string;
  path: string | null;
  present: boolean;
  events: EventDetail[] | null;
  eventsMalformed: number | null;
  eventsUnreadable: number | null;
  closedBeads: ClosedBeadSource | null;
  handoffSections: HandoffSection[] | null;
  handoffSectionIndex: HandoffSectionIndex[] | null;
  handoffSectionsTruncated: number | null;
  gitLog: string[] | null;
  constitutionDiffs: ConstitutionDiff[] | null;
  telemetry: TelemetryCounts | null;
  eventsTruncated: number | null;
  eventsTruncatedComposition: EventTruncationComposition[] | null;
};

export type CivilizationDigest = {
  since: string;
  until: string;
  forts: DigestFort[];
};

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

function inWindow(ts: string, since: number, until: number): boolean {
  const instant = Date.parse(ts);
  return !Number.isNaN(instant) && instant >= since && instant < until;
}

function shardHealthInWindow(
  shards: Record<string, EventShardHealth>,
  since: number,
  until: number,
): { malformed: number; unreadable: number } {
  return Object.entries(shards).reduce(
    (total, [file, shard]) => {
      const date = /^events-(\d{4}-\d{2}-\d{2})\.jsonl$/.exec(file)?.[1];
      if (date === undefined) {
        return {
          malformed: total.malformed + shard.malformed,
          unreadable: total.unreadable + Number(shard.unreadable),
        };
      }
      const dayStart = Date.parse(`${date}T00:00:00.000Z`);
      if (Number.isNaN(dayStart)) {
        return {
          malformed: total.malformed + shard.malformed,
          unreadable: total.unreadable + Number(shard.unreadable),
        };
      }
      // Filenames use the writer's local date, not UTC. Retain a malformed
      // shard unless its possible UTC span is wholly outside the digest window.
      const earliest = dayStart - 14 * 60 * 60 * 1000;
      const latest = dayStart + 36 * 60 * 60 * 1000;
      if (earliest >= until || latest <= since) return total;
      return {
        malformed: total.malformed + shard.malformed,
        unreadable: total.unreadable + Number(shard.unreadable),
      };
    },
    { malformed: 0, unreadable: 0 },
  );
}

function correlateConstitutionDiffs(
  diffs: UncorrelatedConstitutionDiff[] | null,
  events: EventDetail[] | null,
  eventsMalformed: number | null,
  eventsUnreadable: number | null,
): ConstitutionDiff[] | null {
  if (diffs === null) return null;
  if (
    events === null ||
    eventsMalformed === null ||
    eventsUnreadable === null
  ) {
    return diffs.map((diff) => ({
      ...diff,
      announced: "indeterminate",
      announcedBeadRef: null,
    }));
  }
  const announcedBeads = new Set(
    events.flatMap((event) =>
      event.category === "charter.amended" && event.target !== null
        ? [event.target]
        : [],
    ),
  );
  return diffs.map((diff) => {
    const announcedBeadRef = diff.beadRefs.find((beadRef) =>
      announcedBeads.has(beadRef),
    );
    if (announcedBeadRef !== undefined) {
      return {
        ...diff,
        announced: "announced",
        announcedBeadRef,
      };
    }
    return {
      ...diff,
      announced:
        eventsMalformed > 0 || eventsUnreadable > 0
          ? "indeterminate"
          : "unannounced",
      announcedBeadRef: null,
    };
  });
}

async function readDigestFort(
  name: string,
  path: string | null,
  sinceInstant: number,
  untilInstant: number,
  maxEventsPerFort: number,
): Promise<DigestFort> {
  if (path === null || !(await exists(path))) {
    return {
      name,
      path,
      present: false,
      events: null,
      eventsMalformed: null,
      eventsUnreadable: null,
      closedBeads: null,
      handoffSections: null,
      handoffSectionIndex: null,
      handoffSectionsTruncated: null,
      gitLog: null,
      constitutionDiffs: null,
      telemetry: null,
      eventsTruncated: null,
      eventsTruncatedComposition: null,
    };
  }
  const [
    eventFeed,
    closedBeads,
    handoffSections,
    gitLog,
    constitutionDiffs,
    telemetry,
  ] = await Promise.all([
    readEventFeed(join(path, "fort", "events")),
    readClosedBeads(path, sinceInstant, untilInstant),
    readHandoffSections(join(path, "fort", "handoffs")),
    readGitLog(path, sinceInstant, untilInstant),
    readConstitutionDiffs(path, sinceInstant, untilInstant),
    readTelemetryCounts(
      join(path, "fort", "telemetry"),
      sinceInstant,
      untilInstant,
    ),
  ]);
  const events = eventFeed?.events.filter((event) =>
    inWindow(event.ts, sinceInstant, untilInstant),
  );
  const filteredHandoffSections =
    handoffSections === null
      ? null
      : handoffSections.filter((section) => {
          const dayStart = Date.parse(`${section.date}T00:00:00.000Z`);
          const dayEnd = dayStart + 24 * 60 * 60 * 1000;
          return dayStart < untilInstant && dayEnd > sinceInstant;
        });
  const fullWindowEvents = events === undefined ? null : events;
  const truncatedEvents = fullWindowEvents?.slice(maxEventsPerFort) ?? null;
  const eventHealth =
    eventFeed === null
      ? null
      : shardHealthInWindow(eventFeed.shards, sinceInstant, untilInstant);
  const eventsMalformed = eventHealth?.malformed ?? null;
  const eventsUnreadable = eventHealth?.unreadable ?? null;
  return {
    name,
    path,
    present: true,
    events:
      fullWindowEvents === null
        ? null
        : fullWindowEvents.slice(0, maxEventsPerFort),
    eventsMalformed,
    eventsUnreadable,
    eventsTruncated:
      events === undefined
        ? null
        : Math.max(0, events.length - maxEventsPerFort),
    eventsTruncatedComposition:
      truncatedEvents === null
        ? null
        : [
            ...truncatedEvents
              .reduce((counts, event) => {
                const category = event.category;
                const day = event.ts.slice(0, 10);
                const key = `${category ?? ""}\u0000${day}`;
                const current = counts.get(key) ?? { category, day, count: 0 };
                current.count += 1;
                counts.set(key, current);
                return counts;
              }, new Map<string, EventTruncationComposition>())
              .values(),
          ],
    closedBeads,
    handoffSections:
      filteredHandoffSections === null
        ? null
        : filteredHandoffSections.slice(0, maxHandoffSectionsPerFort),
    handoffSectionIndex:
      filteredHandoffSections === null
        ? null
        : indexHandoffSections(name, filteredHandoffSections),
    handoffSectionsTruncated:
      filteredHandoffSections === null
        ? null
        : Math.max(
            0,
            filteredHandoffSections.length - maxHandoffSectionsPerFort,
          ),
    gitLog,
    constitutionDiffs: correlateConstitutionDiffs(
      constitutionDiffs,
      fullWindowEvents,
      eventsMalformed,
      eventsUnreadable,
    ),
    telemetry,
  };
}

export async function readCivilizationDigest(
  registryPath: string,
  since: string,
  until: string,
  options: DigestOptions = {},
): Promise<CivilizationDigest> {
  const sinceInstant = Date.parse(since);
  const untilInstant = Date.parse(until);
  if (Number.isNaN(sinceInstant) || Number.isNaN(untilInstant)) {
    throw new Error("Digest window timestamps must be valid dates");
  }
  if (sinceInstant >= untilInstant) {
    throw new Error("Digest window must have since before until");
  }
  const maxEventsPerFort = options.maxEventsPerFort ?? defaultMaxEventsPerFort;
  if (!Number.isSafeInteger(maxEventsPerFort) || maxEventsPerFort < 1) {
    throw new Error("Digest event cap must be a positive integer");
  }
  const forts = await readRegistryEntries(registryPath);
  return {
    since: new Date(sinceInstant).toISOString(),
    until: new Date(untilInstant).toISOString(),
    forts: await Promise.all(
      forts.map((fort) =>
        readDigestFort(
          fort.name,
          fort.path,
          sinceInstant,
          untilInstant,
          maxEventsPerFort,
        ),
      ),
    ),
  };
}

export async function fetchHandoffSections(
  registryPath: string,
  since: string,
  until: string,
  ids: string[],
): Promise<(HandoffSectionIndex & { body: string })[]> {
  const digest = await readCivilizationDigest(registryPath, since, until);
  const wanted = new Set(ids);
  const found = new Map<string, HandoffSectionIndex & { body: string }>();
  const sinceInstant = Date.parse(since);
  const untilInstant = Date.parse(until);
  for (const fort of digest.forts) {
    if (fort.path === null || fort.handoffSectionIndex === null) continue;
    const sections = await readHandoffSections(
      join(fort.path, "fort", "handoffs"),
    );
    if (sections === null) continue;
    const windowed = sections.filter((section) => {
      const dayStart = Date.parse(`${section.date}T00:00:00.000Z`);
      return (
        dayStart < untilInstant && dayStart + 24 * 60 * 60 * 1000 > sinceInstant
      );
    });
    const index = indexHandoffSections(fort.name, windowed);
    for (const [position, entry] of index.entries()) {
      if (wanted.has(entry.id)) {
        found.set(entry.id, { ...entry, body: windowed[position]?.body ?? "" });
      }
    }
  }
  const missing = ids.filter((id) => !found.has(id));
  if (missing.length > 0) {
    throw new Error(
      `Handoff section id not in digest window: ${missing.join(", ")}`,
    );
  }
  return ids.map(
    (id) => found.get(id) as HandoffSectionIndex & { body: string },
  );
}

export function formatDigest(digest: CivilizationDigest): string {
  return [
    `Digest window: ${digest.since} to ${digest.until} (until exclusive)`,
    ...digest.forts.flatMap((fort) => [
      "",
      `# ${fort.name} — ${fort.present ? "present" : "ABSENT"}`,
      `events: ${fort.events === null ? "ABSENT" : `${fort.events.length} (malformed ${fort.eventsMalformed}; unreadable ${fort.eventsUnreadable}; truncated ${fort.eventsTruncated})`}`,
      ...(fort.eventsTruncatedComposition?.length === 0 ||
      fort.eventsTruncatedComposition === null
        ? []
        : [
            `event truncation composition: ${fort.eventsTruncatedComposition.map((entry) => `${entry.count} ${entry.category ?? "uncategorized"} on ${entry.day}`).join("; ")}`,
          ]),
      `closed beads: ${formatClosedBeads(fort.closedBeads)}`,
      `handoff sections: ${fort.handoffSections === null ? "ABSENT" : `${fort.handoffSections.length} (truncated ${fort.handoffSectionsTruncated})`}`,
      `git log: ${fort.gitLog === null ? "ABSENT" : fort.gitLog.length}`,
      `constitution diffs: ${fort.constitutionDiffs === null ? "ABSENT" : fort.constitutionDiffs.length}`,
      ...(fort.constitutionDiffs ?? []).map(
        (diff) =>
          `  ! ${diff.ts} ${diff.hash} ${diff.subject} [${diff.beadRefs.join(", ") || "NO BEAD REF"}] (${diff.announced}${diff.announcedBeadRef === null ? "" : `: ${diff.announcedBeadRef}`}; ${diff.files.join(", ")})`,
      ),
      `telemetry: ${fort.telemetry === null ? "ABSENT" : `${fort.telemetry.records} records, ${fort.telemetry.files} files, ${fort.telemetry.malformed} malformed`}`,
    ]),
  ].join("\n");
}

function formatClosedBeads(source: ClosedBeadSource | null): string {
  if (source === null) return "ABSENT";
  if (source.status === "error") return `ERROR — ${source.error}`;
  return `${source.beads.length} (export ${source.exportStale ? "STALE" : "fresh"}; updated ${source.exportUpdatedAt}; age ${source.exportAgeSeconds}s)`;
}
