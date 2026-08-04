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
AHEAD=$(git rev-list --count origin/main..main 2>/dev/null)
echo "  branch: $(git branch --show-current), ${AHEAD:-?} commit(s) ahead of origin/main"
[ "${AHEAD:-0}" -gt 3 ] && echo "  ⚠ PUSH DRIFT: >3 unpushed commits"
echo "  last: $(git log --oneline -1)"
echo
echo "── Recent events ──"
tail -5 fort/events/events-*.jsonl 2>/dev/null | grep '^{' | tail -5 | jq -r '"  \(.ts | split("T")[1] | split("-")[0]) [\(.actor)] \(.detail)"' 2>/dev/null || echo "  (no events yet)"
echo
echo "── Staging ──"
timeout 5 curl -sf -o /dev/null -w "  /api/health: %{http_code} (%{time_total}s)\n" \
