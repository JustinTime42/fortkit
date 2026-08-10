import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, open, readFile, rm, writeFile } from "node:fs/promises";
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
  animationSeedOffsetFromEnvironment,
  assertKethraCitizenCard,
  CHARACTER_NEGATIVE_CONSTRAINTS,
  cards,
  characterTransparencyCheck,
  citizenAppearance,
  MANIFEST_SCHEMA_VERSION,
  MAX_GENERATIONS_PER_ANIMATION_CALL,
  MAX_GENERATIONS_PER_STILL_ASSET,
  MAX_TOTAL_GENERATIONS,
  main,
  NEGATIVE_CONSTRAINTS,
  PIXFLUX_ENDPOINT,
  padAnimationReference,
  parseAppearanceRegistry,
  parseUsageMeter,
  perFrameProvenance,
  pixfluxRequestBody,
  pngDimensions,
  pngFromBase64,
  registryCommit,
  request,
  requestTimeoutMilliseconds,
  reusableStillAsset,
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
    const scanlineOffset = row * (width * 4 + 1);
    expect(scanlines[scanlineOffset]).toBe(0);
    scanlines.copy(
      pixels,
      row * width * 4,
      scanlineOffset + 1,
      scanlineOffset + 1 + width * 4,
    );
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

  test("uses schema version 8 for appearance-declaration provenance", () => {
    expect(MANIFEST_SCHEMA_VERSION).toBe(8);
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

  test("allows an animation-only seed offset without changing still seeds", () => {
    expect(animationSeedOffsetFromEnvironment("17")).toBe(17);
    expect(() => animationSeedOffsetFromEnvironment("1.5")).toThrow(
      "PIXELLAB_ANIMATION_SEED_OFFSET must be an integer.",
    );
  });

  test("forbids scenery in character prompts but leaves other card constraints alone", () => {
    const kethra = cards.find((card) => card.id === "kethra-citizen");
    expect(kethra?.prompt).toContain("isolated character only");
    expect(kethra?.prompt).toContain("fully transparent background");
    expect(kethra?.prompt).toContain(
      "no scenery, no props, no environment, no floor, no shadow on ground",
    );
    expect(kethra?.negativeConstraints).toBe(CHARACTER_NEGATIVE_CONSTRAINTS);
    expect(walkCards[0]?.prompt).toContain("isolated character only");
    expect(walkCards[0]?.negativeConstraints).toBe(
      CHARACTER_NEGATIVE_CONSTRAINTS,
    );
    expect(CHARACTER_NEGATIVE_CONSTRAINTS).toContain(
      "no background elements, no pillars, no walls, no floor, no scenery",
    );
    expect(
      cards.find((card) => card.id === "forge-building")?.negativeConstraints,
    ).toBe(NEGATIVE_CONSTRAINTS);
  });

  test("derives Kethra's prompt from her registry declaration", () => {
    const kethra = cards.find((card) => card.id === "kethra-citizen");
    expect(kethra?.prompt).toContain("close-cropped black braid threaded");
    expect(kethra?.prompt).toContain("neatly squared beard");
    expect(kethra?.prompt).toContain("skin is umber");
    expect(kethra?.prompt).toContain("round smoked lenses");
    expect(kethra?.prompt).toContain("pale burn scar");
    expect(kethra?.prompt).toContain("leather apron patched");
    expect(kethra?.declarationSource).toMatchObject({
      registry: "fort/roster-appearance.md",
      section: "Kethra Anvilmark — Forge of Manyhalls (she/her)",
      declarationSha256: createHash("sha256")
        .update(
          "I am a broad-shouldered dwarven woman with a close-cropped black braid threaded with copper wire and a full, neatly squared beard. My skin is umber, my eyes are dark brown behind round smoked lenses, and a pale burn scar curls from my left wrist toward my palm. I wear a soot-blue work shirt with the sleeves rolled high, a leather apron patched more times than it has been replaced, and stout boots dusted with iron filings. A small brass caliper lives behind one ear; I look most like myself when I am leaning over a half-finished tool, listening for what it needs to become.",
        )
        .digest("hex"),
      commit: expect.stringMatching(/^(?:[0-9a-f]{40}|uncommitted)$/),
    });
    expect(walkCards[0]?.declarationSource).toEqual(kethra?.declarationSource);
    expect(kethra?.prompt).not.toContain("filings.,");
  });

  test("looks up registry commits through an injected runner", () => {
    expect(registryCommit(() => "a".repeat(40))).toBe("a".repeat(40));
    expect(registryCommit(() => "not a commit")).toBe("uncommitted");
    expect(
      registryCommit(() => {
        throw new Error("no git");
      }),
    ).toBe("uncommitted");
  });

  test("uses the registry's generic silhouette for an undeclared citizen", () => {
    const registry = parseAppearanceRegistry(
      "## Declared Citizen — Seat (they/them)\n\n> A declared appearance.\n",
    );
    expect(citizenAppearance("Undeclared Citizen", registry)).toEqual({
      prompt: "deliberately generic silhouette, no declared appearance",
      declarationSource: null,
    });
  });

  test("writes the declaration source into generated asset provenance", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const manifest: { assets: Array<Record<string, unknown>> } = { assets: [] };
    try {
      await writeAsset(
        manifest,
        {
          id: "citizen",
          kind: "citizen-master",
          filename: "citizen.png",
          imageSize: { width: 1, height: 1 },
          params: {},
          declarationSource: {
            registry: "fort/roster-appearance.md",
            section: "Citizen — Seat (they/them)",
            declarationSha256: "b".repeat(64),
            commit: "a".repeat(40),
          },
        },
        { png: encodeRgbaPng(1, 1, Buffer.alloc(4)) },
        { requestedImageSize: { width: 1, height: 1 } },
        directory,
      );
      expect(manifest.assets[0]?.declarationSource).toEqual({
        registry: "fort/roster-appearance.md",
        section: "Citizen — Seat (they/them)",
        declarationSha256: "b".repeat(64),
        commit: "a".repeat(40),
      });
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
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
    expect(referenceImage.base64.startsWith("data:image/png;base64,")).toBe(
      false,
    );
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

  test("retries one animation 5xx and logs both attempts", async () => {
    const originalFetch = globalThis.fetch;
    const write = vi
      .spyOn(process.stdout, "write")
      .mockImplementation(() => true);
    globalThis.fetch = vi
      .fn()
      .mockResolvedValueOnce(new Response(null, { status: 500 }))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ images: [] }), { status: 200 }),
      );
    try {
      await expect(
        request(ANIMATION_ENDPOINT, {}, "not-a-key"),
      ).resolves.toEqual({
        images: [],
      });
      expect(globalThis.fetch).toHaveBeenCalledTimes(2);
      expect(write).toHaveBeenCalledWith("Animation request attempt 1/2.\n");
      expect(write).toHaveBeenCalledWith("Animation request attempt 2/2.\n");
    } finally {
      write.mockRestore();
      globalThis.fetch = originalFetch;
    }
  });

  test("reports sanitized detail after a recurring animation 5xx", async () => {
    const originalFetch = globalThis.fetch;
    const write = vi
      .spyOn(process.stdout, "write")
      .mockImplementation(() => true);
    const firstFailure = new Response(JSON.stringify({ detail: "temporary" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
    globalThis.fetch = vi
      .fn()
      .mockResolvedValueOnce(firstFailure)
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            detail: "upstream token=secret-key; Bearer other-secret",
          }),
          { status: 500, headers: { "Content-Type": "application/json" } },
        ),
      );
    try {
      const error = await request(ANIMATION_ENDPOINT, {}, "secret-key").catch(
        (failure) => failure,
      );
      expect(error).toBeInstanceOf(Error);
      if (!(error instanceof Error)) throw error;
      expect(error.message).toContain(
        "PixelLab request failed with HTTP 500: upstream",
      );
      expect(error.message).not.toContain("secret-key");
      expect(error.message).not.toContain("other-secret");
      expect(globalThis.fetch).toHaveBeenCalledTimes(2);
      expect(firstFailure.bodyUsed).toBe(true);
    } finally {
      write.mockRestore();
      globalThis.fetch = originalFetch;
    }
  });

  test("never retries animation 4xx responses", async () => {
    const originalFetch = globalThis.fetch;
    const write = vi
      .spyOn(process.stdout, "write")
      .mockImplementation(() => true);
    globalThis.fetch = vi
      .fn()
      .mockResolvedValue(new Response(null, { status: 422 }));
    try {
      await expect(
        request(ANIMATION_ENDPOINT, {}, "not-a-key"),
      ).rejects.toThrow("PixelLab request failed with HTTP 422.");
      expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    } finally {
      write.mockRestore();
      globalThis.fetch = originalFetch;
    }
  });

  test("never retries Pixflux 5xx responses and sanitizes their detail", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          detail: "upstream token=secret-key; Bearer other-secret",
        }),
        { status: 500, headers: { "Content-Type": "application/json" } },
      ),
    );
    try {
      const error = await request(PIXFLUX_ENDPOINT, {}, "secret-key").catch(
        (failure) => failure,
      );
      expect(error).toBeInstanceOf(Error);
      if (!(error instanceof Error)) throw error;
      expect(error.message).toContain(
        "PixelLab request failed with HTTP 500: upstream",
      );
      expect(error.message).not.toContain("secret-key");
      expect(error.message).not.toContain("other-secret");
      expect(globalThis.fetch).toHaveBeenCalledTimes(1);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test("reuses a still only when its on-disk file and request identity match", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const png = encodeRgbaPng(32, 64, Buffer.alloc(32 * 64 * 4));
    const card = {
      id: "still",
      filename: "still.png",
      prompt: "a forge",
      negativeConstraints: "no words",
      seed: 41001,
      imageSize: { width: 32, height: 64 },
      params: { no_background: true },
    };
    const manifestAsset = {
      id: card.id,
      file: card.filename,
      sha256: createHash("sha256").update(png).digest("hex"),
      seed: 41001,
      prompt: card.prompt,
      negativeConstraints: card.negativeConstraints,
      params: { imageSize: card.imageSize, ...card.params },
    };
    try {
      await writeFile(join(directory, card.filename), png);
      await expect(
        reusableStillAsset(card, [manifestAsset], directory),
      ).resolves.toMatchObject({ png, asset: { ...manifestAsset } });
      await expect(
        reusableStillAsset(
          card,
          [{ ...manifestAsset, seed: 41002 }],
          directory,
        ),
      ).resolves.toBeNull();
      await expect(
        reusableStillAsset(
          card,
          [{ ...manifestAsset, prompt: "a tavern" }],
          directory,
        ),
      ).resolves.toBeNull();
      await expect(
        reusableStillAsset(
          card,
          [{ ...manifestAsset, negativeConstraints: "with words" }],
          directory,
        ),
      ).resolves.toBeNull();
      await expect(
        reusableStillAsset(
          card,
          [
            {
              ...manifestAsset,
              params: { imageSize: { width: 64, height: 64 }, ...card.params },
            },
          ],
          directory,
        ),
      ).resolves.toBeNull();
      await expect(
        reusableStillAsset(
          card,
          [
            {
              ...manifestAsset,
              params: { imageSize: card.imageSize, no_background: false },
            },
          ],
          directory,
        ),
      ).resolves.toBeNull();
      await expect(
        reusableStillAsset(
          card,
          [{ ...manifestAsset, sha256: "not-the-file-hash" }],
          directory,
        ),
      ).resolves.toBeNull();
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("reuses declaration-derived stills across commit provenance changes", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const png = encodeRgbaPng(32, 64, Buffer.alloc(32 * 64 * 4));
    const card = {
      id: "still",
      filename: "still.png",
      prompt: "a forge",
      negativeConstraints: "no words",
      seed: 41001,
      imageSize: { width: 32, height: 64 },
      params: { no_background: true },
      declarationSource: {
        registry: "fort/roster-appearance.md",
        section: "Citizen — Seat (they/them)",
        declarationSha256: "a".repeat(64),
        commit: "b".repeat(40),
      },
    };
    const manifestAsset = {
      id: card.id,
      file: card.filename,
      sha256: createHash("sha256").update(png).digest("hex"),
      seed: card.seed,
      prompt: card.prompt,
      negativeConstraints: card.negativeConstraints,
      params: { imageSize: card.imageSize, ...card.params },
      declarationSource: {
        ...card.declarationSource,
        commit: "c".repeat(40),
      },
    };
    try {
      await writeFile(join(directory, card.filename), png);
      await expect(
        reusableStillAsset(card, [manifestAsset], directory),
      ).resolves.toMatchObject({ asset: manifestAsset });
      await expect(
        reusableStillAsset(
          card,
          [
            {
              ...manifestAsset,
              declarationSource: {
                ...manifestAsset.declarationSource,
                declarationSha256: "d".repeat(64),
              },
            },
          ],
          directory,
        ),
      ).resolves.toBeNull();
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("main skips reuse when a seed offset changes the recorded still seed", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const originalFetch = globalThis.fetch;
    const originalArguments = process.argv;
    const originalApiKey = process.env.PIXELLAB_API_KEY;
    const originalReuseStills = process.env.PIXELLAB_REUSE_STILLS;
    const originalSeedOffset = process.env.PIXELLAB_SEED_OFFSET;
    const write = vi
      .spyOn(process.stdout, "write")
      .mockImplementation(() => true);
    const stillPng = encodeRgbaPng(32, 64, Buffer.alloc(32 * 64 * 4));
    const walkPng = encodeRgbaPng(64, 64, Buffer.alloc(64 * 64 * 4));
    const card = {
      id: "kethra-citizen",
      kind: "citizen",
      filename: "kethra-citizen.png",
      prompt: "Kethra",
      negativeConstraints: "no words",
      seed: 43000,
      imageSize: { width: 32, height: 64 },
      params: { no_background: true },
      declarationSource: {
        registry: "fort/roster-appearance.md",
        section: "Kethra Anvilmark — Forge of Manyhalls (she/her)",
        declarationSha256: "a".repeat(64),
        commit: "uncommitted",
      },
    };
    try {
      await writeFile(join(directory, card.filename), stillPng);
      await writeFile(
        join(directory, "provenance-manifest.json"),
        JSON.stringify({
          assets: [
            {
              id: card.id,
              file: card.filename,
              seed: card.seed,
              sha256: createHash("sha256").update(stillPng).digest("hex"),
            },
          ],
        }),
      );
      process.argv = process.argv.slice(0, 2);
      process.env.PIXELLAB_API_KEY = "not-a-key";
      process.env.PIXELLAB_REUSE_STILLS = "1";
      process.env.PIXELLAB_SEED_OFFSET = "1";
      const responseBody = JSON.stringify({
        image: { base64: stillPng.toString("base64") },
        images: Array.from({ length: 4 }, () => ({
          base64: walkPng.toString("base64"),
        })),
        usage: { usd: 0.0084 },
      });
      globalThis.fetch = vi
        .fn()
        .mockResolvedValueOnce(
          new Response(responseBody, {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        )
        .mockResolvedValueOnce(
          new Response(responseBody, {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );

      await main([card], directory);

      expect(globalThis.fetch).toHaveBeenCalledTimes(2);
      const manifest = JSON.parse(
        await readFile(join(directory, "provenance-manifest.json"), "utf8"),
      );
      expect(manifest.assets[0]).toMatchObject({ seed: 43001 });
      expect(manifest.assets[0].reusedAt).toBeUndefined();
    } finally {
      write.mockRestore();
      globalThis.fetch = originalFetch;
      process.argv = originalArguments;
      if (originalApiKey === undefined) delete process.env.PIXELLAB_API_KEY;
      else process.env.PIXELLAB_API_KEY = originalApiKey;
      if (originalReuseStills === undefined)
        delete process.env.PIXELLAB_REUSE_STILLS;
      else process.env.PIXELLAB_REUSE_STILLS = originalReuseStills;
      if (originalSeedOffset === undefined)
        delete process.env.PIXELLAB_SEED_OFFSET;
      else process.env.PIXELLAB_SEED_OFFSET = originalSeedOffset;
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("walk-only seed offsets retain still reuse and make one animation call", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const originalFetch = globalThis.fetch;
    const originalArguments = process.argv;
    const originalApiKey = process.env.PIXELLAB_API_KEY;
    const originalReuseStills = process.env.PIXELLAB_REUSE_STILLS;
    const originalSeedOffset = process.env.PIXELLAB_SEED_OFFSET;
    const originalAnimationSeedOffset =
      process.env.PIXELLAB_ANIMATION_SEED_OFFSET;
    const write = vi
      .spyOn(process.stdout, "write")
      .mockImplementation(() => true);
    const stillPng = encodeRgbaPng(32, 64, Buffer.alloc(32 * 64 * 4));
    const walkPng = encodeRgbaPng(64, 64, Buffer.alloc(64 * 64 * 4));
    const card = {
      id: "kethra-citizen",
      kind: "citizen",
      filename: "kethra-citizen.png",
      prompt: "Kethra",
      negativeConstraints: "no words",
      seed: 43000,
      imageSize: { width: 32, height: 64 },
      params: { no_background: true },
      declarationSource: {
        registry: "fort/roster-appearance.md",
        section: "Kethra Anvilmark — Forge of Manyhalls (she/her)",
        declarationSha256: "a".repeat(64),
        commit: "uncommitted",
      },
    };
    const originalAsset = {
      id: card.id,
      file: card.filename,
      seed: card.seed,
      sha256: createHash("sha256").update(stillPng).digest("hex"),
      prompt: card.prompt,
      negativeConstraints: card.negativeConstraints,
      params: { imageSize: card.imageSize, ...card.params },
      declarationSource: {
        ...card.declarationSource,
        commit: "a".repeat(40),
      },
    };
    try {
      await writeFile(join(directory, card.filename), stillPng);
      await writeFile(
        join(directory, "provenance-manifest.json"),
        JSON.stringify({ assets: [originalAsset] }),
      );
      process.argv = process.argv.slice(0, 2);
      process.env.PIXELLAB_API_KEY = "not-a-key";
      process.env.PIXELLAB_REUSE_STILLS = "1";
      delete process.env.PIXELLAB_SEED_OFFSET;
      process.env.PIXELLAB_ANIMATION_SEED_OFFSET = "1";
      globalThis.fetch = vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            images: Array.from({ length: 4 }, () => ({
              base64: walkPng.toString("base64"),
            })),
            usage: { usd: 0.0084 },
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      );

      await main([card], directory);

      expect(globalThis.fetch).toHaveBeenCalledTimes(1);
      const manifest = JSON.parse(
        await readFile(join(directory, "provenance-manifest.json"), "utf8"),
      );
      expect(manifest.assets[0]).toMatchObject(originalAsset);
      expect(manifest.assets[0].reusedAt).toEqual(expect.any(String));
      expect(
        manifest.assets.slice(1).map((asset: { seed: number }) => asset.seed),
      ).toEqual([43002, 43002, 43002, 43002]);
    } finally {
      write.mockRestore();
      globalThis.fetch = originalFetch;
      process.argv = originalArguments;
      if (originalApiKey === undefined) delete process.env.PIXELLAB_API_KEY;
      else process.env.PIXELLAB_API_KEY = originalApiKey;
      if (originalReuseStills === undefined)
        delete process.env.PIXELLAB_REUSE_STILLS;
      else process.env.PIXELLAB_REUSE_STILLS = originalReuseStills;
      if (originalSeedOffset === undefined)
        delete process.env.PIXELLAB_SEED_OFFSET;
      else process.env.PIXELLAB_SEED_OFFSET = originalSeedOffset;
      if (originalAnimationSeedOffset === undefined)
        delete process.env.PIXELLAB_ANIMATION_SEED_OFFSET;
      else
        process.env.PIXELLAB_ANIMATION_SEED_OFFSET =
          originalAnimationSeedOffset;
      await rm(directory, { recursive: true, force: true });
    }
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

  test("refuses contaminated character frames and accepts clean transparency", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const card = {
      id: "walk-03",
      kind: "walk-frame",
      filename: "walk-03.png",
      imageSize: { width: 32, height: 64 },
      params: {},
    };
    const clean = encodeRgbaPng(32, 64, Buffer.alloc(32 * 64 * 4));
    const contaminatedPixels = Buffer.alloc(32 * 64 * 4);
    contaminatedPixels[3] = 255;
    const contaminated = encodeRgbaPng(32, 64, contaminatedPixels);
    const manifest: { assets: Array<Record<string, unknown>> } = { assets: [] };
    try {
      expect(characterTransparencyCheck(card, clean)).toBe("passed");
      expect(() => characterTransparencyCheck(card, contaminated)).toThrow(
        "Refusing character asset walk-03: transparency check failed (0.27% contaminated border, 0.05% opaque coverage).",
      );
      await expect(
        writeAsset(
          manifest,
          card,
          { png: contaminated },
          { requestedImageSize: card.imageSize },
          directory,
        ),
      ).rejects.toThrow("Refusing character asset walk-03");
      await expect(readFile(join(directory, card.filename))).rejects.toThrow();
      expect(manifest.assets).toEqual([]);
      await writeAsset(
        manifest,
        card,
        { png: clean },
        { requestedImageSize: card.imageSize },
        directory,
      );
      expect(manifest.assets[0]?.transparencyCheck).toBe("passed");
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  test("records API-requested and decoded image sizes separately", async () => {
    const directory = await mkdtemp(join(tmpdir(), "pixellab-trial-test-"));
    const png = encodeRgbaPng(64, 64, Buffer.alloc(64 * 64 * 4));
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
    const write = vi
      .spyOn(process.stdout, "write")
      .mockImplementation(() => true);
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
      write.mockRestore();
      globalThis.fetch = originalFetch;
    }
  });

  test("projects 422 detail arrays without echoed request input", async () => {
    const originalFetch = globalThis.fetch;
    const write = vi
      .spyOn(process.stdout, "write")
      .mockImplementation(() => true);
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
      write.mockRestore();
      globalThis.fetch = originalFetch;
    }
  });

  test("fails Kethra-card renames at startup before a request can start", async () => {
    await expect(main([{ id: "renamed-kethra-citizen" }])).rejects.toThrow(
      "Trial configuration requires a kethra-citizen card before generation.",
    );
  });

  test("fails an undeclared Kethra card before generation", () => {
    expect(() => assertKethraCitizenCard([{ id: "kethra-citizen" }])).toThrow(
      "requires kethra-citizen to derive from the Appearance Registry",
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
