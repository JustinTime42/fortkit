# The law ledger — the charter becomes a constitution and a corpus

Status: DRAFT — pending Overseer approval on fortkit-gbhk.2.
Author: Emrith Cairnwright (Mayor), 2026-08-29.
Bead: fortkit-gbhk.2 (epic fortkit-gbhk). Decision of record: fortkit-gbhk.1.
Provenance: the Overseer's approval of full migration on 2026-08-29, with the
condition recorded in §5; the memory architecture in `docs/specs/memory.md`,
which this spec deliberately mirrors; and Steve Yegge's "Fences, not Sandboxes",
cited as data per standing order 8.

This spec captures WHAT and WHY. Interfaces belong in code.

## 1. The problem, measured

`fort/charter.md` is 125 lines and 4,513 words. Standing order 7 makes records
append-only, so corrections to the charter accumulate **in place**, as inline
parentheticals inside the clause they correct:

- Standing order 12 contains an amendment correcting a **verb tense inside
  standing order 12**, filed because the stale tense was about to be copied
  verbatim into two more settlements.
- Standing order 13 contains a paragraph explaining which of **its own
  paragraphs** are portable, with a word-level diff count against the template.
- The threat model contains a removed residual preserved as a struck-through
  block explaining why it was removed.

Every one of those is correct under SO7 and every one makes the document harder
to read than the law it carries. A fresh seat is told at session start to read
this file.

And the back half of the lifecycle is missing entirely. The event stream carries
38 `charter.amended` and 40 `incident` events and **no event for a rule
firing**. So "has this rule ever caught anything" is unanswerable, nothing can be
retired on evidence, and the corpus can only grow.

Yegge reports the same accretion at larger scale (450 legal artifacts, obsolete
rulings, rulings that were "just good craftsmanship") and answered it by
creating an officer seat to curate the corpus. This fort's answer is cheaper: it
already owns the pattern.

## 2. The shape

Identical in structure to `docs/specs/memory.md`, which is the proven sibling.

| Path | Role | Trust |
|---|---|---|
| `fort/law/rulings/<key>.md` | one ruling per file | store of record |
| `fort/law/current.md` | generated view of active law | derived, tracked |
| `fort/charter.md` | the constitution | store of record, short and stable |

**What stays in the charter:** purpose, the seats table and occupants, the human
gates, the threat model, the amendment rule, the civilization-layer section, and
a pointer. Short enough that a stranger reads it in one sitting, which is what
the Mayor's seat file says the charter is for.

**What moves to the ledger:** the standing orders, the accepted residuals, the
prose-gate rulings, and the amendment record.

## 3. Standing order 7, and why this is permitted

The precedent is borrowed rather than invented. **Overseer ruling 2 on
`fortkit-88u.2`** (2026-08-10) held that append-only law binds records of *what
happened* — beads, handoffs, verdicts, events — and not *current-state facts*,
with git as the supersession chain. That ruling is what let the memory ledger
exist at all.

Rulings are current-state facts about the law. The same ruling covers them.

Concretely: nothing is edited in place, a superseded ruling keeps
`status: superseded` in the ledger, a retired one keeps `status: retired`, and
git holds the history of both. **If a reviewer finds that analogy strained, the
migration stops rather than proceeding under a stretched reading.** The whole
value of the restructure is that the fort's law becomes easier to trust, and
buying that with a strained reading of the order that makes records trustworthy
would be a bad trade.

## 4. The ruling

```markdown
---
key: standing-order-append-only-records
status: active                    # proposed | active | superseded | retired
superseded-by: null
kind: ratchet                     # from docs/specs/enforcement-vocabulary.md
scope:
  seats: [all]
  topics: [records, corrections]
enacted-by: fortkit-zpw8          # the bead that carried it
approved: 2026-08-11              # Overseer's approval date
last-fired: null                  # set from rule.fired events
retirement:                       # present only when status: retired
  approved-by: null               # overseer | regent — REQUIRED to retire
  bead: null                      # REQUIRED to retire
  event: null                     # REQUIRED to retire
provenance:
  source: "fort/charter.md:55 at commit <sha>"
  declared-by: emrith
  date: 2026-08-29
---
Records are append-only: beads, handoffs, review verdicts, events. Corrections
are appended to a bead's `comments`; `notes` carry working state only.
```

**The claim rule.** A ruling that asserts something about code carries a
`file:line`, and that citation is checked mechanically by `law-lint`. This is
the constitution's answer to the fort's worst measured failure class.
`fortkit-bjd8` is the standing instance and it is a good one: the charter's
`fortkit-3jv7` residual cites two `seat-sandbox.sh` line numbers that are **both
comment lines**, inside the very paragraph admitting that its own claim is
unasserted by any test.

**`kind` comes from the enforcement vocabulary.** This is the seam that makes
the two epics worth doing together: a ruling that cannot say what kind of
control it is has not been thought through, and the register
(`fort/controls/`) is where its mechanism is registered.

## 5. Retirement

> **The Overseer's condition, 2026-08-29, on which full migration was approved:
> rule retirement must never happen silently, and never without an Overseer or
> Regent approval gate.**

That is a term of the approval rather than a preference to be traded later. Four
rules follow from it, and `law-lint` enforces all four.

1. **No generator, watcher, or lint may ever set `status: retired`.** They may
   only *report* retirement candidates.
2. **Retirement takes two keys.** *Evidence:* the ruling has never fired after a
   stated observation window, or it is superseded by a named successor.
   *Approval:* an Overseer or Regent decision recorded on a bead, naming the
   ruling. **No seat may supply the second key, the Mayor included.** Neither
   key alone retires anything.
3. **Retirement emits an event.** A ruling that leaves the corpus with no
   announcing event is precisely the signature the charter's civilization-layer
   section already tells every seat to escalate as a possible compromise.
4. **The ruling stays in the ledger** with `status: retired`. Retirement is a
   status flip and never a deletion, so the ledger stays append-only and the
   retirement is itself auditable.

**Why 1 and 2 are separate rules.** Rule 1 keeps the *detector* and the
*actuator* in different hands. A tool that both finds dead law and removes it is
a tool that can quietly rewrite the constitution, which is the single outcome
this design must not permit. `law-lint` reports; a human approves; a bead
records; an event announces.

**Never firing is not the same as being dead.** A rule guarding a rare
catastrophe is doing its job precisely by never firing. `fortkit-gbhk.7`
requires every candidate to be classified as *dead-law* or *rare-catastrophic*,
and that judgement is the substance of the work. **A high retirement count is
not success**; treating it as one would give the fort an incentive to prune its
own law, which is worse than the accretion this spec is curing.

## 6. Lifecycle

`proposed → ratified → enacted → enforced → measured → amended → superseded |
retired`

Seven of the eight already happen here informally. **`measured` is the one the
fort has never had**, and it is why the corpus only grows. It arrives with
`rule.fired` (`fortkit-gbhk.6`), which is also what makes key 1 of §5 producible
rather than a matter of opinion.

## 7. The read path

The migration strands every seat unless the read path moves in the same batch.
`CLAUDE.md`, `AGENTS.md`, the session-start protocol in every `fort/seats/*.md`,
and the launchers all name `fort/charter.md` today.

`fortkit-xgul.6` is the standing instance of exactly this failure: four live
launchers still name the retired `fort/remember.md`, months after it retired.

## 8. Risk, and the condition for abandoning

This is the fort's constitution, and **a migration that silently drops a clause
is the worst outcome available** — undetectable by exactly the machinery meant
to replace hand-reading.

`fortkit-gbhk.4` is the mitigation and it **blocks the cutover**: every paragraph
of the pre-migration charter must map to a ruling, to retained constitution
text, or to an explicit retirement, verified by a script over a pinned commit.
That checker must carry a negative control — deleting a paragraph must turn it
red — and the negative control must be proven *before* any green is trusted.

**If the check cannot be made to work mechanically, abandon the restructure
rather than complete it by hand.** That is an acceptable outcome of that bead
and not a failure to be worked around.

## 9. Portability

Per standing order 13 this reaches the elder forts as an advisory
(`fortkit-gbhk.8`), and declining is a complete answer.

The advisory carries **the measurement, not the prescription**: that this
charter reached 4,513 words under SO7 and how that was measured. A Mayor whose
charter is 900 words should read that and correctly decline.
