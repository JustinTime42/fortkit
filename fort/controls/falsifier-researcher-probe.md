---
key: falsifier-researcher-probe
status: active
kind: falsifier
detects: "A Researcher boundary that no longer denies the lr8h action class"
implements: fort/scripts/researcher.sh:70
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
19 pass / 0 fail (fortkit-vhk.5.1); 7 of 8 on 5.2. NOT WIRED INTO THE VERIFIER —
it is a one-off proof rather than a standing control, which is the difference
between having measured a boundary once and knowing it still holds.
