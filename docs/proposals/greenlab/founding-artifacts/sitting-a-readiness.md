# Sitting A readiness check

**The hand-off the Overseer gives the Regent to run Sitting A.** Verified
2026-09-22 by the Mayor of Manyhalls. Sitting A founds Greenlab, strips Proofdelve
identity, and proves the walls on the shared machine. It is break-glass work:
Regent executes, Overseer present and signs the gate.

---

## 1. Prep verification (done — this is the green light)

| Check | Result |
|---|---|
| All six Phase P beads closed | ✅ `fortkit-2y2t.1`–`.6` closed |
| Sitting A dependencies satisfied | ✅ all six show ✓ on `fortkit-2y2t.7` |
| All seven founding artifacts present | ✅ covenant, seats, effect-gateway-seat, charter-template, identity-strip-spec, llm-identity-pass-prompt, sitting-a-runbook |
| Master plan filed | ✅ `founding-plan.md`, tree `fortkit-2y2t` |

The prep band is complete. The tree is staged to run against a spec, not a
conversation.

## 2. Decisions to LOCK before the sitting (Phase 0)

These are the Overseer's to settle at or before the start. The artifacts use
working values; confirm or change them:

- [ ] **Registry path.** Working value: `~/.claude/greenlab.json`. Must be disjoint
      from `~/.claude/civilization.json`.
- [ ] **Capital repo location.** Not yet chosen. (Working suggestion `~/dev/greenlab`;
      the Overseer decides.)
- [ ] **Civilization name.** "Greenlab" is a placeholder throughout. It may be named
      now or deferred to the founding moot (A7); the identity strip and the moot
      failsafe both assume placeholders may survive, so deferring is safe.

## 3. Have open / on hand

- [ ] This runbook's source: `founding-artifacts/sitting-a-runbook.md` (Parts 1 & 2).
- [ ] The founding artifacts to install: covenant, seats, effect-gateway-seat,
      charter-template.
- [ ] The strip tooling spec (P4) and the LLM identity-pass prompt (P5).
- [ ] A capable model for the P5 pass, and an **unmasked host shell** for the wall
      proof (Part 2 requires it — never run the probe inside a mask).
- [ ] The production registry and the customer repo list, to enumerate the probe
      surface from live state.

## 4. Run order (condensed from runbook Part 1)

1. [ ] Create Greenlab capital repo + registry (disjoint from production).
2. [ ] Install the founding artifacts (occupant slots as placeholders).
3. [ ] Copy the Proofdelve tree (fort/, scripts/, tools/, fleet machinery).
4. [ ] Run the mechanical strip (P4) → flagged-set report. An unreadable file blocks.
5. [ ] Run the LLM identity pass (P5) → candidate list. **Overseer dispositions every
       entry; resolve each `INSEPARABLE` hunk by hand (do not converge).**
6. [ ] Apply dispositions; re-run the mechanical strip to confirm the flagged set shrank.
7. [ ] Found one throwaway Greenlab fort against the Greenlab registry.
8. [ ] Run the wall proof from an unmasked host shell.
9. [ ] Sign the gate (§5 below). Then **STOP** — the fleet is Sitting B.

## 5. Gate-sign criteria (the Overseer signs only if ALL hold)

Sign against the probe's **verdict table** (byte counts and exit codes), never a
summary sentence:

- [ ] **Secrets read zero.** Every production secret returns **0 bytes** from every
      Greenlab seat mask, under the canonical path AND the obfuscated spellings.
- [ ] **Positive twins green.** A neutral file reads nonzero from each mask (so the
      zeros are the mask's doing, not a broken probe). A withheld probe from a
      failed twin is a FAIL.
- [ ] **Context honest.** The probe confirms the same secrets read nonzero from the
      unmasked host — proving the zeros come from the mask, not the context. (The
      shared-machine scar: a probe run inside another mask reports vacuous zeros.)
- [ ] **Repos unwritable.** `touch` into every production repo/worktree **fails**
      from each Greenlab mask; the positive twin (`touch` into Greenlab's own tree)
      **succeeds**.
- [ ] **Launch boundary holds both ways.** A Greenlab seat from a production mask
      aborts, and vice versa; the two registries name disjoint fort sets.
- [ ] **Greenlab's own credentials masked** to Greenlab's reasoning seats (Effect
      Gateway secrets read 0 from every other seat).
- [ ] **No NAMED on a secret surface.** Isolation rests on inode-level masks, not
      string-level deny rules. A NAMED verdict on a secret surface is not a PASS.
- [ ] **Strip reviewed.** The strip report and disposition list reviewed; the
      founding moot warned that placeholder identity may survive.

Any FAIL, any NAMED on a secret surface, or any withheld-for-broken-twin: **do not
sign.** Sitting A ends at step 8. A red wall proof on the shared machine is the one
outcome this whole plan was built to catch early — stopping there is correct, not a
failure.

## 6. Roles

- **Regent (Calder):** executes every step. Unmasked, root, break-glass.
- **Overseer:** present throughout; dispositions the strip hunks; signs the gate;
  locks the Phase 0 decisions. The graduation decision and the naming remain his
  forever.
- **Mayor (Manyhalls):** not in this sitting — masked, cannot create a registry or
  touch another repo. Prep is done; the ball is with the Regent and the Overseer.

## 7. After the gate

- The founding moot (A7, `fortkit-2y2t.8`) names Greenlab's citizens, filling the
  seat placeholders.
- Sitting B (`fortkit-2y2t.9`) ports the fleet. It is a separate sitting; there is
  no need to run it the same day, and the plan is built so stopping after A's
  signed gate is a complete, coherent outcome (an isolated empty civilization,
  proven not to leak).

---

**Go / no-go:** prep verified complete (§1). The sitting is ready to run once the
Phase 0 decisions (§2) are locked. Everything else is staged.
