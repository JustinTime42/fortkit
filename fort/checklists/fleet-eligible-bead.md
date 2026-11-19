# Checklist: writing a bead the fleet may run unattended

> **Carried from Proofdelve at Manyhalls's re-founding, 2026-11-18 (`fortkit-ttpk`).**
> The procedure is the machinery's and holds here. The incidents, bead ids, paths and
> numbers in the examples are that fort's: read them as the reasons for each rule, and
> re-measure anything you would rely on (`fort/scripts/fleet.conf` ships conservative
> values and `FLEET_ENABLED=0`; no Manyhalls timer is installed).

Maintained by the Mayor. `Proofdelve ForgeOs-dx34.6`, from `docs/specs/continuous-fleet.md`
§9 and `Proofdelve ForgeOs-8zb7`. Read before labelling anything `fleet-safe`.

**Why this exists, in the spec's words:** "Acceptance criteria are the
load-bearing control in unattended work, because they are the only place a
human's intent survives into a room with no human in it. Criteria that assert a
conclusion convert a Mayor's mistakes into merged code. Criteria that demand a
measurement catch them." Both demonstrations are this fort's own (`Proofdelve ForgeOs-4k3`
and `Proofdelve ForgeOs-h8qd`, 2026-09-08) and the discipline worked both times because the
Mayor remembered it. This file makes it cheaper than remembering.

**Why it is a checklist and not a `bd formula`.** Formulas pour child beads from
workflow steps (`bd mol pour`). Acceptance criteria are prose inside one bead,
and the failure this guards against is a *sentence* that asserts where it should
measure. A checklist read at authoring time is the vehicle that reaches that
sentence; a formula is not. Decided 2026-09-11.

---

## The description

- [ ] **OBSERVED, not imagined** (standing order 15). Name the run, the review,
      the commit or the measurement that surfaced it. "An attacker could" is a
      threat-model entry, not a bead.
- [ ] **The mechanism, at source.** `file:line`, read today, not recalled. Say
      "read from source" when it is, and "unmeasured" when it is a reading.
- [ ] **The decision, if one was made, and who made it.** A bead that hides a
      product choice inside its criteria gives the Forge a decision the Overseer
      never took.
- [ ] **What is OUT of scope, by name**, when a neighbouring defect will tempt the
      builder (`Proofdelve ForgeOs-342` criterion 6 is the model: "touching it here would
      give the review two contracts to judge").

## The criteria

Numbered. Every one of these must be present; the order is a suggestion.

- [ ] **1. A criterion phrased as a MEASUREMENT whose honest answer may be "no
      change needed", with that outcome named as legitimate.** `Proofdelve ForgeOs-4k3`
      criterion 1 is the worked example and the reason: "IF THE API'S FILE
      DETERMINISTICALLY WINS, WRITE THAT DOWN WITH THE EVIDENCE AND CHANGE
      NOTHING." The Mayor's belief was wrong; the criterion let the builder say
      so; an asserted conclusion would have put the error in the trunk behind a
      green verifier. If the bead cannot be given such a criterion, ask whether
      the Mayor is asserting rather than asking.
- [ ] **2. THE OUTCOME THAT MUST NOT CHANGE, as its own numbered criterion.** The
      thing that would go green as a side effect of a *wrong* fix. `Proofdelve ForgeOs-b0vj.24`
      criterion 3: "if this goes green as a side effect of satisfying 1 and 2,
      validation has been REMOVED rather than REORDERED, and that is a worse
      defect than the one being fixed. State explicitly which happened." Without
      this, every stated criterion can be green while the fix is a regression.
      **If another criterion changes a string, this one must say which
      assertions may change and how (tighten only: `Contain` to exact `Be`).**
      `Proofdelve ForgeOs-b0vj.55` criterion 4 said five refusal tests "pass unmodified"
      while criterion 3 mandated a new message; three of the five assert the
      text, so they could not. The Forge took the escape hatch correctly and
      recorded each edit first, but a wrong fix could have loosened an assertion
      and cited criterion 3. The contradiction is the author's (`Proofdelve ForgeOs-dx34.17`).
- [ ] **3. STEP 1: SHOW IT RED.** The executed negative control. Run the new test
      or check against the PRE-FIX code, or against a planted defect, and show it
      fail; restore, show it pass. Kills the cannot-fail class (`Proofdelve ForgeOs-h8qd`:
      a pin that hashed the file the preceding step had just written).
      **The Warden cannot reproduce this step, by construction:** her scratch
      copy refuses source writes (`sed -i` denied, `perl -pi` prompts, `cp` and
      `git show >` both denied, measured on `Proofdelve ForgeOs-pyy5`, `b0vj.55` and
      `aqc6.5` in one run). Every RED she records is the Forge's paste plus an
      analytic check that the code path must fail that way. So the paste IS the
      execution record, and a review must say "taken on the paste", never
      "reproduced" (`Proofdelve ForgeOs-dx34.17`).
- [ ] **4. STEP 2: SHOW IT GREEN AGAINST A CORRECT VARIANT** that differs in
      spelling or implementation from the one in front of you. Kills the
      pins-a-spelling class. **This is the step most likely to be dropped as
      fussy and the one that has never been asked for by habit here**; it would
      have caught all three of the 2026-09-08 sitting's sightings before they
      shipped, and the Warden found a fourth live in `governor-harness.sh:263`.
      Applies whenever the subject is a *control* (a test, a guard, a harness, a
      verifier stage). For a plain product change, say "not applicable: the
      subject is not a control" rather than leaving it silent.
- [ ] **5. STEP 3: A THIRD OUTCOME, "I could not run", distinct from "the subject
      failed", and shown firing.** Kills the misattribution class. Worked example
      in this tree: `scripts/landable-harness.sh:161-192`, which extracts the
      launcher's function table and then **requires the result to parse**
      (`bash -n`, :172-173) and **requires every symbol a case needs to be
      present** (:190), refusing with `HARNESS REFUSES` and exit 3 instead of
      scoring a column of failures that read like defects in the launcher. Cite it; do not reinvent it. Same applicability rule as step 2.
- [ ] **6. PASTE, AND SAY WHAT.** "Paste the raw runner lines" produced, on
      2026-09-10, six summaries in one day; on 2026-09-11 "PASTE THE RAW RUNNER
      LINES for both runs, not a summary" produced the runner's summary line and a
      paraphrased assertion. So say all three: **the runner's summary line, the per-test
      lines naming WHICH tests failed, AND the assertion text**, into the bead
      comment AND the handoff (`Proofdelve ForgeOs-b0vj.47` pasted `Failed 3/0/3` and the Warden
      could not tell from it that one criterion-1 test was never in the control). A control may be
      deleted only after its output is pasted (`Proofdelve ForgeOs-aqc6.2.7.2` deleted its
      control and left nothing reproducible). `Proofdelve ForgeOs-dx34.10` carries the
      prompt-side half. **A criterion that renames something must ask for the
      OLD name in the record**: `Proofdelve ForgeOs-pyy5` criterion 6 evidenced the
      because-text half and never the name half, and once the old spelling is
      gone from the tree nothing can pin it (`Proofdelve ForgeOs-dx34.17`).
- [ ] **7. A NAMED INSTRUMENT, pasted.** A grep, a `--list-tests`, a `sed -n`
      range, a `sha256sum`: the one command whose output lets the reviewer check
      the claim without opening the file. The Warden reviews under a profile that
      cannot execute anything under `scripts/` (`ADV-0011`), so the paste is the
      only execution record that reaches her. **Write the criterion as "paste the
      raw output of `<exact command>`, before and after", never "confirm with
      grep".** Run `20260911T124207` pasted every runner line and summarised
      three of four instruments; one summary reported a four-hit grep as one hit
      (`Proofdelve ForgeOs-aqc6.5`, `Proofdelve ForgeOs-dx34.16`). The Forge prompt names runner
      output and not instruments, so the criterion has to.
- [ ] **8. The `Proofdelve ForgeOs-u65j.4` line, verbatim:** "Full verifier green in this
      bead's own worktree. If it will not RUN there, that is a finding to report
      on this bead, not an obstacle to route around."
- [ ] **9. LANE and label.** Say who may execute it. `fleet-safe` only if: no gate
      1 trigger on the merits (auth, identity linking, which rows a caller sees),
      no migration, no `fort/scripts/` or `fort/profiles/` path, no Docker-only
      test as the evidence. Product-decision beads carry `human` instead.
      *Posture note, 2026-10-26, permanent by the Overseer's ruling of 2026-11-14 (`Proofdelve ForgeOs-yhn44`; the posture is the one word in `fort/scripts/sandbox-posture`; docket `fort/annals/regent-docket-2026-10-26-secrets-only.txt`). While the posture is `secrets-only`, "no Docker-only test as the evidence" is LIFTED by the Overseer's decision 5 ("yes docker backed test results are actionable for the fleet"): a Docker-backed run (`VERIFY_REQUIRE_DOCKER=1`, MigrationTests included), made in the bead's own worktree and pasted on the bead, is valid fleet evidence. "No migration" stays: a migration is gate 2 and the run informs his signature, never replaces it. Test and validation dev dependencies are pre-approved (decision 4, recorded in `docs/ui-design-system.md` under Allowed packages).*

## Before labelling `fleet-safe`

- [ ] Read the criteria as the Forge will: **is there a sentence a wrong fix
      could satisfy?** If criterion 2 does not name it, find it.
- [ ] Count: one measurement-with-refutation, one must-not-change, one RED, one
      GREEN-variant (or "not applicable" stated), one could-not-run (or "not
      applicable" stated), one paste instruction that names both halves, one
      instrument, the u65j.4 line, a lane. Nine. Fewer is not ready.
- [ ] Queue size: five, or six-plus **deliberately** as the `Proofdelve ForgeOs-dx34.5`
      contention experiment. The governor raises Forge concurrency at roughly six.

## Measured against the hand-written references (`dx34.6` criterion 5)

Applied 2026-09-11 to `Proofdelve ForgeOs-pyy5` (subject: a control), then compared with
the hand-written criteria on `Proofdelve ForgeOs-342`, `etd8` and `4k3`:

| item | 342 | etd8 | 4k3 | pyy5 as first filed | pyy5 via this checklist |
|---|---|---|---|---|---|
| measurement, refutation legitimate | no | no | **yes** (c1) | no | yes |
| must-not-change | c6 (scope), c4 (strengthened not replaced) | c5 | c5 | c3 | yes |
| step 1 RED | c2 ("fail against the pre-fix file") | c4 | implicit in c1's pin | c3 | yes |
| step 2 GREEN-variant | no | no | no | no | **yes** |
| step 3 could-not-run | no | no | no | no | **yes** |
| paste, both halves | no | "output recorded" | no | summary + assertion | yes |
| named instrument | citations | no | c2 (grep) | `--list-tests` | yes |
| u65j.4 line | c7 | no | c6 | no | yes |
| lane | header | no | header | no | yes |

So the three hand-written sets each carry between four and six of the nine, and
none carries steps 2 or 3, which is exactly what `Proofdelve ForgeOs-8zb7` found. The
checklist version of `pyy5` carries all nine and is not weaker than any of the
three on any row. The rewritten criteria are on `Proofdelve ForgeOs-pyy5`; the original set
is preserved in a comment there.
