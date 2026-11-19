#!/bin/bash
# Harness for Proofdelve ForgeOs-6niaz, "review throughput" (Regent sitting 2026-11-11, the
# Overseer present; his approval is recorded on the bead). One section per part
# of the docket (fort/drafts/review-throughput-docket.md):
#   A  finding tiers: file_followup() files [bead] items, a polish-batch bead for
#      [polish] items, nothing for [record]-only; untagged counts as [bead].
#   B  FIX-FORWARD: the Warden's token, the fleet's routing to one bounded lap
#      in the same worktree, and the second one read as APPROVE-WITH-FINDINGS.
#   C  the Workbench session bead is filed with lands-on-review.
#   D  the Workbench offers to stack a new sitting on an unlanded one.
#   E  the Forge cites the launcher-stamped verify, never a dirty-tree self-run.
#
# IT TESTS THE SHIPPED CODE. Functions are extracted from the real launchers by
# name; the run-level half of B (a real lap through the real dispatcher) is
# scenario 6niaz in scripts/fleet-e2e-harness.sh, host-only like the rest of
# that file.
#
# RED ARMS. Every case is written to FAIL, not to refuse, against the launchers
# as they stood before this edict, so the same instrument scores both:
#   FLEET_SH=... WARDEN_SH=... WORKBENCH_SH=... FORGE_SH=... bash this-file
# with the pre-edict copies (git show fa19302f8:<path>) is the red arm, and the
# sitting's record carries both scores.
set -uo pipefail
here="$(dirname "$0")"
fleet="${FLEET_SH:-$here/../fort/scripts/fleet.sh}"
warden="${WARDEN_SH:-$here/../fort/scripts/warden.sh}"
workbench="${WORKBENCH_SH:-$here/../fort/scripts/workbench.sh}"
forge="${FORGE_SH:-$here/../fort/scripts/forge.sh}"
for f in "$fleet" "$warden" "$workbench" "$forge"; do
  [ -f "$f" ] || { echo "HARNESS REFUSES: subject is missing: $f" >&2; exit 3; }
done
printf 'fleet=%s\nwarden=%s\nworkbench=%s\nforge=%s\n' "$fleet" "$warden" "$workbench" "$forge"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }

# extract <file> <name>... : every named top-level function, whole. A name that
# is absent is simply absent, so a case calling it FAILS rather than the harness
# refusing: this instrument must score the pre-edict files too.
extract() {
  local file="$1"; shift
  local names="$*"
  awk -v names=" $names " '
    match($0, /^[A-Za-z_][A-Za-z0-9_]*\(\)/) {
      n = substr($0, 1, RLENGTH - 2)
      if (index(names, " " n " ")) { f = 1 }
    }
    f { print }
    f && /^\}/ { f = 0 }
  ' "$file"
}

# ---------------------------------------------------------------------------
echo "A. FINDING TIERS (fleet.sh file_followup)"
# The stub bd logs every call, prints a real id for create, and can refuse a
# create carrying a given label (to drive the close-gating branch).
mkdir -p "$work/bin"
cat > "$work/bin/bd" <<'B'
#!/bin/bash
args=("$@"); [ "${args[0]:-}" = -C ] && args=("${args[@]:2}")
a="${args[*]}"; printf '%s\n' "${a//$'\n'/ }" >> "$BD_LOG"   # one call per line
case "${args[0]:-}" in
  create)
    if [ -n "${BD_REFUSE_LABEL:-}" ] && printf '%s\n' "${args[@]}" | grep -qx -- "$BD_REFUSE_LABEL"; then exit 1; fi
    n=$(grep -c '^create' "$BD_LOG"); echo "Created issue: T-fu$n (task)" ;;
esac
B
chmod +x "$work/bin/bd"
extract "$fleet" tier_findings file_followup file_followup_tiered > "$work/ff.sh"
grep -q '^file_followup()' "$work/ff.sh" || { echo "HARNESS REFUSES: file_followup() is not in $fleet" >&2; exit 3; }

rec_tiered="$work/rec-tiered"
cat > "$rec_tiered" <<'R'
Warden review (the Warden, opus): VERDICT: APPROVE-WITH-FINDINGS
FINDINGS:
1. [bead] non-blocking: the retry path has no metric; worth its own bead.
2. [polish] non-blocking: the test name says 404 where it asserts 403.
3. **[polish]** non-blocking: a stale comment above DealAccess.Can
   still names the old field.
4. [record] non-blocking: I could not run the MigrationTests here.
END FINDINGS
Verified independently: the build. Taken on faith: nothing.
VERDICT-LINE: APPROVE-WITH-FINDINGS: done, four findings
R
rec_record="$work/rec-record"
printf 'Warden review (t): VERDICT: APPROVE-WITH-FINDINGS\nFINDINGS:\n1. [record] non-blocking: an observation.\n2. [record] non-blocking: a limit of the review.\nEND FINDINGS\nVERDICT-LINE: APPROVE-WITH-FINDINGS: x\n' > "$rec_record"
rec_untagged="$work/rec-untagged"
printf 'Warden review (t): VERDICT: APPROVE-WITH-FINDINGS\nFINDINGS:\n1. non-blocking: no tag on this one.\nEND FINDINGS\nVERDICT-LINE: APPROVE-WITH-FINDINGS: x\n' > "$rec_untagged"
rec_old="$work/rec-old"
printf 'Warden review (t): VERDICT: APPROVE-WITH-FINDINGS\n1. [polish] non-blocking: tags but no FINDINGS section.\nVERDICT-LINE: APPROVE-WITH-FINDINGS: x\n' > "$rec_old"

# ff <record> <outcome> [refuse-label] -> prints "ids|bead|none" and leaves the bd log at $work/bd.log
ff() {
  rm -f "$work/bd.log"; rm -rf "$work/state"; mkdir -p "$work/state/logs"
  PATH="$work/bin:$PATH" BD_LOG="$work/bd.log" BD_REFUSE_LABEL="${3:-}" bash -c '
    set -euo pipefail
    state="$1"; root=/nonexistent; fleet_actor=fleet
    say() { :; }
    source "$2"
    file_followup T-par "$4" "$3" "why one" "why two" "$4"
    printf "%s|%s|%s\n" "${followup_ids:-}" "${followup_bead:-}" "${followup_none:-0}"
  ' _ "$work/state" "$work/ff.sh" "$1" "$2"
}
creates() { if [ -f "$work/bd.log" ]; then grep -c '^create' "$work/bd.log"; else echo 0; fi; }

out="$(ff "$rec_tiered" APPROVE-WITH-FINDINGS)"
if [ "$(creates)" = 2 ] && [ "$(grep '^create' "$work/bd.log" | grep -c -- 'polish-batch')" = 1 ] \
   && grep '^create' "$work/bd.log" | grep -v polish-batch | grep -q 'retry path has no metric' \
   && ! grep '^create' "$work/bd.log" | grep -v polish-batch | grep -q 'test name says 404' \
   && grep '^create' "$work/bd.log" | grep polish-batch | grep -q 'test name says 404' \
   && grep '^create' "$work/bd.log" | grep polish-batch | grep -q 'still names the old field' \
   && ! grep -q 'could not run the MigrationTests' "$work/bd.log" \
   && ! grep '^create' "$work/bd.log" | grep -q fleet-safe \
   && [ "$out" = "T-fu1 T-fu2|T-fu1|0" ]; then
  ok "A1: [bead] item -> one follow-up; two [polish] items -> one polish-batch bead (not fleet-safe); [record] -> nothing"
else no "A1: tiered filing" "creates=$(creates) out=$out log=$(cut -c1-160 "$work/bd.log" 2>/dev/null | tr '\n' '|')"; fi

out="$(ff "$rec_record" APPROVE-WITH-FINDINGS)"
if [ "$(creates)" = 0 ] && [ "$out" = "||1" ]; then
  ok "A2: a review of only [record] findings files no bead and says so (followup_none=1)"
else no "A2: record-only" "creates=$(creates) out=$out"; fi

out="$(ff "$rec_untagged" APPROVE-WITH-FINDINGS)"
if [ "$(creates)" = 1 ] && ! grep -q polish-batch "$work/bd.log" && grep -q 'no tag on this one' "$work/bd.log" && [ "$out" = "T-fu1|T-fu1|0" ]; then
  ok "A3: an untagged finding is filed as [bead] (a missed tag fails safe)"
else no "A3: untagged" "creates=$(creates) out=$out"; fi

out="$(ff "$rec_old" APPROVE-WITH-FINDINGS)"
if [ "$(creates)" = 1 ] && grep -q 'Triage the findings' "$work/bd.log" && [ "${out#*|}" = "T-fu1|0" ]; then
  ok "A4: a review with no FINDINGS section is filed the old way, as one whole-review triage bead"
else no "A4: unparsed fallback" "creates=$(creates) out=$out"; fi

out="$(ff "$rec_tiered" MERGE-PARENT-OPEN)"
if [ "$(creates)" = 1 ] && grep -q 'Triage the findings' "$work/bd.log" && ! grep -q polish-batch "$work/bd.log"; then
  ok "A5: MERGE-PARENT-OPEN keeps its whole-review follow-up even when tagged (refinement a)"
else no "A5: MERGE-PARENT-OPEN" "creates=$(creates) out=$out"; fi

out="$(ff "$rec_tiered" APPROVE-WITH-FINDINGS polish-batch)"
if [ "${out#*|}" = "|0" ]; then
  ok "A6: when the polish-batch bead cannot be filed, followup_bead is empty, so the parent is NOT closed"
else no "A6: close gating" "out=$out"; fi

# A9: an indented numbered sub-list and a wrapped line beginning "3.5" belong to
# the finding above them (the Warden, 6niaz review finding 1).
rec_nested="$work/rec-nested"
cat > "$rec_nested" <<'R'
Warden review (t): VERDICT: APPROVE-WITH-FINDINGS
FINDINGS:
1. [record] non-blocking: two observations:
   1. the first sub-point
   2. the second sub-point
2. [polish] non-blocking: the retry waits
3.5 seconds before the second attempt, which the comment says is 3.
END FINDINGS
VERDICT-LINE: APPROVE-WITH-FINDINGS: x
R
out="$(ff "$rec_nested" APPROVE-WITH-FINDINGS)"
if [ "$(creates)" = 1 ] && grep -q polish-batch "$work/bd.log" && grep -q '3.5 seconds before the second attempt' "$work/bd.log" \
   && ! grep -q 'the first sub-point' "$work/bd.log"; then
  ok "A9: sub-points and a wrapped '3.5 seconds' stay inside their finding: one polish-batch bead carrying the whole item, nothing for the [record] finding"
else no "A9: nested numbering" "creates=$(creates) out=$out log=$(cut -c1-300 "$work/bd.log" 2>/dev/null)"; fi
# A10: a partial filing reports the bead that WAS filed (the Warden, finding 4).
out="$(ff "$rec_tiered" APPROVE-WITH-FINDINGS polish-batch)"
# shellcheck disable=SC2016  # the pattern names the launcher's own text, literally
if [ "${out%%|*}" = T-fu1 ] && grep -q 'lost="\$lost (partially filed: \$followup_ids' "$fleet"; then
  ok "A10: when the [bead] follow-up is filed and the polish-batch bead is not, the filed id is reported and land() names it and edges it"
else no "A10: partial filing" "out=$out"; fi

# A7: the caller in land() passes the outcome token, accepts a [record]-only
# review as owing nothing, and files an edge per filed bead. Read from source:
# land() is not extractable without the whole merge path.
# shellcheck disable=SC2016  # the patterns name the launcher's own text, literally
if grep -q '^    follow="\$followup_ids"$' "$fleet" \
   && grep -q '^    if \[ "\$followup_none" != 1 \] && \[ -z "\$followup_bead" \]; then$' "$fleet" \
   && grep -q '^    for fid in \$followup_ids; do$' "$fleet"; then
  ok "A7: land() takes followup_ids, closes on a [record]-only review, and files one edge per filed bead"
else no "A7: land() caller" "the tiered caller lines are not in $fleet"; fi

# A8: the Warden is told the tiers and the FINDINGS section.
if grep -q 'FINDING TIERS (Proofdelve ForgeOs-6niaz' "$warden" && grep -q "a line reading exactly 'FINDINGS:'" "$warden" \
   && grep -q 'An untagged non-blocking finding is filed as \[bead\]' "$warden"; then
  ok "A8: warden.sh tells the Warden the three tags, the FINDINGS section and the untagged rule"
else no "A8: warden prompt" "the tier paragraph is not in $warden"; fi

# ---------------------------------------------------------------------------
echo "B. FIX-FORWARD (warden.sh token, fleet.sh one bounded lap)"
# B1: the SHIPPED parse block, extracted whole and run over three lines.
awk '/^    case "\$verdict_line" in$/{f=1} f{print} f && /^    esac$/{exit}' "$warden" > "$work/parse.sh"
parse() { bash -c 'verdict_line="$1"; source "$2"; printf "%s" "$verdict"' _ "$1" "$work/parse.sh" 2>/dev/null; }
if [ -s "$work/parse.sh" ] && [ "$(parse 'FIX-FORWARD: two polish items')" = FIX-FORWARD ] \
   && [ "$(parse 'APPROVE-WITH-FINDINGS: x')" = APPROVE-WITH-FINDINGS ] && [ "$(parse 'APPROVE: x')" = APPROVE ] \
   && [ "$(parse 'MERGE-PARENT-OPEN: x')" = MERGE-PARENT-OPEN ]; then
  ok "B1: warden.sh parses FIX-FORWARD, and the existing tokens keep their meaning"
else no "B1: token parse" "FIX-FORWARD -> '$(parse 'FIX-FORWARD: x')'"; fi
# B2: matched before APPROVE, by position (the docket's rule for every case).
ffl=$(grep -n '^      FIX-FORWARD\*)' "$warden" | head -1 | cut -d: -f1)
apl=$(grep -n '^      APPROVE\*)' "$warden" | head -1 | cut -d: -f1)
if [ -n "$ffl" ] && [ -n "$apl" ] && [ "$ffl" -lt "$apl" ] && [ "$ffl" -lt "$(grep -n '^      APPROVE-WITH-FINDINGS\*)' "$warden" | head -1 | cut -d: -f1)" ]; then
  ok "B2: the FIX-FORWARD arm sits above both APPROVE arms"
else no "B2: arm order" "FIX-FORWARD at '${ffl:-absent}', APPROVE at '${apl:-absent}'"; fi
# B3: the prompt carries the token, its meaning, the six-token count and the
# re-check brief, and the re-check is gated on the fleet's two variables.
# shellcheck disable=SC2016  # the patterns name the launcher's own text, literally
if grep -q 'APPROVE-WITH-FINDINGS / FIX-FORWARD / MERGE-PARENT-OPEN' "$warden" && grep -q 'WHAT THE SIX TOKENS MEAN' "$warden" \
   && grep -q 'FIX-FORWARD: THE WORK IS DONE AND APPROVABLE' "$warden" \
   && grep -q '^  if \[ -n "\${WARDEN_FIX_FORWARD_BASE:-}" \] && \[ -s "\${WARDEN_FIX_FORWARD_ITEMS:-}" \]; then$' "$warden" \
   && grep -q 'FIX-FORWARD RE-CHECK -- from fleet.sh' "$warden"; then
  ok "B3: the Warden prompt defines FIX-FORWARD and carries the light re-check brief behind the fleet's variables"
else no "B3: warden prompt" "a FIX-FORWARD paragraph is missing from $warden"; fi

# The fleet half, extracted. land() and the state writers are stubbed and log
# what they were asked to do; bd is the stub above, with show answering labels.
extract "$fleet" tier_findings file_followup_tiered bead_has_label fix_forward_dir fix_forward_pending \
  fix_forward_recheck_done fix_forward worker_review_only bead_status > "$work/ffw.sh"
cat > "$work/bin/bd" <<'B'
#!/bin/bash
args=("$@"); [ "${args[0]:-}" = -C ] && args=("${args[@]:2}")
a="${args[*]}"; printf '%s\n' "${a//$'\n'/ }" >> "$BD_LOG"
case "${args[0]:-}" in
  show) [ "${BD_SHOW:-ok}" = fail ] && exit 1
        printf '{"id":"%s","status":"%s","labels":[%s]}\n' "${args[1]}" "${BD_STATUS:-in_progress}" "${BD_LABELS:-}" ;;
  create) n=$(grep -c '^create' "$BD_LOG"); echo "Created issue: T-fu$n (task)" ;;
esac
B
chmod +x "$work/bin/bd"
# ffw <record> <tip> [review-only] -> runs fix_forward; leaves $work/ffw.log (stub calls) and $work/bd.log
ffw() {
  rm -f "$work/ffw.log"; : > "$work/bd.log"; rm -rf "$work/state"; mkdir -p "$work/state/workers/par" "$work/state/logs"   # bd.log exists, so "no update" is a measurement (the Warden, finding 6)
  [ "${3:-}" = review-only ] && : > "$work/state/workers/par/review-only"
  [ "${PRESET_BASE:-}" = 1 ] && { mkdir -p "$work/state/fix-forward/par"; echo old > "$work/state/fix-forward/par/base"; }
  PATH="$work/bin:$PATH" BD_LOG="$work/bd.log" bash -c '
    set -euo pipefail
    state="$1"; calls="$3"; root=/nonexistent; fleet_actor=fleet; run_id=R
    say() { :; }
    emit() { printf "emit %s\n" "$1" >> "$calls"; }
    land() { printf "land %s %s\n" "$1" "$2" >> "$calls"; }
    worker_set_state() { printf "state %s\n" "$2" >> "$calls"; }
    bead_json() { bd -C "$root" show "$1" --json; }
    source "$2"
    fix_forward T-par /wt "$4" "$5"
    if fix_forward_pending par; then echo pending >> "$calls"; fix_forward_recheck_done par; fix_forward_pending par || echo rechecked >> "$calls"; fi
  ' _ "$work/state" "$work/ffw.sh" "$work/ffw.log" "$1" "$2"
}
rec_ff="$work/rec-ff"
cat > "$rec_ff" <<'R'
Warden review (the Warden, opus): VERDICT: FIX-FORWARD
FINDINGS:
1. [polish] non-blocking: rename shouldReturn404 to shouldReturn403.
2. [bead] non-blocking: add a metric to the retry path.
3. [record] non-blocking: MigrationTests not run here.
END FINDINGS
VERDICT-LINE: FIX-FORWARD: one polish item
R
BD_LABELS='"lands-on-review"' ffw "$rec_ff" abc123
if grep -q '^update T-par --status open --assignee  --add-label fix-forward-used' "$work/bd.log" \
   && ! grep -q 'fleet-return' "$work/bd.log" && ! grep -q '^land' "$work/ffw.log" 2>/dev/null \
   && grep -q 'shouldReturn403' "$work/state/fix-forward/par/brief" && [ "$(cat "$work/state/fix-forward/par/base")" = abc123 ] \
   && grep -q 'emit fleet.returned' "$work/ffw.log" && grep -q '^state settled' "$work/ffw.log"; then
  ok "B4: FIX-FORWARD queues ONE lap on the same branch: back to open, fix-forward-used, the brief carries the [polish] item, base = reviewed tip, no return spent, nothing landed"
else no "B4: the lap" "bd=$(tr '\n' '|' < "$work/bd.log" 2>/dev/null | cut -c1-300) calls=$(tr '\n' '|' < "$work/ffw.log" 2>/dev/null)"; fi
if grep '^create' "$work/bd.log" | grep -q 'add a metric to the retry path' && ! grep '^create' "$work/bd.log" | grep -q polish-batch \
   && ! grep -q 'MigrationTests not run' "$work/bd.log"; then
  ok "B5: the FIX-FORWARD review's [bead] items are filed at once; its [record] items are not"
else no "B5: [bead] items of a FIX-FORWARD review" "bd=$(grep '^create' "$work/bd.log" 2>/dev/null | cut -c1-200)"; fi
if grep -q '^pending$' "$work/ffw.log" && grep -q '^rechecked$' "$work/ffw.log"; then
  ok "B6: the lap is pending until a re-check records a verdict, and no longer after"
else no "B6: lap lifecycle" "$(tr '\n' '|' < "$work/ffw.log" 2>/dev/null)"; fi

BD_LABELS='"lands-on-review","fix-forward-used"' ffw "$rec_ff" abc123
if grep -q '^land T-par APPROVE-WITH-FINDINGS' "$work/ffw.log" && ! grep -q '^update' "$work/bd.log"; then
  ok "B7: AT MOST ONE LAP: a bead carrying fix-forward-used is read as APPROVE-WITH-FINDINGS"
else no "B7: the bound (label)" "calls=$(tr '\n' '|' < "$work/ffw.log" 2>/dev/null) bd=$(tr '\n' '|' < "$work/bd.log" | cut -c1-200)"; fi
PRESET_BASE=1 BD_LABELS='"lands-on-review"' ffw "$rec_ff" abc123
if grep -q '^land T-par APPROVE-WITH-FINDINGS' "$work/ffw.log" && ! grep -q '^update' "$work/bd.log"; then
  ok "B8: the bound holds on the fleet's own record too, even if the label write was lost"
else no "B8: the bound (base file)" "calls=$(tr '\n' '|' < "$work/ffw.log" 2>/dev/null)"; fi
# B8R: RED, GENERATED. The same extraction with the base-file half of the bound
# removed must queue a second lap when the label write was lost, or B8 cannot
# discriminate. (The label half cannot be removed alone: a bead whose label
# lookup says "present" then falls to the "bd would not say" branch, which also
# refuses a second lap. Two guards, and B7 passes on either.)
cp "$work/ffw.sh" "$work/ffw-good.sh"
# shellcheck disable=SC2016  # a sed PATTERN naming the launcher's own text, literally
sed 's/if \[ "\$hl" -eq 0 \] || \[ -e "\$d\/base" \]; then/if [ "$hl" -eq 0 ]; then/' "$work/ffw-good.sh" > "$work/ffw.sh"
if cmp -s "$work/ffw.sh" "$work/ffw-good.sh"; then
  no "B8R: RED variant" "the bound could not be removed (sed matched nothing)"
else
  PRESET_BASE=1 BD_LABELS='"lands-on-review"' ffw "$rec_ff" abc123
  if grep -q 'add-label fix-forward-used' "$work/bd.log"; then ok "B8R RED: without the base-file bound a second lap IS queued, so B8 discriminates"
  else no "B8R RED" "the unbounded variant still read the second FIX-FORWARD as APPROVE-WITH-FINDINGS"; fi
fi
cp "$work/ffw-good.sh" "$work/ffw.sh"
BD_LABELS='"lands-on-review"' ffw "$rec_ff" abc123 review-only
if grep -q '^land T-par APPROVE-WITH-FINDINGS' "$work/ffw.log" && ! grep -q '^update' "$work/bd.log"; then
  ok "B9: a Workbench session branch never gets a Forge lap: read as APPROVE-WITH-FINDINGS"
else no "B9: review-only" "calls=$(tr '\n' '|' < "$work/ffw.log" 2>/dev/null)"; fi
BD_LABELS='"lands-on-review"' ffw "$rec_record" abc123
if grep -q '^land T-par APPROVE-WITH-FINDINGS' "$work/ffw.log" && ! grep -q '^update' "$work/bd.log"; then
  ok "B10: a FIX-FORWARD with no [polish] item has nothing to bound a lap to: read as APPROVE-WITH-FINDINGS"
else no "B10: no polish items" "calls=$(tr '\n' '|' < "$work/ffw.log" 2>/dev/null)"; fi
BD_SHOW=fail ffw "$rec_ff" abc123
if grep -q '^land T-par APPROVE-WITH-FINDINGS' "$work/ffw.log" && ! grep -q '^update' "$work/bd.log"; then
  ok "B11: when bd cannot say whether the lap was spent, no second lap is risked"
else no "B11: bd unknown" "calls=$(tr '\n' '|' < "$work/ffw.log" 2>/dev/null)"; fi

BD_STATUS=closed BD_LABELS='"lands-on-review"' ffw "$rec_ff" abc123
if grep -q '^fix_forward()' "$work/ffw.sh" && ! grep -q '^update' "$work/bd.log" && ! grep -q '^land' "$work/ffw.log" 2>/dev/null && [ ! -e "$work/state/fix-forward/par/base" ]; then
  ok "B14: a bead closed under the review is not reopened for a lap: no write, no lap (the Warden, finding 5)"
else no "B14: closed bead" "bd=$(tr '\n' '|' < "$work/bd.log") calls=$(tr '\n' '|' < "$work/ffw.log" 2>/dev/null)"; fi

# B12: the routing in review_one(), the dispatch brief and the re-check env,
# read from source because those functions need the whole run around them.
# The run-level proof is scripts/fleet-e2e-harness.sh scenario 6niaz.
rv="$(awk '/^review_one\(\)/{f=1} f{print} f&&/^}/{exit}' "$fleet")"
# shellcheck disable=SC2016  # the patterns name the launcher's own text, literally
ffn=$(grep -n 'fix_forward "\$bead" "\$wt"' <<<"$rv" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016  # literal launcher text
lan=$(grep -n 'if verdict_is_landable "\$verdict"; then' <<<"$rv" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016  # the patterns name the launcher's own text, literally
if [ -n "$ffn" ] && [ -n "$lan" ] && [ "$ffn" -lt "$lan" ] && grep -q 'fix_forward_recheck_done "\$sfx"' <<<"$rv" \
   && grep -q 'env "\${ff_env\[@\]}" "\$root/fort/scripts/warden.sh"' <<<"$rv" \
   && grep -q 'FORGE_FIX_FORWARD_BRIEF="\$5" "\$1/fort/scripts/forge.sh"' "$fleet"; then
  ok "B12: review_one() routes FIX-FORWARD before any landable verdict, ends a pending lap on any verdict, and briefs the re-check; the dispatch briefs the lap"
else no "B12: routing" "fix_forward at '${ffn:-absent}', landable at '${lan:-absent}'"; fi
# B13: the Forge's lap brief.
# shellcheck disable=SC2016  # the patterns name the launcher's own text, literally
if grep -q 'FIX-FORWARD LAP -- from fleet.sh' "$forge" && grep -q '\$fix_forward_section"' "$forge" \
   && grep -q 'Fix EXACTLY those items and nothing else' "$forge"; then
  ok "B13: forge.sh briefs a lap with only the listed items when the fleet passes FORGE_FIX_FORWARD_BRIEF"
else no "B13: forge brief" "the lap section is not in $forge"; fi

# ---------------------------------------------------------------------------
echo "C. THE WORKBENCH SESSION BEAD'S LANDING CLASS (workbench.sh)"
extract "$workbench" workbench_actor wb_session_labels wb_create_session_bead wb_unlanded_branch wb_choose_base > "$work/wb.sh"
cat > "$work/bin/bd" <<'B'
#!/bin/bash
args=("$@"); [ "${args[0]:-}" = -C ] && args=("${args[@]:2}")
a="${args[*]}"; printf '%s\n' "${a//$'\n'/ }" >> "$BD_LOG"
case "${args[0]:-}" in
  create) echo '{"id":"T-wb1"}' ;;
  list) cat "$BD_LIST" ;;
esac
B
chmod +x "$work/bin/bd"
rm -f "$work/bd.log"
cid="$(PATH="$work/bin:$PATH" BD_LOG="$work/bd.log" bash -c 'source "$1"; wb_create_session_bead /repo' _ "$work/wb.sh" 2>/dev/null)"
if [ "$cid" = T-wb1 ] && grep -q '^create .* --labels workbench,lands-on-review ' "$work/bd.log"; then
  ok "C1: a new session bead is filed with workbench AND lands-on-review"
else no "C1: session bead labels" "id='$cid' log=$(cut -c1-300 "$work/bd.log" 2>/dev/null)"; fi
# shellcheck disable=SC2016  # the pattern names the launcher's own text, literally
if grep -q '^    bead="\$(wb_create_session_bead "\$REPO")"$' "$workbench" && ! grep -q -- '--labels workbench --actor' "$workbench"; then
  ok "C2: main() files the session bead through that function and nowhere else"
else no "C2: main() call site" "main() does not use wb_create_session_bead, or a bare 'workbench' label filing survives"; fi

# ---------------------------------------------------------------------------
echo "D. THE STACKING OFFER (workbench.sh)"
# A fixture repo: main; bead/old1 one commit ahead (unlanded); bead/old2 merged
# into main (landed); a child bead with no branch; and a closed sitting is never
# listed because the query asks for the open statuses only.
repo="$work/repo"; git init -q -b main "$repo"; git -C "$repo" config user.email h@h; git -C "$repo" config user.name H
echo base > "$repo/f"; git -C "$repo" add f; git -C "$repo" commit -qm base
git -C "$repo" branch bead/old2
git -C "$repo" checkout -qb bead/old1; echo one > "$repo/g"; git -C "$repo" add g; git -C "$repo" commit -qm "T-old1: work"; git -C "$repo" checkout -q main
printf '[{"id":"T-old2","status":"open"},{"id":"T-old1","status":"in_progress"},{"id":"T-old1.3","status":"open"}]\n' > "$work/list.json"
empty_list="$work/list-empty.json"; echo '[]' > "$empty_list"
wbrun() { # $1 function call, $2 stdin, $3 list file -> stdout; stderr to $work/wb.err
  printf '%s' "$2" | PATH="$work/bin:$PATH" BD_LOG="$work/bd.log" BD_LIST="${3:-$work/list.json}" bash -c 'source "$1"; '"$1" _ "$work/wb.sh" 2>"$work/wb.err"
}
if [ "$(wbrun "wb_unlanded_branch $repo" "")" = "T-old1 old1 1 in_progress" ]; then
  ok "D1: the unlanded earlier sitting is found (bead/old1, 1 ahead); a landed branch and a child bead are not"
else no "D1: candidate" "got '$(wbrun "wb_unlanded_branch $repo" "")'"; fi
printf '[{"id":"T-old2","status":"open"}]\n' > "$work/list-landed.json"
# The function must EXIST: an empty answer from a missing function is not a refusal.
if grep -q '^wb_unlanded_branch()' "$work/wb.sh" && [ -z "$(wbrun "wb_unlanded_branch $repo" "" "$work/list-landed.json")" ]; then
  ok "D1b: a sitting whose branch has landed (0 commits ahead) is never offered"
else no "D1b: landed branch" "got '$(wbrun "wb_unlanded_branch $repo" "" "$work/list-landed.json")'"; fi
if [ "$(wbrun "wb_choose_base $repo 0 1" $'\n')" = bead/old1 ] && grep -q 'has not landed: T-old1 on bead/old1 (status in_progress)' "$work/wb.err"; then
  ok "D2: at the prompt the default is YES, and the question names the earlier sitting's status: cut from bead/old1"
else no "D2: default yes" "got '$(wbrun "wb_choose_base $repo 0 1" $'\n')' err=$(tr '\n' '|' < "$work/wb.err")"; fi
if [ "$(wbrun "wb_choose_base $repo 0 1" $'n\n')" = main ]; then
  ok "D3: answering n cuts from main"
else no "D3: decline at the prompt" "got '$(wbrun "wb_choose_base $repo 0 1" $'n\n')'"; fi
if [ "$(wbrun "wb_choose_base $repo 1 1" "")" = main ] && grep -q -- '--from-main given' "$work/wb.err"; then
  ok "D4: --from-main declines the offer and says so"
else no "D4: --from-main" "got '$(wbrun "wb_choose_base $repo 1 1" "")'"; fi
if [ "$(wbrun "wb_choose_base $repo 0 0" "")" = main ] && grep -q 'no terminal to ask at' "$work/wb.err"; then
  ok "D5: with no terminal nothing stacks: cut from main, with a note (refinement c)"
else no "D5: non-interactive" "got '$(wbrun "wb_choose_base $repo 0 0" "")'"; fi
if [ "$(wbrun "wb_choose_base $repo 0 1" "" "$empty_list")" = main ] && [ ! -s "$work/wb.err" ]; then
  ok "D6: with no unlanded sitting there is no question at all"
else no "D6: no candidate" "err=$(tr '\n' '|' < "$work/wb.err")"; fi
# shellcheck disable=SC2016  # the patterns name the launcher's own text, literally
if grep -q '^    base="\$(wb_choose_base "\$REPO" "\$from_main" "\$interactive")"$' "$workbench" \
   && grep -q 'worktree add -q -b "bead/\$sfx" "\$wt" "\$base"' "$workbench" && grep -q 'if \[ "\${1:-}" = --from-main \]' "$workbench"; then
  ok "D7: main() asks before filing the bead, cuts the new branch from the chosen base, and parses --from-main"
else no "D7: main() wiring" "the stacking call sites are not in $workbench"; fi

# ---------------------------------------------------------------------------
echo "F. THE WORKBENCH BELTS (fleet.sh; the Overseer's ruling on the Warden's finding 2)"
extract "$fleet" sign_label gated_range_why stacked_held_why > "$work/belts.sh"
# F1: the gate-1 alternation is the same in both launchers, so the fleet's belt
# and the Warden's diff class cannot drift apart.
g1f="$(grep -m1 'bin/\*|civ/\*|templates/\*|schema/\*|skills/\*)' "$work/belts.sh" | sed 's/^ *//')"
g1w="$(grep -m1 'bin/\*|civ/\*|templates/\*|schema/\*|skills/\*)' "$warden" | sed 's/^ *//')"
if [ -n "$g1f" ] && [ "$g1f" = "$g1w" ]; then
  ok "F1: fleet.sh's gate-1 path list is byte-identical to warden.sh's diff-class list"
else no "F1: gate-1 parity" "fleet='${g1f:0:80}' warden='${g1w:0:80}'"; fi
# A fixture repo: main, and one branch per shape.
gr="$work/grepo"; git init -q -b main "$gr"; git -C "$gr" config user.email h@h; git -C "$gr" config user.name H
mkdir -p "$gr/web/src" "$gr/src/Product.Api" "$gr/fort/seats"; echo a > "$gr/web/src/a.ts"; git -C "$gr" add -A; git -C "$gr" commit -qm base
mkb() { # $1 branch, $2 base, $3 path, $4 content
  git -C "$gr" checkout -q -b "$1" "$2"; mkdir -p "$gr/$(dirname "$3")"; printf '%s\n' "$4" >> "$gr/$3"
  git -C "$gr" add -A; git -C "$gr" commit -qm "$1"; git -C "$gr" checkout -q main
}
mkb bead/g1 main bin/fort-init 'factory change'
mkb bead/g2 main fort/seats/x.md 'seat text'
mkb bead/g3 main web/src/b.ts 'export const ok = 1;'
mkb bead/g6 main fort/systemd/manyhalls-airlock-runner.service 'unit'
mkb bead/g7 main scripts/verify-impl.sh 'verifier'
grw() { bash -c 'root="$1"; main_branch=main; source "$2"; gated_range_why "$3"' _ "$gr" "$work/belts.sh" "$1" 2>/dev/null; }
if grw g1 | grep -q 'gate-1 surface' && grw g2 | grep -q 'gate 6' \
   && grw g6 | grep -q 'gate 6' && grw g7 | grep -q 'gate 6' \
   && [ -z "$(grw g3)" ] && grep -q '^gated_range_why()' "$work/belts.sh"; then
  ok "F2: belt 1 names the factory (gate 1) and constitution ranges (fort/systemd and the verifier included) as gated, and an ordinary source change as not"
else no "F2: gated_range_why" "g1='$(grw g1)' g2='$(grw g2)' g3='$(grw g3)' g6='$(grw g6)' g7='$(grw g7)'"; fi
# Belt 2. bead/h1 held by the ESCALATE route (human, never sign-to-land) and
# bead/s1 cut from it; bead/s2 from main; bead/n1 an unheld sitting and bead/s4
# cut from it; bead/h2 held and bead/s3 cut from it, then main moves and BOTH
# merge main in (Workbench rule 4), which is the criss-cross of the Warden's round-two
# finding 2.
mkb bead/h1 main web/src/h.ts 'held sitting'
mkb bead/s1 bead/h1 web/src/s.ts 'stacked sitting'
mkb bead/s2 main web/src/t.ts 'independent sitting'
mkb bead/n1 main web/src/n.ts 'unheld sitting'
mkb bead/s4 bead/n1 web/src/s4.ts 'stacked on an unheld sitting'
mkb bead/h2 main web/src/h2.ts 'held sitting two'
mkb bead/s3 bead/h2 web/src/s3.ts 'stacked on held sitting two'
echo m1 >> "$gr/web/src/a.ts"; git -C "$gr" commit -qam "main moves"
for b in bead/h2 bead/s3; do git -C "$gr" checkout -q "$b"; git -C "$gr" merge -q --no-edit main; done; git -C "$gr" checkout -q main
cat > "$work/bin/bd" <<'B'
#!/bin/bash
args=("$@"); [ "${args[0]:-}" = -C ] && args=("${args[@]:2}")
case "${args[0]:-}" in
  list) [ "${BD_LIST_FAIL:-}" = 1 ] && exit 1
        [ "${BD_LIST_MODE:-}" = garbage ] && { echo 'not json at all'; exit 0; }
        [ "${BD_LIST_MODE:-}" = nolabels ] && { echo '[{"id":"T-h1","status":"open"}]'; exit 0; }
        # HONOURS --label (all must match), as bd does, so a caller that filters
        # on a label the held sitting does not carry is measured missing it.
        want=(); for ((k=1;k<${#args[@]};k++)); do [ "${args[k]}" = --label ] && want+=("${args[k+1]}"); done
        printf '%s\n' 'T-h1 open workbench,lands-on-review,human' 'T-s1 in_progress workbench,lands-on-review' \
          'T-n1 open workbench,lands-on-review' 'T-h2 open workbench,lands-on-review,human' | python3 -c '
import json, sys
want = sys.argv[1:]
out = []
for line in sys.stdin.read().split("\n"):
    if not line.strip():
        continue
    i, s, l = line.split()
    labels = l.split(",")
    if all(w in labels for w in want):
        out.append({"id": i, "status": s, "labels": labels})
print(json.dumps(out))
' "${want[@]}" ;;
esac
B
chmod +x "$work/bin/bd"
shw() { PATH="$work/bin:$PATH" BD_LIST_FAIL="${2:-}" bash -c 'root="$1"; main_branch=main; source "$2"; stacked_held_why "$3"' _ "$gr" "$work/belts.sh" "$1" 2>/dev/null; }
r1="$(shw s1)"; r2="$(shw s2)"; shw s1 1 >/dev/null; r3=$?; r4="$(shw s4)"; r5="$(shw s3)"
xmb="$(git -C "$gr" merge-base bead/h2 bead/s3)"; xall="$(git -C "$gr" merge-base --all bead/h2 bead/s3 | wc -l)"
if [ "$r1" = "T-h1 (bead/h1)" ] && [ -z "$r2" ] && [ "$r3" -eq 2 ] && [ -z "$r4" ]; then
  ok "F3: belt 2 finds a sitting held by the ESCALATE route (human, no sign-to-land) that a stacked range shares commits with; ignores an independent range and one stacked on an UNHELD sitting; returns 2 when bd will not answer"
else no "F3: stacked_held_why" "s1='$r1' s2='$r2' s4='$r4' rc-on-bd-failure=$r3"; fi
if [ "$xall" -ge 2 ] && git -C "$gr" merge-base --is-ancestor "$xmb" main && [ "$r5" = "T-h2 (bead/h2)" ]; then
  ok "F3b: the criss-cross (both branches merged main, the single merge-base is a main commit) is still caught, through merge-base --all"
else no "F3b: criss-cross" "bases=$xall single=$xmb on-main=$(git -C "$gr" merge-base --is-ancestor "$xmb" main && echo yes || echo no) s3='$r5'"; fi
# F3c: the labels contract fails closed (round three, finding 5): output that
# does not parse, or a row without labels, is "bd will not say" (2), never
# "nothing held".
shm() { PATH="$work/bin:$PATH" BD_LIST_MODE="$2" bash -c 'root="$1"; main_branch=main; source "$2"; stacked_held_why "$3"' _ "$gr" "$work/belts.sh" "$1" >/dev/null 2>&1; }
shm s1 garbage; g=$?; shm s1 nolabels; nl=$?
if [ "$g" -eq 2 ] && [ "$nl" -eq 2 ]; then
  ok "F3c: unparseable list output and a row without labels both return 2, so the caller defers rather than landing"
else no "F3c: labels contract" "garbage rc=$g nolabels rc=$nl (want 2 and 2)"; fi
# F5: the belt-2 deferral saves the verdict before deferring (round two, finding 3).
lnd5="$(awk '/^land\(\)/{f=1} f{print} f&&/^}/{exit}' "$fleet")"
# shellcheck disable=SC2016  # literal launcher text
sv=$(grep -n 'printf .%s\\n. "\$verdict" > "\$wdir/verdict"' <<<"$lnd5" | head -1 | cut -d: -f1)
df=$(grep -n 'bd would not list the Workbench sittings held' <<<"$lnd5" | head -1 | cut -d: -f1)
if [ -n "$sv" ] && [ -n "$df" ] && [ "$sv" -lt "$df" ]; then
  ok "F5: the belt-2 deferral stores the verdict (and tip) before defer_merge, so its retry has a usable verdict"
else no "F5: belt-2 deferral" "verdict saved at '${sv:-absent}', deferral at '${df:-absent}'"; fi
# F4: land() runs both belts for a review-only worker, belt 2 first, before the
# signature hold, and never on a signed landing; read from source.
lnd="$(awk '/^land\(\)/{f=1} f{print} f&&/^}/{exit}' "$fleet")"
# shellcheck disable=SC2016  # literal launcher text, here and in the next three lines
b2=$(grep -n 'swhy="\$(stacked_held_why "\$sfx")"' <<<"$lnd" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016  # literal launcher text
b1=$(grep -n 'gwhy="\$(gated_range_why "\$sfx")"' <<<"$lnd" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016  # literal launcher text
ns=$(grep -n 'needs_signature "\$bead" || sig_rc' <<<"$lnd" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016  # literal launcher text
os=$(grep -n 'if \[ "\$verdict" != "OVERSEER-SIGNED" \]; then' <<<"$lnd" | head -1 | cut -d: -f1)
# shellcheck disable=SC2016  # literal launcher text
if [ -n "$b2" ] && [ -n "$b1" ] && [ -n "$ns" ] && [ -n "$os" ] && [ "$os" -lt "$b2" ] && [ "$b2" -lt "$b1" ] && [ "$b1" -lt "$ns" ] \
   && grep -q 'hold_for_signature "\$bead" "\$verdict" "\$record" "\$wdir" "\${4:-}" gated "\$gwhy"' <<<"$lnd"; then
  ok "F4: land() runs belt 2 then belt 1 for a review-only range, after the signed-landing exemption and before the label hold; belt 1 holds as gated"
else no "F4: land() wiring" "signed=$os belt2=$b2 belt1=$b1 needs_signature=$ns"; fi

# ---------------------------------------------------------------------------
echo "E. THE FORGE CITES THE STAMPED VERIFY (forge.sh)"
# The rule must sit INSIDE the handoff instruction, which is what reaches every
# non-smoke dispatch; a sentence anywhere else in the file reaches nobody.
hi="$(grep '^  handoff_instruction="' "$forge")"
# Proofdelve ForgeOs-gfuc1 (2026-11-13): the Forge no longer runs the gate, so "run it on
# the committed tip" became "say NONE-SEEN, or cite a stream event"; the
# property (never a self-run cited as the gate) is unchanged.
if grep -q 'CITE THE STAMP, NOT A SELF-RUN' <<<"$hi" && grep -q 'say NONE-SEEN (you do not run it)' <<<"$hi" \
   && grep -q 'your targeted run is reported as targeted, never as the gate' <<<"$hi" && grep -q 'Never cite a verify.sh run made on a tree with uncommitted changes' <<<"$hi"; then
  ok "E1: every non-smoke Forge prompt says: cite the stream's verify event or NONE-SEEN, the targeted run is never the gate, never a dirty-tree self-run"
else no "E1: forge prompt" "the citation rule is not in forge.sh's handoff instruction"; fi
forge_seat="$(dirname "$forge")/../seats/forge.md"
if [ -f "$forge_seat" ] && grep -q 'Cite the stamp, not a self-run' "$forge_seat"; then
  ok "E2: fort/seats/forge.md carries the same rule"
elif [ ! -f "$forge_seat" ]; then
  echo "  (E2 not applicable: no seats/forge.md beside $forge)"
else no "E2: forge seat file" "the rule is not in $forge_seat"; fi

echo "C. THE WARDEN'S EFFORT IS PINNED (docket 2026-11-13 item C(4))"
# Her session runs with --setting-sources "", so no user setting can supply an
# effort level; only a flag on her own claude line can.
wl="$(awk '/-- claude -p \\$/{f=1} f{print} f && /--add-dir/{exit}' "$warden")"
# shellcheck disable=SC2016  # literal launcher text
if grep -q -- '--setting-sources ""' <<<"$wl" && grep -q -- '--effort "\$warden_effort"' <<<"$wl" && grep -q '^warden_effort="\${WARDEN_EFFORT:-high}"$' "$warden"; then
  ok "C4: warden.sh's claude line carries --effort, defaulting to high, beside --setting-sources \"\""
else no "C4: warden effort" "$(tr '\n' '|' <<<"$wl" | cut -c1-200)"; fi

echo "RESULT $pass pass / $fail fail"
[ $fail -eq 0 ]
