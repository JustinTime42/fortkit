import { execFile } from "node:child_process";
import { basename } from "node:path";
import { promisify } from "node:util";

import type { ConstitutionDiff, GitState } from "../types.ts";

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

export type UncorrelatedConstitutionDiff = Omit<
  ConstitutionDiff,
  "announced" | "announcedBeadRef"
>;

// Paths whose history the digest surfaces as constitution changes
// (fortkit-9sa, the cycle-7 prose-gate safeguard). The civ paths exist only in
// the capital; a pathspec that matches nothing yields an empty log, not an
// error, so every fort gets the same query.
const CONSTITUTION_PATHS = [
  "fort/charter.md",
  "fort/seats",
  "civ/covenant.md",
  "civ/seats",
];

export async function readConstitutionDiffs(
  path: string,
  since: number,
  until: number,
): Promise<UncorrelatedConstitutionDiff[] | null> {
  // Same one-second early query + half-open re-filter as readGitLog above.
  const querySince = new Date(since - 1000).toISOString();
  const queryUntil = new Date(until).toISOString();
  const output = await git(path, [
    "log",
    "--name-only",
    "--format=%x1e%cI%x09%h%x09%s",
    `--since=${querySince}`,
    `--before=${queryUntil}`,
    "--",
    ...CONSTITUTION_PATHS,
  ]);
  if (output === null) {
    return null;
  }
  // Bead ids are prefixed with the repo directory name (bd's convention), so a
  // subject with no `<repo>-<id>` token is an amendment with no bead on record.
  const beadRefPattern = new RegExp(
    `\\b${basename(path).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}-[a-z0-9]+(?:\\.[a-z0-9]+)*\\b`,
    "gi",
  );
  return output.split("\x1e").flatMap((record) => {
    const lines = record.split("\n").filter((line) => line !== "");
    const [header, ...files] = lines;
    if (header === undefined) {
      return [];
    }
    const [ts = "", hash = "", ...subjectParts] = header.split("\t");
    const instant = Date.parse(ts);
    if (Number.isNaN(instant) || instant < since || instant >= until) {
      return [];
    }
    const subject = subjectParts.join("\t");
    return [
      {
        ts,
        hash,
        subject,
        files,
        beadRefs: Array.from(
          subject.matchAll(beadRefPattern),
          (match) => match[0],
        ),
      },
    ];
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
