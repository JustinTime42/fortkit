#!/bin/bash
# Harness for fleet.sh's landability condition (Proofdelve ForgeOs-vikl, Proofdelve ForgeOs-5m7a, and
# since Proofdelve ForgeOs-dx34.1 the NARROWING of it). Tests the SHIPPED functions,
# extracted from the real launcher, against real git fixtures. Refuses on an
# incomplete extraction.
#
# WHAT CHANGED UNDER IT, 2026-09-09, AND WHY THE CASES INVERTED — TWICE, IN ONE
# DAY, IN OPPOSITE DIRECTIONS FOR THE TWO HALVES OF ONE CONDITION.
#
# Landability used to be a RUN-START condition: preflight called
# assert_landable() and exited 64, so a dirty root meant the fleet did not start.
# Proofdelve ForgeOs-dx34.1 moved the decision to merge time, where land() defers, and cases
# 2-7 inverted from `rc=64` to exit 0 with the reason named.
#
# THAT WENT ONE CONDITION TOO FAR, AND THIS FILE IS HOW IT SHIPPED. landable_why()
# computes TWO conditions — a wrong branch and uncommitted tracked source — and
# only the dirt half was ever asked for, argued or measured. Case 2 was inverted
# to assert "a non-main branch does NOT refuse", so the instrument RATIFIED the
# overreach instead of catching it; case 3 did the same for a detached HEAD, and
# they are one path rather than two (tree_branch() returns the literal
# DETACHED-HEAD and landable_why() compares it against $main_branch like any
# other name). The Warden's covenant-4.5 review blocked on it.
#
# AND THEN THE BRANCH HALF TOOK BACK, ON ITS OWN SIDE, THE ONE PROPERTY THE DIRT
# HALF HAD JUST BOUGHT (Proofdelve ForgeOs-geym, the Overseer's ruling of 2026-09-09).
# --dry-run is the path this file offers for TESTING its guards, and the restored
# branch refusal applied to it — so the mode built to exercise the guard refused
# on the condition the guard checks. Cases 2d, 3d and 3bd are that exemption, and
# they are deliberately PAIRED with 2, 3 and 3b rather than replacing them: the
# real run still refuses at 64 and the dry run reports and proceeds, and each
# case is the other's inversion. Running this whole file against the pre-geym
# launcher fails exactly the three dry cases and passes every other one.
#
# SO CASES 2 AND 3 INVERT BACK HERE, IN THE SAME COMMIT AS THE CODE, and case 3b
# is new. The dirt cases 4-7 do NOT move: they are the half the narrowing was
# for. The property being measured is unchanged and it is the one the whole file
# is about: THE CONDITION MUST STILL DISCRIMINATE. What moved is the severity —
# and the severity is now DIFFERENT FOR THE TWO HALVES, which is the whole
# finding. Cases 0 and 0b are what pin each half to exactly one place.
#
# WHY FIXTURES AND NOT THE LIVE CHECKOUT: the condition's whole job is to
# discriminate five states of a repository, and the live checkout is only ever
# in one of them at a time. A guard measured against one state cannot be shown
# to discriminate. Each case builds its own repo and overrides $root at it.
#
# Point it at a candidate before installing:  FLEET_SH=/path/to/cand ./this
set -uo pipefail
launcher="${FLEET_SH:-$(dirname "$0")/../fort/scripts/fleet.sh}"
printf 'launcher=%s\n' "$launcher"
[ -f "$launcher" ] || { echo "HARNESS REFUSES: launcher is missing: $launcher" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }

# CASE 0 RUNS BEFORE THE EXTRACTION GATE, DELIBERATELY. Every executed case
# below needs report_landability(), which does not exist in the pre-narrowing
# launcher, so against that file this harness can only REFUSE — and a refusal
# proves less about the defect than a failure does (recorded 2026-09-08). This
# case reads only source, so the pre-narrowing file scores a real FAIL here and
# is only then refused.
# 0  THE DIRT HALF, PINNED AT ITS ONLY REMAINING SEVERITY. Cases 4-7 show that
# report_landability continues, but a second exit hidden anywhere in the
# reporting path would restore the old behaviour and those cases would not see
# it. So: preflight must consult the REPORT exactly once, through
# report_landability, and report_landability must contain no exit at all.
# WHY THESE CHECKS DO NOT USE `grep -q` ON A PIPE (Proofdelve ForgeOs-g0ev, 2026-09-10).
# MEASURED: 92 failures in 300 runs of the case-0 check below, every one with
# pipeline status 141 (SIGPIPE), awk exit 0, a complete 24513-byte block, and
# the pattern PRESENT (grep on the same bytes from a file matched every time).
# `grep -q` exits the instant it matches; bash's printf is still flushing a
# 24KB payload in stdio-sized chunks; the next write hits a closed pipe and
# dies 141; `set -o pipefail` makes 141 the pipeline status. THE CHECK FAILS
# BECAUSE THE MATCH WAS FOUND, AND FOUND EARLY.
# It bit only here because only this payload needs more than one flush: land()
# is 24514 bytes where preflight() is 5289 and report_landability() 1076. Those
# are function extractions, so today's safe sizes are not a property to rely on.
# The repair drops -q so grep must read all input, and tests its OUTPUT instead
# of its status. Same grep, same regex engine, same line semantics; no early
# exit, so the writer can never be signalled. It cost the fleet a halt on
# 2026-09-10 that named a documentation-only merge as the cause.
pf_block=$(awk '/^preflight\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{if(f) exit}' "$launcher")
rl_block=$(awk '/^report_landability\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{if(f) exit}' "$launcher")
# HOISTED, NOT INLINE (Proofdelve ForgeOs-g0ev). Each grep runs ONCE, above the branch,
# and the branches test a plain variable. That satisfies SC2143 honestly
# rather than by silencing it, and keeps the property that matters: no -q,
# so grep reads all input and can never SIGPIPE the writer mid-flush.
rl_stop=$(printf '%s' "$rl_block" | grep -E '(^|[^[:alnum:]_])(exit|halt) ')
pf_assert=$(printf '%s' "$pf_block" | grep 'assert_landable')
if [ -z "$pf_block" ] || [ -z "$rl_block" ]; then
  no "preflight or report_landability not found" "extraction empty"
elif [ -n "$rl_stop" ]; then
  no "report_landability can still stop the run" "$(printf '%s' "$rl_block" | grep -nE '(exit|halt) ' | head -3)"
elif [ -n "$pf_assert" ]; then
  no "preflight still calls a refusing landability guard" "assert_landable is reachable from preflight"
elif [ "$(printf '%s' "$pf_block" | grep -c 'report_landability')" -eq 1 ]; then
  ok "SOURCE: preflight consults landability once, through report_landability, which cannot exit"
else
  no "preflight does not consult report_landability exactly once" "$(printf '%s' "$pf_block" | grep -nc 'landab')"
fi

# 0b  THE BRANCH HALF, PINNED AT ITS SEVERITY — AND ALSO ABOVE THE GATE, FOR THE
# REASON CASE 0 IS. This is the case that must FAIL against the pre-restoration
# launcher rather than refuse: that file has no assert_on_main_branch at all, and
# a harness that can only refuse against the file carrying the defect has not
# measured the defect (recorded 2026-09-08, and this is its second outing).
# Preflight must call the branch guard exactly once, and the branch guard must be
# able to stop the run — the mirror image of case 0.
ab_block=$(awk '/^assert_on_main_branch\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{if(f) exit}' "$launcher")
if [ -z "$pf_block" ]; then
  no "preflight not found" "extraction empty"
elif [ -z "$ab_block" ]; then
  no "no branch guard exists: assert_on_main_branch is not defined in $launcher" \
     "a wrong-branch run would start, and every bead in it would be cut off that base"
elif [ "$(printf '%s' "$pf_block" | grep -v '^[[:space:]]*#' | grep -c 'assert_on_main_branch')" -ne 1 ]; then
  # COMMENT LINES ARE STRIPPED FIRST, and that is not fussiness: preflight's own
  # comment names the guard, so counting mentions scored 2 and reported a correct
  # file as broken. This civilization has paid for the mirror of it four times —
  # a retired literal quoted in the comment that retires it, passing or failing a
  # zero-tolerance check for the prose rather than the code.
  no "preflight does not call assert_on_main_branch exactly once" \
     "$(printf '%s' "$pf_block" | grep -v '^[[:space:]]*#' | grep -nc 'assert_on_main_branch')"
elif [ "$(printf '%s' "$pf_block" | grep -vn '^[[:space:]]*#' | grep 'assert_on_main_branch' | cut -d: -f1)" \
      -gt "$(printf '%s' "$pf_block" | grep -vn '^[[:space:]]*#' | grep 'report_landability' | cut -d: -f1)" ]; then
  no "preflight reports landability before it refuses a wrong branch" \
     "order matters: a report that named a wrong branch and then continued is the defect being restored"
else
  # WHAT THIS CASE DELIBERATELY DOES NOT ASSERT: that the guard contains a
  # literal `exit`. The SEVERITY is proved by execution in cases 2, 3 and 3b,
  # which run the shipped function against real fixtures and require status 64.
  # An earlier draft pinned the word here and went red for a correct variant
  # whose refusal delegated to a helper — a control that pins a spelling is a
  # control that goes red for the next correct refactor and teaches its fort to
  # ignore it (fortkit-or2.8, and three cases moved for it on 2026-09-08).
  ok "SOURCE: preflight calls assert_on_main_branch exactly once, before it reports"
fi

# THE EXTRACTION IS THE WHOLE FUNCTION TABLE, NOT A HAND-PICKED SET — TOVA
# MARROWASSAY'S ROUND-ONE FINDING 4, ANSWERED RATHER THAN NOTED. Her general
# form: *a gate that lists the functions a harness extracts does not cover the
# functions those functions CALL*. Under `bash -c` with no `set -e` an
# unextracted callee is `command not found` on stderr, an empty result, and a
# case that scores whatever the fallback path scores. That fired TWICE in the
# sitting that wrote this: tree_branch() stopped being a one-liner and the
# per-name rule (`/^tree_branch\(\)/{print; next}`) copied its opening brace
# alone — every executed case then died with a bash syntax error that reads
# exactly like a defect in the launcher — and a reworded refusal that
# delegated to a helper left the helper behind.
#
# A CLOSURE COMPUTED FROM NAMES WAS TRIED FIRST AND IS NOT KEPT. Scanning the
# extracted text for callees matches prose: `say "...the parked merges land on
# the next pass..."` names land(), which named postmerge_verify(), and one
# helper became a third of the launcher. Command position cannot be recognised
# reliably by grep, and a heuristic here would be a second thing to be wrong.
#
# So: take EVERY top-level function definition, minus the handful the runners
# below stub — those must not be overridden by the launcher's own copies — and
# then REQUIRE THE RESULT TO PARSE. Definitions do not run; only what a case
# calls runs, so this costs nothing but the file size, and a `bash -n` gate on
# the extraction turns any future brace-style surprise into a refusal instead of
# a column of failures that read like defects in the launcher.
harness_stubs=' say warn halt emit worker_state '
: > "$work/guard.sh"
grep -E '^(main_branch|fleet_record_paths)=' "$launcher" >> "$work/guard.sh"
grep -oE '^[a-z_][a-z0-9_]*\(\)' "$launcher" | sed 's/()//' | sort -u \
| while IFS= read -r fn; do
  case "$harness_stubs" in *" $fn "*) continue ;; esac
  awk -v name="$fn" '
    $0 ~ "^" name "\\(\\) *\\{" { if ($0 ~ /\}[[:space:]]*$/) { print; exit } f=1 }
    f{print}
    /^\}$/{ if(f) exit }' "$launcher" >> "$work/guard.sh"
done
bash -n "$work/guard.sh" \
  || { echo "HARNESS REFUSES: the extracted function table does not parse" >&2; exit 3; }

n=$(wc -l < "$work/guard.sh")
# REFUSE ON AN INCOMPLETE EXTRACTION, NAMING EACH SYMBOL. An earlier version
# checked only assert_landable, so when landable_why was introduced and NOT
# extracted every refusal case silently became "command not found -> empty
# reason -> landable", and the clean-main vacuity control PASSED VACUOUSLY while
# five real cases failed. A harness must not be able to score a pass on a
# function it did not load.
# assert_on_main_branch IS DELIBERATELY NOT IN THIS LIST, and that is a judgement
# rather than an oversight. Requiring it would turn every run against the
# pre-restoration launcher into a REFUSAL, and cases 2, 3 and 3b are exactly the
# cases that must FAIL there — the inversion is what proves they discriminate.
# run() below stubs it when it is absent, and the stub prints NO-BRANCH-GUARD
# into the output, so a rename or a deletion produces a loud attributable FAIL
# and never a silent pass.
for sym in 'main_branch=' 'fleet_record_paths=' 'tree_branch()' 'tree_dirty()' 'landable_why()' 'report_landability()' 'parked_merges()'; do
  grep -qF "$sym" "$work/guard.sh" || { echo "HARNESS REFUSES: $sym not extracted from $launcher" >&2; exit 3; }
done
[ "$n" -ge 15 ] || { echo "HARNESS REFUSES: extracted $n lines" >&2; exit 3; }
echo "extracted $n lines of shipped guard code from $launcher"

mkrepo() { # $1 name -> prints path
  local r="$work/$1"
  mkdir -p "$r/.beads" "$r/fort/events" "$r/src"
  git -C "$r" init -q -b main
  git -C "$r" config user.email h@h; git -C "$r" config user.name H
  echo one > "$r/src/a.txt"; echo rec > "$r/.beads/interactions.jsonl"
  echo ev > "$r/fort/events/e.jsonl"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -qm base
  printf '%s' "$r"
}

# PREFLIGHT'S LANDABILITY SEQUENCE, IN PREFLIGHT'S OWN ORDER: the branch guard
# refuses first, then the report. Modelled as a sequence rather than as two
# separate runners because the ORDER is part of the property — a report that
# named a wrong branch and continued would be the defect this restores.
# halt() and exit-by-any-other-name are stubbed LOUD so that any path reaching
# stop-the-world is VISIBLE rather than silent; cases 4-7 must reach none.
# `dry` IS SET EXPLICITLY IN BOTH RUNNERS AND IS NOT DEFAULTED. Since
# Proofdelve ForgeOs-geym the branch guard reads it, and under `set -u` an unset $dry is a
# death rather than a failing assertion — a harness that vanishes instead of
# reporting is the shape recorded on 2026-08-14. fleet.sh itself sets it at :151,
# above preflight, on every path.
# THE COMPOSED SCRIPT GOES THROUGH A FILE, NEVER THROUGH AN ARGUMENT
# (2026-09-17, the Proofdelve ForgeOs-ubgx sitting). These runners used to read
# `bash -c "... $(cat guard.sh) ..."`, which hands the whole extracted function
# table to execve as ONE argv string, and Linux caps a single argument at
# 128 KiB (MAX_ARG_STRLEN -- the same limit Proofdelve ForgeOs-4hzq met on a large bead's
# prompt). The extraction crossed it when fleet.sh gained its signed-landing
# block, and every runner died `Argument list too long`, rc=126: sixteen
# failures that read exactly like defects in the launcher. The text each
# runner composes is unchanged; only the transport is.
runsh() { # stdin: the composed script -> runs it; stdout+stderr as the runner's
  local f rc; f="$work/run-$$-$RANDOM.sh"; cat > "$f"; bash "$f" 2>&1; rc=$?; rm -f "$f"; return $rc; }
run() { # $1 repo -- A REAL RUN: the branch guard must be able to refuse
  runsh <<EOF
set -uo pipefail
root='$1'; dry=0; say(){ echo "SAY \$*"; }; warn(){ echo "WARN \$*" >&2; }
halt(){ echo "HALTED \$*"; exit 70; }
$(cat "$work/guard.sh")
declare -F assert_on_main_branch >/dev/null || assert_on_main_branch(){ echo 'NO-BRANCH-GUARD'; }
assert_on_main_branch; report_landability; echo PREFLIGHT-CONTINUED
EOF
}
run_dry() { # $1 repo -- THE SAME SEQUENCE UNDER --dry-run (Proofdelve ForgeOs-geym)
  runsh <<EOF
set -uo pipefail
root='$1'; dry=1; say(){ echo "SAY \$*"; }; warn(){ echo "WARN \$*" >&2; }
halt(){ echo "HALTED \$*"; exit 70; }
$(cat "$work/guard.sh")
declare -F assert_on_main_branch >/dev/null || assert_on_main_branch(){ echo 'NO-BRANCH-GUARD'; }
assert_on_main_branch; report_landability; echo PREFLIGHT-CONTINUED
EOF
}
why() { # $1 repo -> prints the reason string
  runsh <<EOF
set -uo pipefail
root='$1'; say(){ :; }; warn(){ :; }; halt(){ echo HALTED; exit 70; }
$(cat "$work/guard.sh")
landable_why
EOF
}
# An unlandable fixture must do THREE things: continue, name the condition, and
# say what will happen to merges. Asserted together because a preflight that
# continues silently is a worse instrument than one that refuses.
narrates() { # $1 output, $2 substring the reason must contain
  grep -q PREFLIGHT-CONTINUED <<<"$1" \
    && grep -q "$2" <<<"$1" \
    && grep -q 'NOT LANDABLE RIGHT NOW' <<<"$1" \
    && grep -q 'PARKED' <<<"$1"
}

# A REFUSING FIXTURE MUST DO THREE THINGS: stop, stop at 64, and NAME what it
# found. THE WORDING IS NOT ASSERTED, deliberately (Proofdelve ForgeOs-8zb7 step 2): a case
# that pins a sentence goes red for the next correct rewording and teaches its
# fort to ignore it (fortkit-or2.8). What is asserted is the property — the run
# did not continue, the status is the file's own refusal code, and the operator
# was told which branch state was found.
refuses() { # $1 output, $2 rc, $3 substring naming the condition
  [ "$2" -eq 64 ] \
    && grep -q "$3" <<<"$1" \
    && ! grep -q 'PREFLIGHT-CONTINUED' <<<"$1"
}

# THE --dry-run HALF (Proofdelve ForgeOs-geym) MUST DO FOUR THINGS: continue, exit 0, NAME
# the branch state it found, and SAY THAT A REAL RUN WOULD REFUSE. The fourth is
# the one that makes the exemption honest rather than silent — it is 5m7a's own
# shape, which the dirt half has had since it was narrowed, and without it a dry
# run on a wrong branch reports a queue no real run would ever cut and says
# nothing about it. THE WORDING IS NOT PINNED: what is asserted is that the
# operator was told a real run refuses and at what status, not the sentence that
# tells them (Proofdelve ForgeOs-8zb7 step 2).
reports_dry() { # $1 output, $2 rc, $3 substring naming the condition
  [ "$2" -eq 0 ] \
    && grep -q "$3" <<<"$1" \
    && grep -q 'PREFLIGHT-CONTINUED' <<<"$1" \
    && grep -q 'REAL RUN WOULD REFUSE' <<<"$1" \
    && grep -q '64' <<<"$1"
}

# `grep -q` must not be fed by a concurrent writer under pipefail: once it
# matches, that writer can receive SIGPIPE. This payload puts all four match
# tokens on line 1 and ENDS THAT LINE, then follows with 256 KiB of filler on
# a second line: `grep -q` matches and exits after its first read while a
# pipeline writer still holds most of the payload, which is what raises
# SIGPIPE. MEASURED 2026-09-18 on this host: with the pipeline form,
# 64 KiB of filler gives PIPESTATUS 0 0 (printf's remainder fits the drained
# buffer before grep exits), 128 KiB and above give 141 0. Three earlier
# shapes did not discriminate (the Warden on c815 and c815.1, and the Mayor's own
# first repair): tokens at the END of one line; tokens first with no newline;
# tokens on line 1 with only 64 KiB after. The size is the property.
large_output="PREFLIGHT-CONTINUED is landable REAL RUN WOULD REFUSE 64
$(head -c 262144 /dev/zero | tr '\000' x)"
if [ "${#large_output}" -gt 262144 ] && reports_dry "$large_output" 0 'is landable'; then
  ok "256 KiB output is inspected without SIGPIPE (${#large_output} bytes)"
else
  no "256 KiB output SIGPIPE regression" "bytes=${#large_output}; reports_dry did not match"
fi

# 1 clean main must PASS and say so -- the VACUITY CONTROL. Without it a
# report that says "not landable" unconditionally scores a clean sweep on the
# five unlandable cases below.
r=$(mkrepo clean); out=$(run "$r"); rc=$?
if [ $rc -eq 0 ] && grep -q PREFLIGHT-CONTINUED <<<"$out" \
   && grep -q 'is landable' <<<"$out" \
   && ! grep -q 'NOT LANDABLE' <<<"$out"; then
  ok "VACUITY CONTROL: clean main is reported landable and the run continues"
else no "clean main misreported" "rc=$rc $out"; fi

# ---------------------------------------------------------------------------
# 2-3b  THE BRANCH HALF: STILL AN UNCONDITIONAL REFUSAL, restored 2026-09-09
# after being narrowed with the dirt half for one day. A dirty tree is transient
# and self-healing — the tree gets committed and the parked merges land — while a
# wrong branch poisons the base of every bead the run cuts, cannot be repaired
# after the fact, and would have land() record foreign commits under a bead's
# name. Different in kind, so different severity.

# 2 a wrong branch
r=$(mkrepo wrongbranch); git -C "$r" checkout -qb bead/x
out=$(run "$r"); rc=$?
if refuses "$out" "$rc" "bead/x"; then
  ok "a non-main branch REFUSES at 64 and names the branch"; else no "wrong branch did not refuse" "rc=$rc $out"; fi

# 3 a detached HEAD. THE SAME PATH AS CASE 2 AND NOT A SECOND ONE: tree_branch()
# returns the literal DETACHED-HEAD and the comparison is against $main_branch,
# so a detached HEAD is a wrong branch by that identical test. They invert
# together or the instrument disagrees with the code it guards.
r=$(mkrepo detached); git -C "$r" checkout -q --detach HEAD
out=$(run "$r"); rc=$?
if refuses "$out" "$rc" 'DETACHED-HEAD' && ! grep -q 'UNKNOWN-HEAD' <<<"$out"; then
  ok "a detached HEAD REFUSES at 64 and is named as detached, not as undeterminable"; else no "detached HEAD did not refuse" "rc=$rc $out"; fi

# 3b THE THIRD BRANCH STATE, which the collapse used to hide (round two,
# acceptance 5). `git symbolic-ref --quiet HEAD` exits 1 ONLY for a detached
# HEAD and 128 for a git-level failure, so a $root that is not a repository at
# all used to be reported to the operator as a detached HEAD — a different
# problem with a different fix. Both refuse; the sentence must differ, and the
# sentence is the whole value of a refusal.
r="$work/notarepo"; mkdir -p "$r"
out=$(run "$r"); rc=$?
if refuses "$out" "$rc" 'UNKNOWN-HEAD' && ! grep -q 'DETACHED-HEAD' <<<"$out"; then
  ok "a root whose branch cannot be determined REFUSES at 64 and is named UNKNOWN-HEAD, not DETACHED"
else no "undeterminable branch not discriminated" "rc=$rc $out"; fi

# 2d-3bd  THE SAME THREE FIXTURES UNDER --dry-run (Proofdelve ForgeOs-geym). Each is the
# inversion of the case immediately above it: identical repository, one variable
# different, opposite required outcome. That pairing is what makes either half
# evidence — a guard that refused everything and a guard that refused nothing
# would each pass one column and fail the other.
r=$(mkrepo wrongbranch_dry); git -C "$r" checkout -qb bead/x
out=$(run_dry "$r"); rc=$?
if reports_dry "$out" "$rc" "bead/x"; then
  ok "--dry-run on a non-main branch REPORTS, proceeds, and says a real run would refuse at 64"
else no "dry run on a wrong branch did not report and proceed" "rc=$rc $out"; fi

r=$(mkrepo detached_dry); git -C "$r" checkout -q --detach HEAD
out=$(run_dry "$r"); rc=$?
if reports_dry "$out" "$rc" 'DETACHED-HEAD'; then
  ok "--dry-run on a detached HEAD REPORTS, proceeds, and says a real run would refuse at 64"
else no "dry run on a detached HEAD did not report and proceed" "rc=$rc $out"; fi

r="$work/notarepo_dry"; mkdir -p "$r"
out=$(run_dry "$r"); rc=$?
if reports_dry "$out" "$rc" 'UNKNOWN-HEAD'; then
  ok "--dry-run on an undeterminable branch REPORTS, proceeds, and keeps the UNKNOWN-HEAD sentence"
else no "dry run on an undeterminable branch did not report and proceed" "rc=$rc $out"; fi

# 3v  THE VACUITY CONTROL FOR THE EXEMPTION, and it is not the same as case 1.
# Case 1 shows a CLEAN main is reported landable under a real run. This shows the
# dry-run path is not simply "say nothing and continue": on a clean main it must
# still report landable and must NOT claim a real run would refuse. Without it,
# an assert_on_main_branch that returned 0 unconditionally under --dry-run scores
# a clean sweep on 2d, 3d and 3bd.
r=$(mkrepo clean_dry); out=$(run_dry "$r"); rc=$?
if [ $rc -eq 0 ] && grep -q PREFLIGHT-CONTINUED <<<"$out" \
   && grep -q 'is landable' <<<"$out" \
   && ! grep -q 'REAL RUN WOULD REFUSE' <<<"$out"; then
  ok "VACUITY CONTROL: --dry-run on clean main reports landable and claims no refusal"
else no "the dry-run path reports a refusal on a clean tree" "rc=$rc $out"; fi

# ---------------------------------------------------------------------------
# 4-7  THE DIRT HALF: THE NARROWING (Proofdelve ForgeOs-dx34.1), and it stands. Each of
# these used to exit 64. Each must now CONTINUE, name the condition, and say that
# merges will be parked.

# 4 uncommitted SOURCE
r=$(mkrepo dirtysrc); echo two >> "$r/src/a.txt"
out=$(run "$r"); rc=$?
if [ $rc -eq 0 ] && narrates "$out" 'src/a.txt'; then
  ok "uncommitted tracked source does NOT refuse: it names the file and parks merges"; else no "dirty source" "rc=$rc $out"; fi

# 5 THE EXEMPTION, and the case the condition is most likely to get wrong. bd
# rewrites .beads/interactions.jsonl on nearly every invocation and fleet.sh
# makes dozens per pass; fort/events is what the run is itself appending to.
# Under the narrowing this matters MORE, not less: record dirt read as source
# dirt would park every merge on a tree that is perfectly landable.
r=$(mkrepo dirtyrec); echo more >> "$r/.beads/interactions.jsonl"; echo more >> "$r/fort/events/e.jsonl"
out=$(run "$r"); rc=$?
if [ $rc -eq 0 ] && grep -q 'is landable' <<<"$out" \
   && ! grep -q 'NOT LANDABLE' <<<"$out"; then
  ok "record paths (.beads/, fort/events/) are exempt and are still reported LANDABLE"; else no "record exemption" "rc=$rc $out"; fi

# 6 the exemption must NOT swallow source dirt sitting alongside record dirt
r=$(mkrepo mixed); echo more >> "$r/.beads/interactions.jsonl"; echo two >> "$r/src/a.txt"
out=$(run "$r"); rc=$?
if [ $rc -eq 0 ] && narrates "$out" 'src/a.txt' \
   && ! grep -q 'interactions.jsonl' <<<"$out"; then
  ok "source dirt beside record dirt is still NOT landable, and names only the source"
else no "mixed dirt" "rc=$rc $out"; fi

# 7 untracked files alone must not make a tree unlandable
r=$(mkrepo untracked); echo junk > "$r/agentdb.rvf"
out=$(run "$r"); rc=$?
if [ $rc -eq 0 ] && grep -q 'untracked file' <<<"$out" \
   && ! grep -q 'NOT LANDABLE' <<<"$out"; then
  ok "untracked files do not make a tree unlandable, and are reported"; else no "untracked" "rc=$rc $out"; fi

# ---------------------------------------------------------------------------
# 8-10  Proofdelve ForgeOs-5m7a: THE DECISION AND THE SEVERITY ARE SEPARATE. land() must
# DEFER on an unlandable tree, never halt(): the condition is caused by a third
# party (concurrent sessions share this checkout), so one Mayor edit at 03:00
# would otherwise write $FLEET_STATE/HALT and disable every LATER run until a
# person deleted it by hand -- the "a successful night disables the fleet" shape
# Proofdelve ForgeOs-feeq removed from the budget path, re-entering through this one.

# 8 landable_why REPORTS and never halts or exits
r=$(mkrepo whyonly); echo two >> "$r/src/a.txt"
out=$(why "$r"); rc=$?
if [ $rc -eq 0 ] && grep -q 'src/a.txt' <<<"$out" \
   && ! grep -q 'HALTED' <<<"$out"; then
  ok "landable_why returns a reason without halting or exiting"
else no "landable_why halts or exits" "rc=$rc $out"; fi

# 9 and it is EMPTY on a clean tree, so callers can branch on it
r=$(mkrepo whyclean); out=$(why "$r"); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then
  ok "landable_why is empty on a landable tree"; else no "landable_why not empty when clean" "rc=$rc [$out]"; fi

# 10 THE SEVERITY, read from the shipped source rather than executed: land()'s
# landability branch must defer and must not reach halt. Stated as a source
# assertion because land() cannot be exercised without a real merge slot, a real
# worktree and a real bd; scripts/fleet-e2e-harness.sh is what exercises it.
#
# THE ASSERTION IS THE PROPERTY, NOT THE SPELLING (repaired 2026-09-08, Regent
# sitting, after Proofdelve ForgeOs-usz6). This pinned the literal `fleet.deferred` inside
# land()'s own prologue. usz6 moved the emit into defer_merge(), which land()
# now calls — the behaviour identical, the branch still deferring, still not
# halting — and this case went RED for a correct fix. A control that pins a
# spelling is a control that goes red for the next refactor and teaches its
# fort to ignore it (fortkit-or2.8). So it now accepts either shape AND, when
# the branch delegates, follows the delegate and asserts the same two things
# there: the property is chased rather than loosened.
land_block=$(awk '/^land\(\)[[:space:]]*\{/{f=1} f{print} /^  local into; into=/{if(f) exit}' "$launcher")
defer_block=$(awk '/^defer_merge\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{if(f) exit}' "$launcher")
# HOISTED, NOT INLINE (Proofdelve ForgeOs-g0ev). Each grep runs ONCE, above the branch,
# and the branches test a plain variable. That satisfies SC2143 honestly
# rather than by silencing it, and keeps the property that matters: no -q,
# so grep reads all input and can never SIGPIPE the writer mid-flush.
lb_halt=$(printf '%s' "$land_block" | grep -E '^\s*halt ')
lb_defer=$(printf '%s' "$land_block" | grep 'fleet.deferred')
# The two remaining pipelines of this block were still inline `grep -q` after
# the 53c50a6 repair (Proofdelve ForgeOs-g0ev, 2026-09-11): the same SIGPIPE, reading as
# a FALSE RED here because neither carries a leading `!`. Hoisted like the two
# above. defer_block is 1.6KB today, which is one flush, but it is a function
# extraction and its size is not a property to rely on.
lb_delegates=$(printf '%s' "$land_block" | grep 'defer_merge ')
db_emits=$(printf '%s' "$defer_block" | grep 'fleet.deferred')
db_halt=$(printf '%s' "$defer_block" | grep -E '^\s*halt ')
if [ -z "$land_block" ]; then
  no "land() landability block not found" "extraction empty"
elif [ -n "$lb_halt" ]; then
  no "land() still halts on an unlandable tree" "$(printf '%s' "$land_block" | grep -nE '^\s*halt ' | head -3)"
elif [ -n "$lb_defer" ]; then
  ok "SOURCE: land()'s landability branch defers (fleet.deferred) and does not halt"
elif [ -n "$lb_delegates" ]; then
  # It delegates. The delegate must do both of the things this case is about,
  # or the delegation is where the severity got lost.
  if [ -z "$defer_block" ]; then
    no "land() delegates its deferral to a function that does not exist" "defer_merge not found in $launcher"
  elif [ -n "$db_emits" ] && [ -z "$db_halt" ]; then
    ok "SOURCE: land()'s landability branch delegates to defer_merge(), which emits fleet.deferred and does not halt"
  else
    no "land() delegates, and the delegate halts or emits nothing" "$(printf '%s' "$defer_block" | grep -nE '^\s*halt |fleet.deferred' | head -3)"
  fi
else
  no "land()'s landability branch neither defers nor delegates" "$(printf '%s' "$land_block" | grep -nE 'halt |defer' | head -3)"
fi

# ---------------------------------------------------------------------------
# 12-13  Proofdelve ForgeOs-dx34.1's OWN VISIBILITY CASES (case 0 is the third).


# 12 THE VISIBILITY THE NARROWING OWES. Under it the queue drains into parked
# merges on a long dirty stretch, which is correct and must not have to be
# inferred from a column of tokens. parked_merges() counts deferred-merge
# workers and NOTHING else -- both directions asserted, because a counter that
# counts everything and a counter that counts nothing both look plausible.
pmcount() { # $1 state dir
  runsh <<EOF
set -uo pipefail
state='$1'; run_id=HARNESS; FLEET_LAUNCH_GRACE=120
say(){ :; }; warn(){ :; }
$(cat "$work/guard.sh")
worker_state(){ head -1 "\$1/state"; }
parked_merges
EOF
}
st="$work/state"; mkdir -p "$st/workers"/{a,b,c,d}
echo deferred-merge > "$st/workers/a/state"
echo deferred-merge > "$st/workers/b/state"
echo settled        > "$st/workers/c/state"
echo needs-person   > "$st/workers/d/state"
got=$(pmcount "$st")
if [ "$got" = 2 ]; then
  ok "parked_merges counts deferred-merge workers and nothing else (2 of 4)"
else no "parked_merges miscounts" "[$got], expected 2"; fi

# 13 and it must print A NUMBER AND NOTHING ELSE. Its stdout is its return value
# and both call sites do arithmetic on it; one stray diagnostic line there is a
# syntax error that kills the run and lets the EXIT trap record a clean drain
# for a crash (Proofdelve ForgeOs-0d0i, and live_forges() again on 2026-09-04).
st2="$work/state2"; mkdir -p "$st2/workers/x"; echo deferred-merge > "$st2/workers/x/state"
got=$(pmcount "$st2")
if [ "$(printf '%s' "$got" | wc -l)" -eq 0 ] && [ "$got" = 1 ]; then
  ok "parked_merges emits exactly one bare number on stdout"
else no "parked_merges wrote something other than a number" "[$got]"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ $fail -eq 0 ]
