import { access } from "node:fs/promises";
import { join } from "node:path";
import type { ClosedBead } from "./readers/beads.ts";
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

type DigestFort = {
  name: string;
  path: string | null;
  present: boolean;
  events: EventDetail[] | null;
  eventsMalformed: number | null;
  closedBeads: ClosedBead[] | null;
  handoffSections: HandoffSection[] | null;
  gitLog: string[] | null;
  constitutionDiffs: ConstitutionDiff[] | null;
  telemetry: TelemetryCounts | null;
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
      gitLog: null,
      constitutionDiffs: null,
      telemetry: null,
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
  return {
    name,
    path,
    present: true,
    events:
      eventFeed === null
        ? null
        : eventFeed.events.filter((event) =>
            inWindow(event.ts, sinceInstant, untilInstant),
          ),
    eventsMalformed: eventFeed?.malformed ?? null,
    closedBeads:
      closedBeads === null
        ? null
        : closedBeads.filter(
            (bead) =>
              bead.closedAt !== null &&
              inWindow(bead.closedAt, sinceInstant, untilInstant),
          ),
    handoffSections:
      handoffSections === null
        ? null
        : handoffSections.filter((section) => {
            const dayStart = Date.parse(`${section.date}T00:00:00.000Z`);
            const dayEnd = dayStart + 24 * 60 * 60 * 1000;
            return dayStart < untilInstant && dayEnd > sinceInstant;
          }),
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
      `events: ${fort.events === null ? "ABSENT" : `${fort.events.length} (malformed ${fort.eventsMalformed})`}`,
      `closed beads: ${fort.closedBeads === null ? "ABSENT" : fort.closedBeads.length}`,
      `handoff sections: ${fort.handoffSections === null ? "ABSENT" : fort.handoffSections.length}`,
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
