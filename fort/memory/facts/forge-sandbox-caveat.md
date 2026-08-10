---
key: forge-sandbox-caveat
status: active
superseded-by: null
tier: core
scope:
  seats: [forge]
  topics: [forge.sh, sandbox, constitution]
  beads: [fortkit-6jf]
provenance:
  source: "4dc2038:fort/remember.md:17-41; fortkit-6jf"
  declared-by: kethra
  date: 2026-08-10
  origin: trusted
---
Forge runs with a kernel mask. Charter, seats, profiles, and host-executed
scripts are read-only; config-writing Git commands fail inside the mask.
