#!/bin/bash
# Harness for fleet.sh's POST-MERGE VERIFICATION (ForgeOs-dx34.1, option (d)).
# Tests the SHIPPED postmerge_verify(), extracted from the real launcher, against
# real git worktrees and a stub verifier. Refuses on an incomplete extraction.
#
# WHY THIS EXISTS AS ITS OWN INSTRUMENT. The property option (d) buys is that
# the post-merge verifier scores THE MERGED COMMIT and not the shared checkout,
# and the only way to show that is to put content in the root that differs from
# the content in the commit and see which one the verifier was handed. That is
# ForgeOs-dx34.1's acceptance criterion 4 (the negative control) and criterion 5
# (that the fix did not buy immunity by making the gate blind), and cases 6 and
# 7 below are those two, executed, in that order.
#
# THE THREE-OUTCOME RULE (ForgeOs-8zb7). "It ran and main is red" and "it never
# ran" have opposite remedies, so every unrunnable case here also asserts that
# the verifier WAS NOT CALLED — the stub records its own invocations, and an
# unrunnable outcome that had silently run the verifier would pass on the token
# alone.
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

# CASE 0 RUNS BEFORE THE EXTRACTION GATE, DELIBERATELY. Every other case needs
# postmerge_verify(), which does not exist in the pre-fix launcher, so against
# that file this harness can only REFUSE — and a refusal proves less about the
# defect than a failure does (recorded 2026-09-08). This one case reads code
# that is present in BOTH files, so the pre-fix file scores a real FAIL here and
# only then is refused.
# --- 0  SOURCE: land() must branch on all four outcomes and must halt on
#        exactly one of them. Stated as a source assertion because land() cannot
#        be exercised without a real merge slot and a real bd; the behaviour
#        above is what is executed. THE PROPERTY IS "one halt, in the red arm",
#        not any particular wording (fortkit-or2.8: a control that pins a
#        spelling goes red for the next correct change).
# WHY THESE CHECKS DO NOT USE `grep -q` ON A PIPE (ForgeOs-g0ev, 2026-09-10).
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
land_block=$(awk '/^land\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{if(f) exit}' "$launcher")
halts=$(printf '%s' "$land_block" | grep -cE '^\s+halt ')
# HOISTED, NOT INLINE (ForgeOs-g0ev). Each grep runs ONCE, above the branch,
# and the branches test a plain variable. That satisfies SC2143 honestly
# rather than by silencing it, and keeps the property that matters: no -q,
# so grep reads all input and can never SIGPIPE the writer mid-flush.
pv_hit=$(printf '%s' "$land_block" | grep 'postmerge_verify ')
# THE THIRD SITE, MISSED BY 53c50a6 AND FOUND BY THE SAMPLE IT ASKED FOR
# (ForgeOs-g0ev, 2026-09-11: 1 red in 150 runs, output kept this time). The
# red-arm check below was `printf | awk '{print;exit}' | grep -q halt`: awk's
# `exit` on the first halt after `red)` closes the pipe while printf is still
# flushing the same 24KB block, 141, pipefail, the elif reads false, and the
# else reports "not in the red arm" with evidence showing it IS there. Rarer
# than case 0 because awk reads to the red arm before it can exit. No exit,
# no -q: awk reads all input, the variable is tested.
# The arm is `red|refused)` since ForgeOs-s1reg finding 4: a refused post-merge
# run halts too, through the SAME single halt call, with different words.
red_halt=$(printf '%s' "$land_block" | awk '/^    (red|red\|refused)\)/{f=1} f&&/^\s+halt /{print}')
if [ -z "$land_block" ]; then
  no "land() not found" "extraction empty"
elif [ -z "$pv_hit" ]; then
  no "land() does not call postmerge_verify" "it still verifies somewhere else"
elif [ "$halts" -ne 1 ]; then
  no "land() halts $halts times in its post-merge handling" "exactly one arm may halt"
elif [ -n "$red_halt" ]; then
  ok "SOURCE: land() branches on postmerge_verify() and halts in the red arm ALONE"
else
  no "land()'s single halt is not in the red arm" "$(printf '%s' "$land_block" | grep -nE '^\s+halt ')"
fi


awk '/^run_verifier\(\)[[:space:]]*\{/{f=1} /^postmerge_result=/{print; next} /^postmerge_tree=/{print; next} /^postmerge_verify\(\)[[:space:]]*\{/{f=1}
     /^unrunnable_why=/{print; next} /^verify_unrunnable\(\)[[:space:]]*\{/{f=1} f{print} /^\}$/{f=0}' \
  "$launcher" > "$work/pm.sh"
n=$(wc -l < "$work/pm.sh")
# REFUSE ON AN INCOMPLETE EXTRACTION, NAMING EACH SYMBOL. A harness that scores
# a pass on a function it did not load is the ForgeOs-8zb7 class C failure: it
# reports its own breakage as a defect in the subject. landable-harness.sh paid
# for this once already — a missing symbol made its vacuity control pass.
for sym in 'run_verifier()' 'postmerge_verify()' 'postmerge_result=' 'postmerge_tree='; do
  grep -qF "$sym" "$work/pm.sh" || { echo "HARNESS REFUSES: $sym not extracted from $launcher" >&2; exit 3; }
done
[ "$n" -ge 20 ] || { echo "HARNESS REFUSES: extracted $n lines" >&2; exit 3; }
# CONDITIONAL GATE (ForgeOs-s1reg finding 4): required only when the extracted
# code CALLS it, so this harness still runs, and fails, against an older file.
if grep -qE '(^|[^[:alnum:]_])verify_unrunnable ' "$work/pm.sh" && ! grep -q '^verify_unrunnable()' "$work/pm.sh"; then
  echo "HARNESS REFUSES: postmerge_verify() calls verify_unrunnable() and it was not extracted" >&2; exit 3
fi
echo "extracted $n lines of shipped post-merge code from $launcher"

# A real repo, with one file whose CONTENT is what the stub verifier judges.
# $2 is what gets committed; the root's working copy is dirtied separately.
mkrepo() { # $1 name, $2 committed content -> prints path
  local r="$work/$1"
  mkdir -p "$r/fort/scripts"
  git -C "$r" init -q -b main
  git -C "$r" config user.email h@h; git -C "$r" config user.name H
  printf '%s\n' "$2" > "$r/subject.txt"
  # THE STUB VERIFIER IS THE FORT'S OWN ENTRY POINT, because run_verifier() is
  # extracted verbatim and calls ./fort/scripts/verify.sh relative to the tree
  # it is given. It records WHERE it ran and WHETHER it ran at all, so an
  # unrunnable outcome can be told from a silent green.
  cat > "$r/fort/scripts/verify.sh" <<'V'
#!/bin/bash
printf '%s\n' "$PWD" >> "$VERIFY_CALLS"
grep -q POISON subject.txt && { echo "VERIFIER RED: subject.txt says POISON here"; exit 1; }
echo "VERIFIER GREEN in $PWD"
V
  chmod +x "$r/fort/scripts/verify.sh"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -qm base
  printf '%s' "$r"
}

# Run the shipped postmerge_verify() against a repo, with $root and $run_id
# overridden and signalled() stubbed to the value asked for.
pm() { # $1 repo, $2 sha, $3 signal ("" for none) -> prints result|tree
  bash -c "set -uo pipefail
    root='$1'; run_id=HARNESS; stop_signal='$3'
    signalled(){ [ -n \"\$stop_signal\" ]; }
    $(cat "$work/pm.sh")
    postmerge_verify BEAD-x '$2' '$1/vout.txt'
    printf '%s|%s\n' \"\$postmerge_result\" \"\$postmerge_tree\"" 2>&1
}
calls_for() { wc -l < "$1" 2>/dev/null || echo 0; }
trees_for()  { git -C "$1" worktree list | wc -l; }

# --- 1  VACUITY CONTROL. A clean merged commit must come back green, or every
#        refusal case below scores a pass against a function that refuses
#        everything.
r=$(mkrepo green ok); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
sha=$(git -C "$r" rev-parse HEAD); before=$(trees_for "$r")
out=$(pm "$r" "$sha" "")
if [ "${out%%|*}" = green ] && [ "$(calls_for "$r/calls")" -eq 1 ]; then
  ok "VACUITY CONTROL: a clean merged commit verifies GREEN and the verifier ran once"
else no "clean commit not green" "[$out] calls=$(calls_for "$r/calls")"; fi

# --- 2  GREEN REMOVES ITS WORKTREE. ~245 MB per merge otherwise, in a fort with
#        a measured 11 GB worktree problem (ForgeOs-mpaw).
if [ "${out#*|}" = "" ] && [ "$(trees_for "$r")" -eq "$before" ]; then
  ok "GREEN removes the worktree: no path is kept and the worktree count is back to $before"
else no "green kept a worktree" "tree=[${out#*|}] count $(trees_for "$r") vs $before"; fi

# --- 3  IT RAN IN THE WORKTREE, NOT IN THE ROOT. The whole point of option (d)
#        stated as a path assertion rather than inferred from a green.
ran_in=$(head -1 "$r/calls")
ran_in_hit=$(printf '%s' "$ran_in" | grep -- '-worktrees/postmerge-HARNESS-')
if [ "$ran_in" != "$r" ] && [ -n "$ran_in_hit" ]; then
  ok "the verifier ran in the post-merge worktree ($ran_in), NOT in \$root"
else no "verifier ran in the wrong tree" "$ran_in"; fi

# --- 4  RED KEEPS ITS WORKTREE AND NAMES IT. That is exactly when a person
#        wants the tree and exactly when an automatic cleanup would delete it.
r=$(mkrepo red POISON); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
sha=$(git -C "$r" rev-parse HEAD)
out=$(pm "$r" "$sha" "")
if [ "${out%%|*}" = red ] && [ -n "${out#*|}" ] && [ -d "${out#*|}" ]; then
  ok "RED keeps the worktree and names it (${out#*|})"; else no "red did not keep a named worktree" "[$out]"; fi

# --- 5  A SIGNAL IS NOT A RED MAIN. The verifier dies with the foreground
#        process group on Ctrl-C, and reading that status as a verdict would
#        halt the fleet over a build nobody was allowed to finish.
r=$(mkrepo sig POISON); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
sha=$(git -C "$r" rev-parse HEAD)
out=$(pm "$r" "$sha" "TERM")
if [ "${out%%|*}" = interrupted ]; then
  ok "a failing verifier UNDER A SIGNAL is 'interrupted', never 'red'"; else no "signal read as red" "[$out]"; fi

# ---------------------------------------------------------------------------
# 6 and 7 ARE ForgeOs-dx34.1'S TWO ACCEPTANCE CONTROLS, and they are a pair.
# Neither one alone can tell "the window is closed" from "the gate stopped
# looking", which is the entire reason criterion 5 exists.

# --- 6  CONTROL 1, THE NEGATIVE CONTROL. Dirty the ROOT with content that WOULD
#        fail the verifier, while the merged commit is clean. The verification
#        must come back GREEN: it scored the commit, not the directory. Before
#        option (d) this is precisely the case that halted the fleet and blamed
#        the merged work.
r=$(mkrepo dirtyroot ok); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
sha=$(git -C "$r" rev-parse HEAD)
printf 'POISON\n' > "$r/subject.txt"            # uncommitted, in the shared root
out=$(pm "$r" "$sha" "")
if [ "${out%%|*}" = green ]; then
  ok "CONTROL 1: a root dirtied DURING the window with verifier-failing content does not affect the result"
else no "CONTROL 1: root dirt reached the post-merge verification" "[$out] $(cat "$r/vout.txt" 2>/dev/null)"; fi

# --- 7  CONTROL 2, THE ONE MOST LIKELY TO BE DROPPED AS FUSSY. Same root dirt,
#        but this time the MERGED COMMIT itself carries the regression. It must
#        still come back RED. A change that buys immunity by making the gate
#        stop looking passes case 6 and fails this one.
r=$(mkrepo realregression POISON); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
sha=$(git -C "$r" rev-parse HEAD)
printf 'ok\n' > "$r/subject.txt"                # root is CLEANER than the commit
out=$(pm "$r" "$sha" "")
if [ "${out%%|*}" = red ]; then
  ok "CONTROL 2: a genuine regression IN THE MERGED COMMIT is still RED, even with a clean root"
else no "CONTROL 2: the post-merge gate went blind" "[$out]"; fi

# ---------------------------------------------------------------------------
# 8-10  THE THIRD OUTCOME. "Could not run" must be distinguishable from "ran and
# failed", and each case asserts the verifier was NOT CALLED — a token alone
# cannot tell a refusal from a silent run.

# --- 8  a sha that does not exist
r=$(mkrepo badsha ok); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
out=$(pm "$r" 0000000000000000000000000000000000000000 "")
if [ "${out%%|*}" = unrunnable ] && [ "$(calls_for "$r/calls")" -eq 0 ]; then
  ok "a commit that cannot be checked out is 'unrunnable', not 'red', and the verifier never ran"
else no "bad sha" "[$out] calls=$(calls_for "$r/calls")"; fi

# --- 9  an empty sha, which is what rev-parse failing looks like to the caller
r=$(mkrepo nosha ok); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
out=$(pm "$r" "" "")
if [ "${out%%|*}" = unrunnable ] && [ "$(calls_for "$r/calls")" -eq 0 ]; then
  ok "an unresolvable merged commit is 'unrunnable' and the verifier never ran"
else no "empty sha" "[$out] calls=$(calls_for "$r/calls")"; fi

# --- 10 THE DESTINATION IS NEVER CLOBBERED. A path already there may be a KEPT
#        tree from an earlier red verification, which is evidence.
r=$(mkrepo occupied ok); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
sha=$(git -C "$r" rev-parse HEAD)
mkdir -p "$r-worktrees/postmerge-HARNESS-x"; echo EVIDENCE > "$r-worktrees/postmerge-HARNESS-x/keep"
out=$(pm "$r" "$sha" "")
if [ "${out%%|*}" = unrunnable ] && [ "$(calls_for "$r/calls")" -eq 0 ] \
   && [ "$(cat "$r-worktrees/postmerge-HARNESS-x/keep")" = EVIDENCE ]; then
  ok "an occupied worktree path is 'unrunnable', is NOT clobbered, and the verifier never ran"
else no "occupied path" "[$out] calls=$(calls_for "$r/calls")"; fi


# --- s1reg-4  UNRUNNABLE IS NOT RED. Three verifier outputs that measured
#     nothing about the code come back `refused`, and a real step failure stays
#     `red` (the vacuity control: a classifier that called everything refused
#     would pass the first three alone).
mkstub() { # $1 name, $2 a line the stub prints on stderr ("" none), $3 exit code -> prints repo
  local r; r=$(mkrepo "$1" ok)
  # shellcheck disable=SC2016  # the stub's own $PWD and $VERIFY_CALLS expand when IT runs, not here
  printf '#!/bin/bash\nprintf "%%s\\n" "$PWD" >> "$VERIFY_CALLS"\n[ -n %q ] && printf "%%s\\n" %q >&2\nexit %s\n' "$2" "$2" "$3" > "$r/fort/scripts/verify.sh"
  git -C "$r" add -A >/dev/null; git -C "$r" commit -qm stub
  printf '%s' "$r"
}
for spec in "dockerdown|verify: step 'docker-precheck' FAILED (exit 1). Its full output is kept at /tmp/x|1|refused" \
            "wrongtree|verify: REFUSING TO RUN — WRONG TREE (ForgeOs-afdr). NOTHING WAS VERIFIED.|78|refused" \
            "harnessrefuses|verify: step 'forge-refresh-harness' FAILED (exit 3). Its full output is kept at /tmp/x|3|refused" \
            "realred|verify: step 'dotnet-test' FAILED (exit 1). Its full output is kept at /tmp/x|1|red"; do
  IFS='|' read -r name line code want <<< "$spec"
  r=$(mkstub "$name" "$line" "$code"); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
  out=$(pm "$r" "$(git -C "$r" rev-parse HEAD)" "")
  if [ "${out%%|*}" = "$want" ] && [ "$(calls_for "$VERIFY_CALLS")" -eq 1 ]; then ok "s1reg-4: $name (exit $code) -> $want"
  else no "s1reg-4: $name" "wanted $want, got '$out' calls=$(calls_for "$VERIFY_CALLS")"; fi
done
# RED, GENERATED: postmerge_verify() without the classifier must call the
# Docker-down run red -- so the dockerdown case above is the classifier.
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
sed 's/^  elif verify_unrunnable "\$vout" "\$vrc"; then postmerge_result=refused$/  elif false; then postmerge_result=refused/' "$work/pm.sh" > "$work/pm-noclass.sh"
if ! cmp -s "$work/pm.sh" "$work/pm-noclass.sh"; then
  cp "$work/pm.sh" "$work/pm-shipped.sh"; cp "$work/pm-noclass.sh" "$work/pm.sh"
  r=$(mkstub dockerdown2 "verify: step 'docker-precheck' FAILED (exit 1). x" 1); export VERIFY_CALLS="$r/calls"; : > "$VERIFY_CALLS"
  out=$(pm "$r" "$(git -C "$r" rev-parse HEAD)" "")
  cp "$work/pm-shipped.sh" "$work/pm.sh"
  if [ "${out%%|*}" = red ]; then ok "RED: without the classifier a Docker-down run reads RED -- the case above discriminates"
  else no "RED: no-classifier variant" "got '$out'"; fi
else no "RED: no-classifier variant" "could not be generated (sed matched nothing)"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ $fail -eq 0 ]
