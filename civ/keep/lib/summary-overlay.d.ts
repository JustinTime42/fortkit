export function renderSummaryText(
  text: string,
  knownIds?: string[],
  unverifiedNumbers?: string[],
): string;
export function renderSummaryFacts(factsBlock?: object): string;
export function renderSummarySources(sources?: object[]): string;
export function renderSummaryOverlay(data: object, options?: object): string;
export function markDisplayedRead(
  fort: string,
  windowEnd: string,
  fetchImpl?: typeof fetch,
): Promise<{ upTo?: string }>;
export function createSummaryOverlay(options: object): {
  setFort(key: string, name: string): void;
};
