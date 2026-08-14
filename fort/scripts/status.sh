#!/bin/bash
# Manyhalls fort status — fast, read-only. Usage: fort/scripts/status.sh
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo /home/justin/dev/fortkit)" || exit 1

echo "══════════════════ MANYHALLS FORT STATUS (FORTKIT) ══════════════════"
echo
echo "── Work in progress ──"
bd list --status in_progress 2>/dev/null | grep -v '^─\|^Total\|^Status' | head -8
echo
echo "── Ready queue (top 5) ──"
bd ready 2>/dev/null | head -5
echo
echo "── Blocked ──"
bd list --status open 2>/dev/null | grep '●.*blocked' | head -5
echo
echo "── Worktrees (active Forge sessions) ──"
git worktree list | tail -n +2
echo
echo "── Recent handoffs ──"
found=0
while IFS= read -r f; do
  found=1
  echo "  $f  ($(date -r "$f" '+%b %d %H:%M'))"
done < <(find fort/handoffs -maxdepth 1 -name '*.md' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -3 | cut -d' ' -f2-)
[ "$found" -eq 1 ] || echo "  (none yet)"
echo
echo "── Git ──"
# NOT "ahead of origin" (fortkit-rw86). origin/main is a LOCAL remote-tracking
# ref: it moves only when THIS clone pushes or fetches, so the number below is
# commits since this clone last synced. That equals "ahead of the remote" only
# while this clone is the sole writer to it, which nothing here enforces and no
# code here states. Two elder Mayors caught the difference in one evening, both
# with git ls-remote: a stale 19 in Proofdelve and a stale 24 in Farlantern that
# was really 1. Standing order 6 wants committed, pushed and deployed verified
# SEPARATELY; a local ref verifies the last sync, so this line now says that and
# nothing more. The remote is deliberately NOT queried: status.sh runs at every
# session start in every fort, and a network call there fails at the worst time.
# AN UNREADABLE REF MUST NOT RENDER AS "nothing to worry about". It used to do
# both at once — "?" in the sentence, and ${AHEAD:-0} on the next line
# defaulting the SAME unknown to zero, which silently disarmed the drift warning
# at exactly the moment the fort could not see its own state.
SYNCED=$(git log -g -1 --format=%cd --date=iso refs/remotes/origin/main 2>/dev/null)
if AHEAD=$(git rev-list --count origin/main..main 2>/dev/null); then
  echo "  branch: $(git branch --show-current), $AHEAD commit(s) since last sync with origin/main${SYNCED:+ (synced $SYNCED)}"
  if [ "$AHEAD" -gt 3 ]; then
    echo "  ⚠ PUSH DRIFT: >3 commits since last sync — the remote is not queried here (git ls-remote origin main)"
  fi
else
  echo "  branch: $(git branch --show-current), sync state UNKNOWN — no readable origin/main tracking ref"
  echo "  ⚠ SYNC STATE UNKNOWN — this is not 'level': run git ls-remote origin main"
fi
echo "  last: $(git log --oneline -1)"
echo
echo "── Recent events ──"
tail -5 fort/events/events-*.jsonl 2>/dev/null | grep '^{' | tail -5 | jq -r '"  \(.ts | split("T")[1] | split("-")[0]) [\(.actor)] \(.detail)"' 2>/dev/null || echo "  (no events yet)"
echo
echo "── Staging ──"
timeout 5 curl -sf -o /dev/null -w "  /api/health: %{http_code} (%{time_total}s)\n" \
