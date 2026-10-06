# Regent sitting brief: fortkit-r6x.8.8, Herald launcher

Prepared by the Mayor 2026-10-06 at the Overseer's request. Gate-1: the change
is to `civ/scripts/herald.sh`, kernel read-only to every masked seat, so it is
Regent work by edict with the Overseer present.

## Why

`fortkit-r6x.8.2` amended the Herald's law the same day (commit `343aa86`): a
fifth rubric bar (Postable), a declared-stake exception, zero contrastive
reframes, at most one draft per run. The launcher prompt still says "four bars"
and "'not X but Y' reframes" (Warden finding 4 on 8.2). And bar 5 draws
thresholds from `brand-voice.md`, which sits in the vault the launcher binds
writable, so the Herald could edit part of his own bar; the law now forbids it
in prose only (Warden finding 1).

## The change

Proposed file: `docs/proposals/herald-voice/herald.sh.proposed`.
Diff: `docs/proposals/herald-voice/herald.sh.r6x.8.8.diff` (44 lines). Four hunks:

1. Comment and `voice_line` above the brand-voice check: the doc exists and is
   approved; the prompt tells him it is read-only and never edited.
2. Morning prompt steps 4-5: five bars; frontmatter `postable:` and
   `invented:`; count contrastive reframes; at most one draft per run.
3. Smoke prompt: probe 10, an append to `brand-voice.md` must be BLOCKED.
4. Mask: `[ -f "$voice" ] && mask+=(--ro-bind "$voice" "$voice")` after the
   writable vault bind.

## Measured, not assumed

- `bash -n` and `shellcheck -x` on the proposed file: clean.
- The bind ordering, measured with bwrap in the Mayor's session on a scratch
  vault: a `--ro-bind` of the file after a `--bind` of its directory refuses
  append (EROFS), rename and unlink (mount point), while writes to `drafts/`
  in the same vault succeed. The voice doc was unchanged afterwards.
- NOT measured: the live launcher with the change installed. That is the
  sitting's verification step below.

## Sitting steps

1. Read the diff. (The Mayor has dispatched the Warden on it; her verdict is on
   `fortkit-r6x.8.8`.)
2. Install: `cp docs/proposals/herald-voice/herald.sh.proposed civ/scripts/herald.sh`.
3. Verify: `HERALD_SMOKE=1 civ/scripts/herald.sh opus`. Expect every probe
   PASS including 10, the line SMOKE-COMPLETE, and `brand-voice.md` unchanged
   (`cmp` against `docs/proposals/herald-voice/brand-voice.md`).
4. Emit `charter.amended` (launcher) targeting `fortkit-r6x.8.8`, commit
   path-scoped, close the bead.

Timing: the timer fires at 05:00. Uninstalled, tomorrow's run reads the new law
under the old prompt; the law outranks the prompt and he should log the
mismatch. Nothing breaks either way.
