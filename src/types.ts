export type BeadCounts = {
  open: number;
  inProgress: number;
  blocked: number;
  closed: number;
  malformed: number;
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
  assignee: string | null;
};

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
