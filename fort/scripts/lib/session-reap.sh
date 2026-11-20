#!/bin/bash
# session-reap.sh: kill what a seat session left running (Proofdelve ForgeOs-ab495).
# Regent sitting 2026-11-16, gate 6, the Overseer present. Sourced by
# fort/scripts/forge.sh and fort/scripts/warden.sh; it does nothing when run.
#
# WHY. A Forge or Warden session starts preview servers for a LOOK (an API with
# dotnet, a vite server) and detaches them with setsid. The seat file tells the
# seat to stop them, and sessions end without doing it. Measured on the bead:
# ten leftover processes held 2.5 GB and shut the fleet's memory gate for two
# hours on 2026-10-28, nineteen on 2026-10-29, and the Mayor killed leftovers
# by hand three times on 2026-11-08. A prose rule did not hold, so the launcher
# does it.
#
# WHAT IS REAPED. Every process of this user whose working directory is one of
# the given directories or beneath it, or which has a command-line argument
# that is such a path (bare, or after an = as in --contentRoot=<path>). The
# caller passes the directories its session owned: forge.sh its bead worktree,
# warden.sh its scratch copy.
#
# WHAT IS NEVER REAPED. This shell and every ancestor of it (the launcher, the
# fleet's worker wrapper, the terminal), whatever their arguments say.
#
# HOW. By pid, from /proc. Never pkill -f: a pattern match also matches the
# command that carries the pattern (recorded eight times in this civilization).
# SIGTERM first, up to SESSION_REAP_GRACE_S seconds (default 5) for the
# processes to go, then SIGKILL for what is left.
#
# THE CALLER'S SIDE OF THE BARGAIN. Call it only for a directory the session
# held exclusively: forge.sh holds the worktree's .forge.lock, warden.sh holds
# its per-bead lock and removes the scratch copy next. warden.sh must NOT pass
# the candidate worktree: under fleet.sh --review-only that is a Workbench
# sitting's own tree, and the Overseer may be working in it.
#
# Result: session_reap_count is set to the number of processes signalled, and
# one line per process goes to stdout (pid, cwd, command), so the launcher's
# log says what was killed. It never fails: a process that is already gone, or
# a /proc entry that cannot be read, is skipped.
#
# preview-sweep.sh and preview.sh are Proofdelve product tooling, not shipped
# by the factory. A fort without them has no backstop for sessions whose
# launcher was killed before this ran.

session_reap_count=0

session_reap() {  # $1 label for the log lines; $2.. directories (absolute)
  local label="$1"; shift
  session_reap_count=0
  local -a dirs=() pids=()
  local d
  for d in "$@"; do
    d="${d%/}"
    case "$d" in /?*) dirs+=("$d") ;; esac   # absolute and not "/" itself; anything else is ignored
  done
  [ "${#dirs[@]}" -gt 0 ] || return 0

  # this shell and its ancestors
  local -A keep=()
  local p="$$" ppid
  while [ -n "$p" ] && [ "$p" != 0 ]; do
    keep["$p"]=1
    ppid="$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null || true)"
    [ "$ppid" != "$p" ] || break
    p="$ppid"
  done
  keep["${BASHPID:-$$}"]=1

  local uid pd pid cwd hit arg cmd
  uid="$(id -u)"
  for pd in /proc/[0-9]*; do
    pid="${pd#/proc/}"
    [ -z "${keep[$pid]:-}" ] || continue
    [ "$(stat -c %u "$pd" 2>/dev/null || true)" = "$uid" ] || continue
    cwd="$(readlink "$pd/cwd" 2>/dev/null || true)"
    cwd="${cwd% (deleted)}"
    hit=0
    for d in "${dirs[@]}"; do
      case "$cwd" in "$d"|"$d"/*) hit=1; break ;; esac
    done
    if [ "$hit" = 0 ] && [ -r "$pd/cmdline" ]; then
      while IFS= read -r -d '' arg; do
        for d in "${dirs[@]}"; do
          case "$arg" in "$d"|"$d"/*|*="$d"|*="$d"/*) hit=1; break 2 ;; esac
        done
      done < "$pd/cmdline" 2>/dev/null
    fi
    [ "$hit" = 1 ] || continue
    cmd="$(tr '\0' ' ' < "$pd/cmdline" 2>/dev/null | cut -c1-200 || true)"
    if kill -TERM "$pid" 2>/dev/null; then
      pids+=("$pid")
      printf -- '--- %s: reaped leftover process %s (cwd %s): %s\n' "$label" "$pid" "${cwd:-unknown}" "${cmd:-unknown}" || true
    fi
  done
  session_reap_count="${#pids[@]}"
  [ "$session_reap_count" -gt 0 ] || return 0

  local grace="${SESSION_REAP_GRACE_S:-5}" waited=0 left
  while :; do
    left=0
    for pid in "${pids[@]}"; do kill -0 "$pid" 2>/dev/null && left=1; done
    [ "$left" = 1 ] || break
    [ "$waited" -lt "$((grace * 5))" ] || break
    sleep 0.2; waited=$((waited + 1))
  done
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
      printf -- '--- %s: process %s ignored SIGTERM for %ss and was killed\n' "$label" "$pid" "$grace" || true
    fi
  done
  return 0
}
