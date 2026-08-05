import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";

import type { Bead, BeadCounts } from "../types.ts";

const execFileAsync = promisify(execFile);

export type ClosedBead = {
  id: string;
  title: string | null;
  closedAt: string | null;
};

const statuses = new Map<string, keyof Omit<BeadCounts, "malformed">>([
  ["open", "open"],
  ["in_progress", "inProgress"],
  ["blocked", "blocked"],
  ["closed", "closed"],
]);

export async function readBeads(path: string): Promise<BeadCounts | null> {
  const records = await readBeadRecords(path);
  return records === null ? null : records.counts;
}

export async function readBeadRecords(
  path: string,
): Promise<{ counts: BeadCounts; inProgress: Bead[] } | null> {
  let contents: string;
  try {
    contents = await readFile(path, "utf8");
  } catch {
    return null;
  }

  const counts: BeadCounts = {
    open: 0,
    inProgress: 0,
    blocked: 0,
    closed: 0,
    malformed: 0,
  };
  const inProgress: Bead[] = [];
  for (const line of contents.split(/\r?\n/)) {
    if (line.trim() === "") {
      continue;
    }
    try {
      const record = JSON.parse(line) as Record<string, unknown>;
      const status =
        typeof record.status === "string"
          ? statuses.get(record.status)
          : undefined;
      if (status === undefined) {
        counts.malformed += 1;
      } else {
        counts[status] += 1;
        if (status === "inProgress" && typeof record.id === "string") {
          inProgress.push({
            id: record.id,
            title: typeof record.title === "string" ? record.title : null,
            assignee:
              typeof record.assignee === "string" ? record.assignee : null,
          });
        }
      }
    } catch {
      counts.malformed += 1;
    }
  }
  return { counts, inProgress };
}

export async function readClosedBeads(
  path: string,
  since: number,
  until: number,
): Promise<ClosedBead[] | null> {
  let stdout: string;
  try {
    ({ stdout } = await execFileAsync(
      "bd",
      [
        "--readonly",
        "-C",
        path,
        "list",
        "--all",
        "--status=closed",
        "--limit=0",
        `--closed-after=${new Date(since).toISOString()}`,
        `--closed-before=${new Date(until).toISOString()}`,
        "--json",
      ],
      { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
    ));
  } catch {
    return null;
  }
  try {
    const records = JSON.parse(stdout) as unknown;
    if (!Array.isArray(records)) {
      return null;
    }
    // The digest intentionally includes every bead type: gate, infrastructure,
    // and template work are all part of a fort's complete activity record.
    return records
      .flatMap((record) => {
        if (typeof record !== "object" || record === null) {
          return [];
        }
        const value = record as Record<string, unknown>;
        return typeof value.id === "string"
          ? [
              {
                id: value.id,
                title: typeof value.title === "string" ? value.title : null,
                closedAt:
                  typeof value.closed_at === "string" ? value.closed_at : null,
              },
            ]
          : [];
      })
      .sort((left, right) => left.id.localeCompare(right.id));
  } catch {
    return null;
  }
}
