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
The run_step harness. Nine stages; any one red fails the run. fort/scripts/verify.sh
is a shim that exits 70 with NOTHING WAS VERIFIED if the implementation is
missing, which is itself a small falsifier over this control.
