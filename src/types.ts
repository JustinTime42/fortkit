import type {
  Bead,
  BeadDependency,
  BeadStatus,
  GitState,
} from "./page-types.ts";

export type { Bead, BeadDependency, BeadStatus, GitState };

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
  malformedFiles: string[];
};

export type ConstitutionDiffAnnouncement =
  | "announced"
  | "unannounced"
  | "indeterminate";

export type ConstitutionDiff = {
  ts: string;
  hash: string;
  subject: string;
  files: string[];
  beadRefs: string[];
  announced: ConstitutionDiffAnnouncement;
  announcedBeadRef: string | null;
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
