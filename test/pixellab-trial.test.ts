import { spawn } from "node:child_process";
import { mkdtemp, open, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const script = "scripts/run-pixellab-trial.mjs";
const childEnvironment = { PATH: process.env.PATH ?? "" };

async function runRefusal(arguments_: string[]) {
  const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
  const stdoutPath = join(directory, "stdout");
  const stderrPath = join(directory, "stderr");
  const [stdout, stderr] = await Promise.all([
    open(stdoutPath, "w"),
    open(stderrPath, "w"),
  ]);
  try {
    const code = await new Promise<number | null>((resolve, reject) => {
      const child = spawn("node", [script, ...arguments_], {
        cwd: repoRoot,
        env: childEnvironment,
        stdio: ["ignore", stdout.fd, stderr.fd],
      });
      child.once("error", reject);
      child.once("close", resolve);
    });
    await Promise.all([stdout.close(), stderr.close()]);
    return {
      code,
      stdout: await readFile(stdoutPath, "utf8"),
      stderr: await readFile(stderrPath, "utf8"),
    };
  } finally {
    await Promise.allSettled([stdout.close(), stderr.close()]);
    await rm(directory, { recursive: true, force: true });
  }
}

describe("PixelLab bounded trial", () => {
  test("refuses command-line key attempts without logging their value", async () => {
    const result = await runRefusal(["PIXELLAB_API_KEY=not-a-key"]);
    expect(result.code).toBe(1);
    expect(result.stdout).not.toContain("not-a-key");
    expect(result.stderr).toContain("This script accepts no arguments.");
    expect(result.stderr).not.toContain("not-a-key");
  });

  test("refuses missing environment keys", async () => {
    const result = await runRefusal([]);
    expect(result.code).toBe(1);
    expect(result.stdout).toBe("");
    expect(result.stderr).toContain("PIXELLAB_API_KEY must be set");
  });
});
