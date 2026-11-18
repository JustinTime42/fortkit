#!/bin/bash
# ForgeOS city status — fast, read-only. Usage: fort/scripts/status.sh
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo /home/justin/dev/ForgeOs)" || exit

echo "══════════════════ PROOFDELVE FORT STATUS ══════════════════"
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
find fort/handoffs -maxdepth 1 -type f -name '*.md' ! -name '.gitkeep' -printf '%T@ %p\n' \
  | sort -rn | head -3 | while IFS=' ' read -r _ f; do
  echo "  $f  ($(date -r "$f" '+%b %d %H:%M'))"
done || echo "  (none yet)"
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
# %gd, NOT %cd: under `git log -g` the -g is INERT for %cd, which remains
# the COMMIT's committer date — so the old spelling rendered a commit date
# under a sync label (7s adrift in this clone, unbounded under git fetch: a
# tip another clone committed a week ago reads as 'synced' a week ago no
# matter when you fetched it). %gd is the reflog entry's own time; the sed
# strips git's `origin/main@{...}` wrapper. Do not simplify this back.
# (Ilva Trueglass, blocking finding 1 on fortkit-wg8w.1; fortkit-rw86.)
SYNCED=$(git log -g -1 --format=%gd --date=iso refs/remotes/origin/main 2>/dev/null \
  | sed 's/^[^{]*{//; s/}$//')
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
echo "── Fleet (ForgeOs-3q6g) ──"
# THE THREE FACTS ARE SHOWN TOGETHER OR THE STREAK MISLEADS (Tova, dx34.4 round
# one, finding 6). The supervisor exits on the halt file BEFORE it reads or
# writes its streak record, so during a halt the record is FROZEN: count=N with
# the lock free is not a wedge, it is the last live run's tail, and
# last_refusal is the tell. Hence halt file, lock probe and streak, one block.
FLEET_STATE_DIR="${FLEET_STATE:-$HOME/.local/state/proofdelve-fleet}"
if [ -e "$FLEET_STATE_DIR/HALT" ]; then
  # halt() writes a timestamp line then the reason; a person's file is usually one line. Show whatever is there, joined.
  echo "  HALT: PRESENT since $(date -r "$FLEET_STATE_DIR/HALT" '+%b %d %H:%M') — $(tr '\n' ' ' < "$FLEET_STATE_DIR/HALT" | cut -c1-120)"
  echo "        (the supervisor fires and exits on this file first; the streak below is FROZEN at the last live run)"
else
  echo "  HALT: absent"
fi
if [ -e "$FLEET_STATE_DIR/fleet.lock" ]; then
  # READ-ONLY, SHARED, WITH A DISTINCT CONFLICT CODE (ForgeOs-ip9z finding 8;
  # this is the line the bead QUOTES, and fleet-supervisor.sh carries the same
  # probe silently). The old spelling was `flock -n 9 2>/dev/null 9>>...`, and
  # `9>>` needs WRITE permission on the lock file: with a lock file or a state
  # directory a reader cannot write -- which is every masked seat -- the
  # redirection failed, the `if` was false, and this printed "HELD, a fleet run
  # is live" about a fleet that was not running. A shared lock on a read-only
  # descriptor still conflicts with fleet.sh's exclusive one and needs no write
  # access (scripts/quiescent.sh's idiom), and `-E 75` gives contention a code
  # of its own so a failed OPEN can no longer be read as a held lock.
  lock_rc=0
  ( flock -n -s -E 75 9 ) 9<"$FLEET_STATE_DIR/fleet.lock" 2>/dev/null || lock_rc=$?
  case "$lock_rc" in
    0)  echo "  lock: free (no fleet run is live)" ;;
    75) echo "  lock: HELD — a fleet run is live" ;;
    *)  echo "  lock: UNKNOWN — $FLEET_STATE_DIR/fleet.lock exists and could not be opened for reading (flock exited $lock_rc); this is NOT the same thing as a run being live" ;;
  esac
else
  echo "  lock: no lock file yet (no run has ever started here)"
fi
if [ -f "$FLEET_STATE_DIR/supervisor.streak" ]; then
  sv() { grep -m1 "^$1=" "$FLEET_STATE_DIR/supervisor.streak" 2>/dev/null | cut -d= -f2-; }
  if [ "$(sv count)" != 0 ] && [ -n "$(sv count)" ]; then
    echo "  supervisor streak: $(sv count) refusal(s) since $(sv first_refusal), last $(sv last_refusal)"
  else
    echo "  supervisor streak: 0 (reset $(sv reset_at); the cleared streak was $(sv previous_streak) refusal(s) from $(sv previous_first_refusal))"
  fi
else
  echo "  supervisor streak: no record (never refused, or reset before the record existed)"
fi
echo
echo "── Recent events ──"
tail -5 fort/events/events-*.jsonl 2>/dev/null | grep '^{' | tail -5 | jq -r '"  \(.ts | split("T")[1] | split("-")[0]) [\(.actor)] \(.detail)"' 2>/dev/null || echo "  (no events yet)"
echo
echo "── Staging ──"
timeout 5 curl -sf -o /dev/null -w "  /api/health: %{http_code} (%{time_total}s)\n" \
  "$(grep -o 'https://[^"]*azurecontainerapps.io' docs/azure-staging-runbook.md 2>/dev/null | head -1)/api/health" 2>/dev/null \
  || echo "  (health check skipped: no URL found or unreachable)"
echo "═══════════════════════════════════════════════════════════"
