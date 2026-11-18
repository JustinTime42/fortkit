#!/bin/bash
# Proofdelve scratch reaper — removes what a finished or killed review left on
# disk, and the bead worktrees whose work has landed and whose bead is closed.
# ForgeOs-nv0j (Regent edict 2026-09-12, gate 6), the durable half of incident
# ForgeOs-7gag; ForgeOs-mpaw's worktree half rides on the same timer.
#
# WHAT THIS IS. A host-level process fired hourly by
# fort/systemd/proofdelve-scratch-reaper.timer. Two sweeps, each refusing more
# often than it acts:
#
#   A. WARDEN SCRATCH. warden.sh copies the whole repo per review into
#      $warden_root/<sfx> (and, before 2026-09-12, into /tmp/warden-<sfx>),
#      builds and tests there, and since nv0j removes the copy in its own EXIT
#      trap. What this sweep sees is therefore ONLY what a SIGKILL left, plus the
#      pre-nv0j litter under /tmp. A copy is removed when BOTH hold: it is older
#      than $REAPER_MIN_AGE_MIN minutes (default 120) -- measured from the
#      newest of its lock, lock.info and transcript, because rsync -a gives the
#      copy itself the SOURCE tree's mtime -- and nobody holds its
#      review's lock -- warden.sh takes `flock` on <sfx>.lock BEFORE it creates
#      the copy and holds it for the whole review, so a lock that `flock -n` can
#      take is a review that is over, however it ended. The small files beside
#      the copy (<sfx>.log, .log.record, .log.result.json, .log.err,
#      .log.settings.json, .lock, .lock.info) are the review's record and are
#      never touched. The lock is HELD across the removal, so a review of the
#      same bead starting in that window refuses (exit 75) rather than rsyncing
#      into a tree being deleted.
#
#   B. BEAD WORKTREES. The list comes from `scripts/stranded-sweep.sh
#      --reapable` and from nowhere else: a worktree on a bead/* branch that is
#      merged into main (ahead=0) whose bead is CLOSED. This file re-derives none
#      of that (ForgeOs-mpaw: reuse it, never re-derive). It then refuses on its
#      own account when the tree is DIRTY (any status line, untracked included),
#      when its branch is NOT an ancestor of main (re-checked here, never taken
#      from the list), or when a launcher holds its .forge.lock, and otherwise runs
#      `git worktree remove` WITHOUT --force followed by `git branch -d` -- the
#      lowercase form, which refuses an unmerged branch by itself. THE BRANCH GOES
#      WITH THE WORKTREE, DELIBERATELY: forge.sh cuts a reused bead with
#      `git worktree add "$wt" -b bead/<sfx>` when the directory is missing, so a
#      worktree removed with its branch left behind makes the next dispatch of
#      that bead die rc=255 'a branch named bead/<sfx> already exists' (measured
#      2026-09-09, the w7u5 reaping sitting). Remove both or neither.
#
#   C. HOST /tmp HYGIENE (ForgeOs-jfqu4.8 with ForgeOs-lmgue, Regent docket
#      2026-10-22 item B). The host /tmp is a tmpfs with a per-user quota
#      (12764M) and filling it halted the fleet three times (2026-10-16 twice,
#      2026-10-22). The root cause, Node's compile cache, is now disabled in
#      every fleet, Forge, nightly and verifier run (the node_compile_cache
#      block in those four launchers); this is the backstop. Each part refuses
#      more than it acts:
#        - /tmp/forge-<sfx>.log older than $REAPER_TMP_LOG_DAYS days (7) is
#          removed, unless a launcher holds <worktrees>/<sfx>/.forge.lock;
#        - /tmp/verify-fail-<step>-<pid>.log older than that is removed, unless
#          today's or yesterday's event stream names it (the fleet cites these
#          files as evidence);
#        - /tmp/node-compile-cache is removed when it is over
#          $REAPER_NODE_CACHE_MAX_MB (1024) AND no process has a file in it
#          open (read from /proc/*/fd), renamed aside first so a node that
#          starts mid-removal begins a fresh one.
#      A FIXTURE REPO WITHOUT A FIXTURE TMP DIR NEVER TOUCHES THE REAL /tmp:
#      with REAPER_REPO set and REAPER_TMP_DIR unset, sweep C and the alarm
#      below are skipped and the journal says so (the airlock's AIRLOCK_ROOT
#      rule, for the same reason: a harness that predates this sweep must not
#      prune the host from inside a verifier).
#
#   THE /tmp USAGE ALARM. Every run measures this user's usage of the /tmp
#      quota (`quota -w -p -f`, or df when no quota is set) and emits ONE
#      `incident` when it reaches a band (80, 90, 95 percent) it has not
#      reached yet today, so the next fill is seen before it halts a verify.
#      fleet.sh asks for the same check at the top of every pass with
#      `--tmp-check`, which measures and alarms and touches nothing. The
#      band and date are kept in $REAPER_STATE/tmp-alarm (under
#      ~/.local/share, which no seat mask grants).
#
# WHAT IT NEVER DOES: read or write the fleet's state directory, the halt file,
# or bd. It does not know what the fleet is doing and does not need to: a live
# review holds its lock, a live Forge holds its .forge.lock, and everything
# else it might remove is finished by construction.
#
# QUIET WHEN THERE IS NOTHING TO DO. One stderr line per run for the journal;
# a `progress` event in the fort's stream ONLY when something was removed or a
# removal FAILED (the supervisor's precedent: a stream that says "nothing"
# twenty-four times a day is a stream nobody reads, fortkit-or2.8). A listed
# worktree whose directory is ABSENT while its branch survives (the rc=255
# shape) is named in the journal and counted in the summary line but raises NO
# event -- decided, not overlooked (Tova, round two, finding 2): it is a
# persistent state this reaper cannot repair, so an event per firing would be
# 24 identical lines a day until a person acts, which is fortkit-or2.8 exactly. A FAILED
# removal -- the command ran and the thing is still there -- is reported as
# failed, never as reaped and never as refused (ForgeOs-w7u5's four outcomes).
#
# IT REFUSES FROM A MASKED SEAT. The scratch root is read-only inside every seat
# mask since round two of ForgeOs-nv0j (it moved off the ~/.cache grant), so
# sweep A could do nothing from a seat -- but $root-worktrees is rw in the
# Mayor's mask (lib/seat-sandbox.sh RW_PATHS, the fortkit-1q9 grant), so a
# masked Mayor COULD run sweep B and remove worktrees and branches; she must
# not, because a seat deleting trees on a bd-derived list is the agent-accident
# class the charter ranks first. The marker is the control, exactly as in
# fleet.sh. (Tova Marrowassay, round two: the earlier sentence here cited the
# scratch root as the rw grant, which round two's own fold made false.)
#
# Usage:
#   fort/scripts/scratch-reaper.sh              # one sweep, as the timer does it
#   fort/scripts/scratch-reaper.sh --dry-run    # decide everything, remove nothing
#   fort/scripts/scratch-reaper.sh --tmp-check  # the /tmp usage alarm only (fleet.sh, every pass)
# Exit codes: 0 swept (including nothing to do). 64 refused: masked seat, or
#   the worktree list could not be obtained (sweep A still runs; the refusal is
#   named on stderr). 1 at least one removal FAILED.
#
# Environment (harness use; see scripts/scratch-reaper-harness.sh):
#   REAPER_WARDEN_ROOT   the warden scratch root (default: warden.sh's)
#   REAPER_LEGACY_ROOT   directory holding pre-nv0j warden-<sfx> dirs (default /tmp;
#                        set to a nonexistent path to skip). RETIRE this half once
#                        /tmp/warden-* has been empty for a week.
#   REAPER_REPO          the repository whose worktrees sweep B considers; its
#                        scripts/stranded-sweep.sh is the one run
#   REAPER_MIN_AGE_MIN   minimum age of a warden scratch copy, minutes (120)
#   REAPER_TMP_DIR       the /tmp sweep C and the alarm consider (default /tmp)
#   REAPER_WORKTREES     where a forge log's bead worktree lives ($root-worktrees)
#   REAPER_TMP_LOG_DAYS  minimum age of a forge or verify-fail log, days (7)
#   REAPER_NODE_CACHE_MAX_MB  node-compile-cache size that is removed (1024)
#   REAPER_TMP_USAGE     "<used_kb> <limit_kb>" instead of measuring (harness)
#   REAPER_TMP_ALARM_PCT the lowest alarm band (80)
#   REAPER_STATE         where the alarm keeps its last band (~/.local/share/proofdelve/reaper)

set -uo pipefail

if [ -n "${FORT_MASKED:-}" ]; then
  echo "scratch-reaper.sh: REFUSED — this is a masked seat session (FORT_MASKED=${FORT_MASKED})." >&2
  echo "  The reaper deletes review scratch and merged worktrees on the host. It runs from" >&2
  echo "  its systemd user timer or the Overseer's terminal, never from a seat." >&2
  exit 64
fi

dry=0; tmp_check_only=0
case "${1:-}" in
  "") ;;
  --dry-run) dry=1 ;;
  --tmp-check) tmp_check_only=1 ;;
  -h|--help) awk '/^[^#]/{exit} {print}' "$0"; exit 0 ;;
  *) echo "scratch-reaper.sh: unknown argument: $1" >&2; exit 64 ;;
esac

root="${REAPER_REPO:-/home/justin/dev/ForgeOs}"
# The same expression fort/scripts/warden.sh and fort/scripts/fleet.sh carry as
# warden_root=; governor-harness.sh holds those two byte-equal, and this one is
# overridable so a harness can point the sweep at a fixture.
warden_root="${REAPER_WARDEN_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/proofdelve/warden}"
legacy_root="${REAPER_LEGACY_ROOT:-/tmp}"
min_age="${REAPER_MIN_AGE_MIN:-120}"
emit="$root/fort/scripts/emit.sh"

reaped=0; kept_young=0; kept_live=0; kept_dirty=0; failed=0; refused_list=0; absent_dir=0
tmp_removed=0; tmp_freed_kb=0
lines=()
note() { lines+=("$1"); echo "$1" >&2; }

tmpdir="${REAPER_TMP_DIR:-/tmp}"
tmp_sweep=1
if [ -n "${REAPER_REPO:-}" ] && [ -z "${REAPER_TMP_DIR:-}" ]; then
  tmp_sweep=0
  echo "scratch-reaper.sh: REAPER_REPO is set without REAPER_TMP_DIR: a fixture repo never touches the real /tmp, so sweep C and the /tmp alarm are skipped" >&2
fi
reaper_state="${REAPER_STATE:-${XDG_DATA_HOME:-$HOME/.local/share}/proofdelve/reaper}"

# ---------------------------------------------------------------------------
# The /tmp usage alarm (see the header). Exit 0 always: an alarm that could
# fail the caller would turn a full disk into a dead fleet.
# ---------------------------------------------------------------------------
tmp_usage() {  # -> "used_kb limit_kb source", or nothing when unmeasurable
  local q
  if [ -n "${REAPER_TMP_USAGE:-}" ]; then printf '%s fixture' "$REAPER_TMP_USAGE"; return 0; fi
  # quota -w -p prints one row per filesystem: name, blocks (KiB), quota, limit, ...
  q="$(quota -w -p -f "$tmpdir" 2>/dev/null | awk 'NF >= 4 && $2 ~ /^[0-9]+$/ { l = ($4 > 0) ? $4 : $3; if (l > 0) { print $2, l; exit } }')" || q=""
  if [ -n "$q" ]; then printf '%s quota' "$q"; return 0; fi
  q="$(df -kP "$tmpdir" 2>/dev/null | awk 'NR == 2 { print $3, $2 }')" || q=""
  [ -n "$q" ] && printf '%s df' "$q"
  return 0
}
tmp_alarm() {
  [ "$tmp_sweep" = 1 ] || return 0
  local u used limit src pct band last_day last_band today floor
  u="$(tmp_usage)"; read -r used limit src <<<"$u"
  if ! [[ "${used:-}" =~ ^[0-9]+$ && "${limit:-}" =~ ^[0-9]+$ ]] || [ "$limit" -eq 0 ]; then
    echo "scratch-reaper.sh: /tmp usage could not be measured (quota and df both failed); no alarm possible this run" >&2; return 0
  fi
  pct=$(( used * 100 / limit )); floor="${REAPER_TMP_ALARM_PCT:-80}"
  band=0
  for b in 95 90 "$floor"; do [ "$pct" -ge "$b" ] && { band="$b"; break; }; done
  [ "$tmp_check_only" = 1 ] || echo "scratch-reaper.sh: /tmp at ${pct}% of the limit ($((used / 1024)) of $((limit / 1024)) MiB, $src)" >&2
  [ "$band" -gt 0 ] || return 0
  today="$(date +%F)"; last_day=""; last_band=0
  [ -f "$reaper_state/tmp-alarm" ] && read -r last_day last_band < "$reaper_state/tmp-alarm"
  if [ "$last_day" = "$today" ] && [ "${last_band:-0}" -ge "$band" ]; then return 0; fi
  mkdir -p "$reaper_state" && printf '%s %s\n' "$today" "$band" > "$reaper_state/tmp-alarm"
  echo "scratch-reaper.sh: ALARM /tmp at ${pct}% (band ${band}%)" >&2
  ( cd "$root" && "$emit" incident "Host /tmp is at ${pct}% of this user's limit ($((used / 1024)) of $((limit / 1024)) MiB, by $src): a fill makes the next verify unrunnable and halts the fleet (ForgeOs-lmgue, ForgeOs-jfqu4.8). The hourly scratch reaper prunes old forge and verify-fail logs and an oversized /tmp/node-compile-cache; look at du -xsh /tmp/* on the host for anything else." -a fleet -s fleet \
      -p "{\"pct\":$pct,\"band\":$band,\"used_kb\":$used,\"limit_kb\":$limit,\"source\":\"$src\"}" ) || true
}
if [ "$tmp_check_only" = 1 ]; then tmp_alarm; exit 0; fi

# Can the lock be taken? Yes means no review holds it (or no lock file exists).
lock_free() {  # $1 lock path
  [ -e "$1" ] || return 0
  flock -n 9 9<"$1"
}

# ---------------------------------------------------------------------------
# A. warden scratch copies: $root/<sfx>/ with lock $root/<sfx>.lock (nv0j) and
#    $legacy/warden-<sfx>/ with lock $legacy/warden-<sfx>.lock (pre-nv0j)
# ---------------------------------------------------------------------------
# THE AGE IS THE REVIEW'S, NOT THE DIRECTORY'S. warden.sh builds the copy with
# `rsync -a`, which PRESERVES the source tree's mtime, so a copy made one minute
# ago carries the repo root's timestamp and reads as hours or days old (measured
# 2026-09-12 on the first smoke of the installed launcher: copy at 19:39, dir
# mtime 18:19). What the launcher writes at launch and during the review is the
# lock, its .info, and the transcript the session streams into; the newest of
# those, or the directory itself, is when this review last did anything.
newest_mtime() {  # $@ paths -> epoch seconds of the newest that exists (0 if none)
  local p m best=0
  for p in "$@"; do
    [ -e "$p" ] || continue
    m="$(stat -c %Y "$p" 2>/dev/null || echo 0)"
    [ "$m" -gt "$best" ] && best="$m"
  done
  echo "$best"
}

sweep_scratch() {  # $1 dir, $2 lock, $3 label
  local d="$1" lock="$2" label="$3" age last
  [ -d "$d" ] || return 0
  last="$(newest_mtime "$d" "$lock" "$lock.info" "${lock%.lock}.log")"
  age=$(( ( $(date +%s) - last ) / 60 ))
  if [ "$age" -lt "$min_age" ]; then
    kept_young=$((kept_young + 1)); return 0
  fi
  if ! lock_free "$lock"; then
    kept_live=$((kept_live + 1))
    note "KEPT (review live, lock held) $label ${age}min"
    return 0
  fi
  if [ "$dry" = 1 ]; then note "WOULD REMOVE $label ${age}min"; reaped=$((reaped + 1)); return 0; fi
  # THE LOCK IS HELD ACROSS THE REMOVAL (Tova, round one, finding 5): a probe
  # that takes and drops it leaves a window in which a review of the same bead
  # can start, take the lock, and rsync into a tree this rm is still deleting.
  # Held, that review sees the lock taken and refuses with exit 75 -- a false
  # refusal for the few seconds of the rm, which fails closed. No lock file
  # (never happens for a copy warden.sh made; possible for hand-made litter)
  # means nothing to hold.
  if [ -e "$lock" ]; then
    ( flock -n 9 || exit 75; rm -rf "$d" 2>/dev/null; exit 0 ) 9<"$lock" || { kept_live=$((kept_live + 1)); note "KEPT (lock taken between probe and removal) $label"; return 0; }
  else
    rm -rf "$d" 2>/dev/null || true
  fi
  if [ -e "$d" ]; then
    failed=$((failed + 1)); note "FAILED to remove $label (${age}min) — it is still there"
  else
    reaped=$((reaped + 1)); note "REMOVED $label (${age}min, lock free)"
  fi
}

for d in "$warden_root"/*/; do
  [ -d "$d" ] || continue
  d="${d%/}"; sfx="$(basename "$d")"
  sweep_scratch "$d" "$warden_root/$sfx.lock" "warden scratch $d"
done
for d in "$legacy_root"/warden-*/; do
  [ -d "$d" ] || continue
  d="${d%/}"; sfx="${d##*/warden-}"
  sweep_scratch "$d" "$legacy_root/warden-$sfx.lock" "legacy warden scratch $d"
done

# ---------------------------------------------------------------------------
# B. merged-and-closed bead worktrees, listed by stranded-sweep.sh --reapable
# ---------------------------------------------------------------------------
sweep_worktrees() {
  local out rc branch id wt
  # Exit 1 there means a STRANDED-* unit exists, which is somebody else's
  # finding and does not invalidate the REAPABLE lines; exit 3 is a refusal (bd
  # or git could not be asked) and means this sweep learned nothing.
  local err
  err="$(mktemp)"
  out="$("$root/scripts/stranded-sweep.sh" --repo "$root" --reapable 2>"$err")"; rc=$?
  if [ "$rc" -eq 3 ]; then
    refused_list=1
    note "REFUSED worktree sweep: stranded-sweep.sh --reapable exited 3 (bd or git would not answer); no worktree was considered. Its stderr: $(tr '\n' ' ' < "$err" | cut -c1-300)"
    rm -f "$err"; return 0
  fi
  rm -f "$err"
  while read -r _ branch id wt _; do
    [ -n "${wt:-}" ] || continue
    wt="${wt#worktree=}"
    # A LISTED WORKTREE WHOSE DIRECTORY IS GONE IS THE rc=255 SHAPE ALREADY
    # (Tova, round one, finding 6): the branch survives with no tree, so a
    # re-dispatch of that bead dies on `git worktree add -b`. Not this reaper's
    # to repair (it never made the state), but never silent: named, counted.
    if [ ! -d "$wt" ]; then
      # Only when the branch really does survive: a list is a snapshot, and an
      # entry this very sweep fully reaped a moment ago is not an orphan.
      if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
        absent_dir=$((absent_dir + 1)); note "ABSENT DIRECTORY $wt but branch $branch remains ($id) — a re-dispatch of this bead would refuse (forge.sh rc=255); git worktree prune + branch -d by hand"
      fi
      continue
    fi
    # THE MERGE IS RE-CHECKED HERE, NOT TAKEN FROM THE LIST (finding 6): the
    # list said ahead=0 minutes ago; main may have moved, or the list may be a
    # stub. `git branch -d` refuses an unmerged branch too, but by then the
    # worktree is gone -- which is exactly the rc=255 state. Ask first.
    if ! git -C "$root" merge-base --is-ancestor "refs/heads/$branch" "refs/heads/main" 2>/dev/null; then
      kept_dirty=$((kept_dirty + 1)); note "KEPT (branch $branch is NOT an ancestor of main) $wt ($id)"; continue
    fi
    if [ -n "$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)" ]; then
      kept_dirty=$((kept_dirty + 1)); note "KEPT (dirty tree) $wt ($id)"; continue
    fi
    if ! lock_free "$wt/.forge.lock"; then
      kept_live=$((kept_live + 1)); note "KEPT (launcher holds .forge.lock) $wt ($id)"; continue
    fi
    if [ "$dry" = 1 ]; then note "WOULD REMOVE worktree $wt and branch $branch ($id)"; reaped=$((reaped + 1)); continue; fi
    if git -C "$root" worktree remove "$wt" >/dev/null 2>&1 && [ ! -e "$wt" ]; then
      if git -C "$root" branch -d "$branch" >/dev/null 2>&1; then
        reaped=$((reaped + 1)); note "REMOVED worktree $wt and branch $branch ($id, merged, bead closed)"
      else
        # The tree is gone and the branch is not: the exact state forge.sh
        # dies on (rc=255) if this bead is ever dispatched again. Say so.
        failed=$((failed + 1)); note "FAILED: worktree $wt removed but branch $branch could NOT be deleted ($id) — a re-dispatch of this bead will refuse until the branch is removed by hand"
      fi
    else
      failed=$((failed + 1)); note "FAILED to remove worktree $wt ($id) — it is still there"
    fi
  done < <(printf '%s\n' "$out" | grep '^REAPABLE ' || true)
}
sweep_worktrees

# ---------------------------------------------------------------------------
# C. host /tmp hygiene (see the header)
# ---------------------------------------------------------------------------
tmp_remove() {  # $1 path, $2 label: remove (or say WOULD), count, and report
  local kb
  kb="$(du -sk "$1" 2>/dev/null | cut -f1)"; kb="${kb:-0}"
  if [ "$dry" = 1 ]; then note "WOULD REMOVE $2"; tmp_removed=$((tmp_removed + 1)); return 0; fi
  rm -rf -- "$1" 2>/dev/null || true
  if [ -e "$1" ]; then failed=$((failed + 1)); note "FAILED to remove $2 — it is still there"
  else tmp_removed=$((tmp_removed + 1)); tmp_freed_kb=$((tmp_freed_kb + kb)); note "REMOVED $2 (${kb} KiB)"; fi
}
# Every open file under $1, from /proc: a holder is a process with a file
# descriptor or its cwd inside the directory.
held_under() {  # $1 dir -> exit 0 when some process holds something in it
  local l
  for l in /proc/[0-9]*/fd/* /proc/[0-9]*/cwd; do
    l="$(readlink "$l" 2>/dev/null)" || continue
    case "$l" in "$1"|"$1"/*) return 0 ;; esac
  done
  return 1
}
sweep_tmp() {
  [ "$tmp_sweep" = 1 ] || return 0
  local days="${REAPER_TMP_LOG_DAYS:-7}" wts="${REAPER_WORKTREES:-$root-worktrees}" f base sfx cited cache kb max
  cited="$(cat "$root/fort/events/events-$(date +%F).jsonl" "$root/fort/events/events-$(date -d yesterday +%F).jsonl" 2>/dev/null)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in
      forge-*.log)
        sfx="${base#forge-}"; sfx="${sfx%.log}"
        if ! lock_free "$wts/$sfx/.forge.lock"; then kept_live=$((kept_live + 1)); note "KEPT (a launcher holds $sfx's .forge.lock) $f"; continue; fi ;;
      verify-fail-*.log)
        if [[ "$cited" == *"$base"* ]]; then kept_live=$((kept_live + 1)); note "KEPT (cited by the event stream since yesterday) $f"; continue; fi ;;
      *) continue ;;
    esac
    tmp_remove "$f" "$f (older than $days days)"
  done < <(find "$tmpdir" -maxdepth 1 -type f \( -name 'forge-*.log' -o -name 'verify-fail-*.log' \) -mtime "+$((days - 1))" 2>/dev/null)
  cache="$tmpdir/node-compile-cache"; max="${REAPER_NODE_CACHE_MAX_MB:-1024}"
  [ -d "$cache" ] || return 0
  kb="$(du -sk "$cache" 2>/dev/null | cut -f1)"; kb="${kb:-0}"
  if [ "$kb" -le $((max * 1024)) ]; then return 0; fi
  if held_under "$cache"; then kept_live=$((kept_live + 1)); note "KEPT (a process has a file open in it) $cache, $((kb / 1024)) MiB over the ${max} MiB cap"; return 0; fi
  if [ "$dry" = 1 ]; then note "WOULD REMOVE $cache ($((kb / 1024)) MiB, over ${max} MiB, no holder)"; tmp_removed=$((tmp_removed + 1)); return 0; fi
  # Renamed aside first: a node that starts during the removal makes a fresh
  # cache rather than writing into a tree being deleted.
  local aside="$cache.reaping-$$"
  if ! mv -- "$cache" "$aside" 2>/dev/null; then failed=$((failed + 1)); note "FAILED to move $cache aside for removal"; return 0; fi
  rm -rf -- "$aside" 2>/dev/null || true
  if [ -e "$aside" ]; then failed=$((failed + 1)); note "FAILED to remove $aside (the node compile cache, moved aside) — it is still there"
  else tmp_removed=$((tmp_removed + 1)); tmp_freed_kb=$((tmp_freed_kb + kb)); note "REMOVED $cache ($((kb / 1024)) MiB, over the ${max} MiB cap, no holder)"; fi
}
sweep_tmp
reaped=$((reaped + tmp_removed))
tmp_alarm

summary="scratch reaper: $reaped removed, $failed failed; kept $kept_young young, $kept_live live, $kept_dirty dirty or unmerged$([ "$absent_dir" -gt 0 ] && echo "; $absent_dir listed worktree(s) ABSENT with a surviving branch")$([ "$refused_list" = 1 ] && echo '; worktree list REFUSED')$([ "$dry" = 1 ] && echo ' (DRY RUN, nothing removed)')"
echo "scratch-reaper.sh: $summary" >&2
if [ "$dry" = 0 ] && { [ "$reaped" -gt 0 ] || [ "$failed" -gt 0 ]; }; then
  detail="$summary. $(printf '%s; ' "${lines[@]}")"
  # emit.sh resolves its stream from the working directory (fortkit-nvk).
  ( cd "$root" && "$emit" progress "$detail" -a fleet -s fleet \
      -p "{\"reaped\":$reaped,\"tmp_removed\":$tmp_removed,\"tmp_freed_kb\":$tmp_freed_kb,\"failed\":$failed,\"absent_dir\":$absent_dir,\"kept_young\":$kept_young,\"kept_live\":$kept_live,\"kept_dirty\":$kept_dirty}" ) || true
fi
[ "$failed" -eq 0 ] && [ "$refused_list" -eq 0 ] && exit 0
[ "$failed" -gt 0 ] && exit 1
exit 64
