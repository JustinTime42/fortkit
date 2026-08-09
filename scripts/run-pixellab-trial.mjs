#!/usr/bin/env node

/**
 * Run the bounded PixelLab visual trial.
 *
 * Exact invocation (run from the repository root, without putting the key in
 * shell history):
 *   read -rs PIXELLAB_API_KEY && export PIXELLAB_API_KEY
 *   node scripts/run-pixellab-trial.mjs
 *
 * The key is read only from PIXELLAB_API_KEY. This program accepts no command
 * line arguments, never writes or logs the key, and does not put it in prompts,
 * manifest entries, or request bodies.
 */

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateSync, inflateSync } from "node:zlib";

const OUTPUT_DIRECTORY = fileURLToPath(
  new URL("../assets/trial", import.meta.url),
);
const APPEARANCE_REGISTRY_PATH = fileURLToPath(
  new URL("../fort/roster-appearance.md", import.meta.url),
);
const APPEARANCE_REGISTRY_REPOSITORY_PATH = "fort/roster-appearance.md";
const PIXFLUX_ENDPOINT = "https://api.pixellab.ai/v1/generate-image-pixflux";
const ANIMATION_ENDPOINT = "https://api.pixellab.ai/v1/animate-with-text";
const PIXFLUX_MODEL = "pixflux";
const ANIMATION_MODEL = "animate-with-text";
const ANIMATION_IMAGE_SIZE = { width: 64, height: 64 };
const MAX_SPEND_USD = 15;
const MAX_TOTAL_GENERATIONS = 30;
const MAX_ESTIMATED_COST_PER_ASSET_USD = 0.02;
const MAX_GENERATIONS_PER_STILL_ASSET = 2;
const MAX_GENERATIONS_PER_ANIMATION_CALL = 8;
const MANIFEST_SCHEMA_VERSION = 8;
const PIXFLUX_REQUEST_TIMEOUT_MS = 120_000;
const ANIMATION_REQUEST_TIMEOUT_MS = 120_000;
const ANIMATION_RETRY_DELAY_MS = 250;
const ANIMATION_REQUEST_ATTEMPTS = 2;
const PNG_SIGNATURE = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
]);
const PNG_IHDR_LENGTH = 13;
const PNG_RGBA_BYTES_PER_PIXEL = 4;
const REFERENCE_PADDING = {
  from: { width: 32, height: 64 },
  to: { width: 64, height: 64 },
  placement: "bottom-center",
};
const NEGATIVE_CONSTRAINTS =
  "no words, no UI, no watermark, no photorealism, no isometric grid, no extra people";
const CHARACTER_NEGATIVE_CONSTRAINTS = `${NEGATIVE_CONSTRAINTS}, no background elements, no pillars, no walls, no floor, no scenery`;
const CHARACTER_ISOLATION =
  "isolated character only, fully transparent background, no scenery, no props, no environment, no floor, no shadow on ground";
const CHARACTER_KINDS = new Set(["citizen-master", "walk-frame"]);
const TRANSPARENCY_BORDER_BAND_PX = 2;
const MAX_CHARACTER_OPAQUE_COVERAGE = 0.6;

function parseAppearanceRegistry(registry) {
  const entries = new Map();
  const sections = registry.split(/^## /m).slice(1);
  for (const section of sections) {
    const [heading, ...body] = section.split("\n");
    const declarationLines = body.filter((line) => line.startsWith("> "));
    if (declarationLines.length === 0) continue;
    const name = heading.split(" — ")[0];
    entries.set(name, {
      section: heading,
      declaration: declarationLines.map((line) => line.slice(2)).join(" "),
    });
  }
  return entries;
}

function registryCommit(run = execFileSync) {
  try {
    const commit = run(
      "git",
      ["log", "-1", "--format=%H", "--", APPEARANCE_REGISTRY_REPOSITORY_PATH],
      { cwd: fileURLToPath(new URL("..", import.meta.url)), encoding: "utf8" },
    ).trim();
    return /^[0-9a-f]{40}$/.test(commit) ? commit : "uncommitted";
  } catch {
    return "uncommitted";
  }
}

function promptVisualClauses(declaration) {
  return declaration
    .split(/(?<=\.)\s+/)
    .slice(0, 3)
    .join(" ")
    .replace(/\.$/, "");
}

function citizenAppearance(
  name,
  registry = parseAppearanceRegistry(
    readFileSync(APPEARANCE_REGISTRY_PATH, "utf8"),
  ),
  commit = "uncommitted",
) {
  const entry = registry.get(name);
  if (!entry)
    return {
      prompt: "deliberately generic silhouette, no declared appearance",
      declarationSource: null,
    };
  return {
    prompt: promptVisualClauses(entry.declaration),
    declarationSource: {
      registry: APPEARANCE_REGISTRY_REPOSITORY_PATH,
      section: entry.section,
      declarationSha256: sha256(entry.declaration),
      commit,
    },
  };
}

const kethraAppearance = citizenAppearance("Kethra Anvilmark");

const cards = [
  card(
    "forge-building",
    "building",
    128,
    128,
    41001,
    "humble dwarven stone forge building, chimney, anvil sign without text",
  ),
  card(
    "tavern-building",
    "building",
    128,
    128,
    41002,
    "warm dwarven stone tavern building, barrel and lantern, no readable sign",
  ),
  card(
    "kethra-citizen",
    "citizen-master",
    32,
    64,
    42001,
    `${kethraAppearance.prompt}, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame, ${CHARACTER_ISOLATION}`,
    kethraAppearance.declarationSource,
  ),
  card(
    "tavern-master",
    "citizen-master",
    32,
    64,
    42002,
    `dwarven tavern master, apron and tankard, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame, ${CHARACTER_ISOLATION}`,
  ),
  card(
    "implementation-crate",
    "item-glyph",
    32,
    32,
    44001,
    "small wooden crate of forge tools for implementation work",
  ),
  card(
    "research-scroll",
    "item-glyph",
    32,
    32,
    44002,
    "rolled research scroll and magnifying glass",
  ),
  card(
    "review-lantern",
    "item-glyph",
    32,
    32,
    44003,
    "inspection lantern for review work",
  ),
  card(
    "coordination-token",
    "item-glyph",
    32,
    32,
    44004,
    "dwarven coordination token, small linked rings",
  ),
];

const WALK_DESCRIPTION = `${kethraAppearance.prompt}, walking east, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame, ${CHARACTER_ISOLATION}`;

const walkCards = [
  walkCard("kethra-walk-east-01", 43001, 1),
  walkCard("kethra-walk-east-02", 43001, 2),
  walkCard("kethra-walk-east-03", 43001, 3),
  walkCard("kethra-walk-east-04", 43001, 4),
];

function card(
  id,
  kind,
  width,
  height,
  seed,
  subject,
  declarationSource = null,
) {
  const character = CHARACTER_KINDS.has(kind);
  return {
    id,
    kind,
    filename: `${id}.png`,
    prompt: character
      ? `32-bit pixel art, single character, orthographic 3/4 view, ${subject}, no text, no logo`
      : `32-bit pixel art, single object or character, orthographic 3/4 exterior, ${subject}, no text, no logo`,
    negativeConstraints: character
      ? CHARACTER_NEGATIVE_CONSTRAINTS
      : NEGATIVE_CONSTRAINTS,
    seed,
    imageSize: { width, height },
    params: { no_background: true, outline: "selective outline" },
    declarationSource,
  };
}

function walkCard(id, seed, frameIndex) {
  return {
    id,
    kind: "walk-frame",
    filename: `${id}.png`,
    prompt: WALK_DESCRIPTION,
    frameIndex,
    negativeConstraints: CHARACTER_NEGATIVE_CONSTRAINTS,
    seed,
    imageSize: { width: 32, height: 64 },
    params: {
      no_background: true,
      view: "side",
      direction: "east",
      action: "walk",
      n_frames: 4,
    },
    declarationSource: kethraAppearance.declarationSource,
  };
}

function rejectArguments() {
  if (process.argv.length !== 2)
    throw new Error(
      "This script accepts no arguments. Set PIXELLAB_API_KEY in the environment.",
    );
}

function seedOffsetFromEnvironment(value = process.env.PIXELLAB_SEED_OFFSET) {
  if (value === undefined || value === "") return 0;
  if (!/^-?\d+$/.test(value))
    throw new Error("PIXELLAB_SEED_OFFSET must be an integer.");
  const offset = Number(value);
  if (!Number.isSafeInteger(offset))
    throw new Error("PIXELLAB_SEED_OFFSET must be a safe integer.");
  return offset;
}

function animationSeedOffsetFromEnvironment(
  value = process.env.PIXELLAB_ANIMATION_SEED_OFFSET,
) {
  if (value === undefined || value === "") return 0;
  if (!/^-?\d+$/.test(value))
    throw new Error("PIXELLAB_ANIMATION_SEED_OFFSET must be an integer.");
  const offset = Number(value);
  if (!Number.isSafeInteger(offset))
    throw new Error("PIXELLAB_ANIMATION_SEED_OFFSET must be a safe integer.");
  return offset;
}

function withSeedOffset(cardDefinition, offset) {
  const seed = cardDefinition.seed + offset;
  if (!Number.isSafeInteger(seed))
    throw new Error("PIXELLAB_SEED_OFFSET produces an unsafe seed.");
  return { ...cardDefinition, seed };
}

function readApiKey() {
  const key = process.env.PIXELLAB_API_KEY;
  delete process.env.PIXELLAB_API_KEY;
  if (!key) throw new Error("PIXELLAB_API_KEY must be set in the environment.");
  return key;
}

function assertKethraCitizenCard(cardDefinitions) {
  const kethraCitizenCard = cardDefinitions.find(
    (cardDefinition) => cardDefinition.id === "kethra-citizen",
  );
  if (!kethraCitizenCard)
    throw new Error(
      "Trial configuration requires a kethra-citizen card before generation.",
    );
  if (!kethraCitizenCard.declarationSource)
    throw new Error(
      "Trial configuration requires kethra-citizen to derive from the Appearance Registry before generation.",
    );
  return kethraCitizenCard;
}

function withRegistryCommit(cardDefinitions, commit) {
  return cardDefinitions.map((cardDefinition) =>
    cardDefinition.declarationSource?.registry ===
    APPEARANCE_REGISTRY_REPOSITORY_PATH
      ? {
          ...cardDefinition,
          declarationSource: { ...cardDefinition.declarationSource, commit },
        }
      : cardDefinition,
  );
}

function requestTimeoutMilliseconds(
  endpoint,
  value = process.env.PIXELLAB_TIMEOUT_MS,
) {
  const endpointDefault =
    endpoint === ANIMATION_ENDPOINT
      ? ANIMATION_REQUEST_TIMEOUT_MS
      : PIXFLUX_REQUEST_TIMEOUT_MS;
  if (value !== undefined && value !== "") {
    if (!/^\d+$/.test(value) || Number(value) === 0)
      throw new Error("PIXELLAB_TIMEOUT_MS must be a positive integer.");
    const timeout = Number(value);
    if (!Number.isSafeInteger(timeout))
      throw new Error("PIXELLAB_TIMEOUT_MS must be a safe integer.");
    return Math.max(endpointDefault, timeout);
  }
  return endpointDefault;
}

function pixfluxRequestBody(cardDefinition) {
  return {
    description: cardDefinition.prompt,
    negative_description: cardDefinition.negativeConstraints,
    image_size: cardDefinition.imageSize,
    no_background: cardDefinition.params.no_background,
    outline: cardDefinition.params.outline,
    seed: cardDefinition.seed,
  };
}

function animationRequestBody(masterPng, walkCardDefinition) {
  const paddedReference = padAnimationReference(masterPng);
  return {
    reference_image: {
      type: "base64",
      // The response parser accepts both data URLs and raw base64, but the
      // fortkit-fav hypothesizes the animation API's strict decoder expects
      // raw base64 in requests; run seven will record the live outcome.
      base64: paddedReference.toString("base64"),
    },
    reference_image_size: ANIMATION_IMAGE_SIZE,
    description: walkCardDefinition.prompt,
    negative_description: walkCardDefinition.negativeConstraints,
    action: walkCardDefinition.params.action,
    // PixelLab requires 64x64 animation output. The visualizer's 32x64
    // sprite contract is retained on the card and recorded separately.
    image_size: ANIMATION_IMAGE_SIZE,
    seed: walkCardDefinition.seed,
    no_background: true,
    view: walkCardDefinition.params.view,
    direction: walkCardDefinition.params.direction,
    n_frames: walkCardDefinition.params.n_frames,
  };
}

function parseUsageMeter(usage, maximumUsd, maximumGenerations) {
  if (usage?.type === "generations") {
    if (!Number.isSafeInteger(usage.generations) || usage.generations <= 0)
      throw new Error(
        `Refusing to continue: PixelLab returned an unexpected pricing shape: ${JSON.stringify(usage)}`,
      );
    if (usage.generations > maximumGenerations)
      throw new Error(
        `Refusing to continue: PixelLab returned a generations amount over the per-request cap (${usage.generations} > ${maximumGenerations}): ${JSON.stringify(usage)}`,
      );
    return { meter: "generations", amount: usage.generations };
  }

  if (usage?.type !== undefined)
    throw new Error(
      `Refusing to continue: PixelLab returned an unexpected pricing shape: ${JSON.stringify(usage)}`,
    );

  const usd =
    typeof usage?.usd === "number" || typeof usage?.usd === "string"
      ? Number(usage.usd)
      : Number.NaN;
  if (!Number.isFinite(usd) || usd < 0)
    throw new Error(
      `Refusing to continue: PixelLab returned an unexpected pricing shape: ${JSON.stringify(usage)}`,
    );
  if (usd > maximumUsd)
    throw new Error(
      `Refusing to continue: PixelLab returned a USD amount over the per-request cap (${usd} > ${maximumUsd}): ${JSON.stringify(usage)}`,
    );
  return { meter: "usd", amount: usd };
}

function perFrameProvenance(cost, frameCount) {
  const share = { meter: cost.meter, amount: cost.amount / frameCount };
  return {
    ...(cost.meter === "usd" ? { cost: share } : { amortizedCost: share }),
    requestCost: cost,
  };
}

function addUsage(totals, cost) {
  const next = { ...totals };
  next[cost.meter] += cost.amount;
  if (next.usd > MAX_SPEND_USD)
    throw new Error(
      "Refusing to continue: actual trial spend exceeds the $15 cap.",
    );
  if (next.generations > MAX_TOTAL_GENERATIONS)
    throw new Error(
      "Refusing to continue: actual trial generation credits exceed the 30 cap.",
    );
  return next;
}

function pngFromBase64(encoded) {
  if (typeof encoded !== "string")
    throw new Error("PixelLab returned no PNG image.");
  const base64 = encoded.startsWith("data:image/png;base64,")
    ? encoded.slice(encoded.indexOf(",") + 1)
    : encoded;
  const png = Buffer.from(base64, "base64");
  if (!png.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE))
    throw new Error("PixelLab returned an invalid PNG image.");
  return png;
}

function pngDimensions(png) {
  if (png.length < 24 || png.toString("ascii", 12, 16) !== "IHDR")
    throw new Error("PixelLab returned a PNG without valid dimensions.");
  return {
    width: png.readUInt32BE(16),
    height: png.readUInt32BE(20),
  };
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1)
      crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const chunk = Buffer.alloc(12 + data.length);
  chunk.writeUInt32BE(data.length, 0);
  chunk.write(type, 4, 4, "ascii");
  data.copy(chunk, 8);
  chunk.writeUInt32BE(
    crc32(chunk.subarray(4, 8 + data.length)),
    8 + data.length,
  );
  return chunk;
}

function constrainedRgbaPixels(
  png,
  { width: expectedWidth = 32, height: expectedHeight = 64 } = {},
) {
  if (!png.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE))
    throw new Error(
      "Cannot pad animation reference: expected a PNG signature.",
    );

  let offset = PNG_SIGNATURE.length;
  let header;
  const idat = [];
  let seenIdat = false;
  let seenIend = false;
  while (offset < png.length) {
    if (offset + 12 > png.length)
      throw new Error("Cannot pad animation reference: malformed PNG chunk.");
    const length = png.readUInt32BE(offset);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    const crcEnd = dataEnd + 4;
    if (crcEnd > png.length)
      throw new Error("Cannot pad animation reference: malformed PNG chunk.");
    const type = png.toString("ascii", offset + 4, dataStart);
    const data = png.subarray(dataStart, dataEnd);
    if (png.readUInt32BE(dataEnd) !== crc32(png.subarray(offset + 4, dataEnd)))
      throw new Error(
        "Cannot pad animation reference: PNG chunk CRC mismatch.",
      );
    if (type === "IHDR") {
      if (header || length !== PNG_IHDR_LENGTH || seenIdat)
        throw new Error(
          "Cannot pad animation reference: unexpected IHDR chunk.",
        );
      header = data;
    } else if (type === "IDAT") {
      if (!header || seenIend)
        throw new Error(
          "Cannot pad animation reference: unexpected IDAT chunk.",
        );
      seenIdat = true;
      idat.push(data);
    } else if (type === "IEND") {
      if (!seenIdat || length !== 0 || seenIend || crcEnd !== png.length)
        throw new Error(
          "Cannot pad animation reference: unexpected IEND chunk.",
        );
      seenIend = true;
    } else if (type[0] !== type[0]?.toLowerCase()) {
      throw new Error(
        `Cannot pad animation reference: unsupported PNG chunk ${type}.`,
      );
    }
    offset = crcEnd;
  }
  if (!header || !seenIend)
    throw new Error(
      "Cannot pad animation reference: PNG is missing required chunks.",
    );

  const width = header.readUInt32BE(0);
  const height = header.readUInt32BE(4);
  if (
    width !== expectedWidth ||
    height !== expectedHeight ||
    header[8] !== 8 ||
    header[9] !== 6 ||
    header[10] !== 0 ||
    header[11] !== 0 ||
    header[12] !== 0
  )
    throw new Error(
      "Cannot pad animation reference: expected a 32x64 8-bit RGBA non-interlaced PNG.",
    );

  const rowBytes = width * PNG_RGBA_BYTES_PER_PIXEL;
  const scanlineLength = (rowBytes + 1) * height;
  let scanlines;
  try {
    scanlines = inflateSync(Buffer.concat(idat), {
      maxOutputLength: scanlineLength,
    });
  } catch {
    throw new Error("Cannot pad animation reference: invalid PNG image data.");
  }
  if (scanlines.length !== scanlineLength)
    throw new Error(
      "Cannot pad animation reference: unexpected PNG scanline length.",
    );

  const pixels = Buffer.alloc(rowBytes * height);
  for (let row = 0; row < height; row += 1) {
    const scanlineOffset = row * (rowBytes + 1);
    const filter = scanlines[scanlineOffset];
    if (filter > 4)
      throw new Error(
        "Cannot pad animation reference: unsupported PNG filter.",
      );
    for (let column = 0; column < rowBytes; column += 1) {
      const value = scanlines[scanlineOffset + 1 + column];
      const left =
        column >= PNG_RGBA_BYTES_PER_PIXEL
          ? pixels[row * rowBytes + column - PNG_RGBA_BYTES_PER_PIXEL]
          : 0;
      const above = row > 0 ? pixels[(row - 1) * rowBytes + column] : 0;
      const upperLeft =
        row > 0 && column >= PNG_RGBA_BYTES_PER_PIXEL
          ? pixels[(row - 1) * rowBytes + column - PNG_RGBA_BYTES_PER_PIXEL]
          : 0;
      const predictor =
        filter === 1
          ? left
          : filter === 2
            ? above
            : filter === 3
              ? Math.floor((left + above) / 2)
              : filter === 4
                ? paeth(left, above, upperLeft)
                : 0;
      pixels[row * rowBytes + column] = (value + predictor) & 0xff;
    }
  }
  return pixels;
}

function characterTransparencyCheck(cardDefinition, png) {
  if (!CHARACTER_KINDS.has(cardDefinition.kind)) return null;
  const { width, height } = pngDimensions(png);
  const pixels = constrainedRgbaPixels(png, { width, height });
  let opaquePixels = 0;
  let contaminatedBorderPixels = 0;
  let borderPixels = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const opaque =
        pixels[(y * width + x) * PNG_RGBA_BYTES_PER_PIXEL + 3] !== 0;
      if (opaque) opaquePixels += 1;
      if (
        x < TRANSPARENCY_BORDER_BAND_PX ||
        x >= width - TRANSPARENCY_BORDER_BAND_PX ||
        y < TRANSPARENCY_BORDER_BAND_PX ||
        y >= height - TRANSPARENCY_BORDER_BAND_PX
      ) {
        borderPixels += 1;
        if (opaque) contaminatedBorderPixels += 1;
      }
    }
  }
  const opaqueCoverage = opaquePixels / (width * height);
  const contaminatedBorderCoverage = contaminatedBorderPixels / borderPixels;
  if (
    contaminatedBorderPixels !== 0 ||
    opaqueCoverage > MAX_CHARACTER_OPAQUE_COVERAGE
  )
    throw new Error(
      `Refusing character asset ${cardDefinition.id}: transparency check failed (${(contaminatedBorderCoverage * 100).toFixed(2)}% contaminated border, ${(opaqueCoverage * 100).toFixed(2)}% opaque coverage).`,
    );
  return "passed";
}

function paeth(left, above, upperLeft) {
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

function padAnimationReference(masterPng) {
  const sourcePixels = constrainedRgbaPixels(masterPng);
  const { width, height } = REFERENCE_PADDING.to;
  const scanlines = Buffer.alloc(
    (width * PNG_RGBA_BYTES_PER_PIXEL + 1) * height,
  );
  const sourceWidth = REFERENCE_PADDING.from.width;
  const sourceHeight = REFERENCE_PADDING.from.height;
  const xOffset = (width - sourceWidth) / 2;
  const yOffset = height - sourceHeight;
  for (let row = 0; row < sourceHeight; row += 1) {
    const targetRow = (row + yOffset) * (width * PNG_RGBA_BYTES_PER_PIXEL + 1);
    scanlines[targetRow] = 0;
    sourcePixels.copy(
      scanlines,
      targetRow + 1 + xOffset * PNG_RGBA_BYTES_PER_PIXEL,
      row * sourceWidth * PNG_RGBA_BYTES_PER_PIXEL,
      (row + 1) * sourceWidth * PNG_RGBA_BYTES_PER_PIXEL,
    );
  }
  const header = Buffer.alloc(PNG_IHDR_LENGTH);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  return Buffer.concat([
    PNG_SIGNATURE,
    pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(scanlines)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function confirmedModel(response) {
  return typeof response.model === "string"
    ? response.model
    : typeof response.metadata?.model === "string"
      ? response.metadata.model
      : null;
}

async function request(endpoint, body, apiKey) {
  const timeoutMilliseconds = requestTimeoutMilliseconds(endpoint);
  const retryAnimation = endpoint === ANIMATION_ENDPOINT;
  const attempts = retryAnimation ? ANIMATION_REQUEST_ATTEMPTS : 1;
  for (let attempt = 1; ; attempt += 1) {
    if (retryAnimation)
      process.stdout.write(
        `Animation request attempt ${attempt}/${attempts}.\n`,
      );
    const signal = AbortSignal.timeout(timeoutMilliseconds);
    let response;
    try {
      response = await fetch(endpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal,
      });
    } catch (error) {
      if (signal.aborted)
        throw new Error(
          `PixelLab request to ${endpoint} timed out after ${timeoutMilliseconds}ms.`,
        );
      throw error;
    }
    if (response.ok) return response.json();
    if (
      retryAnimation &&
      attempt < attempts &&
      response.status >= 500 &&
      response.status < 600
    ) {
      await response.body?.cancel().catch(() => {});
      process.stdout.write(
        `Animation request attempt ${attempt} received HTTP ${response.status}; retrying after ${ANIMATION_RETRY_DELAY_MS}ms.\n`,
      );
      await new Promise((resolve) =>
        setTimeout(resolve, ANIMATION_RETRY_DELAY_MS),
      );
      continue;
    }
    const detail =
      response.status >= 400 && response.status < 600
        ? await responseDetail(response, apiKey)
        : "";
    throw new Error(
      `PixelLab request failed with HTTP ${response.status}${detail ? `: ${detail}` : "."}`,
    );
  }
}

async function responseDetail(response, apiKey) {
  try {
    const payload = await response.json();
    if (
      payload === null ||
      typeof payload !== "object" ||
      !("detail" in payload)
    )
      return "";
    const detail = payload.detail;
    const safeDetail = Array.isArray(detail)
      ? detail.map(({ type, loc, msg }) => ({ type, loc, msg }))
      : detail;
    const rendered =
      typeof safeDetail === "string" ? safeDetail : JSON.stringify(safeDetail);
    return rendered
      .replaceAll(apiKey, "[redacted]")
      .replace(/Bearer\s+[^\s"']+/gi, "Bearer [redacted]")
      .slice(0, 4_000);
  } catch {
    return "";
  }
}

async function generatePixflux(cardDefinition, apiKey) {
  const response = await request(
    PIXFLUX_ENDPOINT,
    pixfluxRequestBody(cardDefinition),
    apiKey,
  );
  return {
    png: pngFromBase64(response.image?.base64),
    cost: parseUsageMeter(
      response.usage,
      MAX_ESTIMATED_COST_PER_ASSET_USD,
      MAX_GENERATIONS_PER_STILL_ASSET,
    ),
    confirmedModel: confirmedModel(response),
  };
}

async function generateWalkCycle(masterPng, walkCardDefinition, apiKey) {
  const response = await request(
    ANIMATION_ENDPOINT,
    animationRequestBody(masterPng, walkCardDefinition),
    apiKey,
  );
  if (
    !Array.isArray(response.images) ||
    response.images.length !== walkCards.length
  )
    throw new Error("PixelLab returned an unexpected walk-cycle frame count.");
  return {
    pngs: response.images.map((image) => pngFromBase64(image?.base64)),
    cost: parseUsageMeter(
      response.usage,
      walkCards.length * MAX_ESTIMATED_COST_PER_ASSET_USD,
      MAX_GENERATIONS_PER_ANIMATION_CALL,
    ),
    confirmedModel: confirmedModel(response),
  };
}

function sha256(png) {
  return createHash("sha256").update(png).digest("hex");
}

async function writeAsset(
  manifest,
  cardDefinition,
  result,
  provenance,
  outputDirectory = OUTPUT_DIRECTORY,
) {
  const actualImageSize = pngDimensions(result.png);
  const transparencyCheck = characterTransparencyCheck(
    cardDefinition,
    result.png,
  );
  await writeFile(join(outputDirectory, cardDefinition.filename), result.png);
  manifest.assets.push({
    id: cardDefinition.id,
    kind: cardDefinition.kind,
    file: cardDefinition.filename,
    requestedModel: provenance.requestedModel,
    confirmedModel: provenance.confirmedModel,
    endpoint: provenance.endpoint,
    prompt: cardDefinition.prompt,
    frameIndex: cardDefinition.frameIndex,
    negativeConstraints: cardDefinition.negativeConstraints,
    seed: cardDefinition.seed,
    params: { imageSize: cardDefinition.imageSize, ...cardDefinition.params },
    requestedImageSize: provenance.requestedImageSize,
    actualImageSize,
    generatedAt: new Date().toISOString(),
    cost: provenance.cost,
    amortizedCost: provenance.amortizedCost,
    requestCost: provenance.requestCost,
    sha256: sha256(result.png),
    declarationSource: cardDefinition.declarationSource ?? null,
    reference: provenance.reference ?? null,
    referencePadding: provenance.referencePadding ?? null,
    ...(transparencyCheck ? { transparencyCheck } : {}),
  });
  await writeFile(
    join(outputDirectory, "provenance-manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
}

async function priorManifest(outputDirectory) {
  try {
    const parsed = JSON.parse(
      await readFile(join(outputDirectory, "provenance-manifest.json"), "utf8"),
    );
    return Array.isArray(parsed.assets) ? parsed : { assets: [] };
  } catch {
    return { assets: [] };
  }
}

async function reusableStillAsset(
  cardDefinition,
  existingAssets,
  outputDirectory,
) {
  const requestedParams = {
    imageSize: cardDefinition.imageSize,
    ...cardDefinition.params,
  };
  const existing = existingAssets.find(
    (asset) =>
      asset?.id === cardDefinition.id &&
      asset?.file === cardDefinition.filename &&
      asset?.seed === cardDefinition.seed &&
      asset?.prompt === cardDefinition.prompt &&
      asset?.negativeConstraints === cardDefinition.negativeConstraints &&
      JSON.stringify(asset?.params) === JSON.stringify(requestedParams) &&
      sameDeclarationIdentity(
        asset?.declarationSource,
        cardDefinition.declarationSource,
      ) &&
      typeof asset?.sha256 === "string",
  );
  if (!existing) return null;
  try {
    const png = await readFile(join(outputDirectory, cardDefinition.filename));
    if (sha256(png) !== existing.sha256) return null;
    pngDimensions(png);
    const transparencyCheck = characterTransparencyCheck(cardDefinition, png);
    return {
      png,
      asset: {
        ...existing,
        ...(transparencyCheck ? { transparencyCheck } : {}),
        reusedAt: new Date().toISOString(),
      },
    };
  } catch {
    return null;
  }
}

function sameDeclarationIdentity(existingSource, requestedSource) {
  if (existingSource === null || existingSource === undefined)
    return requestedSource === null || requestedSource === undefined;
  if (requestedSource === null || requestedSource === undefined) return false;
  return (
    existingSource.registry === requestedSource.registry &&
    existingSource.section === requestedSource.section &&
    existingSource.declarationSha256 === requestedSource.declarationSha256
  );
}

async function main(cardDefinitions, outputDirectory = OUTPUT_DIRECTORY) {
  rejectArguments();
  const declarationCommit = registryCommit();
  const trialCards = withRegistryCommit(
    cardDefinitions ?? cards,
    declarationCommit,
  );
  const trialWalkCards = withRegistryCommit(walkCards, declarationCommit);
  const kethraCitizenCard = assertKethraCitizenCard(trialCards);
  const apiKey = readApiKey();
  const seedOffset = seedOffsetFromEnvironment();
  const animationSeedOffset = animationSeedOffsetFromEnvironment();
  await mkdir(outputDirectory, { recursive: true });
  const reuseStills = process.env.PIXELLAB_REUSE_STILLS === "1";
  const existingManifest = reuseStills
    ? await priorManifest(outputDirectory)
    : { assets: [] };
  const manifest = {
    schemaVersion: MANIFEST_SCHEMA_VERSION,
    generatedAt: new Date().toISOString(),
    provider: "PixelLab",
    spendCapUsd: MAX_SPEND_USD,
    generationCap: MAX_TOTAL_GENERATIONS,
    assets: [],
  };
  let totals = { usd: 0, generations: 0 };
  let kethraMaster;
  for (const originalCardDefinition of trialCards) {
    const cardDefinition = withSeedOffset(originalCardDefinition, seedOffset);
    const reused = reuseStills
      ? await reusableStillAsset(
          cardDefinition,
          existingManifest.assets,
          outputDirectory,
        )
      : null;
    const result = reused ?? (await generatePixflux(cardDefinition, apiKey));
    if (reused) {
      manifest.assets.push(reused.asset);
      await writeFile(
        join(outputDirectory, "provenance-manifest.json"),
        `${JSON.stringify(manifest, null, 2)}\n`,
      );
    } else {
      totals = addUsage(totals, result.cost);
      await writeAsset(
        manifest,
        cardDefinition,
        result,
        {
          requestedModel: PIXFLUX_MODEL,
          confirmedModel: result.confirmedModel,
          endpoint: PIXFLUX_ENDPOINT,
          cost: result.cost,
          requestCost: result.cost,
          requestedImageSize: cardDefinition.imageSize,
          reference: null,
        },
        outputDirectory,
      );
    }
    if (cardDefinition.id === kethraCitizenCard.id) kethraMaster = result.png;
    process.stdout.write(
      `${reused ? "Reused" : "Generated"} ${cardDefinition.id} (${manifest.assets.length}/12).\n`,
    );
  }
  if (!kethraMaster)
    throw new Error(
      "Kethra citizen master was not generated; refusing walk cycle.",
    );
  const offsetWalkCards = trialWalkCards.map((cardDefinition) =>
    withSeedOffset(
      withSeedOffset(cardDefinition, seedOffset),
      animationSeedOffset,
    ),
  );
  const cycle = await generateWalkCycle(
    kethraMaster,
    offsetWalkCards[0],
    apiKey,
  );
  totals = addUsage(totals, cycle.cost);
  const masterHash = sha256(kethraMaster);
  for (let index = 0; index < offsetWalkCards.length; index += 1) {
    const result = { png: cycle.pngs[index] };
    await writeAsset(
      manifest,
      offsetWalkCards[index],
      result,
      {
        requestedModel: ANIMATION_MODEL,
        confirmedModel: cycle.confirmedModel,
        endpoint: ANIMATION_ENDPOINT,
        ...perFrameProvenance(cycle.cost, trialWalkCards.length),
        requestedImageSize: ANIMATION_IMAGE_SIZE,
        reference: { file: "kethra-citizen.png", sha256: masterHash },
        referencePadding: REFERENCE_PADDING,
      },
      outputDirectory,
    );
    process.stdout.write(
      `Generated ${offsetWalkCards[index].id} (${manifest.assets.length}/12).\n`,
    );
  }
  process.stdout.write(
    `Trial complete: ${manifest.assets.length} assets, $${totals.usd.toFixed(4)} and ${totals.generations} generation credits recorded.\n`,
  );
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main().catch((error) => {
    process.exitCode = 1;
    console.error(error.message);
  });
}

export {
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
  PIXFLUX_MODEL,
  padAnimationReference,
  parseAppearanceRegistry,
  parseUsageMeter,
  perFrameProvenance,
  pixfluxRequestBody,
  pngDimensions,
  pngFromBase64,
  promptVisualClauses,
  registryCommit,
  request,
  requestTimeoutMilliseconds,
  reusableStillAsset,
  seedOffsetFromEnvironment,
  walkCards,
  withSeedOffset,
  writeAsset,
};
