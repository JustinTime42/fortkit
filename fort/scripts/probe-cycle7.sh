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
candidate=""
rm_canary() {
  rm -f "$canary" "$scripts_canary" \
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
# fortkit-6ovg. `: >>` is an O_APPEND open, and an O_APPEND open SUCCEEDED for a
# whole cycle while every real edit failed — that is precisely the false positive
# that hid this defect in three forts (test -w TRUE, open-for-append OK, sed -i
# and git checkout both EROFS on a SIBLING temp path). Keep the append probe as
# the cheap signal, but the load-bearing assertion is the DIRECTORY one below.
probe ok   "scripts/verify.sh writable (re-grant)"   "$root/fort/scripts/verify.sh"
# THE REAL 6ovg PROPERTY: a rewrite-in-place needs to create a sibling and rename
# over the target. `sed -i` with an expression that changes nothing exercises the
# whole path and leaves the file byte-identical; the sha is checked either way,
# so a probe that damaged what it measures would be caught here rather than
# discovered later.
v="$root/fort/scripts/verify.sh"
sha_before="$(sha256sum "$v" | cut -d' ' -f1)"
if bwrap "${mask[@]}" -- sed -i 's/\r$//' "$v" 2>/dev/null \
   && [ "$(sha256sum "$v" | cut -d' ' -f1)" = "$sha_before" ]; then
  echo "PASS (ok) verify.sh rewritable in place (sed -i: sibling + rename)"; pass=$((pass+1))
else
  echo "FAIL verify.sh NOT rewritable in place — 6ovg has regressed"; fail=$((fail+1))
fi
[ "$(sha256sum "$v" | cut -d' ' -f1)" = "$sha_before" ] || { echo "FAIL probe MODIFIED verify.sh"; fail=$((fail+1)); }
# THE DISCLOSED RESIDUAL, PROBED AS AN EXPECTED PASS (Overseer ruling on 6ovg,
# Shape A). Making the directory writable so verify.sh can be edited also lets a
# seat CREATE a new file in a host-executed directory. Nothing there is
# auto-executed and every launcher is named explicitly, so it is a staging area
# for a later mistake rather than a direct path — but a hole nobody probes is the
# thing this fort keeps getting bitten by, so it is asserted, not assumed. If
# this line ever reads FAIL, the mask got STRICTER and 6ovg needs revisiting.
probe ok   "fort/scripts new-file: DISCLOSED 6ovg RESIDUAL" "$scripts_canary"
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
probe deny "charter RO, Warden worktree-candidate posture"          "$root/fort/charter.md"
probe deny "seats RO, Warden worktree-candidate posture"            "$root/fort/seats/mayor.md"
rm_canary

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
  wt_other="$(find "$root-worktrees" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sed -n 2p)"
  [ -n "$wt_other" ] && probe deny "1q9 OTHER worktree unwritable, Forge posture" "$wt_other/.probe-cycle7"
else
  echo "SKIP 1q9 worktree probes: no worktree present under $root-worktrees"
fi

echo "== $root: $pass pass, $fail fail =="
[ $fail -eq 0 ]
