import { readFile } from "node:fs/promises";

import type { BeadCounts } from "../types.ts";

const statuses = new Map<string, keyof Omit<BeadCounts, "malformed">>([
  ["open", "open"],
  ["in_progress", "inProgress"],
  ["blocked", "blocked"],
  ["closed", "closed"],
]);

export async function readBeads(path: string): Promise<BeadCounts | null> {
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
  for (const line of contents.split(/\r?\n/)) {
    if (line.trim() === "") {
      continue;
    }
    try {
      const record = JSON.parse(line) as { status?: unknown };
      const status =
        typeof record.status === "string"
          ? statuses.get(record.status)
          : undefined;
      if (status === undefined) {
        counts.malformed += 1;
      } else {
        counts[status] += 1;
      }
    } catch {
      counts.malformed += 1;
    }
  }
  return counts;
}
