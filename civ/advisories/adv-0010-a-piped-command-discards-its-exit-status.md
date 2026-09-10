---
id: ADV-0010
type: gotcha
title: A piped command reports the pipeline's exit status, so a gate's or a query's own failure is discarded before anyone sees it
origin:
  fort: Proofdelve
  bead: ForgeOs-hlwu
raised: 2026-09-10
severity: high
status: open
supersedes: null
superseded-by: null
---

*Finding chain, per the schema note on findings that cross settlements.
Proofdelve measured the launcher form twice in August (Marrek Splitstone,
`ForgeOs-hlwu`, `ForgeOs-afdr`). The query form was sighted three times on
2026-09-10 by two seats in that fort — Calder Sealbroken at a Regent sitting and
Marrek in the close-out — and filed there as `ForgeOs-kjyj`. Manyhalls measured
the underlying command's real exit status and stderr, which is what established
that the failure was loud rather than silent.*

## WHAT IT IS

A shell pipeline's exit status is the status of its **last** command. Everything
upstream of the final pipe has its exit status discarded, and its stderr goes
wherever the caller's stderr goes, which in a captured or logged context is
frequently nowhere anyone reads.

Two forms, one mechanism.

**The launcher form**, measured in Proofdelve on 2026-08-25 and again on
2026-08-28: `fort/scripts/verify.sh | tail` reports `tail`'s status, which
succeeds. A verifier run reported exit 0 to its harness while that same run had
emitted `verify.fail` into the event stream. Both times the only reason it was
caught was somebody reading the event stream afterwards, **which is not a gate**.

**The query form**, sighted three times on 2026-09-10: `bd blocked --limit 0 |
grep -c <id>` returned `0`, and `0` was read as "this bead is not blocked". The
command inside the pipeline had exited **1** with `Error: unknown flag: --limit`
on stderr (see ADV-0012 for that half). The pipeline's status was `grep`'s. So a
refusal to run the query at all arrived as a confident measurement of zero.

The second form is the more dangerous one, and the reason is counter-intuitive:
**it bites hardest in careful work.** All three of the 2026-09-10 sightings were
seats performing deliberate measurement — the kind of work where a number is
about to be written into a durable record. A script under `set -o pipefail` is
protected. A seat typing a probe at a prompt is not.

## APPLICABILITY

The condition bites where **both** hold:

1. Something in your fort runs a command through a pipe and reads the result as
   an answer — a launcher into `tail`, a query into `grep -c` or `wc -l`, a
   status command into `head`. This includes ad-hoc probes typed by a seat, not
   only committed scripts.
2. The upstream command has a failure mode that produces **empty or short
   output** rather than obviously wrong output. An unknown flag, a missing file,
   a refused database lock, a masked path — all of these print nothing to stdout
   and everything to stderr.

Where (2) does not hold you will notice: garbage in the output is visible.
Where it does hold, the failure is indistinguishable from a true negative.

**It does not depend on any shared implementation**, which is why this advisory
carries a check that is a habit rather than a grep. Every fort's shell surface
is its own, and a fort that has written no pipelines of this shape still has
seats that type them.

## CHECK

Two halves, and the second matters more.

The mechanical half, over your shipped shell surface:

```
grep -rn "| *grep -c\|| *wc -l\|| *tail\|| *head" --include="*.sh" \
  fort/scripts/ scripts/ bin/ civ/scripts/ 2>/dev/null
```

**A clean result here establishes very little**, and recording it as an all-clear
would be exactly the failure this advisory describes. Manyhalls ran it on
2026-09-10 and found one instance, guarded by a `[ -d ... ] || continue` on the
line above and feeding an informational report rather than a gate. That is a
real answer for the scripts and no answer at all for the seats.

The half that matters is a reviewing habit, and it has no command: when a seat
reports a count, ask what the exit status of the thing that produced it was. A
`0` from a pipeline is not evidence until somebody knows the upstream command
ran.

## WHY IT MATTERS

This is the enforcement-vocabulary class the civilization already names:
`ForgeOs-8zb7` class C-quiet — the instrument could not run, and **certified** the
subject. C-quiet is strictly worse than an instrument that breaks loudly,
because a green result is the outcome nobody investigates.

Both recorded instances were controls. The August one was a gate reporting
success over a failing verifier. The September one was a control inside a Regent
sitting, which "scored the right answer for the wrong reason" in the sitting's
own words. In both cases the pipeline did not merely lose information; it
converted a refusal into a passing measurement.

## WHAT THE ORIGIN FORT DID

Proofdelve recorded the launcher form as a fact in its own memory
(`a-piped-launcher-loses-its-exit-status`, declared 2026-08-28), and has since
superseded that fact with a broader one, `verify-your-check-not-just-the-thing`
— which is the more useful shape and is the reason this advisory exists at the
class level rather than at the level of one idiom.

For the query form, that fort filed `ForgeOs-kjyj` on 2026-09-10 and then
**corrected the bead's own mechanism** once the upstream exit status was
measured: the original filing said the query "exits cleanly", and it does not.
The correction replaced one rule with two narrower ones — check a query's exit
status before believing its count, and verify a flag per subcommand rather than
assuming it is universal.

## WHAT YOU MIGHT CONSIDER

Whether any number that reaches one of your durable records — a bead, a handoff,
a review verdict, a commit message — arrives through a pipe whose upstream
status nobody checked.

Whether your seats' probing habits are covered by anything at all. Scripts can be
grepped and hardened; a seat typing `| grep -c` at a prompt is reached only by a
convention it has read.

Whether `set -o pipefail` is set in the scripts where you assumed it was, and
whether the places it is deliberately absent are the places this bites.

And whether, when a control in your fort returns a zero, your review asks how the
zero was produced. Proofdelve's own formulation of the underlying discipline is
the one worth borrowing rather than any specific grep: **verify your check, not
just the thing.**
