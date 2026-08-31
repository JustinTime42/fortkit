#!/bin/bash
# Audit fence for post-backfill merges. The fixed lower bound avoids treating
# pre-control history as a current defect while making every later main merge
# accountable to an append-only merge event.
set -euo pipefail

usage() { printf 'Usage: %s [--since ISO-8601-timestamp]\n' "${0##*/}"; }

since='2026-08-31T00:00:00-08:00'
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; since="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
git_common="$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null || true)"
if [ -z "$git_common" ] || [ ! -d "$git_common" ]; then
  printf 'merge-event-check: SKIPPED — %s is not a git checkout, so main merge coverage is unavailable.\n' "$repo_root" >&2
  exit 0
fi
case "$git_common" in /*) ;; *) git_common="$repo_root/$git_common" ;; esac
main_root="$(cd "$(dirname "$git_common")" && pwd -P)"
events_dir="$main_root/fort/events"

if ! date -d "$since" +%s >/dev/null 2>&1; then
  printf 'merge-event-check: invalid --since timestamp: %s\n' "$since" >&2
  exit 2
fi
if [ ! -d "$events_dir" ]; then
  printf 'merge-event-check: event stream unavailable: %s\n' "$events_dir" >&2
  exit 1
fi

events="$(mktemp)"; merges="$(mktemp)"
trap 'rm -f "$events" "$merges"' EXIT
while IFS= read -r -d '' event_file; do
  jq -Rc 'fromjson? | select(type == "object" and .category == "merge")' "$event_file" >>"$events"
done < <(find "$events_dir" -maxdepth 1 -type f -name 'events-*.jsonl' -print0 | sort -z)

# CI pull-request checkouts have no local main ref. In that posture, HEAD is the
# checked-out merge candidate and remains the subject this fence can audit.
audit_ref='refs/heads/main'
if ! git -C "$main_root" show-ref --verify --quiet "$audit_ref"; then
  audit_ref='HEAD'
fi

# The Mayor's no-ff merge convention names the bead in the subject. Refusing an
# unparseable post-checkpoint merge makes a changed convention visible instead
# of silently letting it bypass the correspondence check.
git -C "$main_root" log "$audit_ref" --merges --since="$since" --format='%H%x09%s' >"$merges"
commit_count=0
missing=0
declare -A legacy_matches
while IFS=$'\t' read -r commit subject; do
  [ -n "$commit" ] || continue
  commit_count=$((commit_count + 1))
  if [[ "$subject" =~ ^Merge\ (fortkit-[[:alnum:].-]+): ]]; then
    target="${BASH_REMATCH[1]}"
    # A commit hash is an exact correspondence. Older events have only a bead
    # target, so consume those one at a time rather than allowing one event to
    # satisfy every later merge of the same bead.
    if jq -e --arg commit "$commit" \
      'select(.target == $commit or (.payload.mergeCommit? == $commit))' "$events" >/dev/null; then
      :
    else
      used="${legacy_matches[$target]:-0}"
      available="$(jq -s --arg target "$target" '[.[] | select(.target == $target and (.payload.mergeCommit? | not))] | length' "$events")"
      if [ "$used" -lt "$available" ]; then
        legacy_matches["$target"]=$((used + 1))
      else
        printf 'merge-event-check: missing merge event for %s (%s)\n' "$commit" "$target" >&2
        missing=$((missing + 1))
      fi
    fi
  else
    printf 'merge-event-check: cannot identify bead for merge %s: %s\n' "$commit" "$subject" >&2
    missing=$((missing + 1))
  fi
done <"$merges"

event_count="$(jq -s 'length' "$events")"
printf 'merge-event-check: merge events: %s recorded; %s of %s main commits matched since %s\n' "$event_count" "$((commit_count - missing))" "$commit_count" "$since"
[ "$missing" -eq 0 ]
