import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

import type { LastEvent } from "../types.ts";

type EventRecord = { ts?: unknown; actor?: unknown };

export async function readLastEvent(
  eventsDirectory: string,
): Promise<LastEvent | null> {
  let files: string[];
  try {
    files = await readdir(eventsDirectory);
  } catch {
    return null;
  }

  let latest: { instant: number; event: LastEvent } | null = null;
  for (const file of files.filter((name) =>
    /^events-\d{4}-\d{2}-\d{2}\.jsonl$/.test(name),
  )) {
    let contents: string;
    try {
      contents = await readFile(join(eventsDirectory, file), "utf8");
    } catch {
      continue;
    }
    for (const line of contents.split(/\r?\n/)) {
      try {
        const record = JSON.parse(line) as EventRecord;
        if (typeof record.ts !== "string" || typeof record.actor !== "string") {
          continue;
        }
        const instant = Date.parse(record.ts);
        if (Number.isNaN(instant)) {
          continue;
        }
        const event = {
          ts: new Date(instant).toISOString(),
          actor: record.actor,
          utcDay: new Date(instant).toISOString().slice(0, 10),
        };
        if (latest === null || instant > latest.instant) {
          latest = { instant, event };
        }
      } catch {
        // An event shard is append-only and may contain a damaged line.
      }
    }
  }
  return latest?.event ?? null;
}
