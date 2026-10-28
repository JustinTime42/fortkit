// Per-fort Mayor summary overlay. Rendering stays pure so hostile transcript
// and model text can be covered without a browser in the test suite.
import { escapeHtml } from "./graph.mjs";

const date = (value) =>
  value ? new Date(value).toLocaleString() : "unknown time";
const button = (id, label, extra = "") =>
  `<button type="button" ${id ? `id="${id}"` : ""} ${extra}>${label}</button>`;

export function renderSummaryText(
  text = "",
  knownIds = [],
  unverifiedNumbers = [],
) {
  const ids = [...new Set(knownIds)].filter((id) => typeof id === "string");
  const pattern = ids.length
    ? new RegExp(
        `(${ids.map((id) => id.replace(/[.*+?^${}()|[\\]\\]/g, "\\$&")).join("|")})`,
        "g",
      )
    : null;
  const mark = new Set(unverifiedNumbers.map(String));
  const renderPlain = (part) =>
    escapeHtml(part).replace(/\d+/g, (number) =>
      mark.has(number)
        ? `<mark class="summary-unverified" title="not in the supplied facts">${number}</mark>`
        : number,
    );
  if (!pattern) return renderPlain(String(text));
  return String(text)
    .split(pattern)
    .map((part) =>
      ids.includes(part)
        ? `<button type="button" class="summary-bead" data-summary-bead="${escapeHtml(part)}">${escapeHtml(part)}</button>`
        : renderPlain(part),
    )
    .join("");
}

const factList = (title, facts = []) =>
  `<section class="summary-facts"><h3>${title}</h3>${facts.length ? `<ul>${facts.map((fact) => `<li><button type="button" class="summary-bead" data-summary-bead="${escapeHtml(fact.id)}">${escapeHtml(fact.id)}</button>${fact.title ? `: ${escapeHtml(fact.title)}` : ""}</li>`).join("")}</ul>` : "<p>None.</p>"}</section>`;

export function renderSummaryFacts(factsBlock = {}) {
  const counts = factsBlock.counts ?? {};
  return `<div class="summary-facts-block">${factList("Waiting on you", factsBlock.waitingOnOverseer)}${factList("Escalated", factsBlock.escalations)}<section class="summary-facts"><h3>Window counts</h3><dl>${["closed", "filed", "merged", "halts", "verdicts"].map((key) => `<div><dt>${key}</dt><dd>${Number.isFinite(counts[key]) ? counts[key] : 0}</dd></div>`).join("")}</dl></section></div>`;
}

export function renderSummarySources(sources = []) {
  return (
    sources
      .map(
        (source) =>
          `<article><time>${escapeHtml(date(source.timestamp))}</time><p>${escapeHtml(source.text)}</p></article>`,
      )
      .join("") || "<p>None.</p>"
  );
}

export function renderSummaryOverlay(data, { fortName, knownIds = [] } = {}) {
  const latest = data.latest;
  const labels = [];
  if (latest) {
    labels.push(
      `Local-model summary, ${escapeHtml(latest.model ?? "unknown model")}, ${escapeHtml(date(latest.generatedAt))}, window ${escapeHtml(date(latest.windowStart))} to ${escapeHtml(date(latest.windowEnd))}`,
    );
    if (latest.windowReason === "no read mark: last 12 hours")
      labels.push("no read mark: last 12 hours");
    if (latest.windowReason === "read mark capped: last 48 hours")
      labels.push("window capped at 48 hours");
  }
  if (data.running) labels.push("running");
  const failure = data.lastFailure
    ? `<p class="summary-failure">Last attempt failed at ${escapeHtml(date(data.lastFailure.at))}: ${escapeHtml(data.lastFailure.reason ?? "unknown failure")}</p>`
    : "";
  const live = data.liveMayor
    ? ""
    : `<p class="summary-no-live">No live Mayor session for ${escapeHtml(fortName ?? data.fort ?? "this fort")}.${latest ? ` Last summary: ${escapeHtml(date(latest.generatedAt))}.` : ""}</p>`;
  const content = latest
    ? `${renderSummaryFacts(latest.factsBlock)}<section class="summary-body"><h3>Summary</h3><p>${renderSummaryText(latest.summary, knownIds, latest.unverifiedNumbers)}</p></section>`
    : '<p class="summary-empty">No summary yet.</p>';
  return `<div class="summary-backdrop" data-summary-close><section id="summary-overlay" class="summary-overlay" role="dialog" aria-modal="true" aria-labelledby="summary-title" tabindex="-1"><header><div><h2 id="summary-title">Mayor summary</h2>${labels.length ? `<p class="summary-provenance">${labels.join(" · ")}</p>` : ""}</div>${button("summary-close", "Close", 'aria-label="Close Mayor summary"')}</header>${failure}${live}${content}<div class="summary-actions">${button("summary-regenerate", "Regenerate", data.running ? "disabled" : "")}${button("summary-mark-read", "Mark read", latest ? "" : "disabled")}</div><p id="summary-result" aria-live="polite"></p><details id="summary-sources"><summary>Show the Mayor's messages this was built from</summary><div id="summary-source-list"></div></details></section></div>`;
}

export async function markDisplayedRead(fort, windowEnd, fetchImpl = fetch) {
  const response = await fetchImpl(
    `/api/summary/mark-read?fort=${encodeURIComponent(fort)}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ upTo: windowEnd }),
    },
  );
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error ?? `HTTP ${response.status}`);
  return body;
}

export function createSummaryOverlay({ openDrawer, getKnownIds }) {
  const trigger = document.getElementById("mayor-summary");
  let fort = "all";
  let fortName = "All forts";
  let displayed = null;
  let returnFocus = null;
  let poll = null;
  let keydown = null;
  const close = () => {
    clearTimeout(poll);
    if (keydown) document.removeEventListener("keydown", keydown);
    document.querySelector(".summary-backdrop")?.remove();
    returnFocus?.focus();
  };
  const request = async (path, options) => {
    const response = await fetch(path, options);
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? `HTTP ${response.status}`);
    return body;
  };
  const wire = () => {
    const overlay = document.getElementById("summary-overlay");
    const result = document.getElementById("summary-result");
    document.getElementById("summary-close").addEventListener("click", close);
    document
      .querySelector(".summary-backdrop")
      .addEventListener("click", (event) => {
        if (event.target.dataset.summaryClose !== undefined) close();
      });
    document.querySelectorAll("[data-summary-bead]").forEach((item) => {
      item.addEventListener("click", () =>
        openDrawer(item.dataset.summaryBead),
      );
    });
    keydown = (event) => {
      if (!document.getElementById("summary-overlay")) return;
      if (event.key === "Escape") return close();
      if (event.key !== "Tab") return;
      const focusable = [
        ...overlay.querySelectorAll(
          "button:not([disabled]), summary, [tabindex]:not([tabindex='-1'])",
        ),
      ];
      const first = focusable[0],
        last = focusable.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", keydown);
    document
      .getElementById("summary-mark-read")
      .addEventListener("click", async () => {
        try {
          const mark = await markDisplayedRead(
            fort,
            displayed.latest.windowEnd,
          );
          result.textContent = `Marked read up to ${date(mark.upTo)}.`;
        } catch (error) {
          result.textContent = error.message;
        }
      });
    document
      .getElementById("summary-regenerate")
      .addEventListener("click", async () => {
        try {
          await request(
            `/api/summary/regenerate?fort=${encodeURIComponent(fort)}`,
            { method: "POST" },
          );
          refresh(true);
        } catch (error) {
          result.textContent = error.message;
        }
      });
    document
      .getElementById("summary-sources")
      .addEventListener("toggle", async (event) => {
        if (!event.target.open || event.target.dataset.loaded) return;
        try {
          const sources = await request(
            `/api/summary/sources?fort=${encodeURIComponent(fort)}`,
          );
          document.getElementById("summary-source-list").innerHTML =
            renderSummarySources(sources);
          event.target.dataset.loaded = "true";
        } catch (error) {
          document.getElementById("summary-source-list").textContent =
            error.message;
        }
      });
  };
  const refresh = async (again = false) => {
    displayed = await request(`/api/summary?fort=${encodeURIComponent(fort)}`);
    if (keydown) document.removeEventListener("keydown", keydown);
    document.querySelector(".summary-backdrop").outerHTML =
      renderSummaryOverlay(displayed, { fortName, knownIds: getKnownIds() });
    wire();
    if (again && displayed.running)
      poll = setTimeout(() => refresh(true), 1000);
  };
  trigger.addEventListener("click", async () => {
    if (fort === "all") return;
    returnFocus = trigger;
    try {
      await refresh();
      document.getElementById("summary-close").focus();
    } catch (error) {
      trigger.title = error.message;
    }
  });
  return {
    setFort(key, name) {
      fort = key;
      fortName = name;
      trigger.disabled = key === "all";
      trigger.title =
        key === "all" ? "Pick a fort: summaries are per fort" : "";
    },
  };
}
