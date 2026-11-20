#!/bin/bash
# Graph fixtures for Proofdelve ForgeOs-46xh. A zero-commit branch at an older mainline
# commit is CLAIMED-NO-WORK; branches at main's exact tip and live locks are
# silent; a fleet --no-ff landing remains MERGED-NOT-CLOSED.
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
sweep="${SWEEP_SH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/stranded-sweep.sh}"
real_python="$(command -v python3)" \
  || { echo "HARNESS REFUSES: could not ask python3 for its path" >&2; exit 3; }
[ -f "$sweep" ] || { echo "HARNESS REFUSES: $sweep does not exist" >&2; exit 3; }
if [ "${SWEEP_ALLOW_MISSING_DISCRIMINATOR:-0}" != 1 ]; then
  grep -q 'branch_tip_equals_main()' "$sweep" || { echo "HARNESS REFUSES: $sweep has no exact-tip discriminator" >&2; exit 3; }
  grep -q 'branch_tip_on_main_first_parent()' "$sweep" || { echo "HARNESS REFUSES: $sweep has no first-parent discriminator" >&2; exit 3; }
fi

work="$(mktemp -d)"
lockholders=()
trap 'kill "${lockholders[@]}" 2>/dev/null || true; reap_tagged; rm -rf "$work"' EXIT
if [ "${SWEEP_DISABLE_CLASSIFIER:-0}" = 1 ]; then
  # Negative control: remove the ahead>0 class selection from a disposable
  # copy. Fixture 6 must fail, proving its assertion reaches that classifier.
  disabled_sweep="$work/stranded-sweep-without-classifier.sh"
  cp -f "$sweep" "$disabled_sweep"
  # shellcheck disable=SC2016 # The quoted source must match the script literally.
  sed -i 's/if landable "$v"; then cls="STRANDED-REVIEWED    "; else cls="STRANDED-NOT-LANDABLE"; fi/cls="STRANDED-DISABLED     "/' "$disabled_sweep"
  cmp -s "$sweep" "$disabled_sweep" && { echo "HARNESS REFUSES: classifier line not found" >&2; exit 3; }
  sweep="$disabled_sweep"
fi
case "${SWEEP_MUTATION:-}" in
  '') ;;
  floor)
    disabled_sweep="$work/stranded-sweep-without-floor.sh"
    cp -f "$sweep" "$disabled_sweep"
    sed -i 's/if records < 10:/if False:/' "$disabled_sweep"
    cmp -s "$sweep" "$disabled_sweep" && { echo "HARNESS REFUSES: export floor line not found" >&2; exit 3; }
    sweep="$disabled_sweep"
    ;;
  export-map-rc)
    disabled_sweep="$work/stranded-sweep-without-export-map-rc.sh"
    cp -f "$sweep" "$disabled_sweep"
    sed -i 's/export_map_rc=$?/export_map_rc=0 # MUTATED: ignore python failure/' "$disabled_sweep"
    cmp -s "$sweep" "$disabled_sweep" && { echo "HARNESS REFUSES: export-map rc line not found" >&2; exit 3; }
    sweep="$disabled_sweep"
    ;;
  verdicts-rc)
    disabled_sweep="$work/stranded-sweep-without-verdicts-rc.sh"
    cp -f "$sweep" "$disabled_sweep"
    sed -i 's/verdicts_rc=$?/verdicts_rc=0 # MUTATED: ignore python failure/' "$disabled_sweep"
    cmp -s "$sweep" "$disabled_sweep" && { echo "HARNESS REFUSES: verdicts rc line not found" >&2; exit 3; }
    sweep="$disabled_sweep"
    ;;
  *) echo "HARNESS REFUSES: unknown SWEEP_MUTATION $SWEEP_MUTATION" >&2; exit 3 ;;
esac
repo="$work/repo"
g() { git -C "$repo" -c user.email=harness@example.test -c user.name=harness "$@"; }
commit() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" g commit -qm "$2"; }
git init -q -b main "$repo"
printf 'base\n' > "$repo/file"
g add file; commit '2023-11-14T22:13:21Z' base

# Fixture 1: a dead Forge's zero-commit branch remains at an older mainline
# commit while main advances. This is the cf5s shape.
g switch -q -c bead/refreshed
g switch -q main
printf 'main refresh\n' >> "$repo/file"
g add file; commit '2023-11-14T22:13:22Z' 'main refresh'

# Fixture 2: a fresh branch cut at main's tip prints nothing.
g branch bead/fresh-zero-commit

# Fixture 3: an accepted hand --ff landing at main's tip also prints nothing.
g switch -q -c bead/hand-ff-accepted-residual
printf 'hand ff landed\n' >> "$repo/file"
g add file; commit '2023-11-14T22:13:23Z' 'hand ff landed'
g switch -q main
g merge --ff-only -q bead/hand-ff-accepted-residual

# Fixture 4: a bead commit landed by the fleet's --no-ff merge; the bead is
# deliberately left in progress. Its tip is not on main's first-parent line.
g switch -q -c bead/landed
printf 'landed\n' >> "$repo/file"
g add file; commit '2023-11-14T22:13:25Z' landed
g switch -q main
GIT_AUTHOR_DATE='2023-11-14T22:13:27Z' GIT_COMMITTER_DATE='2023-11-14T22:13:27Z' g merge --no-ff -q bead/landed -m landed

# Fixture 5: a graph-shaped landing with a live Forge lock remains quiet.
g switch -q -c bead/live-locked
printf 'live locked\n' >> "$repo/file"
g add file; commit '2023-11-14T22:13:28Z' 'live locked'
g switch -q main
GIT_AUTHOR_DATE='2023-11-14T22:13:29Z' GIT_COMMITTER_DATE='2023-11-14T22:13:29Z' g merge --no-ff -q bead/live-locked -m 'live locked'
g worktree add -q "$work/live-locked" bead/live-locked
flock "$work/live-locked/.forge.lock" sleep 300 >/dev/null 2>&1 &
lockholders+=("$!")

# Fixtures 2 and 3 are live exact-tip shapes and must remain silent. Fixture 1
# deliberately stays at its older mainline commit.
g branch -f bead/fresh-zero-commit main
g branch -f bead/hand-ff-accepted-residual main

# Fixture 6: date before main's tip so fixture mode reaches the classifier.
g switch -q -c bead/unmerged
printf 'unmerged\n' >> "$repo/file"
g add file; commit '2023-11-14T22:13:26Z' unmerged
g switch -q main
mkdir -p "$repo/fort/events"
printf '%s\n' \
  '{"id":"fortkit-refreshed","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-fresh-zero-commit","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-hand-ff-accepted-residual","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-landed","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-live-locked","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-unmerged","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-graph-padding-1","status":"open"}' \
  '{"id":"fortkit-graph-padding-2","status":"open"}' \
  '{"id":"fortkit-graph-padding-3","status":"open"}' \
  '{"id":"fortkit-graph-padding-4","status":"open"}' > "$work/issues.jsonl"

out="$work/output"
bash "$sweep" --repo "$repo" --bd-export "$work/issues.jsonl" > "$out"
rc=$?
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() {
  local observed="${2:-}"
  [ -n "$observed" ] || observed="no output"
  echo "  FAIL  $1 -- $observed"
  fail=$((fail + 1))
}

# Keep this inventory alongside the fixture assertions.  It deliberately lists
# every first-column class the sweep can emit, including the two dynamic
# STRANDED values and the detached-worktree fact.  Both source emit sites and
# rendered fixture rows are checked against it: a class is not covered merely
# because a different emit site for the same class happens to be padded.
class_column_width=22
class_prefixes=(
  'CLAIMED-WORK-PRESENT  '
  'CLAIMED-NO-WORK       '
  'MERGED-NOT-CLOSED     '
  'ORPHAN-BRANCH         '
  'STRANDED-REVIEWED     '
  'STRANDED-NOT-LANDABLE '
  'SKIPPED-MIN-AGE       '
  'WORKTREE-DIRTY        '
  'DETACHED-HEAD         '
  'REAPABLE              '
)

class_prefix_for() {
  local class="$1" prefix
  for prefix in "${class_prefixes[@]}"; do
    if [ "${prefix%% *}" = "$class" ]; then
      printf '%s' "$prefix"
      return
    fi
  done
  return 1
}

# Validate every literal class printf and both dynamic cls assignments.  The
# latter gain printf's separator space, so their stored value is 21 columns.
assert_source_class_rows() {
  local lineno line class spaces prefix expected observed='' seen=''
  while IFS=: read -r lineno line; do
    [[ "$line" =~ printf\ \'([A-Z][A-Z-]*)([[:space:]]*)% ]] || continue
    class="${BASH_REMATCH[1]}"; spaces="${BASH_REMATCH[2]}"; prefix="$class$spaces"
    expected="$(class_prefix_for "$class")" || { observed="unknown class $class at $sweep:$lineno"; break; }
    [ "$prefix" = "$expected" ] || { observed="class $class at $sweep:$lineno is [${#prefix}] columns, expected [$class_column_width]"; break; }
    seen+=" $class "
  done < <(grep -nE "printf '[A-Z][A-Z-]* *%" "$sweep")
  if [ -z "$observed" ] && [ "${SWEEP_DISABLE_CLASSIFIER:-0}" != 1 ]; then
    while IFS= read -r assignment; do
      [[ "$assignment" =~ cls=\"([A-Z][A-Z-]*)([[:space:]]*)\" ]] || continue
      class="${BASH_REMATCH[1]}"; spaces="${BASH_REMATCH[2]}"; prefix="$class$spaces "
      expected="$(class_prefix_for "$class")" || { observed="unknown class $class in dynamic source assignment"; break; }
      [ "$prefix" = "$expected" ] || { observed="class $class in dynamic source assignment renders [${#prefix}] columns, expected [$class_column_width]"; break; }
      seen+=" $class "
    done < <(grep -oE 'cls="[A-Z][A-Z-]* *"' "$sweep")
  fi
  if [ -z "$observed" ]; then
    for expected in "${class_prefixes[@]}"; do
      class="${expected%% *}"
      if [ "${SWEEP_DISABLE_CLASSIFIER:-0}" = 1 ] && [[ "$class" == STRANDED-* ]]; then continue; fi
      [[ "$seen" == *" $class "* ]] || { observed="enumerated class $class has no source emit site"; break; }
    done
  fi
  if [ -z "$observed" ]; then
    ok "every source class emit is enumerated and exactly $class_column_width columns"
  else
    no "every source class emit is enumerated and exactly $class_column_width columns" "$observed"
  fi
}

# Check every class-shaped line across the fixture output files.  The target
# field makes this selective enough to ignore harness headings while detecting
# an unpadded new class (NEW-CLASSbead/...) as well as short and long padding.
assert_rendered_class_rows() {
  local file line class spaces prefix expected observed=''
  while IFS= read -r file; do
    # shellcheck disable=SC2094 # This loop only reads the fixture file; no command writes "$file".
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^([A-Z][A-Z-]*)([[:space:]]*)(bead/|DETACHED-HEAD[[:space:]]) ]] || continue
      class="${BASH_REMATCH[1]}"; spaces="${BASH_REMATCH[2]}"
      # The classifier negative-control child intentionally renders this
      # synthetic replacement; it is not an emit class of the real sweep.
      if [ "$class" = STRANDED-DISABLED ] && [[ "$file" == */inner-disabled.out ]]; then continue; fi
      expected="$(class_prefix_for "$class")" || { observed="unknown class $class in $file: $line"; break 2; }
      prefix="$class$spaces"
      [ "$prefix" = "$expected" ] || { observed="class $class in $file is [${#prefix}] columns, expected [$class_column_width]: $line"; break 2; }
    done < "$file"
  done < <(find "$work" -type f -name '*.out' -print | LC_ALL=C sort)
  if [ -z "$observed" ]; then
    ok "every rendered fixture class row is enumerated and exactly $class_column_width columns"
  else
    no "every rendered fixture class row is enumerated and exactly $class_column_width columns" "$observed"
  fi
}

case "${SWEEP_PREFIX_MUTATION:-}" in
  '') ;;
  short)
    disabled_sweep="$work/stranded-sweep-short-prefix.sh"
    cp -f "$sweep" "$disabled_sweep"
    sed -i 's/CLAIMED-WORK-PRESENT  %-24s/CLAIMED-WORK-PRESENT %-24s/' "$disabled_sweep"
    sweep="$disabled_sweep"
    ;;
  long)
    disabled_sweep="$work/stranded-sweep-long-prefix.sh"
    cp -f "$sweep" "$disabled_sweep"
    sed -i 's/CLAIMED-WORK-PRESENT  %-24s/CLAIMED-WORK-PRESENT   %-24s/' "$disabled_sweep"
    sweep="$disabled_sweep"
    ;;
  new-class)
    disabled_sweep="$work/stranded-sweep-new-class.sh"
    cp -f "$sweep" "$disabled_sweep"
    sed -i 's/CLAIMED-NO-WORK       %-24s/NEW-CLASS%-24s/' "$disabled_sweep"
    sweep="$disabled_sweep"
    ;;
  *) echo "HARNESS REFUSES: unknown SWEEP_PREFIX_MUTATION $SWEEP_PREFIX_MUTATION" >&2; exit 3 ;;
esac
case "${SWEEP_SOURCE_MUTATION:-}" in
  '') ;;
  source-only)
    # The source scanner deliberately recognizes this literal even though it is
    # commented out, while the sweep can never render it into a fixture.
    disabled_sweep="$work/stranded-sweep-source-only.sh"
    cp -f "$sweep" "$disabled_sweep"
    printf "\n# printf 'SOURCE-ONLY           %%s' ignored\n" >> "$disabled_sweep"
    sweep="$disabled_sweep"
    ;;
  *) echo "HARNESS REFUSES: unknown SWEEP_SOURCE_MUTATION $SWEEP_SOURCE_MUTATION" >&2; exit 3 ;;
esac

if [ "${SWEEP_DISABLE_SOURCE_CHECK:-0}" != 1 ]; then
  assert_source_class_rows
fi

if grep -q 'CLAIMED-NO-WORK.*bead/refreshed' "$out" && ! grep -q 'MERGED-NOT-CLOSED.*bead/refreshed' "$out"; then
  ok "older-mainline zero-commit branch is CLAIMED-NO-WORK, not MERGED-NOT-CLOSED"
else
  no "older-mainline zero-commit branch is CLAIMED-NO-WORK, not MERGED-NOT-CLOSED" "$(grep 'bead/refreshed' "$out")"
fi
if ! grep -q 'bead/fresh-zero-commit' "$out"; then
  ok "fresh zero-commit branch prints nothing"
else
  no "fresh zero-commit branch prints nothing" "$(grep 'bead/fresh-zero-commit' "$out")"
fi
if ! grep -q 'bead/hand-ff-accepted-residual' "$out"; then
  ok "accepted residual hand --ff landing prints nothing"
else
  no "accepted residual hand --ff landing prints nothing" "$(grep 'bead/hand-ff-accepted-residual' "$out")"
fi
if grep -q 'MERGED-NOT-CLOSED.*bead/landed' "$out"; then
  ok "landed --no-ff branch is MERGED-NOT-CLOSED"
else
  no "landed --no-ff branch is MERGED-NOT-CLOSED" "$(cat "$out")"
fi
if ! grep -q 'bead/live-locked' "$out"; then
  ok "live Forge lock suppresses MERGED-NOT-CLOSED"
else
  no "live Forge lock suppresses MERGED-NOT-CLOSED" "$(grep 'bead/live-locked' "$out")"
fi
if grep -q 'STRANDED-NOT-LANDABLE.*bead/unmerged' "$out"; then
  ok "dated unmerged branch is STRANDED-NOT-LANDABLE"
else
  no "dated unmerged branch is STRANDED-NOT-LANDABLE" "$(cat "$out")"
fi

# Dirty-tree fixtures for Proofdelve ForgeOs-w8iez. All three branches are zero-commit
# refs at an older mainline commit, so the graph classification is identical;
# only tracked worktree state may split their rendered remediation.
dirty_repo="$work/dirty-repo"; git init -q -b main "$dirty_repo"
dgit() { git -C "$dirty_repo" -c user.email=harness@example.test -c user.name=harness "$@"; }
dcommit() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" dgit commit -qm "$2"; }
printf 'base\n' > "$dirty_repo/tracked"; dgit add tracked; dcommit '2023-11-14T22:13:21Z' base
dgit branch bead/clean-tree
dgit branch bead/tracked-dirty
dgit branch bead/log-only
printf 'main advance\n' >> "$dirty_repo/tracked"; dgit add tracked; dcommit '2023-11-14T22:13:22Z' main-advance
dgit worktree add -q "$work/clean-tree" bead/clean-tree
dgit worktree add -q "$work/tracked-dirty" bead/tracked-dirty
dgit worktree add -q "$work/log-only" bead/log-only
printf 'uncommitted tracked change\n' >> "$work/tracked-dirty/tracked"
printf 'untracked verifier artifact\n' > "$work/log-only/verification-fixture.log"
mkdir -p "$dirty_repo/fort/events"
printf '%s\n' \
  '{"id":"fortkit-clean-tree","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-tracked-dirty","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-log-only","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-dirty-padding-1","status":"open"}' \
  '{"id":"fortkit-dirty-padding-2","status":"open"}' \
  '{"id":"fortkit-dirty-padding-3","status":"open"}' \
  '{"id":"fortkit-dirty-padding-4","status":"open"}' \
  '{"id":"fortkit-dirty-padding-5","status":"open"}' \
  '{"id":"fortkit-dirty-padding-6","status":"open"}' \
  '{"id":"fortkit-dirty-padding-7","status":"open"}' > "$work/dirty-issues.jsonl"
dirty_index="$(git -C "$work/tracked-dirty" rev-parse --git-path index)"
dirty_index_before="$(stat -c %y "$dirty_index")"
bash "$sweep" --repo "$dirty_repo" --bd-export "$work/dirty-issues.jsonl" > "$work/dirty.out"; dirty_rc=$?
dirty_index_after="$(stat -c %y "$dirty_index")"
clean_line="$(grep 'bead/clean-tree' "$work/dirty.out")"
tracked_line="$(grep 'bead/tracked-dirty' "$work/dirty.out")"
log_line="$(grep 'bead/log-only' "$work/dirty.out")"
tracked_prefix="${tracked_line:0:22}"
if [ "$dirty_rc" -eq 0 ] && [[ "$clean_line" == CLAIMED-NO-WORK* ]] && [[ "$clean_line" == *'CLEAN tracked=0'* ]]; then
  ok "clean worktree at mainline history is CLAIMED-NO-WORK with CLEAN tracked count"
else
  no "clean worktree at mainline history is CLAIMED-NO-WORK with CLEAN tracked count" "exit $dirty_rc; $clean_line"
fi
if [ "$dirty_rc" -eq 0 ] && [ "$tracked_prefix" = 'CLAIMED-WORK-PRESENT  ' ] && [[ "$tracked_line" == *'DIRTY tracked=1'* ]] \
  && [[ "$tracked_line" == *'preserve worktree'* ]] && [[ "$tracked_line" != *CLAIMED-NO-WORK* ]]; then
  ok "tracked dirty worktree has a 22-column CLAIMED-WORK-PRESENT prefix, is DIRTY counted, and never old CLAIMED-NO-WORK"
else
  no "tracked dirty worktree has a 22-column CLAIMED-WORK-PRESENT prefix, is DIRTY counted, and never old CLAIMED-NO-WORK" "exit $dirty_rc; prefix=[$tracked_prefix] line=$tracked_line"
fi
if [ "$dirty_rc" -eq 0 ] && [[ "$log_line" == CLAIMED-NO-WORK* ]] && [[ "$log_line" == *'CLEAN tracked=0'* ]]; then
  ok "untracked verification log alone is CLAIMED-NO-WORK with CLEAN tracked count"
else
  no "untracked verification log alone is CLAIMED-NO-WORK with CLEAN tracked count" "exit $dirty_rc; $log_line"
fi
if [ "$dirty_index_before" = "$dirty_index_after" ]; then
  ok "dirty sweep leaves the worktree index mtime unchanged"
else
  no "dirty sweep leaves the worktree index mtime unchanged" "before=$dirty_index_before after=$dirty_index_after"
fi

# Red arm: deliberately erase the dirty split from a disposable copy. The
# dirty fixture's assertion must go red, proving it does not merely coexist
# with an unused classifier branch.
old_sweep="$work/stranded-sweep-without-dirty-split.sh"
cp -f "$sweep" "$old_sweep"
# shellcheck disable=SC2016 # The quoted source must match the script literally.
sed -i 's/if \[\[ "\$tree_state" == DIRTY\* \]\]; then/if false; then/' "$old_sweep"
old_out="$work/old-dirty.out"
bash "$old_sweep" --repo "$dirty_repo" --bd-export "$work/dirty-issues.jsonl" > "$old_out"; old_rc=$?
old_tracked_line="$(grep 'bead/tracked-dirty' "$old_out")"
if [ "$old_rc" -eq 0 ] && [[ "$old_tracked_line" == CLAIMED-NO-WORK* ]] && [[ "$old_tracked_line" != CLAIMED-WORK-PRESENT* ]]; then
  ok "red arm: removing dirty split emits old CLAIMED-NO-WORK for tracked dirty fixture"
else
  no "red arm: removing dirty split emits old CLAIMED-NO-WORK for tracked dirty fixture" "exit $old_rc; $old_tracked_line"
fi

# Prefix-mutation children have exercised the inventory and dirty-tree rows;
# avoid recursively re-running unrelated harness controls.
if [ -n "${SWEEP_PREFIX_MUTATION:-}" ] || [ -n "${SWEEP_SOURCE_MUTATION:-}" ]; then
  if [ "${SWEEP_DISABLE_RENDERED_CHECK:-0}" != 1 ]; then
    assert_rendered_class_rows
  fi
  echo
  echo "RESULT $pass pass / $fail fail (sweep exit $rc)"
  [ "$fail" -eq 0 ]
  exit
fi

# Red arms prove both sides of the exact-width control and prove that an
# unlisted class row cannot slip past a list containing only today's classes.
# Each source arm asserts the class-specific detail it claims. A rendered-only
# arm has no corresponding source emit, so it isolates the rendered check.
if [ -z "${SWEEP_PREFIX_MUTATION:-}" ] && [ -z "${SWEEP_MUTATION:-}" ] \
   && [ -z "${SWEEP_RENDERED_MUTATION:-}" ] && [ "${SWEEP_DISABLE_CLASSIFIER:-0}" != 1 ] \
   && [ "${SWEEP_DISABLE_SOURCE_CHECK:-0}" != 1 ] && [ "${SWEEP_DISABLE_RENDERED_CHECK:-0}" != 1 ]; then
  for prefix_mutation in short long new-class; do
    inner="$work/inner-prefix-$prefix_mutation.out"
    SWEEP_PREFIX_MUTATION="$prefix_mutation" SWEEP_SH="$sweep" bash "${BASH_SOURCE[0]}" > "$inner" 2>&1
    inner_rc=$?
    case "$prefix_mutation" in
      short|long) expected_failure='every source class emit is enumerated and exactly 22 columns -- class CLAIMED-WORK-PRESENT' ;;
      new-class) expected_failure='every source class emit is enumerated and exactly 22 columns -- unknown class NEW-CLASS' ;;
    esac
    if [ "$inner_rc" -eq 1 ] && grep -Fq "  FAIL  $expected_failure" "$inner"; then
      ok "red arm: $prefix_mutation class prefix fails naming its class"
    else
      no "red arm: $prefix_mutation class prefix fails naming its class" \
        "inner exit $inner_rc; $(grep -E '^  FAIL|REFUSES' "$inner" | head -3 | tr '\n' ' ')"
    fi
  done

  inner="$work/inner-rendered-only.out"
  SWEEP_RENDERED_MUTATION=rendered-only SWEEP_SH="$sweep" bash "${BASH_SOURCE[0]}" > "$inner" 2>&1
  inner_rc=$?
  expected_failure='every rendered fixture class row is enumerated and exactly 22 columns -- unknown class RENDERED-ONLY'
  if [ "$inner_rc" -eq 1 ] && grep -Fq "  FAIL  $expected_failure" "$inner"; then
    ok "red arm: rendered-only class fails naming its class"
  else
    no "red arm: rendered-only class fails naming its class" "inner exit $inner_rc; $(grep -E '^  FAIL|REFUSES' "$inner" | head -3 | tr '\n' ' ')"
  fi

  inner="$work/inner-rendered-disabled.out"
  SWEEP_RENDERED_MUTATION=rendered-only SWEEP_DISABLE_RENDERED_CHECK=1 SWEEP_SH="$sweep" bash "${BASH_SOURCE[0]}" > "$inner" 2>&1
  inner_rc=$?
  if [ "$inner_rc" -eq 0 ] && ! grep -Fq "  FAIL  $expected_failure" "$inner"; then
    ok "negative control: disabling rendered check alone makes the rendered-only arm fail"
  else
    no "negative control: disabling rendered check alone makes the rendered-only arm fail" "inner exit $inner_rc; $(grep -E '^  FAIL|REFUSES' "$inner" | head -3 | tr '\n' ' ')"
  fi

  inner="$work/inner-source-disabled.out"
  SWEEP_SOURCE_MUTATION=source-only SWEEP_DISABLE_SOURCE_CHECK=1 SWEEP_SH="$sweep" bash "${BASH_SOURCE[0]}" > "$inner" 2>&1
  inner_rc=$?
  if [ "$inner_rc" -eq 0 ] && ! grep -Fq '  FAIL  every source class emit is enumerated' "$inner"; then
    ok "negative control: disabling source check alone makes source arms fail while rendered check passes"
  else
    no "negative control: disabling source check alone makes source arms fail while rendered check passes" "inner exit $inner_rc; $(grep -E '^  FAIL|REFUSES' "$inner" | head -3 | tr '\n' ' ')"
  fi

  inner="$work/inner-unrelated-failure.out"
  SWEEP_PREFIX_MUTATION=short SWEEP_DISABLE_SOURCE_CHECK=1 SWEEP_UNRELATED_FAILURE=1 SWEEP_SH="$sweep" bash "${BASH_SOURCE[0]}" > "$inner" 2>&1
  inner_rc=$?
  if [ "$inner_rc" -eq 1 ] && ! grep -Fq '  FAIL  every source class emit is enumerated and exactly 22 columns -- class CLAIMED-WORK-PRESENT' "$inner"; then
    ok "negative control: unrelated failure cannot credit a source arm"
  else
    no "negative control: unrelated failure cannot credit a source arm" "inner exit $inner_rc; $(grep -E '^  FAIL|REFUSES' "$inner" | head -3 | tr '\n' ' ')"
  fi
fi

# 6 NEGATIVE CONTROL, RUN BY THIS HARNESS ITSELF (Proofdelve ForgeOs-6qn1). Until
# 2026-09-16 the classifier removal at the top of this file ran only when a
# person set SWEEP_DISABLE_CLASSIFIER=1 by hand (measured on Proofdelve ForgeOs-m37a and
# again on l2wz), so the gate proved fixture 5 PASSES and never that it CAN
# FAIL. This re-runs the file once in disabled mode and scores the inner run
# as a case. The expectation is exact on purpose: inner exit 1 (a refusal is
# 3, a crash or a syntax error is anything else), the derived registered-fixture
# pass count / 1 fail, and the one failure is fixture 6 BY NAME. "Nonzero"
# would score a crash as a
# discrimination, which is the backwards wiring the bead warns about. The
# guard on SWEEP_DISABLE_CLASSIFIER is the recursion stop: the inner run has
# it set and never reaches here.
if [ "${SWEEP_DISABLE_CLASSIFIER:-0}" != 1 ] && [ -z "${SWEEP_MUTATION:-}" ] \
   && [ "${SWEEP_DISABLE_SOURCE_CHECK:-0}" != 1 ] && [ "${SWEEP_DISABLE_RENDERED_CHECK:-0}" != 1 ]; then
  inner="$work/inner-disabled.out"
  SWEEP_DISABLE_CLASSIFIER=1 SWEEP_SH="$sweep" bash "${BASH_SOURCE[0]}" > "$inner" 2>&1
  inner_rc=$?
  inner_pass=$(grep -c '^  PASS  ' "$inner")
  inner_fail=$(grep -c '^  FAIL  ' "$inner")
  # Explicit membership prevents fixture placement from silently changing this
  # child's arithmetic. Register any fixture that runs under
  # SWEEP_DISABLE_CLASSIFIER in exactly one bucket below.
  classifier_graph_fixtures=(refreshed fresh-zero-commit hand-ff landed live-locked)
  classifier_dirty_tree_fixtures=(clean-tree tracked-dirty log-only index-mtime dirty-split-red-arm)
  classifier_tracker_fixtures=(normal-export-absent export-enoent-refusal)
  classifier_reap_fixtures=(reap-tip reap-ff)
  # The disabled copy intentionally removes the two STRANDED assignments.
  # Its source and rendered inventory assertions remain after that removal.
  expected_inner_passes=$((${#classifier_graph_fixtures[@]} + ${#classifier_dirty_tree_fixtures[@]} + ${#classifier_tracker_fixtures[@]} + ${#classifier_reap_fixtures[@]} + 2))
  if [ "$inner_rc" -eq 1 ] && [ "$inner_pass" -eq "$expected_inner_passes" ] && [ "$inner_fail" -eq 1 ] \
     && grep -q '^  FAIL  dated unmerged branch is STRANDED-NOT-LANDABLE' "$inner"; then
    ok "negative control: with the classifier removed, fixture 6 alone goes red (inner exit 1, $expected_inner_passes pass / 1 fail)"
  else
    no "negative control: classifier removal was not detected as exactly fixture 6 failing" \
       "inner exit $inner_rc, $inner_pass pass / $inner_fail fail; $(grep -E '^  FAIL|REFUSES' "$inner" | head -3 | tr '\n' ' ')"
  fi
fi

# A missing id in a complete export is an absent tracker record; an export
# failure is a refusal, never an absent tracker record.
bd_repo="$work/bd-repo"; git init -q -b main "$bd_repo"
printf 'base\n' > "$bd_repo/file"
git -C "$bd_repo" -c user.email=harness@example.test -c user.name=harness add file
GIT_AUTHOR_DATE='2023-11-14T22:13:21Z' GIT_COMMITTER_DATE='2023-11-14T22:13:21Z' \
  git -C "$bd_repo" -c user.email=harness@example.test -c user.name=harness commit -qm base
git -C "$bd_repo" switch -q -c bead/candidate
printf 'candidate\n' >> "$bd_repo/file"
GIT_AUTHOR_DATE='2023-11-14T22:13:22Z' GIT_COMMITTER_DATE='2023-11-14T22:13:22Z' \
  git -C "$bd_repo" -c user.email=harness@example.test -c user.name=harness commit -qam candidate
git -C "$bd_repo" switch -q main
mkdir -p "$bd_repo/fort/events" "$work/bin"
cat > "$work/bin/bd" <<'SH'
#!/bin/bash
case "${BD_SHAPE:-absent}" in
  absent) for n in $(seq 1 10); do printf '{"id":"fortkit-unrelated-%s","status":"open","assignee":"kethra"}\n' "$n"; done ;;
  short) for n in $(seq 1 3); do printf '{"id":"fortkit-short-%s","status":"open","assignee":"kethra"}\n' "$n"; done ;;
  truncated)
    for n in $(seq 1 9); do printf '{"id":"fortkit-truncated-%s","status":"open","assignee":"kethra"}\n' "$n"; done
    printf '{"id":"fortkit-candidate","status":"in_progress"}\n'
    printf '{"id":"fortkit-half"\n'
    ;;
  enoent) echo "openat LOCK: no such file or directory" >&2; exit 1 ;;
esac
SH
chmod +x "$work/bin/bd"
PATH="$work/bin:$PATH" BD_SHAPE=absent bash "$sweep" --repo "$bd_repo" > "$work/absent.out" 2>"$work/absent.err"; absent_rc=$?
if [ "$absent_rc" -eq 0 ] && grep -q 'ORPHAN-BRANCH.*bead/candidate.*ABSENT-FROM-TRACKER' "$work/absent.out"; then
  ok "normal-mode newer branch is ORPHAN ABSENT with exit 0"
else
  no "normal-mode newer branch is ORPHAN ABSENT with exit 0" "exit $absent_rc; $(cat "$work/absent.out" "$work/absent.err")"
fi
PATH="$work/bin:$PATH" BD_SHAPE=enoent bash "$sweep" --repo "$bd_repo" > "$work/enoent.out" 2>"$work/enoent.err"; enoent_rc=$?
if [ "$enoent_rc" -eq 3 ] && grep -q 'SWEEP REFUSES: bd cannot export issues' "$work/enoent.err" && ! grep -q 'ABSENT-FROM-TRACKER' "$work/enoent.out"; then
  ok "ENOENT-shaped bd export failure refuses at exit 3"
else
  no "ENOENT-shaped bd export failure refuses at exit 3" "exit $enoent_rc; $(cat "$work/enoent.out" "$work/enoent.err")"
fi

# Regression controls for Proofdelve ForgeOs-4q03 and Proofdelve ForgeOs-71kb. They use normal mode
# through the fake bd so their assertions pin the rendered output, rather than
# merely observing an exit code in fixture mode.
if [ "${SWEEP_DISABLE_CLASSIFIER:-0}" != 1 ]; then
  PATH="$work/bin:$PATH" BD_SHAPE=short bash "$sweep" --repo "$bd_repo" > "$work/short.out" 2>"$work/short.err"; short_rc=$?
  if [ "$short_rc" -eq 3 ] && grep -q 'export has only 3 records (minimum 10)' "$work/short.err" \
    && ! grep -q 'ABSENT-FROM-TRACKER' "$work/short.out"; then
    ok "short well-formed normal export refuses at exit 3 rather than rendering absent beads"
  else
    no "short well-formed normal export refuses at exit 3 rather than rendering absent beads" "exit $short_rc; $(cat "$work/short.out" "$work/short.err")"
  fi

  PATH="$work/bin:$PATH" BD_SHAPE=truncated bash "$sweep" --repo "$bd_repo" > "$work/truncated.out" 2>"$work/truncated.err"; truncated_rc=$?
  if [ "$truncated_rc" -eq 3 ] && grep -q 'SWEEP REFUSES:' "$work/truncated.err" \
    && ! grep -q 'ABSENT-FROM-TRACKER' "$work/truncated.out"; then
    ok "truncated normal export refuses at exit 3 rather than rendering absent beads"
  else
    no "truncated normal export refuses at exit 3 rather than rendering absent beads" "exit $truncated_rc; $(cat "$work/truncated.out" "$work/truncated.err")"
  fi

  cat > "$work/bin/python3" <<SH
#!/bin/bash
if [[ "\$2" == */fort/events ]]; then exec "$real_python" "\$@"; fi
exit 42
SH
  chmod +x "$work/bin/python3"
  PATH="$work/bin:$PATH" BD_SHAPE=absent bash "$sweep" --repo "$bd_repo" > "$work/python-failed.out" 2>"$work/python-failed.err"; python_failed_rc=$?
  rm -f "$work/bin/python3"
  if [ "$python_failed_rc" -eq 3 ] && grep -q 'SWEEP REFUSES:' "$work/python-failed.err" \
    && ! grep -q 'bead=' "$work/python-failed.out"; then
    ok "python normal export-map failure refuses at exit 3 rather than rendering empty bead states"
  else
    no "python normal export-map failure refuses at exit 3 rather than rendering empty bead states" "exit $python_failed_rc; $(cat "$work/python-failed.out" "$work/python-failed.err")"
  fi

  cat > "$work/bin/python3" <<SH
#!/bin/bash
if [[ "\$2" == */fort/events ]]; then exit 42; fi
exec "$real_python" "\$@"
SH
  chmod +x "$work/bin/python3"
  PATH="$work/bin:$PATH" BD_SHAPE=absent bash "$sweep" --repo "$bd_repo" > "$work/verdict-failed.out" 2>"$work/verdict-failed.err"; verdict_failed_rc=$?
  rm -f "$work/bin/python3"
  if [ "$verdict_failed_rc" -eq 3 ] && grep -q 'could not read review verdicts' "$work/verdict-failed.err" \
    && ! grep -q 'verdict=none' "$work/verdict-failed.out"; then
    ok "verdict-map failure refuses at exit 3 rather than rendering verdict=none"
  else
    no "verdict-map failure refuses at exit 3 rather than rendering verdict=none" "exit $verdict_failed_rc; $(cat "$work/verdict-failed.out" "$work/verdict-failed.err")"
  fi

  # Each control below runs the assertion against a disposable sweep with its
  # guard removed. This proves the named rendered-output clause goes red, not
  # merely that the sweep's exit code changes.
  if [ -z "${SWEEP_MUTATION:-}" ]; then
  for mutation in floor export-map-rc verdicts-rc; do
    case "$mutation" in
      floor)
        expected='short well-formed normal export refuses at exit 3 rather than rendering absent beads'
        expected_fails=1
        ;;
      export-map-rc)
        # The parser and its fake-python failure both cross this one shared rc
        # gate. The short-export floor also reaches it after its Python error.
        expected='python normal export-map failure refuses at exit 3 rather than rendering empty bead states'
        companion='truncated normal export refuses at exit 3 rather than rendering absent beads'
        second_companion='short well-formed normal export refuses at exit 3 rather than rendering absent beads'
        expected_fails=3
        ;;
      verdicts-rc)
        expected='verdict-map failure refuses at exit 3 rather than rendering verdict=none'
        expected_fails=1
        ;;
    esac
    inner="$work/inner-$mutation.out"
    SWEEP_MUTATION="$mutation" SWEEP_SH="$sweep" bash "${BASH_SOURCE[0]}" > "$inner" 2>&1
    inner_rc=$?
    inner_fail=$(grep -c '^  FAIL  ' "$inner")
    if [ "$inner_rc" -eq 1 ] && [ "$inner_fail" -eq "$expected_fails" ] \
      && grep -Fq "  FAIL  $expected" "$inner" \
      && { [ "$mutation" != export-map-rc ] || { grep -Fq "  FAIL  $companion" "$inner" && grep -Fq "  FAIL  $second_companion" "$inner"; }; }; then
      ok "negative control: removing $mutation makes its named rendered-output assertion go red"
    else
      no "negative control: removing $mutation makes its named rendered-output assertion go red" \
        "inner exit $inner_rc, $inner_fail fail; $(grep -E '^  FAIL|REFUSES' "$inner" | head -3 | tr '\n' ' ')"
    fi
  done
  fi
fi

# The classifier negative-control child intentionally skips the age and merge
# order fixtures. Its derived registered-fixture assertion includes the graph and reaper cases.
if [ "${SWEEP_DISABLE_CLASSIFIER:-0}" != 1 ]; then
# Age fixtures use a future-dated main solely to let fixture mode reconstruct
# old and recent branch tips relative to one stable reference. Both branches
# are the same finding class; min-age must discriminate by evidence, not class.
age_repo="$work/age-repo"; git init -q -b main "$age_repo"
ag() { git -C "$age_repo" -c user.email=harness@example.test -c user.name=harness "$@"; }
age_commit() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" ag commit -qm "$2"; }
printf 'base\n' > "$age_repo/file"; ag add file; age_commit '2030-01-01T00:00:00Z' base
old_ts="$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
recent_ts="$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
ag switch -q -c bead/age-old; printf 'old\n' >> "$age_repo/file"; ag add file; age_commit "$old_ts" old
ag switch -q main; ag switch -q -c bead/age-recent; printf 'recent\n' >> "$age_repo/file"; ag add file; age_commit "$recent_ts" recent
ag switch -q main
mkdir -p "$age_repo/fort/events"
printf '%s\n' \
  '{"id":"fortkit-age-old","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-age-recent","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-verdict-recent","status":"in_progress","assignee":"kethra"}' \
  '{"id":"fortkit-age-padding-1","status":"open"}' \
  '{"id":"fortkit-age-padding-2","status":"open"}' \
  '{"id":"fortkit-age-padding-3","status":"open"}' \
  '{"id":"fortkit-age-padding-4","status":"open"}' \
  '{"id":"fortkit-age-padding-5","status":"open"}' \
  '{"id":"fortkit-age-padding-6","status":"open"}' \
  '{"id":"fortkit-age-padding-7","status":"open"}' > "$work/age-issues.jsonl"
ag switch -q -c bead/verdict-recent; printf 'verdict\n' >> "$age_repo/file"; ag add file; age_commit "$old_ts" verdict
ag switch -q main
printf '{"ts":"%s","category":"review.verdict","target":"fortkit-verdict-recent","detail":"APPROVE","payload":{"verdict":"APPROVE"}}\n' "$recent_ts" > "$age_repo/fort/events/events-age.jsonl"
bash "$sweep" --repo "$age_repo" --bd-export "$work/age-issues.jsonl" --min-age 30 > "$work/age-30.out"; age_30_rc=$?
bash "$sweep" --repo "$age_repo" --bd-export "$work/age-issues.jsonl" --min-age 0 > "$work/age-0.out"; age_0_rc=$?
bash "$sweep" --repo "$age_repo" --bd-export "$work/age-issues.jsonl" > "$work/age-default.out"; age_default_rc=$?
echo "AGE CONTROL --min-age 30"
cat "$work/age-30.out"
echo "AGE CONTROL --min-age 0"
cat "$work/age-0.out"
if [ "$age_30_rc" -eq 1 ] && grep -q 'STRANDED-NOT-LANDABLE.*bead/age-old' "$work/age-30.out" \
  && grep -q 'SKIPPED-MIN-AGE.*bead/age-recent' "$work/age-30.out" \
  && grep -q 'SKIPPED-MIN-AGE.*bead/verdict-recent' "$work/age-30.out"; then
  ok "min-age 30 examines old evidence and names recent tip and verdict skips"
else
  no "min-age 30 examines old evidence and names recent tip and verdict skips" "exit $age_30_rc; $(cat "$work/age-30.out")"
fi
if [ "$age_0_rc" -eq 1 ] && grep -q 'bead/age-old' "$work/age-0.out" \
  && grep -q 'bead/age-recent' "$work/age-0.out" \
  && grep -q 'bead/verdict-recent' "$work/age-0.out"; then
  ok "min-age 0 reports both same-class ages and recent verdict evidence"
else
  no "min-age 0 reports both same-class ages and recent verdict evidence" "exit $age_0_rc; $(cat "$work/age-0.out")"
fi
if [ "$age_default_rc" -eq "$age_0_rc" ] && cmp -s "$work/age-default.out" "$work/age-0.out"; then
  ok "flag absent is byte-identical to explicit disabled min-age 0"
else
  no "flag absent is byte-identical to explicit disabled min-age 0" "default exit $age_default_rc; zero exit $age_0_rc"
fi
# Red arm: deleting only the report leaves the classifier unfiltered, so this
# exact fixture must stop seeing its named younger branches as skips.
age_report_removed="$work/stranded-sweep-without-min-age-report.sh"
cp -f "$sweep" "$age_report_removed"
sed -i '/^report_if_too_young()/,/^}/s/  printf '\''SKIPPED-MIN-AGE/  return 1 # MUTATED: omit min-age skip report/' "$age_report_removed"
bash "$age_report_removed" --repo "$age_repo" --bd-export "$work/age-issues.jsonl" --min-age 30 > "$work/age-report-removed.out"; age_report_removed_rc=$?
if [ "$age_report_removed_rc" -eq 1 ] && ! grep -q 'SKIPPED-MIN-AGE.*bead/age-recent' "$work/age-report-removed.out" \
  && grep -q 'STRANDED-NOT-LANDABLE.*bead/age-recent' "$work/age-report-removed.out"; then
  ok "red arm: removing min-age reporting makes the younger-branch skip fixture fail"
else
  no "red arm: removing min-age reporting makes the younger-branch skip fixture fail" "exit $age_report_removed_rc; $(cat "$work/age-report-removed.out")"
fi
# A merged branch becomes MERGED-NOT-CLOSED when its no-ff merge lands, not
# when its older bead tip or verdict was recorded. There is no refresh commit.
ag switch -q -c bead/merge-recent; printf 'merged\n' >> "$age_repo/file"; ag add file; age_commit "$old_ts" merged
ag switch -q main
GIT_AUTHOR_DATE="$recent_ts" GIT_COMMITTER_DATE="$recent_ts" ag merge --no-ff -q bead/merge-recent -m merged
printf '%s\n' '{"id":"fortkit-merge-recent","status":"in_progress","assignee":"kethra"}' '{"id":"fortkit-merge-padding-1","status":"open"}' '{"id":"fortkit-merge-padding-2","status":"open"}' '{"id":"fortkit-merge-padding-3","status":"open"}' '{"id":"fortkit-merge-padding-4","status":"open"}' '{"id":"fortkit-merge-padding-5","status":"open"}' '{"id":"fortkit-merge-padding-6","status":"open"}' '{"id":"fortkit-merge-padding-7","status":"open"}' '{"id":"fortkit-merge-padding-8","status":"open"}' '{"id":"fortkit-merge-padding-9","status":"open"}' > "$work/merge-issues.jsonl"
bash "$sweep" --repo "$age_repo" --bd-export "$work/merge-issues.jsonl" --min-age 30 > "$work/merge-30.out" 2> "$work/merge-30.err"; merge_30_rc=$?
echo "MERGE-AGE CONTROL --min-age 30"
cat "$work/merge-30.out" "$work/merge-30.err"
if [ "$merge_30_rc" -eq 0 ] && grep -q 'SKIPPED-MIN-AGE.*bead/merge-recent' "$work/merge-30.out"; then
  ok "recent landing merge is named as a min-age skip without a refresh commit"
else
  no "recent landing merge is named as a min-age skip without a refresh commit" "exit $merge_30_rc; $(cat "$work/merge-30.out" "$work/merge-30.err")"
fi

# Malformed verdict time is an unmeasurable age gate, never a quiet suppression.
ag switch -q -c bead/bad-verdict-time; printf 'bad timestamp\n' >> "$age_repo/file"; ag add file; age_commit "$old_ts" bad-timestamp
ag switch -q main
printf '{"ts":"not-a-timestamp","category":"review.verdict","target":"fortkit-bad-verdict-time","detail":"APPROVE","payload":{"verdict":"APPROVE"}}\n' >> "$age_repo/fort/events/events-age.jsonl"
printf '%s\n' '{"id":"fortkit-bad-verdict-time","status":"in_progress","assignee":"kethra"}' '{"id":"fortkit-bad-padding-1","status":"open"}' '{"id":"fortkit-bad-padding-2","status":"open"}' '{"id":"fortkit-bad-padding-3","status":"open"}' '{"id":"fortkit-bad-padding-4","status":"open"}' '{"id":"fortkit-bad-padding-5","status":"open"}' '{"id":"fortkit-bad-padding-6","status":"open"}' '{"id":"fortkit-bad-padding-7","status":"open"}' '{"id":"fortkit-bad-padding-8","status":"open"}' '{"id":"fortkit-bad-padding-9","status":"open"}' > "$work/bad-verdict-issues.jsonl"
bash "$sweep" --repo "$age_repo" --bd-export "$work/bad-verdict-issues.jsonl" --min-age 30 > "$work/bad-verdict.out" 2> "$work/bad-verdict.err"; bad_verdict_rc=$?
echo "MALFORMED-VERDICT CONTROL --min-age 30"
cat "$work/bad-verdict.out" "$work/bad-verdict.err"
if [ "$bad_verdict_rc" -eq 3 ] && grep -q "could not parse review verdict timestamp 'not-a-timestamp'" "$work/bad-verdict.err"; then
  ok "malformed verdict timestamp refuses instead of suppressing a finding"
else
  no "malformed verdict timestamp refuses instead of suppressing a finding" "exit $bad_verdict_rc; $(cat "$work/bad-verdict.out" "$work/bad-verdict.err")"
fi

for leading_zero in 012 08; do
  leading_zero_err="$work/min-age-$leading_zero.err"
  bash "$sweep" --repo "$age_repo" --bd-export "$work/age-issues.jsonl" --min-age "$leading_zero" > /dev/null 2> "$leading_zero_err"; leading_zero_rc=$?
  if [ "$leading_zero_rc" -eq 2 ] && grep -q 'without leading zeroes' "$leading_zero_err"; then
    ok "leading-zero min-age $leading_zero is a usage error, not octal arithmetic"
  else
    no "leading-zero min-age $leading_zero is a usage error, not octal arithmetic" "exit $leading_zero_rc; $(cat "$leading_zero_err")"
  fi
done
validation_repo="$work/validation-repo"; git init -q -b main "$validation_repo"
git -C "$validation_repo" -c user.email=harness@example.test -c user.name=harness commit --allow-empty -qm base
for accepted_min_age in 0 5 12 30; do
  accepted_min_age_err="$work/min-age-$accepted_min_age.err"
  bash "$sweep" --repo "$validation_repo" --bd-export "$work/age-issues.jsonl" --min-age "$accepted_min_age" > /dev/null 2> "$accepted_min_age_err"; accepted_min_age_rc=$?
  if [ "$accepted_min_age_rc" -eq 0 ] && [ ! -s "$accepted_min_age_err" ]; then
    ok "plain min-age $accepted_min_age is accepted"
  else
    no "plain min-age $accepted_min_age is accepted" "exit $accepted_min_age_rc; $(cat "$accepted_min_age_err")"
  fi
done
trailing_min_age="$work/min-age-30x.err"
bash "$sweep" --repo "$validation_repo" --bd-export "$work/age-issues.jsonl" --min-age 30x > /dev/null 2> "$trailing_min_age"; trailing_min_age_rc=$?
if [ "$trailing_min_age_rc" -eq 2 ] && grep -q 'without leading zeroes' "$trailing_min_age"; then
  ok "trailing-garbage min-age 30x is a usage error"
else
  no "trailing-garbage min-age 30x is a usage error" "exit $trailing_min_age_rc; $(cat "$trailing_min_age")"
fi
bad_min_age="$work/bad-min-age.err"
bash "$sweep" --repo "$age_repo" --bd-export "$work/age-issues.jsonl" --min-age nope > /dev/null 2> "$bad_min_age"; bad_min_age_rc=$?
if [ "$bad_min_age_rc" -eq 2 ] && grep -q -- '--min-age must be a non-negative integer' "$bad_min_age"; then
  ok "non-integer min-age is usage error exit 2"
else
  no "non-integer min-age is usage error exit 2" "exit $bad_min_age_rc; $(cat "$bad_min_age")"
fi
fi

# Fast-forward landings have no merge commit. Both the exact-tip and older
# mainline forms use tip/verdict evidence, never a later unrelated merge.
reap_repo="$work/reap-repo"; git init -q -b main "$reap_repo"
rgit() { git -C "$reap_repo" -c user.email=harness@example.test -c user.name=harness "$@"; }
reap_commit() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" rgit commit -qm "$2"; }
old_reap_ts="$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
recent_reap_ts="$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
printf 'base\n' > "$reap_repo/file"; rgit add file; reap_commit "$old_reap_ts" base
rgit switch -q -c bead/reap-tip; printf 'tip\n' >> "$reap_repo/file"; rgit add file; reap_commit "$old_reap_ts" tip
rgit switch -q main; rgit merge --ff-only -q bead/reap-tip
rgit worktree add -q "$work/reap-tip" bead/reap-tip
mkdir -p "$reap_repo/fort/events"
printf '%s\n' '{"id":"fortkit-reap-tip","status":"closed"}' '{"id":"fortkit-reap-padding-1","status":"open"}' '{"id":"fortkit-reap-padding-2","status":"open"}' '{"id":"fortkit-reap-padding-3","status":"open"}' '{"id":"fortkit-reap-padding-4","status":"open"}' '{"id":"fortkit-reap-padding-5","status":"open"}' '{"id":"fortkit-reap-padding-6","status":"open"}' '{"id":"fortkit-reap-padding-7","status":"open"}' '{"id":"fortkit-reap-padding-8","status":"open"}' '{"id":"fortkit-reap-padding-9","status":"open"}' > "$work/reap-issues.jsonl"
bash "$sweep" --repo "$reap_repo" --bd-export "$work/reap-issues.jsonl" --reapable --min-age 30 > "$work/reap-tip.out" 2> "$work/reap-tip.err"; reap_tip_rc=$?
if [ "$reap_tip_rc" -eq 0 ] && grep -q 'REAPABLE.*bead/reap-tip' "$work/reap-tip.out"; then
  ok "tip-equals-main fast-forward landing is REAPABLE at min-age 30, not exit 3"
else
  reap_tip_observed="$(cat "$work/reap-tip.out" "$work/reap-tip.err")"
  no "tip-equals-main fast-forward landing is REAPABLE at min-age 30, not exit 3" "exit $reap_tip_rc; ${reap_tip_observed:-no output}"
fi
rgit switch -q -c bead/reap-ff; printf 'ff\n' >> "$reap_repo/file"; rgit add file; reap_commit "$old_reap_ts" ff
rgit switch -q main; rgit merge --ff-only -q bead/reap-ff
rgit switch -q -c bead/unrelated; printf 'unrelated\n' >> "$reap_repo/file"; rgit add file; reap_commit "$recent_reap_ts" unrelated
rgit switch -q main; GIT_AUTHOR_DATE="$recent_reap_ts" GIT_COMMITTER_DATE="$recent_reap_ts" rgit merge --no-ff -q bead/unrelated -m unrelated
rgit worktree add -q "$work/reap-ff" bead/reap-ff
printf '%s\n' '{"id":"fortkit-reap-ff","status":"closed"}' '{"id":"fortkit-reap-padding-1","status":"open"}' '{"id":"fortkit-reap-padding-2","status":"open"}' '{"id":"fortkit-reap-padding-3","status":"open"}' '{"id":"fortkit-reap-padding-4","status":"open"}' '{"id":"fortkit-reap-padding-5","status":"open"}' '{"id":"fortkit-reap-padding-6","status":"open"}' '{"id":"fortkit-reap-padding-7","status":"open"}' '{"id":"fortkit-reap-padding-8","status":"open"}' '{"id":"fortkit-reap-padding-9","status":"open"}' > "$work/reap-ff-issues.jsonl"
bash "$sweep" --repo "$reap_repo" --bd-export "$work/reap-ff-issues.jsonl" --reapable --min-age 30 > "$work/reap-ff.out" 2> "$work/reap-ff.err"; reap_ff_rc=$?
if [ "$reap_ff_rc" -eq 0 ] && grep -q 'REAPABLE.*bead/reap-ff' "$work/reap-ff.out"; then
  ok "older fast-forward landing does not adopt a later unrelated merge timestamp"
else
  reap_ff_observed="$(cat "$work/reap-ff.out" "$work/reap-ff.err")"
  no "older fast-forward landing does not adopt a later unrelated merge timestamp" "exit $reap_ff_rc; ${reap_ff_observed:-no output}"
fi

# The ancestry path includes later, unrelated merges whose branch was cut after
# this one landed. The first matching merge is the landing merge; newest-first
# would silently use that later merge and suppress this old finding.
if [ "${SWEEP_DISABLE_CLASSIFIER:-0}" != 1 ]; then
order_repo="$work/order-repo"; git init -q -b main "$order_repo"
ogit() { git -C "$order_repo" -c user.email=harness@example.test -c user.name=harness "$@"; }
order_commit() { GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" ogit commit -qm "$2"; }
old_order_ts="$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
recent_order_ts="$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
printf 'base\n' > "$order_repo/file"; ogit add file; order_commit "$old_order_ts" base
ogit switch -q -c bead/landed-old; printf 'old\n' >> "$order_repo/file"; ogit add file; order_commit "$old_order_ts" old
ogit switch -q main; GIT_AUTHOR_DATE="$old_order_ts" GIT_COMMITTER_DATE="$old_order_ts" ogit merge --no-ff -q bead/landed-old -m old
ogit switch -q -c bead/later-unrelated; printf 'later\n' >> "$order_repo/file"; ogit add file; order_commit "$recent_order_ts" later
ogit switch -q main; GIT_AUTHOR_DATE="$recent_order_ts" GIT_COMMITTER_DATE="$recent_order_ts" ogit merge --no-ff -q bead/later-unrelated -m later
mkdir -p "$order_repo/fort/events"
printf '%s\n' '{"id":"fortkit-landed-old","status":"in_progress","assignee":"kethra"}' '{"id":"fortkit-order-padding-1","status":"open"}' '{"id":"fortkit-order-padding-2","status":"open"}' '{"id":"fortkit-order-padding-3","status":"open"}' '{"id":"fortkit-order-padding-4","status":"open"}' '{"id":"fortkit-order-padding-5","status":"open"}' '{"id":"fortkit-order-padding-6","status":"open"}' '{"id":"fortkit-order-padding-7","status":"open"}' '{"id":"fortkit-order-padding-8","status":"open"}' '{"id":"fortkit-order-padding-9","status":"open"}' > "$work/order-issues.jsonl"
bash "$sweep" --repo "$order_repo" --bd-export "$work/order-issues.jsonl" --min-age 30 > "$work/order-30.out" 2> "$work/order-30.err"; order_30_rc=$?
echo "LANDING-MERGE ORDER PROBE --min-age 30"
cat "$work/order-30.out" "$work/order-30.err"
if [ "$order_30_rc" -eq 0 ] && grep -q 'MERGED-NOT-CLOSED.*bead/landed-old' "$work/order-30.out"; then
  ok "merged-class evidence is the branch's OWN landing merge, not a later unrelated one"
else
  no "merged-class evidence is the branch's OWN landing merge, not a later unrelated one" "exit $order_30_rc; $(cat "$work/order-30.out" "$work/order-30.err")"
fi
fi
if [ "${SWEEP_RENDERED_MUTATION:-}" = rendered-only ]; then
  printf 'RENDERED-ONLY         bead/rendered-only\n' > "$work/rendered-only.out"
fi
if [ "${SWEEP_DISABLE_RENDERED_CHECK:-0}" != 1 ]; then
  assert_rendered_class_rows
fi
if [ "${SWEEP_UNRELATED_FAILURE:-0}" = 1 ]; then
  no "unrelated injected harness failure"
fi
echo
echo "RESULT $pass pass / $fail fail (sweep exit $rc)"
[ "$fail" -eq 0 ]
