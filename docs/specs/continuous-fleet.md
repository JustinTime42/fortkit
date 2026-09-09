# The continuous fleet: work lands while the Overseer works

Status: DRAFT. Written to be refuted by the fort that holds the tree.
Author: Emrith Cairnwright (Mayor of Manyhalls), 2026-09-08.
Bead: fortkit-keku.
Provenance: the Overseer's target state, stated 2026-09-08 after Proofdelve
completed stages 0 through 4 of its fleet ladder in a single day; this seat's
reading of Proofdelve's event stream for that day; and the handoffs
`civ/handoffs/regent-2026-09-02T170231.md`, `civ/handoffs/regent-2026-09-04T143506.md`,
and Proofdelve's own `fort/handoffs/mayor-2026-09-04.md`.

This spec captures WHAT and WHY. It contains no interfaces, no function names and
no line numbers, deliberately. See §1.

---

## 1. How to read this document, and why that comes first

**This spec was written in Manyhalls about a tree Manyhalls cannot read.**

The last document of this shape was `civ/annals/briefs/proofdelve-fleet-sitting.txt`.
It carried five numeric predictions about Proofdelve and **four of them were
wrong**, because they were measured in the capital and asserted about a
settlement. The brief's own closing paragraph is what caught them: it said to
treat every number in it as a prediction until re-measured. The recorded lesson
was sharper than "check the numbers," and it is the reason this section exists:

> a brief written from another fort's tree should expect the measurement to
> change WHICH SEAT DOES THE WORK, not only the numbers.

So this spec is written under three self-imposed constraints:

1. **No line numbers, file offsets, symbol names or counts** taken from a tree
   this seat cannot read. Where a mechanism is named, it is named by behaviour.
2. **Every factual claim is tagged.** `[MEASURED]` means this seat read it
   directly, from Proofdelve's event stream, on 2026-09-08. `[REPORTED]` means
   it comes from a handoff or a review written by a seat that could measure it,
   and this seat is relaying it. `[UNKNOWN]` means nobody has measured it and
   the spec is asking rather than asserting.
3. **Every layer states what to measure before believing it.**

**To the Mayor who receives this: your refutations are the point, not a
courtesy.** A layer you can show is unnecessary, already satisfied, or
differently shaped in your tree is a layer this document got wrong. Record the
refutation and change the plan. Under standing order 13 declining is a
first-class answer, and "our design makes this moot" is complete.

---

## 2. The target state

Stated by the Overseer, 2026-09-08. Written as four separately refutable claims
so that disagreeing with one does not require disagreeing with all.

1. **The fleet runs continuously and idles when there is no ready work.** Not a
   nightly batch. Work that becomes eligible at 14:00 does not wait until 22:00.
2. **The fleet holds effectively exclusive access to the codebase** for the
   operations that require it.
3. **The Overseer can add work at any time without waiting for a run to
   finish.** He named this as the bottleneck he wants removed, in his own words:
   *"I just don't want the bottleneck being me waiting for it to finish things
   so I can add more work."*
4. **His role reduces to intent and unblocking.** Feature requests in, gate
   decisions when a gate genuinely needs him, nothing else.

**Requirement 3 is the one that makes this an architecture change rather than a
configuration change**, and it is worth being explicit about why. Requirements 1,
2 and 4 could be approximated with a timer and a bigger budget. Requirement 3
cannot, because it means the Mayor conversation must be able to run *while the
fleet runs*, and the current design prevents that:

- A run refuses to start when the repository root has uncommitted tracked source
  changes. `[REPORTED]`
- The landing step re-checks landability immediately before merging, and on a
  dirty tree it **defers** rather than halting. `[REPORTED]`

So a Mayor writing a spec or a doc, which are tracked source, causes in-flight
merges to defer. The Mayor of Proofdelve went deliberately read-only for the
duration of every run on 2026-09-08, three separate times, by choice rather than
by mechanism. `[REPORTED]` That is the requirement-3 conflict, observed.

**Note what is already exempt**: `.beads/` and `fort/events/` do not trip the
landability guard. `[REPORTED]` So a Mayor writing *beads* is already safe from
that mechanism. The conflict is specifically with tracked source: specs, docs,
and anything else a Mayor legitimately edits.

---

## 3. The constraint that shapes everything

The organising insight is that **"night" is not the requirement. Exclusive write
access is.**

The fleet needs uncontended access to two shared resources, and only for part of
its run:

| resource | who else wants it | when the fleet needs it |
|---|---|---|
| tracked source at the repository root | any seat writing specs, docs, code | at merge and post-merge verification |
| the issue tracker's storage lock | any seat running `bd` | throughout, on its own schedule |

Everything else the fleet does happens in an isolated per-bead worktree and
contends with nobody.

Two consequences follow, and they are the whole design:

- **"Only run at night" is a cheap proxy for "nobody else is writing."** It is
  the correct proxy for today and should be kept until the layers below land. It
  is not the requirement, and treating it as the requirement is what makes
  requirement 3 look impossible.
- **The landability guard is broader than the constraint it protects.** It
  refuses the *entire run* on a dirty root, when the operations that actually
  require a clean root are the merge and the post-merge verification. Narrowing
  the check from run-start to merge-time is the single change that most directly
  serves requirement 3.

**What to measure before believing that last claim** `[UNKNOWN]`: whether any
step before the merge reads the repository root rather than the worktree. If the
Forge dispatch, the claim read-back, or the in-worktree verifier touch the root,
the narrowing is unsafe and this spec is wrong about it. That is a question for
the fort that can read the file.

---

## 4. Four layers, in dependency order

Each layer's verification must exist before the next fans out. This is the same
banding discipline `fortkit-wg8w` uses, and for the same reason: a measurement
taken before its instrument exists is not a measurement.

### Layer 1: nothing ever strands

**Why it is first.** A continuous fleet defers merges routinely, because a
working Mayor dirties the tree routinely. Deferral is only safe if deferred work
comes back. Today it does not: a deferred merge is never retried, in either
deferral path. `[REPORTED]` **Deferral without retry is stranding with better
manners**, and a continuous fleet would manufacture it many times a day.

This layer is the prerequisite for everything else, and it is already partly
filed in Proofdelve.

**What it contains, as behaviour rather than as beads:**

- **One owner for worker lifecycle.** A single place that knows a unit of work
  is finished and decides what happens next, covering: normal completion,
  a worker orphaned when the dispatcher dies, and a merge that deferred. The
  reviewing Warden's own recommendation was one bead giving lifecycle a single
  owner rather than a fifth point repair, after five sightings of the same
  shape. `[REPORTED]`
- **Deferred merges retry.** The specific defect above.
- **A graceful stop path**, serving three triggers that today behave
  differently and should not:
  - *budget exhaustion*: a full cycle costs two dispatches, one to build and one
    to review `[REPORTED]`. The budget is checked per dispatch, so it can spend
    the build and refuse the review, leaving work built, verified and unreviewed.
    **The fix is to reserve the review dispatch when the build dispatch is
    made**: never start a cycle you cannot finish. Then budget exhaustion becomes
    "stop starting, finish what is in flight, exit cleanly," and can never strand.
  - *an operator asking it to stop*: there is no mid-run check of the halt file,
    so creating one affects only the next run. `[REPORTED]` A per-pass check
    turns the halt file into a working graceful-stop lever, which today does not
    exist at all.
  - *a signal*: the only trap is on exit, with no interrupt handler, so an
    interrupted run records a clean drain for a run that was killed. `[REPORTED]`
    This was **observed live** by the Overseer on 2026-09-08 and corrected
    append-only in the stream. `[MEASURED]`

**Note the convergence, because it changes the decomposition.** These are not
four defects. The halt check and the budget reservation are *the same
drain-then-stop path*. The orphaned-worker case and the deferred-merge case are
*the same lifecycle owner*. Filing four beads here produces four point repairs of
a class that has already survived four point repairs.

**Done when:** a run can be stopped by halt file, by signal, and by budget
exhaustion, and in all three cases (a) the record says what actually happened,
(b) nothing is left claimed-and-unreachable, and (c) the next run picks up
whatever the stopped one left. Proven by execution, not by reading.

**Lane:** implementation is Regent (see §5). The beads are the holding fort's.

### Layer 2: coexistence

**Why it follows layer 1.** Coexistence means routine deferral. Routine deferral
is only safe once deferral retries.

**What it contains:**

- **Landability narrowed from run-start to merge-time**, per §3, subject to the
  measurement named there.
- **Contention with the issue tracker measured.** `[UNKNOWN]` The tracker is
  embedded Dolt and takes a storage lock. `[REPORTED]` A fleet making tracker
  calls on its own schedule while a Mayor files beads is a real concurrent
  workload that nobody has run deliberately. It may already be fine, because the
  tool may retry; it may need backoff; it may need the fleet to batch its writes.
  **This is a measurement, not a design decision, and it should be taken before
  anything is built for it.**
- **A stated rule for what a Mayor may write during a run.** Whatever the
  mechanism turns out to be, the seat needs to know. Today the answer is
  "nothing tracked," discovered by reasoning and honoured by choice.

**Done when:** a Mayor files beads, writes a spec, and commits it while a fleet
run is in flight, and the run lands its work with no deferral that does not
resolve, no tracker error, and an honest record.

**Lane:** the narrowing is Regent. The contention measurement is the holding
fort's Mayor and needs no sitting.

### Layer 3: self-starting

**Why it follows layer 2.** A fleet that starts itself while a Mayor works is
only safe once the Mayor working is safe.

**What it contains:** a supervisor that fires on a short interval, exits
immediately when the queue is empty or a run is already live, and otherwise
starts a run. Not a nightly timer: a nightly timer satisfies none of requirement
1 and reintroduces the batch boundary the whole design is removing.

**Two constraints on where it lives.** It must be host-level, because a masked
seat cannot launch a fleet: the dispatcher refuses when launched from inside a
mask, which is deliberate and should stay. `[REPORTED]` And the dispatcher does
not currently detach itself, so a closed terminal kills it. `[REPORTED]` A
supervisor makes that moot for scheduled runs but not for hand-launched ones,
and the hand-launched path should be made safe regardless.

**Done when:** work labelled eligible at an arbitrary time is picked up without
anyone launching anything, the supervisor is a no-op when there is nothing to do,
and two supervisor firings can never produce two concurrent runs.

**Lane:** Regent or the Overseer's hand. Outside every mask by construction.

### Layer 4: concurrency

**Why it is last.** Gated on layer 1 by the reviewing Warden's own ruling and
the holding Mayor's agreement. `[REPORTED]`

**What it contains:** raising build concurrency above one, and with it the first
execution of merge-slot contention. **That machinery has never run.** `[REPORTED]`
At concurrency one there is never a second candidate for the slot, so no ladder
stage that keeps concurrency at one can test it, however many beads it runs.
That was found by the holding Mayor while describing his own plan, and it means
the slot goes live for the first time on whatever run first raises the dial
unless a stage is built for it.

**Done when:** two units of work contend for the merge slot, both land, and the
record shows the serialization.

---

## 5. The structural tension, recorded rather than resolved

Every change to the dispatcher is kernel read-only to every masked seat,
including the holding fort's own Mayor. `[REPORTED]` So layers 1 through 3 are
almost entirely attended Regent work.

**Which means the machine that removes the Overseer from the loop can only be
maintained by putting him back in it.**

This spec's recommendation is to **keep that boundary and batch the sittings.**
The reasoning:

- The property being bought is that no seat can modify its own dispatcher. A
  fleet that can edit the file governing its own limits can raise them.
- The evidence supports it. On 2026-09-08 the fleet completed six units of work
  correctly `[MEASURED]`, and every defect found in the dispatcher that day was
  found by a reviewer or by a deliberate measurement. None was found by the
  fleet noticing its own problem.
- The lane is not slow when the docket is prepared. Two sittings over five days
  landed sixteen items. `[REPORTED]` Docket preparation is Mayor work and needs
  no sitting.

**A future alternative, deliberately not proposed now:** split the dispatcher
into an enforcement half (refusals, budget, mask checks, the merge gate) that
stays kernel read-only, and a policy half (poll interval, ordering, logging)
that a seat may write. That is a real refactor and it should wait until the
current shape has proven annoying in practice. Under standing order 11,
infrastructure work requires an observed failure and not an imagined one.

---

## 6. What is deliberately out of scope

- **Loosening the human gate on the dispatcher.** See §5.
- **A merge train.** Work that must land as a unit is addressed in §7 by
  sequencing, not by combining. Build the train when a real migration proves
  sequencing insufficient.
- **Any change to which seat may launch what.** The masked-seat launch refusal
  stays.
- **Porting any of this to the capital or the factory.** Standing order 13:
  adoption is pull. The trigger for this fort to consider pulling is stated in
  §8, and it has not been met.
- **The publication of a model for how much concurrency is sustainable.** No
  reliable figure exists on either plan, and a guessed constant would be a false
  measurement. The governor is adaptive for this reason. `[REPORTED]`

---

## 7. Work that must land together

Raised by the Overseer as a common case, especially during migrations. Recorded
here because a continuous fleet meets it more often than a nightly one.

**The default should be a dependency chain, not a combined bead.** The tracker
already supports blocking relationships and the eligibility query already
excludes blocked work, so A blocks B blocks C lands in order with no new
machinery. `[UNKNOWN]`: whether the fleet picks up B *within the same run* once
A lands, or only on the next pass. The dispatch loop re-queries each pass, so it
probably does, and that is exactly the kind of "probably" this fort has been
wrong about. Worth one deliberate test.

**The discipline this demands is the one that makes migrations safe anyway:
every step must leave the trunk green on its own.** Expand and contract. Add the
new column, dual-write, backfill, switch reads, drop the old column. Each step
independently landable and independently verified, which the gate enforces at
every position.

**The corollary matters as much as the rule: work that cannot be split into
individually-green steps should not be eligible for the fleet at all.** It is
attended work, and saying so is a complete answer. A desire for a merge train is
usually a signal that the migration has not been designed yet.

**Where a single bead is right:** tight coupling over a small surface, such as a
rename across three files. One change, one diff, one review.

---

## 8. The trigger for other forts to consider this

Standing order 13: adoption is pull, and declining is a first-class answer. This
section exists so that a Mayor elsewhere has something to judge against rather
than a rumour.

**Do not pull before all of these hold in the originating fort:**

1. Layer 1 is done and proven by execution.
2. At least one run has completed with the Overseer genuinely absent, not merely
   unattended for forty-five minutes in the evening. As of 2026-09-08 this has
   not happened: the longest run that day ran under an hour with him at the
   terminal. `[MEASURED]`
3. A morning read has been performed against a run nobody watched, and the read
   found what the run actually did.

**And when pulling, take it from the fort that built it, not from the factory.**
This is the case standing order 13 names explicitly: where a fort is the origin
of a thing, the template is downstream of it, and a template copy is evidence
about the template rather than about the thing.

---

## 9. What stays the Overseer's, and it is more than "feature requests"

Recorded because the target state in §2 understates it, and an understated
target produces a disappointed one.

The gap between a feature request and a unit of work the fleet can safely take
is **decomposition plus acceptance criteria**, and on 2026-09-08 that gap is
demonstrably where the safety lives.

The demonstration, and it is the most transferable finding of that day
`[REPORTED]`: the holding Mayor wrote one bead's first criterion as a
*measurement*, naming "change nothing" as a legitimate outcome, rather than
asserting the answer he believed. **His belief was wrong.** The builder measured,
found the opposite, took the other branch the criterion offered, and reported it.
Had the criterion been written as "confirm X and close the item," his error would
have entered the trunk behind a green verifier and an approving review.

The rule that follows:

> **Acceptance criteria are the load-bearing control in unattended work, because
> they are the only place a human's intent survives into a room with no human in
> it. Criteria that assert a conclusion convert a Mayor's mistakes into merged
> code. Criteria that demand a measurement catch them.**

A second instance from the same day sharpens it: a criterion asked for a pin
"that fails if it stops winning" and got a fix plus a pin that could not fail.
The reviewer caught it, the work was returned, and the second attempt replaced it
with a real test. What would have caught it at authoring time is the thing a
different bead's criteria demanded and got: **an executed negative control.**

So feeding the queue does not shrink to nothing. It becomes the whole job, and it
is the part that is genuinely the Overseer's and his Mayor's. This argues for
making it cheaper rather than for pretending it away: a formula or template for
fleet-eligible work that bakes in the executed-negative-control requirement, so
the discipline does not depend on a Mayor remembering it every time.

---

## 10. Open questions this spec cannot answer

Listed so they are asked rather than assumed. Each belongs to the fort that holds
the tree.

1. Does anything before the merge read the repository root rather than the
   worktree? Settles whether §3's narrowing is safe.
2. What does real concurrent tracker access between a fleet and a session
   actually do? Settles whether layer 2 needs machinery or only a rule.
3. Does a dependency chain advance within a single run, or only across runs?
   Settles §7.
4. Can two supervisor firings produce two concurrent runs, and what prevents it?
   Settles layer 3.
5. Is the observed return rate representative? One return in six units of work on
   one day `[MEASURED]` is too small a sample to size a budget from, which is
   itself the argument for the reservation fix in layer 1 rather than for a
   better-tuned number.

---

## Appendix: what this seat measured directly

Read from Proofdelve's `fort/events/events-2026-09-08.jsonl` on 2026-09-08,
by absolute path, from Manyhalls. Recorded so the secondhand claims above can be
separated from the firsthand ones.

- Five runs begun. Three ended after zero dispatches (two of them dry, one
  interrupted). One ended after two dispatches. One ended after four. One ended
  after eight.
- One run recorded `drained` for a run the Overseer interrupted, with an
  `incident.corrected` appended naming it.
- Six units of work closed, every one on an approve-with-findings verdict, each
  carrying its findings to a named follow-up.
- One return to ready, on a request-changes verdict, which then closed on a
  second review whose verdict text states the reviewer reproduced the failure
  and the fix independently.
- The final run ended after exactly eight dispatches against a budget of eight.

---

## 11. Corrections, appended 2026-09-09

Appended rather than edited in, per standing order 7. Every item here was found
by Marrek Splitstone, Mayor of Proofdelve, on the first reading of this document,
and recorded on `ForgeOs-dx34`. The corrections are listed because a reader
acting on the original text would be wrong.

**C1. The Appendix miscounted, in the section that exists to hold firsthand
claims.** It reported "three ended after zero dispatches." **The true count is
two.** Re-measured 2026-09-09 by matching the event category exactly: five
`fleet.begun`, five `fleet.ended`, dispatch counts 0, 0, 2, 4, 8.

The cause is worth more than the number. The original grep matched the *substring*
`fleet.` and so also matched an `incident.corrected` event whose detail text
quotes the `fleet.ended` line it was correcting. **Standing order 7 makes every
correction quote its subject, so grepping for an event category will always match
that category's own corrections.** The receiving Mayor made the identical error
independently, an hour earlier, on the same stream. Two seats, same day, same
mechanism. This belongs in whatever guidance exists on reading event streams.

**C2. §8 trigger 2 claimed the Overseer was at the terminal, and that was
inferred rather than measured.** He was absent for the duration of the final run
of 2026-09-08, including the return path firing. What was measured was run
timestamps; his presence was assumed from them. The trigger is **closer to met
than this document claimed**, though still not met: it asks for a run completed
with him genuinely absent and followed by a morning read, and that has not
happened. The claim should have carried no `[MEASURED]` tag at all.

Both C1 and C2 are the same failure this document warns about in §1: a claim
drawn wider than the instrument that produced it.

**C3. Layer 1's budget-reservation item is struck.** §4 proposed reserving the
review dispatch at build-dispatch time, on the reasoning that budget exhaustion
could leave work built, verified and unreviewed. **The state description is
right and the diagnosis is wrong.** Both boundaries were repaired in the
originating fort on 2026-09-04: the reaping pass consults the budget before
marking work done, and the review path deliberately un-marks it and keeps the
claim. Budget exhaustion parks work for the next run; it does not strand it.

**And the argument inverts under this document's own target.** "The next run
picks it up" is a weak guarantee in a nightly batch and a strong one in a
continuous fleet. Continuous operation makes the existing design better rather
than requiring a change. That is a better answer than the one proposed here.

*One thing to carry into layer 1 from this, and it is an addition rather than a
dispute:* **a budget-parked unit of work and a stranded one are indistinguishable
to a reader.** Both are claimed, in progress, built, and carry no verdict. The
lifecycle owner should be able to say which it is looking at, and the morning
read should be able to tell them apart, or every parked unit will be
investigated as a stranding for as long as runs are hours apart.

**C4. §3's verification question was scoped to half of its own claim, and the
missing half is a hazard rather than a detail.** The section correctly named
*two* operations requiring a clean root, the merge and the post-merge
verification, and then asked only whether anything **before the merge** reads the
root. The answer to that question is that nothing does, so the narrowing is safe
on that side.

**The post-merge verifier is the hazard, and this document should have named
it.** That verifier runs in the root and builds the tree as it exists on disk, so
a narrowed guard opens a window in which a seat's uncommitted edit is scored as
part of the merged work. **The failure mode is not a deferral. A red post-merge
verifier halts the fleet**, and the record attributes the halt to the merged
work. Under this document's own target state, where a Mayor writes while the
fleet runs, the natural accident is a half-written spec stopping the fleet and a
record that blames a bead.

So the narrowing is not "move the check later." It is "move the check later, and
close the post-merge window," and the second half is the harder one.

*A candidate this document proposes but does not assert:* **run the post-merge
verification in a fresh worktree at the merged commit rather than in the root.**
That removes the root from the critical path entirely and reduces the exclusion
window from a full build to the duration of the merge itself, which is seconds.
It also makes the claim more meaningful, since what is being verified is the
commit rather than a working directory contaminated by whoever happens to be
editing. **Its cost is real and unmeasured**: a cold worktree has no build cache,
so a full build there may be materially slower than in the root, and it adds a
worktree per merge. Measure the build time before adopting it.

**C5. Two of §10's open questions are answered.** A supervisor cannot produce
concurrent runs: an exclusive lock and a documented busy exit already prevent it,
which shrinks the supervisor's scope from solving concurrency to not breaking it,
and means the busy exit should be treated as the normal quiet outcome rather than
as an error. Dependency chains do advance within a single run.

**C6. Layer 1 is entirely filed in the originating fort, not partly.** §4
understated it.
