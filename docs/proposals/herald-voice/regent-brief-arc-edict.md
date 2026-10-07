# Regent sitting brief: the Herald's weekly arc (fortkit-r6x.8.6)

Prepared by the Mayor 2026-10-07. Also carries `fortkit-r6x.8.11` (stale
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
| `herald.sh.arc.proposed` (diff `herald.sh.arc.diff`, 8 hunks) | `civ/scripts/herald.sh` | `HERALD_MODE=daily\|arc`; arc writes `reports/arc-<date>.md`; arc prompt from law 9a; exclusive `flock` before `session.start` in every mode, 60-minute wait, then exit 66 with an incident; carried-correction paragraph removed (dqu5.9); mode in session events and the crash stub's title |
| `herald.service.proposed` | `civ/systemd/herald.service` and `~/.config/systemd/user/herald.service` | drops the no-op log move-aside and its stale comment (8.11) |
| `herald-arc.service.proposed` | `civ/systemd/herald-arc.service` and the user unit dir | copy of the daily unit with `HERALD_MODE=arc` and `After=herald.service` |
| `herald-arc.timer.proposed` | `civ/systemd/herald-arc.timer` and the user unit dir | `Sun *-*-* 06:00:00`, `Persistent=true` |

**Deviation from the spec, on purpose:** the lock file is
`${XDG_RUNTIME_DIR:-/tmp}/herald.lock`, not `$vault/.herald.lock`. The
Herald can write the vault, and a lock file he deleted would let a second run
in. Outside the vault, he cannot touch it. The launcher holds fd 9 host-side for
the whole run.

## Measured, not assumed

- `bash -n` and `shellcheck -x` on the proposed launcher: clean. The carried
  correction no longer appears in it.
- The lock, measured with `flock` on a scratch lock file, three holders: A
  takes it and holds 4 s; C (1 s wait) is refused while A holds it; B (10 s
  wait) acquires it the second A releases.
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
   probe PASS and SMOKE-COMPLETE each time.
5. Lock, live: start a smoke run, and while it runs start a second one; the
   second must print nothing until the first ends, then proceed.
6. Optional, costs one arc run: `systemctl --user start herald-arc.service`,
   then confirm `reports/arc-<date>.md` exists and NO new date-named report
   appeared. Otherwise the first live run is Sunday 2026-10-11 06:00, and the
   next daily report's window proves the daily run was untouched.
7. Commit path-scoped, close `fortkit-r6x.8.11` and `fortkit-dqu5.9`; close
   `fortkit-r6x.8.6` after the first live arc report (spec acceptance 4).

`fortkit-r6x.8.10` (wiring herald-lint) is not in this sitting: it waits on the
Forge's `fortkit-r6x.8.3`.
