import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";

import type { Bead, BeadCounts, BeadDependency } from "../types.ts";

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
): Promise<{ counts: BeadCounts; beads: Bead[]; inProgress: Bead[] } | null> {
  let contents: string;
  try {
    contents = await readFile(path, "utf8");
  } catch {
    return null;
  }

  const counts: BeadCounts = {
    open: 0,
    ready: 0,
    inProgress: 0,
    blocked: 0,
    closed: 0,
    malformed: 0,
    gaps: 0,
  };
  const beads: Bead[] = [];
  const inProgress: Bead[] = [];
  for (const line of contents.split(/\r?\n/)) {
    if (line.trim() === "") {
      continue;
    }
    try {
      const record = JSON.parse(line) as Record<string, unknown>;
      const bead = parseBead(record);
      if (bead === null) {
        counts.malformed += 1;
      } else {
        const status = statuses.get(bead.status);
        if (status === undefined) {
          counts.malformed += 1;
          continue;
        }
        counts[status] += 1;
        if (hasSchemaGap(record)) counts.gaps += 1;
        beads.push(bead);
        if (status === "inProgress") inProgress.push(bead);
      }
    } catch {
      counts.malformed += 1;
    }
  }
  counts.ready = beads.filter((bead) => isReady(bead, beads)).length;
  return { counts, beads, inProgress };
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function stringArrayOrNull(value: unknown): string[] | null {
  return Array.isArray(value) && value.every((item) => typeof item === "string")
    ? value
    : null;
}

function parseDependency(value: unknown): BeadDependency | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const dependency = value as Record<string, unknown>;
  return {
    issueId: stringOrNull(dependency.issue_id),
    dependsOnId: stringOrNull(dependency.depends_on_id),
    type: stringOrNull(dependency.type),
    createdAt: stringOrNull(dependency.created_at),
    createdBy: stringOrNull(dependency.created_by),
    metadata: stringOrNull(dependency.metadata),
  };
}

function dependenciesOrNull(value: unknown): BeadDependency[] | null {
  if (!Array.isArray(value)) return null;
  const dependencies = value.map(parseDependency);
  return dependencies.every((dependency) => dependency !== null)
    ? (dependencies as BeadDependency[])
    : null;
}

function parseBead(record: Record<string, unknown>): Bead | null {
  const status = stringOrNull(record.status);
  if (
    typeof record.id !== "string" ||
    status === null ||
    !statuses.has(status)
  ) {
    return null;
  }
  return {
    id: record.id,
    title: stringOrNull(record.title),
    description: stringOrNull(record.description),
    design: stringOrNull(record.design),
    notes: stringOrNull(record.notes),
    acceptanceCriteria: stringOrNull(record.acceptance_criteria),
    status,
    priority: typeof record.priority === "number" ? record.priority : null,
    issueType: stringOrNull(record.issue_type),
    assignee: stringOrNull(record.assignee),
    owner: stringOrNull(record.owner),
    labels: stringArrayOrNull(record.labels),
    dependencies: dependenciesOrNull(record.dependencies),
    createdAt: stringOrNull(record.created_at),
    createdBy: stringOrNull(record.created_by),
    updatedAt: stringOrNull(record.updated_at),
    startedAt: stringOrNull(record.started_at),
    closedAt: stringOrNull(record.closed_at),
    closeReason: stringOrNull(record.close_reason),
  };
}

function hasSchemaGap(record: Record<string, unknown>): boolean {
  return (
    stringArrayOrNull(record.labels) === null ||
    dependenciesOrNull(record.dependencies) === null ||
    typeof record.issue_type !== "string" ||
    typeof record.created_at !== "string" ||
    typeof record.updated_at !== "string"
  );
}

function isReady(bead: Bead, beads: Bead[]): boolean {
  if (bead.status !== "open") return false;
  if (bead.dependencies === null) return false;
  const prerequisiteIds = bead.dependencies.flatMap((dependency) =>
    dependency.type === "blocks" &&
    dependency.issueId === bead.id &&
    dependency.dependsOnId !== null
      ? [dependency.dependsOnId]
      : [],
  );
  return prerequisiteIds.every(
    (id) => beads.find((candidate) => candidate.id === id)?.status === "closed",
  );
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
