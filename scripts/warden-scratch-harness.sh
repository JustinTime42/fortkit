#!/bin/bash
# warden-scratch-harness.sh — warden.sh clears a read-only scratch rig before
# removing it (Proofdelve ForgeOs-owhuw, Regent edict 2026-11-09).
# Usage: scripts/warden-scratch-harness.sh [warden.sh]
#
# 2026-11-09 15:21 the fleet's review of Proofdelve ForgeOs-0o16s died at launch in five
# seconds: the Warden's own round-2 inversion rig had chmod a-w directories
# inside her scratch copy, and warden.sh's plain rm -rf could not remove them.
# This extracts the SHIPPED clear_scratch() and drives it against a fixture
# holding exactly that shape. RED ARM, generated from the shipped file: the
# same function without its chmod leaves the tree standing. Against the pre-fix
# file the control passes, the launch-site case FAILS, and the rest is refused
# (exit 3) for want of clear_scratch().
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
wl="${1:-${WARDEN_SH:-$here/../fort/scripts/warden.sh}}"
[ -f "$wl" ] || { echo "HARNESS REFUSES: no warden.sh at $wl" >&2; exit 3; }
work="$(mktemp -d "${TMPDIR:-/tmp}/warden-scratch.XXXXXX")"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass+1)); }
no() { echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }
mkrig() {  # $1 dir: a scratch copy with a .warden-r2 rig whose directories are a-w
  mkdir -p "$1/.warden-r2/rigA/wt/rv/web" "$1/src"
  echo x > "$1/src/a.txt"; echo y > "$1/.warden-r2/rigA/wt/rv/web/f.txt"
  chmod a-w "$1/.warden-r2/rigA/wt/rv/web" "$1/.warden-r2/rigA/wt/rv"
}
run_fn() {  # $1 function text, $2 path -> rc
  bash -c "$1"$'\n''clear_scratch "$1"' _ "$2"
}

d="$work/s1"; mkrig "$d"
if rm -rf "$d" 2>/dev/null; [ -e "$d" ]; then ok "CONTROL: a plain rm -rf cannot remove the fixture (the 0o16s shape reproduces)"
else no "CONTROL" "the fixture was removable by rm -rf alone, so it does not model the defect"; fi
chmod -R u+w "$d" 2>/dev/null; rm -rf "$d"

# The launch site must use it, and refuse by name if the copy still stands.
site="$(awk '/exec 9>"\$lock"/{f=1} f{print} f && /mkdir -p "\$scratch"/{exit}' "$wl")"
# shellcheck disable=SC2016  # grep patterns for the launcher's literal $-spellings
if printf '%s' "$site" | grep -q 'if ! clear_scratch "\$scratch"; then' && printf '%s' "$site" | grep -q 'REFUSED' \
   && ! printf '%s' "$site" | grep -q '^ *rm -rf "\$scratch"$'; then
  ok "the launch site clears through clear_scratch() and refuses by name, with no bare rm -rf before mkdir"
else no "the launch site" "$(printf '%s' "$site" | tail -8)"; fi

# ASKED AFTER THE TWO CASES ABOVE, which run against code present in every
# version of the launcher, so the pre-fix file scores a measured FAIL on the
# launch site before this refusal rather than refusing outright.
fn="$(awk '/^clear_scratch\(\) \{/{f=1} f{print} f && /^}/{exit}' "$wl")"
[ -n "$fn" ] || { echo "HARNESS REFUSES: no clear_scratch() in $wl" >&2; exit 3; }


d="$work/s2"; mkrig "$d"
if run_fn "$fn" "$d" && [ ! -e "$d" ]; then ok "clear_scratch removes a scratch copy holding a read-only rig and returns 0"
else no "clear_scratch on a read-only rig" "rc=$? exists=$([ -e "$d" ] && echo yes || echo no)"; fi

if run_fn "$fn" "$work/never-existed"; then ok "clear_scratch on an absent path returns 0"
else no "clear_scratch on an absent path" "returned nonzero"; fi

mkdir -p "$work/target"; chmod a-w "$work/target"
d="$work/s3"; mkdir -p "$d"; ln -s "$work/target" "$d/link"
run_fn "$fn" "$d" >/dev/null 2>&1
if [ "$(stat -c %a "$work/target")" = 555 ]; then ok "a symlink met inside the copy is not followed: its target keeps its mode"
else no "symlink followed" "target mode is now $(stat -c %a "$work/target")"; fi
chmod u+w "$work/target"

# RED ARM, generated: the same function without the chmod.
red="$(printf '%s\n' "$fn" | grep -v 'chmod -R u+w')"
if [ "$red" = "$fn" ]; then no "RED ARM" "the generator removed nothing from clear_scratch()"
else
  d="$work/s4"; mkrig "$d"
  if ! run_fn "$red" "$d" && [ -e "$d" ]; then ok "RED ARM: without the chmod the rig survives and clear_scratch returns nonzero, so the case above discriminates"
  else no "RED ARM" "the no-chmod variant removed the rig anyway"; fi
fi

echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
