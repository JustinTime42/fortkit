import { execFile } from "node:child_process";
import { access } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import type { ClosedBead, TelemetryCounts } from "./readers/digest.ts";
import { readClosedBeads, readTelemetryCounts } from "./readers/digest.ts";
import { readEventFeed } from "./readers/events.ts";
import { readHandoffSections } from "./readers/handoffs.ts";
import { readRegistryEntries } from "./readers/registry.ts";
import type { EventDetail } from "./types.ts";

const execFileAsync = promisify(execFile);

type DigestFort = {
  name: string;
  path: string | null;
  present: boolean;
  events: EventDetail[] | null;
  eventsMalformed: number | null;
  closedBeads: ClosedBead[] | null;
  handoffSections: Awaited<ReturnType<typeof readHandoffSections>>;
  gitLog: string[] | null;
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

async function readGitLog(
  path: string,
  since: string,
  until: string,
): Promise<string[] | null> {
  try {
    const { stdout } = await execFileAsync(
      "git",
      [
        "-C",
        path,
        "log",
        "--format=%cI%x09%h%x09%s",
        `--since=${since}`,
        `--before=${until}`,
      ],
      { encoding: "utf8" },
    );
    return stdout.trim() === "" ? [] : stdout.trimEnd().split("\n");
  } catch {
    return null;
  }
}

function inWindow(ts: string, since: number, until: number): boolean {
  const instant = Date.parse(ts);
  return !Number.isNaN(instant) && instant >= since && instant < until;
}

async function readDigestFort(
  name: string,
  path: string | null,
  since: string,
  until: string,
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
      telemetry: null,
    };
  }
  const [eventFeed, closedBeads, handoffSections, gitLog, telemetry] =
    await Promise.all([
      readEventFeed(join(path, "fort", "events")),
      readClosedBeads(path),
      readHandoffSections(join(path, "fort", "handoffs")),
      readGitLog(path, since, until),
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
  const forts = await readRegistryEntries(registryPath);
  return {
    since: new Date(sinceInstant).toISOString(),
    until: new Date(untilInstant).toISOString(),
    forts: await Promise.all(
      forts.map((fort) =>
        readDigestFort(
          fort.name,
          fort.path,
          since,
          until,
          sinceInstant,
          untilInstant,
        ),
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
      `telemetry: ${fort.telemetry === null ? "ABSENT" : `${fort.telemetry.records} records, ${fort.telemetry.files} files, ${fort.telemetry.malformed} malformed`}`,
    ]),
  ].join("\n");
}
