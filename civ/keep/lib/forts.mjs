// The Civ Keep's fort registry: every fort of every civilization on this host.
//
// Sources are the two registries the factories write: ~/.claude/civilization.json
// (production: Proofdelve, Farlantern, Manyhalls, Kithmason) and
// ~/.claude/greenlab.json (Greenlab: plot, Scionhall). A fort added to either by
// fort-init appears here at the next refresh with no code change.
//
// Two things differ per fort and are decided here, never inferred from a bead:
//
//   waitingLabels  the labels that mean "waiting on the Overseer" in THAT fort.
//                  Proofdelve and the Greenlab forts use `human` (their Mayor seat
//                  file: `gate-ready` is explicitly NOT his queue). Manyhalls uses
//                  gate-1/gate-2/gate-3 (fortkit CLAUDE.md, adopted 2026-08-08).
//   mode           'fleet' when the fort runs fort/scripts/fleet.sh: a signature
//                  follows Proofdelve's desk exactly (an unnoted Approve on a bead
//                  with a bead/<suffix> branch restores fleet-safe with the branch
//                  tip pinned; everything else routes to mayor-review).
//                  'plain' otherwise: there is no fleet to hand work to, so every
//                  signature routes to mayor-review and never adds fleet-safe.
import fs from "node:fs";
import path from "node:path";

const waitingOverrides = { fortkit: ["gate-1", "gate-2", "gate-3", "human"] };

function readRegistry(file, fileSystem) {
  try {
    const value = JSON.parse(fileSystem.readFileSync(file, "utf8"));
    return Array.isArray(value.forts) ? value : null;
  } catch {
    return null;
  }
}

export function slug(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

export function fleetStateFor(fort, home) {
  const fleetScript = path.join(fort.repo, "fort/scripts/fleet.sh");
  return {
    fleetScript,
    stateRoot:
      fort.civilization === "Greenlab"
        ? path.join(home, ".local/state/greenlab", `${fort.project}-fleet`)
        : path.join(home, ".local/state", `${slug(fort.name)}-fleet`),
  };
}

export function loadForts(options = {}) {
  const env = options.env ?? process.env;
  const home = env.HOME ?? "";
  const fileSystem = options.fileSystem ?? fs;
  const registries = options.registries ?? [
    path.join(home, ".claude/civilization.json"),
    path.join(home, ".claude/greenlab.json"),
  ];
  const forts = [];
  for (const file of registries) {
    const registry = readRegistry(file, fileSystem);
    if (!registry) continue;
    for (const entry of registry.forts) {
      if (!entry?.repo || !entry?.project) continue;
      const name = entry.fort_name || entry.project;
      const fort = {
        key: slug(entry.project),
        name,
        project: entry.project,
        civilization: registry.civilization ?? path.basename(file, ".json"),
        repo: entry.repo,
        waitingLabels: waitingOverrides[entry.project] ?? ["human"],
      };
      const { fleetScript, stateRoot } = fleetStateFor(fort, home);
      fort.mode = fileSystem.existsSync(fleetScript) ? "fleet" : "plain";
      fort.fleetState = fort.mode === "fleet" ? stateRoot : null;
      if (!forts.some((other) => other.key === fort.key)) forts.push(fort);
    }
  }
  return forts;
}

// The bead-id prefix of a fort, from its own records: the most common segment
// before the first '-'. bd ids look like `<prefix>-<suffix>` and a suffix may
// itself contain '-' (`plot-merge-slot`), so the FIRST dash is the boundary.
export function prefixOf(beads) {
  const counts = new Map();
  for (const bead of beads) {
    const prefix = String(bead.id ?? "").split("-")[0];
    if (prefix) counts.set(prefix, (counts.get(prefix) ?? 0) + 1);
  }
  return [...counts].sort((left, right) => right[1] - left[1])[0]?.[0] ?? null;
}
