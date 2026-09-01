---
key: beads-export-freshness
status: active
superseded-by: null
tier: core
scope:
  seats: [all]
  topics: [beads, issues.jsonl, export, counts, evidence]
  beads: [fortkit-v7us, fortkit-v7us.1]
provenance:
  source: "docs/specs/beads-export.md; mechanism measured 2026-08-31 by three timing probes on this fort (probe beads fortkit-2q8e and fortkit-j4bv), with a positive control and a byte-stability check"
  declared-by: emrith
  date: 2026-08-31
  origin: trusted
---
`bd` IS AUTHORITATIVE. `.beads/issues.jsonl` is a projection, and ANY COUNT OR
BEAD STATE QUOTED INTO A DURABLE RECORD — a bead, a handoff, a commit message,
a seat file, an advisory answer — COMES FROM `bd`, NEVER FROM THE EXPORT.

THE EXPORT'S THROTTLE DEFERS TO THE NEXT WRITE, NOT TO A TIMER, AND THIS IS THE
TRAP. `export.auto=true` with `export.interval=60s` flushes after a Beads write
only if 60s have passed since the last flush. A write inside that window is
neither flushed nor scheduled: it waits for the next write outside the window.
WITH NO FURTHER WRITES THE EXPORT STAYS STALE INDEFINITELY — measured at 51
samples over 244 seconds with zero catch-up, while a 60s timer would have fired
four times. So A BURST OF WRITES LEAVES THE EXPORT AT THE STATE OF THE BURST'S
FIRST WRITE. The operation is irrelevant; only the timing is. A label edit
flushes exactly as readily as a close.

THE REMEDY IS ONE COMMAND, before any review, handoff, commit, or number you
are about to write down: `bd export -o .beads/issues.jsonl`.

THIS ALREADY COST THE FORT ONCE. Gate-queue figures read from a burst-stale
export reached `fort/advisories.md`, a dispatch brief, and an Overseer-signed
amendment in `fort/seats/mayor.md`; the true value at signing is unrecoverable.
The tool was never wrong — `scripts/digest.sh` queries `bd` live — only the
prose was.

AND THE EXPENSIVE HALF, which is not about Beads at all: THE RULE ABOVE WAS
WRITTEN DOWN CORRECTLY ON 2026-08-07 AND NOBODY READ IT FOR THREE WEEKS. It sat
in `docs/proposals/`, referenced from exactly one handoff, describing a
mechanism live in every fort — so a P1 bead was filed in 2026-08-31 asserting a
DIFFERENT and false mechanism, and three probes re-derived what the repository
already knew. A correct rule stored where no seat reads it is indistinguishable
from an absent one. See [[read-the-artifact-remember-the-why]]: this is that
class, arrived at from the third direction — not a proxy measured, not a subject
edited, but A RECORD NEVER OPENED.

THE WARDEN CANNOT READ `bd`, AND THE REASON IS THE MASK RATHER THAN HER PROFILE
(measured 2026-08-31, `fortkit-v7us.3`, inside a live review). Her profile permits
`bd -C * show/list/search/memories` and the permission layer passes the call
through; it dies at storage with `openat LOCK: read-only file system`, because
embedded Dolt opens the database read-write even to serve a read and `.beads` is
bound read-only in her sandbox. IT ERRORS, IT IS NOT DENIED — four earlier reviews
were right that it cannot run and wrong about why. So the export's freshness is
load-bearing for this fort's only review seat.

Full mechanism and audience: `docs/specs/beads-export.md`.
