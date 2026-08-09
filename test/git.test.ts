import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join } from "node:path";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

import {
  readConstitutionDiffs,
  readGitLog,
  readGitState,
} from "../src/readers/git.js";

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

  test("uses parsed date-only bounds with an inclusive since boundary", async () => {
    const path = await mkdtemp(join(tmpdir(), "fortkit-git-digest-"));
    const commit = async (message: string, date: string) => {
      await writeFile(join(path, "README.md"), `${message}\n`);
      await execFileAsync("git", ["-C", path, "add", "README.md"]);
      await execFileAsync(
        "git",
        ["-C", path, "commit", "--quiet", "--date", date, "-m", message],
        {
          env: {
            ...process.env,
            GIT_AUTHOR_DATE: date,
            GIT_COMMITTER_DATE: date,
          },
        },
      );
    };
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
      await commit("before", "2026-08-03T23:59:59Z");
      await commit("at since", "2026-08-04T00:00:00Z");
      await commit("inside", "2026-08-04T12:00:00Z");
      await commit("at until", "2026-08-05T00:00:00Z");

      await expect(
        readGitLog(path, Date.parse("2026-08-04"), Date.parse("2026-08-05")),
      ).resolves.toEqual([
        expect.stringContaining("inside"),
        expect.stringContaining("at since"),
      ]);
    } finally {
      await rm(path, { recursive: true, force: true });
    }
  });

  test("surfaces constitution diffs with bead refs, ignoring other paths and the window's outside", async () => {
    const path = await mkdtemp(join(tmpdir(), "fortkit-git-constitution-"));
    const beadPrefix = basename(path);
    const commit = async (file: string, message: string, date: string) => {
      await mkdir(join(path, dirname(file)), { recursive: true });
      await writeFile(join(path, file), `${message}\n`);
      await execFileAsync("git", ["-C", path, "add", file]);
      await execFileAsync(
        "git",
        ["-C", path, "commit", "--quiet", "--date", date, "-m", message],
        {
          env: {
            ...process.env,
            GIT_AUTHOR_DATE: date,
            GIT_COMMITTER_DATE: date,
          },
        },
      );
    };
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
      await commit(
        "fort/charter.md",
        `${beadPrefix}-x1y: amend the charter`,
        "2026-08-04T08:00:00Z",
      );
      await commit(
        "src/other.ts",
        "unrelated source change",
        "2026-08-04T09:00:00Z",
      );
      await commit(
        "fort/seats/mayor.md",
        "quiet seat edit with no bead",
        "2026-08-04T10:00:00Z",
      );
      await commit(
        "fort/charter.md",
        `${beadPrefix}-zzz: outside the window`,
        "2026-08-05T00:00:00Z",
      );

      await expect(
        readConstitutionDiffs(
          path,
          Date.parse("2026-08-04"),
          Date.parse("2026-08-05"),
        ),
      ).resolves.toEqual([
        expect.objectContaining({
          subject: "quiet seat edit with no bead",
          files: ["fort/seats/mayor.md"],
          beadRef: null,
        }),
        expect.objectContaining({
          subject: `${beadPrefix}-x1y: amend the charter`,
          files: ["fort/charter.md"],
          beadRef: `${beadPrefix}-x1y`,
        }),
      ]);
    } finally {
      await rm(path, { recursive: true, force: true });
    }
  });
});
