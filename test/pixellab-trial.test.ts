import { spawn } from "node:child_process";
import { mkdtemp, open, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import {
  animationRequestBody,
  pngFromBase64,
  seedOffsetFromEnvironment,
  withSeedOffset,
} from "../scripts/run-pixellab-trial.mjs";

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
  test("allows an integer seed offset to reroll every card", () => {
    expect(seedOffsetFromEnvironment("17")).toBe(17);
    expect(withSeedOffset({ seed: 41001 }, 17).seed).toBe(41018);
    expect(() => seedOffsetFromEnvironment("1.5")).toThrow(
      "PIXELLAB_SEED_OFFSET must be an integer.",
    );
  });

  test("sends the recorded animation fields to PixelLab", () => {
    const body = animationRequestBody(Buffer.from("master"), {
      prompt: "Kethra walks east",
      negativeConstraints: "no words",
      seed: 43001,
      imageSize: { width: 32, height: 64 },
      params: {
        no_background: true,
        view: "side",
        direction: "east",
        action: "walk",
        n_frames: 4,
      },
    });
    expect(body).toMatchObject({
      description: "Kethra walks east",
      negative_description: "no words",
      n_frames: 4,
    });
  });

  test("rejects non-PNG response bytes", () => {
    expect(() =>
      pngFromBase64(Buffer.from("not png").toString("base64")),
    ).toThrow("PixelLab returned an invalid PNG image.");
  });

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
