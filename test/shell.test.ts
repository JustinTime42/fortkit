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
  *--all*) printf '%s\\n' '[
    {"id":"fortkit-session","status":"open","title":"Session digest","issue_type":"epic"},
    {"id":"fortkit-gate-active","status":"in_progress","title":"Active decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"dependencies":[{"depends_on_id":"fortkit-hook","type":"blocks"}],"updated_at":"2026-08-08T00:00:00Z"},
    {"id":"fortkit-gate-old","status":"open","title":"Older decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-01T00:00:00Z"},
    {"id":"fortkit-gate-new","status":"open","title":"Newest decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-gate-3","status":"open","title":"Decision 3","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-03T00:00:00Z"},
    {"id":"fortkit-gate-4","status":"open","title":"Decision 4","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-04T00:00:00Z"},
    {"id":"fortkit-gate-5","status":"open","title":"Decision 5","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-05T00:00:00Z"},
    {"id":"fortkit-gate-6","status":"open","title":"Decision 6","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-06T00:00:00Z"},
    {"id":"fortkit-regent","status":"open","title":"Regent sitting","parent":"fortkit-session","labels":["gate-3","act-regent"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-host","status":"open","title":"Install host hook","labels":["gate-2","act-host"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-unclassified","status":"open","title":"Needs classification","labels":["gate-2"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-hook","status":"open","title":"Install the Stop hook"},
    {"id":"fortkit-session-done","status":"closed","title":"Completed digest work","parent":"fortkit-session"}
  ]' ;;
  *--status=closed*) printf '%s\\n' '[{"id":"fortkit-closed","status":"closed","title":"Already closed","closed_at":"2021-01-01T00:00:00Z"}]' ;;
  *gate-1*) printf '%s\\n' '[
    {"id":"fortkit-gate-active","status":"in_progress","title":"Active decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-08T00:00:00Z"},
    {"id":"fortkit-gate-old","status":"open","title":"Older decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-01T00:00:00Z"},
    {"id":"fortkit-gate-new","status":"open","title":"Newest decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-gate-3","status":"open","title":"Decision 3","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-03T00:00:00Z"},
    {"id":"fortkit-gate-4","status":"open","title":"Decision 4","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-04T00:00:00Z"},
    {"id":"fortkit-gate-5","status":"open","title":"Decision 5","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-05T00:00:00Z"},
    {"id":"fortkit-gate-6","status":"open","title":"Decision 6","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-06T00:00:00Z"}
  ]' ;;
  *gate-2*) printf '%s\\n' '[
    {"id":"fortkit-host","status":"open","title":"Install host hook","labels":["gate-2","act-host"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-unclassified","status":"open","title":"Needs classification","labels":["gate-2"],"updated_at":"2026-08-07T00:00:00Z"}
  ]' ;;
  *gate-3*) printf '%s\\n' '[
    {"id":"fortkit-regent","status":"open","title":"Regent sitting","parent":"fortkit-session","labels":["gate-3","act-regent"],"updated_at":"2026-08-07T00:00:00Z"}
  ]' ;;
  *) printf '%s\\n' '[
    {"id":"fortkit-gate-active","status":"in_progress","title":"Active decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-08T00:00:00Z"},
    {"id":"fortkit-gate-old","status":"open","title":"Older decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-01T00:00:00Z"},
    {"id":"fortkit-gate-new","status":"open","title":"Newest decision","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-gate-3","status":"open","title":"Decision 3","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-03T00:00:00Z"},
    {"id":"fortkit-gate-4","status":"open","title":"Decision 4","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-04T00:00:00Z"},
    {"id":"fortkit-gate-5","status":"open","title":"Decision 5","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-05T00:00:00Z"},
    {"id":"fortkit-gate-6","status":"open","title":"Decision 6","parent":"fortkit-session","labels":["gate-1","act-decide"],"updated_at":"2026-08-06T00:00:00Z"},
    {"id":"fortkit-regent","status":"open","title":"Regent sitting","parent":"fortkit-session","labels":["gate-3","act-regent"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-host","status":"open","title":"Install host hook","labels":["gate-2","act-host"],"updated_at":"2026-08-07T00:00:00Z"},
    {"id":"fortkit-unclassified","status":"open","title":"Needs classification","labels":["gate-2"],"updated_at":"2026-08-07T00:00:00Z"}
  ]' ;;
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
    expect(result.stdout).toContain("DECIDE: 7 decision(s) waiting");
    expect(result.stdout).toContain("SUMMON REGENT: 1 decision(s) waiting");
    expect(result.stdout).toContain("ACT ON HOST: 1 decision(s) waiting");
    expect(result.stdout).toContain(
      "ACTION NOT YET CLASSIFIED: 1 decision(s) waiting",
    );
    expect(result.stdout).toContain("showing 5 of 7, most recently updated");
    expect(result.stdout).toContain("2 decision(s) elided; full count is 7");
    expect(result.stdout).toContain(
      "Active decision [fortkit-gate-active; in_progress; gate-1]",
    );
    expect(result.stdout).toContain(
      "Newest decision [fortkit-gate-new; open; gate-1]",
    );
    expect(result.stdout).not.toContain(
      "Older decision [fortkit-gate-old; open; gate-1]",
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

    expect(result.stdout).toContain("DECIDE: 7 decision(s) waiting");
    expect(result.stdout).toContain(
      "Newest decision [fortkit-gate-new; open; gate-1]",
    );
    expect(result.stdout).toContain("2026-08-01T23:24:00-08:00 verify.pass");
  });

  test("groups the live gate queue by subject with progress and titled blockers", async () => {
    const root = await createFort();
    await installDigest(root);
    const fakeBin = await installFakeBd(root);

    const result = await execFileAsync(
      "bash",
      ["scripts/digest.sh", "--by-subject", "--since", "2026-08-01T00:00:00Z"],
      {
        cwd: root,
        env: { ...process.env, PATH: `${fakeBin}:${process.env.PATH}` },
      },
    );

    expect(result.stdout).toContain("BY SUBJECT");
    expect(result.stdout).toContain(
      "Session digest [fortkit-session] — 1/9 done; blocked by: Install the Stop hook",
    );
    expect(result.stdout).toContain(
      "Active decision [fortkit-gate-active; in_progress; act-decide; gate-1]",
    );
    expect(result.stdout).toContain(
      "Install host hook [fortkit-host; open; act-host; gate-2]",
    );
    expect(result.stdout).not.toContain("Install host hook [fortkit-host] —");
    const subjectSection = result.stdout.split("BY SUBJECT\n")[1];
    if (subjectSection === undefined) throw new Error("BY SUBJECT section was not rendered");
    expect(subjectSection.match(/Install host hook/g)).toHaveLength(1);
    expect(result.stdout).not.toContain("blocked by: fortkit-hook");
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

describe("scripts/quiescent.sh and digest-hook.sh", () => {
  async function installQuiescence(root: string) {
    await mkdir(join(root, "scripts"), { recursive: true });
    await mkdir(join(root, "fort", "events"), { recursive: true });
    for (const script of ["quiescent.sh", "digest-hook.sh"]) {
      await writeFile(
        join(root, "scripts", script),
        await readFile(join(repoRoot, "scripts", script), "utf8"),
      );
      await chmod(join(root, "scripts", script), 0o755);
    }
  }

  test("ignores Mayor's unmatched session start but reports a live Forge lock", async () => {
    const root = await createFort();
    await installQuiescence(root);
    const worktrees = join(root, "worktrees");
    const forgeWorktree = join(worktrees, "zj8e3");
    await mkdir(forgeWorktree, { recursive: true });
    const lock = join(forgeWorktree, ".forge.lock");
    await writeFile(lock, "");
    await writeFile(join(forgeWorktree, ".forge.lock.info"), "fixture holder");
    await writeFile(
      join(root, "fort", "events", "events-2026-08-31.jsonl"),
      `${JSON.stringify({
        ts: new Date().toISOString(),
        actor: "emrith",
        seat: "mayor",
        category: "session.start",
        target: null,
        detail: "Mayor start",
        payload: null,
      })}\n`,
    );

    const result = await execFileAsync(
      "bash",
      [
        "-c",
        'exec 9>"$1"; flock -n 9; "$2"',
        "--",
        lock,
        join(root, "scripts", "quiescent.sh"),
      ],
      { cwd: root, env: { ...process.env, FORTKIT_WORKTREES_ROOT: worktrees } },
    ).catch((error: { code?: number; stdout?: string }) => error);

    expect(result).toMatchObject({ code: 1 });
    expect(result.stdout).toContain("busy: forge lock");
    expect(result.stdout).toContain("fixture holder");
  });

  test("reports a fresh non-Mayor session as busy", async () => {
    const root = await createFort();
    await installQuiescence(root);
    await writeFile(
      join(root, "fort", "events", "events-2026-08-31.jsonl"),
      `${JSON.stringify({
        ts: new Date().toISOString(),
        actor: "kethra",
        seat: "forge",
        category: "session.start",
        target: "fortkit-live",
        detail: "Forge starts work",
        payload: null,
      })}\n`,
    );

    const result = await execFileAsync("bash", ["scripts/quiescent.sh"], {
      cwd: root,
      env: {
        ...process.env,
        FORTKIT_WORKTREES_ROOT: join(root, "worktrees"),
      },
    }).catch((error: { code?: number; stdout?: string }) => error);

    expect(result).toMatchObject({ code: 1 });
    expect(result.stdout).toContain("busy: session forge|fortkit-live");
  });

  test("ignores a Bash command that merely names another fort's Warden script", async () => {
    const root = await createFort();
    await installQuiescence(root);
    const foreignWarden = join(
      root,
      "other-fort",
      "fort",
      "scripts",
      "warden.sh",
    );
    await mkdir(join(root, "other-fort", "fort", "scripts"), {
      recursive: true,
    });
    await writeFile(foreignWarden, "#!/bin/sh\n");
    const ready = join(root, "foreign-warden-name-ready");
    const child = execFile(
      "bash",
      [
        "-c",
        'touch "$1"; while :; do sleep 1; done',
        "bash",
        ready,
        foreignWarden,
      ],
      { cwd: root },
    );

    try {
      for (let attempt = 0; attempt < 20; attempt += 1) {
        try {
          await access(ready);
          break;
        } catch {
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      }
      await access(ready);

      const result = await execFileAsync("bash", ["scripts/quiescent.sh"], {
        cwd: root,
        env: {
          ...process.env,
          FORTKIT_WORKTREES_ROOT: join(root, "worktrees"),
        },
      }).catch((error: { stdout?: string }) => error);

      // The predicate observes /proc, so unrelated real seats may legitimately
      // print their own busy reasons. The fixture's confounder must not.
      expect(result.stdout).not.toContain(`pid=${child.pid}`);
      expect(result.stdout).not.toContain(foreignWarden);
    } finally {
      child.kill("SIGTERM");
    }
  });

  test("reports Bash executing this fort's Warden script as busy", async () => {
    const root = await createFort();
    await installQuiescence(root);
    const wardenDirectory = join(root, "fort", "scripts");
    const wardenScript = join(wardenDirectory, "warden.sh");
    const ready = join(root, "warden-ready");
    await mkdir(wardenDirectory, { recursive: true });
    await writeFile(
      wardenScript,
      `#!/bin/bash
touch "${ready}"
while :; do sleep 1; done
`,
    );
    await chmod(wardenScript, 0o755);
    // Mayor launches Wardens from the fort root with a relative script path.
    const child = execFile("bash", ["fort/scripts/warden.sh"], { cwd: root });

    try {
      for (let attempt = 0; attempt < 20; attempt += 1) {
        try {
          await access(ready);
          break;
        } catch {
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      }
      await access(ready);

      const result = await execFileAsync("bash", ["scripts/quiescent.sh"], {
        cwd: root,
        env: {
          ...process.env,
          FORTKIT_WORKTREES_ROOT: join(root, "worktrees"),
        },
      }).catch((error: { code?: number; stdout?: string }) => error);

      expect(result).toMatchObject({ code: 1 });
      expect(result.stdout).toContain("busy: warden process");
    } finally {
      child.kill("SIGTERM");
    }
  });

  test("reports Bash executing this fort's Warden script by absolute path as busy", async () => {
    const root = await createFort();
    await installQuiescence(root);
    const wardenDirectory = join(root, "fort", "scripts");
    const wardenScript = join(wardenDirectory, "warden.sh");
    const ready = join(root, "absolute-warden-ready");
    await mkdir(wardenDirectory, { recursive: true });
    await writeFile(
      wardenScript,
      `#!/bin/bash
touch "${ready}"
while :; do sleep 1; done
`,
    );
    await chmod(wardenScript, 0o755);
    const child = execFile("bash", [wardenScript], { cwd: root });

    try {
      for (let attempt = 0; attempt < 20; attempt += 1) {
        try {
          await access(ready);
          break;
        } catch {
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      }
      await access(ready);

      const result = await execFileAsync("bash", ["scripts/quiescent.sh"], {
        cwd: root,
        env: {
          ...process.env,
          FORTKIT_WORKTREES_ROOT: join(root, "worktrees"),
        },
      }).catch((error: { code?: number; stdout?: string }) => error);

      expect(result).toMatchObject({ code: 1 });
      expect(result.stdout).toContain(`busy: warden process pid=${child.pid}`);
    } finally {
      child.kill("SIGTERM");
    }
  });

  test("reports Bash executing this fort's verifier by relative path as busy", async () => {
    const root = await createFort();
    await installQuiescence(root);
    const verifierDirectory = join(root, "scripts");
    const verifierScript = join(verifierDirectory, "verify-impl.sh");
    const ready = join(root, "verifier-ready");
    await writeFile(
      verifierScript,
      `#!/bin/bash
touch "${ready}"
while :; do sleep 1; done
`,
    );
    await chmod(verifierScript, 0o755);
    const child = execFile("bash", ["scripts/verify-impl.sh"], { cwd: root });

    try {
      for (let attempt = 0; attempt < 20; attempt += 1) {
        try {
          await access(ready);
          break;
        } catch {
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      }
      await access(ready);

      const result = await execFileAsync("bash", ["scripts/quiescent.sh"], {
        cwd: root,
        env: {
          ...process.env,
          FORTKIT_WORKTREES_ROOT: join(root, "worktrees"),
        },
      }).catch((error: { code?: number; stdout?: string }) => error);

      expect(result).toMatchObject({ code: 1 });
      expect(result.stdout).toContain("busy: verifier process");
    } finally {
      child.kill("SIGTERM");
    }
  });

  test("declines the hook with the quiescence reason and does not run the digest", async () => {
    const root = await createFort();
    await installQuiescence(root);
    const worktrees = join(root, "worktrees");
    const forgeWorktree = join(worktrees, "zj8e3");
    await mkdir(forgeWorktree, { recursive: true });
    const lock = join(forgeWorktree, ".forge.lock");
    await writeFile(lock, "");
    await writeFile(join(forgeWorktree, ".forge.lock.info"), "fixture holder");
    const digest = join(root, "digest-fixture.sh");
    await writeFile(digest, "#!/bin/sh\nprintf 'DIGEST RAN\\n'\n");
    await chmod(digest, 0o755);

    const result = await execFileAsync(
      "bash",
      [
        "-c",
        'exec 9>"$1"; flock -n 9; "$2"',
        "--",
        lock,
        join(root, "scripts", "digest-hook.sh"),
      ],
      {
        cwd: root,
        env: {
          ...process.env,
          FORTKIT_WORKTREES_ROOT: worktrees,
          DIGEST_SCRIPT: digest,
        },
      },
    );

    expect(result.stdout).toContain(
      "digest-hook: declined; fort is not quiescent",
    );
    expect(result.stdout).toContain("busy: forge lock");
    expect(result.stdout).not.toContain("DIGEST RAN");
  });

  test("runs the digest when the fort is quiet", async () => {
    const root = await createFort();
    await installQuiescence(root);
    // The full verifier is itself a live verifier process, so replace only
    // this predicate fixture with its already-proven quiet result.
    await writeFile(
      join(root, "scripts", "quiescent.sh"),
      "#!/bin/sh\nexit 0\n",
    );
    await chmod(join(root, "scripts", "quiescent.sh"), 0o755);
    const digest = join(root, "digest-fixture.sh");
    await writeFile(digest, "#!/bin/sh\nprintf 'DIGEST RAN\\n'\n");
    await chmod(digest, 0o755);

    const result = await execFileAsync("bash", ["scripts/digest-hook.sh"], {
      cwd: root,
      env: {
        ...process.env,
        FORTKIT_WORKTREES_ROOT: join(root, "worktrees"),
        DIGEST_SCRIPT: digest,
      },
    });

    expect(result.stdout).toBe("DIGEST RAN\n");
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
