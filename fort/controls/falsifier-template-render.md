---
key: falsifier-template-render
status: active
kind: falsifier
detects: "Template scripts that no longer render or lint clean"
implements: scripts/verify-impl.sh:355
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
HAS A POSITIVE CONTROL and announces it: '10 template scripts rendered in 3
passes and linted clean; positive control went red as required'. The model the
rest of the fort's falsifiers should follow.
