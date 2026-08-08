import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { afterEach, describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);
const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const emitPath = join(repoRoot, "fort/scripts/emit.sh");
const roots: string[] = [];

async function createFort() {
  const root = await mkdtemp(join(tmpdir(), "fortkit-shell-"));
  roots.push(root);
  await execFileAsync("git", ["init", "--quiet"], { cwd: root });
  return root;
}

async function emit(root: string, args: string[]) {
  return execFileAsync("bash", [emitPath, ...args], { cwd: root });
}

afterEach(async () => {
  await Promise.all(
    roots.splice(0).map((root) => rm(root, { force: true, recursive: true })),
  );
});

describe("fort shell scripts", () => {
  // Harness pattern: run a shipped script from a git-init'd temporary fort. Its
  // git-common-dir lookup then writes only inside that fort, never live events.
  test("emit.sh rejects malformed positional shapes before writing", async () => {
    const root = await createFort();

    await expect(
      emit(root, ["work.begun", "--bead", "fortkit-so2", "-a", "kethra"]),
    ).rejects.toMatchObject({
      code: 2,
      stderr: expect.stringContaining("detail must not begin with '-'"),
    });
    await expect(
      emit(root, ["work.begun", "valid detail", "leftover"]),
    ).rejects.toMatchObject({
      code: 2,
      stderr: expect.stringContaining("unexpected argument: leftover"),
    });
    await expect(
      readFile(join(root, "fort/events/events-2026-08-08.jsonl")),
    ).rejects.toMatchObject({
      code: "ENOENT",
    });
  });

  test("emit.sh rejects option-shaped categories before writing", async () => {
    const root = await createFort();

    await expect(emit(root, ["-work.begun", "detail"])).rejects.toMatchObject({
      code: 2,
      stderr: expect.stringContaining("category must not begin with '-'"),
    });
    await expect(
      readFile(join(root, "fort/events/events-2026-08-08.jsonl")),
    ).rejects.toMatchObject({
      code: "ENOENT",
    });
  });

  test("emit.sh writes a valid event to the temporary fort", async () => {
    const root = await createFort();

    // `--` is deliberately accepted as getopts' conventional option terminator.
    // Since the emitter permits no trailing positionals, anything after it fails.
    await emit(root, [
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
