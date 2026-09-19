# 03 — Porting from Proofdelve, and the identity-strip task

## The decision (D2): copy Proofdelve, not the template

The obvious path is `fort-init` off the `fortkit/templates/` set, because that is
what the factory is built to do and the template is generic by construction. **We
are not taking that path**, for a measured reason: most of the last two weeks of
evolution landed in Proofdelve and never reached the template. Proofdelve carries
the fleet, the supervisor, the scratch reaper, the airlock, the Keep, the
push-ready gate, the touch-set guard, the signed-landing path, and ~40 harnesses;
the template carries none of the fleet at all
(`comm` of Proofdelve `fort/scripts/` against the template shows `airlock.sh`,
`fleet.conf`, `fleet.sh`, `fleet-supervisor.sh`, `probe-boundaries.sh`,
`probe-forge-masks.sh`, `scratch-reaper.sh`, `watch-push-drift.sh` present in
Proofdelve and absent from the template).

Founding Greenlab off the template would mean rebuilding two weeks of proven work.
Founding it off Proofdelve means **copying living files and then stripping
identity** — the more expensive and more dangerous path, and the one standing
order 12 explicitly warns about.

## The standing-order-12 hazard, named up front

`fort/charter.md` standing order 12: *"Architecture ports between forts; identity
never does."* And its sharpest clause: *"If you cannot separate them, stop and
ask — converging the file is not the safe default, it is the destructive one."*

Copying Proofdelve wholesale drags Proofdelve's **citizens, bead history,
incidents, annals, moot record, and fort-specific memory** into Greenlab, all of
which the rule forbids from travelling. So the port is not a copy; it is a copy
**plus a mandatory strip-and-reset task**, done per-hunk, with a human check that
no Proofdelve identity survived. This task is itself a deliverable and a risk, and
it is the reason Phase 1 in the sequence (05) has an explicit "no foreign
identity" exit gate.

## What ports (architecture — take it)

| Machinery | Source in Proofdelve | Notes |
|---|---|---|
| The fleet loop | `fort/scripts/fleet.sh`, `fleet-supervisor.sh`, `fleet.conf` | The centerpiece. Dials loosen (04, 05); model coupling generalizes (04) |
| Secret masks + host-RO binds | `fort/scripts/lib/seat-sandbox.sh` | **Unchanged — the walls of 01.** Extend the secret glob to cover production repos on the shared disk |
| Launchers | `fort/scripts/{mayor,forge,warden,researcher}.sh` | Identity-stripped; Forge gains the open-harness branch (04) |
| The airlock | `fort/scripts/airlock.sh` | Gains an effect-uncertain state; becomes the effect gateway's substrate |
| The Keep | `tools/keep/` | Becomes the experiment dashboard + signing desk |
| bd + event schema | beads, `schema/events.md` | Unchanged; add categories add-only |
| Memory ledger | `fort/memory/`, `consolidate-memory.mjs`, `memory-lint` | Unchanged; add the strength tag (02 §10) |
| Harnesses & verifier | `scripts/verify-impl.sh`, `scripts/*-harness.sh` | Verifier stays deterministic; its role shifts from gate to (mostly) tripwire per 02 |
| Control vocabulary | `docs/specs/enforcement-vocabulary.md` (Manyhalls) | The tool for sorting each control into keep/drop |
| fort-init | `bin/fort-init` | Copy the mechanism; point `FORT_REGISTRY` at the Greenlab registry; diverge the templates |

## What must be stripped and reset (identity — leave it)

Per standing order 12, every one of these is Proofdelve's and must not travel.
The strip task walks each and resets it:

- **Citizen names, pronouns, personalities:** Marrek Splitstone, Kethra/Veyra,
  Tova Marrowassay, Saelin Stillmere, and the Regent Calder Sealbroken. Every
  launcher's seat-identity marker, every seat file's occupant block, every
  `actor` default in the scripts. Greenlab holds its own founding moot and names
  its own citizens; none are inherited.
- **Bead history and IDs.** Proofdelve's `.beads/` and every `ForgeOs-*` id in
  comments, facts, and script headers. Greenlab starts with an empty tracker.
  Script comments citing `ForgeOs-*` beads as their rationale must be
  re-pointed or reset to Greenlab's own beads, or the rationale is a dangling
  reference to another fort's history.
- **Handoffs, annals, moot record, events.** Deleted, not carried. Greenlab's
  record starts at its own founding.
- **Fort-specific memory.** Proofdelve's `fort/memory/facts/` are about
  Proofdelve. The *architecture* facts (how the fleet behaves) may be
  generalized into Greenlab's own facts; the *incident* facts (what broke in
  Proofdelve on which date) do not travel.
- **Charter and seat prose** that names Proofdelve, its purpose, its customer,
  its gates. Replaced by the Greenlab covenant (02) and Greenlab seat files.

## The per-hunk discipline (how the strip is done safely)

Standing order 12 again: *"the two mix inside a single file, so the rule is
applied per hunk and never per file."* A launcher like `mayor.sh` carries both
the mask architecture (port it) and the Mayor's name and a Proofdelve push gate
(strip or reset it).

**The strip is not purely mechanical** (Overseer, 2026-09-18). A grep only catches
the literal strings; it misses personality prose, implicit references ("the seat
that reviews," a fact that is *about* a Proofdelve incident without naming it), and
tone that belongs to a specific citizen. So the strip is three layers, weakest
mechanical first, and ends with a human failsafe:

1. **Copy.** Proofdelve `fort/` and the relevant `scripts/` and `tools/` into the
   new Greenlab tree.
2. **Mechanical scan (cheap, catches the literals).** Grep for every current-civ
   citizen name, every `ForgeOs-` / `fortkit-` / `longburn-` / `WWWW-` id, every
   production fort name (Proofdelve, Manyhalls, Farlantern, Kithmason), every
   production registry path. Each hit is a hunk to review. Reset or rewrite the
   ones that are unambiguous (a registry path, a bead id in a comment).
3. **LLM identity pass (catches what grep cannot).** Feed the copied tree — or at
   least every file the mechanical scan flagged, plus the seat files, charter, and
   any prose-heavy script headers — through a model whose one job is to find
   identity markers the grep missed: personality, voice, implicit references to a
   Proofdelve citizen or incident, examples that assume Proofdelve's product. It
   proposes; a human disposes, per standing order 12's rule that where
   architecture and identity cannot be separated in a hunk you **stop and ask**
   rather than converge. The LLM is a finder, never an authority — its output is a
   candidate list, and the untrusted-input order applies to the tree it reads.
4. **Report.** Emit what was stripped and what was left, so the Phase 1 exit gate
   can review it. This is the closest thing to mechanical enforcement of a rule
   that is otherwise only prose — but it is explicitly not claimed to be complete,
   which is why the moot failsafe exists.

**The founding-moot failsafe.** Because no scan — mechanical or model — is proven
complete, the Greenlab founding moot is told plainly: *the tree may still carry
placeholder or example identity from Proofdelve, and part of founding is replacing
any such marker with the new civilization's own.* This turns the residual risk
into a standing task the founding citizens own, rather than a silent assumption
that the strip was total. It is the same instinct as a positive control: assume the
scan can fail, and make the failure something a human is looking for rather than
something that ships unnoticed.

## What changes on the port (law and dials)

Detailed in 02 (covenant), 04 (models/harnesses), 05 (sequence). In brief:

- Warden merge-gate → tripwire, except the money path.
- Prose push/deploy gate → gone; governed + gated only above spend/identity
  threshold.
- Human gates six → three.
- Governor ceilings added.
- Forge gains the open-harness branch and the routing ladder.
- The effect gateway seat is added.
- Facts gain the evidence-strength tag.

## Why not just improve the template first

Considered and rejected for now. Backporting two weeks of Proofdelve evolution
into `fortkit/templates/` is real, valuable work (it is what the fort-backport
machinery exists for), but it is a large task on the critical path of the
*production* civilization, and Greenlab does not need to wait for it. The clean
sequence is: found Greenlab off Proofdelve now with the strip task; separately,
and later, backport the generic half into the template so the *next* fort in
either civilization is cheaper. The strip task's foreign-identity report is, not
coincidentally, most of the evidence a good template backport would need anyway.
