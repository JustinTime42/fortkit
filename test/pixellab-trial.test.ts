import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { describe, expect, test } from "vitest";

const execFileAsync = promisify(execFile);
const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const script = "scripts/run-pixellab-trial.mjs";

describe("PixelLab bounded trial", () => {
  test("refuses command-line key attempts without logging their value", async () => {
    await expect(
      execFileAsync("node", [script, "PIXELLAB_API_KEY=not-a-key"], {
        cwd: repoRoot,
        env: {},
      }),
    ).rejects.toMatchObject({
      code: 1,
      stdout: "",
      stderr: "",
    });
  });

  test("refuses missing environment keys", async () => {
    await expect(
      execFileAsync("node", [script], { cwd: repoRoot, env: {} }),
    ).rejects.toMatchObject({
      code: 1,
    });
  });
});
