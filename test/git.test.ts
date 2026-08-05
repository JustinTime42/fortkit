import { execFile } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

import { readGitState } from "../src/readers/git.js";

const execFileAsync = promisify(execFile);

describe("git reader", () => {
  test("reports a short SHA for a detached HEAD", async () => {
    const path = await mkdtemp(join(tmpdir(), "fortkit-git-"));
    try {
      await execFileAsync("git", ["init", "--quiet", path]);
      await execFileAsync("git", [
        "-C",
        path,
        "config",
        "user.email",
        "test@example.test",
      ]);
      await execFileAsync("git", ["-C", path, "config", "user.name", "Test"]);
      await writeFile(join(path, "README.md"), "fixture\n");
      await execFileAsync("git", ["-C", path, "add", "README.md"]);
      await execFileAsync("git", [
        "-C",
        path,
        "commit",
        "--quiet",
        "-m",
        "fixture",
      ]);
      const { stdout } = await execFileAsync("git", [
        "-C",
        path,
        "rev-parse",
        "--short",
        "HEAD",
      ]);
      await execFileAsync("git", [
        "-C",
        path,
        "checkout",
        "--quiet",
        "--detach",
      ]);
      await expect(readGitState(path)).resolves.toMatchObject({
        branch: stdout.trim(),
      });
    } finally {
      await rm(path, { recursive: true, force: true });
    }
  });
});
