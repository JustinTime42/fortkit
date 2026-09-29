import { execFile } from "node:child_process";
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

import { recall } from "../src/recall.ts";

const execFileAsync = promisify(execFile);
const repositoryRoot = fileURLToPath(new URL("..", import.meta.url));

async function fixtureRoot(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "fortkit-recall-"));
  await Promise.all([
    mkdir(join(root, "fort", "memory", "facts"), { recursive: true }),
    mkdir(join(root, "fort", "handoffs"), { recursive: true }),
    mkdir(join(root, "fort", "events"), { recursive: true }),
    mkdir(join(root, "fort", "annals"), { recursive: true }),
    mkdir(join(root, ".beads"), { recursive: true }),
    mkdir(join(root, "civ", "events"), { recursive: true }),
    mkdir(join(root, "civ", "handoffs"), { recursive: true }),
  ]);
  await Promise.all([
    writeFile(
      join(root, "fort", "memory", "facts", "recall-fact.md"),
      `---
key: recall-fact
status: active
superseded-by: null
tier: on-demand
scope:
  seats: [forge]
  topics: [retrieval]
  beads: [fortkit-88u.7]
provenance:
  source: "fortkit-88u.7"
  declared-by: kethra
  date: 2026-08-10
  origin: trusted
---
The ledger-canary proves fact recall.
`,
    ),
    writeFile(
      join(root, "fort", "handoffs", "forge-2026-08-10.md"),
      "# Handoff: Forge 2026-08-10T12:00:00Z\n\n## State of work\n\nThe handoff-canary is ready.\n\n## Next actions\n\nUse recall.\n\n## Failed attempts\n\nThe failed-canary is recorded.\n",
    ),
    writeFile(
      join(root, "fort", "events", "events-local-shard.jsonl"),
      '{"ts":"2026-08-10T23:24:00-08:00","actor":"kethra","seat":"forge","category":"work.begun","target":"fortkit-88u.7","detail":"The event-canary crosses the UTC seam"}\n',
    ),
    writeFile(
      join(root, "fort", "annals", "recall.md"),
      "# Recall annal\n\nThe annal-canary records the ruling.\n",
    ),
    writeFile(
      join(root, ".beads", "issues.jsonl"),
      '{"id":"fortkit-88u.7","status":"closed","title":"The bead-canary title","description":"The bead-description-canary is searchable","close_reason":"The close-reason-canary is searchable","updated_at":"2026-08-10T12:00:00Z"}\n',
    ),
    writeFile(
      join(root, "civ", "events", "civ.jsonl"),
      '{"ts":"2026-08-10T12:00:00Z","detail":"The civ-event-canary is searchable"}\n',
    ),
    writeFile(
      join(root, "civ", "handoffs", "herald.md"),
      "# Herald handoff 2026-08-10T14:00:00Z\n\nThe civ-handoff-canary is searchable.\n",
    ),
    writeFile(
      join(root, "civ", "remember.md"),
      "# Remember\n\nThe civ-remember-canary is searchable.\n",
    ),
  ]);
  return root;
}

describe("fortkit recall", () => {
  test("finds each indexed corpus surface with structured provenance", async () => {
    const root = await fixtureRoot();
    try {
      await expect(
        recall(root, "ledger-canary", {
          seat: "forge",
          topic: "retrieval",
          bead: "fortkit-88u.7",
        }),
      ).resolves.toMatchObject({
        hits: [
          {
            source: "fort/memory/facts/recall-fact.md",
            section: "fact",
            provenance: "fortkit-88u.7",
            actor: "kethra",
          },
        ],
      });
      await expect(recall(root, "handoff-canary", {})).resolves.toMatchObject({
        hits: expect.arrayContaining([
          expect.objectContaining({
            source: "fort/handoffs/forge-2026-08-10.md",
            section: "State of work",
            seat: "forge",
          }),
        ]),
      });
      await expect(recall(root, "event-canary", {})).resolves.toMatchObject({
        hits: expect.arrayContaining([
          expect.objectContaining({
            source: "fort/events/events-local-shard.jsonl",
            section: "work.begun",
            actor: "kethra",
            seat: "forge",
          }),
        ]),
      });
      await expect(recall(root, "annal-canary", {})).resolves.toMatchObject({
        hits: [{ source: "fort/annals/recall.md", section: "Recall annal" }],
      });
      await expect(recall(root, "bead-canary", {})).resolves.toMatchObject({
        hits: [
          {
            source: ".beads/issues.jsonl",
            section: "fortkit-88u.7",
            provenance: ".beads/issues.jsonl:1",
          },
        ],
      });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("windows parsed event instants across the local-to-UTC seam", async () => {
    const root = await fixtureRoot();
    try {
      const result = await recall(root, "event-canary", {
        since: "2026-08-11T07:00:00Z",
        until: "2026-08-11T08:00:00Z",
      });
      expect(result.hits).toMatchObject([
        {
          date: "2026-08-11T07:24:00.000Z",
          source: "fort/events/events-local-shard.jsonl",
        },
      ]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("treats all-scoped facts as matching every seat", async () => {
    const root = await fixtureRoot();
    try {
      await writeFile(
        join(root, "fort", "memory", "facts", "authoritative-verifier.md"),
        `---
key: authoritative-verifier
status: active
superseded-by: null
tier: core
scope:
  seats: [all]
  topics: [verification]
provenance:
  source: "fortkit-88u.7"
  declared-by: kethra
  date: 2026-08-10
  origin: trusted
---
The verifier-canary is authoritative for every seat.
`,
      );
      await expect(
        recall(root, "verifier-canary", { seat: "forge" }),
      ).resolves.toMatchObject({
        hits: [
          {
            source: "fort/memory/facts/authoritative-verifier.md",
            section: "fact",
          },
        ],
      });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("discloses matching undated rows excluded by a date window", async () => {
    const root = await fixtureRoot();
    try {
      const result = await recall(root, "annal-canary", {
        since: "2026-08-01T00:00:00Z",
      });
      expect(result.hits).toEqual([]);
      expect(result.gaps).toContainEqual({
        source: "",
        reason:
          "1 indexed rows have no parsed timestamp and were excluded by --since/--until",
      });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("discloses unreadable corpus files as gaps", async () => {
    const root = await fixtureRoot();
    const unreadable = join(root, "fort", "annals", "unreadable.md");
    try {
      await writeFile(
        unreadable,
        "# Unreadable\n\nThe gap-canary must not vanish.\n",
      );
      await chmod(unreadable, 0o000);
      const result = await recall(root, "annal-canary", {});
      expect(result.gaps).toEqual(
        expect.arrayContaining([
          expect.objectContaining({ source: "fort/annals/unreadable.md" }),
        ]),
      );
    } finally {
      await chmod(unreadable, 0o600).catch(() => undefined);
      await rm(root, { recursive: true, force: true });
    }
  });

  test("indexes widened corpus fields without rewriting tracked memory views", async () => {
    const root = await fixtureRoot();
    const current = join(root, "fort", "memory", "current.md");
    try {
      await writeFile(current, "tracked view must remain untouched\n");
      const before = await readFile(current, "utf8");
      for (const canary of [
        "bead-description-canary",
        "close-reason-canary",
        "failed-canary",
        "civ-event-canary",
        "civ-handoff-canary",
        "civ-remember-canary",
      ])
        await expect(recall(root, canary, {})).resolves.toMatchObject({
          hits: expect.arrayContaining([
            expect.objectContaining({
              snippet: expect.stringContaining(canary),
            }),
          ]),
        });
      await expect(readFile(current, "utf8")).resolves.toBe(before);
      await expect(
        recall(root, "civ-handoff-canary", {}),
      ).resolves.toMatchObject({
        hits: [
          {
            source: "civ/handoffs/herald.md",
            date: "2026-08-10T14:00:00.000Z",
            seat: "herald",
          },
        ],
      });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("limits ranked results by default and honors --limit through the API", async () => {
    const root = await fixtureRoot();
    try {
      for (let index = 0; index < 25; index += 1)
        await writeFile(
          join(root, "fort", "memory", "facts", `rank-${index}.md`),
          `---\nkey: rank-${index}\nstatus: active\nsuperseded-by: null\ntier: on-demand\nscope:\n  seats: [all]\n  topics: [retrieval]\n  beads: []\nprovenance:\n  source: test\n  declared-by: kethra\n  date: 2026-08-10\n  origin: trusted\n---\nrank-canary ${index}\n`,
        );
      const defaultResult = await recall(root, "rank-canary", {});
      expect(defaultResult.hits).toHaveLength(20);
      expect(defaultResult.gaps).toContainEqual({
        source: "",
        reason:
          "20 of 25 matching rows shown; use --limit to adjust the result cap",
      });
      expect(
        (await recall(root, "rank-canary", { limit: 3 })).hits,
      ).toHaveLength(3);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("ranks coverage, recency, source, section, provenance, and row id", async () => {
    const root = await fixtureRoot();
    try {
      await Promise.all([
        writeFile(
          join(root, "fort", "memory", "facts", "coverage-first.md"),
          `---\nkey: coverage-first\nstatus: active\nsuperseded-by: null\ntier: on-demand\nscope:\n  seats: [all]\n  topics: [retrieval]\nprovenance:\n  source: test\n  declared-by: kethra\n  date: 2026-08-01\n  origin: trusted\n---\ncoverage-canary alpha beta\n`,
        ),
        writeFile(
          join(root, "fort", "memory", "facts", "coverage-partial.md"),
          `---\nkey: coverage-partial\nstatus: active\nsuperseded-by: null\ntier: on-demand\nscope:\n  seats: [all]\n  topics: [retrieval]\nprovenance:\n  source: test\n  declared-by: kethra\n  date: 2026-08-11\n  origin: trusted\n---\ncoverage-canary alpha\n`,
        ),
      ]);
      const coverage = await recall(root, "coverage-canary alpha beta", {});
      expect(coverage.hits.slice(0, 2).map((hit) => hit.source)).toEqual([
        "fort/memory/facts/coverage-first.md",
        "fort/memory/facts/coverage-partial.md",
      ]);

      await Promise.all([
        writeFile(
          join(root, "fort", "memory", "facts", "a-older.md"),
          `---\nkey: a-older\nstatus: active\nsuperseded-by: null\ntier: on-demand\nscope:\n  seats: [all]\n  topics: [retrieval]\nprovenance:\n  source: test\n  declared-by: kethra\n  date: 2026-08-01\n  origin: trusted\n---\nrecency-canary\n`,
        ),
        writeFile(
          join(root, "fort", "memory", "facts", "z-newer.md"),
          `---\nkey: z-newer\nstatus: active\nsuperseded-by: null\ntier: on-demand\nscope:\n  seats: [all]\n  topics: [retrieval]\nprovenance:\n  source: test\n  declared-by: kethra\n  date: 2026-08-11\n  origin: trusted\n---\nrecency-canary\n`,
        ),
      ]);
      expect(
        (await recall(root, "recency-canary", {})).hits.map(
          (hit) => hit.source,
        ),
      ).toEqual([
        "fort/memory/facts/z-newer.md",
        "fort/memory/facts/a-older.md",
      ]);

      await Promise.all([
        writeFile(
          join(root, "fort", "handoffs", "alpha-2026-08-12.md"),
          "# Handoff: Alpha 2026-08-12T12:00:00Z\n\n## State of work\n\ntie-canary\n\n## Next actions\n\ntie-canary\n",
        ),
        writeFile(
          join(root, "fort", "handoffs", "beta-2026-08-12.md"),
          "# Handoff: Beta 2026-08-12T12:00:00Z\n\n## State of work\n\ntie-canary\n",
        ),
      ]);
      expect(
        (await recall(root, "tie-canary", {})).hits.map(
          ({ source, section }) => `${source}:${section}`,
        ),
      ).toEqual([
        "fort/handoffs/alpha-2026-08-12.md:Next actions",
        "fort/handoffs/alpha-2026-08-12.md:State of work",
        "fort/handoffs/beta-2026-08-12.md:State of work",
      ]);

      await writeFile(
        join(root, "fort", "events", "same-keys.jsonl"),
        '{"ts":"2026-08-12T12:00:00Z","category":"same-key-canary","detail":"first indexed row"}\n{"ts":"2026-08-12T12:00:00Z","category":"same-key-canary","detail":"second indexed row"}\n',
      );
      await recall(root, "same-key-canary", {});
      const index = join(root, "fort", "memory", "index.db");
      const db = new DatabaseSync(index);
      try {
        db.prepare(
          "UPDATE source SET section = 'same-key-canary', provenance = 'same', row_id = CASE snippet WHEN 'first indexed row' THEN 1 ELSE 0 END WHERE source = 'fort/events/same-keys.jsonl'",
        ).run();
      } finally {
        db.close();
      }
      expect(
        (await recall(root, "same-key-canary", {})).hits.map(
          (hit) => hit.snippet,
        ),
      ).toEqual(["second indexed row", "first indexed row"]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("rebuilds an obsolete or corrupted index", async () => {
    const root = await fixtureRoot();
    try {
      await recall(root, "ledger-canary", {});
      const index = join(root, "fort", "memory", "index.db");
      const db = new DatabaseSync(index);
      db.prepare(
        "UPDATE meta SET value = 'obsolete' WHERE key = 'builder_version'",
      ).run();
      db.close();
      await expect(recall(root, "ledger-canary", {})).resolves.toBeDefined();
      const repaired = new DatabaseSync(index, { readOnly: true });
      try {
        expect(
          repaired
            .prepare("SELECT value FROM meta WHERE key = 'builder_version'")
            .get(),
        ).toEqual({ value: "3" });
      } finally {
        repaired.close();
      }
      await writeFile(index, "corrupted");
      await expect(recall(root, "ledger-canary", {})).resolves.toBeDefined();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("invokes recall through npm and node, and rejects invalid limits", async () => {
    const root = await fixtureRoot();
    try {
      const cli = join(repositoryRoot, "src", "cli.ts");
      const packageJson = JSON.parse(
        await readFile(join(repositoryRoot, "package.json"), "utf8"),
      ) as { scripts: { recall: string } };
      await symlink(join(repositoryRoot, "src"), join(root, "src"));
      await writeFile(
        join(root, "package.json"),
        JSON.stringify({ scripts: { recall: packageJson.scripts.recall } }),
      );
      await expect(
        execFileAsync("node", [cli, "recall", "ledger-canary"], { cwd: root }),
      ).resolves.toBeDefined();
      await expect(
        execFileAsync("npm", ["run", "recall", "--", "ledger-canary"], {
          cwd: root,
        }),
      ).resolves.toBeDefined();
      for (const limit of ["0", "x"])
        await expect(
          execFileAsync(
            "node",
            [cli, "recall", "ledger-canary", "--limit", limit],
            {
              cwd: root,
            },
          ),
        ).rejects.toMatchObject({ code: 2 });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("leaves git status clean after an index-only query", async () => {
    const root = await fixtureRoot();
    try {
      await writeFile(join(root, ".gitignore"), "fort/memory/index.db\n");
      await execFileAsync("git", ["init", "-q"], { cwd: root });
      await execFileAsync("git", ["add", "."], { cwd: root });
      await execFileAsync(
        "git",
        [
          "-c",
          "user.name=Recall test",
          "-c",
          "user.email=recall@example.test",
          "commit",
          "-qm",
          "initial",
        ],
        { cwd: root },
      );
      await expect(recall(root, "ledger-canary", {})).resolves.toBeDefined();
      await expect(
        execFileAsync("git", ["status", "--porcelain"], { cwd: root }),
      ).resolves.toMatchObject({ stdout: "" });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
