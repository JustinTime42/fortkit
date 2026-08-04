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
  ahead: number | null;
  behind: number | null;
  dirty: boolean | null;
  worktrees: string[] | null;
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
