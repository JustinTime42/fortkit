// These are the JSON shapes consumed by browser page scripts. Keep this module
// free of Node runtime imports so it remains safe to include in the browser
// typecheck project.
export type GitState = {
  branch: string | null;
  ahead: number | null;
  behind: number | null;
  dirty: boolean | null;
  worktrees: string[] | null;
};

export type BeadStatus = "open" | "in_progress" | "blocked" | "closed";

export type BeadDependency = {
  issueId: string;
  dependsOnId: string;
  type: string;
  createdAt: string | null;
  createdBy: string | null;
  metadata: string | null;
};

export type Bead = {
  id: string;
  title: string | null;
  description: string | null;
  design: string | null;
  notes: string | null;
  acceptanceCriteria: string | null;
  status: BeadStatus;
  priority: number | null;
  issueType: string | null;
  assignee: string | null;
  owner: string | null;
  labels: string[] | null;
  dependencies: BeadDependency[] | null;
  createdAt: string | null;
  createdBy: string | null;
  updatedAt: string | null;
  startedAt: string | null;
  closedAt: string | null;
  closeReason: string | null;
};
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
  personality: string | null;
  currentBead: string | null;
  /** A live session always overrides ambient placement, even without a bead target. */
  session: ColonySession | null;
  lastHandoff: string | null;
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
  /** Every live bead, retained so fixed buildings can render honest queues. */
  beads: Bead[];
  /** Beads explicitly recorded as newly filed in the event stream. */
  intake: Bead[];
  /** The ready/blocked work queue. */
  jobBoard: Bead[];
  /** Beads with a review verdict not followed by a merge event. */
  depot: Bead[];
  workshops: ColonyWorkshop[];
  benches: ColonyBench[];
  dungeon: Bead[];
  citizens: ColonyCitizen[];
  unassigned: Bead[];
  announcements: string[];
  gaps: string[];
};
