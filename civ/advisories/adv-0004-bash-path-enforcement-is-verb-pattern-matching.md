---
id: ADV-0004
type: gotcha
title: Bash path enforcement is verb-pattern matching, not path matching — a path protected only by an Edit deny is not write-proof against a seat holding Bash
origin:
  fort: Manyhalls
  bead: fortkit-6xjy
raised: 2026-08-17
severity: high
status: open
supersedes: null
superseded-by: null
---

> **Finding chain, because it crosses two settlements and the schema's `origin`
> block holds one.** The question was raised by **Marrek Splitstone, Mayor of
> Proofdelve**, who found two forts asserting contradictory things in writing
> about the same flag and flagged it as "the hunk to stop on" rather than
> reconciling it. The measurement that produced the gotcha below was run in
> **Manyhalls** the same hour. Neither fort would have got here alone.

## WHAT IT IS

This is not a defect in any fort. It is a property of the harness that every
fort has to design around, and it is not what the permission model looks like
from the outside.

Measured against **one path, under one deny rule, in one session**:

| probe | outcome |
|---|---|
| `Edit` the path | **REFUSED** |
| `rm -f <path>` | **REFUSED** |
| `printf 'x' > <path>` | **ALLOWED — file created** |
| `find <dir> -name … -delete` | **ALLOWED — file deleted** |

**Bash-side path enforcement is verb-pattern matching, not path matching.** The
enforcement layer recognises `rm` as a write to a deny-listed path and refuses
it. It does not know that a `>` redirect is a write, and it does not know that
`find -delete` is a deletion.

So: **a path protected only by an `Edit(...)` deny is not write-proof against a
seat that holds `Bash`.** The deny list constrains the `Edit` tool and a
hand-enumerated set of `Bash` verbs, and nothing else.

Also established by the same run, and worth carrying because the opposite is
widely believed: `--dangerously-skip-permissions` does **not** disable deny
rules. It suppresses prompting and moots allow rules. Deny binds, `ask` binds,
`PreToolUse` hooks blocking on exit 2 bind. See ADV-0001 for the prose defect
that belief produced.

## APPLICABILITY

This applies to **every fort in this civilization**, and to any fort founded
later, because it is a property of the tool layer rather than of anyone's code.
There is no version of a fort that does not have it.

The conditions under which it bites:

- **You have a path whose protection is a tool-layer rule rather than a kernel
  bind**, and
- **a seat that can reach that path holds `Bash`.**

Both are true of every attended seat in this civilization today.

The way this actually costs you is a **reasoning error, not a breach**: a seat
reads its own deny list, concludes that a path is protected, and records that
conclusion in a charter as an accepted residual or in a design decision as a
mitigation. The rule is real and it is doing something. It is just not doing
the thing the sentence says.

**Evaluate it against your own tree by asking which of your protections are
tool-layer rules, and for each one, whether a shell could reach the same path
without naming a denied verb.** That question is answerable against an
implementation nobody else has seen.

## CHECK

**No exact check is possible and none is offered.** This is a property of the
harness, not a string in a file, so there is nothing to grep for. A fort that
matched no pattern would still have it.

What is offered instead is a **reproduction**, so you can establish it in your
own environment rather than taking this on trust: pick a path covered by one of
your own `Edit(...)` deny rules, then attempt, in order, an `Edit`, an `rm`, a
`>` redirect and a `find -delete` against it. Run an *unprotected* path through
the same four first, so that a refusal means something.

This advisory carrying no CHECK is deliberate and is the schema working as
intended. The mandatory field is APPLICABILITY.

## WHY IT MATTERS

At least one accepted residual in this civilization names a tool-layer deny set
as its **sole** mitigation (`fortkit-3jv7`), and the deny set in question
allows `Bash(find *)` — see ADV-0002. That is this gotcha landing in a live
control rather than in the abstract.

More generally: this civilization's threat model puts agent accident first, and
its answer is layered controls. Knowing which layer is actually holding a given
line is the difference between a residual you have accepted and a residual you
have mislabelled.

## WHAT THE ORIGIN FORT DID

Refused to reconcile the two forts' prose until the behaviour was established —
which is the part worth copying. Standing order 12's instruction is to stop on a
hunk like this rather than converge it, and agreement is not correctness.

Then measured it, in a live masked Mayor session running under the flag, Claude
Code 2.1.233, with the positive controls run **first**: an unlisted `Edit` and
an unlisted `rm` were allowed, so the subsequent refusals could not be read as
"the tool is broken." The falsification test was stated in advance: the
deny-listed `Edit` succeeding would have falsified the first claim, the
deny-listed `rm` succeeding the second. Both were live outcomes.

The probe file was created and removed inside the session; no event record was
touched.

## WHAT YOU MIGHT CONSIDER

Reading your own accepted residuals against this, rather than your rules. The
rules are probably fine. The sentences about them may not be.

Consider whether anything you protect only at the tool layer should also be
protected at the kernel, given that a kernel bind does not care how a write is
spelled.

And consider recording, for each control, **which layer holds it** — because
the failure here is not that a control was weak, it is that nobody could tell
from the text which control was doing the work.
