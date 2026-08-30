---
key: wall-claude-config
status: active
kind: wall
refuses: "Writes to ~/.claude settings, CLAUDE.md and helpers by claude seats"
implements: fort/scripts/lib/seat-sandbox.sh:250
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
A session cannot rewrite its own permission rules or the global instructions
for the next one (21f.5).
