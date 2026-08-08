import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

import { readColony } from "../src/colony-reader.js";

const execFileAsync = promisify(execFile);

async function createFort(root: string, name = "Temporary"): Promise<string> {
  const fort = join(root, name);
  await Promise.all([
    mkdir(join(fort, ".beads"), { recursive: true }),
    mkdir(join(fort, "fort", "events"), { recursive: true }),
    mkdir(join(fort, "fort", "handoffs"), { recursive: true }),
    mkdir(join(fort, "fort", "seats"), { recursive: true }),
  ]);
  await execFileAsync("git", ["init", "--quiet", fort]);
  return fort;
}

async function writeRegistry(
  root: string,
  forts: Array<{ fort_name: string; repo: string }>,
): Promise<string> {
  const path = join(root, "civilization.json");
  await writeFile(path, JSON.stringify({ forts }));
  return path;
}

describe("colony reader", () => {
  test("resolves the registered fort and fans out to every colony reader", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-colony-reader-"));
    try {
      const fort = await createFort(root);
      await Promise.all([
        writeFile(
          join(fort, ".beads", "issues.jsonl"),
          JSON.stringify({
            id: "fortkit-test",
            status: "open",
            issue_type: "task",
            labels: ["test"],
            dependencies: [],
            created_at: "2026-08-07T00:00:00Z",
            updated_at: "2026-08-07T00:00:00Z",
          }),
        ),
        writeFile(
          join(fort, "fort", "events", "events-2026-08-07.jsonl"),
          JSON.stringify({
            ts: "2026-08-07T12:00:00Z",
            actor: "Kethra Anvilmark",
            seat: "forge",
            category: "session.start",
            target: "fortkit-test",
            detail: "Reader fixture",
            payload: null,
          }),
        ),
        writeFile(
          join(fort, "fort", "seats", "forge.md"),
          '# Seat: Forge\n\n**Held by: Dorin Stoneward** (he/him)\n\n**Personality (in his own words):** "Builds durable lenses"\n',
        ),
        writeFile(
          join(fort, "fort", "handoffs", "forge-2026-08-07.md"),
          "# Handoff: Forge 2026-08-07T12:00:00Z\n",
        ),
      ]);
      const registry = await writeRegistry(root, [
        { fort_name: "Temporary", repo: fort },
      ]);

      const projection = await readColony(registry, "Temporary");

      expect(projection).toMatchObject({
        workshops: [
          { type: "implementation", beads: [] },
          { type: "spec", beads: [] },
          { type: "test", beads: [{ id: "fortkit-test" }] },
          { type: "infra", beads: [] },
        ],
        benches: [{ worktree: fort, session: null }],
        announcements: ["Reader fixture"],
        citizens: [
          {
            name: "Dorin Stoneward",
            pronouns: "he/him",
            seat: "Forge",
            personality: "Builds durable lenses",
            currentBead: "fortkit-test",
            session: expect.objectContaining({ beadId: "fortkit-test" }),
            lastHandoff: "Handoff: Forge 2026-08-07T12:00:00Z",
          },
        ],
        gaps: [],
      });
      expect(await readColony(registry, fort)).toBeNull();
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test.each([
    ["his", "Builds durable lenses"],
    ["their", "Builds durable lenses"],
    ["Their", null],
  ])(
    "parses personality phrasing case-sensitively: in %s own words",
    async (pronoun, personality) => {
      const root = await mkdtemp(join(tmpdir(), "fortkit-colony-reader-"));
      try {
        const fort = await createFort(root);
        await writeFile(
          join(fort, "fort", "seats", "forge.md"),
          `# Seat: Forge\n\n**Held by: Ari Vale** (they/them)\n\n**Personality (in ${pronoun} own words):** "Builds durable lenses"\n`,
        );
        const registry = await writeRegistry(root, [
          { fort_name: "Temporary", repo: fort },
        ]);

        expect((await readColony(registry, "Temporary"))?.citizens).toEqual([
          expect.objectContaining({ personality }),
        ]);
      } finally {
        await rm(root, { recursive: true, force: true });
      }
    },
  );

  test("propagates absent fort and zero-parse roster gaps", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-colony-reader-"));
    try {
      const absent = join(root, "absent");
      const fort = await createFort(root, "unseated");
      await writeFile(
        join(fort, "fort", "seats", "forge.md"),
        "# Seat: Forge\n\n**Held by:** {{UNFILLED — set at the Founding Moot}}\n",
      );
      const registry = await writeRegistry(root, [
        { fort_name: "Absent", repo: absent },
        { fort_name: "Unseated", repo: fort },
      ]);

      expect((await readColony(registry, "Absent"))?.gaps).toEqual([
        "Beads export ABSENT",
        "git worktree list ABSENT",
        "event stream ABSENT",
        "seats roster ABSENT",
      ]);
      expect((await readColony(registry, "Unseated"))?.gaps).toContain(
        "seats roster present, nothing parsed",
      );
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });

  test("uses an em dash for a present holder without parseable pronouns", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-colony-reader-"));
    try {
      const fort = await createFort(root);
      await writeFile(
        join(fort, "fort", "seats", "forge.md"),
        "# Seat: Forge\n\n**Held by: Brunna Stonevein** (unparseable)\n",
      );
      const registry = await writeRegistry(root, [
        { fort_name: "Temporary", repo: fort },
      ]);

      expect((await readColony(registry, "Temporary"))?.citizens).toEqual([
        {
          name: "Brunna Stonevein",
          pronouns: "—",
          seat: "Forge",
          personality: null,
          currentBead: null,
          session: null,
          lastHandoff: null,
        },
      ]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
