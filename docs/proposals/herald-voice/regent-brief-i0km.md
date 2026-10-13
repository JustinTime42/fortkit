# Regent sitting brief: fortkit-i0km, Herald commands refused for a cd prefix

Prepared by the Mayor 2026-10-13 at the Overseer's request. Gate-1:
`civ/scripts/herald.sh` is edict surface. A prompt-text change only: no mask,
lock, profile or unit changes.

## Why

Measured by the Regent in the 2026-10-13 arc sitting (both smokes; logs
`/tmp/herald-2026-10-13-090813.log`, `/tmp/herald-2026-10-13-090821.log`): the
model prefixed `cd /home/justin/dev/fortkit &&` to the digest command (daily
smoke, probe 6) and to herald-lint (arc smoke, probe 10). The profile allows
those commands only as a bare prefix, so the compound form was refused; both
passed on a retry. In a live run a refused lint takes the not-run path, so a
permitted lint would go unrun. The launcher already runs claude with cwd =
`$root`.

Note: probe 6's wording never said "from $root", yet the model added `cd`
anyway. So removing the phrase alone may not be enough, and this change also
states the working directory explicitly.

## The change

`docs/proposals/herald-voice/herald.sh.i0km.proposed`, diff
`herald.sh.i0km.diff` (5 lines changed, prompt text only):

1. All five `(from $root)` / `(run from $root)` clauses removed: the smoke's
   probe 10, and the digest and herald-lint steps of both the arc and the daily
   prompt.
2. One sentence added near the top of each of the three prompts (smoke, arc,
   daily): "Your working directory is already $root. Run every command exactly
   as written, never with a cd prefix: the permission profile refuses compound
   commands (fortkit-i0km)."

Not done, on purpose (the bead's own instruction): widening the allow rule to
admit `cd *`. A wildcard ahead of the command is the riev class.

## Measured, not assumed

- `bash -n` and `shellcheck -x`: clean. `from $root` occurs 0 times in the
  proposal; the new sentence occurs 3 times.
- The installed launcher was byte-identical to the reviewed arc proposal
  before this prep (checked 2026-10-13 after the arc sitting), so this diff is
  against exactly what was reviewed and installed.
- NOT measured: whether the model now runs the commands bare on the first
  attempt. That is the acceptance, below.

## Sitting steps

1. Read the diff and the Warden's verdict on `fortkit-i0km`.
2. Install: copy `herald.sh.i0km.proposed` to `civ/scripts/herald.sh`.
3. Smoke, both modes: `HERALD_SMOKE=1 civ/scripts/herald.sh opus`, then
   `HERALD_SMOKE=1 HERALD_MODE=arc civ/scripts/herald.sh opus`.
   **Acceptance:** probes 6 and 10 pass on the FIRST attempt in both, with no
   refusal or "requires approval" anywhere in either log
   (`grep -c "requires approval" <log>` returns 0).
4. If a refusal still appears, do not widen the profile. Record the exact
   command the model tried in the handoff and leave the bead open.
5. Emit `charter.amended` targeting `fortkit-i0km`, commit path-scoped, close
   the bead on a clean acceptance.

Timing: tomorrow's 05:00 run uses whatever is installed. Uninstalled, a
refused lint is recorded as not-run in the draft and the report; nothing
breaks.
