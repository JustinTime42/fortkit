---
key: falsifier-skills-install-check
status: active
kind: falsifier
detects: "Installed skill symlinks that no longer point into this repo"
implements: scripts/verify-impl.sh:328
falsified-by: fence-verifier
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Guards the surface wall-claude-global-instruction protects: ~/.claude/skills is
two symlinks into skills/, which is session-executed instruction.
