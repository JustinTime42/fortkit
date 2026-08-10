---
key: a-masked-mayor-session-cannot-launch-the-herald
status: active
superseded-by: null
tier: core
scope:
  seats: [mayor]
  topics: [herald.sh, seat-sandbox, launchers]
  beads: [fortkit-izz]
provenance:
  source: "bd memory of the same key; verified 2026-08-06 by mount inspection during the r6x.6 maiden-run attempts"
  declared-by: emrith
  date: 2026-08-10
  origin: trusted
---
A masked Mayor session CANNOT launch the Herald (or any seat that writes
outside the repo): seat-sandbox.sh binds all of $HOME read-only with only the
repo rw, and every spawned process inherits it — herald.sh's vault writes fail
EROFS both inside its nested bwrap and at the launcher's host-side crash stub
(identical with harness sandbox on or off). herald.sh must be launched from an
unmasked shell: the Overseer's terminal, or the H7 systemd user timer. The
Regent's smoke passes only because the Regent runs unmasked.
