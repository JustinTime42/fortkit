---
key: falsifier-vitest
status: active
kind: falsifier
detects: "Behavioural regressions"
implements: scripts/verify-impl.sh:341
falsified-by: fence-verifier
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
192 tests in 16 files as of 2026-08-29. `test/control-lint.test.ts` also makes
the register's live census falsifiable: it compares every `control-census`
declaration in `fort/controls/` with `control-lint` output and proves a
deliberate mismatch goes red. fortkit-x1n is open: the UTC pinning test was
defanged and has not been restored, so this falsifier has a known hole.
