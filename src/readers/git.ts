import { execFile } from "node:child_process";
import { promisify } from "node:util";

import type { GitState } from "../types.ts";

const execFileAsync = promisify(execFile);

async function git(path: string, args: string[]): Promise<string | null> {
  try {
    const { stdout } = await execFileAsync("git", ["-C", path, ...args], {
      encoding: "utf8",
    });
    return stdout;
  } catch {
    return null;
  }
}

export async function readGitLog(
  path: string,
  since: number,
  until: number,
): Promise<string[] | null> {
  // Git's --since is exclusive, whereas all digest sources include `since`.
  // Query one second early (commit timestamps have second precision), then apply
  // the canonical half-open interval below.
  const querySince = new Date(since - 1000).toISOString();
  const queryUntil = new Date(until).toISOString();
  const output = await git(path, [
    "log",
    "--format=%cI%x09%h%x09%s",
    `--since=${querySince}`,
    `--before=${queryUntil}`,
  ]);
  if (output === null) {
    return null;
  }
  return output
    .trimEnd()
    .split("\n")
    .filter((line) => line !== "")
    .filter((line) => {
      const instant = Date.parse(line.split("\t", 1)[0] ?? "");
      return !Number.isNaN(instant) && instant >= since && instant < until;
    });
}

export async function readGitState(path: string): Promise<GitState> {
  const [insideWorkTree, branch, shortSha, status, worktreeOutput] =
    await Promise.all([
      git(path, ["rev-parse", "--is-inside-work-tree"]),
      git(path, ["branch", "--show-current"]),
      git(path, ["rev-parse", "--short", "HEAD"]),
      git(path, ["--no-optional-locks", "status", "--porcelain"]),
      git(path, ["worktree", "list", "--porcelain"]),
    ]);
  if (insideWorkTree?.trim() !== "true") {
    return {
      branch: null,
      ahead: null,
      behind: null,
      dirty: null,
      worktrees: null,
    };
  }
  const upstream = await git(path, [
    "rev-parse",
    "--abbrev-ref",
    "--symbolic-full-name",
    "@{upstream}",
  ]);
  const divergence =
    upstream === null
      ? null
      : await git(path, [
          "rev-list",
          "--left-right",
          "--count",
          "HEAD...@{upstream}",
        ]);
  const counts = divergence?.trim().split(/\s+/).map(Number);
  const ahead = counts?.[0] ?? null;
  const behind = counts?.[1] ?? null;
  return {
    branch: branch?.trim() || shortSha?.trim() || null,
    ahead: Number.isFinite(ahead) ? ahead : null,
    behind: Number.isFinite(behind) ? behind : null,
    dirty: status === null ? null : status !== "",
    worktrees:
      worktreeOutput === null
        ? null
        : worktreeOutput
            .split(/\r?\n/)
            .flatMap((line) =>
              line.startsWith("worktree ")
                ? [line.slice("worktree ".length)]
                : [],
            ),
  };
}
