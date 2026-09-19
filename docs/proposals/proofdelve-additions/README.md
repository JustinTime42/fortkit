# Proofdelve additions and advisory candidates

**Status: PLANNING / DRAFT.** From the 2026-09-18 research review of
`~/dev/autonomy` against the fort/civilization work. Nothing here is filed as a
bead or an advisory yet; these are review documents.

Two things came out of the review for the **current** civilization, and they use
different channels:

| File | Channel | What it is |
|---|---|---|
| [additions.md](additions.md) | Beads / adoption-pull | Seven capabilities worth **adding** to Proofdelve, ranked, each with an evidence gate. Feature-shaped: a Mayor reads them against her tree and chooses |
| [advisory-candidates.md](advisory-candidates.md) | `civ/advisories/` | Four **defects/gaps** that could bite silently, drafted in the advisory registry format, ready to file on approval. Service bulletins, not features |

The distinction is the civilization's own (standing order 13, `civ/advisories/README.md`):
an advisory reports *trouble that bites silently*; a feature announces itself and
needs no registry. Keeping them separate is deliberate — filing a feature as an
advisory would be exactly the category error the registry is designed to prevent.

## Three decisions the Overseer made (2026-09-18)

- **Owner-effort tracking is TABLED as a documented need.** Attention-minutes
  cannot be measured honestly (reading vs AFK); coupling latency is real but
  swamped by the Overseer's own irregular presence; owner-acts reduces to a thin
  approval count. No metric has a usable signal-to-noise ratio yet, so it is
  recorded and not implemented. See the "Tabled" section of additions.md.
  **Consequence for filing: advisory candidate B (coupling latency) is withdrawn
  from the filing set** — filing an advisory telling forts to measure a thing we
  just decided we can't measure well would contradict itself.
- **The `[MEASURED/REFUTED/OPEN/UNMEASURABLE]` tags stay.** The corpus
  evidence-strength ladder is a *different axis* (how good was the test), not a
  better version of the same one (should I believe it). Keep the epistemic tags
  in the current forts unchanged; the strength ladder earns its place only in
  Greenlab, where "real vs simulated" is the central question. So no swap here.
- **Identity stripping is mechanical + LLM + a moot failsafe**, not purely
  mechanical. See `../greenlab/03-port-and-identity-strip.md`.

## What is being filed (2026-09-18)

Three advisories, not four. Candidate B is withdrawn (above).

- **A** → `civ/advisories/adv-0013-airlock-send-ack-has-no-state.md`
- **C** → appended finding on the existing `adv-0011-*.md`
- **D** → `civ/advisories/adv-0014-acceptance-criteria-that-assert-instead-of-measure.md`

## Mayor's note

Filing these advisories is Manyhalls' duty, not a favour: the registry lives in
this repository and only the capital can write it (covenant §12.5). Filed
2026-09-18 on the Overseer's go-ahead. Origin blocks attribute to Proofdelve (the
fort whose tree carries each defect) with a head note naming Manyhalls' Mayor as
the finder during the 2026-09-18 research review — the ADV-0004 cross-settlement
pattern the registry schema documents.
