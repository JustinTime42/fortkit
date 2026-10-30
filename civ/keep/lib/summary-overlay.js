// Per-fort Mayor summary overlay. Rendering stays pure so hostile transcript
// and model text can be covered without a browser in the test suite.
import { escapeHtml } from "./graph.mjs";
import { idPattern } from "./id-pattern.js";

const date = (value) =>
  value ? new Date(value).toLocaleString() : "unknown time";
const button = (id, label, extra = "") =>
  `<button type="button" ${id ? `id="${id}"` : ""} ${extra}>${label}</button>`;
const bareCandidate = "[a-z0-9]{2,8}(?:\\.\\d+)*";
const datesAndTimes =
  /\b\d{1,4}(?:[-/:]\d{1,2}){1,2}(?:T\d{1,2}:\d{2}(?::\d{2})?)?\b|\b\d{1,2}:\d{2}(?::\d{2})?\b/g;

const numberIsInDateOrTime = (text, index) => {
  datesAndTimes.lastIndex = 0;
  return [...text.matchAll(datesAndTimes)].some(
    (match) => index >= match.index && index < match.index + match[0].length,
  );
};
const renderPlain = (text, unverified) => {
  let html = "",
    cursor = 0;
  for (const match of text.matchAll(/\d+/g)) {
    html += escapeHtml(text.slice(cursor, match.index));
    const number = match[0];
    html +=
      unverified.has(number) && !numberIsInDateOrTime(text, match.index)
        ? `<mark class="summary-unverified" title="not in the supplied facts">${number}</mark>`
        : escapeHtml(number);
    cursor = match.index + number.length;
  }
  return html + escapeHtml(text.slice(cursor));
};

export function renderSummaryText(
  text = "",
  knownIds = [],
  unverifiedNumbers = [],
  bareIds = [],
) {
  const full = new Set(knownIds.filter((id) => typeof id === "string"));
  const bare = new Map(
    bareIds
      .filter((id) => typeof id === "string")
      .map((id) => [id.slice(id.indexOf("-") + 1), id]),
  );
  const unverified = new Set(unverifiedNumbers.map(String));
  const value = String(text);
  // Keep the full-id grammar tied to the Keep's resolver. The bare form is
  // deliberately narrower because it is only a suffix already resolved by this
  // fort's bead facts.
  const prefixes = [
    ...new Set(
      [...full].map((id) => id.slice(0, id.indexOf("-"))).filter(Boolean),
    ),
  ];
  const fullCandidate = prefixes
    .map((prefix) => `(?:${idPattern(prefix).source.slice(1, -1)}(?<!\\.))`)
    .join("|");
  const beadCandidate = new RegExp(
    `(?<![a-z0-9.-])(?=[a-z0-9.]*[a-z])(?:${fullCandidate || "(?!)"}|${bareCandidate})(?![a-z0-9-]|\\.[a-z0-9])`,
    "gi",
  );
  let html = "",
    cursor = 0;
  for (const match of value.matchAll(beadCandidate)) {
    html += renderPlain(value.slice(cursor, match.index), unverified);
    const candidate = match[0];
    const id = full.has(candidate) ? candidate : bare.get(candidate);
    html += id
      ? `<button type="button" class="summary-bead" data-summary-bead="${escapeHtml(id)}">${escapeHtml(candidate)}</button>`
      : renderPlain(candidate, unverified);
    cursor = match.index + candidate.length;
  }
  return html + renderPlain(value.slice(cursor), unverified);
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
          `<article><time>${escapeHtml(date(source.timestamp))}</time><strong>${escapeHtml(source.speaker ?? "Mayor")}</strong><p>${escapeHtml(source.text)}</p></article>`,
      )
      .join("") || "<p>None.</p>"
  );
}
const factIds = (latest) =>
  [
    ...(latest?.beadFacts ?? []),
    ...(latest?.factsBlock?.waitingOnOverseer ?? []),
    ...(latest?.factsBlock?.escalations ?? []),
  ]
    .map((fact) => fact.id)
    .filter(Boolean);

export function renderSummaryOverlay(data, { fortName, knownIds = [] } = {}) {
  const latest = data.latest;
  const labels = [];
  if (latest) {
    const provider = latest.provider === "claude" ? "Claude" : "Local-model";
    const usage = latest.usage ?? {};
    labels.push(
      `${escapeHtml(provider)} summary, ${escapeHtml(latest.model ?? "unknown model")}, ${escapeHtml(date(latest.generatedAt))}, window ${escapeHtml(date(latest.windowStart))} to ${escapeHtml(date(latest.windowEnd))}, ${escapeHtml(latest.mode ?? "full")}, ${escapeHtml(String(usage.input_tokens ?? 0))} in / ${escapeHtml(String(usage.output_tokens ?? 0))} out`,
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
  const ids = [...new Set([...knownIds, ...factIds(latest)])];
  const content = latest
    ? `${renderSummaryFacts(latest.factsBlock)}<section class="summary-body"><h3>Summary</h3><p>${renderSummaryText(
        latest.summary,
        ids,
        latest.unverifiedNumbers,
        latest.beadFacts?.map((fact) => fact.id),
      )}</p></section>`
    : '<p class="summary-empty">No summary yet.</p>';
  return `<div class="summary-backdrop" data-summary-close><section id="summary-overlay" class="summary-overlay" role="dialog" aria-modal="true" aria-labelledby="summary-title" tabindex="-1"><header><div><h2 id="summary-title">Mayor summary</h2>${labels.length ? `<p class="summary-provenance">${labels.join(" · ")}</p>` : ""}</div>${button("summary-close", "Close", 'aria-label="Close Mayor summary"')}</header>${failure}${live}${content}<div class="summary-actions">${button("summary-regenerate", "Regenerate", data.running ? "disabled" : "")}${button("summary-mark-read", "Mark read", latest ? "" : "disabled")}</div><p id="summary-result" aria-live="polite"></p><details id="summary-sources"><summary>Show the source messages this was built from</summary><div id="summary-source-list"></div></details></section></div>`;
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

export function createSummaryOverlay({
  openDrawer,
  getKnownIds,
  document: documentImpl = document,
  root = documentImpl.body,
  fetchImpl = fetch,
  setTimeoutImpl = setTimeout,
  clearTimeoutImpl = clearTimeout,
}) {
  const find = (selector) => root.querySelector(selector);
  const trigger = find("#mayor-summary");
  let fort = "all",
    fortName = "All forts",
    displayed = null,
    returnFocus = null,
    poll = null,
    keydown = null,
    open = false,
    generation = 0;
  const close = () => {
    open = false;
    generation += 1;
    clearTimeoutImpl(poll);
    if (keydown) documentImpl.removeEventListener("keydown", keydown);
    find(".summary-backdrop")?.remove();
    returnFocus?.focus();
  };
  const request = async (path, options) => {
    const response = await fetchImpl(path, options);
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error ?? `HTTP ${response.status}`);
    return body;
  };
  const preserve = () => {
    const sources = find("#summary-sources");
    return {
      result: find("#summary-result")?.textContent ?? "",
      sourcesOpen: sources?.open,
      sourcesLoaded: sources?.dataset.loaded,
      sourceHtml: find("#summary-source-list")?.innerHTML ?? "",
      focusId: documentImpl.activeElement?.id,
    };
  };
  const mount = (html, previous) => {
    const existing = find(".summary-backdrop");
    if (existing) existing.outerHTML = html;
    else root.insertAdjacentHTML("beforeend", html);
    if (!previous) return;
    find("#summary-result").textContent = previous.result;
    const sources = find("#summary-sources");
    sources.open = previous.sourcesOpen;
    if (previous.sourcesLoaded) sources.dataset.loaded = previous.sourcesLoaded;
    find("#summary-source-list").innerHTML = previous.sourceHtml;
  };
  const restoreFocus = (previous) => {
    const restored = previous?.focusId
      ? documentImpl.getElementById(previous.focusId)
      : null;
    const target =
      restored && !restored.disabled
        ? restored
        : (find("#summary-close") ?? find("#summary-overlay"));
    if (typeof target?.focus === "function") target.focus();
  };
  const wire = () => {
    const overlay = find("#summary-overlay"),
      result = find("#summary-result");
    find("#summary-close").addEventListener("click", close);
    find(".summary-backdrop").addEventListener("click", (event) => {
      if (event.target.dataset.summaryClose !== undefined) close();
    });
    root.querySelectorAll("[data-summary-bead]").forEach((item) => {
      item.addEventListener("click", () => {
        const id = item.dataset.summaryBead;
        close();
        openDrawer(id);
      });
    });
    keydown = (event) => {
      if (!find("#summary-overlay")) return;
      if (event.key === "Escape") return close();
      if (event.key !== "Tab") return;
      const focusable = [
          ...overlay.querySelectorAll(
            "button:not([disabled]), summary, [tabindex]:not([tabindex='-1'])",
          ),
        ],
        first = focusable[0],
        last = focusable.at(-1);
      if (event.shiftKey && documentImpl.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && documentImpl.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    documentImpl.addEventListener("keydown", keydown);
    find("#summary-mark-read").addEventListener("click", async () => {
      try {
        const mark = await markDisplayedRead(
          fort,
          displayed.latest.windowEnd,
          fetchImpl,
        );
        result.textContent = `Marked read up to ${date(mark.upTo)}.`;
      } catch (error) {
        result.textContent = error.message;
      }
    });
    find("#summary-regenerate").addEventListener("click", async () => {
      try {
        await request(
          `/api/summary/regenerate?fort=${encodeURIComponent(fort)}`,
          { method: "POST" },
        );
        await refresh(true);
      } catch (error) {
        result.textContent = error.message;
      }
    });
    find("#summary-sources").addEventListener("toggle", async (event) => {
      if (!event.target.open || event.target.dataset.loaded) return;
      try {
        const sources = await request(
          `/api/summary/sources?fort=${encodeURIComponent(fort)}`,
        );
        find("#summary-source-list").innerHTML = renderSummarySources(sources);
        event.target.dataset.loaded = "true";
      } catch (error) {
        find("#summary-source-list").textContent = error.message;
      }
    });
  };
  const refresh = async (again = false, expectedGeneration = generation) => {
    const previous = preserve();
    displayed = await request(`/api/summary?fort=${encodeURIComponent(fort)}`);
    if (!open || expectedGeneration !== generation) return false;
    if (keydown) documentImpl.removeEventListener("keydown", keydown);
    mount(
      renderSummaryOverlay(displayed, { fortName, knownIds: getKnownIds() }),
      previous,
    );
    wire();
    restoreFocus(previous);
    if (again && displayed.running)
      poll = setTimeoutImpl(async () => {
        try {
          await refresh(true, expectedGeneration);
        } catch (error) {
          if (open && expectedGeneration === generation)
            find("#summary-result").textContent = error.message;
        }
      }, 1000);
    return true;
  };
  trigger.addEventListener("click", async () => {
    if (fort === "all") return;
    returnFocus = trigger;
    open = true;
    generation += 1;
    try {
      if (await refresh(false, generation)) find("#summary-close")?.focus();
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
