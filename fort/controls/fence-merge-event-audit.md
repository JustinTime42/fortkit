---
key: fence-merge-event-audit
status: active
kind: fence
refuses: "A post-backfill main merge with no corresponding merge event"
implements: scripts/merge-event-check.sh:48
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
The Mayor must wire it into `scripts/verify-impl.sh`; the Forge cannot edit
that kernel-protected verifier implementation.
