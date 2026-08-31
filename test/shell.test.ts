import { execFile, execFileSync } from "node:child_process";
import {
  access,
  chmod,
  cp,
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  unlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { afterEach, describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);
const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const emitCopies = [
  ["shipped", join(repoRoot, "fort/scripts/emit.sh")],
  ["template", join(repoRoot, "templates/fort/scripts/emit.sh")],
] as const;
const roots: string[] = [];
const foundingSmokeSkipReason =
  "founding smoke requires bd+jq; CI install step tracked separately";
const foundingSmokeToolsAvailable = (() => {
  try {
    execFileSync(
      "sh",
      ["-c", "command -v bd >/dev/null && command -v jq >/dev/null"],
      {
        stdio: "ignore",
      },
    );
    return true;
  } catch {
    return false;
  }
})();

async function createFort() {
  const root = await mkdtemp(join(tmpdir(), "fortkit-shell-"));
  roots.push(root);
  await execFileAsync("git", ["init", "--quiet"], { cwd: root });
  return root;
}

async function emit(root: string, emitPath: string, args: string[]) {
  const copiedEmitter = join(root, "emit.sh");
  const source = await readFile(emitPath, "utf8");
  await writeFile(copiedEmitter, source.replaceAll("{{REPO_PATH}}", repoRoot));
  return execFileAsync("bash", [copiedEmitter, ...args], { cwd: root });
}

async function expectNoEvents(root: string) {
  await expect(access(join(root, "fort/events"))).rejects.toMatchObject({
    code: "ENOENT",
  });
}

afterEach(async () => {
  await Promise.all(
    roots
      .splice(0)
      .flatMap((root) => [
        rm(root, { force: true, recursive: true }),
        rm(`${root}-worktrees`, { force: true, recursive: true }),
        rm(`${root}-worktree`, { force: true, recursive: true }),
      ]),
  );
});

describe.each(emitCopies)("%s emit.sh", (_copyName, emitPath) => {
  // Harness pattern: run a shipped script from a git-init'd temporary fort. Its
  // git-common-dir lookup then writes only inside that fort, never live events.
  test("emit.sh rejects malformed positional shapes before writing", async () => {
    const root = await createFort();

    await expect(
      emit(root, emitPath, [
        "work.begun",
        "--bead",
        "fortkit-so2",
        "-a",
        "kethra",
      ]),
    ).rejects.toMatchObject({
      code: 2,
      stderr: expect.stringContaining("detail must not begin with '-'"),
    });
    await expect(
      emit(root, emitPath, ["work.begun", "valid detail", "leftover"]),
    ).rejects.toMatchObject({
      code: 2,
      stderr: expect.stringContaining("unexpected argument: leftover"),
    });
    await expect(
      emit(root, emitPath, ["work.begun", "valid detail", "--", "leftover"]),
    ).rejects.toMatchObject({
      code: 2,
      stderr: expect.stringContaining("unexpected argument: leftover"),
    });
    await expectNoEvents(root);
  });

  test("emit.sh rejects option-shaped categories before writing", async () => {
    const root = await createFort();

    await expect(
      emit(root, emitPath, ["-work.begun", "detail"]),
    ).rejects.toMatchObject({
      code: 2,
      stderr: expect.stringContaining(
        "category must not be empty or begin with '-'",
      ),
    });
    await expect(emit(root, emitPath, ["", "detail"])).rejects.toMatchObject({
      code: 2,
      stderr: expect.stringContaining(
        "category must not be empty or begin with '-'",
      ),
    });
    await expectNoEvents(root);
  });

  test("emit.sh writes a valid event to the temporary fort", async () => {
    const root = await createFort();

    // `--` is deliberately accepted as getopts' conventional option terminator.
    // Since the emitter permits no trailing positionals, anything after it fails.
    await emit(root, emitPath, [
      "work.begun",
      "",
      "-a",
      "kethra",
      "-s",
      "forge",
      "-t",
      "fortkit-so2",
      "-T",
      "2026-08-08T12:34:56Z",
      "--",
    ]);

    const file = join(root, "fort/events/events-2026-08-08.jsonl");
    await expect(readFile(file, "utf8")).resolves.toBe(
      `${JSON.stringify({
        ts: "2026-08-08T12:34:56Z",
        actor: "kethra",
        seat: "forge",
        category: "work.begun",
        target: "fortkit-so2",
        detail: "",
        payload: null,
      })}\n`,
    );
  });
});

describe("scripts/digest.sh", () => {
  async function installDigest(root: string) {
    await mkdir(join(root, "scripts"), { recursive: true });
    await mkdir(join(root, "fort", "events"), { recursive: true });
    await writeFile(
      join(root, "scripts", "digest.sh"),
      await readFile(join(repoRoot, "scripts", "digest.sh"), "utf8"),
    );
    await mkdir(join(root, "fort", "scripts"), { recursive: true });
    await writeFile(
      join(root, "fort", "scripts", "emit.sh"),
      await readFile(join(repoRoot, "fort", "scripts", "emit.sh"), "utf8"),
    );
    await chmod(join(root, "fort", "scripts", "emit.sh"), 0o755);
    await chmod(join(root, "scripts", "digest.sh"), 0o755);
  }

  async function installMergeEventCheck(root: string) {
    await mkdir(join(root, "scripts"), { recursive: true });
    await mkdir(join(root, "fort", "events"), { recursive: true });
    await writeFile(
      join(root, "scripts", "merge-event-check.sh"),
      await readFile(join(repoRoot, "scripts", "merge-event-check.sh"), "utf8"),
    );
    await chmod(join(root, "scripts", "merge-event-check.sh"), 0o755);
  }

  async function installFakeBd(root: string) {
    const bin = join(root, "bin");
    await mkdir(bin);
    await writeFile(
      join(bin, "bd"),
      `#!/bin/sh
case "$*" in
  *--status=closed*) printf '%s\\n' '[{"id":"fortkit-closed","status":"closed","title":"Already closed","closed_at":"2021-01-01T00:00:00Z"}]' ;;
  *--status=in_progress*--label=gate-1*) printf '%s\\n' '[{"id":"fortkit-gate-active","status":"in_progress","title":"Active decision","updated_at":"2026-08-08T00:00:00Z"}]' ;;
  *--label=gate-1*) printf '%s\\n' '[
    {"id":"fortkit-gate-old","status":"open","title":"Older decision","updated_at":"2026-08-01T00:00:00Z"},
    {"id":"fortkit-gate-new","status":"open","title":"Newest decision","updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-gate-3","status":"open","title":"Decision 3","updated_at":"2026-08-03T00:00:00Z"},
    {"id":"fortkit-gate-4","status":"open","title":"Decision 4","updated_at":"2026-08-04T00:00:00Z"},
    {"id":"fortkit-gate-5","status":"open","title":"Decision 5","updated_at":"2026-08-05T00:00:00Z"},
    {"id":"fortkit-gate-6","status":"open","title":"Decision 6","updated_at":"2026-08-06T00:00:00Z"}
  ]' ;;
  *) printf '%s\\n' '[]' ;;
esac
`,
    );
    await chmod(join(bin, "bd"), 0o755);
    return bin;
  }

  test("announces an empty event window instead of succeeding silently", async () => {
    const root = await createFort();
    await installDigest(root);
    const fakeBin = await installFakeBd(root);

    const result = await execFileAsync(
      "bash",
      ["scripts/digest.sh", "--since", "2026-08-01T00:00:00Z"],
      {
        cwd: root,
        env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
      },
    );

    expect(result.stdout).toContain("EMPTY WINDOW");
    expect(result.stdout).toContain("GATE 2: no decisions waiting");
    expect(result.stdout).toContain("showing 5 of 7, most recently updated");
    expect(result.stdout).toContain("2 decision(s) elided; full count is 7");
    expect(result.stdout).toContain(
      "fortkit-gate-active [in_progress] Active decision",
    );
    expect(result.stdout).toContain("fortkit-gate-new [open] Newest decision");
    expect(result.stdout).not.toContain(
      "fortkit-gate-old [open] Older decision",
    );
    expect(result.stdout).toContain(
      "no merge/close/file events in the selected window",
    );
    expect(result.stdout).toContain("no verifier event in the selected window");
  });

  test("uses the main event stream from a worktree and reports the blocking gate", async () => {
    const root = await createFort();
    await installDigest(root);
    await writeFile(
      join(root, "fort", "events", "events-2026-08-01.jsonl"),
      `${JSON.stringify({
        ts: "2026-08-01T23:24:00-08:00",
        actor: "harness",
        seat: null,
        category: "verify.pass",
        target: "fortkit-gate",
        detail: "Verifier passed",
        payload: null,
      })}\n`,
    );
    await execFileAsync("git", ["add", "scripts/digest.sh"], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--quiet",
        "-m",
        "fixture",
      ],
      { cwd: root },
    );
    const worktree = `${root}-worktree`;
    await execFileAsync(
      "git",
      ["worktree", "add", "--detach", "--quiet", worktree],
      { cwd: root },
    );
    const fakeBin = await installFakeBd(root);

    const result = await execFileAsync(
      "bash",
      ["scripts/digest.sh", "--since", "2026-08-02T07:00:00Z"],
      {
        cwd: worktree,
        env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
      },
    );

    expect(result.stdout).toContain("GATE 1: 7 decision(s) waiting");
    expect(result.stdout).toContain("fortkit-gate-new [open] Newest decision");
    expect(result.stdout).toContain("2026-08-01T23:24:00-08:00 verify.pass");
  });

  test("dates active sessions and omits unmatched starts for closed beads", async () => {
    const root = await createFort();
    await installDigest(root);
    await writeFile(
      join(root, "fort", "events", "events-2026-08-01.jsonl"),
      [
        {
          ts: "2026-08-01T01:00:00Z",
          actor: "kethra",
          seat: "forge",
          category: "session.start",
          target: "fortkit-closed",
          detail: "Closed work began",
          payload: null,
        },
        {
          ts: "2026-08-01T02:00:00Z",
          actor: "kethra",
          seat: "forge",
          category: "session.start",
          target: "fortkit-active",
          detail: "Active work began",
          payload: null,
        },
      ]
        .map((event) => JSON.stringify(event))
        .join("\n"),
    );
    const fakeBin = await installFakeBd(root);

    const result = await execFileAsync(
      "bash",
      ["scripts/digest.sh", "--since", "2026-08-01T00:00:00Z"],
      {
        cwd: root,
        env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
      },
    );

    expect(result.stdout).toContain(
      "SESSION forge|fortkit-active (1 unmatched start, started 2026-08-01T02:00:00Z)",
    );
    expect(result.stdout).not.toContain("SESSION forge|fortkit-closed");
    expect(result.stdout).toContain(
      "1 unmatched session start(s) omitted because the target bead is closed",
    );
  });

  test("reports merge and closed-bead audit discrepancies", async () => {
    const root = await createFort();
    await installDigest(root);
    await writeFile(join(root, "tracked"), "tracked\n");
    await execFileAsync("git", ["add", "."], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--quiet",
        "-m",
        "initial",
      ],
      { cwd: root },
    );
    await execFileAsync("git", ["branch", "-M", "main"], { cwd: root });
    await execFileAsync("git", ["checkout", "--quiet", "-b", "fortkit-test"], {
      cwd: root,
    });
    await writeFile(join(root, "change"), "change\n");
    await execFileAsync("git", ["add", "change"], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--quiet",
        "-m",
        "change",
      ],
      { cwd: root },
    );
    await execFileAsync("git", ["checkout", "--quiet", "main"], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "merge",
        "--no-ff",
        "--no-edit",
        "fortkit-test",
      ],
      { cwd: root },
    );
    const fakeBin = await installFakeBd(root);

    const result = await execFileAsync(
      "bash",
      ["scripts/digest.sh", "--since", "2020-01-01T00:00:00Z"],
      {
        cwd: root,
        env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
      },
    );

    expect(result.stdout).toContain("merge events: 0 of 1 commits");
    expect(result.stdout).toContain(
      "WARNING: 1 merge commits in window, 0 merge events",
    );
    expect(result.stdout).toContain("bead.closed events: 0 of 1 closed beads");
    expect(result.stdout).toContain(
      "WARNING: 1 closed beads in window, 0 bead.closed events",
    );

    await writeFile(
      join(root, "fort", "events", "events-2026-08-31.jsonl"),
      [
        {
          ts: new Date().toISOString(),
          actor: "emrith",
          seat: "mayor",
          category: "merge",
          target: "fortkit-test",
          detail: "fixture merged",
          payload: null,
        },
        {
          ts: new Date().toISOString(),
          actor: "emrith",
          seat: "mayor",
          category: "bead.closed",
          target: "fortkit-closed",
          detail: "fixture closed",
          payload: null,
        },
      ]
        .map((event) => JSON.stringify(event))
        .join("\n"),
    );
    const matched = await execFileAsync(
      "bash",
      ["scripts/digest.sh", "--since", "2020-01-01T00:00:00Z"],
      {
        cwd: root,
        env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
      },
    );
    expect(matched.stdout).toContain("merge events: 1 of 1 commits");
    expect(matched.stdout).toContain("bead.closed events: 1 of 1 closed beads");
    expect(matched.stdout.split("VERIFIER")[0]).not.toContain("WARNING:");
  });

  test("matches only identity-linked audit records across a 120-second window edge", async () => {
    const root = await createFort();
    await installDigest(root);
    await writeFile(join(root, "tracked"), "tracked\n");
    await execFileAsync("git", ["add", "."], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--quiet",
        "-m",
        "initial",
      ],
      { cwd: root },
    );
    await execFileAsync("git", ["branch", "-M", "main"], { cwd: root });

    const mergeBranch = async (branch: string, timestamp: string) => {
      await execFileAsync("git", ["checkout", "--quiet", "-b", branch], {
        cwd: root,
      });
      await writeFile(join(root, branch), `${branch}\n`);
      await execFileAsync("git", ["add", branch], { cwd: root });
      await execFileAsync(
        "git",
        [
          "-c",
          "user.name=test",
          "-c",
          "user.email=test@example.invalid",
          "commit",
          "--quiet",
          "-m",
          branch,
        ],
        { cwd: root },
      );
      await execFileAsync("git", ["checkout", "--quiet", "main"], {
        cwd: root,
      });
      await execFileAsync(
        "git",
        [
          "-c",
          "user.name=test",
          "-c",
          "user.email=test@example.invalid",
          "merge",
          "--no-ff",
          "--no-edit",
          "-m",
          `Merge ${branch}: fixture`,
          branch,
        ],
        {
          cwd: root,
          env: {
            ...process.env,
            GIT_AUTHOR_DATE: timestamp,
            GIT_COMMITTER_DATE: timestamp,
          },
        },
      );
    };

    const now = Date.now();
    await mergeBranch("fortkit-boundary", new Date(now - 60_000).toISOString());
    await writeFile(
      join(root, "fort", "events", "events-2026-08-31.jsonl"),
      `${JSON.stringify({ ts: new Date(now - 5_000).toISOString(), actor: "emrith", seat: "mayor", category: "merge", target: "fortkit-boundary", detail: "boundary fixture", payload: null })}\n`,
    );
    const fakeBin = await installFakeBd(root);
    const boundary = await execFileAsync(
      "bash",
      ["scripts/digest.sh", "--since", new Date(now - 30_000).toISOString()],
      {
        cwd: root,
        env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
      },
    );
    expect(boundary.stdout).toContain(
      "boundary tolerance: 120s; 1 merge event matched by identity across a window edge",
    );
    expect(boundary.stdout).toContain("merge events: 0 of 0 commits");
    expect(boundary.stdout.split("VERIFIER")[0]).not.toContain("WARNING:");

    await mergeBranch(
      "fortkit-hour-gap",
      new Date(now - 3_600_000).toISOString(),
    );
    await writeFile(
      join(root, "fort", "events", "events-2026-08-31.jsonl"),
      `${JSON.stringify({ ts: new Date(now - 5_000).toISOString(), actor: "emrith", seat: "mayor", category: "merge", target: "fortkit-hour-gap", detail: "hour-gap fixture", payload: null })}\n`,
    );
    const hourGap = await execFileAsync(
      "bash",
      ["scripts/digest.sh", "--since", new Date(now - 30_000).toISOString()],
      {
        cwd: root,
        env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
      },
    );
    expect(hourGap.stdout).toContain("merge events: 1 of 0 commits");
    expect(hourGap.stdout).toContain(
      "WARNING: 1 merge events in window, 0 merge commits",
    );
  });

  test("merge-event check fails for an unmatched main merge and passes with its event", async () => {
    const root = await createFort();
    await installMergeEventCheck(root);
    await writeFile(join(root, "tracked"), "tracked\n");
    await execFileAsync("git", ["add", "."], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--quiet",
        "-m",
        "initial",
      ],
      { cwd: root },
    );
    await execFileAsync("git", ["branch", "-M", "main"], { cwd: root });
    await execFileAsync("git", ["checkout", "--quiet", "-b", "fortkit-test"], {
      cwd: root,
    });
    await writeFile(join(root, "change"), "change\n");
    await execFileAsync("git", ["add", "change"], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--quiet",
        "-m",
        "change",
      ],
      { cwd: root },
    );
    await execFileAsync("git", ["checkout", "--quiet", "main"], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "merge",
        "--no-ff",
        "--no-edit",
        "-m",
        "Merge fortkit-test: fixture",
        "fortkit-test",
      ],
      { cwd: root },
    );
    const firstMerge = (
      await execFileAsync("git", ["rev-parse", "HEAD"], { cwd: root })
    ).stdout.trim();

    await expect(
      execFileAsync(
        "bash",
        ["scripts/merge-event-check.sh", "--since", "2020-01-01T00:00:00Z"],
        { cwd: root },
      ),
    ).rejects.toMatchObject({
      code: 1,
      stderr: expect.stringContaining("missing merge event"),
    });

    await writeFile(
      join(root, "fort", "events", "events-2026-08-31.jsonl"),
      `${JSON.stringify({ ts: "2026-08-31T00:00:00Z", actor: "emrith", seat: "mayor", category: "merge", target: "fortkit-test", detail: "fixture merged", payload: { mergeCommit: firstMerge } })}\n`,
    );
    const result = await execFileAsync(
      "bash",
      ["scripts/merge-event-check.sh", "--since", "2020-01-01T00:00:00Z"],
      { cwd: root },
    );
    expect(result.stdout).toContain("1 of 1 main commits matched");

    const foreignCwd = await mkdtemp(
      join(tmpdir(), "fortkit-merge-event-cwd-"),
    );
    roots.push(foreignCwd);
    const foreignCwdResult = await execFileAsync(
      "bash",
      [
        join(root, "scripts", "merge-event-check.sh"),
        "--since",
        "2020-01-01T00:00:00Z",
      ],
      { cwd: foreignCwd },
    );
    expect(foreignCwdResult.stdout).toContain("1 of 1 main commits matched");
    expect(foreignCwdResult.stderr).not.toContain("SKIPPED");

    await execFileAsync("git", ["checkout", "--quiet", "--detach"], {
      cwd: root,
    });
    await execFileAsync("git", ["branch", "-D", "main"], { cwd: root });
    const detachedResult = await execFileAsync(
      "bash",
      ["scripts/merge-event-check.sh", "--since", "2020-01-01T00:00:00Z"],
      { cwd: root },
    );
    expect(detachedResult.stderr).toContain(
      "SKIPPED — refs/heads/main is not present",
    );
  });

  test("merge-event check consumes legacy bead events one merge at a time", async () => {
    const root = await createFort();
    await installMergeEventCheck(root);
    await writeFile(join(root, "tracked"), "tracked\n");
    await execFileAsync("git", ["add", "."], { cwd: root });
    await execFileAsync(
      "git",
      [
        "-c",
        "user.name=test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--quiet",
        "-m",
        "initial",
      ],
      { cwd: root },
    );
    await execFileAsync("git", ["branch", "-M", "main"], { cwd: root });

    for (const [index, suffix] of ["first", "second"].entries()) {
      await execFileAsync("git", ["checkout", "--quiet", "-b", suffix], {
        cwd: root,
      });
      await writeFile(join(root, suffix), `${suffix}\n`);
      await execFileAsync("git", ["add", suffix], { cwd: root });
      await execFileAsync(
        "git",
        [
          "-c",
          "user.name=test",
          "-c",
          "user.email=test@example.invalid",
          "commit",
          "--quiet",
          "-m",
          suffix,
        ],
        { cwd: root },
      );
      await execFileAsync("git", ["checkout", "--quiet", "main"], {
        cwd: root,
      });
      await execFileAsync(
        "git",
        [
          "-c",
          "user.name=test",
          "-c",
          "user.email=test@example.invalid",
          "merge",
          "--no-ff",
          "--no-edit",
          "-m",
          "Merge fortkit-test: fixture",
          suffix,
        ],
        { cwd: root },
      );
      if (index === 0) {
        await writeFile(
          join(root, "fort", "events", "events-2026-08-31.jsonl"),
          `${JSON.stringify({ ts: "2026-08-31T00:00:00Z", actor: "emrith", seat: "mayor", category: "merge", target: "fortkit-test", detail: "legacy fixture merged", payload: null })}\n`,
        );
        const legacyResult = await execFileAsync(
          "bash",
          ["scripts/merge-event-check.sh", "--since", "2020-01-01T00:00:00Z"],
          { cwd: root },
        );
        expect(legacyResult.stdout).toContain("1 of 1 main commits matched");
      }
    }

    await writeFile(
      join(root, "fort", "events", "events-2026-08-31.jsonl"),
      `${JSON.stringify({ ts: "2026-08-31T00:00:00Z", actor: "emrith", seat: "mayor", category: "merge", target: "fortkit-test", detail: "legacy fixture merged", payload: null })}\n`,
    );
    await expect(
      execFileAsync(
        "bash",
        ["scripts/merge-event-check.sh", "--since", "2020-01-01T00:00:00Z"],
        { cwd: root },
      ),
    ).rejects.toMatchObject({
      code: 1,
      stderr: expect.stringContaining("missing merge event"),
    });
  });

  test("merge-event check skips explicitly outside a git checkout", async () => {
    const root = await mkdtemp(join(tmpdir(), "fortkit-merge-event-outside-"));
    roots.push(root);
    await mkdir(join(root, "scripts"));
    await writeFile(
      join(root, "scripts", "merge-event-check.sh"),
      await readFile(join(repoRoot, "scripts", "merge-event-check.sh"), "utf8"),
    );

    const result = await execFileAsync(
      "bash",
      ["scripts/merge-event-check.sh"],
      {
        cwd: root,
      },
    );
    expect(result.stderr).toContain("merge-event-check: SKIPPED");
    expect(result.stderr).toContain("is not a git checkout");
  });

  test("anchors a default window at its rendered upper boundary", async () => {
    const root = await createFort();
    await installDigest(root);
    await writeFile(
      join(root, "fort", "events", "events-2026-08-01.jsonl"),
      `${JSON.stringify({
        ts: "2026-08-01T00:00:00Z",
        actor: "harness",
        seat: null,
        category: "digest.emitted",
        target: "digest.sh",
        detail: "Previous digest",
        payload: null,
      })}\n`,
    );
    const fakeBin = await installFakeBd(root);

    const result = await execFileAsync("bash", ["scripts/digest.sh"], {
      cwd: root,
      env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
    });
    const upperBoundary = /\([^,]+, ([^)]+)\]/u.exec(result.stdout)?.[1];
    expect(upperBoundary).toBeDefined();

    const eventFiles = await readdir(join(root, "fort", "events"));
    const events = (
      await Promise.all(
        eventFiles.map(async (file) =>
          (
            await readFile(join(root, "fort", "events", file), "utf8")
          )
            .trim()
            .split("\n")
            .filter(Boolean)
            .map(
              (line) => JSON.parse(line) as { category: string; ts: string },
            ),
        ),
      )
    ).flat();
    const anchor = events.findLast(
      (event) => event.category === "digest.emitted",
    );
    expect(anchor?.ts).toBe(upperBoundary);
  });
});

describe("fort-init", () => {
  test.skipIf(!foundingSmokeToolsAvailable)(
    "renders the Mayor's Codex deny with the founding home path",
    async () => {
      const root = await createFort();
      const registryDirectory = join(root, "registry");
      const founderHome = join(root, "founder-home");
      await mkdir(registryDirectory);
      await mkdir(founderHome);

      await execFileAsync(
        "bash",
        [
          join(repoRoot, "bin/fort-init"),
          root,
          "permissions",
          "Permission test.",
        ],
        {
          env: {
            ...process.env,
            FORT_REGISTRY: join(registryDirectory, "civilization.json"),
            HOME: founderHome,
          },
        },
      );

      const settings = await readFile(
        join(root, ".claude", "settings.json"),
        "utf8",
      );
      const foundedPermissions = JSON.parse(settings).permissions as {
        deny: string[];
      };
      expect(foundedPermissions.deny).toContain(
        `Edit(${founderHome}/.codex/**)`,
      );
      expect(settings).not.toMatch(/{{[A-Z_]*}}/);
    },
  );

  test.skipIf(!foundingSmokeToolsAvailable)(
    `executes the founded fort's unattended artifacts (${foundingSmokeSkipReason})`,
    async () => {
      const root = await createFort();
      const registryDirectory = join(root, "registry");
      await mkdir(registryDirectory);
      await writeFile(
        join(root, "package.json"),
        JSON.stringify({
          private: true,
          scripts: {
            typecheck: "node -e 'process.exit(0)'",
            lint: "node -e 'process.exit(0)'",
            test: "node -e 'process.exit(0)'",
          },
        }),
      );

      await execFileAsync(
        "bash",
        [join(repoRoot, "bin/fort-init"), root, "smoke", "Smoke test fort."],
        {
          env: {
            ...process.env,
            FORT_REGISTRY: join(registryDirectory, "civilization.json"),
          },
        },
      );

      await expect(
        execFileAsync("bash", ["fort/scripts/status.sh"], { cwd: root }),
      ).resolves.toMatchObject({ stdout: expect.any(String) });
      await expect(
        execFileAsync("bash", ["fort/scripts/verify.sh", "--no-emit"], {
          cwd: root,
        }),
      ).resolves.toMatchObject({ stdout: expect.any(String) });
    },
  );

  test.skipIf(!foundingSmokeToolsAvailable)(
    `fails when a rendered status template is broken (${foundingSmokeSkipReason})`,
    async () => {
      const root = await createFort();
      const registryDirectory = join(root, "registry");
      const kit = join(root, "kit");
      await mkdir(registryDirectory);
      await cp(join(repoRoot, "bin"), join(kit, "bin"), { recursive: true });
      await cp(join(repoRoot, "templates"), join(kit, "templates"), {
        recursive: true,
      });
      await writeFile(
        join(kit, "templates/fort/scripts/status.sh"),
        "#!/bin/bash\nexit 91\n",
      );

      await execFileAsync(
        "bash",
        [join(kit, "bin/fort-init"), root, "broken-status", "Smoke test fort."],
        {
          env: {
            ...process.env,
            FORT_REGISTRY: join(registryDirectory, "civilization.json"),
          },
        },
      );

      await expect(
        execFileAsync("bash", ["fort/scripts/status.sh"], { cwd: root }),
      ).rejects.toMatchObject({ code: 91 });
    },
  );

  test.skipIf(!foundingSmokeToolsAvailable)(
    `fails loudly when the founded verifier implementation is missing (${foundingSmokeSkipReason})`,
    async () => {
      const root = await createFort();
      const registryDirectory = join(root, "registry");
      await mkdir(registryDirectory);

      await execFileAsync(
        "bash",
        [
          join(repoRoot, "bin/fort-init"),
          root,
          "broken-verifier",
          "Smoke test fort.",
        ],
        {
          env: {
            ...process.env,
            FORT_REGISTRY: join(registryDirectory, "civilization.json"),
          },
        },
      );
      await unlink(join(root, "scripts/verify-impl.sh"));

      await expect(
        execFileAsync("bash", ["fort/scripts/verify.sh", "--no-emit"], {
          cwd: root,
        }),
      ).rejects.toMatchObject({
        code: 70,
        stderr: expect.stringContaining("NOTHING WAS VERIFIED"),
      });
    },
  );

  test.skipIf(!foundingSmokeToolsAvailable)(
    "a founded fort refuses nested Mayor launches from every seat mask",
    async () => {
      const root = await createFort();
      const registryDirectory = join(root, "registry");
      const fakeBin = join(root, "fake-bin");
      await mkdir(registryDirectory);
      await mkdir(fakeBin);
      await execFileAsync("git", ["config", "user.email", "test@example.com"], {
        cwd: root,
      });
      await execFileAsync("git", ["config", "user.name", "Test"], {
        cwd: root,
      });
      await execFileAsync("git", ["commit", "--allow-empty", "-m", "initial"], {
        cwd: root,
      });

      await execFileAsync(
        "bash",
        [join(repoRoot, "bin/fort-init"), root, "mask", "Mask test fort."],
        {
          env: {
            ...process.env,
            FORT_REGISTRY: join(registryDirectory, "civilization.json"),
          },
        },
      );

      // This narrow bwrap double applies the launcher's FORT_MASKED --setenv
      // and asks the founded Mayor launcher to run unmasked. The Mayor must
      // refuse before it can launch a CLI, so this verifies the runtime path
      // rather than merely inspecting generated launcher text.
      await writeFile(
        join(fakeBin, "bwrap"),
        `#!/bin/bash
set -euo pipefail
marker=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --setenv)
      [ "$2" = FORT_MASKED ] && marker="$3"
      shift 3
      ;;
    --)
      break
      ;;
    *)
      shift
      ;;
  esac
done
env FORT_MASKED="$marker" MAYOR_NO_MASK=1 "$FAKE_BWRAP_ROOT/fort/scripts/mayor.sh" 2>&1
`,
        { mode: 0o755 },
      );

      const runtimeEnvironment = {
        ...process.env,
        FAKE_BWRAP_ROOT: root,
        PATH: `${fakeBin}:${process.env.PATH}`,
      };
      const refusal = (marker: string) =>
        expect.stringContaining(`already inside the '${marker}' seat mask`);

      await expect(
        execFileAsync("bash", ["fort/scripts/mayor.sh"], {
          cwd: root,
          env: { ...runtimeEnvironment, FORT_MASKED: "mayor" },
        }),
      ).rejects.toMatchObject({ code: 77, stderr: refusal("mayor") });
      await expect(
        execFileAsync("bash", ["fort/scripts/forge.sh", "fortkit-mask"], {
          cwd: root,
          env: runtimeEnvironment,
        }),
      ).resolves.toMatchObject({ stdout: refusal("forge") });
      await expect(
        execFileAsync(
          "bash",
          ["fort/scripts/warden.sh", "fortkit-mask", "HEAD", root],
          { cwd: root, env: runtimeEnvironment },
        ),
      ).rejects.toMatchObject({ code: 65, stdout: refusal("warden") });
    },
  );
});
