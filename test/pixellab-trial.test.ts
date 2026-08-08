import { spawn } from "node:child_process";
import { mkdtemp, open, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, test } from "vitest";

import {
  ANIMATION_ENDPOINT,
  ANIMATION_IMAGE_SIZE,
  animationRequestBody,
  main,
  PIXFLUX_ENDPOINT,
  parseUsage,
  pixfluxRequestBody,
  pngDimensions,
  pngFromBase64,
  request,
  requestTimeoutMilliseconds,
  seedOffsetFromEnvironment,
  walkCards,
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
  test("pins the verified PixelLab endpoints", () => {
    expect(PIXFLUX_ENDPOINT).toBe(
      "https://api.pixellab.ai/v1/generate-image-pixflux",
    );
    expect(ANIMATION_ENDPOINT).toBe(
      "https://api.pixellab.ai/v1/animate-with-text",
    );
  });

  test("sends the verified Pixflux body to PixelLab", () => {
    expect(
      pixfluxRequestBody({
        prompt: "a forge",
        negativeConstraints: "no words",
        imageSize: { width: 128, height: 128 },
        seed: 41001,
        params: { no_background: true, outline: "selective outline" },
      }),
    ).toEqual({
      description: "a forge",
      negative_description: "no words",
      image_size: { width: 128, height: 128 },
      seed: 41001,
      no_background: true,
      outline: "selective outline",
    });
  });

  test("allows an integer seed offset to reroll every card", () => {
    expect(seedOffsetFromEnvironment("17")).toBe(17);
    expect(withSeedOffset({ seed: 41001 }, 17).seed).toBe(41018);
    expect(() => seedOffsetFromEnvironment("1.5")).toThrow(
      "PIXELLAB_SEED_OFFSET must be an integer.",
    );
  });

  test("sends the verified 64x64 animation body to PixelLab", () => {
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
      image_size: { width: 64, height: 64 },
      reference_image_size: { width: 32, height: 64 },
    });
    expect(ANIMATION_IMAGE_SIZE).toEqual({ width: 64, height: 64 });
  });

  test("accepts the verified usage.usd shape", () => {
    expect(parseUsage({ usd: 0.0084 }, 0.02)).toBe(0.0084);
    expect(() => parseUsage({ type: "usd" }, 0.02)).toThrow(
      "PixelLab returned unexpected pricing.",
    );
  });

  test("reads actual dimensions from generated PNG data", () => {
    const png = Buffer.alloc(24);
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(png);
    png.write("IHDR", 12, "ascii");
    png.writeUInt32BE(64, 16);
    png.writeUInt32BE(64, 20);
    expect(pngDimensions(png)).toEqual({ width: 64, height: 64 });
  });

  test("records one truthful animation prompt and a separate frame index", () => {
    const firstPrompt = walkCards[0]?.prompt ?? "";
    expect(walkCards.map((card) => card.prompt)).toEqual([
      firstPrompt,
      firstPrompt,
      firstPrompt,
      firstPrompt,
    ]);
    expect(firstPrompt).not.toMatch(/frame \d of 4/);
    expect(walkCards.map((card) => card.frameIndex)).toEqual([1, 2, 3, 4]);
  });

  test("uses endpoint-specific defaults and permits one environment override", () => {
    expect(requestTimeoutMilliseconds(PIXFLUX_ENDPOINT, undefined)).toBe(
      30_000,
    );
    expect(requestTimeoutMilliseconds(ANIMATION_ENDPOINT, undefined)).toBe(
      120_000,
    );
    expect(requestTimeoutMilliseconds(PIXFLUX_ENDPOINT, "12345")).toBe(12345);
  });

  test("names the timed-out endpoint", async () => {
    const originalFetch = globalThis.fetch;
    const originalTimeout = process.env.PIXELLAB_TIMEOUT_MS;
    process.env.PIXELLAB_TIMEOUT_MS = "1";
    globalThis.fetch = (_input, options) =>
      new Promise((_, reject) => {
        const signal = options?.signal;
        if (!signal) return reject(new Error("Expected an abort signal."));
        signal.addEventListener("abort", () => reject(signal.reason));
      });
    try {
      await expect(request(PIXFLUX_ENDPOINT, {}, "not-a-key")).rejects.toThrow(
        `PixelLab request to ${PIXFLUX_ENDPOINT} timed out after 1ms.`,
      );
    } finally {
      globalThis.fetch = originalFetch;
      if (originalTimeout === undefined) delete process.env.PIXELLAB_TIMEOUT_MS;
      else process.env.PIXELLAB_TIMEOUT_MS = originalTimeout;
    }
  });

  test("prints sanitized 4xx response detail", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            detail:
              "image_size must be 64x64; token=secret-key; Bearer other-secret",
          }),
          { status: 422, headers: { "Content-Type": "application/json" } },
        ),
      );
    try {
      await expect(
        request(ANIMATION_ENDPOINT, {}, "secret-key"),
      ).rejects.toThrow("image_size must be 64x64");
      await expect(
        request(ANIMATION_ENDPOINT, {}, "secret-key"),
      ).rejects.not.toThrow("secret-key");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("fails Kethra-card renames at startup before a request can start", async () => {
    await expect(main([{ id: "renamed-kethra-citizen" }])).rejects.toThrow(
      "Trial configuration requires a kethra-citizen card before generation.",
    );
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
