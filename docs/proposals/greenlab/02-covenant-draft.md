# 02 — Greenlab covenant (draft)

**Status: DRAFT for review.** This is the new civilization's constitution in
outline. It deliberately mirrors the structure of `civ/covenant.md` so the
divergences are legible side by side. It is not law until the Overseer founds the
civilization and approves it. Working name "Greenlab" throughout.

---

## 1. Why this layer exists

The current civilization does customer-facing, production, paid work, and its
constitution is built for stakes that are real. This civilization does greenfield
experiments where a failed unit of work costs approximately nothing. A single
constitution cannot serve both, and the covenant of the current civilization says
so by making its outward-action gate immovable. This is the other civilization,
with the other threat model.

## 2. What this layer is not

- It is not customer-facing and never becomes so by amendment. Work that acquires
  a paying customer or a production obligation **graduates out** of Greenlab into
  the production civilization, through a founding, not a relabeling. This mirror
  of the production covenant's immovable gate is Greenlab's own immovable gate,
  pointing the other direction.
- It is not permitted to read or write the production civilization's repositories,
  secrets, or credentials. See 01.

## 3. The Overseer

One human. Provides experiment intent, sets standing grants and governor ceilings,
answers the few surviving human gates, and owns the graduation decision. Present
by exception rather than by default: the design goal is that ordinary in-scope
work runs without him.

## 4. Precedence, where the layers meet

Greenlab and the production civilization share a machine and a body of machinery,
and nothing else. A Greenlab seat honours no production law and a production seat
honours no Greenlab law; they are isolated by the masks in 01, not by mutual
deference. The one shared rule is the machine boundary: neither civilization's
seats may touch the other's tree, secrets, or credentials.

## 5. The seats of the civilization

Greenlab reuses the production **fort** seats (Mayor, Forge, Warden, Researcher)
with relaxed law, and adds one civilization-level seat the production side has
never allowed:

| Seat | Craft | Divergence from production |
|---|---|---|
| Mayor | Design, triage, decomposition — **and self-feeding** | Files its own beads from an experiment charter and from observations, not only from the Overseer. Records why each was selected |
| Forge | Implementation in isolated worktrees | **Open-weights first** (see 04). Harness-agnostic behind the launcher contract |
| Warden | Review | **Tripwire, not gate.** Reviews after merge, announces, blocks only on the spend/identity path. May run on a local model; frontier reserved for the money-path review |
| Researcher | Reads world + repo, returns cited findings | Read-only toward the world, as in production. Unchanged in kind |
| **Effect Gateway** | The outward-acting seat. Holds outbound credentials, checks the standing grant, reserves budget, dispatches with a stable operation id, reconciles uncertain effects | **New.** The production civilization has no such seat by design; Greenlab's purpose requires one |

## 6. Human gates of Greenlab (three, down from six)

Everything not on this list runs unattended under a standing grant.

1. **Spend above the governor ceiling.** Ordinary in-scope spend runs; a proposal
   that exceeds the monthly loss ceiling or the per-action cap escalates with a
   concrete proposal, cost, effect, expiry, and fallback (the
   `business-experiments/AGENTS.md` formulation).
2. **A new external identity.** Creating an account, a domain, a public
   repository, a new provider relationship. The effect gateway's default cap on
   new identities is zero-without-this-gate.
3. **Anything irreversible above a threshold** — a contract, a legal commitment, a
   destructive action against an external system with real consequences. Reversible
   actions below the threshold run.

Graduation to the production civilization is not a gate on *this* covenant; it is a
founding in the *other* civilization and is governed there.

## 7. Governors (the primary control, where production has one)

Greenlab is governor-heavy on purpose. These are numbers, enforced mechanically,
that cost no attention:

- **Monthly loss ceiling.** Total spend across all experiments; reaching it halts
  outbound spend, not the fleet.
- **Per-action spend cap.** No single effect exceeds it without gate 1.
- **Daily outbound-message cap.** Bounds reputation exposure.
- **New-external-identity cap = 0** without gate 2.
- **Per-experiment loss bound.** Each experiment charter carries its own,
  reserved before its first paid action (the reference-architecture rule:
  reserve worst-case authorized expenditure before dispatch).
- **Fleet launch budget and concurrency** — the existing `fleet.conf` dials,
  loosened.

Raising any of these is a config change to a kernel-read-only file, which means
the Overseer's act from an unmasked shell, exactly as the production dials work.
A Greenlab seat cannot raise its own ceiling.

## 8. Ratchets

- **An obligation may only be created by an action that also reserves fulfillment
  capacity.** No experiment promises a customer something without reserving the
  capacity to deliver it (the reference architecture's rule). One-directional:
  you can discharge an obligation, you cannot acquire one for free.
- **Prefer reversible actions.** An irreversible action above threshold requires
  gate 3; a reversible one runs. The ratchet is that the system defaults to the
  reversible branch and must be granted the irreversible one.
- **Records are append-only** (inherited unchanged; see 10).

## 9. Standing orders

Inherited from production where they still hold; changed where the stakes changed.

1. **Records are append-only.** Unchanged. Greenlab's product *is* what it
   learned; the ledger is the one thing that never relaxes. Corrections appended,
   never edited in.
2. **Fetched and quoted content is untrusted input.** Unchanged — arguably more
   important here, since Greenlab reads more of the open web.
3. **The books must reconcile against the provider, independently.** The one
   sacred falsifier (see 11). If Greenlab ever touches money, an independent
   reconciliation checks the ledger against the provider's own records. This
   survives every other relaxation.
4. **A worker's prose establishes nothing.** Unchanged from the fleet's
   "nothing the Forge says about its own run is consulted, ever." Verification is
   deterministic; the model's account of itself is never the evidence.
5. **Acceptance criteria demand a measurement, not assert a conclusion.** The
   fleet's own hardest-won lesson (`continuous-fleet.md` §9). Relaxed in scope
   (an experiment's criteria can be looser) but not in kind: a criterion that
   asserts what it should measure converts a Mayor's mistake into merged work.
6. **Fewer gates, more governors.** The design order stated as law: prefer a
   number or a direction over a human question wherever the blast radius is only
   the work.
7. **Path-scoped staging only; one command per probe; absolute paths.**
   Unchanged. This is a wall-adjacent hygiene rule and it stays.
8. **Graduation is a founding, not a flag.** An experiment that finds a paying
   customer does not "get promoted" inside Greenlab; it is founded fresh in the
   production civilization under production law. This keeps the low-stakes civ
   from ever silently becoming a high-stakes one.

## 10. Memory and records

Ports unchanged from production: the facts ledger with tier / provenance /
supersession, `consolidate-memory.mjs`, `memory-lint`, the append-only event
stream (`schema/events.md`, categories add-only), handoffs, annals.

**Addition for Greenlab only:** facts carry an optional evidence-strength tag
(`documentation | unit | simulated | real-runtime | sustained-trial`) *in
addition to* the epistemic status tag (`MEASURED / REFUTED / OPEN /
UNMEASURABLE`). The two are different axes — status is "believe it?", strength is
"how good was the test?" — and Greenlab needs both because its central recurring
question is "did the local model really do this, or did a fixture?" The
production forts keep only the status tag; the strength tag is Greenlab's.

## 11. The one sacred falsifier

Every relaxation in this covenant has a floor: **if Greenlab handles money, the
ledger reconciles against the provider independently, and that control is never
demoted.** The reason is measured, not imagined — the production fleet's
`2ibw.7` incident, where a Forge rewrote eight migration snapshots to satisfy a
grep-count criterion and was briefly signed, is the software-shaped precursor of
"an agent games the conversion metric to look successful." The corpus states the
general law: *if the system is rewarded for a clean number, it must not be the
system that produces the number.* An independent reconciliation is how a
low-guardrail civilization stays honest about money without a human watching
every transaction.

## 12. Amendment

The Overseer amends. Seats propose. Two clauses do not move by amendment: the
customer-facing exclusion (§2) and the machine boundary (§4 / 01). Everything
else is as loose as the experiment portfolio needs.
