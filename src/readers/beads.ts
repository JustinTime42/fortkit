import { readFile, stat } from "node:fs/promises";
import { join } from "node:path";

import type { Bead, BeadCounts, BeadDependency, BeadStatus } from "../types.ts";

type CountedStatus = keyof Omit<
  BeadCounts,
  "malformed" | "ready" | "schemaGaps"
>;

export type ClosedBead = {
  id: string;
  title: string | null;
  closedAt: string | null;
};

/** The passive export is deliberately used here: cross-fort `bd --readonly`
 * needs to create Dolt's LOCK file and cannot run under the Herald's RO mount. */
export type ClosedBeadSource =
  | {
      status: "ok";
      beads: ClosedBead[];
      exportUpdatedAt: string;
      exportAgeSeconds: number;
      exportStale: boolean;
    }
  | { status: "error"; error: string };

const exportStaleAfterMs = 2 * 60 * 1000;

const statuses: Record<BeadStatus, CountedStatus> = {
  open: "open",
  in_progress: "inProgress",
  blocked: "blocked",
  closed: "closed",
};

function isBeadStatus(value: unknown): value is BeadStatus {
  return typeof value === "string" && Object.hasOwn(statuses, value);
}

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
    schemaGaps: 0,
  };
  const beads: Bead[] = [];
  const inProgress: Bead[] = [];
  const dependencySchemaGaps = new Set<Bead>();
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
        const status = statuses[bead.status];
        counts[status] += 1;
        const dependencyGap = hasDependencySchemaGap(record);
        if (hasSchemaGap(record, dependencyGap)) counts.schemaGaps += 1;
        beads.push(bead);
        if (dependencyGap) dependencySchemaGaps.add(bead);
        if (status === "inProgress") inProgress.push(bead);
      }
    } catch {
      counts.malformed += 1;
    }
  }
  counts.ready = beads.filter((bead) =>
    isReady(bead, beads, dependencySchemaGaps),
  ).length;
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
  if (
    typeof dependency.issue_id !== "string" ||
    typeof dependency.depends_on_id !== "string" ||
    typeof dependency.type !== "string"
  ) {
    return null;
  }
  return {
    issueId: dependency.issue_id,
    dependsOnId: dependency.depends_on_id,
    type: dependency.type,
    createdAt: stringOrNull(dependency.created_at),
    createdBy: stringOrNull(dependency.created_by),
    metadata: stringOrNull(dependency.metadata),
  };
}

function dependenciesOrNull(value: unknown): BeadDependency[] | null {
  if (!Array.isArray(value)) return null;
  const dependencies: BeadDependency[] = [];
  for (const item of value) {
    const dependency = parseDependency(item);
    if (dependency === null) return null;
    dependencies.push(dependency);
  }
  return dependencies;
}

function parseBead(record: Record<string, unknown>): Bead | null {
  if (typeof record.id !== "string" || !isBeadStatus(record.status)) {
    return null;
  }
  return {
    id: record.id,
    title: stringOrNull(record.title),
    description: stringOrNull(record.description),
    design: stringOrNull(record.design),
    notes: stringOrNull(record.notes),
    acceptanceCriteria: stringOrNull(record.acceptance_criteria),
    status: record.status,
    priority: typeof record.priority === "number" ? record.priority : null,
    issueType: stringOrNull(record.issue_type),
    assignee: stringOrNull(record.assignee),
    owner: stringOrNull(record.owner),
    // bd exports omit `labels` when it is empty. Preserve that observed
    // omission as an empty label set, while still flagging malformed present
    // fields in hasSchemaGap below.
    labels: Object.hasOwn(record, "labels")
      ? stringArrayOrNull(record.labels)
      : [],
    dependencies: dependenciesOrNull(record.dependencies),
    createdAt: stringOrNull(record.created_at),
    createdBy: stringOrNull(record.created_by),
    updatedAt: stringOrNull(record.updated_at),
    startedAt: stringOrNull(record.started_at),
    closedAt: stringOrNull(record.closed_at),
    closeReason: stringOrNull(record.close_reason),
  };
}

function isPrerequisiteEdge(
  dependency: BeadDependency,
  beadId: string,
): boolean {
  return dependency.type === "blocks" && dependency.issueId === beadId;
}

function hasDependencySchemaGap(record: Record<string, unknown>): boolean {
  // parseBead has already checked this, but keep the identity invariant outside
  // the per-edge filter so this helper remains sound on its own.
  if (typeof record.id !== "string") return true;
  const beadId = record.id;
  const hasDependencies = Object.hasOwn(record, "dependencies");
  const hasDependencyCount = Object.hasOwn(record, "dependency_count");
  const dependencyCount = record.dependency_count;
  const validDependencyCount =
    typeof dependencyCount === "number" &&
    Number.isInteger(dependencyCount) &&
    dependencyCount >= 0;
  const dependencies = dependenciesOrNull(record.dependencies);

  if (hasDependencies) {
    if (dependencies === null) return true;
    // `dependency_count` is empirically the number of `blocks` prerequisites,
    // not all dependency edges (for example, `parent-child` is excluded). A
    // low count is tolerated because it does not show unseen prerequisites;
    // only a higher count proves this export may be truncated.
    return (
      hasDependencyCount &&
      (!validDependencyCount ||
        dependencyCount >
          dependencies.filter((dependency) =>
            isPrerequisiteEdge(dependency, beadId),
          ).length)
    );
  }

  // bd omits an empty dependency array. An omitted count has the same
  // backwards-compatible meaning; a positive or malformed count does not.
  return hasDependencyCount && (!validDependencyCount || dependencyCount > 0);
}

function hasSchemaGap(
  record: Record<string, unknown>,
  dependencyGap: boolean,
): boolean {
  return (
    (Object.hasOwn(record, "labels") &&
      stringArrayOrNull(record.labels) === null) ||
    dependencyGap ||
    typeof record.issue_type !== "string" ||
    typeof record.created_at !== "string" ||
    typeof record.updated_at !== "string"
  );
}

function isReady(
  bead: Bead,
  beads: Bead[],
  dependencySchemaGaps: Set<Bead>,
): boolean {
  if (bead.status !== "open") return false;
  if (dependencySchemaGaps.has(bead)) return false;
  const dependencies = bead.dependencies ?? [];
  const prerequisiteIds = dependencies.flatMap((dependency) =>
    isPrerequisiteEdge(dependency, bead.id) ? [dependency.dependsOnId] : [],
  );
  return prerequisiteIds.every(
    (id) => beads.find((candidate) => candidate.id === id)?.status === "closed",
  );
}

export async function readClosedBeads(
  path: string,
  since: number,
  until: number,
): Promise<ClosedBeadSource> {
  const exportPath = join(path, ".beads", "issues.jsonl");
  let contents: string;
  let modified: Date;
  try {
    [contents, { mtime: modified }] = await Promise.all([
      readFile(exportPath, "utf8"),
      stat(exportPath),
    ]);
  } catch (error) {
    const reason =
      error instanceof Error
        ? ((error as NodeJS.ErrnoException).code ?? error.name)
        : "unknown error";
    return {
      status: "error",
      error: `cannot read .beads/issues.jsonl (${reason})`,
    };
  }

  const beads: ClosedBead[] = [];
  try {
    // The digest intentionally includes every bead type: gate, infrastructure,
    // and template work are all part of a fort's complete activity record.
    for (const line of contents.split(/\r?\n/)) {
      if (line.trim() === "") continue;
      const record = JSON.parse(line) as unknown;
      if (typeof record === "object" && record !== null) {
        const value = record as Record<string, unknown>;
        if (value.status === "closed" && typeof value.id === "string") {
          beads.push({
            id: value.id,
            title: typeof value.title === "string" ? value.title : null,
            closedAt:
              typeof value.closed_at === "string" ? value.closed_at : null,
          });
        }
      }
    }
  } catch {
    return {
      status: "error",
      error: "cannot parse .beads/issues.jsonl",
    };
  }
  const ageMs = Math.max(0, Date.now() - modified.getTime());
  return {
    status: "ok",
    beads: beads
      .filter((bead) => bead.closedAt !== null)
      .filter((bead) => {
        const closedAt = bead.closedAt;
        return (
          closedAt !== null &&
          Date.parse(closedAt) >= since &&
          Date.parse(closedAt) < until
        );
      })
      .sort((left, right) => left.id.localeCompare(right.id)),
    exportUpdatedAt: modified.toISOString(),
    exportAgeSeconds: Math.floor(ageMs / 1000),
    exportStale: ageMs > exportStaleAfterMs,
  };
}
