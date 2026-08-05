import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

import type { EventDetail, EventFeed, LastEvent } from "../types.ts";

type EventRecord = Record<string, unknown>;

export async function readLastEvent(
  eventsDirectory: string,
): Promise<LastEvent | null> {
  const feed = await readEventFeed(eventsDirectory);
  const event = feed?.events[0];
  return event === undefined
    ? null
    : { ts: event.ts, actor: event.actor, utcDay: event.ts.slice(0, 10) };
}

export async function readEventFeed(
  eventsDirectory: string,
): Promise<EventFeed | null> {
  let files: string[];
  try {
    files = await readdir(eventsDirectory);
  } catch {
    return null;
  }

  const events: Array<{ instant: number; event: EventDetail }> = [];
  let malformed = 0;
  for (const file of files
    .filter((name) => /^events-\d{4}-\d{2}-\d{2}\.jsonl$/.test(name))
    .sort()) {
    let contents: string;
    try {
      contents = await readFile(join(eventsDirectory, file), "utf8");
    } catch {
      continue;
    }
    for (const line of contents.split(/\r?\n/)) {
      if (line.trim() === "") {
        continue;
      }
      try {
        const record = JSON.parse(line) as EventRecord;
        if (typeof record.ts !== "string" || typeof record.actor !== "string") {
          malformed += 1;
          continue;
        }
        const instant = Date.parse(record.ts);
        if (Number.isNaN(instant)) {
          malformed += 1;
          continue;
        }
        const event: EventDetail = {
          ts: new Date(instant).toISOString(),
          actor: record.actor,
          seat: typeof record.seat === "string" ? record.seat : null,
          category:
            typeof record.category === "string" ? record.category : null,
          target: typeof record.target === "string" ? record.target : null,
          detail: typeof record.detail === "string" ? record.detail : null,
          payload: record.payload ?? null,
        };
        events.push({ instant, event });
      } catch {
        // An event shard is append-only and may contain a damaged line.
        malformed += 1;
      }
    }
  }
  events.sort((left, right) => right.instant - left.instant);
  return { events: events.map(({ event }) => event), malformed };
}
