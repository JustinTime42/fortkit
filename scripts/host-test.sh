#!/usr/bin/env bash
# Docker-backed host tests. Usage: host-test.sh <main|fortkit-<bead>|bead> '<dotnet test filter>' [--mutate patch]
# Overrides: HOST_TEST_MAIN_WORKTREE and HOST_TEST_WORKTREES_DIR.
set -euo pipefail
readonly EX_USAGE=64
readonly max_filter_length=200
readonly filter_pattern='^[A-Za-z0-9._~=!&|() ]+$'
root="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
source "$root/scripts/lib/preview-common.sh"
worktrees_dir="${HOST_TEST_WORKTREES_DIR:-$preview_worktrees_default}"
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
    tree="${HOST_TEST_MAIN_WORKTREE:-$HOME/dev/fortkit-host-test}"
    if [ ! -e "$tree/.git" ]; then
        git -C "$root" worktree add --detach "$tree" main
    else
        git -C "$tree" merge --ff-only main
    fi
else
    suffix="${target#fortkit-}"
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
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/fortkit-host-test.XXXXXX")"
    git clone -q --no-hardlinks "$tree" "$tmp/tree"
    tree="$tmp/tree"
    git -C "$tree" apply "$mutate"
fi
(
    cd "$tree"
    dotnet build Product.sln
    dotnet test tests/Product.Tests/Product.Tests.csproj --filter "$filter"
)
