import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

import { projectColony } from "./colony.ts";
import type { ColonyCitizen, ColonyProjection } from "./page-types.ts";
import { readBeadRecords } from "./readers/beads.ts";
import { readEventFeed } from "./readers/events.ts";
import { readGitState } from "./readers/git.ts";
import { readRegistry } from "./readers/registry.ts";

async function readCitizens(path: string): Promise<ColonyCitizen[] | null> {
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
          const holder = /\*\*Held by:\*\*\s*([^(*]+?)\s*\*\*\(([^)]+)\)/.exec(
            contents,
          );
          return seat === undefined || holder === null
            ? null
            : {
                name: holder[1]?.trim() ?? "unknown",
                pronouns: holder[2]?.trim() ?? "unknown",
                seat,
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
  const [beads, events, git, citizens] = await Promise.all([
    readBeadRecords(join(fort.path, ".beads", "issues.jsonl")),
    readEventFeed(join(fort.path, "fort", "events")),
    readGitState(fort.path),
    readCitizens(join(fort.path, "fort", "seats")),
  ]);
  return projectColony({
    beads: beads?.beads ?? null,
    worktrees: git.worktrees,
    events: events?.events ?? null,
    citizens,
  });
}
