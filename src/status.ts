import { access } from "node:fs/promises";
import { join } from "node:path";

import { readBeads } from "./readers/beads.ts";
import { readLastEvent } from "./readers/events.ts";
import { readGitState } from "./readers/git.ts";
import { readLastHandoff } from "./readers/handoffs.ts";
import { readRegistry } from "./readers/registry.ts";
import type { FortSummary } from "./types.ts";

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

export async function readFortStatus(
  name: string,
  path: string,
): Promise<FortSummary> {
  const present = await exists(path);
  if (!present) {
    return {
      name,
      path,
      present: false,
      beads: null,
      lastEvent: null,
      lastHandoff: null,
      git: {
        branch: null,
        ahead: null,
        behind: null,
        dirty: null,
        worktrees: null,
      },
    };
  }
  const [beads, lastEvent, lastHandoff, git] = await Promise.all([
    readBeads(join(path, ".beads", "issues.jsonl")),
    readLastEvent(join(path, "fort", "events")),
    readLastHandoff(join(path, "fort", "handoffs")),
    readGitState(path),
  ]);
  return { name, path, present: true, beads, lastEvent, lastHandoff, git };
}

export async function readCivilizationStatus(
  registryPath: string,
): Promise<FortSummary[]> {
  const forts = await readRegistry(registryPath);
  return Promise.all(forts.map((fort) => readFortStatus(fort.name, fort.path)));
}

export function formatStatusTable(forts: FortSummary[]): string {
  const rows = forts.map((fort) => [
    fort.name,
    fort.present ? "present" : "absent",
    fort.beads === null
      ? "absent"
      : `open ${fort.beads.open}, active ${fort.beads.inProgress}, blocked ${fort.beads.blocked}`,
    fort.lastEvent === null
      ? "absent"
      : `${fort.lastEvent.ts} (${fort.lastEvent.actor})`,
    fort.lastHandoff === null
      ? "absent"
      : `${fort.lastHandoff.seat} ${fort.lastHandoff.date}`,
    fort.git.dirty === null ? "absent" : fort.git.dirty ? "dirty" : "clean",
  ]);
  const headers = [
    "FORT",
    "STATE",
    "BEADS",
    "LAST EVENT",
    "LAST HANDOFF",
    "GIT",
  ];
  const widths = headers.map((header, index) =>
    Math.max(header.length, ...rows.map((row) => row[index]?.length ?? 0)),
  );
  const render = (row: string[]) =>
    row
      .map((cell, index) => cell.padEnd(widths[index] ?? cell.length))
      .join("  ");
  return [
    render(headers),
    render(widths.map((width) => "-".repeat(width))),
    ...rows.map(render),
  ].join("\n");
}
