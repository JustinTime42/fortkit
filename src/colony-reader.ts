import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

import { projectColony } from "./colony.ts";
import type { ColonyCitizen, ColonyProjection } from "./page-types.ts";
import { readBeadRecords } from "./readers/beads.ts";
import { readEventFeed } from "./readers/events.ts";
import { readGitState } from "./readers/git.ts";
import { readLatestHandoffs } from "./readers/handoffs.ts";
import { readRegistry } from "./readers/registry.ts";

async function readCitizens(
  path: string,
  handoffs: Map<string, string | null> | null,
): Promise<ColonyCitizen[] | null> {
  let files: string[];
  try {
    files = await readdir(path);
  } catch {
    return null;
  }
  const citizens = await Promise.all(
    files
      .filter((file) => file.endsWith(".md"))
      .sort()
      .map(async (file) => {
        try {
          const contents = await readFile(join(path, file), "utf8");
          const seat = /^# Seat:\s*(.+)$/m.exec(contents)?.[1]?.trim();
          const holder = /\*\*Held by:\s*([^*]+?)\*\*\s*\(([^)]*)/.exec(
            contents,
          );
          const pronouns = /\b([a-z]+\/[a-z]+)\b/.exec(holder?.[2] ?? "")?.[1];
          const personality =
            /\*\*Personality \(in [a-z/]+ own words\):\*\*\s*[“"]([^”"]*)[”"]/s
              .exec(contents)?.[1]
              ?.trim();
          return seat === undefined || holder === null
            ? null
            : {
                name: holder[1]?.trim() || "—",
                pronouns: pronouns ?? "—",
                seat,
                personality: personality ?? null,
                currentBead: null,
                session: null,
                lastHandoff: handoffs?.get(seat.toLocaleLowerCase()) ?? null,
              };
        } catch {
          return null;
        }
      }),
  );
  return citizens.flatMap((citizen) => (citizen === null ? [] : [citizen]));
}

/** Read one registered fort without allowing the browser to choose a filesystem path. */
export async function readColony(
  registryPath: string,
  fortName: string,
): Promise<ColonyProjection | null> {
  const fort = (await readRegistry(registryPath)).find(
    (candidate) => candidate.name === fortName,
  );
  if (fort === undefined) return null;
  const handoffDirectory = join(fort.path, "fort", "handoffs");
  const [beads, events, git, handoffs] = await Promise.all([
    readBeadRecords(join(fort.path, ".beads", "issues.jsonl")),
    readEventFeed(join(fort.path, "fort", "events")),
    readGitState(fort.path),
    readLatestHandoffs(handoffDirectory),
  ]);
  const citizens = await readCitizens(
    join(fort.path, "fort", "seats"),
    handoffs,
  );
  return projectColony({
    beads: beads?.beads ?? null,
    worktrees: git.worktrees,
    events: events?.events ?? null,
    citizens,
  });
}
