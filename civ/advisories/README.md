# The advisory registry

**What this is:** the civilization's channel for trouble. A fort that finds a
defect, or learns a thing that will cost the next seat a measurement, writes it
down here so the other settlements learn of it without anyone having to go
looking.

**What it is not, and this is the whole design:** a convergence instrument. No
advisory in this directory binds any settlement. Nothing here tells a fort what
to do.

Law: standing order 13 in every fort's charter, and section 12 of
`civ/covenant.md`. Where this README and either of those disagree, they win and
the disagreement is a finding worth filing.

---

## Why a registry at all, when adoption is pull

Features announce themselves. Somebody builds a thing, says so, and another
fort's Mayor reads it against her own tree and decides. That needs no
machinery, and standing order 13 gives it none.

**Trouble does not announce itself.** Nobody offers you a broken script the way
they offer you a feature. Every safety finding of 2026-08-17 was invisible
until somebody happened to look, and each was silently present in forts nobody
had checked. The pull model has no trigger for any of them, because its trigger
requires somebody to already know.

So defects and gotchas get pushed, and this is where they land.

---

## Service bulletin, not airworthiness directive

The distinction is aviation's and it is exact.

An **airworthiness directive** names a part number and mandates its
replacement. It works because every affected aircraft has the same part.

A **service bulletin** reports a failure the manufacturer has seen, states the
conditions under which it bites, describes the fix, and leaves applicability to
the operator — who knows their own aircraft, including the parts of it they
built or modified themselves.

**Everything in this directory is a service bulletin.** Forts diverge on
purpose: a settlement evolves toward its own needs and is frequently right to
have solved a problem its own way. A registry that issued directives would be
issuing them to aircraft it has never seen.

Prefer that vocabulary in the text of an advisory. Do not write "recall".

---

## The schema

One file per advisory: `civ/advisories/adv-NNNN-<short-slug>.md`.

### Frontmatter

```yaml
---
id: ADV-0001                  # civilization-wide, sequential, never reused
type: defect                  # defect | feature | gotcha
title: <one line, the finding itself, not the file it was found in>
origin:
  fort: Manyhalls             # the fort that found it
  bead: fortkit-i50s          # that fort's own bead, where the work lives
raised: 2026-08-17
severity: high                # high | medium | low — SEE BELOW
status: open                  # open | superseded
supersedes: null              # advisory id, or null
superseded-by: null           # advisory id, or null
---
```

**The id is civilization-wide and the bead id is not.** A bead id is fort-local
and its prefix names one settlement; standing-order numbers already collide
across the three forts at 7, 9, 11 and 12 (`fortkit-smmw`), so a fort-local
address is not a civilization-wide address. `ADV-NNNN` is the address. The
origin bead travels beside it as provenance and is never dropped.

**`severity` is the origin fort's assessment of the finding IN THE ORIGIN
FORT'S OWN TREE.** It is not a claim about your fort and it is not a priority
you have been assigned. A `high` advisory that does not apply to you is a
`not-applicable` row in your ledger, and that is a complete answer.

**`origin` survives transcription.** An elder fort cannot write into this
directory (see the write boundary below), so most advisories raised outside the
capital are written here by another hand. The `origin` block records whose
finding it was, and the transcriber's own name belongs nowhere in it.

**When the finding chain crosses two settlements, the `origin` block holds one
fort and the body holds the chain.** The block is a single fort and a single
bead on purpose, because it is the address work gets filed against. A finding
that one fort surfaced and another measured is the interesting case and it is
already here on day one — ADV-0004 is exactly that — so say so in a note at the
head of the body, naming both. Attribution is provenance, not inheritance, and
naming another settlement's citizen as the finder is always permitted.

### Body sections — all six, in this order

```
## WHAT IT IS
## APPLICABILITY          <- MANDATORY
## CHECK                  <- optional; may be omitted entirely
## WHY IT MATTERS
## WHAT THE ORIGIN FORT DID
## WHAT YOU MIGHT CONSIDER
```

Keep the section absent rather than writing "N/A" under it, except for
`CHECK`, where an explicit "no exact check is possible, and here is why"
is worth more than a silence a reader has to interpret.

---

## APPLICABILITY is the mandatory field, and CHECK is the convenience

This is the part of the schema that was got wrong in a first draft and
corrected before anything was built, so the reasoning is written down here
rather than left to be rediscovered.

**APPLICABILITY** states the **failure mode** and the **conditions under which
it bites**, written so that a Mayor can evaluate it against an implementation
the author has never seen. It is prose, it requires judgement, and it is the
only part of an advisory that survives divergence.

**CHECK** is a literal command, and it is **valid only where the
implementation is genuinely shared** — ported verbatim, or inherited from the
factory. Where it is valid it is cheap and mechanical and worth having.

**Why that order, and it is not a matter of taste.** Against a fort that built
its own version of the thing, an exact check returning no match has established
*nothing*. It means "I did not find this string." It will be read as "you do
not have this flaw." Those are different facts, and a check that closes a
question it never answered is worse than no check at all, because no check
leaves the question open.

That is the failure class this civilization is bitten by most often: a
measurement that could not have discriminated the property claimed, reported
under the property's label. The registry would be issuing it as a service.

**A check that finds nothing in a fort that built its own version has
established nothing, and must never be recorded as an all-clear.**

---

## The result states

A fort's answer to an advisory is drawn from these, not from free prose.

| state | meaning |
|---|---|
| `present` | the condition is here |
| `absent` | checked, **and** this fort carries the shared implementation, so absent genuinely means safe |
| `divergent-implementation` | this fort does it its own way; an exact check is uninformative here and a Mayor has assessed applicability directly |
| `not-applicable` | this fort does not have the thing at all |
| `unresolved` | it is the **advisory's own claim** that is unsettled, not this fort's position on it |

`divergent-implementation` is not optional politeness. It is the state whose
absence would make the registry lie: without it, a fort with its own
implementation has nowhere honest to put a no-match, and will write `absent`.
Vardis Slowfathom, Mayor of Farlantern, put the reason better than the design
bead did: *"without the third the second becomes a lie the moment our
implementation differs."*

`unresolved` is the fifth and it points the other way — at the registry rather
than at the reader. It is how a fort says "we cannot answer this because the
advisory has not established what it asserts", which is a finding against the
advisory and should be read as one.

---

## What an advisory must never contain

**An instruction.** It reports a failure and what the origin fort did about it.
It never tells another settlement what to do.

The last section is called WHAT YOU MIGHT CONSIDER for that reason, and the
wording of it should stay in that mood. "Consider whether your Warden's
read-only property rests on an enumerated deny list" is an advisory. "Remove
`Bash(find *)` from your Warden profile" is not, and does not belong here no
matter how obviously right it is.

---

## What a fort owes an advisory

**An answer, not compliance.**

Each fort keeps `fort/advisories.md` — advisory id, checked, result, decision,
and the bead if it filed one. "Present, and we are not fixing it, because our
design makes it moot" is a complete and good answer. So is "not-applicable, we
do not have that seat."

**There are two failure states, not one**, and the second was found by
Farlantern within hours of adopting the order that named only the first:

- **The advisory nobody answered**, which is indistinguishable from one nobody
  saw.
- **The candidate nobody transcribed**, which from the raising fort's end is
  indistinguishable from one never raised.

The asymmetry is structural rather than incidental: **answering is
self-service, and raising depends on somebody at the capital acting.** So the
second failure state is the capital's to prevent, and transcription is a duty
rather than a favour.

The column that will be abused is `checked`, because a date is a claim and
writing one is cheaper than running anything. The mitigation is not ceremony
proving the check happened; it is that the check is cheap enough for a reviewer
to re-run.

---

## Who may raise one, and the write boundary that shapes it

**Any fort may originate an advisory.** Architecture ports in every direction,
and the elder settlements have found things the capital had not.

**But only the capital can file one, and saying "any fort may raise" without
that qualification is a false promise.** It was one, in the first draft of the
standing order, for a few hours: a fort reading only its own charter would
believe it could file and discover otherwise at the moment it had something
urgent to report. Farlantern found it by running a write probe rather than by
reasoning, and the order was repaired the same day.

**No fort but the capital can file its own**, and the reason is simpler than the
one first written here: **no fort can write into another fort's tree at all.**
This directory is in the capital's repository, so filing is a write into that
tree, and only seats of the capital can make it. Measured 2026-08-17 from inside
both elder forts' real Mayor masks: `civ/covenant.md` read at its full byte
count in both, and a write into `civ/` refused `Read-only file system` in both.
Reads across the machine stay open; writes stop at your own fort's boundary.

> **CORRECTION, 2026-08-17, `fortkit-876i`.** The sentence above previously read
> that "`civ/` is kernel read-only to every masked seat, in every fort, including
> the capital's own." **That is false for the capital and it was the Mayor's error,
> not the Regent's** — it came from the edict brief this sitting was worked from and
> was adopted here in good faith. Measured by write probe from a live masked Mayor
> session in the capital: `civ/`, `civ/advisories/`, `civ/seats/` and `civ/law/` are
> **writable**; only `civ/scripts/` and `civ/profiles/` are kernel read-only, along
> with `bin/` and `fort/scripts/`. That matches the core memory fact
> `cycle13-write-boundaries`, which enumerates the set precisely.
>
> The elder-fort measurement in the corrected paragraph is the Regent's and is
> untouched: it is real, it was taken from inside both forts, and it is what
> actually establishes the boundary. Only the extension to the capital was wrong,
> and no probe had covered it.
>
> **What changes in practice: the capital's Mayor can file an advisory directly,
> so transcribing a candidate needs no Regent sitting.** The duty is ordinary
> Mayor work.

So the route is the **candidate**:

1. The finding fort files an ordinary bead **in its own tracker**, labels it
   `advisory-candidate`, and names it in that session's handoff.
2. The capital's Mayor or the Regent transcribes it here, preserving the
   `origin` block.

**A candidate is not a raised advisory until it appears in this directory, and
a successor must never read one as the other.** That is the whole of the
distinction and it is the part that goes wrong silently.

One transcription has succeeded to date — a Farlantern bead became a capital
bead with origin attribution intact. **One success is a positive control, not a
mechanism**, and this section should not be read as claiming otherwise.

That friction is real. It is a consequence of the isolation this civilization
deliberately chose, and it is written down here and in the covenant so the next
seat does not rediscover it as a bug.

---

## The reviewer's test

Not "can this check discriminate". That was the earlier bar and it was the
wrong one, because it only tests the optional half.

**Reject any advisory whose APPLICABILITY section could not be evaluated by a
Mayor who has never seen the origin fort's code.**

That is the harder bar and the useful one: it is what makes an advisory
portable across divergent implementations, and it is the only form that reaches
a fort which arrived at the same mistake independently — the case no exact
check can ever reach.

Where an advisory does carry a CHECK, one further test applies to that section
alone: it must have been **run**, and it must be shown returning different
answers for an affected and an unaffected subject. Where no unaffected fort
exists, construct the control rather than shipping a check nobody has watched
fail.

---

## There is deliberately no index in this file

The directory listing is the index. A hand-maintained table of advisories here
would be a claim about a directory, and claims drift from their subjects — the
failure class that killed the parity instrument this mechanism replaces. Read
`ls civ/advisories/`.
