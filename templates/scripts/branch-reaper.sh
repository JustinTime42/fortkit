#!/bin/bash
# Remove merged bead branches left behind after their worktrees have gone.
#
# This is deliberately separate from fort/scripts/scratch-reaper.sh: the
# service reaper can only remove a branch while it removes its worktree.  This
# script covers the complementary, no-worktree case and is installed by an
# operator.
#
# Usage:
#   scripts/branch-reaper.sh --dry-run [--repo <path>] [--main <ref>]
#   scripts/branch-reaper.sh [--repo <path>] [--main <ref>]
#
# Run --dry-run first: it reports branches that would be removed without
# deleting anything.  Inspect that count before running without --dry-run.
# --repo selects the repository (default: this script's parent); --main names
# the commit ref branches must be merged into (default: main).
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
main_ref="main"
dry_run=0
# This default is intentionally bound before --repo parsing; normal use runs
# from this script's checkout, while harnesses provide BRANCH_REAPER_EMIT_SH.
emit="${BRANCH_REAPER_EMIT_SH:-$repo/fort/scripts/emit.sh}"

usage() {
  sed -n '2,/^set -uo pipefail$/p' "$0" | sed '$d'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --main) main_ref="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "branch-reaper.sh: unknown argument: $1" >&2; exit 64 ;;
  esac
done

git -C "$repo" rev-parse --verify --quiet "$main_ref^{commit}" >/dev/null \
  || { echo "branch-reaper.sh: REFUSED: '$main_ref' is not a commit in $repo" >&2; exit 64; }

removed=0; kept_attached=0; kept_locked=0; kept_unmerged=0; failed=0
note() { echo "$*" >&2; }

# A matching worktree is live if its lock cannot be acquired.  The branch is
# retained either way, but naming the lock makes a launcher/reaper race visible.
branch_worktree_state() { # $1 full ref; prints locked, attached, or absent
  local wt lock
  while read -r wt; do
    [ -n "$wt" ] || continue
    lock="$wt/.forge.lock"
    if [ -f "$lock" ] && ! flock -n "$lock" -c ':' 2>/dev/null; then
      printf '%s\n' locked
      return
    fi
    printf '%s\n' attached
    return
  done < <(git -C "$repo" worktree list --porcelain | awk -v want="$1" '
    /^worktree / { wt=substr($0, 10) }
    /^branch / { if (substr($0, 8) == want) print wt }
  ')
  printf '%s\n' absent
}

while read -r ref; do
  [ -n "$ref" ] || continue
  branch="${ref#refs/heads/}"

  case "$(branch_worktree_state "$ref")" in
    locked)
      kept_locked=$((kept_locked + 1))
      note "KEPT $branch (launcher holds .forge.lock)"
      continue
      ;;
    attached)
      kept_attached=$((kept_attached + 1))
      note "KEPT $branch (worktree attached)"
      continue
      ;;
  esac

  # The list is only a candidate snapshot. `git branch -d` is the
  # removal-time guard: it refuses if the graph changes after this check.
  if ! git -C "$repo" merge-base --is-ancestor "$ref" "$main_ref" 2>/dev/null; then
    kept_unmerged=$((kept_unmerged + 1))
    note "KEPT $branch (NOT an ancestor of $main_ref)"
    continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    removed=$((removed + 1))
    note "WOULD REMOVE $branch (merged, no worktree attached)"
    continue
  fi

  # Lowercase -d is a second, Git-enforced refusal if the graph changed after
  # the explicit ancestry check.
  if git -C "$repo" branch -d "$branch" >&2; then
    removed=$((removed + 1))
    note "REMOVED $branch (merged, no worktree attached)"
  else
    failed=$((failed + 1))
    note "FAILED $branch (git branch deletion refused or failed)"
  fi
done < <(git -C "$repo" for-each-ref --format='%(refname)' 'refs/heads/bead/*')

summary="branch-reaper.sh: $removed $([ "$dry_run" -eq 1 ] && printf 'would remove' || printf 'removed'), $failed failed; kept $kept_attached attached, $kept_locked locked, $kept_unmerged unmerged$([ "$dry_run" -eq 1 ] && printf ' (DRY RUN, nothing removed)')"
note "$summary"

if [ "$dry_run" -eq 0 ] && { [ "$removed" -gt 0 ] || [ "$failed" -gt 0 ]; }; then
  detail="branch reaper: $removed removed, $failed failed; kept $kept_attached attached, $kept_locked locked, $kept_unmerged unmerged"
  ( cd "$repo" && "$emit" progress "$detail" -a fleet -s fleet \
      -p "{\"removed\":$removed,\"failed\":$failed,\"kept_attached\":$kept_attached,\"kept_locked\":$kept_locked,\"kept_unmerged\":$kept_unmerged}" ) || true
fi

[ "$failed" -eq 0 ] || exit 1
