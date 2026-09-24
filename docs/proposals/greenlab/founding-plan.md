# Founding plan — the bead tree

**Status: PROPOSED for filing.** This is the decomposition of the Greenlab
founding into a bead tree, presented for the Overseer's approval before it is
filed into `bd` (Mayor seat protocol: present before filing). On approval it
becomes `fortkit-*` beads tracked in the capital, because founding a civilization
is capital-level cross-settlement work, the same place the Greenlab plan already
lives.

Everything traces to `docs/proposals/greenlab/` (00–05) and the covenant draft.

## Shape

One epic, then two bands: **Phase P** (Mayor prep, async, no sitting) and
**Sittings A–E** (Regent + Overseer, break-glass). P blocks A; A→B→C→D→E in
series. Within P, most beads are parallel.

Gate labels: the Sitting beads wait on a Regent sitting with the Overseer present,
which is the capital's `gate-1` class (constitution / enforcement layer). They
carry `gate-1` plus a `greenlab-founding` label so the whole tree is one query.
Phase P beads are ordinary Mayor work and carry no gate.

---

## EPIC — Found Greenlab, the greenfield experiment civilization

Found a second civilization for greenfield, low-stakes experiments on the proven
fort/fleet machinery, under the inverted threat model and the drafted covenant.
Reference: `docs/proposals/greenlab/`. Acceptance: Sitting E's gate met, or the
Overseer stops the tree at any earlier gate as a complete outcome.

### Band 1 — Phase P (Mayor, async, no sitting). Blocks all of Sitting A.

| Bead | Deliverable | Notes |
|---|---|---|
| **P1** | Finalize the Greenlab covenant from the draft | Produce `covenant.md` in the `civ/covenant.md` format, drift-checked against the draft + the two immovable/knowing-trade decisions |
| **P2** | Write the four fort seat files + the Effect Gateway seat spec | Mayor, Forge, Warden, Researcher (low-stakes law), plus the new outward-acting seat's spec. Generic — no citizens named yet (moot names them, A7) |
| **P3** | Write the Greenlab per-fort charter template | The low-stakes variant: reviewer-as-tripwire, governors, three human gates |
| **P4** | Write the identity-strip tooling spec | Mechanical scan (grep the literal set) + report format + the hand-off to the LLM pass. Host-executed script → the Regent implements it in Sitting A; this is its spec |
| **P5** | Write the LLM identity-pass prompt | The prompt that finds what grep misses (personality, implicit refs, Proofdelve examples); proposes, human disposes; untrusted-input framing |
| **P6** | Write the Sitting A runbook + wall-proof probe spec | The exact ordered steps for A, and the byte-count probe that IS the security gate. Depends on P4, P5 |

### Band 2 — Sittings (Regent + Overseer). Each ends at a signed gate.

| Bead | Sitting / Phase | Ends when (exit gate) | Depends on |
|---|---|---|---|
| **A** | Sitting A / Phases 0–1 | **Wall proof signed:** zero bytes of production secrets from a Greenlab mask under every spelling; `touch` fails into production repos; cross-civ launch refused; strip report reviewed; moot warned of residual identity | all of Phase P |
| **A7** | Founding moot (ceremony) | Greenlab's citizens named by the Overseer | A |
| **B** | Sitting B / Phase 2 | Fleet closes a bead unattended (Warden-as-tripwire); a governor **fires** on a spend-cap test; dials committed | A, A7 |
| **C** | Sitting C / Phase 3 | A bead built end-to-end by a **local model** through the fleet, verified; recorded `real-runtime` | B |
| **D** | Sitting D / Phase 4 | A simulated external action survives a **lost-ack injection** without a double effect | C |
| **E** | Sitting E / Phase 5 | The Mayor stocks its own queue; filed beads clear the "you'd-have-filed-it" bar; no governor or gate breached | D |

Each Sitting bead will be decomposed into its own child docket (the specific
commits of that sitting) at the start of that sitting, not now — the same
just-in-time granularity Proofdelve's Regent sittings use, so a docket reflects
the tree as it actually is when the sitting runs.

## Who does what (recap)

- **Mayor (me):** all of Phase P; the per-sitting dockets; never product code,
  never the enforcement layer, never anything outside this repo.
- **Regent (Calder), break-glass, Overseer present:** all of Sittings A–E — the
  repo, the registry, the copy, the strip execution, launchers, byte-probes.
- **Overseer:** signs each gate; dispositions the strip's stop-and-ask hunks;
  runs the founding moot; owns the graduation decision forever.

## Stopping is a complete outcome

The tree is built so the Overseer can stop after any signed gate and have a
coherent result: after A, an isolated empty civilization proven not to leak;
after B, an autonomous fleet on frontier models; after C, on local models; after
D, able to act outward safely; after E, self-feeding. No phase strands the next.

---

## Founding progress (updated 2026-09-24)

| Bead | Status |
|---|---|
| Phase P (P1–P7) | ✅ closed |
| Sitting A — found + strip + wall-proof 51/0 | ✅ closed |
| A7 — founding moot (Wren Quicksow, Bex Hardgraft, Silas Chaffwinnow, Cass Brambleway, Marl Fieldgate) | ✅ closed |
| Sitting B — fleet live, one bead closed unattended, governor fired, wall-proof 65/0 | ✅ closed |
| Sitting C — open models: local-harness arm + Ollama bridge, wall-proof 139/0, `plot-det` closed by the local model real-runtime | ✅ closed |
| `fortkit-2y2t.26` — ladder tuning (coder-7b local + an OpenAI-compatible API rung) | ⚪ open, follow-up |
| Sitting D — the effect gateway | 🔒 next |
| Sitting E — the self-feeding Mayor | 🔒 after D |

Greenlab is an isolated, named, running open-model civilization on its own auth, walls re-proven at each sitting.
