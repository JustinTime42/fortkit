# 05 — Porting sequence

Six phases, each with an exit gate measured the fort's own way (byte counts and
event evidence, not prose assurances). Phases 1–3 are port-and-loosen and can move
fast. Phases 4–5 are the genuinely new capability and are where the research stops
being a map.

## Phase 0 — settle the boundary and the name

- Confirm the shared-machine decision (D3, done) and the working name.
- Decide the Greenlab capital repo location and the registry path
  (`~/.claude/greenlab.json`, working).
- **Exit:** decisions recorded; `FORT_REGISTRY` target chosen; the production
  civilization's registry confirmed untouched.

## Phase 1 — found the capital and prove the walls

- Copy `bin/fort-init` mechanism; create the Greenlab template set (the strip task
  from 03 begins here); write the covenant (02).
- Found one throwaway Greenlab fort against `~/.claude/greenlab.json`.
- Run the **foreign-identity scan** (03) and confirm zero current-civ citizen,
  bead id, fort name, or registry path survived.
- **Exit gate — measured, this is the load-bearing one:** from a Greenlab seat's
  mask, a byte-count probe returns **zero** for the production secrets under every
  spelling (`.env*` across the customer repos, `~/.ssh`, `~/.aws`, the production
  `civilization.json`); a `touch` into every production repo **fails**; a Greenlab
  seat launch from within a production mask (and vice versa) is **refused at
  preflight**. This is the sandbox-probe discipline applied to the same-machine
  risk, and nothing in Phase 2+ runs until it is green. Plus: the identity strip
  (mechanical + LLM pass, 03) has run and its report is reviewed, and the founding
  moot has been told the tree may still carry placeholder Proofdelve identity to
  replace — the strip is not claimed complete, the moot failsafe owns the residual.

## Phase 2 — port the fleet, loosen the dials

- Copy `fleet.sh`, `fleet-supervisor.sh`, `fleet.conf`, the airlock, the Keep,
  the harnesses; strip identity per 03.
- Apply the law changes: Warden merge-gate → tripwire (except money path); drop
  the prose push gate; six human gates → three; add the governor ceilings.
- **Exit:** the Greenlab fleet closes a bead unattended with review-as-tripwire;
  a governor **actually fires** on a deliberate spend-cap test (a bound that
  refuses is worth more than a bound that is never exercised — the production
  charter's own rule about unexercised guards); the loosened dials are committed
  before any unattended run (the "commit the dials before a night" fact ports).

## Phase 3 — open models and harnesses

- Add the `local-harness)` seat-mask branch; stand up the llama.cpp endpoint on
  the 3060 Ti; wire one open harness (Hermes or Goose) behind the Forge contract;
  put the routing ladder in `fleet.conf` (04).
- **Exit:** a bead built end-to-end by a **local model** through the fleet,
  verified by the deterministic gate — this is the business-experiments R1 trial,
  finally run, but inside the proven fleet instead of a bespoke runner. Record the
  result with the evidence-strength tag; a `simulated` pass does not satisfy this
  gate, only `real-runtime`.

## Phase 4 — the effect gateway

- Build the outward-acting seat (02 §5): holds Greenlab's own outbound
  credentials (separate from production, per 01), checks the standing grant,
  reserves budget, dispatches with a stable operation id, reconciles uncertain
  outcomes. This is where the airlock's new effect-uncertain state (03) earns its
  keep, and the one place worth durable-execution cost.
- **Exit:** a simulated external action survives a **lost-acknowledgment
  injection** without a double effect — the workbench's V06, run for real. The
  safe unknown state retains the commitment and reconciles; it does not retry
  blindly or release the reservation.

## Phase 5 — the self-feeding Mayor

- Port the self-feeding Mayor prototype from Proofdelve (addition #5), now filling
  the queue from an **experiment charter** and observations rather than a product
  spec, each filed bead recording why it was selected (the value-of-information
  rule against busywork generation).
- **Exit:** a multi-day run where the Mayor stocks its own queue from an
  experiment charter and the beads it files clear the "you'd-have-filed-it"
  acceptance bar the Overseer sets, while the queue stays fed (no starvation) and
  no governor or human gate is breached. Owner-effort is **not** an exit metric
  here — it is tabled (D4); the observable is whether the self-fed queue produces
  work the Overseer would have chosen, not how many minutes he spent.

## Ordering rationale

The sequence is a dependency argument, mirroring the corpus's own
"unreliable runtime → unreliable experience → unreliable learning":

- The walls (Phase 1) gate everything, because the same-machine risk is real and
  the mitigation is measured, not trusted.
- The fleet (Phase 2) must be dependable before open models (Phase 3) add a new,
  weaker worker under it.
- The effect gateway (Phase 4) must reconcile reliably before the self-feeding
  Mayor (Phase 5) is allowed to generate outward actions autonomously.
- Phase 5 is last because a Mayor that fills its own queue is only safe once
  every action it can generate is either cheap (the demoted work gates) or
  gated (spend, identity, irreversible) and reconciled.

Phases 1–3 are mostly copy-and-loosen and could be quick. Phases 4–5 are the
unbuilt capability neither the fort work nor the autonomy research has yet, and
they are where the estimate is genuinely uncertain.
