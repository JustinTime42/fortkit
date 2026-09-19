# Greenlab — a second civilization for greenfield experiments

**Status: PLANNING. Nothing here is founded, filed, or executed.** These are
review documents capturing the 2026-09-18 design conversation between the
Overseer and the Mayor of Manyhalls. They are staged in `fortkit/docs/proposals/`
because that is where founding proposals live (see `docs/proposals/publication-founding/`);
on founding they move to the new civilization's own capital repository and this
copy becomes historical.

**"Greenlab" is a working name.** The Overseer names the civilization at founding
(covenant human gate: naming is his, permanently). Every use of "Greenlab" below
is a placeholder.

## Why this exists, in one line

To run greenfield, low-stakes, high-volume AI experiments on the same machinery
that Proofdelve proved, under an **inverted threat model** and **far fewer
guardrails**, without touching the production civilization that does
customer-facing paid work.

## The two civilizations, side by side

| | Current civilization (Manyhalls, Proofdelve, Farlantern, Kithmason) | Greenlab (proposed) |
|---|---|---|
| Purpose | Customer-facing, production, paid work | Greenfield experiments; failure is cheap and expected |
| Threat rank 1 | Agent accident against the work | Credential/repo leakage into the experiment civ |
| Stakes of a failed unit of work | High — a paying customer sees it | ~Zero — delete it and move on |
| Guardrail philosophy | Walls + fences + prose gates + human gates | Walls + governors + ratchets; almost no gates |
| Reviewer | Merge gate (blocks) | Tripwire (announces, does not block) |
| Models | Frontier (Warden opus 592/592; "never a rung below frontier") | Open weights first-class; frontier reserved for the one control that must not be gamed |
| Human gates | Six | Roughly three |
| Registry | `~/.claude/civilization.json` | `~/.claude/greenlab.json` (working path) |
| Capital repo | `fortkit` | a new repo (working name `greenlab`) |
| Machine | Primary work machine | **Same machine** (RTX 3060 Ti primary) — risk accepted, see 01 |

## Document set

| File | What it holds |
|---|---|
| [00-overview.md](00-overview.md) | The thesis, the "same architecture built twice" finding, the two-civ split, and why it must be a separate civilization and not an amendment |
| [01-threat-model-and-boundary.md](01-threat-model-and-boundary.md) | The inverted threat model; the same-machine decision and its accepted risk; the mask non-negotiables and credential separation that survive even at low stakes |
| [02-covenant-draft.md](02-covenant-draft.md) | The new law: human gates, the governor list, standing orders, reviewer-as-tripwire. The centerpiece |
| [03-port-and-identity-strip.md](03-port-and-identity-strip.md) | Copy from Proofdelve (not the stale template); the identity-strip-and-reset task; what ports and what changes |
| [04-open-models-and-harnesses.md](04-open-models-and-harnesses.md) | The local-harness seat branch, the routing ladder, the shared inference server, and why the Warden goes light |
| [05-porting-sequence.md](05-porting-sequence.md) | Phases 0–5, each with an exit gate measured the fort's own way |

## Decisions of record from the 2026-09-18 conversation

- **D1. Separate civilization, not a carve-out.** Confirmed by the Overseer.
  Covenant human gate 1 (publishing/external, "does not move by amendment") is
  incompatible with an outward-acting founder; weakening it would erode the
  protection the paid work depends on. Found the second civilization instead.
- **D2. Port from Proofdelve, not the template.** The `fortkit/templates/` copy
  is behind — most evolution of the last two weeks landed in Proofdelve and not
  in the factory. Copy Proofdelve's living files and add an explicit
  identity-strip-and-reset task, accepting that this is the more expensive path
  and the one standing order 12 warns is destructive if done carelessly. See 03.
- **D3. Same physical machine, risk accepted.** The RTX 3060 Ti box is the
  Overseer's primary work machine and will host Greenlab. The credential/repo
  isolation in 01 is therefore load-bearing rather than convenience. Risk stated
  and accepted by the Overseer on 2026-09-18.
- **D4. Owner-effort tracking is TABLED as a documented need.** Attention-minutes
  cannot be measured honestly (reading vs AFK), and coupling latency — though
  automated — is swamped by the Overseer's own irregular presence. No metric has a
  usable signal-to-noise ratio yet, so it is recorded and not implemented. The
  Greenlab porting sequence therefore does not gate any phase on an owner-effort
  number. See `../proofdelve-additions/additions.md`.
- **D5. Keep the `[MEASURED/REFUTED/OPEN/UNMEASURABLE]` epistemic tags in the
  current forts.** The corpus evidence-strength ladder is a different axis and
  earns its place only in Greenlab, where "real vs simulated" is the central
  question. See 04 and `../proofdelve-additions/`.
