#!/bin/bash
# Deterministic Fort digest. Reads the event stream and Beads; it does not read
# memory or infer outcomes from the event text.
set -euo pipefail

usage() { printf 'Usage: %s [--by-subject] [--since ISO-8601-timestamp]\n' "${0##*/}"; }

since_override=""
by_subject=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --by-subject) by_subject=1; shift ;;
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
all_events="$(mktemp)"; timestamped_events="$(mktemp)"; window_events="$(mktemp)"; closed_beads="$(mktemp)"; timestamp_report="$(mktemp)"; audit_merges="$(mktemp)"; audit_coverage="$(mktemp)"; live_gate_beads="$(mktemp)"; all_beads="$(mktemp)"; gate_one="$(mktemp)"; gate_two="$(mktemp)"; gate_three="$(mktemp)"
trap 'rm -f "$all_events" "$timestamped_events" "$window_events" "$closed_beads" "$timestamp_report" "$audit_merges" "$audit_coverage" "$live_gate_beads" "$all_beads" "$gate_one" "$gate_two" "$gate_three"' EXIT
max_decisions_per_action=5
boundary_tolerance_seconds=120

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
set +e
bd -C "$main_root" list --status=open,in_progress --label=gate-1 --json >"$gate_one"; gate_one_status=$?
bd -C "$main_root" list --status=open,in_progress --label=gate-2 --json >"$gate_two"; gate_two_status=$?
bd -C "$main_root" list --status=open,in_progress --label=gate-3 --json >"$gate_three"; gate_three_status=$?
set -e
live_gate_status=$(( gate_one_status != 0 ? gate_one_status : gate_two_status != 0 ? gate_two_status : gate_three_status ))
if [ "$live_gate_status" -eq 0 ]; then jq -s 'add | unique_by(.id)' "$gate_one" "$gate_two" "$gate_three" >"$live_gate_beads"; fi
if [ "$live_gate_status" -ne 0 ]; then
  printf '  ACTION GROUPS: UNAVAILABLE (bd exit %s)\n' "$live_gate_status"
elif ! jq -e 'type == "array"' "$live_gate_beads" >/dev/null 2>&1; then
  printf '  ACTION GROUPS: UNAVAILABLE (bd returned invalid JSON)\n'
else
  node - "$live_gate_beads" "$max_decisions_per_action" <<'NODE'
const fs = require("node:fs");
const [beadsPath, limitArg] = process.argv.slice(2);
const beads = JSON.parse(fs.readFileSync(beadsPath, "utf8"));
const limit = Number(limitArg);
const groups = [
  ["act-decide", "DECIDE"],
  ["act-regent", "SUMMON REGENT"],
  ["act-host", "ACT ON HOST"],
  [null, "ACTION NOT YET CLASSIFIED"],
];
const actionOf = (bead) => groups.slice(0, 3).find(([label]) => bead.labels?.includes(label))?.[0] ?? null;
const gateTag = (bead) => (bead.labels ?? []).filter((label) => /^gate-[123]$/.test(label)).sort().join(", ") || "gate unknown";
for (const [action, heading] of groups) {
  const members = beads.filter((bead) => actionOf(bead) === action)
    .sort((left, right) => String(right.updated_at ?? right.created_at ?? "").localeCompare(String(left.updated_at ?? left.created_at ?? "")));
  if (members.length === 0) {
    console.log(`  ${heading}: no decisions waiting`);
    continue;
  }
  const shown = members.slice(0, limit);
  console.log(`  ${heading}: ${members.length} decision(s) waiting (showing ${shown.length} of ${members.length}, most recently updated)`);
  for (const bead of shown) console.log(`    ${bead.title ?? "untitled"} [${bead.id ?? "UNKNOWN"}; ${bead.status ?? "open"}; ${gateTag(bead)}]`);
  if (members.length > shown.length) console.log(`    ${members.length - shown.length} decision(s) elided; full count is ${members.length}.`);
}
NODE
fi

if [ "$by_subject" -eq 1 ]; then
  printf 'BY SUBJECT\n'
  set +e
  bd -C "$main_root" list --all --json >"$all_beads"
  all_beads_status=$?
  set -e
  if [ "$all_beads_status" -ne 0 ]; then
    printf '  SUBJECT VIEW: UNAVAILABLE (bd exit %s)\n' "$all_beads_status"
  elif ! jq -e 'type == "array"' "$all_beads" >/dev/null 2>&1; then
    printf '  SUBJECT VIEW: UNAVAILABLE (bd returned invalid JSON)\n'
  elif [ "$live_gate_status" -ne 0 ]; then
    printf '  SUBJECT VIEW: UNAVAILABLE (the live gate queue is unavailable)\n'
  else
    node - "$live_gate_beads" "$all_beads" <<'NODE'
const fs = require("node:fs");
const [livePath, allPath] = process.argv.slice(2);
const live = JSON.parse(fs.readFileSync(livePath, "utf8"));
const all = JSON.parse(fs.readFileSync(allPath, "utf8"));
const byId = new Map(all.map((bead) => [bead.id, bead]));
const rootOf = (bead) => {
  const seen = new Set(); let current = bead;
  while (current?.parent && byId.has(current.parent) && !seen.has(current.parent)) { seen.add(current.parent); current = byId.get(current.parent); }
  return current ?? bead;
};
const groups = new Map();
for (const bead of live) {
  const root = rootOf(bead);
  if (!groups.has(root.id)) groups.set(root.id, { root, members: [] });
  groups.get(root.id).members.push(bead);
}
const tagFor = (bead) => {
  const labels = bead.labels ?? [];
  const action = ["act-decide", "act-regent", "act-host"].find((label) => labels.includes(label)) ?? "action not yet classified";
  const gate = labels.filter((label) => /^gate-[123]$/.test(label)).sort().join(", ") || "gate unknown";
  return `${action}; ${gate}`;
};
for (const { root, members } of [...groups.values()].sort((left, right) => String(left.root.title ?? "").localeCompare(String(right.root.title ?? "")))) {
  const descendants = all.filter((bead) => rootOf(bead).id === root.id);
  const closed = descendants.filter((bead) => bead.status === "closed").length;
  const blockerIds = members.flatMap((member) => (member.dependencies ?? []).filter((dependency) => dependency.type === "blocks").map((dependency) => dependency.depends_on_id));
  const blockers = blockerIds.map((id) => byId.get(id)).filter(Boolean);
  const blockerDataUnavailable = blockerIds.some((id) => !byId.has(id));
  const blockerText = blockerDataUnavailable ? "; blocker data unavailable" : blockers.length ? `; blocked by: ${[...new Set(blockers.map((blocker) => blocker.title ?? "untitled"))].join("; ")}` : "";
  console.log(`  ${root.title ?? "untitled"} [${root.id ?? "UNKNOWN"}] — ${closed}/${descendants.length} done${blockerText}`);
  for (const member of members.sort((left, right) => String(left.title ?? "").localeCompare(String(right.title ?? "")))) {
    if (member.id === root.id && root.issue_type === "epic") continue;
    console.log(`    ${member.title ?? "untitled"} [${member.id ?? "UNKNOWN"}; ${member.status ?? "open"}; ${tagFor(member)}]`);
  }
}
if (groups.size === 0) console.log("  no decisions waiting");
NODE
  fi
fi

printf 'SHIPPED\n'
if [ "$(jq -s '[.[] | select(.category == "merge" or .category == "bead.closed" or .category == "bead.filed")] | length' "$window_events")" -eq 0 ]; then
  printf '  no merge/close/file events in the selected window\n'
else
  print_window_events 'select(.category == "merge" or .category == "bead.closed" or .category == "bead.filed")'
fi

# Audit coverage compares artifacts, including a small identity-matched margin
# at each edge. Committer and event timestamps can differ by seconds; a matching
# pair that straddles an edge is excluded from this window's count rather than
# reported once as a missing event and again as an unmatched event.
printf 'AUDIT COVERAGE\n'
audit_ref='refs/heads/main'
if ! git -C "$main_root" show-ref --verify --quiet "$audit_ref"; then audit_ref='HEAD'; fi
audit_since="$(date -d "$since - $boundary_tolerance_seconds seconds" -Is)"
audit_until="$(date -d "$now + $boundary_tolerance_seconds seconds" -Is)"
if git -C "$main_root" rev-parse --verify --quiet "$audit_ref" >/dev/null; then
  git -C "$main_root" log "$audit_ref" --merges --since="$audit_since" --until="$audit_until" --format='%H%x09%ct%x09%s' |
    node -e '
      let input = "";
      process.stdin.setEncoding("utf8");
      process.stdin.on("data", (chunk) => { input += chunk; });
      process.stdin.on("end", () => {
        for (const line of input.split("\n")) {
          if (!line) continue;
          const [commit, epoch, subject = ""] = line.split("\t", 3);
          process.stdout.write(JSON.stringify({ commit, epoch: Number(epoch), subject }) + "\n");
        }
      });
    ' >"$audit_merges"
else
  : >"$audit_merges"
fi
closed_status=0
set +e
bd -C "$main_root" list --status=closed --json >"$closed_beads"
closed_status=$?
set -e
if [ "$closed_status" -eq 0 ] && ! jq -e 'type == "array"' "$closed_beads" >/dev/null 2>&1; then closed_status=1; fi

node - "$timestamped_events" "$audit_merges" "$closed_beads" "$since_epoch" "$now_epoch" "$boundary_tolerance_seconds" "$closed_status" <<'NODE' >"$audit_coverage"
const [eventsPath, mergesPath, closedPath, since, now, tolerance, closedStatus] = process.argv.slice(2);
const readJsonLines = (path) => require("node:fs").readFileSync(path, "utf8").split("\n").filter(Boolean).map(JSON.parse);
const events = readJsonLines(eventsPath);
const merges = readJsonLines(mergesPath);
const lower = Number(since);
const upper = Number(now);
const margin = Number(tolerance);
const inside = (epoch) => epoch > lower && epoch <= upper;
const near = (epoch) => epoch > lower - margin && epoch <= upper + margin;
const mergeTarget = (subject) => /^Merge (fortkit-[A-Za-z0-9.-]+):/.exec(subject)?.[1] ?? null;
const eventMatchesMerge = (event, merge) =>
  event.target === merge.commit || event.payload?.mergeCommit === merge.commit ||
  (event.target === mergeTarget(merge.subject) && !event.payload?.mergeCommit);
const crossBoundaryPairs = (subjects, records, matches) => {
  const used = new Set();
  let subjectInside = subjects.filter((subject) => inside(subject.epoch)).length;
  let recordInside = records.filter((record) => inside(record._epoch)).length;
  let pairs = 0;
  for (const subject of subjects) {
    for (let index = 0; index < records.length; index += 1) {
      const record = records[index];
      if (used.has(index) || !near(record._epoch) || inside(subject.epoch) === inside(record._epoch)) continue;
      if (Math.abs(subject.epoch - record._epoch) > margin || !matches(record, subject)) continue;
      used.add(index);
      if (inside(record._epoch)) recordInside -= 1;
      if (inside(subject.epoch)) subjectInside -= 1;
      pairs += 1;
      break;
    }
  }
  return { subjects: subjectInside, records: recordInside, pairs };
};
const mergeCoverage = crossBoundaryPairs(
  merges.filter((merge) => near(merge.epoch)),
  events.filter((event) => event.category === "merge" && near(event._epoch)),
  eventMatchesMerge,
);
let closedCoverage = null;
if (Number(closedStatus) === 0) {
  const closed = JSON.parse(require("node:fs").readFileSync(closedPath, "utf8"))
    .map((bead) => ({ id: bead.id, epoch: Math.floor(Date.parse(bead.closed_at) / 1000) }))
    .filter((bead) => bead.id && Number.isFinite(bead.epoch) && near(bead.epoch));
  closedCoverage = crossBoundaryPairs(
    closed,
    events.filter((event) => event.category === "bead.closed" && near(event._epoch)),
    (event, bead) => event.target === bead.id,
  );
}
process.stdout.write(JSON.stringify({ mergeCoverage, closedCoverage }));
NODE

merge_commits="$(jq '.mergeCoverage.subjects' "$audit_coverage")"
merge_events="$(jq '.mergeCoverage.records' "$audit_coverage")"
merge_pairs="$(jq '.mergeCoverage.pairs' "$audit_coverage")"
printf '  boundary tolerance: %ss; %s merge event%s matched by identity across a window edge\n' "$boundary_tolerance_seconds" "$merge_pairs" "$( [ "$merge_pairs" -eq 1 ] || printf s)"
printf '  merge events: %s of %s commits\n' "$merge_events" "$merge_commits"
if [ "$merge_events" -lt "$merge_commits" ]; then
  printf '  WARNING: %s merge commits in window, %s merge events — the stream is missing %s.\n' "$merge_commits" "$merge_events" "$((merge_commits - merge_events))"
elif [ "$merge_events" -gt "$merge_commits" ]; then
  printf '  WARNING: %s merge events in window, %s merge commits — the stream has %s unmatched event(s).\n' "$merge_events" "$merge_commits" "$((merge_events - merge_commits))"
fi

if [ "$closed_status" -eq 0 ]; then
  closed_window="$(jq '.closedCoverage.subjects' "$audit_coverage")"
  closed_events="$(jq '.closedCoverage.records' "$audit_coverage")"
  closed_pairs="$(jq '.closedCoverage.pairs' "$audit_coverage")"
  printf '  boundary tolerance: %ss; %s bead.closed event%s matched by identity across a window edge\n' "$boundary_tolerance_seconds" "$closed_pairs" "$( [ "$closed_pairs" -eq 1 ] || printf s)"
  printf '  bead.closed events: %s of %s closed beads\n' "$closed_events" "$closed_window"
  if [ "$closed_events" -lt "$closed_window" ]; then
    printf '  WARNING: %s closed beads in window, %s bead.closed events — the stream is missing %s.\n' "$closed_window" "$closed_events" "$((closed_window - closed_events))"
  elif [ "$closed_events" -gt "$closed_window" ]; then
    printf '  WARNING: %s bead.closed events in window, %s closed beads — the stream has %s unmatched event(s).\n' "$closed_events" "$closed_window" "$((closed_events - closed_window))"
  fi
else
  printf '  bead.closed events: UNAVAILABLE (bd exit %s)\n' "$closed_status"
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
