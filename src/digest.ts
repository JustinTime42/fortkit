import { access } from "node:fs/promises";
import { join } from "node:path";
import type { ClosedBeadSource } from "./readers/beads.ts";
import { readClosedBeads } from "./readers/beads.ts";
import { readEventFeed } from "./readers/events.ts";
import type { ConstitutionDiff } from "./readers/git.ts";
import { readConstitutionDiffs, readGitLog } from "./readers/git.ts";
import type { HandoffSection } from "./readers/handoffs.ts";
import { readHandoffSections } from "./readers/handoffs.ts";
import { readRegistryEntries } from "./readers/registry.ts";
import type { TelemetryCounts } from "./readers/telemetry.ts";
import { readTelemetryCounts } from "./readers/telemetry.ts";
import type { EventDetail } from "./types.ts";

const maxEventsPerFort = 50;
const maxHandoffSectionsPerFort = 50;

type DigestFort = {
  name: string;
  path: string | null;
  present: boolean;
  events: EventDetail[] | null;
  eventsMalformed: number | null;
  closedBeads: ClosedBeadSource | null;
  handoffSections: HandoffSection[] | null;
  handoffSectionsTruncated: number | null;
  gitLog: string[] | null;
  constitutionDiffs: ConstitutionDiff[] | null;
  telemetry: TelemetryCounts | null;
  eventsTruncated: number | null;
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

async function readDigestFort(
  name: string,
  path: string | null,
  sinceInstant: number,
  untilInstant: number,
): Promise<DigestFort> {
  if (path === null || !(await exists(path))) {
    return {
      name,
      path,
      present: false,
      events: null,
      eventsMalformed: null,
      closedBeads: null,
      handoffSections: null,
      handoffSectionsTruncated: null,
      gitLog: null,
      constitutionDiffs: null,
      telemetry: null,
      eventsTruncated: null,
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
  return {
    name,
    path,
    present: true,
    events: events === undefined ? null : events.slice(0, maxEventsPerFort),
    eventsMalformed: eventFeed?.malformed ?? null,
    eventsTruncated:
      events === undefined
        ? null
        : Math.max(0, events.length - maxEventsPerFort),
    closedBeads,
    handoffSections:
      filteredHandoffSections === null
        ? null
        : filteredHandoffSections.slice(0, maxHandoffSectionsPerFort),
    handoffSectionsTruncated:
      filteredHandoffSections === null
        ? null
        : Math.max(
            0,
            filteredHandoffSections.length - maxHandoffSectionsPerFort,
          ),
    gitLog,
    constitutionDiffs,
    telemetry,
  };
}

export async function readCivilizationDigest(
  registryPath: string,
  since: string,
  until: string,
): Promise<CivilizationDigest> {
  const sinceInstant = Date.parse(since);
  const untilInstant = Date.parse(until);
  if (Number.isNaN(sinceInstant) || Number.isNaN(untilInstant)) {
    throw new Error("Digest window timestamps must be valid dates");
  }
  if (sinceInstant >= untilInstant) {
    throw new Error("Digest window must have since before until");
  }
  const forts = await readRegistryEntries(registryPath);
  return {
    since: new Date(sinceInstant).toISOString(),
    until: new Date(untilInstant).toISOString(),
    forts: await Promise.all(
      forts.map((fort) =>
        readDigestFort(fort.name, fort.path, sinceInstant, untilInstant),
      ),
    ),
  };
}

export function formatDigest(digest: CivilizationDigest): string {
  return [
    `Digest window: ${digest.since} to ${digest.until} (until exclusive)`,
    ...digest.forts.flatMap((fort) => [
      "",
      `# ${fort.name} — ${fort.present ? "present" : "ABSENT"}`,
      `events: ${fort.events === null ? "ABSENT" : `${fort.events.length} (malformed ${fort.eventsMalformed}; truncated ${fort.eventsTruncated})`}`,
      `closed beads: ${formatClosedBeads(fort.closedBeads)}`,
      `handoff sections: ${fort.handoffSections === null ? "ABSENT" : `${fort.handoffSections.length} (truncated ${fort.handoffSectionsTruncated})`}`,
      `git log: ${fort.gitLog === null ? "ABSENT" : fort.gitLog.length}`,
      `constitution diffs: ${fort.constitutionDiffs === null ? "ABSENT" : fort.constitutionDiffs.length}`,
      ...(fort.constitutionDiffs ?? []).map(
        (diff) =>
          `  ! ${diff.ts} ${diff.hash} ${diff.subject} [${diff.beadRef ?? "NO BEAD REF"}] (${diff.files.join(", ")})`,
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
