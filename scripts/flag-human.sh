#!/bin/bash
# Record the raise before adding the label: a visible human label must never
# exist without its durable decision.raised event.
#
# WHOSE MOVE IS THE ASSIGNEE (ForgeOs-29j3g, from 2026-10-19). His board is the
# open beads assigned to justin, each with one comment line beginning "ASK:".
# So a hand-back now posts the ASK line FIRST and then, in the same single
# update that flips the labels, assigns the bead to him: a bead never reaches
# his board without its reason. `human` is still added, as history.
set -euo pipefail

usage() {
  printf 'Usage: %s <bead-id> <why, one line> [sign|grant|decide|run host test|answer]\n' "${0##*/}" >&2
}

[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || { usage; exit 2; }
bead_id="$1"
why="$2"
verb="${3:-decide}"
case "$verb" in
  sign|grant|decide|"run host test"|answer) ;;
  *) printf 'flag-human: the ask must be one of sign, grant, decide, run host test, answer\n' >&2; exit 2 ;;
esac
case "$why" in
  *$'\n'*|"") printf 'flag-human: why must be one non-empty line\n' >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
git_common="$(git -C "$repo_root" rev-parse --git-common-dir)"
case "$git_common" in
  /*) ;;
  *) git_common="$repo_root/$git_common" ;;
esac
main_root="$(cd "$(dirname "$git_common")" && pwd -P)"
emitter="$main_root/fort/scripts/emit.sh"

"$emitter" decision.raised "$why" -a "${FORT_ACTOR:-marrek}" -s "${FORT_SEAT:-mayor}" -t "$bead_id" || exit 3
ask_file="$(mktemp)" || exit 3
trap 'rm -f "$ask_file"' EXIT
printf 'ASK: %s -- %s\n' "$verb" "$why" > "$ask_file"
bd -C "$main_root" comment "$bead_id" --file "$ask_file" || exit 3
bd -C "$main_root" update "$bead_id" --remove-label mayor-review --add-label human --assignee justin || exit 3
