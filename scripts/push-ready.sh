#!/bin/bash
# push-ready.sh -- may the Mayor push main right now?
#
# WHY THIS EXISTS. The Mayor's push grant is conditional: push after a fleet
# merge lands AND its post-merge verify is GREEN. Judging that meant reading the
# tail of the event stream by eye, and on 2026-09-15 at 19:34 this seat read a
# line reading `verify.run commit=1bdd708`, matched the commit, and pushed --
# without reading the CATEGORY. The verifier was still running. It passed 76
# seconds later, so nothing broke; the process was still wrong, and "pushed,
# verify green" would have been a true-sounding sentence describing something
# that did not happen in that order.
#
# Prose did not prevent it: the same seat had correctly WAITED on `verify.run`
# in three earlier cycles that day. A one-line eyeball check is not a gate.
#
# WHAT IT ANSWERS. Exactly one question, about the CURRENT HEAD:
#   exit 0  a verify.pass exists for this commit, recorded on branch HEAD
#          (a detached post-merge verify) or on the checkout's own branch -> push
#   exit 1  a verify.fail is the latest verdict for it           -> DO NOT push
#   exit 2  a verify.run with no verdict yet, or no event at all -> WAIT
#   exit 3  could not ask (no stream, unreadable, git silent)    -> a refusal
#
# Exit 2 and exit 3 are DIFFERENT ON PURPOSE. "Not yet" and "I could not tell"
# are distinct states, and collapsing them is how a seat talks itself into
# treating silence as permission.
#
# It reports and never pushes. The push stays a deliberate act.
set -uo pipefail

root="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)" || exit 3
head="$(git -C "$root" rev-parse HEAD)" || exit 3
# THE TREE, for a REUSED pass (ForgeOs-s1reg). fleet.sh may record main's
# post-merge pass without a second run when the merged tree is the tree its host
# verifier passed; such an event says reused:true and names verifiedTree. It is
# a verdict for HEAD only if HEAD's tree IS that tree, checked here, never taken
# from the event's word.
head_tree="$(git -C "$root" rev-parse 'HEAD^{tree}')" || exit 3
# The branch the checkout is on. A fleet post-merge verify runs detached and
# records branch "HEAD"; a verifier run by hand in the main checkout at the
# same sha records "main". Both are a verdict on THIS commit (measured
# 2026-09-15 23:26: verify.pass 28ae20a on main was refused as absent, and the
# only route to a push was to wait for an unrelated merge). A verify on some
# OTHER branch that happens to share the sha is still not accepted: the rule
# is the tree that was checked, not the sha alone.
branch="$(git -C "$root" rev-parse --abbrev-ref HEAD)" || exit 3
# A post-merge verifier can remain unpushed through several midnights when an
# empty ssh-agent blocks an otherwise approved push. Keep the decision window
# bounded at the same N as fleet.sh's 14 day-file horizon — same N, different
# unit, ForgeOs-uy86j. The calendar must not change a HEAD's verdict
# (ForgeOs-0nhz4), but make it long enough that a second midnight cannot
# manufacture an absence. The order is intentional: event files are append-only,
# and a later calendar day's verdict is later than every verdict in the
# preceding file.
today="$(date +%F)"
window_days=14
window_start="$(date -d "$((window_days - 1)) days ago" +%F)"
streams=()
for ((offset = window_days - 1; offset >= 0; offset--)); do
  day="$(date -d "$offset days ago" +%F)"
  candidate="$root/fort/events/events-$day.jsonl"
  if [ -e "$candidate" ] && ! [ -r "$candidate" ]; then
    echo "push-ready: cannot read event stream $candidate -- refusing to guess"
    exit 3
  fi
  if [ -r "$candidate" ]; then
    streams+=("$candidate")
  fi
done

if [ "${#streams[@]}" -eq 0 ]; then
  echo "push-ready: cannot read event window $window_start through $today -- refusing to guess"
  exit 3
fi

# ForgeOs-47mq: three approved pushes (08-17, 08-21, 08-28) failed with
# "Permission denied (publickey)" AFTER the grant, because the agent held no
# identity: ~/.ssh is filtered to known_hosts inside the mask, so ssh-add there
# has nothing to load, and `ssh-add -l` exits 1 ("no identities") or 2 (no
# agent) silently. Ask the agent here, once, before anyone plans a push. The
# verdict below is about the TREE and is unchanged by this; the line is a
# warning printed after it, never a substitute exit code, so a caller that
# greps '^push-ready: YES' still gets the SHA and the push then fails loudly
# rather than being talked out of by this script. The remedy is on the host:
# fact ssh-add-must-run-outside-the-mask.
agent_note=""
if ! ssh-add -l >/dev/null 2>&1; then
  agent_note="push-ready: WARN -- ssh-agent holds no identities (ssh-add -l exit $?); a push from this seat will fail with 'Permission denied (publickey)'. Run ssh-add on the HOST, outside the mask; the seat sees the identity at once (ForgeOs-47mq)."
fi

HEAD_SHA="$head" HEAD_TREE="$head_tree" HEAD_BRANCH="$branch" WINDOW_START="$window_start" WINDOW_END="$today" AGENT_NOTE="$agent_note" python3 - "${streams[@]}" <<'PY'
import json, os, sys

head = os.environ["HEAD_SHA"]
verdict, seen_run, when = None, False, None

try:
    # Read chronological day files in order. Within each append-only file the
    # last matching verdict wins, so a newer failure cannot be overruled by an
    # older pass from the preceding day.
    for stream in sys.argv[1:]:
        with open(stream, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                except ValueError:
                    continue                  # a torn line is not a verdict
                p = e.get("payload") or {}
                if p.get("branch") not in ("HEAD", os.environ["HEAD_BRANCH"]):
                    continue
                commit = str(p.get("commit") or "")
                # The stream carries short shas; HEAD is full. Compare on the
                # shorter of the two, and require a real prefix, never equality of
                # truncations that merely look alike.
                # A prefix shorter than 7 is not an identifier here; refuse it
                # rather than let a 3-character coincidence become a push.
                if len(commit) < 7 or not head.startswith(commit):
                    continue
                cat = e.get("category")
                # ForgeOs-l3l8: a verify on a DIRTY tree, or one whose HEAD moved
                # during the run, scored bytes that commit X does not contain. Such
                # a pass is real evidence about the working tree and none about X,
                # so it is not a verdict for HEAD here. Older events lack the keys
                # and are read as before (absent means unknown, not dirty).
                if p.get("dirtyAtStart") is True or p.get("dirtyAtEnd") is True or p.get("headMoved") is True:
                    if cat == "verify.run":
                        seen_run = True
                    continue
                # ForgeOs-s1reg: a reused pass counts only on tree equality.
                if cat == "verify.pass" and p.get("reused") is True \
                        and p.get("verifiedTree") != os.environ["HEAD_TREE"]:
                    continue
                if cat == "verify.run":
                    seen_run = True
                elif cat in ("verify.pass", "verify.fail"):
                    verdict, when = cat, e.get("ts")   # last one wins
except OSError as exc:
    print("push-ready: %s" % exc)
    sys.exit(3)

short = head[:7]
if verdict == "verify.pass":
    print("push-ready: YES -- verify.pass for HEAD %s at %s" % (short, when))
    if os.environ.get("AGENT_NOTE"):
        print(os.environ["AGENT_NOTE"])
    sys.exit(0)
if verdict == "verify.fail":
    print("push-ready: NO -- verify.fail for HEAD %s at %s. Do not push." % (short, when))
    sys.exit(1)
if seen_run:
    print("push-ready: WAIT -- a verifier is running on HEAD %s and has not "
          "reported. This is the case that caused this script to exist." % short)
    sys.exit(2)
print("push-ready: WAIT -- no post-merge verify event for HEAD %s at all. "
      "Searched event window %s through %s. Absence is not a pass." %
      (short, os.environ["WINDOW_START"], os.environ["WINDOW_END"]))
sys.exit(2)
PY
