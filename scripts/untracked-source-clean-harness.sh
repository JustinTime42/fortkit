#!/bin/bash
# Hermetic fixtures for untracked_source_clean() in scripts/verify-impl.sh (Proofdelve ForgeOs-ju6r8).
#
# It extracts the path list and the function VERBATIM from the subject and sources
# them, the locked-dir-clean-harness pattern, so it scores the code that will run.
#
# WHY IT EXISTS: on 2026-10-21 a host verify.pass certified Proofdelve ForgeOs-413u8.40's tip
# although the commit did not build. Three new source files sat untracked in the
# worktree; dirtyAtStart counts tracked files only, so nothing said the run scored
# more than the commit. ARM 2 is that case: a committed file referring to a sibling
# that exists only untracked.
#
# Subject via VERIFY_IMPL_SH. Exit 0 all pass, 1 a case failed, 3 refuses (cannot
# find or cannot extract the subject); a refusal is never a clean run.
set -uo pipefail

subject="${VERIFY_IMPL_SH:-$(dirname "$0")/verify-impl.sh}"
printf 'subject=%s\n' "$subject"
[ -f "$subject" ] || { echo "HARNESS REFUSES: subject is missing: $subject" >&2; exit 3; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
inc="$work/untracked_source_clean.inc"

python3 - "$subject" "$inc" <<'PY' || { echo "HARNESS REFUSES: could not extract untracked_source_clean from the subject" >&2; exit 3; }
import sys
src = open(sys.argv[1]).read()
open_anchor = "untracked_source_paths=("
call_anchor = "run_step untracked-source-clean untracked_source_clean"
for a in (open_anchor, call_anchor):
    if src.count(a) != 1:
        sys.exit("anchor %r appears %d times, wanted 1" % (a, src.count(a)))
body = src[src.index(open_anchor):src.index(call_anchor)]
if "untracked_source_clean()" not in body:
    sys.exit("extracted region does not contain the function definition")
open(sys.argv[2], "w").write(body)
PY

# shellcheck disable=SC1090
source "$inc"
# shellcheck disable=SC2154  # untracked_source_paths is defined by the sourced extraction above.
declare -p untracked_source_paths >/dev/null 2>&1 || { echo "HARNESS REFUSES: untracked_source_paths did not survive extraction" >&2; exit 3; }
printf 'guarding=%s\n' "${untracked_source_paths[*]}"

pass=0; fail=0
check() {  # $1 name, $2 expected exit, $3 dir, $4 expected stderr substring ("" = none required)
  local name="$1" want="$2" dir="$3" needle="$4" got out
  out="$(cd "$dir" && untracked_source_clean 2>&1)"; got=$?
  if [ "$got" = "$want" ] && { [ -z "$needle" ] || grep -qF -- "$needle" <<< "$out"; }; then
    pass=$((pass + 1)); printf 'PASS %s\n' "$name"
  else
    fail=$((fail + 1)); printf 'FAIL %s: exit %s (wanted %s); output: %s\n' "$name" "$got" "$want" "$out"
  fi
}

fixture() {  # $1 dir -> a git repo with one committed source file and an ignore rule
  mkdir -p "$1/src/App" "$1/test" "$1/docs"
  git -C "$1" init -q
  git -C "$1" config user.email h@example.invalid; git -C "$1" config user.name harness
  printf 'bin/\nobj/\n' > "$1/.gitignore"
  printf 'class Uses { Missing m; }\n' > "$1/src/App/Uses.cs"
  git -C "$1" add -A; git -C "$1" commit -q -m base
}

f1="$work/clean"; fixture "$f1"
check "1 clean tree passes" 0 "$f1" ""

f2="$work/src-untracked"; fixture "$f2"
printf 'class Missing {}\n' > "$f2/src/App/Missing.cs"
check "2 committed reference to an untracked src file refuses and names it" 1 "$f2" "src/App/Missing.cs"

f3="$work/tests-untracked"; fixture "$f3"
printf 'x\n' > "$f3/test/new.test.ts"
check "3 untracked test file refuses" 1 "$f3" "test/new.test.ts"

f5="$work/ignored"; fixture "$f5"
mkdir -p "$f5/src/App/bin"; printf 'x\n' > "$f5/src/App/bin/out.dll"
check "5 an ignored build output under src passes" 0 "$f5" ""

f6="$work/outside"; fixture "$f6"
printf 'x\n' > "$f6/docs/notes.md"; printf 'x\n' > "$f6/scratch.txt"
check "6 untracked files outside src and test pass" 0 "$f6" ""

f7="$work/not-git"; mkdir -p "$f7/src"; printf 'x\n' > "$f7/src/a.cs"
check "7 outside a git tree says NOT CHECKED and does not claim green silently" 0 "$f7" "NOT CHECKED"

printf 'RESULT: %d pass / %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
