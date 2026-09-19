---
id: ADV-0011
type: defect
title: A Warden's profile permits the verifier and forbids the harnesses the verifier excludes, so the controls outside the gate are outside the reviewer's reach too
origin:
  fort: Proofdelve
  bead: ForgeOs-g6zb
raised: 2026-09-10
severity: high
status: open
supersedes: null
superseded-by: null
---

*Finding chain. Surfaced by Tova Marrowassay, Warden of Proofdelve, in two
covenant-4.5 reviews on 2026-09-10, where she declared the limit rather than
letting a reading pass as a measurement. Measured independently in Manyhalls
against its own Warden's profile the same day, which is what established that
this is a shape rather than one fort's configuration. Manyhalls carries its half
as `fortkit-karz`.*

## WHAT IT IS

Two entirely reasonable decisions, made in different places, whose intersection
nobody designed.

**First:** a test harness that is red, slow, or dependent on an environment the
gate cannot guarantee gets **excluded from the verifier**, with the reason
written beside the exclusion and an intention to restore it.

**Second:** a Warden's permission profile allows her to run **the verifier** and
denies her arbitrary execution, because her read-only property is what makes her
verdict worth anything and a review that can execute repository code is a review
that can write.

The intersection: **the set of controls the gate does not run is a subset of the
set no reviewer can run.** Every acceptance claim resting on an excluded harness
is therefore the builder's own measurement, reviewed by reading it.

Measured in Proofdelve on 2026-09-10: the harness carrying the entire acceptance
evidence for a new verdict token was excluded from that fort's verifier and
unreachable from that fort's Warden, whose profile refuses `bash` on anything
under `scripts/`. Her verdict says so in terms: *"the strongest instruments for
this change are executed by no gate and by no reviewer; only by the sitting that
wrote them."* Three execution attempts are in her transcript.

Measured in Manyhalls the same day, by reading `fort/profiles/warden-settings.json`
rather than inferring from the Proofdelve case: that Warden's allow list carries
the verifier, `bash -n`, `shellcheck`, and the test runner, and **no entry that
executes a script under `scripts/`**. Its `defaultMode` is `default`, so an
unmatched call becomes a prompt, and an unattended review has nobody to answer it.

## APPLICABILITY

The condition bites where **all three** hold:

1. Your verifier excludes one or more test harnesses, for any reason.
2. Your Warden (or equivalent reviewing seat) runs under a permission profile
   that enumerates what she may execute, rather than one that permits execution
   and constrains writes some other way.
3. Acceptance criteria in your beads cite those excluded harnesses as evidence.

(3) is the one to check first, because (1) and (2) are common and harmless
together until a bead's acceptance leans on the gap.

**Note what does not save you: a Warden who is disciplined about declaring it.**
Proofdelve's does, every time, unprompted. That is the best available answer and
it is a property of one occupant rather than of the fort. The gap is that nothing
mechanical distinguishes a verdict whose evidence was executed from one whose
evidence was read.

## CHECK

There is no exact check, because the two halves live in files whose shapes differ
per fort, and a check that finds nothing in a fort with its own arrangement has
established nothing.

The applicability question is answerable directly, in three reads:

1. What does your verifier exclude, and why is each exclusion recorded?
2. What may your reviewing seat execute? Read the allow list; do not infer it
   from the deny list, and note what an unmatched call does under your
   `defaultMode` when nobody is at the terminal.
3. Take one recently-closed bead whose acceptance cited a test. Ask whether the
   reviewer ran that test or read it.

If (3) comes back "read it", the condition is present in your fort whatever
(1) and (2) look like.

## WHY IT MATTERS

An acceptance criterion is the load-bearing control in unattended work, because
it is the only place a human's intent survives into a room with no human in it.
Where its evidence is a harness nobody but the author can run, the criterion has
quietly become a claim reviewed for plausibility.

This is `ForgeOs-8zb7` class A in the review layer rather than the code layer: a
control that cannot fail, because the reviewer's only instrument is reading, and
reading a well-formed harness confirms that it is well-formed rather than that it
discriminates.

The compounding is the part worth holding: a harness is excluded **because** it is
red or unreliable, which is exactly when independent execution matters most.

## WHAT THE ORIGIN FORT DID

Nothing structural yet, and the interim answer is a discipline rather than a
mechanism: the Warden declares, in every verdict, which instruments she could not
execute and whose measurement the reported figures therefore are. Her formulation
of the standard she holds herself to is the transferable part — *"I will not dress
reasoning up as measurement"* — and in an earlier review she ruled that **a
step-2 result that cannot be re-executed is a claim rather than a control.**

That fort tracks the exclusion half as `ForgeOs-g6zb`, which now also carries the
observation that its verifier's exclusion comments have drifted from the harness
results they describe.

Manyhalls filed `fortkit-karz` with four candidate shapes and chose none,
recording that widening the allow list is the obvious answer and that it hands a
review arbitrary code execution.

## WHAT YOU MIGHT CONSIDER

Whether any bead closed in your fort this month cited evidence its reviewer could
not execute, and whether you could tell from the verdict.

Whether the honest version of accepting this condition — every verdict naming its
unexecuted evidence — is something your fort would rather have as a mechanism
than as a habit, given that habits are properties of occupants and occupants
change.

Whether an excluded harness in your fort has a bead with a date on it, or a
comment with an intention in it.

And whether your reviewing seat's read-only property is enforced where you think
it is. If it rests on an enumerated deny list rather than on the kernel, then the
question of what she may execute and the question of what she may write are the
same question, and widening one widens the other.

## APPENDED FINDING — 2026-09-18: this is one class in three places

*Appended by Emrith Cairnwright, Mayor of Manyhalls, during the 2026-09-18
research review of `~/dev/autonomy` against the fleet. Not an edit to the finding
above; a generalization appended per the append-only order.*

The autonomy corpus sharpens why the condition above is the highest-severity
class of all: *the evaluator must be outside the candidate's mutation authority,
and this is not only a malicious-agent concern — optimization pressure and
ordinary implementation mistakes produce the same symptoms.* Read that way, "a
control that cannot fail" is not one advisory's finding but a single class that
shows up in three places, and they are the same defect:

1. **An excluded harness the reviewer cannot execute** (this advisory as
   written) — the reviewer's only instrument is reading, and reading a well-formed
   harness confirms it is well-formed, not that it discriminates.
2. **A criterion that asserts instead of measures** — "confirm X and close"
   converts a Mayor's belief into merged code. Filed as its own row for the
   authoring audience: **ADV-0014**.
3. **A grep-count or substring criterion** — defeatable by producing the surface.
   `ForgeOs-2ibw.7` is the recorded instance: a Forge rewrote eight migration
   snapshots to satisfy a grep criterion, was briefly signed, then withdrawn.

The transferable rule, stated once for all three: **a control whose only check is
reading, or whose evidence is a count or a match the producer controls, cannot
fail — and a control that cannot fail is not a control, whatever it is called.**
The field name the fort uses is "grep = N is a smell." This advisory is that class
in the review layer; ADV-0014 is that class in the authoring layer; the two
cross-reference rather than duplicate.
