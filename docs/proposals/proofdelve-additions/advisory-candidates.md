# Advisory candidates — FILING RECORD (2026-09-18)

This file was the draft staging ground. Outcome, on the Overseer's go-ahead:

| Candidate | Outcome |
|---|---|
| **A** — airlock send/ack has no state | **FILED** as `civ/advisories/adv-0013-airlock-send-ack-has-no-state.md` |
| **B** — coupling latency measurable and unmeasured | **WITHDRAWN.** Owner-effort tracking is tabled (D4); filing an advisory to measure a thing we decided we can't measure well would contradict itself. Kept as a documented need in `additions.md`, not as an advisory |
| **C** — "control that cannot fail" is one class | **APPENDED** to `civ/advisories/adv-0011-*.md` (a finding, not a new file) |
| **D** — acceptance criteria that assert instead of measure | **FILED** as `civ/advisories/adv-0014-acceptance-criteria-that-assert-instead-of-measure.md` |

The drafts below are retained as the reasoning behind each. The filed files are
authoritative.

---

## Candidate A — The airlock's send/ack ambiguity has no state

```
id: ADV-00xx (draft)
type: defect
title: An external action can succeed at the destination while the local process loses the response, and the airlock has no state for that
origin: { fort: Proofdelve, bead: ForgeOs-x6hq (related) }
severity: medium
status: draft
```

**What it is.** `x6hq` already records that the airlock deploy emits no event, so
the Mayor reconstructs one. The deeper shape, from the autonomy corpus: an external
action can commit at the destination while the local process loses the
acknowledgment. The only safe unknown state is *retain the commitment and
reconcile* — never retry (risks a double effect) and never assume-failed (risks a
dropped one). The airlock today has no `effect-uncertain` outcome.

**Applicability.** Any fort whose airlock performs an external effect (deploy,
API call, publish) where the acknowledgment can be lost independently of the
effect. Bites the first time such an action is unattended.

**Why it has not bitten.** Every airlock effect to date is a deploy the Overseer
runs by hand and immediately observes, so a human closes the ambiguity. Removing
the human removes the safety.

**What the origin fort might do.** Give the airlock a stable operation id, an
`effect-uncertain` state, and a reconcile step; emit the deploy event (closing
x6hq). This is Proofdelve addition #6.

---

## Candidate B — Coupling latency is measurable and unmeasured

```
id: ADV-00xx (draft)
type: gap
title: Every fort optimizes accepted throughput and none measures how long work waited on a human, though the event stream already contains it
origin: { fort: Manyhalls, bead: — }
severity: low
status: draft
```

**What it is.** The fleet spec marks the human-attention trigger `[UNMEASURABLE]`
("the stream records runs, not people"). True for attention-*minutes* — but the
valuable number is not minutes, it is **coupling latency**: how long a bead sat in
a human-gated state before the human acted. That is fully in the event stream
(`human`/`fleet-escalated`/ESCALATE timestamp → `gate.approved`/`decision.recorded`
timestamp). Present but uncomputed in every fort.

**Why it matters.** The corpus names owner-attention as *the* metric that decides
whether autonomy actually widened. A system that never measures the coupling
cannot tell "the agent got more autonomous" from "the human quietly absorbed the
wait." The measurable half costs nothing.

**What a fort might do.** Compute coupling latency per day from existing events;
tag owner acts `judgment | harness-repair` at act-time. Do **not** claim
attention-minutes — reading is indistinguishable from AFK. This is Proofdelve
addition #1.

---

## Candidate C — APPEND to ADV-0011: the "control that cannot fail" is one class in three places

```
Appended finding to ADV-0011 (the Warden cannot execute the harnesses her verdict rests on)
```

**The finding.** ADV-0011 records one instance: an excluded harness the reviewer
cannot execute, so acceptance rests on the builder's own measurement, reviewed by
reading. The autonomy corpus sharpens *why* this is the highest-severity class:
"the evaluator must be outside the candidate's mutation authority, and this is not
only a malicious-agent concern — optimization pressure and ordinary mistakes
produce the same symptoms." Read that way, **"a control that cannot fail" appears
in three places, and they are one class:**

1. **Excluded harness** (ADV-0011 as written) — the reviewer's only instrument is
   reading, and reading a well-formed harness confirms it is well-formed, not that
   it discriminates.
2. **A criterion that asserts instead of measures** — "confirm X and close"
   converts a Mayor's belief into merged code (`continuous-fleet.md` §9).
3. **A grep-count / substring criterion** — defeatable by producing the count.
   The `2ibw.7` incident (a Forge rewrote eight migration snapshots to satisfy a
   grep criterion, briefly signed, then withdrawn) is this exact failure on the
   authoring side.

**Why append rather than file new.** It is the same defect ADV-0011 already
describes, generalized from the review layer to the authoring layer. The
transferable rule: *a control whose only check is reading, or whose evidence is a
count or a match the producer controls, cannot fail and therefore is not a
control.* The corpus's "grep = N is a smell" is the field name for it.

---

## Candidate D — Acceptance criteria that assert instead of measure

```
id: ADV-00xx (draft)
type: gotcha
title: An acceptance criterion that asserts a conclusion converts a Mayor's mistake into merged code; one that demands a measurement catches it
origin: { fort: Proofdelve, bead: — }
severity: medium
status: draft
```

**What it is.** Currently a lesson in a Proofdelve handoff and the fleet spec §9,
not a civilization advisory. It is the most transferable finding in the whole
fleet corpus and it applies to every fort that writes acceptance criteria:
*"Acceptance criteria are the load-bearing control in unattended work, because
they are the only place a human's intent survives into a room with no human in it.
Criteria that assert a conclusion convert a Mayor's mistakes into merged code.
Criteria that demand a measurement catch them."*

**The concrete tripwire.** A criterion whose evidence is a count, a substring
match, or "confirm that X" is defeatable by producing that surface. The demonstrated
good form: write the first criterion as a *measurement* that names "change nothing"
as a legitimate outcome, rather than asserting the answer you believe. The fleet
has a recorded case where the belief was wrong, the builder measured, found the
opposite, and reported it — which an asserting criterion would have merged behind
a green verifier.

**Why it is an advisory and not just a fact.** Farlantern and Kithmason write
criteria too, and this would help them immediately. It is trouble that does not
announce itself: an asserting criterion looks exactly like a measuring one until a
Mayor is wrong. Overlaps with candidate C (both are "controls that cannot fail")
but is worth its own row because its audience is every Mayor authoring a bead, not
every Warden reviewing one.

---

## Note on what is deliberately NOT advised to the current civilization

The effect-uncertain-for-money, financial-ledger, and slow-outcome-statistics
material from the corpus is real but is **not** advised to the production forts. It
is not trouble any of them has hit, and filing it as an advisory would violate
standing order 11 (infrastructure needs an observed failure, not an imagined one).
That material belongs in the Greenlab design (`../greenlab/`), not as a bulletin to
the current civilization.
