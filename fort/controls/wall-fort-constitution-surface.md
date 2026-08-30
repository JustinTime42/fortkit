---
key: wall-fort-constitution-surface
status: active
kind: wall
refuses: "Writes to .claude, fort/profiles, .git/config and .git/hooks by any masked seat"
implements: fort/scripts/lib/seat-sandbox.sh:188
falsified-by: falsifier-probe-cycle7
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Cycle 7's core boundary: write access follows execution context. These are the
surfaces a masked seat could use to control the NEXT, possibly unmasked, launch.
