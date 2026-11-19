#!/usr/bin/env bash
# Host tests of main or of a bead's worktree. Usage: host-test.sh <main|{{BEAD_PREFIX}}-<bead>|bead> '<test filter>' [--mutate patch]
# The filter is handed to this fort's test runner once one is wired below.
# Overrides: HOST_TEST_MAIN_WORKTREE and HOST_TEST_WORKTREES_DIR.
set -euo pipefail
readonly EX_USAGE=64
readonly max_filter_length=200
readonly filter_pattern='^[A-Za-z0-9._/ -]+$'
root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
worktrees_dir="${HOST_TEST_WORKTREES_DIR:-{{REPO_PATH}}-worktrees}"
readonly bead_target_regex='^({{BEAD_PREFIX}}-)?[a-z0-9]+(\.[0-9]+)*$'
valid_target() {
    [[ "$1" == main || "$1" =~ $bead_target_regex ]]
}
die() {
    printf 'host-test: %s\n' "$*" >&2
    exit "$EX_USAGE"
}
valid_filter() {
    [ "${#1}" -le "$max_filter_length" ] && [[ "$1" =~ $filter_pattern ]]
}
if [ "$#" -ne 2 ] && [ "$#" -ne 4 ]; then
    die "usage: host-test.sh <main|bead> '<filter>' [--mutate patch]"
fi
target="$1"
filter="$2"
mutate=""
if [ "$#" -eq 4 ]; then
    [ "$3" = --mutate ] || die 'expected --mutate'
    mutate="$(realpath -- "$4" 2>/dev/null)" || die "patch does not exist: $4"
    [ -f "$mutate" ] || die "patch does not exist: $mutate"
fi
valid_target "$target" || die "invalid target: $target"
valid_filter "$filter" || die 'invalid filter'
if [ "$target" = main ]; then
    tree="${HOST_TEST_MAIN_WORKTREE:-$HOME/dev/{{FORT_SLUG}}-host-test}"
    if [ ! -e "$tree/.git" ]; then
        git -C "$root" worktree add --detach "$tree" main
    else
        git -C "$tree" merge --ff-only main
    fi
else
    suffix="${target#{{BEAD_PREFIX}}-}"
    tree="$worktrees_dir/$suffix"
    [ -e "$tree/.git" ] || die "bead worktree does not exist: $tree"
fi
tmp=""
cleanup() {
    [ -z "$tmp" ] || rm -rf "$tmp"
}
trap cleanup EXIT
if [ -n "$mutate" ]; then
    dirty_paths="$(git -C "$tree" status --porcelain)"
    if [ -n "$dirty_paths" ]; then
        printf 'host-test: --mutate refuses dirty worktree:\n%s\n' "$dirty_paths" >&2
        exit "$EX_USAGE"
    fi
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/{{BEAD_PREFIX}}-host-test.XXXXXX")"
    git clone -q --no-hardlinks "$tree" "$tmp/tree"
    tree="$tmp/tree"
    git -C "$tree" apply "$mutate"
fi
(
    cd "$tree"
    # No product test runner is wired in a newly founded fort. Name this fort's
    # runner here before an airlock operation points at this script.
    read -r -a filter_words <<< "$filter"
    echo "host-test: no product test runner is wired in this fort (filter: ${filter_words[*]})" >&2
    exit 69
)
