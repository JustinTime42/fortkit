---
key: fence-verifier
status: active
kind: fence
refuses: "A bead closing on unverified work"
implements: scripts/verify-impl.sh:101
falsified-by: falsifier-template-render
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
The run_step harness. TEN stages; any one red fails the run. (Nine until
2026-08-31, when `control-lint` was wired in at `fortkit-4ah3.3` and this
sentence was left standing over its edited subject for one commit — Warden
round-2 blocking finding on `fortkit-4ah3.2`. Counted, not incremented:
`grep -c '^run_step ' scripts/verify-impl.sh` returns 10.) fort/scripts/verify.sh
is a shim that exits 70 with NOTHING WAS VERIFIED if the implementation is
missing, which is itself a small falsifier over this control.
