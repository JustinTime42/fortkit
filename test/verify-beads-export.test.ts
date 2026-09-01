import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const run = promisify(execFile);
const check = fileURLToPath(
  new URL("../scripts/beads-export-check.sh", import.meta.url),
);

// fortkit-v7us.2. This file IS the `falsified-by` of fort/controls/
// falsifier-beads-export.md, so it must actually be able to fail the stage.
// Twenty-nine of that register's entries carry `falsified-by: null`; this one
// does not, and the claim is only worth making if these assertions would go red
// when the check stops working.

async function hasBd(): Promise<boolean> {
  try {
    await run("bd", ["--version"]);
    return true;
  } catch {
    return false;
  }
}

/** A git checkout with a real Beads workspace and a single bead in it. */
async function beadsFixture() {
  const root = await mkdtemp(join(tmpdir(), "fortkit-beads-export-"));
  await run("git", ["init", "-q", root]);
  await run("git", [
    "-C",
    root,
    "config",
    "user.email",
    "fixture@example.invalid",
  ]);
  await run("git", ["-C", root, "config", "user.name", "fixture"]);
  // `bd -C <dir> init` refuses a directory with no project yet, so the fixture
  // is initialised from inside it exactly as bin/fort-init does.
  await run("bd", ["init"], { cwd: root });
  await run(
    "bd",
    [
      "create",
      "--title=fixture bead",
      "--description=fixture",
      "--type=task",
      "--priority=2",
    ],
    { cwd: root },
  );
  const tracked = join(root, ".beads", "issues.jsonl");
  await mkdir(join(root, ".beads"), { recursive: true });
  await run("bd", ["export", "-o", tracked], { cwd: root });
  return { root, tracked };
}

describe("beads-export-check", () => {
  test("passes when the committed export matches the database", async () => {
    if (!(await hasBd())) return;
    const { root } = await beadsFixture();
    const result = await run(check, [root]);
    expect(result.stderr).toContain("matches the database");
  }, 60_000);

  test("FAILS when the committed export diverges — the control's own falsifier", async () => {
    if (!(await hasBd())) return;
    const { root, tracked } = await beadsFixture();
    const original = await readFile(tracked, "utf8");
    const [first, ...rest] = original.split("\n").filter(Boolean);
    expect(first).toBeDefined();
    const parsed = JSON.parse(first as string);
    parsed.status = parsed.status === "open" ? "closed" : "open";
    await writeFile(
      tracked,
      `${[JSON.stringify(parsed), ...rest].join("\n")}\n`,
    );

    await expect(run(check, [root])).rejects.toMatchObject({ code: 1 });
    try {
      await run(check, [root]);
    } catch (error) {
      const stderr = String((error as { stderr?: string }).stderr ?? "");
      expect(stderr).toContain("does not match the database");
      expect(stderr).toContain("differing content");
      // The remedy must be named, or a red stage gets worked around rather
      // than obeyed (the fortkit-dqu5 habituation failure).
      expect(stderr).toContain("bd export -o");
    }
  }, 60_000);

  test("announces a SKIP, never a silent pass, when there is no committed export", async () => {
    if (!(await hasBd())) return;
    const { root, tracked } = await beadsFixture();
    await run("rm", [tracked]);
    const result = await run(check, [root]);
    expect(result.stderr).toContain("SKIPPED");
    expect(result.stderr).toContain("no committed projection to judge");
  }, 60_000);

  test("announces a SKIP in a worktree, whose export is a branch snapshot", async () => {
    if (!(await hasBd())) return;
    const { root } = await beadsFixture();
    await writeFile(join(root, "README.md"), "fixture\n");
    await run("git", ["-C", root, "add", "README.md"]);
    await run("git", ["-C", root, "commit", "-qm", "init"]);
    const worktree = join(root, "..", `${root.split("/").pop()}-wt`);
    await run("git", [
      "-C",
      root,
      "worktree",
      "add",
      "-q",
      worktree,
      "-b",
      "fixture-branch",
    ]);
    const result = await run(check, [worktree]);
    expect(result.stderr).toContain("SKIPPED");
    expect(result.stderr).toContain("is a worktree of");
  }, 60_000);

  test("announces a SKIP outside a git checkout", async () => {
    if (!(await hasBd())) return;
    const bare = await mkdtemp(join(tmpdir(), "fortkit-beads-export-nogit-"));
    const result = await run(check, [bare]);
    expect(result.stderr).toContain("SKIPPED");
    expect(result.stderr).toContain("not a git checkout");
  }, 60_000);
});
