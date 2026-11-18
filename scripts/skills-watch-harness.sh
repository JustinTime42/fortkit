#!/bin/bash
# shellcheck disable=SC2088 # Assertions deliberately match the watcher's literal ~ paths.
# shellcheck disable=SC2016 # Fixture mutations deliberately match literal shell source.
# Fixture harness for skills-watch.sh. Each RED arm mutates a copy of the
# watcher and proves its matching safety assertion would fail.
set -uo pipefail

if [ "${SKILLS_WATCH_RED_ARM:-0}" = 1 ]; then
  if [ -z "${SKILLS_WATCH_SH:-}" ]; then
    echo "FAIL  SKILLS_WATCH_RED_ARM=1 requires SKILLS_WATCH_SH for a child run" >&2
    exit 1
  fi
  echo "SKIP  RED arms (child run, SKILLS_WATCH_RED_ARM=1)"
fi

watcher="${SKILLS_WATCH_SH:-$(dirname "$0")/skills-watch.sh}"
[ -f "$watcher" ] || { echo "HARNESS REFUSES: watcher is missing: $watcher" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
trees="$work/trees"; state="$work/state"; emitted="$work/emitted"
mkdir -p "$trees/user-skills" "$trees/user-commands" "$trees/project-skills" "$trees/project-commands"
mkdir -p "$work/link-target-one/civ" "$work/link-target-two/civ"
printf '%s\n' 'old skill' > "$trees/user-skills/example.md"
printf '%s\n' 'run safely' > "$trees/user-commands/task.md"
printf '%s\n' 'project skill' > "$trees/project-skills/project.md"
ln -s example.md "$trees/user-skills/current.md"
printf '%s\n' 'linked skill' > "$work/link-target-one/civ/SKILL.md"
printf '%s\n' 'linked skill' > "$work/link-target-two/civ/SKILL.md"
ln -s "$work/link-target-one/civ" "$trees/user-skills/civ"
cat > "$work/emit.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${HARNESS_EMITTED:?}"
EOF
chmod +x "$work/emit.sh"

run() {
  local implementation="$1"
  shift
  HARNESS_EMITTED="$emitted" bash "$implementation" --user-skills "$trees/user-skills" --user-commands "$trees/user-commands" --project-skills "$trees/project-skills" --project-commands "$trees/project-commands" --state-dir "$state" --emit-sh "$work/emit.sh" "$@"
}
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1 -- $2"; fail=$((fail + 1)); }

baseline="$(run "$watcher")"; baseline_rc=$?
if [ "$baseline_rc" -eq 0 ] && [ "$baseline" = 'baseline recorded' ]; then ok 'first run records one baseline'; else no 'first run records one baseline' "exit $baseline_rc: $baseline"; fi
before_no_change=0; [ -f "$state/changes.log" ] && before_no_change="$(wc -c < "$state/changes.log")"; second="$(run "$watcher")"; second_rc=$?; after_no_change=0; [ -f "$state/changes.log" ] && after_no_change="$(wc -c < "$state/changes.log")"
if [ "$second_rc" -eq 0 ] && [ -z "$second" ] && [ "$before_no_change" = "$after_no_change" ]; then ok 'no-change run appends nothing and does not baseline again'; else no 'no-change run appends nothing and does not baseline again' "exit $second_rc: $second"; fi

printf '%s\n' 'added' > "$trees/project-skills/added.md"; run "$watcher" >/dev/null; added_rc=$?
if [ "$added_rc" -eq 1 ] && grep -Fq 'ADDED .claude/skills/added.md' "$state/changes.log"; then ok 'added file is logged with its real path'; else no 'added file is logged with its real path' "exit $added_rc"; fi
printf '%s\n' 'changed skill' > "$trees/user-skills/example.md"; run "$watcher" >/dev/null; changed_rc=$?
if [ "$changed_rc" -eq 1 ] && awk '$0 == "--- old/~/.claude/skills/example.md" { if ((getline) != 1 || $0 != "+++ new/~/.claude/skills/example.md") exit 1; if ((getline) != 1 || $0 !~ /^@@ /) exit 1; found=1 } END { exit !found }' "$state/changes.log"; then ok 'changed text file has ordered unified diff with real paths'; else no 'changed text file has ordered unified diff with real paths' "exit $changed_rc"; fi
for line in $(seq 1 250); do printf 'long changed skill %s\n' "$line"; done > "$trees/user-skills/example.md"; run "$watcher" >/dev/null; long_diff_rc=$?; diff_cut_line="$(grep -F 'DIFF CUT after 200 lines for ' "$state/changes.log" | tail -n 1)"
if [ "$long_diff_rc" -eq 1 ] && [ "$diff_cut_line" = 'DIFF CUT after 200 lines for ~/.claude/skills/example.md' ] && awk '$0 == "--- old/~/.claude/skills/example.md" { start=NR; if ((getline) != 1 || $0 != "+++ new/~/.claude/skills/example.md") exit 1; if ((getline) != 1 || $0 !~ /^@@ /) exit 1; valid=1; next } $0 == "DIFF CUT after 200 lines for ~/.claude/skills/example.md" && valid && NR - start == 200 { found=1; exit } END { exit !found }' "$state/changes.log"; then ok 'long diff contains ordered header and 200 lines before its real-path cut'; else no 'long diff contains ordered header and 200 lines before its real-path cut' "exit $long_diff_rc: $diff_cut_line"; fi
rm "$trees/user-skills/civ"; ln -s "$work/link-target-two/civ" "$trees/user-skills/civ"; run "$watcher" >/dev/null; retarget_rc=$?
if [ "$retarget_rc" -eq 1 ] && grep -Fq 'RETARGETED ~/.claude/skills/civ' "$state/changes.log" && ! grep -F 'RETARGETED ~/.claude/skills/civ' "$state/changes.log" | grep -Fq EXECUTABLE; then ok 'plain retargeted directory link is logged but not EXECUTABLE'; else no 'plain retargeted directory link is logged but not EXECUTABLE' "exit $retarget_rc"; fi
printf '%s\n' 'printf linked' > "$work/link-target-one/civ/run.sh"; rm "$trees/user-skills/civ"; ln -s "$work/link-target-one/civ" "$trees/user-skills/civ"; run "$watcher" >/dev/null; retarget_executable_rc=$?
if [ "$retarget_executable_rc" -eq 1 ] && grep -F 'RETARGETED ~/.claude/skills/civ' "$state/changes.log" | tail -n 1 | grep -Fq EXECUTABLE; then ok 'retargeted directory link is EXECUTABLE only when its new target is executable'; else no 'retargeted directory link is EXECUTABLE only when its new target is executable' "exit $retarget_executable_rc"; fi
printf '%s\n' '! printf unsafe' > "$trees/user-commands/shell.md"; run "$watcher" >/dev/null; executable_rc=$?
if [ "$executable_rc" -eq 1 ] && grep -F 'ADDED ~/.claude/commands/shell.md' "$state/changes.log" | grep -Fq EXECUTABLE && grep -Fq '~/.claude/commands/shell.md' "$emitted"; then ok '! command is marked EXECUTABLE in log and alert with real paths'; else no '! command is marked EXECUTABLE in log and alert with real paths' "exit $executable_rc"; fi

cat > "$work/fail-emit.sh" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$work/fail-emit.sh"
printf '%s\n' 'must be reported again' > "$trees/project-commands/retry.md"; run "$watcher" --emit-sh "$work/fail-emit.sh" >/dev/null; failed_emit_rc=$?; emitted_before_retry="$(wc -l < "$emitted")"; run "$watcher" >/dev/null; retry_rc=$?; emitted_after_retry="$(wc -l < "$emitted")"
if [ "$failed_emit_rc" -eq 3 ] && [ "$retry_rc" -eq 1 ] && [ "$emitted_after_retry" -gt "$emitted_before_retry" ] && tail -n 1 "$emitted" | grep -Fq '.claude/commands/retry.md'; then ok 'failed emit leaves state uncommitted so the next run re-reports the alert'; else no 'failed emit leaves state uncommitted so the next run re-reports the alert' "failed=$failed_emit_rc retry=$retry_rc emitted=$emitted_before_retry/$emitted_after_retry"; fi

# RED arms remove one invariant at a time. A passing RED arm proves the harness
# discriminates, because the weakened implementation makes its matching check fail.
if [ "${SKILLS_WATCH_RED_ARM:-0}" != 1 ]; then
# shellcheck disable=SC2016 # sed expression intentionally matches literal shell source.
red="$work/no-long-diff-lines.sh"; sed 's/head -n 200 "$diff_file" >> "$changes_tmp"/: # RED: omit truncated diff lines/' "$watcher" > "$red"; chmod +x "$red"; red_long_output="$(SKILLS_WATCH_RED_ARM=1 SKILLS_WATCH_SH="$red" bash "$0" 2>&1)"; red_long_rc=$?
if [ "$red_long_rc" -eq 1 ] && printf '%s\n' "$red_long_output" | grep -Fq 'FAIL  long diff contains ordered header and 200 lines before its real-path cut'; then ok 'RED long-diff omission fails the ordered 200-line check'; else no 'RED long-diff omission fails the ordered 200-line check' "exit $red_long_rc: $red_long_output"; fi
# shellcheck disable=SC2016 # sed expressions intentionally match literal shell source.
red="$work/no-added.sh"; sed 's/status=ADDED; added=\$((added + 1))/continue # RED: suppress added/' "$watcher" > "$red"; chmod +x "$red"; rm -rf "$state"; : > "$emitted"; run "$red" >/dev/null; red_base_rc=$?; printf x > "$trees/project-skills/red-added.md"; run "$red" >/dev/null; red_added_rc=$?
if [ "$red_base_rc" -eq 0 ] && [ "$red_added_rc" -eq 0 ]; then ok 'RED added-file omission fails to report a change'; else no 'RED added-file omission fails to report a change' "baseline=$red_base_rc change=$red_added_rc"; fi
# shellcheck disable=SC2016
red="$work/no-diff.sh"; sed 's/cat "\$diff_file" >> "\$changes_tmp"/: # RED: omit diff content/' "$watcher" > "$red"; chmod +x "$red"; printf 'red old\n' > "$trees/user-skills/example.md"; rm -rf "$state"; run "$red" >/dev/null; printf changed > "$trees/user-skills/example.md"; run "$red" >/dev/null; red_diff_rc=$?
if [ "$red_diff_rc" -eq 1 ] && ! grep -Fq -- '--- old/~/.claude/skills/example.md' "$state/changes.log"; then ok 'RED changed-file omission leaves no ordered diff'; else no 'RED changed-file omission leaves no ordered diff' "exit $red_diff_rc"; fi
# shellcheck disable=SC2016
red="$work/no-retarget.sh"; sed 's/elif \[ "\$old_link" != "\$new_link" \]; then status=RETARGETED; retargeted=\$((retargeted + 1))/elif false; then status=RETARGETED/' "$watcher" > "$red"; chmod +x "$red"; rm -rf "$state"; rm "$trees/user-skills/civ"; ln -s "$work/link-target-one/civ" "$trees/user-skills/civ"; run "$red" >/dev/null; rm "$trees/user-skills/civ"; ln -s "$work/link-target-two/civ" "$trees/user-skills/civ"; run "$red" >/dev/null; red_retarget_rc=$?
if [ "$red_retarget_rc" -eq 1 ] && ! grep -Fq 'RETARGETED ~/.claude/skills/civ' "$state/changes.log"; then ok 'RED retarget omission lacks directory-link RETARGETED status'; else no 'RED retarget omission lacks directory-link RETARGETED status' "exit $red_retarget_rc"; fi
# shellcheck disable=SC2016
red="$work/no-executable.sh"; sed 's/flag=" EXECUTABLE"/flag="" # RED: omit executable/' "$watcher" > "$red"; chmod +x "$red"; rm -rf "$state"; run "$red" >/dev/null; printf '! red shell\n' > "$trees/user-commands/red.md"; run "$red" >/dev/null; red_executable_rc=$?
if [ "$red_executable_rc" -eq 1 ] && ! grep -F 'ADDED ~/.claude/commands/red.md' "$state/changes.log" | grep -Fq EXECUTABLE; then ok 'RED ! command omission lacks EXECUTABLE flag'; else no 'RED ! command omission lacks EXECUTABLE flag' "exit $red_executable_rc"; fi
# shellcheck disable=SC2016
red="$work/commit-before-emit.sh"; sed 's/^summary="skills/mv -f "$next_manifest" "$manifest" || fail "RED committed manifest early"\nrm -rf "$snapshot" || fail "RED replaced snapshot early"\nmv -f "$next_snapshot" "$snapshot" || fail "RED installed snapshot early"\nsummary="skills/' "$watcher" > "$red"; chmod +x "$red"; rm -rf "$state"; run "$red" >/dev/null; printf '%s\n' 'lost by early commit' > "$trees/project-commands/red-retry.md"; run "$red" --emit-sh "$work/fail-emit.sh" >/dev/null; red_failed_emit_rc=$?; red_emitted_before_retry="$(wc -l < "$emitted")"; run "$red" >/dev/null; red_retry_rc=$?; red_emitted_after_retry="$(wc -l < "$emitted")"
if [ "$red_failed_emit_rc" -eq 3 ] && [ "$red_retry_rc" -eq 0 ] && [ "$red_emitted_after_retry" = "$red_emitted_before_retry" ]; then ok 'RED early state commit loses the failed alert on retry'; else no 'RED early state commit loses the failed alert on retry' "failed=$red_failed_emit_rc retry=$red_retry_rc emitted=$red_emitted_before_retry/$red_emitted_after_retry"; fi
# shellcheck disable=SC2016
red="$work/no-nochange.sh"; sed '/if \[ ! -s "\$changes_tmp" \]; then/a\  printf "RED NO-CHANGE APPEND\\n" >> "$state_dir/changes.log"' "$watcher" > "$red"; chmod +x "$red"; rm -rf "$state"; run "$red" >/dev/null; red_before=0; [ -f "$state/changes.log" ] && red_before="$(wc -c < "$state/changes.log")"; run "$red" >/dev/null; red_after="$(wc -c < "$state/changes.log")"
if [ "$red_after" -gt "$red_before" ]; then ok 'RED no-change variant appends to the log'; else no 'RED no-change variant appends to the log' "before=$red_before after=$red_after"; fi
# shellcheck disable=SC2016
red="$work/second-baseline.sh"; sed 's/if \[ ! -e "\$manifest" \]; then/if true; then # RED: always baseline/' "$watcher" > "$red"; chmod +x "$red"; rm -rf "$state"; red_first="$(run "$red")"; red_second="$(run "$red")"
if [ "$red_first" = 'baseline recorded' ] && [ "$red_second" = 'baseline recorded' ]; then ok 'RED always-baseline variant reports a second baseline'; else no 'RED always-baseline variant reports a second baseline' "first=$red_first second=$red_second"; fi
fi
missing="$work/missing"; rm -rf "$missing"; run "$watcher" --user-skills "$missing" >/dev/null 2>&1; unreadable_rc=$?
if [ "$unreadable_rc" -eq 3 ]; then ok 'unreadable or missing tree never exits 0'; else no 'unreadable or missing tree never exits 0' "exit $unreadable_rc"; fi

echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
