#!/bin/bash
# nightly-verify-harness.sh -- Proofdelve ForgeOs-s1reg criterion 3: the nightly full verify
# runs on main with Docker required, and a RED halts the fleet.
#
# Runs the SHIPPED fort/scripts/nightly-verify.sh, copied into a throwaway fort
# with a stub verifier and a stub emitter; FLEET_STATE points at scratch. No
# real fort state is read or written.
set -uo pipefail
# THE CALLER'S VERIFY ENVIRONMENT IS NOT THIS HARNESS'S (found by the sitting's
# own full verify at b878e70d): the post-merge and nightly runs set
# VERIFY_REQUIRE_DOCKER=1 and a fleet host verify sets VERIFY_TIER and
# VERIFY_RESULT_FILE, and verify-impl.sh runs this file under them. Every case
# below sets what it asserts about, so nothing is inherited.
unset VERIFY_REQUIRE_DOCKER VERIFY_TIER VERIFY_RESULT_FILE FLEET_VERIFY_TIERS FLEET_VERIFY_REUSE
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
subject="${NIGHTLY_SH:-$here/../fort/scripts/nightly-verify.sh}"
[ -s "$subject" ] || { echo "HARNESS REFUSES: no subject at $subject" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1 -- $2"; fail=$((fail + 1)); }

mkfix() { # $1 name, $2 stub verifier exit code, [$3 a line the stub prints on stderr] -> sets r st
  r="$work/$1"; st="$work/$1-state"
  mkdir -p "$r/fort/scripts" "$st"
  git -C "$work" init -q -b main "$1"; git -C "$r" config user.email h@h; git -C "$r" config user.name H
  cp "$subject" "$r/fort/scripts/nightly-verify.sh"; chmod +x "$r/fort/scripts/nightly-verify.sh"
  cat > "$r/fort/scripts/verify.sh" <<V
#!/bin/bash
printf '%s|%s|%s|%s\n' "\$PWD" "\$(git rev-parse HEAD)" "\${VERIFY_REQUIRE_DOCKER:-unset}" "\${VERIFY_TIER:-unset}" >> "$r/verify-calls"
grep -q POISON subject.txt && { echo RED; exit 1; }
$( [ -n "${3:-}" ] && printf 'printf "%%s\\n" %q >&2' "$3" )
exit $2
V
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/emitted"\n' "$r" > "$r/fort/scripts/emit.sh"
  chmod +x "$r/fort/scripts/verify.sh" "$r/fort/scripts/emit.sh"
  echo ok > "$r/subject.txt"
  git -C "$r" add -A; git -C "$r" commit -qm base
}
runit() { ( env -u FORT_MASKED FLEET_STATE="$st" "$r/fort/scripts/nightly-verify.sh" ) > "$work/out" 2>&1; }
trees() { git -C "$r" worktree list | grep -c 'nightly-' || true; }

# 1 GREEN, and the root's DIRTY working tree is not what was scored.
mkfix green 0; echo POISON > "$r/subject.txt"
runit; rc=$?
IFS='|' read -r wd at dock tier < "$r/verify-calls"
if [ "$rc" -eq 0 ] && [ ! -e "$st/HALT" ] && [ "$(trees)" -eq 0 ] && [ "$at" = "$(git -C "$r" rev-parse main)" ] \
   && [ "$dock" = 1 ] && [ "$tier" = full ] && [ "$wd" != "$r" ] && grep -q 'progress Nightly full verify GREEN' "$r/emitted"; then
  ok "green: rc 0, no halt, the worktree removed, run at main's tip with VERIFY_REQUIRE_DOCKER=1 and tier full, in a worktree (the dirty root was not scored)"
else no "green" "rc=$rc halt=$([ -e "$st/HALT" ] && echo yes || echo no) trees=$(trees) call=$(cat "$r/verify-calls") out=$(cat "$work/out")"; fi

# 2 RED halts the fleet and keeps the evidence.
mkfix red 1; runit; rc=$?
sha="$(git -C "$r" rev-parse main)"
if [ "$rc" -eq 1 ] && grep -q "nightly full verify is RED at $sha" "$st/HALT" 2>/dev/null && [ "$(trees)" -eq 1 ] \
   && grep -q '^incident NIGHTLY VERIFY RED' "$r/emitted"; then
  ok "red: rc 1, the halt file written naming the commit, the failed worktree KEPT, an incident emitted"
else no "red" "rc=$rc halt=[$(cat "$st/HALT" 2>/dev/null)] trees=$(trees) emitted=$(cat "$r/emitted" 2>/dev/null)"; fi

# 3 RED with a halt file already present: appended, never overwritten.
mkfix red2 1; echo "Mayor halt for a sitting" > "$st/HALT"; runit; rc=$?
if [ "$rc" -eq 1 ] && [ "$(head -1 "$st/HALT")" = "Mayor halt for a sitting" ] && grep -q '^ALSO: the nightly full verify is RED' "$st/HALT"; then
  ok "red over an existing halt: the person's reason is kept and the nightly's is appended"
else no "red over halt" "rc=$rc halt=[$(cat "$st/HALT")]"; fi

# 4 Refused inside a mask; nothing runs.
mkfix masked 1
( FORT_MASKED=mayor FLEET_STATE="$st" "$r/fort/scripts/nightly-verify.sh" ) > "$work/out" 2>&1; rc=$?
if [ "$rc" -eq 64 ] && [ ! -e "$r/verify-calls" ] && [ ! -e "$st/HALT" ]; then ok "masked: refused at 64, the verifier never ran, no halt"
else no "masked" "rc=$rc"; fi

# 5 A nightly already running: 75 and nothing else.
mkfix busy 1
( exec 8>>"$st/nightly-verify.lock"; flock 8; runit; echo "$?" > "$work/rc" )
rc="$(cat "$work/rc")"
if [ "$rc" -eq 75 ] && [ ! -e "$r/verify-calls" ] && [ ! -e "$st/HALT" ]; then ok "busy: another nightly holds the lock -> 75, nothing run, no halt"
else no "busy" "rc=$rc"; fi

# 6 RED, GENERATED: the same script without its halt write must leave no halt
# file on the red fixture -- so case 2 is the halt, not something else.
nohalt="$work/nightly-nohalt.sh"
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the script's own text, literally
sed 's/^  printf .%s\\n. "\$why" > "\$halt_file"$/  : no halt/' "$subject" > "$nohalt"
if ! cmp -s "$subject" "$nohalt"; then
  mkfix red3 1; cp "$nohalt" "$r/fort/scripts/nightly-verify.sh"; runit
  if [ ! -e "$st/HALT" ]; then ok "RED: without the halt write the red fixture leaves no halt file -- case 2 discriminates"
  else no "RED: no-halt variant" "a halt file appeared anyway: $(cat "$st/HALT")"; fi
else no "RED: no-halt variant" "could not be generated (sed matched nothing)"; fi

# 7-9 UNRUNNABLE IS NOT RED (Proofdelve ForgeOs-s1reg finding 4). Docker down under the
# nightly's own VERIFY_REQUIRE_DOCKER=1, and a harness refusing (exit 3, the
# 2026-10-16 class), exit 69 with NO halt and a ran:false incident; a real step
# failure still halts (case 9, the vacuity control).
mkfix dockdown 1 "verify: step 'docker-precheck' FAILED (exit 1). Its full output is kept at /tmp/x"; runit; rc=$?
if [ "$rc" -eq 69 ] && [ ! -e "$st/HALT" ] && [ "$(trees)" -eq 0 ] && grep -q '^incident Nightly verify UNRUNNABLE.*Docker was unreachable' "$r/emitted" \
   && grep -q '"ran":false' "$r/emitted"; then ok "s1reg-4: Docker down -> 69, no halt, worktree removed, an UNRUNNABLE incident with ran:false"
else no "s1reg-4: Docker down" "rc=$rc halt=[$(cat "$st/HALT" 2>/dev/null)] trees=$(trees) emitted=$(cat "$r/emitted" 2>/dev/null)"; fi
mkfix hrefuse 3 "verify: step 'forge-refresh-harness' FAILED (exit 3). Its full output is kept at /tmp/x"; runit; rc=$?
if [ "$rc" -eq 69 ] && [ ! -e "$st/HALT" ] && grep -q 'instrument could not load what it tests' "$r/emitted"; then ok "s1reg-4: a harness refusing (exit 3) -> 69, no halt"
else no "s1reg-4: harness refusal" "rc=$rc halt=[$(cat "$st/HALT" 2>/dev/null)]"; fi
mkfix realred 1 "verify: step 'dotnet-test' FAILED (exit 1). Its full output is kept at /tmp/x"; runit; rc=$?
if [ "$rc" -eq 1 ] && [ -e "$st/HALT" ]; then ok "s1reg-4 vacuity: a real step failure still halts (rc 1)"
else no "s1reg-4 vacuity" "rc=$rc"; fi
# 10 RED, GENERATED: without the classifier the Docker-down fixture halts.
noclass="$work/nightly-noclass.sh"
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the script's own text, literally
sed 's/^if verify_unrunnable "\$log" "\$rc"; then$/if false; then/' "$subject" > "$noclass"
if ! cmp -s "$subject" "$noclass"; then
  mkfix dockdown2 1 "verify: step 'docker-precheck' FAILED (exit 1). x"; cp "$noclass" "$r/fort/scripts/nightly-verify.sh"; runit; rc=$?
  if [ "$rc" -eq 1 ] && [ -e "$st/HALT" ]; then ok "RED: without the classifier Docker down halts the fleet -- case 7 discriminates"
  else no "RED: no-classifier variant" "rc=$rc"; fi
else no "RED: no-classifier variant" "could not be generated (sed matched nothing)"; fi
# 11 The two copies of verify_unrunnable() are byte-identical (fleet.sh's and
# this script's); a fix to one that misses the other is the drift this catches.
# The sibling of the SUBJECT, never of this file: verify-impl.sh runs a copy of
# this harness from a temp directory outside the repo (harness_path), where
# $here/.. is nothing. Found by the sitting's own full verify at 4c7550f1.
fleet="${FLEET_SH:-$(dirname "$subject")/fleet.sh}"
blk() { awk '/^# >>> verify_unrunnable/{f=1} f{print} /^# <<< verify_unrunnable/{f=0}' "$1"; }
if [ -s "$fleet" ] && [ -n "$(blk "$subject")" ] && [ "$(blk "$subject")" = "$(blk "$fleet")" ]; then ok "s1reg-4: verify_unrunnable() is byte-identical in nightly-verify.sh and fleet.sh"
else no "s1reg-4: verify_unrunnable() copies" "missing or different (fleet=$fleet)"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
