#!/bin/bash
# Remove the label before recording the answer so a failed label change cannot
# claim an answered decision. If the emit fails, restore the label: the durable
# record must never leave a label change without its matching event.
#
# WHOSE MOVE IS THE ASSIGNEE (Proofdelve ForgeOs-29j3g, from 2026-10-19): his answer
# recorded means the move is the Mayor's, so the same update assigns emrith and
# the bead leaves his board; a restore puts it back on his board (justin).
set -euo pipefail

usage() {
  printf 'Usage: %s <bead-id> <decision, one line>\n' "${0##*/}" >&2
}

[ "$#" -eq 2 ] || { usage; exit 2; }
bead_id="$1"
decision="$2"
case "$decision" in
  *$'\n'*|"") printf 'unflag-human: decision must be one non-empty line\n' >&2; exit 2 ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
git_common="$(git -C "$repo_root" rev-parse --git-common-dir)"
case "$git_common" in
  /*) ;;
  *) git_common="$repo_root/$git_common" ;;
esac
main_root="$(cd "$(dirname "$git_common")" && pwd -P)"
emitter="$main_root/fort/scripts/emit.sh"

bd -C "$main_root" update "$bead_id" --remove-label human --assignee emrith || exit 3
if ! "$emitter" decision.answered "$decision" -a "${FORT_ACTOR:-emrith}" -s "${FORT_SEAT:-mayor}" -t "$bead_id"; then
  if ! bd -C "$main_root" update "$bead_id" --add-label human --assignee justin; then
    printf 'unflag-human: failed to restore human label for %s; label is absent and decision.answered was not recorded\n' "$bead_id" >&2
  fi
  exit 3
fi
