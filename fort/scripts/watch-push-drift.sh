#!/bin/bash
# Alert when main has accumulated more unpushed commits than the safe threshold.
# Intended for cron: fort/scripts/watch-push-drift.sh
set -euo pipefail

root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
git_bin="${GIT_BIN:-git}"
bd_bin="${BD_BIN:-bd}"
emit="$root/fort/scripts/emit.sh"
threshold="${PUSH_DRIFT_THRESHOLD:-3}"
verbose=false

usage() {
  printf 'Usage: %s [--verbose]\n' "${0##*/}" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verbose) verbose=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
  shift
done

if ! [[ "$threshold" =~ ^[0-9]+$ ]]; then
  printf 'PUSH_DRIFT_THRESHOLD must be a non-negative integer.\n' >&2
  exit 2
fi

# Cron can overlap after a slow network fetch. One watcher is sufficient, and
# serializing it keeps the read-then-create deduplication check meaningful.
lock_file="${TMPDIR:-/tmp}/fortkit-push-drift.lock"
exec 9>"$lock_file"
if ! flock -n 9; then
  printf 'Push-drift watcher is already running; skipping overlapping invocation.\n'
  exit 0
fi

fetch_failed=false
if ! "$git_bin" -C "$root" fetch --quiet origin \
  +refs/heads/main:refs/remotes/origin/main; then
  # The count below is from the cached ref, so make the watcher's blindness
  # loud even when that stale count remains under the push-drift threshold.
  fetch_failed=true
  printf 'WARNING: unable to refresh origin/main; using its cached ref.\n' >&2
fi

if ! "$git_bin" -C "$root" rev-parse --verify --quiet refs/heads/main >/dev/null; then
  printf 'Local main branch does not exist; push drift cannot be determined.\n' >&2
  exit 1
fi

if ! "$git_bin" -C "$root" rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; then
  printf 'origin/main does not exist; push drift cannot be determined.\n' >&2
  exit 1
fi

ahead="$("$git_bin" -C "$root" rev-list --count origin/main..main)"
if [ "$fetch_failed" = true ]; then
  title="Push drift: cannot refresh origin/main"
  description="Cannot refresh origin/main; the watcher is using a stale cached ref. Local main appears ${ahead} commit(s) ahead of that stale origin/main ref. Restore fetch access and then verify the count before acting."
  alert_detail="cannot refresh origin/main; stale ref shows main ${ahead} commits ahead"
elif [ "$ahead" -gt "$threshold" ]; then
  title="Push drift: main ahead of origin/main"
  description="Detected push drift: local main is ${ahead} commit(s) ahead of origin/main; alert threshold is greater than ${threshold}. Verify the commits and push or reconcile main."
  alert_detail="main is ${ahead} commits ahead of origin/main"
else
  if [ "$verbose" = true ]; then
    printf 'Push drift clear: main is %s commit(s) ahead of origin/main (threshold >%s).\n' \
      "$ahead" "$threshold"
  fi
  exit 0
fi

existing="$("$bd_bin" -C "$root" list --status open,in_progress,blocked --title "$title" --json)"
bead_id="$(jq -r '.[0].id // empty' <<<"$existing")"

if [ -z "$bead_id" ]; then
  bead_id="$("$bd_bin" -C "$root" create --silent --title "$title" --description "$description" \
    --type task --priority P1 --labels watcher,push-drift)"
  printf 'Filed %s: %s\n' "$bead_id" "$alert_detail"
else
  printf 'Push-drift alert remains open in %s: %s\n' "$bead_id" "$alert_detail"
fi

payload="$(jq -nc --argjson ahead "$ahead" --argjson threshold "$threshold" \
  --argjson fetchFailed "$fetch_failed" \
  '{ahead:$ahead,threshold:$threshold,fetchFailed:$fetchFailed}')"
if ! "$emit" watcher.alert "$alert_detail" \
  -a watcher:push-drift -t "$bead_id" -p "$payload"; then
  printf 'WARNING: push drift detected but event emission failed.\n' >&2
fi

exit 1
