import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
        join(root, "fort", "handoffs", "forge-2026-08-10.md"),
        "# Handoff: Forge 2026-08-10T01:00:00Z\n\n## State of work\n\n- Ready.\n- Preserve this second line.\n\n## Next actions\n\n1. Ship it.\n2. Verify it.\n",
      ),
      writeFile(
        join(root, "fort", "handoffs", "mayor-2026-08-10.md"),
        "# Handoff: Mayor 2026-08-10T02:00:00Z\n\n## 2. State of session B's work\n\nMayor state.\n\n## Next actions\n\nMayor action.\n",
      ),
      writeFile(
        join(root, "fort", "events", "events-2026-08-10.jsonl"),
        '{"ts":"2026-08-10T02:00:00Z","category":"incident","detail":"Needs attention"}\n',
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

  test("pins the migrated cycle-7 correction as the active Forge truth", async () => {
    const current = await readFile(
      join(repositoryRoot, "fort", "memory", "current.md"),
      "utf8",
    );
    expect(current).toContain("Forge runs with a kernel mask");
    expect(current).not.toContain("read-only set omits fort/charter.md");
  });
});
