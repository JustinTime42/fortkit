---
key: falsifier-memory-lint
status: active
kind: falsifier
detects: "A fact ledger that has outgrown its per-seat budget or lost provenance"
implements: scripts/memory-lint.mjs:1
falsified-by: fence-verifier
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Wired at verify-impl.sh:311. fortkit-88u.17 is open against it: unscoped core
facts escape counting and unknown seat names mint phantom buckets.
