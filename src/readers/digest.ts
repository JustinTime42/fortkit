import { execFile } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export type ClosedBead = {
  id: string;
  title: string | null;
  closedAt: string | null;
};

export type TelemetryCounts = {
  files: number;
  records: number;
  malformed: number;
};

export async function readClosedBeads(
  path: string,
): Promise<ClosedBead[] | null> {
  let stdout: string;
  try {
    ({ stdout } = await execFileAsync(
      "bd",
      ["-C", path, "list", "--status=closed", "--json"],
      { encoding: "utf8" },
    ));
  } catch {
    return null;
  }
  try {
    const records = JSON.parse(stdout) as unknown;
    if (!Array.isArray(records)) {
      return null;
    }
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

export async function readTelemetryCounts(
  directory: string,
  since: number,
  until: number,
): Promise<TelemetryCounts | null> {
  let files: string[];
  try {
    files = await readdir(directory);
  } catch {
    return null;
  }
  const counts: TelemetryCounts = { files: 0, records: 0, malformed: 0 };
  for (const file of files.filter((name) => name.endsWith(".jsonl")).sort()) {
    let contents: string;
    try {
      contents = await readFile(join(directory, file), "utf8");
    } catch {
      counts.malformed += 1;
      continue;
    }
    counts.files += 1;
    for (const line of contents.split(/\r?\n/)) {
      if (line.trim() === "") {
        continue;
      }
      try {
        const record = JSON.parse(line) as Record<string, unknown>;
        const instant =
          typeof record.ts === "string" ? Date.parse(record.ts) : NaN;
        if (Number.isNaN(instant)) {
          counts.malformed += 1;
        } else if (instant >= since && instant < until) {
          counts.records += 1;
        }
      } catch {
        counts.malformed += 1;
      }
    }
  }
  return counts;
}
