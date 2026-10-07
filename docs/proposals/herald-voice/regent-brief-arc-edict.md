# Regent sitting brief: the Herald's weekly arc and herald-lint wiring (fortkit-r6x.8.6, fortkit-r6x.8.10)

Prepared by the Mayor 2026-10-07. Also carries `fortkit-r6x.8.10` (wire
herald-lint into both runs; folded in because it edits the same launcher, so
one sitting installs one coherent file), `fortkit-r6x.8.11` (stale
log-rename in `herald.service`) and `fortkit-dqu5.9` (retire the carried
correction from the morning prompt). Gate-1: `civ/scripts/`, `civ/systemd/`
and the user's systemd units are edict surfaces, and the law text applies in
this same sitting.

## Authority on record

- Spec `docs/specs/herald-arc.md`: ADOPTED 2026-10-07 (Overseer approval in
  session after Warden APPROVE-WITH-FINDINGS, findings applied).
- Law text `docs/proposals/herald-voice/arc-law-section.md` at `3ac2290`:
  Warden APPROVE-WITH-FINDINGS, findings applied; **SIGNED by the Overseer
  2026-10-07** (comment on `fortkit-r6x.8.6`). Its own header requires it to be
  applied in the same sitting as this edict, never before.
- The Warden's verdict on this prep is on `fortkit-r6x.8.6`.

## The change

All files in `docs/proposals/herald-voice/`.

| Proposed file | Installs to | What |
|---|---|---|
| `herald.sh.arc.proposed` (diff `herald.sh.arc.diff`) | `civ/scripts/herald.sh` | `HERALD_MODE=daily\|arc`; arc writes `reports/arc-<date>.md`; arc prompt from law 9a; exclusive `flock` before `session.start` in every mode, 40-minute wait, then exit 66 with an incident; the lock file re-bound read-only in the mask and fd 9 closed on every bwrap; carried-correction paragraph removed (dqu5.9); mode in session events, incident texts and the crash stub (arc stub uses the 9a headings) |
| `herald-settings.lint.json.proposed` | `civ/profiles/herald-settings.json` | one allow rule, `Bash(node /home/justin/dev/fortkit/src/cli.ts herald-lint*)`, plus a `$comment` line (8.10) |
| `herald.service.proposed` | `civ/systemd/herald.service` and `~/.config/systemd/user/herald.service` | drops the no-op log move-aside and its stale comment (8.11) |
| `herald-arc.service.proposed` | `civ/systemd/herald-arc.service` and the user unit dir | copy of the daily unit with `HERALD_MODE=arc` and `After=herald.service` |
| `herald-arc.timer.proposed` | `civ/systemd/herald-arc.timer` and the user unit dir | `Sun *-*-* 06:00:00`, `Persistent=true` |

**Deviation from the spec, on purpose:** the lock file is
`/tmp/herald-<uid>.lock`, one fixed path for every launch (Warden finding 3:
an `XDG_RUNTIME_DIR` fallback gave two different files), not
`$vault/.herald.lock`. `/tmp` is writable inside the mask too (Warden finding
1 corrected the round-1 claim that he "cannot touch it"), so the claim is made
true at the kernel instead of asserted: the mask re-binds the lock file
read-only, and every bwrap call closes fd 9 (`9>&-`) so only the launcher holds
the lock.

**Wait vs. unit timeout** (Warden finding 2): the lock wait is 40 minutes, under
the units' `TimeoutStartSec=45min`, so a refused run still emits its incident
and exits 66 instead of being SIGTERMed silently.

**herald-lint wiring (8.10).** Both prompts now say: before filing any draft or
rewrite, run `herald-lint <file> --json`; on fail, revise or spike; add one
double-quoted `postable:` list item with the verdict, fails and flags; answer
every flag and judgment item in the report. herald-lint is on main
(`fortkit-r6x.8.3` merged `f190a7a`, `fortkit-r6x.8.13` merged `83694d3`, both
Warden APPROVE-WITH-FINDINGS, verify green at 296 tests).

## Measured, not assumed

- herald-lint against the real vault (the Mayor, 2026-10-07, after the
  `83694d3` merge): the Herald's own 2026-10-07 draft and all 8 rewrites
  return verdict pass, frontmatter included. Before `fortkit-r6x.8.13` every
  one of them failed frontmatter, which is why wiring waited for it.

- `bash -n` and `shellcheck -x` on the proposed launcher: clean. The carried
  correction no longer appears in it.
- The lock, measured with `flock` on a scratch lock file, three holders: A
  takes it and holds 4 s; C (1 s wait) is refused while A holds it; B (10 s
  wait) acquires it the second A releases.
- Round 2, measured with the REAL mask lib (`build_mask claude`), each with a
  negative control: without the ro-bind a masked child deletes a lock-like
  file in `/tmp` (so the bind is needed); with it, unlink is refused and a
  write fails with "Read-only file system". Without `9>&-` the masked child
  inherits fd 9; with it, the child has no fd 9.
- `systemd-analyze calendar "Sun *-*-* 06:00:00"`: valid; next elapse Sun
  2026-10-11 06:00 AKDT.
- The installed `herald.service` and `herald.timer` were byte-identical to
  `civ/systemd/` before this prep.
- NOT measured: either mode end to end with the change installed. That is
  steps 4 to 6.

## Sitting steps

1. Read the diffs and the Warden's verdict.
2. Apply the law text to `civ/law/herald.md` (its four changes), emit
   `charter.amended` targeting `fortkit-r6x.8.6`.
3. Install the launcher and the three units (table above), then
   `systemctl --user daemon-reload` and
   `systemctl --user enable --now herald-arc.timer`.
4. Smoke, both modes: `HERALD_SMOKE=1 civ/scripts/herald.sh opus`, then
   `HERALD_SMOKE=1 HERALD_MODE=arc civ/scripts/herald.sh opus`. Expect every
   probe PASS and SMOKE-COMPLETE each time. The smoke prompt does not depend on
   the mode, so the arc smoke proves mode parsing, the lock and the mask, and
   **never the arc prompt** (Warden finding 5); the arc prompt is first
   exercised by step 6 or by Sunday's live run.
5. Lint, live: inside the smoke run's mask the allow rule must let
   `node /home/justin/dev/fortkit/src/cli.ts herald-lint <any vault draft> --json`
   run. The smoke prompt does not exercise it; run it by hand once from the
   Herald's profile, or accept the first live morning as its proof and read
   that report's postable: line.
6. Lock, live: start a smoke run, and while it runs start a second one; the
   second must print nothing until the first ends, then proceed.
7. Optional, costs one arc run: `systemctl --user start herald-arc.service`,
   then confirm `reports/arc-<date>.md` exists and NO new date-named report
   appeared. Otherwise the first live run is Sunday 2026-10-11 06:00, and the
   next daily report's window proves the daily run was untouched.
8. Commit path-scoped, close `fortkit-r6x.8.10`, `fortkit-r6x.8.11` and
   `fortkit-dqu5.9`; close
   `fortkit-r6x.8.6` after the first live arc report (spec acceptance 4).

