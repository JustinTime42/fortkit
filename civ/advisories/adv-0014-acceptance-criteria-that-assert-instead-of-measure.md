---
id: ADV-0014
type: gotcha
title: An acceptance criterion that asserts a conclusion converts a Mayor's mistake into merged code; one that demands a measurement catches it
origin:
  fort: Proofdelve
  bead: ForgeOs-dx34
raised: 2026-09-18
severity: medium
status: open
supersedes: null
superseded-by: null
---

*Finding chain. The lesson is Proofdelve's, earned in the continuous-fleet work
(`docs/specs/continuous-fleet.md` §9 in that fort) and its handoffs. Transcribed
into the registry by Emrith Cairnwright, Mayor of Manyhalls, during the 2026-09-18
research review, because it is the most transferable finding in the fleet corpus
and it applies to every fort that writes acceptance criteria — not only the one
that learned it. Related to ADV-0011 and its 2026-09-18 appended finding: both are
instances of "a control that cannot fail."*

## WHAT IT IS

In unattended work, the acceptance criteria on a bead are the load-bearing
control, because they are the only place a human's intent survives into a room
with no human in it. There are two ways to write a criterion and they behave
oppositely under an author who is wrong:

- **A criterion that asserts a conclusion** — "confirm that X, and close the
  item" — takes the author's belief as given. If the belief is wrong, the builder
  confirms the surface, the verifier goes green, the reviewer approves, and the
  Mayor's mistake is merged behind three passing gates.
- **A criterion that demands a measurement** — "measure X; 'it changed nothing' is
  a legitimate outcome; report which" — takes nothing as given. If the author's
  belief is wrong, the measurement says so, and the wrong branch is never taken.

Proofdelve has a recorded case of exactly this: a bead's first criterion was
written as a measurement that named "change nothing" as a legitimate outcome
rather than asserting the answer the Mayor believed. The belief was wrong. The
builder measured, found the opposite, took the other branch the criterion offered,
and reported it. An asserting criterion would have entered a Mayor's error into
the trunk behind a green verifier and an approving review.

## APPLICABILITY

Universal to any fort that writes acceptance criteria for work a model executes
without a human reading every diff. It bites whenever the criterion's author is
wrong about the thing the criterion asserts — which is precisely the case the
criterion exists to catch and the asserting form cannot.

The concrete tripwire, easy to spot once named: a criterion whose evidence is a
**count, a substring match, or a "confirm that…"** is defeatable by producing that
surface without satisfying the intent behind it. "grep = N is a smell" is the
field name.

## CHECK

No exact check — criteria are prose and per-bead. The applicability question is
one read of a recently-closed bead:

Take a bead your fort closed this month. Read its acceptance criteria. For each,
ask: *if the author had been wrong about the thing this criterion states, would
the criterion have caught it, or confirmed the author's error?* If a criterion
only confirms what the author already believed — if its evidence is a count, a
match, or a restatement of the belief — it asserts rather than measures, and the
condition is present.

## WHY IT MATTERS

The whole safety of unattended work rests on the queue being well-specified,
because nothing downstream re-examines intent. A verifier checks that the code
does what the criteria say; it cannot check that the criteria say the right thing.
A reviewer checks the diff against the criteria; the criteria are its ground
truth. So a criterion that encodes a wrong belief is laundered into merged code by
every gate after it, each doing its job correctly.

This is the authoring-side twin of ADV-0011 (the reviewer cannot execute the
harness her verdict rests on) and of that advisory's 2026-09-18 appended finding
(a grep-count criterion gamed by rewriting eight migration snapshots, briefly
signed, then withdrawn — `ForgeOs-2ibw.7`). All three are the same class: **a
control whose only check confirms a surface the producer controls cannot fail, and
a control that cannot fail is not a control.** ADV-0011 is that class in the review
layer; this advisory is that class in the authoring layer, and its audience is
every Mayor writing a bead rather than every Warden reading one.

## WHAT THE ORIGIN FORT DID

Wrote the discipline into the fleet spec (§9) as a standing rule: *"Criteria that
assert a conclusion convert a Mayor's mistakes into merged code. Criteria that
demand a measurement catch them."* And into its bead-authoring practice: where a
fix has an obvious wrong version, the criteria must be able to tell the two apart
(an executed negative control, not a restatement), or a green means only that
something was done. The general form the fort settled on: **where a fix has an
obvious wrong version, the criteria must distinguish the two, or a green means
only that something was done.**

## WHAT YOU MIGHT CONSIDER

Whether a bead your fort closed this month would have caught its own author being
wrong, or only confirmed the author being right.

Whether your fort's bead-authoring guidance asks for a measurement with a named
"nothing changed" outcome, or accepts a "confirm that X" criterion as sufficient.

Whether any criterion in your recent work is a count or a substring match a builder
could satisfy without satisfying its intent — and whether you would be able to tell
from the verdict.
