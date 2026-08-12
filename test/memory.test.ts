import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const run = promisify(execFile);
const assembler = fileURLToPath(
  new URL("../scripts/consolidate-memory.mjs", import.meta.url),
);
const lint = fileURLToPath(
  new URL("../scripts/memory-lint.mjs", import.meta.url),
);
const repositoryRoot = fileURLToPath(new URL("..", import.meta.url));
const handoffFixtureRoot = fileURLToPath(
  new URL("./fixtures/memory-handoffs", import.meta.url),
);

const fact = `---
key: current-truth
status: active
superseded-by: null
tier: core
scope:
  seats: [all]
  topics: [test]
provenance:
  source: "fort/remember.md:41; fortkit-88u.5"
  declared-by: test
  date: 2026-08-10
  origin: trusted
---
The cycle-7 correction is the current truth.
`;

describe("memory consolidation", () => {
  test("is byte-identical, provenance-pointed, and leaves episodic sources untouched", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-memory-"));
    await Promise.all([
      mkdir(join(root, "fort", "memory", "facts"), { recursive: true }),
      mkdir(join(root, "fort", "handoffs"), { recursive: true }),
      mkdir(join(root, "fort", "events"), { recursive: true }),
      mkdir(join(root, ".beads"), { recursive: true }),
    ]);
    await Promise.all([
      writeFile(
        join(root, "fort", "memory", "facts", "current-truth.md"),
        fact,
      ),
      writeFile(
        join(root, ".beads", "issues.jsonl"),
        '{"id":"x","status":"open","title":"Open work","updated_at":"2026-08-10T00:00:00Z"}\n',
      ),
      writeFile(
        join(root, ".beads", "interactions.jsonl"),
        '{"interaction":"Fixture interaction corpus"}\n',
      ),
      writeFile(
        join(root, "fort", "handoffs", "forge-2026-08-10.md"),
        "# Handoff: Forge 2026-08-10T01:00:00Z\n\n## State of work\n\n- Ready.\n- Preserve this second line.\n\n## Next actions\n\n1. Ship it.\n2. Verify it.\n",
      ),
      writeFile(
        join(root, "fort", "handoffs", "mayor-2026-08-10.md"),
        "# Handoff: Mayor 2026-08-10T02:00:00Z\n\n## 2. State of session B's work\n\nMayor state.\n\n## Next actions\n\nMayor action.\n",
      ),
      writeFile(
        join(root, "fort", "events", "events-2026-08-10.jsonl"),
        '{"ts":"2026-08-10T02:00:00Z","category":"incident","detail":"Needs attention"}\n{"ts":"2026-08-10T02:00:00Z","category":"incident","detail":"Needs attention"}\n',
      ),
    ]);
    const episodic = await Promise.all([
      readFile(join(root, ".beads", "issues.jsonl"), "utf8"),
      readFile(join(root, "fort", "handoffs", "forge-2026-08-10.md"), "utf8"),
      readFile(join(root, "fort", "events", "events-2026-08-10.jsonl"), "utf8"),
    ]);
    await run(process.execPath, [assembler, root]);
    const first = await readFile(
      join(root, "fort", "memory", "current.md"),
      "utf8",
    );
    await run(process.execPath, [assembler, root]);
    expect(
      await readFile(join(root, "fort", "memory", "current.md"), "utf8"),
    ).toBe(first);
    expect(first).toContain("cycle-7 correction is the current truth");
    expect(first).toContain("fort/memory/facts/current-truth.md");
    expect(first).toContain("bead:x");
    expect(first).toContain("forge-2026-08-10.md");
    expect(first).toContain("Preserve this second line.");
    expect(first).toContain("Verify it.");
    expect(first).toContain("Mayor state.");
    expect(first).toContain("Mayor action.");
    expect(first).toContain(
      "Incident log — resolution linkage not yet implemented",
    );
    expect(first).toContain("events-2026-08-10.jsonl");
    expect(first.match(/Needs attention/g)?.length).toBe(1);
    const index = new DatabaseSync(join(root, "fort", "memory", "index.db"));
    try {
      const sourceCount = index
        .prepare("SELECT COUNT(*) AS count FROM source")
        .get() as { count: number } | undefined;
      const interaction = index
        .prepare("SELECT section, snippet FROM source WHERE source = ?")
        .get(".beads/interactions.jsonl") as
        | { section: string; snippet: string }
        | undefined;
      const gapCount = index
        .prepare("SELECT COUNT(*) AS count FROM gaps WHERE source = ?")
        .get(".beads/interactions.jsonl") as { count: number } | undefined;
      if (
        sourceCount === undefined ||
        interaction === undefined ||
        gapCount === undefined
      )
        throw new Error("memory index count query returned no row");
      expect(sourceCount.count).toBeGreaterThan(0);
      expect(interaction.section).toBe("interactions");
      expect(interaction.snippet).toContain("Fixture interaction corpus");
      expect(gapCount.count).toBe(0);
    } finally {
      index.close();
    }
    await expect(run(process.execPath, [lint, root])).resolves.toBeDefined();
    await expect(
      Promise.all([
        readFile(join(root, ".beads", "issues.jsonl"), "utf8"),
        readFile(join(root, "fort", "handoffs", "forge-2026-08-10.md"), "utf8"),
        readFile(
          join(root, "fort", "events", "events-2026-08-10.jsonl"),
          "utf8",
        ),
      ]),
    ).resolves.toEqual(episodic);
  });

  test("reports a missing interactions corpus with the searched path", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-memory-interactions-"));
    await mkdir(join(root, "fort", "memory", "facts"), { recursive: true });
    await writeFile(
      join(root, "fort", "memory", "facts", "current-truth.md"),
      fact,
    );

    await run(process.execPath, [assembler, root]);

    await expect(
      readFile(join(root, "fort", "memory", "current.md"), "utf8"),
    ).resolves.toContain(
      ".beads/interactions.jsonl: absent at searched path .beads/interactions.jsonl",
    );
  });

  test("pins the migrated cycle-7 correction as the active Forge truth", async () => {
    const current = await readFile(
      join(repositoryRoot, "fort", "memory", "current.md"),
      "utf8",
    );
    expect(current).toContain("attended seats (Mayor, Warden) have");
    expect(current).toContain("PROSE- gated");
    expect(current).not.toContain("Forge runs with a kernel mask");
  });

  test("caps ready beads without dropping in-progress or gate-labeled work", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-memory-cap-"));
    await Promise.all([
      mkdir(join(root, "fort", "memory", "facts"), { recursive: true }),
      mkdir(join(root, ".beads"), { recursive: true }),
    ]);
    const ready = Array.from({ length: 17 }, (_, index) => ({
      id: `ready-${String(index + 1).padStart(2, "0")}`,
      status: "open",
      title: "Ready work",
      priority: 4,
    }));
    await Promise.all([
      writeFile(
        join(root, "fort", "memory", "facts", "current-truth.md"),
        fact,
      ),
      writeFile(
        join(root, ".beads", "issues.jsonl"),
        [
          ...ready,
          { id: "active", status: "in_progress", title: "Active", priority: 4 },
          {
            id: "human-gate",
            status: "blocked",
            title: "Awaiting approval",
            priority: 4,
            labels: ["gate-1"],
          },
        ]
          .map((bead) => JSON.stringify(bead))
          .join("\n"),
      ),
    ]);
    await run(process.execPath, [assembler, root]);
    const current = await readFile(
      join(root, "fort", "memory", "current.md"),
      "utf8",
    );
    expect(current).toContain("active [in_progress]");
    expect(current).toContain("human-gate [blocked]");
    expect(current).toContain("ready-15 [open]");
    expect(current).not.toContain("ready-16 [open]");
    expect(current).toContain(
      "17 of 19 open beads shown; full list via bd ready",
    );
  });

  test("reports invalid handoff timestamps and picks the latest suffixed handoff", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-memory-handoffs-"));
    await cp(handoffFixtureRoot, root, { recursive: true });

    await run(process.execPath, [assembler, root]);
    const current = await readFile(
      join(root, "fort", "memory", "current.md"),
      "utf8",
    );
    expect(current).toContain("mayor-2026-08-11-b.md");
    expect(current).toContain("Mayor suffix.");
    expect(current).toContain("forge-2026-08-11-r3.md");
    expect(current).toContain("Forge round three.");
    expect(current).toContain("warden-2026-08-10.md");
    expect(current).toContain(
      'fort/handoffs/warden-2026-08-11.md: unparseable timestamp "2026-08-11T"',
    );
    expect(current).not.toContain("Warden invalid.");
  });

  test("fails lint for schema violations and retired instruction references", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-memory-lint-"));
    await mkdir(join(root, "fort", "memory", "facts"), { recursive: true });
    await writeFile(
      join(root, "fort", "memory", "facts", "invalid.md"),
      fact.replace("key: current-truth", "key: incorrect"),
    );
    await expect(run(process.execPath, [lint, root])).rejects.toMatchObject({
      code: 1,
    });
    await writeFile(
      join(root, "fort", "memory", "facts", "invalid.md"),
      fact.replace("current-truth", "replacement"),
    );
    await writeFile(
      join(root, "fort", "memory", "facts", "retired.md"),
      fact
        .replace("current-truth", "retired")
        .replace("status: active", "status: superseded")
        .replace("superseded-by: null", "superseded-by: replacement"),
    );
    await writeFile(join(root, "AGENTS.md"), "Read retired before work.\n");
    await expect(run(process.execPath, [lint, root])).rejects.toMatchObject({
      code: 1,
    });
  });

  test("covers every live instruction surface while allowing retirement records", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-memory-retired-"));
    const violations = [
      "fort/charter.md",
      "fort/seats/forge.md",
      "templates/fort/seats/forge.md",
      "fort/scripts/forge.sh",
      "bin/forge",
    ];
    await Promise.all([
      mkdir(join(root, "fort", "memory", "facts"), { recursive: true }),
      mkdir(join(root, "fort", "seats"), { recursive: true }),
      mkdir(join(root, "templates", "fort", "seats"), { recursive: true }),
      mkdir(join(root, "fort", "scripts"), { recursive: true }),
      mkdir(join(root, "scripts"), { recursive: true }),
      mkdir(join(root, "templates", "fort", "memory"), { recursive: true }),
      mkdir(join(root, "bin"), { recursive: true }),
      mkdir(join(root, "civ", "handoffs"), { recursive: true }),
    ]);
    await Promise.all([
      writeFile(
        join(root, "fort", "memory", "facts", "current-truth.md"),
        fact,
      ),
      writeFile(
        join(root, "fort", "remember.md"),
        "Pointer: fort/remember.md\n",
      ),
      writeFile(
        join(root, "scripts", "memory-lint.mjs"),
        '"fort/remember.md"\n',
      ),
      writeFile(
        join(root, "templates", "fort", "memory", "memory-lint.mjs"),
        '"fort/remember.md"\n',
      ),
      writeFile(join(root, "bin", "fort-init"), "cat > fort/remember.md\n"),
      writeFile(
        join(root, "civ", "handoffs", "migration.md"),
        "Historical record: fort/remember.md\n",
      ),
      writeFile(
        join(root, "civ", "remember.md"),
        "History: fort/remember.md\n",
      ),
      ...violations.map((path) =>
        writeFile(
          join(root, path),
          path === "fort/charter.md"
            ? "Amended 2026-08-11: the migration retired fort/remember.md because the ledger succeeded.\n\nRead fort/remember.md before work.\n"
            : "Read fort/remember.md before work.\n",
        ),
      ),
    ]);

    const stderrPath = join(root, "memory-lint.stderr");
    const failure = await run("sh", [
      "-c",
      '"$1" "$2" "$3" 2> "$4"',
      "sh",
      process.execPath,
      lint,
      root,
      stderrPath,
    ]).catch((error: { code?: number }) => error);
    expect(failure).toMatchObject({ code: 1 });
    const stderr = await readFile(stderrPath, "utf8");
    for (const path of violations) expect(stderr).toContain(join(root, path));

    await Promise.all(
      violations.map((path) =>
        writeFile(join(root, path), "Current memory.\n"),
      ),
    );
    await expect(run(process.execPath, [lint, root])).resolves.toBeDefined();
  });

  test("enforces each seat's core budget and reports the shared floor", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-memory-seat-budget-"));
    await Promise.all([
      mkdir(join(root, "fort", "memory", "facts"), { recursive: true }),
      mkdir(join(root, "fort", "seats"), { recursive: true }),
    ]);
    await Promise.all([
      writeFile(join(root, "fort", "seats", "forge.md"), "# Seat: Forge\n"),
      writeFile(join(root, "fort", "seats", "mayor.md"), "# Seat: Mayor\n"),
      writeFile(
        join(root, "fort", "memory", "facts", "shared.md"),
        fact.replace("key: current-truth", "key: shared"),
      ),
      ...Array.from({ length: 22 }, (_, index) =>
        writeFile(
          join(root, "fort", "memory", "facts", `forge-${index}.md`),
          fact
            .replace("key: current-truth", `key: forge-${index}`)
            .replace("seats: [all]", "seats: [forge]"),
        ),
      ),
    ]);

    await expect(run(process.execPath, [lint, root])).resolves.toBeDefined();
    await writeFile(
      join(root, "fort", "memory", "facts", "forge-22.md"),
      fact
        .replace("key: current-truth", "key: forge-22")
        .replace("seats: [all]", "seats: [forge]"),
    );
    await expect(run(process.execPath, [lint, root])).rejects.toMatchObject({
      code: 1,
    });
  });
});
