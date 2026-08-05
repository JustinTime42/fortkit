import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

export type TelemetryCounts = {
  files: number;
  records: number;
  malformed: number;
};

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
