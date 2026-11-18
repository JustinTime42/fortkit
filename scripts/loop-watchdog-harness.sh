#!/bin/bash
# loop-watchdog-harness: the instrument for fort/scripts/loop-watchdog.sh
# (Proofdelve ForgeOs-dycc9, Proofdelve ForgeOs-76uob.6; Regent sitting 2026-11-16).
#
# It runs the REAL script against a fixture fort: a fixture event stream, a stub
# bd that answers from a fixture board and logs every write, a stub emit.sh and
# a stub notify-send. Each condition is driven true and false, the one-alert
# latch is exercised, and three generated variants of the subject show the
# cases can fail (the latch removed, each duration removed).
#
# Subject: LOOP_WATCHDOG_SH, or fort/scripts/loop-watchdog.sh beside this file's
# parent. verify-impl.sh passes the subject, because it runs a copy of this
# file from a temp directory.
# Exit: 0 all cases passed; 1 a case failed or did not run; 3 refused.
set -uo pipefail
unset FORT_MASKED WATCHDOG_ROOT WATCHDOG_STATE WATCHDOG_FLEET_STATE WATCHDOG_NOW \
      WATCHDOG_WORK_SILENT_MIN WATCHDOG_SILENT_MIN WATCHDOG_DRY_MIN BEADS_ACTOR
here="$(cd "$(dirname "$0")" && pwd)"
subject="${LOOP_WATCHDOG_SH:-$here/../fort/scripts/loop-watchdog.sh}"
[ -f "$subject" ] || { echo "HARNESS REFUSES: no subject at $subject (set LOOP_WATCHDOG_SH)"; exit 3; }
work="$(mktemp -d "${TMPDIR:-/tmp}/loop-watchdog-harness.XXXXXX")"
case "$work" in /*) ;; *) echo "HARNESS REFUSES: scratch dir is not absolute: $work"; exit 3 ;; esac
trap 'rm -rf "$work"' EXIT
pass=0; fail=0; notrun=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1 -- $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi; }

T0=1794000000   # a fixed "now" for every case; offsets are in minutes from it

# --- stubs --------------------------------------------------------------------
mkdir -p "$work/bin"
cat > "$work/bin/bd" <<'STUB'
#!/usr/bin/env python3
# Stub bd. Board: $BDFIX/board.json. Every call is logged, verb first, to $BDFIX/calls.log.
import json, os, sys
fix = os.environ["BDFIX"]; a = sys.argv[1:]
if a[:1] == ["-C"]: a = a[2:]
with open(os.path.join(fix, "calls.log"), "a") as fh: fh.write(" ".join(a) + "\n")
if os.path.exists(os.path.join(fix, "down")): sys.exit(1)
bp = os.path.join(fix, "board.json")
board = json.load(open(bp))
def opt(name, default=None):
    return a[a.index(name) + 1] if name in a else default
verb = a[0]
if verb in ("list", "ready"):
    label = opt("--label"); status = opt("--status")
    out = []
    for b in board:
        if label and label not in b.get("labels", []): continue
        if verb == "ready":
            if b["status"] != "open" or b.get("blocked"): continue
        elif status:
            if b["status"] not in status.split(","): continue
        elif b["status"] == "closed": continue
        out.append({k: v for k, v in b.items() if k != "blocked"})
    print(json.dumps(out)); sys.exit(0)
if verb == "create":
    if os.path.exists(os.path.join(fix, "nocreate")): sys.exit(1)
    n = sum(1 for b in board if b["id"].startswith("W-")) + 1
    b = {"id": "W-%d" % n, "status": "open", "labels": (opt("-l") or "").split(","),
         "assignee": opt("-a"), "issue_type": opt("-t", "task"), "title": opt("--title"),
         "actor": opt("--actor")}
    board.append(b); json.dump(board, open(bp, "w")); print(b["id"]); sys.exit(0)
if verb == "close":
    for b in board:
        if b["id"] == a[1]: b["status"] = "closed"
    json.dump(board, open(bp, "w")); sys.exit(0)
if verb == "comment":
    with open(os.path.join(fix, "comments.log"), "a") as fh:
        fh.write(a[1] + ": " + open(opt("--file")).read().replace("\n", " ") + "\n")
    sys.exit(0)
sys.exit(2)
STUB
cat > "$work/bin/notify-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$BDFIX/notify.log"
STUB
chmod +x "$work/bin/bd" "$work/bin/notify-send"

# --- fixtures -----------------------------------------------------------------
fx=""   # the current fixture directory
mkfix() {  # fresh fixture fort; prints nothing, sets $fx
  fx="$(mktemp -d "$work/fx.XXXXXX")"
  mkdir -p "$fx/root/fort/events" "$fx/root/fort/scripts" "$fx/state" "$fx/fleet" "$fx/bd"
  cat > "$fx/root/fort/scripts/emit.sh" <<'STUB'
#!/bin/bash
# stub emitter: category first on each line, then the rest
printf '%s\n' "$*" >> "$BDFIX/emit.log"
STUB
  chmod +x "$fx/root/fort/scripts/emit.sh"
  echo '[]' > "$fx/bd/board.json"
  : > "$fx/bd/calls.log"; : > "$fx/bd/emit.log"; : > "$fx/bd/notify.log"; : > "$fx/bd/comments.log"
}
event() {  # $1 actor, $2 minutes before T0, $3 detail (optional)
  local ts; ts="$(date -Is -d "@$((T0 - $2 * 60))")"
  printf '{"ts":"%s","actor":"%s","seat":null,"category":"progress","target":null,"detail":"%s","payload":null}\n' \
    "$ts" "$1" "${3:-x}" >> "$fx/root/fort/events/events-$(date -d "$ts" +%F).jsonl"
}
board() { printf '%s' "$1" > "$fx/bd/board.json"; }   # $1 JSON list of beads
fire() {  # $1 minutes after T0, rest: extra args -> runs $SUBJ (default: the subject); sets rc
  local at="$1"; shift
  rc=0
  env -u FORT_MASKED PATH="$work/bin:$PATH" BDFIX="$fx/bd" WATCHDOG_ROOT="$fx/root" WATCHDOG_STATE="$fx/state" \
    WATCHDOG_FLEET_STATE="$fx/fleet" WATCHDOG_NOW="$((T0 + at * 60))" bash "${SUBJ:-$subject}" "$@" > "$fx/out.log" 2>&1 || rc=$?
}
alerts()  { grep -c '^watcher\.alert ' "$fx/bd/emit.log" || true; }      # the category at column one, never the word
clears()  { grep -c '^watcher\.cleared ' "$fx/bd/emit.log" || true; }
creates() { grep -c '^create ' "$fx/bd/calls.log" || true; }
popups()  { wc -l < "$fx/bd/notify.log"; }
open_w()  { python3 -c 'import json,sys; print(sum(1 for b in json.load(open(sys.argv[1])) if b["id"].startswith("W-") and b["status"]=="open"))' "$fx/bd/board.json"; }
SAFE='[{"id":"B-1","status":"open","labels":["fleet-safe"]},{"id":"B-2","status":"open","labels":["fleet-escalated"],"assignee":"emrith"}]'
BACKLOG='[{"id":"B-3","status":"open","labels":[]}]'
fleet_print() { find "$fx/fleet" -printf "%p %s %T@\n" | sort | sha256sum; }
SUBJ=""

# 1. VACUITY CONTROL: a Mayor five minutes fresh with work on the board alerts nothing.
mkfix; event emrith 5; board "$SAFE"; fire 0
check "1 vacuity: fresh Mayor + work -> exit 0" 0 "$rc"
check "1b vacuity: no alert, no bead, no popup" "0 0 0" "$(alerts) $(creates) $(popups)"

# 2. mayor-silent-with-work TRUE: work, Mayor 61 minutes silent.
mkfix; event emrith 61; board "$SAFE"; fire 0
check "2 work + 61 min silent -> one watcher.alert" 1 "$(alerts)"
check "2b one bead filed, assigned to justin, by the watcher" "1 justin watcher:loop" "$(open_w) $(python3 -c 'import json,sys; b=[x for x in json.load(open(sys.argv[1])) if x["id"]=="W-1"][0]; print(b["assignee"], b["actor"])' "$fx/bd/board.json")"
check "2c the bead carries an ASK line" 1 "$(grep -c '^W-1: ASK: look -- ' "$fx/bd/comments.log" || true)"
check "2d one desktop popup" 1 "$(popups)"
check "2e the alert names its condition" 1 "$(grep -c '^watcher\.alert Loop watchdog: mayor-silent-with-work\. ' "$fx/bd/emit.log" || true)"
# 3. THE LATCH: the same state fifteen minutes later says nothing more.
fire 15
check "3 latched: second firing adds no alert, bead or popup" "1 1 1" "$(alerts) $(creates) $(popups)"
fire 30
check "3b latched: third firing still silent" "1 1 1" "$(alerts) $(creates) $(popups)"
# 4. THE CLEAR: the Mayor speaks; the bead is commented and closed; the next episode alerts again.
event emrith -31; fire 32
check "4 cleared: one watcher.cleared, the bead closed, the latch gone" "1 0 no" "$(clears) $(open_w) $([ -f "$fx/state/latch-mayor-silent-with-work" ] && echo yes || echo no)"
check "4b cleared: the bead got a CLEARED comment" 1 "$(grep -c '^W-1: CLEARED at ' "$fx/bd/comments.log" || true)"
fire 95
check "4c a NEW episode alerts again with a new bead" "2 2" "$(alerts) $(creates)"

# 5. mayor-silent-with-work FALSE both ways.
mkfix; event emrith 59; board "$SAFE"; fire 0
check "5 work + 59 min silent -> nothing" "0 0" "$(alerts) $(creates)"
mkfix; event emrith 200; board "$BACKLOG"; : > "$fx/state/pool-dry.since"; echo "$T0" > "$fx/state/pool-dry.since"; fire 0
check "5b 200 min silent with NO fleet or Mayor work -> nothing" "0 0" "$(alerts) $(creates)"
# 5c. a mayor-review bead alone counts as work.
mkfix; event emrith 61; board '[{"id":"B-9","status":"in_progress","labels":["mayor-review"]}]'; fire 0
check "5c a mayor-review bead alone is work" 1 "$(alerts)"

# 6. mayor-silent: 6 hours, whatever the board holds.
mkfix; event emrith 359; board '[]'; fire 0
check "6 empty board, 359 min silent -> nothing" 0 "$(alerts)"
fire 1
check "6b empty board, 360 min silent -> one mayor-silent alert" "1 1" "$(alerts) $(grep -c '^watcher\.alert Loop watchdog: mayor-silent\. ' "$fx/bd/emit.log" || true)"
fire 16
check "6c latched" 1 "$(alerts)"
# 6d. no Mayor event anywhere in the stream is silence, not an error.
mkfix; event kethra 5; board '[]'; fire 0
check "6d no Mayor event at all -> mayor-silent alerts" 1 "$(alerts)"
# 6e. a name in another actor's detail is not an event by that actor.
mkfix; event emrith 400; event harness 1 "emrith said hello"; board '[]'; fire 0
check "6e 'emrith' quoted in a harness event does not count" 1 "$(alerts)"
# 6f. an event stamped in the future does not hide a silence.
mkfix; event emrith 400; event emrith -600; board '[]'; fire 0
check "6f a future-stamped Mayor event is ignored" 1 "$(alerts)"
# 6g. both silences at once are two conditions and two beads.
mkfix; event emrith 400; board "$SAFE"; fire 0
check "6g work + 400 min silent -> two alerts, two beads" "2 2" "$(alerts) $(creates)"

# 7. pool-dry: three outcomes (Proofdelve ForgeOs-76uob.6 criterion 3) and the red arm of criterion 4.
mkfix; event emrith 1; board "$SAFE"; fire 0; event emrith -119; fire 120
check "7 pool deep for two hours -> silent" 0 "$(alerts)"
mkfix; event emrith 1; board "$BACKLOG"; fire 0
check "7b pool empty on first sight -> silent, the moment recorded" "0 yes" "$(alerts) $([ -s "$fx/state/pool-dry.since" ] && echo yes || echo no)"
board "$SAFE"; fire 2; board "$BACKLOG"; fire 4
check "7c pool empty briefly (a restart 81 s after a label change) -> silent, the clock restarted" "0 $((T0 + 240))" "$(alerts) $(cat "$fx/state/pool-dry.since")"
mkfix; event emrith 1; board "$BACKLOG"; fire 0; event emrith -118; fire 119
check "7d pool empty 119 min with open work -> silent" 0 "$(alerts)"
event emrith -119; fire 120
check "7e pool empty 120 min with open work -> one pool-dry alert" "1 1" "$(alerts) $(grep -c '^watcher\.alert Loop watchdog: pool-dry\. ' "$fx/bd/emit.log" || true)"
event emrith -134; fire 135; event emrith -149; fire 150
check "7f pool-dry is one alert, not one per firing" "1 1" "$(alerts) $(creates)"
board "$(python3 -c 'import json,sys; b=json.load(open(sys.argv[1])); b.append({"id":"B-7","status":"open","labels":["fleet-safe"]}); print(json.dumps(b))' "$fx/bd/board.json")"; event emrith -164; fire 165
check "7g the pool refills -> cleared, the clock removed" "1 no" "$(clears) $([ -e "$fx/state/pool-dry.since" ] && echo yes || echo no)"
# 7h. NORMAL IDLE: nothing open at all never alerts, however long.
mkfix; event emrith 1; board '[]'; fire 0; event emrith -599; fire 600
check "7h idle with nothing open for ten hours -> silent" 0 "$(alerts)"
# 7i. only unroutable work open (an epic, his own bead, a regent-docket bead, a blocked bead) is not work.
mkfix; event emrith 1; board '[{"id":"E-1","status":"open","labels":[],"issue_type":"epic"},{"id":"J-1","status":"open","labels":[],"assignee":"justin"},{"id":"R-1","status":"open","labels":["regent-docket"]},{"id":"H-1","status":"open","labels":["human"]},{"id":"X-1","status":"open","labels":[],"blocked":true}]'
fire 0; event emrith -599; fire 600
check "7i only epics, his beads, regent-docket, human and blocked beads open -> silent" 0 "$(alerts)"
# 7j. a fleet-safe bead in progress is a pool in use, not a dry one.
mkfix; event emrith 1; board '[{"id":"B-5","status":"in_progress","labels":["fleet-safe"]},{"id":"B-3","status":"open","labels":[]}]'; fire 0; event emrith -299; fire 300
check "7j a fleet-safe bead in progress -> not dry" 0 "$(alerts)"

# 8. bd DOWN: no answer is neither an alert nor a clear.
mkfix; event emrith 61; board "$SAFE"; fire 0
touch "$fx/bd/down"; event emrith -14; fire 15
check "8 bd down -> exit 64" 64 "$rc"
check "8b bd down -> the existing latch is NOT cleared" "yes 0" "$([ -f "$fx/state/latch-mayor-silent-with-work" ] && echo yes || echo no) $(clears)"
mkfix; event emrith 400; touch "$fx/bd/down"; fire 0
check "8c bd down -> mayor-silent is still evaluated from the stream" "1 64" "$(alerts) $rc"
rm -f "$fx/bd/down"; fire 15
check "8d the bead that could not be filed is filed on the next firing, with no second alert" "1 1" "$(alerts) $(open_w)"

# 9. refusals.
mkfix; event emrith 400; board "$SAFE"
rc=0; env PATH="$work/bin:$PATH" BDFIX="$fx/bd" FORT_MASKED=mayor WATCHDOG_ROOT="$fx/root" WATCHDOG_STATE="$fx/state" WATCHDOG_FLEET_STATE="$fx/fleet" WATCHDOG_NOW="$T0" bash "$subject" >/dev/null 2>&1 || rc=$?
check "9 a masked seat is refused at 64 and nothing is written" "64 0 0" "$rc $(alerts) $(find "$fx/state" -mindepth 1 | wc -l)"
rc=0; env -u FORT_MASKED PATH="$work/bin:$PATH" BDFIX="$fx/bd" WATCHDOG_ROOT="$fx/root" WATCHDOG_NOW="$T0" bash "$subject" >/dev/null 2>&1 || rc=$?
check "9b a fixture root without fixture state directories is refused" "64 0" "$rc $(alerts)"

# 10. it reports and touches nothing of the fleet's (criterion 5).
mkfix; event emrith 400; board "$SAFE"; touch "$fx/fleet/HALT" "$fx/fleet/fleet.lock"
before="$(fleet_print)"; fire 0
check "10 the fleet state directory is untouched by an alerting firing" "$before" "$(fleet_print)"
check "10b both alerts say the fleet is halted" 2 "$(grep -c 'the fleet is HALTED' "$fx/bd/emit.log" || true)"

# 11. --status and --test-alert change no latch.
mkfix; event emrith 400; board "$SAFE"; fire 0 --status
check "11 --status alerts nothing and writes no latch" "0 0 0" "$(alerts) $(creates) $(find "$fx/state" -name "latch-*" | wc -l)"
fire 0 --test-alert
check "11b --test-alert sends one marked test down all three paths and writes no latch" "1 1 1 0" "$(grep -c '^watcher\.alert TEST ALERT ' "$fx/bd/emit.log" || true) $(creates) $(popups) $(find "$fx/state" -name "latch-*" | wc -l)"

# --- RED ARMS: generated variants of the subject must FAIL the case that holds them ----
variant() {  # $1 name, $2 python expression rewriting t -> path, or empty when it could not be generated
  local out="$work/variant-$1.sh"
  python3 - "$subject" "$out" "$2" <<'PY' || { echo ""; return 0; }
import sys
t = open(sys.argv[1]).read(); before = t
exec(sys.argv[3])
if t == before: sys.exit(1)
open(sys.argv[2], "w").write(t)
PY
  echo "$out"
}
red() {  # $1 label, $2 expected-by-the-real-subject, $3 got-from-the-variant
  if [ "$2" != "$3" ]; then ok "$1 (variant gives [$3], the subject [$2])"; else bad "$1" "the variant behaves like the subject: [$3]"; fi
}
# R1. NO LATCH (alarms on every firing): case 3 must fail.
# shellcheck disable=SC2016  # the dollar signs are the subject's text, matched literally
v="$(variant nolatch 't = t.replace("      if [ -f \"$latch\" ]; then\n", "      if false; then\n")')"
if [ -n "$v" ]; then
  mkfix; event emrith 61; board "$SAFE"; SUBJ="$v"; fire 0; fire 15; fire 30; SUBJ=""
  red "R1 a watchdog with no latch alerts on every firing" 1 "$(alerts)"
else notrun=$((notrun+1)); echo "NOT RUN R1 -- the no-latch variant could not be generated"; fi
# R2. THE 60-MINUTE THRESHOLD REMOVED: the vacuity control must alert.
v="$(variant nowork 't = t.replace("WATCHDOG_WORK_SILENT_MIN:-60}", "WATCHDOG_WORK_SILENT_MIN:-0}")')"
if [ -n "$v" ]; then
  mkfix; event emrith 5; board "$SAFE"; SUBJ="$v"; fire 0; SUBJ=""
  red "R2 with the 60-minute threshold removed a fresh Mayor alerts" 0 "$(alerts)"
else notrun=$((notrun+1)); echo "NOT RUN R2 -- variant could not be generated"; fi
# R3. THE 6-HOUR THRESHOLD REMOVED.
v="$(variant nosilent 't = t.replace("WATCHDOG_SILENT_MIN:-360}", "WATCHDOG_SILENT_MIN:-0}")')"
if [ -n "$v" ]; then
  mkfix; event emrith 5; board '[]'; SUBJ="$v"; fire 0; SUBJ=""
  red "R3 with the 6-hour threshold removed a fresh Mayor alerts" 0 "$(alerts)"
else notrun=$((notrun+1)); echo "NOT RUN R3 -- variant could not be generated"; fi
# R4. THE 2-HOUR DURATION REMOVED (alarm on an instant, Proofdelve ForgeOs-76uob.6 criterion 4).
v="$(variant nodry 't = t.replace("WATCHDOG_DRY_MIN:-120}", "WATCHDOG_DRY_MIN:-0}")')"
if [ -n "$v" ]; then
  mkfix; event emrith 1; board "$BACKLOG"; SUBJ="$v"; fire 0; SUBJ=""
  red "R4 with the 2-hour duration removed an empty pool alarms on first sight" 0 "$(alerts)"
else notrun=$((notrun+1)); echo "NOT RUN R4 -- variant could not be generated"; fi

echo "RESULT loop-watchdog-harness: $pass pass / $fail fail / $notrun not run (subject: $subject)"
[ "$fail" = 0 ] && [ "$notrun" = 0 ]
