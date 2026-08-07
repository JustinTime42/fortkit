import type { ColonyProjection } from "./page-types.ts";

// This checked ES module is composed into a classic browser script. Keep its
// imports type-only: runtime imports or exports would remain in the served JS.

type ActorStyle = { glyph: string; color: string };

const buildingWidth = 210;
const buildingHeight = 112;
const detailBaselineOffset = 46;
const detailRowHeight = 13;
const detailRows = 5;
const detailHitStartOffset = detailBaselineOffset - 10;
const detailTextLength = 27;
const citizenColumns = 6;
const citizenStartX = 48;
const citizenColumnWidth = 170;
const citizenStartY = 530;
const citizenRowHeight = 48;

function esc(value: string): string {
  return value.replace(/[&<>"']/g, (character) => {
    const entities: Record<string, string> = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    };
    return entities[character] ?? character;
  });
}

function display(value: string | number | null): string {
  return value === null ? "unknown" : String(value);
}

function detailList(fields: Array<[string, string | number | null]>): string {
  return `<dl>${fields
    .map(
      ([name, value]) => `<dt>${esc(name)}</dt><dd>${esc(display(value))}</dd>`,
    )
    .join("")}</dl>`;
}

function seatPanel(citizen: ColonyProjection["citizens"][number]): string {
  return `<h2>Seat: ${esc(citizen.seat)}</h2>${detailList([
    ["name", citizen.name],
    ["pronouns", citizen.pronouns],
    ["personality", citizen.personality],
    ["current bead", citizen.currentBead],
    ["last handoff", citizen.lastHandoff],
  ])}`;
}

function beadPanel(bead: ColonyProjection["unassigned"][number]): string {
  const fields: Array<[string, string | number | null]> = [
    ["id", bead.id],
    ["title", bead.title],
    ["description", bead.description],
    ["design", bead.design],
    ["notes", bead.notes],
    ["acceptance criteria", bead.acceptanceCriteria],
    ["status", bead.status],
    ["priority", bead.priority],
    ["type", bead.issueType],
    ["assignee", bead.assignee],
    ["owner", bead.owner],
    ["labels", bead.labels?.join(", ") ?? null],
    ["created", bead.createdAt],
    ["created by", bead.createdBy],
    ["updated", bead.updatedAt],
    ["started", bead.startedAt],
    ["closed", bead.closedAt],
    ["close reason", bead.closeReason],
  ];
  const provenance = (bead.dependencies ?? [])
    .map(
      (edge) =>
        `<li>${esc(edge.type)}: ${esc(edge.issueId)} → ${esc(edge.dependsOnId)}; created ${esc(display(edge.createdAt))} by ${esc(display(edge.createdBy))}; metadata ${esc(display(edge.metadata))}</li>`,
    )
    .join("");
  return `<h2>Bead: ${esc(bead.id)}</h2>${detailList(fields)}<h3>Provenance edges</h3><ul>${provenance || "<li>none</li>"}</ul>`;
}

function actorStyles(projection: ColonyProjection): Map<string, ActorStyle> {
  const actors = [
    ...new Set([
      ...projection.citizens.map((citizen) => citizen.name),
      ...projection.benches.flatMap((bench) =>
        bench.session === null ? [] : [bench.session.actor],
      ),
    ]),
  ].sort();
  return new Map(
    actors.map((actor, index) => [
      actor,
      {
        glyph: index.toString(36).toUpperCase(),
        color: `hsl(${Math.round((index * 360) / Math.max(actors.length, 1))} 72% 68%)`,
      },
    ]),
  );
}

function label(bead: { id: string; title: string | null }): string {
  return bead.title === null ? bead.id : `${bead.id} — ${bead.title}`;
}

function visibleDetails(details: string[]): string[] {
  if (details.length <= detailRows) return details;
  return [
    ...details.slice(0, detailRows - 1),
    `… +${details.length - (detailRows - 1)} more`,
  ];
}

function truncateDetail(detail: string): string {
  return detail.length <= detailTextLength
    ? detail
    : `${detail.slice(0, detailTextLength - 1)}…`;
}

function building(
  context: CanvasRenderingContext2D,
  x: number,
  y: number,
  name: string,
  details: string[],
  color: string,
) {
  context.fillStyle = color;
  context.fillRect(x, y, buildingWidth, buildingHeight);
  context.strokeStyle = "#e8ddbf";
  context.strokeRect(x, y, buildingWidth, buildingHeight);
  context.fillStyle = "#17140f";
  context.font = "bold 16px system-ui";
  context.fillText(name, x + 10, y + 24);
  context.font = "12px system-ui";
  visibleDetails(details).forEach((detail, index) => {
    context.fillText(
      truncateDetail(detail),
      x + 10,
      y + detailBaselineOffset + index * detailRowHeight,
    );
  });
}

function render(projection: ColonyProjection) {
  const canvas = document.querySelector<HTMLCanvasElement>("#colony");
  const ticker = document.querySelector<HTMLElement>("#ticker");
  const gaps = document.querySelector<HTMLElement>("#gaps");
  const detailPanel = document.querySelector<HTMLElement>("#detail-panel");
  const context = canvas?.getContext("2d");
  if (
    canvas === null ||
    ticker === null ||
    gaps === null ||
    detailPanel === null ||
    context === null ||
    context === undefined
  )
    return;
  canvas.height = Math.max(
    620,
    citizenStartY +
      Math.ceil(projection.citizens.length / citizenColumns) *
        citizenRowHeight +
      20,
  );
  context.fillStyle = "#17140f";
  context.fillRect(0, 0, canvas.width, canvas.height);
  building(
    context,
    30,
    35,
    "GATE",
    projection.unassigned.map(label),
    "#6b4e2d",
  );
  building(
    context,
    275,
    35,
    "TRADE DEPOT",
    projection.benches.map((bench) =>
      bench.session === null
        ? (bench.worktree.split("/").at(-1) ?? "bench")
        : `${bench.session.actor}: ${bench.session.beadId ?? "working"}`,
    ),
    "#785a2d",
  );
  building(
    context,
    520,
    35,
    "ARCHIVE",
    projection.citizens.map((citizen) => `${citizen.seat}: ${citizen.name}`),
    "#3b5a63",
  );
  building(
    context,
    765,
    35,
    "DUNGEON",
    projection.dungeon.map(label),
    "#70404b",
  );
  projection.workshops.forEach((workshop, index) => {
    building(
      context,
      30 + index * 265,
      230,
      `${workshop.type.toUpperCase()} WORKSHOP`,
      workshop.beads.map(label),
      "#48643d",
    );
  });
  const styles = actorStyles(projection);
  projection.citizens.forEach((citizen, index) => {
    const style = styles.get(citizen.name);
    if (style === undefined) return;
    const column = index % citizenColumns;
    const row = Math.floor(index / citizenColumns);
    const x = citizenStartX + column * citizenColumnWidth;
    const y = citizenStartY + row * citizenRowHeight;
    context.fillStyle = style.color;
    context.font = "bold 24px monospace";
    context.fillText(style.glyph, x, y);
    context.font = "12px system-ui";
    context.fillText(`${citizen.name} (${citizen.pronouns})`, x, y + 20);
  });
  // The ticker is visual-only: polling must not repeatedly announce it.
  ticker.textContent =
    projection.announcements.length === 0
      ? "No announcements."
      : projection.announcements.join("  •  ");
  gaps.textContent =
    projection.gaps.length === 0
      ? ""
      : `Source gaps: ${projection.gaps.join(" · ")}`;
  canvas.onclick = (event) => {
    const bounds = canvas.getBoundingClientRect();
    const x = ((event.clientX - bounds.left) * canvas.width) / bounds.width;
    const y = ((event.clientY - bounds.top) * canvas.height) / bounds.height;
    const detailIndex = (
      left: number,
      top: number,
      detailCount: number,
    ): number | undefined => {
      if (
        x < left ||
        x > left + buildingWidth ||
        y < top + detailHitStartOffset ||
        y >= top + detailHitStartOffset + detailRows * detailRowHeight
      )
        return undefined;
      const index = Math.floor(
        (y - (top + detailHitStartOffset)) / detailRowHeight,
      );
      const visibleBeadCount = Math.min(
        detailCount,
        detailCount > detailRows ? detailRows - 1 : detailRows,
      );
      return index < visibleBeadCount ? index : undefined;
    };
    const gateIndex = detailIndex(30, 35, projection.unassigned.length);
    const dungeonIndex = detailIndex(765, 35, projection.dungeon.length);
    const workshopIndex = projection.workshops.findIndex(
      (workshop, index) =>
        detailIndex(30 + index * 265, 230, workshop.beads.length) !== undefined,
    );
    const workshopDetailIndex =
      workshopIndex === -1
        ? undefined
        : detailIndex(
            30 + workshopIndex * 265,
            230,
            projection.workshops[workshopIndex]?.beads.length ?? 0,
          );
    const bead =
      gateIndex === undefined
        ? dungeonIndex === undefined
          ? workshopDetailIndex === undefined
            ? undefined
            : projection.workshops[workshopIndex]?.beads[workshopDetailIndex]
          : projection.dungeon[dungeonIndex]
        : projection.unassigned[gateIndex];
    const citizenRow = Math.floor(
      (y - (citizenStartY - 15)) / citizenRowHeight,
    );
    const citizenColumn = Math.floor((x - citizenStartX) / citizenColumnWidth);
    const citizen =
      citizenRow >= 0 &&
      citizenColumn >= 0 &&
      citizenColumn < citizenColumns &&
      y <= canvas.height
        ? projection.citizens[citizenRow * citizenColumns + citizenColumn]
        : undefined;
    detailPanel.innerHTML =
      citizen === undefined
        ? bead === undefined
          ? ""
          : beadPanel(bead)
        : seatPanel(citizen);
  };
}

async function load() {
  const fort = new URLSearchParams(location.search).get("fort");
  if (fort === null) return;
  document.title = `Bartizan — ${fort} colony`;
  const title = document.querySelector<HTMLElement>("#colony-title");
  if (title !== null) title.textContent = `Bartizan — ${fort} colony`;
  try {
    const response = await fetch(`/colony?fort=${encodeURIComponent(fort)}`);
    if (!response.ok) throw new Error("Colony unavailable");
    render((await response.json()) as ColonyProjection);
  } catch (error) {
    const ticker = document.querySelector<HTMLElement>("#ticker");
    if (ticker !== null)
      ticker.textContent = `Colony data unavailable: ${error}`;
  }
}

load();
setInterval(load, 5000);
