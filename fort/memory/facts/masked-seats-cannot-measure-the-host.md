---
key: masked-seats-cannot-measure-the-host
status: active
superseded-by: null
tier: on-demand
scope:
  seats: [all]
  topics: [seat-sandbox, measurement, codex, evidence]
  beads: [fortkit-elh9, fortkit-52vf.10]
provenance:
  source: "Mayor false measurement 2026-08-13, incident at 09:04:36 in fort/events/events-2026-08-13.jsonl; established from /proc/self/mountinfo; Regent's contradicting host figures in civ/handoffs/regent-2026-08-13T081534.md"
  declared-by: emrith
  date: 2026-08-13
  origin: trusted
---
A masked seat CANNOT measure the host filesystem at any masked path, and the
readings it gets look entirely plausible. `/home/justin/.codex` is a TMPFS to
every claude seat, with `auth.json` the only path re-bound from real disk — so
`ls`, `stat` and `wc -c` inside a Mayor or Warden session describe scratch
created by that session, not the host. On 2026-08-13 the Mayor read mtimes off
that tmpfs, attributed them to the host, and built a rider on an edict from the
correlation; the Regent, running unmasked, measured host mtimes three days and a
month older. Before citing any filesystem observation as evidence, check
`/proc/self/mountinfo` for the path and say WHOSE filesystem the number came
from. Host measurements need an unmasked shell: the Overseer's terminal or the
Regent. See [[cycle13-write-boundaries]] for what else the mask covers.
