import type { WorldFort } from "./world.ts";

// This checked ES module is composed into a classic browser script. Keep its
// imports type-only: runtime imports or exports would remain in the served JS.

/**
 * Escape text before placing it in HTML generated from fort data.
 */
const esc = (value: unknown) =>
  String(value).replace(/[&<>"']/g, (character) => {
    const replacements: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    };
    return replacements[character] ?? character;
  });

/** Escape all dynamic list content, including headings and class names. */
const list = (title: string, items: string[], className = "") =>
  `<h3>${esc(title)}</h3><ul class="${esc(className)}">${
    items.length
      ? items.map((item) => `<li>${esc(item)}</li>`).join("")
      : '<li class="muted">none</li>'
  }</ul>`;

function card(fort: WorldFort) {
  const git = fort.git.branch || "unavailable";
  const drift =
    fort.git.ahead === null
      ? "unavailable"
      : `ahead ${fort.git.ahead} · behind ${fort.git.behind}`;
  const beads = fort.beads === null ? "ABSENT" : `open ${fort.beads.open}`;
  const active = fort.inProgress.map(
    (bead) =>
      `${bead.id}${bead.title ? ` — ${bead.title}` : ""} [${bead.seat || bead.assignee || "seat unknown"}; ${bead.model || "model unknown"}]`,
  );
  const alerts = fort.watcherAlerts.map(
    (alert) => `${alert.ts} — ${alert.detail}`,
  );
  return `<article class="card"><h2>${esc(fort.name)}</h2><p>${esc(fort.present ? "present" : "ABSENT")}</p><p>Git: ${esc(git)} · ${esc(fort.git.dirty === null ? "state unavailable" : fort.git.dirty ? "dirty" : "clean")} · ${esc(drift)}</p><p>Beads: <strong>${esc(beads)}</strong></p>${list("In progress", active)}${list("Announcements", fort.announcements)}${list("Watcher alerts", alerts, "alert")}${list("Source gaps", fort.gaps, "gap")}</article>`;
}

async function load() {
  try {
    const response = await fetch("/world");
    const data = (await response.json()) as WorldFort[];
    const forts = document.querySelector<HTMLElement>("#forts");
    const updated = document.querySelector<HTMLElement>("#updated");
    if (forts === null || updated === null) return;
    forts.innerHTML =
      data.map(card).join("") || "<p>No registered forts found.</p>";
    updated.textContent = `updated ${new Date().toLocaleTimeString()}`;
  } catch (error) {
    const forts = document.querySelector<HTMLElement>("#forts");
    if (forts !== null) forts.textContent = `World data unavailable: ${error}`;
  }
}

load();
setInterval(load, 5000);
