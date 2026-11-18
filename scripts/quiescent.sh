#!/bin/bash
# Exit 0 when the fort has no Forge, Warden, or verifier activity. Exit 1 and
# print a reason when something is still moving.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
git_common="$(git -C "$repo_root" rev-parse --git-common-dir)"
case "$git_common" in
  /*) ;;
  *) git_common="$repo_root/$git_common" ;;
esac
main_root="$(cd "$(dirname "$git_common")" && pwd -P)"
events_dir="${FORGE_EVENTS_DIR:-$main_root/fort/events}"
stale_after_seconds=$((2 * 60 * 60))
forge_worktrees_root="${FORGE_WORKTREES_ROOT:-/home/justin/dev/ForgeOs-worktrees}"

busy=0

check_forge_locks() {
  local lock fd info
  local -a locks

  shopt -s nullglob
  locks=("$forge_worktrees_root"/*/.forge.lock)
  shopt -u nullglob

  for lock in "${locks[@]}"; do
    # The non-blocking acquisition is the sole liveness signal. The info file
    # is only a human-readable label for a lock we already know is held.
    # A shared lock on a read-only descriptor conflicts with Forge's exclusive
    # lock. This avoids needing write access to another worktree just to
    # observe its launcher lock.
    exec {fd}<"$lock"
    if ! flock -n -s "$fd"; then
      info="$(cat "${lock}.info" 2>/dev/null || printf 'holder info unavailable')"
      printf 'busy: forge lock %s (%s)\n' "$lock" "$info"
      busy=1
    else
      flock -u "$fd"
    fi
    exec {fd}>&-
  done
}

check_warden_events() {
  local ts category target timestamp epoch terminal_epoch now_epoch age
  local -A latest_terminal=()

  [ -d "$events_dir" ] || return 0

  # First retain the latest terminal event for each target. Event order is not
  # trusted: timestamps establish whether a terminal event is actually later.
  while IFS=$'\t' read -r ts category target; do
    timestamp="$(date -d "$ts" +%s 2>/dev/null || true)"
    [ -n "$timestamp" ] || continue
    if [ "$category" = "session.end" ] || [ "$category" = "review.verdict" ]; then
      if [ -z "${latest_terminal[$target]+x}" ] || [ "$timestamp" -gt "${latest_terminal[$target]}" ]; then
        latest_terminal[$target]="$timestamp"
      fi
    fi
  done < <(
    find "$events_dir" -maxdepth 1 -type f -name 'events-*.jsonl' -print 2>/dev/null |
      sort | xargs -r -n1 cat |
      jq -r 'select((.category == "review.verdict" or (.category == "session.end" and .seat == "warden")) and (.target | type == "string") and (.ts | type == "string")) | [.ts, .category, .target] | @tsv'
  )

  now_epoch="$(date +%s)"
  while IFS=$'\t' read -r ts target; do
    epoch="$(date -d "$ts" +%s 2>/dev/null || true)"
    [ -n "$epoch" ] || continue
    terminal_epoch="${latest_terminal[$target]:-0}"
    [ "$terminal_epoch" -gt "$epoch" ] && continue

    age=$((now_epoch - epoch))
    if [ "$age" -gt "$stale_after_seconds" ]; then
      printf 'stale: warden target=%s since=%s (age %ss; treated as quiet)\n' "$target" "$ts" "$age"
    else
      printf 'busy: warden target=%s since=%s\n' "$target" "$ts"
      busy=1
    fi
  done < <(
    find "$events_dir" -maxdepth 1 -type f -name 'events-*.jsonl' -print 2>/dev/null |
      sort | xargs -r -n1 cat |
      jq -r 'select(.category == "session.start" and .seat == "warden" and (.target | type == "string") and (.ts | type == "string")) | [.ts, .target] | @tsv'
  )
}

check_verifier_processes() {
  local proc pid arg verify_arg

  for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    [ "$pid" = "$$" ] && continue
    [ -r "$proc/cmdline" ] || continue
    verify_arg=""
    while IFS= read -r -d '' arg; do
      case "$arg" in
        scripts/verify-impl.sh|*/scripts/verify-impl.sh)
          verify_arg="$arg"
          break
          ;;
      esac
    done <"$proc/cmdline"
    if [ -n "$verify_arg" ]; then
      printf 'busy: verifier pid=%s script=%s\n' "$pid" "$verify_arg"
      busy=1
    fi
  done
}

check_forge_locks
check_warden_events
check_verifier_processes

exit "$busy"
