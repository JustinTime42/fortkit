#!/bin/bash
# The transcript supplement (ForgeOs-eng3.11), approved by Justin 2026-09-01 on
# his own suggestion: "maybe the final summary hook needs to also actually read
# the convo itself to ensure it's not missing anything obvious."
#
# WHAT IT IS FOR. digest.sh reads events, Beads, and git. It only knows what
# somebody wrote down. A question asked in prose and never turned into a bead, a
# caveat stated once, a decision made in conversation that no `bd` command
# captured -- none of those leave a trace any deterministic reader can find, and
# they are exactly the class that gets buried in a long scroll.
#
# WHY IT IS A SEPARATE SECTION AND NOT MERGED INTO THE DIGEST. digest.sh's stated
# virtue, in its own header, is that it does not infer outcomes from event text.
# It is deterministic: it can be INCOMPLETE but it cannot LIE. A model reading a
# transcript is the opposite instrument -- it finds what no script could, and it
# can also invent one. A reader who knows which half is which can trust the first
# and skim the second. A reader handed one merged summary has to trust all of it
# or none, and the first time the merged version invents a decision, the reliable
# half loses its credibility too. So: two sections, always labelled, never mixed.
#
# DEFAULT OFF. Set FORT_TRANSCRIPT_DIGEST=1 to enable. This calls a model from a
# Stop hook, which is the highest-blast-radius thing in this repo's tooling: it
# runs on every quiescent stop, unattended. Shipping it on by default would make
# a misfire fire constantly. Standing order 2 -- easy to change later.
#
# Usage: digest-transcript.sh <transcript.jsonl>
set -uo pipefail

transcript="${1:-}"
[ -n "$transcript" ] || exit 0
[ -r "$transcript" ] || exit 0
[ "${FORT_TRANSCRIPT_DIGEST:-0}" = "1" ] || exit 0

# REENTRANCY GUARD. This script spawns `claude`, and a spawned claude that loaded
# this project's settings would run this project's Stop hook, which would spawn
# claude. --setting-sources "" below is the real fix (it loads no project hooks
# at all); this variable is the belt to that suspenders, and it is also what
# stops a hand-run from nesting inside a hook-run.
[ "${FORT_IN_TRANSCRIPT_DIGEST:-0}" = "1" ] && exit 0
export FORT_IN_TRANSCRIPT_DIGEST=1

command -v claude >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# PROSE ONLY. Human turns (string content -- an array is a tool result, not a
# person) and the assistant's own text blocks. Tool calls and tool output are
# dropped: they are where the deterministic digest already looks, and they are
# 98% of the bytes. Measured on this session: 2,972,367 -> 44,497, a 67x
# reduction, which is what makes this affordable at all.
prose="$(mktemp)"
trap 'rm -f "$prose"' EXIT
jq -r '
  if .type=="user" and (.message.content|type=="string")
  then "HUMAN: " + .message.content
  elif .type=="assistant"
  then (.message.content[]? | select(.type=="text") | "ASSISTANT: " + .text)
  else empty end
' "$transcript" 2>/dev/null | tail -c 120000 > "$prose"

[ -s "$prose" ] || exit 0

read -r -d '' ask <<'PROMPT' || true
Below is the prose of one work session: the human's turns and the assistant's
replies, with all tool traffic removed.

A separate deterministic report already covers commits, merges, issue-tracker
state, review verdicts and push state. Do not repeat any of that, and do not
summarize the session.

List ONLY what the human still needs and a mechanical scan would MISS:
  - questions the assistant asked that were never answered
  - caveats or risks stated once in passing and never recorded anywhere
  - decisions made in conversation that no command appears to have captured
  - commitments the assistant made that it does not appear to have kept

Quote a short fragment for each so it can be checked against the transcript.
Prefer recall over precision: a false positive costs a glance, a miss costs the
whole point. If there is genuinely nothing, reply with exactly: nothing found.
PROMPT

out="$(timeout 120 claude -p "$ask

---

$(cat "$prose")" \
  --setting-sources "" \
  --allowed-tools "" \
  2>/dev/null)"

status=$?
if [ "$status" -ne 0 ] || [ -z "$out" ]; then
  # Degrade silently to the deterministic section alone. A hook must never
  # prevent a turn ending, and a model call can be slow, rate-limited or absent.
  exit 0
fi

printf '\n'
printf 'FROM THE CONVERSATION — model-generated, may be wrong, quotes are checkable\n'
printf '%s\n' "$out" | sed 's/^/  /'
exit 0
