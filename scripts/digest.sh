#!/bin/bash
# Deterministic Fort digest. Reads the event stream and Beads; it does not read
# memory or infer outcomes from the event text.
set -euo pipefail

usage() {
  printf 'Usage: %s [--since ISO-8601-timestamp]\n' "${0##*/}"
}

since_override=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --since)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      since_override="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
git_common="$(git -C "$repo_root" rev-parse --git-common-dir)"
case "$git_common" in
  /*) ;;
  *) git_common="$repo_root/$git_common" ;;
esac
main_root="$(cd "$(dirname "$git_common")" && pwd -P)"
events_dir="$main_root/fort/events"
emitter="$main_root/fort/scripts/emit.sh"
window_file="$(mktemp)"
events_file="$(mktemp)"
human_file="$(mktemp)"
beads_file="$(mktemp)"
in_flight_file="$(mktemp)"
landed_file="$(mktemp)"
trap 'rm -f "$window_file" "$events_file" "$human_file" "$beads_file" "$in_flight_file" "$landed_file"' EXIT

events_source() {
  find "$events_dir" -maxdepth 1 -type f -name 'events-*.jsonl' -print 2>/dev/null | sort | xargs -r -n1 cat
}

# Event timestamps are emitted by `date -Is` (offset form) as well as the Z
# form used by older fixtures. Keep this conversion in jq so event scans do not
# launch a `date` process for every row.
# shellcheck disable=SC2016 # jq program intentionally contains literal $ names.
jq_epoch='def epoch: try (capture("^(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?:\\.[0-9]+)?(?<zone>Z|(?<sign>[+-])(?<hour>[0-9]{2}):(?<minute>[0-9]{2}))$") as $m | ($m.date + "Z" | fromdateiso8601) as $utc | if $m.zone == "Z" then $utc else (($m.hour | tonumber) * 3600 + ($m.minute | tonumber) * 60) as $offset | $utc - (if $m.sign == "+" then $offset else -$offset end) end) catch empty;'

epoch() {
  [ -n "$1" ] || return 1
  date -d "$1" +%s 2>/dev/null
}

last_event_timestamp() {
  local jq_filter="$1"
  jq -r -s "$jq_epoch [.[] | select($jq_filter) | select(.ts | type == \"string\") | . + {event_epoch: (.ts | epoch)} | select(.event_epoch != null)] | if length == 0 then \"\" else max_by(.event_epoch).ts end" "$events_file"
}

declare -A last_verdict_details=()
load_last_verdict_details() {
  local target detail
  while IFS= read -r -d '' target && IFS= read -r -d '' detail; do
    last_verdict_details["$target"]="$detail"
  done < <(jq -jr -s "$jq_epoch [.[] | select(.category == \"review.verdict\" and (.target | type == \"string\") and (.ts | type == \"string\")) | . + {event_epoch: (.ts | epoch)} | select(.event_epoch != null)] | sort_by(.target, .event_epoch) | group_by(.target) | .[] | last | .target, \"\\u0000\", (.detail // \"\"), \"\\u0000\"" "$events_file")
}

events_source >"$events_file"

fallback_note=""
if [ -n "$since_override" ]; then
  since="$since_override"
else
  since="$(last_event_timestamp '.category == "digest.emitted"')"
  if [ -z "$since" ]; then
    since="$(last_event_timestamp '.category == "session.start" and .seat == "mayor"')"
    if [ -z "$since" ]; then
      printf 'digest: no digest.emitted or mayor session.start event exists. Supply --since.\n' >&2
      exit 1
    fi
    fallback_note="first run; using last mayor session.start"
  fi
fi

since_epoch="$(epoch "$since")" || { printf 'digest: invalid --since timestamp: %s\n' "$since" >&2; exit 2; }
now="$(date -Is)"
now_epoch="$(epoch "$now")"

jq -c --argjson since_epoch "$since_epoch" --argjson now_epoch "$now_epoch" "$jq_epoch select(.ts | type == \"string\") | . + {event_epoch: (.ts | epoch)} | select(.event_epoch != null and .event_epoch > \$since_epoch and .event_epoch <= \$now_epoch)" "$events_file" >"$window_file"

# A human label has no timestamp in Beads. The flag wrapper records the missing
# timestamp as decision.raised; creation date remains only for pre-wrapper
# labels that have no raise event anywhere in the stream.
human_status=0
set +e
bd -C "$main_root" human list --json >"$human_file"
human_status=$?
set -e
human_beads=()
closed_still_labelled=()
if [ "$human_status" -eq 0 ]; then
  # A closed bead keeps its labels, correctly: closing must not silently mutate
  # metadata, and the label is the record that this bead once needed Justin. So
  # `bd human list` answers "which beads carry the label", which is not the
  # question this section asks. Filter here rather than upstream (ForgeOs-eng3.8,
  # approved 2026-09-01). They are counted rather than dropped: a closed bead
  # still carrying the label is a label nobody removed, and hiding it silently
  # means nobody ever does.
  mapfile -t human_beads < <(jq -c '.[] | select((.status // "open") != "closed")' "$human_file")
  mapfile -t closed_still_labelled < <(jq -r '.[] | select((.status // "open") == "closed") | .id' "$human_file")
fi

# `bd human list --json` intentionally omits dependency information. Parent
# edges therefore come from the complete list shape, where a parent-child edge
# names its parent in `depends_on_id`.
beads_status=0
set +e
bd -C "$main_root" list --status all --limit 0 --json >"$beads_file"
beads_status=$?
set -e

event_lines() {
  local filter="$1"
  jq -r "$filter | .detail" "$window_file"
}

event_count() {
  local filter="$1"
  jq -s "[.[] | select($filter)] | length" "$window_file"
}

qualifying_count="$(event_count '.category != "digest.emitted"')"
if [ -z "$since_override" ] && [ "$qualifying_count" -eq 0 ]; then
  exit 0
fi

printf 'DECISIONS WAITING\n'
if [ "$human_status" -ne 0 ]; then
  printf '  UNAVAILABLE (bd exit %s)\n' "$human_status"
elif [ "${#human_beads[@]}" -eq 0 ]; then
  printf '%s\n' '  none'
else
  declare -A last_raised_epoch=()
  declare -A last_answered_epoch=()
  while IFS=$'\t' read -r target category event_epoch; do
    case "$category" in
      decision.raised) last_raised_epoch["$target"]="$event_epoch" ;;
      decision.answered) last_answered_epoch["$target"]="$event_epoch" ;;
    esac
  done < <(jq -r -s "$jq_epoch [.[] | select((.category == \"decision.raised\" or .category == \"decision.answered\") and (.target | type == \"string\") and (.ts | type == \"string\")) | . + {event_epoch: (.ts | epoch)} | select(.event_epoch != null)] | sort_by(.target, .category, .event_epoch) | group_by([.target, .category]) | .[] | last | [.target, .category, .event_epoch] | @tsv" "$events_file")

  raised_beads=()
  standing_beads=()
  inherited_suspects=()
  for bead in "${human_beads[@]}"; do
    id="$(jq -r '.id' <<<"$bead")"
    created_epoch="$(epoch "$(jq -r '.created_at // empty' <<<"$bead")")" || created_epoch=0
    raised_epoch="${last_raised_epoch[$id]:-}"
    answered_epoch="${last_answered_epoch[$id]:-}"
    if [ -n "$raised_epoch" ] && [ "$raised_epoch" -gt "$since_epoch" ] && [ "$raised_epoch" -le "$now_epoch" ]; then
      # A stale label must not make a decision outstanding after its answer.
      if [ -z "$answered_epoch" ] || [ "$answered_epoch" -le "$raised_epoch" ]; then
        raised_beads+=("$bead")
      fi
    elif [ -z "$raised_epoch" ]; then
      if [ "$created_epoch" -gt "$since_epoch" ] && [ "$created_epoch" -le "$now_epoch" ]; then
        raised_beads+=("$bead")
      else
        standing_beads+=("$bead")
      fi
    else
      standing_beads+=("$bead")
    fi

    parent=""
    if [ "$beads_status" -eq 0 ]; then
      parent="$(jq -r --arg child "$(jq -r '.id' <<<"$bead")" '[.[] | select(.id == $child) | .dependencies[]? | select(.type == "parent-child") | .depends_on_id] | first // empty' "$beads_file")"
    fi
    if [ -n "$parent" ] && bd -C "$main_root" show "$parent" --json | jq -e '(if type == "array" then .[0] else . end | .labels // []) | index("human") != null' >/dev/null; then
      inherited_suspects+=("$(jq -r '.id' <<<"$bead")")
    fi
  done

  if [ "${#raised_beads[@]}" -gt 0 ]; then
    printf '%s\n' '  RAISED THIS RUN'
    for bead in "${raised_beads[@]}"; do
      id="$(jq -r '.id' <<<"$bead")"
      title="$(jq -r '.title' <<<"$bead")"
      status="$(jq -r '.status // "open"' <<<"$bead")"
      if [ -z "${last_raised_epoch[$id]:-}" ]; then
        printf '    %s [%s] %s (no raise event; by creation date)\n' "$id" "$status" "$title"
      else
        printf '    %s [%s] %s\n' "$id" "$status" "$title"
      fi
    done
  fi

  if [ "${#standing_beads[@]}" -gt 0 ]; then
    # Timestamps with offsets must be compared as epochs. Missing or invalid
    # timestamps sort last rather than falsely becoming the oldest standing row.
    mapfile -t oldest_standing < <(
      for bead in "${standing_beads[@]}"; do
        created_epoch="$(epoch "$(jq -r '.created_at // empty' <<<"$bead")")" || created_epoch=9223372036854775807
        printf '%s\t%s\n' "$created_epoch" "$(base64 -w 0 <<<"$bead")"
      done | sort -s -n -k1,1 | head -n 3 | cut -f2-
    )
    oldest_summary=""
    for encoded in "${oldest_standing[@]}"; do
      bead="$(base64 --decode <<<"$encoded")"
      id="$(jq -r '.id' <<<"$bead")"
      created_epoch="$(epoch "$(jq -r '.created_at // empty' <<<"$bead")")" || created_epoch="$now_epoch"
      age_days=$(( (now_epoch - created_epoch) / 86400 ))
      if [ -n "$oldest_summary" ]; then
        oldest_summary+=", "
      fi
      oldest_summary+="$id (${age_days}d)"
    done
    printf '  Also standing: %s blocked on you; oldest: %s.\n' "${#standing_beads[@]}" "$oldest_summary"
  fi

  if [ "${#inherited_suspects[@]}" -gt 0 ]; then
    printf '  %s may be inherited labels: %s\n' "${#inherited_suspects[@]}" "$(printf '%s, ' "${inherited_suspects[@]}" | sed 's/, $//')"
  fi
fi

if [ "${#closed_still_labelled[@]}" -gt 0 ]; then
  printf '  Label hygiene: %s CLOSED bead(s) still carry the human label: %s\n' \
    "${#closed_still_labelled[@]}" "$(printf '%s, ' "${closed_still_labelled[@]}" | sed 's/, $//')"
fi

if [ -n "$fallback_note" ]; then
  printf 'WINDOW\n  %s (%s)\n' "$since" "$fallback_note"
fi

if [ "$(event_count '.category == "merge" or .category == "deploy" or .category == "bead.closed"')" -gt 0 ]; then
  printf 'SHIPPED\n'
  event_lines 'select(.category == "merge" or .category == "deploy" or .category == "bead.closed")' | sed 's/^/  /'
fi

in_flight_status=0
set +e
bd -C "$main_root" list --status=in_progress --limit 0 --json >"$in_flight_file"
in_flight_status=$?
set -e
in_flight=()
in_flight_rows=()
if [ "$in_flight_status" -eq 0 ]; then
  mapfile -t in_flight < <(jq -c '.[]' "$in_flight_file")
  mapfile -t in_flight_rows < <(jq -r '.[] | [.id, .title] | @tsv' "$in_flight_file")
  load_last_verdict_details
fi
if [ "$in_flight_status" -ne 0 ]; then
  printf 'IN FLIGHT: UNAVAILABLE (bd exit %s)\n' "$in_flight_status"
elif [ "${#in_flight[@]}" -gt 0 ]; then
  printf 'IN FLIGHT\n'
  for row in "${in_flight_rows[@]}"; do
    id="${row%%$'\t'*}"
    title="${row#*$'\t'}"
    verdict_detail="${last_verdict_details[$id]:-}"
    if [ -n "$verdict_detail" ]; then
      printf '  %s: %s\n    %s\n' "$id" "$title" "$verdict_detail"
    else
      printf '  %s: %s\n' "$id" "$title"
    fi
  done
fi

# LANDED BUT OPEN (ForgeOs-eng3.8.1, approved by Justin 2026-09-01).
#
# The label-hygiene line above catches a CLOSED bead that kept its label. This
# catches the larger and quieter case: a bead whose work is already merged and
# which nobody closed. Three instances on 2026-09-01 alone -- ForgeOs-b0vj.5,
# ForgeOs-sk3c.21 and (on 08-31) ForgeOs-eng3.4. sk3c.21 is why this exists:
# merged 2026-08-28 with gate 1 signed, it sat in the decision queue for four
# days as an outstanding gate-1 auth review that had already happened, and
# JUSTIN caught it from memory when no queue could. A digest that reports
# something the reader can disprove from his own experience costs the trust he
# needs to act on the rest of it.
#
# REPORTS, NEVER CLOSES. A branch contained in main is strong evidence the work
# landed and is NOT proof the bead is done: on the same evening, three readers
# agreed ForgeOs-b0vj.10.1 was moot because the method it was filed against had
# been deleted, and that bead's own text said one of its two findings was
# regression cover for four other call sites. Surface candidates; let a person
# close them with a reason.
landed_open=()
if git -C "$main_root" rev-parse --verify --quiet main >/dev/null; then
  # One ref enumeration rather than a git call per bead: most open beads have no
  # branch at all, and the intersection is what we are actually after.
  declare -A bead_branch_exists=()
  while IFS= read -r ref; do
    [ -n "$ref" ] && bead_branch_exists["${ref#bead/}"]=1
  done < <(git -C "$main_root" for-each-ref --format='%(refname:short)' 'refs/heads/bead/*' 2>/dev/null)

  if [ "${#bead_branch_exists[@]}" -gt 0 ]; then
    set +e
    bd -C "$main_root" list --status=open --limit 0 --json >"$landed_file" 2>/dev/null
    open_status=$?
    set -e
    candidates=()
    if [ "$open_status" -eq 0 ]; then
      mapfile -t candidates < <(jq -r '.[] | [.id, .title] | @tsv' "$landed_file" 2>/dev/null)
    fi
    # in_flight was already fetched above; reuse it rather than asking bd twice.
    candidates+=("${in_flight_rows[@]:-}")

    for row in "${candidates[@]:-}"; do
      [ -n "$row" ] || continue
      id="${row%%$'\t'*}"
      title="${row#*$'\t'}"
      suffix="${id##*-}"
      [ -n "${bead_branch_exists[$suffix]:-}" ] || continue
      # --is-ancestor exits 1 for "no", which set -e would treat as fatal.
      if git -C "$main_root" merge-base --is-ancestor "bead/$suffix" main 2>/dev/null; then
        landed_open+=("$id: $title")
      fi
    done
  fi
fi
if [ "${#landed_open[@]}" -gt 0 ]; then
  printf 'LANDED BUT OPEN (%s) — branch already contained in main; verify and close with a reason\n' "${#landed_open[@]}"
  printf '  %s\n' "${landed_open[@]}"
fi

if [ "$(event_count '.category == "review.verdict"')" -gt 0 ]; then
  printf 'GATES\n'
  event_lines 'select(.category == "review.verdict")' | sed 's/^/  /'
fi

if [ "$(event_count '.category == "incident" or .category == "incident.corrected" or .category == "verify.fail" or .category == "verify.blocked"')" -gt 0 ]; then
  printf 'TROUBLE\n'
  event_lines 'select(.category == "incident" or .category == "incident.corrected" or .category == "verify.fail" or .category == "verify.blocked")' | sed 's/^/  /'
fi

if git -C "$main_root" rev-parse --verify --quiet origin/main >/dev/null; then
  mapfile -t unpushed < <(git -C "$main_root" log origin/main..main --oneline)
  if [ "${#unpushed[@]}" -gt 0 ]; then
    printf 'UNPUSHED (%s)\n' "${#unpushed[@]}"
    printf '  %s\n' "${unpushed[@]}"
  fi
fi

# PERMISSION PROMPTS (ForgeOs-758): the prompt-telemetry hook appends one row per
# surviving permission prompt to fort/telemetry/prompts.jsonl. Reviewed once by
# hand on 2026-09-17 (137 rows since 08-04, 21 since 09-01, no allowlist change
# worth a gate-6 amendment: the survivors are compound shells and bd-comment
# heredocs the classifier cannot read). This line keeps the count in front of a
# reader every digest so a silent hook (zero rows while prompts are being
# answered by hand) and a prompt storm are both visible. Rows in the window only.
prompts_file="$main_root/fort/telemetry/prompts.jsonl"
if [ -r "$prompts_file" ]; then
  prompt_count="$(jq -c --argjson since_epoch "$since_epoch" --argjson now_epoch "$now_epoch" "$jq_epoch select(.ts | type == \"string\") | . + {event_epoch: (.ts | epoch)} | select(.event_epoch != null and .event_epoch > \$since_epoch and .event_epoch <= \$now_epoch)" "$prompts_file" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${prompt_count:-0}" -gt 0 ]; then
    printf 'PERMISSION PROMPTS (%s) — fort/telemetry/prompts.jsonl rows in this window; cluster them before proposing an allowlist change (gate 6)\n' "$prompt_count"
  fi
fi

if [ -z "$since_override" ]; then
  "$emitter" digest.emitted "Digest emitted for event window since $since" -a harness -t digest.sh
fi
