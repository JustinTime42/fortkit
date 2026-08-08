export function seedOffsetFromEnvironment(value?: string): number;

export function withSeedOffset<T extends { seed: number }>(
  cardDefinition: T,
  offset: number,
): T;

export function animationRequestBody(
  masterPng: Buffer,
  walkCardDefinition: {
    prompt: string;
    negativeConstraints: string;
    seed: number;
    imageSize: { width: number; height: number };
    params: {
      no_background: boolean;
      view: string;
      direction: string;
      action: string;
      n_frames: number;
    };
  },
): Record<string, unknown>;
export function pixfluxRequestBody(cardDefinition: {
  prompt: string;
  negativeConstraints: string;
  imageSize: { width: number; height: number };
  seed: number;
  params: { no_background: boolean; outline: string };
}): Record<string, unknown>;

export function pngFromBase64(encoded: string): Buffer;
export function pngDimensions(png: Buffer): { width: number; height: number };

export type UsageMeter = {
  meter: "usd" | "generations";
  amount: number;
};

export function parseUsageMeter(
  usage: unknown,
  maximumUsd: number,
  maximumGenerations: number,
): UsageMeter;

export function addUsage(
  totals: { usd: number; generations: number },
  cost: UsageMeter,
): { usd: number; generations: number };

export function perFrameProvenance(
  cost: UsageMeter,
  frameCount: number,
): {
  cost?: UsageMeter;
  amortizedCost?: UsageMeter;
  requestCost: UsageMeter;
};

export function assertKethraCitizenCard<T extends { id: string }>(
  cardDefinitions: T[],
): T;

export function main(cardDefinitions?: Array<{ id: string }>): Promise<void>;

export function requestTimeoutMilliseconds(
  endpoint: string,
  value?: string,
): number;

export function request(
  endpoint: string,
  body: Record<string, unknown>,
  apiKey: string,
): Promise<unknown>;

export function writeAsset(
  manifest: { assets: Array<Record<string, unknown>> },
  cardDefinition: {
    id: string;
    kind: string;
    filename: string;
    imageSize: { width: number; height: number };
    params: Record<string, unknown>;
  },
  result: { png: Buffer },
  provenance: {
    requestedImageSize: { width: number; height: number };
    [key: string]: unknown;
  },
  outputDirectory?: string,
): Promise<void>;

export const walkCards: Array<{
  id: string;
  prompt: string;
  frameIndex: number;
}>;
export const PIXFLUX_ENDPOINT: string;
export const PIXFLUX_MODEL: string;
export const ANIMATION_ENDPOINT: string;
export const ANIMATION_IMAGE_SIZE: { width: number; height: number };
export const MAX_GENERATIONS_PER_STILL_ASSET: number;
export const MAX_GENERATIONS_PER_ANIMATION_CALL: number;
export const MAX_TOTAL_GENERATIONS: number;
export const MANIFEST_SCHEMA_VERSION: number;
