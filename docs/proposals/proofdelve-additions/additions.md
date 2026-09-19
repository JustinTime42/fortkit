# Highest-value additions to Proofdelve

Ranked most-valuable first. Each is a bead-tree, not an advisory — adoption is
pull, and a Mayor reads each against her own tree. Each carries an evidence gate:
the observation that would show it works, stated the fort's own way.

**Owner-effort tracking is tabled** (Overseer, 2026-09-18) and now sits at the
foot of this file as a documented need, not a ranked addition. The reasoning is
recorded there.

The through-line of what remains: 1–2 are cheap and make later work measurable;
3 is the capability neither the fort work nor the autonomy research has yet; 4–5
are the Greenlab founder's prerequisites, de-risked in the safe software domain
first.

---

## 1. Evidence-status discipline on facts and handoff claims

Keep the `[MEASURED/REFUTED/OPEN/UNMEASURABLE]` tags the fleet spec already
invented, and **generalize them from that one spec to the whole facts ledger**,
enforced by `memory-lint`. This is not the corpus strength-ladder (that axis
stays out of the current forts; it earns its place only in Greenlab, where "real
vs simulated" is the central question). It is making the fleet's own best habit a
fort-wide rule, because the fort's worst measured failure class is "a claim
outliving its instrument," and a dated status tag is what catches it.

**Evidence gate:** `memory-lint` fails a fact that asserts without a status tag or
a date; a spot check finds no `[MEASURED]` fact older than its stated observation
window without a re-measure or a `[REFUTED]`.

## 2. Decision packets on the Keep

Today a "needs you" row is a verdict plus a diff. The corpus's decision-inbox
contract is: proposal, evidence, cost, effect-of-delay, expiry, fallback. A small
render change to the Keep. Makes batched judgment faster and lower-error, which
directly serves the decoupling thesis — better packets mean the queue clears in
less attention.

**Evidence gate:** every "needs you" row renders the six fields, sourced from the
bead and the verdict, with unknowns shown as unknown rather than blank.

## 3. The self-feeding Mayor, prototyped in software

The big one, and Proofdelve is the safe place to try it. The fleet already stocks
its own queue from the findings treadmill unsupervised. Extend that one step: the
Mayor files beads from the product spec and the backlog, **each recording why it
was selected** (the corpus value-of-information rule — the cheapest credible
observation that could change an allocation decision — so the queue does not
become an autonomous busywork generator).

**Evidence gate:** a week where the Mayor-filed beads have a "you'd-have-filed-it"
acceptance rate the Overseer is comfortable with. If the beads it files are ones
you would have filed, Greenlab has a founder missing only hands. If not, no amount
of gateway engineering rescues it — and you learned that for the cost of some
beads, in the domain with a binary verifier and a human watching.

## 4. `OBSERVING` as a first-class bead state

The stall detector cannot yet tell a bead *waiting on the world* (a deploy soak, a
CI run, an external callback) from a wedge. The "silence is not a wedge" fact
covers model latency; this covers external waits. A bead with a wake-up condition
and a deadline that the supervisor treats as "waiting, not stalled" is the
primitive every slow-feedback task needs — small in software, essential for
Greenlab's experiment maturity windows.

**Evidence gate:** a bead parked in `OBSERVING` with a deadline does not trip the
stall halt, and does wake when its condition fires or its deadline passes.

## 5. Effect-uncertain state in the airlock

The build-out of advisory ADV-0013. Stable operation id, reserve-then-dispatch,
reconcile-don't-retry, and an emitted deploy event (closing `ForgeOs-x6hq`). Worth
doing in Proofdelve because it is the pattern the Greenlab founder needs most, and
Proofdelve is where it can be tested against a real deploy under a human's eye.

**Evidence gate:** a deploy whose acknowledgment is dropped is reconciled to its
true outcome without a second deploy; the airlock emits a `deploy` event and an
`effect-uncertain` state exists and is reachable.

## 6. A measured local-model rung on a non-critical seat

Not "switch to local" — add **one** open-weights rung *below* the escalation point
on a seat where a wrong answer is cheap, and measure accepted-cost against
frontier. This gives you your own data instead of the corpus's caveats, and it
hardens the local-harness machinery (Greenlab Phase 3) in the domain with a binary
verifier before the low-guardrail civ depends on it.

**Evidence gate:** a side-by-side on the same beads showing accepted-cost
(including review and repair) for the local rung vs frontier, recorded with the
evidence tags. A `real-runtime` result, not a fixture.

---

## Tabled — owner-effort tracking (documented need, not implemented)

**Decision (Overseer, 2026-09-18): do not implement yet. Keep as a documented
need until a metric with a usable signal-to-noise ratio exists.**

The eventual goal is real and the corpus is right that owner-attention is *the*
metric that decides whether autonomy actually widened. But every candidate metric
we could find is too noisy to act on today:

- **Attention-minutes** cannot be measured at all — reading is indistinguishable
  from AFK.
- **Coupling latency** (how long work waited on a human) is fully automated and in
  the event stream, but the signal is swamped by the Overseer's own irregular
  presence: a day at the keyboard, a day checking in twice, a day away entirely on
  another project all produce wildly different latencies for reasons that have
  nothing to do with the system's autonomy. Without a way to normalize for "was
  the Overseer even looking," the number is noise.
- **Owner acts** reduces, at best, to a count of approvals split product-vs-harness
  — and even that is thin. Everything richer is noise.

So the need is recorded and the metric is not pursued. Revisit when there is a way
to separate "the system made the human wait" from "the human was elsewhere." A
plausible future handle: gate this on an explicit presence signal (the Overseer
marks a session as attended) so coupling latency is only computed over windows he
was actually watching — but that is itself friction, and not worth building until
the rest of the founder loop makes the number worth having.
