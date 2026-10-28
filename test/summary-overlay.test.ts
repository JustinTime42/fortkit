import { describe, expect, test } from "vitest";
import {
  createSummaryOverlay,
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

type FakeEvent = {
  target?: FakeNode;
  key?: string;
  shiftKey?: boolean;
  preventDefault?: () => void;
};

class FakeNode {
  listeners = new Map<string, ((event: FakeEvent) => unknown)[]>();
  dataset: Record<string, string> = {};
  textContent = "";
  innerHTML = "";
  open = false;
  disabled = false;
  title = "";
  constructor(
    readonly id: string,
    private readonly doc: FakeDocument,
  ) {}
  addEventListener(type: string, handler: (event: FakeEvent) => unknown) {
    this.listeners.set(type, [...(this.listeners.get(type) ?? []), handler]);
  }
  async fire(type: string, event: FakeEvent = { target: this }) {
    for (const handler of this.listeners.get(type) ?? []) await handler(event);
  }
  focus() {
    this.doc.activeElement = this;
  }
  remove() {
    this.doc.clear();
  }
  querySelectorAll() {
    return [];
  }
  set outerHTML(value: string) {
    this.doc.render(value);
  }
}

class FakeDocument {
  nodes = new Map<string, FakeNode>();
  activeElement: FakeNode | null = null;
  listeners = new Map<string, ((event: FakeEvent) => unknown)[]>();
  body = this;
  querySelector(selector: string) {
    return (
      this.nodes.get(selector.replace(/^#/, "")) ??
      (selector === ".summary-backdrop"
        ? this.nodes.get("backdrop")
        : undefined)
    );
  }
  querySelectorAll(selector: string) {
    return selector === "[data-summary-bead]"
      ? [...this.nodes.values()].filter((node) => node.dataset.summaryBead)
      : [];
  }
  insertAdjacentHTML(_where: string, value: string) {
    this.render(value);
  }
  addEventListener(type: string, handler: (event: FakeEvent) => unknown) {
    this.listeners.set(type, [...(this.listeners.get(type) ?? []), handler]);
  }
  removeEventListener(type: string, handler: (event: FakeEvent) => unknown) {
    this.listeners.set(
      type,
      (this.listeners.get(type) ?? []).filter((item) => item !== handler),
    );
  }
  async fire(type: string, event: FakeEvent) {
    for (const handler of this.listeners.get(type) ?? []) await handler(event);
  }
  clear() {
    this.nodes.clear();
  }
  render(html: string) {
    this.clear();
    for (const id of [...html.matchAll(/id="([^"]+)"/g)].flatMap((match) =>
      match[1] ? [match[1]] : [],
    ))
      this.nodes.set(id, new FakeNode(id, this));
    const backdrop = new FakeNode("backdrop", this);
    backdrop.dataset.summaryClose = "";
    this.nodes.set("backdrop", backdrop);
    for (const id of [...html.matchAll(/data-summary-bead="([^"]+)"/g)].flatMap(
      (match) => (match[1] ? [match[1]] : []),
    )) {
      const node = new FakeNode(`bead-${id}`, this);
      node.dataset.summaryBead = id;
      this.nodes.set(node.id, node);
    }
  }
}

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

  test("links only complete resolved ids and marks numbers without corrupting entities, dates, or times", () => {
    const html = renderSummaryText(
      "fortkit-t7vz.5 xfortkit-t7vzz unknown-a1 a1 ' 39 2026-10-28 12:39",
      ["fortkit-t7vz", "fortkit-t7vz.5", "halls-a1"],
      ["39"],
      ["halls-a1"],
    );
    expect(html).toContain('data-summary-bead="fortkit-t7vz.5"');
    expect(html).not.toContain('data-summary-bead="fortkit-t7vz"');
    expect(html).not.toContain('data-summary-bead="unknown-a1"');
    expect(html).toContain('data-summary-bead="halls-a1">a1</button>');
    expect(html).toContain("&#39;");
    expect(html).toContain(
      '<mark class="summary-unverified" title="not in the supplied facts">39</mark>',
    );
    expect(html).not.toContain(">2026</mark>");
    expect(html).not.toContain(">12</mark>");
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

  test("mounts, closes, opens drawers above the modal, and posts the displayed window end", async () => {
    const doc = new FakeDocument();
    const trigger = new FakeNode("mayor-summary", doc);
    doc.nodes.set("mayor-summary", trigger);
    const calls: { path: string; options?: RequestInit }[] = [];
    const fakeFetch: typeof fetch = async (path, options) => {
      calls.push({ path: String(path), ...(options ? { options } : {}) });
      if (String(path).includes("mark-read"))
        return new Response(JSON.stringify({ upTo: windowEnd }));
      return new Response(
        JSON.stringify({
          latest: { ...latest, beadFacts: [{ id: "halls-a1" }] },
          liveMayor: true,
        }),
      );
    };
    const opened: string[] = [];
    const overlay = createSummaryOverlay({
      openDrawer: (id: string) => opened.push(id),
      getKnownIds: () => ["halls-a1"],
      document: doc,
      root: doc,
      fetchImpl: fakeFetch,
    });
    overlay.setFort("halls", "Halls");
    await trigger.fire("click");
    expect(doc.querySelector(".summary-backdrop")).toBeTruthy();
    const markRead = doc.querySelector("#summary-mark-read");
    expect(markRead).toBeTruthy();
    if (!markRead) throw new Error("mark-read button missing");
    await markRead.fire("click");
    expect(calls.at(-1)?.options?.body).toBe(
      JSON.stringify({ upTo: windowEnd }),
    );
    const bead = doc.querySelectorAll("[data-summary-bead]")[0];
    expect(bead).toBeTruthy();
    if (!bead) throw new Error("bead button missing");
    await bead.fire("click");
    expect(doc.querySelector(".summary-backdrop")).toBeUndefined();
    expect(opened).toEqual(["halls-a1"]);
    await trigger.fire("click");
    await doc.fire("keydown", { key: "Escape" });
    expect(doc.querySelector(".summary-backdrop")).toBeUndefined();
    expect(doc.activeElement).toBe(trigger);
  });
});
