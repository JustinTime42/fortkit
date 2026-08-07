import type { ColonyProjection } from "./page-types.ts";

type ActorStyle = { glyph: string; color: string };

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

function building(
  context: CanvasRenderingContext2D,
  x: number,
  y: number,
  name: string,
  details: string[],
  color: string,
) {
  context.fillStyle = color;
  context.fillRect(x, y, 210, 112);
  context.strokeStyle = "#e8ddbf";
  context.strokeRect(x, y, 210, 112);
  context.fillStyle = "#17140f";
  context.font = "bold 16px system-ui";
  context.fillText(name, x + 10, y + 24);
  context.font = "12px system-ui";
  details.slice(0, 5).forEach((detail, index) => {
    context.fillText(detail.slice(0, 27), x + 10, y + 46 + index * 13);
  });
}

function render(projection: ColonyProjection) {
  const canvas = document.querySelector<HTMLCanvasElement>("#colony");
  const ticker = document.querySelector<HTMLElement>("#ticker");
  const gaps = document.querySelector<HTMLElement>("#gaps");
  const context = canvas?.getContext("2d");
  if (canvas === null || ticker === null || gaps === null || context == null)
    return;
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
    context.fillStyle = style.color;
    context.font = "bold 24px monospace";
    context.fillText(style.glyph, 48 + index * 170, 530);
    context.font = "12px system-ui";
    context.fillText(
      `${citizen.name} (${citizen.pronouns})`,
      48 + index * 170,
      550,
    );
  });
  ticker.textContent =
    projection.announcements.length === 0
      ? "No announcements."
      : projection.announcements.join("  •  ");
  gaps.textContent =
    projection.gaps.length === 0
      ? ""
      : `Source gaps: ${projection.gaps.join(" · ")}`;
}

async function load() {
  const fort = new URLSearchParams(location.search).get("fort");
  if (fort === null) return;
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
