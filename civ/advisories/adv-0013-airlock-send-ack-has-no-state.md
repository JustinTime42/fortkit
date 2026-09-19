---
id: ADV-0013
type: defect
title: An external action can succeed at its destination while the local process loses the acknowledgment, and the airlock has no state for that outcome
origin:
  fort: Proofdelve
  bead: ForgeOs-x6hq
raised: 2026-09-18
severity: medium
status: open
supersedes: null
superseded-by: null
---

*Finding chain. Surfaced by Emrith Cairnwright, Mayor of Manyhalls, during a
2026-09-18 research review of `~/dev/autonomy` (an autonomous-systems corpus)
against the Proofdelve fleet. The defect lives in Proofdelve's airlock; the
generalization from "the deploy emits no event" (`ForgeOs-x6hq`) to "the airlock
has no state for an uncertain external effect" is the review's contribution. Both
forts named per the registry's cross-settlement rule.*

## WHAT IT IS

An airlock action performs an external effect — a deploy, an API call, a publish —
against a system the fort does not control. That effect and its **acknowledgment**
can fail independently: the action can commit at the destination while the local
process loses the response, or never reach the destination while appearing to
fail locally. These are different outcomes and the airlock cannot currently tell
them apart, because it has no state between "succeeded" and "failed."

The corpus states the rule this exposes: for an effect whose acknowledgment can be
lost, the only safe unknown state is **retain the commitment and reconcile** —
never retry (a retry risks a double effect on a non-idempotent endpoint) and never
assume-failed (which risks a silently-dropped one). A local success/failure flag,
or an outbox that guarantees the *intent* was durable, does not establish what
actually happened at the destination.

`ForgeOs-x6hq` already records one face of this: the Proofdelve airlock deploy
emits no event, so the Mayor reconstructs one after the fact. That is the same
gap seen from the reporting side — the fort learns an external effect happened
only by inference, never from the effect's own acknowledgment.

## APPLICABILITY

The condition bites where **all** hold:

1. Your fort has an airlock (or equivalent) that performs an external effect.
2. That effect's acknowledgment can be lost independently of the effect itself —
   i.e. the destination is a real external system, not a local file.
3. The airlock's outcome vocabulary is binary (succeeded / failed) with no
   "effect-uncertain, reconciliation pending" state.

It bites hardest the first time such an action runs **unattended**. Today it is
masked entirely by a human: every Proofdelve airlock effect is a deploy the
Overseer runs by hand and immediately observes, so a person closes the ambiguity
in real time. Remove the human — which is the direction of travel — and the
ambiguity has nowhere to live.

## CHECK

No exact check, because airlock shapes differ per fort. The applicability
question is three reads:

1. List your airlock's terminal outcomes. Is there one that means "the effect may
   have happened; I am reconciling"? If the only outcomes are success and failure,
   the condition is present.
2. Does each external effect carry a **stable operation id** the destination can
   deduplicate against, or that you can query the destination by after a lost
   acknowledgment? If effects are fire-and-forget, a retry is a double effect.
3. Take one recent airlock action. Ask: if its acknowledgment had been lost, how
   would the fort have learned the true outcome? If the answer is "a human
   happened to check," the safety is the human, not the airlock.

## WHY IT MATTERS

An unattended fort that treats an uncertain external effect as a failure will
retry it, and a retried non-idempotent effect is a double deploy, a double
charge, a duplicate message. One that treats it as a success will drop a real
one. The corpus's phrasing: *at-least-once delivery is compatible with this
design; blindly repeating external effects is not.* An outbox guarantees durable
intent, never exactly-once effect on an arbitrary recipient.

This is the highest-consequence gap for any fort moving toward outward action,
because unlike an internal accident (cheap, recoverable) an external effect
reaches a system the fort cannot roll back.

## WHAT THE ORIGIN FORT DID

Nothing structural yet; `ForgeOs-x6hq` is open for the reporting half (emit a
deploy event). The full shape — a stable operation id per effect, an
`effect-uncertain` terminal state, reserve-then-dispatch, and a reconcile step
that queries the destination rather than retrying blindly — is proposed as a
Proofdelve addition ("effect-uncertain state in the airlock") to be built and
tested against a real deploy under a human's eye, because it is the pattern a
future outward-acting civilization needs most and Proofdelve is the safe place to
prove it.

## WHAT YOU MIGHT CONSIDER

Whether your airlock has ever performed an effect whose acknowledgment could have
been lost, and whether anything but a watching human would have caught it.

Whether the effects your fort will perform when it is *less* attended are more
external and less reversible than the ones it performs today.

Whether "the intent was durably recorded" has been quietly standing in for "the
effect's true outcome is known," which are different facts an outbox does not
bridge.
