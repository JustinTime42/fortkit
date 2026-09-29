import { execFile } from "node:child_process";
import { access, readdir, stat } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const run = promisify(execFile);
const consolidate = fileURLToPath(
  new URL("../scripts/consolidate-memory.mjs", import.meta.url),
);

export type RecallFilters = {
  seat?: string;
  topic?: string;
  bead?: string;
  since?: string;
  until?: string;
  limit?: number;
};

type IndexRow = {
  source: string;
  ts: string;
  actor: string;
  seat: string;
  section: string;
  provenance: string;
  scope_seats: string;
  scope_topics: string;
  scope_beads: string;
  snippet: string;
  row_id: number;
};

export type RecallHit = {
  source: string;
  date: string | null;
  actor: string | null;
  seat: string | null;
  section: string;
  provenance: string;
  snippet: string;
};

export type RecallResult = {
  hits: RecallHit[];
  gaps: { source: string; reason: string }[];
};

function instant(value: string, flag: string): number {
  const parsed = Date.parse(value);
  if (Number.isNaN(parsed)) throw new Error(`${flag} must be an ISO timestamp`);
  return parsed;
}

function tags(value: string): string[] {
  return value
    .split(",")
    .map((tag) => tag.trim().toLowerCase())
    .filter(Boolean);
}

function scopeMatches(
  value: string,
  expected: string | undefined,
  wildcard = false,
): boolean {
  const actual = tags(value);
  return (
    expected === undefined ||
    actual.includes(expected.toLowerCase()) ||
    (wildcard && actual.includes("all"))
  );
}

const DEFAULT_LIMIT = 20;
const INDEX_BUILDER_VERSION = "3";

function score(row: IndexRow, query: string): number {
  const haystack = `${row.section}\n${row.snippet}`.toLowerCase();
  const words = query.toLowerCase().split(/\s+/u).filter(Boolean);
  return words.reduce(
    (total, word) => total + (haystack.includes(word) ? 1 : 0),
    0,
  );
}

async function indexIsStale(root: string, index: string): Promise<boolean> {
  let indexMtime: number;
  try {
    indexMtime = (await stat(index)).mtimeMs;
  } catch {
    return true;
  }
  try {
    const db = new DatabaseSync(index, { readOnly: true });
    try {
      const meta = db
        .prepare("SELECT value FROM meta WHERE key = 'builder_version'")
        .get() as { value: string } | undefined;
      if (meta?.value !== INDEX_BUILDER_VERSION) return true;
    } finally {
      db.close();
    }
  } catch {
    return true;
  }
  const inputs = [
    ".beads/issues.jsonl",
    ".beads/interactions.jsonl",
    "fort/memory/facts",
    "fort/handoffs",
    "fort/events",
    "fort/annals",
    "civ/events",
    "civ/handoffs",
    "civ/remember.md",
  ];
  async function newer(path: string): Promise<boolean> {
    try {
      const entry = await stat(path);
      if (entry.mtimeMs > indexMtime) return true;
      if (!entry.isDirectory()) return false;
      for (const child of await readdir(path))
        if (await newer(join(path, child))) return true;
    } catch {
      // Optional corpus surfaces can be absent. The index builder discloses them.
    }
    return false;
  }
  for (const input of inputs) if (await newer(join(root, input))) return true;
  return false;
}

export async function recall(
  root: string,
  query: string,
  filters: RecallFilters,
): Promise<RecallResult> {
  const absoluteRoot = resolve(root);
  const index = join(absoluteRoot, "fort", "memory", "index.db");
  await access(dirname(consolidate));
  if (await indexIsStale(absoluteRoot, index))
    await run(process.execPath, [consolidate, "--index-only", absoluteRoot]);
  const db = new DatabaseSync(index, { readOnly: true });
  try {
    const rows = db.prepare("SELECT * FROM source").all() as IndexRow[];
    const gaps = db
      .prepare("SELECT source, reason FROM gaps ORDER BY source, reason")
      .all() as {
      source: string;
      reason: string;
    }[];
    const since =
      filters.since === undefined
        ? undefined
        : instant(filters.since, "--since");
    const until =
      filters.until === undefined
        ? undefined
        : instant(filters.until, "--until");
    if (since !== undefined && until !== undefined && since >= until)
      throw new Error("--since must be before --until");
    const candidates = rows
      .map((row) => ({ row, score: score(row, query) }))
      .filter(
        ({ row, score: match }) =>
          match > 0 &&
          scopeMatches(row.scope_seats, filters.seat, true) &&
          scopeMatches(row.scope_topics, filters.topic) &&
          scopeMatches(row.scope_beads, filters.bead),
      );
    const undated = candidates.filter(({ row }) =>
      Number.isNaN(row.ts === "" ? Number.NaN : Date.parse(row.ts)),
    );
    const matching = candidates
      .filter(({ row }) => {
        const timestamp = row.ts === "" ? Number.NaN : Date.parse(row.ts);
        return (
          (since === undefined ||
            (!Number.isNaN(timestamp) && timestamp >= since)) &&
          (until === undefined ||
            (!Number.isNaN(timestamp) && timestamp < until))
        );
      })
      .sort((left, right) => {
        const scoreOrder = right.score - left.score;
        if (scoreOrder !== 0) return scoreOrder;
        const leftTimestamp = Date.parse(left.row.ts);
        const rightTimestamp = Date.parse(right.row.ts);
        if (
          !Number.isNaN(leftTimestamp) &&
          !Number.isNaN(rightTimestamp) &&
          rightTimestamp !== leftTimestamp
        )
          return rightTimestamp - leftTimestamp;
        if (!Number.isNaN(leftTimestamp) && Number.isNaN(rightTimestamp))
          return -1;
        if (Number.isNaN(leftTimestamp) && !Number.isNaN(rightTimestamp))
          return 1;
        return (
          left.row.source.localeCompare(right.row.source) ||
          left.row.section.localeCompare(right.row.section) ||
          left.row.provenance.localeCompare(right.row.provenance) ||
          left.row.row_id - right.row.row_id
        );
      });
    const limit = filters.limit ?? DEFAULT_LIMIT;
    const hits = matching.slice(0, limit).map(({ row }) => ({
      source: row.source,
      date: row.ts === "" ? null : new Date(row.ts).toISOString(),
      actor: row.actor || null,
      seat: row.seat || null,
      section: row.section,
      provenance: row.provenance,
      snippet: row.snippet,
    }));
    if (matching.length > hits.length)
      gaps.push({
        source: "",
        reason: `${hits.length} of ${matching.length} matching rows shown; use --limit to adjust the result cap`,
      });
    if ((since !== undefined || until !== undefined) && undated.length > 0) {
      gaps.push({
        source: "",
        reason: `${undated.length} indexed rows have no parsed timestamp and were excluded by --since/--until`,
      });
    }
    return { hits, gaps };
  } finally {
    db.close();
  }
}
