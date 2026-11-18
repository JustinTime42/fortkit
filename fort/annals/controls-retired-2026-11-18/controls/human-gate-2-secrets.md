---
key: human-gate-2-secrets
status: active
kind: prose-gate
refuses: "Any agent access to .env and secrets"
implements: fort/charter.md:14
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
THE POLICY. Mechanisms: wall-secret-file-mask and the profile deny sets. NOT
CO-EXTENSIVE with either: the wall does not descend into directories, and deny
globs bind a spelling. The gate promises more than the mechanisms deliver.
