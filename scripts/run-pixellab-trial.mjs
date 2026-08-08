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

import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const OUTPUT_DIRECTORY = fileURLToPath(
  new URL("../assets/trial", import.meta.url),
);
const PIXFLUX_ENDPOINT = "https://api.pixellab.ai/v1/generate-image-pixflux";
const ANIMATION_ENDPOINT = "https://api.pixellab.ai/v1/animate-with-text";
const PIXFLUX_MODEL = "pixflux";
const ANIMATION_MODEL = "animate-with-text";
const ANIMATION_IMAGE_SIZE = { width: 64, height: 64 };
const MAX_SPEND_USD = 15;
const MAX_ESTIMATED_COST_PER_ASSET_USD = 0.02;
const PIXFLUX_REQUEST_TIMEOUT_MS = 30_000;
const ANIMATION_REQUEST_TIMEOUT_MS = 120_000;
const PNG_SIGNATURE = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
]);
const NEGATIVE_CONSTRAINTS =
  "no words, no UI, no watermark, no photorealism, no isometric grid, no extra people";

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
    "dwarven forge master Kethra, leather apron, hammer, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame",
  ),
  card(
    "tavern-master",
    "citizen-master",
    32,
    64,
    42002,
    "dwarven tavern master, apron and tankard, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame",
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

const WALK_DESCRIPTION =
  "dwarven forge master Kethra walking east, leather apron and hammer, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame";

const walkCards = [
  walkCard("kethra-walk-east-01", 43001, 1),
  walkCard("kethra-walk-east-02", 43001, 2),
  walkCard("kethra-walk-east-03", 43001, 3),
  walkCard("kethra-walk-east-04", 43001, 4),
];

function card(id, kind, width, height, seed, subject) {
  return {
    id,
    kind,
    filename: `${id}.png`,
    prompt: `32-bit pixel art, single object or character, orthographic 3/4 exterior, ${subject}, no text, no logo`,
    negativeConstraints: NEGATIVE_CONSTRAINTS,
    seed,
    imageSize: { width, height },
    params: { no_background: true, outline: "selective outline" },
  };
}

function walkCard(id, seed, frameIndex) {
  return {
    id,
    kind: "walk-frame",
    filename: `${id}.png`,
    prompt: WALK_DESCRIPTION,
    frameIndex,
    negativeConstraints: NEGATIVE_CONSTRAINTS,
    seed,
    imageSize: { width: 32, height: 64 },
    params: {
      no_background: true,
      view: "side",
      direction: "east",
      action: "walk",
      n_frames: 4,
    },
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
  return kethraCitizenCard;
}

function requestTimeoutMilliseconds(
  endpoint,
  value = process.env.PIXELLAB_TIMEOUT_MS,
) {
  if (value !== undefined && value !== "") {
    if (!/^\d+$/.test(value) || Number(value) === 0)
      throw new Error("PIXELLAB_TIMEOUT_MS must be a positive integer.");
    const timeout = Number(value);
    if (!Number.isSafeInteger(timeout))
      throw new Error("PIXELLAB_TIMEOUT_MS must be a safe integer.");
    return timeout;
  }
  return endpoint === ANIMATION_ENDPOINT
    ? ANIMATION_REQUEST_TIMEOUT_MS
    : PIXFLUX_REQUEST_TIMEOUT_MS;
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
  return {
    reference_image: {
      type: "base64",
      base64: `data:image/png;base64,${masterPng.toString("base64")}`,
    },
    reference_image_size: { width: 32, height: 64 },
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

function parseUsage(usage, maximumUsd) {
  if (
    typeof usage?.usd !== "number" ||
    !Number.isFinite(usage.usd) ||
    usage.usd < 0 ||
    usage.usd > maximumUsd
  ) {
    throw new Error(
      "Refusing to continue: PixelLab returned unexpected pricing.",
    );
  }
  return usage.usd;
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
    throw new Error("PixelLab returned an invalid PNG image.");
  return {
    width: png.readUInt32BE(16),
    height: png.readUInt32BE(20),
  };
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
  if (!response.ok) {
    const detail =
      response.status >= 400 && response.status < 500
        ? await responseDetail(response, apiKey)
        : "";
    throw new Error(
      `PixelLab request failed with HTTP ${response.status}${detail ? `: ${detail}` : "."}`,
    );
  }
  return response.json();
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
    const rendered =
      typeof detail === "string" ? detail : JSON.stringify(detail);
    return rendered
      .replaceAll(apiKey, "[redacted]")
      .replace(/Bearer\\s+[^\\s"']+/gi, "Bearer [redacted]")
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
    costUsd: parseUsage(response.usage, MAX_ESTIMATED_COST_PER_ASSET_USD),
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
    costUsd: parseUsage(
      response.usage,
      walkCards.length * MAX_ESTIMATED_COST_PER_ASSET_USD,
    ),
    confirmedModel: confirmedModel(response),
  };
}

function sha256(png) {
  return createHash("sha256").update(png).digest("hex");
}

async function writeAsset(manifest, cardDefinition, result, provenance) {
  await writeFile(join(OUTPUT_DIRECTORY, cardDefinition.filename), result.png);
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
    actualImageSize: pngDimensions(result.png),
    generatedAt: new Date().toISOString(),
    costUsd: provenance.costUsd,
    requestCostUsd: provenance.requestCostUsd,
    sha256: sha256(result.png),
    reference: provenance.reference,
  });
  await writeFile(
    join(OUTPUT_DIRECTORY, "provenance-manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );
}

async function main(cardDefinitions = cards) {
  rejectArguments();
  const kethraCitizenCard = assertKethraCitizenCard(cardDefinitions);
  const apiKey = readApiKey();
  const seedOffset = seedOffsetFromEnvironment();
  await mkdir(OUTPUT_DIRECTORY, { recursive: true });
  const manifest = {
    schemaVersion: 3,
    generatedAt: new Date().toISOString(),
    provider: "PixelLab",
    spendCapUsd: MAX_SPEND_USD,
    assets: [],
  };
  let spentUsd = 0;
  let kethraMaster;
  for (const originalCardDefinition of cardDefinitions) {
    const cardDefinition = withSeedOffset(originalCardDefinition, seedOffset);
    const result = await generatePixflux(cardDefinition, apiKey);
    spentUsd += result.costUsd;
    if (spentUsd > MAX_SPEND_USD)
      throw new Error(
        "Refusing to continue: actual trial spend exceeds the $15 cap.",
      );
    await writeAsset(manifest, cardDefinition, result, {
      requestedModel: PIXFLUX_MODEL,
      confirmedModel: result.confirmedModel,
      endpoint: PIXFLUX_ENDPOINT,
      costUsd: result.costUsd,
      requestCostUsd: result.costUsd,
      reference: null,
    });
    if (cardDefinition.id === kethraCitizenCard.id) kethraMaster = result.png;
    process.stdout.write(
      `Generated ${cardDefinition.id} (${manifest.assets.length}/12).\n`,
    );
  }
  if (!kethraMaster)
    throw new Error(
      "Kethra citizen master was not generated; refusing walk cycle.",
    );
  const offsetWalkCards = walkCards.map((cardDefinition) =>
    withSeedOffset(cardDefinition, seedOffset),
  );
  const cycle = await generateWalkCycle(
    kethraMaster,
    offsetWalkCards[0],
    apiKey,
  );
  spentUsd += cycle.costUsd;
  if (spentUsd > MAX_SPEND_USD)
    throw new Error(
      "Refusing to continue: actual trial spend exceeds the $15 cap.",
    );
  const masterHash = sha256(kethraMaster);
  for (let index = 0; index < offsetWalkCards.length; index += 1) {
    const result = { png: cycle.pngs[index] };
    await writeAsset(manifest, offsetWalkCards[index], result, {
      requestedModel: ANIMATION_MODEL,
      confirmedModel: cycle.confirmedModel,
      endpoint: ANIMATION_ENDPOINT,
      costUsd: cycle.costUsd / walkCards.length,
      requestCostUsd: cycle.costUsd,
      reference: { file: "kethra-citizen.png", sha256: masterHash },
    });
    process.stdout.write(
      `Generated ${offsetWalkCards[index].id} (${manifest.assets.length}/12).\n`,
    );
  }
  process.stdout.write(
    `Trial complete: ${manifest.assets.length} assets, $${spentUsd.toFixed(4)} recorded.\n`,
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
  animationRequestBody,
  assertKethraCitizenCard,
  main,
  PIXFLUX_ENDPOINT,
  PIXFLUX_MODEL,
  parseUsage,
  pixfluxRequestBody,
  pngDimensions,
  pngFromBase64,
  request,
  requestTimeoutMilliseconds,
  seedOffsetFromEnvironment,
  walkCards,
  withSeedOffset,
};
