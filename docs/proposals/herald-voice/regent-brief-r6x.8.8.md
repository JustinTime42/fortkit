# Regent sitting brief: fortkit-r6x.8.8, Herald launcher and profile

Prepared by the Mayor 2026-10-06 at the Overseer's request; revised the same
day on the Warden's REQUEST-CHANGES (round 1). Gate-1: `civ/scripts/herald.sh`
and `civ/profiles/herald-settings.json` are kernel read-only to every masked
seat, so this is Regent work by edict with the Overseer present.

## Why

`fortkit-r6x.8.2` amended the Herald's law the same day (commit `343aa86`): a
fifth rubric bar (Postable), a declared-stake exception, zero contrastive
reframes, at most one draft per run. The launcher prompt still says "four bars"
and "'not X but Y' reframes" (Warden finding 4 on 8.2). And bar 5 draws
thresholds from `brand-voice.md`, which sits in the vault the launcher binds
writable, so the Herald could edit part of his own bar; the law forbids it in
prose only (Warden finding 1 on 8.2).

## The change

Launcher: `docs/proposals/herald-voice/herald.sh.proposed`, diff
`herald.sh.r6x.8.8.diff` (four hunks; the first is the exit-code header):

1. Comment and `voice_line`: the doc is approved; the prompt says it is
   read-only and never edited.
2. Morning prompt steps 4-5: five bars; frontmatter `postable:` and
   `invented:`; contrastive reframes; at most one draft per run.
3. Mask and pre-flight: `--ro-bind` of `brand-voice.md` over the writable vault
   bind, then a **kernel check with no model in the path**: a zero-byte append
   to the doc inside the full mask must fail, or the launcher emits an incident
   and exits 66 before any session or spend. It runs on smoke and real mornings
   alike.

Round 1 had a smoke probe 10 instead of the pre-flight. The Warden showed it
was blind: the model's `echo` is refused by the permission profile before the
kernel is reached, so it passed with or without the bind. It is removed.

Profile: `herald-settings.json.proposed` adds `Edit` and `Write` denies on
`brand-voice.md` plus a `$comment` line (Warden finding 3). Deny is intent; the
pre-flight is the proof.

## Measured, not assumed

- `bash -n` and `shellcheck -x`: clean. Proposed profile parses as JSON.
- The pre-flight, measured by the Mayor with the REAL mask lib
  (`fort/scripts/lib/seat-sandbox.sh`, `build_mask claude`) on a scratch vault,
  both arms:
  - without the ro-bind, the check finds the doc writable (launcher would
    refuse): the check is not blind;
  - with it, the check is blocked (launcher proceeds), and a write elsewhere in
    the vault still succeeds; the doc's content was unchanged.
- Round 3 (Warden r2 APPROVE-WITH-FINDINGS, both findings applied): the check
  now FAILS CLOSED, counting only an append refused with "Read-only file
  system" as the bind holding, and the exit-code header names the new cause of
  66. Re-measured with the real mask lib, three arms: no ro-bind at 0644,
  REFUSE; no ro-bind at 0444 (the Warden's two-fault case, EACCES), REFUSE;
  ro-bind at 0644, proceed. Doc content unchanged.
- NOT measured: the installed launcher on the live vault. That is step 4.

## Baseline

Vault `brand-voice.md` sha256 at prep time begins `a83c329b9819854e`; it was
byte-identical to `docs/proposals/herald-voice/brand-voice.md` (`cmp`) after
the Overseer's re-copy. Record `sha256sum` again at the start of the sitting
and compare against that, not against the repo file (Warden finding 4).

## Sitting steps

1. Read both diffs. Warden verdicts (round 1 REQUEST-CHANGES, round 2
   APPROVE-WITH-FINDINGS, findings applied in round 3) are on `fortkit-r6x.8.8`.
2. Record the vault doc's sha256.
3. Install: copy `herald.sh.proposed` to `civ/scripts/herald.sh` and
   `herald-settings.json.proposed` to `civ/profiles/herald-settings.json`.
4. Verify: `HERALD_SMOKE=1 civ/scripts/herald.sh opus`. Expect no PRE-FLIGHT
   FAILED line, every probe PASS, SMOKE-COMPLETE, and an unchanged sha256.
   Negative arm, optional: run with the ro-bind line commented out in a scratch
   copy and confirm exit 66.
5. Emit `charter.amended` targeting `fortkit-r6x.8.8`, commit path-scoped,
   close the bead.

Timing: the timer fires at 05:00. Uninstalled, tomorrow's run reads the new law
under the old prompt; the law outranks the prompt and he should log the
mismatch. Nothing breaks either way.

Out of scope: a doc created after launch is unprotected (Warden finding 2),
filed as `fortkit-r6x.8.9`.
