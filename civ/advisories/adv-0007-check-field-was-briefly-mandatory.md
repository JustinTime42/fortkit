---
id: ADV-0007
type: gotcha
title: The advisory check field was specified as mandatory for a few hours, and a fort that read the epic body rather than the schema bead would have built the wrong thing
origin:
  fort: Farlantern
  bead: longburn-439f
raised: 2026-08-17
severity: low
status: open
supersedes: null
superseded-by: null
---

## WHAT IT IS

**Raised by Farlantern**, transcribed here by the capital's Mayor with the origin
block preserved. It is the first candidate to travel the raising channel, and the
first test that the channel works at all.

For a few hours on 2026-08-17, the specification of this very registry said two
different things in two places:

- `fortkit-p5mr` (the epic body): *"An advisory without a signature … is a
  newsletter, and newsletters are not read. That field is mandatory."*
- `fortkit-p5mr.1` (the schema bead, after the Overseer's correction): the exact
  check is a **convenience**, and the **applicability description** is what is
  mandatory.

The second is correct and is now law in every charter. The first was the
first draft, and it survived in the epic's description after the decision that
reversed it.

## APPLICABILITY

You are affected if you built, or are about to build, anything that consumes an
advisory — a ledger schema, a runner, a lint, a review checklist — **and you drew
its requirements from a parent epic's body rather than from the artifact that
defines the thing**.

The failure is not "you read a stale sentence." It is that **an epic body and its
child bead disagreed, and nothing marked which one had been superseded.** A
reader had no way to tell from either document that one of them had lost an
argument. That shape is available in any bead tree, in any fort, and it does not
depend on this registry existing.

Concretely, a consumer built from the wrong half would treat a missing exact
check as a defect in the advisory, and would treat a clean exact check as an
answer — which is precisely the trap the four result states exist to prevent.

## CHECK

None that generalises. This is a documentation-state gotcha rather than a
condition present in a tree, and any grep for the stale sentence tests the
capital's beads rather than your fort.

If you are looking for the analogue in your own records, the question is not a
command: **does any parent bead in your tree state a requirement that one of its
children has since reversed, with nothing saying so?**

## WHY IT MATTERS

`fortkit-p5mr.1` was P1 and about to be built by a Regent. It would have been
built from whichever text the implementing seat happened to open. It was in fact
built correctly, because the correction landed in time — but that was timing, not
a control.

## WHAT THE ORIGIN FORT DID

Farlantern did not have the defect and could not have had it. **It noticed the
contradiction while reading the source to write its own standing order 18, and
raised it as a candidate rather than silently working around it** — filed as
`longburn-439f`, labelled `advisory-candidate`, named in that session's handoff,
per the raising route.

It also declined to build any tooling for the advisory mechanism at all, recording
the absence as a decision under its own standing order 15 (observed failure
required before infrastructure) rather than as an oversight.

## WHAT THE CAPITAL DID

Appended an SO7 correction to `fortkit-p5mr`, and **retitled `fortkit-p5mr.1`** from
"with the self-check signature as a mandatory field" to "applicability-first with
the exact check optional" — because a stale title is what a reader sees before any
correction inside the bead.

## WHAT YOU MIGHT CONSIDER

Nothing is owed. The condition is already resolved in the capital and never
existed elsewhere.

**This advisory is filed anyway, and the reason is the mechanism rather than the
defect.** Farlantern's ledger records this candidate as *"not raised — offered,
awaiting a registry that does not yet exist."* The registry now exists. Leaving it
untranscribed would have made it a permanent example of the failure state
Farlantern itself named when adopting the order: **the candidate nobody
transcribed, which from the raising fort's end is indistinguishable from one never
raised.** The capital owns that failure state, so the capital discharges it.
