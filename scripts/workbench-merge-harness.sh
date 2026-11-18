#!/bin/bash
# workbench-merge-harness: the instrument for workbench.sh's host-side merge of
# main (Proofdelve ForgeOs-guue7; Regent sitting 2026-11-16).
#
# workbench.sh is sourceable (it runs main only when executed), so this sources
# the SHIPPED file and calls wb_merge_main() against fixture repositories whose
# main has changed fort/scripts after the session branch was cut. Five outcomes
# are driven: current, merged, conflicts, in-progress, refused.
#
# Subject: WORKBENCH_SH, or fort/scripts/workbench.sh beside this file's parent.
# Exit: 0 all passed; 1 a case failed or did not run; 3 refused.
# shellcheck disable=SC2016  # file-wide: single-quoted runner bodies and source patterns
set -uo pipefail
unset FORT_MASKED
here="$(cd "$(dirname "$0")" && pwd)"
subject="${WORKBENCH_SH:-$here/../fort/scripts/workbench.sh}"
[ -f "$subject" ] || { echo "HARNESS REFUSES: no subject at $subject (set WORKBENCH_SH)"; exit 3; }
grep -q '^wb_merge_main() {' "$subject" || { echo "HARNESS REFUSES: no wb_merge_main() in $subject (a launcher from before Proofdelve ForgeOs-guue7)"; exit 3; }
work="$(mktemp -d "${TMPDIR:-/tmp}/workbench-merge-harness.XXXXXX")"
case "$work" in /*) ;; *) echo "HARNESS REFUSES: scratch dir is not absolute"; exit 3 ;; esac
trap 'rm -rf "$work"' EXIT
pass=0; fail=0; notrun=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1 -- $2"; }
n=0; r=""; wt=""
g() { git -c user.email=h@h -c user.name=H -c commit.gpgsign=false "$@"; }
mk() {  # a repo with main, and a session worktree on bead/s1 cut from it; then main moves
  n=$((n+1)); r="$work/repo$n"; wt="$work/repo$n-worktrees/s1"
  mkdir -p "$r/fort/scripts" "$r/web"
  g -C "$r" init -q -b main
  printf 'v1\n' > "$r/fort/scripts/fleet.sh"; printf 'line1\nline2\nline3\n' > "$r/web/app.ts"; printf 'other\n' > "$r/web/other.ts"
  g -C "$r" add -A; g -C "$r" commit -qm base
  g -C "$r" worktree add -q -b bead/s1 "$wt" main
  printf 'session work\n' > "$wt/web/session.ts"; g -C "$wt" add -A; g -C "$wt" commit -qm "E2E-s1: session work"
}
main_moves() {  # main changes fort/scripts (the guue7 trigger) and, optionally, web/app.ts
  printf 'v2 from main\n' > "$r/fort/scripts/fleet.sh"
  [ "${1:-}" = app ] && printf 'line1\nMAIN line2\nline3\n' > "$r/web/app.ts"
  g -C "$r" add -A; g -C "$r" commit -qm "main: fort/scripts changed"
}
call() {  # runs the shipped wb_merge_main on $wt; sets state and note
  local out
  out="$(GIT_AUTHOR_NAME=H GIT_AUTHOR_EMAIL=h@h GIT_COMMITTER_NAME=H GIT_COMMITTER_EMAIL=h@h bash -c 'source "$1"; wb_merge_main "$2" E2E-s1; printf "%s\n%s\n" "$wb_merge_state" "$wb_merge_note"' _ "$subject" "$wt" 2>&1)"
  state="$(printf '%s\n' "$out" | sed -n 1p)"; note="$(printf '%s\n' "$out" | sed -n 2p)"
}
contains_main() { git -C "$wt" merge-base --is-ancestor main HEAD; }
in_merge() { [ -e "$(git -C "$wt" rev-parse --path-format=absolute --git-path MERGE_HEAD)" ]; }

# 1. current: nothing to do, nothing done.
mk; h0="$(git -C "$wt" rev-parse HEAD)"; call
if [ "$state" = current ] && [ "$(git -C "$wt" rev-parse HEAD)" = "$h0" ]; then ok "1 a branch that already contains main: state current, HEAD unchanged"; else bad "1 current" "state=[$state] note=[$note]"; fi

# 2. merged: main changed fort/scripts; the host merge lands it.
mk; main_moves
if ! contains_main; then ok "2pre positive control: before the launcher's merge the branch does NOT contain main"; else bad "2pre" "the fixture branch already contains main; case 2 would be vacuous"; fi
call
if [ "$state" = merged ] && contains_main && [ "$(cat "$wt/fort/scripts/fleet.sh")" = "v2 from main" ] && ! in_merge; then ok "2 main changed fort/scripts: state merged, the branch contains main and carries main's fort/scripts"; else bad "2 merged" "state=[$state] note=[$note]"; fi
if git -C "$wt" log -1 --format=%s | grep -q '^E2E-s1: merge main into bead/s1 before the sitting (Proofdelve ForgeOs-guue7, by workbench.sh)$' && [ "$(git -C "$wt" rev-list --parents -n1 HEAD | wc -w)" = 3 ]; then ok "2b it is one merge commit whose message names the bead, the reason and the launcher"; else bad "2b" "$(git -C "$wt" log -1 --format=%s)"; fi
if [ -f "$wt/web/session.ts" ]; then ok "2c the session's own commit is still there"; else bad "2c" "session work lost"; fi

# 3. conflicts: left in progress for the seat, the read-only paths already written.
mk; printf 'line1\nSESSION line2\nline3\n' > "$wt/web/app.ts"; g -C "$wt" commit -qam "E2E-s1: edit app"; main_moves app; call
if [ "$state" = conflicts ] && in_merge && [ "$(git -C "$wt" diff --name-only --diff-filter=U)" = web/app.ts ]; then ok "3 a content conflict: state conflicts, the merge is LEFT IN PROGRESS, the conflicted file is web/app.ts"; else bad "3 conflicts" "state=[$state] in_merge=$(in_merge && echo yes || echo no) note=[$note]"; fi
if [ "$(cat "$wt/fort/scripts/fleet.sh")" = "v2 from main" ]; then ok "3b main's fort/scripts content is already in the worktree, written on the host"; else bad "3b" "fort/scripts/fleet.sh is [$(cat "$wt/fort/scripts/fleet.sh")]"; fi
case "$note" in *"web/app.ts"*"Do not abort it"*) ok "3c the note names the conflicted file and says not to abort" ;; *) bad "3c" "$note" ;; esac
# 3d. the seat's half works with fort/scripts READ-ONLY: resolve, add, commit.
chmod -R a-w "$wt/fort/scripts"
printf 'line1\nRESOLVED line2\nline3\n' > "$wt/web/app.ts"
if g -C "$wt" add web/app.ts && g -C "$wt" commit -qm "E2E-s1: conclude the merge" 2>"$work/err3d" && contains_main && ! in_merge; then ok "3d with fort/scripts read-only the merge can still be concluded (add the resolved file, commit)"; else bad "3d" "$(head -3 "$work/err3d")"; fi
chmod -R u+w "$wt/fort/scripts"

# 4. in-progress: somebody's unfinished merge is not touched.
mk; printf 'line1\nSESSION line2\nline3\n' > "$wt/web/app.ts"; g -C "$wt" commit -qam "E2E-s1: edit app"; main_moves app
g -C "$wt" merge --no-edit main >/dev/null 2>&1; mh0="$(cat "$(git -C "$wt" rev-parse --path-format=absolute --git-path MERGE_HEAD)")"; st0="$(git -C "$wt" status --porcelain | sha256sum)"
call
if [ "$state" = in-progress ] && in_merge && [ "$(cat "$(git -C "$wt" rev-parse --path-format=absolute --git-path MERGE_HEAD)")" = "$mh0" ] && [ "$(git -C "$wt" status --porcelain | sha256sum)" = "$st0" ]; then ok "4 a merge already in progress: state in-progress, MERGE_HEAD and the tree untouched"; else bad "4 in-progress" "state=[$state] note=[$note]"; fi

# 5. refused: uncommitted work in the way. Nothing changes and the reason is kept.
mk; main_moves app; printf 'line1\nUNCOMMITTED line2\nline3\n' > "$wt/web/app.ts"; h0="$(git -C "$wt" rev-parse HEAD)"; call
if [ "$state" = refused ] && [ "$(git -C "$wt" rev-parse HEAD)" = "$h0" ] && ! in_merge && grep -q UNCOMMITTED "$wt/web/app.ts"; then ok "5 uncommitted work overlapping main's change: state refused, HEAD unchanged, no merge started, the work intact"; else bad "5 refused" "state=[$state] note=[$note]"; fi
case "$note" in *"main is NOT merged"*) ok "5b the note says main is not merged and carries git's reason" ;; *) bad "5b" "$note" ;; esac

# 6. uncommitted work that does not overlap rides through a clean merge.
mk; main_moves; printf 'scratch\n' > "$wt/web/other.ts"; call
if [ "$state" = merged ] && contains_main && [ "$(cat "$wt/web/other.ts")" = scratch ]; then ok "6 uncommitted work elsewhere survives a clean merge"; else bad "6" "state=[$state] note=[$note]"; fi

# 7. THE CALL SITE AND THE PROMPT.
a="$(grep -n '^  wb_merge_main "\$wt" "\$bead"$' "$subject" | cut -d: -f1)"; b="$(grep -n '^  wb_mask "\$REPO" "\$wt" ||' "$subject" | cut -d: -f1)"; c="$(grep -n 'symbolic-ref --short -q HEAD' "$subject" | head -1 | cut -d: -f1)"
if [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$c" -lt "$a" ] && [ "$a" -lt "$b" ]; then ok "7 main() merges after the branch check and before the mask is built (so it runs unmasked, on the host)"; else bad "7 call site" "merge call [$a], branch check [$c], wb_mask [$b]"; fi
if grep -q 'launch+=(--append-system-prompt "MAIN AT LAUNCH (Proofdelve ForgeOs-guue7; state: \$wb_merge_state): \$wb_merge_note")' "$subject"; then ok "7b the seat is told the merge state at launch"; else bad "7b" "no MAIN AT LAUNCH prompt line"; fi
p="$(bash -c 'source "$1"; wb_prompt fortkit-x9 /wt opus' _ "$subject" 2>/dev/null)"
case "$p" in *"reopen it with fort/scripts/workbench.sh fortkit-x9"*"NEVER route around it"*) ok "7c the end-of-sitting rule tells the seat to ask for a reopen, and still forbids routing around" ;; *) bad "7c" "the prompt lacks the reopen instruction" ;; esac

echo "RESULT workbench-merge-harness: $pass pass / $fail fail / $notrun not run (subject: $subject)"
[ "$fail" = 0 ] && [ "$notrun" = 0 ]
