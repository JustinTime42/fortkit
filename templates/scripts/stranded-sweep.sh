#!/bin/bash
# Stranded-unit sweeper (Proofdelve ForgeOs-p0a6, option b; Proofdelve ForgeOs-mpaw's reaper is the
# same join read the other way). REPORTS AND NEVER ACTS.
#
# The question, from bd and git rather than from fleet worker state: which
# beads are claimed or in progress, have a bead/* branch ahead of main, and are
# merged by nobody? Worker state only knows about work the fleet dispatched; the
# live specimen (Proofdelve ForgeOs-b0vj.12.11, stranded 2026-09-02 to 2026-09-08) was
# hand-dispatched and no dispatcher ever had a record of it.
#
# CLASSES, and why they are kept apart:
#   STRANDED-REVIEWED    bead open/in_progress, branch unmerged and ahead, and
#                        a LANDABLE verdict recorded (APPROVE,
#                        APPROVE-WITH-FINDINGS, MERGE-PARENT-OPEN). The sharp
#                        case: verified, reviewed, then merged by nobody.
#   STRANDED-NOT-LANDABLE same, with no landable verdict on record: never
#                        reviewed, or reviewed to ESCALATE / REQUEST-CHANGES
#                        (gated or returned).
#   ORPHAN-BRANCH        bead CLOSED, branch unmerged and ahead. Work closed
#                        without its branch landing, or superseded. Not stranded
#                        (nobody is waiting), but it is what a stranded unit
#                        becomes if someone closes the bead by hand.
#   CLAIMED-NO-WORK      bead open/in_progress, with a zero-commit branch at an
#                        older main commit, a CLEAN worktree, and no live Forge.
#                        It may be removed only after human review.
#   CLAIMED-WORK-PRESENT same graph shape, but its attached worktree has
#                        uncommitted tracked changes. Preserve the
#                        worktree; commit or hand it off, never remove it
#                        from this report.
#   MERGED-NOT-CLOSED    branch merged into main, bead still open/in_progress.
#                        The b0vj.23 halt shape; a person is waiting for
#                        nothing. Reported, not counted as stranded.
#   REAPABLE             (--reapable only) a bead worktree whose bead is closed
#                        and whose branch is merged. `worktree=` is its fourth
#                        whitespace field: scratch-reaper consumes that stable
#                        positional contract. Listed, never removed.
#   WORKTREE-DIRTY        attached bead worktree, or a detached worktree, with
#                        uncommitted tracked changes that graph classes do
#                        not otherwise print. Fact only: preserve for
#                        human assessment.
#   SKIPPED-MIN-AGE       (--min-age only) finding with newer tip, merge, or
#                        verdict evidence. Reported but never classified, and
#                        never affects the exit status. A deferred STRANDED unit
#                        is not counted until it ages past the threshold, so
#                        --min-age can change the exit status even though this
#                        line never does.
#   DETACHED-HEAD         detached worktree inventory entry. A clean
#                        entry proves it was inspected; a dirty one uses
#                        WORKTREE-DIRTY instead.
#
# STEADY STATE: no STRANDED-* lines, exit 0, nothing on stdout but
# ORPHAN-BRANCH, MERGED-NOT-CLOSED, CLAIMED-NO-WORK, CLAIMED-WORK-PRESENT,
# REAPABLE, WORKTREE-DIRTY, SKIPPED-MIN-AGE, and DETACHED-HEAD lines if any.
# CLAIMED-WORK-PRESENT asks for a person's look even on exit 0: preserve its
# worktree, then commit or hand it off (do not remove).
# Exit 1 when a STRANDED-* unit exists. Exit 3 when bd or git could not be
# asked, which is a REFUSAL and not a clean sweep (a broken sweeper also returns
# nothing; the exit status is how you tell them apart).
#
# WHICH bd SURFACES ARE TRUSTED, AND WHY (Proofdelve ForgeOs-l0e7, Proofdelve ForgeOs-p0a6 c5):
#   The candidate set comes from GIT, not from bd. The loop asks bd state about
#   EVERY bead/* branch (385 today), not only the 11 unmerged ones, because
#   merged branches can be MERGED-NOT-CLOSED, CLAIMED-NO-WORK, or REAPABLE.
#   It asks once with `bd export`, a complete dump that either produces every
#   issue or errors, then looks up exact ids in that fresh export. Unlike
#   `bd list --label-pattern`, it is not a filter and cannot fail open (357 of
#   357 for a nonsense pattern); `bd search` also misses titles. Verdicts come
#   from fort/events/*.jsonl review.verdict events, which warden.sh writes from
#   the transcript's VERDICT-LINE (Proofdelve ForgeOs-9mfw.5).
#
# FIXTURE MODE (the executed negative control, criterion 3):
#   --main <ref>          treat <ref> as main (history: --main ecb1162)
#   --bd-export <file>    read bead state from a JSONL export instead of bd
#                         (history: <(git show ecb1162:.beads/issues.jsonl))
#   --events-until <ts>   ignore review.verdict events after <ts> (ISO)
#   --min-age <minutes>   report, but do not classify, findings with newer
#                         evidence (default: 0, disabled)
#   --repo <dir>          repository to read (default: this one)
#   --reapable            also list REAPABLE worktrees
set -uo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main_ref="main"; bd_export=""; fixture_mode=0; events_until=""; min_age_minutes=0; reapable=0
while [ $# -gt 0 ]; do
  case "$1" in
    --main) main_ref="$2"; shift 2 ;;
    --bd-export) bd_export="$2"; fixture_mode=1; shift 2 ;;
    --events-until) events_until="$2"; shift 2 ;;
    --min-age)
      min_age_minutes="$2"
      [[ "$min_age_minutes" =~ ^(0|[1-9][0-9]*)$ ]] \
        || { echo "stranded-sweep: --min-age must be a non-negative integer number of minutes without leading zeroes" >&2; exit 2; }
      shift 2 ;;
    --repo) repo="$2"; shift 2 ;;
    --reapable) reapable=1; shift ;;
    -h|--help) sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "stranded-sweep: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

git -C "$repo" rev-parse --verify --quiet "$main_ref^{commit}" >/dev/null \
  || { echo "SWEEP REFUSES: '$main_ref' is not a commit in $repo" >&2; exit 3; }
main_ct=$(git -C "$repo" log -1 --format=%ct "$main_ref")
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
if [ -n "$bd_export" ]; then
  # Read it ONCE. A process substitution (<(git show ...)) is a pipe, and the
  # first per-bead read would drain it, leaving every later bead "absent".
  # Measured on the first run of this script against the ecb1162 fixture.
  cat "$bd_export" > "$work/export.jsonl" || { echo "SWEEP REFUSES: cannot read $bd_export" >&2; exit 3; }
  bd_export="$work/export.jsonl"
else
  # A fresh dump is trusted differently from a bd list filter: it contains all
  # issues or fails. Never substitute tracked .beads/issues.jsonl, which is a
  # deliberately stale passive export.
  bd -C "$repo" export > "$work/export.jsonl" \
    || { echo "SWEEP REFUSES: bd cannot export issues in $repo; not a clean sweep" >&2; exit 3; }
  bd_export="$work/export.jsonl"
fi

# A short export is not the board. Ten is deliberately well below the fort's
# normal issue count, but rejects the one-record "success" that previously
# turned every bead branch into an absent tracker record.
declare -A bead_status bead_assignee
export_map="$(python3 - "$bd_export" <<'PY'
import json
import sys

path = sys.argv[1]
records = 0
states = {}
try:
    with open(path, encoding="utf-8") as source:
        lines = source.readlines()
except OSError as exc:
    print("cannot read export: %s" % exc, file=sys.stderr)
    raise SystemExit(1)

if not lines:
    print("export is empty", file=sys.stderr)
    raise SystemExit(1)

for number, line in enumerate(lines, 1):
    try:
        record = json.loads(line)
    except json.JSONDecodeError as exc:
        print("export line %d is not valid JSON: %s" % (number, exc), file=sys.stderr)
        raise SystemExit(1)
    if not isinstance(record, dict):
        print("export line %d is not a JSON object" % number, file=sys.stderr)
        raise SystemExit(1)
    records += 1
    bead_id = record.get("id")
    status = record.get("status")
    if not isinstance(bead_id, str) or not bead_id or not isinstance(status, str) or not status:
        print("export line %d has no usable id and status" % number, file=sys.stderr)
        raise SystemExit(1)
    states[bead_id] = (status, record.get("assignee") or "")

if records < 10:
    print("export has only %d records (minimum 10)" % records, file=sys.stderr)
    raise SystemExit(1)

for bead_id, (status, assignee) in states.items():
    print("%s\t%s\t%s" % (bead_id, status, assignee))
PY
)"
export_map_rc=$?
[ "$export_map_rc" -eq 0 ] || {
  echo "SWEEP REFUSES: could not read a complete bead export (python3 failed, rc $export_map_rc); not a clean sweep" >&2
  exit 3
}
while IFS=$'\t' read -r bead_id loaded_status loaded_assignee; do
  [ -n "$bead_id" ] || continue
  bead_status["$bead_id"]="$loaded_status"
  bead_assignee["$bead_id"]="$loaded_assignee"
done <<< "$export_map"

state_of() {  # $1 bead id -> sets status/assignee; absent ids get an absent state
  if [ -v "bead_status[$1]" ]; then
    status="${bead_status[$1]}"
    assignee="${bead_assignee[$1]}"
  else
    status="absent"
    assignee=""
  fi
}

# Latest recorded verdict per bead from the event stream (landable or not).
verdicts="$(python3 - "$repo/fort/events" "$events_until" <<'PY'
import sys, json, glob, os
d, until = sys.argv[1], sys.argv[2]
latest = {}
for f in sorted(glob.glob(os.path.join(d, "events-*.jsonl"))):
    for line in open(f, encoding="utf-8"):
        try: e = json.loads(line)
        except ValueError: continue
        if e.get("category") != "review.verdict": continue
        if until and e.get("ts", "") > until: continue
        p = e.get("payload") or {}
        v = (p.get("verdict") or "").upper()
        if not v:
            # No payload.verdict (every event before 2026-09-03). Take the
            # EARLIEST token by position, never by a priority list: the Warden's
            # "ESCALATE ... merits APPROVE-WITH-FINDINGS, awaiting sign-off"
            # (Proofdelve ForgeOs-u65j.3) is a gate-6 hold, and a priority parse read it
            # as landable (the Warden, p0a6 finding 1). Uppercase first: the
            # 2026-08-03 payloads are lowercase.
            det = (e.get("detail") or "").upper()
            hits = [(det.find(tok), tok) for tok in ("MERGE-PARENT-OPEN", "APPROVE-WITH-FINDINGS", "REQUEST-CHANGES", "ESCALATE", "APPROVE") if det.find(tok) >= 0]
            # APPROVE inside APPROVE-WITH-FINDINGS starts at the same offset; the longer token wins a tie.
            hits.sort(key=lambda h: (h[0], -len(h[1])))
            v = hits[0][1] if hits else ""
        ts = e.get("ts", "")
        latest[e.get("target")] = "%s@%s\t%s" % (v or "unparsed", ts[:16], ts)
for k, v in latest.items(): print("%s\t%s" % (k, v))
PY
)"
verdicts_rc=$?
[ "$verdicts_rc" -eq 0 ] || {
  echo "SWEEP REFUSES: could not read review verdicts (python3 failed, rc $verdicts_rc); not a clean sweep" >&2
  exit 3
}
verdict_of() { printf '%s\n' "$verdicts" | awk -F'\t' -v b="$1" '$1==b{print $2}'; }
verdict_timestamp() { printf '%s\n' "$verdicts" | awk -F'\t' -v b="$1" '$1==b{print $3}'; }
landable() { case "$1" in APPROVE@*|APPROVE-WITH-FINDINGS@*|MERGE-PARENT-OPEN@*) return 0;; *) return 1;; esac; }

# A state may briefly be true while a normal merge is in progress. Unmerged
# findings use their latest tip/verdict evidence. A merged branch instead uses
# the mainline merge that made the finding true; its older tip and review are
# not evidence that the post-merge state has already settled.
merge_epoch_for_branch() {  # $1 branch ref -> committer epoch of its landing merge
  local merge parent index
  local -a record
  # The ancestry path contains only mainline commits after this branch tip.
  # A tip on main's first-parent line is an --ff/zero-commit shape, so callers
  # deliberately use unmerged evidence for it instead of borrowing a later,
  # unrelated landing merge.
  # Oldest-first is essential: a later branch refresh contains this tip too,
  # but its merge is unrelated and must never become this branch's evidence.
  # --no-commit-header leaves one SHA-and-parents record per line. Check every
  # non-first parent so an octopus landing retains the old loop's semantics.
  while read -r -a record; do
    merge="${record[0]}"
    for ((index = 2; index < ${#record[@]}; index++)); do
      parent="${record[index]}"
      git -C "$repo" merge-base --is-ancestor "$1" "$parent" 2>/dev/null || continue
      git -C "$repo" log -1 --format=%ct "$merge" 2>/dev/null
      return
    done
  done < <(git -C "$repo" rev-list --first-parent --ancestry-path --reverse --merges --no-commit-header --format='%H %P' "$1..$main_ref")
  return 1
}

finding_is_old_enough() {  # $1 branch ref, $2 bead id, $3 merged|unmerged
  [ "$min_age_minutes" -eq 0 ] && return 0
  local tip_epoch verdict_ts verdict_epoch evidence_epoch now_epoch
  if [ "$3" = merged ]; then
    evidence_epoch="$(merge_epoch_for_branch "$1")" || {
      echo "SWEEP REFUSES: could not determine landing merge for $1; not a clean sweep" >&2
      exit 3
    }
  else
    tip_epoch="$(git -C "$repo" log -1 --format=%ct "$1" 2>/dev/null)" || {
      echo "SWEEP REFUSES: could not read evidence commit for $1; not a clean sweep" >&2
      exit 3
    }
    verdict_ts="$(verdict_timestamp "$2")"
    verdict_epoch=0
    [ -z "$verdict_ts" ] || verdict_epoch="$(date -d "$verdict_ts" +%s 2>/dev/null)" || {
      echo "SWEEP REFUSES: could not parse review verdict timestamp '$verdict_ts' for $2; not a clean sweep" >&2
      exit 3
    }
    evidence_epoch="$tip_epoch"
    [ "$verdict_epoch" -gt "$evidence_epoch" ] && evidence_epoch="$verdict_epoch"
  fi
  now_epoch="$(date +%s)"
  [ $((now_epoch - evidence_epoch)) -ge $((min_age_minutes * 60)) ]
}

# A nonzero age threshold is a deliberate partial sweep, never a quiet one.
# Keep this outside the classifiers so each existing finding shape can state
# that it was inspected but deferred, without changing default output.
report_if_too_young() {  # $1 branch name, $2 ref, $3 bead id, $4 merged|unmerged
  [ "$min_age_minutes" -eq 0 ] && return 1
  finding_is_old_enough "$2" "$3" "$4" && return 1
  printf 'SKIPPED-MIN-AGE       %-24s %-14s threshold=%sm; newer %s evidence was inspected but not classified\n' \
    "$1" "$3" "$min_age_minutes" "$4"
  return 0
}

stranded=0
# The fleet lands beads with --no-ff. Its resulting merge commit has the main
# tip as first parent and the bead tip as second parent, so a landed bead tip
# is absent from main's first-parent line. A zero-commit bead ref remains on
# that line whether it is freshly created or fast-forward refreshed before
# re-dispatch. This graph discriminator does not depend on reflog retention.
branch_tip_equals_main() {  # $1 ref -> true iff it is exactly main's current tip
  [ "$(git -C "$repo" rev-parse "$1^{commit}" 2>/dev/null)" = "$(git -C "$repo" rev-parse "$main_ref^{commit}")" ]
}

branch_tip_on_main_first_parent() {  # $1 ref -> true iff its tip is a mainline commit
  local tip
  tip="$(git -C "$repo" rev-parse "$1^{commit}" 2>/dev/null)" || return 1
  # Do not use grep -q here: under pipefail it can close early, make rev-list
  # die on SIGPIPE, and turn a mainline tip into a false negative on long refs.
  git -C "$repo" rev-list --first-parent "$main_ref" | grep -Fx "$tip" >/dev/null
}

branch_has_live_forge_lock() {  # $1 ref -> true iff its worktree holds .forge.lock
  local wt lock
  while read -r wt; do
    [ -f "$wt/.forge.lock" ] || continue
    lock="$wt/.forge.lock"
    flock -n "$lock" -c ':' 2>/dev/null || return 0
  done < <(git -C "$repo" worktree list --porcelain | awk -v want="$1" '
    /^worktree / { wt=substr($0, 10) }
    /^branch / { if (substr($0, 8) == want) print wt }
  ')
  return 1
}

# `git status` can refresh the index, so force optional locks off before asking
# it for tracked changes. A report must not alter the worktree it measures.
# `--untracked-files=no` excludes verification-*.log artifacts and every other
# untracked run byproduct from this safety classification.
declare -A branch_worktree
declare -a detached_worktrees
while IFS=$'\t' read -r wt_ref wt_path; do
  [ -n "$wt_ref" ] || continue
  branch_worktree["$wt_ref"]="$wt_path"
done < <(git -C "$repo" worktree list --porcelain | awk '
  /^worktree / { wt=substr($0, 10) }
  /^branch / { print substr($0, 8) "\t" wt }
')
while read -r wt_path; do
  [ -n "$wt_path" ] || continue
  detached_worktrees+=("$wt_path")
done < <(git -C "$repo" worktree list --porcelain | awk '
  /^worktree / { wt=substr($0, 10) }
  /^detached$/ { print wt }
')

tracked_tree_state() {  # $1 ref -> prints CLEAN/0 or DIRTY/count, then worktree path
  local ref="$1" wt count
  wt="${branch_worktree[$ref]:-}"
  if [ -z "$wt" ]; then
    printf 'CLEAN tracked=0 worktree=none'
    return
  fi
  count="$(GIT_OPTIONAL_LOCKS=0 git -C "$wt" status --porcelain --untracked-files=no | wc -l)" || return 1
  if [ "$count" -gt 0 ]; then
    printf 'DIRTY tracked=%s worktree=%s' "$count" "$wt"
  else
    printf 'CLEAN tracked=0 worktree=%s' "$wt"
  fi
}

while read -r ref; do
  [ -n "$ref" ] || continue
  branch="${ref#refs/heads/}"; id="{{BEAD_PREFIX}}-${branch#bead/}"
  ahead=$(git -C "$repo" rev-list --count "$main_ref..$ref" 2>/dev/null || echo "?")
  if [ "$ahead" = "0" ]; then
    # THE MIRROR CASE (the Warden, p0a6 finding 6): branch merged, bead still open or
    # in_progress. The b0vj.23 halt shape: landed, and nobody closed it. Not
    # stranded (the work is on main) but a person is waiting for nothing.
    # A newly cut branch is exactly main's tip. It is live work, not landed
    # work, so keep the report quiet. A held Forge lock likewise wins over a
    # graph-shaped landing while that Forge is still running.
    if branch_tip_equals_main "$ref" || branch_has_live_forge_lock "$ref"; then continue; fi
    state_of "$id"
    case "$status" in
      open|in_progress)
        # CLAIMED-NO-WORK has no landing merge. It deliberately keeps the
        # latest tip/verdict evidence; its true transition is the first
        # mainline commit after the tip, which is a different query.
        if branch_tip_on_main_first_parent "$ref"; then
          tip_on_main_first_parent=1
          age_kind=unmerged
        else
          tip_on_main_first_parent=0
          age_kind=merged
        fi
        if report_if_too_young "$branch" "$ref" "$id" "$age_kind"; then continue; fi
        if [ "$tip_on_main_first_parent" -eq 1 ]; then
          tree_state="$(tracked_tree_state "$ref")" || {
            echo "SWEEP REFUSES: could not inspect tracked changes for $branch; not a clean sweep" >&2
            exit 3
          }
          if [[ "$tree_state" == DIRTY* ]]; then
            printf 'CLAIMED-WORK-PRESENT  %-24s %-14s zero commits off %s, bead=%s assignee=%s %s; preserve worktree, commit or hand off (do not remove)\n' "$branch" "$id" "$main_ref" "$status" "${assignee:-none}" "$tree_state"
          else
            printf 'CLAIMED-NO-WORK       %-24s %-14s zero commits off %s, bead=%s assignee=%s %s; review before removal\n' "$branch" "$id" "$main_ref" "$status" "${assignee:-none}" "$tree_state"
          fi
        else
          # A MERGE-PARENT-OPEN verdict makes this state deliberate (diff landed,
          # remainder re-queued); print the verdict so the reader can tell.
          v="$(verdict_of "$id")"; [ -n "$v" ] || v="none"
          tree_state="$(tracked_tree_state "$ref")" || { echo "SWEEP REFUSES: could not inspect tracked changes for $branch; not a clean sweep" >&2; exit 3; }
          printf 'MERGED-NOT-CLOSED     %-24s %-14s merged into %s, bead=%s assignee=%s verdict=%s %s\n' "$branch" "$id" "$main_ref" "$status" "${assignee:-none}" "$v" "$tree_state"
        fi ;;
    esac
    continue
  fi
  # FIXTURE MODE ONLY: a branch whose tip postdates the reference main did not
  # exist in the state being reconstructed. Live, main's tip is older than
  # every active branch and this filter would hide everything, so it is gated
  # on --bd-export and on nothing else. The live export also has a bd_export
  # path, so this must use fixture_mode rather than testing that path.
  if [ "$fixture_mode" = 1 ] && [ "$(git -C "$repo" log -1 --format=%ct "$ref")" -gt "$main_ct" ]; then continue; fi
  state_of "$id"
  v="$(verdict_of "$id")"; [ -n "$v" ] || v="none"
  tree_state="$(tracked_tree_state "$ref")" || { echo "SWEEP REFUSES: could not inspect tracked changes for $branch; not a clean sweep" >&2; exit 3; }
  case "$status" in
    closed)
      report_if_too_young "$branch" "$ref" "$id" unmerged && continue
      printf 'ORPHAN-BRANCH         %-24s %-14s ahead=%-3s bead=closed verdict=%s %s\n' "$branch" "$id" "$ahead" "$v" "$tree_state" ;;
    open|in_progress)
      report_if_too_young "$branch" "$ref" "$id" unmerged && continue
      if landable "$v"; then cls="STRANDED-REVIEWED    "; else cls="STRANDED-NOT-LANDABLE"; fi
      stranded=$((stranded+1))
      printf '%s %-24s %-14s ahead=%-3s bead=%s assignee=%s verdict=%s %s\n' "$cls" "$branch" "$id" "$ahead" "$status" "${assignee:-none}" "$v" "$tree_state" ;;
    absent)
      report_if_too_young "$branch" "$ref" "$id" unmerged && continue
      printf 'ORPHAN-BRANCH         %-24s %-14s ahead=%-3s bead=ABSENT-FROM-TRACKER verdict=%s %s\n' "$branch" "$id" "$ahead" "$v" "$tree_state" ;;
    *)
      report_if_too_young "$branch" "$ref" "$id" unmerged && continue
      printf 'ORPHAN-BRANCH         %-24s %-14s ahead=%-3s bead=%s verdict=%s %s\n' "$branch" "$id" "$ahead" "$status" "$v" "$tree_state" ;;
  esac
done < <(git -C "$repo" for-each-ref --format='%(refname)' 'refs/heads/bead/*')

# Graph classes intentionally suppress fresh/exact-tip branches. That is not a
# reason to suppress the safety fact: an attached dirty worktree is work
# present even when its branch has no reportable commit shape. Emit it without
# inventing a remediation or a stranded classification.
dirty_report="$({
  for ref in "${!branch_worktree[@]}"; do
    case "$ref" in refs/heads/bead/*) ;; *) continue ;; esac
    tree_state="$(tracked_tree_state "$ref")" || {
      echo "SWEEP REFUSES: could not inspect tracked changes for ${ref#refs/heads/}; not a clean sweep" >&2
      exit 3
    }
    [[ "$tree_state" == DIRTY* ]] || continue
    branch="${ref#refs/heads/}"; id="{{BEAD_PREFIX}}-${branch#bead/}"
    printf 'WORKTREE-DIRTY        %-24s %-14s %s; fact only, preserve for human assessment\n' "$branch" "$id" "$tree_state"
  done
  for wt in "${detached_worktrees[@]}"; do
    count="$(GIT_OPTIONAL_LOCKS=0 git -C "$wt" status --porcelain --untracked-files=no | wc -l)" || {
      echo "SWEEP REFUSES: could not inspect tracked changes for detached worktree $wt; not a clean sweep" >&2
      exit 3
    }
    if [ "$count" -gt 0 ]; then
      printf 'WORKTREE-DIRTY        %-24s %-14s DIRTY tracked=%s worktree=%s; fact only, preserve for human assessment\n' \
        'DETACHED-HEAD' 'no-bead' "$count" "$wt"
    else
      printf 'DETACHED-HEAD         %-24s %-14s CLEAN tracked=0 worktree=%s; inspected detached worktree\n' \
        'DETACHED-HEAD' 'no-bead' "$wt"
    fi
  done
})" || exit $?
printf '%s\n' "$dirty_report" | LC_ALL=C sort

if [ "$reapable" = 1 ]; then
  while read -r wt; do
    [ -n "$wt" ] || continue
    b=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null) || continue
    case "$b" in bead/*) ;; *) continue ;; esac
    id="{{BEAD_PREFIX}}-${b#bead/}"
    ahead=$(git -C "$repo" rev-list --count "$main_ref..refs/heads/$b" 2>/dev/null || echo "?")
    [ "$ahead" = "0" ] || continue
    state_of "$id"
    [ "$status" = closed ] || continue
    # A fast-forward landing remains on main's first-parent line and has no
    # landing merge. Use its tip/verdict evidence rather than refusing or
    # adopting a later, unrelated merge's timestamp.
    if branch_tip_on_main_first_parent "refs/heads/$b"; then age_kind=unmerged; else age_kind=merged; fi
    tree_state="$(tracked_tree_state "refs/heads/$b")" || { echo "SWEEP REFUSES: could not inspect tracked changes for $b; not a clean sweep" >&2; exit 3; }
    # scratch-reaper parses this positionally: keep `worktree=` as field four
    # and append the worktree state after the established human prose.
    if report_if_too_young "$b" "refs/heads/$b" "$id" "$age_kind"; then continue; fi
    printf 'REAPABLE              %-24s %-14s worktree=%s (merged, bead closed; NOT removed) %s\n' "$b" "$id" "$wt" "$tree_state"
  done < <(git -C "$repo" worktree list --porcelain | awk '/^worktree /{print $2}')
fi

[ "$stranded" -eq 0 ] && exit 0 || exit 1
