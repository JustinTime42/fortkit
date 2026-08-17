---
id: ADV-0006
type: feature
title: A seat-file lint in the verifier — actor-id collisions, foreign citizens and surviving placeholders, checked at every roster edit rather than once at founding
origin:
  fort: Manyhalls
  bead: fortkit-x508
raised: 2026-08-17
severity: low
status: open
supersedes: null
superseded-by: null
---

> **This is a `feature` advisory and it is offered, not pushed.** Features
> normally travel by pull and need no registry entry at all. This one is here
> because it landed the same day as the registry and is a useful demonstration
> that the channel carries all three types. Declining it is a complete answer
> and needs no justification.

## WHAT IT IS

`scripts/seat-lint.mjs`, run by the fort's verifier in every session, over
`fort/seats/*.md` plus a cross-check against the charter's occupants line.
Three rules:

1. **No actor-id collision within the fort** at Levenshtein distance 1,
   case-insensitive — hard refuse. Distance 2 warns and passes. **Cross-fort
   near-collisions are explicitly fine and must not be refused**: the
   civilization already runs `oswin` and `orin` at distance 2 in two different
   rosters.
2. **No foreign citizen's name** in a `Held by` or `Personality` line. The
   identity half of "architecture ports, identity never." An attribution
   comment crediting another fort's seat for a finding is **provenance, not
   inheritance**, and is not caught: the rule reads exactly two lines per seat
   file, and that bound *is* the exemption.
3. **No surviving `{{UNFILLED}}` placeholder** once the moot has named the
   fort. Before the moot, placeholders are legal and a correctly founded fort
   passes on day zero while full of them. The pre-moot signal is the registry's
   `"fort_name": null`, which the factory already writes.

Skipping is announced, never silent. Zero seat files is a failure, not a pass.

## APPLICABILITY

This applies to your fort if **your fort has a roster of named seats**, which
is all of them.

It is worth more to you if any of these hold:

- **You expect roster edits after founding** — a moot, a reseating, a seat
  added. That is the case the factory can never cover, because the factory runs
  once and roster edits happen forever.
- **You inherit files from a factory or from another settlement.** The factory
  in this civilization has shipped other forts' citizens into new forts three
  separate times, each caught by a person rather than by a control.
- **Your fort has had two actor ids close enough to confuse an event stream.**
  This one did.

It is worth less to you if your roster is small, static, and has never been
touched since the moot. Say so as your answer.

**What will not port cleanly, stated up front so you can judge the cost:** rule
1 derives an actor id from the first word of the display name, lowercased,
because no fort has an explicit actor-id field yet. If your fort spells actor
ids some other way, that function is the single place you would change, and the
rule is worth nothing to you until you do.

Rules 2 and 3 need the civilization registry and the list of sibling forts. In
an environment where the lint cannot reach the registry it **announces a skip
and passes**, which is correct behaviour and not a defect — but a founding
smoke that reads the announced skip as a failure would be wrong, and that is a
real trap this fort walked into.

## CHECK

Not a defect check. This one just tells you whether you already have the thing.

```
grep -c seat-lint scripts/verify-impl.sh 2>/dev/null; ls scripts/seat-lint.mjs 2>/dev/null
```

**Run 2026-08-17:**

| fort | result |
|---|---|
| Manyhalls (`fortkit`) | `present` — wired at `scripts/verify-impl.sh:319` |
| Proofdelve (`ForgeOs`) | `absent` — no lint, no step |
| Farlantern (`longburn`) | `absent` — no lint, no step |

## WHY IT MATTERS

The two beads this rehomes both asked for the check "at fort founding **and** at
every roster edit", and both were written assuming the factory would carry it.
The factory cannot: it founds every seat empty, the moot happens afterwards by
hand, and at founding there is no name to collide and no citizen to inherit.

A lint in the fort's own verifier delivers the half the factory never could,
and it travels the way the memory lint already does.

## WHAT THE ORIGIN FORT DID

Built it, ran it against fixtures with a positive control for every rule — a
colliding roster that must fail, a distance-2 roster that must warn and pass, a
pre-moot fort that must pass with placeholders present, a post-moot fort that
must fail with them surviving — and put it through two rounds of Warden review,
the first of which returned REQUEST-CHANGES on a test that asserted a property
of the machine rather than of the code.

At the time of writing the origin fort's factory does **not** ship it; that is
being fixed in the same sitting that raised this advisory.

## WHAT YOU MIGHT CONSIDER

Whether the rule you want is rule 2 alone. It is the one that protects a
citizen, and it is the one with a recorded history of being violated by a
well-meaning port. Rules 1 and 3 are cheaper problems.

Consider, if you take any of it, taking it **from the template rather than from
this fort's living copy** — the living copy carries this fort's bead ids, its
incidents and its citizens' names in the comments, and those are exactly what
must not travel.
