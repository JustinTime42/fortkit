---
key: falsifier-seat-lint
status: active
kind: falsifier
detects: "Roster claims the seat files no longer support"
implements: scripts/seat-lint.mjs:1
falsified-by: fence-verifier
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
Three rules plus a charter cross-check, run by the verifier in every session of
every fort. Carries the anti-vacuity doctrine at :12-19: zero seat files is a
FAILURE, and a checker that checks nothing must say so as it exits 0.
DOES NOT YET CHECK THE LAURELS SECTION — fortkit-35uf.4 — which is why 'laurel'
sat in the schema with zero emissions for the fort's whole life.
