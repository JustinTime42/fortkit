---
key: fence-warden-setting-sources
status: active
kind: fence
refuses: "Every permission source except the fort's own profile"
implements: fort/scripts/warden.sh:5
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
--setting-sources '' so warden-settings.json is the ONLY source. Weaker under
Codex, whose -p/--profile LAYERS on the user config rather than replacing it.
