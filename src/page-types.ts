import type { Bead, GitState } from "./types.ts";

// These are the JSON shapes consumed by browser page scripts. Keep this module
// free of Node runtime imports so it remains safe to include in the browser
// typecheck project.
export type WorldFort = {
  name: string;
  path: string;
  present: boolean;
  git: GitState;
  beads: { open: number; malformed: number } | null;
  inProgress: Array<Bead & { seat: string | null; model: string | null }>;
  announcements: string[];
  watcherAlerts: Array<{ detail: string; ts: string }>;
  gaps: string[];
};

export type ColonyWorkType = "implementation" | "spec" | "test" | "infra";

export type ColonyCitizen = {
  name: string;
  pronouns: string;
  seat: string;
};

export type ColonySession = {
  actor: string;
  seat: string | null;
  beadId: string | null;
  model: string | null;
  startedAt: string;
};

export type ColonyBench = {
  worktree: string;
  session: ColonySession | null;
};

export type ColonyWorkshop = {
  type: ColonyWorkType;
  beads: Bead[];
};

export type ColonyProjection = {
  workshops: ColonyWorkshop[];
  benches: ColonyBench[];
  dungeon: Bead[];
  citizens: ColonyCitizen[];
  unassigned: Bead[];
  gaps: string[];
};
