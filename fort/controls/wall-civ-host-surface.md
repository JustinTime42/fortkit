---
key: wall-civ-host-surface
status: active
kind: wall
refuses: "Writes to bin/, civ/scripts and civ/profiles in the capital"
implements: fort/scripts/lib/seat-sandbox.sh:199
falsified-by: falsifier-probe-cycle7
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Guarded on civ/covenant.md rather than bare existence (Warden suti finding 6),
so an ordinary fort growing its own bin/ does not find it silently read-only.
This is why the factory, bin/fort-init, is Regent work and not Forge work.
