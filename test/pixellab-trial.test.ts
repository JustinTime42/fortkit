import { spawn } from "node:child_process";
import { mkdtemp, open, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync, inflateSync } from "node:zlib";

import { describe, expect, test, vi } from "vitest";

import {
  ANIMATION_ENDPOINT,
  ANIMATION_IMAGE_SIZE,
  addUsage,
  animationRequestBody,
  MANIFEST_SCHEMA_VERSION,
  MAX_GENERATIONS_PER_ANIMATION_CALL,
  MAX_GENERATIONS_PER_STILL_ASSET,
  MAX_TOTAL_GENERATIONS,
  main,
  PIXFLUX_ENDPOINT,
  padAnimationReference,
  parseUsageMeter,
  perFrameProvenance,
  pixfluxRequestBody,
  pngDimensions,
  pngFromBase64,
  request,
  requestTimeoutMilliseconds,
  seedOffsetFromEnvironment,
  walkCards,
  withSeedOffset,
  writeAsset,
} from "../scripts/run-pixellab-trial.mjs";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const script = "scripts/run-pixellab-trial.mjs";
const childEnvironment = { PATH: process.env.PATH ?? "" };
const pngSignature = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
]);

function crc32(bytes: Buffer) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1)
      crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type: string, data: Buffer) {
  const result = Buffer.alloc(12 + data.length);
  result.writeUInt32BE(data.length, 0);
  result.write(type, 4, 4, "ascii");
  data.copy(result, 8);
  result.writeUInt32BE(
    crc32(result.subarray(4, 8 + data.length)),
    8 + data.length,
  );
  return result;
}

function encodeRgbaPng(
  width: number,
  height: number,
  pixels: Buffer,
  {
    bitDepth = 8,
    colorType = 6,
    extraScanlineBytes = 0,
    filterType = 0,
    interlace = 0,
  } = {},
) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = bitDepth;
  header[9] = colorType;
  header[12] = interlace;
  const scanlines = Buffer.alloc((width * 4 + 1) * height + extraScanlineBytes);
  for (let row = 0; row < height; row += 1) {
    const scanlineOffset = row * (width * 4 + 1);
    scanlines[scanlineOffset] = filterType;
    for (let column = 0; column < width * 4; column += 1) {
      const value = pixels[row * width * 4 + column] ?? 0;
      const left =
        column >= 4 ? (pixels[row * width * 4 + column - 4] ?? 0) : 0;
      const above = row > 0 ? (pixels[(row - 1) * width * 4 + column] ?? 0) : 0;
      const upperLeft =
        row > 0 && column >= 4
          ? (pixels[(row - 1) * width * 4 + column - 4] ?? 0)
          : 0;
      const predictor =
        filterType === 1
          ? left
          : filterType === 2
            ? above
            : filterType === 3
              ? Math.floor((left + above) / 2)
              : filterType === 4
                ? paeth(left, above, upperLeft)
                : 0;
      scanlines[scanlineOffset + 1 + column] = (value - predictor) & 0xff;
    }
  }
  return Buffer.concat([
    pngSignature,
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(scanlines)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function paeth(left: number, above: number, upperLeft: number) {
  const estimate = left + above - upperLeft;
  const leftDistance = Math.abs(estimate - left);
  const aboveDistance = Math.abs(estimate - above);
  const upperLeftDistance = Math.abs(estimate - upperLeft);
  return leftDistance <= aboveDistance && leftDistance <= upperLeftDistance
    ? left
    : aboveDistance <= upperLeftDistance
      ? above
      : upperLeft;
}

function decodeFilterZeroRgbaPng(png: Buffer) {
  const width = png.readUInt32BE(16);
  const height = png.readUInt32BE(20);
  let offset = 8;
  const idat: Buffer[] = [];
  while (offset < png.length) {
    const length = png.readUInt32BE(offset);
    const type = png.toString("ascii", offset + 4, offset + 8);
    if (type === "IDAT")
      idat.push(png.subarray(offset + 8, offset + 8 + length));
    offset += length + 12;
  }
  const scanlines = inflateSync(Buffer.concat(idat));
  const pixels = Buffer.alloc(width * height * 4);
  for (let row = 0; row < height; row += 1) {
    const offset = row * (width * 4 + 1);
    expect(scanlines[offset]).toBe(0);
    scanlines.copy(pixels, row * width * 4, offset + 1, offset + 1 + width * 4);
  }
  return { width, height, pixels };
}

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

  test("uses schema version 5 for reference-padding provenance", () => {
    expect(MANIFEST_SCHEMA_VERSION).toBe(5);
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
    const body = animationRequestBody(
      encodeRgbaPng(32, 64, Buffer.alloc(32 * 64 * 4)),
      {
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
      },
    );
    expect(body).toMatchObject({
      description: "Kethra walks east",
      negative_description: "no words",
      n_frames: 4,
      image_size: { width: 64, height: 64 },
      reference_image_size: { width: 64, height: 64 },
    });
    const referenceImage = body.reference_image as { base64: string };
    expect(
      pngDimensions(
        Buffer.from(
          referenceImage.base64.replace("data:image/png;base64,", ""),
          "base64",
        ),
      ),
    ).toEqual({ width: 64, height: 64 });
    expect(ANIMATION_IMAGE_SIZE).toEqual({ width: 64, height: 64 });
  });

  test("pads every PNG filter type without resampling its pixels", () => {
    const source = Buffer.alloc(32 * 64 * 4);
    for (let index = 0; index < source.length; index += 1)
      source[index] = (index * 37 + Math.floor(index / 17) * 19) & 0xff;
    const paddedPixels = [];
    for (let filterType = 0; filterType <= 4; filterType += 1) {
      const padded = decodeFilterZeroRgbaPng(
        padAnimationReference(encodeRgbaPng(32, 64, source, { filterType })),
      );
      expect(padded.width).toBe(64);
      expect(padded.height).toBe(64);
      paddedPixels.push(padded.pixels);
      for (let row = 0; row < 64; row += 1) {
        const sourceRow = source.subarray(row * 32 * 4, (row + 1) * 32 * 4);
        expect(
          padded.pixels.subarray((row * 64 + 16) * 4, (row * 64 + 48) * 4),
        ).toEqual(sourceRow);
        expect(
          padded.pixels.subarray(row * 64 * 4, (row * 64 + 16) * 4),
        ).toEqual(Buffer.alloc(16 * 4));
        expect(
          padded.pixels.subarray((row * 64 + 48) * 4, (row + 1) * 64 * 4),
        ).toEqual(Buffer.alloc(16 * 4));
      }
    }
    for (const pixels of paddedPixels.slice(1))
      expect(pixels).toEqual(paddedPixels[0]);
  });

  test("fails closed when a reference PNG is not 8-bit RGBA", () => {
    expect(() =>
      padAnimationReference(
        encodeRgbaPng(32, 64, Buffer.alloc(32 * 64 * 4), { colorType: 2 }),
      ),
    ).toThrow("expected a 32x64 8-bit RGBA non-interlaced PNG");
  });

  test("bounds decompression to the exact PNG scanline length", () => {
    expect(() =>
      padAnimationReference(
        encodeRgbaPng(32, 64, Buffer.alloc(32 * 64 * 4), {
          extraScanlineBytes: 1024 * 1024,
        }),
      ),
    ).toThrow("invalid PNG image data");
  });

  test("accepts USD and generation usage meters under their per-request caps", () => {
    expect(parseUsageMeter({ usd: 0.0084 }, 0.02, 2)).toEqual({
      meter: "usd",
      amount: 0.0084,
    });
    expect(parseUsageMeter({ usd: "0.0084" }, 0.02, 2)).toEqual({
      meter: "usd",
      amount: 0.0084,
    });
    expect(
      parseUsageMeter({ type: "generations", generations: 2 }, 0.02, 2),
    ).toEqual({ meter: "generations", amount: 2 });
  });

  test("distinguishes unexpected pricing shapes from amounts over caps", () => {
    const usage = { type: "usd" };
    expect(() => parseUsageMeter(usage, 0.02, 2)).toThrow(
      `PixelLab returned an unexpected pricing shape: ${JSON.stringify(usage)}`,
    );
    const overStillCap = { type: "generations", generations: 3 };
    expect(() => parseUsageMeter(overStillCap, 0.02, 2)).toThrow(
      `generations amount over the per-request cap (3 > 2): ${JSON.stringify(overStillCap)}`,
    );
    const overAnimationCap = { type: "generations", generations: 9 };
    expect(() => parseUsageMeter(overAnimationCap, 0.08, 8)).toThrow(
      `generations amount over the per-request cap (9 > 8): ${JSON.stringify(overAnimationCap)}`,
    );
    expect(MAX_GENERATIONS_PER_STILL_ASSET).toBe(2);
    expect(MAX_GENERATIONS_PER_ANIMATION_CALL).toBe(8);
    expect(MAX_TOTAL_GENERATIONS).toBe(30);
  });

  test("uses the usage discriminator before an accompanying USD field", () => {
    expect(
      parseUsageMeter(
        { type: "generations", generations: 2, usd: "999" },
        0.02,
        2,
      ),
    ).toEqual({ meter: "generations", amount: 2 });
    expect(() =>
      parseUsageMeter({ type: "unknown", usd: "0.0084" }, 0.02, 2),
    ).toThrow("unexpected pricing shape");
  });

  test("rejects invalid generation quantities before recording them", () => {
    for (const generations of [0, -1, 1.5]) {
      expect(() =>
        parseUsageMeter({ type: "generations", generations }, 0.02, 2),
      ).toThrow("unexpected pricing shape");
    }
  });

  test("caps the total generation-credit meter separately from USD", () => {
    expect(
      addUsage(
        { usd: 14.99, generations: 29 },
        { meter: "generations", amount: 1 },
      ),
    ).toEqual({ usd: 14.99, generations: 30 });
    expect(() =>
      addUsage(
        { usd: 0, generations: 29 },
        { meter: "generations", amount: 2 },
      ),
    ).toThrow("actual trial generation credits exceed the 30 cap");
    expect(() =>
      addUsage({ usd: 14.99, generations: 0 }, { meter: "usd", amount: 0.02 }),
    ).toThrow("actual trial spend exceeds the $15 cap");
  });

  test("only calls a per-frame generation share amortized", () => {
    expect(perFrameProvenance({ meter: "usd", amount: 0.02 }, 4)).toEqual({
      cost: { meter: "usd", amount: 0.005 },
      requestCost: { meter: "usd", amount: 0.02 },
    });
    expect(perFrameProvenance({ meter: "generations", amount: 1 }, 4)).toEqual({
      amortizedCost: { meter: "generations", amount: 0.25 },
      requestCost: { meter: "generations", amount: 1 },
    });
  });

  test("reads actual dimensions from generated PNG data", () => {
    const png = Buffer.alloc(24);
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(png);
    png.write("IHDR", 12, "ascii");
    png.writeUInt32BE(64, 16);
    png.writeUInt32BE(64, 20);
    expect(pngDimensions(png)).toEqual({ width: 64, height: 64 });
  });

  test("records API-requested and decoded image sizes separately", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const png = Buffer.alloc(24);
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(png);
    png.write("IHDR", 12, "ascii");
    png.writeUInt32BE(64, 16);
    png.writeUInt32BE(64, 20);
    const manifest: { assets: Array<Record<string, unknown>> } = { assets: [] };
    try {
      await writeAsset(
        manifest,
        {
          id: "walk",
          kind: "walk-frame",
          filename: "walk.png",
          imageSize: { width: 32, height: 64 },
          params: {},
        },
        { png },
        {
          requestedImageSize: { width: 64, height: 64 },
          amortizedCost: { meter: "generations", amount: 0.25 },
          requestCost: { meter: "generations", amount: 4 },
          referencePadding: {
            from: { width: 32, height: 64 },
            to: { width: 64, height: 64 },
            placement: "bottom-center",
          },
        },
        directory,
      );
      expect(manifest.assets[0]).toMatchObject({
        requestedImageSize: { width: 64, height: 64 },
        actualImageSize: { width: 64, height: 64 },
        amortizedCost: { meter: "generations", amount: 0.25 },
        requestCost: { meter: "generations", amount: 4 },
        referencePadding: {
          from: { width: 32, height: 64 },
          to: { width: 64, height: 64 },
          placement: "bottom-center",
        },
      });
      expect(manifest.assets[0]?.reference).toBeNull();
      expect(manifest.assets[0]?.referencePadding).toEqual({
        from: { width: 32, height: 64 },
        to: { width: 64, height: 64 },
        placement: "bottom-center",
      });
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("records null reference fields for still assets", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const png = encodeRgbaPng(1, 1, Buffer.alloc(4));
    const manifest: { assets: Array<Record<string, unknown>> } = { assets: [] };
    try {
      await writeAsset(
        manifest,
        {
          id: "still",
          kind: "item-glyph",
          filename: "still.png",
          imageSize: { width: 1, height: 1 },
          params: {},
        },
        { png },
        { requestedImageSize: { width: 1, height: 1 } },
        directory,
      );
      expect(manifest.assets[0]?.reference).toBeNull();
      expect(manifest.assets[0]?.referencePadding).toBeNull();
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
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

  test("uses endpoint-specific defaults and floors one environment override", () => {
    expect(requestTimeoutMilliseconds(PIXFLUX_ENDPOINT, undefined)).toBe(
      120_000,
    );
    expect(requestTimeoutMilliseconds(ANIMATION_ENDPOINT, undefined)).toBe(
      120_000,
    );
    expect(requestTimeoutMilliseconds(PIXFLUX_ENDPOINT, "12345")).toBe(120_000);
    expect(requestTimeoutMilliseconds(ANIMATION_ENDPOINT, "12345")).toBe(
      120_000,
    );
    expect(requestTimeoutMilliseconds(PIXFLUX_ENDPOINT, "180000")).toBe(
      180_000,
    );
  });

  test("names the timed-out endpoint", async () => {
    const originalFetch = globalThis.fetch;
    const originalTimeout = process.env.PIXELLAB_TIMEOUT_MS;
    process.env.PIXELLAB_TIMEOUT_MS = "1";
    const abortController = new AbortController();
    const timeoutSpy = vi
      .spyOn(AbortSignal, "timeout")
      .mockReturnValue(abortController.signal);
    globalThis.fetch = (_input, options) =>
      new Promise((_, reject) => {
        const signal = options?.signal;
        if (!signal) return reject(new Error("Expected an abort signal."));
        signal.addEventListener("abort", () => reject(signal.reason));
      });
    try {
      const pendingRequest = request(PIXFLUX_ENDPOINT, {}, "not-a-key");
      abortController.abort();
      await expect(pendingRequest).rejects.toThrow(
        `PixelLab request to ${PIXFLUX_ENDPOINT} timed out after 120000ms.`,
      );
    } finally {
      timeoutSpy.mockRestore();
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
      await expect(
        request(ANIMATION_ENDPOINT, {}, "secret-key"),
      ).rejects.not.toThrow("other-secret");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("projects 422 detail arrays without echoed request input", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            detail: [
              {
                type: "value_error",
                loc: ["body", "reference_image"],
                msg: "invalid image",
                input: "data:image/png;base64,should-not-appear",
              },
            ],
          }),
          { status: 422, headers: { "Content-Type": "application/json" } },
        ),
      );
    try {
      await expect(
        request(ANIMATION_ENDPOINT, {}, "secret-key"),
      ).rejects.toThrow(
        '{"type":"value_error","loc":["body","reference_image"],"msg":"invalid image"}',
      );
      await expect(
        request(ANIMATION_ENDPOINT, {}, "secret-key"),
      ).rejects.not.toThrow("should-not-appear");
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

  test("distinguishes PNG dimension failures from base64 decoding failures", () => {
    expect(() => pngDimensions(Buffer.alloc(24))).toThrow(
      "PixelLab returned a PNG without valid dimensions.",
    );
  });

  test("validates PNG dimensions before writing trial output", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const manifest: { assets: Array<Record<string, unknown>> } = { assets: [] };
    try {
      await expect(
        writeAsset(
          manifest,
          {
            id: "invalid",
            kind: "test",
            filename: "invalid.png",
            imageSize: { width: 0, height: 0 },
            params: {},
          },
          { png: Buffer.alloc(24) },
          { requestedImageSize: { width: 0, height: 0 } },
          directory,
        ),
      ).rejects.toThrow("PixelLab returned a PNG without valid dimensions.");
      await expect(readFile(join(directory, "invalid.png"))).rejects.toThrow();
      expect(manifest.assets).toEqual([]);
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
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
