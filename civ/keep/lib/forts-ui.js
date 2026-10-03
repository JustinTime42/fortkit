// CIV KEEP: the fort picker shared by every page. The choice lives in the URL
// (?fort=<key>) so a view can be bookmarked, and falls back to the last choice
// made in this browser.
import { escapeHtml } from "./graph.mjs";

const storageKey = "civ-keep-fort";
const el = (id) => document.getElementById(id);

export async function fortControls(onChange) {
  const params = new URL(location.href).searchParams;
  let current = params.get("fort") || localStorage.getItem(storageKey) || "all";
  let forts = [];
  const select = el("fort");
  const label = () =>
    current === "all"
      ? "All forts"
      : (forts.find((fort) => fort.key === current)?.name ?? current);
  const choose = (key) => {
    current = key;
    localStorage.setItem(storageKey, key);
    const url = new URL(location.href);
    if (key === "all") url.searchParams.delete("fort");
    else url.searchParams.set("fort", key);
    history.replaceState(null, "", url);
    select.value = key;
    renderStrip();
    onChange(key);
  };
  const renderStrip = () => {
    el("fort-strip").innerHTML = forts
      .map((fort) => {
        const title = `${fort.name} (${fort.civilization}): ${fort.open} open, ${fort.needsYou} need you${fort.halted ? ", fleet HALTED" : ""}${fort.stale ? `, STALE: ${fort.error ?? ""}` : ""}`;
        return `<button class="fort-pill${fort.key === current ? " active" : ""}${fort.stale ? " stale" : ""}" data-fort="${escapeHtml(fort.key)}" title="${escapeHtml(title)}">${escapeHtml(fort.name)}${fort.needsYou ? ` <b class="needs">${fort.needsYou}</b>` : ""}${fort.halted ? ' <span class="halted">halt</span>' : ""}</button>`;
      })
      .join("");
    document.querySelectorAll(".fort-pill").forEach((pill) => {
      pill.addEventListener("click", () =>
        choose(pill.dataset.fort === current ? "all" : pill.dataset.fort),
      );
    });
  };
  const refresh = async () => {
    const response = await fetch("/api/forts");
    if (!response.ok) return;
    forts = await response.json();
    const groups = [...new Set(forts.map((fort) => fort.civilization))];
    select.innerHTML = `<option value="all">All forts</option>${groups
      .map(
        (group) =>
          `<optgroup label="${escapeHtml(group === "Justin" ? "Production" : group)}">${forts
            .filter((fort) => fort.civilization === group)
            .map(
              (fort) =>
                `<option value="${escapeHtml(fort.key)}">${escapeHtml(fort.name)}${fort.needsYou ? ` (${fort.needsYou})` : ""}</option>`,
            )
            .join("")}</optgroup>`,
      )
      .join("")}`;
    if (current !== "all" && !forts.some((fort) => fort.key === current))
      current = "all";
    select.value = current;
    renderStrip();
  };
  select.addEventListener("change", () => choose(select.value));
  await refresh();
  return { current: () => current, label, refresh };
}
