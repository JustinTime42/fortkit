---
key: tripwire-drift-watch
status: active
kind: tripwire
detects: "Files diverging across the three forts and the factory"
implements: civ/scripts/drift-watch.mjs:1
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Runs on fortkit-drift-watch.timer, VERIFIED PRESENT 2026-08-29 by systemctl
--user list-timers. Emits drift.scan (17 in the record) and files beads.
