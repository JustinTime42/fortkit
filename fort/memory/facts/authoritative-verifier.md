---
key: authoritative-verifier
status: active
superseded-by: null
tier: core
scope:
  seats: [all]
  topics: [verification, verify.sh]
  beads: [fortkit-88u.5]
provenance:
  source: "4dc2038:fort/remember.md:7-10; fortkit-88u.5"
  declared-by: kethra
  date: 2026-08-10
  origin: trusted
---
`fort/scripts/verify.sh` is the authoritative verifier. It runs TypeScript,
Biome, Vitest, and ShellCheck; `--no-emit` and `CI` suppress event emission.
