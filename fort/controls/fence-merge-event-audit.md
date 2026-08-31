---
key: fence-merge-event-audit
status: active
kind: fence
refuses: "A post-backfill main merge with no corresponding merge event"
implements: scripts/merge-event-check.sh:77
falsified-by: null
provenance:
  source: "fortkit-zj8e.7, 2026-08-31"
  declared-by: kethra
  date: 2026-08-31
---
`scripts/merge-event-check.sh` examines every merge on `refs/heads/main` since
the disclosed 2026-08-31 backfill boundary. It requires a `merge` event whose
target names the merge's bead (or whose payload names the commit), reports its
healthy count, and exits non-zero for each missing or unidentifiable match.
It is `inactive` until the Mayor wires it into `scripts/verify-impl.sh`; the
Forge cannot edit that kernel-protected verifier implementation. The wiring
commit must change this status to `active` and re-point this citation to its
`run_step` line.

WIRED 2026-08-31 as verifier stage 11 (`scripts/verify-impl.sh`), Mayor lane —
the Forge is kernel-refused on that file by `seat-sandbox.sh:241`. `status` moved
from `inactive` to `active` in the same commit as the wiring, because an entry
saying `inactive` about a stage that runs is exactly the drift this register
exists to catch.

Four rounds were spent making its red mean ONE thing. Absent `refs/heads/main`
SKIPS and announces — a pull-request checkout is not a missing event — and a
cwd-relative `--git-common-dir` no longer reads as "not a checkout". Both were
verified by probe before wiring, not read off a handoff.
