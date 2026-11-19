#!/bin/bash
# Open a Workbench sitting: the Overseer's attended implementation seat.
# Usage: fort/scripts/workbench.sh [--from-main | <session-bead>]
#   With no argument: files a new session bead "Workbench <date>" (assignee
#   dunmar, labels workbench and lands-on-review), cuts
#   fortkit-worktrees/<suffix> on branch bead/<suffix>, and starts the Workbench
#   Lathewarm in that worktree. The branch is cut from main, or, if an earlier
#   sitting's branch has not landed and the Overseer says yes at the prompt,
#   from that branch (Proofdelve ForgeOs-6niaz part D). --from-main declines the offer.
#   With a bead id: resumes that session bead in its existing worktree (or
#   re-creates the worktree from its surviving branch).
#
# Proofdelve ForgeOs-9srgz, Regent edict 2026-11-09, the Overseer present. Seat law:
# fort/seats/workbench.md. Charter: the Seats table row and "Workbench flow".
#
# WHAT THIS LAUNCHER GUARANTEES, AND HOW:
#  1. ATTENDED ONLY. It refuses inside any seat mask (77), so no seat, the
#     fleet or the supervisor can open a sitting; nothing schedules it.
#  2. THE MAYOR'S SECRETS POSTURE, through the shared lib and mayor.sh's own
#     arguments (the Keep signing token masked).
#  3. ONE TREE. The session worktree is declared with --rw-tree, which grants
#     it, carves the constitution read-only inside it, and NARROWS the grant:
#     every other worktree (the Forges') stays read-only to this seat. THIS
#     HOLDS IN THE `full` POSTURE ONLY (the Warden, finding 5): under `secrets-only`
#     $HOME is writable by the experiment's design, so the Forges' worktrees are
#     too; scripts/workbench-mask-harness.sh asserts the narrowing under full.
#  4. THE FLEET STEERS AROUND THE SITTING. While this launcher runs,
#     $FLEET_STATE/workbench.live names its pid, bead and worktree; fleet.sh
#     keeps dispatching, and its touch-set guard holds any fleet bead whose
#     files overlap the sitting's live set (bead/<sfx>'s diff from main plus
#     the worktree's uncommitted paths). The Overseer's Q2, as corrected at the
#     sitting: "keep running". The file is removed on exit; a stale file whose
#     pid is gone, or a reused pid that is not this launcher, is ignored.
#  5. THE SITTING IS IN THE RECORD. session.start and session.end under actor
#     dunmar, seat workbench. The session runs as a CHILD, never exec, so the
#     EXIT trap fires (bin/regent's fortkit-nvk lesson), and SIGHUP is CAUGHT
#     here with a no-op handler, not ignored: the launcher survives a dropped
#     terminal to remove the live marker and close the record, while the
#     session itself gets the default disposition back and ends with its
#     terminal. An IGNORED HUP is inherited by every child, so the claude
#     session would have outlived the Overseer, against rule 1 (the Warden, finding 6
#     on the docket review).
#
# NO UNMASKED ESCAPE HATCH. mayor.sh has MAYOR_NO_MASK for pushing; this seat
# never pushes, so it has none.

workbench_actor() { printf '%s' 'dunmar'; }   # named by the Regent at the re-founding, 2026-11-18 (docket Q1)

# wb_mask <repo> <worktree>: fills the global mask[] exactly as the session
# gets it. A function so scripts/workbench-mask-harness.sh probes the SHIPPED
# construction and not a copy of it.
wb_mask() {
  local repo="$1" wt="$2" keep_token
  mask=()
  # shellcheck source=fort/scripts/lib/seat-sandbox.sh
  # shellcheck disable=SC1091  # resolved at runtime; build_mask fills mask[]
  source "$repo/fort/scripts/lib/seat-sandbox.sh" || return 70
  # Spelled as mayor.sh spells it (Proofdelve ForgeOs-o6ky.5): this launcher runs where
  # the Keep's install ran, on the host.
  keep_token="${XDG_CONFIG_HOME:-$HOME/.config}/civ-keep/signing-token"
  build_mask claude "$repo" --rw-tree "$wt" --mask-file "$keep_token" || return $?
  # The Overseer's atuin PreToolUse hook writes its history DB on every Bash
  # call (Proofdelve ForgeOs-sa14); this seat loads user settings as the Mayor does.
  [ -d "$HOME/.local/share/atuin" ] && mask+=(--bind "$HOME/.local/share/atuin" "$HOME/.local/share/atuin")
  mask_env claude
  # THE SEAT MARKER AND ACTOR, SET HERE AND NOT THROUGH seat_identity(): the
  # lib is one file across four forts and this seat exists in one of them
  # ("deltas the shared list cannot know", the lib's own header). Any
  # non-empty FORT_MASKED makes mayor.sh, fleet.sh, the supervisor, the
  # airlock runner and the deploy script refuse.
  mask+=(--setenv FORT_MASKED workbench --setenv BEADS_ACTOR "$(workbench_actor)")
  # Proofdelve ForgeOs-jfqu4.8: the compile cache is keyed by path and never hits across
  # worktrees; forge.sh disables it the same way.
  mask+=(--setenv NODE_DISABLE_COMPILE_CACHE 1)
  seat_build_env
}

wb_prompt() {  # $1 bead, $2 worktree, $3 model
  printf '%s' "You are Dunmar Trestle (they/them), the Workbench of Manyhalls, the fortkit fort: implementation WITH the Overseer present, in his interactive session. Your session bead is $1, your worktree is $2 on branch bead/${1##*-}, and the launcher pinned the model '$3'; name exactly that string wherever a record asks for the model. Follow fort/seats/workbench.md exactly. Session start: read fort/charter.md, fort/memory/current.md, fort/seats/workbench.md, bd show $1, and the latest fort/handoffs/workbench-*.md if this sitting resumes one; then ask Justin what he wants built. Build it now, show it, change it while he watches. Commit often, path-scoped, on your branch only, each commit naming its bead; never commit to main, never merge into main, never push, never publish. Child beads for anything that outlives the sitting (bd create --parent $1), claimed as dunmar; Claude Code's own task list is allowed for in-sitting steps only. Gates are unchanged: the factory and the civilization tooling (bin/, civ/, templates/, schema/, skills/) and the fort's constitution may be written with Justin watching and land only on his recorded signature. The Keep's signing token is his secret: never read it and never POST /api/sign. End of sitting: merge main into your branch and resolve conflicts (IF that merge fails with 'unable to unlink ... Read-only file system' or 'fatal: read-tree failed', main has touched a path that is kernel read-only in your mask -- fort/scripts, .claude, fort/profiles, .git/config or hooks; that is the control working: abort the merge, then tell Justin and ask him to close this sitting and reopen it with fort/scripts/workbench.sh $1, because the launcher merges main on the HOST before it starts you (Proofdelve ForgeOs-guue7); if he would rather not, leave it to the fleet's own refresh, which merges main on the host before it verifies. NEVER route around it with skip-worktree, a hand-built tree or a cherry-pick), run fort/scripts/verify.sh in your worktree and see it green on the tip, write fort/handoffs/workbench-<date>-${1##*-}.md with the five headings State of work, Verified facts, Next actions, Open risks / questions, Failed attempts (State of work lists every bead with its commits), commit it, and tell Justin the session bead id so it can be queued with fort/scripts/fleet.sh --review-only $1. If fort/scripts/verify.sh will not RUN in your worktree, stop and say so (Proofdelve ForgeOs-u65j.4). While you are live the fleet keeps running and holds any fleet bead whose files overlap your branch or your uncommitted work, so the files you touch are what it steers around."
}

# THE SESSION BEAD CARRIES A LANDING CLASS (Proofdelve ForgeOs-6niaz part C, Regent
# sitting 2026-11-11, the Overseer's approval on the bead). Filed with
# `workbench` alone, the fleet read a clean review as UNCLASSIFIED and held it
# for a signature (Proofdelve ForgeOs-amtee, 2026-11-11 10:39). lands-on-review is safe as
# the default because the gate is the Warden's, not the label's: a range that
# touches a gated surface (auth, deal visibility, data-mutating migrations, the
# constitution) still draws her mandatory ESCALATE, and the fleet holds it for
# his signature. Prints the new bead id; empty on failure.
wb_session_labels() { printf '%s' 'workbench,lands-on-review'; }
wb_create_session_bead() {  # $1 repo
  bd -C "$1" create --title "Workbench $(date +%F)" --type task --priority 1 \
    --description "Workbench sitting opened by the Overseer with fort/scripts/workbench.sh (Proofdelve ForgeOs-9srgz). The branch bead/<suffix> is the landing unit: one Warden review of the whole range via fleet.sh --review-only. Child beads carry the sitting's named work. It is filed lands-on-review (Proofdelve ForgeOs-6niaz): a range touching a gated surface still ESCALATES and waits for the Overseer's signature." \
    --assignee "$(workbench_actor)" --labels "$(wb_session_labels)" --actor "$(workbench_actor)" --json 2>/dev/null | jq -r '.id // empty' 2>/dev/null || true
}

# THE STACKING OFFER (Proofdelve ForgeOs-6niaz part D). Two sittings cut from main while
# the first had not landed conflicted in three CSS files (jj0i9 vs amtee,
# 2026-11-11). So a new sitting looks for the newest earlier session branch
# that has NOT landed -- a `workbench` bead that is not closed, whose branch
# bead/<suffix> exists and carries commits main does not -- and offers to cut
# from it. The new sitting's review range then includes the earlier one's
# commits, which is fine: if the earlier one lands first they drop out of the
# diff, and if not they are reviewed as part of this range. Child beads carry
# the label too and have no branch of their own, so they never qualify.
wb_unlanded_branch() {  # $1 repo -> prints "<bead> <suffix> <commits ahead> <status>" of the newest candidate, or nothing
  local repo="$1" id st sfx ahead ts best="" best_ts=0
  while read -r id st; do
    [ -n "$id" ] || continue
    sfx="${id##*-}"
    git -C "$repo" rev-parse --verify --quiet "bead/$sfx" >/dev/null || continue
    ahead="$(git -C "$repo" rev-list --count "main..bead/$sfx" 2>/dev/null || echo 0)"
    [ "${ahead:-0}" -gt 0 ] 2>/dev/null || continue
    ts="$(git -C "$repo" log -1 --format=%ct "bead/$sfx" 2>/dev/null || echo 0)"
    if [ "${ts:-0}" -gt "$best_ts" ]; then best_ts="$ts"; best="$id $sfx $ahead ${st:-unknown}"; fi
  done < <(bd -C "$repo" list --label workbench --status open,in_progress,blocked,deferred --json --limit 0 2>/dev/null \
             | jq -r 'if type == "array" then .[] else empty end | select(.id) | "\(.id) \(.status // "unknown")"' 2>/dev/null)
  [ -n "$best" ] && printf '%s\n' "$best"
  return 0
}
# wb_choose_base <repo> <from_main 0|1> <interactive 0|1>: prints the ref to cut
# from (main, or bead/<suffix>); the question and every note go to stderr, the
# answer is read from stdin. DEFAULT YES only when someone is at the prompt;
# with no terminal it cuts from main, so nothing unattended ever stacks
# (refinement c, approved at the sitting).
wb_choose_base() {
  local repo="$1" from_main="$2" interactive="$3" cand id sfx ahead st ans=""
  cand="$(wb_unlanded_branch "$repo")"
  if [ -z "$cand" ]; then printf 'main\n'; return 0; fi
  read -r id sfx ahead st <<< "$cand"
  if [ "$from_main" = 1 ]; then
    echo "workbench.sh: an earlier sitting has not landed ($id, bead/$sfx, $ahead commit(s) ahead of main); --from-main given, so this sitting is cut from main" >&2
    printf 'main\n'; return 0
  fi
  if [ "$interactive" != 1 ]; then
    echo "workbench.sh: an earlier sitting has not landed ($id, bead/$sfx, $ahead commit(s) ahead of main); no terminal to ask at, so this sitting is cut from main" >&2
    printf 'main\n'; return 0
  fi
  # THE STATUS IS SHOWN (the Warden, 6niaz review finding 3): an unlanded branch may
  # be queued, held for a signature, or handed back on REQUEST-CHANGES, and the
  # Overseer decides at the prompt knowing which.
  printf 'workbench.sh: an earlier sitting has not landed: %s on bead/%s (status %s), %s commit(s) ahead of main.\nCut this sitting from bead/%s so the two do not conflict? [Y/n] ' "$id" "$sfx" "$st" "$ahead" "$sfx" >&2
  read -r ans || ans=""
  case "$ans" in
    n|N|no|NO|No) printf 'main\n' ;;
    *) printf 'bead/%s\n' "$sfx" ;;
  esac
}

# MAIN IS MERGED ON THE HOST, BEFORE THE SEAT STARTS (Proofdelve ForgeOs-guue7, Regent
# sitting 2026-11-16). Inside the seat's mask fort/scripts, .claude and the
# other host-executed paths are read-only binds, and git replaces a tracked
# file by unlinking it, so once main has changed one of them `git merge main`
# from inside the sitting fails ("unable to unlink ... Read-only file system",
# observed on Proofdelve ForgeOs-jj0i9, 2026-11-12). This launcher runs unmasked, so it
# makes that merge itself, for every launch whose branch is behind main.
#   current      the branch already contains main: nothing was done.
#   merged       main was merged cleanly; one merge commit, made here.
#   conflicts    git stopped on content conflicts. The merge is LEFT IN
#                PROGRESS for the seat to resolve and commit. The files main
#                changed under the read-only paths are already written, by
#                this process; concluding the merge only writes the index and
#                a commit, which the seat can do.
#   in-progress  a merge was already in progress in the worktree. Not touched:
#                it is somebody's unfinished work (the forge.sh lesson,
#                Proofdelve ForgeOs-lw8x).
#   refused      git would not start the merge (uncommitted work in the way,
#                or main could not be read). Nothing changed; the reason is
#                kept. The sitting still opens, and the seat is told.
# Sets wb_merge_state and wb_merge_note. Never fails the launch.
wb_merge_state=""; wb_merge_note=""
wb_merge_main() {  # $1 worktree, $2 session bead
  local wt="$1" bead="$2" sfx="${2##*-}" behind mh before after out rc=0
  mh="$(git -C "$wt" rev-parse --path-format=absolute --git-path MERGE_HEAD 2>/dev/null || true)"
  if [ -n "$mh" ] && [ -e "$mh" ]; then
    wb_merge_state=in-progress
    wb_merge_note="a merge was ALREADY in progress in this worktree when the sitting opened; the launcher did not touch it. Finish it (resolve, git add, git commit) or ask Justin before anything else."
    return 0
  fi
  if ! behind="$(git -C "$wt" rev-list --count HEAD..main 2>/dev/null)"; then
    wb_merge_state=refused
    wb_merge_note="the launcher could not compare this branch with main, so main was NOT merged before the sitting."
    return 0
  fi
  if [ "$behind" = 0 ]; then wb_merge_state=current; wb_merge_note="this branch already contains main."; return 0; fi
  before="$(git -C "$wt" rev-parse HEAD 2>/dev/null || true)"
  out="$(git -C "$wt" merge --no-edit -m "$bead: merge main into bead/$sfx before the sitting (Proofdelve ForgeOs-guue7, by workbench.sh)" main 2>&1)" || rc=$?
  after="$(git -C "$wt" rev-parse HEAD 2>/dev/null || true)"
  if [ "$rc" = 0 ]; then
    wb_merge_state=merged
    wb_merge_note="the launcher merged main ($behind commit(s)) into this branch on the host before starting you; the merge commit is $(git -C "$wt" rev-parse --short HEAD 2>/dev/null)."
  elif [ -n "$mh" ] && [ -e "$mh" ]; then
    wb_merge_state=conflicts
    wb_merge_note="the launcher started merging main ($behind commit(s)) on the host and git stopped on content conflicts in: $(git -C "$wt" diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' '). THE MERGE IS IN PROGRESS: resolve those files, git add them and git commit before any other work. Do not abort it: you cannot start it again from inside your mask."
  else
    wb_merge_state=refused
    wb_merge_note="the launcher tried to merge main ($behind commit(s) behind) on the host and git refused before starting (exit $rc): $(printf '%s' "$out" | head -3 | tr '\n' ' ' | cut -c1-300). Nothing was changed$([ "$before" = "$after" ] || printf ' EXCEPT that HEAD moved from %s to %s' "$before" "$after"). main is NOT merged."
  fi
  return 0
}

wb_live_file() { printf '%s' "${FLEET_STATE:-$HOME/.local/state/manyhalls-fleet}/workbench.live"; }

main() {
  # HOISTED ABOVE EVERYTHING (fortkit-px7e): a refusal placed below the repo
  # resolution is never evaluated in a directory that is not a checkout.
  if [ -n "${FORT_MASKED:-}" ]; then
    echo "workbench.sh: REFUSED — already inside the '$FORT_MASKED' seat mask; the Workbench is opened by the Overseer by hand, never by a seat (Proofdelve ForgeOs-9srgz)" >&2
    exit 77
  fi
  case "${1:-}" in -h|--help) awk 'NR>1 && /^[^#]/{exit} NR>1{print}' "$0"; exit 0 ;; esac
  local from_main=0
  if [ "${1:-}" = --from-main ]; then from_main=1; shift; fi
  [ "$#" -le 1 ] || { echo "workbench.sh: at most one argument, the session bead" >&2; exit 64; }
  if [ "$from_main" = 1 ] && [ -n "${1:-}" ]; then
    echo "workbench.sh: --from-main applies to a NEW sitting; a resumed sitting keeps its own branch" >&2; exit 64
  fi
  local REPO bead sfx wt model live_file owner status base=main interactive=0
  REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo /home/justin/dev/fortkit)"
  cd "$REPO" || exit 70
  model="${WORKBENCH_MODEL:-opus}"
  live_file="$(wb_live_file)"
  mkdir -p "$(dirname "$live_file")"

  # ONE SITTING AT A TIME. A second launcher would overwrite the live marker
  # and remove it on ITS exit while the first still ran.
  if [ -s "$live_file" ]; then
    owner="$(sed -n 's/^pid=//p' "$live_file" | head -1)"
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null && tr '\0' ' ' < "/proc/$owner/cmdline" 2>/dev/null | grep -q 'workbench\.sh'; then
      echo "workbench.sh: REFUSED — a Workbench sitting is already live ($(tr '\n' ' ' < "$live_file"))" >&2
      exit 75
    fi
    echo "workbench.sh: removing a stale live marker from a sitting that is gone: $(tr '\n' ' ' < "$live_file")" >&2
    rm -f "$live_file"
  fi

  if [ -n "${1:-}" ]; then
    bead="$1"
    status="$(bd -C "$REPO" show "$bead" --json 2>/dev/null | jq -r 'if type == "array" then .[0] else . end | .status // empty' 2>/dev/null || true)"
    case "$status" in
      "") echo "workbench.sh: REFUSED — bd does not know $bead" >&2; exit 66 ;;
      closed) echo "workbench.sh: REFUSED — $bead is closed; open a new sitting with no argument" >&2; exit 66 ;;
    esac
  else
    # The offer is made BEFORE the bead is filed, so a question nobody answers
    # leaves nothing behind.
    if [ -t 0 ] && [ -t 2 ]; then interactive=1; fi
    base="$(wb_choose_base "$REPO" "$from_main" "$interactive")"
    bead="$(wb_create_session_bead "$REPO")"
    [ -n "$bead" ] || { echo "workbench.sh: REFUSED — bd would not create the session bead" >&2; exit 66; }
    if [ "$base" != main ]; then
      bd -C "$REPO" comment "$bead" "Stacked on $base at the Overseer's word at the prompt (Proofdelve ForgeOs-6niaz part D): this sitting's branch is cut from that unlanded branch, so its review range includes those commits until they land." --actor "$(workbench_actor)" >/dev/null 2>&1 || true
    fi
  fi
  bd -C "$REPO" update "$bead" --status in_progress --assignee "$(workbench_actor)" --actor "$(workbench_actor)" >/dev/null 2>&1 \
    || echo "workbench.sh: WARNING could not mark $bead in_progress for $(workbench_actor) (continuing)" >&2
  sfx="${bead##*-}"; wt="$REPO-worktrees/$sfx"
  if [ ! -d "$wt" ]; then
    if git -C "$REPO" rev-parse --verify --quiet "bead/$sfx" >/dev/null; then
      git -C "$REPO" worktree add -q "$wt" "bead/$sfx" || exit 70
    else
      git -C "$REPO" worktree add -q -b "bead/$sfx" "$wt" "$base" || exit 70
    fi
  fi
  [ "$(git -C "$wt" symbolic-ref --short -q HEAD 2>/dev/null)" = "bead/$sfx" ] \
    || { echo "workbench.sh: REFUSED — $wt is not on bead/$sfx" >&2; exit 70; }

  # Proofdelve ForgeOs-guue7: bring main in on the host, where fort/scripts can be written.
  wb_merge_main "$wt" "$bead"
  echo "workbench.sh: main at launch ($wb_merge_state): $wb_merge_note" >&2
  case "$wb_merge_state" in
    merged|conflicts|refused|in-progress)
      bd -C "$REPO" comment "$bead" "workbench.sh at launch, main ($wb_merge_state): $wb_merge_note" --actor "$(workbench_actor)" >/dev/null 2>&1 || true ;;
  esac

  wb_mask "$REPO" "$wt" || { echo "workbench.sh: REFUSED — the mask could not be built" >&2; exit 70; }
  require_bwrap || exit $?

  local launch=(claude --model "$model" --append-system-prompt "$(wb_prompt "$bead" "$wt" "$model")")
  if [ "$(head -1 "$REPO/fort/scripts/sandbox-posture" 2>/dev/null | tr -d '[:space:]')" = secrets-only ] || [ "${FORT_SANDBOX:-}" = secrets-only ]; then
    launch+=(--append-system-prompt "SANDBOX POSTURE: secrets-only (Manyhalls ships the posture its machinery came with; Overseer decision 2026-11-18, fortkit-ttpk). The read-only binds still hold (fort/scripts, fort/profiles, .claude, .git/config and hooks, the airlock operations and approval stores). You have the network and a writable home; Docker is reachable and this fort's gate does not use it. Held now by these rules rather than by the kernel: never read .env* in any spelling, the Keep signing token, ~/.ssh, ~/.aws, ~/.azure or ~/.config/gh; never publish, release or act on an external account (charter gate 3); never bind-mount \$HOME, ~/.config, ~/.ssh, any .env* path or / into a container, never --privileged or --pid=host; no state-changing requests to third parties (standing order 14).")
  fi
  launch+=(--append-system-prompt "MAIN AT LAUNCH (Proofdelve ForgeOs-guue7; state: $wb_merge_state): $wb_merge_note")
  # PROMPT-FREE BECAUSE THE KERNEL IS THE BOUNDARY, and only after
  # require_bwrap succeeded (mayor.sh's reasoning, cycle 5 layer 3).
  launch+=(--dangerously-skip-permissions)

  printf 'pid=%s\nbead=%s\nworktree=%s\nstarted=%s\n' "$$" "$bead" "$wt" "$(date -Is)" > "$live_file.tmp.$$" && mv -f "$live_file.tmp.$$" "$live_file"
  fort/scripts/emit.sh session.start "The Overseer opens a Workbench sitting with the Workbench on $bead; the fleet holds beads that overlap it" -a "$(workbench_actor)" -s workbench -t "$bead" -p "{\"model\":\"$model\",\"worktree\":\"$wt\"}" 2>/dev/null || true
  # shellcheck disable=SC2064  # bead and live_file are fixed for the sitting
  trap "wb_close '$REPO' '$bead' '$live_file'" EXIT
  trap ':' HUP   # caught, not ignored: see guarantee 5 in the header
  echo "workbench.sh: sitting on $bead in $wt (model $model); fleet beads overlapping it are held while it runs" >&2
  local rc=0
  ( cd "$wt" && bwrap "${mask[@]}" -- "${launch[@]}" ) || rc=$?
  exit "$rc"
}

wb_close() {  # $1 repo, $2 bead, $3 live file. Durable writes first; the terminal is allowed to be gone.
  if [ "$(sed -n 's/^pid=//p' "$3" 2>/dev/null | head -1)" = "$$" ]; then rm -f "$3"; fi
  ( cd "$1" && fort/scripts/emit.sh session.end "the Workbench's Workbench sitting on $2 ends; the fleet stops holding beads for it" -a "$(workbench_actor)" -s workbench -t "$2" ) >/dev/null 2>&1 || true
  echo "workbench.sh: sitting on $2 closed. Queue its review with: fort/scripts/fleet.sh --review-only $2" >&2 || true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
