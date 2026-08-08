#!/usr/bin/env node
/**
 * Run the bounded PixelLab visual trial.
 *
 * Exact invocation (run from the repository root):
 *   PIXELLAB_API_KEY='your PixelLab API key' node scripts/run-pixellab-trial.mjs
 *
 * The key is read only from PIXELLAB_API_KEY. This program accepts no command
 * line arguments, never writes or logs the key, and does not put it in prompts,
 * manifest entries, or request bodies.
 */

import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const OUTPUT_DIRECTORY = resolve("assets/trial");
const ENDPOINT = "https://api.pixellab.ai/v2/create-image-pixen";
const MODEL = "pixen";
const MAX_SPEND_USD = 15;
// A deliberately conservative preflight estimate: twelve requests at $0.02.
const MAX_ESTIMATED_COST_PER_ASSET_USD = 0.02;
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
    "kethra-walk-east-01",
    "walk-frame",
    32,
    64,
    43001,
    "dwarven forge master Kethra walking east, frame 1 of 4, leather apron and hammer, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame",
  ),
  card(
    "kethra-walk-east-02",
    "walk-frame",
    32,
    64,
    43002,
    "dwarven forge master Kethra walking east, frame 2 of 4, leather apron and hammer, same actor as frame 1, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame",
  ),
  card(
    "kethra-walk-east-03",
    "walk-frame",
    32,
    64,
    43003,
    "dwarven forge master Kethra walking east, frame 3 of 4, leather apron and hammer, same actor as frame 1, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame",
  ),
  card(
    "kethra-walk-east-04",
    "walk-frame",
    32,
    64,
    43004,
    "dwarven forge master Kethra walking east, frame 4 of 4, leather apron and hammer, same actor as frame 1, 32 by 48 visible pixels aligned to the bottom of a 32 by 64 transparent frame",
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

function rejectArguments() {
  if (process.argv.length !== 2) {
    throw new Error(
      "This script accepts no arguments. Set PIXELLAB_API_KEY in the environment.",
    );
  }
}

function readApiKey() {
  const key = process.env.PIXELLAB_API_KEY;
  delete process.env.PIXELLAB_API_KEY;
  if (!key) {
    throw new Error("PIXELLAB_API_KEY must be set in the environment.");
  }
  return key;
}

function assertPreflightBudget() {
  const estimatedTotal = cards.length * MAX_ESTIMATED_COST_PER_ASSET_USD;
  if (estimatedTotal > MAX_SPEND_USD) {
    throw new Error(
      "Refusing to run: estimated trial spend exceeds the $15 cap.",
    );
  }
}

function requestBody(cardDefinition) {
  return {
    description: cardDefinition.prompt,
    negative_description: cardDefinition.negativeConstraints,
    image_size: cardDefinition.imageSize,
    no_background: cardDefinition.params.no_background,
    outline: cardDefinition.params.outline,
    seed: cardDefinition.seed,
  };
}

function parseResponse(response) {
  const usage = response.usage;
  if (
    usage?.type !== "usd" ||
    typeof usage.usd !== "number" ||
    !Number.isFinite(usage.usd) ||
    usage.usd < 0 ||
    usage.usd > MAX_ESTIMATED_COST_PER_ASSET_USD
  ) {
    throw new Error(
      "Refusing to continue: PixelLab returned unexpected pricing.",
    );
  }
  const encoded = response.image?.base64;
  if (
    typeof encoded !== "string" ||
    !encoded.startsWith("data:image/png;base64,")
  ) {
    throw new Error("PixelLab returned no PNG image.");
  }
  return {
    costUsd: usage.usd,
    png: Buffer.from(encoded.slice(encoded.indexOf(",") + 1), "base64"),
  };
}

async function generate(cardDefinition, apiKey) {
  const response = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody(cardDefinition)),
  });
  if (!response.ok) {
    throw new Error(`PixelLab request failed with HTTP ${response.status}.`);
  }
  return parseResponse(await response.json());
}

async function main() {
  rejectArguments();
  assertPreflightBudget();
  const apiKey = readApiKey();
  await mkdir(OUTPUT_DIRECTORY, { recursive: true });
  const manifest = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    provider: "PixelLab",
    spendCapUsd: MAX_SPEND_USD,
    assets: [],
  };
  let spentUsd = 0;

  for (const cardDefinition of cards) {
    const result = await generate(cardDefinition, apiKey);
    spentUsd += result.costUsd;
    if (spentUsd > MAX_SPEND_USD) {
      throw new Error(
        "Refusing to continue: actual trial spend exceeds the $15 cap.",
      );
    }
    const outputPath = resolve(OUTPUT_DIRECTORY, cardDefinition.filename);
    await writeFile(outputPath, result.png);
    manifest.assets.push({
      id: cardDefinition.id,
      kind: cardDefinition.kind,
      file: cardDefinition.filename,
      model: MODEL,
      endpoint: ENDPOINT,
      prompt: cardDefinition.prompt,
      negativeConstraints: cardDefinition.negativeConstraints,
      seed: cardDefinition.seed,
      params: { imageSize: cardDefinition.imageSize, ...cardDefinition.params },
      generatedAt: new Date().toISOString(),
      costUsd: result.costUsd,
    });
    await writeFile(
      resolve(OUTPUT_DIRECTORY, "provenance-manifest.json"),
      `${JSON.stringify(manifest, null, 2)}\n`,
    );
    process.stdout.write(
      `Generated ${cardDefinition.id} (${manifest.assets.length}/${cards.length}).\n`,
    );
  }
  process.stdout.write(
    `Trial complete: ${manifest.assets.length} assets, $${spentUsd.toFixed(4)} recorded.\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`, () => {
    process.exitCode = 1;
  });
});
