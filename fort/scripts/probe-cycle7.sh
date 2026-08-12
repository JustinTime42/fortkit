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
canary="$root/fort/memory/facts/.probe-cycle7-canary"
rm_canary() { rm -f "$canary"; }
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
probe ok   "scripts/verify.sh writable (re-grant)"   "$root/fort/scripts/verify.sh"
probe deny ".git/config RO (fortkit-cqc)"            "$root/.git/config"
probe deny ".git/hooks new-file RO (fortkit-cqc)"    "$root/.git/hooks/cycle7-canary"
probe deny ".claude settings RO (unchanged)"         "$root/.claude/settings.json"
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
rmdir "$candidate" 2>/dev/null || true

echo "== $root: $pass pass, $fail fail =="
[ $fail -eq 0 ]
