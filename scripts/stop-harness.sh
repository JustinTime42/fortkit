#!/bin/bash
# Harness for fleet.sh's STOP PATH (Proofdelve ForgeOs-a2fx): the signal trap, the reason
# that reaches the fleet.ended payload, and the leftovers report. Tests the
# SHIPPED functions and the SHIPPED trap string, extracted from the real
# launcher. Refuses on an empty or partial extraction.
#
# HOW IT INVERTS, which is the part worth reading before trusting a green run.
# Two of these cases are asked of code that exists in BOTH files — the EXIT trap
# string — so against the pre-a2fx fleet.sh they FAIL rather than refuse, and
# that is the positive control: the trap there emits no `interrupted` field, so
# a killed run and a drained one are the same event. The rest are asked of
# functions a2fx introduces, so against that file this harness REFUSES at
# extraction. Both are inversions; a harness that scored a clean pass against a
# file lacking the code would be measuring nothing (Proofdelve ForgeOs-5m7a round two, and
# the landable-harness vacuity lesson).
set -uo pipefail
launcher="${FLEET_SH:-$(dirname "$0")/../fort/scripts/fleet.sh}"
printf 'launcher=%s\n' "$launcher"
[ -f "$launcher" ] || { echo "HARNESS REFUSES: launcher is missing: $launcher" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

awk '/^set_end_reason\(\)[[:space:]]*\{/{f=1} /^on_signal\(\)[[:space:]]*\{/{f=1} /^report_leftovers\(\)[[:space:]]*\{/{f=1} /^say\(\)[[:space:]]*\{/{f=1} /^warn\(\)[[:space:]]*\{/{f=1} /^worker_state\(\)[[:space:]]*\{/{f=1} /^worker_set_state\(\)[[:space:]]*\{/{f=1} /^worker_reason\(\)[[:space:]]*\{/{f=1} /^worker_explain\(\)[[:space:]]*\{/{f=1} /^parked_merges\(\)[[:space:]]*\{/{f=1} /^report_parked_merges\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{f=0}' \
  "$launcher" > "$work/stop.sh"
# The predicates are one-liners and do not end at a bare `}`; take them whole
# by line instead. report_leftovers speaks through the Proofdelve ForgeOs-w7u5 lifecycle
# owner, so worker_state and its predicates are part of this subject now.
grep -E '^(signalled|stopping|worker_live|worker_needs_person|worker_reapable)\(\)[[:space:]]*\{' "$launcher" >> "$work/stop.sh" 2>/dev/null || true


# THE SHIPPED EXIT TRAP STRING, taken from the real file rather than retyped.
# Everything between the first `trap '` and the trailing `' EXIT`.
trapbody="$(sed -n "s/^trap '\(.*\)' EXIT$/\1/p" "$launcher")"
[ -n "$trapbody" ] || { echo "HARNESS REFUSES: no EXIT trap string found in $launcher" >&2; exit 3; }

pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }

# say() AND warn() ARE REAL, EACH ON THE STREAM ITS CONTRACT NAMES. A
# say(){ :; } stub is exactly why the governor harness could not catch
# Proofdelve ForgeOs-0d0i: it silenced the write that broke the caller.
harness() { # $@ = shell body
  bash -c "set -uo pipefail
    run_id=T; launches=2; fleet_actor=fleet; halt_file='$work/HALT'
    state='$work/state'; FLEET_LAUNCH_GRACE=120
    narrative_log='$work/harness-narrative.log'
    end_reason=drained; halted=false
    stop_signal=''; interrupted=false; stop_requested=0; exit_code=0
    emit(){ printf 'EMIT %s\n' \"\$*\"; }
    say(){ printf 'SAY %s\n' \"\$*\"; }
    warn(){ printf 'WARN %s\n' \"\$*\" >&2; }
    $(cat "$work/stop.sh")
    $*"
}
# The trap body is evaluated by a shell that has ONLY the variables it reads,
# so a trap referring to something undeclared fails loudly instead of silently.
trap_out() { # $1 end_reason  $2 interrupted  $3 stop_signal  $4 halted
  bash -c "set -uo pipefail
    run_id=T; launches=2; fleet_actor=fleet
    end_reason='$1'; interrupted=$2; stop_signal='$3'; halted=$4
    # stalled is a payload field since Proofdelve ForgeOs-dx34.9. Declared false here: no
    # case in this harness ends a run through stall_check(), and the trap must
    # still evaluate against a launcher that carries the field.
    stalled=false; stall_peak=0
    emit(){ printf 'EMIT %s\n' \"\$*\"; }
    $trapbody" 2>&1
}

# ---------------------------------------------------------------------------
# 1-2  THE DISTINCTION SURVIVES INTO THE PAYLOAD, not only into the prose.
# These two are asked of code that exists in both files. Case 1 FAILS against
# the pre-a2fx launcher; case 2 is its vacuity control.
# ---------------------------------------------------------------------------
out="$(trap_out 'interrupted by SIGINT' true INT false)"
if grep -q '"interrupted":true' <<<"$out" \
   && grep -q '"signal":"INT"' <<<"$out" \
   && grep -q '"reason":"interrupted by SIGINT"' <<<"$out"; then
  ok "a killed run's fleet.ended payload says so: interrupted=true, signal=INT"
else no "the payload cannot distinguish a killed run from a drained one" "$out"; fi

out="$(trap_out drained false '' false)"
if grep -q '"interrupted":false' <<<"$out" \
   && grep -q '"reason":"drained"' <<<"$out" \
   && ! grep -q '"signal":"INT"' <<<"$out"; then
  ok "vacuity control: an uninterrupted run still reports drained, interrupted=false"
else no "vacuity control: the payload reports interruption unconditionally" "$out"; fi

# ASSERT EVERY SYMBOL THIS HARNESS DEPENDS ON, BY NAME. landable-harness.sh
# checked one extracted symbol, the code was split under it, and the missing
# function then read as a satisfied condition while the vacuity control PASSED
# (Proofdelve ForgeOs-5m7a, Regent 2026-09-04). A missing function must never be able to
# look like a met expectation.
missing=""
# report_parked_merges JOINED THE SUBJECT WITH Proofdelve ForgeOs-dx34.1's B2, and its
# absence from this list was live for one commit: report_leftovers gained a call
# to it, this harness did not extract it, and every leftovers case here ran
# against a function whose last statement died `command not found` — on stderr,
# under a `bash -c` with no `set -e`, so the cases still scored PASS. A harness
# that keeps passing while the code under it half-executes is the Proofdelve ForgeOs-8zb7
# class C failure with the volume turned down. Caught by reading this harness's
# stderr while adding the ke5u cases below, not by the score.
for f in set_end_reason signalled stopping on_signal report_leftovers report_parked_merges parked_merges worker_state worker_explain; do
  grep -qE "^$f\(\)[[:space:]]*\{" "$work/stop.sh" || missing="${missing:+$missing }$f"
done
if [ -n "$missing" ]; then
  echo
  echo "PARTIAL RESULT $pass pass / $fail fail (cases 1-2 only)"
  echo "HARNESS REFUSES the remaining cases: these symbols are absent from $launcher: $missing" >&2
  echo "  Against a launcher that predates Proofdelve ForgeOs-a2fx (no stop path) or Proofdelve ForgeOs-w7u5 (no" >&2
  echo "  lifecycle owner) that is the expected outcome and is itself the finding. Cases 1-2" >&2
  echo "  above have already run against the shipped EXIT trap either way." >&2
  exit 3
fi
n=$(wc -l < "$work/stop.sh")
[ "$n" -ge 20 ] || { echo "HARNESS REFUSES: extracted $n lines" >&2; exit 3; }
echo "extracted $n lines of shipped stop-path code from $launcher"

# ---------------------------------------------------------------------------
# 3-5  on_signal sets every variable the rest of the file branches on.
# ---------------------------------------------------------------------------
out="$(harness "on_signal INT; echo R=\$end_reason; echo I=\$interrupted; echo S=\$stop_signal; echo Q=\$stop_requested; echo X=\$exit_code")"
if grep -q 'R=interrupted by SIGINT' <<<"$out" \
   && grep -q 'I=true' <<<"$out" && grep -q 'S=INT' <<<"$out" \
   && grep -q 'Q=1' <<<"$out" && grep -q 'X=130' <<<"$out"; then
  ok "on_signal INT sets reason, the JSON literal, the signal, the stop flag and exit 130"
else no "on_signal INT leaves the run describing itself as drained" "$out"; fi

out="$(harness "on_signal TERM; echo X=\$exit_code; echo R=\$end_reason")"
if grep -q 'X=143' <<<"$out" && grep -q 'R=interrupted by SIGTERM' <<<"$out"; then
  ok "on_signal TERM exits 143 and names SIGTERM"
else no "on_signal TERM" "$out"; fi

# A SECOND Ctrl-C MUST NOT REWRITE THE RECORD OF THE FIRST.
out="$(harness "on_signal INT; on_signal TERM; echo R=\$end_reason; echo X=\$exit_code")"
if grep -q 'R=interrupted by SIGINT' <<<"$out" && grep -q 'X=130' <<<"$out"; then
  ok "a second signal does not rewrite the first signal's record"
else no "the last signal wins, so the recorded reason is whichever arrived last" "$out"; fi

# ---------------------------------------------------------------------------
# 6  THE TWO PREDICATES ARE NOT THE SAME QUESTION, and the difference is what
# keeps a halt-file stop from being described as a signal. Every misattribution
# guard in fleet.sh asks signalled(); the loop asks stopping().
# ---------------------------------------------------------------------------
out="$(harness "stop_requested=1; stopping && echo STOPPING; signalled && echo SIGNALLED; echo END")"
if grep -q 'STOPPING' <<<"$out" && ! grep -q 'SIGNALLED' <<<"$out"; then
  ok "a halt-file stop is stopping but NOT signalled"
else no "stopping and signalled are the same predicate" "$out"; fi
out="$(harness "on_signal INT >/dev/null; stopping && echo STOPPING; signalled && echo SIGNALLED")"
if grep -q 'STOPPING' <<<"$out" && grep -q 'SIGNALLED' <<<"$out"; then
  ok "a signal stop is both stopping and signalled"
else no "a signal does not register as signalled" "$out"; fi

# ---------------------------------------------------------------------------
# 7-10  report_leftovers names what the run is walking away from.
# ---------------------------------------------------------------------------
mkdir -p "$work/state/workers"
# 7 VACUITY CONTROL FIRST: with nothing to report it must say so in a sentence,
# or "no output" and "nothing left behind" are indistinguishable to a reader.
out="$(harness "report_leftovers")"
if grep -q 'leaves nothing behind' <<<"$out"; then
  ok "vacuity control: an empty state says 'leaves nothing behind' out loud"
else no "an empty state reports nothing at all" "$out"; fi

mkdir -p "$work/state/workers/unreaped"
printf 'fortkit-unreaped\n' > "$work/state/workers/unreaped/bead"
printf '0\n' > "$work/state/workers/unreaped/exit"
out="$(harness "report_leftovers")"
if grep -q 'NOT YET REAPED' <<<"$out" && grep -q 'fortkit-unreaped' <<<"$out" \
   && grep -qi 'the next run verifies' <<<"$out"; then
  ok "a finished-but-unreaped worker is named, with what will pick it up"
else no "an unreaped worker is left unmentioned" "$out"; fi

mkdir -p "$work/state/workers/alive"
printf 'fortkit-alive\n' > "$work/state/workers/alive/bead"
sleep 30 & alive_pid=$!
printf '%s\n' "$alive_pid" > "$work/state/workers/alive/pid"
out="$(harness "report_leftovers")"
if grep -q 'RUNNING — its Forge is alive' <<<"$out" && grep -q 'fortkit-alive' <<<"$out"; then
  ok "a live detached Forge is named and is NOT claimed to be dead"
else no "a live Forge is misreported" "$out"; fi
kill "$alive_pid" 2>/dev/null; wait "$alive_pid" 2>/dev/null

mkdir -p "$work/state/workers/orphan"
printf 'fortkit-orphan\n' > "$work/state/workers/orphan/bead"
printf '4194303\n' > "$work/state/workers/orphan/pid"   # a pid that cannot exist
out="$(harness "report_leftovers")"
if grep -q 'NEEDS A PERSON' <<<"$out" && grep -q 'fortkit-orphan' <<<"$out"; then
  ok "a worker with no exit code and a dead pid is escalated to a person, not counted as fine"
else no "an orphaned worker is reported as ordinary" "$out"; fi

# 11 a settled worker is not reported at all — the report must be about what is
# LEFT, or a busy successful run buries its own leftovers in a list.
mkdir -p "$work/state/workers/settled"
printf 'fortkit-settled\n' > "$work/state/workers/settled/bead"
printf '0\n' > "$work/state/workers/settled/exit"; touch "$work/state/workers/settled/done"
out="$(harness "report_leftovers")"
if ! grep -q 'fortkit-settled' <<<"$out"; then
  ok "a worker that is finished with is not reported as left behind"
else no "the report includes workers nothing further will happen to" "$out"; fi


# ---------------------------------------------------------------------------
# 12-15  Proofdelve ForgeOs-dx34.3: THE NARRATIVE IS DURABLE, AND A DEAD TERMINAL CANNOT
# TAKE THE RUN DOWN. The end-to-end proof is a pty whose master is closed under
# a live run (recorded on the bead); these are the mechanical guards, so the
# property survives the next edit to say().
# ---------------------------------------------------------------------------
nh() { # $@ = shell body, with the REAL say()/warn() rather than this harness's stubs
  bash -c "set -uo pipefail
    narrative_log='$work/narrative.log'
    $(sed -n '/^say()[[:space:]]*{/,/^}$/p;/^warn()[[:space:]]*{/,/^}$/p' "$work/stop.sh")
    $*"
}
rm -f "$work/narrative.log"
if ! grep -qE "^trap '' HUP" "$launcher"; then
  no "SIGHUP is ignored, so a closed terminal does not kill the run" \
     "$launcher installs no HUP trap: a hand-launched run still dies with its terminal"
else
  ok "SIGHUP is ignored, so a closed terminal does not kill the run"
fi
if ! grep -q 'narrative_log=' "$launcher"; then
  no "the narrative has a durable home" "$launcher defines no narrative log: the timeline exists only in the terminal"
  no "say() survives a closed stdout" "same"
  no "warn() reaches the log as well as stderr" "same"
else
  out="$(nh "say 'hello there'" 2>/dev/null)"
  if grep -q 'hello there' <<<"$out" && grep -q 'hello there' "$work/narrative.log"; then
    ok "the narrative has a durable home: say() writes to the log AND to stdout"
  else no "say() does not reach both" "stdout=$out log=$(cat "$work/narrative.log" 2>/dev/null)"; fi

  # THE LOAD-BEARING ONE. Once the terminal is gone, writing to stdout returns
  # EIO; an unguarded printf in say() would end the run under `set -e` at its
  # next narrative line, so "survives a closed terminal" would become "dies a
  # few seconds later from a different cause". Closing fd 1 reproduces that
  # without a pty.
  rm -f "$work/narrative.log"
  rc=0; nh "exec 1>&-; say 'after the terminal went away'; exit 0" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 0 ] && grep -q 'after the terminal went away' "$work/narrative.log"; then
    ok "say() survives a closed stdout: it returns success and the log still gets the line"
  else no "a dead terminal takes the run down or loses the line" "rc=$rc log=$(cat "$work/narrative.log" 2>/dev/null)"; fi

  rm -f "$work/narrative.log"
  err="$(nh "warn 'something odd'" 2>&1 >/dev/null)"
  if grep -q 'something odd' <<<"$err" && grep -q 'something odd' "$work/narrative.log"; then
    ok "warn() reaches the log as well as stderr, and still keeps stdout clean"
  else no "warn() does not reach both, or polluted stdout" "stderr=$err log=$(cat "$work/narrative.log" 2>/dev/null)"; fi
fi

# ---------------------------------------------------------------------------
# Proofdelve ForgeOs-ke5u ACCEPTANCE 4 — THE TWO FALSE LINES. A worker abandoned in-hand by
# a signalled run produced two records that disagreed: the interrupting run's
# leftovers report said "IN HAND ... No action", and the NEXT run's report said
# ORPHANED and demanded a person. The second of those also asserted "no exit
# code and no live process" for a worker that HAD an exit code and had passed
# its verifier. ke5u removes the state that reaches them; these two cases pin
# the lines themselves, because the state is reachable by other routes.
mkworker() { # $1 sfx, $2 state line, $3 exit code ("" for none), $4 pid ("")
  local d="$work/state/workers/$1"; mkdir -p "$d"
  printf 'E2E-%s\n' "$1" > "$d/bead"
  printf '%s\n' "$2" > "$d/state"
  [ -n "$3" ] && printf '%s\n' "$3" > "$d/exit"
  [ -n "$4" ] && printf '%s\n' "$4" > "$d/pid"
  printf '%s' "$d"
}

# 1 THE ORPHANED LINE MUST REPORT WHAT IS THERE, NOT ASSERT WHAT IS NOT. A
#   worker orphaned WITH an exit code is the ke5u shape; the old line called it
#   "no exit code and no live process" and a person acts on that.
d=$(mkworker o1 'in-hand|ANOTHERRUN|taken and never settled' 0 '')
out="$(harness "worker_explain '$d'")"
if grep -q ORPHANED <<<"$out" \
   && grep -q 'its Forge exited 0' <<<"$out" \
   && ! grep -q 'no exit code' <<<"$out"; then
  ok "ke5u: an ORPHANED worker that HAS an exit code reports it instead of denying it"
else no "the ORPHANED line still asserts unchecked facts" "$out"; fi

# 2 AND IT MUST STILL SAY SO WHEN THERE GENUINELY IS NONE — both directions,
#   because a line that reports the same thing either way discriminates nothing.
d=$(mkworker o2 'in-hand|ANOTHERRUN|taken and never settled' '' '')
out="$(harness "worker_explain '$d'")"
if grep -q ORPHANED <<<"$out" \
   && grep -q 'no exit code was ever written' <<<"$out" \
   && grep -q 'no pid was ever written' <<<"$out"; then
  ok "ke5u: an ORPHANED worker with nothing written says exactly that (the other direction)"
else no "the ORPHANED line does not discriminate" "$out"; fi

# 3 THE IN-HAND LINE MUST NOT PROMISE "No action" WITHOUT SAYING WHAT HAPPENS IF
#   THE RUN ENDS. It is printed by report_leftovers on the way OUT of a run, so
#   the reader is looking at it precisely when the run is about to stop.
d=$(mkworker o3 'in-hand|T|taken by this run' '' '')
out="$(harness "worker_explain '$d'")"
if grep -q 'IN HAND' <<<"$out" \
   && grep -q 'ORPHANED' <<<"$out" \
   && grep -q 'need a person' <<<"$out"; then
  ok "ke5u: the IN HAND line names what happens if the run ends without settling the worker"
else no "the IN HAND line still says 'No action' unconditionally" "$out"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ $fail -eq 0 ]
