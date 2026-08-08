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
