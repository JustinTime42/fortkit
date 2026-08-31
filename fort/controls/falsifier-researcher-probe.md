---
key: falsifier-researcher-probe
status: absent
kind: falsifier
detects: "A Researcher boundary that no longer denies the lr8h action class"
implements: docs/specs/researcher-seat.md:170
falsified-by: null
provenance:
  source: "read from the tree 2026-08-29 during fortkit-4ah3.2; CORRECTED 2026-08-31 after Warden round-1 blocking finding 1(c) on fortkit-4ah3.2"
  declared-by: emrith
  date: 2026-08-31
---
STATUS ABSENT: THIS FORT HAS NO RUNNABLE RESEARCHER BOUNDARY PROBE.

The v1 entry claimed `status: active` and cited `fort/scripts/researcher.sh:70`,
which is the RESEARCH-COMPLETE grep and has nothing to do with a boundary probe.
Both were wrong. The Warden resolved the citation by hand and found no probe in
`scripts/`, `fort/scripts/` or `civ/scripts/`.

WHAT DOES EXIST, and the Mayor found it after her finding: the probe is in the
FACTORY at `templates/fort/scripts/probe-researcher-boundaries.sh`. The capital
ships a Researcher boundary probe to every fort it founds and does not have one
itself — the `fortkit-5aon` shape inverted. Filed as its own bead.

`implements:` now cites §7 of the spec, "The boundary proof", which is the
document of record for the control. The 19 pass / 0 fail (`fortkit-vhk.5.1`) and
the 7 of 8 (`fortkit-vhk.5.2`) are historical one-off measurements recorded in
that spec and in the session record. They are evidence the boundary held ONCE.
They are not a standing control, and nothing re-runs them.

CONSEQUENCE, stated because two other entries depended on it and are now fixed:
this key WAS named as `falsified-by` by `fence-researcher-tool-whitelist` and
`fence-researcher-deny-set`. Those two fences named a falsifier that cannot run,
which is worse than `null` because it reads as covered. **Both are `null` as of
2026-08-31 and neither names this key any more.**

*Written in the present tense until Warden round-3 finding 3, which is the same
defect this entry is about: a condition described as live in one sentence and
repaired in the next, so a reader stopping one sentence early is misled. Tense
is a claim about time, and it drifts exactly as a number does.*
