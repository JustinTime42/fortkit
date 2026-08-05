#!/bin/bash
# Civilization-layer event emitter — append-only stream for the civ seats.
#
# Usage: emit.sh <category> <detail> [-a actor] [-s seat] [-t target] [-p payload-json] [-T iso-timestamp]
#
# THIS SCRIPT RESOLVES ITS TARGET STREAM FROM ITS OWN LOCATION, NOT FROM THE
# CALLER'S WORKING DIRECTORY. That is deliberate and it is the difference from
# fort/scripts/emit.sh, which walks git's common dir from $PWD so a worktree
# appends to its main repo's stream. That behaviour is right for worktrees and
# is a trap for any cross-layer caller: invoking a fort's emit.sh from somewhere
# else writes into the CALLER's fort. It did exactly that for the whole of the
# Regent's first two days, and two settlements were never told an edict had
# begun (fortkit-nvk). A civ seat calls into three repositories in a single
# session, so this script cannot afford that contract. Proposed as the hardening
# for the fort emitters too: fortkit-iqp.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "emit.sh: usage: emit.sh <category> <detail> [-a actor] [-s seat] [-t target] [-p payload] [-T ts]" >&2
  exit 2
fi

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
CIV="$(cd "$(dirname "$SELF")/.." && pwd)"

category="$1"; detail="$2"; shift 2
actor="civ"; seat=""; target=""; payload="null"; ts="$(date -Is)"
while getopts "a:s:t:p:T:" opt; do
  case $opt in
    a) actor="$OPTARG";; s) seat="$OPTARG";; t) target="$OPTARG";;
    p) payload="$OPTARG";; T) ts="$OPTARG";;
    *) echo "emit.sh: unknown flag" >&2; exit 2;;
  esac
done

dir="$CIV/events"
mkdir -p "$dir"
file="$dir/events-$(date -d "$ts" +%F 2>/dev/null || date +%F).jsonl"

line=$(jq -nc --arg ts "$ts" --arg actor "$actor" --arg seat "$seat" \
  --arg category "$category" --arg target "$target" --arg detail "$detail" \
  --argjson payload "$payload" \
  '{ts:$ts, actor:$actor, seat:(if $seat=="" then null else $seat end),
    category:$category, target:(if $target=="" then null else $target end),
    detail:$detail, payload:$payload}')

( flock -x 9; printf '%s\n' "$line" >&9 ) 9>>"$file"
