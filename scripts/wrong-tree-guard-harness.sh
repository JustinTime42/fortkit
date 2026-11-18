#!/bin/bash
# wrong-tree-guard-harness.sh -- re-runs the five postures of the verifier's
# wrong-tree refusal (Proofdelve ForgeOs-afdr) that were measured by hand on 2026-08-28
# and never re-run since (Proofdelve ForgeOs-t5vq, the Warden's finding 3 on afdr).
#
# THE TECHNIQUE is the original measurement's: invoke the verifier with an
# invalid argument, so a run that passes the guard dies at argument parsing
# with exit 2, AFTER the guard and BEFORE any step or event. The guard itself
# exits 78. So: 78 means refused, 2 means allowed through, anything else means
# the prologue changed shape and this harness is stale (which is a finding).
#
# Hermetic: two throwaway git trees A and B plus a linked worktree of A, the
# real verify-impl.sh copied into A/scripts/, no fort state read or written.
# VERIFY_IMPL_SRC points the harness at a variant (the RED control: a copy with
# the `exit 78` removed must FAIL case 1).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${VERIFY_IMPL_SRC:-$here/verify-impl.sh}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1 (exit $3)"; pass=$((pass+1)); else echo "  FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi; }
mkrepo() { mkdir -p "$1"; git -C "$1" init -q -b main; git -C "$1" -c user.name=h -c user.email=h@h commit -q --allow-empty -m base; }
A="$tmp/A"; B="$tmp/B"; mkrepo "$A"; mkrepo "$B"
mkdir -p "$A/scripts" "$A/fort/scripts" "$A/sub"
cp -f "$src" "$A/scripts/verify-impl.sh"; chmod +x "$A/scripts/verify-impl.sh"
git -C "$A" -c user.name=h -c user.email=h@h add -A >/dev/null; git -C "$A" -c user.name=h -c user.email=h@h commit -q -m verifier
git -C "$A" worktree add -q "$tmp/A-wt" -b side >/dev/null 2>&1
V="$A/scripts/verify-impl.sh"
run() { ( cd "$1" && "$V" --this-flag-does-not-exist >"$tmp/out" 2>&1; echo $?); }   # exit 2 = passed the guard

check "1 standing in B, scoring A -> REFUSE 78"                 78 "$(run "$B")"
if grep -q 'WRONG TREE' "$tmp/out"; then echo "  PASS  1b names the refusal"; pass=$((pass+1)); else echo "  FAIL  1b names the refusal"; fail=$((fail+1)); fi
check "2 same, VERIFY_ALLOW_TREE_MISMATCH=1 -> warns, proceeds (2)" 2 "$( ( cd "$B" && VERIFY_ALLOW_TREE_MISMATCH=1 "$V" --this-flag-does-not-exist >"$tmp/out" 2>&1; echo $?) )"
if grep -q 'cross-tree run permitted' "$tmp/out"; then echo "  PASS  2b the override is announced"; pass=$((pass+1)); else echo "  FAIL  2b the override is announced"; fail=$((fail+1)); fi
check "3 standing in A itself -> proceeds (2)"                   2 "$(run "$A")"
check "4 standing in a subdirectory of A -> proceeds (2)"       2 "$(run "$A/sub")"
check "5 outside any git tree -> proceeds (2)"                  2 "$(run "$tmp")"
check "6 standing in a linked worktree of A -> REFUSE 78 (a worktree is a different tree)" 78 "$(run "$tmp/A-wt")"

echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
