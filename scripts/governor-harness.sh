#!/bin/bash
# Harness for fleet.sh's budget governor (Proofdelve ForgeOs-9mfw.4). Tests the SHIPPED
# functions, extracted from the real launcher, against crafted logs. Refuses on
# an empty extraction.
set -uo pipefail
# The default must be the fleet launcher in this harness's own tree. An absolute
# path silently scores main when this file is run from a candidate worktree.
# FLEET_SH remains the explicit override for positive controls.
launcher="${FLEET_SH:-$(dirname "$0")/../fort/scripts/fleet.sh}"
printf 'launcher=%s\n' "$launcher"
[ -f "$launcher" ] || { echo "HARNESS REFUSES: launcher is missing: $launcher" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
awk '/^looks_rate_limited\(\)[[:space:]]*\{/{f=1} /^looks_env_failure\(\)[[:space:]]*\{/{f=1} /^env_halt_if\(\)[[:space:]]*\{/{f=1} /^governor_init\(\)[[:space:]]*\{/{f=1} /^governor_down\(\)[[:space:]]*\{/{f=1} /^governor_up_maybe\(\)[[:space:]]*\{/{f=1} /^spend\(\)[[:space:]]*\{/{f=1} /^budget_left\(\)[[:space:]]*\{/{f=1} /^budget_stop\(\)[[:space:]]*\{/{f=1} /^set_end_reason\(\)[[:space:]]*\{/{f=1} /^live_forges\(\)[[:space:]]*\{/{f=1} /^reapable_workers\(\)[[:space:]]*\{/{f=1} /^returns_of\(\)[[:space:]]*\{/{f=1} /^worker_state\(\)[[:space:]]*\{/{f=1} /^worker_set_state\(\)[[:space:]]*\{/{f=1} /^worker_reason\(\)[[:space:]]*\{/{f=1} /^worker_explain\(\)[[:space:]]*\{/{f=1} /^worker_resume_at\(\)[[:space:]]*\{/{f=1} /^worker_reap_worktree\(\)[[:space:]]*\{/{f=1} /^defer_merge\(\)[[:space:]]*\{/{f=1} /^reap_pass\(\)[[:space:]]*\{/{f=1} /^reap_order\(\)[[:space:]]*\{/{f=1} /^verdict_is_landable\(\)[[:space:]]*\{/{f=1} /^verdict_files_followup\(\)[[:space:]]*\{/{f=1} /^page_overseer\(\)[[:space:]]*\{/{f=1} /^reason_key\(\)[[:space:]]*\{/{f=1} /^reason_seen\(\)[[:space:]]*\{/{f=1} /^touch_prefix\(\)[[:space:]]*\{/{f=1} /^touch_set_of\(\)[[:space:]]*\{/{f=1} /^deliverable_of\(\)[[:space:]]*\{/{f=1} /^touch_sets_intersect\(\)[[:space:]]*\{/{f=1} /^touch_conflict_with_live\(\)[[:space:]]*\{/{f=1} /^governor_carry_out\(\)[[:space:]]*\{/{f=1} /^governor_carry_reset\(\)[[:space:]]*\{/{f=1} /^prelanding_refresh\(\)[[:space:]]*\{/{f=1} /^stall_check\(\)[[:space:]]*\{/{f=1} /^return_to_ready\(\)[[:space:]]*\{/{f=1} /^bead_status\(\)[[:space:]]*\{/{f=1} /^refill_slots\(\)[[:space:]]*\{/{f=1} /^mem_mb\(\)[[:space:]]*\{/{f=1} /^young_forges\(\)[[:space:]]*\{/{f=1} /^mem_gate_why\(\)[[:space:]]*\{/{f=1} /^mem_stepdown_maybe\(\)[[:space:]]*\{/{f=1} /^host_verify\(\)[[:space:]]*\{/{f=1} /^ask_overseer\(\)[[:space:]]*\{/{f=1} /^overseer_assignee\(\)/{print; next} /^mayor_assignee\(\)/{print; next} /^verify_tier_of\(\)[[:space:]]*\{/{f=1} /^nightly_backstop_ok\(\)[[:space:]]*\{/{f=1} /^stale_signature_check\(\)[[:space:]]*\{/{f=1} /^stored_verdict_is_signable\(\)[[:space:]]*\{/{f=1} /^nightly_why=/{print; next} f{print} /^\}$/{f=0}' \
  "$launcher" > "$work/gov.sh"
# The lifecycle predicates are one-liners and do not end at a bare `}`; take
# them whole by line. Absent from a pre-Proofdelve ForgeOs-w7u5 launcher, which is the
# point: the cases below then FAIL rather than the harness refusing, because
# this instrument still has to be usable against either file.
grep -E '^(worker_(live|reapable|needs_person)|env_signature|touches_(migrations|everything)|governor_carry_file)\(\)[[:space:]]*\{' "$launcher" >> "$work/gov.sh" 2>/dev/null || true
n=$(wc -l < "$work/gov.sh")
[ "$n" -ge 20 ] || { echo "HARNESS REFUSES: extracted $n lines" >&2; exit 3; }
# EVERY SYMBOL THE EXTRACTED CODE CALLS MUST BE DEFINED IN IT, BECAUSE A LINE
# COUNT CANNOT SEE A MISSING CALLEE. On 2026-09-10 reap_pass() gained a call to
# verdict_is_landable(), which the awk list above did not extract: the function
# was simply absent, bash said `command not found` on stderr, the arm FELL
# THROUGH to its needs-person branch, and three cases failed as though the
# LAUNCHER were wrong. Under a runner without `set -e` a missing callee can fall
# through to a branch that PASSES just as easily, which is the Proofdelve ForgeOs-8zb7
# class A shape: a control reporting success while measuring nothing.
#
# TWO LISTS, AND THE SECOND ONE IS CONDITIONAL ON PURPOSE. The first names what
# this harness is ABOUT, and its absence means the awk has stopped matching and
# nothing below is measuring anything. The second names callees that a NEWER
# launcher introduced: requiring them unconditionally would make this instrument
# refuse against every pre-2026-09-10 file, and a harness that refuses against
# the old file proves less than one that fails on it -- the same reason the
# lifecycle predicates above are taken with `have()` rather than gated.
for sym in looks_rate_limited governor_init governor_down governor_up_maybe \
           spend budget_left budget_stop set_end_reason live_forges returns_of \
           worker_state worker_set_state worker_reason worker_explain \
           worker_resume_at worker_reap_worktree defer_merge reap_pass; do
  grep -qE "^$sym\(\)" "$work/gov.sh" \
    || { echo "HARNESS REFUSES: $sym() is not in the extraction" >&2; exit 3; }
done
# Called-but-not-defined is always a defect; not-called-at-all is just an older
# launcher. Add a new callee here when you add a caller, in the same commit.
# page_overseer joined 2026-09-11: reap_pass() calls it on forge.sh's exit 76
# (Proofdelve ForgeOs-lw8x), and a harness that extracts the caller without the callee
# falls through to a branch that can PASS (the 2026-09-10 sighting).
# reason_key/reason_seen joined the same day: defer_merge() and reap_pass()
# call them for the dx34.15 seen-list fingerprint.
# looks_env_failure / env_halt_if / env_signature joined 2026-09-12 (Proofdelve ForgeOs-g3n1):
# reap_pass() consults the environmental signature before the governor does.
# touch_* and touches_* joined 2026-09-14 (Proofdelve ForgeOs-b9mj): touch_set_of() and
# touch_sets_intersect() read the two sentinel one-liners.
# refill_slots and the memory gate (mem_mb, young_forges, mem_gate_why,
# mem_stepdown_maybe) joined 2026-10-15 (Proofdelve ForgeOs-uwjme, Proofdelve ForgeOs-asad6): reap_pass()
# calls refill_slots() at its step boundaries, which calls live_forges() and
# dispatch_pass(); dispatch_pass() is NOT extracted, so every runner that reaches
# a refill stubs it or stubs refill_slots() itself.
# ask_overseer, overseer_assignee and mayor_assignee joined 2026-10-19
# (Proofdelve ForgeOs-29j3g): page_overseer() and return_to_ready() assign the bead.
# nightly_backstop_ok joined 2026-10-20 (s1reg finding 3): host_verify() asks it
# whether a nightly ran; a fixture root with no events reads stale -> tier full.
# host_verify and verify_tier_of joined 2026-10-19 (Proofdelve ForgeOs-s1reg): reap_pass()
# verifies a branch through host_verify(), which picks the tier from the diff;
# without them every verify arm dies "command not found" and reads as RED.
# reap_order joined 2026-10-21 (Proofdelve ForgeOs-jfqu4.7): reap_pass() takes its worker
# list from it, so an extraction without it would reap nothing at all.
# deliverable_of joined 2026-09-18 (Proofdelve ForgeOs-nz3u): reap_pass() consults it at the
# ss9d handoff-only guard; an extraction without it makes every declared bead
# read as undeclared and RETURN, which is the pre-nz3u behaviour exactly.
for sym in verdict_is_landable verdict_files_followup page_overseer reason_key reason_seen \
           looks_env_failure env_halt_if env_signature \
           touch_prefix touch_set_of touch_sets_intersect touch_conflict_with_live touches_migrations touches_everything \
           deliverable_of \
           governor_carry_file governor_carry_out governor_carry_reset prelanding_refresh stall_check \
           reap_order refill_slots mem_mb young_forges mem_gate_why mem_stepdown_maybe host_verify verify_tier_of nightly_backstop_ok ask_overseer overseer_assignee mayor_assignee; do
  if grep -qE "(^|[^[:alnum:]_])$sym([^[:alnum:]_(]|\$)" "$work/gov.sh" \
     && ! grep -qE "^$sym\(\)" "$work/gov.sh"; then
    echo "HARNESS REFUSES: the extracted code CALLS $sym() and does not define it" >&2; exit 3
  fi
done
echo "extracted $n lines of shipped governor and lifecycle code; no callee is undefined"
have(){ grep -qE "^$1\(\)[[:space:]]*\{" "$work/gov.sh"; }

pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }

# clean and dirty fixtures
printf 'restore ok\nbuild ok\n260 passed\n' > "$work/clean.log"
printf 'thinking...\nAPI error: 429 Too Many Requests\nretrying\n'   > "$work/rl429.log"
printf 'You have hit your usage limit; resets at 12pm\n'             > "$work/rlusage.log"
printf 'Error: server overloaded, try again\n'                       > "$work/rlover.log"
# Proofdelve ForgeOs-g3n1 fixtures. disk.log is the 7gag text verbatim; mixed.log has BOTH
# a host line and a separate plan line, so each detector must see its own.
printf 'tee: /tmp/verify-fail-dotnet-build-835161.log: Disk quota exceeded\nMSB3883: Unexpected exception\n' > "$work/disk.log"
printf 'write error: No space left on device\n'                          > "$work/nospace.log"
printf 'tee: /tmp/x.log: Disk quota exceeded\nAPI error: 429 Too Many Requests\n' > "$work/mixed.log"

harness() { # $@ = shell body
  bash -c "set -uo pipefail
    run_id=T; FLEET_HARD_STOP=3; FLEET_FORGE_MIN=1; FLEET_FORGE_MAX=6; FLEET_FORGE_START=3; FLEET_WARDEN_CONC=1
    ceiling_log='$work/ceiling.log'; launches=0; fleet_actor=fleet
    end_reason=drained; halted=false; halt_file='$work/HALT'
    # TOP-LEVEL GLOBALS fleet.sh sets before its loop (Proofdelve ForgeOs-uwjme). A runner
    # that reaches reap_pass without stubbing refill_slots() reaches the real
    # one, and forge_conc=0 means no free slot, so that refill is a no-op and
    # never needs the unextracted dispatch_pass(). governor_init() overwrites it.
    in_dispatch=0; forge_conc=0
    state='$work/state'; FLEET_LAUNCH_GRACE=120
    emit(){ :; }
    # say() AND warn() ARE REAL HERE, EACH ON THE STREAM ITS CONTRACT NAMES.
    # A say(){ :; } stub is exactly why this harness could not catch
    # Proofdelve ForgeOs-0d0i: it silenced the very write that broke the caller.
    say(){ printf 'SAY %s\n' \"\$*\"; }
    warn(){ printf 'WARN %s\n' \"\$*\" >&2; }
    $(cat "$work/gov.sh")
    $*"
}

# 1..3 detection fires on each marker family
for f in rl429 rlusage rlover; do
  if harness "looks_rate_limited '$work/$f.log' && echo HIT" | grep -q HIT; then ok "detects $f"; else no "detects $f" "no hit"; fi
done
# 4 VACUITY CONTROL: a clean log must NOT trip it, or every log looks throttled
if harness "looks_rate_limited '$work/clean.log' && echo HIT" | grep -q HIT; then
  no "vacuity control: clean log must not trip detection" "clean log reported as rate-limited"
else ok "vacuity control: clean log does not trip detection"; fi
# 4h-4o 429 ONLY AS A STATUS CODE (Proofdelve ForgeOs-dx34.20). The two log lines that
# stepped the governor 4 -> 3 -> 2 on 2026-10-20 are fixtures verbatim; neither
# session was throttled, and the digits 429 sit inside the microseconds. A uuid
# and a hex hash carry letters on both sides of the digits, so a digit fence
# alone would not have been enough; they are fixtures too.
printf '2026-10-20T16:47:19.094299Z ERROR codex_core::session: failed to record rollout items\n' > "$work/ts1.log"
printf '2026-10-20T18:28:23.542914Z ERROR codex_core::session: failed to record rollout items\n' > "$work/ts2.log"
printf 'session 3fa4291c-a429-4290-b429-0429a42942f9 commit a429fe0d4291\n'                          > "$work/hex.log"
for f in ts1 ts2 hex; do
  if harness "looks_rate_limited '$work/$f.log' && echo HIT" | grep -q HIT; then
    no "dx34.20: $f (a 429 inside a timestamp, uuid or hash) must NOT read as plan back-pressure" "it did"
  else ok "dx34.20: $f is not plan back-pressure"; fi
done
# Real throttling, in every spelling the bead names, still steps down.
n=0
for line in 'unexpected status 429 Too Many Requests' 'HTTP 429' 'status: 429' '{"error":{"status":429}}' 'error code=429' \
            'rate limit reached for gpt-5' 'You have hit your usage limit; resets at 12pm'; do
  n=$((n + 1)); printf '%s\n' "$line" > "$work/real$n.log"
  if harness "looks_rate_limited '$work/real$n.log' && echo HIT" | grep -q HIT; then ok "dx34.20: real throttling still detected: $line"
  else no "dx34.20: real throttling MISSED" "$line"; fi
done
# RED, GENERATED: the same extraction with the bare 429 restored must read the
# first timestamp line as back-pressure -- so ts1 above is the fence working.
sed 's#|(http|status|code)\[ :=_\\/"\]{0,3}429(\[^0-9a-z\]|\$)|#|429|#' "$work/gov.sh" > "$work/gov-bare429.sh"
if ! cmp -s "$work/gov.sh" "$work/gov-bare429.sh"; then
  cp "$work/gov.sh" "$work/gov-shipped.sh"; cp "$work/gov-bare429.sh" "$work/gov.sh"
  out="$(harness "looks_rate_limited '$work/ts1.log' && echo HIT")"
  cp "$work/gov-shipped.sh" "$work/gov.sh"
  if grep -q HIT <<< "$out"; then ok "RED: with the bare 429 restored the 16:47:19.094299Z line IS back-pressure -- the case above discriminates"
  else no "RED: bare-429 variant" "the restored bare 429 did not match the timestamp ($out)"; fi
else no "RED: bare-429 variant" "could not be generated (sed matched nothing)"; fi

# 4b-4g THE TWO SIGNATURES ARE KEPT APART (Proofdelve ForgeOs-g3n1, incident Proofdelve ForgeOs-7gag).
# 'Disk quota exceeded' is EDQUOT, not a plan message; pre-fix the plan regex's
# bare 'quota exceeded' matched it and the governor stepped down five times for a
# full disk. RED against the shipped file: 4b fails there.
if harness "looks_rate_limited '$work/disk.log' && echo HIT" | grep -q HIT; then
  no "g3n1: the EDQUOT line alone must NOT read as plan back-pressure" "the plan detector matched a full disk"
else ok "g3n1: the EDQUOT line alone does NOT read as plan back-pressure"; fi
if have looks_env_failure; then
  if harness "looks_env_failure '$work/disk.log' && echo HIT" | grep -q HIT; then ok "g3n1: the EDQUOT line IS an environmental failure"; else no "g3n1: env detector misses EDQUOT" "no hit"; fi
  if harness "looks_env_failure '$work/nospace.log' && echo HIT" | grep -q HIT; then ok "g3n1: the ENOSPC line IS an environmental failure"; else no "g3n1: env detector misses ENOSPC" "no hit"; fi
  # THE LABELS OF THIS FILE MUST NEVER SPELL THE SIGNATURE (the Warden,
  # g3n1 round one, the blocking finding): run_step prints every case label
  # into verify.sh's stdout, run_verifier() captures that into $vout, and the
  # fleet asks looks_env_failure of $vout when the verifier is RED -- so three
  # labels here that quoted the EDQUOT text would have halted a healthy fort on
  # any RED at step 13 or later. Checked structurally: every ok/no label string
  # in this file, run through the shipped detector.
  grep -oE '(ok|no) "[^"]*"' "$0" | sed 's/^[on][ko] "//; s/"$//' > "$work/labels.txt"
  if harness "looks_env_failure '$work/labels.txt' && echo HIT" | grep -q HIT; then
    no "g3n1: no case label in this harness may spell the environmental signature" "$(harness "grep -ciE \"\$(env_signature)\" '$work/labels.txt'") label(s) match; the text is deliberately not printed here (it would put the signature into \$vout)"
  else ok "g3n1: no case label in this harness spells the environmental signature ($(wc -l < "$work/labels.txt") labels checked)"; fi
  # the plan regex no longer carries a bare 'quota exceeded'; the API spellings are in
  printf 'Error: You exceeded your current quota, please check your plan\n' > "$work/rlapiq.log"
  printf 'some tool: quota exceeded for this bucket\n' > "$work/bareq.log"
  if harness "looks_rate_limited '$work/rlapiq.log' && echo HIT" | grep -q HIT; then ok "g3n1: the API's 'exceeded your current quota' IS plan back-pressure"; else no "g3n1: API quota phrasing missed" "no hit"; fi
  if harness "looks_rate_limited '$work/bareq.log' && echo HIT" | grep -q HIT; then no "g3n1: a bare 'quota exceeded' must no longer read as plan back-pressure" "hit"; else ok "g3n1: a bare non-API 'quota exceeded' is not plan back-pressure (finding 4)"; fi
  if harness "looks_env_failure '$work/rl429.log' && echo HIT" | grep -q HIT; then no "g3n1: a 429 log must NOT read as environmental" "hit"; else ok "g3n1: vacuity control: a 429 log is not environmental"; fi
  if harness "looks_env_failure '$work/clean.log' && echo HIT" | grep -q HIT; then no "g3n1: a clean log must NOT read as environmental" "hit"; else ok "g3n1: vacuity control: a clean log is not environmental"; fi
  # mixed: the host line is excluded from the plan regex, the separate 429 line still counts, and the env detector fires too
  out=$(harness "looks_rate_limited '$work/mixed.log' && echo RL; looks_env_failure '$work/mixed.log' && echo ENV")
  if grep -q RL <<<"$out" && grep -q ENV <<<"$out"; then ok "g3n1: a log with a host line AND a separate 429 line trips BOTH detectors, each on its own line"; else no "g3n1: mixed log" "$out"; fi
else
  no "g3n1: looks_env_failure exists" "this fleet.sh has no environmental signature (Proofdelve ForgeOs-g3n1)"
fi

# 5 a step down is a MEASURED step down
out=$(harness "governor_init; governor_down 'simulated 429'; echo CONC=\$forge_conc")
if grep -q 'CONC=2' <<<"$out"; then ok "step down 3 -> 2 on back-pressure"; else no "step down" "$out"; fi
# 6 it floors at MIN and does not go to zero or negative
out=$(harness "governor_init; governor_down a; governor_down b; governor_down c; governor_down d; echo CONC=\$forge_conc")
if grep -q 'CONC=1' <<<"$out"; then ok "floors at FLEET_FORGE_MIN, no hot zero"; else no "floor" "$out"; fi
# 7 it steps back up only after a sustained clean period, never sooner
out=$(harness "governor_init; governor_down x; clean_streak=0
  governor_up_maybe; governor_up_maybe; governor_up_maybe; governor_up_maybe; echo AT4=\$forge_conc
  governor_up_maybe; echo AT5=\$forge_conc")
if grep -q 'AT4=2' <<<"$out" && grep -q 'AT5=3' <<<"$out"; then
  ok "steps up only on the 5th clean completion"; else no "step up" "$out"; fi
# 8 THE CAP IS N LAUNCHES, NOT N-1 (Proofdelve ForgeOs-feeq, Regent edict 2026-09-04).
# This case previously asserted `spend c` returning 1 at FLEET_HARD_STOP=3 --
# it encoded the off-by-one as intended behaviour, because spend() incremented
# and THEN tested `launches < FLEET_HARD_STOP`, so the Nth launch reported
# failure and was never made. Deciding is now budget_left()'s job and it is
# asked BEFORE anything is mutated; spend() only records.
out=$(harness "governor_init
  budget_left && spend a; budget_left && spend b; budget_left && spend c
  budget_left; echo FOURTH=\$?; echo N=\$launches")
if grep -q 'N=3' <<<"$out" && grep -q 'FOURTH=1' <<<"$out"; then
  ok "FLEET_HARD_STOP=3 permits exactly 3 launches and refuses the 4th"
else no "hard stop is N, not N-1" "$out"; fi
# 8b VACUITY CONTROL for case 8: budget_left must be TRUE below the cap, or a
# function that refuses everything scores a clean pass on the refusal case.
out=$(harness "governor_init; budget_left; echo FIRST=\$?")
if grep -q 'FIRST=0' <<<"$out"; then
  ok "vacuity control: budget_left permits the first launch"
else no "vacuity control: budget_left refuses even the first launch" "$out"; fi
# 8c spend() DECIDES NOTHING. Anything branching on its status is reading a
# value it no longer sets, which is how the off-by-one survived review.
out=$(harness "governor_init; launches=99; spend past-the-cap; echo S=\$?")
if grep -q 'S=0' <<<"$out"; then
  ok "spend() records and returns success even past the cap"
else no "spend() still returns a decision" "$out"; fi
# 8d ORDINARY EXHAUSTION IS NOT A HALT. budget_stop must not write the halt
# file: that file disables every LATER run until a person deletes it, and a
# successful busy night must not do that.
out=$(harness "governor_init; budget_stop 'test'; echo R=\$end_reason; echo H=\$halted
  [ -e \"\$halt_file\" ] && echo HALTFILE=yes || echo HALTFILE=no")
if grep -q 'HALTFILE=no' <<<"$out" \
   && grep -q 'R=budget spent' <<<"$out" \
   && grep -q 'H=false' <<<"$out"; then
  ok "budget_stop ends the run without a halt file and names the reason"
else no "budget_stop conflates exhaustion with halting" "$out"; fi
# 9 the ceiling log is written and readable
if [ -s "$work/ceiling.log" ] && grep -q 'DOWN 3 -> 2' "$work/ceiling.log"; then
  ok "sustained-ceiling log records the adjustment"; else no "ceiling log" "$(cat "$work/ceiling.log" 2>/dev/null | head -3)"; fi

# ---------------------------------------------------------------------------
# 10-14  Proofdelve ForgeOs-0d0i: A HELPER WHOSE STDOUT IS A VALUE MUST PRINT ONLY THAT
# VALUE. Both live_forges call sites feed it straight into arithmetic --
# slots=$((forge_conc - $(live_forges))) and [ "$(live_forges)" -eq 0 ] -- so one
# diagnostic line on stdout is an arithmetic syntax error, which under
# set -euo pipefail kills the run, and the EXIT trap then records a CLEAN DRAIN
# for a run that crashed. These cases fail against the diff that introduced it.
# The old say(){ :; } stub is precisely why they could not exist before: it
# silenced the write that broke the caller.
mkdir -p "$work/state/workers/stale"
printf 'fortkit-stale\n' > "$work/state/workers/stale/bead"
touch -d '2 hours ago' "$work/state/workers/stale/started"  # no pid/exit/done, past grace

# 10 VACUITY CONTROL for 11: the stale-worker branch must actually be REACHED.
# Without this, a live_forges that returned "0" without ever entering that
# branch would score a clean pass on case 11 and prove nothing.
# The ASSERTION IS THE PROPERTY, NOT THE WORDING: it must say something, on
# STDERR, naming the worker. Proofdelve ForgeOs-w7u5 moved the wording from live_forges'
# own sentence ("a Forge that died hard") to worker_explain's ("ORPHANED"), and
# a control that pinned the old string would have gone red for the fix.
if harness "live_forges >/dev/null" 2>&1 >/dev/null | grep -q 'stale'; then
  ok "vacuity control: the stale-worker branch is reached and reports on stderr"
else no "vacuity control: stale-worker branch never reached" "$(harness "live_forges >/dev/null" 2>&1 >/dev/null | head -2)"; fi

# 11 THE REGRESSION: stdout must be a bare integer; diagnostics belong on stderr
out=$(harness "live_forges" 2>/dev/null)
if [ "$out" = "0" ]; then
  ok "live_forges prints ONLY its count on stdout, with something to say"
else no "live_forges pollutes its own return value" "captured: $(printf '%s' "$out" | tr '\n' '|')"; fi

# 12 and the captured value survives the arithmetic its call sites perform.
# shellcheck disable=SC2016  # single quotes are the point: harness() interpolates
# this string into a `bash -c` body, so it must reach that shell UNEXPANDED.
if harness 'n=$(live_forges); echo SUM=$((5 - n))' 2>/dev/null | grep -q 'SUM=5'; then
  ok "the captured value survives the arithmetic at both call sites"
else no "arithmetic on the captured value fails" "$(harness 'n=$(live_forges); echo SUM=$((5 - n))' 2>&1 | tail -2)"; fi

# shellcheck disable=SC2016  # same reason: the body is evaluated by harness().
# 13 Proofdelve ForgeOs-0d0i(b): returns_of prints exactly ONE integer when bd will not
# answer -- the condition every || true in return_to_ready exists to survive,
# and the one this fort hit four times on 2026-09-04 ("storage is nil").
out=$(harness 'bead_json(){ return 1; }; FLEET_MAX_RETURNS=2; returns_of fortkit-x' 2>/dev/null)
if [ "$out" = "0" ]; then
  ok "returns_of prints exactly one integer when bd is unavailable"
else no "returns_of prints more than one value with bd down" "captured: $(printf '%s' "$out" | tr '\n' '|')"; fi

# 14 and its consumer's arithmetic survives that path.
# shellcheck disable=SC2016  # same reason: the body is evaluated by harness().
if harness 'bead_json(){ return 1; }; FLEET_MAX_RETURNS=2; n=$(returns_of fortkit-x); n=$((n + 1)); echo N=$n' 2>/dev/null | grep -q 'N=1'; then
  ok "return_to_ready's n=\$((n + 1)) works with bd down"
else no "return_to_ready dies with bd down" "$(harness 'bead_json(){ return 1; }; FLEET_MAX_RETURNS=2; n=$(returns_of fortkit-x); n=$((n + 1)); echo N=$n' 2>&1 | tail -2)"; fi


# ---------------------------------------------------------------------------
# 15-24  Proofdelve ForgeOs-w7u5: THE WORKER LIFECYCLE HAS ONE OWNER, AND IT NAMES ITS
# CASE INSTEAD OF RETURNING A BOOLEAN.
#
# All five recorded sightings of the finished-but-not-landed class are cases
# here. They are guarded on the owner EXISTING rather than on the extraction
# succeeding, so against a pre-w7u5 fleet.sh they FAIL — a harness that merely
# refused would leave this instrument's other twenty cases unusable, and a
# harness that passed against both files would have tested nothing at all
# (Proofdelve ForgeOs-5m7a round two, the landable-harness vacuity lesson).
# ---------------------------------------------------------------------------
# $1 case name, $2 shell body, $3.. FIXED STRINGS the output must all contain.
# Fixed strings and one per line, not one multi-line regex: `grep -E` has no
# `\n`, so a pattern like `A(.|\n)*B` matches nothing and warns "stray \ before
# n" on stderr — which reads as a failing assertion rather than as a broken one.
lc() {
  local name="$1" body="$2"; shift 2
  if ! have worker_state; then
    no "$name" "this fleet.sh has no lifecycle owner: worker_state does not exist (Proofdelve ForgeOs-w7u5)"
    return
  fi
  local out want miss=""
  out="$(harness "$body" 2>&1)"
  for want in "$@"; do
    grep -qF -- <<<"$out" "$want" || miss="${miss:+$miss; }missing: $want"
  done
  if [ -z "$miss" ]; then ok "$name"; else no "$name" "$miss || got: $(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"; fi
}
mk() { mkdir -p "$work/state/workers/$1"; printf 'fortkit-%s\n' "$1" > "$work/state/workers/$1/bead"; }

# 15 SIGHTINGS 1 AND 2 (Proofdelve ForgeOs-bzyk, the two merge-without-close paths). A
# bead merged and not closed must be a state a person is told about, and must
# NOT be reapable — re-reaping it would re-verify and re-review already merged
# work.
mk bzyk
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
lc "sighting 1+2 (bzyk): merged-but-not-closed is needs-person, not reapable, and is announced" \
   'worker_set_state "$state/workers/bzyk" needs-person "MERGED but NOT CLOSED"
    echo "STATE=$(worker_state "$state/workers/bzyk")"
    worker_reapable "$state/workers/bzyk" && echo REAPABLE || echo NOT-REAPABLE
    worker_needs_person "$state/workers/bzyk" && echo PERSON || echo NO-PERSON
    worker_explain "$state/workers/bzyk"' \
   STATE=needs-person NOT-REAPABLE PERSON 'MERGED but NOT CLOSED'

# 16 SIGHTING 3 (Proofdelve ForgeOs-5p00, review_one's budget branch). The old remedy
# deleted the `done` marker so the worker was reaped FROM THE TOP, which cost a
# second full verifier run. The resume point is the fix: reapable, at `review`.
mk p500
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
lc "sighting 3 (5p00): a review-budget park is reapable AND resumes at the review, not the verifier" \
   'worker_set_state "$state/workers/p500" parked-review "budget"
    worker_reapable "$state/workers/p500" && echo REAPABLE || echo NOT-REAPABLE
    echo "RESUME=$(worker_resume_at "$state/workers/p500")"' \
   REAPABLE RESUME=review

# 17 SIGHTING 4 (Proofdelve ForgeOs-usz6, the deferred merge). THIS IS THE CASE THAT
# FLIPPED when usz6 landed, and its previous form is why: it asserted that a
# deferred merge was announced to a PERSON, because nothing retried it. It is
# now reapable and healthy, and the executable cases 25-29 below prove that the
# retry is real rather than merely renamed.
mk usz6
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
lc "sighting 4 (usz6): a deferred merge is REAPABLE, resumes at land, and needs no person" \
   'worker_set_state "$state/workers/usz6" deferred-merge "root not landable"
    echo "RESUME=$(worker_resume_at "$state/workers/usz6")"
    worker_reapable "$state/workers/usz6" && echo REAPABLE || echo NOT-REAPABLE
    worker_needs_person "$state/workers/usz6" && echo PERSON || echo NO-PERSON' \
   RESUME=land REAPABLE NO-PERSON

# 18 SIGHTING 5 (round-three finding 2): --dry-run wrote `touch "$d/done"` NINE
# LINES ABOVE the dry-run guard, so a dry run marked a real finished Forge's
# worker done and every later real run skipped it permanently. THIS CASE
# EXECUTES THE SHIPPED reap_pass and fails against the pre-w7u5 file by
# observing the marker it leaves.
mkdir -p "$work/state/workers/dryrun"
printf 'fortkit-dryrun\n' > "$work/state/workers/dryrun/bead"
printf '0\n'              > "$work/state/workers/dryrun/exit"
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
dryout="$(harness 'dry=1; root=/nonexistent; run_id=DRY
  stopping(){ return 1; }; signalled(){ return 1; }
  budget_left(){ return 0; }; budget_stop(){ :; }
  looks_rate_limited(){ return 1; }; governor_up_maybe(){ :; }; governor_down(){ :; }
  run_verifier(){ return 0; }; review_one(){ echo "REVIEWED $1"; }; return_to_ready(){ echo "RETURNED $1"; }
  reap_pass' 2>&1)"
if [ -e "$work/state/workers/dryrun/done" ] || [ -e "$work/state/workers/dryrun/state" ]; then
  no "sighting 5: a --dry-run must leave NO durable worker state" \
     "it wrote $( [ -e "$work/state/workers/dryrun/done" ] && echo 'a done marker' ) $( [ -e "$work/state/workers/dryrun/state" ] && cat "$work/state/workers/dryrun/state" ) -- the next real run will skip this worker forever"
else
  ok "sighting 5: a --dry-run decides everything and leaves no durable worker state"
fi
# 18b VACUITY CONTROL for 18: the dry run must have REACHED that worker at all.
# Without this, a reap_pass that returned immediately would score a clean pass.
if grep -q 'dryrun' <<<"$dryout"; then
  ok "vacuity control: the dry run actually reached the fixture worker"
else no "vacuity control: reap_pass never reached the fixture" "$(printf '%s' "$dryout" | tr '\n' '|' | cut -c1-200)"; fi

# 19 NOTHING WRITES `done` ANY MORE. The root conflation was that one marker
# meant both "the Forge ended" and "nothing further will happen here". Cheap,
# and it fails loudly against any file that still writes it.
# shellcheck disable=SC2016  # the pattern is a literal to grep for in another file, not an expansion.
donesites="$(grep -cE 'touch "\$(d|wdir)/done"' "$launcher")"
if [ "$donesites" -gt 0 ]; then
  no "the two meanings of \`done\` are separated" "$launcher still writes that marker at $donesites site(s)"
else
  ok "nothing writes the \`done\` marker: its two meanings are separate states"
fi

# 20 BUT A LIVE RIG'S EXISTING `done` FILES MUST STILL READ CORRECTLY, or this
# change turns seven settled workers into seven phantom stranded ones on the
# morning it lands.
mk legacy; touch "$work/state/workers/legacy/done"; printf '0\n' > "$work/state/workers/legacy/exit"
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
lc "a legacy \`done\` marker reads as settled, so an existing state directory is not misread" \
   'echo "STATE=$(worker_state "$state/workers/legacy")"
    worker_reapable "$state/workers/legacy" && echo REAPABLE || echo NOT-REAPABLE' \
   STATE=settled NOT-REAPABLE

# 21 THE TAXONOMY. Emrith Cairnwright's addition, and the reason a boolean was
# not enough: a budget-parked unit and a stranded one are indistinguishable to
# a reader today, so every parked bead gets investigated as a stranding.
mk parked; mk lost
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
lc "a parked unit and a stranded one are DISTINGUISHABLE: one is healthy, one needs a person" \
   'worker_set_state "$state/workers/parked" parked-budget "budget ran out"
    worker_set_state "$state/workers/lost"   needs-person "close failed after the merge"
    worker_needs_person "$state/workers/parked" && echo PARKED-NEEDS-PERSON || echo PARKED-HEALTHY
    worker_needs_person "$state/workers/lost"   && echo LOST-NEEDS-PERSON   || echo LOST-HEALTHY
    worker_explain "$state/workers/parked"' \
   PARKED-HEALTHY LOST-NEEDS-PERSON 'PARKED FOR BUDGET, HEALTHY'

# 22 THE ORPHANED DISPATCHER, the third of the four cases. A worker taken IN
# HAND by a run that is gone is not in hand any more; only one fleet runs at a
# time, so nothing will ever finish it.
mk orph
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
lc "a worker in hand from an earlier run reads as ORPHANED, not as in flight" \
   'worker_set_state "$state/workers/orph" in-hand "taken"
    echo "SAME=$(worker_state "$state/workers/orph")"
    run_id=A-LATER-RUN
    echo "LATER=$(worker_state "$state/workers/orph")"
    worker_live "$state/workers/orph" && echo LIVE || echo NOT-LIVE' \
   SAME=in-hand LATER=orphaned NOT-LIVE

# 23 VACUITY CONTROL for 15-22: a settled worker must be none of these things,
# or predicates that answered yes to everything would score a clean sweep.
mk done1
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
lc "vacuity control: a settled worker is neither reapable, nor live, nor needing a person" \
   'worker_set_state "$state/workers/done1" settled "merged and closed"
    worker_reapable "$state/workers/done1" && echo REAPABLE || echo NOT-REAPABLE
    worker_live "$state/workers/done1" && echo LIVE || echo NOT-LIVE
    worker_needs_person "$state/workers/done1" && echo PERSON || echo NO-PERSON' \
   NOT-REAPABLE NOT-LIVE NO-PERSON

# 24 A REASON CONTAINING THE FIELD SEPARATOR MUST NOT CORRUPT THE TOKEN. The
# reasons written by land() carry landable_why()'s joined file list.
mk pipe
# shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
lc "a reason containing | does not corrupt the state token or the run id" \
   'worker_set_state "$state/workers/pipe" deferred-merge "a|b|c uncommitted"
    echo "STATE=$(worker_state "$state/workers/pipe")"
    echo "WHY=$(worker_reason "$state/workers/pipe")"' \
   STATE=deferred-merge 'WHY=a|b|c uncommitted'


# ---------------------------------------------------------------------------
# 25-31  Proofdelve ForgeOs-usz6: A DEFERRED MERGE IS RETRIED, AND THE RETRY IS THE MERGE
# ALONE. These cases EXECUTE the shipped reap_pass against fixtures and a real
# throwaway git repository, and they observe what it calls. Against a pre-usz6
# launcher a deferred worker is not reapable at all, so land() is never called
# and every one of them fails on the observation rather than on a stub.
# ---------------------------------------------------------------------------
repo="$work/repo"
g() { git -C "$repo" -c user.email=h@h -c user.name=h "$@"; }
# A REAL WORKTREE FOR A WORKER FIXTURE (Proofdelve ForgeOs-tvb2). prelanding_refresh()
# inspects the worktree's HEAD on every path now, so a finished worker whose
# tree is a bare directory (or absent) is REFUSED rather than verified; fixtures
# that want the verify arm need a worktree on bead/<sfx> with one commit of its
# own (the ss9d/4hzq "committed nothing" returns fire otherwise).
mkwt() { # $1 sfx
  g worktree remove --force "$repo-worktrees/$1" >/dev/null 2>&1 || true; rm -rf "$repo-worktrees/$1"
  g branch -D "bead/$1" >/dev/null 2>&1 || true
  g branch "bead/$1" main; g worktree add -q "$repo-worktrees/$1" "bead/$1"
  printf '%s\n' "$1" > "$repo-worktrees/$1/wt-$1.txt"; git -C "$repo-worktrees/$1" add -A >/dev/null; git -C "$repo-worktrees/$1" -c user.email=h@h -c user.name=h commit -qm "$1: work"
}
git init -q -b main "$repo" 2>/dev/null
g commit -q --allow-empty -m base
# bead/def: a real unlanded branch, one commit ahead of main -- and the commit
# carries a PRODUCT file, since Proofdelve ForgeOs-ss9d: an empty commit is "no product
# change" to the reap guard and would be returned, so the 4hzq vacuity case
# below (a real branch is still verified) needs real work on the branch.
g branch bead/def
g checkout -q bead/def; mkdir -p "$repo/src"; printf 'work\n' > "$repo/src/def.cs"; g add src/def.cs; g commit -q -m work; g checkout -q main
# bead/merged: the same shape, but already an ancestor of main — the case where
# somebody landed it by hand while it waited.
g branch bead/merged
g checkout -q bead/merged; g commit -q --allow-empty -m handwork; g checkout -q main
g merge -q --no-ff -m "landed by hand" bead/merged
# The reap loop tests for the bead's worktree directory, so the fixtures that
# take the verify path need one to exist. Since Proofdelve ForgeOs-36b9 the verify path
# REFRESHES the branch from main inside its worktree first, so `def` -- whose
# base main has moved past (the hand-landed merge above) -- has to be a REAL
# worktree on its branch, not an empty directory; the others stay directories.
mkdir -p "$repo-worktrees/fresh" "$repo-worktrees/merged"
g worktree add -q "$repo-worktrees/def" bead/def 2>/dev/null || mkdir -p "$repo-worktrees/def"

# reap() runs the SHIPPED reap_pass with everything it could call stubbed to
# ANNOUNCE ITSELF, so a case can assert what was and was not invoked. The stubs
# print rather than fall silent: a `:` stub is why the governor harness could
# not see Proofdelve ForgeOs-0d0i.
reap() { # $1 extra setup
  # main_branch joined 2026-09-14: prelanding_refresh() (Proofdelve ForgeOs-36b9) reads it
  # from reap_pass's verify arm, and it is a top-level variable in fleet.sh.
  harness "root='$repo'; run_id=R1; dry=0; main_branch=main
    stopping(){ return 1; }; signalled(){ return 1; }
    budget_stop(){ echo \"BUDGET-STOP \$1\"; }
    looks_rate_limited(){ return 1; }; governor_up_maybe(){ :; }; governor_down(){ :; }
    run_verifier(){ echo VERIFIER-RAN; return 0; }
    review_one(){ echo \"REVIEW-LAUNCHED \$1\"; }
    return_to_ready(){ echo \"RETURNED \$1\"; }
    land(){ echo \"LAND bead=\$1 verdict=\$2 record=\$3\"; }
    budget_left(){ return 0; }
    refill_slots(){ echo \"REFILL \$1\"; }   # Proofdelve ForgeOs-uwjme: announced, not run (a real refill needs dispatch_pass)
    $1
    reap_pass" 2>&1
}
mkdefer() { # $1 dir suffix, $2 branch suffix, $3 verdict, $4 write a record?
  rm -rf "$work/state/workers/$1"; mkdir -p "$work/state/workers/$1"
  printf 'fortkit-%s\n' "$1" > "$work/state/workers/$1/bead"
  printf '0\n' > "$work/state/workers/$1/exit"
  printf '%s\n' "$3" > "$work/state/workers/$1/verdict"
  [ "$4" = yes ] && printf 'VERDICT-LINE: %s: fine\n' "$3" > "$work/state/workers/$1/warden-record"
  printf 'deferred-merge|OLDRUN|deferral 1\n' > "$work/state/workers/$1/state"
}

if ! have defer_merge; then
  no "usz6: a deferred merge is retried" "this fleet.sh has no defer_merge: nothing retries a deferred merge (Proofdelve ForgeOs-usz6)"
  no "usz6: the retry re-runs neither the verifier nor the review" "same"
  no "usz6: a deferred merge with no stored verdict is escalated, not landed" "same"
  no "usz6: APPROVE-WITH-FINDINGS with no stored record is escalated, not landed" "same"
  no "usz6: a branch somebody already merged is settled, not re-merged" "same"
  no "usz6: an exhausted budget does not block a retry that spends no launch" "same"
  no "usz6: one fleet.deferred per distinct reason, and the count still rises" "same"
else
  # 25 + 26. THE RETRY HAPPENS, AND IT IS THE MERGE ALONE.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkdefer def def APPROVE-WITH-FINDINGS yes
  out="$(reap '')"
  if grep -q 'LAND bead=fortkit-def verdict=APPROVE-WITH-FINDINGS' <<<"$out"; then
    ok "usz6: a deferred merge is retried, on its STORED verdict"
  else no "usz6: a deferred merge is retried" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-220)"; fi
  if ! grep -q 'VERIFIER-RAN' <<<"$out" && ! grep -q 'REVIEW-LAUNCHED' <<<"$out"; then
    ok "usz6: the retry re-runs neither the verifier nor the review"
  else no "usz6: the retry re-runs the verifier or spends a second review launch" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-220)"; fi
  # 26a Proofdelve ForgeOs-g3n1: A FORGE LOG NAMING THE HOST HALTS, DOES NOT STEP DOWN,
  # DOES NOT RETURN, AND LEAVES THE WORKER RESUMABLE. The 7gag shape: a1w5's
  # Forge exited 1 on 'Disk quota exceeded'; pre-fix the governor stepped down
  # and the bead was returned (twice, then escalated). Real detectors here, a
  # halt() stub that announces itself and exits 70 as the real one does.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/envf"
  printf 'fortkit-envf\n' > "$work/state/workers/envf/bead"; printf '1\n' > "$work/state/workers/envf/exit"
  printf 'seat-sandbox.sh: line 498: printf: write error: Disk quota exceeded\n' > "$work/state/workers/envf/forge.log"
  out="$(harness "root='$repo'; run_id=R1; dry=0; main_branch=main
    stopping(){ return 1; }; signalled(){ return 1; }
    budget_stop(){ echo \"BUDGET-STOP \$1\"; }; budget_left(){ return 0; }
    governor_up_maybe(){ echo GOV-UP; }; governor_down(){ echo \"GOV-DOWN \$1\"; }
    halt(){ echo \"HALT-CALLED: \$1\"; echo \"STATE=\$(worker_state \"\$state/workers/envf\")\"; exit 70; }
    run_verifier(){ echo VERIFIER-RAN; return 0; }; review_one(){ echo REVIEW-LAUNCHED; }
    return_to_ready(){ echo \"RETURNED \$1\"; }; land(){ echo LAND; }
    reap_pass" 2>&1)"
  if grep -q 'HALT-CALLED: ENVIRONMENTAL FAILURE' <<<"$out" && grep -q 'STATE=finished' <<<"$out" \
     && ! grep -q 'GOV-DOWN' <<<"$out" && ! grep -q 'RETURNED' <<<"$out"; then
    ok "g3n1: a Forge log naming the host HALTS (environmental), steps nothing down, returns nothing, worker back to finished"
  else no "g3n1: forge-log environmental halt" "$(printf '%s' "$out" | sed -E 's/disk quota exceeded|no space left on device/<the signature>/Ig' | tr '\n' '|' | cut -c1-300)"; fi
  # 26a-scope (the Warden, g3n1 round one): a Forge that exited 0 whose transcript merely
  # MENTIONS the signature is prose, not a failure: verified, never halted.
  mkwt envf   # the verify arm needs the bead's REAL worktree on bead/envf (Proofdelve ForgeOs-tvb2; a bare directory is refused since the inspection was hoisted)
  printf 'I read the fleet.sh change: it halts on Disk quota exceeded. Done.\n' > "$work/state/workers/envf/forge.log"; printf '0\n' > "$work/state/workers/envf/exit"
  printf 'finished|R0|x\n' > "$work/state/workers/envf/state"
  out="$(harness "root='$repo'; run_id=R1; dry=0; main_branch=main
    stopping(){ return 1; }; signalled(){ return 1; }
    budget_stop(){ echo \"BUDGET-STOP \$1\"; }; budget_left(){ return 0; }
    governor_up_maybe(){ echo GOV-UP; }; governor_down(){ echo \"GOV-DOWN \$1\"; }
    halt(){ echo \"HALT-CALLED: \$1\"; exit 70; }
    run_verifier(){ echo VERIFIER-RAN; return 0; }; review_one(){ echo REVIEW-LAUNCHED; }
    return_to_ready(){ echo \"RETURNED \$1\"; }; land(){ echo LAND; }
    reap_pass" 2>&1)"
  if grep -q 'VERIFIER-RAN' <<<"$out" && ! grep -q 'HALT-CALLED' <<<"$out"; then
    ok "g3n1 scope: a Forge that exited 0 whose transcript MENTIONS the signature is verified, never halted (prose is not a failure)"
  else no "g3n1 scope: successful Forge mentioning the signature" "$(printf '%s' "$out" | sed -E 's/disk quota exceeded|no space left on device/<the signature>/Ig' | tr '\n' '|' | cut -c1-300)"; fi
  # 26a-control: the same worker with a PLAN line steps down and is returned (the pre-g3n1 path is intact for a real plan refusal)
  printf 'API error: 429 Too Many Requests\n' > "$work/state/workers/envf/forge.log"; printf '1\n' > "$work/state/workers/envf/exit"
  printf 'finished|R0|x\n' > "$work/state/workers/envf/state"
  out="$(harness "root='$repo'; run_id=R1; dry=0; main_branch=main
    stopping(){ return 1; }; signalled(){ return 1; }
    budget_stop(){ echo \"BUDGET-STOP \$1\"; }; budget_left(){ return 0; }
    governor_up_maybe(){ echo GOV-UP; }; governor_down(){ echo \"GOV-DOWN \$1\"; }
    halt(){ echo \"HALT-CALLED: \$1\"; exit 70; }
    run_verifier(){ echo VERIFIER-RAN; return 0; }; review_one(){ echo REVIEW-LAUNCHED; }
    return_to_ready(){ echo \"RETURNED \$1\"; }; land(){ echo LAND; }
    reap_pass" 2>&1)"
  if grep -q 'GOV-DOWN' <<<"$out" && grep -q 'RETURNED fortkit-envf' <<<"$out" && ! grep -q 'HALT-CALLED' <<<"$out"; then
    ok "g3n1 control: a Forge log with a real 429 still steps down and is returned, never halted"
  else no "g3n1 control: plan path" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi

  # 26b VACUITY CONTROL: reap_pass must still run the verifier for a worker
  # that is merely FINISHED, or case 26 passes for a reap_pass that does nothing.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkdir -p "$work/state/workers/fresh"; mkwt fresh   # Proofdelve ForgeOs-tvb2: a real worktree on bead/fresh, or the hoisted inspection refuses it
  printf 'fortkit-fresh\n' > "$work/state/workers/fresh/bead"; printf '0\n' > "$work/state/workers/fresh/exit"
  out="$(reap '')"
  if grep -q 'VERIFIER-RAN' <<<"$out"; then
    ok "vacuity control: a merely-finished worker IS still verified"
  else no "vacuity control: reap_pass verifies nothing at all" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"; fi

  # 26c Proofdelve ForgeOs-lw8x. forge.sh EXIT 76 IS A REFUSAL TO DISPATCH, NOT A FORGE
  # FAILURE: the reused worktree could not be brought current with main and no
  # session ran. It is PAGED (a person's merge), never RETURNED (a return
  # re-dispatches into the same refusal), never verified, and the worker is
  # left needs-person with the reason naming the worktree.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkdir -p "$work/state/workers/fresh"
  printf 'fortkit-fresh\n' > "$work/state/workers/fresh/bead"; printf '76\n' > "$work/state/workers/fresh/exit"
  printf -- '--- forge.sh: REFUSED to refresh (fixture log)\n' > "$work/state/workers/fresh/forge.log"
  # shellcheck disable=SC2016  # single quotes are the point: the stub reaches harness() UNEXPANDED and its $1/$4 are the callee's arguments
  out="$(reap 'page_overseer(){ echo "PAGED $1 :: $4"; }')"
  if grep -q '^PAGED fortkit-fresh :: Nothing was built' <<<"$out" \
     && ! grep -q 'RETURNED' <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out" \
     && [ "$(cut -d'|' -f1 "$work/state/workers/fresh/state")" = needs-person ] \
     && grep -q "reused worktree $repo-worktrees/fresh" "$work/state/workers/fresh/state"; then
    ok "lw8x: forge.sh exit 76 is PAGED with its own standing sentence, not returned, not verified, worker needs-person naming the worktree"
  else no "lw8x: exit 76 is not routed to a person" "state=$(cat "$work/state/workers/fresh/state" 2>/dev/null) out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # 26c-77 Proofdelve ForgeOs-4hzq (the Warden finding 2). forge.sh EXIT 77 IS THE PROMPT-CEILING
  # REFUSAL: no session ran and a re-dispatch rebuilds the same oversized prompt,
  # so it is PAGED like 76, never RETURNED. Discrimination from a real Forge
  # failure is 26d below (any other nonzero is returned).
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/fresh"
  printf 'fortkit-fresh\n' > "$work/state/workers/fresh/bead"; printf '77\n' > "$work/state/workers/fresh/exit"
  printf -- '--- forge.sh: REFUSED -- prompt over the size ceiling (fixture log)\n' > "$work/state/workers/fresh/forge.log"
  # shellcheck disable=SC2016  # single quotes are the point: the stub reaches harness() UNEXPANDED
  out="$(reap 'page_overseer(){ echo "PAGED $1 :: $4"; }')"
  if grep -q '^PAGED fortkit-fresh :: Nothing was built' <<<"$out" \
     && ! grep -q 'RETURNED' <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out" \
     && [ "$(cut -d'|' -f1 "$work/state/workers/fresh/state")" = needs-person ] \
     && grep -q 'size ceiling' "$work/state/workers/fresh/state"; then
    ok "4hzq: forge.sh exit 77 (prompt over ceiling) is PAGED, not returned, not verified, worker needs-person naming the ceiling"
  else no "4hzq: exit 77 is not routed to a person" "state=$(cat "$work/state/workers/fresh/state" 2>/dev/null) out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # 26d DISCRIMINATION CONTROL: any OTHER nonzero Forge exit is still RETURNED,
  # so the 76 branch is catching exactly one code and not "nonzero".
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkdir -p "$work/state/workers/fresh"
  printf 'fortkit-fresh\n' > "$work/state/workers/fresh/bead"; printf '1\n' > "$work/state/workers/fresh/exit"
  # shellcheck disable=SC2016  # single quotes are the point: the stub reaches harness() UNEXPANDED and its $1/$4 are the callee's arguments
  out="$(reap 'page_overseer(){ echo "PAGED $1"; }')"
  if grep -q 'RETURNED fortkit-fresh' <<<"$out" && ! grep -q 'PAGED' <<<"$out" \
     && [ "$(cut -d'|' -f1 "$work/state/workers/fresh/state")" = settled ]; then
    ok "lw8x control: a Forge exit of 1 is still RETURNED and settled -- the page fires on 76 alone"
  else no "lw8x control: exit 1 no longer returns" "state=$(cat "$work/state/workers/fresh/state" 2>/dev/null) out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi

  # 27 no usable stored verdict -> escalated, never landed
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkdefer def def "" no
  out="$(reap '')"
  if ! grep -q 'LAND ' <<<"$out" && [ "$(cut -d'|' -f1 "$work/state/workers/def/state")" = needs-person ]; then
    ok "usz6: a deferred merge with no stored verdict is escalated, not landed"
  else no "usz6: it landed on an unusable verdict" "state=$(cat "$work/state/workers/def/state") out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-160)"; fi

  # 28 APPROVE-WITH-FINDINGS whose record is gone -> escalated. Landing would
  # merge and then be unable to file the follow-up that gates the close.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkdefer def def APPROVE-WITH-FINDINGS no
  out="$(reap '')"
  if ! grep -q 'LAND ' <<<"$out" && [ "$(cut -d'|' -f1 "$work/state/workers/def/state")" = needs-person ]; then
    ok "usz6: APPROVE-WITH-FINDINGS with no stored record is escalated, not landed"
  else no "usz6: it landed without the record the follow-up bead needs" "state=$(cat "$work/state/workers/def/state") out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-160)"; fi

  # 29 a branch already merged by hand is settled, not re-merged
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkdefer merged merged APPROVE yes
  out="$(reap '')"
  if ! grep -q 'LAND ' <<<"$out" && [ "$(cut -d'|' -f1 "$work/state/workers/merged/state")" = settled ]; then
    ok "usz6: a branch somebody already merged is settled, not re-merged"
  else no "usz6: it re-merged an ancestor and would have reported it as a landing" "state=$(cat "$work/state/workers/merged/state") out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-160)"; fi

  # 30 AN EXHAUSTED BUDGET MUST NOT BLOCK A RETRY THAT SPENDS NO LAUNCH. This
  # is the exact moment the old stranding was most likely, so gating it here
  # would have re-created the defect inside its own fix.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkdefer def def APPROVE yes
  out="$(harness "root='$repo'; run_id=R1; dry=0; main_branch=main
    stopping(){ return 1; }; signalled(){ return 1; }
    budget_left(){ return 1; }; budget_stop(){ echo \"BUDGET-STOP \$1\"; }
    looks_rate_limited(){ return 1; }; governor_up_maybe(){ :; }; governor_down(){ :; }
    run_verifier(){ echo VERIFIER-RAN; return 0; }; review_one(){ echo REVIEW-LAUNCHED; }
    return_to_ready(){ echo RETURNED; }; land(){ echo \"LAND bead=\$1\"; }
    reap_pass" 2>&1)"
  if grep -q 'LAND bead=fortkit-def' <<<"$out" && ! grep -q 'BUDGET-STOP' <<<"$out"; then
    ok "usz6: an exhausted budget does not block a retry that spends no launch"
  else no "usz6: the budget blocks the deferred merge, re-creating the stranding" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"; fi

  # 30b-30f Proofdelve ForgeOs-dx34.11 / dx34.15: THE BACK-OUT OF THE PROVISIONAL REAP
  # COUNT, AT UNIT LEVEL. reap_pass counts a reapable worker as a pass that
  # changed state, then withdraws that count when a deferred merge re-defers on
  # a reason it has ALREADY given -- so a perpetually parked merge cannot reset
  # the stall counter. The e2e harness (scenario 34) proves the unchanging-reason
  # case at run level; these five isolate the fingerprint: same reason, a NEW
  # reason, a reason that FLAPS back (dx34.15, the case the last-distinct test
  # could not see), the legacy worker with no seen-list, and the vacuity control
  # that a merge which LANDS still counts. land() is stubbed to call the REAL
  # defer_merge (or to settle), so the seen-list is written by shipped code.
  bo() { # $1 defer-reason now, $2 seen-list keys (newline-separated, may be empty), $3 land body -> prints REAPED=<n>
    rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
    mkdefer def def APPROVE yes
    printf '%s\n' "$1" > "$work/state/workers/def/defer-reason"
    [ -n "$2" ] && printf '%s\n' "$2" > "$work/state/workers/def/defer-reasons-seen"
    harness "root='$repo'; run_id=R1; dry=0; pass_reaped=0
      stopping(){ return 1; }; signalled(){ return 1; }
      budget_left(){ return 0; }; budget_stop(){ :; }
      looks_rate_limited(){ return 1; }; governor_up_maybe(){ :; }; governor_down(){ :; }
      run_verifier(){ return 0; }; review_one(){ :; }; return_to_ready(){ :; }
      land(){ $3; }
      reap_pass; echo REAPED=\$pass_reaped" 2>&1 | grep '^REAPED='
  }
  kA=$(printf '%s' A | sha256sum | cut -d' ' -f1); kB=$(printf '%s' B | sha256sum | cut -d' ' -f1)
  seenAB="$kA
$kB"
  # 30b same reason again (dx34.11): backed out
  # shellcheck disable=SC2016  # single quotes are the point: the land body reaches harness() UNEXPANDED
  out=$(bo B "$seenAB" 'defer_merge "$state/workers/def" "$1" "$2" B')
  if [ "$out" = "REAPED=0" ]; then ok "dx34.11: a re-deferral on the SAME reason is backed out (REAPED=0)"; else no "dx34.11 same reason" "$out"; fi
  # 30c a genuinely new reason: counts
  # shellcheck disable=SC2016  # single quotes are the point: the land body reaches harness() UNEXPANDED
  out=$(bo B "$seenAB" 'defer_merge "$state/workers/def" "$1" "$2" C')
  if [ "$out" = "REAPED=1" ]; then ok "dx34.15 control: a deferral on a NEW reason still counts as activity (REAPED=1)"; else no "new reason must count" "$out"; fi
  # 30d THE FLAP (dx34.15): B -> A where A was seen before -- backed out
  # shellcheck disable=SC2016  # single quotes are the point: the land body reaches harness() UNEXPANDED
  out=$(bo B "$seenAB" 'defer_merge "$state/workers/def" "$1" "$2" A')
  if [ "$out" = "REAPED=0" ]; then ok "dx34.15: a reason that FLAPS back to one already seen (B -> A, A seen) is backed out (REAPED=0) -- the flap no longer masks a stall"; else no "dx34.15 flap" "$out (a last-distinct-reason fingerprint counts the flap as progress)"; fi
  # 30e legacy worker, no seen-list, same reason: the equality fallback still backs out
  # shellcheck disable=SC2016  # single quotes are the point: the land body reaches harness() UNEXPANDED
  out=$(bo B "" 'defer_merge "$state/workers/def" "$1" "$2" B')
  if [ "$out" = "REAPED=0" ]; then ok "dx34.15: a worker deferred before the seen-list existed still backs out on the same reason"; else no "legacy equality fallback" "$out"; fi
  # 30f VACUITY CONTROL: a merge that LANDS (settled) is counted, so the back-out is not unconditional
  # shellcheck disable=SC2016  # single quotes are the point: the land body reaches harness() UNEXPANDED
  out=$(bo B "$seenAB" 'worker_set_state "$state/workers/def" settled "landed"')
  if [ "$out" = "REAPED=1" ]; then ok "vacuity control: a retry that lands keeps its count (REAPED=1)"; else no "landing must count" "$out"; fi

  # 31 defer_merge: one event per distinct reason, and the count still rises on
  # every deferral. A stream that repeats one fact every poll is one nobody
  # reads (fortkit-or2.8); a count that stops rising is one nobody can act on.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/dm"
  printf 'fortkit-dm\n' > "$work/state/workers/dm/bead"
  # shellcheck disable=SC2016  # single quotes are the point: the body below is interpolated into a `bash -c` string by harness(), so it must reach that shell UNEXPANDED.
  # The shared harness() stubs emit to a no-op; this case is ABOUT what reaches
  # the stream, so it puts a real one back. (The first draft did not, scored
  # zero emits, and read as a defect in defer_merge.)
  out="$(harness 'run_id=R1
    emit(){ printf "EMIT %s\n" "$*"; }
    defer_merge "$state/workers/dm" fortkit-dm APPROVE "tree dirty"
    defer_merge "$state/workers/dm" fortkit-dm APPROVE "tree dirty"
    defer_merge "$state/workers/dm" fortkit-dm APPROVE "merge slot busy"
    echo "COUNT=$(cat "$state/workers/dm/defers")"' 2>&1)"
  if [ "$(printf '%s' "$out" | grep -c 'EMIT fleet.deferred')" = 2 ] \
     && grep -q 'COUNT=3' <<<"$out"; then
    ok "usz6: one fleet.deferred per distinct reason, and the count still rises"
  else no "usz6: the deferral stream repeats itself or the count stalls" "emits=$(printf '%s' "$out" | grep -c 'EMIT fleet.deferred') $(printf '%s' "$out" | grep COUNT=)"; fi
fi

# ---------------------------------------------------------------------------
# 32-36  THE REAPING BRANCH (2026-09-09 docket item 1). FOUR OUTCOMES, AND THE
# WHOLE POINT IS THAT THEY ARE FOUR AND NOT TWO.
# ---------------------------------------------------------------------------
# The docket's acceptance 6: a removal that FAILS must be distinguishable from
# one that DID NOT RUN, and must not be reported as success. So `reaped`,
# `absent`, `failed` and `refused` are asserted separately, each against a
# fixture that produces only that one.
#
# THESE CASES ARE THE UNIT HALF. The end-to-end half — a bead that merges and
# closes leaves no worktree, a deferred merge KEEPS its worktree until the retry
# lands, and a state needing a person keeps its worktree — is in
# scripts/fleet-e2e-harness.sh, where it is measured by running the real
# dispatcher rather than by asserting anything about a function.
#
# GUARDED ON THE FUNCTION EXISTING, NOT ON THE EXTRACTION, so against a
# pre-reap fleet.sh these FAIL rather than making this instrument refuse and
# taking its other thirty cases with it.
mkwtrepo() { # $1 name, $2 suffix -> prints the repo root; leaves a real worktree
  local r="$work/$1"
  mkdir -p "$r"
  git -C "$r" init -q -b main >/dev/null 2>&1
  git -C "$r" config user.email h@h; git -C "$r" config user.name H
  echo base > "$r/f"; git -C "$r" add -A >/dev/null; git -C "$r" commit -qm base >/dev/null
  git -C "$r" worktree add "$r-worktrees/$2" -b "bead/$2" >/dev/null 2>&1
  printf '%s' "$r"
}
reapcase() { # $1 name, $2 body, $3.. fixed strings the output must contain
  local name="$1" body="$2"; shift 2
  if ! have worker_reap_worktree; then
    no "$name" "this fleet.sh has no reaping branch: worker_reap_worktree does not exist (2026-09-09 docket item 1)"
    return
  fi
  local out want miss=""
  out="$(harness "$body" 2>&1)"
  for want in "$@"; do
    grep -qF -- <<<"$out" "$want" || miss="${miss:+$miss; }missing: $want"
  done
  if [ -z "$miss" ]; then ok "$name"; else no "$name" "$miss || got: $(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
}

# 32 REAPED. A settled worker's worktree is removed, and git stops listing it.
# `git worktree list` is asserted as well as the directory: an `rm -rf` would
# satisfy the directory test and leave a stale administrative entry behind.
r32="$(mkwtrepo reap32 aaa)"; mk aaa
# shellcheck disable=SC2016  # single quotes are the point: the body is interpolated into a `bash -c` string by harness() and must reach it UNEXPANDED.
reapcase "reap: a SETTLED worker's worktree is removed, and git no longer lists it"    'root="'"$r32"'"
    worker_set_state "$state/workers/aaa" settled "merged and closed"
    worker_reap_worktree "$state/workers/aaa" fortkit-aaa
    echo "RESULT=$reap_result"
    [ -e "$root-worktrees/aaa" ] && echo DIR-STILL-THERE || echo DIR-GONE
    git -C "$root" worktree list | grep -q -- "-worktrees/aaa" && echo GIT-STILL-LISTS || echo GIT-CLEAN'    RESULT=reaped DIR-GONE GIT-CLEAN

# 33 REFUSED — THE CONSTRAINT, AT UNIT LEVEL. A deferred merge is exactly the
# worker whose worktree Proofdelve ForgeOs-usz6's retry reads from, and it is `reapable`
# but NOT `settled`. IDENTICAL FIXTURE TO CASE 32, one field different: that
# pairing is what makes 32 evidence of discrimination rather than evidence that
# the function removes whatever it is handed.
r33="$(mkwtrepo reap33 bbb)"; mk bbb
# shellcheck disable=SC2016  # single quotes are the point: the body is interpolated into a `bash -c` string by harness() and must reach it UNEXPANDED.
reapcase "reap: a DEFERRED-MERGE worker keeps its worktree and the removal REFUSES"    'root="'"$r33"'"
    worker_set_state "$state/workers/bbb" deferred-merge "root not landable"
    worker_reap_worktree "$state/workers/bbb" fortkit-bbb
    echo "RESULT=$reap_result"
    [ -e "$root-worktrees/bbb" ] && echo DIR-STILL-THERE || echo DIR-GONE'    RESULT=refused DIR-STILL-THERE

# 34 REFUSED, THE OTHER DIRECTION (docket acceptance 2 and 4): a worker in a
# state needing a person keeps its worktree, because that worktree is the
# evidence the person was called for.
r34="$(mkwtrepo reap34 ccc)"; mk ccc
# shellcheck disable=SC2016  # single quotes are the point: the body is interpolated into a `bash -c` string by harness() and must reach it UNEXPANDED.
reapcase "reap: a NEEDS-PERSON worker keeps its worktree — that tree is the evidence"    'root="'"$r34"'"
    worker_set_state "$state/workers/ccc" needs-person "the close FAILED"
    worker_reap_worktree "$state/workers/ccc" fortkit-ccc
    echo "RESULT=$reap_result"
    [ -e "$root-worktrees/ccc" ] && echo DIR-STILL-THERE || echo DIR-GONE'    RESULT=refused DIR-STILL-THERE

# 35 ABSENT. Nothing to remove is not a failure and must not be reported as one.
r35="$(mkwtrepo reap35 ddd)"; mk ddd
git -C "$r35" worktree remove --force "$r35-worktrees/ddd" >/dev/null 2>&1
# shellcheck disable=SC2016  # single quotes are the point: the body is interpolated into a `bash -c` string by harness() and must reach it UNEXPANDED.
reapcase "reap: no worktree to remove reports ABSENT, which is neither a success nor a failure"    'root="'"$r35"'"
    worker_set_state "$state/workers/ddd" settled "merged and closed"
    worker_reap_worktree "$state/workers/ddd" fortkit-ddd
    echo "RESULT=$reap_result"'    RESULT=absent

# 36 FAILED — THE ONE ACCEPTANCE 6 IS ABOUT. The path exists and is NOT a
# registered worktree, so `git worktree remove --force` exits 128 with "is not a
# working tree" and the directory survives (measured 2026-09-09). The record
# must say so: `failed`, not `reaped`, and not `refused` either — a reader who
# is told a 257 MB tree was tidied away when it is still there will not look.
r36="$(mkwtrepo reap36 eee)"; mk eee
git -C "$r36" worktree remove --force "$r36-worktrees/eee" >/dev/null 2>&1
mkdir -p "$r36-worktrees/eee"; echo residue > "$r36-worktrees/eee/f"
# shellcheck disable=SC2016  # single quotes are the point: the body is interpolated into a `bash -c` string by harness() and must reach it UNEXPANDED.
reapcase "reap: a removal that FAILS says failed, is not confused with refused, and says the tree is still there"    'root="'"$r36"'"
    worker_set_state "$state/workers/eee" settled "merged and closed"
    worker_reap_worktree "$state/workers/eee" fortkit-eee
    echo "RESULT=$reap_result"
    [ -e "$root-worktrees/eee" ] && echo DIR-STILL-THERE || echo DIR-GONE'    RESULT=failed DIR-STILL-THERE 'IS STILL THERE'

# 36b-c reapable_workers() COUNTS WHAT THE NEXT REAP PASS WOULD TAKE, AND
# live_forges() DOES NOT MOVE (Proofdelve ForgeOs-dx34.18). A finished worker and a
# deferred merge count; a settled one, a running one and a needs-person one do
# not; and the governor's slot count still sees only the running one.
if have reapable_workers; then
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mk fin; printf '0\n' > "$work/state/workers/fin/exit"
  mk dfm; printf 'deferred-merge|R0|deferral 1\n' > "$work/state/workers/dfm/state"
  mk stl; printf 'settled|R0|merged\n' > "$work/state/workers/stl/state"
  mk npr; printf 'needs-person|R0|paged\n' > "$work/state/workers/npr/state"
  mk run; printf '%s\n' "$$" > "$work/state/workers/run/pid"   # this harness's own pid: alive
  out=$(harness "echo REAP=\$(reapable_workers) LIVE=\$(live_forges)" 2>/dev/null)
  if grep -q 'REAP=2 LIVE=1' <<<"$out"; then
    ok "dx34.18: reapable_workers counts finished + deferred-merge (2) and live_forges still counts only the running one (1)"
  else no "dx34.18: reapable_workers" "$out"; fi
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  out=$(harness "echo REAP=\$(reapable_workers)" 2>/dev/null)
  if grep -q 'REAP=0' <<<"$out"; then ok "dx34.18 vacuity: an empty workers directory counts 0"; else no "dx34.18 vacuity" "$out"; fi
else
  no "dx34.18: reapable_workers exists" "this fleet.sh has no reapable_workers(): the drain check cannot see a finished worker (Proofdelve ForgeOs-dx34.18)"
fi

# 37 THE WARDEN SCRATCH ROOT IS ONE SPELLING IN TWO FILES (Proofdelve ForgeOs-nv0j).
# fleet.sh reads <sfx>.log.result.json and <sfx>.log.record from $warden_root;
# warden.sh writes them there. Neither sources the other, so the two assignment
# lines are held byte-equal HERE: a root changed in one file and not the other
# makes review_one() fail closed on a result that exists somewhere else, spend
# every rung, and page a person over a review that recorded fine. warden.sh is
# taken from beside the launcher under test, so a candidate fleet.sh in a
# scratch directory scores NOT RUN rather than a false pass or a false fail.
wsh="$(dirname "$launcher")/warden.sh"
if [ -f "$wsh" ]; then
  fl_root="$(grep -m1 '^warden_root=' "$launcher" || true)"
  wd_root="$(grep -m1 '^warden_root=' "$wsh" || true)"
  if [ -n "$fl_root" ] && [ "$fl_root" = "$wd_root" ]; then
    ok "warden_root= is spelled identically in fleet.sh and warden.sh ($fl_root)"
  else no "warden_root= must be one spelling in fleet.sh and warden.sh" "fleet.sh: '${fl_root:-<absent>}'  warden.sh: '${wd_root:-<absent>}'"; fi
else
  echo "  NOT RUN  warden_root equality: no warden.sh beside $launcher (candidate in a scratch dir); run against the installed launcher"
fi


# Proofdelve ForgeOs-4hzq(B-ii): THE ZERO-COMMIT BRANCH GUARD. A Forge that exits 0 having
# committed nothing leaves bead/<sfx> at main; verifying it scores MAIN (green,
# meaningless) and hands the Warden an empty diff -- exactly what kbt4.4 did on
# 2026-09-14 01:41. reap_pass must RETURN it, never verify it. Against a pre-4hzq
# fleet.sh (FLEET_SH=<old>) this case FAILS: the old reap runs the verifier on
# the empty branch. Gated in reap_pass on the branch EXISTING, so 26b (a finished
# worker with no branch) still verifies -- the vacuity control here proves the
# guard does not swallow a branch that IS ahead.
g branch bead/zero 2>/dev/null   # at main: 0 commits ahead
mkdir -p "$repo-worktrees/zero"
rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/zero"
printf 'fortkit-zero\n' > "$work/state/workers/zero/bead"; printf '0\n' > "$work/state/workers/zero/exit"
out="$(reap '')"
if grep -q 'RETURNED fortkit-zero' <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out"; then
  ok "4hzq(B-ii): a Forge that exited 0 with 0 commits ahead of main is RETURNED, never verified"
else no "4hzq(B-ii): a zero-commit branch reached the verifier" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-240)"; fi
# vacuity: bead/def is one commit ahead (created in the fixture setup) -> verified as normal
rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/def"
printf 'fortkit-def\n' > "$work/state/workers/def/bead"; printf '0\n' > "$work/state/workers/def/exit"
out="$(reap '')"
if grep -q 'VERIFIER-RAN' <<<"$out"; then
  ok "4hzq(B-ii) vacuity: a branch WITH commits ahead of main is still verified (the guard does not swallow real work)"
else no "4hzq(B-ii) vacuity: a real branch was not verified" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-240)"; fi

# Proofdelve ForgeOs-ss9d: THE HANDOFF-ONLY BRANCH. A Forge that stops with a blocked
# handoff leaves it uncommitted; forge.sh's stamp step commits it, and the
# branch is one commit ahead of main with NOTHING outside fort/handoffs/ -- the
# 4hzq shape one commit wider (w4fm.4.1, 2026-09-14 12:32: a verify and a Warden
# launch spent on "handoff-only diff"). reap_pass must RETURN it before the
# verifier with a reason naming the handoff, keep the branch and its worktree,
# and still verify a branch that carries a handoff commit AND a product change.
# Against a pre-ss9d fleet.sh the first case FAILS (the old reap verifies it).
mkhand() { # $1 sfx, then paths to write on the branch (each gets content = its own name)
  local s="$1"; shift
  g branch "bead/$s" main; g worktree add -q "$repo-worktrees/$s" "bead/$s"
  local p; for p in "$@"; do mkdir -p "$repo-worktrees/$s/$(dirname "$p")"; printf '%s\n' "$p" > "$repo-worktrees/$s/$p"; done
  git -C "$repo-worktrees/$s" add -A; git -C "$repo-worktrees/$s" -c user.email=h@h -c user.name=h commit -qm "$s: stamp handoff attribution from launcher record"
}
mkhand hoo fort/handoffs/forge-2026-09-14-hoo.md
mkhand hps fort/handoffs/forge-2026-09-14-hps.md src/hps.cs
rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/hoo"
printf 'fortkit-hoo\n' > "$work/state/workers/hoo/bead"; printf '0\n' > "$work/state/workers/hoo/exit"
out="$(reap '')"
if grep -q 'RETURNED fortkit-hoo' <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out" && ! grep -q 'REVIEW-LAUNCHED' <<<"$out" \
   && grep -q 'no product change' <<<"$out" \
   && git -C "$repo" rev-parse --verify --quiet bead/hoo >/dev/null && [ -d "$repo-worktrees/hoo" ] \
   && [ "$(git -C "$repo" rev-list --count main..bead/hoo)" -eq 1 ]; then
  ok "ss9d: a branch whose only commit is the launcher's handoff stamp is RETURNED before the verifier with reason 'no product change'; branch, commit and worktree kept"
else no "ss9d: a handoff-only branch reached the verifier (or lost its record)" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300) commits=$(git -C "$repo" rev-list --count main..bead/hoo 2>/dev/null) wt=$([ -d "$repo-worktrees/hoo" ] && echo kept || echo GONE)"; fi
rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/hps"
printf 'fortkit-hps\n' > "$work/state/workers/hps/bead"; printf '0\n' > "$work/state/workers/hps/exit"
out="$(reap '')"
if grep -q 'VERIFIER-RAN' <<<"$out" && ! grep -q 'RETURNED' <<<"$out"; then
  ok "ss9d vacuity: a branch with a handoff commit AND a src/ change is verified as before (the guard reads product paths, not commit counts)"
else no "ss9d vacuity: a branch with real work beside its handoff was not verified" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi

# Proofdelve ForgeOs-nz3u: THE DECLARED DELIVERABLE. The ss9d case above IS criterion 3's
# undeclared half (a handoff-only branch with no declaration is RETURNED);
# these are the declared half and its two edges. bead_json is stubbed to hand
# back a description carrying `Deliverable: answer`, which is the only field
# deliverable_of() reads. Against a pre-nz3u fleet.sh the extraction has no
# deliverable_of() and the first case FAILS (the old reap returns hoo whatever
# the bead says). The end-to-end half is scenario 56 of fleet-e2e-harness.sh.
if have deliverable_of; then
  dl() { harness "bead_json(){ printf '%s' '{\"id\":\"X\",\"description\":\"$1\"}'; }; deliverable_of X"; }
  if [ "$(dl 'prose\nDeliverable: answer')" = answer ] && [ "$(dl 'Touches: x\n  Deliverable: Answer  ')" = answer ] \
     && [ -z "$(dl 'no line here')" ] && [ -z "$(dl 'Touches: fort/')" ] && [ -z "$(dl 'the deliverable: answer is prose, not a line')" ]; then
    ok "nz3u: deliverable_of reads a 'Deliverable: <word>' LINE (case-folded, indent tolerated) and nothing else -- prose mentioning the word, a Touches line, or no line all read as undeclared"
  else no "nz3u: deliverable_of parsing" "answer=[$(dl 'prose\nDeliverable: answer')] Answer=[$(dl 'Touches: x\n  Deliverable: Answer  ')] none=[$(dl 'no line here')] prose=[$(dl 'the deliverable: answer is prose, not a line')]"; fi
  # shellcheck disable=SC2016  # $1 is for the stubbed bead_json to expand at call time, inside the harness shell
  declared='bead_json(){ printf "%s" "{\"id\":\"$1\",\"description\":\"OBSERVED: fixture.\\nDeliverable: answer\"}"; }'
  # (a) declared + handoff-only -> VERIFIED, not returned (criterion 2)
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/hoo"
  printf 'fortkit-hoo\n' > "$work/state/workers/hoo/bead"; printf '0\n' > "$work/state/workers/hoo/exit"
  out="$(reap "$declared")"
  if grep -q 'VERIFIER-RAN' <<<"$out" && ! grep -q 'RETURNED' <<<"$out" && grep -q 'Deliverable: answer' <<<"$out"; then
    ok "nz3u: the SAME handoff-only branch (hoo) with 'Deliverable: answer' declared is VERIFIED and not returned, and the pass says why (side by side with the ss9d case above, criterion 3)"
  else no "nz3u: a declared handoff-only branch was returned or not verified" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # (b) declared + product change -> the ordinary path (never reaches the guard)
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/hps"
  printf 'fortkit-hps\n' > "$work/state/workers/hps/bead"; printf '0\n' > "$work/state/workers/hps/exit"
  out="$(reap "$declared")"
  if grep -q 'VERIFIER-RAN' <<<"$out" && ! grep -q 'RETURNED' <<<"$out" && ! grep -q 'Deliverable: answer' <<<"$out"; then
    ok "nz3u: a declared bead whose Forge ALSO changed src/ takes the ordinary path (verified, and the declaration is never consulted)"
  else no "nz3u: a declared bead with product change took the wrong path" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # (c) declared + ZERO commits -> still returned by the 4hzq guard (no handoff is not an answer)
  g branch bead/abc main 2>/dev/null; mkdir -p "$repo-worktrees/abc"   # at main: 0 commits ahead, the 4hzq shape
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/abc"
  printf 'fortkit-abc\n' > "$work/state/workers/abc/bead"; printf '0\n' > "$work/state/workers/abc/exit"
  out="$(reap "$declared")"
  if grep -q 'RETURNED fortkit-abc' <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out" && grep -q 'committed nothing' <<<"$out"; then
    ok "nz3u: a declared bead whose Forge committed NOTHING is still returned by the 4hzq guard (an absent handoff is not an answer)"
  else no "nz3u: the zero-commit guard let a declared bead through" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
else
  no "nz3u: deliverable_of exists" "this fleet.sh has no deliverable declaration (Proofdelve ForgeOs-nz3u): a handoff-only answer is returned whatever the bead says"
fi

# Proofdelve ForgeOs-b9mj: TOUCH SETS AND THE CO-DISPATCH GUARD, at the predicate level.
# The end-to-end half (two beads, one pass, concurrency 2) is scenario 42 of
# scripts/fleet-e2e-harness.sh; these cases pin the parsing and the intersection
# rule so a later "tidy" of either goes red here first. bead_json is stubbed to
# hand back a description, which is the only field touch_set_of() reads.
if have touch_set_of; then
  tset() { # $1 description -> the normalised set, one per line
    harness "bead_json(){ printf '%s' '{\"id\":\"X\",\"description\":\"$1\"}'; }; touch_set_of X"
  }
  if [ "$(tset 'prose\nTouches: web/src/App.tsx, docs/* ./src/x /abs/y\nTouches: second/ignored' | tr '\n' ' ')" = "web/src/App.tsx docs/ src/x abs/y " ]; then
    ok "b9mj: a Touches line parses on commas and whitespace, a glob is its prefix, ./ and / are dropped, and only the FIRST line counts"
  else no "b9mj: Touches parsing" "$(tset 'prose\nTouches: web/src/App.tsx, docs/* ./src/x /abs/y\nTouches: second/ignored' | tr '\n' ' ')"; fi
  if [ "$(tset 'no line here')" = "<everything>" ] && [ "$(tset 'Touches: *')" = "<everything>" ] && [ "$(tset 'Touches:   ')" = "<everything>" ]; then
    ok "b9mj: no Touches line, a bare '*', and an empty line each read as EVERYTHING (the conservative set)"
  else no "b9mj: the everything cases" "[$(tset 'no line here')] [$(tset 'Touches: *')] [$(tset 'Touches:   ')]"; fi
  if [ "$(tset 'Touches: src/Product.Infrastructure/Migrations/2026_x.cs, src/Product.Infrastructure/Migrations/ProductDbContextModelSnapshot.cs' | sort -u | tr '\n' ' ')" = "src/Product.Infrastructure/Migrations/ " ]; then
    ok "b9mj: any path under Migrations/ is widened to the whole directory (every migration rewrites the snapshot there)"
  else no "b9mj: migration widening" "$(tset 'Touches: src/Product.Infrastructure/Migrations/2026_x.cs')"; fi
  # the intersection rule, on files
  printf 'web/src/App.tsx\ndocs/\n' > "$work/tA"; printf 'web/src/\n' > "$work/tB"; printf 'src/Product.Api/\ntests/\n' > "$work/tC"; printf '<everything>\n' > "$work/tE"; : > "$work/tEmpty"
  isect() { harness "touch_sets_intersect '$work/$1' '$work/$2' || echo NO"; }
  if [ "$(isect tA tB)" = "web/src/App.tsx ~ web/src/" ] && [ "$(isect tB tA)" = "web/src/ ~ web/src/App.tsx" ]; then
    ok "b9mj: prefix intersection holds in BOTH directions and names the overlapping pair, first set's prefix first"
  else no "b9mj: prefix intersection" "[$(isect tA tB)] [$(isect tB tA)]"; fi
  if [ "$(isect tA tC)" = NO ] && [ "$(isect tC tB)" = NO ]; then
    ok "b9mj: disjoint sets do not intersect (the vacuity control: the rule can say no)"
  else no "b9mj: disjoint sets reported as overlapping" "[$(isect tA tC)] [$(isect tC tB)]"; fi
  if [ "$(isect tA tE)" = "<everything>" ] && [ "$(isect tE tC)" = "<everything>" ] && [ "$(isect tC tEmpty)" = "<everything>" ] && [ "$(isect tC /nonexistent)" = "<everything>" ]; then
    ok "b9mj: the everything sentinel intersects any set, and an EMPTY or ABSENT touches file (a worker from before this guard) reads as everything"
  else no "b9mj: sentinel / absent-file handling" "[$(isect tA tE)] [$(isect tE tC)] [$(isect tC tEmpty)] [$(isect tC /nonexistent)]"; fi
  # against live workers: only LIVE ones are consulted
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/liv" "$work/state/workers/old"
  printf 'fortkit-liv\n' > "$work/state/workers/liv/bead"; printf 'web/src/\n' > "$work/state/workers/liv/touches"; printf '%s\n' "$$" > "$work/state/workers/liv/pid"; date -Is > "$work/state/workers/liv/started"
  printf 'fortkit-old\n' > "$work/state/workers/old/bead"; printf 'docs/\n' > "$work/state/workers/old/touches"; printf 'settled|R0|done\n' > "$work/state/workers/old/state"
  out="$(harness "touch_conflict_with_live '$work/tA' || echo NO")"
  if [ "$out" = "fortkit-liv on web/src/App.tsx ~ web/src/" ]; then
    ok "b9mj: a candidate is checked against LIVE workers' cached sets and the answer names the worker and the pair"
  else no "b9mj: conflict with a live worker" "[$out]"; fi
  # FINDING 2 (the Warden, review of 40c3d6d): the first cut of this case passed tC,
  # which shares no prefix with the settled worker's docs/, so it returned NO
  # whether or not settled workers were consulted. tD overlaps docs/ and NOT
  # the live worker's web/src/, and the mutation control below flips the same
  # worker to deferred-merge and must see the answer flip.
  printf 'docs/\n' > "$work/tD"
  out="$(harness "touch_conflict_with_live '$work/tD' || echo NO")"
  if [ "$out" = NO ]; then
    ok "b9mj: a SETTLED worker's set (docs/, which DOES overlap the candidate) is never consulted -- it holds no branch"
  else no "b9mj: a settled worker blocked a candidate" "[$out]"; fi
  # FINDING 1: a worker that holds an UNLANDED branch without being live --
  # deferred-merge, finished, parked-* -- is consulted. The collision is at
  # the merge, and a deferred merge is exactly a branch waiting to collide.
  printf 'deferred-merge|R0|tree not landable\n' > "$work/state/workers/old/state"
  out="$(harness "touch_conflict_with_live '$work/tD' || echo NO")"
  if [ "$out" = "fortkit-old on docs/ ~ docs/" ]; then
    ok "b9mj: the SAME worker flipped to deferred-merge now blocks the candidate (mutation control for the case above; the Warden finding 1)"
  else no "b9mj: a deferred-merge worker did not hold its touch set" "[$out]"; fi
  rm -f "$work/state/workers/old/state"; printf '0\n' > "$work/state/workers/old/exit"   # finished: exit file, no state, no live pid
  out="$(harness "touch_conflict_with_live '$work/tD' || echo NO")"
  if [ "$out" = "fortkit-old on docs/ ~ docs/" ]; then
    ok "b9mj: a FINISHED (unreaped) worker holds its touch set too"
  else no "b9mj: a finished worker did not hold its touch set" "[$out]"; fi
  rm -f "$work/state/workers/old/exit"; printf 'settled|R0|done\n' > "$work/state/workers/old/state"
  # FINDING 3: dry-dispatched sets of the same pass are consulted
  mkdir -p "$work/state/.touches-dry"; printf 'docs/\n' > "$work/state/.touches-dry/fortkit-dry"
  out="$(harness "touch_conflict_with_live '$work/tD' || echo NO")"
  if [ "$out" = "fortkit-dry (dry-run, this pass) on docs/ ~ docs/" ]; then
    ok "b9mj: a set recorded by a dry-run dispatch earlier in the pass blocks a later dry candidate (the Warden finding 3)"
  else no "b9mj: dry-run pass-local sets are not consulted" "[$out]"; fi
  rm -rf "$work/state/.touches-dry"
else
  no "b9mj: touch_set_of exists" "this fleet.sh has no touch-set guard (Proofdelve ForgeOs-b9mj)"
fi

# Proofdelve ForgeOs-xzg1: THE CEILING IS CARRIED ACROSS RUNS. governor_init reads
# $state/ceiling.last (written by the two ordinary ends, removed by every halt
# path) and starts from it, clamped. The harness fixes START=3, MIN=1, MAX=6.
# The e2e half (a real drain writes it, a real halt removes it) is scenario 43
# of scripts/fleet-e2e-harness.sh.
if have governor_carry_out; then
  carry() { harness "mkdir -p '$work/state'; $1"; }
  rm -f "$work/state/ceiling.last"
  out="$(carry "governor_init; echo CONC=\$forge_conc")"
  if grep -q 'CONC=3' <<<"$out" && grep -q 'start forge_conc=3 (FLEET_FORGE_START)' "$work/ceiling.log"; then
    ok "xzg1: with no carry file a run starts at FLEET_FORGE_START and the ceiling log says so"
  else no "xzg1: no-file start" "$(printf '%s' "$out" | tr '\n' '|')"; fi
  out="$(carry "forge_conc=2; run_id=RPREV; governor_carry_out; run_id=T; governor_init; echo CONC=\$forge_conc")"
  if grep -q 'CONC=2' <<<"$out" && [ "$(cut -d'|' -f1,2 "$work/state/ceiling.last")" = "2|RPREV" ] \
     && grep -q 'start forge_conc=2 (carried from run RPREV)' "$work/ceiling.log"; then
    ok "xzg1: an ordinary end writes ceiling.last (value|run|time) and the next run starts from it, naming the run it came from"
  else no "xzg1: carry out / carry in" "$(printf '%s' "$out" | tr '\n' '|') file=[$(cat "$work/state/ceiling.last" 2>/dev/null)]"; fi
  printf '9|RBIG|t\n' > "$work/state/ceiling.last"
  out="$(carry "governor_init; echo CONC=\$forge_conc")"
  if grep -q 'CONC=6' <<<"$out" && grep -q 'clamped from 9 to FLEET_FORGE_MAX' "$work/ceiling.log"; then
    ok "xzg1: a carried value above FLEET_FORGE_MAX is clamped to MAX and the clamp is logged"
  else no "xzg1: MAX clamp" "$(printf '%s' "$out" | tr '\n' '|')"; fi
  printf '0|RZERO|t\n' > "$work/state/ceiling.last"
  out="$(carry "governor_init; echo CONC=\$forge_conc")"
  if grep -q 'CONC=1' <<<"$out" && grep -q 'clamped from 0 to FLEET_FORGE_MIN' "$work/ceiling.log"; then
    ok "xzg1: a carried value below FLEET_FORGE_MIN is clamped to MIN"
  else no "xzg1: MIN clamp" "$(printf '%s' "$out" | tr '\n' '|')"; fi
  printf 'garbage\n' > "$work/state/ceiling.last"
  out="$(carry "governor_init; echo CONC=\$forge_conc")"
  if grep -q 'CONC=3' <<<"$out" && grep -q "was unreadable ('garbage')" "$work/ceiling.log"; then
    ok "xzg1: an unreadable carry file is ignored, named in the log, and the run starts from FLEET_FORGE_START"
  else no "xzg1: unreadable file" "$(printf '%s' "$out" | tr '\n' '|')"; fi
  printf '2|RX|t\n' > "$work/state/ceiling.last"
  out="$(carry "governor_carry_reset 'halted'; governor_init; echo CONC=\$forge_conc")"
  if [ ! -e "$work/state/ceiling.last" ] && grep -q 'CONC=3' <<<"$out" && grep -q 'carry RESET (halted)' "$work/ceiling.log"; then
    ok "xzg1: a reset (every halt path) removes the carry file, logs it, and the next start is FLEET_FORGE_START again"
  else no "xzg1: reset" "$(printf '%s' "$out" | tr '\n' '|') exists=$([ -e "$work/state/ceiling.last" ] && echo yes || echo no)"; fi
  rm -f "$work/state/ceiling.last"
  out="$(carry "governor_init; forge_conc=4; launches=3; budget_stop 'x'; echo END=\$end_reason")"
  # Proofdelve ForgeOs-lzvo INVERTED this case: budget_stop used to carry mid-pass (the
  # xzg1 shape), leaving a later governor_down in the same pass uncarried. The
  # carry is now ONE call at loop exit (fleet-e2e scenario 51 measures that it
  # is the pass's LAST value); budget_stop only sets the reason.
  if [ ! -e "$work/state/ceiling.last" ] && grep -q 'END=budget spent' <<<"$out"; then
    ok "lzvo: budget_stop sets the reason and does NOT write the carry file -- the carry is one call at loop exit, so a later step in the same pass is not lost"
  else no "lzvo: budget_stop still carries mid-pass" "$(printf '%s' "$out" | tr '\n' '|') file=[$(cat "$work/state/ceiling.last" 2>/dev/null)]"; fi
  # Proofdelve ForgeOs-lzvo (the Warden's finding 5): governor_init runs AFTER the run lock, so a lock-refused instance writes no start line to ceiling.log
  gi="$(grep -n '^governor_init$' "$launcher" | head -1 | cut -d: -f1)"; fl="$(grep -n '^if ! flock -n 8; then$' "$launcher" | head -1 | cut -d: -f1)"
  if [ -n "$gi" ] && [ -n "$fl" ] && [ "$gi" -gt "$fl" ]; then
    ok "lzvo: governor_init (line $gi) is called after the run lock is taken (line $fl), so a refused instance writes no start line"
  else no "lzvo: governor_init before the lock" "governor_init at '${gi:-none}', flock at '${fl:-none}'"; fi
  # MUST NOT CHANGE: a carried start still steps DOWN immediately on back-pressure
  printf '4|RY|t\n' > "$work/state/ceiling.last"
  out="$(carry "governor_init; governor_down 'simulated 429'; echo CONC=\$forge_conc STREAK=\$clean_streak")"
  if grep -q 'CONC=3 STREAK=0' <<<"$out"; then
    ok "xzg1 MUST NOT CHANGE: back-pressure steps a carried ceiling down immediately and zeroes the streak"
  else no "xzg1: governor_down after a carried start" "$(printf '%s' "$out" | tr '\n' '|')"; fi
  rm -f "$work/state/ceiling.last"
else
  no "xzg1: governor_carry_out exists" "this fleet.sh does not carry the ceiling across runs (Proofdelve ForgeOs-xzg1)"
fi

# Proofdelve ForgeOs-36b9: LANDABILITY BEFORE THE REVIEW, REFRESH BEFORE THE VERIFY. Real
# branches and real worktrees in the fixture repo; run_verifier is stubbed to
# print the HEAD it was handed, so "verified at the refreshed tip" is a sha
# comparison and not a claim. page_overseer is stubbed to print its reason.
if have prelanding_refresh; then
  pre() { # $1 worker suffix -> reap output with the verifier and the pager announcing themselves
    rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/$1"
    printf 'fortkit-%s\n' "$1" > "$work/state/workers/$1/bead"; printf '0\n' > "$work/state/workers/$1/exit"
    # shellcheck disable=SC2016  # the single-quoted $state and $1 expand in the inner harness shell, on purpose
    reap 'state="'"$work"'/state"; mkdir -p "$state/logs"
      run_verifier(){ echo "VERIFIER-RAN at $(git -C "$1" rev-parse HEAD)"; return 0; }
      page_overseer(){ echo "PAGED $1 :: $2"; }'
  }
  # fixtures: main moves past every branch cut here, via a commit that edits g
  g checkout -q main; printf 'base\n' > "$repo/f"; printf 'base\n' > "$repo/g"; g add f g; g commit -qm "files"
  mkbr() { # $1 sfx, $2 file to edit on the branch
    g branch "bead/$1" main; g worktree add -q "$repo-worktrees/$1" "bead/$1"
    printf '%s\n' "$1" > "$repo-worktrees/$1/$2"; git -C "$repo-worktrees/$1" -c user.email=h@h -c user.name=h commit -qam "$1 edits $2"
  }
  mkbr pcl f          # clean: edits f
  mkbr pcf g          # conflict: edits g, which main also edits below
  mkbr pmh f          # refused: MERGE_HEAD present
  mkbr pwb f          # refused: worktree left on another branch
  printf 'main moved\n' > "$repo/g"; g commit -qam "main edits g"; mainsha="$(g rev-parse main)"
  # 36b9-1 CLEAN: refreshed, and the verifier ran at a tip that CONTAINS main
  out="$(pre pcl)"; tip="$(git -C "$repo-worktrees/pcl" rev-parse HEAD)"
  if grep -q 'refreshed .*pcl from main' <<<"$out" && grep -q "VERIFIER-RAN at $tip" <<<"$out" \
     && git -C "$repo" merge-base --is-ancestor "$mainsha" "bead/pcl" && grep -q 'REVIEW-LAUNCHED fortkit-pcl' <<<"$out"; then
    ok "36b9: a clean branch behind a moved main is REFRESHED in its worktree, verified AT THE REFRESHED TIP (which contains main), and then reviewed"
  else no "36b9: clean refresh" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300) tip=$tip contains-main=$(git -C "$repo" merge-base --is-ancestor "$mainsha" bead/pcl && echo yes || echo no)"; fi
  # 36b9-2 CONFLICT: paged with the path, nothing verified, nothing reviewed, tree untouched
  before="$(git -C "$repo-worktrees/pcf" rev-parse HEAD)"; out="$(pre pcf)"
  if grep -q 'CONFLICTS with main on g ' <<<"$out" && grep -q 'PAGED fortkit-pcf :: .*conflicts on: g ' <<<"$out" \
     && ! grep -q 'VERIFIER-RAN' <<<"$out" && ! grep -q 'REVIEW-LAUNCHED' <<<"$out" \
     && [ "$(git -C "$repo-worktrees/pcf" rev-parse HEAD)" = "$before" ] && ! git -C "$repo-worktrees/pcf" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
     && [ "$(head -1 "$work/state/workers/pcf/state" | cut -d'|' -f1)" = needs-person ] && [ -s "$work/state/logs/conflict-fortkit-pcf.txt" ]; then
    ok "36b9: a branch that CONFLICTS with a moved main is PAGED before the verifier and the review, naming the path; the worktree is untouched and merge-tree's output is the evidence"
  else no "36b9: conflict" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-400) state=$(head -1 "$work/state/workers/pcf/state" 2>/dev/null)"; fi
  # 36b9-3 REFUSED: a merge already in progress is not ours
  git -C "$repo-worktrees/pmh" merge --no-commit --no-ff -q main >/dev/null 2>&1 || true
  git -C "$repo-worktrees/pmh" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 || no "36b9-3 fixture: the --no-commit merge left no MERGE_HEAD" "fixture defect, not the subject's"
  out="$(pre pmh)"
  if grep -q 'PAGED fortkit-pmh :: .*MERGE_HEAD present' <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out" \
     && git -C "$repo-worktrees/pmh" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    ok "36b9: a worktree with a merge already in progress is REFUSED and paged; the fleet neither concludes nor aborts a merge it did not start"
  else no "36b9: MERGE_HEAD refusal" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300) merge_head=$(git -C "$repo-worktrees/pmh" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && echo present || echo absent)"; fi
  # 36b9-4 REFUSED: HEAD is not on the bead's branch
  git -C "$repo-worktrees/pwb" checkout -q --detach >/dev/null 2>&1
  out="$(pre pwb)"
  if grep -q "PAGED fortkit-pwb :: .*is on 'a detached HEAD', not bead/pwb" <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out"; then
    ok "36b9: a worktree whose HEAD is off its branch is REFUSED and paged, untouched"
  else no "36b9: off-branch refusal" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # Proofdelve ForgeOs-ubgx.3 item 2.4: THE CLAIMANT TRAVELS WITH THE CALL. It was a
  # top-level variable set before one call site and reset after it, and the
  # page's closing sentence is the only thing that reads it. The pwb fixture
  # above is already refused-and-paged, so it reaches that sentence; $4 is
  # where it lands.
  clm() { # $1 sfx, $2 = extra args after the worker dir ("" = omit them)
    rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/$1"
    printf 'fortkit-%s\n' "$1" > "$work/state/workers/$1/bead"
    harness "root='$repo'; main_branch=main
      page_overseer(){ printf 'CLOSING %s\n' \"\$4\"; }
      prelanding_refresh fortkit-$1 $1 '$repo-worktrees/$1' '$work/state/workers/$1' ${2:-}" 2>&1
  }
  out="$(clm pwb '')"
  if grep -q 'claimed by the Forge actor' <<<"$out"; then
    ok "ubgx.3 2.4: with no claimant argument the page says 'the Forge actor' -- the default is the ordinary dispatch case, unchanged"
  else no "ubgx.3 2.4: the default claimant is wrong or the page was not reached" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  out="$(clm pwb 'refresh "the fleet actor"')"
  if grep -q 'claimed by the fleet actor' <<<"$out" && ! grep -q 'claimed by the Forge actor' <<<"$out"; then
    ok "ubgx.3 2.4: the claimant passed as \$6 reaches the page's closing sentence -- a signed landing names the actor that actually holds the claim, with no global to set and reset"
  else no "ubgx.3 2.4: the sixth positional was ignored" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # AND THERE IS NO GLOBAL LEFT TO GET WRONG. The property, not the spelling:
  # the extracted code must not depend on any top-level prelanding_claimant,
  # which is what cost the fold a round (the 2026-09-14 unbound-variable rule).
  if ! grep -q 'prelanding_claimant' "$work/gov.sh"; then
    ok "ubgx.3 2.4: the extracted code carries no prelanding_claimant at all -- nothing for an extracting harness to find unbound and nothing for a caller to forget to reset"
  else no "ubgx.3 2.4: a prelanding_claimant reference survives in the extracted code" "$(grep -n prelanding_claimant "$work/gov.sh" | head -3)"; fi
  # 36b9-5 CURRENT: a branch that already contains main is verified as before, no refresh commit
  g branch bead/pcu main; g worktree add -q "$repo-worktrees/pcu" bead/pcu
  printf 'pcu\n' > "$repo-worktrees/pcu/f"; git -C "$repo-worktrees/pcu" -c user.email=h@h -c user.name=h commit -qam "pcu edits f"
  tip="$(git -C "$repo-worktrees/pcu" rev-parse HEAD)"; out="$(pre pcu)"
  if grep -q "VERIFIER-RAN at $tip" <<<"$out" && ! grep -q 'refreshed' <<<"$out" && [ "$(git -C "$repo-worktrees/pcu" rev-parse HEAD)" = "$tip" ]; then
    ok "36b9 MUST NOT CHANGE: a branch already containing main is verified at its own tip with no refresh commit"
  else no "36b9: current branch" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # 36b9-7 PARKED-REVIEW RESUME (the Warden finding 3 on 823074e): the landability
  # check runs WITHOUT a refresh -- a conflict pages before the review launch;
  # a clean-but-behind branch is reviewed on the tree that was verified, tip
  # unchanged. prv: conflicts (edits g, main edited g); pru: clean (edits f).
  mkbr prv g; mkbr pru f
  printf 'main moved again\n' > "$repo/g"; g commit -qam "main edits g again"
  prr() { # $1 sfx -> reap output for a parked-review worker
    rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/$1"
    printf 'fortkit-%s\n' "$1" > "$work/state/workers/$1/bead"; printf '0\n' > "$work/state/workers/$1/exit"
    printf 'parked-review|R0|budget\n' > "$work/state/workers/$1/state"
    # shellcheck disable=SC2016  # as above
    reap 'state="'"$work"'/state"; mkdir -p "$state/logs"; run_verifier(){ echo VERIFIER-RAN; return 0; }; page_overseer(){ echo "PAGED $1 :: $2"; }'
  }
  before="$(git -C "$repo-worktrees/prv" rev-parse HEAD)"; out="$(prr prv)"
  if grep -q 'PAGED fortkit-prv :: .*conflicts on: g ' <<<"$out" && ! grep -q 'REVIEW-LAUNCHED' <<<"$out" \
     && ! grep -q 'VERIFIER-RAN' <<<"$out" && [ "$(git -C "$repo-worktrees/prv" rev-parse HEAD)" = "$before" ]; then
    ok "36b9: a PARKED-REVIEW worker whose branch now conflicts with main is PAGED before the review launch, untouched (check-only; the Warden finding 3)"
  else no "36b9: parked-review conflict" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  tip="$(git -C "$repo-worktrees/pru" rev-parse HEAD)"; out="$(prr pru)"
  if grep -q 'REVIEW-LAUNCHED fortkit-pru' <<<"$out" && grep -q 'not refreshed here' <<<"$out" \
     && ! grep -q 'VERIFIER-RAN' <<<"$out" && [ "$(git -C "$repo-worktrees/pru" rev-parse HEAD)" = "$tip" ]; then
    ok "36b9: a PARKED-REVIEW worker behind a moved main that merges cleanly is reviewed on the tree that was verified -- no refresh commit, no second verify"
  else no "36b9: parked-review clean" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # 36b9-6 UNCHECKED: merge-tree cannot answer, so the pass says so and proceeds
  # in the OLD order. REFIXTURED under Proofdelve ForgeOs-tvb2: the old fixture was a worker
  # with NO worktree and NO branch ("fresh", the 26b shape), which reached
  # merge-tree only because the worktree was inspected after it; with the
  # inspection hoisted that shape is a REFUSAL (36b9-9 below), which is the
  # answer to the bead's design question. The unchecked path now needs a real
  # worktree on its own branch and a merge-tree that fails for another reason:
  # here, a git wrapper that refuses the merge-tree call and nothing else.
  mkbr pun f
  printf 'main moves past pun\n' > "$repo/g"; g commit -qam "main moves past pun"   # so pun is BEHIND main and the `current` short-circuit does not skip merge-tree
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/pun"
  printf 'fortkit-pun\n' > "$work/state/workers/pun/bead"; printf '0\n' > "$work/state/workers/pun/exit"
  # shellcheck disable=SC2016  # as above
  # merge-tree alone is made to fail (a git wrapper in the harness shell): overriding main_branch would trip the ss9d/4hzq diff checks upstream of prelanding
  out="$(reap 'state="'"$work"'/state"; mkdir -p "$state/logs"; git(){ if [ "${3:-}" = merge-tree ]; then echo "merge-tree: fixture refuses to answer" >&2; return 128; fi; command git "$@"; }; run_verifier(){ echo VERIFIER-RAN; return 0; }; page_overseer(){ echo "PAGED $1"; }')"
  if grep -q 'landability could not be checked before review' <<<"$out" && grep -q 'VERIFIER-RAN' <<<"$out" && ! grep -q 'PAGED' <<<"$out"; then
    ok "36b9: when merge-tree cannot answer (a wrapper refuses the call) the pass says so and proceeds in the OLD order rather than paging a false conflict"
  else no "36b9: unchecked path" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # ---- Proofdelve ForgeOs-tvb2: THE WORKTREE IS INSPECTED ON EVERY PATH, not only the one
  # that writes. Against a pre-tvb2 launcher 36b9-8, -9 and -10 all FAIL: the
  # detached tree and the non-worktree directory go to the verifier (or the
  # review) as if they were bead/X -- the positive control.
  # 36b9-8: a DETACHED worktree whose branch already CONTAINS main (the `current` path) is REFUSED, not verified
  g branch bead/pdt main; g worktree add -q "$repo-worktrees/pdt" bead/pdt
  printf 'pdt\n' > "$repo-worktrees/pdt/f"; git -C "$repo-worktrees/pdt" -c user.email=h@h -c user.name=h commit -qam "pdt edits f"
  git -C "$repo-worktrees/pdt" checkout -q --detach >/dev/null 2>&1
  out="$(pre pdt)"
  if grep -q "PAGED fortkit-pdt :: .*is on 'a detached HEAD', not bead/pdt" <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out" \
     && [ "$(head -1 "$work/state/workers/pdt/state" | cut -d'|' -f1)" = needs-person ]; then
    ok "tvb2: a DETACHED worktree whose branch already contains main is REFUSED and paged before the verifier (the current short-circuit no longer skips the inspection)"
  else no "tvb2: detached-but-current went to the verifier" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # 36b9-9: a plain DIRECTORY that is not a git worktree at all (the old 26b fixture's shape) is REFUSED -- the design question answered: refuse, do not fall through
  mkwt pnd; g worktree remove --force "$repo-worktrees/pnd" >/dev/null 2>&1   # the branch keeps its commit; the directory becomes a plain one
  mkdir -p "$repo-worktrees/pnd"; printf 'not a worktree\n' > "$repo-worktrees/pnd/f"
  out="$(pre pnd)"
  if grep -q "PAGED fortkit-pnd :: .*is on 'not a git worktree at all', not bead/pnd" <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out"; then
    ok "tvb2: a directory that is not a git worktree is REFUSED and paged, never verified as bead/X (the bead's design question: refuse, not fall through)"
  else no "tvb2: a non-worktree directory fell through" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # 36b9-10: check mode (a parked-review worker) with a detached HEAD is REFUSED, wording says the tree was verified green earlier and not reviewed
  g branch bead/prd main; g worktree add -q "$repo-worktrees/prd" bead/prd
  printf 'prd\n' > "$repo-worktrees/prd/f"; git -C "$repo-worktrees/prd" -c user.email=h@h -c user.name=h commit -qam "prd edits f"
  git -C "$repo-worktrees/prd" checkout -q --detach >/dev/null 2>&1
  out="$(prr prd)"
  if grep -q "PAGED fortkit-prd :: .*before reviewing it.*is on 'a detached HEAD', not bead/prd" <<<"$out" && ! grep -q 'REVIEW-LAUNCHED' <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out"; then
    ok "tvb2: a PARKED-REVIEW worker on a detached HEAD is REFUSED before the review launch, and the page says 'before reviewing it' (mode-aware wording; the stub pager prints only the message)"
  else no "tvb2: detached parked-review went to review" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-400)"; fi
else
  no "36b9: prelanding_refresh exists" "this fleet.sh checks landability only at the merge, after the review launch is spent (Proofdelve ForgeOs-36b9)"
fi

# Proofdelve ForgeOs-b9mj ROUND THREE (the Warden's blocking finding on ad911a7): a candidate
# held behind a REAPABLE, NOT-LIVE holder is a waiting pass, and the stall
# detector leaves its counter alone -- but only while a reapable worker
# actually exists, so the flag alone cannot switch the detector off.
if have stall_check && grep -q 'pass_held_unlanded' "$work/gov.sh"; then
  sc() { # $1 setup -> output; halt is stubbed to announce itself
    harness "stall_passes=0; stall_peak=0; waiting_said=0; reapable_said=0; held_said=0; FLEET_STALL_PASSES=3; narrative_log=/dev/null
      pass_dispatched=0; pass_reaped=0; pass_note=''; halt(){ echo \"HALT-CALLED: \$1 (\$2)\"; }
      $1"
  }
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/dm"
  printf 'fortkit-dm\n' > "$work/state/workers/dm/bead"; printf 'deferred-merge|R0|tree not landable\n' > "$work/state/workers/dm/state"
  out="$(sc "pass_held_unlanded=1; stall_check 0 yes; stall_check 0 yes; stall_check 0 yes; stall_check 0 yes; echo PASSES=\$stall_passes")"
  if grep -q 'PASSES=0' <<<"$out" && ! grep -q 'HALT-CALLED' <<<"$out" \
     && [ "$(printf '%s' "$out" | grep -c 'held behind a worker whose branch has not landed')" -eq 1 ]; then
    ok "b9mj r3: four quiet passes with a candidate held behind a DEFERRED-MERGE holder do not count as a stall, and the waiting sentence is said once"
  else no "b9mj r3: held-behind-unlanded counted as a stall" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # CONTROL: the flag with NO reapable worker still counts and still halts
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  out="$(sc "pass_held_unlanded=1; stall_check 0 yes; stall_check 0 yes; stall_check 0 yes; echo PASSES=\$stall_passes")"
  if grep -q 'HALT-CALLED: 3 consecutive passes' <<<"$out" ; then
    ok "b9mj r3 CONTROL: the held flag with no reapable worker in existence does NOT silence the detector -- three passes halt as before"
  else no "b9mj r3: the flag alone silenced the stall detector" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
  # CONTROL: no flag, a reapable worker, startable work -> counts (dx34.9 unchanged)
  mkdir -p "$work/state/workers/dm"; printf 'fortkit-dm\n' > "$work/state/workers/dm/bead"; printf 'deferred-merge|R0|x\n' > "$work/state/workers/dm/state"
  out="$(sc "stall_check 0 yes; stall_check 0 yes; stall_check 0 yes; echo PASSES=\$stall_passes")"
  if grep -q 'HALT-CALLED: 3 consecutive passes' <<<"$out"; then
    ok "b9mj r3 MUST NOT CHANGE: with nothing held, a reapable worker beside startable work still counts and halts on the third pass (dx34.9)"
  else no "b9mj r3: dx34.9's own case changed" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
else
  no "b9mj r3: stall_check knows pass_held_unlanded" "this fleet.sh halts the fleet on a candidate held behind a parked merge (the Warden, round two on ad911a7)"
fi

echo; 
# ---- Proofdelve ForgeOs-x2lv: a bead the Mayor closed while its worker was settling
# STAYS closed through the return pass. return_to_ready() is driven with a
# stub `bd` that records every write and a bead_json() stub that answers with
# a chosen status. Against a pre-x2lv launcher bead_status() is absent and the
# closed case still writes `--status open`: cases x2lv-1/2 FAIL (positive
# control); x2lv-3/4 (the open bead still escalates / still returns) pass on
# both, which is criterion 2's "the escalation must not go silent".
mkdir -p "$work/state/logs" "$work/bin"
cat > "$work/bin/bd" <<'STUB'
#!/bin/bash
printf 'BD %s\n' "$*" >> "${BD_LOG:?}"
exit 0
STUB
chmod +x "$work/bin/bd"
# shellcheck disable=SC2016  # bodies are evaluated by harness(); the $ are for THAT shell.
x2lv_run() {  # $1 status of the bead, $2 FLEET_MAX_RETURNS, $3 existing return count -> prints SAY/EMIT lines; BD_LOG holds the writes
  : > "$work/bdlog"
  BD_LOG="$work/bdlog" PATH="$work/bin:$PATH" harness "root='$work'; FLEET_MAX_RETURNS=$2
    bead_json(){ printf '{\"id\":\"fortkit-x\",\"status\":\"$1\",\"labels\":[\"fleet-safe\"$( [ "$3" -gt 0 ] && printf ',\"fleet-return-%s\"' "$3" )]}'; }
    emit(){ printf 'EMIT %s | %s\n' \"\$1\" \"\$2\"; }
    return_to_ready fortkit-x 'harness reason' ''" 2>&1
}
out=$(x2lv_run closed 2 1)
if ! grep -q 'BD ' "$work/bdlog" && grep -q '^EMIT fleet.returned | fortkit-x was closed before its return pass' <<<"$out"; then
  ok "x2lv-1: a CLOSED bead at its 2nd return (the escalation lap): NO bd write of any kind, and fleet.returned says it was closed and stayed closed"
else no "x2lv-1 closed bead escalation lap" "writes=$(tr '\n' '|' < "$work/bdlog") out=$(printf '%s' "$out" | tr '\n' '|')"; fi
out=$(x2lv_run closed 2 0)
if ! grep -q 'BD ' "$work/bdlog" && grep -q 'was closed before its return pass' <<<"$out"; then
  ok "x2lv-2: a CLOSED bead at its 1st return: no write, no counter label, no comment; the skip is on the stream"
else no "x2lv-2 closed bead first return" "writes=$(tr '\n' '|' < "$work/bdlog")"; fi
out=$(x2lv_run open 2 1)
if grep -q 'update fortkit-x --remove-label fleet-safe --add-label fleet-escalated --status open' "$work/bdlog" && grep -q 'update fortkit-x --add-label fleet-return-2' "$work/bdlog" && grep -q '^EMIT fleet.returned | fortkit-x returned 2 times and is escalated' <<<"$out"; then
  ok "x2lv-3: an OPEN bead at its 2nd return still escalates: fleet-safe removed, fleet-escalated and fleet-return-2 applied, fleet.returned says escalated (criterion 2: not silent)"
else no "x2lv-3 open bead still escalates" "writes=$(tr '\n' '|' < "$work/bdlog") out=$(printf '%s' "$out" | tr '\n' '|')"; fi
out=$(x2lv_run in_progress 2 0)
if grep -q 'update fortkit-x --status open --assignee ' "$work/bdlog" && grep -q 'update fortkit-x --add-label fleet-return-1' "$work/bdlog" && grep -q 'returned to ready (1 of 2)' <<<"$out"; then
  ok "x2lv-4: an in_progress bead at its 1st return is returned to ready exactly as before"
else no "x2lv-4 open bead first return unchanged" "writes=$(tr '\n' '|' < "$work/bdlog") out=$(printf '%s' "$out" | tr '\n' '|')"; fi
out=$(x2lv_run '' 2 1)
if grep -q 'fleet-escalated' "$work/bdlog"; then
  ok "x2lv-5: when bd will not say the status (empty), the return pass proceeds as before rather than treating unknown as closed"
else no "x2lv-5 unknown status proceeds" "writes=$(tr '\n' '|' < "$work/bdlog")"; fi

# --------------------------------------------------------------------------
# Proofdelve ForgeOs-uwjme: refill_slots() and where reap_pass() calls it. And
# Proofdelve ForgeOs-asad6 step 2: the memory gate's arithmetic, against crafted meminfo.
# Both absent from a pre-2026-10-15 launcher, where every case below FAILS
# rather than refusing, so this instrument stays usable against either file.
if ! have refill_slots; then
  no "uwjme: refill_slots exists" "this fleet.sh has no refill_slots: dispatch waits for the whole completion lane (Proofdelve ForgeOs-uwjme)"
  no "uwjme: reap_pass refills before taking a worker in hand and after its verifier" "same"
else
  rf() { # $1 setup -> output of one refill_slots call with dispatch_pass announcing itself
    harness "dry=0; in_dispatch=0; forge_conc=2
      stopping(){ return 1; }; budget_left(){ return 0; }
      dispatch_pass(){ echo \"DISPATCH \$*\"; }
      $1
      refill_slots 'at the test'" 2>/dev/null
  }
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  if rf '' | grep -q '^DISPATCH refill$'; then
    ok "uwjme: a free slot runs dispatch_pass in REFILL mode (the Forge half only)"
  else no "uwjme: a free slot did not refill" "$(rf '' | tr '\n' '|')"; fi
  if rf 'live_forges(){ echo 2; }' | grep -q DISPATCH; then
    no "uwjme: a booked lane must not read the tracker" "refill dispatched with 2 of 2 slots live"
  else ok "uwjme: with every slot live, refill is a no-op (no tracker read on a booked pass)"; fi
  if rf 'in_dispatch=1' | grep -q DISPATCH; then
    no "uwjme: refill must not nest inside a dispatch" "it dispatched with in_dispatch=1"
  else ok "uwjme: inside a dispatch (signed_landing -> land), refill does not nest"; fi
  if rf 'dry=1' | grep -q DISPATCH || rf 'budget_left(){ return 1; }' | grep -q DISPATCH || rf 'stopping(){ return 0; }' | grep -q DISPATCH; then
    no "uwjme: refill under dry-run, a spent budget or a stop" "it dispatched"
  else ok "uwjme: refill does nothing under --dry-run, a spent budget, or a stopping run"; fi
  if harness "dry=0; forge_conc=1; stopping(){ return 1; }; budget_left(){ return 0; }; dispatch_pass(){ echo DISPATCH; }; unset in_dispatch; refill_slots x" 2>&1 | grep -q 'unbound'; then
    no "uwjme: refill_slots reads an unset in_dispatch" "set -u killed it (an extracting harness or an early caller sees no top-level default)"
  else ok "uwjme: refill_slots tolerates in_dispatch unset (set -u safe)"; fi
  # THE CALL ORDER, executed through the shipped reap_pass with refill stubbed.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/rfa"; mkwt rfa   # the same shape as 26b's merely-finished worker
  printf 'fortkit-rfa\n' > "$work/state/workers/rfa/bead"; printf '0\n' > "$work/state/workers/rfa/exit"
  out="$(reap '')"   # reap() itself announces every refill
  seq_="$(grep -oE '^(REFILL before fortkit-rfa is taken in hand|VERIFIER-RAN|REFILL after fortkit-rfa.s host verifier|REVIEW-LAUNCHED fortkit-rfa)' <<<"$out" | tr '\n' '>')"
  if [ "$seq_" = "REFILL before fortkit-rfa is taken in hand>VERIFIER-RAN>REFILL after fortkit-rfa's host verifier>REVIEW-LAUNCHED fortkit-rfa>" ]; then
    ok "uwjme: reap_pass refills before the worker is taken in hand, runs the verifier, refills again, then reviews"
  else no "uwjme: reap_pass refill order" "seq=[$seq_] $(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
fi

if ! have mem_gate_why; then
  no "asad6: mem_gate_why exists" "this fleet.sh has no memory gate (Proofdelve ForgeOs-asad6 step 2)"
else
  mi() { printf 'MemTotal: 32673396 kB\nMemAvailable: %s kB\nSwapTotal: %s kB\nSwapFree: %s kB\n' "$1" "${2:-8388604}" "${3:-8388604}" > "$work/meminfo"; }
  mg() { # $1 setup -> "rc=N|why"
    harness "run_id=T; FLEET_MEMINFO='$work/meminfo'; FLEET_MEM_FLOOR_MB=8192; FLEET_MEM_PER_BUILD_MB=2560; FLEET_MEM_BUILD_WINDOW_S=900
      $1
      w=\$(mem_gate_why); echo \"rc=\$?|\$w\"" 2>/dev/null
  }
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  # need with no young Forge = 8192 + 2560 x 2 = 13312 MiB = 13631488 kB
  mi 13631488; a="$(mg '')"; mi 13630464; b="$(mg '')"
  if [ "${a%%|*}" = rc=0 ] && [ "${b%%|*}" = rc=1 ] && grep -q '13312 MiB' <<<"$b"; then
    ok "asad6: at exactly floor + 2 builds (13312 MiB) a launch clears; 1 MiB under, it waits, and the reason carries the numbers"
  else no "asad6: the gate's boundary" "at=[$a] under=[$b]"; fi
  # a YOUNG live Forge reserves a build; an OLD one does not (its memory is already in MemAvailable)
  mkdir -p "$work/state/workers/yg"; printf 'started\n' > "$work/state/workers/yg/started"
  mi 15000000; c="$(mg 'worker_live(){ return 0; }')"
  touch -d '-20 minutes' "$work/state/workers/yg/started"; d="$(mg 'worker_live(){ return 0; }')"
  if [ "${c%%|*}" = rc=1 ] && grep -q '1 young Forge' <<<"$c" && [ "${d%%|*}" = rc=0 ]; then
    ok "asad6: a live Forge inside the build window reserves 2.5G (15000000 kB waits); the same Forge 20 min old does not (clears)"
  else no "asad6: young-Forge reservation" "young=[$c] old=[$d]"; fi
  rm -rf "$work/state/workers/yg"
  e="$(harness "run_id=T; FLEET_MEMINFO='$work/nonexistent'; w=\$(mem_gate_why); echo \"rc=\$?|\$w\"" 2>/dev/null)"
  if [ "${e%%|*}" = rc=1 ] && grep -q 'failing closed' <<<"$e"; then
    ok "asad6: an unreadable meminfo FAILS CLOSED with a reason, never clears a launch"
  else no "asad6: unreadable meminfo" "[$e]"; fi
  if [ "${a%%|*}" = rc=0 ] && ! grep -q MEMGATE "$work/ceiling.log" 2>/dev/null; then :; fi
  if grep -q 'MEMGATE refuse  avail=13311MiB  young=0  need=13312MiB' "$work/ceiling.log" 2>/dev/null; then
    ok "asad6: every refusal writes its numbers to ceiling.log, so the defaults can be tuned from the record"
  else no "asad6: refusal not logged with numbers" "$(grep MEMGATE "$work/ceiling.log" 2>/dev/null | tail -2)"; fi
  sd() { # $1 avail kB, $2 swapfree kB -> governor_down lines
    mi "$1" 8388604 "$2"
    harness "run_id=T; forge_conc=3; FLEET_FORGE_MIN=1; mem_down_epoch=0; FLEET_MEMINFO='$work/meminfo'
      governor_down(){ echo \"DOWN \$1\"; }
      mem_stepdown_maybe; echo CONC=\$forge_conc" 2>/dev/null
  }
  f="$(sd 5000000 8388604)"; g="$(sd 14686564 9364)"; h="$(sd 7000000 9364)"
  if grep -q '^DOWN memory: MemAvailable 4882 MiB below 6144' <<<"$f" && ! grep -q '^DOWN' <<<"$g" && grep -q '^DOWN memory: swap full' <<<"$h"; then
    ok "asad6: steps down below 6 GiB available, and on swap-full only WITH available below the floor -- not on the measured idle host (swap 9 MB free, 14 GiB available)"
  else no "asad6: step-down conditions" "low=[$(tr '\n' '|' <<<"$f")] idle-swapfull=[$(tr '\n' '|' <<<"$g")] swapfull+low=[$(tr '\n' '|' <<<"$h")]"; fi
  i="$(mi 5000000; harness "run_id=T; forge_conc=3; FLEET_FORGE_MIN=1; mem_down_epoch=\$(date +%s); FLEET_MEMINFO='$work/meminfo'
      governor_down(){ echo \"DOWN \$1\"; }; mem_stepdown_maybe; echo done" 2>/dev/null)"
  if ! grep -q '^DOWN' <<<"$i"; then ok "asad6: step-down is throttled (at most once per FLEET_MEM_STEPDOWN_EVERY_S)"
  else no "asad6: step-down throttle" "$(tr '\n' '|' <<<"$i")"; fi
fi

# Proofdelve ForgeOs-xu0mj: a live NEEDS A PERSON is warned ONCE PER PASS, however many
# times the pass counts its slots (refill_slots() counts at every step of the
# completion lane). np_warned is the pass's set; the loop resets it each pass.
rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/npw"
printf 'fortkit-npw\n' > "$work/state/workers/npw/bead"; printf 'needs-person|OLD|a real conflict\n' > "$work/state/workers/npw/state"
# CALLED THE WAY EVERY PRODUCTION CALLER CALLS IT, as $(live_forges): a
# subshell. The first version of this case called it bare, so a set kept in a
# shell variable passed here and was lost in production, where it warned twice
# in one pass in the first live run (20261015T115003, 11:50:08 and 11:50:11).
# A new pass is the loop's own reset, the removal of the pass's set file.
rm -f "$work/state/.np-warned"
# shellcheck disable=SC2016  # single quotes are the point: the body reaches harness() UNEXPANDED
w2="$(harness 'a=$(live_forges); b=$(live_forges)' 2>&1 >/dev/null | grep -c 'fortkit-npw: NEEDS A PERSON')"
rm -f "$work/state/.np-warned"
# shellcheck disable=SC2016  # the same
w3="$(harness 'a=$(live_forges); rm -f "$state/.np-warned"; b=$(live_forges)' 2>&1 >/dev/null | grep -c 'fortkit-npw: NEEDS A PERSON')"
rm -f "$work/state/.np-warned"
if [ "$w2" -eq 1 ] && [ "$w3" -eq 2 ]; then
  ok "xu0mj: two slot counts in one pass warn about a live NEEDS A PERSON once; a new pass warns again (2 counts -> $w2, reset between -> $w3)"
else no "xu0mj: once-per-pass warning" "same pass -> $w2 (want 1), across passes -> $w3 (want 2)"; fi

# FOLD of the Warden's review of docket Proofdelve ForgeOs-9dqa6 (2026-10-15).
# Finding 1: no refill between a merge and its post-merge verifier. Read from the
# SHIPPED land(): between the merge command and the postmerge_verify call, no
# live (non-comment) line calls refill_slots. A Forge cut there builds on a main
# that has not been verified.
lm="$(awk '/^land\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$launcher" \
  | awk '/merge --no-ff/{m=1} m && /postmerge_verify "\$bead"/{exit} m' | grep -v '^[[:space:]]*#' | grep -c 'refill_slots' || true)"
lmerge="$(awk '/^land\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$launcher" | grep -c 'merge --no-ff' || true)"
if [ "$lmerge" -ge 1 ] && [ "$lm" -eq 0 ]; then
  ok "9dqa6 fold 1: land() refills nothing between the merge and its post-merge verifier"
else no "9dqa6 fold 1: a refill sits between the merge and the post-merge verifier" "refill calls there=$lm (merge anchors found=$lmerge)"; fi
# Finding 2: a memory refusal is LOGGED once per pass. mem_gate_why runs in $( )
# and can only READ pass_mem_held; the caller sets it after the first refusal.
if have mem_gate_why; then
  printf 'MemAvailable: 4194304 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n' > "$work/meminfo-low"
  rm -f "$work/ceiling.log"
  harness "run_id=T; FLEET_MEMINFO='$work/meminfo-low'; pass_mem_held=0; a=\$(mem_gate_why); pass_mem_held=1; b=\$(mem_gate_why); c=\$(mem_gate_why); echo \"\$c\"" > "$work/m2.out" 2>/dev/null
  nl="$(grep -c 'MEMGATE refuse' "$work/ceiling.log" 2>/dev/null || true)"
  if [ "${nl:-0}" -eq 1 ] && grep -q 'below the' "$work/m2.out"; then
    ok "9dqa6 fold 2: three refusals in one pass write ONE ceiling.log line, and every refusal still returns its reason"
  else no "9dqa6 fold 2: memory refusals logged per call, not per pass" "ceiling lines=${nl:-0} reason=[$(cat "$work/m2.out")]"; fi
fi

# Fold 3 (found live, not by the review): a stop that lands DURING the refill
# before a worker is taken in hand must stop the reap there, not after a verifier.
if have refill_slots; then
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers/stp"; mkwt stp
  printf 'fortkit-stp\n' > "$work/state/workers/stp/bead"; printf '0\n' > "$work/state/workers/stp/exit"
  # shellcheck disable=SC2016  # single quotes are the point: the body reaches harness() UNEXPANDED
  out="$(reap 'stop_now=0; refill_slots(){ echo "REFILL $1"; stop_now=1; }; stopping(){ [ "$stop_now" = 1 ]; }')"
  if grep -q '^REFILL before fortkit-stp' <<<"$out" && ! grep -q 'VERIFIER-RAN' <<<"$out" \
     && [ "$(head -1 "$work/state/workers/stp/state" 2>/dev/null | cut -d'|' -f1)" != in-hand ]; then
    ok "9dqa6 fold 3: a stop that arrives during the refill ends the reap before the worker is taken in hand -- no verifier starts while draining"
  else no "9dqa6 fold 3: a stop during the refill still starts the verifier" "$(printf '%s' "$out" | tr '\n' '|' | cut -c1-240)"; fi
fi

# ---------------------------------------------------------------------------
# Proofdelve ForgeOs-jfqu4.7: THE COMPLETION LANE'S ORDER. Each case builds worker
# directories whose names sort the OPPOSITE way to the order wanted, so glob
# order cannot pass by accident. bd is a shell function in the runner body, so
# the real tracker is never asked. The reap_pass-level case reads the order off
# the "REFILL before <bead> is taken in hand" line the reap() runner prints once
# per worker, in the order the lane takes them.
# Each RED arm is a variant of the extraction generated here and run through
# the same case, so the inversion is executed, not described.
# ---------------------------------------------------------------------------
jq_order_bd='bd(){ case " $* " in *" show "*) printf "[{\"id\":\"fortkit-aaa\",\"priority\":4},{\"id\":\"fortkit-mmm\",\"priority\":2},{\"id\":\"fortkit-zzz\",\"priority\":1},{\"id\":\"fortkit-ppp\",\"priority\":2},{\"id\":\"fortkit-qqq\",\"priority\":2},{\"id\":\"fortkit-ddd\",\"priority\":4}]\n" ;; *) return 1 ;; esac; }'
mkfin() { # $1 sfx, $2 exit mtime (touch -d)
  mkdir -p "$work/state/workers/$1"
  printf 'fortkit-%s\n' "$1" > "$work/state/workers/$1/bead"
  printf '0\n' > "$work/state/workers/$1/exit"; touch -d "$2" "$work/state/workers/$1/exit"
}
order_of() { # $1 gov file, $2 extra body -> the bead suffixes reap_order prints, space-separated
  local gf="$1"
  # Each call is a fresh pass: the main loop clears reap_order's once-per-pass
  # bd-down flag at the top of a pass (Proofdelve ForgeOs-4bzvk), and earlier reap() cases
  # in this file leave it behind in the shared fixture state.
  rm -f "$work/state/.reap-order-warned"
  bash -c "set -uo pipefail
    run_id=T; root='$work/no-such-root'; state='$work/state'; FLEET_LAUNCH_GRACE=120
    emit(){ :; }; say(){ printf 'SAY %s\n' \"\$*\" >&2; }; warn(){ :; }
    $(cat "$gf")
    $2
    reap_order" 2>"$work/order.err" | sed 's#.*/workers/##; s#/$##' | tr '\n' ' ' | sed 's/ $//'
}
if ! have reap_order; then
  for c in "priority beats name" "equal priority: oldest finish first" "a deferred merge and a parked signed landing go first" "bd down: finish-time order, said once" "reap_pass takes workers in reap_order"; do
    no "jfqu4.7: $c" "this fleet.sh has no reap_order(): the lane walks workers/*/ in glob order"
  done
else
  gv_glob="$work/gov-glob.sh"; gv_notie="$work/gov-notie.sh"; gv_fatal="$work/gov-fatal.sh"; gv_noprio="$work/gov-noprio.sh"; gv_nolane="$work/gov-nolane.sh"; gv_snap="$work/gov-snap.sh"
  # RED 1: priority ignored (the sort's priority key dropped) -- finish time alone.
  sed 's/sort -k1,1n -k2,2n -k3,3n -k4,4/sort -k1,1n -k3,3n -k4,4/' "$work/gov.sh" > "$gv_noprio"
  # RED 2: the tie-break dropped -- equal priorities fall back to name order.
  sed 's/sort -k1,1n -k2,2n -k3,3n -k4,4/sort -k1,1n -k2,2n -k4,4/' "$work/gov.sh" > "$gv_notie"
  # RED 3: a bd failure is fatal -- the lane takes nothing.
  sed 's/      say "reap order: bd could not report bead priorities this pass;.*/      return 1/' "$work/gov.sh" > "$gv_fatal"
  # RED 4: no fast lane -- land and signed resumes take an ordinary tier.
  # shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
  # The ordinary tier is 2 since Proofdelve ForgeOs-9srgz (tier 1 is a Workbench
  # review-only branch, at the front of the ordinary completions); the lane is
  # removed by putting merges and signed landings at the ORDINARY tier.
  sed 's/      land|signed) tier=0; prio=0 ;;/      land|signed) tier=2; prio="${prio_of[$bead]:-99}" ;;/' "$work/gov.sh" > "$gv_nolane"
  # RED 5: reap_pass walks the glob again (since Proofdelve ForgeOs-4bzvk the order is
  # re-asked inside the loop, so the glob replaces that question).
  # shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
  sed 's|^    for c in \$(reap_order); do$|    for c in "$state/workers"/*/; do|' "$work/gov.sh" > "$gv_glob"
  # RED 6 (Proofdelve ForgeOs-4bzvk): the order asked ONCE at the top of the pass and the
  # snapshot walked, which is the shape before 4bzvk, rebuilt from today's loop.
  # shellcheck disable=SC2016  # sed PATTERNS: the $ names the launcher's own text, literally
  sed -e '/^  local d c sfx bead wt vout resume frc taken=" "$/a\  local snap; snap="$(reap_order)"' \
      -e 's|^    for c in \$(reap_order); do$|    for c in $snap; do|' "$work/gov.sh" > "$gv_snap"
  for v in "$gv_noprio" "$gv_notie" "$gv_fatal" "$gv_nolane" "$gv_glob" "$gv_snap"; do
    cmp -s "$v" "$work/gov.sh" && { no "jfqu4.7: RED variant $(basename "$v") could not be generated" "sed matched nothing; the case below would not be inverted"; }
  done
  # A. priority beats name: aaa P4 finished first, mmm P2, zzz P1 finished last.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkfin aaa '2026-10-21 10:00'; mkfin mmm '2026-10-21 10:10'; mkfin zzz '2026-10-21 10:20'
  got="$(order_of "$work/gov.sh" "$jq_order_bd")"
  if [ "$got" = "zzz mmm aaa" ]; then ok "jfqu4.7: priority beats name and finish time (P1 zzz, P2 mmm, P4 aaa)"; else no "jfqu4.7: priority beats name" "got '$got'"; fi
  got="$(order_of "$gv_noprio" "$jq_order_bd")"
  if [ "$got" != "zzz mmm aaa" ]; then ok "jfqu4.7 RED: with the priority key dropped the same fixture is NOT priority-ordered (got '$got')"; else no "jfqu4.7 RED: priority key dropped" "still priority-ordered: the case cannot see priority"; fi
  # B. equal priority: ppp finished BEFORE qqq... named so name order is the reverse.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkfin qqq '2026-10-21 09:00'; mkfin ppp '2026-10-21 11:00'
  got="$(order_of "$work/gov.sh" "$jq_order_bd")"
  if [ "$got" = "qqq ppp" ]; then ok "jfqu4.7: equal priority -- oldest finish first (qqq 09:00 before ppp 11:00)"; else no "jfqu4.7: equal priority: oldest finish first" "got '$got'"; fi
  got="$(order_of "$gv_notie" "$jq_order_bd")"
  if [ "$got" = "ppp qqq" ]; then ok "jfqu4.7 RED: with the tie-break dropped equal priorities fall to name order (got '$got')"; else no "jfqu4.7 RED: tie-break dropped" "got '$got', expected name order"; fi
  # C. the fast lane: a P4 deferred merge (ddd) and a parked signed landing
  # (zzz, P1 here but it is the lane, not the priority, that matters) both go
  # ahead of a P1 finished worker named aaa... priority alone would take aaa first.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkfin aaa '2026-10-21 08:00'
  mkfin ddd '2026-10-21 09:00'; printf 'deferred-merge|OLD|deferral 1\n' > "$work/state/workers/ddd/state"; touch -d '2026-10-21 09:00' "$work/state/workers/ddd/state"
  mkfin zzz '2026-10-21 09:30'; printf 'parked-signed|OLD|stopped by a signal\n' > "$work/state/workers/zzz/state"
  bd_aaa_p1='bd(){ case " $* " in *" show "*) printf "[{\"id\":\"fortkit-aaa\",\"priority\":0},{\"id\":\"fortkit-ddd\",\"priority\":4},{\"id\":\"fortkit-zzz\",\"priority\":4}]\n" ;; *) return 1 ;; esac; }'
  got="$(order_of "$work/gov.sh" "$bd_aaa_p1")"
  if [ "$got" = "ddd zzz aaa" ]; then ok "jfqu4.7: a deferred merge and a parked signed landing (both P4) go ahead of a finished P0"; else no "jfqu4.7: the merge lane goes first" "got '$got'"; fi
  got="$(order_of "$gv_nolane" "$bd_aaa_p1")"
  if [ "$got" != "ddd zzz aaa" ]; then ok "jfqu4.7 RED: with the merge lane removed the P0 is taken first (got '$got')"; else no "jfqu4.7 RED: merge lane removed" "order unchanged"; fi
  # D. bd down: finish-time order, said once, and the lane still runs.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkfin aaa '2026-10-21 12:00'; mkfin mmm '2026-10-21 10:00'; mkfin zzz '2026-10-21 11:00'
  got="$(order_of "$work/gov.sh" 'bd(){ return 1; }')"; said="$(grep -c 'bd could not report bead priorities' "$work/order.err")"
  if [ "$got" = "mmm zzz aaa" ] && [ "$said" = 1 ]; then ok "jfqu4.7: bd down -- the lane runs in finish-time order and says so once"; else no "jfqu4.7: bd down" "got '$got', said=$said"; fi
  got="$(order_of "$gv_fatal" 'bd(){ return 1; }')"
  if [ -z "$got" ]; then ok "jfqu4.7 RED: a fatal bd failure takes nothing at all (the case sees the difference)"; else no "jfqu4.7 RED: fatal bd failure" "still got '$got'"; fi
  # E. reap_pass itself follows reap_order, end to end through the shipped loop.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  for s in aaa mmm zzz; do mkwt "$s"; done
  mkfin aaa '2026-10-21 10:00'; mkfin mmm '2026-10-21 10:10'; mkfin zzz '2026-10-21 10:20'
  lane_of() { grep -o '^REFILL before fortkit-[a-z]* is taken in hand' | sed 's/REFILL before fortkit-//; s/ is taken in hand//' | tr '\n' ' ' | sed 's/ $//'; }
  # FLEET_REAP_PER_PASS=9: these cases are about ORDER across three workers;
  # the per-pass cap (Proofdelve ForgeOs-bzr1z, default 2) has its own cases below.
  got="$(reap "$jq_order_bd
    FLEET_REAP_PER_PASS=9" | lane_of)"
  if [ "$got" = "zzz mmm aaa" ]; then ok "jfqu4.7: reap_pass takes finished workers in reap_order (P1 zzz first, P4 aaa last)"; else no "jfqu4.7: reap_pass follows reap_order" "got '$got'"; fi
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  for s in aaa mmm zzz; do mkwt "$s"; done
  mkfin aaa '2026-10-21 10:00'; mkfin mmm '2026-10-21 10:10'; mkfin zzz '2026-10-21 10:20'
  got="$(cp "$work/gov.sh" "$work/gov.keep"; cp "$gv_glob" "$work/gov.sh"; reap "$jq_order_bd
    FLEET_REAP_PER_PASS=9" | lane_of; cp "$work/gov.keep" "$work/gov.sh")"
  if [ "$got" = "aaa mmm zzz" ]; then ok "jfqu4.7 RED: reap_pass reverted to the glob takes aaa (P4) first"; else no "jfqu4.7 RED: glob reap_pass" "got '$got'"; fi
  # F. Proofdelve ForgeOs-4bzvk: A P0 THAT BECOMES REAPABLE AFTER THE PASS STARTS IS TAKEN
  # NEXT. aaa (P4) and mmm (P2) are finished at the top of the pass; zzz (P1, the
  # most urgent here) is still RUNNING (a live pid, no exit file) and finishes
  # while the first worker is being taken in hand -- the refill_slots stub writes
  # its exit file on its first call. A fresh order after mmm puts zzz ahead of
  # aaa; a snapshot from the top of the pass does not contain zzz at all.
  mk4bzvk() {
    rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
    for s in aaa mmm zzz; do mkwt "$s"; done
    mkfin aaa '2026-10-21 10:00'; mkfin mmm '2026-10-21 10:10'
    mkdir -p "$work/state/workers/zzz"; printf 'fortkit-zzz\n' > "$work/state/workers/zzz/bead"; printf '%s\n' "$$" > "$work/state/workers/zzz/pid"
  }
  finish_zzz="refill_slots(){ echo \"REFILL \$1\"; [ -e '$work/state/workers/zzz/exit' ] || printf '0\\n' > '$work/state/workers/zzz/exit'; }"
  mk4bzvk
  got="$(reap "$jq_order_bd
    FLEET_REAP_PER_PASS=9
    $finish_zzz" | lane_of)"
  if [ "$got" = "mmm zzz aaa" ]; then ok "4bzvk: a P1 that finishes while the first worker is taken is reaped next, ahead of the P4 already waiting (mmm zzz aaa)"; else no "4bzvk: a worker finishing mid-pass is taken next" "got '$got'"; fi
  mk4bzvk
  got="$(cp "$work/gov.sh" "$work/gov.keep"; cp "$gv_snap" "$work/gov.sh"; reap "$jq_order_bd
    FLEET_REAP_PER_PASS=9
    $finish_zzz" | lane_of; cp "$work/gov.keep" "$work/gov.sh")"
  if [ "$got" = "mmm aaa" ]; then ok "4bzvk RED: with the order asked once per pass, the worker that finished mid-pass is not taken this pass at all (mmm aaa)"; else no "4bzvk RED: snapshot order" "got '$got', expected mmm aaa"; fi
  # F2. and a worker already taken this pass is not taken twice when it stays
  # reapable (a deferred merge): the lane ends instead of looping.
  rm -rf "$work/state/workers"; mkdir -p "$work/state/workers"
  mkwt ddd; mkdefer ddd ddd APPROVE yes
  # The land stub stops the run on its fourth call, so a lane that loops fails
  # this case instead of hanging the verifier.
  rm -f "$work/land.count"
  got="$(reap "$jq_order_bd
    land(){ echo \"LAND bead=\$1\"; n=\$(cat '$work/land.count' 2>/dev/null || echo 0); echo \$((n + 1)) > '$work/land.count'; [ \"\$n\" -lt 3 ] || exit 9; }" | grep -c '^LAND bead=fortkit-ddd')"
  if [ "$got" = 1 ]; then ok "4bzvk: a worker that stays reapable after its turn (a deferred merge) is taken once per pass, not again"; else no "4bzvk: a reapable-again worker looped" "LAND printed $got times"; fi

  # G. Proofdelve ForgeOs-w5xkw: A BEAD RE-DISPATCHED INSIDE ONE PASS IS REAPED AGAIN IN
  # THAT PASS. zzz (P1) is taken first; while aaa is being taken in hand, zzz is
  # returned and re-dispatched into the SAME worker directory (rm -rf, a new
  # started stamp) and its Forge finishes. Keyed by the launch, the second
  # finish is a new entry: lane "zzz aaa zzz". Keyed by the directory (RED), it
  # is invisible until the run ends: "zzz aaa".
  gv_dirkey="$work/gov-dirkey.sh"
  # shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
  sed 's|^      key="\$c@\$(cat "\$c/started" 2>/dev/null \|\| echo -)"$|      key="$c"|' "$work/gov.sh" > "$gv_dirkey"
  mkw5x() {
    rm -rf "$work/state/workers" "$work/redispatched"; mkdir -p "$work/state/workers"
    for s in aaa zzz; do mkwt "$s"; done
    mkfin aaa '2026-10-21 10:00'; mkfin zzz '2026-10-21 10:10'
    printf '2026-10-21T10:00:00-08:00\n' > "$work/state/workers/zzz/started"
  }
  redispatch_zzz="refill_slots(){ echo \"REFILL \$1\"; case \"\$1\" in *fortkit-aaa*) [ -e '$work/redispatched' ] || { : > '$work/redispatched'; rm -rf '$work/state/workers/zzz'; mkdir -p '$work/state/workers/zzz'; printf 'fortkit-zzz\n' > '$work/state/workers/zzz/bead'; printf '2026-10-21T10:30:00-08:00\n' > '$work/state/workers/zzz/started'; printf '0\n' > '$work/state/workers/zzz/exit'; } ;; esac; }"
  # shellcheck disable=SC2016  # the literal launcher spelling is what is searched for
  if ! grep -q 'key="\$c@' "$work/gov.sh"; then
    no "w5xkw: a re-dispatched worker is reaped again within the pass" "this fleet.sh keys taken by directory alone (no started stamp in the key)"
    mkw5x; got="$(reap "$jq_order_bd
      FLEET_REAP_PER_PASS=9
      $redispatch_zzz" | lane_of)"
    no "w5xkw (measured on this file)" "lane '$got'"
  else
    mkw5x; got="$(reap "$jq_order_bd
      FLEET_REAP_PER_PASS=9
      $redispatch_zzz" | lane_of)"
    if [ "$got" = "zzz aaa zzz" ]; then ok "w5xkw: a bead returned and re-dispatched into its own worker dir inside one pass is reaped again in that pass (zzz aaa zzz)"; else no "w5xkw: re-dispatch reaped within the pass" "got '$got'"; fi
    if cmp -s "$gv_dirkey" "$work/gov.sh"; then no "w5xkw RED" "the directory-key variant could not be generated (sed matched nothing)"
    else
      mkw5x; got="$(cp "$work/gov.sh" "$work/gov.keep"; cp "$gv_dirkey" "$work/gov.sh"; reap "$jq_order_bd
        FLEET_REAP_PER_PASS=9
        $redispatch_zzz" | lane_of; cp "$work/gov.keep" "$work/gov.sh")"
      if [ "$got" = "zzz aaa" ]; then ok "w5xkw RED: keyed by directory alone, the re-dispatched zzz is NOT reaped again this pass (zzz aaa)"; else no "w5xkw RED: directory key" "got '$got', expected zzz aaa"; fi
    fi
  fi

  # H. Proofdelve ForgeOs-bzr1z: THE PASS IS BOUNDED. aaa, mmm, zzz finished; every
  # refill finishes ANOTHER Forge (s1..s5), the shape of a busy run fed by
  # Proofdelve ForgeOs-uwjme. With the cap at its default (2) the pass takes zzz and mmm
  # and ends, saying so, so the next pass reaches phase 1 (signed landings).
  # RED: the cap removed, the stream keeps the pass going.
  gv_nocap="$work/gov-nocap.sh"
  # shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
  sed 's|^        if \[ "\$full_taken" -ge "\$reap_cap" \]; then$|        if false; then|' "$work/gov.sh" > "$gv_nocap"
  mkstream() {
    rm -rf "$work/state/workers" "$work/stream.n"; mkdir -p "$work/state/workers"
    for s in aaa mmm zzz; do mkwt "$s"; done
    mkfin aaa '2026-10-21 10:00'; mkfin mmm '2026-10-21 10:10'; mkfin zzz '2026-10-21 10:20'
  }
  stream="refill_slots(){ echo \"REFILL \$1\"; n=\$(cat '$work/stream.n' 2>/dev/null || echo 0); [ \"\$n\" -lt 5 ] || return 0; n=\$((n + 1)); echo \$n > '$work/stream.n'; mkdir -p '$work/state/workers/s'\$n; printf 'fortkit-s%s\n' \$n > '$work/state/workers/s'\$n/bead; printf '0\n' > '$work/state/workers/s'\$n/exit; }"
  lane_any() { grep -o '^REFILL before fortkit-[a-z0-9]* is taken in hand' | sed 's/REFILL before fortkit-//; s/ is taken in hand//' | tr '\n' ' ' | sed 's/ $//'; }
  if ! grep -q 'reap_cap' "$work/gov.sh"; then
    mkstream; got="$(reap "$jq_order_bd
      $stream" | lane_any)"
    no "bzr1z: the reap pass is bounded" "this fleet.sh has no per-pass cap; a refill stream kept the pass going: lane '$got'"
  else
    mkstream; out="$(reap "$jq_order_bd
      $stream")"; got="$(lane_any <<<"$out")"
    if [ "$got" = "zzz mmm" ] && grep -q 'reap pass ends after 2 verify-or-review completion(s) (FLEET_REAP_PER_PASS=2)' <<<"$out"; then
      ok "bzr1z: with a refill stream finishing Forges, the pass takes 2 (zzz mmm) and ENDS, saying so -- the next pass starts with the signed landings"
    else no "bzr1z: the reap pass is bounded" "lane '$got'; $(grep 'reap pass ends' <<<"$out" || echo 'no reap-pass-ends line')"; fi
    if cmp -s "$gv_nocap" "$work/gov.sh"; then no "bzr1z RED" "the no-cap variant could not be generated (sed matched nothing)"
    else
      mkstream; got="$(cp "$work/gov.sh" "$work/gov.keep"; cp "$gv_nocap" "$work/gov.sh"; reap "$jq_order_bd
        $stream" | lane_any; cp "$work/gov.keep" "$work/gov.sh")"
      if [ "$(wc -w <<<"$got")" -gt 2 ]; then ok "bzr1z RED: without the cap the stream keeps the same pass going ($(wc -w <<<"$got") workers: $got)"; else no "bzr1z RED: no cap" "got '$got', expected more than 2"; fi
    fi
    # H2. A tier-0 resume (land/signed: a merge, no review) does not count and
    # is still taken after the cap. ddd becomes a deferred merge while mmm is
    # taken in hand (the 297ul shape: landable again mid-pass). Lane: zzz mmm
    # ddd, LAND for ddd, then the cap ends the pass before aaa. RED: tier 0
    # counted, ddd waits for the next pass.
    gv_t0="$work/gov-t0counted.sh"
    sed 's/^      land|signed) ;;$/      land_never_matches) ;;/' "$work/gov.sh" > "$gv_t0"
    mkwt ddd
    defer_ddd="refill_slots(){ echo \"REFILL \$1\"; case \"\$1\" in *fortkit-mmm*) mkdir -p '$work/state/workers/ddd'; printf 'fortkit-ddd\n' > '$work/state/workers/ddd/bead'; printf '0\n' > '$work/state/workers/ddd/exit'; printf 'APPROVE\n' > '$work/state/workers/ddd/verdict'; printf 'deferred-merge|OLDRUN|deferral 1\n' > '$work/state/workers/ddd/state' ;; esac; }
      land(){ echo \"LAND bead=\$1\"; }"
    mkstream; out="$(reap "$jq_order_bd
      $defer_ddd")"; got="$(lane_of <<<"$out")"
    if [ "$got" = "zzz mmm ddd" ] && grep -q '^LAND bead=fortkit-ddd' <<<"$out"; then
      ok "bzr1z: a merge that becomes reapable after the cap is reached is still taken in the same pass (zzz mmm ddd, LAND ddd); aaa waits"
    else no "bzr1z: tier 0 is not capped" "lane '$got'"; fi
    if cmp -s "$gv_t0" "$work/gov.sh"; then no "bzr1z tier-0 RED" "the variant could not be generated (sed matched nothing)"
    else
      mkstream; got="$(cp "$work/gov.sh" "$work/gov.keep"; cp "$gv_t0" "$work/gov.sh"; reap "$jq_order_bd
        $defer_ddd" | lane_of; cp "$work/gov.keep" "$work/gov.sh")"
      if [ "$got" = "zzz mmm" ]; then ok "bzr1z RED: with tier 0 counted against the cap, the deferred merge waits for the next pass (zzz mmm)"; else no "bzr1z tier-0 RED" "got '$got', expected zzz mmm"; fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# I. Proofdelve ForgeOs-8gmt4 (Regent docket 2026-10-27 item C): A HELD BEAD WHOSE BRANCH
# STOPS MERGING IS HANDED TO THE MAYOR BEFORE A SIGNATURE IS SPENT. stc is held
# (ESCALATE) and conflicts with main on conf-8gmt4.txt; stk is held and merges
# cleanly; sta conflicts the same way but its stored verdict is APPROVE (not
# held). Only stc gets mayor-review, the Mayor as assignee, and one comment
# naming the file; a second pass on the same conflict is silent.
# ---------------------------------------------------------------------------
if ! have stale_signature_check; then
  no "8gmt4: a held bead that stops merging is handed to the Mayor" "this fleet.sh has no stale_signature_check(): a signature on a stale branch is discovered only at the landing"
else
  g checkout -q main; printf 'base\n' > "$repo/conf-8gmt4.txt"; g add conf-8gmt4.txt; g commit -qm "8gmt4 base"
  for s in stc sta; do
    g branch -f "bead/$s" main; g checkout -q "bead/$s"; printf 'branch %s\n' "$s" > "$repo/conf-8gmt4.txt"; g commit -qam "$s work"; g checkout -q main
  done
  g branch -f bead/stk main; g checkout -q bead/stk; printf 'new\n' > "$repo/stk-8gmt4.txt"; g add stk-8gmt4.txt; g commit -qm "stk work"; g checkout -q main
  printf 'main moved\n' > "$repo/conf-8gmt4.txt"; g commit -qam "8gmt4: main moves under the held branches"
  mkstc() {
    rm -rf "$work/state/workers" "$work/stc.bd"; mkdir -p "$work/state/workers" "$work/state/logs"
    for s in stc stk sta; do
      mkdir -p "$work/state/workers/$s"; printf 'fortkit-%s\n' "$s" > "$work/state/workers/$s/bead"
      printf 'settled|R0|held\n' > "$work/state/workers/$s/state"
    done
    printf 'ESCALATE\n' > "$work/state/workers/stc/verdict"; printf 'ESCALATE\n' > "$work/state/workers/stk/verdict"
    printf 'APPROVE\n' > "$work/state/workers/sta/verdict"
  }
  stc_run() { # $1 gov file, $2 dry (0|1)
    local keep="$work/gov.stc.keep"; cp "$work/gov.sh" "$keep"; cp "$1" "$work/gov.sh"
    harness "root='$repo'; run_id=R1; dry=$2; main_branch=main
      stopping(){ return 1; }
      bd(){ printf '%s\n' \"\$*\" >> '$work/stc.bd'; }
      emit(){ printf 'EMIT %s\n' \"\$1\"; }
      stale_signature_check" 2>&1
    cp "$keep" "$work/gov.sh"
  }
  mkstc; out="$(stc_run "$work/gov.sh" 0)"
  if grep -q ' update fortkit-stc --add-label mayor-review --assignee emrith' "$work/stc.bd" 2>/dev/null \
     && grep -q ' comment fortkit-stc --file .*stale-signature-fortkit-stc.txt' "$work/stc.bd" \
     && grep -q 'conflicts on: conf-8gmt4.txt' "$work/state/logs/stale-signature-fortkit-stc.txt" 2>/dev/null \
     && grep -q '^EMIT fleet.stale-signature' <<<"$out" && [ -s "$work/state/workers/stc/stale-merge" ]; then
    ok "8gmt4: the held bead whose branch stopped merging gets mayor-review, the Mayor as assignee, and one comment naming conf-8gmt4.txt"
  else no "8gmt4: held + conflicting is handed to the Mayor" "bd: $(tr '\n' '|' < "$work/stc.bd" 2>/dev/null) out: $(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"; fi
  if ! grep -qE 'fortkit-(stk|sta)' "$work/stc.bd" 2>/dev/null; then
    ok "8gmt4: a held bead that still merges, and a conflicting bead that is not held (APPROVE), are left alone"
  else no "8gmt4: only held + conflicting is touched" "bd: $(tr '\n' '|' < "$work/stc.bd")"; fi
  rm -f "$work/stc.bd"; stc_run "$work/gov.sh" 0 >/dev/null
  if [ ! -s "$work/stc.bd" ]; then ok "8gmt4: the next pass on the same conflict is silent (no second label write, no second comment)"
  else no "8gmt4: dedupe" "second pass wrote: $(tr '\n' '|' < "$work/stc.bd")"; fi
  mkstc; out="$(stc_run "$work/gov.sh" 1)"
  if [ ! -s "$work/stc.bd" ] && grep -q 'DRY-RUN would hand fortkit-stc to the Mayor' <<<"$out" && [ ! -e "$work/state/workers/stc/stale-merge" ]; then
    ok "8gmt4: a dry run says what it would do and writes nothing"
  else no "8gmt4: dry run" "bd: $(tr '\n' '|' < "$work/stc.bd" 2>/dev/null) out: $(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"; fi
  # shellcheck disable=SC2016  # the literal launcher spelling is what is searched for
  if grep -A1 -x '  in_dispatch=1; dispatch_pass signed; in_dispatch=0' "$launcher" | grep -q . && awk '/^  in_dispatch=1; dispatch_pass signed; in_dispatch=0$/{f=1} f && /^  stale_signature_check/{print "found"; exit} f && /^  reap_pass$/{exit}' "$launcher" | grep -q found; then
    ok "8gmt4: the main loop asks it once per pass, after phase 1 and before the completion lane"
  else no "8gmt4: main-loop call" "stale_signature_check is not called between dispatch_pass signed and reap_pass"; fi
  # RED arms, generated: (a) the fingerprint check removed -> the second pass
  # comments again; (b) the held-verdict filter removed -> sta is handed over too.
  gv_nofp="$work/gov-8gmt4-nofp.sh"; gv_nohold="$work/gov-8gmt4-nohold.sh"
  # shellcheck disable=SC2016  # sed PATTERNS naming the launcher's own text, literally
  sed '/^    \[ "\$fp" = "\$old" \] && continue$/d' "$work/gov.sh" > "$gv_nofp"
  # shellcheck disable=SC2016  # a sed PATTERN naming the launcher's own text, literally
  sed '/^    stored_verdict_is_signable "\$(cat "\$vf" 2>\/dev\/null)" || continue$/d' "$work/gov.sh" > "$gv_nohold"
  if cmp -s "$gv_nofp" "$work/gov.sh" || cmp -s "$gv_nohold" "$work/gov.sh"; then
    no "8gmt4 RED" "a variant could not be generated (sed matched nothing)"
  else
    mkstc; stc_run "$gv_nofp" 0 >/dev/null; rm -f "$work/stc.bd"; stc_run "$gv_nofp" 0 >/dev/null
    if grep -q ' comment fortkit-stc' "$work/stc.bd" 2>/dev/null; then ok "8gmt4 RED: without the fingerprint the same conflict is commented on every pass"
    else no "8gmt4 RED: no fingerprint" "the second pass was silent anyway; the dedupe case cannot discriminate"; fi
    mkstc; stc_run "$gv_nohold" 0 >/dev/null
    if grep -q ' update fortkit-sta --add-label mayor-review' "$work/stc.bd" 2>/dev/null; then ok "8gmt4 RED: without the held-verdict filter an APPROVE bead is handed to the Mayor too"
    else no "8gmt4 RED: no hold filter" "sta was not touched; the filter case cannot discriminate"; fi
  fi
fi

echo "RESULT $pass pass / $fail fail"
[ $fail -eq 0 ]
