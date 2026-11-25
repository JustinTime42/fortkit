#!/bin/bash
# posture-rule-harness.sh: one rule decides which sandbox posture is in effect
# (fortkit-awlc; the Warden's finding 1 on 5e85d93+60b6a5e and finding 3 on the
# fold 6527455).
# Usage: scripts/posture-rule-harness.sh [fort/scripts directory]
#
# WHY. Until 2026-11-24 two rules decided the posture. The mask library let
# FORT_SANDBOX override the word in fort/scripts/sandbox-posture; the launchers
# turned their secrets-only grants on when the file OR the variable said
# secrets-only. FORT_SANDBOX=full over a secrets-only file therefore built full
# masks while the Warden kept bypassPermissions and Codex kept its sandbox off.
# The lib's fort_posture() is now the one rule. This harness pins two things:
#   1. the matrix: what fort_posture() answers for each file and variable state;
#   2. that nothing under fort/scripts except the lib reads the posture file or
#      the variable for itself, so a later launcher edit cannot bring a second
#      rule back without this going red.
# No mask is built and nothing is launched, so it runs anywhere.
#
# RED AND GREEN. Against 60b6a5e's fort/scripts (before the one rule) part 1
# refuses, because the function does not exist, and part 2 finds the launchers'
# own posture lines. Against the tree with the rule: all pass.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dir="${1:-$here/../fort/scripts}"
lib="$dir/lib/seat-sandbox.sh"
[ -f "$lib" ] || { echo "HARNESS REFUSES: no mask library at $lib" >&2; exit 3; }
fx="$(mktemp -d)" || exit 3
trap 'rm -rf "$fx"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1 -- $2"; }

echo "=== posture-rule-harness: $dir ==="
if ! grep -q '^fort_posture() {' "$lib"; then
  echo "HARNESS REFUSES: $lib defines no fort_posture(); there is no one rule to measure" >&2
  # Part 2 still runs below: it is what shows a tree that decides the posture in several places.
  no_fn=1
else
  no_fn=0
fi

if [ "$no_fn" = 0 ]; then
  for f in secrets-only full absent; do
    mkdir -p "$fx/$f/fort/scripts"
    [ "$f" = absent ] || printf '%s\n' "$f" > "$fx/$f/fort/scripts/sandbox-posture"
  done
  ask() { # <root> <variable state: unset | a value, possibly empty>
    # shellcheck disable=SC1090,SC2034  # the lib is a path in a variable; fort_posture reads FORT_SANDBOX
    if [ "$2" = unset ]; then ( unset FORT_SANDBOX; source "$lib" >/dev/null 2>&1; fort_posture "$1" )
    else ( FORT_SANDBOX="$2"; source "$lib" >/dev/null 2>&1; fort_posture "$1" ); fi
  }
  expect() { # <file state> <variable state> <expected>
    local got; got="$(ask "$fx/$1" "$2")"
    if [ "$got" = "$3" ]; then ok "file $1, variable ${2:-empty}: $got"
    else bad "file $1, variable ${2:-empty}" "expected $3, got ${got:-nothing}"; fi
  }
  expect secrets-only unset        secrets-only
  expect secrets-only ""           secrets-only
  expect secrets-only full         full
  expect secrets-only secrets-only secrets-only
  expect full         unset        full
  expect full         secrets-only secrets-only
  expect absent       unset        full
  expect absent       secrets-only secrets-only
  # An unknown word passes through unjudged: build_mask is what refuses it.
  expect secrets-only bogus        bogus
fi

# Part 2: no second rule. Comment lines are not code; the lib is the one place
# allowed to read either source.
# No line is exempted for mentioning fort_posture (the Warden, finding 2 on
# 6096a97): a line that calls it AND tests FORT_SANDBOX itself is the second
# rule this part exists to catch.
offenders="$(grep -rnE 'sandbox-posture|FORT_SANDBOX' "$dir" --include='*.sh' 2>/dev/null \
  | grep -v "^$dir/lib/seat-sandbox.sh:" \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
if [ -z "$offenders" ]; then
  ok "nothing under $(basename "$dir") but the lib reads the posture file or FORT_SANDBOX for itself"
else
  bad "a second posture rule" "these lines decide the posture without fort_posture(): $(printf '%s' "$offenders" | cut -c1-160 | tr '\n' ';')"
fi

echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ] && [ "$no_fn" = 0 ]
