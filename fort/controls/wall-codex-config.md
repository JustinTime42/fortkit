---
key: wall-codex-config
status: active
kind: wall
refuses: "Writes to ~/.codex/config.toml by either seat type"
implements: fort/scripts/lib/seat-sandbox.sh:331
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Closes the disarm-the-next-launch vector without breaking token rotation.
~/.codex itself is bound live read-write for BOTH seat types because Codex
rotates its token by RENAME; that is the accepted residual fortkit-3jv7.
