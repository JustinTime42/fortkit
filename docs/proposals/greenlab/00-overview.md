# 00 — Overview and rationale

## The finding that started this

Reviewing the `~/dev/autonomy` research repository against the fort/civilization
work surfaced one fact worth stating plainly: **the same architecture was built
twice in two weeks, in two materials, at two stages of life.**

- The autonomy corpus's "recommended experimental architecture"
  (`research/autonomy-architecture/analysis/REPORT.md` §12) reads: *one durable
  task ledger, one controller, one isolated worker, an artifact store, a
  verifier, a small context builder; prove an accepted task survives restart,
  duplicate delivery, and context reset; then add a merge queue and a second
  worker.* That is the Proofdelve fleet's four layers, in order.
- The `platform/workbench` specifies R01–R16 with great care and has **one
  fixture rehearsal (S013)** to show for it.
- The Proofdelve fleet has **86 runs and 341 closes** over ten days.

So the corpus is a better *description* of what the fleet is than anything in
the fort's own tree, and the fleet is the only *evidence* the corpus's thesis
has. Greenlab is the deliberate merge: the corpus's vocabulary and its
money/effect/statistics machinery, carried onto the fleet's proven, running
substrate — but pointed at greenfield experiments under a threat model that lets
almost all the work-protecting guardrails go.

## What Greenlab is for

High-volume, low-stakes, greenfield experimentation. Software prototypes,
content, small products, market probes — the "nearly autonomous business
founder" direction from `applications/business-experiments`, but built on the
fleet rather than on a bespoke runner. The defining property: **a failed unit of
work costs approximately nothing.** Delete the worktree, close the bead, move on.
That single fact is what licenses fewer guardrails.

## Why it must be a separate civilization

The Overseer's covenant already answered this, in writing, on purpose.
Civilization human gate 1 (`civ/covenant.md` §6): *"Publishing, and anything
public-facing — domains, releases, external accounts, public repositories. The
Overseer's, permanently. This gate does not move by amendment."*

A greenfield founder's entire purpose is outward action. It cannot live under
that sentence. Weakening the sentence would erode the exact protection the
current civilization's paid, customer-facing work depends on. Therefore:

- **Found the second civilization.** Its own covenant, its own gates, its own
  threat model, its own registry.
- **Do not amend the first.** The production civilization's constitution stays
  as strong as it is.

This is not a workaround; it is the covenant working as designed. The current
civilization is deliberately unable to become an outward-acting founder, and the
right response to a deliberate incapacity is a new organ, not a loosened old one.

## The core reframe: fewer *gates*, not fewer *safeguards*

"Way fewer guardrails" is the right instinct and the wrong phrase. The fort's
controls do two different jobs under one word:

1. **Protect the operator from the machine** — secret masks, host-script
   read-only binds, the credential boundary. These are **walls** (in the
   `enforcement-vocabulary.md` sense): they cost zero attention because a seat
   cannot form an intent against them.
2. **Protect the work from the agent** — the verifier as a merge gate, the
   Warden as a blocking reviewer, prose gates, human gates. These cost
   attention: every one is a place a human is asked something.

Greenlab drops job (2) almost entirely — let an experiment ship a mediocre
landing page; the market is the reviewer, and that *is* the experiment — and
keeps job (1) untouched, because the blast radius of job (1) is your accounts,
your keys, and your paying customers' repositories on the same disk.

In the vocabulary's own terms: **fewer fences and prose gates, more governors
and ratchets, walls unchanged.** A governor is a number and a ratchet is a
direction; neither asks you anything. That is how you get fewer interruptions
without fewer safeguards.

The enforcement vocabulary (`docs/specs/enforcement-vocabulary.md`) is therefore
not a fort artifact Greenlab inherits by accident — it is **the tool for deciding
which guardrails to drop.** Every control Proofdelve has gets run through the
decision procedure (§4 of that spec) and sorted into "wall — keep, free" or
"gate — drop or demote."

## What Greenlab needs that neither project has yet

Two capabilities are genuinely new. The rest is assembly.

- **The self-feeding Mayor.** The fleet's own finding was that the bottleneck
  moved from waiting to *feeding the queue*, and feeding is still a human. A
  Greenlab Mayor takes intent from an experiment charter and from observations,
  not from the Overseer, and files its own beads — each recording *why it was
  selected* (the corpus's value-of-information rule, to stop the queue becoming
  an "autonomous busywork generator"). This is prototyped in Proofdelve first,
  on software, where the domain is safe (see `../proofdelve-additions/`).
- **The effect gateway.** The seat kind the current civilization has never
  allowed: one that acts outward. It holds the credentials the reasoning seats
  never see, checks the standing grant, reserves the budget, dispatches with a
  stable operation id, and reconciles uncertain outcomes. This is the
  workbench's real contribution and the one place worth spending
  durable-execution cost.

Everything else — the fleet, bd, the masks, the Keep, the memory ledger,
fort-init — ports.
