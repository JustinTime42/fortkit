import type { ColonyProjection } from "./page-types.ts";

// This checked ES module is composed into a classic browser script. Keep its
// imports type-only: runtime imports or exports would remain in the served JS.

type ActorStyle = { glyph: string; color: string };
type DetailTarget =
  | { kind: "bead"; id: string }
  | { kind: "citizen"; seat: string };
type BuildingLayout = {
  x: number;
  y: number;
  name: string;
  color: string;
};
type Building = BuildingLayout & {
  details: string[];
  targetAt: (index: number) => DetailTarget | undefined;
};

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
const citizenGlyphAscent = 15;

const buildingLayouts = {
  gate: { x: 30, y: 35, name: "GATE", color: "#6b4e2d" },
  depot: { x: 275, y: 35, name: "TRADE DEPOT", color: "#785a2d" },
  archive: { x: 520, y: 35, name: "ARCHIVE", color: "#3b5a63" },
  dungeon: { x: 765, y: 35, name: "DUNGEON", color: "#70404b" },
  workshop: { x: 30, y: 230, name: "WORKSHOP", color: "#48643d" },
} as const satisfies Record<string, BuildingLayout>;
const workshopStride = 265;

let selectedTarget: DetailTarget | undefined;

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

function building(context: CanvasRenderingContext2D, layout: Building) {
  context.fillStyle = layout.color;
  context.fillRect(layout.x, layout.y, buildingWidth, buildingHeight);
  context.strokeStyle = "#e8ddbf";
  context.strokeRect(layout.x, layout.y, buildingWidth, buildingHeight);
  context.fillStyle = "#17140f";
  context.font = "bold 16px system-ui";
  context.fillText(layout.name, layout.x + 10, layout.y + 24);
  context.font = "12px system-ui";
  visibleDetails(layout.details).forEach((detail, index) => {
    context.fillText(
      truncateDetail(detail),
      layout.x + 10,
      layout.y + detailBaselineOffset + index * detailRowHeight,
    );
  });
}

function beadBuilding(
  layout: BuildingLayout,
  beads: ColonyProjection["unassigned"],
): Building {
  return {
    ...layout,
    details: beads.map(label),
    targetAt: (index) => {
      const bead = beads[index];
      return bead === undefined ? undefined : { kind: "bead", id: bead.id };
    },
  };
}

function buildings(projection: ColonyProjection): Building[] {
  return [
    beadBuilding(buildingLayouts.gate, projection.unassigned),
    {
      ...buildingLayouts.depot,
      details: projection.benches.map((bench) =>
        bench.session === null
          ? (bench.worktree.split("/").at(-1) ?? "bench")
          : `${bench.session.actor}: ${bench.session.beadId ?? "working"}`,
      ),
      targetAt: () => undefined,
    },
    {
      ...buildingLayouts.archive,
      details: projection.citizens.map(
        (citizen) => `${citizen.seat}: ${citizen.name}`,
      ),
      targetAt: (index) => {
        const citizen = projection.citizens[index];
        return citizen === undefined
          ? undefined
          : { kind: "citizen", seat: citizen.seat };
      },
    },
    beadBuilding(buildingLayouts.dungeon, projection.dungeon),
    ...projection.workshops.map((workshop, index) =>
      beadBuilding(
        {
          ...buildingLayouts.workshop,
          x: buildingLayouts.workshop.x + index * workshopStride,
          name: `${workshop.type.toUpperCase()} WORKSHOP`,
        },
        workshop.beads,
      ),
    ),
  ];
}

function detailIndex(
  x: number,
  y: number,
  building: Building,
): number | undefined {
  if (
    x < building.x ||
    x > building.x + buildingWidth ||
    y < building.y + detailHitStartOffset ||
    y >= building.y + detailHitStartOffset + detailRows * detailRowHeight
  )
    return undefined;
  const index = Math.floor(
    (y - (building.y + detailHitStartOffset)) / detailRowHeight,
  );
  const visibleTargetCount = Math.min(
    building.details.length,
    building.details.length > detailRows ? detailRows - 1 : detailRows,
  );
  return index < visibleTargetCount ? index : undefined;
}

function detailTargetAt(
  x: number,
  y: number,
  buildingList: Building[],
): DetailTarget | undefined {
  for (const building of buildingList) {
    const index = detailIndex(x, y, building);
    if (index !== undefined) return building.targetAt(index);
  }
  return undefined;
}

function selectedPanel(
  projection: ColonyProjection,
  target: DetailTarget | undefined,
): string {
  if (target?.kind === "bead") {
    const bead = [
      ...projection.unassigned,
      ...projection.dungeon,
      ...projection.workshops.flatMap((workshop) => workshop.beads),
    ].find((candidate) => candidate.id === target.id);
    return bead === undefined ? "" : beadPanel(bead);
  }
  if (target?.kind === "citizen") {
    const citizen = projection.citizens.find(
      (candidate) => candidate.seat === target.seat,
    );
    return citizen === undefined ? "" : seatPanel(citizen);
  }
  return "";
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
  const buildingList = buildings(projection);
  buildingList.forEach((layout) => {
    building(context, layout);
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
  detailPanel.innerHTML = selectedPanel(projection, selectedTarget);
  canvas.onclick = (event) => {
    const bounds = canvas.getBoundingClientRect();
    const x = ((event.clientX - bounds.left) * canvas.width) / bounds.width;
    const y = ((event.clientY - bounds.top) * canvas.height) / bounds.height;
    const buildingTarget = detailTargetAt(x, y, buildingList);
    const citizenRow = Math.floor(
      (y - (citizenStartY - citizenGlyphAscent)) / citizenRowHeight,
    );
    const citizenColumn = Math.floor((x - citizenStartX) / citizenColumnWidth);
    const citizen =
      citizenRow >= 0 &&
      citizenColumn >= 0 &&
      citizenColumn < citizenColumns &&
      y >= citizenStartY - citizenGlyphAscent &&
      y <
        citizenStartY -
          citizenGlyphAscent +
          Math.ceil(projection.citizens.length / citizenColumns) *
            citizenRowHeight
        ? projection.citizens[citizenRow * citizenColumns + citizenColumn]
        : undefined;
    selectedTarget =
      citizen === undefined
        ? buildingTarget
        : { kind: "citizen", seat: citizen.seat };
    detailPanel.innerHTML = selectedPanel(projection, selectedTarget);
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
    const status = document.querySelector<HTMLElement>("#status");
    if (status !== null) status.textContent = "";
  } catch (error) {
    const status = document.querySelector<HTMLElement>("#status");
    if (status !== null)
      status.textContent = `Colony data unavailable: ${error}`;
  }
}

load();
setInterval(load, 5000);
