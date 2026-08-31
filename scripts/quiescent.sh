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
  local lock holder lock_status
  local -a locks

  shopt -s nullglob
  locks=("$worktrees_root"/*/.forge.lock)
  shopt -u nullglob
  for lock in "${locks[@]}"; do
    # A shared lock conflicts with Forge's exclusive launcher lock, and needs
    # no write access to another worktree.  The sidecar is explanatory only.
    set +e
    flock -E 75 -n -s "$lock" -c true 2>/dev/null
    lock_status=$?
    set -e
    if [ "$lock_status" -eq 75 ]; then
      holder="$(cat "${lock}.info" 2>/dev/null || printf 'holder info unavailable')"
      mark_busy "forge lock $lock ($holder)"
    elif [ "$lock_status" -ne 0 ]; then
      mark_busy "forge lock $lock is undetermined (flock exit $lock_status)"
    fi
  done
}

check_warden_and_verifier_processes() {
  local proc pid arg index is_warden is_verifier argv0 cwd resolved_arg
  local warden_script warden_settings
  # Predicate: is a Warden or verifier belonging to THIS fort alive?  A script
  # basename alone cannot answer that: editors, other forts, and inaccessible
  # namespaces may carry the same name.
  warden_script="$main_root/fort/scripts/warden.sh"
  warden_settings="$main_root/fort/profiles/warden-settings.json"

  for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    [ "$pid" = "$$" ] && continue
    [ -r "$proc/cmdline" ] || continue
    argv0=""; cwd=""; is_warden=0; is_verifier=0; index=0
    # A process may exit after the readability check and before this redirect.
    # Treat that vanished process as quiet, then continue checking the rest.
    if ! while IFS= read -r -d '' arg; do
      if [ "$index" -eq 0 ]; then
        argv0="$arg"
        index=$((index + 1))
        continue
      fi

      # warden.sh is only live when Bash is actually executing THIS fort's
      # script as argv[1]. Resolve a relative script from the process cwd:
      # Mayor launches `cd $main_root; fort/scripts/warden.sh ...`. Do not
      # search command text, since editors and other forts are not work.
      if [ "$index" -eq 1 ] && { [ "$argv0" = "/bin/bash" ] || [ "$argv0" = "/usr/bin/bash" ] || [ "$argv0" = "bash" ]; } && [[ "$arg" = */warden.sh || "$arg" = warden.sh ]]; then
        if [[ "$arg" = /* ]]; then
          # Absolute script paths remain scoped even when /proc/<pid>/cwd is
          # unreadable, so they can be positively identified without guessing.
          resolved_arg="$(realpath -m -- "$arg")"
        else
          cwd="$(readlink -f "$proc/cwd" 2>/dev/null || true)"
          # A relative path with an unreadable cwd cannot be attributed to this
          # fort. Reporting it as undetermined would let another fort pin this
          # hook forever, so only an inspectable candidate is fail-closed.
          [ -n "$cwd" ] || { index=$((index + 1)); continue; }
          resolved_arg="$(realpath -m -- "$cwd/$arg")"
        fi
        [ "$resolved_arg" != "$warden_script" ] || is_warden=1
      fi

      # The Warden review itself is the bwrap child.  Scope its settings path
      # to this fort as well; a bwrap for another settlement is unrelated.
      if { [ "$argv0" = "/usr/bin/bwrap" ] || [ "$argv0" = "/bin/bwrap" ] || [ "$argv0" = "bwrap" ]; } && [ "$arg" = "$warden_settings" ]; then
        is_warden=1
      fi

      # verify-impl remains a Bash parent while its individual gate commands
      # run.  Accept only this fort's main checkout or its own worktrees.
      if [ "$index" -eq 1 ] && { [ "$argv0" = "/bin/bash" ] || [ "$argv0" = "/usr/bin/bash" ] || [ "$argv0" = "bash" ]; } && [[ "$arg" = */verify-impl.sh || "$arg" = verify-impl.sh ]]; then
        if [[ "$arg" = /* ]]; then
          resolved_arg="$(realpath -m -- "$arg")"
        else
          cwd="$(readlink -f "$proc/cwd" 2>/dev/null || true)"
          # See the Warden branch: an uninspectable relative path is not
          # sufficient evidence that this fort has a live verifier.
          [ -n "$cwd" ] || { index=$((index + 1)); continue; }
          resolved_arg="$(realpath -m -- "$cwd/$arg")"
        fi
        case "$resolved_arg" in
          "$main_root/scripts/verify-impl.sh"|"$worktrees_root"/*/scripts/verify-impl.sh) is_verifier=1 ;;
        esac
      fi
      index=$((index + 1))
    done <"$proc/cmdline"; then
      continue
    fi
    [ "$is_warden" -eq 0 ] || mark_busy "warden process pid=$pid"
    [ "$is_verifier" -eq 0 ] || mark_busy "verifier process pid=$pid"
  done
}

check_session_events() {
  local now_epoch ts seat target category detail epoch key age closed_status has_unmatched
  local closed_beads
  trap 'rm -f "${closed_beads:-}"' RETURN
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
      while IFS= read -r event; do
        ts="${event%%$'\t'*}"
        epoch="$(date -d "$ts" +%s 2>/dev/null || true)"
        [ -n "$epoch" ] && printf '%s\t%s\n' "$epoch" "$event"
      done | sort -n | cut -f2-
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
  trap - RETURN
}

check_forge_locks
check_warden_and_verifier_processes
check_session_events

exit "$busy"
