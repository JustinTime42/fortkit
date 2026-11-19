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
  symlink,
  unlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { afterEach, beforeEach, describe, expect, test } from "vitest";

import {
  nestedShellSpawnSkipReason,
  shellSpawnSkipReason,
  spawnPermissionSkipReason,
} from "./spawn-permission.js";

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

// The late registry catch can only be provoked with a real bind mount, so its
// control is gated on bwrap the way the founding smoke is gated on bd+jq. It
// skips with a named reason rather than silently (Ilva Trueglass, finding 2 on
// the fortkit-2twy review).
const bwrapSkipReason =
  "the late registry catch needs bwrap to build a bind mount";
const bwrapAvailable = (() => {
  try {
    execFileSync("sh", ["-c", "command -v bwrap"], { stdio: "ignore" });
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

test("only classifies spawn permission failures as shell-test skips", () => {
  expect(spawnPermissionSkipReason({ code: "EPERM" })).toContain("EPERM");
  expect(spawnPermissionSkipReason({ code: "EACCES" })).toContain("EACCES");
  expect(spawnPermissionSkipReason({ code: "ENOENT" })).toBeNull();
  expect(spawnPermissionSkipReason({ code: 1 })).toBeNull();
});

// The Forge mask denies every shell spawn with EPERM. Check immediately before
// each test because a one-time probe is not evidence that a later spawn works.
// In a normal posture this hook is inactive and all existing positive controls
// and deliberate-failure tests still run.
let announcedShellSpawnSkip = false;
beforeEach(async (context) => {
  if (
    context.task.name ===
    "only classifies spawn permission failures as shell-test skips"
  ) {
    return;
  }
  const reason = shellSpawnSkipReason() ?? (await nestedShellSpawnSkipReason());
  if (reason === null) return;
  if (!announcedShellSpawnSkip) {
    console.warn(`shell-spawning tests: SKIPPED - ${reason}`);
    announcedShellSpawnSkip = true;
  }
  context.skip(reason);
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

// RETIRED AT THE RE-FOUNDING (2026-11-18, fortkit-ttpk; the Overseer's decision recorded on
// that bead). Fifteen tests that pinned Manyhalls's former scripts/digest.sh, quiescent.sh and
// digest-hook.sh were removed with those scripts, which were replaced by the copies the new
// launchers and fleet are built against. Their replacements are covered by
// scripts/digest-harness.sh (digest.sh, digest-hook.sh, digest-transcript.sh) and, for
// quiescent.sh, by the two cases kept below and the fleet harnesses that call it.
// The merge-event tests below are unchanged: scripts/merge-event-check.sh is Manyhalls's own.

describe("scripts/digest.sh", () => {
  async function installMergeEventCheck(root: string) {
    await mkdir(join(root, "scripts"), { recursive: true });
    await mkdir(join(root, "fort", "events"), { recursive: true });
    await writeFile(
      join(root, "scripts", "merge-event-check.sh"),
      await readFile(join(repoRoot, "scripts", "merge-event-check.sh"), "utf8"),
    );
    await chmod(join(root, "scripts", "merge-event-check.sh"), 0o755);
  }

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
});

describe("scripts/quiescent.sh and digest-hook.sh", () => {
  async function installQuiescence(root: string) {
    await mkdir(join(root, "scripts"), { recursive: true });
    await mkdir(join(root, "fort", "events"), { recursive: true });
    for (const script of ["quiescent.sh", "digest-hook.sh", "digest.sh"]) {
      await writeFile(
        join(root, "scripts", script),
        await readFile(join(repoRoot, "scripts", script), "utf8"),
      );
      await chmod(join(root, "scripts", script), 0o755);
    }
  }

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

// RETIRED AT THE RE-FOUNDING (2026-11-18, fortkit-ttpk, docket T10): three tests of the
// former template verifier's npm stages (skip with no package.json, skip an absent script,
// fail on a failing script). That verifier is replaced by a product-gate STUB, so those
// stages no longer exist in a founded fort; the stub's contract is asserted in "executes
// the founded fort's unattended artifacts" below. Founding renders about 140 files now,
// so every case here gets a longer timeout than the suite default.
describe("fort-init", { timeout: 120_000 }, () => {
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
      // THE PRODUCT GATE IS A STUB (Regent sitting 2026-11-18, fortkit-ttpk, docket
      // T10): the founded verifier runs its own lints and then fails at the step
      // named product-gate, by design, until the fort wires its build and tests.
      // The server tier runs the lints and the product gate and skips the
      // machinery harnesses, which take minutes and are proved by founding a
      // fort and running the whole verifier (the docket's T12). The tree is
      // committed first: the verifier refuses untracked files where the host
      // executes.
      await execFileAsync(
        "git",
        ["add", "--", "fort", "scripts", ".claude", "docs", "package.json"],
        { cwd: root },
      );
      await execFileAsync(
        "git",
        [
          "-c",
          "user.email=h@example.invalid",
          "-c",
          "user.name=harness",
          "commit",
          "--quiet",
          "-m",
          "found",
        ],
        { cwd: root },
      );
      let stub: { code?: number; stderr?: string } | undefined;
      try {
        await execFileAsync("bash", ["fort/scripts/verify.sh", "--no-emit"], {
          cwd: root,
          env: { ...process.env, VERIFY_TIER: "server" },
        });
      } catch (error) {
        stub = error as { code?: number; stderr?: string };
      }
      expect(stub?.code).toBe(1);
      expect(stub?.stderr).toContain("NO PRODUCT GATE IS WIRED");
      expect(stub?.stderr).toContain("step 'product-gate' FAILED");
      expect(
        (stub?.stderr ?? "").match(/verify: step '[a-z-]+' FAILED/g),
      ).toHaveLength(1);

      // The clean founding beside the three deliberate failures below
      // (fortkit-2twy). A refusal control set proves only that the script says
      // no; this is the half that proves it still says yes correctly.
      // current.md is the distilled view injected into every seat at session
      // start, and 200 bytes is the same threshold bin/fort-init asserts on
      // itself — a fort born without it starts every session blind.
      const distilled = await readFile(
        join(root, "fort", "memory", "current.md"),
        "utf8",
      );
      expect(distilled.length).toBeGreaterThanOrEqual(200);

      const stream = await readdir(join(root, "fort", "events"));
      const emitted = (
        await Promise.all(
          stream
            .filter((name) => name.endsWith(".jsonl"))
            .map((name) =>
              readFile(join(root, "fort", "events", name), "utf8"),
            ),
        )
      )
        .flatMap((text) => text.split("\n"))
        .filter((line) => line.trim() !== "")
        .map((line) => JSON.parse(line) as { category: string });
      expect(
        emitted.filter((event) => event.category === "fort.founded"),
      ).toHaveLength(1);
      expect(
        emitted.filter((event) => event.category === "seat.founded"),
      ).toHaveLength(4);
      expect(
        JSON.parse(
          await readFile(join(registryDirectory, "civilization.json"), "utf8"),
        ).forts,
      ).toHaveLength(1);
    },
  );

  test.skipIf(!foundingSmokeToolsAvailable)(
    `fails when a rendered status template is broken (${foundingSmokeSkipReason})`,
    async () => {
      const root = await createFort();
      const registryDirectory = join(root, "registry");
      const kit = join(root, "kit");
      await mkdir(registryDirectory);
      await cp(join(repoRoot, "bin"), join(kit, "bin"), {
        recursive: true,
      });
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
        // warden.sh makes its per-review directory under XDG_DATA_HOME. Without
        // this it used the developer's real HOME, and failed in a read-only one
        // (the Warden's finding 5, review 2 on fortkit-ttpk).
        XDG_DATA_HOME: join(root, ".xdg-data"),
      };
      const refusal = (marker: string) =>
        expect.stringContaining(`already inside the '${marker}' seat mask`);

      await expect(
        execFileAsync("bash", ["fort/scripts/mayor.sh"], {
          cwd: root,
          env: { ...runtimeEnvironment, FORT_MASKED: "mayor" },
        }),
      ).rejects.toMatchObject({ code: 77, stderr: refusal("mayor") });
      // The launchers of the 2026-11-18 template refresh read their bead from the
      // tracker and work in a worktree cut from HEAD, so the founded tree is
      // committed and a real bead is filed, as a real founding would have. What
      // is asserted is unchanged: the Mayor launcher, run inside each seat's
      // mask, refuses and names the mask. The launchers' own exit codes are not
      // pinned: with a runtime that only refuses, each ends on its no-result path.
      await execFileAsync(
        "git",
        ["add", "--", "fort", "scripts", ".claude", "docs"],
        { cwd: root },
      );
      await execFileAsync("git", ["commit", "--quiet", "-m", "found"], {
        cwd: root,
      });
      const { stdout: created } = await execFileAsync(
        "bd",
        [
          "create",
          "--title",
          "mask probe",
          "--description",
          "nested launch refusal",
          "-t",
          "task",
          "-p",
          "3",
          "--silent",
        ],
        { cwd: root },
      );
      const bead = created.trim();
      const output = async (launcher: string, args: string[]) => {
        try {
          const done = await execFileAsync(
            "bash",
            [`fort/scripts/${launcher}`, ...args],
            { cwd: root, env: runtimeEnvironment },
          );
          return `${done.stdout}${done.stderr}`;
        } catch (error) {
          const failed = error as { stdout?: string; stderr?: string };
          return `${failed.stdout ?? ""}${failed.stderr ?? ""}`;
        }
      };
      expect(await output("forge.sh", [bead])).toEqual(refusal("forge"));
      expect(await output("warden.sh", [bead, "HEAD", root])).toEqual(
        refusal("warden"),
      );
    },
  );

  // ==================================================================
  // FOUNDING INTEGRITY (fortkit-2twy, closing fortkit-9ahr and fortkit-fg7s
  // and guarding the ordering half of fortkit-byhp).
  //
  // bin/fort-init used to discover fatal conditions AFTER it had built the
  // tree, initialised bd, emitted the founding events and written the
  // civilization registry; `set -euo pipefail` then aborted mid-founding and
  // left a fort that LOOKS founded. fortkit-fg7s records one of those wrecks
  // reproducing an unrelated bug's symptom for the wrong reason and nearly
  // confirming a false hypothesis.
  //
  // THESE ARE POSITIVE CONTROLS. Each names the state the world must be in
  // after a deliberate failure rather than merely asserting that a command
  // failed, because without that this is one ordering claim replacing
  // another — which is what fortkit-9ahr's own acceptance criterion says.
  // ==================================================================

  // THE PATH SHIM IS NOT DECORATION. /usr/bin/node is a distinct binary from
  // the nvm one, so dropping the nvm directory from PATH does NOT hide node,
  // and a control built that way founds a fort successfully while reporting
  // that it measured a node-less host (recorded 2026-08-17). Symlink all of
  // /usr/bin except the node family, then re-add the tools that live
  // elsewhere. Pass `fakeNode` to put a node on PATH that always fails, which
  // is how the consolidate-memory crash is provoked: it is the only node
  // invocation in the whole factory.
  async function shimPath(root: string, name: string, fakeNode?: string) {
    const shim = join(root, name);
    await mkdir(shim, { recursive: true });
    for (const entry of await readdir("/usr/bin")) {
      if (["node", "nodejs", "npm", "npx"].includes(entry)) continue;
      await symlink(join("/usr/bin", entry), join(shim, entry));
    }
    for (const tool of ["bd", "jq", "git"]) {
      const { stdout } = await execFileAsync("sh", [
        "-c",
        `command -v ${tool}`,
      ]);
      const resolved = stdout.trim();
      await rm(join(shim, tool), { force: true });
      await symlink(resolved, join(shim, tool));
    }
    if (fakeNode !== undefined) {
      await writeFile(join(shim, "node"), fakeNode, { mode: 0o755 });
    }
    return shim;
  }

  const emptyRegistry = '{"civilization":"Justin","forts":[]}';

  async function stagedRegistry(root: string) {
    const registryDirectory = join(root, "registry");
    await mkdir(registryDirectory, { recursive: true });
    const registry = join(registryDirectory, "civilization.json");
    await writeFile(registry, emptyRegistry);
    return registry;
  }

  async function absent(path: string) {
    await expect(access(path)).rejects.toMatchObject({ code: "ENOENT" });
  }

  test.skipIf(!foundingSmokeToolsAvailable)(
    "refuses a node-less host before it has touched anything (fortkit-9ahr)",
    async () => {
      const root = await createFort();
      const registry = await stagedRegistry(root);
      const shim = await shimPath(root, "shim-bin");

      await expect(
        execFileAsync(
          "bash",
          [join(repoRoot, "bin/fort-init"), root, "nodeless", "No node here."],
          { env: { ...process.env, PATH: shim, FORT_REGISTRY: registry } },
        ),
      ).rejects.toMatchObject({
        code: 1,
        stderr: expect.stringContaining("node not found"),
      });

      // The world, unchanged. Before the repair this founding left all four.
      await absent(join(root, "fort"));
      await absent(join(root, ".beads"));
      await absent(join(root, "scripts"));
      await absent(join(root, ".claude", "settings.json"));
      expect(await readFile(registry, "utf8")).toBe(emptyRegistry);

      // VACUITY CONTROL, and it is the load-bearing half: the same shim PATH
      // with node restored must found a fort. Without it the assertions above
      // are equally satisfied by a shim that simply broke the script.
      const second = await createFort();
      const secondRegistry = await stagedRegistry(second);
      const { stdout } = await execFileAsync("sh", ["-c", "command -v node"]);
      await symlink(stdout.trim(), join(shim, "node"));
      await execFileAsync(
        "bash",
        [join(repoRoot, "bin/fort-init"), second, "nodeful", "Node restored."],
        {
          env: {
            ...process.env,
            PATH: shim,
            FORT_REGISTRY: secondRegistry,
          },
        },
      );
      expect(
        JSON.parse(await readFile(secondRegistry, "utf8")).forts,
      ).toHaveLength(1);
    },
  );

  test.skipIf(!foundingSmokeToolsAvailable)(
    "refuses an unwritable civilization registry before building the tree, and names FORT_REGISTRY (fortkit-fg7s)",
    async () => {
      const root = await createFort();
      const registry = await stagedRegistry(root);
      // A read-only registry FILE inside a writable directory: that is the
      // discriminator the preflight uses, so this control exercises the branch
      // without needing a sandbox.
      //
      // SAY WHAT IT IS NOT. chmod does not reproduce the FAILURE, only the
      // precondition — rename over a read-only file in a writable directory is
      // permitted, so the pre-repair factory SUCCEEDS here rather than dying at
      // the mv. What this test discriminates is therefore the ORDERING (refuse
      // before the tree exists), which is the property under repair. The real
      // posture is a read-only single-file bind mount of
      // ~/.claude/civilization.json in every seat mask
      // (fort/scripts/lib/seat-sandbox.sh), where the rename fails EBUSY
      // because it cannot replace a mount point; that was measured under bwrap
      // during the fortkit-2twy sitting, and `test -w` reads NO on the bound
      // file while its parent directory reads YES.
      await chmod(registry, 0o444);
      try {
        await expect(
          execFileAsync(
            "bash",
            [join(repoRoot, "bin/fort-init"), root, "noreg", "No registry."],
            { env: { ...process.env, FORT_REGISTRY: registry } },
          ),
        ).rejects.toMatchObject({
          code: 1,
          // BOTH sentences, because every registry refusal names FORT_REGISTRY
          // by design — the not-a-regular-file branch and the missing-directory
          // branch satisfy that string just as well as this one does, so on its
          // own it is a control that passes for the wrong reason (Ilva
          // Trueglass, finding 4 on the fortkit-2twy review).
          stderr: expect.stringContaining("is not writable"),
        });
        await expect(
          execFileAsync(
            "bash",
            [join(repoRoot, "bin/fort-init"), root, "noreg", "No registry."],
            { env: { ...process.env, FORT_REGISTRY: registry } },
          ),
        ).rejects.toMatchObject({
          stderr: expect.stringContaining("FORT_REGISTRY"),
        });

        await absent(join(root, "fort"));
        await absent(join(root, ".beads"));
        await absent(join(root, "scripts"));
        // The abort used to land BETWEEN the registry write and the founding
        // emissions, so the wreckage was a complete tree with an empty
        // fort/events/ and a stray .new file beside the registry.
        await absent(`${registry}.new`);
        expect(await readFile(registry, "utf8")).toBe(emptyRegistry);
      } finally {
        await chmod(registry, 0o644);
      }
    },
  );

  test.skipIf(!foundingSmokeToolsAvailable || !bwrapAvailable)(
    `names the failing step when the registry rename is refused after the tree is built (${bwrapSkipReason})`,
    async () => {
      const root = await createFort();
      const registry = await stagedRegistry(root);

      // THE ONE FAILURE A PRECHECK CANNOT REACH, and therefore the one that most
      // needs a control. A precheck cannot establish that a rename will succeed
      // without performing one, so a WRITABLE registry file over which rename
      // still fails slips past the preflight entirely. That posture is real: a
      // read-WRITE single-file bind mount gives `test -w` YES and `mv` EBUSY,
      // because the rename cannot replace a mount point. Measured under bwrap
      // during the fortkit-2twy sitting and pinned here, because otherwise the
      // two `if !` blocks at the registry append are executed by nothing.
      let failure: { code?: number; stderr?: string } | undefined;
      try {
        await execFileAsync("bwrap", [
          "--bind",
          "/",
          "/",
          "--dev",
          "/dev",
          "--bind",
          registry,
          registry,
          "--",
          "env",
          `FORT_REGISTRY=${registry}`,
          "bash",
          join(repoRoot, "bin/fort-init"),
          root,
          "pinned",
          "Pinned registry.",
        ]);
      } catch (error) {
        failure = error as { code?: number; stderr?: string };
      }

      expect(failure).toBeDefined();
      expect(failure?.code).not.toBe(0);
      // The catch must say WHICH step failed and how to finish by hand: `set -e`
      // on a 350-line founding script otherwise reports nothing about how far it
      // got, which is fortkit-fg7s's second request.
      expect(failure?.stderr).toContain("NOT registered");
      expect(failure?.stderr).toContain("FORT_REGISTRY");

      // The fort announced itself before the registry was attempted, which is the
      // recoverable half of the ordering. And the catch cleans up after itself.
      const stream = await readdir(join(root, "fort", "events"));
      expect(stream.filter((name) => name.endsWith(".jsonl"))).not.toHaveLength(
        0,
      );
      await absent(`${registry}.new`);
      expect(await readFile(registry, "utf8")).toBe(emptyRegistry);
    },
  );

  test.skipIf(!foundingSmokeToolsAvailable)(
    "refuses to report a founding whose distilled view failed to generate (fortkit-byhp)",
    async () => {
      const root = await createFort();
      const registry = await stagedRegistry(root);
      const shim = await shimPath(
        root,
        "shim-crash",
        "#!/bin/bash\necho 'this node always fails' >&2\nexit 3\n",
      );

      let failure: { code?: number; stderr?: string } | undefined;
      try {
        await execFileAsync(
          "bash",
          [join(repoRoot, "bin/fort-init"), root, "noview", "No view."],
          { env: { ...process.env, PATH: shim, FORT_REGISTRY: registry } },
        );
      } catch (error) {
        failure = error as { code?: number; stderr?: string };
      }

      // toBeDefined first: without it the two assertions below pass vacuously
      // on a founding that reported success.
      expect(failure).toBeDefined();
      expect(failure?.code).not.toBe(0);
      expect(failure?.stderr).toContain("current.md");

      // THE DELIBERATE ORDERING, pinned so a later reader does not "repair" it
      // back. This step is last, after the emissions and the registry append,
      // because it is the one failure that cannot be decided without mutating.
      // Placed earlier it would leave the fortkit-fg7s wreckage — a complete
      // tree with an EMPTY fort/events/. Placed here it leaves a fort that
      // announced itself, is registered, is missing only its distilled view,
      // refuses to claim success, and is repaired by re-running one command.
      const events = await readdir(join(root, "fort", "events"));
      expect(events.filter((name) => name.endsWith(".jsonl"))).not.toHaveLength(
        0,
      );
      expect(JSON.parse(await readFile(registry, "utf8")).forts).toHaveLength(
        1,
      );
    },
  );
});
