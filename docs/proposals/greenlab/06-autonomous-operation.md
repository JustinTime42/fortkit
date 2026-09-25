# 06: Autonomous operation, one working fort with many experiments

Status: DRAFT by the Manyhalls Mayor (Emrith), 2026-09-24, from the Overseer's
decisions in the Mayor session of that date. Replaces the single-charter reading
of Phase 5 in `05-porting-sequence.md`. Bead: `fortkit-2y2t.12` (Sitting E) and
the tree filed under it.

## What the Overseer asked for

Greenlab should research product and market gaps, brainstorm business ideas, and
run experiments that validate or kill them, as autonomously as possible, without
stopping. The fort and its citizens must learn and grow across experiments, and
a failed experiment must be something the fort discards, not something that
takes the fort down with it.

## Shape: one working fort, experiments inside it

- **Greenlab** is the civilization. **`~/dev/greenlab`** is its capital: law,
  covenant, grants, the Effect Gateway, the governor, the fort factory. No
  product or experiment work happens in the capital.
- **One working fort** holds all experiment work, with Wren Quicksow as its Mayor
  and Bex, Silas and Cass as its seats. Experiments are NOT forts. The fort's
  memory, law, seats and history persist across every experiment.
- **plot stays** as the capital's test bench: a fort whose fleet is normally off
  and whose state is disposable, where a Regent proves a template or launcher
  change before it reaches the working fort. Nobody lives there. It is not a
  second workplace.

Why a new working fort rather than promoting plot: the working fort's fleet will
be on nearly always, so changes to the fleet need somewhere else to be tested
first. Promoting plot and founding a fresh test bench is equivalent; the point is
that the always-on fort and the test bench are different forts. Plot's toy beads
and toy code have no value to carry.

## An experiment inside the fort

- **An experiment is an epic bead** with an experiment charter (below), plus a
  directory `experiments/<slug>/` holding its code, data and notes.
- **Discarding an experiment** means closing the epic with a verdict (`killed`,
  with the reason and the evidence) and leaving its directory in git history.
  Nothing else in the fort changes. That is the "discard without suicide"
  property: an experiment owns only its epic and its directory.
- **Learning survives the experiment.** Every verdict, kill or not, writes at
  least one fact to the fort's memory ledger: what was tested, what was learned,
  and what it implies for future selection. Wren reads that ledger when choosing
  what to do next. Code that proves useful beyond one experiment moves into a
  shared directory in the fort, by an ordinary bead.

## The two charters

**The mission charter** is the Overseer's, one page, rarely changed. First
version, from his words on 2026-09-24:

> Hunt widely for product and market gaps, business ideas, and ways to validate
> them. Keep the scope open and narrow it as we learn. Out of bounds: anything
> illegal; anything grossly unethical; anything that would damage the
> Overseer's reputation. Do not spend effort on ideas or actions the Overseer
> would not approve: his approval gates stop them reaching the world, but work
> that can only end at a refusal is waste.

**An experiment charter** is Wren's, one per experiment, filed on the epic:
hypothesis; the cheapest test that could disprove it; kill criterion; the
outward actions it needs (each named against a standing grant or a gate); its
loss bound under the governors; and why it was chosen now over the alternatives
(the value-of-information rule).

## The loop

research (Cass, read-only web) → idea brief → experiment charter →
**promotion review** → build (the fleet) → run (through the Effect Gateway) →
verdict (kill, iterate, or *propose* graduation, which is the Overseer's alone).

Wren runs the loop continuously and files her own beads at every stage.

## Controls on a self-feeding queue

1. **Filing check, mechanical, no model.** A self-filed bead must cite its
   experiment (or the research stage), say why it was selected, what it would
   tell us, and what it costs or sends outward. A bead that cannot is refused at
   filing.
2. **Promotion review, a model on a different vendor from Wren's.** Only at idea
   → experiment charter, where outward effects and cost begin. It checks the
   charter against the mission charter's exclusions and the standing grants, and
   refuses any charter whose outward actions would need an approval the Overseer
   would not give. Build beads inside an approved experiment are not reviewed
   here; Silas's post-merge tripwire covers them.
3. **The Overseer's weekly sample, calibration not approval.** About ten
   self-filed beads, chosen at random, each marked "would I have filed this?".
   This is how the "you'd have filed it" bar is measured.
4. **Queue governors.** A cap on concurrently running experiments and a daily
   self-filing cap, so the loop cannot flood itself.

## Outward action: gates now, a growing ruleset later

Every new external identity (gate 2) and every action outside a standing grant
goes to the Overseer, for now. As experience accumulates, approved action types
become standing grants on the Effect Gateway, each with a cost cap and an
expiry, so the list of actions agents may take alone grows by explicit grants,
never by removing a gate. Research, ideation and local prototypes need no
outward identity and run fully autonomously from the start.

## Models and capacity

- Local: `greenlab-qwen2.5-coder:7b-instruct-32k` joins the local rungs for
  coding (`fortkit-2y2t.26`). A bake-off against gpt-oss-20b and
  Qwen3-Coder-30B-A3B on a fixed bead set decides which local model stays.
- Frontier: subscription (Claude and Codex logins Greenlab already holds).
- Metered: a $50 prepaid trial of DeepSeek, direct (Overseer, 2026-09-25), as a
  frontier-class Forge rung behind the inference bridge, with the key held host
  side (`fortkit-2y2t.35`); the model-spend governor caps metered spend at $50
  (`fortkit-2y2t.17`). A two-week trial against Codex (`fortkit-2y2t.36`) feeds
  the Overseer's decision on replacing Codex in one or both civilizations
  (`fortkit-2y2t.37`).
- Planned division of labour, to be confirmed by the trial: Claude for
  judgment (Mayor, Warden, Regent, specs and tests), DeepSeek and local models
  for implementation against frontier-written tests the implementer cannot
  modify.
- The real constraint is subscription capacity, not dollars. Greenlab's logins
  SHARE the Overseer's subscription with his own work and the production forts
  (Overseer, 2026-09-24), so every frontier session Greenlab spends is one he
  does not have.

**Local-first routing is the primary control; the governor is the backstop.**
The Overseer's direction: offload as much small, easy work as possible to local
models and use the subscription only for what cannot be done well locally.

- Every seat task has a task class, and every class defaults to a local model
  (instruct or coder). A class runs on the subscription only when a written
  reason says it cannot be done well locally, and that reason is recorded in a
  routing table beside the class.
- Likely frontier classes, each to be justified or demoted by measurement:
  Wren's selection and experiment-charter judgment; the promotion review; the
  money/identity-path review (frontier permanently, covenant section 11);
  research synthesis across many sources.
- Likely local classes: bead drafting from an approved charter, filing-check
  failures and summaries, fetch-and-extract research steps, build beads under
  the Forge ladder, the ordinary post-merge tripwire (`fortkit-2y2t.22`).
- A local attempt that fails escalates by the existing ladder, and every
  escalation is counted, so the table is revised from evidence: a class that
  escalates most of the time moves up, and a frontier class that a local model
  handles in a trial moves down.
- The digest shows the local/frontier share per seat, so drift toward the
  subscription is visible.
- Backstop: a capacity governor caps concurrent frontier sessions and backs off
  on a rate-limit response rather than retrying into it.

## Proving window and handoff

Sitting E's exit is **7 days of continuous operation** in which: the queue stays
fed; no governor or gate is breached; the weekly sample clears the Overseer's
bar; and at least one experiment reaches a recorded verdict. The Overseer signs,
day-to-day Greenlab operation passes to Wren Quicksow, and operation continues
without an end date. The Manyhalls Mayor steps back to the capital.
