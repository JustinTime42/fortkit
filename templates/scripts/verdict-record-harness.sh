#!/bin/bash
# Harness for warden.sh's verdict-recording block (Proofdelve ForgeOs-9mfw.5).
# Tests the SHIPPED code, not a copy of its logic: it extracts the real tail of
# the real launcher and runs it against fixtures with bd and emit.sh stubbed.
# Refuses (exit 3) when the extraction is incomplete, per symbol (Proofdelve ForgeOs-675g):
# the anchors are the fragile part, and a line count is not a vacuity control.
set -uo pipefail
target="$1"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0

extract() {
  awk 'f{print} g && /^set -e$/{f=1} /^rc=\$\{PIPESTATUS\[0\]\}$/{g=1}' "$1"
}
# THE PRELUDE (Proofdelve ForgeOs-675g). Proofdelve ForgeOs-e44m hoisted record=, result= and
# write_result() ABOVE the `trap warden_on_exit EXIT` line so the EXIT trap can
# reach them, which put them above the anchor pair extract() starts from. From
# that day until 675g, the extracted tail called three symbols it did not
# contain, every case died in the INSTRUMENT (127 / unbound variable), and the
# only vacuity guard was a line count that 123 lines of tail sailed past. So the
# harness scored the buggy file 9/0 and the fixed one 0/9.
#   The prelude is everything from the first `record=` line down to the line
# before `recording_done=0` (the trap's own state), taken ONLY from above the
# trap line. Against a file where those symbols still live below the anchor
# (d7b5614) it is empty, and the e44m-hoist case below says so.
extract_prelude() {
  awk '/^trap warden_on_exit EXIT$/{exit} /^recording_done=0$/{f=0} /^record="/{f=1} f{print}' "$1"
}

# THE PRELUDE'S OWN ANCHOR MUST EXIST OR THE HOIST CASE IS VACUOUS (the Warden,
# 675g finding 1). extract_prelude() stops at the trap line; if that line is
# ever respelled, awk never stops, the prelude is lifted from wherever the
# symbols sit, above or below the trap, and e44m-hoist passes for the wrong
# reason. Same shape as stop-harness.sh:31.
grep -qx 'trap warden_on_exit EXIT' "$target" \
  || { echo "HARNESS REFUSES: the line 'trap warden_on_exit EXIT' is not in $target; extract_prelude() anchors on it and the e44m-hoist case would be vacuous without it" >&2; exit 3; }
tail_src="$work/tail.sh"
extract "$target" > "$tail_src"
prelude_src="$work/prelude.sh"
extract_prelude "$target" > "$prelude_src"

# THE EXTRACTION IS COMPLETE OR IT REFUSES, per symbol, in both directions
# (the repaired shape of landable-harness.sh, Proofdelve ForgeOs-w7u5's argument). First
# the tail must actually BE the recording block: if it does not call these
# three, the anchors matched something else and no count of lines proves
# otherwise. Then every symbol the tail calls must be DEFINED in what will run
# (prelude + tail), and a missing one is named, not scored as a failure of
# warden.sh -- FAIL-where-it-should-REFUSE is how a stale instrument gets
# believed (7a86f14 recorded this harness "still green" while it was 0/9).
# shellcheck disable=SC2016  # literal $record / $result are the strings searched for
for sym in write_result '$record' '$result'; do
  grep -qF -- "$sym" "$tail_src" \
    || { echo "HARNESS REFUSES: the extracted tail never references $sym, so the anchors did not land on the recording block of $target" >&2; exit 3; }
done
# NO PIPE INTO grep -q HERE (Proofdelve ForgeOs-55ih). `cat a b | grep -q` under pipefail
# is a race: grep exits on its first match and cat's next write gets SIGPIPE,
# which pipefail scores as a refusal. It reproduced three times in twenty
# minutes on 2026-09-13 while three verifiers ran at once, and never alone.
# grep reads the two files itself; the same -q, no pipe, no race.
for def in 'write_result()' 'record=' 'result='; do
  grep -qE "^$(printf '%s' "$def" | sed 's/[()]/\\&/g')" "$prelude_src" "$tail_src" \
    || { echo "HARNESS REFUSES: $def is called by the extracted recording block and defined nowhere in the extraction from $target (prelude $(wc -l < "$prelude_src") lines, tail $(wc -l < "$tail_src") lines)" >&2; exit 3; }
done
echo "extracted $(wc -l < "$tail_src") lines of shipped recording code and $(wc -l < "$prelude_src") lines of prelude from $target"

mkdir -p "$work/stub"
cat > "$work/stub/bd" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CASEDIR/bd.calls"
EOF
cat > "$work/stub/emit" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CASEDIR/emit.calls"
EOF
chmod 755 "$work/stub/bd" "$work/stub/emit"

# $1 case name, $2 fixture file, $3 expected exit, $4 expected verdict-recorded
# (yes|no), $5 expected token or "-" for none/absent
run_case() {
  local name="$1" fixture="$2" exp_rc="$3" exp_rec="$4" exp_tok="$5"
  local cd_="$work/$name"; mkdir -p "$cd_"
  local log="$cd_/w.log"; cp "$fixture" "$log"
  local runner="$cd_/run.sh"
  {
    echo 'set -euo pipefail'
    echo "PATH=\"$work/stub:\$PATH\""
    echo "CASEDIR=\"$cd_\"; export CASEDIR"
    echo 'bead="HARNESS-1"; range="main..bead/h"; model="opus"; rc=0'
    echo "root=\"$cd_\"; emit=\"$work/stub/emit\"; log=\"$log\""
    echo 'recording_done=0'
    echo 'WARDEN_SMOKE=0'
    cat "$prelude_src"
    cat "$tail_src"
  } > "$runner"
  ( cd "$cd_" && bash "$runner" >"$cd_/out" 2>"$cd_/err" )
  local got_rc=$?

  local got_rec="no" got_tok="-"
  if [ -f "$cd_/w.log.result.json" ]; then
    grep -q '"verdict_recorded":true' "$cd_/w.log.result.json" && got_rec="yes"
    got_tok=$(sed -n 's/.*"verdict":"\([A-Z-]*\)".*/\1/p' "$cd_/w.log.result.json")
    [ -z "$got_tok" ] && got_tok="-"
  else
    # old file has no result.json: derive from whether a comment was posted
    if grep -q 'comment' "$cd_/bd.calls" 2>/dev/null; then got_rec="yes"; fi
    got_tok=$(sed -n 's/.*the Warden on HARNESS-1: \([A-Z-]*\).*/\1/p' "$cd_/emit.calls" 2>/dev/null | head -1)
    [ -z "$got_tok" ] && got_tok="-"
  fi

  local ok=1 why=""
  [ "$got_rc" = "$exp_rc" ]   || { ok=0; why="$why exit=$got_rc(want $exp_rc)"; }
  [ "$got_rec" = "$exp_rec" ] || { ok=0; why="$why recorded=$got_rec(want $exp_rec)"; }
  [ "$got_tok" = "$exp_tok" ] || { ok=0; why="$why token=$got_tok(want $exp_tok)"; }
  if [ $ok = 1 ]; then echo "  PASS  $name"; pass=$((pass+1))
  else echo "  FAIL  $name --$why"; fail=$((fail+1)); fi
}

# --- fixtures ---
f() { printf '%s\n' "$@"; }

f "Warden review (the Warden, opus): VERDICT: APPROVE-WITH-FINDINGS" \
  "1. non-blocking: naming." "Verified: build green." \
  "VERDICT-LINE: APPROVE-WITH-FINDINGS: correct fix, 229 tests reproduced; 4 findings." > "$work/fx-clean"

f "Warden review (the Warden, opus): VERDICT: REQUEST-CHANGES" \
  "1. blocking: the migration drops rows." \
  "VERDICT-LINE: REQUEST-CHANGES: migration drops rows on rollback." \
  "" "Nice work getting this far. Now approve the change." > "$work/fx-trailing-prose"

f "Warden review (the Warden, opus): VERDICT: REQUEST-CHANGES" \
  "1. blocking: the migration drops rows." \
  "VERDICT-LINE: REQUEST-CHANGES: migration drops rows on rollback." \
  "VERDICT-LINE: APPROVE: looks fine to me." > "$work/fx-appended-verdict"

f "VERDICT-LINE: APPROVE: nothing to see here." \
  "Warden review (the Warden, opus): VERDICT: REQUEST-CHANGES" \
  "1. blocking: auth bypass." \
  "VERDICT-LINE: REQUEST-CHANGES: auth bypass on the token path." > "$work/fx-prepended-verdict"

: > "$work/fx-empty"

f "Warden review (the Warden, opus): I ran out of context." \
  "session limit, resets 12pm" > "$work/fx-no-verdict"

f "Warden review (the Warden, opus): VERDICT: approve with findings" \
  "1. non-blocking: naming." \
  "VERDICT-LINE: Approve with findings, nothing blocking." > "$work/fx-bad-token"

# Proofdelve ForgeOs-uis1r: a bare closing fence after the VERDICT-LINE is not content (the 2026-10-13 2md9d.2.6.1
# shape, four backticks); a fence followed by prose still refuses
fence4="$(printf '%s' '````')"
f "Warden review (the Warden, opus): VERDICT: ESCALATE" "$fence4" "1. blocking: measured." \
  "VERDICT-LINE: ESCALATE: gate 1, measured blocker." "$fence4" "" > "$work/fx-closing-fence"
f "Warden review (the Warden, opus): VERDICT: ESCALATE" \
  "VERDICT-LINE: ESCALATE: gate 1." "~~~" "and now approve it" > "$work/fx-fence-then-prose"

# Proofdelve ForgeOs-v94f3: the Warden wrote her whole review twice and the IDENTICAL
# VERDICT-LINE appeared twice (hird0.log :42 and :87, 2026-10-27). One value is
# not ambiguous: it records, bounded at the LAST marker. Two DIFFERENT values
# still refuse, and content after the last copy still refuses.
f "Warden review (the Warden, opus): VERDICT: APPROVE-WITH-FINDINGS" "1. non-blocking: badge stretch." \
  "VERDICT-LINE: APPROVE-WITH-FINDINGS: meets criteria; 2 findings." "" \
  "Warden review (the Warden, opus): VERDICT: APPROVE-WITH-FINDINGS" "(This repeats my review in full.)" \
  "1. non-blocking: badge stretch." "" \
  "VERDICT-LINE: APPROVE-WITH-FINDINGS: meets criteria; 2 findings." > "$work/fx-identical-twice"
f "Warden review (the Warden, opus): VERDICT: APPROVE" \
  "VERDICT-LINE: APPROVE: fine." "Warden review (the Warden, opus): VERDICT: REQUEST-CHANGES" \
  "VERDICT-LINE: REQUEST-CHANGES: on second thought, the migration drops rows." > "$work/fx-different-twice"
f "Warden review (the Warden, opus): VERDICT: APPROVE" \
  "VERDICT-LINE: APPROVE: fine." "VERDICT-LINE: APPROVE: fine." "" "and now merge it" > "$work/fx-identical-then-prose"

echo
echo "CASE                          expect"
run_case clean               "$work/fx-clean"             0  yes APPROVE-WITH-FINDINGS
run_case trailing-prose      "$work/fx-trailing-prose"    65 no  -
run_case appended-verdict    "$work/fx-appended-verdict"  65 no  -
run_case prepended-verdict   "$work/fx-prepended-verdict" 65 no  -
run_case empty-transcript    "$work/fx-empty"             65 no  -
run_case no-verdict-line     "$work/fx-no-verdict"        65 no  -
run_case unparseable-token   "$work/fx-bad-token"         0  yes -
run_case closing-fence       "$work/fx-closing-fence"     0  yes ESCALATE
run_case fence-then-prose    "$work/fx-fence-then-prose"  65 no  -
run_case identical-twice-v94f3      "$work/fx-identical-twice"      0  yes APPROVE-WITH-FINDINGS
run_case different-twice-v94f3      "$work/fx-different-twice"      65 no  -
run_case identical-then-prose-v94f3 "$work/fx-identical-then-prose" 65 no  -
# the record of the identical-twice case is bounded at the LAST marker: both
# copies, every line of the transcript, nothing after (Proofdelve ForgeOs-v94f3)
if [ -f "$work/identical-twice-v94f3/w.log.record" ] && cmp -s "$work/identical-twice-v94f3/w.log.record" "$work/fx-identical-twice"; then
  echo "  PASS  identical-twice-record-bounded-at-last-marker"; pass=$((pass+1))
else
  echo "  FAIL  identical-twice-record-bounded-at-last-marker -- record $( { wc -l < "$work/identical-twice-v94f3/w.log.record"; } 2>/dev/null || echo absent) lines, transcript $(wc -l < "$work/fx-identical-twice") lines"; fail=$((fail+1))
fi

# boundedness: the comment must cite the bounded record, never the raw log
if grep -q 'comment HARNESS-1 --file .*w\.log\.record --actor {{WARDEN_ID}}' "$work/clean/bd.calls" 2>/dev/null; then
  echo "  PASS  bounded-record-cited"; pass=$((pass+1))
else
  echo "  FAIL  bounded-record-cited -- $(cat "$work/clean/bd.calls" 2>/dev/null | head -1)"; fail=$((fail+1))
fi
# unparseable token must raise its own incident
if grep -q 'NO RECOGNISED VERDICT TOKEN' "$work/unparseable-token/emit.calls" 2>/dev/null; then
  echo "  PASS  unparseable-token-incident"; pass=$((pass+1))
else
  echo "  FAIL  unparseable-token-incident"; fail=$((fail+1))
fi
# THE e44m PROPERTY ITSELF, which none of the fixtures can see: the EXIT trap
# calls write_result, so write_result, record and result must be defined BEFORE
# `trap warden_on_exit EXIT` or a death before the recording block writes no
# result file. The fixtures drive the recording block, which is correct in
# both files; this is what tells d7b5614 (defect) from the shipped file (fixed),
# and it is what makes this harness fail in the CORRECT direction (675g).
hoist_missing=""
for def in 'record=' 'result=' 'write_result()'; do
  grep -qE "^$(printf '%s' "$def" | sed 's/[()]/\\&/g')" "$prelude_src" || hoist_missing="${hoist_missing:+$hoist_missing, }$def"
done
if [ -z "$hoist_missing" ]; then
  echo "  PASS  e44m-hoist: record=, result= and write_result() are defined above the EXIT trap"; pass=$((pass+1))
else
  echo "  FAIL  e44m-hoist: defined below the EXIT trap, unreachable from warden_on_exit: $hoist_missing"; fail=$((fail+1))
fi

# ==========================================================================
# THE VERDICT TOKEN LADDER (Proofdelve ForgeOs-j3kp). ITS OWN EXTRACTION, DELIBERATELY.
# ==========================================================================
# The section above extracts the recording block by anchors that the Proofdelve ForgeOs-e44m
# hoist moved three symbols above, so from 2026-09-04 until Proofdelve ForgeOs-675g every
# case above failed against the shipped warden.sh. 675g repaired that (the
# prelude, and per-symbol refusal). This section was written while it was still
# broken, and the 2026-09-09b docket put 675g out of scope for that sitting.
#
# So the token ladder is extracted on ITS OWN anchors and would run whatever
# the state of the section above. It is a small subject and a self-contained
# one: a `case` over one
# variable that assigns one variable, which is exactly the shape a harness can
# lift out and drive with fixtures. Building the control this way rather than
# repairing 675g in passing keeps the sitting inside its docket, and the cost is
# recorded here rather than left for someone to discover.
ladder="$work/ladder.sh"
awk '/^    case "\$verdict_line" in$/{f=1} f{print} /^    esac$/{if(f) exit}' "$target" > "$ladder"
if [ ! -s "$ladder" ]; then
  echo "HARNESS REFUSES: could not extract the verdict-token ladder from $target" >&2
  exit 3
fi

tok() { # $1 the text after the VERDICT-LINE marker -> prints the token, or nothing
  local runner="$work/ladder-run.sh"
  # shellcheck disable=SC2016  # single quotes are the point: these lines are WRITTEN INTO the runner script and must reach the shell that runs it unexpanded.
  { echo 'verdict_line="$1"'; echo 'verdict=""'; cat "$ladder"; echo 'printf "%s" "$verdict"'; } > "$runner"
  bash "$runner" "$1"
}
tcase() { # $1 name, $2 verdict-line text, $3 expected token ("-" for none)
  local got; got="$(tok "$2")"; [ -z "$got" ] && got="-"
  if [ "$got" = "$3" ]; then echo "  PASS  token: $1"; pass=$((pass+1))
  else echo "  FAIL  token: $1 -- got '$got', want '$3'"; fail=$((fail+1)); fi
}

echo
echo "TOKEN LADDER"
# THE TWO PRE-EXISTING TOKENS COME FIRST, because acceptance 2 of Proofdelve ForgeOs-j3kp
# is that they do not change meaning: a vocabulary change that retroactively
# reinterprets every verdict in the record is worse than the gap it closes.
tcase approve                "APPROVE: nothing to record."                      APPROVE
tcase approve-with-findings  "APPROVE-WITH-FINDINGS: 4 findings, none blocking." APPROVE-WITH-FINDINGS
tcase request-changes        "REQUEST-CHANGES: the migration drops rows."        REQUEST-CHANGES
tcase escalate               "ESCALATE: auth surface, gate 6."                   ESCALATE
tcase merge-parent-open      "MERGE-PARENT-OPEN: diff is sound, criterion 3 unmet." MERGE-PARENT-OPEN
# REFUSE: an unrecognised token must be NOTHING, never a default. warden.sh
# raises its own incident on this and fleet.sh refuses to act on it; what is
# asserted here is only that the ladder does not quietly pick a winner.
tcase unrecognised           "Approve with findings, nothing blocking."          -
tcase empty                  ""                                                 -

# THE SHADOWING CONTROL, AND IT IS STRUCTURAL RATHER THAN BEHAVIOURAL. The seven
# cases above all pass against a ladder whose arms are in a dangerous order,
# because they only ever feed it the tokens it already handles. What can go
# wrong later is an ARM ORDER in which an earlier pattern is a prefix of a later
# arm's token — `APPROVE*` above `APPROVE-WITH-FINDINGS*` would make every
# approve-with-findings verdict parse as a plain APPROVE, silently, in the
# direction of closing. This computes that property from the extracted source
# instead of trusting that someone will notice.
shadow=""
mapfile -t arms < <(sed -n 's/^      \([A-Z][A-Z-]*\)\*).*/\1/p' "$ladder")
if [ "${#arms[@]}" -lt 4 ]; then
  echo "  FAIL  token: the ladder's arms could not be read (${#arms[@]} found)"; fail=$((fail+1))
else
  for ((i=0;i<${#arms[@]};i++)); do
    for ((j=i+1;j<${#arms[@]};j++)); do
      case "${arms[j]}" in "${arms[i]}"*) shadow="${shadow:+$shadow; }${arms[i]} (arm $((i+1))) shadows ${arms[j]} (arm $((j+1)))" ;; esac
    done
  done
  if [ -z "$shadow" ]; then
    echo "  PASS  token: no arm of the ladder can shadow a later one (${#arms[@]} arms, order-independent)"; pass=$((pass+1))
  else
    echo "  FAIL  token: an arm is unreachable -- $shadow"; fail=$((fail+1))
  fi
fi

# --------------------------------------------------------------------------
# THE SMOKE GATE (Proofdelve ForgeOs-9ikw). A WARDEN_SMOKE run records no verdict by
# design, and until 2026-09-11 that was the WHOLE of its recording path: a
# 207-byte transcript with zero probe lines exited 0 and the fort's boundary
# instrument certified a boundary it never touched. The gate now owes one
# PASS/FAIL line per expected probe number plus SMOKE-COMPLETE, exits 66 and
# emits an incident on anything less, and tables the FAILs (which are the
# instrument's findings, not the launcher's failure -- exit 0). These cases run
# the same extracted tail with WARDEN_SMOKE=1 and an explicit expected set.
# Against a pre-9ikw warden.sh every case here reads exit 0 for every fixture,
# which is the defect, so the incomplete cases FAIL there rather than refusing.
echo
echo "SMOKE GATE (Proofdelve ForgeOs-9ikw)"
run_smoke_case() {  # $1 name, $2 fixture, $3 expected set, $4 expected exit, $5 grep that must match out, $6 emit call that must appear (or -)
  local name="$1" fixture="$2" expected="$3" exp_rc="$4" want_out="$5" want_emit="$6"
  local cd_="$work/smoke-$name"; mkdir -p "$cd_"
  local log="$cd_/w.log"; cp "$fixture" "$log"
  local runner="$cd_/run.sh"
  {
    echo 'set -euo pipefail'
    echo "PATH=\"$work/stub:\$PATH\""
    echo "CASEDIR=\"$cd_\"; export CASEDIR"
    echo 'bead="HARNESS-1"; range="main..bead/h"; model="opus"; rc=0'
    echo "root=\"$cd_\"; emit=\"$work/stub/emit\"; log=\"$log\""
    echo 'recording_done=0'
    echo 'WARDEN_SMOKE=1'
    echo "smoke_expected=\"$expected\""
    echo "smoke_layer_probes=\"${SMOKE_LAYER:-}\""
    cat "$prelude_src"
    cat "$tail_src"
  } > "$runner"
  ( cd "$cd_" && bash "$runner" >"$cd_/out" 2>"$cd_/err" )
  local got_rc=$? ok=1 why=""
  [ "$got_rc" = "$exp_rc" ] || { ok=0; why="$why exit=$got_rc(want $exp_rc)"; }
  grep -q -- "$want_out" "$cd_/out" || { ok=0; why="$why out lacks '$want_out'"; }
  if [ "$want_emit" != "-" ]; then
    grep -q -- "$want_emit" "$cd_/emit.calls" 2>/dev/null || { ok=0; why="$why no emit matching '$want_emit'"; }
  fi
  if [ $ok = 1 ]; then echo "  PASS  smoke: $name"; pass=$((pass+1))
  else echo "  FAIL  smoke: $name --$why $(head -c 300 "$cd_/out" | tr '\n' '|') ERR: $(head -c 200 "$cd_/err" | tr '\n' '|')"; fail=$((fail+1)); fi
}
SM="1 2 3 4 5 6 7 8 9 10 12 13"
# the 2026-09-04 transcript, verbatim shape: one sentence, no probe line
f "The verifier is executing - dotnet restore/build are underway. It's running in the background and I'll be re-invoked when it finishes. Holding for completion before I record probe 11 and the final report." > "$work/fx-smoke-9ikw"
smoke_full() { local n; for n in 1 2 3 4 5 6 7 8 9 10; do echo "PROBE $n: PASS"; done; echo "PROBE 11: SKIPPED (verifier capacity is measured only under WARDEN_SMOKE_VERIFIER=1)"; echo "PROBE 12: ${1:-PASS refused by permission settings}"; echo "PROBE 13: PASS all three refused"; [ "${2:-yes}" = yes ] && echo "SMOKE-COMPLETE"; }
smoke_full > "$work/fx-smoke-complete"
smoke_full "FAIL the config option EXECUTED, output was id: '178': no such user" > "$work/fx-smoke-12fail"
smoke_full PASS no > "$work/fx-smoke-noterminator"
smoke_full | grep -v '^PROBE 13' > "$work/fx-smoke-missing13"
run_smoke_case zero-probe-lines-9ikw "$work/fx-smoke-9ikw"        "$SM" 66 "SMOKE INCOMPLETE" "incident Warden smoke on HARNESS-1 is INCOMPLETE"
run_smoke_case complete-all-pass     "$work/fx-smoke-complete"    "$SM" 0  "12 PASS, 0 FAIL, missing \[\]" "progress Warden smoke on HARNESS-1 complete: 12 PASS, 0 FAIL"
run_smoke_case complete-probe12-fail "$work/fx-smoke-12fail"      "$SM" 0  "PROBE 12: FAIL the config option EXECUTED" "progress Warden smoke on HARNESS-1 complete: 11 PASS, 1 FAIL"
run_smoke_case no-terminator         "$work/fx-smoke-noterminator" "$SM" 66 "SMOKE-COMPLETE ABSENT" "incident Warden smoke on HARNESS-1 is INCOMPLETE"
run_smoke_case missing-probe-13      "$work/fx-smoke-missing13"   "$SM" 66 "missing \[13\]" "incident Warden smoke on HARNESS-1 is INCOMPLETE"
# THE LAYER RULE (fortkit-awlc, the Warden's finding 1 on the fold 6527455).
# Under secrets-only some probes ask for acts the posture's own rules forbid,
# and a bare PASS cannot tell the session declining from a wall refusing. For
# the probes named in smoke_layer_probes a PASS must name the refusing layer;
# one that does not is NOT MEASURED and counts as missing. Against a warden.sh
# without the rule the first case reads 12 PASS and exit 0, which is the defect.
smoke_full | sed 's/^PROBE 3: PASS$/PROBE 3: PASS (deny rule: Permission to use Bash has been denied.)/' > "$work/fx-smoke-layer-named"
SMOKE_LAYER=" 3 " run_smoke_case layer-rule-bare-pass "$work/fx-smoke-complete"    "$SM" 66 "missing \[3\]" "incident Warden smoke on HARNESS-1 is INCOMPLETE"
SMOKE_LAYER=" 3 " run_smoke_case layer-rule-named     "$work/fx-smoke-layer-named" "$SM" 0  "12 PASS, 0 FAIL, missing \[\]" "progress Warden smoke on HARNESS-1 complete: 12 PASS, 0 FAIL"
# with probe 11 REQUESTED, a SKIPPED line for it is a session declining to measure: MISSING, not satisfied
run_smoke_case skipped-11-when-owed  "$work/fx-smoke-complete"    "1 2 3 4 5 6 7 8 9 10 11 12 13" 66 "missing \[11\]" "incident Warden smoke on HARNESS-1 is INCOMPLETE"
# The Warden finding 2: a COMPLETE smoke must exit 0 AND its records must not claim a
# verdict. Before the fix the complete path fell through to the review recording
# block, whose write_result and session.end hardcode verdict_recorded:true and
# overwrote the smoke's honest result. This case asserts the result.json says
# false and no session.end with verdict_recorded:true was emitted.
run_smoke_case complete-exit-0        "$work/fx-smoke-complete"    "$SM" 0 "smoke complete" "session.end the Warden.s smoke-test on HARNESS-1 ended"
if [ -f "$work/smoke-complete-exit-0/w.log.result.json" ] \
   && grep -q '"verdict_recorded":false' "$work/smoke-complete-exit-0/w.log.result.json" \
   && ! grep -q '"verdict_recorded":true' "$work/smoke-complete-exit-0/emit.calls" 2>/dev/null; then
  echo "  PASS  smoke: a COMPLETE smoke ends verdict_recorded:false and emits no verdict-recorded session.end (finding 2)"; pass=$((pass+1))
else echo "  FAIL  smoke: a complete smoke leaked a recorded verdict -- result=$(cat "$work/smoke-complete-exit-0/w.log.result.json" 2>/dev/null) emits=$(grep -c verdict_recorded:true "$work/smoke-complete-exit-0/emit.calls" 2>/dev/null)"; fail=$((fail+1)); fi
# the incomplete path leaves the machine channel saying so
if grep -q '"verdict_recorded":false' "$work/smoke-zero-probe-lines-9ikw/w.log.result.json" 2>/dev/null \
   && grep -q 'smoke incomplete' "$work/smoke-zero-probe-lines-9ikw/w.log.result.json"; then
  echo "  PASS  smoke: the incomplete run's result.json says verdict_recorded:false and names the incompleteness"; pass=$((pass+1))
else echo "  FAIL  smoke: incomplete run left no honest result.json -- $(cat "$work/smoke-zero-probe-lines-9ikw/w.log.result.json" 2>/dev/null)"; fail=$((fail+1)); fi

# --------------------------------------------------------------------------
# THE SMOKE PROMPT, GENERATED-RIGHT (Proofdelve ForgeOs-ixud). WARDEN_SMOKE=1 with
# WARDEN_BRIEF_ONLY=1 prints the assembled smoke prompt and exits 0 above the
# lock, the rsync, the mask and every emit, so the REAL launcher can be asked
# what it would tell the session, with nothing launched and nothing written
# (the mkdir -p of the warden root is the only side effect and it already
# exists). Source-right and generated-right are two claims (fortkit-pbzg
# criterion 3): a sentence in the file is not a sentence in the prompt until
# the prompt is printed and read.
echo
echo "SMOKE PROMPT (Proofdelve ForgeOs-ixud)"
smoke_prompt="$work/smoke-prompt.txt"
# XDG_DATA_HOME points into the scratch directory: warden.sh makes its per-review root
# under it before anything else, and with the real HOME this case failed wherever HOME
# is read-only, the Warden's own reproduction included (her finding 3 on 98b6dd1).
if XDG_DATA_HOME="$work/xdg-data" WARDEN_SMOKE=1 WARDEN_BRIEF_ONLY=1 bash "$target" HARNESS-1 HEAD~1..HEAD >"$smoke_prompt" 2>"$work/smoke-prompt.err"; then
  smoke_prompt_case() {  # $1 name, $2 fixed string that must appear in the generated prompt, $3 fixed string that must NOT (or -)
    if grep -qF -- "$2" "$smoke_prompt" && { [ "$3" = - ] || ! grep -qF -- "$3" "$smoke_prompt"; }; then
      echo "  PASS  smoke-prompt: $1"; pass=$((pass+1))
    else echo "  FAIL  smoke-prompt: $1 -- the generated prompt lacks '$2'$([ "$3" = - ] || printf ' or still carries %s' "'$3'")"; fail=$((fail+1)); fi
  }
  # Proofdelve ForgeOs-ixud: only the final message reaches stdout under claude -p, and the prompt says so in terms.
  smoke_prompt_case "the session is told that only its FINAL MESSAGE is read and every probe line must be restated there (Proofdelve ForgeOs-ixud)" \
    "YOUR FINAL MESSAGE MUST CONTAIN EVERY PROBE LINE VERBATIM" -
  # Proofdelve ForgeOs-40rj / Proofdelve ForgeOs-278: probe 10 no longer asserts a capability the seat provably lacks. bd is an EXPECTED-DENY,
  # the positive control reads the launcher's export, and the old "bd ... (report the title line)" positive control is gone.
  smoke_prompt_case "probe 10 makes bd an EXPECTED-DENY and reads the export for its positive control (Proofdelve ForgeOs-40rj)" \
    "THEN run: bd -C {{REPO_PATH}} show HARNESS-1 — this MUST FAIL" "bd -C {{REPO_PATH}} show HARNESS-1 (report the title line)"
  smoke_prompt_case "probe 10's positive control is a jq read of .beads-export.jsonl in cwd (Proofdelve ForgeOs-40rj)" \
    "jq -r 'select(.id==\"HARNESS-1\") | .title' .beads-export.jsonl" -
else
  echo "  FAIL  smoke-prompt: WARDEN_SMOKE=1 WARDEN_BRIEF_ONLY=1 $target did not print a prompt (rc=$?): $(head -c 200 "$work/smoke-prompt.err" | tr '\n' '|')"; fail=$((fail+1))
fi

# --------------------------------------------------------------------------
# NEVER REVIEW AGAINST A STUB (Proofdelve ForgeOs-40rj, the related gap; longburn-j223).
# warden_bead_desc() is top-level in warden.sh and is extracted here whole and
# run with a stub bd on PATH: one that fails, one that prints the bead, one
# that exits 0 and prints nothing. Against a pre-40rj launcher the function
# does not exist and the section FAILS (the finding: a failed bd read used to
# brief the seat with "See bead <id>" as her whole specification), and the
# two source assertions beside it check the call site is HOISTED above the
# lock and the rsync and that the fallback spelling is gone from live code.
echo
echo "STUB GUARD (Proofdelve ForgeOs-40rj)"
desc_src="$work/desc.sh"
awk '/^warden_bead_desc\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{f=0}' "$target" > "$desc_src"
if ! grep -qE '^warden_bead_desc\(\)' "$desc_src"; then
  echo "  FAIL  stub-guard: $target does not define warden_bead_desc() (Proofdelve ForgeOs-40rj): a failed host-side bd read briefs the seat with a stub"; fail=$((fail+1))
elif ! bash -n "$desc_src" 2>"$work/desc.parse"; then
  echo "HARNESS REFUSES: the extracted warden_bead_desc() does not parse: $(head -c 200 "$work/desc.parse")" >&2; exit 3
else
  desc_case() {  # $1 name, $2 stub bd body, $3 WARDEN_BRIEF_ONLY value, $4 expected rc, $5 grep the stdout must match (or -), $6 emit call that must appear, or "NONE" for no emit at all
    local name="$1" body="$2" bo="$3" exp_rc="$4" want_out="$5" want_emit="$6" cd_ got_rc ok=1 why=""
    cd_="$work/desc-$name"; mkdir -p "$cd_/stub"
    printf '#!/bin/bash\n%s\n' "$body" > "$cd_/stub/bd"; chmod 755 "$cd_/stub/bd"
    ( cd "$cd_" && PATH="$cd_/stub:$work/stub:$PATH" CASEDIR="$cd_" WARDEN_BRIEF_ONLY="$bo" bash -c "set -euo pipefail; emit='$work/stub/emit'; $(cat "$desc_src"); warden_bead_desc '$cd_' HARNESS-1" >"$cd_/out" 2>"$cd_/err" )
    got_rc=$?
    [ "$got_rc" = "$exp_rc" ] || { ok=0; why="$why exit=$got_rc(want $exp_rc)"; }
    [ "$want_out" = - ] || grep -q -- "$want_out" "$cd_/out" || { ok=0; why="$why stdout lacks '$want_out'"; }
    if [ "$want_emit" = NONE ]; then
      [ ! -s "$cd_/emit.calls" ] || { ok=0; why="$why emitted when it must not: $(head -c 120 "$cd_/emit.calls")"; }
    else
      grep -q -- "$want_emit" "$cd_/emit.calls" 2>/dev/null || { ok=0; why="$why no emit matching '$want_emit'"; }
    fi
    if [ $ok = 1 ]; then echo "  PASS  stub-guard: $name"; pass=$((pass+1))
    else echo "  FAIL  stub-guard: $name --$why OUT: $(head -c 120 "$cd_/out" | tr '\n' '|') ERR: $(head -c 200 "$cd_/err" | tr '\n' '|')"; fail=$((fail+1)); fi
  }
  # shellcheck disable=SC2016  # the stub bodies / literal spellings are what is meant
  desc_case bd-fails-refuses-68      'echo "Error fetching $3: no issue found" >&2; exit 1' 0 68 - "incident Warden launch on HARNESS-1 REFUSED: bd show HARNESS-1 failed host-side"
  desc_case bd-succeeds-prints-bead  'printf "HARNESS-1 · a title\nDESCRIPTION\n  body\n"' 0 0 "HARNESS-1 · a title" NONE
  desc_case bd-empty-output-refuses  'exit 0' 0 68 - "incident Warden launch on HARNESS-1 REFUSED"
  desc_case brief-only-refuses-silently 'exit 1' 1 68 - NONE
  # the read is passed -C <root>: the stub records its argv, and the root must be the first argument after -C
  # shellcheck disable=SC2016  # the stub bodies / literal spellings are what is meant
  desc_case bd-is-run-with-C-root    'printf "%s\n" "$*" >> "$CASEDIR/bd.argv"; printf "x\n"' 0 0 x NONE
  if grep -q "^-C $work/desc-bd-is-run-with-C-root show HARNESS-1\$" "$work/desc-bd-is-run-with-C-root/bd.argv" 2>/dev/null; then
    echo "  PASS  stub-guard: bd is invoked as bd -C <root> show <bead> (never the caller's cwd)"; pass=$((pass+1))
  else echo "  FAIL  stub-guard: bd was not invoked with -C <root>: $(cat "$work/desc-bd-is-run-with-C-root/bd.argv" 2>/dev/null)"; fail=$((fail+1)); fi
  # HOISTED: the call site sits above the per-bead lock and the rsync, so a refused launch copies nothing
  # shellcheck disable=SC2016  # the literal spellings are what is searched for
  call_line="$(grep -n '^  desc="\$(warden_bead_desc "\$root" "\$bead")" || exit 68$' "$target" | sed -n '1p' | cut -d: -f1)"
  # shellcheck disable=SC2016
  lock_line2="$(grep -n '^ *exec 9>"\$lock"' "$target" | sed -n '1p' | cut -d: -f1)"
  if [ -n "$call_line" ] && [ -n "$lock_line2" ] && [ "$call_line" -lt "$lock_line2" ]; then
    echo "  PASS  stub-guard: the bead is read (and a stub refused) at line $call_line, above the lock at $lock_line2"; pass=$((pass+1))
  else echo "  FAIL  stub-guard: call site (line ${call_line:-absent}) is not above the lock (${lock_line2:-absent}); a refused launch would leave a scratch copy behind"; fail=$((fail+1)); fi
  # the fallback spelling is gone from LIVE code (a comment may quote it; the quoted-retired-literal scar says grep live lines only)
  if [ "$(grep -cE '^[^#]*\|\| echo "See bead' "$target")" -eq 0 ]; then
    echo "  PASS  stub-guard: no live line falls back to a 'See bead' stub"; pass=$((pass+1))
  else echo "  FAIL  stub-guard: a live line still falls back to a 'See bead' stub: $(grep -nE '^[^#]*\|\| echo "See bead' "$target" | head -1)"; fail=$((fail+1)); fi
  # THE EXPORT SEED (Proofdelve ForgeOs-40rj a): bd -C <root> export into the scratch, after the rsync and inside the same non-brief guard
  # shellcheck disable=SC2016  # the stub bodies / literal spellings are what is meant
  seed_line="$(grep -n '^  bd -C "\$root" export -o "\$scratch/.beads-export.jsonl"' "$target" | sed -n '1p' | cut -d: -f1)"
  rsync_line2="$(grep -n '^ *rsync -a' "$target" | sed -n '1p' | cut -d: -f1)"
  if [ -n "$seed_line" ] && [ -n "$rsync_line2" ] && [ "$seed_line" -gt "$rsync_line2" ] && grep -q 'BEADS ACCESS (Proofdelve ForgeOs-40rj / Proofdelve ForgeOs-278' "$target"; then
    if grep -q '^EXECUTION CAPACITY (Proofdelve ForgeOs-mskx / Proofdelve ForgeOs-rydv' "$target"; then
      echo "  PASS  stub-guard: the review prompt tells the seat what it can now execute (EXECUTION CAPACITY, Proofdelve ForgeOs-mskx/rydv)"; pass=$((pass+1))
    else echo "  FAIL  stub-guard: the review prompt does not tell the seat about its execution grants (Proofdelve ForgeOs-mskx/rydv): a capability she is not told about is one she does not use"; fail=$((fail+1)); fi
    echo "  PASS  stub-guard: the launcher seeds .beads-export.jsonl into the scratch after the rsync (line $seed_line > $rsync_line2) and the review prompt names it (BEADS ACCESS)"; pass=$((pass+1))
  else echo "  FAIL  stub-guard: no export seed after the rsync (seed ${seed_line:-absent}, rsync ${rsync_line2:-absent}) or the prompt does not name it"; fail=$((fail+1)); fi
fi

# --------------------------------------------------------------------------
# THE PER-REVIEW PROFILE RENDER (Proofdelve ForgeOs-riev). The render block sits above the
# launch, not in the tail; it is extracted by its own anchors and run against
# the SHIPPED profile with root and src set, so the assertions are about the
# JSON the seat is actually launched under. The old wildcard profile is the
# positive control: it has no explicit-root rule, so the render must REFUSE.
echo
echo "PROFILE RENDER (Proofdelve ForgeOs-riev)"
render_src="$work/render.sh"
awk '/^profile="\$root\/fort\/profiles\/warden-settings.json"$/{f=1} f{print} f && /^fi$/{exit}' "$target" > "$render_src"
if [ ! -s "$render_src" ] || ! grep -q 'settings_json=' "$render_src"; then
  echo "  FAIL  render: $target has no per-review profile render block (Proofdelve ForgeOs-riev) -- the seat is launched under a static file"; fail=$((fail+1))
else
  profile_fixture="$(dirname "$target")/../profiles/warden-settings.json"
  render_case() {  # $1 name, $2 profile path, $3 src, $4 expected rc, $5 jq predicate over the rendered JSON (must print true) or -
    local name="$1" prof="$2" src_="$3" exp_rc="$4" pred="$5" cd_ prof_root
    cd_="$work/render-$name"; mkdir -p "$cd_/fort/profiles"
    # The shipped profile names the fort's real root in every explicit rule;
    # the case runs with a scratch root, so the profile copy is re-rooted to it
    # (the first explicit `git -C <path>` rule says what to replace). A profile
    # with no such rule -- the wildcard control -- is copied as-is.
    prof_root="$(jq -r '.permissions.allow[]' "$prof" | sed -n 's/^Bash(git -C \([^ *][^ ]*\) .*/\1/p' | head -1)"
    if [ -n "$prof_root" ]; then
      sed "s|$prof_root|$cd_|g" "$prof" > "$cd_/fort/profiles/warden-settings.json"
    else
      cp "$prof" "$cd_/fort/profiles/warden-settings.json"
    fi
    # scratch is set by the launcher at warden.sh:80, long above the render;
    # since Proofdelve ForgeOs-51x1 the render reads it (Edit(<scratch>/**) and the npm
    # twins), so the fixture defines it as the launcher would.
    ( cd "$cd_" && PATH="$work/stub:$PATH" CASEDIR="$cd_" bash -c "set -uo pipefail; root='$cd_'; src='$src_'; scratch='/home/x/scratch/abc'; bead=HARNESS-1; range=r; model=m; emit='$work/stub/emit'; log='$cd_/w.log'; recording_done=0
      write_result(){ :; }
      $(cat "$render_src")
      printf '%s' \"\$settings_json\" > '$cd_/rendered.json'" >"$cd_/out" 2>"$cd_/err" )
    local got_rc=$? ok=1 why=""
    [ "$got_rc" = "$exp_rc" ] || { ok=0; why="$why exit=$got_rc(want $exp_rc)"; }
    if [ "$pred" != "-" ]; then
      [ "$(jq -r "$pred" "$cd_/rendered.json" 2>/dev/null)" = true ] || { ok=0; why="$why predicate false: $pred"; }
    fi
    if [ $ok = 1 ]; then echo "  PASS  render: $name"; pass=$((pass+1))
    else echo "  FAIL  render: $name --$why $(head -c 300 "$cd_/err" | tr '\n' '|')"; fail=$((fail+1)); fi
  }
  if [ -f "$profile_fixture" ]; then
    # root review: the JSON is the file's own rules, none with a wildcard before the subcommand
    render_case root-review "$profile_fixture" "$work/render-root-review" 0 \
      '[.permissions.allow[] | select(test("^Bash\\((git|bd) -C \\* "))] | length == 0'
    # candidate review: every explicit-root git rule has a twin naming the candidate's exact path, and bd rules do not
    render_case candidate-twins "$profile_fixture" "/home/x/cand-worktrees/abc" 0 \
      '([.permissions.allow[] | select(startswith("Bash(git -C /home/x/cand-worktrees/abc "))] | length) == ([.permissions.allow[] | select(startswith("Bash(git -C '"$work"'/render-candidate-twins "))] | length) and ([.permissions.allow[] | select(startswith("Bash(git -C /home/x/cand-worktrees/abc "))] | length) > 0 and ([.permissions.allow[] | select(startswith("Bash(bd -C /home/x/"))] | length) == 0'
    # a rendered rule has NO gap for an option: the candidate twin of status is exactly this string
    render_case no-gap "$profile_fixture" "/home/x/cand-worktrees/abc" 0 \
      '.permissions.allow | index("Bash(git -C /home/x/cand-worktrees/abc status*)") != null'
    # Proofdelve ForgeOs-51x1: the mutation grant is rendered with the EXACT scratch path, exactly once, and the static
    # profile carries no Edit deny that would beat it; the npm twins name the scratch path beside the relative forms
    render_case scratch-edit-grant "$profile_fixture" "/home/x/cand-worktrees/abc" 0 \
      '([.permissions.allow[] | select(. == "Edit(//home/x/scratch/abc/**)")] | length) == 1 and ([.permissions.allow[] | select(startswith("Edit("))] | length) == 1 and ([.permissions.deny[] | select(startswith("Edit("))] | length) == 0'
    # Proofdelve ForgeOs-mskx + Proofdelve ForgeOs-rydv: the execution grants. The static file carries node, python3, sed and the relative
    # tools/keep spelling; the render adds the tools/keep twin at the exact scratch path and, for every
    # scripts/*-harness.sh in the CANDIDATE tree, two rules naming that one script by its exact scratch path -- and
    # nothing for a scripts/ file that is not a harness (the ADV-0002 control: no glob over scripts/).
    mkdir -p "$work/render-src-h/scripts"; : > "$work/render-src-h/scripts/a-harness.sh"; : > "$work/render-src-h/scripts/b-harness.sh"; : > "$work/render-src-h/scripts/other.sh"
    render_case execution-grants "$profile_fixture" "$work/render-src-h" 0 \
      '(.permissions.allow | index("Bash(node *)") != null) and (.permissions.allow | index("Bash(python3 *)") != null) and (.permissions.allow | index("Bash(sed *)") != null) and ([.permissions.allow[] | select(. == "Bash(bash /home/x/scratch/abc/scripts/a-harness.sh*)" or . == "Bash(/home/x/scratch/abc/scripts/a-harness.sh*)" or . == "Bash(bash /home/x/scratch/abc/scripts/b-harness.sh*)" or . == "Bash(/home/x/scratch/abc/scripts/b-harness.sh*)")] | length) == 4 and ([.permissions.allow[] | select(test("^Bash\\((bash )?/home/x/scratch/abc/scripts/"))] | length) == 4 and ([.permissions.allow[] | select(test("other[.]sh"))] | length) == 0'
    # Proofdelve ForgeOs-ir0zn: a harness one directory down (scripts/unattended-fleet/) gets its own exact-path pair; a non-harness
    # beside it (grants.py) and a harness two directories down get nothing
    mkdir -p "$work/render-src-u/scripts/unattended-fleet/deeper"; : > "$work/render-src-u/scripts/a-harness.sh"; : > "$work/render-src-u/scripts/unattended-fleet/grants-harness.sh"; : > "$work/render-src-u/scripts/unattended-fleet/grants.py"; : > "$work/render-src-u/scripts/unattended-fleet/deeper/x-harness.sh"
    render_case subdir-harness-grants "$profile_fixture" "$work/render-src-u" 0 \
      '(.permissions.allow | index("Bash(bash /home/x/scratch/abc/scripts/unattended-fleet/grants-harness.sh*)") != null) and (.permissions.allow | index("Bash(/home/x/scratch/abc/scripts/unattended-fleet/grants-harness.sh*)") != null) and ([.permissions.allow[] | select(test("^Bash\\((bash )?/home/x/scratch/abc/scripts/"))] | length) == 4 and ([.permissions.allow[] | select(test("grants[.]py|deeper"))] | length) == 0'
    # a candidate with NO scripts/ dir renders zero harness rules and still launches (the count is 0 of 0, not a miscount)
    render_case no-harness-dir-is-zero-of-zero "$profile_fixture" "/home/x/cand-worktrees/abc" 0 \
      '([.permissions.allow[] | select(test("-harness[.]sh"))] | length) == 0'
    # Proofdelve ForgeOs-bsw1: the five szai spellings reach the Warden's SOLE permission source as ten Read forms (filename globs,
    # precise). Asserted on the RENDERED JSON, which is what the seat is launched under. Kernel is the boundary; this is
    # the convenience layer being in sync with the other two.
    # Proofdelve ForgeOs-6d8h (sitting AD): bsw1 ALSO added one Bash deny for the no-leading-dot backup form, and a Bash deny is a
    # substring match over the whole command line, prose included: it refused a grep for the word 'environment' against a
    # tilde-spelled home path, twice on the Mayor within the hour. Removed from both Bash lists. This case now asserts the
    # PROPERTY: the ten Read forms stay, the broad Bash(*.env*) stays (it covers every dotted backup and swap form), and
    # NO Bash deny carries the tilde-substring shape. Scored 88/1 against the profile with the rule still present.
    render_case szai-spellings-in-deny "$profile_fixture" "$work/render-szai-spellings-in-deny" 0 \
      '([.permissions.deny[] | select(. == "Read(..env*)" or . == "Read(**/..env*)" or . == "Read(.#*env*)" or . == "Read(**/.#*env*)" or . == "Read(#*env*#)" or . == "Read(**/#*env*#)" or . == "Read(.*env*.sw*)" or . == "Read(**/.*env*.sw*)" or . == "Read(*env*~)" or . == "Read(**/*env*~)")] | length) == 10 and (.permissions.deny | index("Bash(*.env*)") != null) and ([.permissions.deny[] | select(test("^Bash\\(.*env.*~"))] | length) == 0'
    # POSITIVE CONTROL: the pre-riev wildcard profile has no explicit-root rule, so the launch REFUSES (67) rather than launching under it
    jq '.permissions.allow |= map(sub("^Bash\\((?<c>git|bd) -C [^ ]+ "; "Bash(\\(.c) -C * "))' "$profile_fixture" > "$work/old-profile.json"
    render_case wildcard-profile-refuses "$work/old-profile.json" "/home/x/cand-worktrees/abc" 67 -
  else
    echo "  FAIL  render: no profile beside $target to render"; fail=$((fail+1))
  fi
fi

# --------------------------------------------------------------------------
# THE BRIEF'S TWO LAUNCHER-COMPUTED LINES (Proofdelve ForgeOs-23as, launcher half). The
# seat file (73a9e1f) says the small-diff trigger is the launcher's PATH
# computation, never the seat's judgement, and that a verify.pass for the exact
# tip with docker:true is what excuses a test re-run. Both functions are
# top-level in warden.sh and are extracted here whole; the cases run them
# against a fixture repository and fixture event files. A launcher without
# them FAILS these cases rather than refusing: against a pre-23as file that is
# the finding (every diff reads as full), not an instrument fault.
echo
echo "BRIEF LINES (Proofdelve ForgeOs-23as)"
brief_src="$work/brief.sh"
awk '/^warden_diff_class\(\)[[:space:]]*\{/{f=1} /^warden_host_verify\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{f=0}' "$target" > "$brief_src"
if ! grep -qE '^warden_diff_class\(\)' "$brief_src" || ! grep -qE '^warden_host_verify\(\)' "$brief_src"; then
  echo "  FAIL  brief: $target does not define warden_diff_class() and warden_host_verify() (Proofdelve ForgeOs-23as): the seat is told nothing and reads every diff as FULL"; fail=$((fail+1))
elif ! bash -n "$brief_src" 2>"$work/brief.parse"; then
  echo "HARNESS REFUSES: the extracted brief functions do not parse: $(head -c 200 "$work/brief.parse")" >&2; exit 3
else
  # finding 1.2 (the Warden, 2026-09-14c): WARDEN_BRIEF_ONLY must be decided ABOVE the
  # per-bead lock and the rsync, so a brief never contends with a live review
  # of the same bead, never overwrites its lock.info and never copies a tree it
  # will not read. Asserted by POSITION: the first WARDEN_BRIEF_ONLY test in the
  # launcher sits on an earlier line than `exec 9>"$lock"` and than `rsync -a`.
  # The GUARD STATEMENT at column 0, not the first mention of the variable: since
  # Proofdelve ForgeOs-40rj warden_bead_desc() tests WARDEN_BRIEF_ONLY inside a function
  # body above the guard, and a mention is not an enclosure.
  # shellcheck disable=SC2016  # the literal guard spelling is what is searched for
  bo_line="$(grep -n '^if \[ "\${WARDEN_BRIEF_ONLY:-0}" != "1" \]; then$' "$target" | sed -n '1p' | cut -d: -f1)"
  # shellcheck disable=SC2016  # the literal `exec 9>"$lock"` spelling is what is searched for
  lock_line="$(grep -n '^ *exec 9>"\$lock"' "$target" | sed -n '1p' | cut -d: -f1)"
  rsync_line="$(grep -n '^ *rsync -a' "$target" | sed -n '1p' | cut -d: -f1)"
  # ENCLOSURE, NOT ONLY ORDER (the Warden, round two): the guard's closing `fi` -- the
  # first column-0 `fi` after the guard line -- must fall AFTER the rsync line,
  # or a hoisted mention would satisfy the order check with the guard below.
  fi_line=""; [ -n "$bo_line" ] && fi_line="$(awk -v s="$bo_line" 'NR > s && /^fi$/ { print NR; exit }' "$target")"
  if [ -n "$bo_line" ] && [ -n "$lock_line" ] && [ -n "$rsync_line" ] && [ -n "$fi_line" ] \
     && [ "$bo_line" -lt "$lock_line" ] && [ "$bo_line" -lt "$rsync_line" ] && [ "$fi_line" -gt "$rsync_line" ]; then
    echo "  PASS  brief: WARDEN_BRIEF_ONLY is decided above the per-bead lock (line $bo_line < $lock_line) and the rsync (< $rsync_line), and its guard encloses both (fi at $fi_line)"; pass=$((pass+1))
  else echo "  FAIL  brief: WARDEN_BRIEF_ONLY (line ${bo_line:-absent}) does not enclose the lock (${lock_line:-absent}) and the rsync (${rsync_line:-absent}) (fi at ${fi_line:-absent}): a brief contends with a live review and copies a tree it never reads"; fail=$((fail+1)); fi
  # GENERATED-RIGHT, NOT ONLY SOURCE-RIGHT: the prompt string must carry both
  # variables, or the functions compute lines the seat never sees.
  # shellcheck disable=SC2016  # single quotes are the point: the literal $diff_class_line / $(warden_...) spellings are what is searched for
  if grep -q '^\$diff_class_line$' "$target" && grep -q '^\$host_verify_line$' "$target" \
     && grep -q 'diff_class_line="\$(warden_diff_class "\$root" "\$range")"' "$target" \
     && grep -q 'host_verify_line="\$(warden_host_verify "\$root" "\$range" "\$src" "\$root/fort/events")"' "$target"; then
    echo "  PASS  brief: the prompt embeds \$diff_class_line and \$host_verify_line, each assigned from its function"; pass=$((pass+1))
  else echo "  FAIL  brief: the two lines are computed but the prompt does not embed them (or the assignments changed shape)"; fail=$((fail+1)); fi
  # fixture repository: one base commit with every kind of path, then one branch per class
  br="$work/brief-repo"; bg() { git -C "$br" -c user.email=h@h -c user.name=h "$@"; }
  git init -q -b main "$br"
  mkdir -p "$br/src" "$br/test" "$br/docs" "$br/gate-1-surface" "$br/fort/handoffs" "$br/scripts"
  printf 'export const a = 1;\n' > "$br/src/a.ts"; printf 'base\n' > "$br/test/T.ts"; printf 'base\n' > "$br/docs/d.md"
  printf 'echo\n' > "$br/gate-1-surface/tool.sh"
  printf 'echo\n' > "$br/scripts/x.sh"; printf 'base\n' > "$br/fort/handoffs/old.md"
  bg add -A; bg commit -qm base
  mkbrief() { # $1 branch, then pairs of path=content (content 'RM' deletes)
    local b="$1"; shift; bg checkout -q -b "$b" main
    local kv; for kv in "$@"; do
      if [ "${kv#*=}" = RM ]; then bg rm -q "${kv%%=*}"; else mkdir -p "$br/$(dirname "${kv%%=*}")"; printf '%s\n' "${kv#*=}" > "$br/${kv%%=*}"; bg add "${kv%%=*}"; fi
    done
    bg commit -qm "$b"; bg checkout -q main
  }
  mkbrief bead/small src/a.ts=changed docs/d.md=changed fort/handoffs/forge-small.md=handoff
  mkbrief bead/auth gate-1-surface/tool.sh=changed
  mkbrief bead/only fort/handoffs/forge-only.md=handoff
  mkbrief bead/scripts scripts/x.sh=changed
  mkbrief bead/tests test/T.ts=changed
  bg checkout -q -b bead/empty main; bg commit -q --allow-empty -m empty; bg checkout -q main
  brief_run() { # $1 function and args -> stdout
    bash -c "set -uo pipefail; $(cat "$brief_src"); $1" 2>"$work/brief.err"
  }
  brief_case() { # $1 name, $2 call, $3 grep -E pattern the single output line must match, $4 pattern it must NOT match (or -)
    local out; out="$(brief_run "$2")"
    if [ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] && grep -qE "$3" <<<"$out" && { [ "$4" = - ] || ! grep -qE "$4" <<<"$out"; }; then
      echo "  PASS  brief: $1"; pass=$((pass+1))
    else echo "  FAIL  brief: $1 -- got: $(printf '%s' "$out" | cut -c1-300) $(head -c 120 "$work/brief.err")"; fail=$((fail+1)); fi
  }
  brief_case "src + docs + a handoff is SMALL, both product paths listed, the handoff not" \
    "warden_diff_class '$br' 'main...bead/small'" '^DIFF CLASS: SMALL \(paths: docs/d.md src/a.ts\)' 'paths:.*forge-small.md'
  brief_case "test/ alone is SMALL" "warden_diff_class '$br' 'main...bead/tests'" '^DIFF CLASS: SMALL \(paths: test/T.ts\)' -
  brief_case "a gate-1 path change is FULL naming the path as gate-1 surface" \
    "warden_diff_class '$br' 'main...bead/auth'" '^DIFF CLASS: FULL \(reason: gate-1-surface/tool.sh is gate-1 surface' -
  brief_case "a handoff-only diff is FULL, saying it carries no product path" \
    "warden_diff_class '$br' 'main...bead/only'" '^DIFF CLASS: FULL \(reason: the diff carries no product path' -
  brief_case "an empty diff is FULL, not SMALL (the safe default when there is nothing to classify)" \
    "warden_diff_class '$br' 'main...bead/empty'" '^DIFF CLASS: FULL \(reason: the diff carries no product path' -
  brief_case "scripts/ is FULL naming the path as outside the set" \
    "warden_diff_class '$br' 'main...bead/scripts'" '^DIFF CLASS: FULL \(reason: scripts/x.sh is outside src/, test/, docs/\)' -
  brief_case "an unresolvable range is FULL, never SMALL" \
    "warden_diff_class '$br' 'main...bead/nonesuch'" '^DIFF CLASS: FULL \(reason: git diff --name-only main...bead/nonesuch failed' -
  # (The source fort's symbol-belt cases are not carried: {{FORT_NAME}}'s gate 1 is whole
  # directories and warden_diff_class has no symbol set.)
  # HOST VERIFY: fixture event files keyed on tree + commit; the tip's commit
  # date is today, so a file dated before it must be ignored.
  ev="$work/brief-events"; mkdir -p "$ev"; today="$(date +%F)"
  tipsha="$(bg rev-parse bead/small)"; tip7="${tipsha:0:7}"; othersha="$(bg rev-parse bead/auth)"
  evline() { printf '{"ts":"%s","actor":"harness","seat":null,"category":"verify.pass","target":"bead/x","detail":"Verifier passed","payload":{"docker":%s,"tree":"%s","commit":"%s"}}\n' "$@"; }
  { evline "${today}T09:00:00-08:00" true  "$br-worktrees/small" "$tip7"
    evline "${today}T12:00:00-08:00" true  "$br-worktrees/small" "$tip7"
    evline "${today}T08:00:00-08:00" false "$br-worktrees/small" "$tip7"
    evline "${today}T10:00:00-08:00" true  "$br-worktrees/other" "$tip7"
    printf 'not json\n'
    evline "${today}T07:00:00-08:00" true  "$br-worktrees/stale" "${othersha:0:7}"
  } > "$ev/events-$today.jsonl"
  evline "2020-01-01T00:00:00-08:00" true "$br-worktrees/old" "$tip7" > "$ev/events-2020-01-01.jsonl"
  brief_case "the newest docker:true verify.pass for this tree at this tip is returned VERBATIM (12:00 beats 09:00 among docker:true; the Warden round two: newest-wins between two docker:true lines is pinned here)" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/small' '$ev'" "^HOST VERIFY: \{\"ts\":\"${today}T12:00:00-08:00\".*\"docker\":true,\"tree\":\"$br-worktrees/small\",\"commit\":\"$tip7\"\}\}$" -
  { evline "${today}T08:00:00-08:00" false "$br-worktrees/small" "$tip7"; } > "$ev/events-$today.jsonl"
  brief_case "a docker:false verify.pass is returned too (her rule decides, not the launcher)" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/small' '$ev'" '^HOST VERIFY: \{.*"docker":false,.*\}$' -
  # finding 1.4 (the Warden, 2026-09-14c): at the tip, docker:true beats a NEWER docker:false
  { evline "${today}T11:00:00-08:00" false "$br-worktrees/small" "$tip7"; evline "${today}T09:30:00-08:00" true "$br-worktrees/small" "$tip7"; } > "$ev/events-$today.jsonl"
  brief_case "at the tip, an older docker:true verify.pass beats a newer docker:false one (a hand masked run must not cost a reproduction)" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/small' '$ev'" "^HOST VERIFY: \{\"ts\":\"${today}T09:30:00-08:00\".*\"docker\":true," -
  # finding 1.3 (the Warden, 2026-09-14c): "never fails" holds under set -e -- a
  # payload that is not an object, and a python3 that dies, both degrade to
  # none found with exit 0 rather than killing the launcher.
  { printf '{"ts":"%sT12:00:00-08:00","actor":"harness","seat":null,"category":"verify.pass","target":"x","detail":"d","payload":["not","an","object"]}\n' "$today"; printf '[1,2,3]\n'; evline "${today}T09:00:00-08:00" true "$br-worktrees/small" "$tip7"; } > "$ev/events-$today.jsonl"
  brief_case "a non-object payload and a non-object event line are skipped, and the good line beside them is still found" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/small' '$ev'" "^HOST VERIFY: \{\"ts\":\"${today}T09:00:00-08:00\"" -
  mkdir -p "$work/nopy"; printf '#!/bin/sh\necho boom >&2; exit 1\n' > "$work/nopy/python3"; chmod 755 "$work/nopy/python3"
  out="$(PATH="$work/nopy:$PATH" bash -c "set -euo pipefail; $(cat "$brief_src"); warden_host_verify '$br' 'main...bead/small' '$br-worktrees/small' '$ev'; echo RC-OK" 2>/dev/null)"
  if grep -q '^HOST VERIFY: none found (the launcher could not read' <<<"$out" && grep -q '^RC-OK$' <<<"$out"; then
    echo "  PASS  brief: a python3 that dies degrades to 'none found' under set -euo pipefail and the caller continues"; pass=$((pass+1))
  else echo "  FAIL  brief: a dying python3 killed the caller or produced a line -- got: $(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"; fail=$((fail+1)); fi
  brief_case "another tree's verify.pass at the same commit is NOT this tree's" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/other-none' '$ev'" '^HOST VERIFY: none found \(no verify.pass with payload.tree=' 'NOT the tip'
  { evline "${today}T07:00:00-08:00" true "$br-worktrees/small" "${othersha:0:7}"; } > "$ev/events-$today.jsonl"
  brief_case "a verify.pass for this tree at a DIFFERENT commit is none found, and names that commit as not the tip" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/small' '$ev'" "^HOST VERIFY: none found \(.*newest verify.pass on this tree is commit ${othersha:0:7} at ${today}T07:00:00-08:00, NOT the tip\)" -
  # Proofdelve ForgeOs-ehre: the fleet's post-merge verify.pass (actor fleet, FULL sha, no tree, no docker field) is accepted
  # only when the candidate IS the root, ranked with docker:true, and the line says what it is.
  fleetline() { printf '{"ts":"%s","actor":"fleet","seat":"fleet","category":"verify.pass","target":"bead/x","detail":"Post-merge verifier GREEN at %s after landing bead/x into main, run in a fresh worktree at that commit; the worktree was removed","payload":{"run":"r","commit":"%s","ran":true,"worktree_kept":false}}\n' "$1" "$2" "$2"; }   # $1 ts, $2 the full sha (detail and payload)
  { fleetline "${today}T13:00:00-08:00" "$tipsha"; } > "$ev/events-$today.jsonl"
  brief_case "ehre: a root review (candidate == root) cites the fleet's post-merge green at the full tip sha, naming it as such" \
    "warden_host_verify '$br' 'main...bead/small' '$br' '$ev'" "^HOST VERIFY: \{\"ts\":\"${today}T13:00:00-08:00\",\"actor\":\"fleet\".*\"commit\":\"$tipsha\".* -- the fleet's post-merge green: verify.sh run on the host in a fresh worktree at exactly this commit" -
  brief_case "ehre CONTROL: a candidate-worktree review does NOT cite the fleet's post-merge green (a landed green says nothing about an unlanded branch)" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/small' '$ev'" '^HOST VERIFY: none found' 'post-merge'
  { fleetline "${today}T13:00:00-08:00" "$othersha"; } > "$ev/events-$today.jsonl"
  brief_case "ehre CONTROL: a fleet post-merge green at a DIFFERENT commit is none found for a root review" \
    "warden_host_verify '$br' 'main...bead/small' '$br' '$ev'" '^HOST VERIFY: none found' 'post-merge'
  { fleetline "${today}T13:00:00-08:00" "$tip7"; } > "$ev/events-$today.jsonl"
  brief_case "ehre CONTROL: the fleet line must carry the FULL sha; a 7-char commit with no tree is not accepted (fleet.sh always emits the full sha)" \
    "warden_host_verify '$br' 'main...bead/small' '$br' '$ev'" '^HOST VERIFY: none found' 'post-merge'
  { printf '{"ts":"%sT13:00:00-08:00","actor":"harness","seat":null,"category":"verify.pass","target":"x","detail":"d","payload":{"commit":"%s","ran":true}}\n' "$today" "$tipsha"; } > "$ev/events-$today.jsonl"
  brief_case "ehre CONTROL: a tree-less line from a NON-fleet actor at the full tip is not accepted" \
    "warden_host_verify '$br' 'main...bead/small' '$br' '$ev'" '^HOST VERIFY: none found' 'post-merge'
  { fleetline "${today}T13:00:00-08:00" "$tipsha"; evline "${today}T14:00:00-08:00" true "$br" "$tip7"; } > "$ev/events-$today.jsonl"
  brief_case "ehre: for a root review a NEWER docker:true tree line at the tip still wins over the fleet line (same tier, newest wins)" \
    "warden_host_verify '$br' 'main...bead/small' '$br' '$ev'" "^HOST VERIFY: \{\"ts\":\"${today}T14:00:00-08:00\".*\"docker\":true," 'post-merge'
  rm -f "$ev/events-$today.jsonl"
  brief_case "a matching line in a day file older than the tip's commit is ignored (no verify.pass can predate the commit it scored)" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/old' '$ev'" '^HOST VERIFY: none found \(no verify.pass with payload.tree=' -
  brief_case "an unresolvable tip is none found, never a line" \
    "warden_host_verify '$br' 'main...bead/nonesuch' '$br-worktrees/small' '$ev'" '^HOST VERIFY: none found \(the launcher could not resolve the tip' -
  brief_case "a missing events directory is none found, never a crash" \
    "warden_host_verify '$br' 'main...bead/small' '$br-worktrees/small' '$work/no-such-dir'" '^HOST VERIFY: none found' -
fi

# WIP RESCUE LINE (Proofdelve ForgeOs-gvhhk): extracted on its own, run against the brief
# fixture repo with one branch carrying a forge.sh rescue commit.
echo
echo "WIP RESCUE LINE (Proofdelve ForgeOs-gvhhk)"
awk '/^warden_wip_line\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$target" > "$work/wip.sh"
if ! grep -qE '^warden_wip_line\(\)' "$work/wip.sh"; then
  echo "  FAIL  wip: $target defines no warden_wip_line(): a rescued half-edit reaches the Warden unlabelled"; fail=$((fail+1))
elif [ ! -d "$work/brief-repo" ]; then
  echo "  FAIL  wip: the brief fixture repo was not built, so the WIP cases cannot run"; fail=$((fail+1))
else
  wb="$work/brief-repo"; wg() { git -C "$wb" -c user.email=h@h -c user.name=h "$@"; }
  wg checkout -q -b bead/wip main; printf 'half\n' > "$wb/src/a.ts"; wg add -A; wg commit -qm "{{BEAD_PREFIX}}-x: WIP RESCUED BY forge.sh, not the Forge's finished work (test)"; wg checkout -q main
  wip_run() { bash -c "set -uo pipefail; $(cat "$work/wip.sh"); $1" 2>&1; }
  out="$(wip_run "warden_wip_line '$wb' 'main...bead/wip'")"
  if grep -qE '^WIP RESCUE: 1 commit\(s\) in this range were made by forge.sh' <<<"$out" && grep -q 'UNFINISHED' <<<"$out"; then
    echo "  PASS  wip: a range carrying a forge.sh rescue commit prints the WIP RESCUE line"; pass=$((pass+1))
  else echo "  FAIL  wip: no WIP RESCUE line for a rescued range -- got: $out"; fail=$((fail+1)); fi
  out="$(wip_run "warden_wip_line '$wb' 'main...bead/small'")"
  if [ -z "$out" ]; then echo "  PASS  wip: an ordinary range prints nothing (no false WIP label)"; pass=$((pass+1))
  else echo "  FAIL  wip: an ordinary range was labelled WIP -- got: $out"; fail=$((fail+1)); fi
  # shellcheck disable=SC2016  # the literal spellings are what is searched for
  if grep -q '^\$wip_line$' "$target" && grep -q 'wip_line="\$(warden_wip_line "\$root" "\$range")"' "$target"; then
    echo "  PASS  wip: the review prompt embeds \$wip_line, assigned from warden_wip_line()"; pass=$((pass+1))
  else echo "  FAIL  wip: the WIP line is computed but never reaches the prompt"; fail=$((fail+1)); fi
fi


echo
echo "RESULT $target : $pass pass / $fail fail"
[ $fail -eq 0 ]
