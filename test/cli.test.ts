import { execFile, spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);
const cliPath = fileURLToPath(new URL("../src/cli.ts", import.meta.url));

function cliChild(args: string[]): string {
  return `
    console.log = (...values) => process.send?.({ stdout: values.join(" ") });
    console.error = (...values) => process.send?.({ stderr: values.join(" ") });
    process.argv = [process.execPath, ${JSON.stringify(cliPath)}, ...${JSON.stringify(args)}];
    await import(${JSON.stringify(cliPath)});
  `;
}

function childMessage(
  child: ReturnType<typeof spawn>,
  property: string,
  expected: string,
) {
  return new Promise<unknown>((resolve) => {
    child.on("message", (message) => {
      const value =
        typeof message === "object" && message !== null
          ? (message as Record<string, unknown>)[property]
          : undefined;
      if (typeof value === "string" && value.includes(expected)) {
        resolve(message);
      }
    });
  });
}

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
      const child = spawn(
        process.execPath,
        [
          "--input-type=module",
          "--eval",
          cliChild([
            "ambient",
            "Kethra Anvilmark",
            "--on",
            "2026-08-07T12:30:00Z",
          ]),
        ],
        {
          cwd: fort,
          env: { ...process.env, HOME: home },
          stdio: ["ignore", "pipe", "pipe", "ipc"],
        },
      );
      const [message, [code]] = await Promise.all([
        childMessage(child, "stdout", "Ambient schedule for kethra"),
        once(child, "close"),
      ]);
      expect(code).toBe(0);
      expect(message).toMatchObject({
        stdout: expect.stringContaining(
          "Ambient schedule for kethra — 2026-08-07 UTC",
        ),
      });
      expect((message as { stdout: string }).stdout).toContain(
        "lunching at tavern",
      );

      const unregistered = spawn(
        process.execPath,
        [
          "--input-type=module",
          "--eval",
          cliChild(["ambient", "kethra", "--on", "2026-08-07T12:30:00Z"]),
        ],
        {
          cwd: root,
          env: { ...process.env, HOME: home },
          stdio: ["ignore", "pipe", "pipe", "ipc"],
        },
      );
      const [error, [errorCode]] = await Promise.all([
        childMessage(unregistered, "stderr", "is not a registered fort"),
        once(unregistered, "close"),
      ]);
      expect(errorCode).toBe(1);
      expect(error).toMatchObject({
        stderr: expect.stringContaining("is not a registered fort"),
      });
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
