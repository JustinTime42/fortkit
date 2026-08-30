---
key: wall-fort-scripts
status: active
kind: wall
refuses: "Writes to fort/scripts, WHOLE, for every seat type"
implements: fort/scripts/lib/seat-sandbox.sh:386
falsified-by: falsifier-mask-harness
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Cycle 13's correction. The earlier shape carved individual files and left the
DIRECTORY renamable; the harness measured rename=YES, so a seat could move
fort/scripts aside and have a host wrapper exec its replacement unmasked. One
whole-directory bind has no such residual. This is why emit.sh, the launchers
and the probes are all Regent-lane work.
