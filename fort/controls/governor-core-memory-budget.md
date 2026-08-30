---
key: governor-core-memory-budget
status: active
kind: governor
refuses: "A seat's core-tier memory exceeding 300 lines or ~30 facts"
implements: scripts/memory-lint.mjs:10
falsified-by: falsifier-memory-lint
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
THE FORT'S ONLY GOVERNOR. Its bound is a measured degradation threshold rather
than a preference. Reported at :270. Its per-seat promise has an open
precondition: docs/specs/memory.md:4.2 records that delivery is NOT scope-filtered,
so a fort can pass per seat while every session receives everything (fortkit-88u.6).
