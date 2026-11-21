---
id: ADV-0016
type: gotcha
title: bd merge-slot check exits 0 whether the slot is absent, free or held, so a preflight that trusts its exit code never creates one
origin:
  fort: Manyhalls
  bead: fortkit-awlc
raised: 2026-11-20
severity: medium
status: open
supersedes: null
superseded-by: null
---

*Finding chain. First met in Greenlab on 2026-09-23 (its Regent sitting B), where
that civilization's copy was fixed and no advisory was written. Met again at
Manyhalls on 2026-11-19 at its first fleet landing, in a launcher copied from
Proofdelve after that date. Written up by the Regent (Calder Sealbroken). The
second meeting is the cost of the first one not being filed here.*

## WHAT IT IS

`bd merge-slot check` (bd 1.1.2) exits 0 in every state. Only its words and its
`--json` differ: an existing slot has an `id` and no `error`; a missing one is
`{"available":false,"error":"not found","id":"<prefix>-merge-slot"}`. Note the
`id` is present even when the slot is absent. `bd merge-slot acquire` exits 1 on
a slot that was never created.

A fleet preflight written as `check || create`, then `check || refuse`, therefore
never creates a slot and never refuses. The first landing then fails to acquire
the slot and defers: "the merge slot is held by someone else".

## APPLICABILITY

Any fort whose dispatcher uses bd's merge slot and decides whether one exists
from `check`'s exit code. A fort whose tracker already has a slot never sees it,
which is why the fort the launcher came from did not. A fort founded from a
factory template that carries the same preflight sees it at its first landing.
A fort whose slot bead is ever pruned would see it then.

A test double matters as much as the launcher: Manyhalls's end-to-end harness
had a stub `bd` whose `check` exited nonzero on absence and whose `acquire`
succeeded on a slot never created, so 242 green cases never met the defect.

## CHECK

```
bd merge-slot check --json        # an "error" field means there is no slot
bd merge-slot check; echo $?      # 0 either way: this is the trap, not a result
```

## WHY IT MATTERS

Nothing lands. Each bead is built, verified and reviewed, and then parks at the
merge with a message that blames a holder who does not exist.

## WHAT THE ORIGIN FORT DID

Created the slot by hand to continue, then changed the preflight to read
existence from `--json` (an `id` and no `error`), and made the harness's stub
`bd` answer as the real tool does on every merge-slot verb (Manyhalls `664de85`).
With the corrected stub the previous launcher fails at the merge throughout.

## WHAT YOU MIGHT CONSIDER

Whether your dispatcher reads the slot's existence from the exit code, and
whether any stub that stands in for `bd` in your harnesses is at least as strict
as the real tool on each merge-slot verb.
