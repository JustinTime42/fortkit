#!/bin/bash
# Deterministic harness for fort/scripts/fleet-supervisor.sh (Proofdelve ForgeOs-dx34.4).
# No model, no tokens, no real record touched: the supervisor is copied with
# its hardcoded `root=` repointed at a scratch fort whose fort/scripts/ holds a
# stub fleet.sh and a stub emit.sh, and `bd` and `systemd-run` are stubs first
# on PATH. Everything else — the flock probe, the streak file, the halt file —
# is real.
#
# WHAT EACH CASE IS FOR is written on the case, in the terms of the bead's
# criteria, so the next person to break one can tell whether they broke the
# property or only its spelling.
#
# THE CONTROLS ARE GENERATED, NOT ARGUED. Three sabotaged variants of the
# shipped file are made by sed and each must FAIL the case whose property it
# removes (Proofdelve ForgeOs-8zb7 class A: a case that passes against a file lacking the
# property is not a control). A substitution that does not land exactly once
# reports NOT RUN, never PASS.
#
# Usage: scripts/supervisor-harness.sh            (SUPERVISOR_SH overrides the file; SUPERVISOR_SH_PRE_IP9Z supplies the pre-ip9z control)
set -uo pipefail
# NOTHING THIS HARNESS STARTS OUTLIVES IT (Regent sitting 2026-11-19, fortkit-awlc).
# Its fixtures start long sleeps (lock holders, processes for a reaper to find).
# Killing the pid that was started is not enough: `flock f sleep 300` and
# `bash -c 'sleep 300; :'` leave the sleep behind as an orphan, and 20 of those
# were found holding the fleet's run lock after a verifier run. Every process
# this harness starts inherits FORT_HARNESS_TAG, and the EXIT trap kills every
# process that carries it, whoever its parent is by then.
export FORT_HARNESS_TAG="fh-$$-$RANDOM"
reap_tagged() {
  local p pid
  for p in /proc/[0-9]*; do
    pid="${p#/proc/}"
    [ "$pid" = "$$" ] && continue
    if grep -qzx "FORT_HARNESS_TAG=$FORT_HARNESS_TAG" "$p/environ" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null; fi
  done
  return 0
}

here="$(cd "$(dirname "$0")/.." && pwd)"
subject="${SUPERVISOR_SH:-$here/fort/scripts/fleet-supervisor.sh}"
[ -r "$subject" ] || { echo "HARNESS REFUSES: no supervisor at $subject" >&2; exit 3; }

pass=0; fail=0; notrun=0
ok()   { pass=$((pass + 1)); echo "PASS $1"; }
bad()  { fail=$((fail + 1)); echo "FAIL $1"; }
skip() { notrun=$((notrun + 1)); echo "NOT RUN $1"; }
b7_failed=0
b8_failed=0

scratch="$(mktemp -d)"
trap 'reap_tagged; rm -rf "$scratch"' EXIT

# --- the scratch fort and the stubs -----------------------------------------
fort="$scratch/fort"
mkdir -p "$fort/fort/scripts" "$scratch/bin" "$scratch/state"
cat > "$fort/fort/scripts/fleet.sh" <<'STUB'
#!/bin/bash
echo "STUB fleet.sh ran: $*" >> "${STUB_LOG:?}"
# --reapable (Proofdelve ForgeOs-dx34.18): the real launcher prints one count; the stub
# prints STUB_REAPABLE (default 0) so every earlier case keeps its world, or
# fails like a broken launcher under STUB_REAPABLE_RC.
case "${1:-}" in --reapable) [ "${STUB_REAPABLE_RC:-0}" = 0 ] || exit "${STUB_REAPABLE_RC}"; echo "${STUB_REAPABLE:-0}"; exit 0 ;; esac
STUB
cat > "$fort/fort/scripts/emit.sh" <<'STUB'
#!/bin/bash
printf 'EMIT %s\n' "$*" >> "${STUB_LOG:?}"
STUB
# bd: answers from a fixture file; BD_MODE=down makes it fail like an outage.
cat > "$scratch/bin/bd" <<'STUB'
#!/bin/bash
printf 'BD %s\n' "$*" >> "${STUB_LOG:?}"
case "${BD_MODE:-ok}" in
  down) echo "bd: cannot open database" >&2; exit 1 ;;
esac
cat "${BD_READY_FIXTURE:?}"
STUB
# systemd-run: records its argv and does NOT run the command (the real one
# would hand it to the user manager; here the property is only that it was
# asked, with the fleet as the command).
cat > "$scratch/bin/systemd-run" <<'STUB'
#!/bin/bash
printf 'SYSTEMD-RUN %s\n' "$*" >> "${STUB_LOG:?}"
exit "${SYSTEMD_RUN_RC:-0}"
STUB
printf 'FLEET_ENABLED=1\n' > "$fort/fort/scripts/fleet.conf"
chmod +x "$fort/fort/scripts/"*.sh "$scratch/bin/"*
echo '[]' > "$scratch/ready-empty.json"
echo '[{"id":"E2E-aaa"},{"id":"E2E-bbb"}]' > "$scratch/ready-two.json"

# --- rendering a subject with its root repointed -----------------------------
render() {  # $1 source file, $2 destination; asserts the root line lands once
  local n
  n="$(grep -c '^root="/home/justin/dev/fortkit"$' "$1")"
  [ "$n" = 1 ] || { echo "HARNESS REFUSES: expected exactly one root= line in $1, found $n" >&2; return 3; }
  sed "s|^root=\"/home/justin/dev/fortkit\"$|root=\"$fort\"|" "$1" > "$2"
  chmod +x "$2"
  # nothing else changed
  [ "$(diff <(grep -v '^root=' "$1") <(grep -v '^root=' "$2") | wc -l)" = 0 ] \
    || { echo "HARNESS REFUSES: the render changed more than the root line" >&2; return 3; }
}
render "$subject" "$scratch/supervisor.sh" || exit 3
sup="$scratch/supervisor.sh"

# --- a firing ------------------------------------------------------------------
# fire <state-dir> <ready-fixture> -> sets rc, out (stdout+stderr), and appends
# stub calls to $log. Every run gets a fresh stub log so cases can assert "no
# call" without inheriting an earlier one.
fire() {
  local st="$1" fx="$2"
  log="$scratch/stub.$RANDOM.log"; : > "$log"
  out="$(cd "$scratch" && PATH="${SUP_PATH:-$scratch/bin:$PATH}" FLEET_STATE="$st" STUB_LOG="$log" \
         BD_READY_FIXTURE="$fx" BD_MODE="${BD_MODE:-ok}" SYSTEMD_RUN_RC="${SYSTEMD_RUN_RC:-0}" \
         STUB_REAPABLE="${STUB_REAPABLE:-0}" STUB_REAPABLE_RC="${STUB_REAPABLE_RC:-0}" \
         FORT_MASKED="${MASKED:-}" "$sup" "${SUP_ARGS[@]}" 2>&1)"; rc=$?
}
SUP_ARGS=()
sha() { if [ -f "$1" ]; then sha256sum "$1" | cut -c1-16; else echo ABSENT; fi; }
val() { grep -m1 "^$2=" "$1/supervisor.streak" 2>/dev/null | cut -d= -f2-; }
# hold_lock <state> : holds the run lock from a background flock until release_lock
hold_lock() {
  mkdir -p "$1"; ( exec 9>>"$1/fleet.lock"; flock 9; echo $$ > "$1/.holder"; exec sleep 300 ) &
  holder=$!
  local i=0
  while flock -n "$1/fleet.lock" true 2>/dev/null; do   # still free: the holder has not taken it yet
    i=$((i + 1)); [ $i -gt 50 ] && { echo "HARNESS REFUSES: could not take the lock for a fixture" >&2; exit 3; }; sleep 0.1
  done
}
release_lock() { kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; }

# ============================================================================
# Cases against the shipped file.
# ============================================================================
S="$scratch/state/a"; mkdir -p "$S"

# --- criterion 2: nothing to do is a no-op ---------------------------------
fire "$S" "$scratch/ready-empty.json"
if [ $rc = 0 ] && [ -z "$out" ] && ! grep -q SYSTEMD-RUN "$log" && [ ! -e "$S/supervisor.streak" ]; then
  ok "c2: lock free, queue empty -> exit 0, no output, no launch, no streak record"
else bad "c2: lock free, queue empty (rc=$rc out='$out' launch=$(grep -c SYSTEMD-RUN "$log"))"; fi

# --- criterion 3/4: a live run -> 75, silent, counted ------------------------
hold_lock "$S"
fire "$S" "$scratch/ready-two.json"
c="$(val "$S" count)"; f1="$(val "$S" first_refusal)"; l1="$(val "$S" last_refusal)"
if [ $rc = 75 ] && [ -z "$out" ] && [ "$c" = 1 ] && [ -n "$f1" ] && ! grep -q 'SYSTEMD-RUN\|^BD' "$log"; then
  ok "c3: lock held -> exit 75, no output, no launch, bd NOT consulted, streak count=1 first_refusal=$f1"
else bad "c3: lock held (rc=$rc out='$out' count='$c' first='$f1' calls=$(grep -c 'SYSTEMD-RUN\|^BD' "$log"))"; fi
sleep 1.1   # so last_refusal can be shown to move at one-second resolution
fire "$S" "$scratch/ready-two.json"
c="$(val "$S" count)"; f2="$(val "$S" first_refusal)"; l2="$(val "$S" last_refusal)"
if [ $rc = 75 ] && [ -z "$out" ] && [ "$c" = 2 ] && [ "$f2" = "$f1" ] && [ "$l2" != "$l1" ]; then
  ok "c4b: second firing during the run -> count 1->2, first_refusal UNCHANGED ($f1), last_refusal advanced"
else bad "c4b: second firing (rc=$rc count='$c' first '$f1'->'$f2' last '$l1'->'$l2')"; fi
if ! grep -q 'SYSTEMD-RUN' "$log"; then ok "c4a: no second run was started while the lock was held"; else bad "c4a: a launch was attempted under a held lock"; fi

# --- the third case for criterion 4: the halt file ----------------------------
before="$(sha "$S/supervisor.streak")"
touch "$S/HALT"
fire "$S" "$scratch/ready-two.json"
after="$(sha "$S/supervisor.streak")"
if [ $rc = 0 ] && [ -z "$out" ] && [ "$before" = "$after" ] && [ ! -s "$log" ]; then
  ok "halt: halt file present, lock held, work ready -> exit 0, no output, no bd call, no launch, streak byte-identical"
else bad "halt: (rc=$rc out='$out' streak $before->$after calls=$(wc -l < "$log"))"; fi
rm -f "$S/HALT"

# --- criterion 5: the run ends -> the streak resets ------------------------------
release_lock
fire "$S" "$scratch/ready-empty.json"
c="$(val "$S" count)"; ps="$(val "$S" previous_streak)"; pf="$(val "$S" previous_first_refusal)"; ra="$(val "$S" reset_at)"
if [ $rc = 0 ] && [ -z "$out" ] && [ "$c" = 0 ] && [ "$ps" = 2 ] && [ "$pf" = "$f1" ] && [ -n "$ra" ] && [ -z "$(val "$S" first_refusal)" ]; then
  ok "c5: run ended, fired once more -> count 0, first_refusal cleared, previous_streak=2 previous_first_refusal=$pf reset_at=$ra"
else bad "c5: reset (rc=$rc count='$c' previous_streak='$ps' previous_first='$pf' reset_at='$ra')"; fi
before="$(sha "$S/supervisor.streak")"
fire "$S" "$scratch/ready-empty.json"
if [ "$(sha "$S/supervisor.streak")" = "$before" ]; then ok "c5b: a further quiet firing at count 0 does not rewrite the record"; else bad "c5b: the record was rewritten at count 0"; fi

# --- criterion 1: work appears -> a run is started, as the fleet, once -------------
fire "$S" "$scratch/ready-two.json"
n_launch="$(grep -c '^SYSTEMD-RUN' "$log")"
if [ $rc = 0 ] && [ "$n_launch" = 1 ] && grep -q "^SYSTEMD-RUN .*$fort/fort/scripts/fleet.sh\$" "$log" && grep -q -- "--setenv FLEET_STATE=$S " "$log" \
   && grep -q -- '--unit manyhalls-fleet-run-' "$log" && grep -q -- '-p KillMode=process' "$log" \
   && grep -q '^EMIT fleet.autostart ' "$log" && grep -q '"candidates":2' "$log" \
   && [ "$(printf '%s' "$out" | wc -l)" = 0 ] && grep -q '^fleet-supervisor.sh: started manyhalls-fleet-run-' <<<"$out"; then
  ok "c1: lock free, 2 ready -> systemd-run asked ONCE for fleet.sh as unit manyhalls-fleet-run-*, KillMode=process, one stderr line, fleet.autostart emitted with candidates=2"
else bad "c1: start (rc=$rc launches=$n_launch out='$out' log: $(tr '\n' '|' < "$log" | cut -c1-300))"; fi
if [ "$(val "$S" count)" = 0 ]; then ok "c1b: starting a run leaves the streak at 0"; else bad "c1b: streak changed on a start"; fi

# --- Proofdelve ForgeOs-eedj: ONE PATH, forwarded and checked ---------------------------
# The supervisor used to hand systemd-run its own hardcoded copy of the unit's
# PATH. Now it forwards the PATH it was fired under and refuses, naming the
# tool, when that PATH does not resolve what a run needs. Against the pre-eedj
# file: e1 FAILs (the --setenv PATH is the hardcoded list, not the firing's),
# e2 FAILs (a run starts on a PATH with no codex).
fire "$S" "$scratch/ready-two.json"
sup_path="$scratch/bin:$PATH"
if grep -q -- "--setenv PATH=$sup_path " "$log"; then
  ok "e1 (eedj): the run inherits the PATH the supervisor was fired under -- the unit's Environment=PATH is the one list"
else bad "e1 (eedj): the run's PATH is not the firing's PATH: $(grep -o -- '--setenv PATH=[^ ]*' "$log" | head -1)"; fi
# a PATH that resolves the stubs and the coreutils but NOT codex: a toolchain dir went missing (the node-upgrade shape)
mkdir -p "$scratch/thinbin"
for t in bd systemd-run; do ln -sf "$scratch/bin/$t" "$scratch/thinbin/$t"; done
# THE TOOL LIST IS READ OUT OF THE SUBJECT, NEVER COPIED FROM IT (Proofdelve ForgeOs-ip9z
# finding 6 added claude and dotnet to fleet_tools and this hand-written copy
# went stale in the same commit, turning e2's own vacuity control red). A list
# that must match a list in another file is generated from that file or it is
# wrong the first time either one moves. `codex` is deliberately EXCLUDED here
# and linked in afterwards: it is the tool e2 removes.
sup_tools="$(grep -m1 '^fleet_tools="' "$subject" | sed 's/^fleet_tools="//; s/"$//')"
[ -n "$sup_tools" ] || { echo "HARNESS REFUSES: could not read fleet_tools out of $subject" >&2; exit 3; }
for t in $sup_tools bash grep sed awk cat mkdir date mv rm head cut printf sha256sum; do
  [ "$t" = codex ] && continue
  [ "$t" = bd ] && continue          # already linked to the stub above
  p="$(command -v "$t" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$scratch/thinbin/$t"
done
SUP_PATH="$scratch/thinbin" fire "$S" "$scratch/ready-two.json"
if [ $rc = 64 ] && grep -q 'does not resolve: codex' <<<"$out" && grep -q "PATH=$scratch/thinbin" <<<"$out" && ! grep -q 'SYSTEMD-RUN' "$log"; then
  ok "e2 (eedj): a PATH without codex REFUSES at 64, names the missing tool and the PATH, and starts no run"
else bad "e2 (eedj): (rc=$rc out='$out' launch=$(grep -c SYSTEMD-RUN "$log"))"; fi
# vacuity control for e2: the same thin PATH WITH codex linked in starts the run
p="$(command -v codex 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$scratch/thinbin/codex"
SUP_PATH="$scratch/thinbin" fire "$S" "$scratch/ready-two.json"
if [ $rc = 0 ] && grep -q 'SYSTEMD-RUN' "$log"; then
  ok "e2 control: the same thin PATH with codex present starts the run -- e2 measured the missing tool, not a broken PATH"
else bad "e2 control: (rc=$rc out='$out')"; fi

# --- Proofdelve ForgeOs-s49w: THE BACK-OFF, driven by the outcome record fleet.sh writes ---
# The supervisor decides nothing about beads; it reads $FLEET_STATE/last-run.outcome
# (run, autostart, launches, reason, duration_s) and backs off only when ITS own
# last run drained quickly with zero launches. Fixtures write that record by hand
# (the stub systemd-run runs nothing). Against the pre-s49w file every case
# below that expects a back-off FAILs: it starts a run every firing.
B="$scratch/state/bo"; mkdir -p "$B"
outcome() { printf 'run=R\nautostart=%s\nlaunches=%s\nreason=%s\nduration_s=%s\nended_at=T\n' "$1" "$2" "$3" "$4" > "$B/last-run.outcome"; }
fire "$B" "$scratch/ready-two.json"     # a first start: records the unit it started
u1="$(grep -o 'manyhalls-fleet-run-[0-9T]*' "$log" | head -1)"
if [ -n "$u1" ] && grep -q -- "--setenv FLEET_AUTOSTART=$u1 " "$log" && [ "$(grep -m1 '^last_autostart_unit=' "$B/supervisor.backoff" | cut -d= -f2)" = "$u1" ]; then
  ok "b0 (s49w): a start passes FLEET_AUTOSTART=<unit> to the run and records that unit as the one to judge next time"
else bad "b0 (s49w): (unit='$u1' backoff=$(tr '\n' '|' < "$B/supervisor.backoff" 2>/dev/null) log=$(grep -o -- '--setenv FLEET_AUTOSTART=[^ ]*' "$log"))"; fi
outcome "$u1" 0 drained 2               # our run drained in 2 s with 0 launches: nothing was dispatchable
fire "$B" "$scratch/ready-two.json"
if [ $rc = 0 ] && ! grep -q SYSTEMD-RUN "$log" && grep -q '^EMIT fleet.backoff ' "$log" && grep -q 'BACKING OFF (1)' <<<"$out" \
   && [ "$(grep -m1 '^backoff_n=' "$B/supervisor.backoff" | cut -d= -f2)" = 1 ] && [ -n "$(grep -m1 '^backoff_until=' "$B/supervisor.backoff" | cut -d= -f2)" ]; then
  ok "b1 (s49w): our last run drained in 2 s with 0 launches -> no run started, ONE fleet.backoff event, backoff_n=1 with an until"
else bad "b1 (s49w): (rc=$rc out='$out' launch=$(grep -c SYSTEMD-RUN "$log") events=$(grep -c '^EMIT' "$log") backoff=$(tr '\n' '|' < "$B/supervisor.backoff" 2>/dev/null))"; fi
fire "$B" "$scratch/ready-two.json"     # inside the window
# (the ready query still runs first -- the back-off is asked only when there is work -- so one BD line is expected and nothing else)
if [ $rc = 0 ] && [ -z "$out" ] && ! grep -q 'SYSTEMD-RUN\|^EMIT' "$log" && [ "$(grep -m1 '^skips=' "$B/supervisor.backoff" | cut -d= -f2)" = 1 ]; then
  ok "b2 (s49w): a firing inside the back-off window is silent -- no output, no event, no launch -- and counted (skips=1)"
else bad "b2 (s49w): (rc=$rc out='$out' calls=$(wc -l < "$log") backoff=$(tr '\n' '|' < "$B/supervisor.backoff" 2>/dev/null))"; fi
# THE WINDOW EXPIRES WITH THE SAME OUTCOME ON RECORD (Proofdelve ForgeOs-enred). That
# outcome was already judged, and no run has started since, so judging it
# again proves nothing: ONE probe run starts, carrying the step count. b3 read
# "the step doubles" until 2026-10-19 -- it asserted the defect: measured that
# morning, 4 -> 8 -> 32 minutes of back-off with no run ever started, until a
# person deleted the file. Against the pre-enred supervisor b3 FAILs (RED arm).
sed -i 's/^backoff_until=.*/backoff_until=2020-01-01T00:00:00-08:00/' "$B/supervisor.backoff"
fire "$B" "$scratch/ready-two.json"
up="$(grep -o -- '--setenv FLEET_AUTOSTART=[^ ]*' "$log" | head -1 | cut -d= -f2)"
if [ $rc = 0 ] && [ -n "$up" ] && grep -q SYSTEMD-RUN "$log" && ! grep -q '^EMIT fleet.backoff ' "$log" && grep -q 'PROBE after back-off step 1' <<<"$out" \
   && [ "$(grep -m1 '^last_autostart_unit=' "$B/supervisor.backoff" | cut -d= -f2)" = "$up" ] \
   && [ "$(grep -m1 '^backoff_n=' "$B/supervisor.backoff" | cut -d= -f2)" = 1 ] \
   && [ -z "$(grep -m1 '^backoff_until=' "$B/supervisor.backoff" | cut -d= -f2)" ]; then
  ok "b3 (enred): after the window expires with the already-judged outcome on record, ONE probe run starts, is recorded as the run to judge, and carries backoff_n=1"
else bad "b3 (enred): (rc=$rc out='$out' launch=$(grep -c SYSTEMD-RUN "$log") backoff=$(tr '\n' '|' < "$B/supervisor.backoff" 2>/dev/null))"; fi
# b3b THE PROBE ALSO DID NOTHING: back off one step further, judged on the probe.
outcome "$up" 0 drained 2
fire "$B" "$scratch/ready-two.json"
if [ $rc = 0 ] && ! grep -q SYSTEMD-RUN "$log" && grep -q 'BACKING OFF (2)' <<<"$out" && grep -q "($up)" <<<"$out" \
   && [ "$(grep -m1 '^backoff_n=' "$B/supervisor.backoff" | cut -d= -f2)" = 2 ]; then
  ok "b3b (enred): the probe drained with 0 launches too -> the step doubles (backoff_n=2), judged on the PROBE's own outcome"
else bad "b3b (enred): (rc=$rc out='$out' backoff=$(tr '\n' '|' < "$B/supervisor.backoff" 2>/dev/null))"; fi
# b4 A PROBE THAT DID WORK CLEARS IT. The window ends, a second probe starts
# carrying 2, and that probe launched something: the next firing clears.
sed -i 's/^backoff_until=.*/backoff_until=2020-01-01T00:00:00-08:00/' "$B/supervisor.backoff"
fire "$B" "$scratch/ready-two.json"
up2="$(grep -o -- '--setenv FLEET_AUTOSTART=[^ ]*' "$log" | head -1 | cut -d= -f2)"
outcome "$up2" 2 drained 90
fire "$B" "$scratch/ready-two.json"
if [ $rc = 0 ] && [ -n "$up2" ] && grep -q SYSTEMD-RUN "$log" && [ "$(grep -m1 '^backoff_n=' "$B/supervisor.backoff" | cut -d= -f2)" = 0 ]; then
  ok "b4 (s49w, enred): the probe LAUNCHED something -> a run starts and the back-off is cleared (backoff_n=0)"
else bad "b4 (s49w, enred): (rc=$rc out='$out' launch=$(grep -c SYSTEMD-RUN "$log") backoff=$(tr '\n' '|' < "$B/supervisor.backoff" 2>/dev/null))"; fi

# --- The churn note on Proofdelve ForgeOs-owt37: LANDINGS, NOT DURATION ---
# 2026-10-05 16:06-16:16: zero-launch drains of 20-28 s, past the 20 s cutoff,
# so the supervisor started a run every firing. fleet.sh now records landings=N;
# when the field is present the supervisor backs off on 0 launches AND 0
# landings whatever the duration. Against the pre-change supervisor l1 FAILs
# (it starts a run at 28 s) -- the RED arm.
BL="$scratch/state/bl"; mkdir -p "$BL"
outcome_l() { printf 'run=R\nautostart=%s\nlaunches=%s\nlandings=%s\nreason=%s\nduration_s=%s\nended_at=T\n' "$2" "$3" "$4" "$5" "$6" > "$1/last-run.outcome"; }
fire "$BL" "$scratch/ready-two.json"; ul="$(grep -o 'manyhalls-fleet-run-[0-9T]*' "$log" | head -1)"
outcome_l "$BL" "$ul" 0 0 drained 28
fire "$BL" "$scratch/ready-two.json"
if [ $rc = 0 ] && ! grep -q SYSTEMD-RUN "$log" && grep -q 'BACKING OFF (1)' <<<"$out" && grep -q '0 landings' <<<"$out"; then
  ok "l1 (owt37 churn): our last run drained in 28 s with 0 launches and 0 landings -> it BACKS OFF (the 2026-10-05 shape, which the 20 s cutoff missed)"
else bad "l1 (owt37 churn): (rc=$rc out='$out' launch=$(grep -c SYSTEMD-RUN "$log"))"; fi
BL2="$scratch/state/bl2"; mkdir -p "$BL2"
fire "$BL2" "$scratch/ready-two.json"; ul2="$(grep -o 'manyhalls-fleet-run-[0-9T]*' "$log" | head -1)"
outcome_l "$BL2" "$ul2" 0 1 drained 28
fire "$BL2" "$scratch/ready-two.json"
if [ $rc = 0 ] && grep -q SYSTEMD-RUN "$log" && ! grep -q '^EMIT fleet.backoff ' "$log"; then
  ok "l2 (owt37 churn): the same 28 s, 0-launch run that LANDED one merge does not back off -- a run starts (the control: l1 measured landings, not a blanket back-off)"
else bad "l2 (owt37 churn): (rc=$rc out='$out' launch=$(grep -c SYSTEMD-RUN "$log"))"; fi
BL3="$scratch/state/bl3"; mkdir -p "$BL3"
fire "$BL3" "$scratch/ready-two.json"; ul3="$(grep -o 'manyhalls-fleet-run-[0-9T]*' "$log" | head -1)"
printf 'run=R\nautostart=%s\nlaunches=0\nreason=drained\nduration_s=28\nended_at=T\n' "$ul3" > "$BL3/last-run.outcome"
fire "$BL3" "$scratch/ready-two.json"
if [ $rc = 0 ] && grep -q SYSTEMD-RUN "$log"; then
  ok "l3 (owt37 churn): an outcome record with NO landings field (an older fleet.sh) keeps the duration test: 28 s starts a run, as before"
else bad "l3 (owt37 churn): (rc=$rc out='$out')"; fi

# --- Proofdelve ForgeOs-ip9z finding 7: THE BACK-OFF WINDOW MUST NEVER LAND IN THE PAST ---
# `mins=$((4 << (n - 1)))` with the 60-minute cap applied AFTERWARDS still
# performs the shift, and the shift overflows signed 64-bit at n >= 62
# (4 << 61 = -9223372036854775808, 4 << 62 = 0). A negative or zero value is
# not greater than 60, so the cap never fires and `until` is computed as
# now + a negative number of minutes: every later firing is outside its own
# window and emits fleet.backoff, every two minutes, forever. The fixture
# drives the counter straight to the edge rather than waiting 61 hours for it.
B7="$scratch/state/b7"; mkdir -p "$B7"
# THE SHARED outcome() HELPER IS NOT REDEFINED HERE. It is bound to $B and a
# second definition would leave every later case writing into this fixture's
# state directory -- an instrument defect that presents as a subject defect.
outcome_into() { printf 'run=R\nautostart=%s\nlaunches=%s\nreason=%s\nduration_s=%s\nended_at=T\n' "$2" "$3" "$4" "$5" > "$1/last-run.outcome"; }
fire "$B7" "$scratch/ready-two.json"                 # firing 1: starts a run, records the unit
u7="$(grep -o -- '--setenv FLEET_AUTOSTART=[^ ]*' "$log" | head -1 | cut -d= -f2)"
outcome_into "$B7" "$u7" 0 drained 2
# backoff_until EMPTY since Proofdelve ForgeOs-enred: that is the state a run (or a probe)
# leaves behind carrying its step count, and the only state in which an outcome
# is judged. An expired until now means "already judged" and starts a probe.
printf 'last_autostart_unit=%s\nbackoff_n=61\nbackoff_until=\nskips=0\n' "$u7" > "$B7/supervisor.backoff"
fire "$B7" "$scratch/ready-two.json"
until7="$(grep -m1 '^backoff_until=' "$B7/supervisor.backoff" | cut -d= -f2-)"
n7="$(grep -m1 '^backoff_n=' "$B7/supervisor.backoff" | cut -d= -f2)"
until7_epoch="$(date -d "$until7" +%s 2>/dev/null || echo 0)"
if [ "$n7" = 62 ] && [ "$until7_epoch" -gt "$(date +%s)" ] \
   && [ $(( (until7_epoch - $(date +%s)) / 60 )) -ge 58 ] && [ $(( (until7_epoch - $(date +%s)) / 60 )) -le 61 ]; then
  ok "b7 (ip9z 7): at backoff step 62 the window is still 60 minutes IN THE FUTURE ($until7) -- the shift no longer overflows, and the step counter keeps counting"
else b7_failed=1; bad "b7 (ip9z 7): the back-off window is not a future 60 minutes (backoff_n=$n7 until=$until7 delta_min=$(( (until7_epoch - $(date +%s)) / 60 )))"; fi
# THE SEQUENCE BELOW THE CAP IS UNCHANGED, which is what makes this a bug fix
# and not a retune: 4, 8, 16, 32, then 60 from step 5 on.
seqbad=""
for step in 1 2 3 4 5; do
  printf 'last_autostart_unit=%s\nbackoff_n=%s\nbackoff_until=\nskips=0\n' "$u7" "$((step - 1))" > "$B7/supervisor.backoff"
  fire "$B7" "$scratch/ready-two.json"
  u="$(grep -m1 '^backoff_until=' "$B7/supervisor.backoff" | cut -d= -f2-)"
  got="$(( ( $(date -d "$u" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 60 ))"
  case "$step" in 1) want=4;; 2) want=8;; 3) want=16;; 4) want=32;; 5) want=60;; esac
  # (initialised before the loop; see seqbad="" above)
  if [ "$got" -ge "$((want - 2))" ] && [ "$got" -le "$want" ]; then :; else seqbad="$seqbad step$step=${got}m(want ${want}m)"; fi
done
if [ -z "${seqbad:-}" ]; then
  ok "b7b (ip9z 7): the doubling below the cap is untouched -- steps 1-5 give 4, 8, 16, 32, 60 minutes"
else bad "b7b (ip9z 7): the sequence moved:$seqbad"; fi

# --- Proofdelve ForgeOs-ip9z finding 8: A LOCK FILE THAT CANNOT BE WRITTEN IS NOT A LIVE RUN ---
# The fixture is the realistic one the bead names: the lock file exists and is
# readable, and the probe cannot WRITE it. The old `9>>` redirection failed,
# the `if` was false, and the supervisor took the run-is-live branch -- silently,
# and for as long as the permission stood.
B8="$scratch/state/b8"; mkdir -p "$B8"
: > "$B8/fleet.lock"; chmod 0444 "$B8/fleet.lock"
fire "$B8" "$scratch/ready-two.json"
if [ $rc != 75 ] && [ "$(val "$B8" count)" != 1 ]; then
  ok "b8 (ip9z 8): a lock file that is readable but NOT WRITABLE is probed read-only and reads as FREE -- no phantom 75, no refusal streak"
else b8_failed=1; bad "b8 (ip9z 8): an unwritable lock file still reads as a live run (rc=$rc streak_count=$(val "$B8" count))"; fi
chmod 0644 "$B8/fleet.lock"
# VACUITY, ON ITS OWN STATE DIR. Without it, b8 is equally satisfied by a
# supervisor that never reports a held lock at all.
B8V="$scratch/state/b8v"; mkdir -p "$B8V"; hold_lock "$B8V"
fire "$B8V" "$scratch/ready-two.json"
if [ $rc = 75 ]; then
  ok "b8 control: a lock genuinely HELD by another process still exits 75 -- b8 measured the permission, not the probe being switched off"
else bad "b8 control: a genuinely held lock was not detected (rc=$rc)"; fi
release_lock
# AND AN ABSENT LOCK FILE IS NOT AN ERROR: fleet.sh creates it the first time it
# takes the lock, so a virgin state directory must not refuse the first firing.
B8N="$scratch/state/b8n"; mkdir -p "$B8N"
fire "$B8N" "$scratch/ready-two.json"
if [ $rc = 0 ] && grep -q SYSTEMD-RUN "$log"; then
  ok "b8 (ip9z 8): a state directory with NO lock file at all starts a run -- an absent lock is 'never taken', not an error"
else bad "b8: a virgin state dir did not start a run (rc=$rc)"; fi

# --- THE INVERSIONS for findings 7 and 8, against a mutated shipped subject ---
# THE "BEFORE" FILE IS DERIVED FROM THE SUBJECT, NOT GIT (Proofdelve ForgeOs-64s8o).
# verify-impl.sh copies this harness outside its checkout before it runs it, and
# The Warden deliberately verifies from an rsync scratch tree without .git.
# SUPERVISOR_SH_PRE_IP9Z may supply that derived pre-ip9z control explicitly.
# Both substitutions are anchored and must land exactly once: if the subject no
# longer has the two fixed spellings, this is a REFUSAL, never a skipped control.
ip9z_anchor_attribution() { # $1 check, $2 failed, $3 anchor count, $4 fix name
  [ "$2" = 1 ] || return
  case "$3" in
    0) printf ' %s failed above and the %s anchor count is 0, so the subject has likely lost the %s.' "$1" "$4" "$4" ;;
    1) ;;
    *) printf ' %s failed above and the %s anchor count is %s, so the %s is duplicated.' "$1" "$4" "$3" "$4" ;;
  esac
}
ip9z_anchor_remedy() { # $1 failed, $2 anchor count, $3 fix name
  [ "$1" = 1 ] || return
  case "$2" in
    0) printf 'restore the %s' "$3" ;;
    1) ;;
    *) printf 'remove the extra copy of the %s' "$3" ;;
  esac
}
ip9z_join_remedies() {
  local result part
  [ "$#" = 0 ] && return
  result="$1"
  shift
  for part; do result="$result and $part"; done
  printf '%s' "$result"
}
ip9z_refusal() { # attribution subject backoff-anchor lock-anchor b7-failed backoff-hits b8-failed lock-hits
  local attribution="$1" source="$2" backoff_anchor="$3" lock_anchor="$4"
  local b7_failed="$5" backoff_hits="$6" b8_failed="$7" lock_hits="$8"
  local remedies=() remedy_part remedy
  remedy_part="$(ip9z_anchor_remedy "$b7_failed" "$backoff_hits" 'ip9z backoff fix')"
  [ -z "$remedy_part" ] || remedies+=("$remedy_part")
  remedy_part="$(ip9z_anchor_remedy "$b8_failed" "$lock_hits" 'ip9z lock probe')"
  [ -z "$remedy_part" ] || remedies+=("$remedy_part")
  if [ "$b7_failed" = 0 ] && [ "$b8_failed" = 0 ]; then
    remedy="the anchors may need updating to the subject's current spelling"
  elif [ ${#remedies[@]} = 0 ]; then
    remedy="supply SUPERVISOR_SH_PRE_IP9Z; neither failed check is attributable to its anchor"
  else
    remedy="supply SUPERVISOR_SH_PRE_IP9Z or $(ip9z_join_remedies "${remedies[@]}")"
  fi
  printf 'HARNESS REFUSES:%s Could not build the ip9z 7/8 inversion from %s (backoff anchor=%s, lock anchor=%s; expected 1 each); %s, because this harness does not pass a control it did not run' \
    "$attribution" "$source" "$backoff_anchor" "$lock_anchor" "$remedy"
}
# Keep these assertions outside the pass count: the long-standing harness
# summary remains the regression count. The full-message fixture calls the
# same function as the refusal below, and the call-site shape makes a manual
# bare-space reassembly a named failure instead of an invisible regression.
# shellcheck disable=SC2016  # literal call-site spelling is the mutation anchor
ip9z_message_call='    ip9z_refusal "$attribution" "$subject" "$backoff_anchor" "$lock_anchor" "$b7_failed" "$backoff_hits" "$b8_failed" "$lock_hits" >&2'
if [ "$(ip9z_join_remedies)" != '' ]; then
  echo 'HARNESS REFUSES: ip9z helper-level arm failed: zero-remedy join' >&2
  exit 3
elif [ "$(ip9z_join_remedies 'restore the ip9z backoff fix')" != 'restore the ip9z backoff fix' ]; then
  echo 'HARNESS REFUSES: ip9z helper-level arm failed: one-remedy join' >&2
  exit 3
elif [ "$(ip9z_join_remedies 'restore the ip9z backoff fix' 'restore the ip9z lock probe')" != 'restore the ip9z backoff fix and restore the ip9z lock probe' ]; then
  echo 'HARNESS REFUSES: ip9z helper-level arm failed: two-remedy join' >&2
  exit 3
elif [ "$(ip9z_join_remedies 'restore the ip9z backoff fix' 'remove the extra copy of the ip9z lock probe')" != 'restore the ip9z backoff fix and remove the extra copy of the ip9z lock probe' ]; then
  echo 'HARNESS REFUSES: ip9z helper-level arm failed: mixed lost-and-duplicate join' >&2
  exit 3
elif [ "$(ip9z_refusal '' subject 'missing (0)' 'missing (0)' 1 0 1 0)" != 'HARNESS REFUSES: Could not build the ip9z 7/8 inversion from subject (backoff anchor=missing (0), lock anchor=missing (0); expected 1 each); supply SUPERVISOR_SH_PRE_IP9Z or restore the ip9z backoff fix and restore the ip9z lock probe, because this harness does not pass a control it did not run' ]; then
  echo 'HARNESS REFUSES: ip9z refusal-message fixture failed' >&2
  exit 3
elif [ "$(grep -Fxc "$ip9z_message_call" "$0")" != 1 ]; then
  echo 'HARNESS REFUSES: ip9z refusal call-site arm failed' >&2
  exit 3
fi
if [ -z "${SUPERVISOR_SH_PRE_IP9Z:-}" ]; then
  SUPERVISOR_SH_PRE_IP9Z="$scratch/pre-ip9z.src"
  # shellcheck disable=SC2016  # literal source spellings are the mutation anchors
  ip9z_backoff_anchor='  if [ "$n" -ge 5 ]; then mins=60; else mins=$((4 << (n - 1))); fi'
  # shellcheck disable=SC2016  # literal source spellings are the mutation anchors
  ip9z_lock_anchor='  ( flock -n -s -E 75 9 ) 9<"$lock_file" 2>/dev/null || lock_rc=$?'
  backoff_hits="$(grep -Fxc "$ip9z_backoff_anchor" "$subject")"
  lock_hits="$(grep -Fxc "$ip9z_lock_anchor" "$subject")"
  if [ "$backoff_hits" != 1 ] || [ "$lock_hits" != 1 ]; then
    if [ "$backoff_hits" = 0 ]; then backoff_anchor="missing (0)"
    elif [ "$backoff_hits" = 1 ]; then backoff_anchor="unique (1)"
    else backoff_anchor="duplicated ($backoff_hits)"; fi
    if [ "$lock_hits" = 0 ]; then lock_anchor="missing (0)"
    elif [ "$lock_hits" = 1 ]; then lock_anchor="unique (1)"
    else lock_anchor="duplicated ($lock_hits)"; fi
    attribution="$(ip9z_anchor_attribution b7 "$b7_failed" "$backoff_hits" 'ip9z backoff fix')$(ip9z_anchor_attribution b8 "$b8_failed" "$lock_hits" 'ip9z lock probe')"
    ip9z_refusal "$attribution" "$subject" "$backoff_anchor" "$lock_anchor" "$b7_failed" "$backoff_hits" "$b8_failed" "$lock_hits" >&2
    exit 3
  fi
  # shellcheck disable=SC2016  # sed patterns and replacements intentionally carry literal shell syntax
  sed -e 's@^  if \[ "$n" -ge 5 \]; then mins=60; else mins=\$((4 << (n - 1))); fi$@  mins=$((4 << (n - 1))); [ "$mins" -gt 60 ] \&\& mins=60@' \
      -e 's@^  ( flock -n -s -E 75 9 ) 9<"\$lock_file" 2>/dev/null || lock_rc=\$?$@  if flock -n 9 2>/dev/null 9>>"$lock_file"; then lock_rc=0; else lock_rc=75; fi@' \
      "$subject" > "$SUPERVISOR_SH_PRE_IP9Z"
fi
if [ -s "$SUPERVISOR_SH_PRE_IP9Z" ]; then
  ip9z_sup_save="$sup"
  render "$SUPERVISOR_SH_PRE_IP9Z" "$scratch/pre-ip9z.sh" && sup="$scratch/pre-ip9z.sh"
  R7="$scratch/state/r7"; mkdir -p "$R7"
  fire "$R7" "$scratch/ready-two.json"
  u="$(grep -o -- '--setenv FLEET_AUTOSTART=[^ ]*' "$log" | head -1 | cut -d= -f2)"
  outcome_into "$R7" "$u" 0 drained 2
  printf 'last_autostart_unit=%s\nbackoff_n=61\nbackoff_until=2020-01-01T00:00:00-08:00\nskips=0\n' "$u" > "$R7/supervisor.backoff"
  fire "$R7" "$scratch/ready-two.json"
  pu="$(grep -m1 '^backoff_until=' "$R7/supervisor.backoff" | cut -d= -f2-)"
  pe="$(date -d "$pu" +%s 2>/dev/null || echo 0)"
  if [ "$pe" -le "$(date +%s)" ]; then
    ok "RED (ip9z 7): the pre-fix supervisor computes a back-off window ALREADY IN THE PAST at step 62 ($pu) -- every later firing escapes it and emits fleet.backoff, so b7 can fail"
  else bad "the pre-fix supervisor did not reproduce the overflow (until=$pu)"; fi
  R8="$scratch/state/r8"; mkdir -p "$R8"
  : > "$R8/fleet.lock"; chmod 0444 "$R8/fleet.lock"
  fire "$R8" "$scratch/ready-two.json"
  if [ $rc = 75 ]; then
    ok "RED (ip9z 8): the pre-fix supervisor reads an UNWRITABLE lock file as a live run and exits 75 -- the phantom 'live', so b8 can fail"
  else bad "the pre-fix supervisor did not reproduce the phantom live (rc=$rc)"; fi
  chmod 0644 "$R8/fleet.lock"
  sup="$ip9z_sup_save"
else
  # SUPERVISOR_SH_PRE_IP9Z is an explicit override for the derived pre-ip9z
  # control. An empty or unreadable override cannot establish either inversion.
  echo "HARNESS REFUSES: could not read the supplied ip9z 7/8 inversion at $SUPERVISOR_SH_PRE_IP9Z, and this harness does not pass a control it did not run" >&2
  exit 3
fi
# a quick zero-launch drain that was NOT ours (a person's run, autostart empty): no back-off
outcome "" 0 drained 2
fire "$B" "$scratch/ready-two.json"
if [ $rc = 0 ] && grep -q SYSTEMD-RUN "$log"; then
  ok "b5 (s49w): a quick zero-launch drain by a run this supervisor did NOT start is not held against it -> a run starts"
else bad "b5 (s49w): (rc=$rc out='$out')"; fi
u3="$(grep -o 'manyhalls-fleet-run-[0-9T]*' "$log" | head -1)"
# a zero-launch run that LASTED (a parked merge landing: verifier time) is work, not a wedge
outcome "$u3" 0 drained 45
sleep 1.1   # unit names carry one-second resolution; b7 needs the unit this fire starts to DIFFER from u3
fire "$B" "$scratch/ready-two.json"
if [ $rc = 0 ] && grep -q SYSTEMD-RUN "$log"; then
  ok "b6 (s49w): our zero-launch run that lasted 45 s (a landing) is not a wedge -> a run starts (the duration is the discriminator)"
else bad "b6 (s49w): (rc=$rc out='$out')"; fi
u4="$(grep -o 'manyhalls-fleet-run-[0-9T]*' "$log" | head -1)"
# a halted last run writes no record: the record still names an OLDER unit -> no back-off
outcome "$u3" 0 drained 2
fire "$B" "$scratch/ready-two.json"
if [ $rc = 0 ] && grep -q SYSTEMD-RUN "$log"; then
  ok "b7 (s49w): the outcome record names an older unit than the last start ($u3 != $u4, the halted-last-run shape) -> not ours to judge, a run starts"
else bad "b7 (s49w): (rc=$rc out='$out')"; fi

# --- the kill switch (the Warden, round one, finding 2): disabled is nothing to do ----
printf 'FLEET_ENABLED=0\n' > "$fort/fort/scripts/fleet.conf"
fire "$S" "$scratch/ready-two.json"
if [ $rc = 0 ] && [ -z "$out" ] && ! grep -q 'SYSTEMD-RUN\|^BD\|EMIT' "$log"; then
  ok "disabled: FLEET_ENABLED=0 with 2 ready -> exit 0, no output, bd not consulted, no launch, no event"
else bad "disabled: (rc=$rc out='$out' calls=$(wc -l < "$log"))"; fi
rm -f "$fort/fort/scripts/fleet.conf"
fire "$S" "$scratch/ready-two.json"
# INVERTED under Proofdelve ForgeOs-81p9 (the Warden, dx34.4 round two, finding 2): an unreadable
# config used to read as disabled and exit 0 silently; it is an OUTAGE and now
# refuses at 64 with one stderr line naming the file, like bd not answering.
# Disabled (the case above) stays silent. Against the pre-81p9 file this FAILS.
if [ $rc = 64 ] && grep -q "no readable fleet config at $fort/fort/scripts/fleet.conf" <<<"$out" && [ "$(printf '%s' "$out" | wc -l)" = 0 ] && ! grep -q 'SYSTEMD-RUN\|^BD\|EMIT' "$log"; then
  ok "no-conf (81p9): an unreadable fleet.conf is an OUTAGE -> exit 64, ONE stderr line naming the config, bd not consulted, no launch, no event"
else bad "no-conf (81p9): (rc=$rc out='$out' calls=$(wc -l < "$log"))"; fi
printf 'FLEET_ENABLED=1\n' > "$fort/fort/scripts/fleet.conf"
fire "$S" "$scratch/ready-two.json"
if [ $rc = 0 ] && grep -q '^SYSTEMD-RUN' "$log"; then ok "enabled-again: the switch is read on every firing (vacuity control for the two above)"; else bad "enabled-again: no launch after re-enabling (rc=$rc)"; fi

# --- refusals are loud: bd down, and the launch failing -------------------------
BD_MODE=down fire "$S" "$scratch/ready-two.json"
if [ $rc = 64 ] && grep -q 'bd would not answer' <<<"$out" && ! grep -q SYSTEMD-RUN "$log"; then
  ok "bd-down: exit 64, one stderr line naming bd, no launch (an outage is not 'nothing to do')"
else bad "bd-down: (rc=$rc out='$out')"; fi
SYSTEMD_RUN_RC=1 fire "$S" "$scratch/ready-two.json"
if [ $rc = 64 ] && grep -q 'systemd-run could not start' <<<"$out" && ! grep -q 'EMIT fleet.autostart' "$log"; then
  ok "launch-fail: systemd-run failing -> exit 64, named on stderr, NO fleet.autostart recorded for a run that did not start"
else bad "launch-fail: (rc=$rc out='$out')"; fi

# --- criterion 6: the masked-seat refusal, before anything is read or written ---
T="$scratch/state/masked"; mkdir -p "$T"; hold_lock "$T"
MASKED=mayor fire "$T" "$scratch/ready-two.json"
if [ $rc = 64 ] && grep -q 'REFUSED — this is a masked seat' <<<"$out" && [ ! -e "$T/supervisor.streak" ] && [ ! -s "$log" ]; then
  ok "c6: FORT_MASKED set -> exit 64 naming the mask, no streak write even under a held lock, no bd, no launch"
else bad "c6: masked (rc=$rc out='$out' streak=$(sha "$T/supervisor.streak"))"; fi
release_lock

# --- criterion 7: the record is findable --------------------------------------------
SUP_ARGS=(--status); fire "$S" "$scratch/ready-empty.json"; SUP_ARGS=()
if [ $rc = 0 ] && grep -q '^count=0$' <<<"$out" && grep -q '^previous_streak=2$' <<<"$out"; then
  ok "c7: --status prints the record (count=0, previous_streak=2)"
else bad "c7: --status (rc=$rc out='$out')"; fi
# One awk, no pipe (Proofdelve ForgeOs-pyte): the usage block is >8 KiB, so `awk | grep -q`
# under pipefail raced -- grep -q exited on the first match, awk's second write
# took SIGPIPE, and a TRUE predicate scored FAIL 34 times in 300 idle runs.
if grep -q 'supervisor.streak' "$subject" && awk '/^[^#]/{exit} /first_refusal=/{found=1} END{exit !found}' "$subject"; then
  ok "c7b: the usage block names the record's path and its keys"
else bad "c7b: usage block does not document the record"; fi

# ============================================================================
# --- Proofdelve ForgeOs-dx34.18 criterion 5: leftovers start a run when nothing is ready ---
# The stub fleet.sh answers --reapable from STUB_REAPABLE; the supervisor must ask
# it ONLY when bd ready is empty, start a run on a nonzero answer, and treat a
# failed query as a refusal rather than as zero.
D="$scratch/state/d"; mkdir -p "$D"
STUB_REAPABLE=1 fire "$D" "$scratch/ready-empty.json"
if [ $rc = 0 ] && grep -q '^STUB fleet.sh ran: --reapable$' "$log" && [ "$(grep -c SYSTEMD-RUN "$log")" = 1 ] \
   && grep -q 'EMIT fleet.autostart.*reapable worker' "$log" && grep -q '"reapable":1' "$log" && grep -q 'started manyhalls-fleet-run-' <<<"$out"; then
  ok "dx34.18 c5: queue empty, fleet.sh --reapable says 1 -> ONE run started, fleet.autostart names the reapable worker and carries reapable=1"
else bad "dx34.18 c5: leftover pickup (rc=$rc out='$out' log=$(tr '\n' '|' < "$log" | cut -c1-300))"; fi
STUB_REAPABLE=0 fire "$D" "$scratch/ready-empty.json"
if [ $rc = 0 ] && [ -z "$out" ] && grep -q '^STUB fleet.sh ran: --reapable$' "$log" && ! grep -q SYSTEMD-RUN "$log"; then
  ok "dx34.18 c5 vacuity: queue empty, --reapable says 0 -> asked, and nothing started (c2's silence is now a measured zero, not an unasked question)"
else bad "dx34.18 c5 vacuity: (rc=$rc out='$out' log=$(tr '\n' '|' < "$log" | cut -c1-200))"; fi
STUB_REAPABLE=1 fire "$D" "$scratch/ready-two.json"
if [ $rc = 0 ] && ! grep -q -- '--reapable' "$log" && [ "$(grep -c SYSTEMD-RUN "$log")" = 1 ] && grep -q '"candidates":2,"reapable":null' "$log"; then
  ok "dx34.18 c5: with beads READY the reapable question is not asked (payload reapable=null, not 0) and the start names the beads (common path unchanged)"
else bad "dx34.18 c5 ready-path: (rc=$rc log=$(tr '\n' '|' < "$log" | cut -c1-300))"; fi
STUB_REAPABLE_RC=1 fire "$D" "$scratch/ready-empty.json"
if [ $rc = 64 ] && grep -q -- <<<"$out" '--reapable did not answer' && ! grep -q SYSTEMD-RUN "$log"; then
  ok "dx34.18 c5: a failing --reapable query is a REFUSAL (exit 64, named), not a zero"
else bad "dx34.18 c5 query-failure: (rc=$rc out='$out')"; fi
STUB_REAPABLE=1 fire "$D" "$scratch/ready-empty.json"   # the RED for the inversion below reads this same fixture

# THE CONTROLS: three sabotaged variants, each must FAIL its own case.
# ============================================================================
variant() {  # $1 name, $2 sed expr, $3 expected-once pattern -> path or NOT RUN
  local src="$scratch/variant-$1.src" dst="$scratch/variant-$1.sh" n
  n="$(grep -c -- "$3" "$subject")"
  if [ "$n" != 1 ]; then skip "control $1: anchor '$3' found $n times in the shipped file (expected 1)"; return 1; fi
  sed -e "$2" "$subject" > "$src"
  render "$src" "$dst" || { skip "control $1: render refused"; return 1; }
  sup="$dst"
}
orig_sup="$scratch/supervisor.sh"

# shellcheck disable=SC2016  # the sed expressions and anchors below are literal by design
# (a) a supervisor that DISCARDS refusals (never advances the count): c4b must fail.
# shellcheck disable=SC2016
if variant discards 's/^count=\$((count + 1))$/count=$count/' '^count=\$((count + 1))$'; then
  V="$scratch/state/va"; mkdir -p "$V"; hold_lock "$V"
  fire "$V" "$scratch/ready-two.json"; fire "$V" "$scratch/ready-two.json"
  c="$(val "$V" count)"
  if [ $rc = 75 ] && [ "$c" != 2 ]; then ok "control discards: the variant exits 75 exactly like the shipped file and count='$c' — c4b would FAIL, so c4b discriminates counting from discarding"; else bad "control discards: variant still counts (count='$c')"; fi
  release_lock
fi
sup="$orig_sup"
# (b) a supervisor that NEVER RESETS: c5 must fail.
# shellcheck disable=SC2016
if variant noreset 's/^  if \[ -n "\$count" \] && \[ "\$count" != 0 \]; then$/  if false; then/' '^  if \[ -n "\$count" \] && \[ "\$count" != 0 \]; then$'; then
  V="$scratch/state/vb"; mkdir -p "$V"; hold_lock "$V"
  fire "$V" "$scratch/ready-two.json"; fire "$V" "$scratch/ready-two.json"
  release_lock
  fire "$V" "$scratch/ready-empty.json"
  c="$(val "$V" count)"
  if [ $rc = 0 ] && [ "$c" = 2 ]; then ok "control noreset: after the run ends the variant leaves count=2 — c5 would FAIL, so c5 discriminates a reset from a monotone counter"; else bad "control noreset: variant reset anyway (count='$c')"; fi
fi
sup="$orig_sup"
# (c) a supervisor that READS PAST the halt file: the halt case must fail.
# shellcheck disable=SC2016
if variant haltbypass 's/^\[ -e "\$halt_file" \] && exit 0$/true/' '^\[ -e "\$halt_file" \] && exit 0$'; then
  V="$scratch/state/vc"; mkdir -p "$V"; touch "$V/HALT"
  fire "$V" "$scratch/ready-two.json"
  if grep -q SYSTEMD-RUN "$log"; then ok "control haltbypass: the variant STARTS a run under a halt file — the halt case would FAIL, so it discriminates"; else bad "control haltbypass: variant did not start under a halt file"; fi
fi
sup="$orig_sup"

echo "RESULT: $pass pass / $fail fail / $notrun not run"
[ $fail = 0 ] && [ $notrun = 0 ]
