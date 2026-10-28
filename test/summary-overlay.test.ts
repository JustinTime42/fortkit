import { describe, expect, test } from "vitest";
import {
  markDisplayedRead,
  renderSummaryOverlay,
  renderSummarySources,
  renderSummaryText,
} from "../civ/keep/lib/summary-overlay.js";

const windowStart = "2026-10-28T00:00:00.000Z";
const windowEnd = "2026-10-28T01:00:00.000Z";
const latest = {
  model: "local-7b",
  generatedAt: "2026-10-28T01:02:00.000Z",
  windowStart,
  windowEnd,
  summary:
    "The <script>alert(1)</script> says halls-a1 has 73 things and <img onerror=boom>.",
  unverifiedNumbers: ["73"],
  factsBlock: {
    waitingOnOverseer: [{ id: "halls-a1", title: "<img onerror=boom>" }],
    escalations: [],
    counts: { closed: 2, filed: 3, merged: 4, halts: 5, verdicts: 6 },
  },
};

describe("Mayor summary overlay renderers", () => {
  test("escapes hostile summary, title, and failure text while linking only known ids", () => {
    const html = renderSummaryOverlay(
      {
        latest,
        lastFailure: { at: windowEnd, reason: "<script>failure</script>" },
      },
      { fortName: "Halls", knownIds: ["halls-a1"] },
    );
    expect(html).toContain("&lt;script&gt;alert(1)&lt;/script&gt;");
    expect(html).toContain("&lt;img onerror=boom&gt;");
    expect(html).toContain("&lt;script&gt;failure&lt;/script&gt;");
    expect(html).toContain('data-summary-bead="halls-a1"');
    expect(html).not.toContain('data-summary-bead="img');
    expect(html).not.toContain("<script>alert");
    expect(
      renderSummarySources([
        { timestamp: windowEnd, text: "<img onerror=boom>" },
      ]),
    ).toContain("&lt;img onerror=boom&gt;");
  });

  test("marks only unverified numbers", () => {
    const html = renderSummaryText("verified 2, unverified 73", [], ["73"]);
    expect(html).toContain(
      '<mark class="summary-unverified" title="not in the supplied facts">73</mark>',
    );
    expect(html).not.toContain(">2</mark>");
  });

  test("renders provenance variants and no-live states", () => {
    const capped = renderSummaryOverlay(
      {
        latest: {
          ...latest,
          windowReason: "read mark capped: last 48 hours",
        },
        running: true,
        liveMayor: null,
      },
      { fortName: "Halls" },
    );
    expect(capped).toContain("window capped at 48 hours");
    expect(capped).toContain("running");
    expect(capped).toContain("No live Mayor session for Halls.");
    const noMark = renderSummaryOverlay(
      { latest: { ...latest, windowReason: "no read mark: last 12 hours" } },
      { fortName: "Halls" },
    );
    expect(noMark).toContain("no read mark: last 12 hours");
    const empty = renderSummaryOverlay(
      { latest: null, liveMayor: null },
      { fortName: "Halls" },
    );
    expect(empty).toContain("No summary yet.");
    expect(empty).toContain('summary-mark-read" disabled');
  });

  test("marks the displayed window end, never the click time", async () => {
    let call: { path?: string; options?: RequestInit | undefined } = {};
    const fakeFetch: typeof fetch = async (path, options) => {
      call = { path: String(path), options };
      return new Response(JSON.stringify({ upTo: windowEnd }), { status: 200 });
    };
    await markDisplayedRead("halls", windowEnd, fakeFetch);
    expect(call.path).toBe("/api/summary/mark-read?fort=halls");
    expect(call.options?.body).toBe(JSON.stringify({ upTo: windowEnd }));
  });
});
