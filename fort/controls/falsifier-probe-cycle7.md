---
key: falsifier-probe-cycle7
status: active
kind: falsifier
detects: "A live capital whose cycle-7 boundaries have drifted"
implements: fort/scripts/probe-cycle7.sh:15
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-29
---
35 pass / 0 fail on the live capital. Tests write-openability with ': >>' so
nothing measured is modified, and CARRIES A POSITIVE CONTROL FOR 'writable' at
:15 (fortkit-52vf.1), which is what makes it a falsifier rather than a tripwire.
fortkit-5aon is open: this exists ONLY in the capital, so two forts cannot run
their own standing mask probe.
