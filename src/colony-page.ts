import type { ColonyProjection } from "./page-types.ts";

// This checked ES module is composed into a classic browser script. Keep its
// imports type-only: runtime imports or exports would remain in the served JS.

type ActorStyle = { glyph: string; color: string };
type DetailTarget =
  | { kind: "bead"; id: string }
  | { kind: "citizen"; seat: string }
  | { kind: "queue"; name: string; beads: string[] };
type BuildingLayout = {
  x: number;
  y: number;
  name: string;
  color: string;
  rendered?: boolean;
};
type Building = BuildingLayout & {
  details: string[];
  targetAt: (index: number) => DetailTarget | undefined;
  summaryTarget?: DetailTarget;
};
type VisibleDetail = { text: string; index: number | undefined };

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
const buildingStartX = 30;
const buildingStride = 245;

// The living fort's stable geometry. Places reserved for later districts stay
// in this one table so ambient destinations cannot drift from the map.
const buildingLayouts = {
  mayor: {
    x: buildingStartX,
    y: 35,
    name: "MAYOR'S OFFICE",
    color: "#6b4e2d",
  },
  forge: {
    x: buildingStartX + buildingStride,
    y: 35,
    name: "THE FORGE",
    color: "#48643d",
  },
  warden: {
    x: buildingStartX + buildingStride * 2,
    y: 35,
    name: "WARDEN'S TOWER",
    color: "#3b5a63",
  },
  gate: {
    x: buildingStartX + buildingStride * 3,
    y: 35,
    name: "THE GATE",
    color: "#6b4e2d",
  },
  jobBoard: {
    x: buildingStartX,
    y: 205,
    name: "THE JOB BOARD",
    color: "#785a2d",
  },
  depot: {
    x: buildingStartX + buildingStride,
    y: 205,
    name: "TRADE DEPOT",
    color: "#785a2d",
  },
  dungeon: {
    x: buildingStartX + buildingStride * 2,
    y: 205,
    name: "THE DUNGEON",
    color: "#70404b",
  },
  archive: {
    x: buildingStartX + buildingStride * 3,
    y: 205,
    name: "THE ARCHIVE",
    color: "#3b5a63",
  },
  tavern: {
    x: buildingStartX,
    y: 375,
    name: "THE TAVERN",
    color: "#6c4c2a",
    rendered: false,
  },
  walls: {
    x: buildingStartX + buildingStride,
    y: 375,
    name: "WALLS",
    color: "#5c554a",
    rendered: false,
  },
} as const satisfies Record<string, BuildingLayout>;

let selectedTarget: DetailTarget | undefined;
let previousPanelMarkup: string | undefined;
let previousStatusText: string | undefined;

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

function itemLabel(
  bead: Pick<
    ColonyProjection["beads"][number],
    "id" | "title" | "issueType" | "labels"
  >,
): string {
  const glyph =
    bead.issueType === "bug"
      ? "☠"
      : bead.labels?.includes("implementation")
        ? "⚒"
        : bead.labels?.includes("spec")
          ? "✎"
          : bead.labels?.includes("test")
            ? "✓"
            : bead.labels?.includes("infra")
              ? "⚙"
              : "□ crate";
  return `${glyph} ${label(bead)}`;
}

function visibleDetails(details: string[]): VisibleDetail[] {
  if (details.length <= detailRows)
    return details.map((text, index) => ({ text, index }));
  return [
    ...details.slice(0, detailRows - 1).map((text, index) => ({ text, index })),
    { text: `… +${details.length - (detailRows - 1)} more`, index: undefined },
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
      truncateDetail(detail.text),
      layout.x + 10,
      layout.y + detailBaselineOffset + index * detailRowHeight,
    );
  });
}

function beadBuilding(
  layout: BuildingLayout,
  beads: ColonyProjection["beads"],
): Building {
  return {
    ...layout,
    details: beads.length === 0 ? ["none recorded"] : beads.map(itemLabel),
    targetAt: (index) => {
      const bead = beads[index];
      return bead === undefined ? undefined : { kind: "bead", id: bead.id };
    },
    ...(beads.length > detailRows
      ? {
          summaryTarget: {
            kind: "queue" as const,
            name: layout.name,
            beads: beads.map((bead) => bead.id),
          },
        }
      : {}),
  };
}

function seatBuilding(
  layout: BuildingLayout,
  citizens: ColonyProjection["citizens"],
): Building {
  return {
    ...layout,
    details:
      citizens.length === 0
        ? ["seat roster unavailable"]
        : citizens.map(
            (citizen) =>
              `${citizen.name}${citizen.currentBead === null ? " — idle" : ` — ${citizen.currentBead}`}`,
          ),
    targetAt: (index) => {
      const citizen = citizens[index];
      return citizen === undefined
        ? undefined
        : { kind: "citizen", seat: citizen.seat };
    },
  };
}

function buildings(projection: ColonyProjection): Building[] {
  const beads = projection.beads ?? [
    ...projection.unassigned,
    ...projection.dungeon,
    ...projection.workshops.flatMap((workshop) => workshop.beads),
  ];
  const mayor = projection.citizens.filter(
    (citizen) => citizen.seat.toLocaleLowerCase() === "mayor",
  );
  const warden = projection.citizens.filter(
    (citizen) => citizen.seat.toLocaleLowerCase() === "warden",
  );
  const intake = projection.intake ?? projection.unassigned;
  const jobBoard = projection.jobBoard ?? projection.unassigned;
  const depot = projection.depot ?? [];
  return [
    seatBuilding(buildingLayouts.mayor, mayor),
    {
      ...buildingLayouts.forge,
      details: projection.benches.map((bench) =>
        bench.session === null
          ? `empty bench — ${bench.worktree.split("/").at(-1) ?? "bench"}`
          : `${bench.session.actor}: ${itemLabel(beads.find((bead) => bead.id === bench.session?.beadId) ?? { id: bench.session.beadId ?? "working", title: null, issueType: null, labels: null })}`,
      ),
      targetAt: () => undefined,
    },
    seatBuilding(buildingLayouts.warden, warden),
    beadBuilding(buildingLayouts.gate, intake),
    beadBuilding(buildingLayouts.jobBoard, jobBoard),
    beadBuilding(buildingLayouts.depot, depot),
    beadBuilding(buildingLayouts.dungeon, projection.dungeon),
    {
      ...buildingLayouts.archive,
      details: projection.citizens
        .filter((citizen) => citizen.lastHandoff !== null)
        .map((citizen) => `${citizen.seat}: ${citizen.lastHandoff}`),
      targetAt: () => undefined,
    },
  ].map((building) => {
    if (building.name !== buildingLayouts.archive.name) return building;
    const archiveCitizens = projection.citizens.filter(
      (citizen) => citizen.lastHandoff !== null,
    );
    return {
      ...building,
      details:
        building.details.length === 0
          ? ["no handoffs recorded"]
          : building.details,
      targetAt: (index) => {
        const citizen = archiveCitizens[index];
        return citizen === undefined
          ? undefined
          : { kind: "citizen", seat: citizen.seat };
      },
    };
  });
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
  return visibleDetails(building.details)[index]?.index;
}

function detailTargetAt(
  x: number,
  y: number,
  buildingList: Building[],
): DetailTarget | undefined {
  for (const building of buildingList) {
    const index = detailIndex(x, y, building);
    if (index !== undefined) return building.targetAt(index);
    if (
      building.summaryTarget !== undefined &&
      x >= building.x &&
      x <= building.x + buildingWidth &&
      y >= building.y + detailHitStartOffset &&
      y < building.y + detailHitStartOffset + detailRows * detailRowHeight
    )
      return building.summaryTarget;
  }
  return undefined;
}

function selectedPanel(
  projection: ColonyProjection,
  target: DetailTarget | undefined,
): string {
  if (target?.kind === "bead") {
    const bead = (
      projection.beads ?? [
        ...projection.unassigned,
        ...projection.dungeon,
        ...projection.workshops.flatMap((workshop) => workshop.beads),
      ]
    ).find((candidate) => candidate.id === target.id);
    return bead === undefined ? "" : beadPanel(bead);
  }
  if (target?.kind === "queue") {
    const beads = (projection.beads ?? []).filter((bead) =>
      target.beads.includes(bead.id),
    );
    return `<h2>${esc(target.name)}</h2><p>${beads.length} live item(s)</p><ul>${beads.map((bead) => `<li>${esc(itemLabel(bead))}</li>`).join("")}</ul>`;
  }
  if (target?.kind === "citizen") {
    const citizen = projection.citizens.find(
      (candidate) => candidate.seat === target.seat,
    );
    return citizen === undefined ? "" : seatPanel(citizen);
  }
  return "";
}

function updateDetailPanel(panel: HTMLElement, markup: string): void {
  if (previousPanelMarkup === markup) return;
  panel.innerHTML = markup;
  previousPanelMarkup = markup;
}

function updateStatus(status: HTMLElement, text: string): void {
  if (previousStatusText === text) return;
  status.textContent = text;
  previousStatusText = text;
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
  const panelMarkup = selectedPanel(projection, selectedTarget);
  updateDetailPanel(detailPanel, panelMarkup);
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
    const panelMarkup = selectedPanel(projection, selectedTarget);
    updateDetailPanel(detailPanel, panelMarkup);
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
    if (status !== null) updateStatus(status, "");
  } catch (error) {
    const status = document.querySelector<HTMLElement>("#status");
    if (status !== null)
      updateStatus(status, `Colony data unavailable: ${error}`);
  }
}

load();
setInterval(load, 5000);
