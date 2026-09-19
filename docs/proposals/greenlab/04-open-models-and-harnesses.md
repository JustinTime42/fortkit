# 04 — Open models and harnesses as first-class

This is where Greenlab genuinely diverges in *code*, not just law. The current
civilization's launchers cannot express an open-weights worker: they hard-branch
on two seat types and couple to two hosted CLIs.

## The current coupling, located

`fort/scripts/lib/seat-sandbox.sh` branches on exactly two seat types:
`codex)` (~:232), `claude)` (~:270), and `*) unknown seat type` (~:392). The
model itself is coupled in only two, well-isolated places:

- `fort/scripts/fleet.conf`: `FLEET_FORGE_MODEL=gpt-5.6-terra`.
- The launcher invocations: `codex exec ... -m "$model"` (`forge.sh` ~:710–723)
  and `claude -p --model "$model"` (`warden.sh` ~:612).

**The good news:** the coupling is already at the config + launcher edge, not
smeared through the fleet loop. `fleet.sh` speaks about "the model" only through
`fleet.conf` and the launcher contract. So making open weights first-class is a
new seat-mask branch plus a launcher plus a conf change — not surgery on the
orchestrator.

## The design (from the business-experiments analysis, already worked out)

`applications/business-experiments/analysis/{REPORT,REFERENCE-ARCHITECTURE,
LOCAL-INFERENCE,HARNESS-SELECTION}.md` did this analysis; Greenlab adopts it and
runs it on the fleet.

### One inference server, many experiments

Parallel experiments are **not** parallel model copies. A single local server
(llama.cpp first, per LOCAL-INFERENCE; compare vLLM on the 3060 Ti only under a
sustained batch workload) multiplexes requests from every logical experiment with
continuous batching. Seats are stateless between bounded calls and reconstruct
context from records. A portfolio stays active while only a few inference
sequences occupy VRAM. Task-based admission, not one loaded model per experiment.

### A routing ladder replaces the fixed model

`FLEET_FORGE_MODEL=<one hosted model>` becomes a ladder in `fleet.conf`:

1. **Deterministic transform** — no model at all, where the task is mechanical.
2. **Small local model** — extraction, bounded drafting (Qwen3.5-9B class per the
   analysis; candidates, not winners).
3. **Stronger local model** — planning, code, if it wins on *accepted* cost
   (Qwen3.6-35B-A3B class).
4. **Optional frontier escalation** — disabled in a strictly-local experiment;
   when local cannot complete, the system narrows the task or asks, rather than
   silently reaching for a hosted model.

This is a `fleet.conf` ladder plus a launcher branch, structurally identical to
the existing `FLEET_WARDEN_LADDER`. The failover discipline ports unchanged:
a rung that produces no result is an availability failure and the next rung is
tried; competence failure escalates or narrows, never silently retries cheaper.

### The seat-mask third branch

`seat-sandbox.sh` gains a `local-harness)` branch beside `codex)` and `claude)`.
It binds the shared inference endpoint (localhost, the one server), masks
everything the other branches mask, and runs an **open harness** (Hermes or Goose
per HARNESS-SELECTION) behind the same `forge.sh`-shaped launcher contract. Adding
a harness is adding a launcher, not a loop. The harness's own session/persistence
is distinct from the authoritative bd/event records — one scheduler owner (the
fleet), the harness is a replaceable worker.

### Harness-agnostic worker contract

The business docs insist on it and Greenlab enforces it: the Forge launcher
presents the same contract (bead in, worktree out, verifier run by the fleet on
the host, nothing the worker says about itself consulted) whether the worker is
`codex exec`, Hermes, Goose, or a raw local model. The harness sits behind the
contract; the fleet never learns which one ran except as an event field, the way
it records the model today.

## The Warden goes light — and that is coherent

The corpus is blunt: **model review is weak evidence; deterministic checks carry
the strongest claims.** A local-model reviewer is weaker still. Two consequences,
both already the plan:

- **Lean harder on deterministic verification, lighter on model review.** This is
  the same move as demoting the Warden from gate to tripwire (02 §5). The
  verifier — real tests, real checks, on the host — does the load-bearing work;
  the reviewer announces what the tests cannot see.
- **Spend model quality where it cannot be gamed.** Keep one **frontier** rung for
  the single seat whose judgment must not be cheap: the money-path reviewer and
  the reconciliation-adjacent checks (02 §11). Everything else runs local. This is
  coherent budgeting: frontier on the one sacred falsifier, open weights on the
  cheap, high-volume, throwaway work.

## Why the strength tag lives here (D5)

Greenlab's central recurring question is "did the local model actually do this,
or did a fixture / a happy path?" — the workbench's whole "a passing stub is not
real integration" problem, which the production forts almost never face because
their system is already *running*. So Greenlab facts carry the evidence-strength
ladder (`documentation | unit | simulated | real-runtime | sustained-trial`) in
addition to the epistemic status tag. On the current forts that axis is ceremony
and stays out (see `../proofdelve-additions/`); here it is decision-relevant on
nearly every claim about whether a model can be trusted with a task.

## The bridge back to Proofdelve

The machinery to run a local harness through the fleet should be **built and
hardened in Proofdelve first**, on low-stakes software beads (addition #7 in
`../proofdelve-additions/`): add one open-model rung below the escalation point on
a non-critical seat, measure accepted-cost against frontier, and get your own data
instead of the corpus's caveats. Then Greenlab depends on a proven branch rather
than a new one. This keeps the risky new code in the domain with a binary
verifier and a human watching, before the low-guardrail civ leans on it.
