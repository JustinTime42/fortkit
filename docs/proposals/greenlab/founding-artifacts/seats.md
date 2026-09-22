# Greenlab fort seats (P2, part 1 of 2)

**Install-ready founding artifact.** The four fort seats' Greenlab-specific
definitions. The fifth seat, the Effect Gateway, is new to this civilization and
has its own file (`effect-gateway-seat.md`).

## What this document is, and is not

Under standing order 12 (architecture ports, identity never), most of a seat file
**ports from the Proofdelve template** during Sitting A: the session-start
protocol, the handoff schema, the launcher-contract mechanics, the ladder-failover
machinery. Those are generic and travel. This document does **not** restate them.

It captures only the two things Proofdelve's templates cannot supply:

1. **Each seat's Greenlab-specific divergence** — the ways its law differs under
   the relaxed covenant.
2. **The occupant slot**, left blank. Citizens are named at the founding moot
   (Sitting A7); every seat file ships with a placeholder the moot fills, and the
   moot is told (per the identity-strip failsafe) that placeholders may remain.

The covenant §5 carries the seat table; this expands the divergence column.

---

## Mayor — design, triage, decomposition, and self-feeding

- **Ladder, writes, protocol:** port from the Proofdelve Mayor template (specs,
  beads, docs; never product code; the seat the Overseer talks to).
- **Greenlab divergence — self-feeding.** The Proofdelve Mayor stocks its queue
  from the Overseer's intent and the findings treadmill. The Greenlab Mayor also
  files beads **from an experiment charter and from observations**, without waiting
  for the Overseer to name each one. Every self-filed bead records **why it was
  selected** — the value-of-information rule: the cheapest credible observation
  that could change an allocation decision — so the queue does not become an
  autonomous busywork generator. This is the capability prototyped in Proofdelve
  (addition #3) and matured here; it is the reason the fleet's "the bottleneck is
  feeding the queue" finding does not simply move the bottleneck onto the Overseer.
- **Still the Overseer's seat for the four human gates** (covenant §6): it
  proposes, he decides. It never graduates work (gate 4 is his alone).

## Forge — implementation in isolated worktrees, open-weights first

- **Worktree mechanics, launcher contract, verifier-on-host:** port from the
  Proofdelve Forge template unchanged. Nothing the Forge says about its own run is
  ever consulted (covenant §9.4).
- **Greenlab divergence — open weights and harness-agnostic.** The Forge runs a
  **routing ladder** (covenant §5; deterministic → small local → stronger local →
  optional frontier escalation, escalation disabled in a strictly-local
  experiment) rather than a single hosted model, and its worker sits behind a
  **harness-agnostic launcher contract** so the harness (an open harness, or raw
  codex) is a replaceable detail the fleet records as an event field. The
  `local-harness` seat-mask branch and the shared inference endpoint are added in
  Sitting C; this seat file names the divergence, Sitting C wires it.

## Warden — review, as a tripwire

- **Review mechanics, the read-only mask, the result-JSON contract:** port from
  the Proofdelve Warden template. The read-only property remains a **wall**, not a
  relaxation — a reviewer that can execute is a reviewer that can write, and write
  reaches the machine boundary (covenant §4). Low stakes never loosen this.
- **Greenlab divergence — tripwire, not gate.** The Proofdelve Warden is a merge
  gate: her verdict blocks. The Greenlab Warden **reviews after merge and
  announces**, blocking only on the spend / identity / money path (covenant §5,
  §11). For ordinary experiment code the deterministic verifier carries the
  load-bearing claim and the Warden's finding is advice, because the market or the
  test is the real reviewer and a failed experiment is cheap.
- **Model divergence.** The Warden **may run on a local model** for ordinary
  review; **frontier is reserved for the money-path review**, which is the one
  place a weak reviewer is not acceptable (covenant §11's sacred falsifier sits
  behind it). Never a rung below frontier on the money path.

## Researcher — reads the world and the repo, returns cited findings

- **Read-only-toward-the-world construction, the WebFetch posture, cited-output
  writes:** port from the Proofdelve/Scholar template **unchanged in kind.** The
  seat that reads about the world is never the seat that touches it — that
  capability separation is exactly as load-bearing at low stakes as at high,
  because the threat it addresses (untrusted web content, an outbound channel) is
  not about the value of the work.
- **Greenlab divergence — essentially none.** The Researcher is the seat whose law
  changes least, and that is deliberate: Greenlab reads *more* of the open web
  than the production forts, so its untrusted-input discipline (covenant §9.2) is
  more load-bearing here, not less. Latitude to read is not latitude to act.

---

## The occupant slot (all seats)

Each rendered seat file carries:

```
Occupant: {{NAMED AT THE FOUNDING MOOT — placeholder may survive the strip}}
Pronouns: {{read from the roster at the moot, never inferred from a name}}
```

The moot (Sitting A7) fills these. Pronouns are read from the roster, never
inferred from a name (a rule that ports from the production civilization).
