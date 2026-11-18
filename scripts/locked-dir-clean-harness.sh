#!/bin/bash
# Hermetic fixtures for locked_dir_clean() in scripts/verify-impl.sh.
#
# WHY IT EXTRACTS RATHER THAN REIMPLEMENTS (the verdict-record-harness precedent,
# ForgeOs-9mfw.5): it pulls the locked_dirs array and the function VERBATIM out of
# the subject file and sources them, so it scores the code that will run rather
# than a paraphrase that can drift. A harness holding its own copy of the logic
# passes forever while the subject rots.
#
# WHY IT EXISTS AT ALL (ForgeOs-9vx7, ForgeOs-8zb7). locked_dir_clean has guarded
# fort/scripts since ForgeOs-x0ki with NO executed control of any kind, and its own
# comment records what that cost: the first version ran `git ls-files` unguarded, so
# outside a git tree the substitution failed, $stray came back empty, and the step
# reported GREEN with a bare `fatal: not a git repository` in the middle of a passing
# run. The Warden found that by reading. A fixture would have caught it. ARM 5 below
# is that case, pinned.
#
# WHY A FIXTURE AND NOT A LIVE TEST: all three protected directories are kernel
# read-only to every masked seat, which is the entire reason they are guarded, so no
# seat can plant a stray in them to see the gate fire. The red arms are only
# reachable in a temporary repository. That is a property of the subject, not a
# weakness of the test.
#
# Subject via VERIFY_IMPL_SH. Exit 0 all pass, 1 a case failed, 3 refuses (cannot
# find or cannot extract the subject) -- a refusal is never a clean run.
set -uo pipefail

subject="${VERIFY_IMPL_SH:-$(dirname "$0")/verify-impl.sh}"
printf 'subject=%s\n' "$subject"
[ -f "$subject" ] || { echo "HARNESS REFUSES: subject is missing: $subject" >&2; exit 3; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
inc="$work/locked_dir_clean.inc"

# Extract from `locked_dirs=(` through the line before the run_step that calls it.
# Both anchors must be present exactly once or we refuse: a silent partial
# extraction is how a vacuous harness is born (ForgeOs-675g).
python3 - "$subject" "$inc" <<'PY' || { echo "HARNESS REFUSES: could not extract locked_dir_clean from the subject" >&2; exit 3; }
import sys
src = open(sys.argv[1]).read()
open_anchor = "locked_dirs=("
call_anchor = "run_step locked-dir-clean locked_dir_clean"
if src.count(open_anchor) != 1:
    sys.exit("anchor %r appears %d times, wanted 1" % (open_anchor, src.count(open_anchor)))
if src.count(call_anchor) != 1:
    sys.exit("anchor %r appears %d times, wanted 1" % (call_anchor, src.count(call_anchor)))
body = src[src.index(open_anchor):src.index(call_anchor)]
if "locked_dir_clean()" not in body:
    sys.exit("extracted region does not contain the function definition")
open(sys.argv[2], "w").write(body)
PY

pass=0; fail=0
# shellcheck disable=SC1090
source "$inc"
# shellcheck disable=SC2154  # locked_dirs is defined by the sourced extraction above.
declare -p locked_dirs >/dev/null 2>&1 || { echo "HARNESS REFUSES: locked_dirs did not survive extraction" >&2; exit 3; }
printf 'guarding=%s\n' "${locked_dirs[*]}"

# ASSERT ON THE HEADER LINE, NOT ON THE WHOLE OUTPUT, and the reason is a vacuity
# this harness ALREADY HAD (measured 2026-09-19, before it was wired). The first
# version asked whether the output contained the directory name anywhere. It always
# does: `git ls-files -- fort/scripts` prints `fort/scripts/stray.bak`, so the
# directory name arrives in the FILE LISTING whether or not the header names it. A
# mutation that stripped `$d` from the header scored 8 pass / 0 fail. The property
# under test is that the MESSAGE tells a reader which locked directory grew a file,
# so the assertion has to be anchored to the message.
header_names() {  # $1 output, $2 directory -> 0 if a header line names that directory
  printf '%s\n' "$1" | grep -qE "kernel-locked directory ${2//./\\.}( |:|$)"
}

check() {  # $1 label, $2 expected rc, $3 directory the HEADER must name ("" = none)
  local label="$1" want="$2" needle="$3" out rc
  out="$(locked_dir_clean 2>&1)"; rc=$?
  if [ "$rc" != "$want" ]; then
    echo "  FAIL  $label -- rc=$rc wanted $want"; fail=$((fail+1)); return
  fi
  if [ -n "$needle" ] && ! header_names "$out" "$needle"; then
    echo "  FAIL  $label -- no header line names '$needle'"
    printf '%s\n' "$out" | sed 's/^/        /'; fail=$((fail+1)); return
  fi
  echo "  PASS  $label"; pass=$((pass+1))
}

repo="$work/repo"; mkdir -p "$repo"; cd "$repo" || exit 3
git init -q -b main .
git -c user.email=harness@example.test -c user.name=harness commit -q --allow-empty -m base
for d in "${locked_dirs[@]}"; do mkdir -p "$d"; done

check "a clean tree passes" 0 ""

# ONE RED ARM PER GUARDED DIRECTORY. N guards, N falsifying cases: a loop over the
# subject's OWN array, so adding a fourth directory to locked_dirs grows this test
# automatically instead of leaving the new one unpinned.
for d in "${locked_dirs[@]}"; do
  : > "$d/stray.bak"
  check "a stray in $d fails AND names $d" 1 "$d"
  rm -f "$d/stray.bak"
done

# The gate must not have become "any untracked file anywhere".
mkdir -p src; : > src/stray.bak
check "a stray outside the guarded set is ignored" 0 ""
rm -rf src

# Two dirty at once: the caller needs every one named, not the first.
if [ "${#locked_dirs[@]}" -ge 2 ]; then
  a="${locked_dirs[0]}"; b="${locked_dirs[1]}"
  : > "$a/one.bak"; : > "$b/two.bak"
  out="$(locked_dir_clean 2>&1)"; rc=$?
  if [ "$rc" = 1 ] && header_names "$out" "$a" && header_names "$out" "$b"; then
    echo "  PASS  two dirty directories are both named in one run"; pass=$((pass+1))
  else
    echo "  FAIL  two-dirty case rc=$rc (wanted 1, both named)"
    printf '%s\n' "$out" | sed 's/^/        /'; fail=$((fail+1))
  fi
  rm -f "$a/one.bak" "$b/two.bak"
fi

# A guarded directory that does not exist in this tree is not an error. The Warden's
# scratch copy and a bead worktree do not necessarily carry all three.
missing_dir="${locked_dirs[-1]}"
rm -rf "$missing_dir"
check "a guarded directory absent from the tree is not a failure" 0 ""
mkdir -p "$missing_dir"

# ForgeOs-7gs: a probe that cannot run must SAY so rather than pass. This is the
# case that shipped broken and was found by reading instead of by a gate.
outside="$work/not-a-repo"; mkdir -p "$outside/${locked_dirs[0]}"; cd "$outside" || exit 3
out="$(locked_dir_clean 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [[ "$out" == *"NOT CHECKED"* ]] && [[ "$out" == *"${locked_dirs[0]}"* ]]; then
  echo "  PASS  outside a git tree it returns 0 and says NOT CHECKED, naming the directories"
  pass=$((pass+1))
else
  echo "  FAIL  non-git arm rc=$rc (wanted 0 with NOT CHECKED naming the dirs)"
  printf '%s\n' "$out" | sed 's/^/        /'; fail=$((fail+1))
fi

echo
echo "RESULT $pass pass / $fail fail"
[ "$fail" = 0 ]
