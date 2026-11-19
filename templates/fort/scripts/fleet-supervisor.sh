#!/bin/bash
# {{FORT_NAME}} fleet supervisor — starts a fleet run when work appears, and is a
# no-op otherwise. Proofdelve ForgeOs-dx34.4 (spec section 4, layer 3). Regent edict of
# 2026-09-10, Overseer present throughout; gate 6.
#
# WHAT THIS IS. A host-level process fired on a short interval by
# fort/systemd/{{FORT_SLUG}}-fleet-supervisor.timer. On each firing it asks four
# questions in order and exits on the first that settles it:
#
#   1. Is the halt file present?          -> exit 0, no output, touch nothing.
#   2. Is another fleet run holding the    -> exit 75, no output, no event, and
#      run lock?                              the refusal is COUNTED (below).
#   3. Is fleet.conf readable?             -> no: exit 64, one stderr line (81p9).
#      Is the fleet enabled in it?         -> no: exit 0, no output, no event.
#   4. Is any bead ready and fleet-safe?  -> no: ask 4b.
#   4b. Does fleet.sh report a REAPABLE       -> no: exit 0, no output, no event.
#       worker (`fleet.sh --reapable`)?
#   4c. Did the LAST run this file started do  -> no, and the back-off has not
#       anything (Proofdelve ForgeOs-s49w)?                  expired: exit 0, counted, silent.
#   4d. Does the PATH resolve the run's tools? -> no: exit 64, one stderr line (eedj).
#   5. Otherwise START A RUN, as its own systemd transient unit, and exit.
#
# 4c IS THE BACK-OFF (Proofdelve ForgeOs-s49w; the Warden's round-one finding 3). A bead that
# passes question 4's query and that fleet.sh's dispatchable() refuses starts a
# run that drains at once -- fleet.autostart + fleet.begun + fleet.ended every
# interval, 2,160 events a day of nothing, until the bead is fixed. This file
# still decides NOTHING about beads (Proofdelve ForgeOs-czhb: no second dispatchable());
# it reads the OUTCOME of the run it last started, which fleet.sh writes to
# $FLEET_STATE/last-run.outcome on its ordinary exit path: run, autostart (the
# unit name this file passed as FLEET_AUTOSTART), launches, reason,
# duration_s. When that record says OUR unit drained with zero launches in
# under FLEET_BACKOFF_IDLE_S seconds (default 20: a real landing runs a
# verifier and takes longer), the last pickup did nothing, and this firing
# backs off: doubling from 4 minutes, capped at 60, with ONE fleet.backoff
# event saying until when, then silence, counted in $FLEET_STATE/supervisor.backoff
# (key=value: last_autostart_unit, backoff_n, backoff_until, skips). A run
# that launched anything, or lasted, or that a person started, clears it.
# WHEN A WINDOW ENDS, ONE RUN STARTS (Proofdelve ForgeOs-enred): the outcome on record is
# then the one already judged, so the firing starts a PROBE run carrying the
# step count, and the next firing judges the PROBE's outcome. Before this, it
# re-judged the same stale record and backed off again, forever.
# Only the drained-quickly-with-nothing shape backs off: a halt writes no
# outcome record (halt() exits directly), so a halted last run reads as the
# previous run's unit and never matches ours.
#
# 4b IS Proofdelve ForgeOs-dx34.18's SUPERVISOR HALF. A run that ends with a worker
# finished-but-unreaped (15k.6, 2026-09-11: its Forge exited inside another
# bead's seven-minute reap pass) leaves a bead that is CLAIMED, so it is not in
# `bd ready`, so question 4 alone never starts the run that would reap it; the
# Mayor had to label an unrelated bead. The same is true of every worker a HALT
# or a hard stop leaves behind. The count comes from fleet.sh itself (`--reapable`,
# which runs before preflight like --status) so that "reapable" has ONE
# definition -- this file re-reads no state token list, for the same reason it
# carries no second copy of dispatchable() (Proofdelve ForgeOs-czhb). A query that fails is
# a refusal, not zero: exit 64 and a stderr line, like bd not answering.
#
# IT IS NOT A NIGHTLY TIMER. A nightly timer reintroduces the batch boundary
# the continuous-fleet design exists to remove. Work labelled fleet-safe at an
# arbitrary time is picked up within one interval, by nobody.
#
# IT DOES NOT SOLVE CONCURRENCY, AND IT MUST NOT TRY. fleet.sh takes an
# exclusive flock on $FLEET_STATE/fleet.lock immediately before announcing a run
# and exits 75 when it is held (Proofdelve ForgeOs-l1ef). This file only PROBES that lock,
# with the same `flock -n 9 9>>` spelling print_status() uses, and never
# changes how fleet.sh takes it. The lock file is ZERO BYTES by design: it
# carries no pid and nothing can be learned from reading it.
#
# THE KILL SWITCH IS READ HERE TOO (the Warden, round-one finding 2). FLEET_ENABLED
# lives in fort/scripts/fleet.conf, kernel read-only to every seat, and it is
# the one launch control no seat can flip. fleet.sh refuses on it at preflight
# -- AFTER this file would have emitted fleet.autostart and started a unit --
# so a disabled fleet with ready beads would otherwise announce a start every
# two minutes that never begins: 720 events a day. A disabled fleet is
# "nothing to do", and question 3 says so silently. This is not a second
# decider about beads; it is the same switch, read the same way (sourced, and
# tested against the literal 1 exactly as fleet.sh:410 tests it).
#
# THE SUPERVISOR SELECTS; fleet.sh DECIDES (Proofdelve ForgeOs-czhb). Question 4 is the
# exact query fleet.sh's ready_candidates() runs, `bd ready --limit 0 --label
# fleet-safe`, and NOTHING MORE: no label exclusions, no dependency reading, no
# second copy of dispatchable(). Two deciders diverged once and wedged a run
# (Proofdelve ForgeOs-czhb); this file will not be the second. The cost is stated: a bead
# that passes the query and that dispatchable() refuses starts a run that
# drains at once, one fleet.begun/fleet.ended pair per interval, until the
# bead is fixed. That is visible in the stream and the fix is on the bead.
#
# QUIET, BUT COUNTED (criterion 3, amended 2026-09-10). Exit 75 is the normal
# outcome of firing during a live run, and the longest run in 27 has been 80.5
# minutes, so a supervisor that reported it would report it constantly. It is
# therefore silent — but every refusal appends to a durable streak record, so
# "refused continuously since T" is answerable by anything that looks later:
#
#   $FLEET_STATE/supervisor.streak      key=value, one per line, atomic rename
#     count=N                            consecutive refusals; 0 after a reset
#     first_refusal=<ISO-8601>           when this streak began; empty after reset
#     last_refusal=<ISO-8601>            the most recent refusal; empty after reset
#     reset_at=<ISO-8601>                present only after a reset
#     previous_streak=N                  the count the reset cleared
#     previous_first_refusal=<ISO-8601>  when that cleared streak began
#
# THE STREAK RESETS WHEN THE LOCK IS FOUND FREE (criterion 5). A counter that
# only increments cannot tell a wedge from a busy night; the reset is what
# makes the record mean anything. The supervisor itself DECIDES NOTHING from
# the streak, pages nobody, and has NO TIME THRESHOLD: every threshold available
# from outside a run was measured over 27 runs and refuted (Proofdelve ForgeOs-dx34.4's
# design field — 16.1 minutes wedged against 14.2 minutes healthy). Wedge
# detection lives INSIDE fleet.sh, where the state that discriminates is
# (Proofdelve ForgeOs-dx34.9), and a stall WRITES THE HALT FILE — which is why question 1
# covers it: a stalled fleet is never restarted into the same wedge.
#
# THE HALT FILE IS NEVER READ PAST, CLEARED OR BYPASSED HERE, and question 1
# runs before anything is read or written, so a firing under a halt file
# leaves the streak record byte-identical.
#
# A RUN IS STARTED AS ITS OWN TRANSIENT UNIT (`systemd-run --user`), not as a
# child of this process, for two reasons. The oneshot service firing this file
# must exit at once, or the timer would never fire DURING a run and the streak
# could never count; and a run in its own unit has its own journal
# (`journalctl --user -u {{FORT_SLUG}}-fleet-run-<id>`) and its own stop handle
# (`systemctl --user stop {{FORT_SLUG}}-fleet-run-<id>`, which sends SIGTERM to
# fleet.sh ALONE under KillMode=process — the drain-then-stop path, leaving the
# detached Forges exactly as a hand-launched run does). The user manager's
# environment is not a login shell's, so PATH is passed explicitly: THIS
# process's own PATH, which the service unit sets, forwarded unchanged and
# checked for the run's tools first (Proofdelve ForgeOs-eedj). FLEET_STATE is passed too (the Warden, dx34.18
# finding 6): this file decides on $state -- the halt file, the lock and now
# the reapable count -- so the run it starts must resolve the same directory,
# or an operator override would have the supervisor read one state dir and
# start a run against another.
#
# IT REFUSES FROM A MASKED SEAT, AND THE REFUSAL IS THE ONLY THING THAT STOPS
# IT. fleet.sh refuses under FORT_MASKED and so does this file, before reading
# anything. Measured on 2026-09-10 inside a real Mayor mask (the Regent's
# handoff for Proofdelve ForgeOs-dx34.4): with the marker set, exit 64 and nothing
# touched. With the marker STRIPPED, this file ran to completion inside the
# mask -- $HOME/.local/state is an rw grant in seat-sandbox.sh, so the streak
# was written, and `systemd-run --user` succeeded because the session bus is
# reachable from inside every seat mask and starts an UNMASKED host process.
# That second fact is a defect in the mask and not in this file (fortkit-y7no,
# P0): it was true of fleet.sh before tonight and this file adds no capability
# to it. Until the bus is masked, the marker is the control here, exactly as it
# is in fleet.sh. And because ~/.local/state is seat-writable, THE HALT FILE
# IS A LAUNCH CONTROL A MASKED MAYOR CAN REMOVE once the timer is enabled --
# stated to the Overseer on the bead before his signature.
#
# Usage:
#   fort/scripts/fleet-supervisor.sh            # one firing, as the timer does it
#   fort/scripts/fleet-supervisor.sh --status   # print the streak record and exit
# Exit codes: 0 nothing to do, or a run was started. 75 a run is live (counted,
#   silent). 64 refused: masked seat, bd would not answer, or the run could not
#   be started — one line on stderr, which the journal keeps.
#
# Environment: FLEET_STATE overrides the state directory (harness use; the
#   real one is ~/.local/state/{{FORT_SLUG}}-fleet). The launch command is
#   `systemd-run` on PATH, so a harness stubs THAT rather than this file
#   carrying an override that could act (the FLEET_CONF lesson in fleet.sh).

set -euo pipefail

root="{{REPO_PATH}}"
fleet="$root/fort/scripts/fleet.sh"
state="${FLEET_STATE:-$HOME/.local/state/{{FORT_SLUG}}-fleet}"
halt_file="$state/HALT"
lock_file="$state/fleet.lock"
streak_file="$state/supervisor.streak"
backoff_file="$state/supervisor.backoff"
outcome_file="$state/last-run.outcome"
backoff_idle_s="${FLEET_BACKOFF_IDLE_S:-20}"
# ONE SOURCE OF TRUTH FOR THE TOOLCHAIN PATH (Proofdelve ForgeOs-eedj; the Warden's round-one
# finding 5). This file used to carry its own copy of the PATH the service unit
# sets, with a comment saying the two matched and nothing asserting it: a node
# upgrade would have silently removed codex from supervisor-started runs while
# hand-launched runs kept working, presenting as a Forge that never starts.
# Now the unit's Environment=PATH (or the terminal's, when fired by hand) is
# the only list, forwarded unchanged to the run, and the tools a run needs are
# RESOLVED ON IT before anything is started: a missing one is a refusal that
# names the tool and the PATH, in the journal, at exit 64.
fleet_path="$PATH"
# claude AND dotnet ARE ON THIS LIST BECAUSE A RUN NEEDS ITS WARDEN AND ITS
# VERIFIER (Proofdelve ForgeOs-ip9z finding 6). The comment above says "the tools a run
# needs" and the list held only the ones the DISPATCHER calls: warden.sh
# launches `claude` and scripts/verify-impl.sh runs `dotnet`, so a PATH that
# resolves every name here could still produce a review that never starts and
# a verifier that is RED for the host's reason -- the two failures this
# refusal exists to turn into one legible line. Both resolve on the unit's own
# Environment=PATH, measured on this host 2026-09-22:
#   claude  {{HOME}}/.local/bin/claude          (~/.local/bin, on the unit PATH)
#   npm     resolved on the unit PATH beside node
fleet_tools="bd codex node git jq flock python3 claude"

if [ -n "${FORT_MASKED:-}" ]; then
  echo "fleet-supervisor.sh: REFUSED — this is a masked seat session (FORT_MASKED=${FORT_MASKED})." >&2
  echo "  The supervisor writes outside the repo and starts the fleet, which starts" >&2
  echo "  launchers; every process would inherit \$HOME read-only. It runs from the" >&2
  echo "  Overseer's terminal or from its systemd user timer, never from a seat." >&2
  exit 64
fi

case "${1:-}" in
  "") ;;
  --status)
    if [ -f "$streak_file" ]; then cat "$streak_file"; else echo "no streak record at $streak_file (never refused, or reset before the record existed)"; fi
    exit 0 ;;
  -h|--help) awk '/^[^#]/{exit} {print}' "$0"; exit 0 ;;
  *) echo "fleet-supervisor.sh: unknown argument: $1" >&2; exit 64 ;;
esac

# 1. The halt file. Checked before ANY read or write of the streak record, so
# this firing is provably a no-op: a stalled or red-main fleet stays stopped,
# and the record of the streak that preceded it is left as it was.
[ -e "$halt_file" ] && exit 0

mkdir -p "$state"
now="$(date -Is)"

streak_get() {  # $1 key -> value or empty; never fails
  [ -f "$streak_file" ] || { echo ""; return 0; }
  local v
  v="$(grep -m1 "^$1=" "$streak_file" || true)"
  echo "${v#*=}"
}
streak_write() {  # stdin -> the record, atomically
  local tmp="$streak_file.tmp.$$"
  cat > "$tmp"
  mv -f "$tmp" "$streak_file"
}

# 2. The run lock. print_status()'s exact probe: `flock -n 9 9>>` opens the
# file for append (never truncating it) and holds the lock for the duration
# of `true`, which is microseconds. It is the ONLY thing this file learns from
# the lock file.
# READ-ONLY, SHARED, AND WITH A DISTINCT CONFLICT CODE (Proofdelve ForgeOs-ip9z finding
# 8). The old probe was `flock -n 9 2>/dev/null 9>>"$lock_file"`, and `9>>`
# needs WRITE permission on the lock file: whenever the redirection failed --
# a read-only state directory, a lock file a seat cannot write -- the `if` was
# false, so this file took the "a run is live" branch below, advanced the
# refusal streak and exited 75 -- SILENTLY. The bead quotes the line
# "HELD - a fleet run is live"; that literal is fort/scripts/status.sh:76,
# which carries the identical probe and is fixed in the same commit. Two files,
# one spelling, two symptoms: one a person reads and one nobody does.
# A false "live" is the worst answer available here, because it is silent and
# indefinite: the supervisor waits forever for a run that does not exist, and
# the only trace is a streak record nobody reads until they wonder why nothing
# ran.
#
# Three things fix it, and they are separable. (a) The descriptor is opened
# READ-ONLY and the lock taken SHARED, which still conflicts with fleet.sh's
# exclusive lock and needs no write access -- scripts/quiescent.sh's idiom,
# used here for the same reason. (b) `-E 75` gives contention a code of its
# own, so a failing child or a failing redirection can no longer be read as
# contention (the flock lesson this civilization already paid for once). (c) An
# ABSENT lock file is not an error: fleet.sh creates it the first time it takes
# the lock, so a virgin state directory means no run has ever run, and probing
# it must not refuse the first firing.
lock_rc=0
if [ ! -e "$lock_file" ]; then
  lock_rc=0
else
  ( flock -n -s -E 75 9 ) 9<"$lock_file" 2>/dev/null || lock_rc=$?
fi
if [ "$lock_rc" != 0 ] && [ "$lock_rc" != 75 ]; then
  echo "fleet-supervisor.sh: REFUSED — $lock_file exists and could not be opened for reading to probe it (flock exited $lock_rc)." >&2
  echo "  This is NOT the same thing as a run being live, and it must not be reported as one." >&2
  echo "  Look at the file and its directory: ls -l $lock_file" >&2
  exit 64
fi
if [ "$lock_rc" = 0 ]; then
  # Free. If a streak was running, it ended with the run: reset it, keeping the
  # cleared count and start in the record so a later reader can see what the
  # last live run's refusal streak looked like. A record already at zero is
  # left untouched, so quiet firings do not rewrite it.
  count="$(streak_get count)"
  if [ -n "$count" ] && [ "$count" != 0 ]; then
    first="$(streak_get first_refusal)"
    streak_write <<REC
count=0
first_refusal=
last_refusal=
reset_at=$now
previous_streak=$count
previous_first_refusal=$first
REC
  fi
else
  # Held: a run is live. Quiet, but counted. The first-refusal timestamp is
  # written once, when the streak begins, and never rewritten while it runs.
  count="$(streak_get count)"
  first="$(streak_get first_refusal)"
  if [ -z "$count" ] || [ "$count" = 0 ] || [ -z "$first" ]; then count=0; first="$now"; fi
  streak_write <<REC
count=$((count + 1))
first_refusal=$first
last_refusal=$now
REC
  exit 75
fi

# 3. Is the fleet enabled? The config is sourced in a subshell exactly as
# fleet.sh sources it, so the spelling that disables one disables the other.
# AN UNREADABLE CONFIG IS AN OUTAGE, NOT "NOTHING TO DO" (Proofdelve ForgeOs-81p9; the Warden's
# round-two finding 2). This used to fold [ -r $conf ] failing into the same
# silent exit 0 as FLEET_ENABLED=0, while fleet.sh refuses the same case
# loudly at 64 and question 4 below argues that an outage must show in the
# journal. A config that has vanished from a kernel-read-only, git-tracked
# directory is exactly that kind of outage: one stderr line naming the file,
# exit 64, so it shows in `systemctl --user --failed`. Disabled stays silent.
conf="$root/fort/scripts/fleet.conf"
if [ ! -r "$conf" ]; then
  echo "fleet-supervisor.sh: REFUSED — no readable fleet config at $conf (fleet.sh would refuse on it too); not starting a run." >&2
  exit 64
fi
# shellcheck source=/dev/null
enabled="$( { . "$conf" && printf '%s' "${FLEET_ENABLED:-}"; } 2>/dev/null || true)"
[ "$enabled" = "1" ] || exit 0

# 4. Is there work? ready_candidates()'s query, verbatim. bd not answering is
# NOT "nothing to do" and is not silent: it is one line on stderr and exit 64,
# so a tracker outage shows in the journal and in `systemctl --user --failed`
# rather than as a supervisor that quietly never starts anything again.
if ! ready_json="$(bd -C "$root" ready --limit 0 --label fleet-safe --json 2>/dev/null)"; then
  echo "fleet-supervisor.sh: REFUSED — bd would not answer for $root; not starting a run." >&2
  exit 64
fi
n="$(printf '%s' "$ready_json" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if raw in ("", "null"): print(0); sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict): d = d.get("data", d)
print(len(d) if isinstance(d, list) else 0)
' 2>/dev/null)" || { echo "fleet-supervisor.sh: REFUSED — bd's answer could not be parsed; not starting a run." >&2; exit 64; }
# 4b. Any leftovers? Asked only when nothing is ready, so the common path costs
# nothing extra; asked of fleet.sh, never of the state directory directly.
reapable=null   # JSON null until the question is actually asked (the Warden, finding 5): a start on ready beads never asks it
if [ "$n" -eq 0 ]; then
  if ! reapable="$(FLEET_STATE="$state" "$fleet" --reapable 2>/dev/null)" || ! [ "$reapable" -ge 0 ] 2>/dev/null; then
    echo "fleet-supervisor.sh: REFUSED — fleet.sh --reapable did not answer with a count; not starting a run." >&2
    exit 64
  fi
  [ "$reapable" -gt 0 ] || exit 0
fi
why="$n fleet-safe bead(s) were ready"
[ "$n" -eq 0 ] && why="no bead was ready but $reapable reapable worker(s) await verify/review/merge (Proofdelve ForgeOs-dx34.18)"
n_ready_json_count="$n"   # the back-off's payload reads this; the back-off arithmetic below reuses $n

# 4c. THE BACK-OFF (Proofdelve ForgeOs-s49w; the reasoning is in the header). Asked only
# when there is work, so quiet firings never read these files.
kv() {  # $1 file, $2 key -> value or empty; never fails (a missing file under set -e -o pipefail would otherwise end the firing at exit 2)
  [ -f "$1" ] || { echo ""; return 0; }
  local v; v="$(grep -m1 "^$2=" "$1" || true)"; echo "${v#*=}"
}
backoff_write() {  # $1 unit, $2 n, $3 until, $4 skips -> atomic
  local tmp="$backoff_file.tmp.$$"
  printf 'last_autostart_unit=%s\nbackoff_n=%s\nbackoff_until=%s\nskips=%s\n' "$1" "$2" "$3" "$4" > "$tmp"
  mv -f "$tmp" "$backoff_file"
}
bo_unit="$(kv "$backoff_file" last_autostart_unit)"; bo_n="$(kv "$backoff_file" backoff_n)"; bo_until="$(kv "$backoff_file" backoff_until)"; bo_skips="$(kv "$backoff_file" skips)"
bo_n="${bo_n:-0}"; bo_skips="${bo_skips:-0}"
now_epoch="$(date +%s)"
if [ -n "$bo_until" ] && [ "$(date -d "$bo_until" +%s 2>/dev/null || echo 0)" -gt "$now_epoch" ]; then
  # inside a back-off window: silent, counted, nothing started
  backoff_write "$bo_unit" "$bo_n" "$bo_until" "$((bo_skips + 1))"
  exit 0
fi
# THE PROBE (Proofdelve ForgeOs-enred). A window that has EXPIRED, with no run started
# since, means the outcome on record is the one this file already judged:
# starting a run clears backoff_until (backoff_write below), so a non-empty,
# past until can only mean nothing has run since the back-off was decided.
# Measured 2026-10-19 08:04-08:34: re-judging that same stale record backed off
# 4 -> 8 -> 32 minutes without ever starting a run, and after any single empty
# drain the fleet stayed stopped until a person deleted supervisor.backoff --
# which no masked seat can do, since fleet.sh refuses under FORT_MASKED. So when
# a window ends, ONE run starts (the probe), carrying the step count; the NEXT
# firing judges the probe's own outcome: nothing again backs off one step
# further, work done clears the back-off.
probe=no
[ -n "$bo_until" ] && probe=yes
lr_unit="$(kv "$outcome_file" autostart)"; lr_launches="$(kv "$outcome_file" launches)"; lr_reason="$(kv "$outcome_file" reason)"; lr_dur="$(kv "$outcome_file" duration_s)"
lr_landings="$(kv "$outcome_file" landings)"
# DID NOTHING = zero launches AND zero landings, when fleet.sh records landings
# (2026-10-06, the churn note on Proofdelve ForgeOs-owt37). Duration was the proxy for
# "landed something" and it failed in the field: on 2026-10-05 the zero-launch
# drains took 20-28 s against the 20 s cutoff, so this file started ten runs in
# a row that dispatched nothing while dispatchable() refused every candidate as
# unclassified. A run's length drifts as the fort grows (the Proofdelve ForgeOs-9x3vj
# lesson); a count does not. An outcome record without the field -- written by
# a fleet.sh older than this change -- keeps the duration test, unchanged.
did_nothing=no
if [ -n "$lr_landings" ]; then
  [ "$lr_landings" = 0 ] && did_nothing=yes
elif [ "${lr_dur:-99999}" -lt "$backoff_idle_s" ] 2>/dev/null; then
  did_nothing=yes
fi
if [ "$probe" = no ] && [ -n "$bo_unit" ] && [ "$lr_unit" = "$bo_unit" ] && [ "${lr_launches:-1}" = 0 ] && [ "$lr_reason" = drained ] \
   && [ "$did_nothing" = yes ]; then
  # our last run did nothing: back off, doubling from 4 minutes, capped at 60
  # THE SHIFT IS GUARDED, NOT ITS RESULT (Proofdelve ForgeOs-ip9z finding 7). This read
  # `mins=$((4 << (n - 1))); [ "$mins" -gt 60 ] && mins=60`, which performs the
  # shift and only then caps: at n >= 62 it overflows signed 64-bit
  # (4 << 61 = -9223372036854775808, 4 << 62 = 0), the negative or zero value
  # is not greater than 60 so the cap never fires, and `until` lands in the
  # PAST. Every later firing is then outside its own back-off window and emits
  # fleet.backoff -- every two minutes, forever: the exact flood this back-off
  # exists to prevent, produced by the back-off itself. Reached after about 61
  # hours of continuous back-off, so it is latent today (backoff_n reads 0) and
  # permanent if left.
  # n STAYS A PLAIN COUNTER so the record still says how long this has been
  # going on; only the DOUBLING stops. The sequence is unchanged for every
  # value it ever reached before: 4, 8, 16, 32, then 60 from n=5 on (4 << 4 is
  # 64, which the old cap turned into 60 anyway).
  n=$((bo_n + 1))
  if [ "$n" -ge 5 ]; then mins=60; else mins=$((4 << (n - 1))); fi
  until="$(date -Is -d "@$((now_epoch + mins * 60))")"
  backoff_write "$bo_unit" "$n" "$until" 0
  echo "fleet-supervisor.sh: BACKING OFF ($n): the last run this supervisor started ($bo_unit) drained in ${lr_dur}s with 0 launches and ${lr_landings:-unrecorded} landings -- $why, and fleet.sh dispatched none of it. No run until $until." >&2
  ( cd "$root" && "$root/fort/scripts/emit.sh" fleet.backoff \
      "Fleet supervisor backing off (step $n, until $until): its last run $bo_unit drained in ${lr_dur}s with 0 launches although $why -- fleet.sh refused every candidate (Proofdelve ForgeOs-s49w)" \
      -a fleet -s fleet -p "{\"unit\":\"$bo_unit\",\"backoff_n\":$n,\"until\":\"$until\",\"candidates\":$n_ready_json_count,\"reapable\":$reapable}" ) || true
  exit 0
fi
# our last run did work, or lasted, or was not ours: any back-off is over.
# NOT on a probe: the step count rides into the probe run, below, and is
# cleared or advanced by the judgement of THAT run's outcome.
if [ "$probe" = no ] && [ "$bo_n" != 0 ]; then backoff_write "$bo_unit" 0 "" 0; fi

# 4d. Does the PATH this run will inherit resolve every tool it needs?
# (Proofdelve ForgeOs-eedj). Asked only once a run is about to start, so quiet firings
# cost nothing; refused loudly, because "codex not found" at dispatch time
# looks like a Forge failure and is a PATH one.
missing=""
for t in $fleet_tools; do command -v "$t" >/dev/null 2>&1 || missing="$missing $t"; done
if [ -n "$missing" ]; then
  echo "fleet-supervisor.sh: REFUSED — the PATH this run would inherit does not resolve:$missing (PATH=$fleet_path). Fix the unit's Environment=PATH (or ~/.nvm/current); not starting a run." >&2
  exit 64
fi

# 5. Start a run. One line on stderr — the journal is where this is read — and
# the run itself announces fleet.begun in the stream once it holds the lock.
# --collect: the transient unit is removed when it ends, whatever its exit
# code; the run's record is the event stream and its journal, not a lingering
# failed unit. KillMode=process: a stop reaches fleet.sh alone (its TERM trap
# drains and exits 143) and never the detached Forges. TimeoutStopSec is long
# because bash defers the TERM trap until the foreground command returns, and
# a Warden review in flight finishes first (Proofdelve ForgeOs-ke5u) — a SIGKILL at 90s
# would skip the EXIT trap and lose fleet.ended, the false-record class.
unit="{{FORT_SLUG}}-fleet-run-$(date +%Y%m%dT%H%M%S)"
if ! systemd-run --user --quiet --collect --unit "$unit" \
    -p KillMode=process -p TimeoutStopSec=45min \
    --setenv "PATH=$fleet_path" --setenv "FLEET_STATE=$state" --setenv "FLEET_AUTOSTART=$unit" --working-directory "$root" \
    "$fleet" >/dev/null 2>&1; then
  echo "fleet-supervisor.sh: REFUSED — systemd-run could not start $unit; $n fleet-safe bead(s) are ready and no run was started." >&2
  exit 64
fi
if [ "$probe" = yes ]; then
  why="$why; this run is the PROBE after back-off step $bo_n ended (Proofdelve ForgeOs-enred)"
  backoff_write "$unit" "$bo_n" "" 0   # the probe to judge next time, the step count carried (Proofdelve ForgeOs-enred)
else
  backoff_write "$unit" 0 "" 0   # the run to judge next time (Proofdelve ForgeOs-s49w); any prior back-off is over
fi
echo "fleet-supervisor.sh: started $unit ($why). journalctl --user -u $unit" >&2
# The run announces fleet.begun itself once it holds the lock; that line cannot
# say WHO started it, and a pickup nobody launched is the whole point of this
# file, so the start is recorded beside it under the mechanism's own actor.
# emit.sh resolves its stream from the working directory (fortkit-nvk).
( cd "$root" && "$root/fort/scripts/emit.sh" fleet.autostart \
    "Fleet supervisor started $unit: $why and no run was live" \
    -a fleet -s fleet -p "{\"unit\":\"$unit\",\"candidates\":$n,\"reapable\":$reapable}" ) || true
exit 0
