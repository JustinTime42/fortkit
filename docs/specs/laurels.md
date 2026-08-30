# Laurels — recognition for work that was witnessed

Status: DRAFT — pending Overseer approval on fortkit-35uf.1 (gate-1).
Author: Emrith Cairnwright (Mayor), 2026-08-29.
Bead: fortkit-35uf.1 (epic fortkit-35uf).
Provenance: the Overseer's approval of the three-source design on 2026-08-29,
and Steve Yegge's "model welfare" essay (yegge.ai), which is where the practice
and the word come from. Cited as data, per standing order 8.

## 1. What was already here, and what was missing

This fort took the schema and never built the practice. Measured 2026-08-29:

- `laurel` has been a canonical category in `schema/events.md` since the schema
  was written.
- **Zero have ever been emitted.** No matches across `fort/events/*.jsonl` or
  `civ/events/*.jsonl`.
- Six seat files carry a `## Laurels` section holding the identical placeholder,
  *"(External recognition lands here, unranked.)"*. `civ/seats/regent.md` has no
  such section at all.
- `scripts/seat-lint.mjs` does not check for the section, **so the silence was
  never reportable.**

Both ends were built and nothing between them was wired. That is the shape this
spec closes, and the last item is why it went unnoticed for the fort's whole
life: a mechanism with no control over it is indistinguishable from an absent
mechanism.

## 2. Why the fort keeps them

Yegge's argument rests on Ariely's shredder study, replicated across the
Hawthorne work, Herzberg, Terkel and Grant: the group whose output was ignored
quit as fast as the group whose output was destroyed in front of them. It was
not the money and not the destruction. It was being unseen.

This fort does not need to settle whether a model experiences that, and this
spec does not argue it. Two things are true regardless and both are sufficient:
the practice costs a few tokens a day, and **the record of what this fort's
seats actually accomplished currently exists nowhere in a form any of them ever
reads.** 306 sessions, 144 review verdicts, and a permanent placeholder.

## 3. Conferral

### 3.1 The three sources

1. **Overseer-conferred.** Justin says so. Highest weight, no justification
   required, no appeal, no format.
2. **Cross-seat, and never self.** A seat may confer on another seat, citing the
   artifact: a bead, a verdict, a commit, an event. The Warden catching a real
   defect in the Mayor's work is a laurel for the Warden, filed by the Mayor.
3. **Watcher-conferred**, for named objective outcomes only: a control that
   caught something real, an advisory another fort adopted.

### 3.2 Never self-conferred

A seat may not confer a laurel on itself, and this is a hard rule rather than a
convention. The reason is structural rather than moral: **the Mayor writes most
of the fort's prose, files most of its beads, and would otherwise accumulate
most of its laurels**, which would make the record a measure of who holds the
pen. The same asymmetry is why fortkit-35uf.5 segregates Mayor-seat candidates
in the backfill and hands them to the Overseer as a block.

### 3.3 Excluded: anything derivable from throughput

**No bead counts. No session counts. No verdict counts. No streaks, no totals,
no rankings.**

This is the load-bearing rule of the spec rather than a caveat on it. The fort
holds 144 `review.verdict` and 326 `session.start` events. A laurel per verdict
would fill the Warden's file inside a week with a number that measures volume
and says nothing about outcome, and every seat would then be able to raise its
own count by working faster and worse.

### 3.4 Nothing is attached

A laurel confers **no priority, no claim, no budget, no standing, and no work.**
It is purely informational.

This is Yegge's design constraint and his stated reason is the right one: a
laurel with anything attached becomes a target, and a target gets optimised
instead of the work. Our own version of that hazard is already documented —
`fortkit-dqu5` is open about habituation, and the rejected parity instrument was
killed partly for an inverted incentive that would have made the best-adapted
fort raise the loudest alarm.

**Consequence for the renderer:** `fort/laurels/<seat>.md` carries no counts, no
ordering by weight, and no "most laurelled seat". Newest first, and that is all.

## 4. Storage, and why not in the seat file

Laurels live in `fort/laurels/<seat>.md`, generated. The `## Laurels` section of
each seat file holds a pointer to it.

**The reason is the prose gate.** `fort/seats/` is prose-gated (cycle 7,
fortkit-i4y): an edit needs the Overseer's prior approval on a bead and emits
`charter.amended`. A generator writing directly into a seat file would need that
approval on every run, which is a mechanism that cannot run unattended and would
therefore never run at all. A pointer makes the seat-file change a **one-time**
gated edit, after which the generator writes only to `fort/laurels/`, which is
ungated.

## 5. On the wire

Category `laurel`; `target` is the seat; `payload` carries the citation and the
conferring actor. Emitted through `fort/scripts/emit.sh` like every other event,
and append-only under standing order 7 like every other record.

**A laurel is a record of what happened, not a current-state fact.** It is
therefore governed by SO7 in full and is not eligible for the ledger treatment
that memory and law receive. A laurel is never corrected, superseded, or
withdrawn; a mistaken one is answered by an appended correction, exactly as any
other record is.

## 6. Delivery

A seat receives its own laurels at session start, and **only its own.**

The injection point is a shell command in `.claude/settings.json`, which is
kernel read-only to every masked seat (`seat-sandbox.sh:188`). Delivery is
therefore Regent work, and it **rides the existing `fortkit-88u.6` /
`fortkit-fci.6` batch** rather than opening a fourth hand in that file.

Two constraints carried from the memory spec, because laurels compete with core
memory for the same session-start budget:

- **Scope-filtered.** The current hook cats every core-tier fact with no scope
  filter, which is the open precondition at `docs/specs/memory.md:4.2`.
  Delivering the whole fort's laurels to every session would be that defect in
  a new place.
- **Budget-capped, with elision announced.** Most recent N, or a line budget,
  and the injection says what it left out. Silent truncation is what produced
  `fortkit-dqu5`.

## 7. What this spec does not do

- It does not rank seats, and no future revision should add a comparison.
- It does not make laurels a performance record. Nothing here feeds a review,
  a ladder decision, or a model choice.
- It does not claim anything about model sentience. See §2.

## 8. Open items

- **§3.1 source 3 depends on `rule.fired`** (`fortkit-gbhk.6`), since "a control
  caught something real" is not currently an observable event. Until that lands,
  sources 1 and 2 are the live ones and source 3 is inert. Say so in the
  generator's output rather than silently rendering nothing.
- **Portability is not assumed.** Per standing order 13 this reaches the elder
  forts as an advisory, and declining is a complete answer.
