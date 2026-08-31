---
key: fence-researcher-deny-set
status: active
kind: fence
refuses: "Writes and shell escapes at the Researcher's tool layer"
implements: fort/profiles/researcher-settings.json:1
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
11 deny entries. The profile's own text says these are defence in depth only
and that the LAUNCHER'S tool set is the real boundary — see
fence-researcher-tool-whitelist, which is the control that actually holds.
