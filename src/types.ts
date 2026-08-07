export type BeadCounts = {
  open: number;
  ready: number;
  inProgress: number;
  blocked: number;
  closed: number;
  malformed: number;
  schemaGaps: number;
};

export type LastEvent = {
  ts: string;
  actor: string;
  utcDay: string;
};

export type LastHandoff = {
  seat: string;
  date: string;
  title: string | null;
};

export type GitState = {
  branch: string | null;
  ahead: number | null;
  behind: number | null;
  dirty: boolean | null;
  worktrees: string[] | null;
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

export type BeadDependency = {
  issueId: string;
  dependsOnId: string;
  type: string;
  createdAt: string | null;
  createdBy: string | null;
  metadata: string | null;
};

export type BeadStatus = "open" | "in_progress" | "blocked" | "closed";

export type EventDetail = {
  ts: string;
  actor: string;
  seat: string | null;
  category: string | null;
  target: string | null;
  detail: string | null;
  payload: unknown;
};

export type EventFeed = {
  events: EventDetail[];
  malformed: number;
};

export type FortSummary = {
  name: string;
  path: string;
  present: boolean;
  beads: BeadCounts | null;
  lastEvent: LastEvent | null;
  lastHandoff: LastHandoff | null;
  git: GitState;
};

export type RegistryFort = {
  name: string;
  path: string;
};
