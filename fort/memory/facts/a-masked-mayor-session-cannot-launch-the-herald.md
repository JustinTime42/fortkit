---
key: a-masked-mayor-session-cannot-launch-the-herald
status: active
superseded-by: null
tier: core
scope:
  seats: [mayor]
  topics: [herald.sh, seat-sandbox, launchers, cross-fort, warden.sh]
  beads: [fortkit-izz, fortkit-wg8w]
provenance:
  source: "bd memory of the same key; verified 2026-08-06 by mount inspection during the r6x.6 maiden-run attempts; cross-fort case measured 2026-08-13 by write probe in Mayor session d"
  declared-by: emrith
  date: 2026-08-13
  origin: trusted
---
A masked Mayor session CANNOT launch the Herald (or any seat that writes
outside the repo): seat-sandbox.sh binds all of $HOME read-only with only the
repo rw, and every spawned process inherits it — herald.sh's vault writes fail
EROFS both inside its nested bwrap and at the launcher's host-side crash stub
(identical with harness sandbox on or off). herald.sh must be launched from an
unmasked shell: the Overseer's terminal, or the H7 systemd user timer. The
Regent's smoke passes only because the Regent runs unmasked.

THE CROSS-FORT CASE IS THE SAME MECHANISM AND IT COSTS A MEASUREMENT EVERY TIME
SOMEONE REDISCOVERS IT (added 2026-08-13). A Manyhalls Mayor CANNOT dispatch
another fort's Warden — not Tova in Proofdelve, not Sereth in Farlantern.
"Only the repo rw" means THIS repo. Measured by write probe rather than
inferred from the mask config: `touch` failed in both /home/justin/dev/ForgeOs
and /home/justin/dev/longburn from a masked Mayor session. A Warden launched
from here inherits the namespace and cannot write her verdict, her transcript,
her fort's event stream, or her `bd comment` — every one of her outputs lands
in the other fort's tree. Cross-fort dispatch is the Overseer's terminal or the
Regent, and the covenant-4.5 reviews owed by elder forts are therefore always
an unmasked act.

THE PLANNING COROLLARY, which is the expensive half: this is why BAND 2 OF THE
PARITY GATE is mostly Regent work. `bin/` is kernel read-only to every masked
seat in the capital, the Forge included (seat-sandbox.sh:187-203, guarded on
`civ/covenant.md`, above the `case "$seat"` at :205 so it binds both branches,
and it reaches the Forge's worktree deliberately). The factory IS
`bin/fort-init`. Before assigning a fort-machinery bead to a lane, check which
FILE it edits against that RO list — the seat that should logically do the work
is frequently not the seat that can. See [[cycle13-write-boundaries]] for the
full boundary table and [[read-the-artifact-remember-the-why]] for why this was
measured rather than recalled.
