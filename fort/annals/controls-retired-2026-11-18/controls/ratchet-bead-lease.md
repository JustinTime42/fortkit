---
key: ratchet-bead-lease
status: active
kind: latch
detects: "A claimed bead whose worker died, returning it to ready"
implements: fort/charter.md:83
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
THE ONLY LATCH THE FORT RELIES ON, AND IT IS BORROWED. Lease expiry belongs to
bd, not to Manyhalls. fortkit-6ps is open for the one we lack: forge.sh has no
concurrency guard, so two launchers can work the same bead in one worktree.
This entry is the evidence on which A1 admitted the latch primitive at all.
