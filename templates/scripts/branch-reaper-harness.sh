#!/bin/bash
# Hermetic graph fixtures for branch-reaper.sh.  Every invocation targets the
# temporary repository below; the real repository is never passed to reaper.
set -uo pipefail

reaper="${BRANCH_REAPER_SH:-$(dirname "$0")/branch-reaper.sh}"
real_git="$(command -v git)"
printf 'reaper=%s\n' "$reaper"
[ -f "$reaper" ] || { echo "HARNESS REFUSES: reaper is missing: $reaper" >&2; exit 3; }

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
repo="$work/repo"; emitted="$work/emitted"; mkdir -p "$repo"
g() { git -C "$repo" -c user.email=harness@example.test -c user.name=harness "$@"; }
git init -q -b main "$repo"
printf 'base\n' > "$repo/file"; g add file; g commit -qm base

# merged is a safe candidate. unmerged and race each have a commit main lacks.
g branch bead/merged
g switch -q -c bead/unmerged; printf 'unmerged\n' >> "$repo/file"; g add file; g commit -qm unmerged; unmerged_tip="$(g rev-parse HEAD)"; g switch -q main
g branch bead/dry
g branch keep/not-a-bead
g branch bead/attached
mkdir -p "$work/attached"; g worktree add -q "$work/attached" bead/attached

mkdir -p "$work/bin"
cat > "$work/emit.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${HARNESS_EMITTED:?}"
STUB
chmod +x "$work/emit.sh"
# The wrapper moves the named fixture ref just
# before the real deletion command, after reaper's candidate ancestry check.
cat > "$work/bin/git" <<STUB
#!/bin/bash
if [ "\${RACE_ARMED:-0}" = 1 ] && [ "\$1" = -C ] && [ "\$3" = branch ] && { [ "\$4" = -d ] || [ "\$4" = -D ] || [ "\$4" = --delete ]; } && [ "\$5" = bead/race ]; then
  "$real_git" -C "\$2" branch -f bead/race "\${RACE_TIP:?}"
fi
exec "$real_git" "\$@"
STUB
chmod +x "$work/bin/git"

pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1 -- $2"; fail=$((fail + 1)); }
run() { HARNESS_EMITTED="$emitted" BRANCH_REAPER_EMIT_SH="$work/emit.sh" bash "$reaper" --repo "$repo" "$@" 2>"$work/err"; }

# --help is an operator safety control, not merely an argument parser probe.
help="$(bash "$reaper" --help)"; help_rc=$?
if [ "$help_rc" -eq 0 ] && grep -Fq '#   scripts/branch-reaper.sh --dry-run' <<<"$help" && grep -Fq -- '--repo' <<<"$help" && grep -Fq -- '--main' <<<"$help"; then ok "--help documents --dry-run first and every flag"; else no "--help documents --dry-run first and every flag" "exit $help_rc: $help"; fi

run --dry-run; rc=$?
if [ "$rc" -eq 0 ] && g show-ref --verify --quiet refs/heads/bead/merged && g show-ref --verify --quiet refs/heads/bead/dry && ! [ -e "$emitted" ] && grep -q 'WOULD REMOVE bead/merged' "$work/err"; then ok "--dry-run reports candidates, deletes nothing, and emits no reap event"; else no "--dry-run reports candidates, deletes nothing, and emits no reap event" "exit $rc: $(cat "$work/err")"; fi

lock_ready="$work/lock-ready"
# These overrides let the harness prove that an unavailable prerequisite fails
# rather than leaving a verifier step waiting forever.
setsid_bin="${SETSID_BIN:-setsid}"
flock_bin="${FLOCK_BIN:-flock}"
lock_start_timeout_seconds="${LOCK_START_TIMEOUT_SECONDS:-5}"
lock_holder_mode="${LOCK_HOLDER_MODE:-ready}"

if ! command -v "$setsid_bin" >/dev/null 2>&1; then
  echo "HARNESS REFUSES: lock holder never started: setsid is unavailable ($setsid_bin)" >&2
  exit 3
fi
if ! command -v "$flock_bin" >/dev/null 2>&1; then
  echo "HARNESS REFUSES: lock holder never started: flock is unavailable ($flock_bin)" >&2
  exit 3
fi
if ! [[ "$lock_start_timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "HARNESS REFUSES: lock holder never started: LOCK_START_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 3
fi
case "$lock_holder_mode" in
  ready) lock_holder_command="touch \"\$1\"; exec sleep 30" ;;
  no-readiness) lock_holder_command='exec sleep 30' ;;
  *)
    echo "HARNESS REFUSES: lock holder never started: LOCK_HOLDER_MODE must be ready or no-readiness" >&2
    exit 3
    ;;
esac

"$setsid_bin" "$flock_bin" "$work/attached/.forge.lock" bash -c "$lock_holder_command" bash "$lock_ready" & lock_pid=$!
lock_start_started_at=$SECONDS
while [ ! -e "$lock_ready" ]; do
  if ! kill -0 "$lock_pid" 2>/dev/null; then
    wait "$lock_pid" 2>/dev/null || true
    echo "HARNESS REFUSES: lock holder never started: holder exited before readiness" >&2
    exit 3
  fi
  # SECONDS advances on shell-second boundaries. Strictly exceeding the bound
  # makes "after Ns" conservative rather than allowing an early timeout.
  if [ "$SECONDS" -gt $((lock_start_started_at + lock_start_timeout_seconds)) ]; then
    kill -- "-$lock_pid" 2>/dev/null || true
    wait "$lock_pid" 2>/dev/null || true
    echo "HARNESS REFUSES: lock holder never started after ${lock_start_timeout_seconds}s" >&2
    exit 3
  fi
  sleep 0.01
done
run; rc=$?
kill -- "-$lock_pid" 2>/dev/null || true; wait "$lock_pid" 2>/dev/null || true
if [ "$rc" -eq 0 ] && ! g show-ref --verify --quiet refs/heads/bead/merged && ! g show-ref --verify --quiet refs/heads/bead/dry && g show-ref --verify --quiet refs/heads/bead/unmerged && g show-ref --verify --quiet refs/heads/bead/attached && g show-ref --verify --quiet refs/heads/main && g show-ref --verify --quiet refs/heads/keep/not-a-bead && grep -q 'NOT an ancestor' "$work/err" && grep -q 'launcher holds .forge.lock' "$work/err" && grep -q '^progress ' "$emitted" && grep -q '"removed":2' "$emitted" && grep -q '"kept_locked":1' "$emitted"; then ok "merged bead refs reap; locked, unmerged, and protected/non-bead refs survive; event records counts"; else no "merged bead refs reap; locked, unmerged, and protected/non-bead refs survive; event records counts" "exit $rc: $(cat "$work/err"; cat "$emitted" 2>/dev/null)"; fi

# This is deliberately worktree-less: ancestry is its only refusal.
if g show-ref --verify --quiet refs/heads/bead/unmerged; then ok "unmerged branch with no worktree still exists after refusal"; else no "unmerged branch with no worktree still exists after refusal" "ref was deleted"; fi

rm -f "$emitted"
# race begins as a merged candidate.  The PATH wrapper moves it to an unmerged
# tip only once branch-reaper reaches its removal command.
g branch bead/race
PATH="$work/bin:$PATH" RACE_ARMED=1 RACE_TIP="$unmerged_tip" HARNESS_EMITTED="$emitted" BRANCH_REAPER_EMIT_SH="$work/emit.sh" bash "$reaper" --repo "$repo" 2>"$work/race.err"; rc=$?
if [ "$rc" -eq 1 ] && g show-ref --verify --quiet refs/heads/bead/race && grep -q 'FAILED bead/race' "$work/race.err" && grep -q '"failed":1' "$emitted"; then ok "ref moved after listing is refused by git branch -d and its failure emits an event"; else no "ref moved after listing is refused by git branch -d and its failure emits an event" "exit $rc: $(cat "$work/race.err"; cat "$emitted" 2>/dev/null)"; fi

# The child keeps flock and setsid available and its holder alive, but never
# creates the readiness file. This reaches the bounded-wait loop rather than a
# prerequisite refusal. Keep it out of the child invocation to avoid recursion.
if [ "${HARNESS_LOOP_CONTROL:-0}" != 1 ]; then
  loop_control_started_at="$(date +%s%N)"
  # The child repeats fixture setup and teardown around a (2, 3]s wait.  An
  # 8s ceiling leaves at least 5s for measured 0.25-0.65s idle overhead to
  # stretch under concurrent load, while timeout still distinguishes a
  # regressed unbounded wait from the child's ordinary refusal.
  HARNESS_LOOP_CONTROL=1 LOCK_HOLDER_MODE=no-readiness LOCK_START_TIMEOUT_SECONDS=2 timeout 15 bash "$0" >"$work/loop-control.out" 2>"$work/loop-control.err"
  loop_control_rc=$?
  loop_control_finished_at="$(date +%s%N)"
  loop_control_elapsed_ms=$(((loop_control_finished_at - loop_control_started_at) / 1000000))
  printf 'LOOP CONTROL elapsed_ms=%s exit=%s\n' "$loop_control_elapsed_ms" "$loop_control_rc"
  if [ "$loop_control_rc" -eq 124 ]; then
    no "alive holder without readiness reaches the bounded wait and refuses on time" "loop-control child exceeded its 15s timeout; the readiness wait regressed to unbounded"
  elif [ "$loop_control_rc" -eq 3 ] && [ "$loop_control_elapsed_ms" -ge 2000 ] && [ "$loop_control_elapsed_ms" -le 8000 ] && grep -Fq 'HARNESS REFUSES: lock holder never started after 2s' "$work/loop-control.err"; then
    ok "alive holder without readiness reaches the bounded wait and refuses on time"
  else
    no "alive holder without readiness reaches the bounded wait and refuses on time" "exit $loop_control_rc after ${loop_control_elapsed_ms}ms: $(cat "$work/loop-control.err")"
  fi
fi

echo; echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
