#!/bin/bash
# Exit 0 only when no Forge, Warden, or verifier work is live.  A nonzero exit
# always explains the activity that prevented quiescence.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
git_common="$(git -C "$repo_root" rev-parse --git-common-dir)"
case "$git_common" in /*) ;; *) git_common="$repo_root/$git_common" ;; esac
main_root="$(cd "$(dirname "$git_common")" && pwd -P)"
events_dir="${FORTKIT_EVENTS_DIR:-$main_root/fort/events}"
worktrees_root="${FORTKIT_WORKTREES_ROOT:-/home/justin/dev/fortkit-worktrees}"
stale_after_seconds="${QUIESCENT_STALE_AFTER_SECONDS:-$((2 * 60 * 60))}"

busy=0

mark_busy() {
  printf 'busy: %s\n' "$*"
  busy=1
}

check_forge_locks() {
  local lock fd holder
  local -a locks

  shopt -s nullglob
  locks=("$worktrees_root"/*/.forge.lock)
  shopt -u nullglob
  for lock in "${locks[@]}"; do
    # A shared lock conflicts with Forge's exclusive launcher lock, and needs
    # no write access to another worktree.  The sidecar is explanatory only.
    exec {fd}<"$lock"
    if ! flock -n -s "$fd"; then
      holder="$(cat "${lock}.info" 2>/dev/null || printf 'holder info unavailable')"
      mark_busy "forge lock $lock ($holder)"
    else
      flock -u "$fd"
    fi
    exec {fd}>&-
  done
}

check_warden_and_verifier_processes() {
  local proc pid arg previous is_warden is_verifier
  for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    [ "$pid" = "$$" ] && continue
    [ -r "$proc/cmdline" ] || continue
    is_warden=0; is_verifier=0; previous=""
    while IFS= read -r -d '' arg; do
      case "$arg" in
        fort/scripts/warden.sh|*/fort/scripts/warden.sh|warden.sh)
          is_warden=1
          ;;
        scripts/verify-impl.sh|*/scripts/verify-impl.sh)
          is_verifier=1
          ;;
        warden-settings.json|*/warden-settings.json)
          # The bwrap child is the process that does the Warden review, after
          # warden.sh has launched it.  Its settings argument identifies it.
          is_warden=1
          ;;
      esac
      if [ "$previous" = "FORT_MASKED" ] && [ "$arg" = "warden" ]; then
        is_warden=1
      fi
      previous="$arg"
    done <"$proc/cmdline"
    [ "$is_warden" -eq 0 ] || mark_busy "warden process pid=$pid"
    [ "$is_verifier" -eq 0 ] || mark_busy "verifier process pid=$pid"
  done
}

check_session_events() {
  local now_epoch ts seat target category detail epoch key age closed_status has_unmatched
  local closed_beads
  local -A starts=() start_ts=() start_detail=()

  [ -d "$events_dir" ] || return 0
  now_epoch="$(date +%s)"
  while IFS=$'\t' read -r ts seat target category detail; do
    # mayor.sh execs bwrap, so its EXIT trap cannot supply session.end.  Mayor
    # events are deliberately outside this predicate (fortkit-t9iw).
    [ "$seat" = "mayor" ] && continue
    [ -n "$seat" ] && [ -n "$target" ] || {
      mark_busy "unmatchable session event seat=${seat:-missing} target=${target:-missing} since=$ts"
      continue
    }
    epoch="$(date -d "$ts" +%s 2>/dev/null || true)"
    [ -n "$epoch" ] || {
      mark_busy "session with invalid timestamp seat=$seat target=$target ts=$ts"
      continue
    }
    key="$seat|$target"
    if [ "$category" = "session.start" ]; then
      starts["$key"]=$(( ${starts[$key]:-0} + 1 ))
      start_ts["$key"]="$ts"
      start_detail["$key"]="$detail"
    elif [ "${starts[$key]:-0}" -gt 0 ]; then
      starts["$key"]=$(( ${starts[$key]} - 1 ))
    fi
  done < <(
    find "$events_dir" -maxdepth 1 -type f -name 'events-*.jsonl' -print 2>/dev/null |
      sort | xargs -r -n1 cat |
      jq -r 'select((.category == "session.start" or .category == "session.end") and (.ts | type == "string")) | [.ts, (.seat // "" | tostring), (.target // "" | tostring), .category, (.detail // "" | tostring)] | @tsv' |
      sort
  )

  has_unmatched=0
  for key in "${!starts[@]}"; do
    if [ "${starts[$key]}" -gt 0 ]; then
      has_unmatched=1
      break
    fi
  done
  [ "$has_unmatched" -eq 1 ] || return 0

  closed_beads="$(mktemp)"
  set +e
  bd -C "$main_root" list --status=closed --json >"$closed_beads" 2>/dev/null
  closed_status=$?
  set -e
  if [ "$closed_status" -eq 0 ] && ! jq -e 'type == "array"' "$closed_beads" >/dev/null 2>&1; then
    closed_status=1
  fi

  for key in "${!starts[@]}"; do
    [ "${starts[$key]}" -gt 0 ] || continue
    target="${key#*|}"
    if [ "$closed_status" -eq 0 ] && jq -e --arg id "$target" 'any(.[]; .id == $id)' "$closed_beads" >/dev/null; then
      printf 'stale: session %s targets a closed bead (treated as quiet)\n' "$key"
      continue
    fi
    ts="${start_ts[$key]}"
    epoch="$(date -d "$ts" +%s 2>/dev/null || true)"
    [ -n "$epoch" ] || continue
    age=$((now_epoch - epoch))
    if [ "$age" -gt "$stale_after_seconds" ]; then
      printf 'stale: session %s since=%s (age %ss; treated as quiet)\n' "$key" "$ts" "$age"
    else
      mark_busy "session $key since=$ts (${start_detail[$key]})"
    fi
  done
  rm -f "$closed_beads"
}

check_forge_locks
check_warden_and_verifier_processes
check_session_events

exit "$busy"
