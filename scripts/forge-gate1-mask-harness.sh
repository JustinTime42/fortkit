#!/bin/bash
# forge-gate1-mask-harness.sh: the Forge cannot write the ROOT checkout's gate-1
# surface (templates/, schema/, skills/, civ/), and can write its own worktree's
# (Regent sitting 2026-11-19, fortkit-ttpk).
# Usage: scripts/forge-gate1-mask-harness.sh [forge.sh]
#
# Evaluates the SHIPPED forge.sh's own mask lines (from the keep_token line to
# seat_build_env) against a fixture fort under ~/dev, and reads permissions from
# inside bwrap. Nothing is written from inside the mask. HOST ONLY: it refuses
# inside a seat mask, so it is not a verifier step (the verifier runs in masks).
#
# CONTROLS. Vacuity: the worktree's own templates/ IS writable, so a mask that
# refuses everything cannot pass. Red arm: forge.sh with the gate-1 block removed
# must show the root's templates/ writable under secrets-only.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
forge="${1:-$here/../fort/scripts/forge.sh}"
lib="$(dirname "$forge")/lib/seat-sandbox.sh"
[ -f "$forge" ] && [ -f "$lib" ] || { echo "HARNESS REFUSES: forge.sh or its lib missing ($forge, $lib)" >&2; exit 3; }
command -v bwrap >/dev/null || { echo "HARNESS REFUSES: no bwrap on this host" >&2; exit 3; }
[ -z "${FORT_MASKED:-}" ] || { echo "HARNESS REFUSES: run on the host, not inside a seat mask (FORT_MASKED=$FORT_MASKED)" >&2; exit 3; }

fx="$(mktemp -d "$HOME/dev/.forge-gate1.XXXXXX")" || { echo "HARNESS REFUSES: cannot make a fixture under ~/dev" >&2; exit 3; }
trap 'chmod -R u+w "$fx" 2>/dev/null; rm -rf "$fx"' EXIT
root="$fx/repo"; wt="$root-worktrees/b1"
for t in "$root" "$wt"; do
  mkdir -p "$t/fort/scripts/lib" "$t/templates" "$t/schema" "$t/skills" "$t/civ" "$t/src" "$t/.claude" "$t/fort/profiles"
  cp "$lib" "$t/fort/scripts/lib/seat-sandbox.sh"
done
git -C "$root" init -q
printf '{"civilization":"fixture","forts":[{"project":"repo","repo":"%s","fort_name":"Fixturefort"}]}\n' "$root" > "$fx/registry.json"
cat > "$fx/in.sh" <<'IN'
r="$1"; w="$2"
c() { [ -w "$1" ] && echo yes || echo no; }
for d in templates schema skills civ; do echo "root_$d=$(c "$r/$d")"; echo "wt_$d=$(c "$w/$d")"; done
echo "root_src=$(c "$r/src")"
IN

# The launcher's own mask lines, cut from the subject. Refuse on an empty cut.
block_of() { sed -n '/^keep_token=/,/^seat_build_env/p' "$1"; }
probe() {  # $1 forge.sh, $2 posture -> key=value lines
  local b; b="$(block_of "$1")"
  [ -n "$b" ] || { echo "cut=EMPTY"; return; }
  # shellcheck disable=SC2030,SC2031  # each probe sets its own environment in its own subshell
  ( export FORT_SANDBOX="$2" FORT_REGISTRY="$fx/registry.json"
    mask=()
    # shellcheck disable=SC1090  # the lib beside the subject, by design
    source "$lib" 2>/dev/null || { echo "mask=FAILED"; exit 0; }
    # shellcheck disable=SC2034  # root, wt and bead are read by the evaluated block
    bead=fixture-b1
    eval "$b" >/dev/null 2>&1 || { echo "mask=FAILED"; exit 0; }
    bwrap "${mask[@]}" -- /bin/bash "$fx/in.sh" "$root" "$wt" 2>/dev/null )
}
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1 ($2)"; pass=$((pass+1)); else echo "FAIL  $1 (got '$2', want '$3')"; fail=$((fail+1)); fi; }
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

for posture in full secrets-only; do
  out="$(probe "$forge" "$posture")"
  case "$out" in *cut=EMPTY*|*mask=FAILED*) echo "FAIL  [$posture] the mask block could not be cut or built ($out)"; fail=$((fail+1)); continue ;; esac
  for d in templates schema skills civ; do
    check "[$posture] the ROOT checkout's $d/ is read-only to the Forge" "$(val "$out" "root_$d")" no
  done
  check "[$posture] VACUITY: the Forge's own worktree templates/ IS writable" "$(val "$out" wt_templates)" yes
done

red="$fx/forge-red.sh"
sed '/^# MANYHALLS: THE GATE-1 SURFACE/,/^# END MANYHALLS GATE-1 BIND/d' "$forge" > "$red"
if cmp -s "$red" "$forge"; then echo "NOT RUN  red arm: the gate-1 block was not found in $forge"; fail=$((fail+1))
else
  out="$(probe "$red" secrets-only)"
  check "RED ARM (gate-1 block removed, secrets-only): the root's templates/ becomes writable" "$(val "$out" root_templates)" yes
fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
