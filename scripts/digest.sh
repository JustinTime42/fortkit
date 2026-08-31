#!/bin/bash
# Deterministic Fort digest. Reads the event stream and Beads; it does not read
# memory or infer outcomes from the event text.
set -euo pipefail

usage() { printf 'Usage: %s [--since ISO-8601-timestamp]\n' "${0##*/}"; }

since_override=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; since_override="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
git_common="$(git -C "$repo_root" rev-parse --git-common-dir)"
case "$git_common" in /*) ;; *) git_common="$repo_root/$git_common" ;; esac
main_root="$(cd "$(dirname "$git_common")" && pwd -P)"
events_dir="$main_root/fort/events"
emitter="$main_root/fort/scripts/emit.sh"
all_events="$(mktemp)"; window_events="$(mktemp)"
trap 'rm -f "$all_events" "$window_events"' EXIT

epoch() { [ -n "$1" ] && date -d "$1" +%s 2>/dev/null; }

stream_state="ok"; malformed=0
if [ ! -d "$events_dir" ]; then
  stream_state="unavailable"
else
  while IFS= read -r -d '' event_file; do
    while IFS= read -r line || [ -n "$line" ]; do
      if jq -e 'type == "object"' >/dev/null 2>&1 <<<"$line"; then
        printf '%s\n' "$line" >>"$all_events"
      else
        malformed=$((malformed + 1))
      fi
    done <"$event_file"
  done < <(find "$events_dir" -maxdepth 1 -type f -name 'events-*.jsonl' -print0 2>/dev/null | sort -z)
fi

last_event_timestamp() {
  local wanted="$1" line ts candidate_epoch latest="" latest_epoch=-1
  while IFS= read -r line; do
    [ "$(jq -r '.category // empty' <<<"$line")" = "$wanted" ] || continue
    ts="$(jq -r '.ts // empty' <<<"$line")"
    candidate_epoch="$(epoch "$ts")" || continue
    if [ "$candidate_epoch" -ge "$latest_epoch" ]; then latest="$ts"; latest_epoch="$candidate_epoch"; fi
  done <"$all_events"
  printf '%s\n' "$latest"
}

fallback_note=""
if [ -n "$since_override" ]; then
  since="$since_override"
else
  since="$(last_event_timestamp digest.emitted)"
  if [ -z "$since" ]; then
    since="$(last_event_timestamp session.start)"
    if [ -z "$since" ]; then
      printf 'digest: no digest.emitted or session.start event exists. Supply --since.\n' >&2; exit 1
    fi
    fallback_note="first run; using last session.start"
  fi
fi
since_epoch="$(epoch "$since")" || { printf 'digest: invalid --since timestamp: %s\n' "$since" >&2; exit 2; }
now="$(date -Is)"; now_epoch="$(epoch "$now")"
while IFS= read -r line; do
  ts="$(jq -r '.ts // empty' <<<"$line")"
  event_epoch="$(epoch "$ts")" || continue
  if [ "$event_epoch" -gt "$since_epoch" ] && [ "$event_epoch" -le "$now_epoch" ]; then printf '%s\n' "$line" >>"$window_events"; fi
done <"$all_events"

event_count() { jq -s '[.[]] | length' "$window_events"; }
print_window_events() {
  jq -r "$1 | [.ts, .category, (.target // \"\"), (.detail // \"\")] | @tsv" "$window_events" |
    while IFS=$'\t' read -r ts category target detail; do
      if [ -n "$target" ]; then printf '  %s %s [%s] %s\n' "$ts" "$category" "$target" "$detail"
      else printf '  %s %s %s\n' "$ts" "$category" "$detail"; fi
    done
}

printf 'WINDOW\n  (%s, %s]\n' "$since" "$now"
[ -z "$fallback_note" ] || printf '  %s\n' "$fallback_note"
if [ "$stream_state" = unavailable ]; then
  printf 'EVENT STREAM\n  UNAVAILABLE (directory missing: %s)\n' "$events_dir"
elif [ "$(event_count)" -eq 0 ]; then
  printf 'EVENT STREAM\n  EMPTY WINDOW (no valid events in the selected window)\n'
else
  printf 'EVENT STREAM\n  %s valid event(s) in the selected window\n' "$(event_count)"
fi
[ "$malformed" -eq 0 ] || printf '  WARNING: %s malformed stream record(s) were unreadable\n' "$malformed"

printf 'DECISIONS WAITING\n'
for gate in gate-1 gate-2 gate-3; do
  gate_number="${gate#gate-}"; gate_file="$(mktemp)"
  set +e; bd -C "$main_root" list --status=open --label="$gate" --json >"$gate_file"; gate_status=$?; set -e
  if [ "$gate_status" -ne 0 ]; then
    printf '  GATE %s: UNAVAILABLE (bd exit %s)\n' "$gate_number" "$gate_status"
  elif ! jq -e 'type == "array"' "$gate_file" >/dev/null 2>&1; then
    printf '  GATE %s: UNAVAILABLE (bd returned invalid JSON)\n' "$gate_number"
  elif [ "$(jq 'length' "$gate_file")" -eq 0 ]; then
    printf '  GATE %s: no decisions waiting\n' "$gate_number"
  else
    printf '  GATE %s:\n' "$gate_number"
    jq -r '.[] | [(.id // "UNKNOWN"), (.status // "open"), (.title // "untitled")] | @tsv' "$gate_file" |
      while IFS=$'\t' read -r id status title; do printf '    %s [%s] %s\n' "$id" "$status" "$title"; done
  fi
  rm -f "$gate_file"
done

printf 'SHIPPED\n'
if [ "$(jq -s '[.[] | select(.category == "merge" or .category == "bead.closed" or .category == "bead.filed")] | length' "$window_events")" -eq 0 ]; then
  printf '  none in the selected window\n'
else
  print_window_events 'select(.category == "merge" or .category == "bead.closed" or .category == "bead.filed")'
fi

printf 'VERIFIER\n'
latest_verifier=""; latest_epoch=-1
while IFS=$'\t' read -r ts category target detail; do
  candidate_epoch="$(epoch "$ts")" || continue
  if [ "$candidate_epoch" -ge "$latest_epoch" ]; then latest_epoch="$candidate_epoch"; latest_verifier="$ts|$category|$target|$detail"; fi
done < <(jq -r 'select(.category == "verify.pass" or .category == "verify.run" or .category == "verify.fail") | [.ts, .category, (.target // ""), (.detail // "")] | @tsv' "$window_events")
if [ -z "$latest_verifier" ]; then printf '  no verifier event in the selected window\n'
else IFS='|' read -r ts category target detail <<<"$latest_verifier"; printf '  %s %s%s %s\n' "$ts" "$category" "${target:+ [$target]}" "$detail"; fi

printf 'IN FLIGHT\n'
declare -A session_count session_detail
unmatchable=0
while IFS= read -r line; do
  category="$(jq -r '.category // empty' <<<"$line")"
  [ "$category" = session.start ] || [ "$category" = session.end ] || continue
  seat="$(jq -r '.seat // empty' <<<"$line")"; [ "$seat" = mayor ] && continue
  target="$(jq -r '.target // empty' <<<"$line")"
  if [ -z "$seat" ] || [ -z "$target" ]; then unmatchable=$((unmatchable + 1)); continue; fi
  key="$seat|$target"
  if [ "$category" = session.start ]; then
    session_count["$key"]=$(( ${session_count[$key]:-0} + 1 )); session_detail["$key"]="$(jq -r '.detail // ""' <<<"$line")"
  elif [ "${session_count[$key]:-0}" -gt 0 ]; then session_count["$key"]=$(( ${session_count[$key]} - 1 )); fi
done <"$all_events"
active_sessions=0
for key in "${!session_count[@]}"; do
  count="${session_count[$key]}"; [ "$count" -gt 0 ] || continue
  active_sessions=$((active_sessions + count)); printf '  SESSION %s (%s unmatched start%s): %s\n' "$key" "$count" "$( [ "$count" -eq 1 ] || printf s)" "${session_detail[$key]}"
done
[ "$active_sessions" -ne 0 ] || printf '  no non-Mayor sessions in flight\n'
[ "$unmatchable" -eq 0 ] || printf '  UNDETERMINED: %s session event(s) lack seat or target\n' "$unmatchable"

live_locks=0
while IFS= read -r worktree; do
  lock="$worktree/.forge.lock"; [ -e "$lock" ] || continue
  # The Forge holds an exclusive lock. A non-blocking shared lock detects it
  # without opening another worktree's lock file for write.
  set +e
  flock -n -s "$lock" -c true 2>/dev/null
  lock_status=$?
  set -e
  if [ "$lock_status" -eq 1 ]; then
    live_locks=$((live_locks + 1)); holder="$(cat "$worktree/.forge.lock.info" 2>/dev/null || printf 'holder metadata unavailable')"
    printf '  FORGE LOCK %s: %s\n' "$worktree" "$holder"
  elif [ "$lock_status" -ne 0 ]; then
    printf '  FORGE LOCK %s: UNDETERMINED (cannot inspect lock, flock exit %s)\n' "$worktree" "$lock_status"
  fi
done < <(git -C "$main_root" worktree list --porcelain | sed -n 's/^worktree //p')
[ "$live_locks" -ne 0 ] || printf '  no live Forge locks\n'

if [ -z "$since_override" ]; then "$emitter" digest.emitted "Digest emitted for event window since $since" -a harness -t digest.sh; fi
