---
key: falsifier-vitest
status: active
kind: falsifier
detects: "Behavioural regressions"
implements: scripts/verify-impl.sh:332
falsified-by: fence-verifier
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
192 tests in 16 files as of 2026-08-29. fortkit-x1n is open: the UTC pinning
test was defanged and has not been restored, so this falsifier has a known hole.
