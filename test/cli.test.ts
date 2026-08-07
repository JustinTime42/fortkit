import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);
const cliPath = fileURLToPath(new URL("../src/cli.ts", import.meta.url));

describe("world CLI", () => {
  test("rejects unknown arguments when --port is absent", async () => {
    await expect(
      execFileAsync("node", ["src/cli.ts", "world", "nonsense"]),
    ).rejects.toMatchObject({ code: 2 });
  });

  test("requires a valid non-empty digest window", async () => {
    await expect(
      execFileAsync("node", ["src/cli.ts", "digest", "--since", "invalid"]),
    ).rejects.toMatchObject({ code: 2 });
    await expect(
      execFileAsync("node", [
        "src/cli.ts",
        "digest",
        "--since",
        "2026-08-04T09:00:00Z",
        "--until",
        "2026-08-04T09:00:00Z",
      ]),
    ).rejects.toMatchObject({ code: 2 });
  });

  test("ambient follows the neighbouring CLI branches' exit-code contract", async () => {
    await expect(
      execFileAsync("node", [
        "src/cli.ts",
        "ambient",
        "kethra",
        "--since",
        "invalid",
      ]),
    ).rejects.toMatchObject({ code: 2 });

    const root = await mkdtemp(join(tmpdir(), "fortkit-ambient-cli-"));
    const home = join(root, "home");
    const fort = join(root, "fort");
    try {
      await mkdir(join(home, ".claude"), { recursive: true });
      await mkdir(fort);
      await writeFile(
        join(home, ".claude", "civilization.json"),
        JSON.stringify({ forts: [{ fort_name: "Test Fort", repo: fort }] }),
      );
      await expect(
        execFileAsync(
          process.execPath,
          [cliPath, "ambient", "kethra", "--on", "2026-08-07T12:30:00Z"],
          { cwd: fort, env: { ...process.env, HOME: home } },
        ),
      ).resolves.toEqual(expect.anything());

      await expect(
        execFileAsync(
          process.execPath,
          [cliPath, "ambient", "kethra", "--on", "2026-08-07T12:30:00Z"],
          { cwd: root, env: { ...process.env, HOME: home } },
        ),
      ).rejects.toMatchObject({ code: 1 });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
