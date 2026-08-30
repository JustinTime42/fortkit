# The enforcement vocabulary — what kind of thing each control is

Status: DRAFT — pending Overseer approval on fortkit-4ah3.1 (gate-1).
Author: Emrith Cairnwright (Mayor), 2026-08-29.
Bead: fortkit-4ah3.1 (epic fortkit-4ah3).
Provenance: the Overseer's direction of 2026-08-29 to read Steve Yegge's
"Fences, not Sandboxes" (yegge.ai, 2026-08) against this fort's architecture,
and his approval of the eight-primitive shape in the same session. Every
citation below was read from the tree on 2026-08-29, not recalled.

This spec captures WHAT and WHY. The register that applies it is
fortkit-4ah3.2; the lint that keeps it honest is fortkit-4ah3.3.

## 1. Purpose

This fort runs a large number of distinct controls and has one word for them:
*gate*. That word currently covers a kernel bind the seat cannot form an intent
against, a deny glob a seat with a shell defeats, a sentence in the charter a
seat honours by choice, and a human decision routed to the Overseer. Four
different promises under one noun.

**How large a number is itself unsettled, and saying so is the point.** Counted
on 2026-08-29: 14 wall-declaration sites in `seat-sandbox.sh`, two permission
profiles carrying 48 deny entries between them, 10 verifier stages, 2 wired
lints, a 63-assertion mask harness, one host-side probe, one drift watcher, 13
standing orders and 3 human gates. Whether that is 40 controls or 150 depends
entirely on granularity, and the fort has never had to choose because it has
never had a register. Fixing the granularity is fortkit-4ah3.2's first job, and
this spec deliberately does not guess at a total.

The cost is measurable in the charter itself. `fort/charter.md` carries an
entire section, "Prose gates", whose main work is explaining that one kind of
gate is weaker than another: *"A prose gate is one a model chooses to honour;
it is not one it cannot cross."* That sentence is a definition doing duty as a
paragraph, and it has to be restated in prose every time the distinction
matters, which is one reason the charter has reached 4,513 words.

The second cost is invisible rather than verbose. With one word, the fort
cannot ask *"which kinds of control do we have none of?"* It has never asked,
and the answer turns out to be interesting (§6).

Yegge reports the same discovery from the other direction: his agents
spontaneously produced seven such words (fence, ratchet, governor, tripwire,
latch, gate, falsifier) before he investigated what they meant. This spec is
not an import of his list. It is this fort's own controls, sorted, with the
words chosen to match where they fit and replaced where they do not.

## 2. The two axes

Every control answers two questions, and the primitives are what you get when
you cross them.

**WHEN does it act?** Before the action can be formed · at the moment of the
action · after the action · on demand, against a claim.

**WHAT does it do?** Refuse · bound a quantity · permit one direction only ·
detect and announce · hold a state.

A word that does not pin down both answers is not a primitive and does not
belong here.

## 3. The primitives

| Primitive | When | What | Defeated by |
|---|---|---|---|
| **Wall** | before intent | refuses | nothing available to a masked seat |
| **Fence** | at the action | refuses | a seat holding a shell |
| **Prose gate** | at the action | refuses | the seat deciding otherwise |
| **Ratchet** | continuously | permits one direction | an actor outside the ratchet's reach |
| **Governor** | continuously | bounds a quantity | widening the bound |
| **Tripwire** | after | detects conduct | acting where it does not watch |
| **Falsifier** | on demand | detects a false claim | a claim it cannot discriminate |
| **Latch** | after tripping | holds state | clearing it |

### 3.1 Wall

**Definition.** A control that refuses at the kernel, so the masked seat cannot
form the action at all. It is not a decision the seat makes and not a policy
the seat consults; the syscall fails.

**Discriminating test.** *Does a seat holding an unrestricted shell defeat it?*
If no, it is a wall.

**Live citation.** `fort/scripts/lib/seat-sandbox.sh:428` binds every path in
`RO_PATHS` with `--ro-bind`; `:481` replaces every directory in `MASK_DIRS`
with `--tmpfs`. `:386` binds `fort/scripts` read-only for every seat type.

**Note.** This is what Yegge calls a sandbox and argues against. This fort has
the most of them, deliberately, and §7 states why that disagreement is
deliberate rather than unexamined.

### 3.2 Fence

**Definition.** A control that refuses at the tool or policy layer, in a place
where the kernel would have allowed the action. It works because the runtime
consults it, and it therefore binds a *spelling* rather than a *file*.

**Discriminating test.** *Does a seat holding an unrestricted shell defeat it?*
If yes, and there is still a mechanical refusal, it is a fence.

**Live citation.** `fort/profiles/warden-settings.json:46` opens the Warden's
`deny` array. The file's own `$comment` at `:2` is the clearest statement of
fence-ness this fort has ever written, and it was written two years before the
word existed here: *"Treat the allow list as convenience, the deny list as the
boundary"*, and *"deny globs bind a spelling, not a file."*

**Why the distinction earns its keep.** The accepted residual on `fortkit-3jv7`
exists entirely because one property is fence-enforced where the fort's prose
implied it was wall-enforced. The charter needs a full paragraph to say that.
With these words it is one sentence: the Warden's read-only property is a fence
at `~/.codex` and a wall everywhere else.

### 3.3 Prose gate

**Definition.** A control that refuses only through the seat's own reading of
it. There is no mechanical refusal anywhere in the path.

**Discriminating test.** *Is there any mechanical refusal at all?* If no, it is
a prose gate.

**Live citation.** `fort/charter.md`, section "Prose gates": the Mayor's push
and deploy gate, and charter and seat-file amendments for attended seats.

**Retained name.** The charter already uses this term correctly and has since
cycle 6. Nothing about it changes; it gains six siblings.

### 3.4 Ratchet

**Definition.** A control that permits movement in one direction only. It does
not refuse the action, it refuses the *reversal*.

**Discriminating test.** *Does it bound a quantity, or a direction?* Direction
means ratchet.

**Live citations.** `fort/charter.md:55`, standing order 7: *"Records are
append-only: beads, handoffs, review verdicts, events — never falsified or
pruned."* And `schema/events.md:1`, which declares the event categories
*"add-only, never rename"*.

**Finding this classification produces immediately.** Both examples are
ratchets *made of prose*. Nothing mechanically prevents a category from being
renamed or a record from being edited. A prose ratchet is a real control and it
is also weaker than the fort's writing implies, which is the same asymmetry
§3.2 found for the Warden. Whether that matters is for the register (A2) to
report, not for this spec to assert.

### 3.5 Governor

**Definition.** A control that bounds a quantity or a rate rather than an
action. It permits the thing and constrains how much of it.

**Discriminating test.** *Would raising a number make it permit more?* If yes,
it is a governor.

**Live citation.** `scripts/memory-lint.mjs:10`, `const coreLineBudget = 300`,
enforced per seat and reported at `:270`. This is the fort's only governor and
its bound came from a measured degradation threshold rather than a preference.

### 3.6 Tripwire

**Definition.** A control that detects **conduct** after it has happened and
announces it. It never refuses and never blocks.

**Discriminating test.** *Does it watch an actor's behaviour, or a
proposition?* Behaviour means tripwire.

**Live citation.** `civ/scripts/drift-watch.mjs`, which emits `drift.scan`
events (17 in the record as of 2026-08-29) and files beads for what it finds.

### 3.7 Falsifier

**Definition.** A control that goes red when a **claim** stops being true. It
watches a proposition rather than an actor, and its subject is usually a
sentence the fort has written about itself.

**Discriminating test.** *What result would have falsified the claim?* If the
control has an answer, and the answer is a result it can actually produce, it
is a falsifier. If no plausible failure of the property would change the
control's output, it is not one, whatever it is called.

**Live citation.** `fort/scripts/probe-cycle7.sh:15` carries a **positive
control for "writable"**, added under `fortkit-52vf.1`. That line is the
distinction in miniature: a probe without a positive control is a tripwire
wearing a falsifier's name, because it cannot tell "the property holds" from
"the probe is broken." `scripts/mask-harness.sh` is the fort's largest
falsifier, scoring assertion sets against a mask library.

**Relationship to existing law.** The discriminating test above is the cheap
test from [[read-the-artifact-remember-the-why]], applied to machinery instead
of prose. That memory names both halves as required and this vocabulary is why
they are separable: the prose half is a claim, the machinery half is a
falsifier over it.

### 3.8 Latch

**Definition.** A control that holds a tripped state until something explicitly
clears it. Its purpose is to survive the next clean run.

**Discriminating test.** *Does a subsequent clean run erase the record of the
trip?* If yes, it is a tripwire. If the state persists until cleared, it is a
latch.

**Evidence that this fort needs one, per standing order 11.** `fortkit-6ps` is
open and observed: *"forge.sh: no concurrency guard or liveness record — two
launchers can work the same bead in one worktree."* A lock or lease is a latch,
and its absence is the bead. This primitive is admitted on that observed
failure, not on Yegge's word for it.

**The one latch the fort already relies on is borrowed.** `fort/charter.md:83`
describes the failover path, including *"lease expiry returns the bead to
ready"*. That lease is a latch, and it belongs to `bd` rather than to this
fort. Manyhalls has built none of its own.

## 4. Using the vocabulary: the decision procedure

Applied in order, the first test that answers classifies the control.

1. Is there any mechanical refusal? **No → prose gate.**
2. Does a seat with a shell defeat it? **Yes → fence. No → wall.**
3. Does it refuse a reversal rather than an action? **→ ratchet.**
4. Would raising a number make it permit more? **→ governor.**
5. Does it watch a proposition rather than an actor? **→ falsifier.**
6. Does it watch an actor and only announce? **→ tripwire.**
7. Does its state survive the next clean run? **→ latch.**

A control that answers to two of these is two controls and is registered
twice. This is common and not a defect: `verify-impl.sh` is a fence over
merges and a harness of falsifiers at the same time.

## 5. What this spec deliberately does not do

- It does not rank the primitives. A wall is not "better" than a prose gate;
  they buy different things at different costs, and the charter already records
  one place where a wall was traded away knowingly.
- It does not mandate that any control change kind. Classification is
  description first. Any retrofit is a separate bead with its own evidence.
- It does not define the register's file format. That is fortkit-4ah3.2.

## 6. Findings the classification already produces

Recorded here as predictions to be confirmed or refuted by the register (A2),
not as established results. Each becomes a bead under A4 only if it survives.

1. **One governor, and one borrowed latch.** The fort has many refusals and
   almost no bounds or held states.
2. **`fortkit-dqu5` is a tripwire with no falsifier over it.** The constitution
   watch read a truncated event list and reported three announced amendments as
   unannounced. A falsifier with a positive control could not have returned
   that. This is the clearest evidence that the missing word was costing
   something.
3. **`schema/events.md` is a prose gate presenting as a fence.**
   `fort/scripts/emit.sh:16-18` validates only that the category is non-empty
   and does not begin with `-`. Any string is accepted. Filed as A4
   (fortkit-4ah3.4, Regent lane).
4. **Two of the fort's ratchets are prose** (§3.4).
5. **Four kinds of refusal have been sharing one noun throughout the charter**,
   which is a direct contributor to its length.

## 7. On Yegge's argument, and why this fort keeps its walls

The essay's thesis is that walls are the wrong instrument and fences are the
right one, because a sufficiently capable agent walks around a wall and honours
a rule it understands.

This fort declines that conclusion, and the reason is in `fort/charter.md`'s
threat model rather than in a preference. Threat 1 is **agent accident**, and
the charter records that *every incident actually recorded in any fort is in
that class*. A fence does nothing against accident. The seat that runs the
wrong command was not reasoning about the rule.

The part of the essay this fort does take is narrower and, read carefully, is
what his own system does: the **reason** and the **mechanism** are separate
artifacts, and both are written down. His fence keeping Fable as the only seat
that talks to humans is enforced at the Slack and email boundaries, which is a
wall with a rule attached. This vocabulary is what lets Manyhalls say that in
one line per control instead of a paragraph, and `fortkit-qj3` (open, gate-1,
*"narrow human gate 1 prose to what the mask actually enforces"*) is the same
observation, filed here before the essay was read.

## 8. Open items

- **Latch is the weakest primitive in this draft.** It is admitted on
  `fortkit-6ps` and on a borrowed lease. If the Overseer judges that
  insufficient, drop to seven primitives and refile latch when the fort builds
  one. Shipping an eighth primitive justified by an imagined need would violate
  standing order 11 inside the spec that cites it.
- **Portability is not assumed.** Per standing order 13 this reaches the elder
  forts as an advisory (A6) and declining is a complete answer. A fort that
  distinguishes its controls some other way is right to keep its own.
