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
all_events="$(mktemp)"; timestamped_events="$(mktemp)"; window_events="$(mktemp)"; closed_beads="$(mktemp)"; timestamp_report="$(mktemp)"
trap 'rm -f "$all_events" "$timestamped_events" "$window_events" "$closed_beads" "$timestamp_report"' EXIT
max_decisions_per_gate=5

epoch() { [ -n "$1" ] && date -d "$1" +%s 2>/dev/null; }

stream_state="ok"; malformed=0; shard_count=0; invalid_timestamps=0
if [ ! -d "$events_dir" ]; then
  stream_state="unavailable"
else
  while IFS= read -r -d '' event_file; do
    shard_count=$((shard_count + 1))
    # Process a shard at once. Per-record jq invocations make a complete
    # historical stream needlessly slow, while raw-input parsing keeps one bad
    # JSONL line from preventing the digest from reporting the rest.
    total_records="$(awk 'END { print NR }' "$event_file")"
    valid_records="$(jq -Rc 'fromjson? | select(type == "object")' "$event_file" | tee -a "$all_events" | awk 'END { print NR }')"
    malformed=$((malformed + total_records - valid_records))
  done < <(find "$events_dir" -maxdepth 1 -type f -name 'events-*.jsonl' -print0 2>/dev/null | sort -z)
fi

# Parse timestamps once, after the JSONL stream has been validated. Date.parse
# understands ISO-8601 offsets, so this keeps the schema's timestamp ordering
# rule without treating event shard names as dates.
if [ -s "$all_events" ]; then
  node -e '
    let invalid = 0;
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => { input += chunk; });
    process.stdin.on("end", () => {
      for (const line of input.split("\n")) {
        if (!line) continue;
        const event = JSON.parse(line);
        const instant = typeof event.ts === "string" ? Date.parse(event.ts) : NaN;
        if (Number.isNaN(instant)) { invalid += 1; continue; }
        process.stdout.write(JSON.stringify({ ...event, _epoch: Math.floor(instant / 1000) }) + "\n");
      }
      process.stderr.write(String(invalid));
    });
  ' <"$all_events" >"$timestamped_events" 2>"$timestamp_report"
  invalid_timestamps="$(cat "$timestamp_report")"
fi

last_event_timestamp() {
  jq -sr --arg wanted "$1" '[.[] | select(.category == $wanted)] | if length == 0 then "" else max_by(._epoch).ts end' "$timestamped_events"
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
jq -c --argjson since "$since_epoch" --argjson now "$now_epoch" 'select(._epoch > $since and ._epoch <= $now)' "$timestamped_events" >"$window_events"

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
elif [ "$shard_count" -eq 0 ]; then
  printf 'EVENT STREAM\n  EMPTY WINDOW (0 event shards found in %s)\n' "$events_dir"
elif [ "$(event_count)" -eq 0 ]; then
  printf 'EVENT STREAM\n  EMPTY WINDOW (no valid events in the selected window)\n'
else
  printf 'EVENT STREAM\n  %s valid event(s) in the selected window\n' "$(event_count)"
fi
[ "$malformed" -eq 0 ] || printf '  WARNING: %s malformed stream record(s) were unreadable\n' "$malformed"
[ "$invalid_timestamps" -eq 0 ] || printf '  WARNING: %s valid stream record(s) had unreadable timestamps\n' "$invalid_timestamps"

printf 'DECISIONS WAITING\n'
for gate in gate-1 gate-2 gate-3; do
  gate_number="${gate#gate-}"; gate_file="$(mktemp)"; gate_open="$(mktemp)"; gate_in_progress="$(mktemp)"
  set +e; bd -C "$main_root" list --status=open --label="$gate" --json >"$gate_open"; gate_open_status=$?
  bd -C "$main_root" list --status=in_progress --label="$gate" --json >"$gate_in_progress"; gate_in_progress_status=$?; set -e
  if [ "$gate_open_status" -eq 0 ] && [ "$gate_in_progress_status" -eq 0 ]; then jq -s 'add | unique_by(.id)' "$gate_open" "$gate_in_progress" >"$gate_file"; fi
  gate_status=$((gate_open_status != 0 ? gate_open_status : gate_in_progress_status))
  if [ "$gate_status" -ne 0 ]; then
    printf '  GATE %s: UNAVAILABLE (bd exit %s)\n' "$gate_number" "$gate_status"
  elif ! jq -e 'type == "array"' "$gate_file" >/dev/null 2>&1; then
    printf '  GATE %s: UNAVAILABLE (bd returned invalid JSON)\n' "$gate_number"
  elif [ "$(jq 'length' "$gate_file")" -eq 0 ]; then
    printf '  GATE %s: no decisions waiting\n' "$gate_number"
  else
    gate_total="$(jq 'length' "$gate_file")"
    gate_shown=$(( gate_total < max_decisions_per_gate ? gate_total : max_decisions_per_gate ))
    printf '  GATE %s: %s decision(s) waiting (showing %s of %s, most recently updated)\n' "$gate_number" "$gate_total" "$gate_shown" "$gate_total"
    jq -r --argjson limit "$max_decisions_per_gate" 'sort_by(.updated_at // .created_at // "") | reverse | .[:$limit][] | [(.id // "UNKNOWN"), (.status // "open"), (.title // "untitled")] | @tsv' "$gate_file" |
      while IFS=$'\t' read -r id status title; do printf '    %s [%s] %s\n' "$id" "$status" "$title"; done
    if [ "$gate_total" -gt "$gate_shown" ]; then
      printf '    %s decision(s) elided; full count is %s.\n' "$((gate_total - gate_shown))" "$gate_total"
    fi
  fi
  rm -f "$gate_file" "$gate_open" "$gate_in_progress"
done

printf 'SHIPPED\n'
if [ "$(jq -s '[.[] | select(.category == "merge" or .category == "bead.closed" or .category == "bead.filed")] | length' "$window_events")" -eq 0 ]; then
  printf '  no merge/close/file events in the selected window\n'
else
  print_window_events 'select(.category == "merge" or .category == "bead.closed" or .category == "bead.filed")'
fi

printf 'VERIFIER\n'
latest_verifier="$(jq -sr '[.[] | select(.category == "verify.pass" or .category == "verify.run" or .category == "verify.fail")] | if length == 0 then "" else max_by(._epoch) | [.ts, .category, (.target // ""), (.detail // "")] | @tsv end' "$window_events")"
if [ -z "$latest_verifier" ]; then printf '  no verifier event in the selected window\n'
else IFS=$'\t' read -r ts category target detail <<<"$latest_verifier"; printf '  %s %s%s %s\n' "$ts" "$category" "${target:+ [$target]}" "$detail"; fi

printf 'IN FLIGHT\n'
declare -A session_count session_detail session_timestamp
unmatchable=0
while IFS= read -r line; do
  IFS=$'\t' read -r category seat target ts detail <<<"$line"
  [ "$seat" = mayor ] && continue
  if [ -z "$seat" ] || [ -z "$target" ]; then unmatchable=$((unmatchable + 1)); continue; fi
  key="$seat|$target"
  if [ "$category" = session.start ]; then
    session_count["$key"]=$(( ${session_count[$key]:-0} + 1 )); session_detail["$key"]="$detail"; session_timestamp["$key"]="$ts"
  elif [ "${session_count[$key]:-0}" -gt 0 ]; then session_count["$key"]=$(( ${session_count[$key]} - 1 )); fi
done < <(jq -rs 'sort_by(._epoch)[] | select(.category == "session.start" or .category == "session.end") | [.category, (.seat // ""), (.target // ""), .ts, (.detail // "")] | @tsv' "$timestamped_events")

closed_status=0
set +e
bd -C "$main_root" list --status=closed --json >"$closed_beads"
closed_status=$?
set -e
if [ "$closed_status" -eq 0 ] && ! jq -e 'type == "array"' "$closed_beads" >/dev/null 2>&1; then closed_status=1; fi
active_sessions=0
closed_sessions=0
for key in "${!session_count[@]}"; do
  count="${session_count[$key]}"; [ "$count" -gt 0 ] || continue
  target="${key#*|}"
  if [ "$closed_status" -eq 0 ] && jq -e --arg id "$target" 'any(.[]; .id == $id)' "$closed_beads" >/dev/null; then
    closed_sessions=$((closed_sessions + count)); continue
  fi
  active_sessions=$((active_sessions + count)); printf '  SESSION %s (%s unmatched start%s, started %s): %s\n' "$key" "$count" "$( [ "$count" -eq 1 ] || printf s)" "${session_timestamp[$key]}" "${session_detail[$key]}"
done
[ "$active_sessions" -ne 0 ] || printf '  no non-Mayor sessions in flight\n'
[ "$closed_sessions" -eq 0 ] || printf '  %s unmatched session start(s) omitted because the target bead is closed.\n' "$closed_sessions"
[ "$closed_status" -eq 0 ] || printf '  UNDETERMINED: could not query closed beads (bd exit %s); unmatched sessions may target closed work.\n' "$closed_status"
[ "$unmatchable" -eq 0 ] || printf '  UNDETERMINED: %s session event(s) lack seat or target\n' "$unmatchable"

live_locks=0
while IFS= read -r worktree; do
  lock="$worktree/.forge.lock"; [ -e "$lock" ] || continue
  # The Forge holds an exclusive lock. A non-blocking shared lock detects it
  # without opening another worktree's lock file for write.
  set +e
  flock -E 75 -n -s "$lock" -c true 2>/dev/null
  lock_status=$?
  set -e
  if [ "$lock_status" -eq 75 ]; then
    live_locks=$((live_locks + 1)); holder="$(cat "$worktree/.forge.lock.info" 2>/dev/null || printf 'holder metadata unavailable')"
    printf '  FORGE LOCK %s: %s\n' "$worktree" "$holder"
  elif [ "$lock_status" -ne 0 ]; then
    printf '  FORGE LOCK %s: UNDETERMINED (cannot inspect lock, flock exit %s)\n' "$worktree" "$lock_status"
  fi
done < <(git -C "$main_root" worktree list --porcelain | sed -n 's/^worktree //p')
[ "$live_locks" -ne 0 ] || printf '  no live Forge locks\n'

if [ -z "$since_override" ]; then
  # This timestamp is the window boundary the anchor names, not a backfill of
  # when emission happened. Anchoring at $now prevents an unreported gap while
  # the digest itself is rendering.
  "$emitter" digest.emitted "Digest emitted for event window since $since" -a harness -t digest.sh -T "$now"
fi
