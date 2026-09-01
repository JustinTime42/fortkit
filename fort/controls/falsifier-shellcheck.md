---
key: falsifier-shellcheck
status: active
kind: falsifier
detects: "Shell defects across the shipped shell surface"
implements: scripts/verify-impl.sh:354
falsified-by: fence-verifier
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
bin/fort-init, bin/regent, fort/scripts/*.sh, lib, and the template scripts.
