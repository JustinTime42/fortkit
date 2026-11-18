#!/bin/bash
# Proofdelve loop watchdog: alert the Overseer when nobody is minding the fort.
# ForgeOs-dycc9 and ForgeOs-76uob.6. Regent sitting 2026-11-16, gate 6, the
# Overseer present. No model. Fired every 15 minutes by
# fort/systemd/proofdelve-loop-watchdog.timer.
#
# WHAT IT WATCHES. Three conditions, each with a duration:
#
#   mayor-silent-with-work   Open fleet-safe, fleet-escalated or mayor-review
#                            beads exist, and the newest event by actor marrek
#                            in fort/events is 60 or more minutes old.
#   mayor-silent             The newest event by actor marrek is 6 or more hours
#                            old, whatever the board holds. This covers a closed
#                            session and the /loop cron's 7-day expiry.
#   pool-dry                 No fleet-safe bead is ready or in progress, and that
#                            has been true for 2 or more hours, while open work
#                            that is not blocked and not the Overseer's exists.
#                            An idle fort with nothing open does not alert.
#
# HOW AN ALERT REACHES HIM (the Overseer's choice, recorded on ForgeOs-dycc9,
# 2026-11-16). The supervisor's own path is a journal line and a stream event,
# and with the Mayor silent nobody reads either. So an alert does three things:
#   1. emits one watcher.alert event (actor watcher:loop), the durable record;
#   2. files ONE bead assigned to justin with an ASK line, which puts it on the
#      Civ Keep's needs-you board;
#   3. fires notify-send on this desktop, best effort.
#
# ONE ALERT PER EPISODE. Each condition has a latch file in the state directory.
# A condition that is true and latched is silent. When it stops being true the
# watchdog comments on the alert's bead, closes it, emits watcher.cleared and
# removes the latch, so the next episode alerts again. The timer fires 96 times a
# day; an alarm that fired with it would train its reader to ignore it
# (ForgeOs-76uob.6 criterion 4, the ForgeOs-eng3.9 failure).
#
# WHAT "WORK" MEANS FOR pool-dry. `bd ready` (open and not blocked), minus
# epics, minus beads assigned to justin, minus beads labelled human or
# regent-docket. Those four are work no fleet and no Mayor can route, and
# counting them would make the alarm permanent. This is a count for an alarm.
# It decides nothing about any bead and starts nothing (ForgeOs-czhb: no second
# dispatchable()).
#
# WHAT IT NEVER DOES. It never writes HALT, never starts or stops a run, never
# touches the fleet's state directory (it reads whether HALT exists, to say so
# in the alert). It reports (ForgeOs-76uob.6 criterion 5).
#
# WHEN bd WILL NOT ANSWER. The two conditions that need the board are skipped
# for that firing with one stderr line and exit 64; their latches are left as
# they were. No answer is neither an alert nor a clear. mayor-silent needs only
# the event stream and is still evaluated.
#
# IT REFUSES FROM A MASKED SEAT, before reading anything, as the supervisor does.
#
# Usage:
#   fort/scripts/loop-watchdog.sh               one firing, as the timer does it
#   fort/scripts/loop-watchdog.sh --status      print what it sees and the latches; changes nothing
#   fort/scripts/loop-watchdog.sh --test-alert  send ONE clearly marked test alert down all
#                                               three paths; touches no latch
# Exit codes: 0 evaluated. 64 refused, or bd would not answer (see above).
#
# Environment (harness use; the timer sets none of these):
#   WATCHDOG_ROOT   the fort root. When set, WATCHDOG_STATE and WATCHDOG_FLEET_STATE
#                   must be set too, or the script refuses: a fixture root must
#                   never be paired with the real state directories.
#   WATCHDOG_STATE  latch directory. Default ~/.local/share/proofdelve-watchdog,
#                   which is not among the rw grants of the full posture.
#   WATCHDOG_FLEET_STATE  the fleet's state directory (read only, for HALT).
#   WATCHDOG_NOW    "now" as epoch seconds.
#   WATCHDOG_WORK_SILENT_MIN, WATCHDOG_SILENT_MIN, WATCHDOG_DRY_MIN
#                   the three durations in minutes (60, 360, 120).
# bd, notify-send and the fort's emit.sh are found the ordinary way, so a
# harness stubs them on PATH and in its fixture root.

set -euo pipefail

if [ -n "${FORT_MASKED:-}" ]; then
  echo "loop-watchdog.sh: REFUSED: this is a masked seat session (FORT_MASKED=${FORT_MASKED}). The watchdog runs from its systemd user timer or the Overseer's terminal, never from a seat." >&2
  exit 64
fi

if [ -n "${WATCHDOG_ROOT:-}" ]; then
  if [ -z "${WATCHDOG_STATE:-}" ] || [ -z "${WATCHDOG_FLEET_STATE:-}" ]; then
    echo "loop-watchdog.sh: REFUSED: WATCHDOG_ROOT is set without WATCHDOG_STATE and WATCHDOG_FLEET_STATE. A fixture root is never paired with the real state directories." >&2
    exit 64
  fi
fi
root="${WATCHDOG_ROOT:-/home/justin/dev/ForgeOs}"
state="${WATCHDOG_STATE:-$HOME/.local/share/proofdelve-watchdog}"
fleet_state="${WATCHDOG_FLEET_STATE:-$HOME/.local/state/proofdelve-fleet}"
events_dir="$root/fort/events"
emit_bin="$root/fort/scripts/emit.sh"
now="${WATCHDOG_NOW:-$(date +%s)}"
work_silent_min="${WATCHDOG_WORK_SILENT_MIN:-60}"
silent_min="${WATCHDOG_SILENT_MIN:-360}"
dry_min="${WATCHDOG_DRY_MIN:-120}"
actor="watcher:loop"
overseer="justin"
mayor="marrek"

mode=run
case "${1:-}" in
  "") ;;
  --status) mode=status ;;
  --test-alert) mode="test" ;;
  -h|--help) awk 'NR>1 && /^[^#]/{exit} NR>1{print}' "$0"; exit 0 ;;
  *) echo "loop-watchdog.sh: unknown argument: $1" >&2; exit 64 ;;
esac

mkdir -p "$state"
iso() { date -Is -d "@$1"; }
emit() { ( cd "$root" && "$emit_bin" "$@" ) >/dev/null 2>&1 || true; }

# --- what it sees -----------------------------------------------------------

# The newest event by the Mayor, as epoch seconds; empty when the last 14 day
# files hold none. Selected on the actor FIELD, never grepped: a name quoted in
# another event's detail is not an event by that actor. An event stamped later
# than now is ignored, so a mistyped -T cannot hide a silence.
mayor_last="$(printf '%s\n' "$events_dir"/events-*.jsonl | sort | tail -14 | python3 -c '
import json, sys
from datetime import datetime
who = sys.argv[1]; now = float(sys.argv[2]); best = None
for path in sys.stdin.read().split():
    try:
        with open(path) as fh:
            for line in fh:
                try:
                    e = json.loads(line)
                    if e.get("actor") != who: continue
                    t = datetime.fromisoformat(e.get("ts")).timestamp()
                except Exception: continue
                if t > now + 300: continue
                if best is None or t > best: best = t
    except OSError: continue
if best is not None: print(int(best))
' "$mayor" "$now" 2>/dev/null || true)"
if [ -n "$mayor_last" ]; then
  silent_for=$(( (now - mayor_last) / 60 )); [ "$silent_for" -lt 0 ] && silent_for=0
  mayor_last_iso="$(iso "$mayor_last")"
else
  silent_for=999999; mayor_last_iso="none in the last 14 day files"
fi

# The board. Each count is a number, or empty when bd would not answer.
bd_count() {  # $1 bd subcommand (list|ready), the rest passed to bd; $BD_FILTER names which beads count
  local sub="$1"; shift
  local out
  out="$(bd -C "$root" "$sub" --limit 0 --json "$@" 2>/dev/null)" || return 1
  printf '%s' "$out" | python3 -c '
import json, sys
which = sys.argv[1]; overseer = sys.argv[2]
raw = sys.stdin.read().strip()
if raw in ("", "null"): print(0); sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict): d = d.get("data", d)
if not isinstance(d, list): sys.exit(1)
n = 0
for b in d:
    status = b.get("status")
    labels = set(b.get("labels") or [])
    if which == "live":          # not closed
        if status == "closed": continue
    elif which == "pool":        # ready or in progress
        if status not in ("open", "in_progress"): continue
    elif which == "routable":    # work a Mayor could route
        if b.get("issue_type") == "epic": continue
        if b.get("assignee") == overseer: continue
        if labels & {"human", "regent-docket"}: continue
    n += 1
print(n)
' "$BD_FILTER" "$overseer" 2>/dev/null
}
board_ok=1
n_safe=""; n_esc=""; n_review=""; n_pool_ready=""; n_pool_busy=""; n_routable=""
BD_FILTER=live     n_safe="$(bd_count list --status open,in_progress --label fleet-safe)" || board_ok=0
BD_FILTER=live     n_esc="$(bd_count list --status open,in_progress --label fleet-escalated)" || board_ok=0
BD_FILTER=live     n_review="$(bd_count list --status open,in_progress --label mayor-review)" || board_ok=0
BD_FILTER=pool     n_pool_ready="$(bd_count ready --label fleet-safe)" || board_ok=0
BD_FILTER=pool     n_pool_busy="$(bd_count list --status in_progress --label fleet-safe)" || board_ok=0
BD_FILTER=routable n_routable="$(bd_count ready)" || board_ok=0
for v in "$n_safe" "$n_esc" "$n_review" "$n_pool_ready" "$n_pool_busy" "$n_routable"; do
  case "$v" in ''|*[!0-9]*) board_ok=0 ;; esac
done

halt_note="no HALT file"
[ -e "$fleet_state/HALT" ] && halt_note="the fleet is HALTED ($fleet_state/HALT is present)"

# pool-dry needs a duration, so the moment the pool was first seen dry is kept.
dry_file="$state/pool-dry.since"
dry_since=""
if [ "$board_ok" = 1 ]; then
  if [ "$n_pool_ready" = 0 ] && [ "$n_pool_busy" = 0 ]; then
    dry_since="$(cat "$dry_file" 2>/dev/null || true)"
    case "$dry_since" in ''|*[!0-9]*) dry_since="$now"; [ "$mode" = run ] && printf '%s\n' "$now" > "$dry_file" ;; esac
  else
    [ "$mode" = run ] && rm -f "$dry_file"
  fi
fi

# --- the three conditions: true, false, or unknown ---------------------------
c_work=unknown; c_silent=false; c_dry=unknown
why_work=""; why_silent=""; why_dry=""
[ "$silent_for" -ge "$silent_min" ] && c_silent=true
why_silent="No event by the Mayor ($mayor) for $silent_for minutes (newest: $mayor_last_iso; the alarm is $silent_min minutes). The Mayor session is closed or its /loop cron has expired. $halt_note."
if [ "$board_ok" = 1 ]; then
  n_work=$((n_safe + n_esc + n_review))
  c_work=false
  [ "$n_work" -gt 0 ] && [ "$silent_for" -ge "$work_silent_min" ] && c_work=true
  why_work="The board holds $n_work bead(s) waiting on the fleet or the Mayor ($n_safe fleet-safe, $n_esc fleet-escalated, $n_review mayor-review) and there has been no event by the Mayor ($mayor) for $silent_for minutes (newest: $mayor_last_iso; the alarm is $work_silent_min minutes). $halt_note."
  c_dry=false
  if [ -n "$dry_since" ] && [ "$n_routable" -gt 0 ] && [ $(( (now - dry_since) / 60 )) -ge "$dry_min" ]; then c_dry=true; fi
  why_dry="No fleet-safe bead has been ready or in progress since $( [ -n "$dry_since" ] && iso "$dry_since" || echo never ) (the alarm is $dry_min minutes), while $n_routable open bead(s) that are not blocked, not yours and not regent-docket wait to be routed. The fleet has nothing to dispatch. $halt_note."
fi

if [ "$mode" = status ]; then
  echo "loop-watchdog status at $(iso "$now")"
  echo "  newest Mayor event: $mayor_last_iso ($silent_for min ago)"
  if [ "$board_ok" = 1 ]; then
    echo "  board: fleet-safe=$n_safe fleet-escalated=$n_esc mayor-review=$n_review pool(ready=$n_pool_ready, in_progress=$n_pool_busy) routable=$n_routable"
  else
    echo "  board: bd would not answer"
  fi
  echo "  $halt_note; pool dry since: $( [ -n "$dry_since" ] && iso "$dry_since" || echo 'not dry, or unknown' )"
  for c in mayor-silent-with-work:$c_work mayor-silent:$c_silent pool-dry:$c_dry; do
    l="$state/latch-${c%%:*}"
    echo "  ${c%%:*}: ${c##*:}$( [ -f "$l" ] && printf ' (latched: %s)' "$(tr '\n' ' ' < "$l")" )"
  done
  exit 0
fi

# --- alerting ----------------------------------------------------------------
file_bead() {  # $1 title, $2 body text, $3 ASK line -> prints the bead id, or nothing
  local id="" f="$state/.body.$$"
  printf '%s\n' "$2" > "$f"
  id="$(bd -C "$root" create --title "$1" --body-file "$f" -t task -p 1 -l watchdog -a "$overseer" --actor "$actor" --silent 2>/dev/null | tail -1 | tr -d '[:space:]')" || id=""
  if [ -n "$id" ]; then
    printf 'ASK: look -- %s\n' "$3" > "$f"
    bd -C "$root" comment "$id" --file "$f" --actor "$actor" >/dev/null 2>&1 || true
  fi
  rm -f "$f"
  printf '%s' "$id"
}
desktop() {  # $1 title, $2 text; best effort, never fatal
  command -v notify-send >/dev/null 2>&1 || return 0
  timeout 5 notify-send -u critical -a "Proofdelve watchdog" "$1" "$2" >/dev/null 2>&1 || true
}
body_for() {  # $1 condition, $2 why
  printf 'The Proofdelve loop watchdog (fort/scripts/loop-watchdog.sh, ForgeOs-dycc9) raised this at %s.\n\nCondition: %s\n\n%s\n\nThis is one alert for the whole episode. When the condition clears the watchdog comments here and closes this bead. To see what it sees now: fort/scripts/loop-watchdog.sh --status\n' "$(iso "$now")" "$1" "$2"
}

if [ "$mode" = test ]; then
  why="THIS IS A TEST. Nothing is wrong. The Overseer or the Regent ran loop-watchdog.sh --test-alert to see an alert arrive before the timer is enabled. Close this bead by hand."
  bead="$(file_bead "WATCHDOG TEST ALERT (nothing is wrong): confirm you saw this, then close it" "$(body_for test "$why")" "this is a watchdog test alert; nothing is wrong. Close it once you have seen it on the board and on the desktop.")"
  emit watcher.alert "TEST ALERT from the loop watchdog (nothing is wrong): $why" -a "$actor" -s watcher -t "${bead:-loop-watchdog}" -p "{\"condition\":\"test\",\"test\":true,\"bead\":\"${bead}\"}"
  desktop "Proofdelve watchdog: TEST ALERT" "Nothing is wrong. Bead: ${bead:-could not be filed}"
  echo "loop-watchdog.sh: test alert sent. Bead: ${bead:-COULD NOT BE FILED}. Event: watcher.alert. Desktop: notify-send (best effort)." >&2
  exit 0
fi

title_for() {
  case "$1" in
    mayor-silent-with-work) echo "WATCHDOG: the Mayor has been silent for $silent_for min while work waits" ;;
    mayor-silent)           echo "WATCHDOG: no Mayor event for $((silent_for / 60)) h; the session is closed or the loop expired" ;;
    pool-dry)               echo "WATCHDOG: the fleet pool has been dry for $(( (now - dry_since) / 60 )) min while $n_routable open bead(s) wait" ;;
  esac
}
handle() {  # $1 condition, $2 true|false|unknown, $3 why
  local cond="$1" val="$2" why="$3" latch="$state/latch-$1" bead=""
  case "$val" in
    unknown) return 0 ;;   # no answer is neither an alert nor a clear
    true)
      if [ -f "$latch" ]; then
        # Latched: silent. If the bead could not be filed when the alert went
        # out, try that one write again, with no second event and no popup.
        bead="$(sed -n 's/^bead=//p' "$latch" | head -1)"
        if [ -z "$bead" ]; then
          bead="$(file_bead "$(title_for "$cond")" "$(body_for "$cond" "$why")" "$why")"
          [ -n "$bead" ] && printf 'since=%s\nbead=%s\n' "$(sed -n 's/^since=//p' "$latch" | head -1)" "$bead" > "$latch"
        fi
        return 0
      fi
      bead="$(file_bead "$(title_for "$cond")" "$(body_for "$cond" "$why")" "$why")"
      printf 'since=%s\nbead=%s\n' "$(iso "$now")" "$bead" > "$latch"
      emit watcher.alert "Loop watchdog: $cond. $why" -a "$actor" -s watcher -t "${bead:-loop-watchdog}" -p "{\"condition\":\"$cond\",\"bead\":\"$bead\",\"silentMin\":$silent_for}"
      desktop "Proofdelve watchdog: $cond" "$why"
      echo "loop-watchdog.sh: ALERT $cond (bead ${bead:-NOT FILED}): $why" >&2
      ;;
    false)
      [ -f "$latch" ] || return 0
      bead="$(sed -n 's/^bead=//p' "$latch" | head -1)"
      if [ -n "$bead" ]; then
        printf 'CLEARED at %s: the condition %s no longer holds. %s\nClosed by the watchdog; the next episode files a new bead.\n' "$(iso "$now")" "$cond" "$why" > "$state/.clear.$$"
        bd -C "$root" comment "$bead" --file "$state/.clear.$$" --actor "$actor" >/dev/null 2>&1 || true
        rm -f "$state/.clear.$$"
        bd -C "$root" close "$bead" --reason "watchdog: $cond cleared at $(iso "$now")" --actor "$actor" >/dev/null 2>&1 || true
      fi
      rm -f "$latch"
      emit watcher.cleared "Loop watchdog: $cond cleared" -a "$actor" -s watcher -t "${bead:-loop-watchdog}" -p "{\"condition\":\"$cond\",\"bead\":\"$bead\"}"
      echo "loop-watchdog.sh: CLEARED $cond (bead ${bead:-none})" >&2
      ;;
  esac
}

handle mayor-silent-with-work "$c_work" "$why_work"
handle mayor-silent "$c_silent" "$why_silent"
handle pool-dry "$c_dry" "$why_dry"

if [ "$board_ok" != 1 ]; then
  echo "loop-watchdog.sh: bd would not answer for $root; mayor-silent-with-work and pool-dry were NOT evaluated this firing and their latches are unchanged." >&2
  exit 64
fi
exit 0
