const hour = 3_600_000;

function open(bead) {
  return bead.status !== "closed";
}
function latestVerdicts(events) {
  const result = new Map();
  for (const event of events) {
    if (event.category !== "review.verdict" || !event.target) continue;
    const previous = result.get(event.target);
    if (!previous || Date.parse(event.ts) >= Date.parse(previous.ts)) {
      result.set(event.target, {
        token: event.payload?.verdict ?? null,
        ts: event.ts,
      });
    }
  }
  return result;
}
function latestDecisions(events) {
  const categories = new Set([
    "gate.approved",
    "gate.declined",
    "decision.recorded",
  ]);
  const result = new Map();
  for (const event of events) {
    if (!categories.has(event.category) || !event.target) continue;
    const previous = result.get(event.target);
    if (!previous || Date.parse(event.ts) >= Date.parse(previous))
      result.set(event.target, event.ts);
  }
  return result;
}
function latestRaisedDecisions(events) {
  const result = new Map();
  for (const event of events) {
    if (event.category !== "decision.raised" || !event.target) continue;
    const previous = result.get(event.target);
    if (!previous || Date.parse(event.ts) >= Date.parse(previous.ts)) {
      result.set(event.target, {
        detail: String(event.detail ?? ""),
        ts: event.ts,
      });
    }
  }
  return result;
}
function liveReviews(events, now) {
  const starts = events.filter(
    (event) =>
      event.category === "session.start" &&
      event.seat === "warden" &&
      Date.parse(event.ts) >= now - hour,
  );
  const ends = events.filter(
    (event) => event.category === "session.end" && event.seat === "warden",
  );
  const live = starts.filter(
    (start) =>
      !ends.some(
        (end) =>
          end.target === start.target &&
          Date.parse(end.ts) >= Date.parse(start.ts),
      ),
  );
  return new Set(live.map((event) => event.target));
}
function workerByBead(workers) {
  return new Map(
    workers
      .filter((worker) => worker.bead)
      .map((worker) => [worker.bead, worker]),
  );
}
function openBlockers(bead, context) {
  return (bead.dependencies ?? []).filter(
    (edge) =>
      edge.type === "blocks" &&
      context.byId.get(edge.depends_on_id)?.status !== "closed",
  );
}
function parentOf(bead) {
  return (
    (bead.dependencies ?? []).find((edge) => edge.type === "parent-child")
      ?.depends_on_id ?? null
  );
}
function ancestors(bead, byId) {
  const result = [];
  const seen = new Set();
  let parent = parentOf(bead);
  while (parent && !seen.has(parent)) {
    result.push(parent);
    seen.add(parent);
    parent = parentOf(byId.get(parent) ?? {});
  }
  return result;
}

// CIV KEEP: waitingLabels is the fort's own "waiting on the Overseer" label set
// (Proofdelve and the Greenlab forts: human; Manyhalls: gate-1/2/3 as well). Every
// use of the literal 'human' below routes through it, so one fort's convention is
// never imposed on another.
function waiting(bead, context) {
  const labels = bead.labels ?? [];
  return (context.waitingLabels ?? ["human"]).some((label) =>
    labels.includes(label),
  );
}

export function graphContext(
  beads,
  events,
  workers,
  now,
  waitingLabels = ["human"],
) {
  return {
    waitingLabels,
    beads,
    byId: new Map(beads.map((bead) => [bead.id, bead])),
    verdicts: latestVerdicts(events),
    decisions: latestDecisions(events),
    raisedDecisions: latestRaisedDecisions(events),
    reviews: liveReviews(events, now),
    workers: workerByBead(workers),
  };
}

export function needsYou(bead, context) {
  if (!open(bead)) return null;
  if (waiting(bead, context)) {
    const raised = context.raisedDecisions.get(bead.id);
    if (
      raised &&
      !(
        Date.parse(context.decisions.get(bead.id) ?? "") > Date.parse(raised.ts)
      )
    ) {
      return { why: `${waitingLabel(bead, context)} label`, ...raised };
    }
    return { why: `${waitingLabel(bead, context)} label` };
  }
  const verdict = context.verdicts.get(bead.id);
  if (
    verdict?.token === "ESCALATE" &&
    !(Date.parse(context.decisions.get(bead.id) ?? "") > Date.parse(verdict.ts))
  ) {
    return { why: "latest review verdict is ESCALATE" };
  }
  return null;
}

function waitingLabel(bead, context) {
  return (
    (context.waitingLabels ?? ["human"]).find((label) =>
      bead.labels?.includes(label),
    ) ?? "human"
  );
}

export function stage(bead, context) {
  if (!open(bead)) return "landed";
  const need = needsYou(bead, context);
  if (need) return "needs-you";
  if (context.reviews.has(bead.id)) return "in-review";
  const worker = context.workers.get(bead.id);
  if (worker?.state === "in-hand") return "verifying";
  if (worker?.state === "running" || worker?.state === "launching")
    return "building";
  const count = openBlockers(bead, context).length;
  if (bead.labels?.includes("fleet-safe") && count === 0) return "ready";
  if (count) return `blocked(${count})`;
  return "waiting";
}

export function graph(
  beads,
  events,
  workers,
  now,
  scope = "frontier",
  closedHours = 24,
  waitingLabels = ["human"],
) {
  const context = graphContext(beads, events, workers, now, waitingLabels);
  const qualifying = new Set(
    beads
      .filter(
        (bead) =>
          open(bead) &&
          (bead.status === "in_progress" ||
            (bead.labels?.includes("fleet-safe") &&
              openBlockers(bead, context).length === 0) ||
            waiting(bead, context) ||
            bead.labels?.includes("fleet-escalated")),
      )
      .map((bead) => bead.id),
  );
  const members = new Set();
  if (scope === "tree")
    beads
      .filter(
        (bead) =>
          open(bead) ||
          Date.parse(bead.closed_at ?? "") >= now - closedHours * hour,
      )
      .forEach((bead) => members.add(bead.id));
  else if (scope === "open")
    beads.filter(open).forEach((bead) => members.add(bead.id));
  else if (scope.startsWith("epic:")) {
    const epic = decodeURIComponent(scope.slice(5));
    beads
      .filter(
        (bead) =>
          bead.id === epic || ancestors(bead, context.byId).includes(epic),
      )
      .forEach((bead) => members.add(bead.id));
  } else {
    for (const bead of beads) {
      const closedRecently =
        !open(bead) &&
        Date.parse(bead.closed_at ?? "") >= now - closedHours * hour;
      const blockedByQualifying =
        open(bead) &&
        (bead.dependencies ?? []).some(
          (edge) =>
            edge.type === "blocks" && qualifying.has(edge.depends_on_id),
        );
      if (qualifying.has(bead.id) || closedRecently || blockedByQualifying)
        members.add(bead.id);
    }
  }
  for (const bead of beads)
    if (members.has(bead.id)) {
      for (const parent of ancestors(bead, context.byId)) members.add(parent);
    }
  const selected = beads.filter((bead) => members.has(bead.id));
  const childrenByParent = new Map();
  for (const bead of beads) {
    const parent = parentOf(bead);
    if (parent)
      childrenByParent.set(parent, [
        ...(childrenByParent.get(parent) ?? []),
        bead.id,
      ]);
  }
  const nodes = selected.map((bead) => ({
    id: bead.id,
    title: bead.title,
    status: bead.status,
    type: bead.issue_type,
    priority: bead.priority,
    labels: bead.labels ?? [],
    stage: stage(bead, context),
    epic: parentOf(bead),
    worker: context.workers.get(bead.id)?.state ?? null,
    verdict: context.verdicts.get(bead.id)?.token ?? null,
    needsYou: needsYou(bead, context),
    assignee: bead.assignee ?? null,
    parent: parentOf(bead),
    children: (childrenByParent.get(bead.id) ?? []).sort((left, right) =>
      left.localeCompare(right),
    ),
    ...(scope === "tree" ? {} : { collapsed: !open(bead) }),
  }));
  const edges = selected.flatMap((bead) =>
    (bead.dependencies ?? [])
      .filter(
        (edge) =>
          edge.type !== "parent-child" && members.has(edge.depends_on_id),
      )
      .map((edge) => ({
        from: edge.depends_on_id,
        to: bead.id,
        type: edge.type,
      })),
  );
  const groups = new Map();
  for (const bead of selected) {
    for (const parent of ancestors(bead, context.byId)) {
      groups.set(parent, [...(groups.get(parent) ?? []), bead.id]);
    }
  }
  const epics = [...groups].map(([id, groupMembers]) => ({
    id,
    title: context.beads.find((bead) => bead.id === id)?.title ?? id,
    members: groupMembers,
  }));
  return { nodes, edges, epics, context };
}

const contextTypes = new Set(["discovered-from", "supersedes", "relates-to"]);

export function signError(status, result) {
  if (status !== 500) return result.error ?? "Signing failed";
  if (result.failed === "outcome-audit") {
    return `applied; outcome line not recorded (completed: ${(result.completed ?? []).join(", ")})`;
  }
  if (result.completed?.includes("audit") && result.failed) {
    return `recorded, not applied (step ${result.failed} failed: ${result.error ?? "Signing failed"}): the Mayor will relay`;
  }
  return `nothing recorded: ${result.error ?? "Signing failed"}`;
}

export function centerOn(
  transform,
  node,
  viewport,
  cardWidth = 220,
  cardHeight = 64,
) {
  const centre = {
    x: node.column * 260 + cardWidth / 2,
    y: node.row * 92 + cardHeight / 2,
  };
  return {
    zoom: transform.zoom,
    x: viewport.width / 2 - centre.x * transform.zoom,
    y: viewport.height / 2 - centre.y * transform.zoom,
  };
}

export function dependencyGroups(bead, byId) {
  const groups = {
    blocks: [],
    blockedBy: [],
    parent: [],
    children: [],
    discoveredFrom: [],
    supersedes: [],
  };
  for (const edge of bead.dependencies ?? []) {
    if (edge.type === "blocks") groups.blockedBy.push(edge.depends_on_id);
    if (edge.type === "parent-child") groups.parent.push(edge.depends_on_id);
    if (edge.type === "discovered-from")
      groups.discoveredFrom.push(edge.depends_on_id);
    if (edge.type === "supersedes") groups.supersedes.push(edge.depends_on_id);
  }
  for (const candidate of byId.values()) {
    for (const edge of candidate.dependencies ?? []) {
      if (edge.depends_on_id !== bead.id) continue;
      if (edge.type === "blocks") groups.blocks.push(candidate.id);
      if (edge.type === "parent-child") groups.children.push(candidate.id);
    }
  }
  for (const ids of Object.values(groups))
    ids.sort((left, right) => left.localeCompare(right));
  return groups;
}

export function stageClass(value) {
  return `stage-${String(value)
    .replace(/\(.+\)/, "")
    .replace(/[^a-z]+/g, "-")}`;
}

export function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[character],
  );
}

export function glyph(type) {
  return escapeHtml(
    { epic: "◆", feature: "◇", bug: "!", gate: "⚑" }[type] ??
      String(type ?? "•"),
  );
}

export function priority(node) {
  return Number.isInteger(node.priority) ? `P${node.priority}` : "?";
}

export function titleLines(value, budget = 30) {
  const title = String(value ?? "");
  if (title.length <= budget) return [title];
  const first = title.slice(0, budget);
  const second = title.slice(budget, budget * 2);
  return [first, `${second}${title.length > budget * 2 ? "…" : ""}`];
}

export function truncate(value, budget) {
  const text = String(value ?? "");
  return text.length <= budget
    ? text
    : `${text.slice(0, Math.max(0, budget - 1))}…`;
}

export function compareNodes(left, right) {
  return (
    (left.priority ?? 99) - (right.priority ?? 99) ||
    left.id.localeCompare(right.id)
  );
}

export function visibleEdges(edges, showContext = false) {
  return edges.filter(
    (edge) =>
      edge.type === "blocks" || (showContext && contextTypes.has(edge.type)),
  );
}

export function searchNodes(nodes, query = "") {
  const needle = query.trim().toLowerCase();
  return nodes.map((node) => ({
    ...node,
    matches:
      !needle || `${node.id} ${node.title}`.toLowerCase().includes(needle),
  }));
}

export function relatedNodeIds(edges, id) {
  const related = new Set([id]);
  for (const edge of edges)
    if (edge.type === "blocks" && (edge.from === id || edge.to === id)) {
      related.add(edge.from);
      related.add(edge.to);
    }
  return related;
}

export function layeredLayout(nodes, edges) {
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const blockers = new Map(nodes.map((node) => [node.id, []]));
  for (const edge of edges)
    if (edge.type === "blocks" && byId.has(edge.from) && byId.has(edge.to)) {
      blockers.get(edge.to).push(edge.from);
    }
  const columns = new Map();
  const visiting = new Set();
  const columnFor = (id) => {
    if (columns.has(id)) return columns.get(id);
    if (visiting.has(id)) return 0;
    visiting.add(id);
    const values = blockers.get(id).map((blocker) => columnFor(blocker) + 1);
    const value = Math.max(0, ...values);
    visiting.delete(id);
    columns.set(id, value);
    return value;
  };
  for (const node of nodes) columnFor(node.id);
  const groups = new Map();
  for (const node of [...nodes].sort(compareNodes)) {
    const column = columns.get(node.id);
    groups.set(column, [...(groups.get(column) ?? []), node]);
  }
  const ordered = new Map(
    [...groups].map(([column, group]) => [column, [...group]]),
  );
  for (const column of [...ordered.keys()].sort((left, right) => left - right))
    if (column > 0) {
      const group = ordered.get(column);
      const prior = ordered.get(column - 1) ?? [];
      const positions = new Map(prior.map((node, index) => [node.id, index]));
      group.sort((left, right) => {
        const average = (node) => {
          const hits = blockers.get(node.id).filter((id) => positions.has(id));
          return hits.length
            ? hits.reduce((sum, id) => sum + positions.get(id), 0) / hits.length
            : Infinity;
        };
        return average(left) - average(right) || compareNodes(left, right);
      });
    }
  const layout = [];
  for (const [column, group] of [...ordered].sort(
    ([left], [right]) => left - right,
  )) {
    group.forEach((node, row) => layout.push({ ...node, column, row }));
  }
  return layout;
}

export function graphOrder(nodes, edges) {
  if (
    nodes.every(
      (node) => Number.isInteger(node.column) && Number.isInteger(node.row),
    )
  ) {
    return [...nodes].sort(
      (left, right) => left.column - right.column || left.row - right.row,
    );
  }
  if (edges) return graphOrder(layeredLayout(nodes, edges));
  return layeredLayout(nodes, []);
}

export function epicRegions(epics, layout, cardWidth = 220, cardHeight = 64) {
  const byId = new Map(layout.map((node) => [node.id, node]));
  return epics
    .map((epic) => {
      const members = epic.members.map((id) => byId.get(id)).filter(Boolean);
      if (!members.length) return null;
      const left = Math.min(...members.map((node) => node.column * 260)) - 12;
      const top = Math.min(...members.map((node) => node.row * 92)) - 28;
      const right =
        Math.max(...members.map((node) => node.column * 260 + cardWidth)) + 12;
      const bottom =
        Math.max(...members.map((node) => node.row * 92 + cardHeight)) + 12;
      return {
        id: epic.id,
        title: epic.title,
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      };
    })
    .filter(Boolean);
}

export function contrastRatio(foreground, background) {
  const luminance = (hex) => {
    const expanded =
      hex.length === 4
        ? `#${[...hex.slice(1)].map((digit) => digit + digit).join("")}`
        : hex;
    const channels = expanded
      .match(/[a-f\d]{2}/gi)
      .map((value) => parseInt(value, 16) / 255)
      .map((value) =>
        value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4,
      );
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
  };
  const values = [luminance(foreground), luminance(background)].sort(
    (left, right) => right - left,
  );
  return (values[0] + 0.05) / (values[1] + 0.05);
}

export function zoomAt(transform, point, factor) {
  const zoom = Math.max(0.28, Math.min(1.25, transform.zoom * factor));
  const scale = zoom / transform.zoom;
  return {
    zoom,
    x: point.x - (point.x - transform.x) * scale,
    y: point.y - (point.y - transform.y) * scale,
  };
}

export function fitTransform(bounds, viewport, padding = 48) {
  const width = Math.max(1, bounds.right - bounds.left);
  const height = Math.max(1, bounds.bottom - bounds.top);
  const zoom = Math.max(
    0.28,
    Math.min(
      1.25,
      (viewport.width - padding) / width,
      (viewport.height - padding) / height,
    ),
  );
  return {
    zoom,
    x: (viewport.width - width * zoom) / 2 - bounds.left * zoom,
    y: (viewport.height - height * zoom) / 2 - bounds.top * zoom,
  };
}
