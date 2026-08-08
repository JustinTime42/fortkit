import { activity, ambientIdFor, fortSeedFor } from "./ambient.ts";
import type { BuildingLayout } from "./colony-layout.ts";
import {
  buildingHeight,
  buildingLayouts,
  buildingWidth,
  homeExtent,
  homeLayout,
} from "./colony-layout.ts";
import type { ColonyProjection } from "./page-types.ts";

// This checked module is composed with colony-layout and ambient into one
// classic browser script. composeColonyPage removes their module syntax; the
// three inlined sources consequently share a scope, so their top-level names
// must not collide. world-page remains independently import-free.

type ActorStyle = { glyph: string; color: string };
type DetailTarget =
  | { kind: "bead"; id: string }
  | { kind: "citizen"; seat: string; activity?: string }
  | { kind: "queue"; name: string; beads: string[] }
  | { kind: "petitions"; name: string; beads: string[] }
  | { kind: "palace"; name: string; seats: string[] };
type Building = BuildingLayout & {
  details: string[];
  targetAt: (index: number) => DetailTarget | undefined;
  summaryTarget?: DetailTarget;
};
type VisibleDetail = { text: string; index: number | undefined };

const detailBaselineOffset = 46;
const detailRowHeight = 13;
const detailRows = 5;
const detailHitStartOffset = detailBaselineOffset - 10;
const detailTextLength = 27;
const citizenGlyphWidth = 15;
const citizenGlyphAscent = 18;
const citizenGlyphDescent = 5;

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

function seatPanel(
  citizen: ColonyProjection["citizens"][number],
  currentActivity: string | null = null,
): string {
  return `<h2>Seat: ${esc(citizen.seat)}</h2>${detailList([
    ["name", citizen.name],
    ["pronouns", citizen.pronouns],
    ["personality", citizen.personality],
    ["activity", currentActivity],
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

function petitionAge(createdAt: string | null): string {
  if (createdAt === null) return "age unknown";
  const timestamp = Date.parse(createdAt);
  if (Number.isNaN(timestamp)) return "age unknown";
  const days = Math.max(0, Math.floor((Date.now() - timestamp) / 86_400_000));
  return days === 1 ? "1 day" : `${days} days`;
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

function homeBuilding(
  citizen: ColonyProjection["citizens"][number],
  index: number,
): Building {
  const layout = homeLayout(index);
  return {
    ...layout,
    name: `${citizen.name}'s HOME`,
    details: [
      "bed",
      citizen.session == null ? "at rest when off duty" : "away at seat",
    ],
    targetAt: () => ({ kind: "citizen", seat: citizen.seat }),
  };
}

function palaceBuilding(
  civicSeats: ColonyProjection["civicSeats"],
): Building | undefined {
  if (!Array.isArray(civicSeats)) return undefined;
  return {
    ...buildingLayouts.palace,
    details:
      civicSeats.length === 0
        ? ["civic roster present, no benches"]
        : civicSeats.map(
            (citizen) =>
              `${citizen.seat} bench — ${citizen.session === null ? "unlit" : `lit: ${citizen.name}`}`,
          ),
    targetAt: (index) => {
      const citizen = civicSeats[index];
      return citizen === undefined
        ? undefined
        : {
            kind: "palace",
            name: buildingLayouts.palace.name,
            seats: [citizen.seat],
          };
    },
    ...(civicSeats.length > detailRows
      ? {
          summaryTarget: {
            kind: "palace" as const,
            name: buildingLayouts.palace.name,
            seats: civicSeats.map((citizen) => citizen.seat),
          },
        }
      : {}),
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
  const palace = palaceBuilding(projection.civicSeats);
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
    {
      ...buildingLayouts.keep,
      details:
        (projection.petitions ?? []).length === 0
          ? ["0 cue(s)"]
          : [
              `${(projection.petitions ?? []).length} cue(s)`,
              ...(projection.petitions ?? []).map((petition) =>
                itemLabel(petition.bead),
              ),
            ],
      targetAt: (index: number): DetailTarget | undefined => {
        if (index === 0)
          return {
            kind: "petitions" as const,
            name: buildingLayouts.keep.name,
            beads: (projection.petitions ?? []).map(
              (petition) => petition.bead.id,
            ),
          };
        const petition = (projection.petitions ?? [])[index - 1];
        return petition === undefined
          ? undefined
          : { kind: "bead" as const, id: petition.bead.id };
      },
      summaryTarget: {
        kind: "petitions" as const,
        name: buildingLayouts.keep.name,
        beads: (projection.petitions ?? []).map((petition) => petition.bead.id),
      },
    },
    beadBuilding(buildingLayouts.dungeon, projection.dungeon),
    {
      ...buildingLayouts.archive,
      details: projection.citizens
        .filter((citizen) => citizen.lastHandoff !== null)
        .map((citizen) => `${citizen.seat}: ${citizen.lastHandoff}`),
      targetAt: () => undefined,
    },
    {
      ...buildingLayouts.tavern,
      details: ["meals · socializing · celebration"],
      targetAt: () => undefined,
    },
    {
      ...buildingLayouts.river,
      details: ["fishing"],
      targetAt: () => undefined,
    },
    {
      ...buildingLayouts["tinker-bench"],
      details: ["idle pursuit: tinkering"],
      targetAt: () => undefined,
    },
    {
      ...buildingLayouts.walls,
      details: ["idle pursuit: walking"],
      targetAt: () => undefined,
    },
    ...(palace === undefined ? [] : [palace]),
    ...projection.citizens.map(homeBuilding),
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

type CitizenPlacement = {
  citizen: ColonyProjection["citizens"][number];
  x: number;
  y: number;
  activity: string;
  place: string;
  idle: boolean;
};

type CitizenMotion = {
  from: Pick<CitizenPlacement, "x" | "y">;
  to: Pick<CitizenPlacement, "x" | "y">;
  startsAt: number;
};

const walkingDurationMilliseconds = 1_200;
const previousPlacements = new Map<string, CitizenPlacement>();
const previousSessionState = new Map<string, boolean>();
const activeMotions = new Map<string, CitizenMotion>();
let animationRequested = false;

function occupantPosition(layout: BuildingLayout, indexWithinPlace: number) {
  return {
    x: layout.x + 22 + (indexWithinPlace % 5) * 34,
    y: layout.y + buildingHeight - 17 - Math.floor(indexWithinPlace / 5) * 24,
  };
}

function placementFor(
  citizen: ColonyProjection["citizens"][number],
  index: number,
  timestamp: number,
  fortSeed: number,
  indexWithinPlace: number = index,
): CitizenPlacement {
  if (citizen.session != null) {
    const seat = citizen.seat.toLocaleLowerCase();
    const layout = buildingLayouts[seat as keyof typeof buildingLayouts];
    // An unknown roster seat still has an honest, stable home fallback rather
    // than vanishing; known seats are always rendered at their fixed building.
    return {
      citizen,
      ...occupantPosition(layout ?? homeLayout(index), indexWithinPlace),
      activity:
        citizen.currentBead === null
          ? "in live session"
          : `working on ${citizen.currentBead}`,
      idle: false,
      place: layout === undefined ? `home:${citizen.name}` : seat,
    };
  }
  const state = activity(ambientIdFor(citizen.name), timestamp, fortSeed);
  const layout = state.place.startsWith("home:")
    ? homeLayout(index)
    : buildingLayouts[
        state.place as Exclude<typeof state.place, `home:${string}`>
      ];
  return {
    citizen,
    ...occupantPosition(layout, indexWithinPlace),
    activity: state.activity,
    place: state.place,
    idle: true,
  };
}

function citizenPlacements(
  projection: ColonyProjection,
  timestamp: number = Date.now(),
  fortSeed: number = fortSeedFor(
    new URLSearchParams(location.search).get("fort") ?? "unknown fort",
  ),
): CitizenPlacement[] {
  const occupantsByPlace = new Map<string, number>();
  return projection.citizens.map((citizen, index) => {
    const destination = placementFor(citizen, index, timestamp, fortSeed);
    const indexWithinPlace = occupantsByPlace.get(destination.place) ?? 0;
    occupantsByPlace.set(destination.place, indexWithinPlace + 1);
    return placementFor(citizen, index, timestamp, fortSeed, indexWithinPlace);
  });
}

function citizenKey(citizen: ColonyProjection["citizens"][number]): string {
  // Seats are the durable colony identity; names remain in the key so a
  // temporarily duplicated or incomplete roster never merges two sprites.
  return `${citizen.seat.toLocaleLowerCase()}\u0000${citizen.name}`;
}

function interpolatedPlacement(
  placement: CitizenPlacement,
  motion: CitizenMotion | undefined,
  timestamp: number,
): CitizenPlacement {
  if (motion === undefined) return placement;
  const progress = Math.min(
    1,
    Math.max(0, (timestamp - motion.startsAt) / walkingDurationMilliseconds),
  );
  return {
    ...placement,
    x: motion.from.x + (motion.to.x - motion.from.x) * progress,
    y: motion.from.y + (motion.to.y - motion.from.y) * progress,
  };
}

/**
 * Keep observed movement entirely client-side. The source and destination are
 * placements from the same layout-driven function used by stationary sprites,
 * so replay timestamps and future layout changes share one coordinate source.
 */
function animatedCitizenPlacements(
  projection: ColonyProjection,
  timestamp: number = Date.now(),
  fortSeed: number = fortSeedFor(
    new URLSearchParams(location.search).get("fort") ?? "unknown fort",
  ),
): CitizenPlacement[] {
  const targets = citizenPlacements(projection, timestamp, fortSeed);
  const visible = targets.map((target, index) => {
    const key = citizenKey(target.citizen);
    const wasInSession = previousSessionState.get(key);
    const isInSession = target.citizen.session !== null;
    const previous = previousPlacements.get(key);
    const existingMotion = activeMotions.get(key);

    if (
      previous !== undefined &&
      wasInSession !== undefined &&
      wasInSession !== isInSession
    ) {
      // Take the current visible position when a second transition arrives
      // mid-walk, avoiding a jump even in a fast replay.
      const from =
        existingMotion === undefined && isInSession
          ? placementFor(
              { ...target.citizen, currentBead: null, session: null },
              index,
              timestamp,
              fortSeed,
            )
          : interpolatedPlacement(previous, existingMotion, timestamp);
      activeMotions.set(key, { from, to: target, startsAt: timestamp });
    }

    previousPlacements.set(key, target);
    previousSessionState.set(key, isInSession);
    const motion = activeMotions.get(key);
    const placement = interpolatedPlacement(target, motion, timestamp);
    if (
      motion !== undefined &&
      timestamp - motion.startsAt >= walkingDurationMilliseconds
    )
      activeMotions.delete(key);
    return placement;
  });

  const currentKeys = new Set(
    targets.map((target) => citizenKey(target.citizen)),
  );
  for (const key of previousPlacements.keys()) {
    if (currentKeys.has(key)) continue;
    previousPlacements.delete(key);
    previousSessionState.delete(key);
    activeMotions.delete(key);
  }
  return visible;
}

function drawCitizen(
  context: CanvasRenderingContext2D,
  placement: CitizenPlacement,
  style: ActorStyle,
) {
  context.save?.();
  context.globalAlpha = placement.idle ? 0.58 : 1;
  context.fillStyle = style.color;
  context.font = "bold 24px monospace";
  context.fillText(style.glyph, placement.x, placement.y);
  context.font = "11px system-ui";
  context.fillText(placement.citizen.name, placement.x - 8, placement.y + 15);
  context.restore?.();
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
    const beads = projection.beads.filter((bead) =>
      target.beads.includes(bead.id),
    );
    return `<h2>${esc(target.name)}</h2><p>${beads.length} bead(s)</p><ul>${beads
      .map((bead) => `<li>${esc(itemLabel(bead))}</li>`)
      .join("")}</ul>`;
  }
  if (target?.kind === "petitions") {
    const petitions = (projection.petitions ?? []).filter((petition) =>
      target.beads.includes(petition.bead.id),
    );
    return `<h2>${esc(target.name)}</h2><p>${petitions.length} live petition(s)</p><ul>${petitions
      .map(
        (petition) =>
          `<li>${esc(itemLabel(petition.bead))} — ${esc(petitionAge(petition.bead.createdAt))} — ${esc(petition.signals.join(", "))}</li>`,
      )
      .join("")}</ul>`;
  }
  if (target?.kind === "palace") {
    const civicSeats = (projection.civicSeats ?? []).filter((citizen) =>
      target.seats.includes(citizen.seat),
    );
    return `<h2>${esc(target.name)}</h2><p>${civicSeats.length} civic bench(es)</p><ul>${civicSeats
      .map(
        (citizen) =>
          `<li>${esc(citizen.seat)} — ${esc(citizen.name)} (${esc(citizen.pronouns)}) — ${citizen.session === null ? "unlit" : `lit: ${esc(citizen.session.actor)}`}</li>`,
      )
      .join("")}</ul>`;
  }
  if (target?.kind === "citizen") {
    const citizen = projection.citizens.find(
      (candidate) => candidate.seat === target.seat,
    );
    return citizen === undefined ? "" : seatPanel(citizen, target.activity);
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

function requestAnimation(projection: ColonyProjection): void {
  if (animationRequested || activeMotions.size === 0) return;
  if (typeof requestAnimationFrame !== "function") return;
  animationRequested = true;
  requestAnimationFrame(() => {
    animationRequested = false;
    render(projection);
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
  canvas.height = homeExtent(projection.citizens.length);
  context.fillStyle = "#17140f";
  context.fillRect(0, 0, canvas.width, canvas.height);
  const buildingList = buildings(projection);
  buildingList.forEach((layout) => {
    building(context, layout);
  });
  const styles = actorStyles(projection);
  const placements = animatedCitizenPlacements(projection);
  placements.forEach((placement) => {
    const style = styles.get(placement.citizen.name);
    if (style === undefined) return;
    drawCitizen(context, placement, style);
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
    const citizen = placements.find(
      (placement) =>
        x >= placement.x &&
        x <= placement.x + citizenGlyphWidth &&
        y >= placement.y - citizenGlyphAscent &&
        y <= placement.y + citizenGlyphDescent,
    );
    selectedTarget =
      citizen === undefined
        ? buildingTarget
        : {
            kind: "citizen",
            seat: citizen.citizen.seat,
            activity: citizen.activity,
          };
    const panelMarkup = selectedPanel(projection, selectedTarget);
    updateDetailPanel(detailPanel, panelMarkup);
  };
  requestAnimation(projection);
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
