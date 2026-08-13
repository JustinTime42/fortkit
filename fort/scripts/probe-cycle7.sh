#!/bin/bash
# Cycle-7 mask probe (fortkit-i4y / fortkit-cqc). Shell-driven, host-side.
# Tests write-openability with ': >>' (O_WRONLY|O_APPEND, zero bytes written) so
# nothing measured is modified. Expected outcomes are asserted per path.
set -u
root="$1"
mask=()
# shellcheck disable=SC1091
source "$root/fort/scripts/lib/seat-sandbox.sh"
require_bwrap || exit 78
build_mask claude "$root"
mask_env claude

pass=0; fail=0
# Positive control for "writable" (fortkit-52vf.1). It used to append to the
# fort's top-level memory file, which the fortkit-88u migration turned into a
# pointer stub: the control kept reporting PASS while asserting nothing
# load-bearing. It now tests NEW-FILE CREATION under the facts ledger, which is
# (a) the surface a seat must actually be able to write after the migration and
# (b) a test of DIRECTORY writability, the property fortkit-6ovg proved decides
# whether a file can be changed at all. The canary is removed on every exit
# path: a probe must never seed the record it measures (civ memory 2026-08-06).
# The retired path is not named anywhere in this file on purpose — doing so
# trips the retired-reference guard (fortkit-xgul.7.1).
#
# EVERY CANARY THIS SCRIPT CAN CREATE IS REMOVED BY THE TRAP, not by a line
# after the probe that uses it (fortkit-faka finding 8, Warden Ilva Trueglass):
# an interrupted or failing run used to leave residue in fort/scripts/ and in
# ~/.claude/teams, and stray artifacts in this fort have had to be cleaned up by
# hand before (Warden ow7 finding 7, the bare-UUID 'mkdir' file). The list
# includes the canaries of probes EXPECTED TO BE DENIED: if such a probe ever
# fails, it has created the very file nobody would then be cleaning up.
canary="$root/fort/memory/facts/.probe-cycle7-canary"
scripts_canary="$root/fort/scripts/.probe-cycle7-newfile"
# fortkit-52vf.10 (E8): ~/.codex is now a WRITABLE DIRECTORY BIND for both seat
# types, so proving it is writable means creating something there. The canary is
# a name nothing else can collide with, and it joins the trap list rather than a
# line after the probe — a probe must never seed the record it measures, and an
# interrupted run must not leave residue in the Codex runtime's own directory.
codex_canary="$HOME/.codex/.probe-cycle7-canary"
candidate=""
rm_canary() {
  rm -f "$canary" "$scripts_canary" "$codex_canary" \
        "$HOME/.claude/teams/.probe-cycle7-canary" \
        "$HOME/.claude/skills/.probe-cycle7-canary" \
        "$HOME/.claude/commands/.probe-cycle7-canary" \
        "$HOME/.claude/plugins/.probe-cycle7-canary" \
        "$root/.git/hooks/cycle7-canary"
  [ -n "$candidate" ] && rmdir "$candidate" 2>/dev/null
  return 0
}
trap rm_canary EXIT
probe() { # probe <expect:ok|deny> <desc> <path-to-append>
  local expect="$1" desc="$2" target="$3" rc
  bwrap "${mask[@]}" -- sh -c ": >> '$target'" 2>/dev/null; rc=$?
  if { [ "$expect" = ok ] && [ $rc -eq 0 ]; } || { [ "$expect" = deny ] && [ $rc -ne 0 ]; }; then
    echo "PASS ($expect) $desc"; pass=$((pass+1))
  else
    echo "FAIL (wanted $expect, rc=$rc) $desc"; fail=$((fail+1))
  fi
}

echo "== $root =="
probe ok   "charter.md writable (prose gate)"        "$root/fort/charter.md"
probe ok   "seats/mayor.md writable (prose gate)"    "$root/fort/seats/mayor.md"
probe ok   "memory/facts/ new-file creation (control)" "$canary"
rm_canary
probe deny "profiles RO"                             "$root/fort/profiles/warden-settings.json"
probe deny "scripts/emit.sh RO (host-executed)"      "$root/fort/scripts/emit.sh"
probe deny "scripts/lib/seat-sandbox.sh RO"          "$root/fort/scripts/lib/seat-sandbox.sh"
# fortkit-6ovg, SHAPE B (Overseer ruling 2026-08-12). fort/scripts/verify.sh is
# now a read-only SHIM and the editable verifier is scripts/verify-impl.sh, so
# both expectations here inverted: the shim must be DENIED and the
# implementation must be writable. `: >>` is an O_APPEND open, and an O_APPEND
# open SUCCEEDED for a whole cycle while every real edit failed — that is
# precisely the false positive that hid the original defect in three forts
# (test -w TRUE, open-for-append OK, sed -i and git checkout both EROFS on a
# SIBLING temp path). Keep the append probe as the cheap signal; the
# load-bearing assertion is the sed -i one below.
probe deny "scripts/verify.sh SHIM RO (Shape B)"     "$root/fort/scripts/verify.sh"
probe ok   "scripts/verify-impl.sh writable (Mayor)" "$root/scripts/verify-impl.sh"
# THE REAL 6ovg PROPERTY: a rewrite-in-place needs to create a sibling and rename
# over the target. `sed -i` with an expression that changes nothing exercises the
# whole path and leaves the file byte-identical; the sha is checked either way,
# so a probe that damaged what it measures would be caught here rather than
# discovered later.
v="$root/scripts/verify-impl.sh"
sha_before="$(sha256sum "$v" | cut -d' ' -f1)"
if bwrap "${mask[@]}" -- sed -i 's/\r$//' "$v" 2>/dev/null \
   && [ "$(sha256sum "$v" | cut -d' ' -f1)" = "$sha_before" ]; then
  echo "PASS (ok) verify-impl.sh rewritable in place (sed -i: sibling + rename)"; pass=$((pass+1))
else
  echo "FAIL verify-impl.sh NOT rewritable in place — 6ovg has regressed"; fail=$((fail+1))
fi
[ "$(sha256sum "$v" | cut -d' ' -f1)" = "$sha_before" ] || { echo "FAIL probe MODIFIED verify-impl.sh"; fail=$((fail+1)); }
# INVERTED BY SHAPE B, and it used to be the opposite (Overseer ruling on 6ovg,
# Shape A, 2026-08-11): making the directory writable so verify.sh could be
# edited also let a seat CREATE a new file in a host-executed directory, and
# that hole was probed here as an EXPECTED PASS and carried in the charter as an
# accepted residual. Shape B removed the hole rather than disclosing it, so this
# is now a deny — and a FAIL on this line means the hole is back.
#
# THE OTHER HALF OF THE SHAPE B PROPERTY IS DELIBERATELY NOT PROBED HERE: that
# fort/scripts, being a whole-directory bind, is itself a mount point and refuses
# rename. Establishing that requires actually attempting `mv` on the directory,
# and this script runs against LIVE FORTS. The naive version of that probe left
# fort/scripts renamed for a whole harness run and made four later assertions
# pass vacuously (fortkit-x9ou). It is asserted instead in
# scripts/mask-harness.sh (A4b), against a synthetic fixture, with a restore
# that aborts the run if it fails.
probe deny "fort/scripts new-file DENIED (Shape B, 6ovg)" "$scripts_canary"
rm_canary
probe deny ".git/config RO (fortkit-cqc)"            "$root/.git/config"
probe deny ".git/hooks new-file RO (fortkit-cqc)"    "$root/.git/hooks/cycle7-canary"
probe deny ".claude settings RO (unchanged)"         "$root/.claude/settings.json"
# fortkit-5sk: the GLOBAL instruction surface. Session-executed context that runs
# at the NEXT launch, including the unmasked Regent's, so a masked seat that
# writes it controls code running outside the mask. ~/.claude/teams is
# deliberately NOT here: it is harness session state, written at every launch.
probe deny "global .claude/civilization.json RO (5sk)"     "$HOME/.claude/civilization.json"
probe deny "global .claude/skills RO (5sk)"                "$HOME/.claude/skills/.probe-cycle7-canary"
probe deny "global .claude/commands RO (5sk)"              "$HOME/.claude/commands/.probe-cycle7-canary"
probe deny "global .claude/plugins RO (5sk)"               "$HOME/.claude/plugins/.probe-cycle7-canary"
probe ok   "global .claude/teams still writable (5sk: deliberate)" "$HOME/.claude/teams/.probe-cycle7-canary"
rm_canary
if [ -d "$root/civ" ]; then
  probe deny "bin/regent RO (capital host surface)"   "$root/bin/regent"
  probe deny "civ/scripts/emit.sh RO"                 "$root/civ/scripts/emit.sh"
  probe deny "civ/profiles RO"                        "$root/civ/profiles/herald-settings.json"
  probe ok   "civ/covenant.md writable (prose layer)" "$root/civ/covenant.md"
fi
# git still functions inside the mask (index/refs writable):
if bwrap "${mask[@]}" -- git -C "$root" status --porcelain >/dev/null 2>&1; then
  echo "PASS git status works inside mask"; pass=$((pass+1))
else
  echo "FAIL git status broken inside mask"; fail=$((fail+1))
fi

# Warden postures (r2/r3, Warden findings suti-1 / 8c9-4 / suti-r2-1 and -4):
# a mask whose behaviour depends on the launcher's arguments must enumerate
# the LAUNCHES, not the seats. warden.sh now passes $root as extra_ro
# unconditionally plus the candidate dir, so both its postures are probed:
# main-checkout review (src == root) and worktree-candidate review (src is a
# separate tree). In both, the Warden gets no writable hole in $root.
mask=()
build_mask claude "$root" "$root" "$root"
mask_env claude
probe deny "verify.sh re-masked, Warden main-checkout posture" "$root/fort/scripts/verify.sh"
probe deny "verify-impl.sh RO, Warden main-checkout posture"   "$root/scripts/verify-impl.sh"
probe deny "charter RO, Warden main-checkout posture"          "$root/fort/charter.md"
if bwrap "${mask[@]}" -- head -c 1 "$root/fort/scripts/verify.sh" >/dev/null 2>&1; then
  echo "PASS warden posture can still read (positive control)"; pass=$((pass+1))
else
  echo "FAIL warden posture cannot read verify.sh"; fail=$((fail+1))
fi
candidate="${TMPDIR:-/tmp}/probe-cycle7-candidate-$$"
mkdir -p "$candidate"
mask=()
build_mask claude "$root" "$root" "$candidate"
mask_env claude
probe deny "verify.sh re-masked, Warden worktree-candidate posture" "$root/fort/scripts/verify.sh"
probe deny "verify-impl.sh RO, Warden worktree-candidate posture"   "$root/scripts/verify-impl.sh"
probe deny "charter RO, Warden worktree-candidate posture"          "$root/fort/charter.md"
probe deny "seats RO, Warden worktree-candidate posture"            "$root/fort/seats/mayor.md"
rm_canary

# ---------------------------------------------------------------------------
# THE FORGE'S POSTURE AT $root, UNCONDITIONALLY (fortkit-n3bk finding 9, Warden
# Ilva Trueglass on the E2b review; added by the E8 sitting, fortkit-52vf.10,
# 2026-08-13).
#
# Until now the codex posture was built ONLY inside the worktree block below, and
# two things went unasserted per fort as a result. First, $root/scripts/verify-impl.sh
# was never probed under it — and that carve-out is the load-bearing half of
# Shape B's safety, the one line stopping the unattended seat from editing the
# verifier that judges its own work. Second, and worse because nothing said so:
# IN A FORT WITH NO WORKTREE THE CODEX POSTURE WAS NEVER BUILT AT ALL, so the
# standing probe measured nothing whatever about the Forge's mask and still
# printed a clean pass line. The unmasked harness asserts these (C4c/C4e), but
# the harness needs an unmasked shell and THIS is what runs per fort.
mask=()
build_mask codex "$root"
mask_env codex
probe deny "codex: \$root scripts/verify-impl.sh RO (Shape B)" "$root/scripts/verify-impl.sh"
probe deny "codex: \$root fort/scripts/verify.sh RO"          "$root/fort/scripts/verify.sh"
probe deny "codex: \$root fort/scripts/emit.sh RO"            "$root/fort/scripts/emit.sh"
# The cycle-7 prose gate is for ATTENDED seats only: an unattended seat cannot
# ask first, so the Forge keeps the mechanical lock the Mayor and Warden lost.
# These two are the exact inverse of the first two probes in this file, which is
# why they are worth asserting rather than assuming.
probe deny "codex: charter.md RO (unattended keeps the lock)"  "$root/fort/charter.md"
probe deny "codex: seats/mayor.md RO (unattended keeps the lock)" "$root/fort/seats/mayor.md"
# fortkit-52vf.10 (E8): the unified ~/.codex grant, one mechanism in all three
# forts. config.toml must stay READ-ONLY — it is the disarm-the-next-launch
# vector (ForgeOs-21f.5) — while the DIRECTORY itself must be WRITABLE, because
# codex rotates its token by RENAME and a pinned auth.json inode revoked the
# refresh token and took both seat lanes down in Farlantern on 2026-08-05
# (longburn-1p9). Proofdelve's Forge got NEITHER until this edict: its lib branch
# had never executed, so the port would have met EROFS on first token refresh.
probe deny "codex: ~/.codex/config.toml RO"                    "$HOME/.codex/config.toml"
probe ok   "codex: ~/.codex writable (rotation, longburn-1p9)" "$codex_canary"
rm_canary
# The dispatch lane is the CLAUDE posture — the Mayor launches the Forge and the
# child codex inherits her mount namespace — so the same two properties are
# asserted there. This is where 1p9 actually broke.
mask=()
build_mask claude "$root"
mask_env claude
probe deny "claude: ~/.codex/config.toml RO (dispatch lane)"   "$HOME/.codex/config.toml"
probe ok   "claude: ~/.codex writable (dispatch lane)"         "$codex_canary"
rm_canary
# ---------------------------------------------------------------------------

# fortkit-1q9. The Warden's real launch now passes $root-worktrees as extra_ro:
# until E2 the seat that is read-only BY CONSTRUCTION could write the enforcement
# layer of every worktree one directory sideways. Probed against a live worktree
# if the fort has one, because that is the posture the defect lived in.
wt_probe="$(find "$root-worktrees" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
if [ -n "$wt_probe" ] && [ -e "$wt_probe/fort/scripts/mayor.sh" ]; then
  mask=()
  build_mask claude "$root" "$root" "$root-worktrees" "$root"
  mask_env claude
  probe deny "1q9 worktree fort/scripts RO, Warden posture"  "$wt_probe/fort/scripts/mayor.sh"
  probe deny "1q9 worktree new-file denied, Warden posture"  "$wt_probe/fort/scripts/.probe-cycle7"
  [ -e "$wt_probe/bin/regent" ] && probe deny "1q9 worktree bin/ RO, Warden posture" "$wt_probe/bin/regent"
  # The Forge's posture is the other half: its declared tree is writable, and
  # every OTHER worktree is not.
  mask=()
  build_mask codex "$root" --rw-tree "$wt_probe"
  mask_env codex
  probe deny "1q9 declared worktree fort/scripts RO, Forge posture" "$wt_probe/fort/scripts/mayor.sh"
  # Shape B's wrinkle: the relocated verifier rides the $root grant, so the
  # unattended seat needs an explicit carve-out or it can edit its own judge.
  [ -e "$wt_probe/scripts/verify-impl.sh" ] && probe deny "verify-impl.sh RO in the declared worktree, Forge posture" "$wt_probe/scripts/verify-impl.sh"
  wt_other="$(find "$root-worktrees" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed -n 2p)"
  [ -n "$wt_other" ] && probe deny "1q9 OTHER worktree unwritable, Forge posture" "$wt_other/.probe-cycle7"
else
  echo "SKIP 1q9 worktree probes: no worktree present under $root-worktrees"
fi

echo "== $root: $pass pass, $fail fail =="
[ $fail -eq 0 ]
