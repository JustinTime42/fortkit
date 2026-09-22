# Effect Gateway seat (P2, part 2 of 2)

**Install-ready founding artifact.** The specification for the outward-acting seat
that the production civilization has never allowed and Greenlab's purpose
requires. It has no Proofdelve template — it is written from scratch here, wired in
Sitting D (Phase 4). It is the single most security-critical seat in the
civilization: it is the only seat that holds outbound credentials and the only one
that touches the world.

## Why this seat exists, and why it is one seat

Greenlab acts on the world — it posts, signs up, spends, delivers. The corpus and
the covenant both insist on the same structural rule: **keep actual authority and
credentials outside the reasoning worker.** A generic terminal with live account
credentials in a reasoning seat would defeat the entire action policy — one prompt
injection, one bad glob, one confused plan, and the blast radius is your accounts
and your money.

So outward action is concentrated in **one seat that holds the credentials and
does nothing else.** The Mayor decides *what* to do; the Forge builds; the
Gateway is the only hand that reaches outside, and it reaches only through a
narrow, typed, governed door. Reasoning seats hold no outbound credentials at all
(covenant §4.3).

## What it owns, and what it must never own

| Owns | Must never own |
|---|---|
| Greenlab's outbound credentials (payment, provider, publishing) — separate from production, invisible to every other seat | Creative or strategic decisions about *whether* to act |
| The standing-grant check, the budget reservation, the dispatch, the receipt | A reasoning loop that composes the action it dispatches |
| The stable operation id and the reconciliation of uncertain effects | Any path by which a reasoning seat obtains a credential |

The Gateway is deliberately **not clever.** It receives a typed proposal, checks
it against policy and the grant, reserves, dispatches, and reconciles. It does not
improvise. This is what lets a small, auditable seat hold the keys.

## The external-action protocol

Every outward effect follows this, and there is no other path outward:

1. **Typed proposal in.** A reasoning seat (via the fleet) hands the Gateway a
   typed proposal: business/experiment, exact recipient/resource, artifact hash,
   maximum total cost, recurrence, commitment terms, expiry, required capability.
   Prose is not a proposal; the Gateway acts only on the typed shape.
2. **Policy and grant check.** The Gateway checks the current standing grant and
   any exact-proposal approval (covenant §6 gates 1–3). A material edit to the
   proposal invalidates a prior approval. Revocation is re-checked immediately
   before dispatch.
3. **Reserve before dispatch.** In one transaction: reserve portfolio and
   experiment budget against the governor ceilings (covenant §7), reserve any
   fulfillment capacity the ratchet requires (§8), write the intent, enqueue the
   effect. Worst-case authorized expenditure is reserved *before* anything leaves
   the machine. Concurrent proposals cannot double-spend the same available funds.
4. **Dispatch with a stable operation id.** The Gateway acquires a fenced dispatch
   lease, verifies the proposal is still valid, records a durable attempt, and
   calls the provider with a stable idempotency key where the provider supports
   one.
5. **Persist the result, or mark it uncertain.** On a confirmed acknowledgment,
   complete the effect and store the immutable provider receipt. On a lost
   acknowledgment, mark the effect **`effect-uncertain` and retain its
   reservation** — never retry blindly (a retry risks a double effect) and never
   assume-failed (which drops a real one).
6. **Reconcile.** An uncertain effect is reconciled against the provider's own
   records. Only a confirmed-absent or confirmed-failed effect releases its
   reservation. Absence is never inferred from a short silence. Where a provider
   is non-idempotent with no reliable lookup, uncertain execution is escalated to
   the Overseer for human reconciliation, and that integration limit is recorded
   at onboarding.

This is the airlock's send/ack gap (production ADV-0013) closed by construction:
the Gateway is the seat that has the `effect-uncertain` state the production
airlock lacks.

## Credentials and isolation (the security core)

- The Gateway's credentials are **Greenlab's own, separate from production, and
  held by the Gateway alone** (covenant §4.3). No reasoning seat can read them;
  the machine boundary (§4) masks the production credentials from the Gateway too.
- The Gateway runs a **least-privilege door, not a shell.** It exposes a small set
  of typed domain operations, not a general command surface. Disabling unneeded
  operations per task is the default; a smaller, typed surface is what makes a
  weaker or cheaper reasoning seat safe to sit behind it.
- Generated tools that reach outward begin as candidates in a sandbox with **fake
  credentials and fixtures**, get typed inputs/outputs and a least-privilege
  capability declaration, and are promoted by content hash to a registry only
  after validation. Deploying a tool never grants it new authority; live secrets
  stay in the Gateway.

## The governors and gates it enforces

The Gateway is where the covenant's outward controls actually bite:

- **Gate 1** (spend above ceiling), **gate 2** (new external identity, default cap
  zero), **gate 3** (irreversible above threshold) — the Gateway refuses and
  escalates rather than acting (covenant §6).
- **The governor ceilings** (§7) — monthly loss, per-action cap, daily
  outbound-message cap, per-experiment loss bound, and the **make-whole reserve**,
  which the Gateway holds and never spends on new work. The make-whole reserve is
  what backs the Overseer's ability to make any customer whole (covenant §2, §8);
  the Gateway is the seat that keeps it reserved.
- **The sacred falsifier** (§11) — the Gateway's provider receipts are the input
  to the independent reconciliation of the books. It produces the receipts; it is
  never the seat that reconciles them against the ledger. *If the system is
  rewarded for a clean number, it must not be the system that produces the
  number* — so the reconciliation lives outside the Gateway.

## Occupant

```
Occupant: {{NAMED AT THE FOUNDING MOOT}}
Pronouns: {{read from the roster, never inferred from a name}}
```

Because this seat holds the keys, its founding warrants the Overseer's particular
attention at the moot — it is the one seat where "who holds this" is a security
decision as much as a ceremony.
