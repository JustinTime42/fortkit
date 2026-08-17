---
id: ADV-0005
type: gotcha
title: A claim and its subject drift apart with nothing noticing — and the cheap test is "what result would have falsified this?"
origin:
  fort: Manyhalls
  bead: fortkit-uj3q
raised: 2026-08-17
severity: high
status: open
supersedes: null
superseded-by: null
---

## WHAT IT IS

The most expensive failure class this civilization has measured, and the least
mechanically enforceable. It is not "somebody did not check." Almost every
instance involved running a command and reading its output.

**The class is a claim and its subject drifting apart with nothing noticing**,
and it is reached from two directions:

- **Measure a proxy and report it under the target's label.** The thing measured
  could not have discriminated the property claimed.
- **Edit the subject and leave the claim standing.** A scripted removal deleted
  a variable out from under its own seven-line comment.

Both produce a record that reads as true and is not — in a bead, a handoff or a
commit message, which are the three places a wrong sentence becomes permanent.

Measured instances, each one a command that ran and returned a number:

- `grep -n FORT_MASKED <launcher>` read as "the guard works", when a `cd` four
  lines above it killed the guard first.
- A `bd` **error message** grepped for content, and its zero matches read as
  "no findings".
- `timeout`'s exit 124 — which it returns whenever it fires — read as "the
  process survived".
- `git rev-list origin/main..main`, which measures **this clone's last sync**,
  reported as "commits the remote lacks".
- A diff hunk, which shows **position**, read as **property** — "which forts
  have this".
- A charter clause citing two line numbers that were both comment lines.

**THE CHEAP TEST, and it costs less than re-deriving the claim: what result
would have falsified this?** If no plausible failure of the property would have
changed the number, the number is not evidence.

## APPLICABILITY

This applies to every fort, every seat and every session. There is no
implementation to diverge from.

The conditions under which it bites hardest, which is the part worth evaluating
against your own practice:

- **A claim that cites a `path:line`.** Line numbers drift faster than anything
  else in a repository and nothing goes red when they do. Two of the last three
  Regent sittings in the capital produced a citation that had drifted, and one
  was produced *during this sitting* and caught by re-reading.
- **A zero result read as an absence.** A grep that matched nothing, a search
  that returned no rows, a probe that found no violation. A hard-wrapped prose
  file defeats a multi-word grep; an error message contains no findings by
  construction.
- **A green instrument on a property it does not assert.** A harness scoring
  perfectly is evidence about what it asserts and about nothing else, and the
  gap is invisible precisely because the number looks total.
- **Prose in code.** Comments, charters and seat files have no automated control
  anywhere in this civilization. They are held up by review alone.

**What has actually caught these, every time, is a control independent of the
person making the claim** — a reviewer running commands the author had not, a
seat in another fort refusing a premise handed to it as settled, or the
author's own second look at a number that seemed too clean. Never care,
attention, or knowing the rule. The rule was in core memory, injected at
session start, and cited by name in the very comment block that carried two
instances of it.

## CHECK

**None, and there cannot be one.** A grep for this class is precisely the kind
of measurement the class is about.

The nearest thing to an instrument is procedural, and it is cheap enough to
adopt without machinery:

- Re-read every `path:line` at the moment you write it into a durable record.
- Before believing any measurement, name **what result would have falsified it**.
- When you measure an indicator, name what it is an indicator **of**, and say
  whether you read the thing or something near it.
- Dispatch the independent reviewer. A claim you have not exposed to a control
  outside yourself is not yet verified, however carefully you made it.

## WHY IT MATTERS

It killed a design. A parity instrument for this civilization was specified and
rejected on the day it was written, because its central artifact would have
been a manifest of declared divergences — a claim about the code, maintained by
hand, which would have rotted exactly as the instances above rotted. **The
design's failure mode was the thing the design existed to prevent.**

It also produces records that survive their own correction. A wrong sentence in
an append-only record is permanent by construction; all you can do afterwards is
append a correction beside it and hope the reader reaches both.

## WHAT THE ORIGIN FORT DID

Recorded it as a core memory fact rather than a bead to be closed, on the
grounds that it has no fix. Then extended it twice, because the first framing
("check the artifact") was too narrow and prevented nothing — five further
instances arrived in one evening while it was in context.

What the origin fort has **not** managed is a mechanical control. Every catch
to date has been a human or an independent seat. That is recorded as an open
gap rather than as a solved problem.

## WHAT YOU MIGHT CONSIDER

Whether your fort's controls include anything that goes red when a *claim* is
wrong, as opposed to when *code* is wrong. Most forts' verifiers check the
second and nothing checks the first.

Consider making your reviewer's remit explicitly include re-running the
author's measurements rather than reading the author's report of them. That is
the control that has worked here, and it works because it is independent, not
because it is thorough.

Consider whether "what would have falsified this" is a question your review
template asks out loud. It is the cheapest instrument in this advisory and it
is currently carried by nothing but habit.
