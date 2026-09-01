---
key: falsifier-beads-export
status: active
kind: falsifier
detects: "A committed .beads/issues.jsonl that no longer matches the Beads database — a stale projection about to reach git, where readers who cannot run bd will take it as current"
implements: scripts/verify-impl.sh:328
falsified-by: falsifier-vitest
provenance:
  source: "built and wired 2026-08-31 under fortkit-v7us.2, after the regeneration rule was measured by three timing probes on this fort; registered in the same change that wired it, per the falsifier-control-lint precedent"
  declared-by: emrith
  date: 2026-08-31
---
THE EXPORT'S FRESHNESS, MADE MECHANICAL. `bd` is authoritative;
`.beads/issues.jsonl` is a projection that a fresh clone, another fort's Mayor,
and any posture without `bd` will read as current. This stage fails when the
committed projection and the database disagree.

WHAT MAKES IT NECESSARY RATHER THAN TIDY, and it is measured rather than
feared (`fortkit-v7us`, 2026-08-31): the exporter's `interval: 60s` is a
throttle that DEFERS TO THE NEXT WRITE, NOT TO A TIMER. A write inside the
window is neither flushed nor scheduled, and with no further writes the export
stays stale INDEFINITELY — 51 samples over 244 seconds, zero catch-up, against
a positive control where one further write brought the file fully current. So a
burst of `bd` writes followed by a path-scoped `git add` commits the state of
the burst's FIRST write. That is how gate-queue figures reached
`fort/advisories.md`, a dispatch brief, and an Overseer-signed amendment in
`fort/seats/mayor.md`, where the true value at signing is unrecoverable.

WHY A PLAIN BYTE COMPARISON IS SOUND. `bd export` is byte-stable: two
consecutive runs against an unchanged database are byte-identical. No tolerance
window, no normalisation, and therefore no flapping — which matters, because a
control that cries wolf is disabled and then absent (`fortkit-dqu5`).

`falsified-by: falsifier-vitest`, AND NOT NULL, WHICH IS THE POINT OF THE
ENTRY. `test/verify-beads-export.test.ts` drives this check against a real
Beads fixture: it asserts green on a matching pair, red on a diverged
projection, and an ANNOUNCED skip for a missing export, a worktree, and a
non-checkout. That suite runs under the verifier's `test` stage, so
`falsifier-vitest` is the registered control that goes red if this one stops
working — the field names a control key, not a file, and the file is the
mechanism by which that key fires.

PROVEN, NOT ASSERTED. The check was sabotaged (`cmp -s` replaced with `true`,
so it always reported a match), the suite was run, and the divergence test went
red; restoring the line returned all five to green. Thirty of this register's
entries carry a null here. This one does not, because a freshness check never
observed to fail is indistinguishable from one wired to nothing — the defect
this fort shipped at `fortkit-52vf.12` finding 4 and `fortkit-vhk.5.1`
finding 8.

THREE THINGS IT DELIBERATELY DOES NOT DO.

It never writes `.beads/issues.jsonl`. The fresh snapshot goes to a `mktemp`
path. A checker that repairs what it measures cannot report on it, and would
mutate the working tree underneath a review in progress.

It SKIPS, ANNOUNCED, in a worktree. A Forge worktree carries its branch's copy
of the export, cut whenever the branch was cut, while the database lives in the
canonical checkout and has moved on. Comparing those is guaranteed to differ
and says nothing about freshness. This is the exact trap that broke
`skills-install` at `fortkit-52vf.9` blocking finding 1 and reddened every
Forge bead; it is designed out here rather than discovered later.

It SKIPS, ANNOUNCED, wherever `bd` will not run — absent from PATH, or an
export that produces nothing. Freshness is then UNKNOWABLE, which is not the
same as PROVEN, and the two must not render alike.

MEASURED LIMIT. This catches a stale export at verify time, not at the instant
a number is quoted into prose. A seat that reads a burst-stale export mid-
session and writes the figure into a bead is outside this control's reach; what
covers that is the rule in `fort/memory/facts/beads-export-freshness.md` —
counts come from `bd`, never from the export — and rules bind only through a
session's own reading of them. The mechanical half stops the artifact reaching
git; it cannot stop a sentence.
