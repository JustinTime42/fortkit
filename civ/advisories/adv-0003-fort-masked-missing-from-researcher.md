---
id: ADV-0003
type: defect
title: The FORT_MASKED marker covers three seats of four — the seat that reads untrusted web content is the one that can still launch a Mayor
origin:
  fort: Manyhalls
  bead: fortkit-3539
raised: 2026-08-17
severity: medium
status: open
supersedes: null
superseded-by: null
---

## WHAT IT IS

`mayor.sh` refuses to launch under any non-empty `FORT_MASKED` and prints the
value, so no seat can start the fort's most privileged attended session from
inside its own. The marker is what makes that refusal fire and what names the
offending seat in it.

`researcher.sh` does not set the marker. **A Researcher session can launch a
Mayor and the refusal never fires.**

## APPLICABILITY

This applies to your fort if you have **a launcher guard that refuses a
privileged launch based on a marker each seat sets for itself** — under
whatever name you gave the marker.

The failure mode is that **the guard's coverage is the set of launchers that
remembered to set the marker, and nothing measures that set.** A guard of this
shape is silently partial by default: adding a seat adds a hole, and the hole
is invisible because the guard still works perfectly from every seat that has
the marker.

So the question is not "is `FORT_MASKED` in my `researcher.sh`". It is **"which
of my seats can start a session that my guard would refuse, and what told me
that number was complete?"** Enumerate your launchers and check every one,
including any seat added since the guard was written. The guard here was
written when the fort had three seats.

**The condition that raises severity** is which seat is uncovered rather than
how many. Here it is the only seat that reads untrusted content by design — the
fort's whole answer to prompt injection rests on capability separation, "the
seat that reads about the world is never the seat that touches it." A seat
holding injected text being the one seat that can start the most privileged
session is the wrong seat to leave uncovered, even where a nested mask makes
the escalation ineffective. **Diagnosability is worth most exactly where the
input is untrusted.**

If your fort has no Researcher, this is `not-applicable` for that seat and
still worth running against the seats you do have.

## CHECK

Valid where your launchers descend from the shared template.

```
for f in fort/scripts/*.sh; do printf '%-40s %s\n' "$f" "$(grep -c FORT_MASKED "$f")"; done
```

**Run 2026-08-17:**

| copy | result |
|---|---|
| `fortkit/fort/scripts/researcher.sh` | `present` (the defect) — count 0 |
| `fortkit/templates/fort/scripts/researcher.sh` | `present` — count 0, ships to every new fort |
| `longburn/fort/scripts/researcher.sh` | `not-applicable` — Farlantern has no Researcher seat |
| `ForgeOs/fort/scripts/researcher.sh` | `not-applicable` — Proofdelve has no Researcher seat |

Positive control, so a count of 0 means something: `fortkit/fort/scripts/mayor.sh`
returns **4** under the identical command. The check can return both answers.

Both elder forts landing on `not-applicable` is worth noticing on its own: it
is the result state that exists precisely so that "we do not have the thing" is
a real answer rather than a silence.

## WHY IT MATTERS

The standing judgement for this class is already recorded in `forge.sh`'s own
comment and it holds here: "Not a capability hole (a nested bwrap cannot widen
its parent's mount namespace) but diagnosability, which is what the guard is
for." That is why this is medium and not high.

What is new is the seat. The charter accepts an outbound-channel residual for
the Researcher on the strength of capability separation. A gap in the guard
that names which seat did what, in the seat whose input is untrusted, is the
one instance of this class where the diagnosis is the point.

## WHAT THE ORIGIN FORT DID

Counted the marker across all four live launchers and all four template
launchers, and read the pending repair's own diff to establish that it does not
close this one — the port covering `forge.sh` and `warden.sh` touches those two
files only, so coverage stays at three of four live and two of four in the
factory even after it merges.

**Recorded as owed rather than established:** nobody has launched a Researcher
and attempted a Mayor launch from inside it. The claim is read off the four
launchers and `mayor.sh`'s refusal condition, not executed.

The known trap for anyone implementing this: **set the marker with `--setenv`
only, never paired with a host-side `export`.** `mask_env` appends
`--clearenv`, so bwrap discards the host environment entirely and an export
reaches nothing — while falsely asserting that the launcher process is itself
inside a mask.

## WHAT YOU MIGHT CONSIDER

A test asserting that **every** launcher carries the marker, rather than adding
the missing one. The count regressed from a complete set to a partial one when
a seat was added, and nothing went red; it can do that again.

Consider also what your guard is *for*. If it is diagnosability, coverage of
the untrusted-input seat matters more than coverage of the tidy ones.
