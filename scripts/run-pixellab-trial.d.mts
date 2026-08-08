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

export function pngFromBase64(encoded: string): Buffer;

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

export const walkCards: Array<{
  id: string;
  prompt: string;
  frameIndex: number;
}>;
export const PIXEN_ENDPOINT: string;
export const ANIMATION_ENDPOINT: string;
