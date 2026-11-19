#!/bin/bash
# Manyhalls fleet — the consumer side of this fort's architecture.
# Proofdelve ForgeOs-9mfw (.2 dispatcher, .3 portcullis, .4 governor).
# Regent edict fortkit-fzpf, 2026-09-02, Overseer present throughout.
#
# WHAT THIS IS. This fort has producers and no consumers: forge.sh takes one
# bead id and is invoked by hand, and 03:00-06:00 has been exactly zero events
# in every fort every day since founding. This is the loop that pulls work,
# gates it, reviews it, lands it and closes it, so a night is not dead time.
#
# IT IS DETERMINISTIC. No model runs in this file and it spends no tokens.
# Crons watch, models act — the charter's own line, and the reason a Marshal
# seat was considered and deliberately not created: on one Claude Max plan those
# tokens are better spent on review.
#
# IT CANNOT RUN FROM A MASKED SEAT, and it refuses to try. It writes outside the
# repo and spawns launchers, and seat-sandbox.sh binds $HOME read-only with only
# the repo rw while every spawned process inherits that namespace (measured
# 2026-08-06 on herald.sh, and again cross-fort on 2026-08-13). The Overseer's
# terminal, or a systemd user timer installed the way the Herald's H7 was.
#
# ---------------------------------------------------------------------------
# THE FOUR THINGS THAT MAKE IT SAFE TO LEAVE RUNNING
# ---------------------------------------------------------------------------
#
# 1. OPT-IN, NEVER OPT-OUT. It dispatches only beads the Mayor has labelled
#    `fleet-safe`. No bead is fleet-safe until she says so. That is what keeps
#    the first run small and deliberate, and it means an honest `bd ready` is
#    not load-bearing here (Proofdelve ForgeOs-9mfw.1 is the Mayor's, and it is an offer).
#
# 2. FAIL CLOSED, ALWAYS. Every guard that cannot reach a verdict refuses. If
#    `bd` will not answer, if the gate list will not parse, if a claim cannot be
#    read back, if a verdict file is missing or malformed — nothing dispatches
#    and nothing lands. It runs unattended, so "cannot tell" must mean "do not".
#    The vocabulary is deliberate: there is no branch in this file that logs a
#    doubt and proceeds.
#
# 3. THE VERIFIER IS RUN HERE, ON THE HOST, AND IS NEVER SELF-REPORTED. This is
#    the crux and the Overseer asked for it in terms. forge.sh does not run
#    fort/scripts/verify.sh at all and prints its `Next: warden.sh` recipe
#    unconditionally after any exit (Proofdelve ForgeOs-bk5k). So this file runs the
#    verifier itself, in the bead's own worktree, and gates on the exit code IT
#    observed. Nothing forge.sh prints and nothing the Forge says about its own
#    run is consulted, ever. Running here also means Docker is reachable, so
#    this is the FULL suite including the Testcontainers MigrationTests that no
#    seat's sandbox can execute.
#
# 4. AN ABSENT VERDICT IS NEVER AN APPROVAL. 17.4% of this fort's Warden runs
#    recorded no verdict at all (32 of 184, measured 2026-09-02), which under
#    automatic closure would mean closing beads on reviews that never happened.
#    warden.sh was repaired first (Proofdelve ForgeOs-9mfw.5) to publish a machine-readable
#    result file, and this file reads that file and refuses anything that is not
#    an unambiguous APPROVE or APPROVE-WITH-FINDINGS.
#
# ---------------------------------------------------------------------------
# WHAT IT WILL NOT DO
# ---------------------------------------------------------------------------
#   - It never merges on ESCALATE or REQUEST-CHANGES, and never on a missing,
#     ambiguous or untokenised verdict.
#   - It never closes a bead whose APPROVE-WITH-FINDINGS follow-up bead could
#     not be filed. It merges and leaves the parent open instead.
#   - It never continues past a red main. A post-merge verifier failure halts
#     the whole run and leaves a halt file that a person must remove. That
#     verification runs in a FRESH WORKTREE AT THE MERGED COMMIT and never in
#     the shared checkout (Proofdelve ForgeOs-dx34.1), so what it scores is a commit rather
#     than a directory anyone may be editing; the worktree is removed when it is
#     green and KEPT when it is red, and the run says which.
#   - It never records "main is red" for a verification that never ran. A
#     post-merge verification that could not start stops the run WITHOUT
#     writing a halt file, and says so in its own event.
#   - It never merges into a tree it cannot land on. That condition is asked AT
#     MERGE TIME and no longer at run start (Proofdelve ForgeOs-dx34.1): a dirty root does
#     not stop the run, it PARKS every merge until the tree is landable. The
#     narrative and --status both say how many are waiting.
#   - It never touches a bead carrying the `human` label or an open bd gate.
#   - It never reads .beads/issues.jsonl. That export is a throttled projection
#     which defers to the next WRITE rather than to a timer and can sit stale
#     indefinitely; this fort's own copy was three hours stale during the
#     sitting that wrote this file. Every query here goes to live `bd`.
#
# Usage:
#   fort/scripts/fleet.sh              # run until the queue drains or a cap hits
#   fort/scripts/fleet.sh --once       # exactly one pass, then exit
#   fort/scripts/fleet.sh --reapable   # print how many workers the next reap pass would take, then exit
#   fort/scripts/fleet.sh --dry-run    # one pass: decide everything, claim/launch/land nothing, then exit
#   fort/scripts/fleet.sh --status     # print state and exit
# Exit codes: 0 normal drain. 64 refused at preflight. 70 halted — on a red main,
#   because the halt file appeared while the run was live, or because the loop
#   STALLED (Proofdelve ForgeOs-dx34.9: N passes that changed no state; fleet.ended says
#   which, in `reason` and `stalled`). 75 another fleet run holds the lock.
#   130/143 stopped by SIGINT/SIGTERM.
#
# IT SURVIVES ITS TERMINAL (Proofdelve ForgeOs-dx34.3). SIGHUP is ignored, so closing the
# window, dropping the ssh session or sleeping the machine does not kill a
# hand-launched run, and the narrative keeps arriving in
#   $FLEET_STATE/logs/run-<run-id>.log
# which the run names on stdout as its first line. One file per run; they are
# small, and they are the only human-readable timeline this file produces.
#
# HOW TO STOP A RUNNING FLEET (Proofdelve ForgeOs-a2fx). Two reflexes work and they are the
# same drain-then-stop path: Ctrl-C or `kill -TERM <pid>`, and creating the halt
# file $FLEET_STATE/HALT, which is now read BETWEEN PASSES as well as at
# preflight. Both stop dispatching, refuse to read anything killed in flight as
# a verdict, print what the run is leaving behind, and record the true reason in
# `fleet.ended`. Neither kills the detached Forges — that decision is recorded
# in full above on_signal().
#
# WHICH SIGNAL, AND THIS IS MEASURED RATHER THAN ASSUMED (2026-09-08, three
# controls on this host). `kill -INT` IS THE WRONG REFLEX FOR A RUN THAT IS NOT
# ATTACHED TO A TERMINAL, and it fails silently, which is the same shape as the
# halt file this bead is fixing:
#   - Ctrl-C in a terminal, on a run started there ...... the INT trap fires,
#     the run drains and exits 130. This is the attended-testing case.
#   - `kill -INT` on a run started as a background job from a script ..........
#     NOTHING HAPPENS. The run continues and the INT trap never fires. bash
#     ignores SIGINT for asynchronous commands, and a signal ignored on entry
#     to the shell cannot be trapped or reset — so the trap below is a no-op in
#     that posture, whatever it says.
#   - `kill -TERM` in every posture ....... the TERM trap fires, exits 143.
# SO: Ctrl-C at a terminal, `kill -TERM <pid>` otherwise, and the halt file
# works in both. Never `kill -INT` on a detached run.
#
# AND THE TWO ARE NOT INTERCHANGEABLE INSIDE THE RUN EITHER (Proofdelve ForgeOs-ke5u).
# Ctrl-C reaches every child, so whatever was in flight dies with it. TERM
# reaches this process ALONE and bash defers the trap until the foreground
# command returns, so THE THING IN FLIGHT FINISHES — a review under TERM records
# a real verdict, and that verdict is honoured rather than discarded. Anything
# that reads a child's status after a signal has to ask which of those happened
# instead of assuming the first.
#
# TRAP LATENCY is up to FLEET_POLL seconds for a signal sent to this process
# alone, because bash defers a trap until the foreground command returns and the
# idle window is a plain `sleep`. Ctrl-C reaches the whole process group, kills
# the sleep, and is prompt. That asymmetry is accepted rather than engineered
# around: a background `sleep` would inherit the run lock on fd 8 and outlive
# the dispatcher holding it, which is exactly Proofdelve ForgeOs-l1ef.

set -euo pipefail

# >>> node_compile_cache: KEEP BYTE-IDENTICAL in fort/scripts/fleet.sh, fort/scripts/forge.sh, fort/scripts/nightly-verify.sh and scripts/verify-impl.sh (scripts/node-cache-harness.sh compares them)
# NODE'S ON-DISK COMPILE CACHE IS OFF for every fleet, Forge, nightly and
# verifier run (Proofdelve ForgeOs-jfqu4.8 with Proofdelve ForgeOs-lmgue and Proofdelve ForgeOs-x1n09, Regent
# docket 2026-10-22 item B, the Overseer's choice on 2026-10-23). typescript,
# eslint, vite and vitest call module.enableCompileCache(); with no
# NODE_COMPILE_CACHE that writes os.tmpdir()/node-compile-cache, keyed by file
# path, so every worktree is a new set of entries that never hits again. It
# grew until the host /tmp quota filled and halted the fleet (2026-10-16
# twice, 2026-10-22). Measured 2026-10-23: tsc --noEmit and eslint ran within
# about 0.3 s of each other with and without it. Every child inherits this.
# (A masked seat's /tmp is its own tmpfs, so a cache written inside a mask
# never reached the host's quota; verify-impl.sh carries this block for those
# runs too.) The switch wins over a NODE_COMPILE_CACHE the parent set
# (measured 2026-10-23, node v24.14.0: status DISABLED, nothing written).
export NODE_DISABLE_COMPILE_CACHE=1
echo "$(basename "$0"): Node compile cache disabled for this run (NODE_DISABLE_COMPILE_CACHE=1, Proofdelve ForgeOs-jfqu4.8)" >&2
# <<< node_compile_cache

root="/home/justin/dev/fortkit"
emit_bin="$root/fort/scripts/emit.sh"
# The config lives in fort/scripts/ because that directory is kernel read-only
# to every masked seat, so no seat can enable the fleet or raise its cap from
# inside a session. FLEET_CONF exists ONLY so the guards can be tested against a
# scratch config, AND IT IS REFUSED UNLESS --dry-run IS ALSO GIVEN, so the
# override can select and decide but can never claim, launch, merge or close.
# Without that coupling the override would be a way around the kernel-read-only
# switch, which is the whole point of putting the file there.
conf="$root/fort/scripts/fleet.conf"
state="${FLEET_STATE:-$HOME/.local/state/manyhalls-fleet}"
# WHERE warden.sh LEAVES WHAT THIS FILE READS (Proofdelve ForgeOs-nv0j, Regent edict
# 2026-09-12). warden.sh writes <sfx>.log.result.json and <sfx>.log.record under
# this root, and removes its scratch COPY beside them when the review ends; the
# root moved off /tmp because thirty scratch copies filled the tmpfs quota and
# took a Warden, the verifier and two Forges down in one second
# (Proofdelve ForgeOs-7gag). THIS LINE IS SPELLED IDENTICALLY IN fort/scripts/warden.sh
# and scripts/governor-harness.sh asserts the two are byte-equal: a root that
# drifts here would make review_one() fail closed on a result file that exists
# somewhere else, spend every rung, and page a person over a review that
# recorded fine.
warden_root="${XDG_DATA_HOME:-$HOME/.local/share}/manyhalls/warden"
forge_actor="kethra"     # read from this fort's own forge.sh, not carried in
fleet_actor="fleet"     # the mechanism is not a citizen and never signs as one
# WHOSE MOVE IS THE ASSIGNEE (Proofdelve ForgeOs-29j3g; the Overseer approved the design on
# the bead on 2026-10-19 before any edit). A bead handed to the Overseer is
# assigned to him and carries one "ASK:" line; a bead handed to the Mayor is
# assigned to her seat. The Keep's board is exactly the open beads assigned to
# him. `human` and `fleet-escalated` are still written, as history and as the
# dispatch guard's belt, and no longer decide whose board a bead is on.
# Functions, not variables, for the env_signature() reason: an extracting
# harness loads functions and never this file's top level.
overseer_assignee() { printf '%s' 'justin'; }
mayor_assignee() { printf '%s' 'emrith'; }
# THE WORKBENCH (Proofdelve ForgeOs-9srgz): the Workbench, declared and seated
# 2026-11-09. A review-only bead's findings go back to him, never to a Forge.
workbench_assignee() { printf '%s' 'dunmar'; }

once=0; dry=0; status_only=0; reapable_only=0; review_only=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --once) once=1 ;;
    --dry-run) dry=1 ;;
    --status) status_only=1 ;;
    --reapable) reapable_only=1 ;;   # print the reapable-worker count and exit (Proofdelve ForgeOs-dx34.18; the supervisor's question 4b)
    --review-only)                    # queue a Workbench session branch for ONE review and exit (Proofdelve ForgeOs-9srgz)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "fleet.sh: --review-only needs a bead id" >&2; exit 64; }
      review_only="$2"; shift ;;
    -h|--help) awk '/^[^#]/{exit} {print}' "$0"; exit 0 ;;
    *) echo "fleet.sh: unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

mkdir -p "$state/workers" "$state/logs"
run_id="$(date +%Y%m%dT%H%M%S)"
run_start_epoch="$(date +%s)"   # for the outcome record's duration (Proofdelve ForgeOs-s49w)
ceiling_log="$state/ceiling.log"
halt_file="$state/HALT"
launches=0
landings=0   # merges this run landed; the supervisor's back-off reads it (Proofdelve ForgeOs-owt37 churn note)

# emit.sh resolves its target stream from the CURRENT WORKING DIRECTORY, so
# every call is wrapped and cd'd. Calling it from elsewhere writes into whatever
# fort the caller happens to be standing in — the defect that left two
# settlements untold an edict had begun for two days (fortkit-nvk).
emit() { ( cd "$root" && "$emit_bin" "$@" ) || true; }

# THE NARRATIVE GOES TO A DURABLE LOG AS WELL AS TO THE TERMINAL
# (Proofdelve ForgeOs-dx34.3). Before this it went to stdout AND NOWHERE ELSE: the event
# stream had the structured record and $FLEET_STATE/logs had the per-bead logs,
# but the human-readable timeline — dispatched, verifier GREEN, merged to main,
# CLOSED — existed only in the terminal, and closing the terminal lost it.
#
# THE TERMINAL WRITE IS THE ONE ALLOWED TO FAIL. Once the controlling terminal
# is gone, writing to stdout returns EIO, and under `set -e` an unguarded
# printf in say() would end the run at its next narrative line — turning
# "survives a closed terminal" into "dies a few seconds later, from a different
# cause, with the EXIT trap recording whatever it happened to say". The log
# write comes first for the same reason: the durable copy must not depend on
# the ephemeral one.
narrative_log="$state/logs/run-$run_id.log"
say()  {
  local line; line="$(printf '%s  %s' "$(date +%H:%M:%S)" "$*")"
  printf '%s\n' "$line" >> "$narrative_log" 2>/dev/null || true
  printf '%s\n' "$line" 2>/dev/null || true
}
# DIAGNOSTICS FROM A FUNCTION WHOSE STDOUT IS A VALUE GO TO STDERR (Proofdelve ForgeOs-0d0i,
# The Warden's round-two blocking finding 1). say() writes to STDOUT, and live_forges()
# is consumed as `$(live_forges)` at two call sites that feed it straight into
# arithmetic. A say() inside it appended its line to the number, which is an
# arithmetic syntax error, which under `set -euo pipefail` kills the run — and
# the EXIT trap then recorded `fleet.ended ... (drained)`, a clean drain for a
# run that crashed. Any helper whose stdout is a RETURN VALUE uses warn().
warn() {
  local line; line="$(printf '%s  %s' "$(date +%H:%M:%S)" "$*")"
  printf 'WARN %s\n' "$line" >> "$narrative_log" 2>/dev/null || true
  printf '%s\n' "$line" >&2 2>/dev/null || true
}

# end_reason is interpolated raw into the fleet.ended payload's JSON by the EXIT
# trap, and halt() builds it from $1, which on the landability path carries a
# joined list of filenames. A quote, backslash, tab or newline in one of those
# would make the event unparseable — a run whose ending is unreadable by the
# thing that reads endings. Sanitised at assignment rather than at emit time, so
# there is one place to be right (the Warden round two, finding 8).
set_end_reason() {  # $1 reason text
  local s="$1"
  s="${s//\\/ }"; s="${s//\"/ }"; s="${s//$'\n'/ }"; s="${s//$'\t'/ }"
  end_reason="$s"
}

# HOW A RUN ENDS. Exactly one `fleet.ended` per run, emitted by the EXIT trap,
# carrying WHY. Proofdelve ForgeOs-stpx: halt() used to emit its own `fleet.ended` and then
# `exit 70`, which fires the trap, which emits a SECOND one — so a halted run
# and a clean drain were indistinguishable in the stream unless a reader
# happened to notice the duplicate. The reason lives in these two variables and
# the trap reads them; nothing else emits fleet.ended.
#
# THE DEFAULT IS AN UNDETERMINED END, NOT "drained" (Proofdelve ForgeOs-6843, third
# sighting). The first two fixes (0d0i, stpx) removed TRIGGERS that misrecorded
# a drain; the default itself still said "drained", so ANY death on a path
# nobody anticipated -- a set -e abort, an unhandled branch -- recorded a clean
# drain. Now every NAMED exit sets its own reason (the drain check, --once,
# --dry-run, budget, halt, a signal), and anything that reaches the trap without
# having set one is legible AS undetermined. The vocabulary for every path that
# already set a reason is unchanged (criterion 2): the drain path still says
# exactly "drained", now set explicitly where the drain is decided.
end_reason="ended without a recorded reason (see the run's narrative log)"
halted=false
stalled=false   # true only when the run halted ITSELF on a stalled loop (Proofdelve ForgeOs-dx34.9)

# ---------------------------------------------------------------------------
# STOPPING (Proofdelve ForgeOs-a2fx). BEFORE THIS, A KILLED RUN RECORDED A CLEAN DRAIN.
# The only trap was EXIT, so Ctrl-C ran it with $end_reason still at its
# default and the stream said `ended after N launches (drained)` for a run a
# person had stopped. That is the Proofdelve ForgeOs-0d0i shape surviving in the signal
# path, because 0d0i was fixed at the arithmetic that caused the crash rather
# than at the trap that mis-described it. Standing order 12: the record is what
# is at risk.
#
# THE STOP IS A DRAIN, NOT A KILL. A signal sets these variables and the loop
# stops between passes. Nothing new is dispatched, verified or reviewed, and
# every place that reads a child's exit status asks signalled() FIRST — because
# Ctrl-C reaches the whole foreground process group, so the verifier or the
# merge this run was executing dies with a nonzero status that means "the
# operator stopped me" and not "your work is red". Reading that as a verdict
# would return a green bead to the Forge, or page the Overseer over a review
# that was never allowed to finish.
#
# THE DETACHED CHILDREN ARE NOT KILLED, AND HERE IS WHY (acceptance 4 asks for
# a recorded decision rather than a silent one; both answers are defensible).
#   - Killing them: bounded, tidy, and throws away in-flight work — a Forge
#     session mid-implementation and the tokens already spent on it. It also
#     leaves a worktree with no `exit` file, which is the one worker state
#     nothing reaps and a person must look at.
#   - Leaving them: they are `nohup setsid` children in their own session, so
#     Ctrl-C never reached them in the first place. Each finishes, writes its
#     own $wdir/exit, and IS REAPED BY THE NEXT RUN — reap_pass iterates every
#     worker directory, not this run's, and takes any that has `exit` and lacks
#     `done`. MEASURED BY READING reap_pass, 2026-09-08, and it corrects this
#     bead's own second fact, which said "NOBODY REAPS IT": nobody reaps it in
#     THIS run, and the next run does.
# Leaving them is chosen. The cost is that the bead stays claimed until a next
# run happens, which in a nightly batch is a day and under the continuous fleet
# is minutes — so the cost shrinks in the direction the fort is moving. What
# makes it safe rather than merely cheap is report_leftovers(), which names
# every one of them on the way out so the wait is visible instead of silent.
stop_signal=""      # "" until a signal arrives; then INT or TERM
interrupted=false   # the same fact as a JSON literal, for the fleet.ended payload
stop_requested=0    # set by a signal AND by the mid-run halt-file check
exit_code=0

signalled() { [ -n "$stop_signal" ]; }
# THE HALT FILE IS CONSULTED PER CLAIM, NOT PER PASS (Proofdelve ForgeOs-fhak, problem 1).
# Until 2026-09-18 only the between-passes block below read $halt_file, so a
# run that spent a whole review pass under a freshly placed HALT then entered
# dispatch_pass, CLAIMED a bead and launched a Forge, and only afterwards found
# the file -- twice (2026-09-14 19:05:11, 2026-09-17 14:23:24), each time with
# a Forge running under a HALT a person had placed to freeze the tree. Folding
# the file into stopping() makes every `stopping && break` in this file -- the
# one before each claim included -- see it, and gives the file exactly the
# drain-then-stop path a signal takes: an in-flight stage finishes, a reached
# merge parks, nothing new starts. halt() writes the file itself and exits
# directly, so $halted excludes that case; this is for a file a PERSON created.
halt_file_present() { [ "${halted:-false}" != true ] && [ -e "$halt_file" ]; }
stopping()  { [ "$stop_requested" = 1 ] || halt_file_present; }
# WHICH FORGES ARE RUNNING RIGHT NOW, MEASURED FROM THE LOCKS (Proofdelve ForgeOs-fhak,
# problem 2). The halt incident used to say "Nothing further was dispatched or
# merged", which reports what this run DECIDED; a person who places a HALT to
# freeze a deploy target reads it as "the fort is idle" while the Forge
# dispatched one second earlier runs on for ten minutes (the Overseer drew that
# inference, 2026-09-14). The measurement is the one scripts/quiescent.sh makes
# for the same question -- a non-blocking SHARED flock attempt on each
# <worktree>/.forge.lock conflicts with the exclusive lock forge.sh holds while
# live -- mirrored here rather than called, because the fleet needs the BEAD
# behind each lock and a fixture fort carries no scripts/. The lock.info beside
# each lock names the bead (forge.sh writes it at launch). Stdout is the value:
# nothing here may say().
forge_locks_held() {
  local lock info bead
  for lock in "$root-worktrees"/*/.forge.lock; do
    [ -e "$lock" ] || continue
    flock -n -s "$lock" true 2>/dev/null && continue    # free: no launcher holds it
    info="${lock}.info"
    bead="$(jq -r '.bead // empty' "$info" 2>/dev/null || true)"
    [ -n "$bead" ] || bead="worktree $(basename "$(dirname "$lock")") (no lock.info)"
    printf '%s\n' "$bead"
  done
}

# shellcheck disable=SC2329  # invoked by the INT and TERM traps installed
# immediately below. ShellCheck cannot see a trap string as a call site, and
# fort/scripts/verify.sh runs shellcheck at DEFAULT severity, so an info-level
# finding here is a red gate (fortkit: linted with the gate's own invocation).
on_signal() {  # $1 signal name
  # A second Ctrl-C must not rewrite the record of the first.
  [ -n "$stop_signal" ] && return 0
  stop_signal="$1"
  interrupted=true
  stop_requested=1
  case "$1" in INT) exit_code=130 ;; TERM) exit_code=143 ;; esac
  set_end_reason "interrupted by SIG$1"
  say "SIG$1 received. DRAINING: nothing further is dispatched, verified, reviewed or merged,"
  say "  and nothing killed in flight will be read as a verdict. The detached Forges keep running"
  say "  and the next run reaps them. This run will print what it is leaving behind."
}
trap 'on_signal INT'  INT
trap 'on_signal TERM' TERM

# SIGHUP IS IGNORED, AND IT IS THE ONE SIGNAL THAT IS NOT A STOP (Proofdelve ForgeOs-dx34.3
# — how it composes with Proofdelve ForgeOs-a2fx, which the second of the two to land owes
# the other). A fleet.sh started in a terminal used to die when that terminal
# closed, the session dropped, or the machine slept: the exit trap ran with
# end_reason still at its default, so the stream recorded a clean drain for a
# run killed by a closed lid, and the detached Forges kept going with nobody to
# reap them. That is a2fx fired by a closed lid instead of by Ctrl-C.
#
# The distinction is deliberate and it is about INTENT. Ctrl-C and `kill -TERM`
# are a person saying stop, and they take the drain-then-stop path and record
# themselves honestly. SIGHUP is a terminal going away, which says nothing about
# whether the work should continue — so the run keeps going, and its narrative
# keeps arriving in $state/logs/run-<run>.log, which is why that log had to
# exist before this could be safe.
#
# `nohup setsid` already made the CHILDREN immune; this is the dispatcher, which
# the wrapper never covered.
trap '' HUP

halt() {  # $1 reason, $2 kind: "halted" (default) or "stalled" (stall_check
          # only). STOP THE WORLD. Writes the halt file; every later run
          # refuses until a person removes it. Reserve it for states a person
          # must look at, never for ordinary budget exhaustion (Proofdelve ForgeOs-feeq).
          #
          # THE KIND IS THE END REASON'S PREFIX AND THE PAYLOAD'S stalled FLAG,
          # AND IT IS SET HERE ON EVERY PATH (Proofdelve ForgeOs-dx34.9 acceptance 2,
          # Proofdelve ForgeOs-6843). A stall has to be distinct in fleet.ended from a
          # halt on a red main, and both from a drain; and end_reason's
          # default reads as a clean drain, so a stall that reached the trap
          # without setting it would record the one outcome this detector
          # exists to make impossible. Nothing on this path relies on the
          # default. The exit code stays 70 for both kinds: both leave the
          # fleet stopped behind a halt file, and the record is where they
          # differ.
  local kind="${2:-halted}"
  case "$kind" in stalled) stalled=true ;; esac
  say "HALT: $1"
  halted=true
  set_end_reason "$kind: $1"
  governor_carry_reset "$kind"   # Proofdelve ForgeOs-xzg1: the run after a halt starts from FLEET_FORGE_START
  printf '%s\n%s\n' "$(date -Is)" "$1" > "$halt_file"
  emit incident "FLEET ${kind^^}: $1 — the run stopped and will not restart until $halt_file is removed by hand" \
    -a "$fleet_actor" -s fleet -p "{\"run\":\"$run_id\",\"launches\":$launches,\"stalled\":$stalled}"
  report_leftovers
  exit 70
}

# ---------------------------------------------------------------------------
# bd access. Every one of these returns nonzero rather than a wrong answer, and
# every caller treats nonzero as "do not proceed with this bead".
# ---------------------------------------------------------------------------

# Print one field of a bead, or fail. Never parses .beads/issues.jsonl.
bead_json() {  # $1 bead id
  bd -C "$root" show "$1" --json 2>/dev/null
}

# THERE IS NO GATE-LIST GUARD, AND THE REASON IS A MEASUREMENT.
# The first draft of this file guarded on `bd gate list --json`, parsing a
# `blocks` field off each gate. MEASURED 2026-09-02 against a real gate created
# for the purpose: that JSON carries id, title, description, status, priority,
# issue_type, owner, timestamps and await_type — AND NOTHING NAMING WHAT IT
# BLOCKS. The blocked bead's id appears only inside the free-text description
# ("Ad-hoc gate blocking Proofdelve ForgeOs-uc6z"). So the guard parsed nothing, returned
# an empty set, and an empty set is indistinguishable from "there are no
# gates": it failed OPEN while reading exactly like a guard that worked. It
# passed its own probe only because `bd ready` had already excluded the gated
# bead, so the thing measured could not have discriminated the property claimed.
#
# The authoritative per-bead signal is the bead's OWN record: `bd show --json`
# carries dependency_count always, and a dependencies array with each blocker's
# status whenever that count is nonzero. A gate is one of those blockers. That
# is what dispatchable() reads, and it fails closed when the count is missing.

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
merge_slot_exists() {  # 0 only when bd's --json names a slot and reports no error
  bd -C "$root" merge-slot check --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if isinstance(d, dict) and isinstance(d.get("data"), dict):
    d = d["data"]
sys.exit(0 if isinstance(d, dict) and d.get("id") and not d.get("error") else 1)
' 2>/dev/null
}
preflight() {
  if [ -n "${FORT_MASKED:-}" ]; then
    echo "fleet.sh: REFUSED — this is a masked seat session (FORT_MASKED=${FORT_MASKED})." >&2
    echo "  The fleet writes outside the repo and spawns launchers; every process it" >&2
    echo "  starts would inherit \$HOME read-only. Run it from the Overseer's terminal" >&2
    echo "  or from a systemd user timer." >&2
    exit 64
  fi
  if [ -n "${FLEET_CONF:-}" ]; then
    if [ "$dry" != 1 ]; then
      echo "fleet.sh: REFUSED — FLEET_CONF is only honoured together with --dry-run." >&2
      echo "  The real config is kernel read-only to every masked seat on purpose;" >&2
      echo "  an override that could act would be a way around that switch." >&2
      exit 64
    fi
    conf="$FLEET_CONF"
    echo "fleet.sh: DRY RUN against an override config: $conf" >&2
  fi
  [ -r "$conf" ] || { echo "fleet.sh: REFUSED — no config at $conf" >&2; exit 64; }
  # shellcheck source=/dev/null
  . "$conf"
  : "${FLEET_ENABLED:?fleet.conf must set FLEET_ENABLED}"
  : "${FLEET_FORGE_START:?}" "${FLEET_FORGE_MIN:?}" "${FLEET_FORGE_MAX:?}"
  : "${FLEET_WARDEN_CONC:?}" "${FLEET_HARD_STOP:?}" "${FLEET_MAX_RETURNS:?}"
  : "${FLEET_POLL:?}" "${FLEET_FORGE_MODEL:?}"
  # FLEET_WARDEN_MODEL was replaced by FLEET_WARDEN_LADDER (Proofdelve ForgeOs-57xc). It is
  # required, not defaulted: a config that predates the ladder must FAIL LOUDLY
  # here rather than silently reviewing on whatever a default happened to be.
  : "${FLEET_WARDEN_LADDER:?fleet.conf must set FLEET_WARDEN_LADDER (it replaced FLEET_WARDEN_MODEL)}"
  : "${FLEET_LAUNCH_GRACE:?fleet.conf must set FLEET_LAUNCH_GRACE}"
  # Required rather than defaulted, in this file's own pattern: a config that
  # predates the stall detector must say so at preflight rather than run on a
  # number nobody wrote down. Its meaning is at stall_check().
  : "${FLEET_STALL_PASSES:?fleet.conf must set FLEET_STALL_PASSES (Proofdelve ForgeOs-dx34.9)}"

  # A HALT FILE THAT CARRIES NO REASON IS A DIFFERENT FACT FROM ONE THAT DOES,
  # AND THIS REFUSAL OWES THE OPERATOR THE DIFFERENCE (Proofdelve ForgeOs-j3ga). halt()
  # writes a date and a reason, so a halt file THIS TOOL wrote explains itself.
  # `touch` — the spelling the startup line below recommends verbatim — writes
  # zero bytes, so the `sed` printed NOTHING and the next line told a person to
  # read a blank record. Whitespace-only lands in the same place: an interrupted
  # echo or a stray newline is not a reason, and a refusal printing four spaces
  # is the same failure with different bytes. Measured on run 20260910T134151,
  # the halt lever's first use with real work in flight.
  #
  # OUT OF SCOPE, SAID HERE SO NOBODY "FIXES" THE WORKING HALF: the mid-run
  # stop path, its operator_halt incident and the fleet.ended record were all
  # correct that day and are untouched. Only this sentence was wrong.
  if [ -e "$halt_file" ]; then
    echo "fleet.sh: REFUSED — a previous run halted and the halt file is still present:" >&2
    # Three states, not two. An UNREADABLE file must not be reported as an
    # empty one: "a person wrote this by hand" would be a claim this check
    # cannot make about bytes it never read.
    if [ ! -r "$halt_file" ]; then
      echo "    (this file exists but cannot be READ from here, so its reason is unknown.)" >&2
      echo "  Look at it yourself: ls -l $halt_file" >&2
      echo "  Then fix what halted the fleet and remove it by hand." >&2
    elif [ -n "$(tr -d '[:space:]' < "$halt_file")" ]; then
      sed 's/^/    /' "$halt_file" >&2
      # halt() always ends its write with a newline; a PERSON's file need not
      # (`echo -n`, an interrupted write), and sed reproduces that faithfully,
      # which runs the reason straight into the line below. Measured.
      if [ -n "$(tail -c1 "$halt_file")" ]; then echo >&2; fi
      echo "  Read the record, fix what halted it, then remove $halt_file by hand." >&2
    else
      echo "    (this file is EMPTY: it carries no reason at all.)" >&2
      echo "  AN EMPTY HALT FILE MEANS A PERSON PLACED IT, not a run halting itself." >&2
      echo "  halt() always writes a date and a reason; \`touch\` writes neither, and it is" >&2
      echo "  the spelling this launcher's own startup line recommends." >&2
      echo "  If a run was live when the file appeared, THAT run recorded why it stopped:" >&2
      echo "    grep operator_halt $root/fort/events/events-*.jsonl | tail -3" >&2
      echo "  If none was, nothing anywhere records the reason — ask whoever placed it." >&2
      echo "  Then remove $halt_file by hand." >&2
    fi
    exit 64
  fi
  if [ "$FLEET_ENABLED" != "1" ]; then
    echo "fleet.sh: the fleet is DISABLED (FLEET_ENABLED=$FLEET_ENABLED in $conf)." >&2
    echo "  It ships that way. Enabling it is the Overseer's act, and the order of" >&2
    echo "  first runs is in the config file's own header." >&2
    exit 64
  fi
  command -v bd  >/dev/null || { echo "fleet.sh: REFUSED — bd not on PATH" >&2; exit 64; }
  command -v git >/dev/null || { echo "fleet.sh: REFUSED — git not on PATH" >&2; exit 64; }
  bd -C "$root" ready --limit 1 --json >/dev/null 2>&1 \
    || { echo "fleet.sh: REFUSED — bd will not answer for $root" >&2; exit 64; }
  # THE BRANCH HALF OF LANDABILITY IS STILL A REFUSAL, AND IT IS DECIDED HERE,
  # ABOVE THE FIRST WRITE THIS FUNCTION MAKES — because it can be. The merge-slot
  # creation below mutates the tracker; this does not, and a check decidable
  # without writing anything belongs above the first write. See
  # assert_on_main_branch() for why this half stayed absolute while the dirt half
  # moved to merge time.
  assert_on_main_branch
  # The merge slot is bd's own exclusive primitive for exactly this race. Create
  # it once if the rig has none; do not invent a second lock beside it.
  # ASSERT THE ARTIFACT, NOT THE EXIT CODE. The first draft of this read
  # `check || create || refuse`, which trusts create's status — and `bd
  # merge-slot create` prints "Created merge slot" and exits 0 whether or not
  # one already existed, so its status cannot discriminate the property. A
  # preflight measured as passing while the slot was absent is exactly the
  # failure this file exists to avoid.
  # AND NOT check's EXIT CODE EITHER (Regent sitting 2026-11-19, fortkit-ttpk;
  # measured at this fort's first fleet landing, fortkit-798f). `bd merge-slot
  # check` exits 0 whether the slot is absent, free or held; only its words and
  # its --json differ. The two lines that stood here trusted that exit code, so
  # a fort that had never had a slot passed preflight without one, and its
  # first landing deferred with "the merge slot is held by someone else". The
  # fort this file came from never met it because its slot already existed.
  # merge_slot_exists() reads the --json: an id and no error.
  merge_slot_exists || bd -C "$root" merge-slot create >/dev/null 2>&1 || true
  merge_slot_exists \
    || { echo "fleet.sh: REFUSED — no merge slot exists after trying to create one" >&2; exit 64; }
  # Proofdelve ForgeOs-vikl asked for BOTH halves of this at preflight. Proofdelve ForgeOs-dx34.1
  # moved the DIRT half's decision to land(), which DEFERS rather than refusing,
  # because a long night is long enough for somebody to dirty the tree under it
  # and that is a third party's doing. The BRANCH half is refused above, and
  # land() asks the whole question again at merge time for the mid-run case.
  #
  # THE DRY-RUN SPECIAL CASE FOR DIRT IS GONE, and its disappearance is the
  # point. It existed because preflight refused ON A DIRTY TREE, and the dry-run
  # path is the one this file offers for TESTING the guards — so it refused
  # exactly when someone was trying to test them (the Warden round two, finding 8).
  # Dirt refuses on neither path now, so both say the same thing.
  #
  # AND SINCE Proofdelve ForgeOs-geym THE BRANCH HALF IS EXEMPT FROM ITS REFUSAL UNDER
  # --dry-run TOO, so the two halves are symmetric again. This paragraph said the
  # opposite for one day — "a wrong branch refuses on both, deliberately" — and
  # that sentence is what the bead was filed against: it made the mode offered
  # for testing the guard refuse on the condition the guard checks. The Overseer
  # ruled on it 2026-09-09 rather than letting it stand by inheritance, and the
  # whole reasoning is at assert_on_main_branch(), which is where a reader
  # narrowing either half will be standing. A REAL run still refuses at 64 on
  # both branch and detached-HEAD; nothing about that moved.
  report_landability
}

# ---------------------------------------------------------------------------
# WHAT THE RUN IS LEAVING BEHIND (Proofdelve ForgeOs-a2fx, acceptance 3)
# ---------------------------------------------------------------------------
# An operator who stops a run should not have to reconstruct this from
# $FLEET_STATE by hand. Printed on EVERY exit path and not only the interrupted
# one, so "leaves nothing behind" is a sentence the record contains rather than
# an absence a reader has to interpret.
report_leftovers() {
  local d open=0 person=0
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    case "$(worker_state "$d")" in settled) continue ;; esac
    open=$((open + 1))
    if worker_needs_person "$d"; then person=$((person + 1)); fi
    say "  $(worker_explain "$d")"
  done
  if [ "$open" = 0 ]; then
    say "run $run_id leaves nothing behind: every worker is settled."
  else
    say "run $run_id leaves $open worker(s) open, $person of them needing a person. State: $state/workers — fort/scripts/fleet.sh --status names each one."
  fi
  report_parked_merges
}

# ---------------------------------------------------------------------------
# governor (Proofdelve ForgeOs-9mfw.4)
# ---------------------------------------------------------------------------
forge_conc=0
clean_streak=0

# THE CEILING IS CARRIED ACROSS RUNS (Proofdelve ForgeOs-xzg1, Regent edict 2026-09-14,
# Overseer present). MEASURED before this change, over 49 runs in ceiling.log:
# every run started at FLEET_FORGE_START=1, governor_up_maybe needs five clean
# completions per step, and FLEET_HARD_STOP=18 is about nine beads at two
# launches each -- so a run reached concurrency 2 around its fifth bead and
# drained a few beads later, and the NEXT run started at 1 again. Concurrency 2
# existed for roughly the last third of a run and never more; 39 fleet beads
# measured a median 14 minutes claim-to-close, effectively serial.
#
# So a run that ends ORDINARILY -- drained, or its launch budget spent --
# writes its final forge_conc to $state/ceiling.last, and the next run starts
# from that, clamped to [FLEET_FORGE_MIN, FLEET_FORGE_MAX]. Every run's start
# line in ceiling.log says WHERE the number came from (carried, clamped, or the
# configured start), so the provenance is readable without reasoning it out.
#
# A HALT OF ANY KIND DOES NOT CARRY. halt() -- a red main, a stall, an
# environmental failure -- and the operator's mid-run halt file both REMOVE the
# carry file, so the run after a halt starts from FLEET_FORGE_START: whatever
# stopped the fleet, the ceiling it had reached is not evidence about the world
# a person has since repaired. A signal stop (Ctrl-C, kill -TERM) leaves the
# file exactly as the last ordinary end wrote it; an interrupted run has
# measured nothing about the ceiling either way. So do --once and --dry-run
# (a report is not a measurement) and the "post-merge verification could not
# run" stop in land(), which stops the run without a halt file (the Warden, review
# of 025a52f, finding 4).
#
# WHO CAN WRITE IT (finding 3, threat model item 2): $FLEET_STATE is an rw
# grant inside the masked Mayor seat, so a seat can set the next run's
# STARTING concurrency. Bounded by construction: clamped to [FLEET_FORGE_MIN,
# FLEET_FORGE_MAX], the governor still steps down on back-pressure, and the
# touch-set guard still serialises undeclared beads. The HALT file in the
# same directory is the larger lever and is already recorded (Proofdelve ForgeOs-dx34.4).
#
# WHAT DOES NOT CHANGE: back-pressure still steps down IMMEDIATELY in
# governor_down (the carried value is only the starting point); the drain
# condition (Proofdelve ForgeOs-dx34.9/dx34.18) and live_forges() are untouched; and
# FLEET_WARDEN_CONC stays 1 -- it is the plan-budget guard and the real
# ceiling, and its fix is a second review rung (fortkit-78o), not a knob.
governor_carry_file() { printf '%s' "$state/ceiling.last"; }
governor_init() {
  local f carried src
  f="$(governor_carry_file)"
  forge_conc="$FLEET_FORGE_START"; src="FLEET_FORGE_START"
  if [ -s "$f" ]; then
    carried="$(head -1 "$f" 2>/dev/null | cut -d'|' -f1)"
    case "$carried" in
      ''|*[!0-9]*)
        src="FLEET_FORGE_START; $f was unreadable ('$carried') and is ignored" ;;
      *)
        forge_conc="$carried"; src="carried from run $(head -1 "$f" | cut -d'|' -f2)"
        if [ "$forge_conc" -gt "$FLEET_FORGE_MAX" ]; then forge_conc="$FLEET_FORGE_MAX"; src="$src, clamped from $carried to FLEET_FORGE_MAX"; fi
        if [ "$forge_conc" -lt "$FLEET_FORGE_MIN" ]; then forge_conc="$FLEET_FORGE_MIN"; src="$src, clamped from $carried to FLEET_FORGE_MIN"; fi ;;
    esac
  fi
  printf '%s  run=%s  start forge_conc=%s (%s) warden_conc=%s hard_stop=%s\n' \
    "$(date -Is)" "$run_id" "$forge_conc" "$src" "$FLEET_WARDEN_CONC" "$FLEET_HARD_STOP" >> "$ceiling_log"
  say "governor: forge concurrency starts at $forge_conc ($src)"
}
# Called ONCE, at loop exit, when the run ended for one of the two ORDINARY
# reasons (drained, budget spent). Proofdelve ForgeOs-lzvo: budget_stop() used to carry
# from inside the pass that spent the budget, so a governor_down later in that
# same pass (a rate-limited Forge reaped after the review that hit the cap) was
# never carried -- one step stale, self-correcting next run, and one call site
# too many. The loop breaks on $end_reason, so the exit sees the pass's last
# step.
governor_carry_out() {
  printf '%s|%s|%s\n' "$forge_conc" "$run_id" "$(date -Is)" > "$(governor_carry_file)"
  printf '%s  run=%s  carry forge_conc=%s for the next run\n' "$(date -Is)" "$run_id" "$forge_conc" >> "$ceiling_log"
}
# Called on every halt path, so the run after a halt starts from FLEET_FORGE_START.
governor_carry_reset() {  # $1 why
  [ -e "$(governor_carry_file)" ] || return 0
  rm -f "$(governor_carry_file)"
  printf '%s  run=%s  carry RESET (%s): the next run starts from FLEET_FORGE_START\n' "$(date -Is)" "$run_id" "$1" >> "$ceiling_log"
}

# Back-pressure is READ FROM THE SESSION LOG, because that is where a plan
# refusal actually lands. Deliberately a few coarse markers rather than a clever
# parser: a false positive costs one step down and a step down costs throughput,
# never correctness.
#
# EXCEPT ONE FALSE POSITIVE, WHICH COST MORE THAN THROUGHPUT (Proofdelve ForgeOs-g3n1,
# incident Proofdelve ForgeOs-7gag, 2026-09-12 17:03). The marker list carried a bare
# 'quota exceeded', and 'Disk quota exceeded' is what EDQUOT prints -- so when
# the host /tmp filled, five fleet.governor events said "plan back-pressure",
# the governor stepped Forge concurrency down (useless against a full disk),
# and the Mayor read the stream and looked at the plan. A full disk is not
# back-pressure: EVERY later launch fails the same way, so the right response
# is to STOP, not to slow down. Two signatures now, kept apart:
#   looks_env_failure   the host itself is broken -> halt (a person must act)
#   looks_rate_limited  the plan is throttling    -> step down (the run goes on)
# The bare 'quota exceeded' is GONE from the plan regex (the Warden, round one,
# finding 4): the API spellings are 'insufficient_quota' and 'exceeded your
# current quota', and a line matching the environmental signature is ALSO
# excluded before the plan regex is tried, so the two cannot be read both ways.
#
# AND THE SIGNATURE MUST NEVER BE ASKED OF A LOG THAT MAY CARRY THE FORT'S OWN
# WRITING ABOUT IT (the Warden, round one, the blocking finding). $vout is the
# verifier's stdout, which prints every harness case label; $wlog carries the
# last forty lines of a Warden's prose; forge.log is a whole codex transcript.
# A case label, a review body or a session that so much as discussed this
# signature would have halted a healthy fort with a false claim in the
# record. So: no harness label spells the signature (governor-harness.sh
# asserts that of its own labels), and each call site below asks only in the
# failure shape it explains -- a verifier that went RED, a review that
# produced NO result file, a Forge that exited nonzero. Those are exactly the
# three shapes 7gag exhibited; a completed review or a successful Forge is
# never asked.
# 'Read-only file system' is DELIBERATELY NOT an environmental signature: inside
# a seat mask EROFS is the mask working (bd's 'openat LOCK: read-only file
# system' appears in every Warden smoke transcript), and halting the fleet on it
# would fire on every review.
# A function, not a variable, so scripts/governor-harness.sh's function
# extraction carries it along with its callers (a top-level variable would be
# unbound there under set -u and fail three cases as though this file were wrong).
env_signature() { printf '%s' 'disk quota exceeded|no space left on device'; }
looks_env_failure() {  # $1 log file
  [ -s "$1" ] || return 1
  # Same honest failure as looks_rate_limited below (the Warden, round one, finding
  # 2): if env_signature() is missing to an extractor, match NOTHING ('a^' can
  # never match) rather than everything -- an empty pattern would read every
  # log as environmental and the first one would halt the fort.
  local env; env="$(env_signature 2>/dev/null || printf 'a^')"
  grep -qiE "$env" "$1"
}
# 429 ONLY AS A STATUS CODE (Proofdelve ForgeOs-dx34.20). The marker list carried a bare
# '429', which matched inside Codex's microsecond timestamps: "16:47:19.094299Z"
# and "18:28:23.542914Z" each contain the digits, and on 2026-10-20 the governor
# stepped Forge concurrency 4 -> 3 -> 2 on those two lines alone. Any Codex log
# line carries ~6 random fractional digits, so the false positive was standing.
# A digit fence alone would not do: a hex hash or uuid puts letters on both
# sides ("a429f"). So the code must follow a word that names it as a status:
# "HTTP 429", "status 429", "status: 429", "\"status\":429", "code=429". The
# API's own "429 Too Many Requests" is caught by "too many requests" anyway.
# THE CLASS AUDIT, every other marker here and in env_signature(): each is a
# run of letters ("rate limit", "too many requests", "usage limit",
# "insufficient_quota", "exceeded your current quota", "resets at",
# "overloaded", "disk quota exceeded", "no space left on device"), and a
# timestamp's only letters are T and Z, a uuid's and a hash's only a-f. Every
# marker contains an r or an s (and the 429 form needs "http", "status" or
# "code", each with a letter past f), so none can match inside one of them.
# Lowercasing does not change that: t and z are not r or s. NOT closed here:
# "rate.?limit" and the rest still match PROSE, and the Forge log is asked
# after every session, so a transcript that discusses rate limits (a bead
# editing this very function) still steps the governor down. That is the g3n1
# class, not this one, and it is recorded on Proofdelve ForgeOs-dx34.20 as a residual.
looks_rate_limited() {  # $1 log file
  [ -s "$1" ] || return 1
  # One awk pass rather than `grep -v | grep -q`: grep -q exits on its first
  # match, the upstream grep takes SIGPIPE, and pipefail turns a SUCCESSFUL
  # match into a nonzero status (this civilization's oldest shell scar).
  # IF env_signature() IS MISSING, EXCLUDE NOTHING -- never everything. An
  # instrument that extracts this function without its callee (the pre-g3n1
  # governor harness, run from main by verify-impl.sh) would otherwise hand awk
  # an EMPTY pattern, which matches every line, and this detector would report
  # "no plan back-pressure" for every log while looking exactly like it worked.
  # With '^$' it excludes only blank lines, so the plan cases still pass there and
  # the Disk-exclusion case fails LOUDLY, which is the honest failure.
  local env; env="$(env_signature 2>/dev/null || printf '^$')"
  awk -v env="$env" '
    { l = tolower($0) }
    l ~ env { next }
    l ~ /rate.?limit|(http|status|code)[ :=_\/"]{0,3}429([^0-9a-z]|$)|too many requests|usage limit|insufficient_quota|exceeded your current quota|resets at|overloaded/ { found = 1; exit }
    END { exit !found }' "$1"
}
# Halt on an environmental failure in a log, naming the line. The worker whose
# log it is must already have been put back in a RESUMABLE state by the caller:
# halt() exits this process, and an in-hand worker left behind is read by the
# next run as orphaned and handed to a person, when what needs a person is the
# disk. Nothing about the bead's own work is recorded against it.
env_halt_if() {  # $1 log file, $2 what that log is, in prose
  looks_env_failure "$1" || return 0
  local line
  line="$(grep -iE -m1 "$(env_signature)" "$1" | cut -c1-160)"
  halt "ENVIRONMENTAL FAILURE, not plan back-pressure: $2 contains '$line'. Every later launch fails the same way until the host is repaired (Proofdelve ForgeOs-g3n1; the 2026-09-12 instance was the /tmp user quota, Proofdelve ForgeOs-7gag). The bead keeps its claim and its worker resumes on the next run."
}

governor_down() {  # $1 why
  local was="$forge_conc"
  [ "$forge_conc" -gt "$FLEET_FORGE_MIN" ] && forge_conc=$((forge_conc - 1))
  clean_streak=0
  printf '%s  run=%s  DOWN %s -> %s  (%s)\n' "$(date -Is)" "$run_id" "$was" "$forge_conc" "$1" >> "$ceiling_log"
  say "governor: forge concurrency $was -> $forge_conc ($1)"
  emit fleet.governor "Forge concurrency stepped down $was -> $forge_conc: $1" \
    -a "$fleet_actor" -s fleet -p "{\"run\":\"$run_id\",\"from\":$was,\"to\":$forge_conc}"
}

governor_up_maybe() {
  clean_streak=$((clean_streak + 1))
  if [ "$clean_streak" -ge 5 ] && [ "$forge_conc" -lt "$FLEET_FORGE_MAX" ]; then
    local was="$forge_conc"
    forge_conc=$((forge_conc + 1)); clean_streak=0
    printf '%s  run=%s  UP %s -> %s  (5 clean completions)\n' "$(date -Is)" "$run_id" "$was" "$forge_conc" >> "$ceiling_log"
    say "governor: forge concurrency $was -> $forge_conc (5 clean completions)"
    emit fleet.governor "Forge concurrency stepped up $was -> $forge_conc after 5 clean completions" \
      -a "$fleet_actor" -s fleet -p "{\"run\":\"$run_id\",\"from\":$was,\"to\":$forge_conc}"
  fi
}

# THE BUDGET IS TWO FUNCTIONS ON PURPOSE (Proofdelve ForgeOs-feeq, the Warden's framing: "budget
# spent, normal" and "stop the world" are different events and the old code
# conflated them). Three defects lived in the single function this replaces:
#
#   1. OFF BY ONE. It incremented and then tested `launches < FLEET_HARD_STOP`,
#      so the Nth launch reported failure and was never made: 20 configured
#      yielded 19 launches. governor-harness.sh case 8 encoded that behaviour as
#      if it were intended.
#   2. IT DECIDED AFTER MUTATING. In dispatch_pass it ran AFTER the bd claim, so
#      the bead that hit the cap was left claimed and in_progress with no Forge
#      behind it, invisible to `bd ready` and to the next run.
#   3. IT CALLED halt(). Ordinary exhaustion of a deliberately-low nightly cap
#      wrote the halt file, so a SUCCESSFUL busy night disabled every later run
#      until somebody deleted a file by hand.
#
# So: budget_left() DECIDES and is asked BEFORE anything is mutated; spend()
# RECORDS and decides nothing; budget_stop() ends the run cleanly, with no halt
# file and no incident, because a spent budget is the cap working.
budget_left() {  # true while one more seat launch is permitted
  [ "$launches" -lt "$FLEET_HARD_STOP" ]
}

spend() {  # $1 what was launched. Records it. Returns nothing to branch on.
  launches=$((launches + 1))
  printf '%s  run=%s  launch %s/%s  %s\n' "$(date -Is)" "$run_id" "$launches" "$FLEET_HARD_STOP" "$1" >> "$ceiling_log"
}

budget_stop() {  # $1 where the budget ran out
  [ "$end_reason" = "budget spent" ] && return 0   # say it once
  set_end_reason "budget spent"
  # the carry happens ONCE at loop exit (Proofdelve ForgeOs-lzvo), not here mid-pass
  say "budget spent: $FLEET_HARD_STOP seat launches in run $run_id ($1). The run ends here."
  say "  This is ORDINARY EXHAUSTION, not a halt. No halt file is written and the next run starts normally."
  emit fleet.capped "Fleet run $run_id reached its hard stop of $FLEET_HARD_STOP seat launches at $1 and ended normally; no halt file written" \
    -a "$fleet_actor" -s fleet -p "{\"run\":\"$run_id\",\"launches\":$launches,\"hard_stop\":$FLEET_HARD_STOP,\"halted\":false}"
}

# ---------------------------------------------------------------------------
# bead state helpers
# ---------------------------------------------------------------------------
# PARSE THE LABELS, DO NOT GREP THE DOCUMENT (Proofdelve ForgeOs-stpx). This used to grep
# the whole bd JSON for "fleet-return-N", which matches the string anywhere in
# the record — a comment quoting a previous return, a title, a dependency's
# text. It is the identical antipattern ecb1162 repaired for `assignee` one
# screen below, left standing here.
# EXACTLY ONE INTEGER ON EVERY PATH, INCLUDING THE ONE WHERE bd IS DOWN
# (Proofdelve ForgeOs-0d0i, the Warden's round-two blocking finding 1b). This was
# `bead_json | python3 ... 2>/dev/null || echo 0`, and on a bd failure BOTH legs
# printed: the python read empty stdin and printed 0 and exited 0, then
# `set -o pipefail` made the pipeline nonzero anyway so `|| echo 0` printed a
# second 0. The consumer is `n=$(returns_of "$bead"); n=$((n + 1))`, and $(( ))
# on "0\n0" is a syntax error — so the run died at exactly the moment
# return_to_ready was invoked with bd unavailable, which is the one condition
# every `|| true` in that function exists to survive, and the condition this
# fort hit four times on 2026-09-04 ("storage is nil", Proofdelve ForgeOs-gepb).
# The output is now validated rather than hoped for: anything that is not a run
# of digits becomes 0.
returns_of() {  # $1 bead — the return counter lives in a label so it is visible
  local json n
  json="$(bead_json "$1" 2>/dev/null || true)"
  n="$(printf '%s' "$json" | python3 -c '
import json, sys, re
raw = sys.stdin.read().strip()
if not raw or raw == "null": print(0); sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict) and "data" in d: d = d["data"]
if isinstance(d, list): d = d[0] if d else {}
ns = [int(m.group(1)) for l in (d.get("labels") or [])
      for m in [re.fullmatch(r"fleet-return-(\d+)", str(l))] if m]
print(max(ns) if ns else 0)
' 2>/dev/null || true)"
  case "$n" in
    ''|*[!0-9]*) echo 0 ;;   # empty, multi-line, or anything not a plain integer
    *)           echo "$n" ;;
  esac
}

bead_status() {  # $1 bead -> prints the status word ("" when bd will not answer); never fails
  local json
  json="$(bead_json "$1" 2>/dev/null || true)"
  printf '%s' "$json" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw or raw == "null": sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict) and "data" in d: d = d["data"]
if isinstance(d, list): d = d[0] if d else {}
print(str(d.get("status") or "").strip().lower())
' 2>/dev/null || true
}

# THE EVIDENCE IS THE FAILING STEP, NOT THE LOG'S TAIL (Proofdelve ForgeOs-tgm5o, Regent
# docket 2026-10-22 item C). A RED host verify used to return the last 60 lines
# of the verify log, and for dotnet-test those are Testcontainers create/
# pg_isready/delete lines: measured three times on 2026-10-22 and twice more on
# 2026-10-23 (2md9d.7.4, 2md9d.7.2.1), the Forge -- which cannot run the
# Docker-backed tests itself -- was sent back with nothing to act on, and the
# Mayor dug the failing test out by hand. So: every dotnet `  Failed <Test> [..]`
# block, with its error message and the first stack frame in tests/ or src/,
# taken from the verify log or else from the step's kept log the verifier names;
# for any other step, the verifier's own FAILED line and the last 60 lines of
# THAT step's kept log; the old tail only when neither exists. It says which.
# The pattern is two spaces then `Failed`, a dotted name and ` [`: the app's own
# log carries "      Failed to load deal detail." on every run and must not
# read as a failing test.
# CAPPED LOG FOR A COMMENT (Proofdelve ForgeOs-2tz10, 2026-11-03). A verify log is ~20,000
# lines while the test host logs at Information, and posting it whole made bead
# comments of up to 776,000 characters (413u8.10); past ~1 MB a bead's own Forge
# prompt overflows. Post the first 20 and last 60 lines, each cut to 400
# characters, and name the file that keeps the rest.
capped_log() {  # $1 log file -> stdout
  local log="${1:-}"
  [ -n "$log" ] && [ -s "$log" ] || return 0
  local lines; lines=$(wc -l < "$log")
  if [ "$lines" -le 80 ]; then cut -c1-400 "$log"; return 0; fi
  head -20 "$log" | cut -c1-400
  printf '\n[... %s lines omitted; the full log is kept at %s ...]\n\n' "$((lines - 80))" "$log"
  tail -60 "$log" | cut -c1-400
}

evidence_of() {  # $1 evidence file -> the evidence section of a return or a page
  local ev="${1:-}"
  [ -n "$ev" ] && [ -s "$ev" ] || return 0
  python3 -c '
import re, sys, os
ev = sys.argv[1]
text = open(ev, errors="replace").read().splitlines()
step_re = re.compile(r"^verify: step \x27([^\x27]+)\x27 FAILED \(exit [0-9]+\)\. Its full output is kept at (/\S+)$")
steps = [m for m in (step_re.match(l) for l in text) if m]
step_line = steps[-1].group(0) if steps else ""
kept = steps[-1].group(2) if steps else ""
test_re = re.compile(r"^  Failed ([A-Za-z_][\w.`+]*(?:\(.*\))?) \[[^]]*\]\s*$")
def blocks(lines):
    out = []
    i = 0
    while i < len(lines):
        m = test_re.match(lines[i])
        if not m:
            i += 1
            continue
        b = {"head": lines[i].strip(), "msg": [], "frame": "", "first_at": ""}
        i += 1
        mode = ""
        while i < len(lines) and not test_re.match(lines[i]):
            l = lines[i]
            st = l.strip()
            if st == "Error Message:":
                mode = "msg"
            elif st == "Stack Trace:":
                mode = "stack"
            elif mode == "msg":
                if len(b["msg"]) < 20:
                    b["msg"].append(l[:400])
            elif mode == "stack":
                if st.startswith("at "):
                    if not b["first_at"]:
                        b["first_at"] = st
                    if not b["frame"] and " in " in st and ("/tests/" in st or "/src/" in st):
                        b["frame"] = st
                else:
                    break
            i += 1
        out.append(b)
    return out
found, source = blocks(text), ev
if not found and kept and os.path.isfile(kept):
    found, source = blocks(open(kept, errors="replace").read().splitlines()), kept
if found:
    print(f"\nFailing tests ({len(found)}), from {source}:\n")
    for b in found[:20]:
        print("  " + b["head"])
        for l in b["msg"]:
            print("    " + l)
        f = b["frame"] or b["first_at"]
        if f:
            print("    first frame: " + f)
        print()
    if len(found) > 20:
        print(f"  ... and {len(found) - 20} more in {source}\n")
    summary = [l for l in text if l.startswith(("Failed!", "Passed!"))]
    if summary:
        print(summary[-1])
    if step_line:
        print(step_line)
elif step_line:
    print("\n" + step_line)
    if kept and os.path.isfile(kept):
        tail = open(kept, errors="replace").read().splitlines()[-60:]
        print(f"\nNo test failure block was found. Last {len(tail)} lines of that step\x27s kept log ({kept}):\n")
        print("\n".join(tail))
    else:
        tail = text[-60:]
        name = kept or "unnamed"
        print(f"\nThe step\x27s kept log ({name}) is gone. Last {len(tail)} lines of the evidence ({ev}):\n")
        print("\n".join(tail))
else:
    tail = text[-60:]
    print(f"\nNo failing step was named in the evidence. Last {len(tail)} lines of it ({ev}):\n")
    print("\n".join(tail))
' "$ev"
}

return_to_ready() {  # $1 bead, $2 reason, $3 evidence file (may be empty)
  local bead="$1" reason="$2" evidence="${3:-}" n status
  # A BEAD THE MAYOR CLOSED WHILE ITS WORKER WAS SETTLING STAYS CLOSED
  # (Proofdelve ForgeOs-x2lv, measured 2026-09-15 on b0vj.65.5: closed 23:15:27Z as a
  # duplicate, REOPENED 23:19:31Z by this function's `--status open`, carrying
  # fleet-escalated and two return counters and the very criteria an approved
  # gate-2 migration had already reversed). The status is read FIRST and the
  # closed case makes NO write: no comment, no counter label, no status. The
  # skip is announced on the stream (a skipped write that leaves no trace is how
  # this class hides), and the payload says skipped=closed so the digest can
  # count it. The window between this read and the writes below is accepted and
  # recorded rather than locked: bd's own latency makes a close landing inside
  # it rarer than the defect this fixes, and a lock is a new failure mode.
  status="$(bead_status "$bead")"
  if [ "$status" = closed ]; then
    say "$bead: was closed before its return pass completed — no write made, it stays closed ($reason)"
    emit fleet.returned "$bead was closed before its return pass completed; the fleet made no write and it stays closed: $reason" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"escalated\":false,\"skipped\":\"closed\"}"
    return 0
  fi
  # A WORKBENCH BRANCH GOES BACK TO THE WORKBENCH, NEVER TO A FORGE
  # (Proofdelve ForgeOs-9srgz, docket seat rule 7). Every path that would return a
  # review-only bead -- a red host verify, REQUEST-CHANGES, a branch with no
  # product change -- lands here, so this is the one place the rule holds.
  if worker_review_only "$state/workers/${bead##*-}"; then
    workbench_hand_back "$bead" "$reason" "$evidence"
    return 0
  fi
  n=$(returns_of "$bead"); n=$((n + 1))
  {
    printf 'FLEET RETURN %s of %s — %s\n\n' "$n" "$FLEET_MAX_RETURNS" "$(date -Is)"
    printf '%s\n' "$reason"
    evidence_of "$evidence"
  # THE OTHER TWO BARE COMPOUNDS IN THIS FILE, AND THE REMEDY IS THE OPPOSITE OF
  # file_followup()-s, WHICH IS THE POINT. This group and page_overseer()-s are
  # already guarded -- the tail runs only inside [ -n ] && [ -s ] -- so the only
  # way they take the run down is a file that exists, is non-empty and will not
  # read. Narrow, but these are RECOVERY paths, and dying in the code that exists
  # to survive a failure is the same defect Proofdelve ForgeOs-j3kp was filed for.
  #
  # HERE `|| true` IS CORRECT AND IN file_followup() IT IS NOT. The header and
  # the reason are already written by the time the tail runs, and THEY are the
  # payload; a missing evidence tail leaves a shorter but still-true comment. In
  # file_followup() the verbatim review IS the payload, so the same spelling
  # would file a bead whose findings section is empty and close the parent on it.
  # The shape of the remedy follows what the truncation would lose.
  } > "$state/logs/return-$bead-$n.txt" || true
  bd -C "$root" comment "$bead" --file "$state/logs/return-$bead-$n.txt" --actor "$fleet_actor" >/dev/null 2>&1 || true
  bd -C "$root" update "$bead" --add-label "fleet-return-$n" --actor "$fleet_actor" >/dev/null 2>&1 || true
  # THE EVENT REPORTS THE WRITE THAT HAPPENED, NOT THE ONE THAT WAS ATTEMPTED
  # (Proofdelve ForgeOs-stpx). Every bd write here is `|| true`, deliberately, because a
  # tracker that will not answer must not take the run down — but the emit
  # underneath used to fire unconditionally, so the stream could record a state
  # change bd had refused. The file's header claims "there is no branch in this
  # file that logs a doubt and proceeds"; that held for the guards and not for
  # this recovery bookkeeping. Now the failure is its own incident, and the
  # bead is left claimed rather than announced as returned.
  local wrc=0
  if [ "$n" -ge "$FLEET_MAX_RETURNS" ]; then
    # Escalate to the Mayor rather than retrying. Never retry indefinitely.
    bd -C "$root" update "$bead" --remove-label fleet-safe --add-label fleet-escalated \
      --status open --assignee "$(mayor_assignee)" --actor "$fleet_actor" >/dev/null 2>&1 || wrc=$?
    if [ "$wrc" -ne 0 ]; then
      say "$bead: returned $n times but the escalating bd write FAILED (exit $wrc) — bead state is unchanged"
      emit incident "Fleet could not escalate $bead after $n returns: the bd write failed (exit $wrc). The bead is still claimed and still fleet-safe; its state does NOT match this stream." \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"returns\":$n,\"bd_exit\":$wrc}"
      return 0
    fi
    say "$bead: returned $n times — escalated to the Mayor (assigned to $(mayor_assignee)), fleet-safe removed"
    emit fleet.returned "$bead returned $n times and is escalated to the Mayor, not retried" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"returns\":$n,\"escalated\":true}"
  else
    bd -C "$root" update "$bead" --status open --assignee "" --actor "$fleet_actor" >/dev/null 2>&1 || wrc=$?
    if [ "$wrc" -ne 0 ]; then
      say "$bead: the returning bd write FAILED (exit $wrc) — the bead is still claimed, NOT returned to ready"
      emit incident "Fleet could not return $bead to ready: the bd write failed (exit $wrc). It is still claimed and in_progress, so no worker will pick it up and it is absent from bd ready." \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"returns\":$n,\"bd_exit\":$wrc}"
      return 0
    fi
    say "$bead: returned to ready ($n of $FLEET_MAX_RETURNS) — $reason"
    emit fleet.returned "$bead returned to ready ($n of $FLEET_MAX_RETURNS): $reason" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"returns\":$n,\"escalated\":false}"
  fi
}

# THE HAND-BACK TO THE WORKBENCH (Proofdelve ForgeOs-9srgz). No return counter: the
# Workbench is an attended seat, not a ladder, and the next sitting decides. The
# bead is reassigned to the Workbench with fleet-safe removed, so no Forge can
# ever be dispatched on it; the evidence goes on the bead as a comment. As in
# return_to_ready(), the event reports the write that happened (Proofdelve ForgeOs-stpx).
workbench_hand_back() {  # $1 bead, $2 reason, $3 evidence file (may be empty)
  local bead="$1" reason="$2" evidence="${3:-}" f wrc=0
  f="$state/logs/handback-$bead-$(date +%Y%m%dT%H%M%S).txt"
  {
    printf 'FLEET HAND-BACK TO THE WORKBENCH (%s) -- %s\n\n' "$(workbench_assignee)" "$(date -Is)"
    printf '%s\n\n' "$reason"
    printf 'This session branch was queued with fleet.sh --review-only. Its findings go back to the Workbench and never to a Forge (Proofdelve ForgeOs-9srgz): resume with fort/scripts/workbench.sh %s, fix, verify, and queue it again.\n' "$bead"
    evidence_of "$evidence"
  } > "$f" || true
  bd -C "$root" comment "$bead" --file "$f" --actor "$fleet_actor" >/dev/null 2>&1 || true
  bd -C "$root" update "$bead" --status open --assignee "$(workbench_assignee)" --remove-label fleet-safe --actor "$fleet_actor" >/dev/null 2>&1 || wrc=$?
  if [ "$wrc" -ne 0 ]; then
    say "$bead: the hand-back to the Workbench FAILED (bd exit $wrc) -- the bead's tracker state is unchanged"
    emit incident "Fleet could not hand $bead back to the Workbench: the bd write failed (exit $wrc). Its tracker state does NOT match this stream." \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"bd_exit\":$wrc}"
    return 0
  fi
  say "$bead: handed BACK TO THE WORKBENCH ($(workbench_assignee)), fleet-safe removed -- $reason"
  emit fleet.returned "$bead handed back to the Workbench ($(workbench_assignee)), never to a Forge: $reason" \
    -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"to_workbench\":true,\"escalated\":false}"
}

# THE OVERSEER'S QUEUE. A bead reaches here when the fleet has decided it must
# stop touching it and a person must look — today only from an exhausted review
# ladder (Proofdelve ForgeOs-57xc). It is NOT return_to_ready: nothing is re-dispatched,
# the return counter is not touched, and the work in the worktree stands.
# TAKE A MERGED-BUT-UNFINISHED BEAD OUT OF THE FLEET, AND SAY WHETHER THAT
# HAPPENED (Proofdelve ForgeOs-s2lx). Four sites in land() used to write these two labels
# with `|| true` and then assert "fleet-safe removed, fleet-escalated applied" in
# the worker state, the narrative and the incident's detail -- a record of the
# write they attempted, not the write that happened (the Proofdelve ForgeOs-stpx class).
# Every one of those branches already hands the bead to a person and
# dispatchable() refuses a non-open status regardless, so the CONSENT BOUNDARY
# was never at stake; the RECORD was. Two outputs, neither on stdout
# (Proofdelve ForgeOs-0d0i): label_rc is the bd exit, and label_note is the sentence the
# caller puts where it used to assert the labels.
label_rc=0; label_note=""
# ONE ASK LINE PER HAND-OFF TO THE OVERSEER (Proofdelve ForgeOs-29j3g). The verb is one of
# sign | grant | decide | run host test | answer; the Keep shows the newest such
# line as the reason a bead is on his board. Checked and never fatal: a lost ASK
# line leaves the bead on his board with no reason, which queue-lint flags.
ask_overseer() {  # $1 bead, $2 verb, $3 one line of what he is asked -> bd's exit status
  local f="$state/logs/ask-$1.txt"
  printf 'ASK: %s -- %s\n' "$2" "$3" > "$f" 2>/dev/null || return 1
  bd -C "$root" comment "$1" --file "$f" --actor "$fleet_actor" >/dev/null 2>&1
}

escalate_labels() {  # $1 bead
  label_rc=0
  bd -C "$root" update "$1" --remove-label fleet-safe --add-label fleet-escalated \
    --assignee "$(mayor_assignee)" --actor "$fleet_actor" >/dev/null 2>&1 || label_rc=$?
  if [ "$label_rc" -eq 0 ]; then
    label_note="fleet-safe removed, fleet-escalated applied and assigned to the Mayor ($(mayor_assignee))"
  else
    label_note="BUT the bd write that removes fleet-safe and applies fleet-escalated FAILED (exit $label_rc), so the bead may still carry fleet-safe and its tracker state does NOT match this record"
  fi
}

page_overseer() {  # $1 bead, $2 reason, $3 evidence file (may be empty),
                   # $4 what stands in the worktree (optional; the default is the
                   # review-ladder case this function was written for, and
                   # Proofdelve ForgeOs-lw8x's refresh refusal passes its own, because there
                   # nothing was ever built)
  local bead="$1" reason="$2" evidence="${3:-}" wrc=0
  local body="$state/logs/paged-$bead.txt"
  {
    printf 'FLEET PAGED THE OVERSEER — %s\n\n' "$(date -Is)"
    printf '%s\n' "$reason"
    printf '\nThe fleet has removed this bead from its queue and will not touch it again.\n'
    printf '%s\n' "${4:-The implementation work in its worktree is UNTOUCHED and was verifier-green.}"
    evidence_of "$evidence"
  # Same class and same reasoning as return_to_ready() above: guarded, narrow,
  # on a recovery path, and what a failed tail loses is the evidence appendix
  # rather than the message itself.
  } > "$body" || true
  bd -C "$root" comment "$bead" --file "$body" --actor "$fleet_actor" >/dev/null 2>&1 || true
  bd -C "$root" update "$bead" --remove-label fleet-safe --add-label human \
    --assignee "$(overseer_assignee)" --actor "$fleet_actor" >/dev/null 2>&1 || wrc=$?
  if [ "$wrc" -ne 0 ]; then
    say "$bead: PAGED but the bd write FAILED (exit $wrc) — it may still be fleet-safe"
    emit incident "Fleet paged the Overseer on $bead but could NOT label it: bd exit $wrc. It may still carry fleet-safe. $reason" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"bd_exit\":$wrc}"
    return 0
  fi
  # Paged beads stay his (the Overseer's ruling on Proofdelve ForgeOs-29j3g, 2026-10-19).
  ask_overseer "$bead" answer "the fleet paged you and removed this bead from its queue: $(printf '%s' "$reason" | head -c 300 | tr '\n' ' ')" \
    || say "$bead: the ASK line could not be posted; it is assigned to $(overseer_assignee) without one"
  say "$bead: PAGED the Overseer — fleet-safe removed, assigned to $(overseer_assignee) with an ASK line. $reason"
  emit incident "Fleet paged the Overseer on $bead and removed it from the fleet: $reason" \
    -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"paged\":true}"
}

# ---------------------------------------------------------------------------
# DISPATCH (Proofdelve ForgeOs-9mfw.2)
# ---------------------------------------------------------------------------
# WORKER LIFECYCLE — ONE OWNER (Proofdelve ForgeOs-w7u5)
# ---------------------------------------------------------------------------
# The Warden, round three of the covenant-4.5 review of Proofdelve ForgeOs-9mfw:
# "one function that answers 'is this worker finished, and what makes it
# reapable again' rather than a fifth point repair."
#
# THE ROOT CONFLATION THIS REMOVES. `done` used to mean two different things —
# "this worker's Forge process is finished" and "nothing further will happen
# here" — and all five recorded sightings are that conflation. Several paths
# set a worker aside and no single place picked it up, so each new instance
# read as a one-off exactly like the five before it. `done` is no longer
# written by anything. Its two meanings are now separate tokens in $wdir/state,
# and every path that sets a worker aside says WHICH state it is leaving it in.
#
# AND THE ANSWER NAMES ITS CASE RATHER THAN RETURNING A BOOLEAN. Emrith
# Cairnwright's addition, and it is the half that makes the morning read work:
# a budget-parked unit and a stranded one are indistinguishable to a reader —
# both are claimed, in_progress, built, with no verdict — so the check the Warden
# prescribed for the first night ("a worker carrying exit and done whose bead
# is still in_progress") describes a perfectly healthy parked unit just as
# well. A lifecycle owner that cannot say which one it is holding has not taken
# ownership; it has centralised a boolean.
#
#   HEALTHY, RESUMES ITSELF          NEEDS A PERSON
#   ----------------------           --------------
#   parked-budget  next run          orphaned      a dispatcher took it or
#                  verifies                        launched it and is gone
#   parked-review  next run          needs-person  the fleet stopped touching
#                  reviews                         it on purpose and said why
#   deferred-merge next pass retries THE MERGE ALONE (Proofdelve ForgeOs-usz6). Not the
#                  verifier, and not a second review launch: the resume point
#                  is what makes that distinction expressible at all.
#   parked-signed  next pass re-asks the three signed questions and resumes
#                  the LANDING (Proofdelve ForgeOs-ohsy). Written only when a signed
#                  landing's verifier is stopped by a signal. `finished` would
#                  resume it at verify-then-review, which spends a Warden
#                  launch on work the Overseer has already signed and, on a
#                  gate-1 diff, costs him a SECOND CLICK.
#
# STATES ARE DERIVED WHERE THEY CAN BE AND STORED WHERE THEY CANNOT.
# running / launching / finished / orphaned are read off the filesystem, so a
# host that died mid-night cannot leave a stale claim behind. The rest are
# decisions and are written down.
worker_state() {  # $1 worker dir. Exactly ONE token on stdout, on every path.
  local d="$1" stored tok srun pid age
  if [ -s "$d/state" ]; then
    stored="$(head -1 "$d/state" 2>/dev/null || echo "")"
    tok="${stored%%|*}"
    srun="${stored#*|}"; srun="${srun%%|*}"
    # IN-HAND MEANS A RUN TOOK THIS WORKER AND NEVER SAID WHAT HAPPENED.
    # Belonging to THIS run that is normal and momentary. Belonging to an
    # earlier one it is the taxonomy's orphaned case: only one fleet runs at a
    # time (the flock), so the dispatcher that took it is gone and nothing will
    # finish it.
    if [ "$tok" = "in-hand" ] && [ "$srun" != "$run_id" ]; then
      echo orphaned; return 0
    fi
    printf '%s\n' "$tok"; return 0
  fi
  # LEGACY. Workers written before this bead carry a bare `done`. Read as
  # settled, which is what it meant on every path that wrote it. Nothing writes
  # it any more; this branch exists so the state directory a live rig already
  # has is not misread as unfinished work.
  if [ -e "$d/done" ]; then echo settled; return 0; fi
  if [ -e "$d/exit" ]; then echo finished; return 0; fi
  pid="$(cat "$d/pid" 2>/dev/null || echo "")"
  # A BARE PID IS TRUSTED, AND PID REUSE IS THE KNOWN RESIDUAL (Proofdelve ForgeOs-l1ef,
  # The Warden round two finding 8): after a wrap the number can belong to an
  # unrelated process and a dead Forge counts as live indefinitely. That errs
  # toward dispatching FEWER Forges, which is the safe direction.
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then echo running; return 0; fi
  # No pid yet, or a pid that is gone. GRACE WINDOW: a directory younger than
  # FLEET_LAUNCH_GRACE is still inside its launch window, because mkdir happens
  # in the parent and the pid is written by the child.
  if [ -e "$d/started" ]; then
    age="$(( $(date +%s) - $(stat -c %Y "$d/started" 2>/dev/null || echo 0) ))"
    if [ "$age" -lt "$FLEET_LAUNCH_GRACE" ]; then echo launching; return 0; fi
  fi
  echo orphaned
}

# The reason is the LAST field so a reason containing "|" cannot corrupt the
# token or the run id.
worker_set_state() {  # $1 worker dir, $2 token, $3 why
  [ -d "$1" ] || return 0
  printf '%s|%s|%s\n' "$2" "$run_id" "$3" > "$1/state"
}

worker_reason() {  # $1 worker dir. The why, or the empty string.
  local stored; stored="$(head -1 "$1/state" 2>/dev/null || echo "")"
  case "$stored" in *"|"*"|"*) printf '%s' "${stored#*|*|}" ;; *) printf '' ;; esac
}

worker_live()         { case "$(worker_state "$1")" in running|launching) return 0 ;; *) return 1 ;; esac; }
# Proofdelve ForgeOs-usz6 MOVED deferred-merge OUT OF THIS LIST. It was here because the
# promise "will retry next pass" was false and a person had to do the merge. It
# is true now: a deferred worker is reapable, and what it resumes is the MERGE
# ALONE.
worker_needs_person() { case "$(worker_state "$1")" in orphaned|needs-person) return 0 ;; *) return 1 ;; esac; }

# IS THIS WORKER FINISHED, AND WHAT MAKES IT REAPABLE AGAIN — the two halves of
# the question, answered in one place. worker_reapable() is the first half;
# worker_resume_at() is the second, and it is what stops a resumed worker
# re-running a verifier that was already green or spending a second review
# launch on one bead (Proofdelve ForgeOs-usz6's stated reason for not being a one-liner).
worker_reapable() { case "$(worker_state "$1")" in finished|parked-budget|parked-review|deferred-merge|parked-signed) return 0 ;; *) return 1 ;; esac; }
worker_resume_at() {  # $1 worker dir. verify | review | land | -
  case "$(worker_state "$1")" in
    finished|parked-budget) echo verify ;;
    parked-review)          echo review ;;
    deferred-merge)         echo land ;;
    parked-signed)          echo signed ;;
    *)                      echo - ;;
  esac
}

# A REVIEW-ONLY WORKER (Proofdelve ForgeOs-9srgz). `fleet.sh --review-only <bead>` writes a
# worker for a Workbench session branch that no Forge built: an `exit` of 0, so
# the lifecycle reads it `finished` and it resumes at the VERIFIER like any
# finished Forge (host verify, one Warden review, merge or escalate), plus this
# marker. The marker changes exactly two things: reap_order() takes the worker
# ahead of every ordinary one, and return_to_ready() hands the bead back to the
# Workbench instead of the ready queue.
worker_review_only() { [ -e "$1/review-only" ]; }

# IS A WORKBENCH SITTING LIVE? fort/scripts/workbench.sh writes
# $state/workbench.live (pid=, bead=) for the length of a sitting and removes it
# on exit. Live means the pid is alive AND is a workbench.sh, so a stale file
# from a launcher that died, or a reused pid, reads as not live. Prints
# "<bead> <pid>" and returns 0 when live. The file sits in a directory every
# seat mask can write (~/.local/state); a forged or deleted marker can hold or
# release fleet beads that overlap a sitting's files, and cannot do more than that.
workbench_live() {
  local f="$state/workbench.live" pid bead
  [ -s "$f" ] || return 1
  pid="$(sed -n 's/^pid=//p' "$f" 2>/dev/null | head -1)"
  bead="$(sed -n 's/^bead=//p' "$f" 2>/dev/null | head -1)"
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'workbench\.sh' || return 1
  printf '%s %s\n' "${bead:-?}" "$pid"
}

# ---------------------------------------------------------------------------
# THE REMOVAL HALF OF THE LIFECYCLE (2026-09-09 docket item 1, Regent sitting).
# ---------------------------------------------------------------------------
# A bead's worktree costs a measured 257 MB and one entry in `git worktree
# list`, and NOTHING has ever removed one. The 2026-09-09 run measured the rate
# for the first time: worktrees 57 -> 59, disk 13G -> 14G, ZERO post-merge trees
# surviving — so the whole delta is bead worktrees, at +1 tree and +257 MB per
# bead LANDED. That is about 1.5 GB a night at six beads and it scales with
# throughput, which is precisely what the supervisor exists to increase. This
# lands before throughput rises, deliberately.
#
# THE RULE IS option (d)'s OWN AND IS PRECEDENT RATHER THAN INVENTION: remove on
# success, KEEP THE EVIDENCE on failure. postmerge_verify() already works that
# way one function below — a green post-merge tree is removed, a red one is kept
# and named, and the recorded path is cleared ONLY on a successful removal.
#
# *** WHY THERE IS EXACTLY ONE CALL SITE, AND WHY `settled` ALONE IS NOT THE
#     CONDITION. THIS IS THE PART THAT IS EASY TO GET WRONG. ***
#
# The obvious reading is "reap when the worker reaches settled". It is wrong,
# and it is wrong twice over. `settled` means "nothing further happens to this
# WORKER", which is not the same sentence as "nothing further needs this
# WORKTREE". It is written at EIGHT sites in this file and only ONE of them is
# a merge and a close that both succeeded:
#
#   the merge failed and was aborted           -> bead back in the queue
#   REQUEST-CHANGES                            -> bead back in the queue
#   The Forge exited nonzero                   -> bead back in the queue
#   no worktree after the Forge session        -> bead back in the queue
#   the pre-review verifier was RED            -> bead back in the queue
#   ESCALATE                                   -> open, on the Overseer's queue
#   already an ancestor: somebody else landed it
#   MERGED AND CLOSED                          <- the only one that reaps
#
# FIVE OF THOSE PUT THE BEAD BACK IN THE QUEUE FOR A FRESH DISPATCH, AND A FRESH
# DISPATCH REUSES THIS WORKTREE. forge.sh:41-43 is
# `if [ ! -d "$wt" ]; then git worktree add "$wt" -b "bead/$suffix"; fi` (since
# Proofdelve ForgeOs-lw8x a reused tree is merged current with main before the session, and
# a merge that cannot be made exits 76, routed to a person in reap_pass) — so
# removing the tree does not give the next dispatch a clean one, it gives it a
# MISSING one while the branch bead/<sfx> still exists, and `worktree add -b`
# against an existing branch is a hard failure. MEASURED 2026-09-09 rather than
# reasoned: rc=255, `fatal: a branch named 'bead/xyz' already exists`. Under
# forge.sh's `set -e` that kills the dispatch before its own lock, so the bead
# would be claimed, nothing would be built, and EVERY later dispatch of that
# bead would die the same way. A reap keyed on `settled` turns five recoverable
# outcomes into a permanently undispatchable bead.
#
# AND THE ONE THE DOCKET NAMES, which the state test alone DOES cover: a
# deferred merge is `deferred-merge`, not `settled`, and Proofdelve ForgeOs-usz6's retry
# READS FROM THAT WORKTREE — it re-attempts the merge alone, without re-running
# the verifier and without spending a second review launch. Reaping between the
# defer and the retry turns a recoverable park into a lost bead, which is the
# exact failure Proofdelve ForgeOs-w7u5 and Proofdelve ForgeOs-usz6 were filed to end.
#
# SO THE GUARD IS BOTH: this function REFUSES unless the worker is `settled`,
# and it is called from ONE place — the branch in land() where the merge and the
# close have BOTH already succeeded. The state test is the belt; the single call
# site is the mechanism. A second call site is not a refactor, it is a change of
# behaviour, and it needs the eight-line table above re-read first.
#
# FOUR OUTCOMES, NOT TWO, AND A FAILURE IS NEVER REPORTED AS A SUCCESS (docket
# acceptance 6). `reaped` and `absent` both mean no worktree is left behind;
# `failed` means the removal ran and did not work, and the tree IS STILL THERE;
# `refused` means it never ran at all. Collapsing failed into refused would tell
# a morning reader that a 257 MB tree was tidied away when it was not.
reap_result=""   # reaped | absent | failed | refused. Never empty after a call.
worker_reap_worktree() {  # $1 worker dir, $2 bead
  local d="$1" bead="$2" wt st
  wt="$root-worktrees/${bead##*-}"
  st="$(worker_state "$d")"
  reap_result=refused
  if [ "$st" != settled ]; then
    # warn(), not say(): a reap asked for on a live, deferred or needs-a-person
    # worker is a call site that should not exist, and it must be loud.
    warn "$bead: REFUSED to remove $wt — this worker is '$st', not settled. Nothing was removed."
    return 0
  fi
  if [ ! -e "$wt" ]; then
    reap_result=absent
    say "$bead: no worktree at $wt to remove."
    return 0
  fi
  if git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1; then
    reap_result=reaped
    say "$bead: its worktree $wt was REMOVED."
    return 0
  fi
  reap_result=failed
  warn "$bead: its worktree $wt could NOT be removed and IS STILL THERE. The merge stands and the bead is closed; only the disk was not reclaimed."
  return 0
}

# ONE LINE A PERSON CAN ACT ON, and it says whether there is anything to act on.
worker_explain() {  # $1 worker dir
  local d="$1" b why ex pid facts
  b="$(cat "$d/bead" 2>/dev/null || basename "$d")"
  why="$(worker_reason "$d")"
  case "$(worker_state "$d")" in
    running)        echo "$b: RUNNING — its Forge is alive. No action." ;;
    launching)      echo "$b: LAUNCHING — dispatched moments ago, its pid has not appeared yet. No action." ;;
    finished)       echo "$b: FINISHED, NOT YET REAPED — the next run verifies and reviews it. No action." ;;
    in-hand)        echo "$b: IN HAND — run $run_id has it and has not yet said what happened. No action WHILE THAT RUN IS ALIVE; if it ends without settling this worker, the next run reads it as ORPHANED and it will need a person." ;;
    parked-budget)  echo "$b: PARKED FOR BUDGET, HEALTHY — the launch budget ran out before it was reaped; the next run resumes at the verifier. No action." ;;
    parked-review)  echo "$b: PARKED FOR BUDGET BEFORE ITS REVIEW, HEALTHY — already verifier-green; the next run resumes at the review and does not re-verify. No action." ;;
    parked-signed)  echo "$b: PARKED MID-SIGNED-LANDING, HEALTHY — its host verifier was stopped by a signal, not failed. The next pass re-asks whether the Overseer's approval still covers this tree and resumes the LANDING; no Forge is dispatched and no review launch is spent. No action. ${why}" ;;
    deferred-merge) echo "$b: DEFERRED AT THE MERGE, HEALTHY — reviewed and approved, waiting for a landable tree. A later pass retries the merge alone; neither the verifier nor a review launch is spent again. No action. ${why}" ;;
    settled)        echo "$b: SETTLED — nothing further happens here. ${why}" ;;
    orphaned)
      # THE FACTS, MEASURED, RATHER THAN AN ASSERTION (Proofdelve ForgeOs-ke5u, acceptance
      # 4). This line used to read "no exit code and no live process", which is
      # true of ONE of the two ways a worker becomes orphaned and false of the
      # other: a worker left `in-hand` by a run that was signalled has an exit
      # code AND has passed its verifier. A line that states unchecked facts is
      # worse than one that states none, because a person acts on it.
      ex="$(cat "$d/exit" 2>/dev/null || echo "")"
      pid="$(cat "$d/pid" 2>/dev/null || echo "")"
      if [ -n "$ex" ]; then facts="its Forge exited $ex"; else facts="no exit code was ever written"; fi
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then facts="$facts, and pid $pid is STILL ALIVE"
      elif [ -n "$pid" ]; then facts="$facts, and pid $pid is gone"
      else facts="$facts, and no pid was ever written"; fi
      echo "$b: ORPHANED — a dispatcher took it or launched it and is gone, so nothing will finish it: $facts. NEEDS A PERSON. ${why}" ;;
    needs-person)   echo "$b: NEEDS A PERSON — the fleet stopped touching it deliberately. ${why}" ;;
    *)              echo "$b: UNKNOWN LIFECYCLE STATE in $d/state — NEEDS A PERSON." ;;
  esac
}

# LIVE MEANS A PROCESS IS ALIVE, NOT MERELY THAT TWO FILES ARE ABSENT
# (Proofdelve ForgeOs-l1ef). This counted any worker directory lacking both `exit` and
# `done`, with no run scoping and no staleness check — so anything that stopped
# a child before it could write `exit` (a reboot, a SIGKILL, the host going
# down mid-night) left a directory that counted as a live Forge FOREVER, and
# every later run started with fewer slots until the count reached the
# concurrency ceiling and the fleet silently dispatched nothing at all. The
# question is now asked of the lifecycle owner rather than answered here.
live_forges() {
  local n=0 d
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    if worker_live "$d"; then n=$((n + 1)); continue; fi
    # warn(), NOT say(): this function's stdout is its return value, and one
    # diagnostic line on stdout is an arithmetic syntax error at both call
    # sites, which kills the run and lets the EXIT trap record a clean drain
    # for a crash (Proofdelve ForgeOs-0d0i).
    # ONCE PER PASS (Proofdelve ForgeOs-xu0mj). refill_slots() calls this at every step of
    # the completion lane, so without the set a live NEEDS A PERSON would print
    # several times a pass instead of once. THE SET IS A FILE, NOT A VARIABLE:
    # every caller runs this as $(live_forges), a subshell, so a variable
    # updated here is lost on return. That is exactly how the first version
    # shipped (a25ca0e2) and warned twice in one pass in the first live run,
    # 20261015T115003 at 11:50:08 and 11:50:11. The loop clears the file at the
    # top of each pass; a worker still needing a person is said again next pass.
    if worker_needs_person "$d"; then
      if ! grep -qxF "$d" "$state/.np-warned" 2>/dev/null; then
        warn "$(worker_explain "$d")"
        printf '%s\n' "$d" >> "$state/.np-warned" 2>/dev/null || true
      fi
    fi
  done
  echo "$n"
}

# HOW MANY WORKERS THE NEXT REAP PASS WOULD TAKE (Proofdelve ForgeOs-dx34.18). The
# drain check asks this beside live_forges(); it is NOT folded into
# live_forges(), which is also the governor's slot count -- widening that would
# change Forge concurrency, and a finished worker holds no seat. Same shape as
# live_forges(): stdout is the return value, so nothing here may say() -- one
# diagnostic line on stdout is an arithmetic error at the call site
# (Proofdelve ForgeOs-0d0i).
reapable_workers() {
  local n=0 d
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    worker_reapable "$d" && n=$((n + 1))
  done
  echo "$n"
}

# THE ONE PLACE A BEAD IS JUDGED DISPATCHABLE. Every refusal path here is a
# refusal: there is no branch that notes a doubt and proceeds.
dispatchable() {  # $1 bead, [$2 "signed": a signed landing, which skips the classification check]. Silent yes; a reason on stderr and nonzero for no.
  local bead="$1" j v
  j="$(bead_json "$bead")" || { echo "bd would not answer for $bead"; return 1; }
  [ -n "$j" ] || { echo "empty bd record for $bead"; return 1; }
  v="$(printf '%s' "$j" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw or raw == "null":
    print("NO bd returned nothing"); sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict) and "data" in d: d = d["data"]
if isinstance(d, list):
    if not d: print("NO bd returned an empty record"); sys.exit(0)
    d = d[0]
labels = d.get("labels") or []
status = d.get("status") or ""
if status != "open":
    print("NO status is %s, not open" % (status or "<missing>")); sys.exit(0)
if "fleet-safe" not in labels:
    print("NO not labelled fleet-safe"); sys.exit(0)
# This fort own convention for "waiting on the Overseer" is the human label
# plus bd human (fort/seats/mayor.md, Proofdelve ForgeOs-eng3.1, 2026-08-29). It is NOT
# the capital gate-N labels, which are not law here and sit on two strays.
# Guarding the wrong convention would guard nothing.
if "human" in labels:
    print("NO carries the human label, so it is waiting on the Overseer"); sys.exit(0)
if "fleet-escalated" in labels:
    print("NO escalated to the Mayor after repeated returns"); sys.exit(0)
# THE MAYOR CLASSIFICATION IS POSITIVE, AND ITS ABSENCE REFUSES (Proofdelve ForgeOs-vee4w
# criterion 6, the Overseer ruling of 2026-10-05). Every bead the fleet works
# carries sign-to-land (it lands only on his signature) or lands-on-review (gate
# 1 class A, or not gate 1 at all). Neither means nobody classified it, and
# doubt is not resolved in the fleet favour: refused here, so no Forge is spent
# on it, and held at land() as the belt. The two names are spelled again in
# sign_label() and review_label(); the e2e harness scenario 61 holds them equal.
# A SIGNED LANDING SKIPS IT (the Warden, round two, finding 1): his recorded
# approval of the exact change IS the gate this label stands in for, and beads
# escalated before the marker existed carry neither label, so without the skip
# his Approve on them would be refused as unclassified.
signed = len(sys.argv) > 1 and sys.argv[1] == "signed"
if not signed and "sign-to-land" not in labels and "lands-on-review" not in labels:
    print("NO unclassified: it carries neither sign-to-land nor lands-on-review, so whether its landing needs the Overseer signature is unknown and it is not dispatched"); sys.exit(0)
if "dependency_count" not in d:
    print("NO the bd record has no dependency_count, so blockers cannot be established"); sys.exit(0)
n = d.get("dependency_count") or 0
if n:
    deps = d.get("dependencies")
    if deps is None:
        print("NO %d blockers reported but none listed, so they cannot be checked" % n); sys.exit(0)
    # ONLY A blocks EDGE BLOCKS, AND THIS LOOP NOW READS THE EDGE TYPE
    # (Proofdelve ForgeOs-czhb). It used to refuse on ANY open dependency, which re-filtered
    # beads bd ready had correctly cleared: ~140 of 349 ready beads hold a
    # non-blocking edge to an open bead, which is very nearly the whole product
    # backlog, and every one of them was undispatchable. The branch had never
    # executed in twelve lifetime beads -- ten carried no edge and two pointed at
    # closed parents -- so twelve clean runs established nothing about it. Dead
    # code that woke up, not code that broke.
    #
    # TWO KEYS, BECAUSE bd SWAPS THEM BETWEEN SUBCOMMANDS. Measured here on
    # 2026-09-10: bd show <id> --json carries the name under dependency_type
    # and leaves type null, while bd list --all --json does the exact
    # opposite. bead_json() calls show, so dependency_type is the live key --
    # but a guard reading only one key would refuse EVERY bead and stop the fleet
    # completely if bd ever normalised them, so both are read and the first
    # non-empty one wins.
    #
    # THE SITTING-THREE DOCKET SAID A DEFAULT EDGE READS BACK NULL. It does not.
    # That claim came from reading type off a bd show record, where EVERY
    # edge reads null whatever its type, so the measurement could not have
    # discriminated; under dependency_type a default edge reads back as the
    # literal string blocks. The design below is unchanged by the correction,
    # but its reason is fail-closed-on-the-unknown rather than the stated one.
    #
    # REFUSE UNLESS THE TYPE IS A KNOWN NON-BLOCKING NAME. Absent, empty or
    # unrecognised REFUSES. Proofdelve ForgeOs-czhb criterion 4 asks for the opposite shape
    # and criterion 2 asks that "absent or unrecognised" refuse; both cannot be
    # had, and the recorded resolution on that bead is that "the SAFE DEFAULT is
    # refusal, not the shape of the list". A predicate keyed on the string
    # blocks alone would dispatch any type bd grows later -- a guard whose
    # comment above reads "there is no branch that notes a doubt and proceeds"
    # doing exactly that. This direction costs a refusal that NAMES THE TYPE,
    # which a person fixes in one line; the other direction is silent.
    NONBLOCKING = (
        "tracks", "related", "parent-child", "discovered-from", "until",
        "caused-by", "validates", "relates-to", "supersedes",
    )
    for dep in deps:
        st = (dep.get("status") or "").lower()
        if st in ("closed", "done"):
            continue
        kind = "gate" if dep.get("issue_type") == "gate" else "blocker"
        # A GATE REFUSES WHATEVER ITS EDGE TYPE SAYS, and it is checked before
        # the type deliberately. A gate is this fort marker for "a person must act"
        # marker; letting a non-blocking edge type make one passable would route
        # around the human, which no throughput argument buys back.
        if kind == "gate":
            print("NO open gate %s (%s)" % (dep.get("id"), st or "status unknown")); sys.exit(0)
        dt = (dep.get("dependency_type") or dep.get("type") or "").strip().lower()
        if dt in NONBLOCKING:
            continue
        if not dt:
            why = "the edge records no type, so it cannot be shown to be non-blocking"
        elif dt == "blocks":
            why = "the edge type is blocks"
        else:
            why = "the edge type %s is not a known non-blocking type, so it is treated as blocking" % dt
        print("NO open %s %s (%s) -- %s" % (kind, dep.get("id"), st or "status unknown", why)); sys.exit(0)
print("YES")
' "${2:-}" 2>/dev/null)" || { echo "the bd record for $bead could not be parsed, failing closed"; return 1; }
  case "$v" in
    YES)    return 0 ;;
    "NO "*) echo "${v#NO }"; return 1 ;;
    *)      echo "the guard reached no decision for $bead, failing closed"; return 1 ;;
  esac
}

# ONE QUERY, ASKED BY BOTH THE DISPATCHER AND THE DRAIN CHECK (Proofdelve ForgeOs-czhb
# acceptance 8). These were two separate bd calls with different flags and on
# 2026-09-10 they disagreed: the drain check asked `bd ready`, got four beads
# back and read that as work; dispatch_pass asked dispatchable() and refused all
# four; and the main loop polled forever because neither side would move. Six
# passes at FLEET_POLL intervals, identical output, halted by hand. They cannot
# diverge again because there is now one query and one decider, so an
# eligibility change that forgets the drain check is no longer expressible.
#
# DELIBERATELY WITHOUT --exclude-label: the query SELECTS, dispatchable()
# DECIDES. That rule was already carried by the inline query this replaces;
# extending it to the drain check is what closes the divergence, because the
# drain check used to pass --exclude-label human -- a filter dispatchable() also
# applies, which is exactly the shape that makes a guard untestable.
ready_candidates() {  # one bead id per line; nonzero if bd would not answer
  bd -C "$root" ready --limit 0 --label fleet-safe --json 2>/dev/null \
  | python3 -c '
import json,sys
raw=sys.stdin.read().strip()
if raw in ("","null"): sys.exit(0)
d=json.loads(raw)
if isinstance(d,dict): d=d.get("data",d)
for i in d: print(i["id"])
'
}

# IS THERE ANY WORK THIS RUN COULD ACTUALLY START? The drain check asks this,
# and it has to be answered through dispatchable() rather than through the
# queue's length, because a bead the dispatcher will refuse is not work.
#
# FAILING CLOSED HERE MEANS "DO NOT DECLARE A DRAIN". If bd cannot be read the
# answer is yes-there-might-be-work: ending a run on an unreadable tracker would
# report a clean drain for a run that never looked. Note also that this is the
# WEAKER of the two questions -- dispatch_pass additionally skips a bead whose
# worktree a live launcher holds -- so such a bead keeps the run polling rather
# than draining it. That is the conservative direction and is what the old drain
# check did too.
any_dispatchable() {
  local bead cands
  cands="$(ready_candidates)" || return 0
  for bead in $cands; do
    if dispatchable "$bead" >/dev/null 2>&1; then return 0; fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# STALL DETECTION (Proofdelve ForgeOs-dx34.9). THE LOOP CAN TELL A STALLED PASS FROM A
# WORKING ONE, AND IT DOES IT BY CONSTRUCTION RATHER THAN BY A CLOCK.
# ---------------------------------------------------------------------------
# THE WEDGE THIS ANSWERS: run 20260910T135709 spun for 16 minutes, emitting
# nothing, and ended only because a person touched the halt file. Its cause
# (Proofdelve ForgeOs-czhb, the drain check and the dispatch guard disagreeing about one
# bead) is fixed; that nothing in this file could NOTICE it is what this section
# fixes, because the next wedge will have a different cause -- and this file
# already names one in any_dispatchable()'s own header: a bead dispatchable()
# accepts whose worktree a launcher outside this run holds "keeps the run
# polling rather than draining it". A tracker refusing every claim
# (Proofdelve ForgeOs-dx34.2's unmeasured write contention) is another.
#
# A TIME THRESHOLD IS REFUTED, NOT UNTRIED. Measured over 27 runs
# (Proofdelve ForgeOs-dx34.4's design field; fort/memory/facts/fleet-silence-does-not-
# indicate-a-wedge.md): the wedged run's longest fleet-event silence was 16.1
# minutes, a CLEAN drain's was 14.2, and a clean drain with ZERO worker events
# inside a 7-minute gap exists. Nothing an outside observer can measure
# separates them. Do not add a clock here.
#
# WHAT DOES SEPARATE THEM IS WHETHER THE PASS CHANGED ANY STATE. A pass that
# dispatched nothing AND reaped nothing, while no Forge is live AND the drain
# check's own test says there is startable work, did no work and changed
# nothing -- so the next pass meets the same queue, the same guards and the
# same answer. That is a stall by construction, with no threshold to fit.
#
# THE FOURTH HEALTHY OUTCOME, WHICH THE BEAD'S OWN PROSE OMITS. Proofdelve ForgeOs-dx34.9
# says "a healthy pass either dispatches, reaps, or finds the queue empty and
# exits". There is a fourth: a pass that does nothing because a Forge is LIVE
# and the queue is waiting behind it. That is every quiet minute of the
# 14.2-minute silence in run 20260910T143714, and a predicate without the
# no-live-worker term would have halted that run -- "a worse failure than the
# wedge", in the bead's words. So the term is load-bearing, and it is free:
# live_forges() is already consulted by the drain check on every pass, and a
# waiting pass is exactly the case where any_dispatchable() is NOT asked.
#
# N ABSORBS ONE TRANSIENT AND IS NOT A THRESHOLD IN THE REFUTED SENSE. Between
# dispatch_pass and the drain check a bead can BECOME startable (the Mayor
# labels it fleet-safe in that window; bd refuses one claim under contention and
# grants the next). One such pass counts as a stall and the next pass dispatches
# it, which resets the count. So N > 1, N is small, and its value is not
# load-bearing the way a clock's would be: a real stall reproduces itself on
# EVERY pass, so any N halts it, and all N decides is how many odd single
# passes are forgiven. FLEET_STALL_PASSES=3 is 90 seconds at the shipped
# FLEET_POLL, against a wedge that ran sixteen minutes.
#
# THE COUNTERS ARE WRITTEN BY THE PASSES THEMSELVES and reset by the main loop
# at the top of every pass. reap_pass counts a worker it took in hand;
# dispatch_pass counts a bead it dispatched, or would have under --dry-run.
# pass_note is the last place a pass DIVERGED -- a bead that passed
# dispatchable() and was still not started, a queue that could not be read, no
# free slot -- so the halt names what the stall was made of and not only that
# one happened. The `${var:-0}` spelling in the passes is deliberate:
# governor-harness.sh extracts reap_pass() and runs it under `set -u` with only
# the launcher's preamble declared, and an unbound counter there would fail
# three governor cases as though the LAUNCHER were wrong (2026-09-10).
pass_dispatched=0; pass_reaped=0; pass_note=""
pass_workbench_held=0   # Proofdelve ForgeOs-9srgz A5: candidates held by the live Workbench sitting's touch set this pass
pass_held_unlanded=0   # Proofdelve ForgeOs-b9mj round three: candidates held behind a reapable, not-live holder this pass
stall_passes=0; stall_peak=0; waiting_said=0; held_said=0
reapable_said=0   # Proofdelve ForgeOs-dx34.18: the drain check's own once-per-stretch sentence
stall_check() {  # $1 live Forge count, $2 startable work: yes | no | unknown.
                 # Called once per pass, after both passes. Resets on any pass
                 # that did work; counts when nothing is live and work is
                 # startable; halts on the Nth; leaves a waiting pass alone.
  if [ "${pass_dispatched:-0}" -gt 0 ] || [ "${pass_reaped:-0}" -gt 0 ]; then
    if [ "$stall_passes" -gt 0 ]; then
      say "stall counter reset from $stall_passes: this pass dispatched $pass_dispatched and reaped $pass_reaped"
    fi
    stall_passes=0; waiting_said=0; reapable_said=0; held_said=0
    return 0
  fi
  if [ "$1" -gt 0 ]; then
    # Said once per quiet stretch, not once per pass: a Forge session is tens of
    # minutes and the narrative log does not need a line every FLEET_POLL to
    # say the same thing. The sentence exists so a reader of a long-gap run can
    # see WHY the counter did not move (Proofdelve ForgeOs-dx34.9 acceptance 4).
    if [ "$waiting_said" != 1 ]; then
      say "waiting: nothing to reap or dispatch while $1 Forge(s) are live -- a quiet pass with a live worker is not a stall, and the stall counter ($stall_passes/$FLEET_STALL_PASSES) is not touched"
      waiting_said=1
    fi
    return 0
  fi
  if [ "${pass_mem_held:-0}" -gt 0 ]; then
    # Proofdelve ForgeOs-asad6: refused for memory, which returns without anyone acting.
    # Not counted; said once per quiet stretch, like the other waits.
    if [ "$held_said" != 1 ]; then
      say "waiting: startable work is held for memory (${pass_note:-see the dispatch line}); not a stall, and the stall counter ($stall_passes/$FLEET_STALL_PASSES) is not touched. Said once per quiet stretch."
      held_said=1
    fi
    return 0
  fi
  if [ "${pass_workbench_held:-0}" -gt 0 ]; then
    # Proofdelve ForgeOs-9srgz A5: candidates held by the live Workbench sitting's touch
    # set, which clears without the fleet acting. Not counted; said once per
    # quiet stretch.
    if [ "$held_said" != 1 ]; then
      say "waiting: $pass_workbench_held candidate(s) held by the live Workbench sitting's touch set; not a stall, and the stall counter ($stall_passes/$FLEET_STALL_PASSES) is not touched. Said once per quiet stretch."
      held_said=1
    fi
    return 0
  fi
  [ "$2" = yes ] || return 0   # nothing startable: the drain check decides (drain, or wait on a reapable worker -- Proofdelve ForgeOs-dx34.18); not a stall either way
  # A CANDIDATE HELD BEHIND AN UNLANDED, NOT-LIVE HOLDER IS A WAITING PASS
  # (Proofdelve ForgeOs-b9mj round three; the reasoning is on touch_conflict_with_live).
  # The holder is reapable, so the next pass takes it: its merge lands or it
  # is paged, and either way the hold ends. Counting this pass would halt the
  # fleet on an ordinary parked merge. Requires a reapable worker to EXIST, so
  # a stale .touches-dry or a phantom hold cannot switch the detector off.
  if [ "${pass_held_unlanded:-0}" -gt 0 ] && [ "$(reapable_workers)" -gt 0 ]; then
    if [ "$held_said" != 1 ]; then
      say "waiting: $pass_held_unlanded candidate(s) held behind a worker whose branch has not landed (deferred merge, parked, or finished) -- the next pass takes that worker; not a stall, and the stall counter ($stall_passes/$FLEET_STALL_PASSES) is not touched. Said once per quiet stretch."
      held_said=1
    fi
    return 0
  fi
  stall_passes=$((stall_passes + 1))
  [ "$stall_passes" -gt "$stall_peak" ] && stall_peak=$stall_passes
  say "stall $stall_passes/$FLEET_STALL_PASSES: this pass dispatched nothing and reaped nothing, no Forge is live, and the drain check finds startable work${pass_note:+ -- $pass_note}"
  [ "$stall_passes" -ge "$FLEET_STALL_PASSES" ] || return 0
  halt "$stall_passes consecutive passes changed no state: nothing dispatched, nothing reaped, no Forge live, and startable work still queued${pass_note:+ ($pass_note)}. The loop cannot clear this by itself; the passes are in $narrative_log" stalled
}

# ---------------------------------------------------------------------------
# TOUCH SETS AND THE CO-DISPATCH GUARD (Proofdelve ForgeOs-b9mj, Regent edict 2026-09-14,
# Overseer present).
# ---------------------------------------------------------------------------
# TWO FORGES CANNOT CLOBBER EACH OTHER IN FLIGHT -- separate worktrees, separate
# branches, mask-granted writes only to their own tree -- SO THEY COLLIDE AT THE
# MERGE, and until this guard the collision was discovered AFTER the review
# launch was spent. 2026-09-13 14:59: Proofdelve ForgeOs-o6ky.13 passed verify, took a
# full Warden review (APPROVE-WITH-FINDINGS), and then 'merge into main failed
# and was aborted'. The same night bead/jtvl.1 and bead/aqc6.2.6 both edited
# tests/Product.Tests/MigrationTests.cs and the Mayor resolved it by union under
# a recorded one-time exception. The Mayor had been sequencing overlapping beads
# by hand with blocks edges, which lives in one head and is checked by nothing.
#
# THE MECHANISM. A bead may declare what it edits as ONE line in its description:
#
#   Touches: web/src/App.tsx, src/Product.Infrastructure/Migrations/, docs/*
#
# Paths or globs, separated by commas or whitespace; the FIRST such line is the
# declaration and later ones are ignored. Each entry is reduced to a PREFIX: a
# glob is its text up to the first wildcard (`docs/*` -> `docs/`), a leading
# `./` or `/` is dropped, and nothing else is interpreted -- there is no matcher
# here on purpose (the docket's own words: "do not build a matcher"). Two sets
# INTERSECT when any prefix of one is a prefix of any prefix of the other, in
# either direction. That over-refuses (`src/Foo` and `src/FooBar/` intersect) and
# the direction of that error is the safe one: an over-refusal costs one pass of
# waiting, an under-refusal costs a spent review.
#
# A MIGRATION BEAD IMPLICITLY TOUCHES THE WHOLE Migrations/ DIRECTORY, because
# every migration rewrites the model snapshot that lives there: any declared
# prefix under the Migrations/ directory (touches_migrations) is widened to the directory itself, so two
# migration beads never co-dispatch however narrowly each was declared.
#
# A BEAD WITH NO Touches LINE TOUCHES EVERYTHING. That is the conservative
# reading and it is exactly today's behaviour: such a bead dispatches only when
# no Forge is live, and while it is live nothing else dispatches. An unlabelled
# board therefore degrades to SERIAL, never to collisions, and the Mayor widens
# concurrency one declared bead at a time. A worker directory with no touches
# file (one dispatched by a launcher older than this guard) is read the same
# way, for the same reason.
#
# WHERE IT SITS: in dispatch_pass, after dispatchable() and the launcher-lock
# skip, BEFORE the budget, the claim and anything else that mutates. A refusal
# here writes nothing anywhere: the bead stays ready and is asked again next
# pass. The candidate's set is computed once per pass from bd and is CACHED in
# $wdir/touches at dispatch, so a live worker's set is read from disk and never
# re-fetched from a tracker that may be busy. Workers dispatched EARLIER IN THE
# SAME PASS are live (their directory is inside the launch grace window), so a
# second candidate in one pass is checked against the first.
#
# WHAT THIS GUARD DOES NOT DO. It does not sequence: a refused bead is not
# blocked, it waits, and dispatches the moment the overlapping holder lands or
# is reaped. It does not touch ready_candidates() ordering, the human/gate
# refusals in dispatchable(), or any_dispatchable().
#
# WHAT IT DOES TO THE STALL DETECTOR, AND THE REGRESSION IT SHIPPED ONCE
# (the Warden, round two on ad911a7, the blocking finding). The first
# text here said the detector was untouched "because this guard never refuses
# when no Forge is live". That was true while the predicate was worker_live
# and became false the moment it widened to reapable workers: a DEFERRED MERGE
# holds its set with no Forge live; an undeclared candidate (everything) is
# held behind it; any_dispatchable() knows nothing of touch sets and says
# startable=yes; the deferred merge's repeat-reason retry backs its own reap
# count out; so the pass reads "dispatched nothing, reaped nothing, no Forge
# live, work startable" and stall_check halted the fleet on the third such
# pass -- ninety seconds after any parked merge on a dirty tree, which the
# file's own text calls transient and self-healing. A candidate held behind
# a holder that is reapable and NOT live is therefore a WAITING pass in
# dx34.18's sense ("a reapable worker is work"): dispatch_pass counts it in
# pass_held_unlanded, and stall_check leaves the counter alone when that
# count is nonzero and a reapable worker exists, said once per quiet stretch
# like the live-Forge case. A candidate held behind a LIVE Forge never
# reaches stall_check's counting branch at all (live > 0 returns first).
# Functions, not variables, so scripts/governor-harness.sh's extraction carries
# them with their callers (the env_signature() precedent: a top-level variable
# is unbound there under set -u).
touches_migrations() { printf '%s' '<no-migrations-in-this-fort>/'; }   # Manyhalls has no migrations directory; the collapse below never fires
touches_everything() { printf '%s' '<everything>'; }   # a sentinel no path can spell

touch_prefix() {  # $1 one declared path or glob -> its normalised prefix (may be empty)
  local p="$1"
  p="${p%%[*?[]*}"                       # a glob is its prefix up to the first wildcard
  while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
  p="${p#/}"
  case "$p" in "$(touches_migrations)"*) p="$(touches_migrations)" ;; esac
  printf '%s\n' "$p"
}

touch_set_of() {  # $1 bead -> one prefix per line on stdout, or the sentinel alone
  local json line tok pfx any=0
  json="$(bead_json "$1" 2>/dev/null || true)"
  line="$(printf '%s' "$json" | python3 -c '
import json, sys, re
raw = sys.stdin.read().strip()
if not raw or raw == "null": sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict) and "data" in d: d = d["data"]
if isinstance(d, list): d = d[0] if d else {}
for l in (d.get("description") or "").splitlines():
    m = re.match(r"\s*Touches:\s*(.*?)\s*$", l)
    if m:
        print(m.group(1)); break
' 2>/dev/null || true)"
  # commas and whitespace both separate; an entry that normalises to nothing
  # (`*`, `/`, `.`) is the whole tree and makes the set everything. `read -a`
  # and not a bare `for tok in $line`: an unquoted expansion GLOBS, so a
  # declared `*` became the dispatcher's cwd listing on the first fixture run.
  local -a toks=()
  read -r -a toks <<< "${line//,/ }"
  for tok in "${toks[@]}"; do
    any=1
    pfx="$(touch_prefix "$tok")"
    if [ -z "$pfx" ]; then touches_everything; echo; return 0; fi
    printf '%s\n' "$pfx"
  done
  [ "$any" = 1 ] || { touches_everything; echo; }
}

# THE DELIVERABLE DECLARATION (Proofdelve ForgeOs-nz3u). A bead whose deliverable is an
# ANSWER rather than a diff -- an investigation, a measurement, an audit, or
# any bead whose premise turns out to be false and whose only honest output is
# a report -- says so in its DESCRIPTION with a line `Deliverable: answer`,
# written by the Mayor at filing exactly as `Touches:` is, and never by the
# Forge. reap_pass's handoff-only guard (ss9d, below) consults it: a declared
# bead whose branch differs from main only under fort/handoffs/ proceeds to the
# verifier and the review (the Warden is the acknowledger of an answer); an
# undeclared one is returned exactly as before. Nothing else reads it. It does
# not read acceptance criteria (nobody teaches fleet.sh English, Proofdelve ForgeOs-j3kp),
# it adds no verdict token, and it is not a bd status: a status is what the
# fleet changes as work moves, a declaration is what the filer states about
# what done means. Prints the declared word, lower-cased, or nothing.
deliverable_of() {  # $1 bead -> the declared deliverable on stdout ("answer"), or nothing
  local json
  json="$(bead_json "$1" 2>/dev/null || true)"
  printf '%s' "$json" | python3 -c '
import json, sys, re
raw = sys.stdin.read().strip()
if not raw or raw == "null": sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict) and "data" in d: d = d["data"]
if isinstance(d, list): d = d[0] if d else {}
for l in (d.get("description") or "").splitlines():
    m = re.match(r"\s*Deliverable:\s*(\S+)\s*$", l)
    if m:
        print(m.group(1).lower()); break
' 2>/dev/null || true
}

touch_sets_intersect() {  # $1 file A, $2 file B -> 0 and the overlapping pair on stdout, else 1
  local a b every; every="$(touches_everything)"
  local -a A=() B=()
  [ -s "$1" ] && mapfile -t A < "$1"
  [ -s "$2" ] && mapfile -t B < "$2"
  # an absent or empty file is a worker with no declaration: everything
  [ "${#A[@]}" -gt 0 ] || A=("$every")
  [ "${#B[@]}" -gt 0 ] || B=("$every")
  for a in "${A[@]}"; do
    [ "$a" = "$every" ] && { printf '%s\n' "$a"; return 0; }
  done
  for b in "${B[@]}"; do
    [ "$b" = "$every" ] && { printf '%s\n' "$b"; return 0; }
  done
  for a in "${A[@]}"; do
    for b in "${B[@]}"; do
      if [[ "$b" == "$a"* ]] || [[ "$a" == "$b"* ]]; then printf '%s ~ %s\n' "$a" "$b"; return 0; fi
    done
  done
  return 1
}

# Does this candidate's set (a file) overlap any worker's that HOLDS AN
# UNLANDED BRANCH? On stdout: the other bead and the pair, for the pass_note
# and the skip line. Same stdout discipline as live_forges(): this function's
# stdout is its answer.
#
# "HOLDS AN UNLANDED BRANCH" AND NOT "IS LIVE" (the Warden, covenant-4.5
# review of 40c3d6d, finding 1). The collision this guard prevents happens at
# the MERGE, and a worker whose Forge has finished still holds an approved,
# unmerged branch: finished, parked-budget, parked-review, parked-signed and
# above all deferred-merge (a tree not landable, a merge slot held) -- none of which is
# running|launching. The first cut asked worker_live, as the docket said, so
# an overlapping candidate could dispatch beside a deferred merge off a main
# that lacked its changes. The predicate is now live OR reapable: exactly the
# workers whose branch has not landed. A settled worker holds nothing.
#
# A DRY RUN CONSULTS ITS OWN PASS TOO (finding 3): the dry branch writes no
# worker directory, so the second candidate of one dry pass was never checked
# against the first and both printed "would dispatch" where a real pass holds
# one. Dry-dispatched sets are kept in $state/.touches-dry/ for the pass and
# read here beside the workers; dispatch_pass clears that directory on entry.
# THE WORKBENCH AS A HOLDER (Proofdelve ForgeOs-9srgz A5, the docket's original design,
# which the Overseer restored at the sitting). While a sitting is live its set
# is the session branch's diff from main (three dots: its own changes, not
# main's movement since the cut) plus every uncommitted or untracked path in
# its worktree, written to $state/.touches-workbench as exact paths. An EMPTY
# set (a sitting that has changed nothing yet) is no file at all, because an
# empty touch file means "everything" to touch_sets_intersect(). A live sitting
# whose set cannot be read FAILS CLOSED: the file holds the everything sentinel
# and every candidate waits, which is what a declared bead costs when it cannot
# be read either. The bead id is kept in .touches-workbench.bead for the
# skip line. A file write, not a global: touch_conflict_with_live() runs inside
# $( ), where a global would be lost.
workbench_touches_refresh() {
  local f="$state/.touches-workbench" wbl bead sfx wt tmp ok=1 rec xy old
  rm -f "$f" "$f.bead"
  wbl="$(workbench_live)" || return 0
  bead="${wbl%% *}"; sfx="${bead##*-}"
  wt="$(sed -n 's/^worktree=//p' "$state/workbench.live" 2>/dev/null | head -1)"
  [ -n "$wt" ] || wt="$root-worktrees/$sfx"
  tmp="$f.tmp.$$"
  # READ WITHOUT TOUCHING THE SITTING (the Warden, finding 1 on the docket review).
  # A plain `git status` refreshes the index and writes it back under
  # index.lock, so a poll landing in the same moment as the Workbench's `git add` or
  # `git commit` fails his command with "index.lock: File exists" -- the fleet
  # disrupting the attended seat. GIT_OPTIONAL_LOCKS=0 is git-status(1)'s own
  # advice for background scripts, and scripts/stranded-sweep.sh already uses it.
  #
  # BOTH NAMES OF A RENAME, AND RAW PATHS (finding 2). --no-renames makes the
  # branch diff list a rename as the old path deleted and the new one added,
  # and -z on both commands gives paths unquoted: without it a path with a
  # space or a non-ASCII byte comes back "quoted" and can never match a
  # candidate's prefix. Porcelain -z writes a rename or copy as
  # "XY new\0old\0", so the loop reads the old name as a second field.
  #
  # ONE FILE PER COMMAND, NOT A PIPELINE: `ok=0` set inside a pipeline stage is
  # set in a subshell and lost, and the fail-closed branch below would never
  # fire (shellcheck SC2030 caught that in the first draft).
  GIT_OPTIONAL_LOCKS=0 git -C "$root" diff --name-only --no-renames -z "$main_branch...bead/$sfx" > "$tmp.diff" 2>/dev/null || ok=0
  GIT_OPTIONAL_LOCKS=0 git -C "$wt" status --porcelain -z --untracked-files=all > "$tmp.st" 2>/dev/null || ok=0
  {
    tr '\0' '\n' < "$tmp.diff"
    while IFS= read -r -d '' rec; do
      xy="${rec:0:2}"
      printf '%s\n' "${rec:3}"
      case "$xy" in
        R*|C*|?R|?C) IFS= read -r -d '' old && printf '%s\n' "$old" ;;
      esac
    done < "$tmp.st"
  } > "$tmp.raw"
  sed '/^$/d' "$tmp.raw" | sort -u > "$tmp"; rm -f "$tmp.raw" "$tmp.diff" "$tmp.st"
  if [ "$ok" = 0 ]; then
    touches_everything > "$tmp"; printf '\n' >> "$tmp"
    say "workbench: the live sitting on $bead has a touch set that cannot be read (bead/$sfx or $wt); holding EVERY candidate this pass (fails closed, Proofdelve ForgeOs-9srgz)"
  fi
  if [ -s "$tmp" ]; then mv -f "$tmp" "$f"; printf '%s\n' "$bead" > "$f.bead"; else rm -f "$tmp"; fi
}

touch_conflict_with_live() {  # $1 candidate touch-set file -> 0 and "<bead> on <pair>"; a Workbench hold is prefixed "WORKBENCH "
  local d obead pair
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    # IN-HAND HOLDS TOO (Proofdelve ForgeOs-uwjme): a refill runs while a worker is in the
    # completion lane, and that worker's branch has not landed.
    if ! worker_live "$d" && ! worker_reapable "$d" && [ "$(worker_state "$d")" != in-hand ]; then continue; fi
    obead="$(cat "$d/bead" 2>/dev/null || basename "$d")"
    if pair="$(touch_sets_intersect "$1" "$d/touches")"; then
      printf '%s on %s\n' "$obead" "$pair"; return 0
    fi
  done
  for d in "$state/.touches-dry"/*; do
    [ -f "$d" ] || continue
    if pair="$(touch_sets_intersect "$1" "$d")"; then
      printf '%s (dry-run, this pass) on %s\n' "$(basename "$d")" "$pair"; return 0
    fi
  done
  if [ -s "$state/.touches-workbench" ] && pair="$(touch_sets_intersect "$1" "$state/.touches-workbench")"; then
    printf 'WORKBENCH %s on %s\n' "$(cat "$state/.touches-workbench.bead" 2>/dev/null || echo '?')" "$pair"; return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# SIGNED LANDING (Proofdelve ForgeOs-ubgx). AN APPROVAL IS PINNED TO A CHANGE, NOT A BEAD.
# ---------------------------------------------------------------------------
# WHAT THIS ANSWERS. A Warden ESCALATE puts a bead on the Overseer's queue with
# the `human` label; his Approve on the Keep removes it and restores fleet-safe
# (Proofdelve ForgeOs-bwfv). Until this block existed the fleet then treated the bead as
# NEW WORK: a Forge dispatched into the reused worktree, read his approval and
# wrote a handoff, the verifier ran, a Warden was launched, she approved on his
# signature, and it merged -- three launches on finished, signed work, measured
# eight times on 2026-09-17 alone (aqc6.2.8.3, 8 min; aqc6.2.3.1, 2h07m behind
# that lap under the touch-set guard) -- and a Mayor stood between the mechanism
# and the race by removing fleet-safe by hand (cmhy, 2026-09-15 10:21). His
# stated goal, on the bead: "when I approve something it can then move forward
# with the fleet effectively, and not require duplicate levels of approval from
# me for the same thing."
#
# THE PROPERTY, in the Mayor's reading on the bead, which the Overseer did not
# object to: an approval covers a CHANGE. While the branch still carries the
# reviewed change the fleet may LAND on that approval and must not re-review or
# re-escalate; the instant the change differs the approval no longer covers it
# and the bead routes to review again. Not "approval bypasses review": what
# makes a signature meaningful is that it names code.
#
# "SAME CHANGE" IS A PATCH-ID, NOT A SHA. prelanding_refresh() merges main into
# the branch before every landing and moves the tip, so a SHA rule would never
# fire. `git diff <merge-base main X> X | git patch-id --verbatim` is the same
# for the approved sha and the current tip exactly when the branch carries the
# same change against its base (verbatim, so whitespace counts; the Warden 1.3). A refresh that CONFLICTS is already paged as a
# person's merge (Proofdelve ForgeOs-36b9) and takes a landing-lap child, a new change and
# a new signature; a refresh that merges cleanly but changes the patch (main
# touched the same lines) is likewise a different change and goes to review.
#
# FOUR QUESTIONS, ALL YES OR NOTHING HAPPENS HERE (fail closed, header rule 2):
#   1. the worker record for this bead holds a stored verdict of ESCALATE --
#      written by review_one()'s ESCALATE branch, so an escalation that predates
#      that line takes today's full lap once and records it on the way out;
#   2. the NEWEST sign event for this bead in the fort's stream (gate.approved,
#      gate.declined or decision.recorded) is a gate.approved whose payload
#      carries an approvedSha -- the Keep records the branch tip at signing time
#      (tools/keep/server.mjs, resolve-sha; docs/specs/keep-dashboard-v2.md);
#      null (a Mayor-lane bead with no branch) is no, and a later Decline or
#      Decide supersedes an earlier approve (the Warden 1.4);
#   3. the patch-id of the approved sha against its merge base with main equals
#      the patch-id of the branch tip against its merge base with main;
#   4. where the ESCALATE arm recorded the tip the Warden reviewed, its patch-id
#      equals the approved one too (the Warden 1.2): what lands is what was reviewed
#      AND what was signed.
# dispatchable() has already said yes before any of this is asked, so
# `fleet-escalated`, `human`, a non-open status and an open blocker refuse
# exactly as they do for a dispatch (criterion 4 on the bead). ONE landing per
# pass at most goes through here per candidate; the questions cost git reads
# and a scan of the recent stream, no bd write and no launch.
#
# WHAT A SIGNED LANDING DOES: no Forge, no review launch. The bead is claimed
# for the fleet actor (no Forge acts, so the claim names the mechanism), a fresh
# worker record is written, prelanding_refresh() runs, the patch-id is
# RECOMPUTED on the refreshed tip -- a refresh that changed it ROUTES TO REVIEW
# (verifier, then review_one(), and the Warden decides; his approval covers what
# it named and nothing else) -- the host verifier runs, and a green tree lands
# through land() on the token OVERSEER-SIGNED, which closes the bead as a plain
# APPROVE does. A red verifier on the SIGNED change is PAGED, never returned: a
# Forge fix would be a different change needing its own review and signature,
# and re-dispatching over signed work is the lap this block exists to end. One
# fleet.signed event names the sha and the patch-id it landed on, so the record
# says WHY no review happened.
#
# THE TOKEN IS THE FLEET'S OWN. No Warden emits OVERSEER-SIGNED; it exists so
# the merge record, the close reason and the deferred-merge retry say what
# actually authorised the merge instead of borrowing APPROVE. It shares no
# prefix with any Warden token (the 2026-09-09 rule on prefix-parsed ladders).
signed_sha=""; signed_patch=""; signed_tip=""
patch_id_of() {  # $1 commit-ish -> the verbatim, order-stable patch-id of its diff from its merge base with main; nothing on any failure
  local base
  base="$(git -C "$root" merge-base "$main_branch" "$1" 2>/dev/null)" || return 1
  [ -n "$base" ] || return 1
  # --verbatim (the Warden, 1.3 on the 2026-09-17 sitting): --stable strips
  # whitespace from every hashed line, so a hand commit after the approval
  # that changed only whitespace inside added lines -- indentation in a YAML
  # or Python file, a quoting change in a script -- kept the id and landed on
  # the signature. A whitespace change is a change. MEASURED on git 2.54
  # rather than read: --verbatim and --stable refuse to be combined (exit
  # 129), --verbatim alone is order-stable (the same id with the files of a
  # diff reordered) and whitespace-sensitive, --stable alone is not. So the
  # flag is --verbatim by itself, and it carries what --stable bought.
  git -C "$root" diff "$base" "$1" 2>/dev/null | git patch-id --verbatim 2>/dev/null | cut -d' ' -f1
}
latest_approved_sha() {  # $1 bead -> the approvedSha of the NEWEST sign event for it in the last 14 day files, if that event is an approve; nothing otherwise
  # Selected on the category and target FIELDS, never grepped: a bead id quoted
  # inside another event's detail would match a grep (the 2026-09-09 rule).
  # THE NEWEST SIGN EVENT OF ANY KIND DECIDES, AND ONLY AN APPROVE COUNTS
  # (the Warden, 1.4): reading gate.approved alone would let an Approve followed by
  # a Decline or a Decide on the same bead still land, because neither of
  # those removes fleet-safe. Unreachable through the Keep today (the bead
  # leaves needs-you when human goes) and closed here anyway.
  # ONLY THE KEEP'S OWN EVENTS ARE SIGN EVENTS (Proofdelve ForgeOs-jib0; the Overseer's
  # ruling of 2026-11-14, built at the Regent sitting of 2026-11-16). The Keeps
  # emit all three categories as actor justin, seat overseer. The Mayor and the
  # Regent also emit decision.recorded and gate.approved under their OWN names,
  # as transcriptions of something he said in a session. Until this filter the
  # newest of ANY of them decided, so a Mayor's decision.recorded written after
  # a Keep approve superseded the approval and the signed bead took a second
  # full lap. Now an event from any other actor or seat is not read here at
  # all: it neither supersedes an approval nor counts as one. What this does
  # not do: the stream has no origin, so a seat that emitted under the
  # Overseer's name would still be read here. That is the covenant's
  # compromise signature, and keep_corroborates() below answers it from the
  # Keep's audit, which no seat can write.
  printf '%s\n' "$root"/fort/events/events-*.jsonl | sort | tail -14 | python3 -c '
import json, sys
bead = sys.argv[1]; best = None
SIGN = ("gate.approved", "gate.declined", "decision.recorded")
for path in sys.stdin.read().split():
    try:
        with open(path) as fh:
            for line in fh:
                try: e = json.loads(line)
                except Exception: continue
                if e.get("category") not in SIGN or e.get("target") != bead: continue
                if e.get("actor") != "justin" or e.get("seat") != "overseer": continue
                ts = e.get("ts") or ""
                if best is None or ts >= best[0]: best = (ts, e)
    except OSError: continue
if best is None: sys.exit(0)
if best[1].get("category") != "gate.approved":
    print("SUPERSEDED %s %s" % (best[1].get("category"), best[0])); sys.exit(0)
p = best[1].get("payload")
sha = p.get("approvedSha") if isinstance(p, dict) else None
print(sha if isinstance(sha, str) else "")
' "$1" 2>/dev/null
}
# THE KEEP'S OWN RECORD CORROBORATES THE STREAM (Proofdelve ForgeOs-ubgx.4, Regent edict
# 2026-10-06). The stream has no origin: emit.sh authenticates nothing and the
# day files are seat-writable, so a gate.approved there is a claim anyone in a
# seat could make. The Keeps write a `pin` line naming the approvedSha into
# their own audit, and that audit now lives in the Overseer store, which
# lib/seat-sandbox.sh binds read-only in every seat mask of every fort. So a
# landing needs the SAME sha in both places: the stream (newest sign event,
# question 2 below) and a Keep record. Either desk counts: the Civ Keep
# (civ-keep/, lines carry fort "fortkit") and this fort's own store
# (manyhalls-keep/). The lib creates BOTH directories at every launch if they are
# absent and binds them read-only, so the own store is the Overseer's whether or
# not this fort runs a Keep of its own; where it runs none the store is empty
# and only the Civ Keep's record can corroborate. A store a seat could create
# first is a signature a seat could seed (the Warden, review 2 on fortkit-ttpk;
# scripts/workbench-mask-harness.sh measures it, red arm 5).
# THE DATED CUTOVER (the Overseer's choice, 2026-10-06). Signatures given before
# the Keeps wrote pin lines have no sha in any record. Rather than trust stream
# events by their timestamp -- which a seat writes, so a backdated forgery would
# pass -- the pre-cutover approvals were SNAPSHOTTED once, by the Regent on the
# host, into civ-keep/legacy-approvals.jsonl, which is read-only to seats like
# the rest of the store. Exactly those (bead, sha) pairs land on the stream
# alone. Nothing is ever added to that file.
# The store root follows the Keeps' own resolution (XDG_STATE_HOME), so a
# harness can point it at a fixture; mask_env forwards no XDG_STATE_HOME into a
# seat, and the unattended fleet runs from a host unit no seat can configure.
keep_corroborates() {  # $1 bead, $2 sha -> exit 0 when the Keep's own audit says his NEWEST decision on this bead is approve at that sha
  # THE NEWEST DECISION, READ FROM THE KEEP'S AUDIT (the Warden, finding A2 on the
  # 2026-10-06 sitting). The first version asked only "did a Keep ever pin this
  # sha for this bead", so a forged NEWER approve in the stream naming an old,
  # once-approved sha passed even after he had Declined in the Keep. The audit
  # is in the Overseer store, read-only to every seat: so the decision is taken
  # there. Every Keep action writes one intent line (it has an "action"); an
  # approve on a fleet fort also writes a "pin" line with the SAME ts naming the
  # sha. The newest intent across both desks decides:
  #   approve with a pin at its ts naming this sha  -> yes
  #   approve with no pin (given before pins existed) -> the pre-cutover snapshot decides
  #   decline / decide / an approve pinning another sha -> no
  #   no intent at all for this bead -> the pre-cutover snapshot decides
  local s="${XDG_STATE_HOME:-$HOME/.local/state}"
  python3 -c '
import json, sys
bead, sha, civ, own, legacy = sys.argv[1:6]
def lines(path):
    try:
        with open(path) as fh:
            for line in fh:
                try: yield json.loads(line)
                except Exception: continue
    except OSError: return
intents, pins = [], []
for path, needs_fort in ((civ, True), (own, False)):
    for e in lines(path):
        if e.get("bead") != bead: continue
        if needs_fort and e.get("fort") != "fortkit": continue
        if "action" in e: intents.append(e)
        elif e.get("step") == "pin": pins.append(e)
def snapshot_says():
    return any(e.get("fort") == "fortkit" and e.get("bead") == bead and e.get("approvedSha") == sha for e in lines(legacy))
if not intents:
    sys.exit(0 if snapshot_says() else 1)
newest = max(intents, key=lambda e: e.get("ts") or "")
if newest.get("action") != "approve": sys.exit(1)
at = [p for p in pins if p.get("ts") == newest.get("ts")]
if at: sys.exit(0 if any(p.get("approvedSha") == sha for p in at) else 1)
sys.exit(0 if snapshot_says() else 1)
' "$1" "$2" "$s/civ-keep/signatures.jsonl" "$s/manyhalls-keep/signatures.jsonl" "$s/civ-keep/legacy-approvals.jsonl" 2>/dev/null
}
# THE QUESTIONS, ENUMERATED HERE AND COUNTED NOWHERE ELSE (Proofdelve ForgeOs-ubgx.3 item
# 2.1). Three call sites said "the three questions" and there have been FOUR
# since the Warden's 1.2 added the reviewed tip; a count written into prose in four
# places is a count that goes stale in three of them, which is what happened.
# The other sites now name this function instead of a number.
#   1. does the worker's STORED VERDICT admit a landing at all
#      (stored_verdict_is_signable: ESCALATE, or the fleet's own
#      OVERSEER-SIGNED from a landing whose merge failed)?
#   2. is the NEWEST sign event for this bead an approve carrying a 40-hex
#      approvedSha that is a commit in this repository, AND does a Keep record
#      in the Overseer store pin that same sha (keep_corroborates, ubgx.4)?
#   3. does bead/<sfx> still exist, with its worktree, and does its tip carry
#      the SAME CHANGE as the approved sha by patch-id?
#   4. and where the ESCALATE arm recorded a reviewed tip, does THAT tip carry
#      the same change too -- so what lands is what was reviewed as well as
#      what was signed?
#
# Silent yes and the three globals above; nonzero for no with the reason in
# signed_why. NOTHING ON STDOUT, so the caller never has to run it inside a
# command substitution -- a value set inside $( ) is set in a subshell and the
# three globals would die there, which is how the first draft of this block
# read every signed landing as "the patch changed" (the 2026-09-09 rule).
# Returns 2 for the ordinary case (no stored ESCALATE: not a signed bead at
# all) so the caller can stay quiet about it, and 1 for a refusal worth a line:
# an escalated bead the fleet looked at and would not land.
# THE STORED-VERDICT PRE-FILTER, IN ONE PLACE (Proofdelve ForgeOs-czhb's rule applied to a
# new pair of callers). signed_landing_ready() asks it of one worker, and
# dispatch_pass asks it of every worker before it will spend a tracker query on
# phase 1 at all. Two copies of this `case` would be two deciders that can
# disagree, and the disagreement would be invisible: the cheap one skipping a
# bead the expensive one would have landed.
stored_verdict_is_signable() {  # $1 a stored verdict token
  case "$1" in ESCALATE|OVERSEER-SIGNED) return 0 ;; *) return 1 ;; esac
}
signed_why=""
signed_landing_ready() {  # $1 bead, $2 sfx
  local bead="$1" sfx="$2" wdir="$state/workers/$2" wt="$root-worktrees/$2" stored sha tip pa pt
  signed_sha=""; signed_patch=""; signed_tip=""; signed_why=""; signed_superseded_by=""
  stored="$(cat "$wdir/verdict" 2>/dev/null || echo "")"
  # OVERSEER-SIGNED IS ACCEPTED AS WELL AS ESCALATE, AND THE REASON IS
  # land()'S MERGE-FAILED BRANCH (Proofdelve ForgeOs-ohsy, the Warden's 1.5, the rarer half).
  # land() writes the verdict token before anything can defer, so a signed
  # landing whose `git merge` failed and was aborted goes back to the queue
  # carrying OVERSEER-SIGNED -- the fleet's OWN token, which no Warden ever
  # emits. Read as "not a signed bead" it took a full FORGE LAP over work the
  # Overseer had already signed. It is only ever a cheap PRE-FILTER: the gate
  # is the questions below, which re-read the approval out of the event stream
  # and re-compare the patch-id from scratch, so accepting it widens nothing a
  # signature does not already cover and stays fail-closed.
  stored_verdict_is_signable "$stored" || return 2
  sha="$(latest_approved_sha "$bead" || echo "")"
  case "$sha" in
    "SUPERSEDED "*)
      signed_superseded_by="${sha#SUPERSEDED }"   # "<category> <ts>"; phase 1's Decline guard reads it (Proofdelve ForgeOs-0x25g)
      # The reason names the superseding event (the Warden 2.2): a reader sent to
      # look for a missing approval would find one that exists and was
      # overtaken -- by a Decline, or by a decision.recorded a Mayor emitted as
      # a transcription, which the fleet does not read as consent either way.
      signed_why="stored verdict ESCALATE and an approval exists, but the newest sign event for $bead is ${sha#SUPERSEDED } and not an approve, so the approval is superseded"; return 1 ;;
  esac
  if ! printf '%s' "$sha" | grep -qE '^[0-9a-f]{40}$'; then
    signed_why="stored verdict ESCALATE but no gate.approved carrying an approvedSha for $bead in the recent stream"; return 1
  fi
  if ! git -C "$root" rev-parse --verify --quiet "$sha^{commit}" >/dev/null 2>&1; then
    signed_why="the approved sha $sha is not a commit in this repository"; return 1
  fi
  if ! keep_corroborates "$bead" "$sha"; then
    signed_why="the stream carries a gate.approved for $bead naming $sha, but no Keep record in the Overseer store pins it as his NEWEST decision (civ-keep, manyhalls-keep, or the pre-cutover snapshot): an approval only the seat-writable stream knows about is not one (Proofdelve ForgeOs-ubgx.4)"; return 1
  fi
  tip="$(git -C "$root" rev-parse --verify --quiet "bead/$sfx" 2>/dev/null)" || { signed_why="bead/$sfx does not exist"; return 1; }
  [ -d "$wt" ] || { signed_why="the worktree $wt is gone, so there is no tree to verify or land"; return 1; }
  pa="$(patch_id_of "$sha" || echo "")"; pt="$(patch_id_of "$tip" || echo "")"
  if [ -z "$pa" ] || [ -z "$pt" ]; then
    signed_why="a patch-id could not be computed (approved ${sha:0:12}: '${pa:-none}', tip ${tip:0:12}: '${pt:-none}')"; return 1
  fi
  if [ "$pa" != "$pt" ]; then
    signed_why="the branch has CHANGED since the approval: approved $sha (patch-id $pa), tip $tip (patch-id $pt) -- the signature does not cover this tree"; return 1
  fi
  # THE REVIEWED TIP, when the ESCALATE arm recorded one (the Warden, 1.2). A worker
  # escalated before that line has no file and this question is not asked of
  # it; the verdict file it also lacks refuses it above anyway -- the fleet was
  # HALTED between fc935e10 (the verdict file) and fd3443ed (this one), so no
  # worker can have one file and not the other. (Proofdelve ForgeOs-ubgx.3 item 2.5 asked
  # for the word "halted" here; e715ba56 had already added it. The two commits
  # are named now so the claim is checkable rather than merely stated.)
  local reviewed pr
  reviewed="$(cat "$wdir/reviewed-sha" 2>/dev/null || echo "")"
  if [ -n "$reviewed" ]; then
    pr="$(patch_id_of "$reviewed" || echo "")"
    if [ -z "$pr" ]; then
      signed_why="the reviewed tip $reviewed no longer yields a patch-id (branch rewritten since the review?)"; return 1
    fi
    if [ "$pr" != "$pa" ]; then
      signed_why="the branch CHANGED between the review and the approval: reviewed $reviewed (patch-id $pr), approved $sha (patch-id $pa) -- the Warden's ESCALATE and his signature name different changes"; return 1
    fi
  fi
  signed_sha="$sha"; signed_patch="$pa"; signed_tip="$tip"
  return 0
}
signed_landing() {  # $1 bead, $2 sfx, $3 worktree, $4 touch-set file. Reads the globals signed_landing_ready() set.
  local bead="$1" sfx="$2" wt="$3" tset="$4" wdir="$state/workers/$2"
  local sha="$signed_sha" pid="$signed_patch" tip="$signed_tip" now_pid vout
  # THE SAME CLAIM AND READ-BACK AS A DISPATCH, for the same reasons (see
  # dispatch_pass below): a claim that cannot be confirmed did not happen.
  if ! bd -C "$root" update "$bead" --claim -a "$fleet_actor" --actor "$fleet_actor" >/dev/null 2>&1; then
    say "skip $bead: claim refused for the signed landing (another worker got it first)"
    [ -n "${pass_note:-}" ] || pass_note="$bead: claim refused"
    return 0
  fi
  if [ "$(bead_json "$bead" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw or raw == "null": print(""); sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict) and "data" in d: d = d["data"]
if isinstance(d, list): d = d[0] if d else {}
print(d.get("assignee") or "")
' 2>/dev/null)" != "$fleet_actor" ]; then
    say "skip $bead: the signed landing's claim could not be read back -- failing closed"
    [ -n "${pass_note:-}" ] || pass_note="$bead: claim could not be read back"
    emit incident "Fleet claimed $bead for a signed landing and could not read the claim back; nothing landed" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\"}"
    return 0
  fi
  # THE WARDEN'S EVIDENCE SURVIVES THIS RESET, AND IT IS NOT THIS LANDING'S TO
  # DESTROY (Proofdelve ForgeOs-ohsy). `verdict` and `reviewed-sha` were written by the
  # review that escalated this bead; the rm -rf below took both, so an
  # interrupted landing left a worker signed_landing_ready() could no longer
  # recognise and the bead went round again as an unreviewed one. Read before,
  # written back after, and absent stays absent -- a worker escalated before
  # the reviewed-sha line exists has no such file and must not gain an empty one.
  # AND THE HELD WARDEN TOKEN AND HER RECORD (Proofdelve ForgeOs-vee4w): a bead the
  # signature hold stopped lands doing what she decided, which land() reads
  # from these two files. Same rule: absent stays absent.
  # ROUND TWO (the Warden's finding 5): the kept files are never removed at all,
  # rather than removed and restored, so no signal can land between the two.
  # Everything else in the worker directory goes; absent stays absent.
  # AND THE HOST-VERIFY RECORD (Proofdelve ForgeOs-gfuc1 A2): host_verify() below may
  # reuse it when the refresh from main brought in docs alone; it re-checks
  # every condition itself, so keeping a stale record costs only a re-run.
  find "$wdir" -mindepth 1 -maxdepth 1 ! -name verdict ! -name reviewed-sha \
    ! -name warden-verdict ! -name warden-record ! -name verified.json -exec rm -rf {} + 2>/dev/null || true
  mkdir -p "$wdir"
  local keep_wv; keep_wv="$(cat "$wdir/warden-verdict" 2>/dev/null || echo "")"
  # THE STORED VERDICT AS STORED (Proofdelve ForgeOs-a13g8): ESCALATE on the common path,
  # OVERSEER-SIGNED when a signed landing's merge failed and it came round
  # again (ohsy). The verdict file is one of the kept ones, so it is read here
  # and announced as it is, never as a literal.
  local stored_v; stored_v="$(cat "$wdir/verdict" 2>/dev/null || echo "")"; stored_v="${stored_v:-unrecorded}"
  printf '%s\n' "$bead" > "$wdir/bead"; date -Is > "$wdir/started"
  printf '%s\n' "$run_id" > "$wdir/run"
  cp -f "$tset" "$wdir/touches" 2>/dev/null || { touches_everything; echo; } > "$wdir/touches"
  printf '%s\n' "$sha" > "$wdir/approved-sha"
  worker_set_state "$wdir" in-hand "signed landing on the Overseer's approval of $sha (patch-id $pid), taken by run $run_id"
  pass_reaped=$((${pass_reaped:-0} + 1))   # a worker record was written and a bead claimed: real activity for the stall counter
  say "$bead: SIGNED LANDING -- the Overseer approved $sha and bead/$sfx (tip ${tip:0:12}) carries the same change (patch-id ${pid:0:12}); no Forge is dispatched and no review launch is spent (Proofdelve ForgeOs-ubgx)"
  emit fleet.signed "Fleet is landing $bead on the Overseer's recorded approval: gate.approved pins $sha and the branch tip $tip carries the same change (patch-id $pid), so no Forge is dispatched and no review launch is spent (Proofdelve ForgeOs-ubgx). The stored verdict is $stored_v${keep_wv:+ (the signature hold; the Warden returned $keep_wv)}; his signature is what authorises this merge." \
    -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"approvedSha\":\"$sha\",\"tip\":\"$tip\",\"patchId\":\"$pid\",\"storedVerdict\":\"$stored_v\",\"wardenVerdict\":\"${keep_wv:-}\"}"
  prelanding_refresh "$bead" "$sfx" "$wt" "$wdir" refresh "the fleet actor"
  case "$prelanding_result" in
    conflict|refused) return 0 ;;   # already paged and its state written (36b9)
    current|refreshed|unchecked) ;;
    *) worker_set_state "$wdir" needs-person "prelanding_refresh returned an unknown result '$prelanding_result' during a signed landing, which is a defect in fleet.sh rather than in the work"
       say "$bead: prelanding check returned '$prelanding_result' -- marked NEEDS A PERSON. This is a fleet.sh defect; report it."
       return 0 ;;
  esac
  vout="$state/logs/verify-$bead.txt"
  # RECOMPUTED AFTER THE REFRESH, ON THE TIP THAT WILL LAND. The signature
  # covers the patch it named; a refresh that changed the patch is a different
  # change and the Warden decides it, exactly as any unsigned branch.
  now_pid="$(patch_id_of "bead/$sfx" || echo "")"
  if [ "$now_pid" != "$pid" ]; then
    say "$bead: the refresh from $main_branch CHANGED the patch (approved ${pid:0:12}, now ${now_pid:-none}); the approval of ${sha:0:12} no longer covers this tree -- ROUTING TO REVIEW, not to merge (Proofdelve ForgeOs-ubgx)"
    say "$bead: running the host verifier in $wt"
    if host_verify "$wt" "$vout" "$wdir"; then
      say "$bead: verifier GREEN -- sending to review"
      review_one "$bead" "$wt"
    elif signalled; then
      worker_set_state "$wdir" finished "its host verifier was stopped by SIG$stop_signal, not failed; nothing was recorded against the bead"
      say "$bead: its host verifier was STOPPED by SIG$stop_signal, not failed. Nothing is recorded against this bead and it keeps its claim; the next run verifies it again."
    else
      worker_set_state "$wdir" settled "the host verifier was RED after the refresh from $main_branch changed the signed patch; the bead was returned to the queue"
      say "$bead: verifier RED after the refresh -- returned, never reviewed"
      return_to_ready "$bead" "the host verifier is RED in this bead's own worktree ($wt) after the fleet refreshed it from $main_branch, and the refresh had already changed the patch the Overseer approved. It was NOT sent to review." "$vout"
    fi
    return 0
  fi
  say "$bead: running the host verifier in $wt"
  if host_verify "$wt" "$vout" "$wdir"; then
    say "$bead: verifier GREEN -- landing on the Overseer's approval of ${sha:0:12}; no review launch is spent"
    land "$bead" "OVERSEER-SIGNED" ""
  elif signalled; then
    # `parked-signed` AND NOT `finished` (Proofdelve ForgeOs-ohsy, the Warden's 1.5). `finished`
    # resumes at verify-then-review, so an operator's Ctrl-C on a signed
    # landing spent a Warden launch on the signed, UNCHANGED change -- which on
    # a gate-1 diff must ESCALATE again and costs the Overseer a second click.
    # The whole point of the signed path is that neither is spent. The resume
    # re-asks signed_landing_ready()'s questions rather than trusting this
    # state: an approval can be superseded, and a branch can move, between the
    # signal and the next pass.
    worker_set_state "$wdir" parked-signed "its host verifier was stopped by SIG$stop_signal during a signed landing, not failed; nothing was recorded against the bead and the next pass resumes the landing"
    say "$bead: its host verifier was STOPPED by SIG$stop_signal during the SIGNED landing, not failed. Nothing is recorded against this bead and it keeps its claim; the next pass re-asks whether the approval still covers this tree and resumes the LANDING, not a review."
  else
    worker_set_state "$wdir" needs-person "the SIGNED change (approved $sha, patch-id $pid) is RED in the host verifier after the refresh from $main_branch; the fleet will not land a red tree and will not re-implement a signed change"
    say "$bead: verifier RED on the SIGNED change -- not landed; PAGING a person (a Forge fix would be a different change and needs its own review and signature)"
    page_overseer "$bead" "the Overseer approved $sha and bead/$sfx still carries exactly that change (patch-id $pid), but the host verifier is RED in $wt after the fleet refreshed it from $main_branch. The fleet will not land a red tree and will not dispatch a Forge over a signed change: any fix is a different change and needs its own review and signature (Proofdelve ForgeOs-ubgx). The verifier's own words are in the evidence below." "$vout" "The branch stands in its worktree unchanged apart from the refresh merge; nothing was merged and nothing was closed. The bead is claimed by the fleet actor."
  fi
  return 0
}

# REFILL THE FORGE SLOTS BETWEEN COMPLETION STEPS (Proofdelve ForgeOs-uwjme, Overseer's
# choice at the 2026-10-15 Regent sitting: shape (a) plus (c)).
#
# THE DEFECT. reap_pass() takes every finished worker through the whole serial
# completion lane -- host verify (~6 min), review (~3 min), merge, post-merge
# verify (~6 min) -- and dispatch_pass() ran only after the lane had DRAINED.
# Measured three times: 93 min of zero dispatch after a hard stop with seven
# carried workers (run 20261015T020202, DEPTH 28-32), the same shape on
# 2026-10-14 18:04-19:3x, and IN-RUN on 20261015T091807, where four Forges
# finished 10:07-10:26 and no dispatch pass ran from 09:56:24 to past 10:44 with
# 0 Forges live and 27 beads ready. The review lane (FLEET_WARDEN_CONC=1) is the
# real ceiling; the Forge slots were idle behind it.
#
# THE REMEDY, AND WHY IT IS THIS SMALL. A refill is dispatch_pass's Forge half
# only, called at the step boundaries of the lane: before each worker is taken in
# hand (which is shape (c): carried workers after a restart no longer hold back
# dispatch) and after each host verifier. So a freed slot refills within one step
# instead of after the whole lane. NOT between a merge and its post-merge
# verifier (the Warden's finding 1, folded): a Forge cut there would build on a main
# not yet verified; see the comment in land(). It is a no-op unless a slot is free, so the tracker is not read on a
# booked pass.
#
# WHAT IT NEVER DOES. It never performs a signed landing: that is completion-lane
# work and stays in the full pass at the foot of each loop. It never dispatches a
# Forge over a bead whose worker holds a signable stored verdict, for the same
# reason the full pass keeps signed_seen. It never runs re-entrantly: land() is
# reached from inside dispatch_pass() through signed_landing(), and a nested
# dispatch would clear the pass-local touch-set scratch under its caller, so a
# refill inside a dispatch is skipped and the dispatch already in progress is the
# refill. And it adds no review capacity: FLEET_WARDEN_CONC is untouched.
#
# THE TOUCH-SET GUARD NOW HOLDS IN-HAND WORKERS (see touch_conflict_with_live).
# Before this, nothing dispatched while a worker was in hand, so the guard never
# had to ask; now a refill runs while one is, and its branch has not landed.
# A MEMORY GATE ON FORGE DISPATCH (Proofdelve ForgeOs-asad6 step 2, Overseer's approval at
# the 2026-10-15 Regent sitting; step 1, FLEET_FORGE_MAX 6 -> 4, was his own hand
# at 328a7184).
#
# THE DEFECT. The governor raised Forge concurrency on clean completions and had
# no memory signal at all. Every Forge runs dotnet build and test in its own
# worktree, and the host verifier runs another; when they overlap, memory spikes.
# systemd-oomd killed the whole fleet unit four times on 2026-10-13/14, and on
# 2026-10-15 06:14 seven Forges plus the verifier left ~4.2G available and swap
# 8/8G full, saved only by the Mayor holding all 60 queued beads by hand.
# Proofdelve ForgeOs-uwjme makes this overlap the NORMAL case -- Forges now build while the
# lane's verifier runs -- which is why the two ship in one sitting.
#
# THE RULE. A launch is refused while
#     MemAvailable - FLEET_MEM_PER_BUILD_MB x (young live Forges + this launch + 1)
# is below FLEET_MEM_FLOOR_MB. A Forge is YOUNG while its worker started less
# than FLEET_MEM_BUILD_WINDOW_S ago: an older one has built, and its memory is
# already inside MemAvailable, so reserving for it again would count it twice.
# The "+ 1" is the host verifier, counted as a slot as the docket asks: at every
# point a dispatch runs, the completion lane's next step is a verifier that has
# not started yet. The defaults are the Mayor's estimates from the 2026-10-15
# near-miss and are tunable in fleet.conf; every refusal and every step-down
# writes its numbers to ceiling.log so they can be.
#
# STEP-DOWN. Concurrency steps down (governor_down, at most once per
# FLEET_MEM_STEPDOWN_EVERY_S) when MemAvailable is below FLEET_MEM_STEPDOWN_MB,
# or when swap is full AND MemAvailable is below the floor. NOT on swap-full
# alone, a deliberate departure from the docket's wording, measured: at the
# sitting, with the fleet halted and nothing building, swap was 9 MB free of 8 GB
# while MemAvailable was 14 GB. Stale pages sit in swap for days on this host, so
# swap-full alone would have pinned concurrency at FLEET_FORGE_MIN permanently.
#
# A REFUSAL IS A WAIT, NOT A STALL. stall_check() is told (pass_mem_held) and
# does not count the pass, because memory comes back without anyone acting and a
# halt would need a person. A host that never frees memory therefore keeps the
# run polling, visibly, once per quiet stretch -- the deferred-merge posture.
#
# FLEET_MEMINFO overrides /proc/meminfo FOR THE HARNESSES ONLY; nothing in this
# fort sets it, and a run reads it from the supervisor's environment.
# A NEEDS A PERSON RECORD WHOSE BEAD IS CLOSED IS ANSWERED (Proofdelve ForgeOs-xu0mj).
#
# THE DEFECT, measured. A worker the fleet marks needs-person keeps that state
# until a person deletes the directory, and live_forges() warned about it on
# every call. A person answers such a record by acting on the BEAD -- landing it
# through a lap, fixing main, closing it -- and nothing carried that answer back
# to the worker. So run 20261015T020202 warned 20 times about Proofdelve ForgeOs-76uob.3,
# closed since 10-14, and the same for 2md9d.1.12 and 2md9d.2.24; on 2026-09-19 it
# was eight records every pass, at least two of them closed days earlier. A
# warning that fires forever is one nobody reads, and NEEDS A PERSON is how the
# fleet asks for help.
#
# THE RULE. Once per pass, a needs-person or orphaned worker whose bead `bd` says
# is CLOSED is settled: the close is the person's answer. It is CLEARED because
# the condition stopped, never silenced while it holds -- a bead that is open, in
# progress, or whose status bd will not give, is left exactly as it was and is
# still said, once per pass. Nothing is removed: the old state line is appended
# to the worker's state-history, and the worktree and branch stay for whoever
# kept them (76uob.3's post-merge worktree is KEPT on purpose).
settle_answered_workers() {
  local d b bs old
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    worker_needs_person "$d" || continue
    b="$(cat "$d/bead" 2>/dev/null || echo "")"
    [ -n "$b" ] || continue
    bs="$(bead_status "$b")"
    [ "$bs" = closed ] || continue
    if [ "$dry" = 1 ]; then
      say "DRY-RUN would settle the worker record of $b: its bead is CLOSED"
      continue
    fi
    old="$(head -1 "$d/state" 2>/dev/null || true)"
    [ -n "$old" ] || old="$(worker_state "$d")|derived|no state file"
    printf '%s  superseded by run %s: bead closed\n' "$old" "$run_id" >> "$d/state-history"
    worker_set_state "$d" settled "its bead $b is CLOSED, so the NEEDS A PERSON this record carried is answered; the old record is in state-history and nothing was removed (Proofdelve ForgeOs-xu0mj)"
    say "$b: worker record SETTLED -- its bead is CLOSED, so the NEEDS A PERSON it carried is answered. The old record is kept in ${d}state-history; its worktree and branch were not touched (Proofdelve ForgeOs-xu0mj)."
  done
  return 0
}

mem_mb() {  # $1 meminfo key -> its value in MiB, or nothing
  awk -v k="$1:" '$1 == k { print int($2 / 1024); exit }' "${FLEET_MEMINFO:-/proc/meminfo}" 2>/dev/null || true
}
young_forges() {  # live Forges whose worker started inside the build window
  local n=0 d age
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    worker_live "$d" || continue
    age="$(( $(date +%s) - $(stat -c %Y "$d/started" 2>/dev/null || echo 0) ))"
    [ "$age" -lt "${FLEET_MEM_BUILD_WINDOW_S:-900}" ] && n=$((n + 1))
  done
  echo "$n"
}
mem_gate_why() {  # silent 0 = launch; 1 and the reason on stdout = wait. Fails CLOSED.
  local avail young need
  avail="$(mem_mb MemAvailable)"
  if [ -z "$avail" ]; then
    echo "MemAvailable could not be read from ${FLEET_MEMINFO:-/proc/meminfo}, so the memory gate cannot clear a launch (failing closed)"; return 1
  fi
  young="$(young_forges)"
  need=$(( ${FLEET_MEM_FLOOR_MB:-8192} + ${FLEET_MEM_PER_BUILD_MB:-2560} * (young + 2) ))
  if [ "$avail" -lt "$need" ]; then
    # ONCE PER PASS (the Warden's finding 2): a refill at every step of the lane asks
    # again, and ceiling.log is the record the numbers are tuned from. This runs
    # in $( ), which can READ pass_mem_held but not set it; the caller sets it.
    [ "${pass_mem_held:-0}" = 1 ] || printf '%s  run=%s  MEMGATE refuse  avail=%sMiB  young=%s  need=%sMiB  (floor %s + %s x (young + launch + verifier))\n' \
      "$(date -Is)" "$run_id" "$avail" "$young" "$need" "${FLEET_MEM_FLOOR_MB:-8192}" "${FLEET_MEM_PER_BUILD_MB:-2560}" >> "$ceiling_log"
    echo "memory: MemAvailable ${avail} MiB is below the ${need} MiB a launch needs (floor ${FLEET_MEM_FLOOR_MB:-8192} + ${FLEET_MEM_PER_BUILD_MB:-2560} MiB x $((young + 2)) builds: $young young Forge(s), this launch, the host verifier)"
    return 1
  fi
  return 0
}
mem_down_epoch=0
mem_stepdown_maybe() {
  local avail sfree stotal now why=""
  now="$(date +%s)"
  [ $((now - mem_down_epoch)) -ge "${FLEET_MEM_STEPDOWN_EVERY_S:-300}" ] || return 0
  avail="$(mem_mb MemAvailable)"; [ -n "$avail" ] || return 0
  sfree="$(mem_mb SwapFree)"; stotal="$(mem_mb SwapTotal)"
  if [ "$avail" -lt "${FLEET_MEM_STEPDOWN_MB:-6144}" ]; then
    why="memory: MemAvailable ${avail} MiB below ${FLEET_MEM_STEPDOWN_MB:-6144} MiB"
  elif [ "${stotal:-0}" -gt 0 ] && [ $(( ${sfree:-0} * 20 )) -lt "$stotal" ] && [ "$avail" -lt "${FLEET_MEM_FLOOR_MB:-8192}" ]; then
    why="memory: swap full (${sfree} of ${stotal} MiB free) and MemAvailable ${avail} MiB below the ${FLEET_MEM_FLOOR_MB:-8192} MiB floor"
  fi
  [ -n "$why" ] || return 0
  mem_down_epoch="$now"
  [ "$forge_conc" -gt "$FLEET_FORGE_MIN" ] || return 0
  governor_down "$why"
}

in_dispatch=0
refill_slots() {  # $1 where in the completion lane, in prose
  [ "$dry" = 1 ] && return 0
  [ "${in_dispatch:-0}" = 1 ] && return 0
  stopping && return 0
  budget_left || return 0
  local live; live="$(live_forges)"
  [ "$live" -lt "$forge_conc" ] || return 0
  say "refill: $((forge_conc - live)) Forge slot(s) free $1 -- dispatching between completion steps (Proofdelve ForgeOs-uwjme)"
  in_dispatch=1
  dispatch_pass refill
  in_dispatch=0
  return 0
}

dispatch_pass() {  # [$1 refill: the Forge half only, from refill_slots() -- Proofdelve ForgeOs-uwjme; signed: phase 1 only, at the top of a pass -- Proofdelve ForgeOs-jfqu4.7]
  local slots n bead sfx wt reason tset tclash held=0 mode="${1:-full}"
  # Proofdelve ForgeOs-a2fx: a stopping run dispatches nothing further. Checked here as
  # well as in the loop because reap_pass runs first and a signal can arrive
  # inside it.
  stopping && return 0
  rm -rf "$state/.touches-dry"; rm -f "$state/.touches-candidate"   # pass-local (Proofdelve ForgeOs-b9mj); cleared on ENTRY, so an early return cannot leave them
  rm -f "$state/.touches-workbench" "$state/.touches-workbench.bead"   # Proofdelve ForgeOs-9srgz: rebuilt by phase 2, never carried from an earlier pass

  # COULD PHASE 1 DO ANYTHING AT ALL? Asked on the FILESYSTEM, before any
  # tracker query, and it is the reason hoisting the signed question above the
  # slot gate costs an ordinary pass nothing. Phase 1 can only act on a bead
  # whose worker carries a stored verdict a landing could rest on; on a normal
  # night no worker does, and this loop is a handful of file reads. Without it,
  # moving the slot gate down would make every fully-booked pass spend a
  # ready_candidates() query it used to skip entirely.
  # THE PREDICATE IS signed_landing_ready()'S OWN, through the same function,
  # so the cheap question and the expensive one cannot drift apart.
  local any_signed=0 vf
  for vf in "$state/workers"/*/verdict; do
    [ -f "$vf" ] || continue
    if stored_verdict_is_signable "$(cat "$vf" 2>/dev/null)"; then any_signed=1; break; fi
  done

  local candidates="" have_candidates=0
  # The query and the reasoning behind it now live in ready_candidates(),
  # because the drain check has to ask the identical question (Proofdelve ForgeOs-czhb
  # acceptance 8).
  if [ "$any_signed" = 1 ]; then
    if ! candidates="$(ready_candidates)"; then
      say "dispatch: REFUSED this pass — the ready queue could not be read (failing closed)"
      pass_note="the ready queue could not be read"
      return 0
    fi
    have_candidates=1
  fi

  # ==========================================================================
  # PHASE 1 — SIGNED LANDINGS, ASKED AHEAD OF THE SLOT GATE (Proofdelve ForgeOs-1kak).
  # ==========================================================================
  # A SIGNED LANDING USES NO FORGE SLOT, SO IT MUST NOT WAIT FOR ONE. The slot
  # gate used to sit above everything: `slots <= 0` returned before any signed
  # question was asked, and `[ n -lt slots ] || break` could end the loop before
  # a signed bead was reached. At forge_conc 1-2 -- the ceiling this fleet
  # actually runs at -- a bead the Overseer had already signed sat behind live
  # Forges needing nothing from them. The Warden, finding 1.6: "worth its
  # own loop ahead of the slot gate".
  #
  # THIS LOOP COSTS NOTHING ON AN ORDINARY BOARD, and the reason is the order
  # of the questions inside it. signed_landing_ready() answers 2 on a single
  # FILE READ when the bead carries no stored ESCALATE, which is every bead on
  # a normal night; nothing below that runs, no bd call is made and no line is
  # printed. Only an escalated bead reaches dispatchable(), the launcher lock or
  # a landing.
  #
  # THE PLACEMENT RELATIVE TO EVERYTHING ELSE IS UNCHANGED and the Warden agreed with
  # it as shipped: still before the co-dispatch guard, whose subject is two
  # Forges writing overlapping code at once, and still before the budget, which
  # gates LAUNCHES and a landing spends none.
  local signed_seen=" " signed_rc2
  for bead in ${candidates:-}; do
    stopping && break
    if [ "$mode" = refill ]; then
      # A REFILL LANDS NOTHING (Proofdelve ForgeOs-uwjme). It asks the same question
      # any_signed asked above, per bead -- signed_landing_ready() returns 2
      # unless the worker's stored verdict is signable, so this is that branch
      # without the stream scan -- and marks the bead seen so phase 2 never
      # dispatches a Forge over a change the Overseer may have signed. The full
      # pass at the foot of the loop lands it.
      if stored_verdict_is_signable "$(cat "$state/workers/${bead##*-}/verdict" 2>/dev/null || echo "")"; then
        signed_seen="$signed_seen$bead "
      fi
      continue
    fi
    # ONE ATTEMPT PER BEAD PER PASS (Proofdelve ForgeOs-jfqu4.7). Phase 1 now runs at the
    # top of the pass AND at its foot; a bead the top already answered (landed,
    # refused, or a merge that failed and returned it) is not tried again at the
    # foot, or a failing landing would spend two returns in one pass. It still
    # joins signed_seen, so phase 2 never dispatches a Forge over it.
    case " ${signed_tried_this_pass:-} " in *" $bead "*) signed_seen="$signed_seen$bead "; continue ;; esac
    sfx="${bead##*-}"
    signed_rc2=0; signed_landing_ready "$bead" "$sfx" || signed_rc2=$?
    if [ "$signed_rc2" -eq 2 ]; then continue; fi
    if [ "$signed_rc2" -eq 1 ] && [ "${signed_superseded_by%% *}" = gate.declined ]; then
      # DECLINED AFTER ESCALATE AND RE-RELEASED WITHOUT A LAP (Proofdelve ForgeOs-0x25g,
      # option (a), the Overseer's choice 2026-10-21). Measured on
      # Proofdelve ForgeOs-2md9d.4.49.2 on 2026-10-20: he Declined, the bead was relabelled
      # fleet-safe, and this branch said "taking the ordinary path" every pass
      # for twenty minutes while nothing moved, because the Decline note is not
      # in the bead and the worker still holds the ESCALATE for this tip. A
      # Decline asks for DIFFERENT WORK, and that work is a lap bead carrying
      # the Decline note as its brief; re-dispatching the same bead gives a
      # Forge nothing new. So the fleet stops here, once: fleet-safe comes off,
      # the bead goes to the Mayor (fleet-escalated, the escalate_labels()
      # route), and a comment says what to file. Nothing is dispatched or
      # landed, and the Overseer's Decline is never read as anything else.
      say "$bead: DECLINED by the Overseer after ESCALATE and NOT landable on the signature ($signed_why) and re-released to the fleet without a lap -- NOT dispatching it; handed to the Mayor to file a lap with the Decline note as its brief (Proofdelve ForgeOs-0x25g)"
      escalate_labels "$bead"
      printf 'fort/scripts/fleet.sh refused to dispatch %s: its newest sign event is %s, after a Warden ESCALATE stored for this tip, and the bead was re-released to the fleet. A Decline asks for different work, so re-dispatching this bead gives a Forge nothing new and the fleet would loop on it (Proofdelve ForgeOs-0x25g, measured on Proofdelve ForgeOs-2md9d.4.49.2). File a LAP bead carrying the Decline note as its brief; do not relabel this one fleet-safe. Labels: %s.\n' \
        "$bead" "$signed_superseded_by" "${label_note:-unknown}" > "$state/logs/declined-$bead.txt" 2>/dev/null || true
      bd -C "$root" comment "$bead" --file "$state/logs/declined-$bead.txt" --actor "$fleet_actor" >/dev/null 2>&1 \
        || warn "$bead: the Decline-guard comment could not be written to the tracker (labels: ${label_note:-unknown})"
      signed_seen="$signed_seen$bead "; signed_tried_this_pass="${signed_tried_this_pass:-} $bead"
      continue
    fi
    if [ "$signed_rc2" -eq 1 ]; then
      # Said once, here, and the bead then takes today's path unchanged in
      # phase 2. It is NOT added to signed_seen: phase 2 owns it entirely.
      say "$bead: escalated and signed but NOT landable on the signature ($signed_why); taking the ordinary path"
      continue
    fi
    wt="$root-worktrees/$sfx"
    if ! reason="$(dispatchable "$bead" signed 2>&1)"; then
      say "skip $bead: $reason"; signed_seen="$signed_seen$bead "; continue
    fi
    # Respect forge.sh's own flock rather than replacing it, exactly as phase 2
    # does: it guards one launcher per worktree, and a landing reads and merges
    # that worktree.
    if [ -e "$wt/.forge.lock" ] && ! flock -n "$wt/.forge.lock" true 2>/dev/null; then
      say "skip $bead: a live launcher already holds $wt"
      [ -n "${pass_note:-}" ] || pass_note="$bead: a live launcher already holds $wt"
      signed_seen="$signed_seen$bead "; continue
    fi
    if [ "$dry" = 1 ]; then
      say "DRY-RUN would LAND $bead on the Overseer's recorded approval of $signed_sha (no Forge, no review launch)"
      pass_reaped=$((${pass_reaped:-0} + 1)); signed_seen="$signed_seen$bead "; continue
    fi
    tset="$state/.touches-candidate"
    touch_set_of "$bead" > "$tset"
    signed_landing "$bead" "$sfx" "$wt" "$tset"
    signed_seen="$signed_seen$bead "
    signed_tried_this_pass="${signed_tried_this_pass:-} $bead"
  done
  # SIGNED MODE ENDS HERE (Proofdelve ForgeOs-jfqu4.7). The loop calls it BEFORE reap_pass
  # so a bead the Overseer has signed lands at the top of every pass instead of
  # waiting for the full pass at the foot of it, which only runs after the whole
  # completion lane (measured 2026-10-21: signed at 10:04, not landed by 11:2x).
  # The full pass at the foot still asks phase 1, for a signature that arrives
  # while the lane is working.
  if [ "$mode" = signed ]; then return 0; fi

  # THE WORKBENCH'S LIVE TOUCH SET, ONCE PER DISPATCH PASS (Proofdelve ForgeOs-9srgz A5,
  # the Overseer's corrected Q2: the fleet keeps running during a sitting). It
  # joins the co-dispatch guard below as one more holder, so a fleet bead whose
  # files overlap the sitting waits and every other bead dispatches. After phase
  # 1, which needs no slot and lands only signed, already-reviewed work.
  workbench_touches_refresh

  # ==========================================================================
  # PHASE 2 — FORGE DISPATCH, which is what actually needs a slot.
  # ==========================================================================
  mem_stepdown_maybe   # Proofdelve ForgeOs-asad6: may lower forge_conc before the slots are counted
  local live; live="$(live_forges)"
  slots=$((forge_conc - live))
  if [ "$slots" -le 0 ]; then
    # The tracker query is not spent here, and on an ordinary fully-booked pass
    # it was never spent at all (the pre-question above answered no).
    # Read only if this pass turns out to be a stall (Proofdelve ForgeOs-dx34.9); on an
    # ordinary waiting pass it is overwritten next pass and never printed.
    # KEPT RATHER THAN OVERWRITTEN since Proofdelve ForgeOs-1kak: phase 1 runs first now
    # and a skip it recorded is the more specific answer to "what diverged".
    [ -n "${pass_note:-}" ] || pass_note="no free Forge slot (ceiling $forge_conc, $live live)"
    return 0
  fi

  if [ "$have_candidates" = 0 ]; then
    if ! candidates="$(ready_candidates)"; then
      say "dispatch: REFUSED this pass — the ready queue could not be read (failing closed)"
      pass_note="the ready queue could not be read"
      return 0
    fi
  fi

  n=0
  for bead in $candidates; do
    stopping && break
    [ "$n" -lt "$slots" ] || break
    # ANSWERED IN PHASE 1 (Proofdelve ForgeOs-1kak): landed, refused by dispatchable(), or
    # held by a live launcher. A bead phase 1 found signed-but-NOT-landable is
    # deliberately absent from this set and takes the ordinary path below.
    case "$signed_seen" in *" $bead "*) continue ;; esac
    if ! reason="$(dispatchable "$bead" 2>&1)"; then
      say "skip $bead: $reason"; continue
    fi
    sfx="${bead##*-}"; wt="$root-worktrees/$sfx"
    # Respect forge.sh's own flock rather than replacing it: it guards one
    # launcher per worktree, which is a different concern from bd's claim
    # guarding one worker per bead. Both are wanted.
    # THE THREE SKIPS BELOW HAPPEN AFTER dispatchable() SAID YES, so each is
    # the dispatcher and the drain check disagreeing about one bead -- the raw
    # material of a stall (Proofdelve ForgeOs-dx34.9). pass_note keeps the first of them
    # so a stall halt can name it.
    if [ -e "$wt/.forge.lock" ] && ! flock -n "$wt/.forge.lock" true 2>/dev/null; then
      say "skip $bead: a live launcher already holds $wt"
      [ -n "${pass_note:-}" ] || pass_note="$bead: a live launcher already holds $wt"
      continue
    fi
    # THE SIGNED QUESTION IS NOT ASKED HERE. It moved to phase 1, above the
    # slot gate (Proofdelve ForgeOs-1kak), because a landing needs no slot; every bead
    # reaching this line has already been asked and is not landable on a
    # signature.
    # THE CO-DISPATCH GUARD (Proofdelve ForgeOs-b9mj; the reasoning is on touch_set_of()
    # above). Asked before the budget and the claim, so a refusal mutates
    # nothing. One skip line per pass for the first refusal and a count for the
    # rest: at concurrency 2 with a serial board every candidate is held on
    # every pass, and twenty lines every FLEET_POLL is a log nobody reads.
    tset="$state/.touches-candidate"
    touch_set_of "$bead" > "$tset"
    if tclash="$(touch_conflict_with_live "$tset")"; then
      case "$tclash" in
        "WORKBENCH "*)
          # Proofdelve ForgeOs-9srgz A5: held by the live Workbench sitting. Ends when the
          # sitting's set stops overlapping or the sitting ends, never by the
          # fleet acting, so the stall detector reads it as waiting.
          pass_workbench_held=$((${pass_workbench_held:-0} + 1))
          [ "$pass_workbench_held" -eq 1 ] && say "skip $bead: HELD -- its touch set overlaps the live Workbench sitting ${tclash#WORKBENCH }; it dispatches once the sitting's files no longer overlap or the sitting ends (Proofdelve ForgeOs-9srgz)"
          [ -n "${pass_note:-}" ] || pass_note="$bead: overlaps the live Workbench sitting ${tclash#WORKBENCH }"
          continue ;;
      esac
      held=$((held + 1))
      # The pass-start live count stands in for "is the holder live": with no
      # Forge live at pass start, every holder is reapable-and-not-live (or a
      # dry-run set of this pass), so this hold is a waiting pass for the stall
      # detector; with one live, stall_check returns before counting anyway
      # (round three; the Warden's round-three note 2 on the earlier wording).
      if [ "$live" -eq 0 ]; then pass_held_unlanded=$((${pass_held_unlanded:-0} + 1)); fi
      [ "$held" -eq 1 ] && say "skip $bead: its touch set overlaps worker $tclash, whose branch has not landed -- waits for it to land or be reaped (Proofdelve ForgeOs-b9mj)"
      [ -n "${pass_note:-}" ] || pass_note="$bead: touch set overlaps worker $tclash"
      continue
    fi
    if [ "$dry" = 1 ]; then
      mkdir -p "$state/.touches-dry"; cp -f "$tset" "$state/.touches-dry/$bead" 2>/dev/null || true   # so the next dry candidate is checked against this one
      say "DRY-RUN would dispatch $bead"; n=$((n + 1)); pass_dispatched=$((${pass_dispatched:-0} + 1)); continue
    fi

    # BUDGET IS ASKED BEFORE ANYTHING IS MUTATED (Proofdelve ForgeOs-feeq). The old code
    # spent AFTER the claim below, so the bead that hit the cap was left claimed
    # and in_progress with no Forge behind it.
    # THE MEMORY GATE (Proofdelve ForgeOs-asad6), after every refusal that mutates nothing
    # and before the claim, so a wait claims nothing. One wait ends the pass's
    # dispatching: memory is a host property, so every later candidate would be
    # refused for the same reason.
    local memwhy
    if ! memwhy="$(mem_gate_why)"; then
      [ "${pass_mem_held:-0}" = 1 ] || say "dispatch waits: $memwhy -- $bead and the rest of the queue wait for memory (Proofdelve ForgeOs-asad6); said once per pass"
      pass_mem_held=1
      [ -n "${pass_note:-}" ] || pass_note="$memwhy"
      break
    fi

    if ! budget_left; then budget_stop "forge dispatch of $bead"; return 0; fi

    # Atomic claim BEFORE launch, then READ IT BACK. A claim that cannot be
    # confirmed is a claim that did not happen, and two dispatcher instances
    # must not be able to double-book one bead.
    if ! bd -C "$root" update "$bead" --claim -a "$forge_actor" --actor "$fleet_actor" >/dev/null 2>&1; then
      say "skip $bead: claim refused (another worker got it first)"
      [ -n "${pass_note:-}" ] || pass_note="$bead: claim refused"
      continue
    fi
    # PARSE THE FIELD, DO NOT GREP THE DOCUMENT. Measured on the first real
    # dispatch, 2026-09-02: "kethra" appeared in BOTH `assignee` AND an entry of
    # `dependencies` on the same bead, so a whole-document grep would confirm a
    # claim that had gone to somebody else as long as any dependency happened to
    # be assigned to the Forge. It was right that time and could be wrong. Note
    # also that bd's `owner` and `assignee` are different fields and `--claim -a
    # X` sets `assignee`: a claimed bead still shows the git user as Owner.
    if [ "$(bead_json "$bead" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw or raw == "null": print(""); sys.exit(0)
d = json.loads(raw)
if isinstance(d, dict) and "data" in d: d = d["data"]
if isinstance(d, list): d = d[0] if d else {}
print(d.get("assignee") or "")
' 2>/dev/null)" != "$forge_actor" ]; then
      say "skip $bead: claim could not be read back — failing closed"
      [ -n "${pass_note:-}" ] || pass_note="$bead: claim could not be read back"
      emit incident "Fleet claimed $bead and could not read the claim back; not dispatched" \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\"}"
      continue
    fi
    spend "forge $bead"

    local wdir="$state/workers/$sfx"
    rm -rf "$wdir"; mkdir -p "$wdir"
    printf '%s\n' "$bead" > "$wdir/bead"; date -Is > "$wdir/started"
    printf '%s\n' "$run_id" > "$wdir/run"
    # THE TOUCH SET IS CACHED HERE, ONCE, AND EVERY LATER PASS READS THE FILE
    # (Proofdelve ForgeOs-b9mj): a live worker's set never costs a bd call.
    cp -f "$tset" "$wdir/touches" 2>/dev/null || { touches_everything; echo; } > "$wdir/touches"
    # shellcheck disable=SC2016  # the single quotes are the point: this body
    # is the CHILD's script and its $1..$4 are the positional arguments passed
    # after the `_`, not this shell's variables. Expanding them here would
    # interpolate the launching shell's state into a detached process.
    # `echo $$ > "$3/pid"` IS THE CHILD'S OWN PID AND MUST BE WRITTEN BY THE
    # CHILD (Proofdelve ForgeOs-l1ef). The parent's $! is nohup's, and setsid forks when it
    # is already a process-group leader — which it is, being a background job —
    # so the parent-visible pid exits within milliseconds and would read as a
    # dead Forge on the very next pass. live_forges() covers the launch window
    # with a grace period instead of trusting a pid that has not appeared yet.
    # A PENDING FIX-FORWARD LAP BRIEFS THE FORGE WITH ITS ITEMS (Proofdelve ForgeOs-6niaz
    # part B); empty otherwise, which forge.sh reads as an ordinary dispatch.
    local ffbrief=""
    if fix_forward_pending "$sfx"; then ffbrief="$(fix_forward_dir "$sfx")/brief"; fi
    # Not $(...): forge_model_route must survive into the emit below.
    local fmodel fmodel_file="$wdir/model"
    forge_model_for "$bead" > "$fmodel_file"; fmodel="$(cat "$fmodel_file")"
    # shellcheck disable=SC2016  # the child's own positional arguments, as above
    nohup setsid bash -c '
      echo $$ > "$3/pid"
      FORGE_FIX_FORWARD_BRIEF="$5" "$1/fort/scripts/forge.sh" "$2" "$4" >"$3/forge.log" 2>&1
      echo $? > "$3/exit"
    ' _ "$root" "$bead" "$wdir" "$fmodel" "$ffbrief" >/dev/null 2>&1 8>&- &
    # CLOSE THE RUN LOCK IN THE CHILD (Proofdelve ForgeOs-l1ef). fd 8 holds this run's
    # flock and every `nohup setsid` child inherits it, so an orphaned Forge
    # outliving its dispatcher kept the lock held and the NEXT run refused with
    # exit 75 — a live fleet locked out by a process that was no longer a fleet.
    say "dispatched $bead -> $wt (forge $fmodel${forge_model_route:+, $forge_model_route}, launch $launches/$FLEET_HARD_STOP)"
    emit bead.claimed "Fleet claimed $bead for $forge_actor and dispatched a Forge" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"model\":\"$fmodel\",\"modelRoute\":\"${forge_model_route:-default}\",\"worktree\":\"$wt\"}"
    n=$((n + 1)); pass_dispatched=$((${pass_dispatched:-0} + 1))
  done
  [ "$held" -gt 1 ] && say "touch-set guard held $held candidate(s) this pass behind live Forges (Proofdelve ForgeOs-b9mj); first named above"
  rm -rf "$state/.touches-dry"; rm -f "$state/.touches-candidate"   # and again on the way out; the entry rm covers the early returns
  return 0
}

# ---------------------------------------------------------------------------
# PORTCULLIS (Proofdelve ForgeOs-9mfw.3)
# ---------------------------------------------------------------------------

# WHAT BRANCH IS $root ON, AND IS ANYTHING THE RECORD WILL CLAIM ABOUT IT FALSE
# (Proofdelve ForgeOs-vikl). land() merged into whatever HEAD happened to be, while the
# merge commit message and the merge event both said "into main"
# unconditionally. The safety property survived either way — the post-merge
# verifier runs in $root whatever branch it is on — so what was at risk is the
# RECORD, which is what standing order 12 protects.
#
# TWO CONDITIONS, AND THEY ARE NOT THE SAME STRENGTH.
#
# 1. THE BRANCH. A detached HEAD or any branch that is not $main_branch is an
#    unconditional refusal at preflight, in assert_on_main_branch(). There is no
#    legitimate state in which this fleet should land work somewhere else, and
#    the check never fires in normal operation, so it costs nothing and can be
#    absolute.
#
#    IT WAS NARROWED WITH THE DIRT HALF ON 2026-09-09 AND RESTORED THE SAME DAY,
#    and the reason is worth more than the fix (Proofdelve ForgeOs-dx34.1 round two, the Warden
#    Marrowassay's blocking finding 1). The safety argument for the narrowing —
#    written on report_landability() below, and quoted there — established that
#    a bead's worktree branches from a COMMIT and not from a working tree, so
#    uncommitted root changes cannot reach it. That is exactly right for the dirt
#    and it is a NON-SEQUITUR for the branch: when HEAD is not $main_branch,
#    "it branches from HEAD" IS the defect. Every bead in the run would be cut
#    off the wrong base, the Warden handed a range carrying foreign commits, and
#    land() would record foreign work under the bead's name.
#
#    WHEN A GUARD TESTS N CONDITIONS AND YOU NARROW IT, THE SAFETY ARGUMENT OWES
#    N ARGUMENTS. landable_why() computes two and the docket carried one. The
#    count was visible in the function the whole time. That is now a fact of this
#    fort: fort/memory/facts/narrowing-a-guard-owes-one-argument-per-condition.md
#
# 2. THE TRACKED DIRT. Narrower than "git status --porcelain is empty", and the
#    narrowing is MEASURED rather than tidy. `.beads/interactions.jsonl` is
#    tracked and is rewritten by essentially every `bd` invocation, and this
#    file makes dozens per pass — so a blanket dirty-refusal would refuse
#    almost every night for a reason that has nothing to do with what the
#    record claims. `fort/events/*.jsonl` is the same shape: append-only record
#    that this run is itself writing while it runs.
#    So RECORD PATHS ARE EXEMPT AND SOURCE PATHS ARE NOT. What the guard is
#    protecting is the sentence "the host verifier was green on main": the
#    verifier scores source, and uncommitted source means it scored something
#    the record does not name. Uncommitted records mean nothing of the kind.
#    If that exemption list ever needs a third entry, that is a signal to look
#    at why, not to extend it quietly.
#
# UNTRACKED FILES ARE NOT A REFUSAL AT ALL. This checkout routinely carries
# tool residue and an unexported bd projection. The count is reported so a
# reader can see what the run stood on.
main_branch="main"
fleet_record_paths='^(\.beads/|fort/events/)'
# tree_branch RETURNS THREE THINGS AND NOT TWO, AND THE THIRD IS NOT DECORATION
# (Proofdelve ForgeOs-dx34.1 round two, acceptance 5, which asked whether the collapse
# mattered rather than leaving it unexamined). `git symbolic-ref --quiet HEAD`
# exits 1 for exactly one reason — HEAD is not a symbolic ref, which is a
# detached HEAD — and 128 for a git-level failure. MEASURED ON THIS HOST,
# 2026-09-09: detached rc=1, no stderr; a directory that is not a repository
# rc=128; a repository whose .git/HEAD is corrupt rc=128; and an UNBORN branch
# rc=0 WITH the branch name, so a fresh repo is not a failure at all and needs no
# case. Collapsing 1 and 128 into one token would have the refusal below tell an
# operator their tree is detached when what happened is that $root is not a
# repository — a different problem with a different fix. Both are unlandable and
# both refuse; only the sentence differs, and the sentence is the whole value of
# a refusal.
#
# THE STATUS IS CAPTURED WITH `|| rc=$?` AND NOT AFTER AN `if`, and the first
# draft of this function got it wrong: `$?` after a COMPLETED `if` with no else
# is 0 whether or not the condition failed, so every detached HEAD read as
# UNKNOWN-HEAD. Case 3 of scripts/landable-harness.sh caught it within a minute
# of being inverted — which is the argument for inverting it, made by the
# instrument rather than in prose.
tree_branch() {
  local br rc=0
  br="$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null)" || rc=$?
  if   [ "$rc" -eq 0 ] && [ -n "$br" ]; then printf '%s' "$br"
  elif [ "$rc" -eq 1 ]; then printf 'DETACHED-HEAD'
  else printf 'UNKNOWN-HEAD'; fi
}
tree_dirty()  {
  git -C "$root" status --porcelain --untracked-files=no 2>/dev/null \
    | sed 's/^...//' | grep -Ev "$fleet_record_paths" || true
}

# WHY IT IS NOT LANDABLE, OR THE EMPTY STRING. One place computes the condition;
# the two callers choose their own severity, which is the whole of Proofdelve ForgeOs-5m7a.
landable_why() {
  local br dirty why=""
  br="$(tree_branch)"
  dirty="$(tree_dirty)"
  [ "$br" != "$main_branch" ] && why="HEAD is on '$br', not '$main_branch'"
  if [ -n "$dirty" ]; then
    why="${why:+$why; }uncommitted tracked SOURCE changes: $(echo "$dirty" | tr '\n' ' ')"
  fi
  printf '%s' "$why"
}

# THE BRANCH HALF: AN UNCONDITIONAL PREFLIGHT REFUSAL (Proofdelve ForgeOs-dx34.1 round two).
# It refuses and it never reports dirt — the two halves are separate functions
# because they are separate in kind, which is the finding this restores.
#
# A DIRTY TREE IS TRANSIENT AND SELF-HEALING: the Overseer commits, and the
# parked merges land on the next pass with nothing re-run (measured three times
# in ninety seconds on run 20260909T125539). A WRONG BRANCH POISONS THE BASE:
# forge.sh:42 cuts each bead's worktree with `git worktree add <wt> -b
# bead/<sfx>` and NO ref, so every bead in the run is cut from whatever HEAD
# names; the pre-review verifier scores that base and goes green on it; the
# Warden is handed a range from main to bead/<sfx> (three-dot since Proofdelve ForgeOs-hifw,
# which does not help here: with main itself wrong, the merge base is wrong too)
# carrying every foreign commit as well as the bead's; and land() would merge
# and RECORD that foreign work under the bead's name. Nothing later in the run can undo a wrong base, and
# no operator action heals it while the run continues. Different in kind, so
# different treatment.
#
# WHY THIS AND NOT AN EXPLICIT BASE FOR THE CUT. Giving forge.sh:42 a named base
# is right regardless and is filed as Proofdelve ForgeOs-7y62; it is NOT a substitute and
# the two are not redundant. An explicit base makes a wrong-branch run BUILD
# correctly; refusing to start is still the honest answer for a run whose
# operator has lost track of the tree. 7y62 also lands in another file and needs
# its own gate-6 pass, and landing both under one review would put two fixes
# under one verdict whose outcomes cannot be told apart.
#
# --dry-run IS EXEMPT, AND IT REPORTS INSTEAD (Proofdelve ForgeOs-geym, the Overseer's
# ruling of 2026-09-09, made deliberately rather than inherited).
#
# THE SYMMETRY IS THE POINT, AND IT IS WRITTEN HERE SO THE NEXT PERSON NARROWING
# EITHER HALF SEES WHAT THE OTHER DOES. Proofdelve ForgeOs-5m7a made exactly this correction
# for the DIRT half: "a dry run neither claims, launches, merges nor closes, and
# it is the path this file offers for TESTING the guards, so refusing it on a
# dirty tree made them untestable exactly when someone was testing them." The
# branch half, restored at preflight one day later, reintroduced on its own side
# the property the dirt half had removed — and divergence between the two halves
# is what produced the bead.
#
# HIS REASONING, WHICH IS 5m7a's APPLIED TO THE OTHER HALF: a dry run dispatches
# nothing, claims nothing and merges nothing, SO A WRONG BRANCH CANNOT POISON A
# BASE THAT IS NEVER CUT. What makes the branch condition worth refusing is that
# a REAL run BUILDS from it. As it stood, the mode this file offers for testing
# the guard refused on the condition the guard checks, which is a loop.
#
# THE ARGUMENT ON THE OTHER SIDE, WEIGHED AND ANSWERED RATHER THAN OMITTED: a
# wrong-branch dry run's REPORT describes a queue that a real run would refuse to
# cut. That is exactly what the dirt half already does — report what a real run
# would have said — and it is answered the same way: the report SAYS SO, in
# terms, at the moment it happens. An operator who is told "a real run would
# refuse here at 64" has not been misled about anything.
#
# THE NAME IS KEPT. It still asserts on every path that builds anything; under
# --dry-run there is nothing to assert about, because nothing is cut.
assert_on_main_branch() {  # preflight. Refuses on a real run; reports under --dry-run.
  local br what; br="$(tree_branch)"
  [ "$br" = "$main_branch" ] && return 0
  case "$br" in
    DETACHED-HEAD)
      what="$root has a DETACHED-HEAD, not '$main_branch'" ;;
    UNKNOWN-HEAD)
      what="the branch of $root could not be determined at all (UNKNOWN-HEAD: git symbolic-ref failed for a reason other than a detached HEAD — $root may not be a git repository, or its HEAD may be unreadable)" ;;
    *)
      what="$root is on '$br', not '$main_branch'" ;;
  esac
  if [ "$dry" = 1 ]; then
    say "WRONG BRANCH, AND THIS DRY RUN PROCEEDS ANYWAY: $what."
    say "  A REAL RUN WOULD REFUSE HERE, at exit 64, and nothing below this line would happen."
    say "  It proceeds because a dry run claims nothing, launches nothing, merges nothing and"
    say "  closes nothing, so no worktree is cut from that base and there is nothing to poison."
    say "  This is the same treatment the dirt half gets, and for the same reason: --dry-run is"
    say "  the path this file offers for TESTING its guards, and a guard that refuses the"
    say "  instrument built to exercise it cannot be exercised (Proofdelve ForgeOs-5m7a, Proofdelve ForgeOs-geym)."
    say "  READ EVERYTHING BELOW WITH THAT IN MIND: the queue this run reports would be cut"
    say "  from '$br' and a real run would never cut it. Run: git -C $root checkout $main_branch"
    return 0
  fi
  echo "fleet.sh: REFUSED — $what." >&2
  echo "  Every bead this run dispatched would be cut from that base, reviewed against a" >&2
  echo "  range that is not its own work, and landed under its own name. Unlike a dirty" >&2
  echo "  tree, which parks merges until it heals, this cannot be repaired after the fact." >&2
  echo "  Run: git -C $root checkout $main_branch" >&2
  echo "  (--dry-run is exempt from this refusal and reports instead: Proofdelve ForgeOs-geym.)" >&2
  exit 64
}

# LANDABILITY IS A MERGE-TIME CONDITION AND NO LONGER A RUN-START ONE
# (Proofdelve ForgeOs-dx34.1, which is requirement 3 of the continuous-fleet spec). THIS
# FUNCTION REPORTS AND NEVER REFUSES. Preflight used to exit 64 here, so a dirty
# root meant the fleet did not start and a night of work simply did not happen.
#
# IT IS THE DIRT HALF THAT MOVED, AND ONLY THE DIRT HALF. The branch half is
# refused at preflight by assert_on_main_branch() above, so by the time this
# function runs, HEAD is on $main_branch. landable_why() still computes both
# because land() calls it too, and a long night is long enough for someone to
# switch the branch under a running fleet — that case defers like any other.
#
# WHAT MAKES THE DIRT NARROWING SAFE, MEASURED 2026-09-08 RATHER THAN ARGUED:
# nothing before a merge reads the repository root's working tree. The
# eligibility query, the claim and the read-back use $root only as bd's working
# directory and read the tracker, not files. Each bead's worktree is created with
# `git worktree add <path> -b bead/<suffix>` and NO ref argument, so it branches
# from HEAD — a commit, not a working tree. The pre-review verifier runs in the
# bead's own worktree, confirmed by every verify payload across six runs. And
# since B1 the POST-merge verifier runs in a fresh worktree at the merged commit,
# which is the hazard that made this narrowing unsafe until it landed: see
# postmerge_verify(). The only working-tree reads at $root are tree_branch() and
# tree_dirty(), which ARE the condition being moved.
#
# THAT PARAGRAPH IS TRUE AND IT COVERS ONE OF THE TWO CONDITIONS. It shipped for
# a day carrying the whole narrowing, and the Warden's blocking finding is
# that "it branches from HEAD" is the DEFENCE for uncommitted changes and the
# DEFECT for a wrong branch: HEAD being a commit says nothing about WHICH commit.
# The claim was never false and checking it only ever confirmed it, which is why
# it passed a docket, a Regent sitting and a Mayor. Left standing here, with its
# scope named, because deleting it would delete the evidence for the half that
# genuinely is safe.
#
# WHAT THE BEHAVIOUR NOW IS, NAMED SO NOBODY HAS TO INFER IT. A dirty root means
# the fleet STARTS, DISPATCHES, BUILDS, VERIFIES AND REVIEWS — and parks every
# merge until the tree is landable. Work accumulates finished-and-unlanded rather
# than not happening. Parking is free in budget terms (a parked bead has already
# spent its launches and the retry spends none: 2 beads, 3 deferrals, 4 launches,
# measured on run 20260909T125540), so the QUEUE is what limits a long dirty
# stretch, not the cap. That is not a defect and it must be VISIBLE, which is
# what report_parked_merges() and --status are for.
#
# LAND() DEFERS, AND DOES NOT halt() (Proofdelve ForgeOs-5m7a, the Warden round two, finding 5).
# The condition is caused by a third party: this fort's own facts ledger records
# that concurrent sessions share this checkout and write to it, so one Mayor edit
# at 03:00 cost a night, a manual recovery, and a bead left claimed after its
# verdict was already recorded. Writing $FLEET_STATE/HALT for that is the
# "a successful night disables the fleet" shape Proofdelve ForgeOs-feeq removed from the
# budget path. halt() stays reserved for states a person must look at.
report_landability() {  # preflight. Says what it found; never exits.
  local why untracked
  why="$(landable_why)"
  if [ -n "$why" ]; then
    say "NOT LANDABLE RIGHT NOW: $why"
    say "  The run STARTS anyway, and that is the intended behaviour rather than a tolerated one."
    say "  Beads will be claimed, built, verified and reviewed; EVERY MERGE IS PARKED until the"
    say "  tree is landable, and a later pass retries the merge alone — not the verifier, and not"
    say "  a second review launch. Commit or stash the source changes and the parked merges"
    say "  land on the next pass without anything being re-run."
    say "  (Only source dirt can be reported here: a wrong branch refuses at preflight, above.)"
  else
    say "$root is landable: HEAD is on $main_branch with no uncommitted tracked source."
  fi
  untracked="$(git -C "$root" ls-files --others --exclude-standard 2>/dev/null | wc -l)"
  if [ "$untracked" -gt 0 ]; then
    say "note: $root carries $untracked untracked file(s); untracked files are never a refusal here."
  fi
  return 0
}

# HOW MANY MERGES ARE WAITING ON A LANDABLE TREE. Stdout is this function's
# return value, so it NEVER logs: one stray diagnostic line here is an arithmetic
# syntax error at the call site, which kills the run and lets the EXIT trap
# record a clean drain for a crash (Proofdelve ForgeOs-0d0i, and live_forges() again in the
# 2026-09-04 sitting).
parked_merges() {
  local n=0 d
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    if [ "$(worker_state "$d")" = deferred-merge ]; then n=$((n + 1)); fi
  done
  echo "$n"
}

# THE ONE LINE THAT MAKES THE NARROWING LEGIBLE. Under a continuous fleet on a
# dirty tree the queue drains into parked merges, which is correct and is not
# something a reader should have to reason out of a worker listing. Said once a
# pass and once on the way out, never per bead: a stream that repeats one fact
# every thirty seconds is a stream nobody reads (fortkit-or2.8).
report_parked_merges() {
  local n why
  n="$(parked_merges)"
  [ "$n" -gt 0 ] || return 0
  why="$(landable_why)"
  say "$n merge(s) PARKED, waiting on a landable tree — ${why:-the tree was unlandable when they were reviewed}"
  say "  Nothing is lost and nothing is stuck: each keeps its verdict and its claim, and a later"
  say "  pass retries the merge alone. fort/scripts/fleet.sh --status names every one of them."
  return 0
}

# The host verifier, run BY THIS FILE, in the tree named. Not --no-emit and not
# under CI: the fort's own verifier emits its own verify.run/pass/fail into the
# record, which is the evidence a reviewer wants and is better than this file
# asserting a result in prose. Docker is reachable here, so this is the FULL
# suite including the MigrationTests no seat's sandbox can execute.
#
# THE POST-MERGE RUN REQUIRES DOCKER BY CONSTRUCTION (Proofdelve ForgeOs-pbkk, fix (b);
# The Warden's finding 5 on Sitting B). warden.sh's HOST VERIFY (ehre)
# cites this file's post-merge verify.pass to the reviewer as docker:true and
# tells her not to reproduce -- but the verifier's own Docker precheck only
# WARNS when the socket is down and continues with the MigrationTests skipped,
# so a Docker-down host would have emitted a green that meant less than the
# brief said. With VERIFY_REQUIRE_DOCKER=1 the precheck FAILS instead and the
# post-merge result is red: a red main, a kept worktree naming Docker in its
# log, and a halt. That is the stated cost, chosen over a false green: the
# fleet stops on a Docker-down host after its first landing rather than
# certifying MigrationTests it never ran. The pre-review runs stay unchanged:
# The Warden reproduces those herself and nothing cites them as docker:true.
run_verifier() {  # $1 tree, $2 output file, [$3 require-docker], [$4 tier], [$5 result file]
  local -a venv=()
  if [ "${3:-}" = require-docker ]; then venv+=(VERIFY_REQUIRE_DOCKER=1); fi
  if [ -n "${4:-}" ]; then venv+=("VERIFY_TIER=$4"); fi
  if [ -n "${5:-}" ]; then venv+=("VERIFY_RESULT_FILE=$5"); fi
  # 8>&- : THE RUN LOCK DOES NOT TRAVEL INTO THE VERIFIER (Regent sitting
  # 2026-11-19, fortkit-ttpk). The verifier's harness fixtures leave `sleep 300`
  # processes behind; each inherited fd 8 and kept fleet.lock held for up to
  # five minutes after the run had ended. The next run was refused at exit 75
  # (09:46 and 12:22 that day) and --status called a finished run LIVE. Measured
  # with fuser: 20 holders, every one a `sleep 300` orphaned from a harness
  # fixture. The Forge dispatch has closed this descriptor since the l1ef fix;
  # the verifier, the review and the scratch reaper now do too.
  ( cd "$1" && env "${venv[@]}" ./fort/scripts/verify.sh ) > "$2" 2>&1 8>&-
}

# ---------------------------------------------------------------------------
# VERIFY ONCE (Proofdelve ForgeOs-s1reg; the Overseer approved the design, with the
# Regent's narrowing, on the bead on 2026-10-19 before any edit).
#
# MEASURED BASIS. The serial finishing line was ~25 min a bead: host verify
# ~9.5, review ~2.5, post-merge verify ~10. prelanding_refresh() already merges
# main into the branch before the host verify (Proofdelve ForgeOs-36b9), so when main has
# not moved by the merge, `git merge --no-ff` produces EXACTLY the tree the host
# verifier scored and the post-merge run re-tests identical bytes. ~900 green
# against ~9 red since September, several environmental, none a code defect a
# verify of the same tree would have missed.
#
# TWO HALVES, BOTH CHOSEN HERE AND NEVER BY A SEAT:
#   the TIER of the host verify, from the bead's own diff (verify_tier_of), and
#   whether the post-merge run may be REUSED (verified_reusable), decided on
#   TREE EQUALITY and on what the run itself recorded, never on the event
#   stream and never on a sha: a sha names a commit, a tree names the bytes.
#
# THE NARROWING, in the Overseer's approval: a branch verify stands in for the
# post-merge run ONLY when it was tier full and Docker ran. warden.sh's HOST
# VERIFY and push-ready.sh both cite a post-merge pass as docker:true (pbkk), so
# a tiered or Docker-less green may never wear that label. A nightly full verify
# on main (fort/scripts/nightly-verify.sh) is the backstop for everything tiers
# skip.
#
# KILL SWITCHES, the Overseer's in fleet.conf, defaulting to on:
#   FLEET_VERIFY_TIERS=off  every host verify is full.
#   FLEET_VERIFY_REUSE=off  every landing runs the post-merge verify.
# AND AN AUTOMATIC ONE (finding 3): no nightly that ran within
# FLEET_NIGHTLY_MAX_AGE_H (36) means both of the above, see nightly_backstop_ok().
#
# THE TIER RULES. Any path not named below, and any doubt at all, is full.
#   full, forced: scripts/verify-impl.sh; the factory and the civilization's
#     tooling (bin/, civ/, templates/, schema/, skills/: charter gate 1, what
#     a change there DOES reaches every fort); fort/ other than fort/handoffs/
#     (every branch carries its handoff there, which is why that one directory
#     is docs and not constitution); .github/.
#   docs:    docs/ and fort/handoffs/ only.
#   server:  src/ and test/ (plus docs): the TypeScript product.
#   harness: scripts/ (plus docs).
#   Both of server/harness at once is full. Manyhalls has no web tier: the
#   word stays in the vocabulary scripts/verify-impl.sh accepts and nothing
#   here produces it.
verify_tier_of() {  # $1 worktree -> exactly one tier word on stdout, "full" on any doubt; never fails
  if [ "${FLEET_VERIFY_TIERS:-on}" = off ]; then printf 'full'; return 0; fi
  local paths p web=0 server=0 harness=0
  # --no-renames (Proofdelve ForgeOs-s1reg finding 5): with rename detection on, a file
  # moved OUT of a forced-full path (Migrations/, *Auth*) is listed only by its
  # new name and tiers by where it went. Without it git lists BOTH paths, so the
  # old one forces full. A refactor that moves many files is exactly that diff.
  paths="$(git -C "$1" diff --no-renames --name-only "$main_branch...HEAD" 2>/dev/null)" || { printf 'full'; return 0; }
  [ -n "$paths" ] || { printf 'full'; return 0; }
  while IFS= read -r p; do
    case "$p" in
      scripts/verify-impl.sh) printf 'full'; return 0 ;;
      bin/*|civ/*|templates/*|schema/*|skills/*) printf 'full'; return 0 ;;
      fort/handoffs/*|docs/*) ;;
      src/*|test/*) server=1 ;;
      scripts/*) harness=1 ;;
      *) printf 'full'; return 0 ;;
    esac
  done <<< "$paths"
  case "$((web + server + harness))" in
    0) printf 'docs' ;;
    1) if [ "$web" = 1 ]; then printf 'web'; elif [ "$server" = 1 ]; then printf 'server'; else printf 'harness'; fi ;;
    *) printf 'full' ;;
  esac
}

# THE NIGHTLY BACKSTOP, ENFORCED (Proofdelve ForgeOs-s1reg finding 3). Tiers skip steps and
# a reused pass re-tests nothing; both are safe only because a full, Docker-
# required verify of main runs every night (nightly-verify.sh). Until now that
# was a sentence in this comment and a timer someone could disable. So: when
# the event stream holds no nightly verify that RAN within
# FLEET_NIGHTLY_MAX_AGE_H hours (default 36: one missed night and some slack),
# every host verify is full and no landing reuses one. A nightly that could
# not run emits ran:false and does not count; a red one halts the fleet anyway.
# The answer is printed as a token, never as an empty string: a python that
# died after printing nothing must read as stale, not as fresh.
nightly_why=""
nightly_backstop_ok() {  # -> 0 a nightly verify ran recently; 1 otherwise (nightly_why says why)
  local maxh="${FLEET_NIGHTLY_MAX_AGE_H:-36}" ans
  case "$maxh" in ''|*[!0-9]*) maxh=36 ;; esac
  nightly_why=""
  ans="$(python3 - "$root/fort/events" "$maxh" <<'PYNIGHTLY' 2>/dev/null
import glob, json, os, sys
from datetime import datetime, timedelta, timezone
d, maxh = sys.argv[1], int(sys.argv[2])
newest = None
for f in sorted(glob.glob(os.path.join(d, "events-*.jsonl")))[-3:]:
    try:
        fh = open(f, encoding="utf-8", errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            if '"nightly"' not in line:
                continue
            try:
                e = json.loads(line)
                p = e.get("payload") or {}
                if p.get("nightly") is not True or p.get("ran") is not True:
                    continue
                ts = datetime.fromisoformat(e["ts"])
            except (ValueError, KeyError, TypeError, AttributeError):
                continue
            if ts.tzinfo is not None and (newest is None or ts > newest):
                newest = ts
if newest is not None and datetime.now(timezone.utc) - newest <= timedelta(hours=maxh):
    print("FRESH")
elif newest is None:
    print("STALE|the event stream holds no nightly verify that ran (last three day files under %s)" % d)
else:
    print("STALE|the newest nightly verify that ran was at %s, more than %dh ago" % (newest.isoformat(), maxh))
PYNIGHTLY
)" || ans=""
  case "$ans" in
    FRESH) return 0 ;;
    STALE\|*) nightly_why="${ans#STALE|}" ;;
    *) nightly_why="the event stream could not be read for a nightly outcome" ;;
  esac
  return 1
}

# THE HOST VERIFY OF A BRANCH. One call site per path that verifies a bead
# before review or before a signed landing; it records what was scored in the
# worker directory, and removes any earlier record FIRST so a run that dies
# leaves nothing a later reuse could mistake for this run's result.
# A GREEN THE REFRESH DID NOT TOUCH IS REUSED, NOT RE-RUN (Proofdelve ForgeOs-gfuc1 A2,
# Regent sitting 2026-11-13, Overseer present). Globals, never stdout (the
# postmerge_verify() rule): refresh_reused_commit / refresh_reuse_why.
#
# WHERE IT APPLIES. Only where a host-verify record survives into a LATER host
# verify of the same worker: today that is a signed landing (signed_landing()
# keeps verified.json across its reset for exactly this), whose refresh from
# main used to re-verify a tree the Warden's host verify had already scored.
# A dispatch wipes the worker directory, so a return lap never reaches here
# with a record and always runs.
#
# THE RULE, and any doubt is a re-run: the record is a pass, clean, HEAD did
# not move, Docker ran, and its tier is the tier this run would use; its commit
# is an ancestor of the worktree's HEAD; the worktree has no tracked change;
# and every path that differs between the verified commit and HEAD is under
# docs/ or fort/handoffs/ -- the docs tier, which no product tier tests. Any
# product, harness or constitution path in that delta, a forced-full path, a
# rename, an unreadable delta: run it.
#
# WHAT IT CLAIMS, AND WHAT IT DOES NOT (Warden finding 1 on gfuc1, round one,
# reproduced: the first text here promised a post-merge run that does not
# always happen). No verifier ran for HEAD's COMMIT. The verify.pass it emits
# says reused:true and ran:false, names the verified commit and tree, says
# sameTree (HEAD's tree is the tree the run scored, or differs under docs/ and
# fort/handoffs/ only), and carries the worktree as "worktree", NEVER as
# "tree": warden.sh's HOST VERIFY and push-ready.sh match a run of a tip by
# payload.tree, so this event can never be cited as a run of HEAD.
# verified.json is left as the run wrote it, and the post-merge verify then
# follows its own tree-equality rule (verified_reusable(), Proofdelve ForgeOs-s1reg):
#   - sameTree:false (a docs delta): the merged tree differs from the scored
#     tree, so the post-merge verify RUNS, and the docs-reading lint steps
#     (mcp-readme-parity, bead-citation-check, mcp-inventory-recount) meet the
#     delta there before the bead is closed;
#   - sameTree:true (a signed landing whose branch was already current): when
#     main has not moved at the merge either, the merged tree IS the scored
#     tree and the post-merge reuse fires too, so that landing runs NO verify.
#     The bytes passed full tier with Docker at review time; the Overseer chose
#     this at the sitting over keeping one run per signed landing (recorded on
#     Proofdelve ForgeOs-gfuc1). The nightly full verify of main is the backstop.
# AND THE GREEN MUST BE RECENT (the Overseer, at the sitting, on Warden
# finding 1: "keep zero-run reuse, but only when the reused green is recent").
# Measured by the record file's own modification time, which verify-impl.sh
# writes when the run ends; the limit is FLEET_REFRESH_REUSE_MAX_AGE_H hours
# (fleet.conf; 12 when unset). He offered "newer than the most recent nightly"
# as the alternative; the file time was chosen as the one that reads reliably
# without parsing the event stream. Older, or unreadable: run it.
refresh_reused_commit=""; refresh_reuse_why=""; refresh_reuse_age_s=""; refresh_reuse_limit_s=""
refresh_reusable() {  # $1 worktree, $2 worker dir, $3 tier this run would use -> 0 reuse, 1 run it
  local wt="$1" f="$2/verified.json" tier="$3" line head vc delta p
  local maxh mt now
  refresh_reused_commit=""; refresh_reuse_why=""; refresh_reuse_age_s=""; refresh_reuse_limit_s=""
  if [ "${FLEET_VERIFY_REUSE:-on}" = off ]; then refresh_reuse_why="FLEET_VERIFY_REUSE=off in fleet.conf"; return 1; fi
  if [ ! -s "$f" ]; then refresh_reuse_why="no earlier host-verify record for this worker"; return 1; fi
  maxh="${FLEET_REFRESH_REUSE_MAX_AGE_H:-12}"
  case "$maxh" in ''|*[!0-9]*) maxh=12 ;; esac
  if [ "$maxh" -eq 0 ]; then refresh_reuse_why="FLEET_REFRESH_REUSE_MAX_AGE_H=0 in fleet.conf turns this reuse off"; return 1; fi
  refresh_reuse_limit_s=$((maxh * 3600))
  mt="$(stat -c %Y "$f" 2>/dev/null)" || mt=""
  now="$(date +%s)"
  case "$mt" in ''|*[!0-9]*) refresh_reuse_why="the earlier host-verify record's age could not be read"; return 1 ;; esac
  refresh_reuse_age_s=$((now - mt))
  if [ "$refresh_reuse_age_s" -lt 0 ]; then
    refresh_reuse_why="the earlier host-verify record's time is in the future (clock or file trouble)"; return 1
  fi
  if [ "$refresh_reuse_age_s" -gt "$refresh_reuse_limit_s" ]; then
    refresh_reuse_why="the earlier green is $((refresh_reuse_age_s / 3600))h old, over the ${maxh}h limit (FLEET_REFRESH_REUSE_MAX_AGE_H)"; return 1
  fi
  line="$(python3 - "$f" "$tier" <<'PYREFRESH' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        d = json.load(fh)
except Exception:
    print("no|the earlier host-verify record could not be parsed")
    sys.exit(0)
why = []
if d.get("result") != "pass":
    why.append("it recorded no pass")
if d.get("tier") != sys.argv[2]:
    why.append("its tier was %s, this run would be %s" % (d.get("tier"), sys.argv[2]))
if d.get("docker") is not True:
    why.append("Docker did not run")
if d.get("dirtyAtStart") is not False or d.get("dirtyAtEnd") is not False:
    why.append("its tree was dirty")
if d.get("headMoved") is not False:
    why.append("HEAD moved during the run")
c = str(d.get("commit") or "")
if len(c) != 40:
    why.append("it names no full commit")
if why:
    print("no|" + "; ".join(why))
else:
    print("yes|%s" % c)
PYREFRESH
)" || line=""
  case "$line" in
    yes\|*) vc="${line#yes|}" ;;
    no\|*)  refresh_reuse_why="${line#no|}"; return 1 ;;
    *)      refresh_reuse_why="the earlier host-verify record could not be read"; return 1 ;;
  esac
  head="$(git -C "$wt" rev-parse --verify --quiet HEAD 2>/dev/null)" || head=""
  if [ -z "$head" ]; then refresh_reuse_why="the worktree's HEAD could not be read"; return 1; fi
  if ! git -C "$wt" merge-base --is-ancestor "$vc" "$head" 2>/dev/null; then
    refresh_reuse_why="the verified commit ${vc:0:12} is not an ancestor of HEAD ${head:0:12}"; return 1
  fi
  if [ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null || echo unreadable)" ]; then
    refresh_reuse_why="the worktree has tracked changes"; return 1
  fi
  delta="$(git -C "$wt" diff --no-renames --name-only "$vc" "$head" 2>/dev/null)" || { refresh_reuse_why="the delta since ${vc:0:12} could not be read"; return 1; }
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      fort/handoffs/*|docs/*) ;;
      *) refresh_reuse_why="the delta since the verified commit ${vc:0:12} changes $p, outside docs/ and fort/handoffs/"; return 1 ;;
    esac
  done <<< "$delta"
  refresh_reused_commit="$vc"
  return 0
}

host_verify() {  # $1 worktree, $2 output file, $3 worker dir -> the verifier's exit status
  local tier; tier="$(verify_tier_of "$1")"
  if [ "$tier" != full ] && ! nightly_backstop_ok; then
    say "  host verifier tier: full, not $tier: no nightly backstop -- $nightly_why (Proofdelve ForgeOs-s1reg finding 3)"
    tier=full
  else
    say "  host verifier tier: $tier (chosen from the diff; Proofdelve ForgeOs-s1reg)"
  fi
  # Proofdelve ForgeOs-gfuc1 A2: decided BEFORE the old record is removed, because the old
  # record is the evidence. A refusal is narrated so a morning reader sees why
  # the run happened; no refusal is silent.
  if refresh_reusable "$1" "$3" "$tier"; then
    local hv_head hv_bead hv_vtree
    hv_head="$(git -C "$1" rev-parse HEAD 2>/dev/null || echo "")"
    hv_bead="$(cat "$3/bead" 2>/dev/null || echo "")"
    hv_vtree="$(git -C "$1" rev-parse --verify --quiet "$refresh_reused_commit^{tree}" 2>/dev/null || echo "")"
    local hv_htree hv_same=false hv_what
    hv_htree="$(git -C "$1" rev-parse --verify --quiet "HEAD^{tree}" 2>/dev/null || echo "")"
    if [ -n "$hv_htree" ] && [ "$hv_htree" = "$hv_vtree" ]; then
      hv_same=true; hv_what="it scored exactly this tree"
    else
      hv_what="this tree differs from the one it scored only under docs/ and fort/handoffs/"
    fi
    say "  host verifier REUSED: the green $tier run at ${refresh_reused_commit:0:12} stands for ${hv_head:0:12}; $hv_what (Proofdelve ForgeOs-gfuc1)"
    emit verify.pass "Host verify REUSED for ${hv_bead:-a worker} at ${hv_head}: the green $tier run at ${refresh_reused_commit} stands, because $hv_what (Proofdelve ForgeOs-gfuc1); that run finished ${refresh_reuse_age_s}s ago, inside the ${refresh_reuse_limit_s}s limit. No verifier ran for this commit; the post-merge verify follows its own tree-equality rule (Proofdelve ForgeOs-s1reg)" \
      -a "$fleet_actor" -s fleet -t "${hv_bead:-}" -p "{\"run\":\"$run_id\",\"commit\":\"$hv_head\",\"worktree\":\"$1\",\"ran\":false,\"reused\":true,\"refreshReuse\":true,\"sameTree\":$hv_same,\"verifiedAgeS\":${refresh_reuse_age_s:-null},\"ageLimitS\":${refresh_reuse_limit_s:-null},\"verifiedCommit\":\"$refresh_reused_commit\",\"verifiedTree\":\"$hv_vtree\",\"tier\":\"$tier\"}"
    printf 'host verify REUSED: %s run at %s stands for %s (Proofdelve ForgeOs-gfuc1)\n' "$tier" "$refresh_reused_commit" "$hv_head" > "$2"
    return 0
  fi
  if [ -s "$3/verified.json" ]; then say "  host verifier runs: $refresh_reuse_why (Proofdelve ForgeOs-gfuc1)"; fi
  rm -f "$3/verified.json" 2>/dev/null || true
  run_verifier "$1" "$2" "" "$tier" "$3/verified.json"
}

# MAY THIS LANDING REUSE ITS BRANCH VERIFY? Globals, never stdout (the
# postmerge_verify() rule). Every refusal names its reason, so a morning reader
# sees why a post-merge run happened rather than inferring it.
reused_tree=""; reused_commit=""; reuse_why=""
verified_reusable() {  # $1 worker dir, $2 merged sha -> 0 reuse, 1 run it (reuse_why says why)
  local f="$1/verified.json" mtree line
  reused_tree=""; reused_commit=""; reuse_why=""
  if [ "${FLEET_VERIFY_REUSE:-on}" = off ]; then reuse_why="FLEET_VERIFY_REUSE=off in fleet.conf"; return 1; fi
  if ! nightly_backstop_ok; then reuse_why="no nightly backstop: $nightly_why (Proofdelve ForgeOs-s1reg finding 3)"; return 1; fi
  if [ ! -s "$f" ]; then reuse_why="no host-verify result was recorded for this worker"; return 1; fi
  mtree="$(git -C "$root" rev-parse --verify --quiet "$2^{tree}" 2>/dev/null)" || mtree=""
  if [ -z "$mtree" ]; then reuse_why="the merged commit's tree could not be resolved"; return 1; fi
  line="$(python3 - "$f" "$mtree" <<'PYREUSE' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        d = json.load(fh)
except Exception:
    print("no|the host-verify result could not be parsed")
    sys.exit(0)
why = []
if d.get("result") != "pass":
    why.append("it recorded no pass")
if d.get("tier") != "full":
    why.append("its tier was %s, not full" % d.get("tier"))
if d.get("docker") is not True:
    why.append("Docker did not run, so MigrationTests did not")
if d.get("dirtyAtStart") is not False or d.get("dirtyAtEnd") is not False:
    why.append("its tree was dirty")
if d.get("headMoved") is not False:
    why.append("HEAD moved during the run")
if d.get("skippedSteps"):
    why.append("it skipped steps (%s)" % ",".join(str(s) for s in d["skippedSteps"]))
tree = str(d.get("tree") or "")
if tree != sys.argv[2]:
    why.append("the merged tree %s is not the verified tree %s (main moved)" % (sys.argv[2][:12], tree[:12] or "none"))
if why:
    print("no|" + "; ".join(why))
else:
    print("yes|%s|%s" % (tree, d.get("commit") or ""))
PYREUSE
)" || line=""
  case "$line" in
    yes\|*) reused_tree="$(cut -d'|' -f2 <<< "$line")"; reused_commit="$(cut -d'|' -f3 <<< "$line")"; return 0 ;;
    no\|*)  reuse_why="${line#no|}"; return 1 ;;
    *)      reuse_why="the host-verify result could not be read"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# THE POST-MERGE VERIFICATION RUNS IN A FRESH WORKTREE AT THE MERGED COMMIT
# (Proofdelve ForgeOs-dx34.1, option (d) — proposed by Emrith Cairnwright of Manyhalls,
# measured by the Mayor before it was adopted).
#
# WHY THE ROOT IS THE WRONG PLACE TO RUN IT. This used to run in $root and
# scored the working directory as it existed on disk, so "main is green after
# landing X" was a statement about A DIRECTORY AT A MOMENT rather than about a
# commit. Concurrent sessions share this checkout and write to it (this fort's
# own facts ledger), so anyone's uncommitted edit during the build was scored
# as the merged work — and the failure mode is not a defer but halt(), which
# disables every LATER run until a person removes a file by hand. The natural
# accident was a half-written spec stopping the fleet with the record blaming
# the merged work. That is what made narrowing the landability check unsafe,
# and it is what this closes: after this, nothing between the merge and the end
# of the verification reads the root's working tree at all. It is Proofdelve ForgeOs-afdr
# — the verifier scores the tree it lives in — applied one level up.
#
# MEASURED BEFORE ADOPTING IT, which was Emrith's own condition (recorded on the
# bead, 2026-09-08): worktree creation 0.07 s, a COLD verify inside it 37 s
# against the 39-40 s the warm root it replaces was measured at across five
# runs. A cold worktree is not a cold cache: NuGet and npm live under $HOME and
# are shared, so a fresh worktree pays for recompilation only, never for
# re-download. The real cost is DISK — about 245 MB of build artifacts per
# merge, in a fort already carrying a measured 11 GB of unreaped worktrees
# (Proofdelve ForgeOs-mpaw). Hence the removal rule below, which is not garnish: it is the
# difference between a seven-second cost and a 1.5 GB/day one.
#
# THE RULE, AND IT IS FOUR OUTCOMES RATHER THAN TWO. "It ran and main is red"
# and "it never ran" are different facts and get different events and different
# severities; a control that cannot tell them apart sends someone to debug the
# wrong artifact.
#   green        main is green AT THAT COMMIT. The worktree is REMOVED.
#   refused      the verifier ran and measured nothing about the code (Docker
#                down, a refusal, a harness refusing: verify_unrunnable()).
#                Halts like red, but the record says UNRUNNABLE and why.
#   red          main is red at that commit. The worktree is KEPT and named:
#                that is exactly when a person wants the tree and exactly when
#                an automatic cleanup would delete the evidence. Halts.
#   unrunnable   the worktree could not be created or the commit could not be
#                checked out, so NOTHING WAS MEASURED. Writes no halt file —
#                the next run is free to try — but does stop this run, because
#                every later merge in it would build on an unverified $into.
#   interrupted  the verification was killed by the operator's signal. Not a
#                verdict about main in either direction. The tree is kept.
#
# IT REPORTS THROUGH GLOBALS AND NOT THROUGH STDOUT, deliberately. A helper
# whose stdout is its return value can never log, and one stray diagnostic line
# in one is what let a crashed run record a clean drain (Proofdelve ForgeOs-0d0i, and
# again on live_forges() in the 2026-09-04 sitting). Two facts have to come back
# from here, so neither of them travels on stdout.
# >>> verify_unrunnable: KEEP BYTE-IDENTICAL in fort/scripts/fleet.sh and fort/scripts/nightly-verify.sh (nightly-verify-harness.sh compares them)
# UNRUNNABLE IS NOT RED (Proofdelve ForgeOs-s1reg finding 4, the Warden's review of docket
# Proofdelve ForgeOs-x7ojh). A nonzero exit from the verifier used to read as "main is
# red" whatever produced it, so on 2026-10-16 the fleet sat ~9 h behind a halt
# file that blamed the code for a harness that had REFUSED to run (exit 3).
# Three shapes measure nothing, or almost nothing, about the code:
#   * Docker down under VERIFY_REQUIRE_DOCKER=1: docker-precheck fails and no
#     later step runs, MigrationTests included.
#   * the verifier refusing before any step ran (verify.sh / verify-impl.sh's
#     own exits 2, 3, 70, 78: usage, the step list, the missing shim, the
#     wrong tree). No "step FAILED" line exists in that output.
#   * a step that exited 3, the harness convention for REFUSES: the
#     instrument could not load what it tests. That is EITHER a broken
#     instrument OR the code it extracts having changed shape (the Warden's finding
#     2 on docket Proofdelve ForgeOs-zw3q5), so the words below say "read the step log"
#     and never "not the code".
# Everything else is a verdict. This classifies; it does not decide. The fleet
# still halts on a refused post-merge run (the Overseer's call, 2026-10-20) and
# only the words change; the nightly writes no halt for one.
unrunnable_why=""
verify_unrunnable() {  # $1 verifier output, $2 its exit status -> 0 unrunnable (unrunnable_why says why), 1 a verdict
  unrunnable_why=""
  [ "$2" -ne 0 ] || return 1
  local failed
  failed="$(grep -m1 -oE "^verify: step '[A-Za-z0-9_.-]+' FAILED \(exit [0-9]+\)" "$1" 2>/dev/null)" || failed=""
  if [ -z "$failed" ]; then
    case "$2" in
      2|3|70|78)
        unrunnable_why="the verifier exited $2 with no step FAILED line (a refusal before the steps, or an abort such as a syntax error, possibly after some passed); read the log. Its first line: $(grep -m1 -E '^verify(\.sh)?: ' "$1" 2>/dev/null | cut -c1-200)"
        return 0 ;;
    esac
    return 1
  fi
  case "$failed" in
    "verify: step 'docker-precheck' FAILED"*)
      unrunnable_why="Docker was unreachable and this run requires it (VERIFY_REQUIRE_DOCKER=1): the verifier stopped at docker-precheck, so MigrationTests and every later step never ran"
      return 0 ;;
    *"(exit 3)")
      unrunnable_why="${failed#verify: }: exit 3 is the harness REFUSES convention, so the instrument could not load what it tests; that is a broken instrument OR code that changed shape under it, so read the step log before deciding which"
      return 0 ;;
  esac
  return 1
}
# <<< verify_unrunnable
postmerge_result=""   # green | red | refused | unrunnable | interrupted
postmerge_tree=""     # the worktree being KEPT, or empty when none is
postmerge_verify() {  # $1 bead, $2 merged sha, $3 output file
  local bead="$1" sha="$2" vout="$3"
  # The run id is in the name so two runs cannot collide, and so a kept tree
  # names the run that left it to a morning reader.
  local wt="$root-worktrees/postmerge-$run_id-${bead##*-}"
  postmerge_result=""; postmerge_tree=""
  if [ -z "$sha" ]; then
    printf 'post-merge verification did not start: the merged commit could not be resolved\n' > "$vout"
    postmerge_result=unrunnable; return 0
  fi
  # NEVER CLOBBER. A path that is already there may be a KEPT tree from an
  # earlier red verification, which is evidence.
  if [ -e "$wt" ]; then
    printf 'post-merge verification did not start: %s already exists and was not clobbered\n' "$wt" > "$vout"
    postmerge_result=unrunnable; postmerge_tree="$wt"; return 0
  fi
  if ! git -C "$root" worktree add --detach "$wt" "$sha" > "$vout" 2>&1; then
    postmerge_result=unrunnable
    # Residue from a half-made worktree is named rather than tidied away: this
    # branch does not know what went wrong, so it does not delete anything.
    if [ -e "$wt" ]; then postmerge_tree="$wt"; fi
    return 0
  fi
  postmerge_tree="$wt"
  local vrc=0
  run_verifier "$wt" "$vout" require-docker || vrc=$?   # Proofdelve ForgeOs-pbkk: this green is cited as docker:true, so it must mean Docker
  if [ "$vrc" -eq 0 ]; then
    if git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1; then postmerge_tree=""; fi
    postmerge_result=green; return 0
  fi
  # ASKED BEFORE THE EXIT CODE IS INTERPRETED. Ctrl-C reaches the whole
  # foreground process group, so the verifier dies with a status that means
  # "the operator stopped me" and not "main is red" — and reading that as a
  # verdict would halt the fleet over a build nobody was allowed to finish.
  if signalled; then postmerge_result=interrupted
  elif verify_unrunnable "$vout" "$vrc"; then postmerge_result=refused
  else postmerge_result=red; fi
  return 0
}

# ONE PLACE DEFERS A MERGE (Proofdelve ForgeOs-usz6). Before this, both defer branches said
# some version of "will retry next pass" and NEITHER WAS RETRIED: reap_pass
# skipped any worker carrying the old `done` marker, which was written near the
# top of the reap iteration — before the verifier, before the review, and
# therefore before land() was ever reached. So a reviewed, approved, verifier-
# green bead whose merge was deferred had no path back, in this run or any
# later one, and waited for a person.
#
# WHY IT WAS NOT A ONE-LINER, in this bead's own words: making the promise true
# needs a retry that re-attempts land() WITHOUT re-running the verifier and
# WITHOUT spending a second Warden launch, and re-reaping the worker naively
# would do both — and spending a review launch twice on one bead is worse than
# the defect. Proofdelve ForgeOs-w7u5's resume point is what makes that expressible: a
# `deferred-merge` worker resumes at `land`, not at `verify`.
#
# WHAT IS PERSISTED, AND WHY IN THE WORKER DIRECTORY. The verdict, and a COPY
# of the Warden record. The record's own home is $warden_root/<sfx>.log.record
# (under ~/.local/share since Proofdelve ForgeOs-nv0j; /tmp before, which a reboot
# removed), and the next review of any bead with the same suffix overwrites it; a retry that ran a day later would then file a
# follow-up bead carrying somebody else's review, or none.
#
# NO DEFERRAL THRESHOLD, DELIBERATELY. A tree that stays unlandable for a week
# means a person is needed, but "a week" is a dial, dials live in fleet.conf,
# and fleet.conf is the Overseer's. The count and the reason are carried in the
# worker's state instead, so `--status` and the leftovers report show a bead
# that has deferred forty times without anyone having had to pick a number.
# Proofdelve ForgeOs-dx34.15. A defer reason keyed for the seen-list: one line per
# reason however many lines the reason has, and no reason text in the list to
# be mistaken for a record. reason_seen() answers "has this worker deferred on
# this reason at any earlier pass", which is a different question from "is it
# the reason it deferred on LAST pass" -- see the back-out in reap_pass().
reason_key() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }
reason_seen() {  # $1 key, $2 seen-list (one key per line) -> 0 if present
  local line
  while IFS= read -r line; do [ "$line" = "$1" ] && return 0; done <<< "$2"
  return 1
}

defer_merge() {  # $1 worker dir, $2 bead, $3 verdict, $4 why
  local wdir="$1" bead="$2" verdict="$3" why="$4" cnt last
  cnt="$(cat "$wdir/defers" 2>/dev/null || echo 0)"
  case "$cnt" in ''|*[!0-9]*) cnt=0 ;; esac
  cnt=$((cnt + 1))
  printf '%s\n' "$cnt" > "$wdir/defers" 2>/dev/null || true
  worker_set_state "$wdir" deferred-merge "deferral $cnt, verdict $verdict: $why"
  say "$bead: NOT MERGED this pass — $why"
  say "  Deferral $cnt. The verdict $verdict stands and the bead keeps its claim; nothing was merged and nothing was closed."
  say "  A later pass retries THE MERGE ALONE: not the verifier, and not a second review launch."
  # ONE EVENT PER DISTINCT REASON, NOT ONE PER PASS. Under a continuous fleet a
  # dirty tree defers every pass, and a stream that repeats one fact every
  # thirty seconds is a stream nobody reads — the fortkit-or2.8 outcome, where
  # an instrument trains its fort to ignore it. The narrative above still says
  # it every time; the durable record says it when it changes.
  last="$(cat "$wdir/defer-reason" 2>/dev/null || echo "")"
  if [ "$last" != "$why" ]; then
    printf '%s\n' "$why" > "$wdir/defer-reason" 2>/dev/null || true
    # EVERY DISTINCT REASON THIS WORKER HAS EVER DEFERRED ON, appended when it
    # changes (Proofdelve ForgeOs-dx34.15). reap_pass reads the list to tell a reason that
    # is NEW from one that is merely different from last pass's.
    printf '%s\n' "$(reason_key "$why")" >> "$wdir/defer-reasons-seen" 2>/dev/null || true
    emit fleet.deferred "Fleet did not merge $bead ($why). Deferral $cnt. The review verdict $verdict stands, the bead is still claimed, and nothing was merged or closed. This is NOT a halt and NOT a stranding: a later pass retries the merge alone." \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"$verdict\",\"deferred\":true,\"deferrals\":$cnt}"
  fi
}

# THE VERDICT VOCABULARY, AS TWO NAMED PROPERTIES IN ONE PLACE (Proofdelve ForgeOs-j3kp
# finding 1, as corrected by the Warden 2026-09-10). Three tokens may be
# acted on and two of those file a follow-up, and until now each site spelled its
# own list: the fresh-review dispatch knew three, the deferred-merge resume knew
# two, and MERGE-PARENT-OPEN fell into the resume's catch-all and was escalated
# to a person as if its verdict were corrupt. A token added later now inherits
# correct behaviour from both predicates instead of inheriting a third site to
# remember.
#
# TWO PREDICATES AND NOT ONE, AND THE DIFFERENCE IS THE WHOLE REPAIR. The
# obvious factoring -- a single predicate, "does this verdict file a follow-up",
# keyed at both sites -- reproduces this very finding on APPROVE, which IS
# landable and files NO follow-up: every deferred plain APPROVE would fall into
# the needs-person arm under a message asserting there is no usable stored
# verdict. Rarer than the bug it replaces (APPROVE-WITH-FINDINGS is 64 of 67
# verdicts in this fort, so APPROVE is at most three) and exactly the same bug,
# introduced by the fix for it. The two sites ask different questions, so they
# get different functions.
verdict_is_landable() {  # may the fleet act on this stored verdict at all?
  # OVERSEER-SIGNED IS THE FLEET'S OWN TOKEN (Proofdelve ForgeOs-ubgx; the reasoning is on
  # signed_landing_ready() below). No Warden emits it. It is here so a signed
  # landing that DEFERS at the merge retries through reap_pass's land arm like
  # any other, and lands and closes like a plain APPROVE. It files no follow-up.
  case "$1" in APPROVE|APPROVE-WITH-FINDINGS|MERGE-PARENT-OPEN|OVERSEER-SIGNED) return 0 ;; *) return 1 ;; esac
}
verdict_files_followup() {  # does this verdict need the stored Warden record?
  case "$1" in APPROVE-WITH-FINDINGS|MERGE-PARENT-OPEN) return 0 ;; *) return 1 ;; esac
}

# ONE PLACE FILES A FOLLOW-UP, FOR BOTH VERDICTS THAT PRODUCE ONE (Proofdelve ForgeOs-j3kp).
# APPROVE-WITH-FINDINGS and MERGE-PARENT-OPEN differ in what happens to the
# PARENT and not at all in how the findings are carried, so the carrying is one
# function. Two copies of a bd-create-plus-check block would drift, and the
# control that makes the factoring safe is the end-to-end GREEN case: the two
# pre-existing tokens must behave identically across this change, which
# scripts/fleet-e2e-harness.sh measures by running them.
#
# THE FINDINGS ARE NOT PARSED OUT OF THE VERDICT, AND THAT IS A REFUSAL RATHER
# THAN A SHORTCUT. The Warden states her findings in prose. Any mechanism that read the
# review BODY for phrases — "should not be closed", "criterion N unmet" — would
# work for the sentence she happened to write and fail on the next one, silently,
# in the direction of merging and closing. That is Proofdelve ForgeOs-8zb7's pinned-spelling
# class raised to protocol level. Nobody teaches fleet.sh English: the token is
# the interface, which is the whole reason Proofdelve ForgeOs-j3kp splits a token instead of
# teaching this file to read.
#
# FINDING TIERS ARE NOT PROSE, AND THAT IS WHY READING THEM IS NOT THE REFUSAL
# ABOVE (Proofdelve ForgeOs-6niaz part A, Regent sitting 2026-11-11, the Overseer
# present; approval recorded on the bead). The Warden now puts her numbered
# findings between a line 'FINDINGS:' and a line 'END FINDINGS', and opens each
# non-blocking one with exactly one tag: [record] (no action), [polish] (tests,
# CSS, comment or harness tidy, no behaviour change, a few lines) or [bead]
# (real follow-up work). The tag is a token in a fixed position, like the
# verdict token; nothing here reads a sentence. tier_findings() splits the
# section into items by their leading number and sorts each by the FIRST tag in
# its opening line. Every miss fails toward MORE filing, never less:
#   - an item with no tag, or a tag this file does not know, counts as [bead];
#   - no FINDINGS section, or one with no numbered item, is UNPARSED, and the
#     caller files the whole-review triage bead exactly as before this change.
# The measured need (Proofdelve ForgeOs-yi221, 11-10/11): about a third of findings were
# record-only and about half were one-to-three line beads, each a full fleet
# lap on the one Warden slot.
#
# Outputs, none on stdout (Proofdelve ForgeOs-0d0i): tier_items/tier_bead/tier_polish/
# tier_record are counts; $2/bead.txt and $2/polish.txt carry the items'
# text, each capped at 2000 characters. Returns 0 when parsed, 1 when not.
tier_items=0; tier_bead=0; tier_polish=0; tier_record=0
tier_findings() {  # $1 record file, $2 output dir
  tier_items=0; tier_bead=0; tier_polish=0; tier_record=0
  local counts
  rm -rf "$2"; mkdir -p "$2" || return 1
  : > "$2/bead.txt"; : > "$2/polish.txt"
  counts="$(awk -v od="$2" '
    function flush() {
      if (cur == "") return
      if (length(cur) > 2000) cur = substr(cur, 1, 2000) "...[cut at 2000 characters; the whole review is on the parent]"
      if (tag == "polish") { print cur "\n" > (od "/polish.txt"); np++ }
      else if (tag == "record") { nr++ }
      else { print cur "\n" > (od "/bead.txt"); nb++ }
      cur = ""; tag = ""
    }
    { t = $0; gsub(/[*#_ \t]/, "", t) }
    !inf && !done && t ~ /^FINDINGS:?$/ { inf = 1; next }
    inf && (t ~ /^ENDFINDINGS:?$/ || $0 ~ /^VERDICT-LINE:/) { flush(); inf = 0; done = 1; next }
    inf {
      # AT THE LEFT MARGIN, AND FOLLOWED BY WHITESPACE (the Warden, 6niaz review
      # finding 1): an indented numbered sub-list or a wrapped line that begins
      # "3.5 seconds" is part of the finding above it, never a new one.
      if ($0 ~ /^[*_]*[0-9]+[.)][*_]*([ \t]|$)/) {
        flush(); items++; cur = $0; tag = ""
        head = substr($0, 1, 160)
        if (match(head, /\[(record|polish|bead)\]/)) tag = substr(head, RSTART + 1, RLENGTH - 2)
      } else if (cur != "") cur = cur "\n" $0
    }
    END { flush(); printf "%d %d %d %d\n", items, nb, np, nr }
  ' "$1" 2>/dev/null)" || return 1
  read -r tier_items tier_bead tier_polish tier_record <<< "$counts" || return 1
  [ "${tier_items:-0}" -gt 0 ] 2>/dev/null || { tier_items=0; return 1; }
  return 0
}

# Two return values, neither on stdout (Proofdelve ForgeOs-0d0i).
followup_bead=""     # the filed bead id, or empty when it could not be filed
followup_body=""     # the path to the body, which the caller posts on failure
followup_ids=""      # every bead filed (Proofdelve ForgeOs-6niaz: a [bead] follow-up and a polish-batch bead can both be filed)
followup_none=0      # 1 when a tiered review held only [record] findings, so nothing was owed a bead
file_followup() {  # $1 bead, $2 verdict, $3 record file, $4 and $5 two lines of why, [$6 the outcome token: tiers apply to APPROVE-WITH-FINDINGS only]
  local bead="$1" verdict="$2" record="$3" why1="$4" why2="$5"
  followup_bead=""; followup_body="$state/logs/followup-$bead.txt"; followup_ids=""; followup_none=0
  # TIERED FILING (Proofdelve ForgeOs-6niaz part A). APPROVE-WITH-FINDINGS only, by the
  # Overseer's ruling at the sitting (refinement a): MERGE-PARENT-OPEN keeps its
  # whole-review follow-up, because that bead is what carries the unmet
  # criterion, and a tag on a finding says nothing about a criterion.
  if [ "${6:-}" = APPROVE-WITH-FINDINGS ] && [ -s "$record" ] && tier_findings "$record" "$state/logs/tiers-$bead"; then
    file_followup_tiered "$bead" "$verdict" "$record" "" "$state/logs/tiers-$bead"
    return 0
  fi
  # THE GROUP'S STATUS IS TESTED, AND SO IS WHAT IT WROTE (the Warden,
  # correction C2 to the sitting-three docket). Two failures live on this line
  # and only one of them was ever visible.
  #
  # THE VISIBLE ONE: the group is a bare compound command, so it takes `cat`'s
  # status, and `set -euo pipefail` is unsuspended here -- an unreadable record
  # KILLED THE RUN inside the one function written to survive a failure, after
  # the merge had already landed, and the EXIT trap then called it a clean drain.
  #
  # WHY `|| true` ALONE IS THE WRONG REMEDY AND IS WORSE THAN THE BUG: the header
  # printfs have already succeeded by the time `cat` fails, so the body exists
  # and is NON-EMPTY with the verbatim section missing. `bd create` then
  # SUCCEEDS, followup_bead is set, the Proofdelve ForgeOs-bzyk merge-but-do-not-close
  # branch is skipped, no incident is emitted, and the parent CLOSES on
  # APPROVE-WITH-FINDINGS WITH THE FINDINGS GONE. That is the review-dies-unread
  # failure this path exists to end, reached through an empty file rather than
  # through prose.
  #
  # AND A SIZE TEST ALONE DOES NOT CLOSE IT EITHER, for the same reason: those
  # headers make the body non-empty whether or not the record was ever appended.
  # So the condition is the GROUP'S OWN STATUS *and* the size -- the status
  # catches a truncated body, the size catches a redirection that wrote nothing
  # at all -- and wrapping both in an `if` is what keeps `set -e` from acting on
  # either. An unfileable follow-up stays survivable and LOUD: followup_bead is
  # left empty, which routes the caller to the bzyk branch that posts the body on
  # the bead, applies fleet-escalated and emits an incident.
  # POINT, DO NOT COPY (2026-11-07). The verdict is already posted whole on
  # $bead as the Warden's own comment; copying it here doubled every review in
  # the tracker (1,276 triage beads, 10 MB of the 64.2 MB export that froze the
  # Overseer's Keep board on 11-07). The body now names where the verdict is and
  # quotes only its verdict line. The record must still be readable and
  # non-empty, so an unreadable record keeps the loud bzyk path described above.
  if [ -s "$record" ] && {
    printf 'Filed automatically by fort/scripts/fleet.sh when %s was merged and\n' "$bead"
    printf '%s\n' "$why1"
    printf '%s\n\n' "$why2"
    printf 'The Warden%s verdict is posted whole, unparsed, as her comment on %s.\n' "'s" "$bead"
    printf 'Read it with: bd show %s --json --include-comments\n' "$bead"
    printf 'Deciding which findings deserve beads is the Mayor%s work, which is the\n' "'s"
    printf 'entire reason this bead exists.\n\n'
    printf 'Verdict line: %s\n' "$(grep -m1 'VERDICT:' "$record" | cut -c1-300)"
  } > "$followup_body" && [ -s "$followup_body" ]; then
    followup_bead="$(bd -C "$root" create --title="Triage the findings from the fleet-merged review of $bead ($verdict)" \
        --description="$(cat "$followup_body")" --type=task --priority=2 --actor "$fleet_actor" 2>/dev/null \
        | sed -n 's/.*Created issue: \([A-Za-z0-9_.-]*\) .*/\1/p' | head -1)" || followup_bead=""
  else
    followup_bead=""
    say "$bead: the follow-up body could not be built from $record, so NO follow-up bead was filed"
  fi
  followup_ids="$followup_bead"
  # RETURN 0, NEVER THE TEST (the Warden, covenant-4.5 review of sitting
  # one, blocking finding). This line used to be a non-emptiness TEST on the
  # follow-up id, so an unfiled follow-up made the function return 1 — and the
  # retired spelling is paraphrased rather than quoted here, because a literal
  # in a comment fails a zero-tolerance grep exactly like a live instruction.
  # Both callers invoke this function
  # BARE IN AN `if` BODY, where `set -euo pipefail` is unsuspended, so the run
  # DIED on exactly the Proofdelve ForgeOs-bzyk path this function exists to survive: the
  # merge had already landed, its record was never written, and the EXIT trap
  # then called it a clean drain. The callers read $followup_bead directly and
  # never needed a status; the function has no business signalling through one.
  return 0
}

# THE TIERED HALF OF file_followup() (Proofdelve ForgeOs-6niaz part A). Up to two beads:
# ONE follow-up for every [bead] item (untagged ones included), and ONE bead
# labelled polish-batch, deliberately NOT fleet-safe, for every [polish] item,
# so the Mayor's polish lane (a Workbench sitting, or a batch she cuts) picks
# them up together instead of the fleet running a lap per line. [record] items
# file nothing: the review stays on the parent as the Warden's own comment.
# THE CLOSE IS STILL GATED ON EVERY FILING THE REVIEW OWED: if either create
# fails, followup_bead is left empty and the caller takes the loud bzyk branch
# (merged, not closed, escalated, incident), exactly as an unfiled whole-review
# follow-up does. A review of only [record] items owes nothing, and says so
# through followup_none so the caller can close with a clear record.
file_followup_tiered() {  # $1 bead, $2 verdict, $3 record, $4 one optional note line, $5 the tier dir
  local bead="$1" verdict="$2" record="$3" note="$4" td="$5" id ok=1 vline
  vline="$(grep -m1 'VERDICT:' "$record" | cut -c1-300)"
  followup_body="$state/logs/followup-$bead.txt"
  {
    printf 'Filed automatically by fort/scripts/fleet.sh from the Warden%s tiered %s review of %s (run %s).\n' "'s" "$verdict" "$bead" "${run_id:-}"
    [ -n "$note" ] && printf '%s\n' "$note"
    printf '\nThe Warden tiered her findings (Proofdelve ForgeOs-6niaz): %s [bead], %s [polish], %s [record].\n' "$tier_bead" "$tier_polish" "$tier_record"
    printf 'Her verdict is posted whole on %s as her own comment; read it with: bd show %s --json --include-comments\n' "$bead" "$bead"
    printf 'Verdict line: %s\n' "$vline"
  } > "$followup_body" 2>/dev/null || ok=0
  if [ "$tier_bead" -gt 0 ] && [ "$ok" = 1 ]; then
    id=""
    if { cat "$followup_body"; printf '\nThe [bead] findings, as she wrote them (an untagged finding counts as [bead]):\n\n'; cat "$td/bead.txt"; } > "$td/bead-body.txt" 2>/dev/null; then
      id="$(bd -C "$root" create --title="Follow-up from the fleet-merged review of $bead ($verdict): $tier_bead finding(s) tagged [bead]" \
          --description="$(cat "$td/bead-body.txt")" --type=task --priority=2 --actor "$fleet_actor" 2>/dev/null \
          | sed -n 's/.*Created issue: \([A-Za-z0-9_.-]*\) .*/\1/p' | head -1)" || id=""
    fi
    if [ -n "$id" ]; then followup_ids="$id"; else ok=0; say "$bead: the [bead] follow-up could NOT be filed"; fi
  fi
  if [ "$tier_polish" -gt 0 ] && [ "$ok" = 1 ]; then
    id=""
    if { cat "$followup_body"; printf '\nThe [polish] items, as she wrote them. No behaviour change, a few lines each; batch them in one Workbench sitting or one Forge bead:\n\n'; cat "$td/polish.txt"; } > "$td/polish-body.txt" 2>/dev/null; then
      id="$(bd -C "$root" create --title="Polish from the fleet-merged review of $bead: $tier_polish [polish] item(s)" \
          --description="$(cat "$td/polish-body.txt")" --type=task --priority=3 --labels polish-batch --actor "$fleet_actor" 2>/dev/null \
          | sed -n 's/.*Created issue: \([A-Za-z0-9_.-]*\) .*/\1/p' | head -1)" || id=""
    fi
    if [ -n "$id" ]; then followup_ids="${followup_ids:+$followup_ids }$id"; else ok=0; say "$bead: the polish-batch bead could NOT be filed"; fi
  fi
  if [ "$ok" != 1 ]; then
    followup_bead=""; return 0
  fi
  if [ -z "$followup_ids" ]; then
    followup_none=1; followup_bead=""
  else
    followup_bead="${followup_ids%% *}"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# THE FORGE MODEL FOR ONE BEAD (docket 2026-11-13 item B, Overseer present:
# "include that optional layout bead reroute"). A bead labelled forge-strong
# is dispatched on FLEET_FORGE_MODEL_STRONG; every other bead, and every bead
# when that setting is empty or absent, on FLEET_FORGE_MODEL. The Mayor labels
# web layout beads forge-strong at filing (fort/seats/mayor.md). A tracker that
# cannot answer sends the bead to the default model and says so: the choice of
# model is cost and quality, never a gate, so the cheaper failure is right.
# Prints the model; the route is left in forge_model_route for bead.claimed, so
# the record says which rule chose it: "strong" (labelled), "default" (not
# labelled, or no strong model configured) or "unknown" (the tracker could not
# say, so the default model ran; Warden finding 7 on gfuc1).
forge_model_route=""
forge_model_for() {  # $1 bead -> prints one model; never fails
  local rc=0
  forge_model_route=default
  if [ -n "${FLEET_FORGE_MODEL_STRONG:-}" ]; then
    bead_has_label "$1" forge-strong || rc=$?
    case "$rc" in
      0) forge_model_route=strong; printf '%s' "$FLEET_FORGE_MODEL_STRONG"; return 0 ;;
      2) forge_model_route=unknown
         say "  $1: the tracker could not say whether it is forge-strong; dispatching on the default model" >&2 ;;
    esac
  fi
  printf '%s' "$FLEET_FORGE_MODEL"
}

# FIX-FORWARD: ONE BOUNDED LAP ON THE SAME BRANCH (Proofdelve ForgeOs-6niaz part B, Regent
# sitting 2026-11-11, the Overseer present; approval and the refinements are
# recorded on the bead).
#
# THE TOKEN MEANS: the work is done and approvable, and the [polish] findings
# The Warden listed are cheaper to fix in this branch now than as a follow-up
# bead later (11-10/11: follow-ups of one to three lines each cost a full fleet
# lap on the one Warden slot, and spawned follow-ups of their own). So:
#   1. the bead goes back to the queue with its branch and worktree intact, and
#      its next dispatch is a Forge lap briefed with ONLY those items;
#   2. host verify as for any dispatch;
#   3. a light Warden re-check of only those items against the lap's diff
#      (warden.sh reads WARDEN_FIX_FORWARD_BASE and _ITEMS); she widens to a
#      full review only if the lap touched more;
#   4. then whatever that re-check returns is acted on as any verdict is:
#      merge-and-close, the signature hold for sign-to-land, ESCALATE, return.
# AT MOST ONE LAP PER BEAD. The bound is the bead label fix-forward-used (the
# durable record) and the lap's own base file (the fleet's record); either one
# present makes a later FIX-FORWARD read as APPROVE-WITH-FINDINGS, whose tiered
# filing puts the [polish] items in a polish-batch bead. Also read as
# APPROVE-WITH-FINDINGS, each with its reason said: a Workbench session branch
# (its findings go back to the Workbench and never to a Forge, and a hand-back
# for polish would cost a whole sitting), a review with no [polish] items in a
# FINDINGS section (nothing to bound the lap to), no reviewed tip to diff the lap
# from, and a bd that will not say what labels the bead carries.
# THE LAP SPENDS NO RETURN (refinement b): it is not a failure. A red verifier
# on the lap is, and charges a return as any red verifier does.
# GATES ARE UNCHANGED: nothing here merges. A gated or sign-to-land bead reaches
# land() only through the re-check's own verdict, and land() holds it there.
bead_has_label() {  # $1 bead, $2 label -> 0 yes, 1 no, 2 bd could not say
  local j
  j="$(bead_json "$1")" || return 2
  printf '%s' "$j" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
try:
    d = json.loads(raw)
except Exception:
    sys.exit(2)
if isinstance(d, dict) and "data" in d:
    d = d["data"]
if isinstance(d, list):
    d = d[0] if d else None
if not isinstance(d, dict) or not d.get("id"):
    sys.exit(2)
labels = d.get("labels") or []
if not isinstance(labels, list):
    sys.exit(2)
sys.exit(0 if sys.argv[1] in labels else 1)
' "$2"
}
fix_forward_dir() { printf '%s' "$state/fix-forward/$1"; }   # $1 sfx
# A lap is PENDING from the moment it is queued until its re-check records a
# verdict. While pending, the dispatch briefs the Forge with the items and the
# review briefs the Warden for the light re-check.
fix_forward_pending() {  # $1 sfx
  local d; d="$(fix_forward_dir "$1")"
  [ -s "$d/base" ] && [ -s "$d/brief" ] && [ ! -e "$d/rechecked" ]
}
fix_forward_recheck_done() {  # $1 sfx: called when a review records a verdict
  local d; d="$(fix_forward_dir "$1")"
  if fix_forward_pending "$1"; then date -Is > "$d/rechecked" 2>/dev/null || true; fi
  return 0
}
fix_forward() {  # $1 bead, $2 worktree, $3 record, $4 the tip the review was launched on
  local bead="$1" record="$3" tip="${4:-}" sfx="${1##*-}" why="" d hl=0 wrc=0 polish_n
  d="$(fix_forward_dir "$sfx")"
  if worker_review_only "$state/workers/$sfx"; then
    why="it is a Workbench session branch, whose findings go back to the Workbench and never to a Forge"
  else
    bead_has_label "$bead" fix-forward-used || hl=$?
    if [ "$hl" -eq 0 ] || [ -e "$d/base" ]; then
      why="this bead has already had its one FIX-FORWARD lap"
    elif [ "$hl" -ne 1 ]; then
      why="bd would not say whether this bead has had its FIX-FORWARD lap, and a second lap is the one thing the bound forbids"
    elif [ -z "$tip" ]; then
      why="the reviewed tip is unknown, so the lap would have no diff to be re-checked against"
    elif ! tier_findings "$record" "$d.items" || [ "$tier_polish" -eq 0 ]; then
      why="the review lists no [polish] item in a FINDINGS section, so there is nothing to bound the lap to"
    fi
  fi
  if [ -n "$why" ]; then
    say "$bead: FIX-FORWARD read as APPROVE-WITH-FINDINGS: $why (Proofdelve ForgeOs-6niaz)"
    emit progress "Fleet read the FIX-FORWARD verdict on $bead as APPROVE-WITH-FINDINGS: $why. Its [polish] items go to a polish-batch bead." \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"FIX-FORWARD\",\"read_as\":\"APPROVE-WITH-FINDINGS\"}"
    land "$bead" APPROVE-WITH-FINDINGS "$record" "$tip"
    return 0
  fi
  # A BEAD CLOSED UNDER THE REVIEW STAYS CLOSED (the Warden, 6niaz review finding 5;
  # the Proofdelve ForgeOs-x2lv rule return_to_ready() already keeps): no lap, no write.
  if [ "$(bead_status "$bead")" = closed ]; then
    worker_set_state "$state/workers/$sfx" settled "FIX-FORWARD: the bead was closed before its lap could be queued; no write made, it stays closed"
    say "$bead: FIX-FORWARD, but the bead was closed before its lap could be queued -- no write made, it stays closed"
    return 0
  fi
  polish_n="$tier_polish"
  mkdir -p "$d" 2>/dev/null || true
  # THE [bead] ITEMS OF A FIX-FORWARD REVIEW ARE FILED NOW. The re-check reviews
  # only the [polish] items, so a [bead] finding left for later would never be
  # filed by anything. A failed filing does not stop the lap: the review is on
  # the bead whole, and the failure is an incident a person reads.
  if [ "$tier_bead" -gt 0 ]; then
    local saved_polish="$tier_polish"
    tier_polish=0; followup_ids=""
    file_followup_tiered "$bead" FIX-FORWARD "$record" \
      "Found on a FIX-FORWARD review: its [polish] items get one lap on the branch, and these [bead] items do not." "$d.items"
    tier_polish="$saved_polish"
    if [ -n "$followup_ids" ]; then
      bd -C "$root" dep add "$followup_ids" "$bead" --type discovered-from --actor "$fleet_actor" >/dev/null 2>&1 || true
      say "$bead: the FIX-FORWARD review's [bead] findings are filed as $followup_ids"
      emit bead.filed "Fleet filed $followup_ids to carry the [bead] findings of the FIX-FORWARD review of $bead" \
        -a "$fleet_actor" -s fleet -t "$followup_ids" -p "{\"run\":\"$run_id\",\"parent\":\"$bead\"}"
    else
      emit incident "Fleet could not file the [bead] findings of the FIX-FORWARD review of $bead; the review is on the bead whole and the lap proceeds" \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"FIX-FORWARD\"}"
    fi
  fi
  if ! {
      printf 'FIX-FORWARD LAP (1 of at most 1) -- %s\n\n' "$(date -Is)"
      printf 'The Warden approved the work on %s and asked for ONE bounded lap on the same branch\n' "$bead"
      printf '(bead/%s, the same worktree) to fix ONLY these %s [polish] item(s), as she wrote them:\n\n' "$sfx" "$polish_n"
      cat "$d.items/polish.txt"
      printf 'Lap base (the tip she reviewed): %s\n' "$tip"
      printf 'After the lap: host verify, then a light re-check of only these items against the lap diff, then merge.\n'
      printf 'This lap spends no return. A second FIX-FORWARD on this bead is read as APPROVE-WITH-FINDINGS (Proofdelve ForgeOs-6niaz).\n'
    } > "$d/brief.tmp" 2>/dev/null || [ ! -s "$d/brief.tmp" ]; then
    rm -f "$d/brief.tmp"
    say "$bead: the FIX-FORWARD brief could not be written; read as APPROVE-WITH-FINDINGS instead"
    land "$bead" APPROVE-WITH-FINDINGS "$record" "$tip"
    return 0
  fi
  mv -f "$d/brief.tmp" "$d/brief"; printf '%s\n' "$tip" > "$d/base"
  bd -C "$root" comment "$bead" --file "$d/brief" --actor "$fleet_actor" >/dev/null 2>&1 || true
  bd -C "$root" update "$bead" --status open --assignee "" --add-label fix-forward-used --actor "$fleet_actor" >/dev/null 2>&1 || wrc=$?
  if [ "$wrc" -ne 0 ]; then
    # The bound is safe either way: the base file above makes a second
    # FIX-FORWARD read as APPROVE-WITH-FINDINGS even without the label. What
    # failed is the return, so say exactly that, as return_to_ready() does.
    worker_set_state "$state/workers/$sfx" needs-person "FIX-FORWARD: the bd write that returns $bead for its lap FAILED (exit $wrc); it is still claimed"
    say "$bead: FIX-FORWARD lap could NOT be queued: the bd write failed (exit $wrc); the bead is still claimed"
    emit incident "Fleet could not queue the FIX-FORWARD lap for $bead: the bd write failed (exit $wrc). It is still claimed and in_progress; its state does NOT match this stream." \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"FIX-FORWARD\",\"bd_exit\":$wrc}"
    return 0
  fi
  worker_set_state "$state/workers/$sfx" settled "FIX-FORWARD: queued for one bounded lap on bead/$sfx ($polish_n [polish] item(s)); no return spent"
  say "$bead: FIX-FORWARD -- queued for ONE bounded lap on the same branch ($polish_n [polish] item(s)); no return spent, fix-forward-used applied"
  emit fleet.returned "$bead queued for its one FIX-FORWARD lap ($polish_n [polish] item(s)) on bead/$sfx; no return spent" \
    -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"fix_forward\":true,\"items\":$polish_n,\"base\":\"$tip\",\"escalated\":false}"
}

# ---------------------------------------------------------------------------
# THE SIGNATURE HOLD IS A PROPERTY OF THE BEAD, NOT OF ONE VERDICT TOKEN
# (Proofdelve ForgeOs-vee4w, Regent sitting 2026-10-05, Overseer present).
#
# Until this, the only thing that kept a gate-1 change from landing without the
# Overseer was the Warden choosing ESCALATE. Four verdicts merge
# (verdict_is_landable), and on 2026-09-22 Proofdelve ForgeOs-etmwb, gate 1 class B,
# merged unsigned on MERGE-PARENT-OPEN while the review PROSE said it needed his
# signature. Prose is not a gate; the fleet reads the token.
#
# So the Mayor marks the bead, before dispatch, with the label sign-to-land:
# every gate-1 class B, C or D bead, and any other bead whose landing he must
# sign. land() is the single place every merge goes through (a fresh review, a
# deferred-merge resume, a signed landing), so the hold lives at its top. A
# sign-to-land bead reaching land() on any Warden verdict is HELD: fleet-safe
# off, human on, open and unclaimed, the verdict stored as ESCALATE, which is
# exactly the state the ESCALATE arm leaves. His Approve on the Keep then pins
# the tip and the ordinary signed landing (Proofdelve ForgeOs-ubgx) lands it. Only
# OVERSEER-SIGNED, the fleet's own token for his recorded approval, passes.
#
# The Warden's own token is kept beside it (warden-verdict, warden-record), so
# the signed landing still does what she decided: APPROVE-WITH-FINDINGS files
# its follow-up and MERGE-PARENT-OPEN leaves the parent open. Without that, a
# signature would silently turn her "do not close" into a close.
#
# FAIL CLOSED: when bd will not say what labels the bead carries, nothing
# merges. The merge is deferred and the next pass asks again.
#
# The label is the interface, and it is read off the record rather than out of
# the review body, for the reason file_followup() gives: nobody teaches this
# file English.
#
# ROUND TWO (the Warden's finding 1; the Overseer chose a positive marker): a label
# that only says "hold" cannot tell class A from never classified, so one missed
# label repeated etmwb exactly. Now the Mayor's classification is positive:
# lands-on-review says the Warden's verdict may land it. A bead carrying NEITHER
# is unclassified, dispatchable() refuses it, and land() holds it and adds
# sign-to-land, so his Approve can land it as any held bead.
sign_label() { printf '%s' 'sign-to-land'; }
# gated_range_why <sfx>: prints why bead/<sfx>'s range touches a gated surface,
# or nothing (Proofdelve ForgeOs-6niaz belt 1). Conservative by construction: a path list
# can only widen what waits for the Overseer, never narrow it, and the gate is
# still defined by what a change DOES, so the Warden's own ESCALATE stands too.
# A diff that cannot be listed is reported as gated.
gated_range_why() {  # $1 sfx
  local paths p
  if ! paths="$(git -C "$root" diff --name-only "$main_branch...bead/$1" 2>/dev/null)"; then
    printf 'the range main...bead/%s could not be listed' "$1"; return 0
  fi
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      bin/*|civ/*|templates/*|schema/*|skills/*)
        printf '%s is gate-1 surface (the factory and the civilization tooling)' "$p"; return 0 ;;
      fort/charter.md|fort/seats/*|fort/profiles/*|fort/scripts/*|fort/systemd/*|fort/airlock/operations.json|.claude/*|scripts/airlock-*|scripts/verify-impl.sh)
        printf '%s is the fort constitution (gate 6)' "$p"; return 0 ;;
    esac
  done <<< "$paths"
  return 0
}
# stacked_held_why <sfx>: names another Workbench sitting HELD for the
# Overseer's signature whose branch shares unlanded commits with bead/<sfx>, or
# prints nothing (Proofdelve ForgeOs-6niaz belt 2). HELD means not closed and carrying
# `human` OR sign-to-land: the ESCALATE route adds `human` and never
# sign-to-land, so a sitting the Warden escalated -- the ordinary held sitting
# -- carries only `human` (the Warden, round two, finding 1). SHARED is asked of EVERY
# merge base (--all): once both branches have merged main in, as Workbench rule
# 4 requires, git can report a criss-cross where the single base it prints is a
# main commit while the held sitting's own commit is the other one (round two,
# finding 2, measured by her probe). Returns 2
# when bd will not answer, so the caller can defer rather than guess. It does
# not ask which of the two branches the shared commits were written on: a
# range that shares them with a held sitting waits either way, which is the
# conservative reading of "never land held commits on an unsigned review".
stacked_held_why() {  # $1 sfx
  local raw ids id osfx mb
  raw="$(bd -C "$root" list --label workbench --status open,in_progress,blocked,deferred --json --limit 0 2>/dev/null)" || return 2
  # THE LABELS CONTRACT FAILS CLOSED (the Warden, 6niaz round three, finding 5; the
  # Overseer chose the fold at the sitting). "Held" is read from each row's
  # labels, so output that does not parse, or a row with no labels key, is a bd
  # that will not say: return 2 and the caller defers, never "nothing held".
  # Measured 2026-11-11: bd 1.1.2 list --json carries labels on all 22 rows.
  ids="$(printf '%s' "$raw" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "[]")
except Exception:
    sys.exit(3)
if isinstance(d, dict) and "data" in d:
    d = d["data"]
if not isinstance(d, list):
    sys.exit(3)
held = set(sys.argv[1:])
for b in d:
    if not isinstance(b, dict) or not b.get("id") or not isinstance(b.get("labels"), list):
        sys.exit(3)
    if held.intersection(b["labels"]):
        print(b["id"])
' human "$(sign_label)" 2>/dev/null)" || return 2
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    osfx="${id##*-}"
    [ "$osfx" = "$1" ] && continue
    git -C "$root" rev-parse --verify --quiet "bead/$osfx" >/dev/null || continue
    while IFS= read -r mb; do
      [ -n "$mb" ] || continue
      if ! git -C "$root" merge-base --is-ancestor "$mb" "$main_branch" 2>/dev/null; then
        printf '%s (bead/%s)' "$id" "$osfx"; return 0
      fi
    done < <(git -C "$root" merge-base --all "bead/$osfx" "bead/$1" 2>/dev/null || true)
  done <<< "$ids"
  return 0
}
review_label() { printf '%s' 'lands-on-review'; }
needs_signature() {  # $1 bead -> 0 sign-to-land, 1 lands-on-review only, 3 unclassified, 2 bd could not say
  local j
  j="$(bead_json "$1")" || return 2
  printf '%s' "$j" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw or raw == "null":
    sys.exit(2)
try:
    d = json.loads(raw)
except Exception:
    sys.exit(2)
if isinstance(d, dict) and "data" in d:
    d = d["data"]
if isinstance(d, list):
    d = d[0] if d else None
if not isinstance(d, dict) or not d.get("id"):
    sys.exit(2)
labels = d.get("labels") or []
if not isinstance(labels, list):
    sys.exit(2)
if sys.argv[1] in labels:
    sys.exit(0)
if sys.argv[2] in labels:
    sys.exit(1)
sys.exit(3)
' "$(sign_label)" "$(review_label)"
}
hold_for_signature() {  # $1 bead, $2 the Warden verdict, $3 record file, $4 worker dir, $5 reviewed tip (may be empty), $6 "unclassified", "gated" or empty, $7 the gated reason
  local bead="$1" wv="$2" record="$3" wdir="$4" rtip="${5:-}" why_held hrc=0 crc=0
  why_held="it carries $(sign_label)"
  [ "${6:-}" = unclassified ] && why_held="it is UNCLASSIFIED (neither $(sign_label) nor $(review_label))"
  [ "${6:-}" = gated ] && why_held="it is a Workbench range that touches a gated path (${7:-unnamed}), so it waits for the Overseer's signature whatever the review token says (Proofdelve ForgeOs-6niaz belt 1)"
  bd -C "$root" update "$bead" --remove-label fleet-safe --add-label human \
     --status open --assignee "$(overseer_assignee)" --actor "$fleet_actor" >/dev/null 2>&1 || hrc=$?
  # AN UNCLASSIFIED BEAD IS CLASSIFIED ON THE WAY PAST, conservatively, so that
  # his Approve can land it: dispatchable() refuses an unclassified bead, and
  # the signed landing goes through dispatchable(). A failure here leaves it
  # held and refused, which is visible ("skip ...: unclassified"), never unsafe.
  if { [ "${6:-}" = unclassified ] || [ "${6:-}" = gated ]; } && [ "$hrc" -eq 0 ]; then
    bd -C "$root" update "$bead" --add-label "$(sign_label)" --actor "$fleet_actor" >/dev/null 2>&1 || crc=$?
    [ "$crc" -eq 0 ] || why_held="$why_held, and adding $(sign_label) FAILED (exit $crc), so the Mayor must classify it before his Approve can land it"
  fi
  if [ -d "$wdir" ]; then
    printf '%s\n' "ESCALATE" > "$wdir/verdict" 2>/dev/null || true
    printf '%s\n' "$wv" > "$wdir/warden-verdict" 2>/dev/null || true
    if [ -s "$record" ] && [ "$record" != "$wdir/warden-record" ]; then
      cp -f "$record" "$wdir/warden-record" 2>/dev/null || true
    fi
    if [ -n "$rtip" ]; then printf '%s\n' "$rtip" > "$wdir/reviewed-sha" 2>/dev/null || true; fi
  fi
  if [ "$hrc" -ne 0 ]; then
    worker_set_state "$wdir" needs-person "the Warden returned $wv and $why_held, so it was HELD for the Overseer's signature, and the bd write that removes fleet-safe and applies human FAILED (exit $hrc): nothing merged, but the bead may still be claimed and fleet-safe, so it is NOT on his queue"
    say "$bead: $wv, and $why_held -- HELD, NOT merged; the bd write that puts it on the Overseer's queue FAILED (exit $hrc)"
    emit incident "Fleet held $bead for the Overseer's signature ($why_held; the Warden returned $wv) and could NOT remove fleet-safe and apply human: the bd write failed (exit $hrc). Nothing was merged. The bead is NOT on his queue." \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"ESCALATE\",\"wardenVerdict\":\"$wv\",\"hold\":\"$(sign_label)\",\"bd_exit\":$hrc,\"returned\":false}"
    return 0
  fi
  ask_overseer "$bead" sign "the Warden returned $wv and $why_held; Approve on the Keep lands the reviewed change as a signed landing" \
    || say "$bead: the ASK line could not be posted; it is assigned to $(overseer_assignee) without one"
  worker_set_state "$wdir" settled "the Warden returned $wv and $why_held: HELD for the Overseer's signature, assigned to him with an ASK line, nothing merged"
  say "$bead: $wv, and $why_held -- HELD for the Overseer's signature, NOT merged (Proofdelve ForgeOs-vee4w)"
  emit fleet.returned "$bead held for the Overseer's signature: $why_held and the Warden returned $wv, which does not land such a bead on its own. fleet-safe removed, assigned to $(overseer_assignee) with an ASK line (human kept as history); his Approve on the Keep lands it as a signed landing." \
    -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"ESCALATE\",\"wardenVerdict\":\"$wv\",\"hold\":\"$(sign_label)\",\"unclassified\":$([ "${6:-}" = unclassified ] && echo true || echo false)}"
}

# A SIGNATURE ON A STALE BRANCH IS WASTED (Proofdelve ForgeOs-8gmt4, Regent docket
# 2026-10-27 item C). A bead held for the Overseer's signature waits hours to
# days, and main moves under it: on 10-26 three of four signatures could not
# land, and on 10-27 2md9d.5.16.1, signed at 10:00, conflicted with a landing
# made at 10:10. Each cost a conflict lap, a review and a SECOND signature.
# So once per pass, every worker whose stored verdict a signed landing could
# rest on (held for signature, or signed and not yet landed) is asked the same
# `git merge-tree --write-tree` question prelanding_refresh() asks before a
# landing (Proofdelve ForgeOs-36b9). When one stops merging cleanly it is handed to the
# Mayor BEFORE he spends a signature: mayor-review added, assigned to the Mayor
# (so it leaves his board, which is `assignee = justin`), and one comment
# naming the conflicting files. The fingerprint (branch tip plus files) is kept
# in the worker dir, so later passes stay silent until the conflict changes; a
# branch that merges cleanly again drops it. Nothing is merged, labelled
# fleet-safe or dispatched here, and the Overseer's records are not touched.
# A dry run says what it would do and writes nothing.
stale_signature_check() {
  local vf wdir sfx bead br out mrc first paths fp old brc
  for vf in "$state/workers"/*/verdict; do
    stopping && return 0
    [ -f "$vf" ] || continue
    stored_verdict_is_signable "$(cat "$vf" 2>/dev/null)" || continue
    wdir="${vf%/verdict}"; sfx="$(basename "$wdir")"; br="bead/$sfx"
    worker_live "$wdir" && continue
    bead="$(cat "$wdir/bead" 2>/dev/null || echo "")"
    [ -n "$bead" ] || continue
    git -C "$root" rev-parse -q --verify "refs/heads/$br" >/dev/null 2>&1 || continue
    git -C "$root" merge-base --is-ancestor "$br" "$main_branch" 2>/dev/null && continue
    mrc=0
    out="$(git -C "$root" merge-tree --write-tree --name-only "$main_branch" "$br" 2>/dev/null)" || mrc=$?
    first="${out%%$'\n'*}"
    if [ "$mrc" -eq 0 ]; then rm -f "$wdir/stale-merge"; continue; fi
    # exit 1 without a 40-hex oid on line 1 is git failing to answer, not a
    # conflict (prelanding_refresh()'s measurement); say nothing and ask again
    # next pass.
    [ "$mrc" -eq 1 ] && [[ "$first" =~ ^[0-9a-f]{40}$ ]] || continue
    paths="$(printf '%s\n' "$out" | sed -n '2,/^$/p' | sed '/^$/d' | tr '\n' ' ' | sed 's/ $//')"
    fp="$(git -C "$root" rev-parse "$br" 2>/dev/null) ${paths:-<unnamed>}"
    old="$(cat "$wdir/stale-merge" 2>/dev/null || echo "")"
    [ "$fp" = "$old" ] && continue
    if [ "$dry" = 1 ]; then
      say "DRY-RUN would hand $bead to the Mayor: $br no longer merges cleanly with $main_branch (conflicts on ${paths:-<unnamed>}), so a signature on it would be wasted"
      continue
    fi
    brc=0
    bd -C "$root" update "$bead" --add-label mayor-review --assignee "$(mayor_assignee)" --actor "$fleet_actor" >/dev/null 2>&1 || brc=$?
    if [ "$brc" -ne 0 ]; then
      warn "$bead: $br no longer merges cleanly with $main_branch (on ${paths:-<unnamed>}) and the bd write handing it to the Mayor FAILED (exit $brc); asking again next pass"
      continue
    fi
    printf '%s\n' "$fp" > "$wdir/stale-merge" 2>/dev/null || true
    printf 'fort/scripts/fleet.sh: %s no longer merges cleanly with %s. "git merge-tree --write-tree %s %s" reports conflicts on: %s. A signature on this tip would be wasted (Proofdelve ForgeOs-8gmt4), so it is handed to the Mayor (mayor-review, assigned to %s) to file a conflict lap BEFORE the Overseer signs. Nothing was merged.\n' \
      "$br" "$main_branch" "$main_branch" "$br" "${paths:-<unnamed>}" "$(mayor_assignee)" > "$state/logs/stale-signature-$bead.txt" 2>/dev/null || true
    bd -C "$root" comment "$bead" --file "$state/logs/stale-signature-$bead.txt" --actor "$fleet_actor" >/dev/null 2>&1 \
      || warn "$bead: the stale-signature comment could not be written (mayor-review was applied)"
    say "$bead: held for signature, but $br NO LONGER MERGES with $main_branch (conflicts on ${paths:-<unnamed>}) -- handed to the Mayor for a conflict lap before a signature is spent (Proofdelve ForgeOs-8gmt4)"
    emit fleet.stale-signature "$bead held for the Overseer's signature no longer merges with $main_branch (conflicts on ${paths:-<unnamed>}); mayor-review added and assigned to $(mayor_assignee) so the lap is filed before a signature is spent" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"branch\":\"$br\",\"paths\":\"${paths//\"/}\"}"
  done
}

land() {  # $1 bead, $2 verdict token, $3 warden record file, [$4 the tip the review was launched on]
  local bead="$1" verdict="$2" record="$3"
  local sfx="${bead##*-}" follow=""
  local vout="$state/logs/postmerge-$bead.txt"
  local wdir="$state/workers/$sfx"

  # THE SIGNATURE HOLD (Proofdelve ForgeOs-vee4w; the reasoning is above sign_label()).
  # FIRST, before the verdict is persisted, so a held bead's record says
  # ESCALATE and never the token that did not land it.
  if [ "$verdict" != "OVERSEER-SIGNED" ]; then
    # THE WORKBENCH BELTS (Proofdelve ForgeOs-6niaz, the Overseer's ruling on the Warden's
    # finding 2 at the sitting). A session bead lands on review (part C), so
    # without these the Warden choosing ESCALATE is the ONLY thing holding gated
    # content in a session range: the exact reliance sign_label()'s comment
    # records letting Proofdelve ForgeOs-etmwb land unsigned.
    if worker_review_only "$wdir"; then
      local gwhy="" swhy="" src=0
      # BELT 2 FIRST: a range that shares unlanded commits with another sitting
      # held for his signature does not land on an unsigned review; it pages.
      swhy="$(stacked_held_why "$sfx")" || src=$?
      if [ "$src" -ne 0 ]; then
        # SAVED FIRST, as the vee4w deferral below saves them (the Warden, 6niaz round
        # two, finding 3): the retry reads the stored verdict, and without it a
        # deferred bead is stranded as having no usable verdict.
        if [ -d "$wdir" ]; then
          printf '%s\n' "$verdict" > "$wdir/verdict" 2>/dev/null || true
          if [ -n "${4:-}" ]; then printf '%s\n' "$4" > "$wdir/reviewed-sha" 2>/dev/null || true; fi
        fi
        defer_merge "$wdir" "$bead" "$verdict" "bd would not list the Workbench sittings held for the Overseer's signature, so whether this range carries one's commits is unknown (Proofdelve ForgeOs-6niaz)"
        return 0
      fi
      if [ -n "$swhy" ]; then
        page_overseer "$bead" "the Warden returned $verdict on this Workbench range, and it shares unlanded commits with $swhy, which is held for your signature. Landing this range would put those commits on main unsigned, so it is NOT merged (Proofdelve ForgeOs-6niaz belt 2). Sign or land that sitting first, then re-queue this one with fleet.sh --review-only $bead." "" \
          "Nothing was merged. The session branch stands as reviewed."
        return 0
      fi
      # BELT 1: a range that touches a gated path waits for his signature
      # whatever the token says. The path list is the gate-1 list warden.sh's
      # diff class uses, plus migrations (gate 2) and the constitution (gate 6);
      # scripts/review-throughput-harness.sh keeps the gate-1 half identical to
      # warden.sh's.
      gwhy="$(gated_range_why "$sfx")"
      if [ -n "$gwhy" ]; then
        hold_for_signature "$bead" "$verdict" "$record" "$wdir" "${4:-}" gated "$gwhy"; return 0
      fi
    fi
    local sig_rc=0
    needs_signature "$bead" || sig_rc=$?
    case "$sig_rc" in
      0) hold_for_signature "$bead" "$verdict" "$record" "$wdir" "${4:-}"; return 0 ;;
      3) hold_for_signature "$bead" "$verdict" "$record" "$wdir" "${4:-}" unclassified; return 0 ;;
      1) ;;
      *) if [ -d "$wdir" ]; then
           printf '%s\n' "$verdict" > "$wdir/verdict" 2>/dev/null || true
           # and the reviewed tip, so a resume into the hold keeps it (the Warden, round two, finding 2)
           if [ -n "${4:-}" ]; then printf '%s\n' "$4" > "$wdir/reviewed-sha" 2>/dev/null || true; fi
         fi
         defer_merge "$wdir" "$bead" "$verdict" "bd would not say what labels the bead carries, so whether it needs the Overseer's signature ($(sign_label)) is unknown (Proofdelve ForgeOs-vee4w)"
         return 0 ;;
    esac
  fi
  # A SIGNED LANDING OF A HELD BEAD DOES WHAT THE WARDEN DECIDED. outcome is
  # the token the close-or-leave-open steps below act on: the Warden's own when
  # this is the signed landing of a bead the hold stopped, otherwise the
  # verdict itself.
  local outcome="$verdict" held=""
  if [ "$verdict" = "OVERSEER-SIGNED" ]; then
    held="$(cat "$wdir/warden-verdict" 2>/dev/null || echo "")"
    case "$held" in
      APPROVE-WITH-FINDINGS|MERGE-PARENT-OPEN) outcome="$held"; record="$wdir/warden-record" ;;
    esac
  fi
  # WHAT THE RECORDS SAY (Proofdelve ForgeOs-owt37, the Warden's vee4w round-one finding 2, lower
  # half). The merge message, close reason and fleet.signed already named the
  # held token (2869ad0d); the follow-up title, fleet.parent-open and bead.closed
  # still said OVERSEER-SIGNED, so a reader of Proofdelve ForgeOs-5rc4g's title could not
  # tell what the Warden decided. shown is the Warden's token plus the route
  # when this is a held bead's signed landing, and the verdict otherwise -- an
  # ESCALATE-then-signed landing keeps saying OVERSEER-SIGNED, its true route.
  local shown="$verdict"
  [ "$outcome" != "$verdict" ] && shown="$outcome, landed on the Overseer's signature"

  # PERSISTED BEFORE THE FIRST THING THAT CAN DEFER, not after it.
  if [ -d "$wdir" ]; then
    printf '%s\n' "$verdict" > "$wdir/verdict" 2>/dev/null || true
    # AND THE REVIEWED TIP (Proofdelve ForgeOs-vee4w round two, the Warden's finding 4): a merge
    # that defers and later resumes into the hold must still know what the
    # Warden was launched on, or the signed landing cannot compare it.
    if [ -n "${4:-}" ]; then printf '%s\n' "$4" > "$wdir/reviewed-sha" 2>/dev/null || true; fi
    if [ -s "$record" ] && [ "$record" != "$wdir/warden-record" ]; then
      cp -f "$record" "$wdir/warden-record" 2>/dev/null || true
    fi
  fi

  # Proofdelve ForgeOs-vikl: establish WHERE we are about to land before landing, and then
  # name that branch in the message and the event rather than asserting "main"
  # unconditionally. A long night is long enough for someone to switch HEAD.
  # Proofdelve ForgeOs-5m7a: DEFER, do not halt. Since Proofdelve ForgeOs-dx34.1 this is the ONLY
  # place landability can refuse anything at all — preflight reports it and
  # starts the run regardless. The reasoning is on report_landability().
  # Proofdelve ForgeOs-a2fx. A merge is the least interruptible thing this file does and
  # the most expensive to half-do, so a stopping run does not start one. The
  # verdict stands and the bead keeps its claim, exactly as the landability
  # defer below — which means Proofdelve ForgeOs-usz6's retry gap covers this path too.
  if stopping; then
    # Proofdelve ForgeOs-fhak: a halt FILE seen here has not set $end_reason yet (the
    # operator-halt record is written when the loop reaches its check), so name
    # the file rather than the default reason.
    if halt_file_present; then
      defer_merge "$wdir" "$bead" "$verdict" "the run is stopping (the halt file $halt_file is present)"
    else
      defer_merge "$wdir" "$bead" "$verdict" "the run is stopping (${end_reason})"
    fi
    return 0
  fi
  local why; why="$(landable_why)"
  if [ -n "$why" ]; then
    defer_merge "$wdir" "$bead" "$verdict" "$root is not landable: $why"
    return 0
  fi
  local into; into="$(tree_branch)"
  # THE RECORD NAMES WHAT AUTHORISED THE MERGE (Proofdelve ForgeOs-ubgx). On a signed
  # landing no Warden said APPROVE; the stored verdict is ESCALATE and the
  # Overseer's recorded approval of a named sha is the basis, so the merge
  # message and the close reason say so rather than borrowing the review's
  # sentence.
  local basis="Verifier green in the worktree before review, Warden verdict
$verdict recorded with a bounded VERDICT-LINE." closed_on="on $verdict; host verifier green before review and again after merge"
  if [ "$verdict" = "OVERSEER-SIGNED" ]; then
    local approved_sha; approved_sha="$(cat "$wdir/approved-sha" 2>/dev/null || echo "unrecorded")"
    # WHAT THE WARDEN ACTUALLY SAID (the Warden's finding 2): a held bead's Warden
    # returned a merging token and the fleet stored ESCALATE for the hold. The
    # merge message and the close reason are permanent, so they say so.
    local said="Stored Warden verdict ESCALATE" said_lc="stored Warden verdict ESCALATE"
    if [ -n "${held:-}" ]; then
      said="Warden verdict $held, HELD by the signature hold (Proofdelve ForgeOs-vee4w)"; said_lc="$said"
    fi
    basis="$said; landed on the Overseer's recorded approval
of $approved_sha (gate.approved from the Keep), the branch carrying the same
change by patch-id (Proofdelve ForgeOs-ubgx). Host verifier green in the worktree before
the merge; no second review launch was spent."
    closed_on="on OVERSEER-SIGNED: the Overseer's recorded approval of $approved_sha, $said_lc, the branch unchanged by patch-id; host verifier green before the merge and again after"
  fi

  if ! bd -C "$root" merge-slot acquire >/dev/null 2>&1; then
    # THE OLDEST OF THE THREE, AND THE ONE THE OTHERS WERE COPIED FROM. It has
    # said "will retry next pass" since the fleet was written, and until
    # Proofdelve ForgeOs-usz6 nothing retried it.
    defer_merge "$wdir" "$bead" "$verdict" "the merge slot is held by someone else"
    return 0
  fi
  if ! git -C "$root" merge --no-ff "bead/$sfx" \
        -m "$bead: merged by the fleet on $verdict (run $run_id)

Merged into $into. $basis Landed by fort/scripts/fleet.sh,
not by a citizen." \
        >"$state/logs/merge-$bead.txt" 2>&1; then
    git -C "$root" merge --abort >/dev/null 2>&1 || true
    bd -C "$root" merge-slot release >/dev/null 2>&1 || true
    worker_set_state "$wdir" settled "the merge into $into failed and was aborted; the bead went back to the queue"
    return_to_ready "$bead" "merge into $into failed and was aborted; $into is untouched" "$state/logs/merge-$bead.txt"
    return 0
  fi
  bd -C "$root" merge-slot release >/dev/null 2>&1 || true
  landings=$((landings + 1))
  say "$bead: merged to $into"
  emit merge "Fleet merged bead/$sfx into $into on $verdict" \
    -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"$verdict\",\"into\":\"$into\"}"

  # POST-MERGE VERIFIER, AND A RED MAIN HALTS THE RUN (Overseer amendment,
  # 2026-09-02, recorded on Proofdelve ForgeOs-9mfw.3). There is a measured instance of
  # main going red after a merge that was green pre-merge in three separate
  # environments (fortkit-h5i: a test coupling to ambient git state). Three
  # workers cannot swarm-diagnose a red main, so this stops rather than logs.
  #
  # IT RUNS IN A FRESH WORKTREE AT THE MERGED COMMIT (Proofdelve ForgeOs-dx34.1, option
  # (d)) — see postmerge_verify() for the whole reasoning and the measurement.
  # The merged sha is resolved HERE, immediately after the merge, so the claim
  # the record makes names a commit and not a branch tip that may move.
  local sha; sha="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo "")"
  # NO REFILL HERE, DELIBERATELY (the Warden's finding 1 on docket Proofdelve ForgeOs-9dqa6).
  # A Forge dispatched between the merge and this verifier is cut from a main
  # nobody has verified yet; if the verifier goes red the run halts with that
  # Forge building on a red main. The refill after the host verifier and the one
  # before the next worker is taken in hand cover the gap (Proofdelve ForgeOs-uwjme).
  # VERIFY ONCE (Proofdelve ForgeOs-s1reg): the post-merge run is skipped only when the
  # merged tree IS the tree the host verifier passed, at full tier with Docker.
  if verified_reusable "$wdir" "$sha"; then
    postmerge_result=reused; postmerge_tree=""
  else
    say "$bead: post-merge verify RUNS: the host verify cannot stand for $into at ${sha:0:12}: $reuse_why"
    postmerge_verify "$bead" "$sha" "$vout"
  fi
  case "$postmerge_result" in
    reused)
      say "$bead: post-merge verify REUSED: $into's tree at ${sha:0:12} is byte-identical to the tree the host verifier passed at ${reused_commit:0:12} (full tier, Docker up); no second run (Proofdelve ForgeOs-s1reg)"
      emit verify.pass "Post-merge verify REUSED at $sha after landing $bead into $into: its tree ${reused_tree} is the tree the host verifier passed at ${reused_commit} (full tier, Docker up), so it was not run twice" \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"commit\":\"$sha\",\"branch\":\"HEAD\",\"ran\":false,\"reused\":true,\"verifiedTree\":\"$reused_tree\",\"verifiedCommit\":\"$reused_commit\",\"tier\":\"full\",\"docker\":true}"
      ;;
    green)
      # SAY WHICH IT DID WITH THE TREE. A morning reader should not have to
      # infer "it was removed" from a directory listing that is not there.
      say "$bead: post-merge verifier GREEN at ${sha:0:12} in a fresh worktree, which was then REMOVED."
      emit verify.pass "Post-merge verifier GREEN at $sha after landing $bead into $into, run in a fresh worktree at that commit; the worktree was removed" \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"commit\":\"$sha\",\"ran\":true,\"worktree_kept\":false}"
      ;;
    red|refused)
      # ONE HALT, TWO TRUTHS (Proofdelve ForgeOs-s1reg finding 4). A refused run halts
      # too, by the Overseer's call on 2026-10-20: the supervisor would
      # otherwise start a run every ~2 min and land one more bead unverified
      # each time. What changes is the record: no verify.fail, because nothing
      # was measured, and a halt file that says UNRUNNABLE and names the cause.
      bd -C "$root" comment "$bead" --file <(capped_log "$vout") --actor "$fleet_actor" >/dev/null 2>&1 || true
      local pm_what
      if [ "$postmerge_result" = refused ]; then
        pm_what="post-merge verification is UNRUNNABLE at $sha after landing $bead (not a measured red, and not a green either: $unrunnable_why)"
      else
        pm_what="post-merge verifier is RED at $sha after landing $bead"
        emit verify.fail "Post-merge verifier RED at $sha after landing $bead into $into" \
          -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"commit\":\"$sha\",\"ran\":true,\"worktree_kept\":true,\"worktree\":\"$postmerge_tree\"}"
      fi
      worker_set_state "$wdir" needs-person "the merge STANDS on $into and the $pm_what; the bead is not closed and the fleet halted. The worktree it ran in is KEPT at $postmerge_tree"
      halt "$pm_what — the merge stands, the bead is NOT closed, and the run stops here. Evidence: $vout, and the worktree it ran in is KEPT at $postmerge_tree"
      ;;
    interrupted)
      # NOT A VERDICT ABOUT $into IN EITHER DIRECTION, so it neither halts nor
      # closes. What it does do is stop claiming the bead is fleet work, on the
      # merged-but-not-closed precedent below (Proofdelve ForgeOs-bzyk): merged +
      # in_progress + still fleet-safe is absent from every queue a person
      # reads.
      escalate_labels "$bead"   # Proofdelve ForgeOs-s2lx: checked; the sentence below carries the truth
      worker_set_state "$wdir" needs-person "MERGED into $into at $sha and the post-merge verification was STOPPED by SIG$stop_signal before it concluded, so $into is UNVERIFIED at that commit and the bead was NOT closed. $label_note${postmerge_tree:+; the worktree is KEPT at $postmerge_tree}"
      say "$bead: MERGED into $into, and its post-merge verification was STOPPED by SIG$stop_signal — that is not a red main. $into is UNVERIFIED at ${sha:0:12}, the bead is NOT closed, and no halt file was written. $label_note.${postmerge_tree:+ The worktree is KEPT at $postmerge_tree.}"
      emit incident "Fleet merged $bead into $into at $sha and its post-merge verification was stopped by SIG$stop_signal before it concluded. $into is UNVERIFIED at that commit; the bead was NOT closed. $label_note. This is NOT a red main and NO halt file was written." \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"commit\":\"$sha\",\"merged\":true,\"closed\":false,\"ran\":false,\"signal\":\"$stop_signal\",\"bd_exit\":$label_rc}"
      return 0
      ;;
    *)
      # unrunnable, and anything postmerge_verify() could ever add to that list.
      # NOTHING WAS MEASURED, which is a different fact from "main is red" and
      # must never be recorded as one.
      #
      # IT DOES NOT HALT, AND IT DOES STOP THE RUN, and those are two decisions.
      # No halt file, because nothing here says a person must look at $into
      # before the fleet may run again — the next run is free to try and will
      # very likely succeed. But this run does not continue: every later merge
      # in it would be stacked on an $into nothing has verified, and the fleet's
      # own promise is that it never continues past an unverified main.
      bd -C "$root" comment "$bead" --file <(capped_log "$vout") --actor "$fleet_actor" >/dev/null 2>&1 || true
      escalate_labels "$bead"   # Proofdelve ForgeOs-s2lx: checked; the sentence below carries the truth
      worker_set_state "$wdir" needs-person "MERGED into $into at $sha and the post-merge verification COULD NOT RUN at all, so $into is UNVERIFIED at that commit and the bead was NOT closed. $label_note. Evidence: $vout${postmerge_tree:+; residue at $postmerge_tree}"
      say "$bead: MERGED into $into, and the post-merge verification COULD NOT RUN — it was not red, it never happened. $into is UNVERIFIED at ${sha:0:12} and the bead is NOT closed. $label_note. Evidence: $vout"
      say "  This run stops here. No halt file is written, so the next run may start normally."
      emit incident "Fleet merged $bead into $into at $sha and then COULD NOT RUN the post-merge verification (result: $postmerge_result). Nothing was measured: this is NOT a red main. $into is UNVERIFIED at that commit, the bead was NOT closed, and the run stopped. $label_note. No halt file was written. Evidence: $vout" \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"commit\":\"$sha\",\"merged\":true,\"closed\":false,\"ran\":false,\"result\":\"$postmerge_result\",\"bd_exit\":$label_rc}"
      stop_requested=1
      set_end_reason "stopped: a post-merge verification could not run, so $into is unverified at $sha"
      return 0
      ;;
  esac

  # APPROVE-WITH-FINDINGS DOES NOT CLOSE SILENTLY. It is 64 of the 67 verdicts
  # that would auto-close in this fort — 96% of the auto-close path — and every
  # one is a review that found things and judged them non-blocking. Closing
  # those overnight with nobody told industrialises the fnjn class: fixes
  # landing as passengers, beads outliving their fixes. So one follow-up bead
  # per approval-with-findings, carrying the verdict VERBATIM. The findings are
  # deliberately NOT parsed out of it: the Warden states them in prose and a parser
  # would do it badly. (Proofdelve ForgeOs-6niaz part A, 2026-11-11: the prose is still not
  # read. What is read is her TIER TAG on each numbered finding, a token in a
  # fixed position, and only on APPROVE-WITH-FINDINGS; see tier_findings().)
  if verdict_files_followup "$outcome"; then
    if [ "$outcome" = "MERGE-PARENT-OPEN" ]; then
      file_followup "$bead" "$shown" "$record" \
        "NOT closed on MERGE-PARENT-OPEN during run $run_id: the reviewer judged the diff" \
        "sound and at least one acceptance criterion unmet, so the parent is still open."
    else
      file_followup "$bead" "$shown" "$record" \
        "closed on APPROVE-WITH-FINDINGS during run $run_id, with nobody awake to read" \
        "the verdict. It is here for the Mayor triage, and its findings are UNTRIAGED." \
        "$outcome"
    fi
    local body="$followup_body"
    follow="$followup_ids"
    # A REVIEW OF ONLY [record] FINDINGS OWES NO BEAD (Proofdelve ForgeOs-6niaz part A), so
    # an empty id list is not a failed filing there and must not take the loud
    # merged-but-not-closed branch below.
    if [ "$followup_none" != 1 ] && [ -z "$followup_bead" ]; then
      # MERGE BUT DO NOT CLOSE. The Overseer's condition, in terms.
      # Proofdelve ForgeOs-bzyk: and take it OUT OF THE FLEET on the way past. Merged +
      # in_progress + still fleet-safe + still assigned is a silent orphan: it
      # is absent from `bd ready`, so nobody sees it, and the label still says
      # the fleet owns it. It is NOT re-dispatchable (dispatchable() refuses any
      # status that is not `open`, and --claim set in_progress), so this is a
      # VISIBILITY defect rather than a token-burn loop — which is exactly why
      # it could sit unnoticed. `fleet-escalated` is the label dispatchable()
      # already refuses, and it is what the Mayor queries for.
      escalate_labels "$bead"   # Proofdelve ForgeOs-s2lx: checked; the sentences below carry the truth
      # THE SENTENCE DIFFERS BY VERDICT AND THE ACTION DOES NOT (Proofdelve ForgeOs-j3kp).
      # On APPROVE-WITH-FINDINGS, not closing IS the failure. On
      # MERGE-PARENT-OPEN the parent was never going to close, and what failed is
      # only that the findings did not get their own bead — less severe, because
      # warden.sh has already posted the whole review as a comment on this same
      # bead. Telling a reader that the failure was "not closed" when not
      # closing was the intended outcome is the conflation this bead exists to
      # end, one layer down.
      local lost
      if [ "$outcome" = "MERGE-PARENT-OPEN" ]; then
        lost="the follow-up bead could not be filed, so the findings have no bead of their own; the parent is open as intended and the review is on it"
      else
        lost="the follow-up triage bead could not be filed, so the parent was NOT closed"
      fi
      # A PARTIAL FILING SAYS WHAT WAS FILED (the Warden, 6niaz review finding 4): a
      # tiered review can file its [bead] follow-up and then fail the
      # polish-batch bead. The parent is still not closed, but the bead that WAS
      # filed gets its edge and is named, rather than orphaned under a sentence
      # saying nothing was filed.
      local pfid
      if [ -n "$followup_ids" ]; then
        for pfid in $followup_ids; do
          bd -C "$root" dep add "$pfid" "$bead" --actor "$fleet_actor" >/dev/null 2>&1 || true
        done
        lost="$lost (partially filed: $followup_ids, edged to the parent; the rest could not be filed)"
      fi
      worker_set_state "$wdir" needs-person "MERGED on $verdict and $lost. $label_note"
      say "$bead: MERGED on $verdict — $lost; $label_note"
      bd -C "$root" comment "$bead" --file "$body" --actor "$fleet_actor" >/dev/null 2>&1 || true
      emit incident "Fleet merged $bead on $verdict but could NOT file the follow-up bead: $lost. The verdict is on the bead; the findings are untriaged. $label_note." \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"$verdict\",\"merged\":true,\"closed\":false,\"bd_exit\":$label_rc}"
      return 0
    fi
    # Proofdelve ForgeOs-8zwv item 3: WITHOUT --actor the edge is attributed to the git
    # user, so `created_by: Justin Schneider` appears on a dependency no human
    # made (measured on Proofdelve ForgeOs-dvqa). Every other bd write in this file names
    # the mechanism; this one was missed.
    #
    # THE EDGE IS WANTED AND ITS TYPE WAS THE DEFECT (the Warden, finding
    # 5 of the sitting-one review; the Overseer's decision, 2026-09-10, on
    # Proofdelve ForgeOs-j3kp). `bd dep add` takes --type and DEFAULTS TO `blocks`, and
    # this line used to take that default by omission — so the follow-up
    # depended on its parent in the blocking sense. That was inert while every
    # follow-up sat beside a parent the fleet CLOSED, and MERGE-PARENT-OPEN
    # turns it live: the token means merge, file the follow-up, LEAVE THE
    # PARENT OPEN, and doing both made the follow-up blocked by an open bead —
    # absent from `bd ready`, out of the dispatchable set, invisible to the
    # Mayor's session-start inbox. The findings would land in a bead nobody
    # sees until the parent closes, and the parent is open precisely because
    # something is unfinished.
    #
    # HIS RULING: A FOLLOW-UP SHOULD BE ACTIONABLE WHILE ITS PARENT IS OPEN. So
    # the new token records provenance instead of blocking. APPROVE-WITH-
    # FINDINGS IS DELIBERATELY UNCHANGED: its parent closes anyway, so the edge
    # stays inert there, and a vocabulary change that silently reinterprets the
    # older token's records is worse than the gap it closes.
    #
    # DELETING THE EDGE WAS CONSIDERED AND REJECTED — it was the Overseer's own
    # first draft and he rejected it; the provenance is worth keeping. So was
    # REVERSING it so the parent depends on the follow-up: that blocks the
    # parent on its own triage bead and changes parent dispatchability, which
    # is a second decision nobody has made.
    #
    # MEASURED IN THIS TREE, 2026-09-10, because until today this database held
    # ZERO `discovered-from` edges and the type's non-blocking behaviour was
    # inferred from documentation rather than observed. A real edge was created
    # (Proofdelve ForgeOs-6843 discovered-from Proofdelve ForgeOs-j3kp, a true relationship kept for
    # its own sake), the parent confirmed OPEN, and the dependent stayed in
    # `bd ready` — total unchanged at 347, and absent from `bd blocked`, whose
    # nine entries include Proofdelve ForgeOs-aqc6.2.3 so that zero is a discrimination
    # and not an empty command. Full note in
    # fort/memory/facts/bd-dependency-types-and-what-actually-blocks.md.
    #
    # WHETHER A TYPE LEAVES A BEAD READY IS A CLAIM ABOUT bd, NOT ABOUT THIS
    # FILE, which is why it is measured by hand and lives in the ledger. A
    # harness asserting it would fail when bd changed and blame fleet.sh. The
    # harness asserts the CALL: scripts/fleet-e2e-harness.sh scenarios 10 and
    # 11 read the stub's call log.
    # ONE ARGUMENT ON ONE PATH, AND THE OTHER CALL IS LEFT ALONE BYTE FOR BYTE.
    # Making the older token pass `--type blocks` explicitly was drafted and
    # backed out: it is behaviour-identical, so it buys nothing this token
    # needs, and "unchanged" is worth more here than "tidier" when the whole
    # risk of a vocabulary change is that it reinterprets records nobody
    # re-read. An explicit `if` rather than `[ test ] && cmd`, because this file
    # has been killed twice by set -e/set -u subtleties in one-liners that were
    # also safe by the letter.
    # ONE EDGE AND ONE bead.filed PER FILED BEAD (Proofdelve ForgeOs-6niaz part A): a
    # tiered review can file a [bead] follow-up AND a polish-batch bead. Every
    # other path files exactly one, so for those this loop runs once and the
    # calls are the ones it always made.
    if [ "$followup_none" = 1 ]; then
      say "$bead: NO follow-up filed: every finding in the review is tagged [record], so nothing is owed a bead (Proofdelve ForgeOs-6niaz)"
    fi
    local fid
    for fid in $followup_ids; do
      if [ "$outcome" = "MERGE-PARENT-OPEN" ]; then
        bd -C "$root" dep add "$fid" "$bead" --type discovered-from --actor "$fleet_actor" >/dev/null 2>&1 || true
      else
        bd -C "$root" dep add "$fid" "$bead" --actor "$fleet_actor" >/dev/null 2>&1 || true
      fi
      say "$bead: follow-up filed as $fid"
      emit bead.filed "Fleet filed $fid to carry the non-blocking findings from $bead" \
        -a "$fleet_actor" -s fleet -t "$fid" -p "{\"run\":\"$run_id\",\"parent\":\"$bead\"}"
    done
  fi

  # ---------------------------------------------------------------------
  # MERGE-PARENT-OPEN: THE DIFF LANDS AND THE PARENT DOES NOT CLOSE
  # (Proofdelve ForgeOs-j3kp). Everything above this line has already happened — the merge,
  # the post-merge verifier, the follow-up if there was one. What is different is
  # only the last step.
  # ---------------------------------------------------------------------
  # WHY THE TOKEN EXISTS. APPROVE-WITH-FINDINGS meant two things: (a) the work is
  # DONE, here is what is next, and (b) the work is NEARLY done, one criterion is
  # unmet. On 2026-09-09 the Warden meant (b), emitted (a), and said (b) in prose; this
  # file closed Proofdelve ForgeOs-7b5x on the token, WHICH WAS THIS FILE BEHAVING CORRECTLY
  # — it cannot read prose and does not try. The vocabulary had no way to say
  # what she meant. Same shape as Proofdelve ForgeOs-w7u5 one layer up: `done` meant two
  # things and was split.
  #
  # THE INTERIM RULE THIS REPLACES, AND WHY IT COULD NOT STAY. From 2026-09-09 a
  # criterion not met was REQUEST-CHANGES. It works and the fleet honours it. But
  # REQUEST-CHANGES returns the bead to the Forge FOR A FULL CYCLE AT TWO
  # LAUNCHES, so a reviewer with nine criteria met and a tenth needing five
  # minutes is tempted to approve instead — which is exactly how this happened. A
  # rule that makes honest reporting costly produces dishonest reporting.
  #
  # THE PARENT'S STATE IS UNAMBIGUOUS AND IS SET RATHER THAN LEFT (j3kp
  # acceptance 3). Open, not claimed, and NOT re-eligible for the fleet: a bead
  # left open still carrying `fleet-safe` would be picked up again on the next
  # pass, which is Proofdelve ForgeOs-p0a6's consent boundary in reverse. Removing
  # `fleet-safe` is what dispatchable() already refuses on, and it leaves the
  # bead in `bd ready` where the Mayor sees it — deliberately NOT
  # `fleet-escalated`, which this file uses for merges that went wrong. This one
  # did not go wrong; it is the outcome the reviewer chose.
  #
  # AND ITS WORKTREE IS KEPT, which follows from the reap living in the close
  # branch and is worth saying out loud: a person may put `fleet-safe` back and
  # the bead is dispatched again, and forge.sh reuses this worktree
  # (forge.sh:41-43). Reaping here would make that dispatch die at
  # `worktree add -b` on a branch that already exists.
  if [ "$outcome" = "MERGE-PARENT-OPEN" ]; then
    # THE EVENT REPORTS THE WRITE THAT HAPPENED, NOT THE ONE THAT WAS ATTEMPTED
    # (Proofdelve ForgeOs-stpx). This write is `|| true` deliberately — a tracker that will
    # not answer must not take a run down after its merge has landed — and the
    # five reports below it fired UNCONDITIONALLY, so a refused write produced a
    # worker marked `settled`, a narrative saying the parent was left open and
    # unclaimed, and a `fleet.parent-open` event, none of which had happened.
    # This file STATES that rule 1100 lines above, at return_to_ready(), and
    # then broke it four lines later. The Warden found it in the
    # sitting-one review and said why it is here rather than in a bead: "I would
    # rather it were fixed than filed."
    #
    # THE WORKER IS MARKED needs-person AND NOT LEFT ALONE, which is one line
    # more than the docket asked for and is the sibling branch's own answer
    # forty lines above. Saying nothing would leave a worker whose recorded
    # state does not mention that a merge happened — the same silent gap one
    # layer over, which is the class this whole sitting is about.
    local prc=0
    # EVERY PATH THAT STRIPS fleet-safe MUST NAME THE NEXT OWNER (Proofdelve ForgeOs-e2rbu).
    # This one alone removed it and added nothing, so a MERGE-PARENT-OPEN bead
    # sat open, unassigned and in no queue any seat reads -- nine instances,
    # every one found by a person or a sweep. mayor-lane is the Mayor's own
    # pool and where a person routed all of them by hand. The earlier instance
    # of the same rule is Proofdelve ForgeOs-ubgx.1: the Keep's Decline and Decide left a
    # bead routed to nobody until every exit from the queue named its owner.
    bd -C "$root" update "$bead" --remove-label fleet-safe --add-label mayor-lane --status open --assignee "" \
      --actor "$fleet_actor" >/dev/null 2>&1 || prc=$?
    if [ "$prc" -ne 0 ]; then
      worker_set_state "$wdir" needs-person "MERGED into $into at $sha on $verdict and the bd write that was to leave the parent open and unclaimed FAILED (exit $prc). The diff IS landed. The bead is still claimed, still in_progress and STILL fleet-safe, so its state does NOT match this stream${follow:+; findings were carried to $follow}"
      say "$bead: MERGED into $into on $verdict, and the bd write that leaves the parent open FAILED (exit $prc)"
      say "  The diff is landed. The bead is still claimed and still fleet-safe: its tracker state does NOT match this run."
      emit incident "Fleet merged $bead on $verdict and then could NOT set the parent open and unclaimed: the bd write failed (exit $prc). The diff IS landed. The bead is still claimed, in_progress and fleet-safe, so the tracker does not reflect this outcome and no fleet.parent-open was emitted for it.${follow:+ Findings were carried to $follow.}" \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"$verdict\",\"commit\":\"$sha\",\"merged\":true,\"closed\":false,\"parent_open\":false,\"bd_exit\":$prc}"
      return 0
    fi
    worker_set_state "$wdir" settled "MERGED into $into on $shown and the PARENT WAS LEFT OPEN deliberately: a criterion is unmet. fleet-safe removed and mayor-lane added, so the fleet does not pick it up again${follow:+; findings carried to $follow}"
    say "$bead: MERGED into $into and DELIBERATELY NOT CLOSED ($verdict)${follow:+, findings on $follow}"
    say "  The reviewer judged the diff sound and a criterion unmet. The bead is OPEN, unclaimed,"
    say "  and out of the fleet: a person decides what remains and puts fleet-safe back if it should"
    say "  run again. Its worktree is KEPT for exactly that."
    emit fleet.parent-open "Fleet merged $bead on $shown and left the parent OPEN: the diff landed, a criterion is unmet, fleet-safe was removed and mayor-lane added, so it waits in the Mayor's pool and the fleet will not pick it up again. This is the reviewer's chosen outcome and NOT a failure.${follow:+ Findings carried to $follow.}" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"$verdict\",\"outcome\":\"$outcome\",\"merged\":true,\"closed\":false,\"parent_open\":true,\"routed\":\"mayor-lane\",\"followup\":\"${follow:-}\"}"
    return 0
  fi

  if bd -C "$root" close "$bead" --reason="merged and closed by fort/scripts/fleet.sh $closed_on${follow:+; findings carried to $follow}" --actor "$fleet_actor" >/dev/null 2>&1; then
    worker_set_state "$wdir" settled "merged into $into and closed on $verdict${follow:+; findings carried to $follow}"
    say "$bead: CLOSED ($verdict)${follow:+, findings on $follow}"
    # THE ONLY REAP IN THIS FILE, AND IT IS HERE BECAUSE THIS IS THE ONLY PLACE
    # WHERE THE MERGE AND THE CLOSE HAVE BOTH SUCCEEDED. Every branch above this
    # one either left the bead in the queue for a fresh dispatch — which reuses
    # this worktree — or left it for a person, whose evidence it is. See
    # worker_reap_worktree() for the eight-site table and the measurement.
    # AFTER the close, never before: a reap before it would be a removal on
    # behalf of an outcome that had not happened yet.
    worker_reap_worktree "$wdir" "$bead"
    emit bead.closed "Fleet closed $bead on $shown${follow:+; findings carried to $follow}" \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"$verdict\",\"outcome\":\"$outcome\",\"followup\":\"${follow:-}\",\"worktree\":\"$reap_result\"}"
  else
    # Proofdelve ForgeOs-bzyk, second of the two merge-without-close paths. Same orphan,
    # same one-line remedy: stop claiming it is fleet work.
    escalate_labels "$bead"   # Proofdelve ForgeOs-s2lx: checked; the sentences below carry the truth
    worker_set_state "$wdir" needs-person "MERGED on $verdict but the close FAILED. $label_note"
    say "$bead: merged but the close FAILED — $label_note"
    emit incident "Fleet merged $bead but could not close it. It is in_progress, so it is absent from bd ready. $label_note." \
      -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"merged\":true,\"closed\":false,\"bd_exit\":$label_rc}"
  fi
}

# A DEAD REVIEW IS A REVIEW FAILURE AND IS NEVER CHARGED TO THE FORGE
# (Proofdelve ForgeOs-57xc). Every review failure used to go to return_to_ready, which
# reopens the bead for a fresh FORGE dispatch — so at the measured 17.2%
# no-verdict rate the likeliest overnight event was re-running IMPLEMENTATION
# over work that was already verifier-green, and after FLEET_MAX_RETURNS the
# bead lost `fleet-safe` on the REVIEW's account rather than its own. warden.sh
# prints "relaunch on the next rung" on exit 65 and the charter's Failover
# policy says the same: "Availability failure -> next rung ... relaunch on next
# rung". Nothing implemented it.
#
# SO THE LADDER IS EXPLICIT AND LIVES IN THE CONFIG. Rungs are tried in order;
# a rung that produces no recorded verdict is an availability failure and the
# next rung is tried. When the ladder is exhausted the bead is PAGED to the
# Overseer, never returned to the Forge — which is the charter's Warden ladder
# ending in "block and page Justin", and its "never retry a failing bead on a
# cheaper model".
#
# WHY FLEET_WARDEN_LADDER IS ONE RUNG TODAY, and it is a real constraint rather
# than a shortcut: the charter's second Warden rung is GPT-5.6 Sol, and
# fortkit-78o records that `gpt-5.6-sol` is not a model the review CLI can
# select. Encoding it would burn a launch slot on a session that dies at launch
# and arrive at the same page. Overseer's decision, 2026-09-04, with the
# alternatives on the record: page on the first no-verdict. When 78o lands, the
# whole fix is to add the rung to that one config line.
review_one() {  # $1 bead, $2 worktree
  local bead="$1" wt="$2"
  local sfx="${bead##*-}"
  local result="$warden_root/$sfx.log.result.json"
  local rung wrc recorded verdict wlog attempt=0 tried="" reviewed_tip=""

  for rung in $FLEET_WARDEN_LADDER; do
    # A STOPPING RUN SPENDS NO RUNG (Proofdelve ForgeOs-b26i; the Warden's finding 5 on
    # Proofdelve ForgeOs-dx34.1, latent while the ladder has one rung). The ke5u block
    # below honours a verdict that COMPLETED under SIGTERM and then falls
    # through to the ordinary handling; if that verdict's token will not parse,
    # the ordinary handling says `continue`, and with a second rung configured
    # the run -- already stopping -- launched another review. The same window
    # exists for a halt file that appeared during the previous rung. So the
    # loop head asks: a run that is stopping parks the worker at its review
    # (verifier-green already, the next run resumes here) and launches nothing.
    # Asked before the budget, because a rung not launched is not a rung spent.
    if stopping; then
      worker_set_state "$state/workers/$sfx" parked-review \
        "the run is stopping ($(signalled && printf 'SIG%s' "$stop_signal" || printf 'halt file present')) before ladder rung $((attempt + 1)) on $rung; verifier-green already, so the next run resumes at the review and no rung was spent (Proofdelve ForgeOs-b26i)"
      say "$bead: the run is stopping -- rung $((attempt + 1)) ($rung) is NOT launched; PARKED at its review for the next run (no rung spent, Proofdelve ForgeOs-b26i)"
      return 0
    fi
    # The budget is asked before the launch, and a bead that cannot be reviewed
    # for want of budget KEEPS ITS CLAIM and is reviewed by the next run. It is
    # not returned: the implementation is done and green, and returning it would
    # throw that away to buy nothing.
    if ! budget_left; then
      budget_stop "review of $bead"
      # Proofdelve ForgeOs-5p00, and Proofdelve ForgeOs-w7u5 replaces its remedy with a better one.
      # "The next run reviews it" is only true if the next run can still SEE it.
      # The old fix deleted the `done` marker so the worker would be reaped
      # again from the top — which worked, and cost a second full verifier run,
      # and left a state indistinguishable from a stranding. `parked-review`
      # says both things at once: the next run resumes HERE, at the review, and
      # a reader can tell at a glance that nothing is wrong.
      worker_set_state "$state/workers/${bead##*-}" parked-review \
        "verifier-green already; the launch budget ran out before its review, so the next run resumes at the review and re-runs neither the verifier nor a spent rung"
      say "$bead: verifier-green and PARKED FOR BUDGET before its review. That is healthy: the next run reviews it, and does not verify it again."
      return 0
    fi
    attempt=$((attempt + 1))
    tried="${tried:+$tried, }$rung"
    wlog="$state/logs/warden-$bead-$attempt.txt"
    rm -f "$result" "$warden_root/$sfx.log.err"   # the previous review's stderr goes with its result (g3n1 round two, finding 1)
    spend "warden $bead ($rung)"
    say "$bead: review starting on $rung, ladder rung $attempt (launch $launches/$FLEET_HARD_STOP)"
    emit review.pending "Fleet sent $bead to review on $rung (ladder rung $attempt)" \
      -a "$fleet_actor" -s fleet -t "$bead" \
      -p "{\"run\":\"$run_id\",\"model\":\"$rung\",\"rung\":$attempt}"
    # THE TIP SHE IS ABOUT TO REVIEW, CAPTURED BEFORE SHE LAUNCHES
    # (Proofdelve ForgeOs-yz7w, the Warden's 2.3). Her range is resolved by git when warden.sh
    # runs, so the branch she read is the branch as it stood AT THAT MOMENT.
    # The ESCALATE arm below used to re-resolve bead/$sfx after warden.sh had
    # returned AND after the bd write, which leaves a window -- small, and
    # reachable only by a hand, which is exactly the hand the reviewed-sha
    # check exists to catch (the lw8x remedy is a person merging main into a
    # bead branch). Recording the later tip as "the tip she reviewed" would
    # make a signed landing compare the approval against a change she never
    # saw, and the record would look right.
    # CAPTURED PER RUNG, INSIDE THE LOOP: the ladder can relaunch, and the
    # value that matters is the tip at the launch of the attempt that produced
    # the verdict. Empty stays empty -- a branch that cannot be resolved must
    # not write a file, because signed_landing_ready() reads an absent
    # reviewed-sha as "this question is not asked of this worker" and an empty
    # one would be a different, false answer.
    reviewed_tip="$(git -C "$root" rev-parse --verify --quiet "bead/$sfx" 2>/dev/null || echo "")"
    set +e
    # THREE DOTS (Proofdelve ForgeOs-hifw): the review range is main...bead/X, from the
    # merge base, so a sibling bead that landed first cannot render as a
    # deletion in the Warden's diff; the two-dot form compared the tips and did.
    # THE LIGHT RE-CHECK AFTER A FIX-FORWARD LAP (Proofdelve ForgeOs-6niaz part B): the
    # same launcher and ladder, briefed with the lap's base and its items.
    local ff_env=()
    if fix_forward_pending "$sfx"; then
      ff_env=("WARDEN_FIX_FORWARD_BASE=$(head -1 "$(fix_forward_dir "$sfx")/base")" "WARDEN_FIX_FORWARD_ITEMS=$(fix_forward_dir "$sfx")/brief")
    fi
    env "${ff_env[@]}" "$root/fort/scripts/warden.sh" "$bead" "$main_branch...bead/$sfx" "$wt" "$rung" > "$wlog" 2>&1 8>&-
    wrc=$?
    set -e
    # A BROKEN HOST IS CHECKED BEFORE THE GOVERNOR AND BEFORE THE LADDER
    # (Proofdelve ForgeOs-g3n1). A Warden that died of EDQUOT recorded no verdict, and
    # reading that as an availability failure spends the rung, then the next,
    # then pages a person over a review nobody could have finished. The worker
    # is parked at REVIEW first (verifier-green already; the next run resumes
    # here, Proofdelve ForgeOs-w7u5's parked-review) so the halt leaves nothing orphaned.
    # ASKED ONLY WHEN THE REVIEW PRODUCED NO RESULT FILE (the Warden, round one): a
    # recorded verdict is a review that ran, whatever its prose says, and $wlog
    # carries forty lines of that prose. The session's own stderr
    # ($warden_root/<sfx>.log.err) is read too: 7gag's line was warden.sh's own,
    # but an EDQUOT can also surface inside the session (finding 5).
    if [ ! -s "$result" ] && { looks_env_failure "$wlog" || looks_env_failure "$warden_root/$sfx.log.err"; }; then
      worker_set_state "$state/workers/$sfx" parked-review "verifier-green already; the host failed under its review (environmental, not the bead's), so the next run resumes at the review"
      if looks_env_failure "$wlog"; then env_halt_if "$wlog" "the review log for $bead ($wlog)"; else env_halt_if "$warden_root/$sfx.log.err" "the review session's stderr for $bead"; fi
    fi
    looks_rate_limited "$wlog" && governor_down "review log shows plan back-pressure"

    # Proofdelve ForgeOs-a2fx, AS CORRECTED BY Proofdelve ForgeOs-ke5u — the Warden's finding 1
    # on the covenant-4.5 review of the sitting that wrote the original branch.
    #
    # THE TWO SIGNAL POSTURES ARE NOT THE SAME, AND THIS USED TO COLLAPSE THEM.
    #   Ctrl-C, ATTENDED. The signal reaches the whole foreground process group,
    #     so the warden.sh this run was waiting on dies with it and writes no
    #     result file. Nothing was reviewed. Reading the absent result as an
    #     availability failure would advance the ladder and an exhausted ladder
    #     PAGES THE OVERSEER over a review nobody was allowed to finish.
    #   kill -TERM, DETACHED — THE SHARP ONE. TERM goes to THIS process alone,
    #     and bash defers a trap until the foreground command returns, so THE
    #     REVIEW RUNS TO COMPLETION, records its verdict on the bead and emits
    #     review.verdict. The original branch was asked BEFORE the result file
    #     was looked at — deliberately — so it discarded a real verdict, spent
    #     the rung, and printed "No verdict is recorded", which is FALSE in that
    #     posture. The fleet's own narrative contradicted the bead's record. And
    #     it is the posture this file's own header tells operators to use.
    #
    # SO THE RESULT FILE IS READ FIRST AND INTERPRETED SECOND, in three outcomes
    # rather than one (Proofdelve ForgeOs-8zb7): a verdict that exists, a result file that
    # exists and will not parse, and no result file at all.
    #
    # EITHER WAY THE WORKER IS GIVEN A RESUME POINT. Returning while it is still
    # `in-hand` left it belonging to a run that has ended, which the next run
    # reads as ORPHANED and hands to a person — while the interrupting run's own
    # leftovers report said "No action". Two records of one worker, disagreeing.
    if signalled; then
      if [ ! -s "$result" ]; then
        worker_set_state "$state/workers/$sfx" parked-review \
          "its review was stopped by SIG$stop_signal before warden.sh recorded anything; it is already verifier-green, so the next run resumes at the review"
        say "$bead: its review was STOPPED by SIG$stop_signal and recorded nothing — that is not a failure and not an approval."
        say "  No verdict exists, the ladder is NOT advanced, the bead keeps its claim, and the next run RESUMES AT THE REVIEW without re-running the verifier."
        return 0
      fi
      recorded="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verdict_recorded"))' "$result" 2>/dev/null)" || recorded=""
      verdict="$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("verdict"); print(v if v else "")' "$result" 2>/dev/null)" || verdict=""
      if [ "$recorded" != "True" ] || [ -z "$verdict" ]; then
        # A RESULT FILE THAT WILL NOT PARSE IS A THIRD THING and must never be
        # reported as either of the other two. It is not "no review happened"
        # (something wrote that file) and it is certainly not an approval.
        worker_set_state "$state/workers/$sfx" parked-review \
          "SIG$stop_signal arrived and $result exists but records no usable verdict (recorded='$recorded', verdict='$verdict'); the next run resumes at the review"
        say "$bead: SIG$stop_signal arrived and $result EXISTS but records no usable verdict (recorded='$recorded', verdict='$verdict')."
        say "  That is neither a killed review nor an approval. The ladder is NOT advanced, the bead keeps its claim, and the next run resumes at the review."
        return 0
      fi
      say "$bead: SIG$stop_signal arrived, and its review COMPLETED FIRST and recorded $verdict."
      say "  The verdict is HONOURED and not discarded: this run is stopping, so it will be acted on exactly as any other, and a merge it reaches will park rather than land."
      # and fall through to the same handling every completed review gets.
    fi

    # FAIL CLOSED ON THE RESULT FILE. warden.sh writes it on every path it
    # survives; its absence means the launcher died, which is not an approval.
    if [ ! -s "$result" ]; then
      say "$bead: rung $rung produced NO result file at $result (warden.sh exit $wrc) — no review happened"
      continue
    fi
    recorded="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verdict_recorded"))' "$result" 2>/dev/null)" || recorded=""
    verdict="$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("verdict"); print(v if v else "")' "$result" 2>/dev/null)" || verdict=""

    if [ "$recorded" != "True" ]; then
      say "$bead: rung $rung recorded NO verdict (warden.sh exit $wrc). An absent verdict is never an approval."
      continue
    fi
    # MERGE-PARENT-OPEN GOES TO land() LIKE THE OTHER TWO (Proofdelve ForgeOs-j3kp): the
    # diff is merged, the post-merge verifier runs, a follow-up is filed. What
    # differs is the LAST step in land(), not the route to it. The set is named
    # once, in verdict_is_landable(), so this site and the deferred-merge resume
    # cannot disagree about it again.
    # A RECORDED VERDICT ENDS A PENDING FIX-FORWARD LAP, whatever it says
    # (Proofdelve ForgeOs-6niaz part B): the re-check has happened. FIX-FORWARD itself is
    # never landable as stored; fix_forward() queues the one lap or reads it
    # as APPROVE-WITH-FINDINGS, and says which.
    fix_forward_recheck_done "$sfx"
    if [ "$verdict" = FIX-FORWARD ]; then
      fix_forward "$bead" "$wt" "$warden_root/$sfx.log.record" "$reviewed_tip"; return 0
    fi
    if verdict_is_landable "$verdict"; then
      land "$bead" "$verdict" "$warden_root/$sfx.log.record" "$reviewed_tip"; return 0
    fi
    case "$verdict" in
      REQUEST-CHANGES)
        # The ONE verdict that is genuinely the Forge's to answer.
        worker_set_state "$state/workers/$sfx" settled "REQUEST-CHANGES: the bead went back to the queue and a fresh dispatch gets a fresh worker"
        return_to_ready "$bead" "Warden verdict REQUEST-CHANGES. Her full review is on this bead above, posted under her own actor id." ""
        return 0 ;;
      *)
        # A recorded review whose token will not parse is a REVIEW-side defect,
        # not an implementation one, so it takes the ladder like any other
        # review failure rather than re-running the Forge over green work.
        if [ "$verdict" = "ESCALATE" ]; then break; fi
        say "$bead: rung $rung recorded a verdict whose token could not be parsed ('$verdict'); no mechanism may act on it"
        continue ;;
    esac
  done

  if [ "${verdict:-}" != "ESCALATE" ]; then
    worker_set_state "$state/workers/$sfx" needs-person "the review ladder was exhausted with no recorded verdict; the work is verifier-green in its worktree and the Overseer was paged"
    page_overseer "$bead" "the review ladder is exhausted after $attempt attempt(s) on: $tried. Every rung failed to record a verdict, so NO review has happened and an absent verdict is never an approval. This bead is verifier-green in $wt and was NOT returned to the Forge: re-running implementation over reviewed-green work would charge a review failure to the Forge (Proofdelve ForgeOs-57xc). Relaunch the review by hand, or add a rung to FLEET_WARDEN_LADDER." "${wlog:-}"
    return 0
  fi
  case "$verdict" in
    ESCALATE)
      # ESCALATE in this fort means a human gate — auth surface, data-mutating
      # migrations, deal visibility, the constitution. That is the Overseer's
      # queue and this fort's signal for it is the `human` label.
      # THE WRITE IS CHECKED, AND THE EVENT REPORTS WHAT HAPPENED (Proofdelve ForgeOs-s2lx,
      # The Warden's finding 5 on the sitting-three docket). This used to
      # be `|| true` followed by an UNCONDITIONAL fleet.returned saying
      # "fleet-safe removed, human label applied": had the write been refused,
      # the durable record would have said the bead left the fleet when it had
      # not, and the Keep's needs-you column, which reads `human`, would never
      # have shown it. Same shape as Proofdelve ForgeOs-stpx's parent-open repair, applied
      # to the one site whose EVENT asserted the label.
      local erc=0
      bd -C "$root" update "$bead" --remove-label fleet-safe --add-label human \
         --status open --assignee "$(overseer_assignee)" --actor "$fleet_actor" >/dev/null 2>&1 || erc=$?
      # His board is the assignee (Proofdelve ForgeOs-29j3g); the ASK line says what for.
      if [ "$erc" -eq 0 ]; then
        ask_overseer "$bead" sign "the Warden returned ESCALATE (a human gate); Approve on the Keep lands the reviewed change, Decline sends it to the Mayor" \
          || say "$bead: the ASK line could not be posted; it is assigned to $(overseer_assignee) without one"
      fi
      # THE VERDICT IS STORED IN THE WORKER RECORD, as land() stores a landable
      # one (Proofdelve ForgeOs-ubgx): it is the first thing signed_landing_ready() asks
      # before landing this bead on the Overseer's signature without a second
      # lap. An escalation that predates this line has no stored verdict and
      # takes today's full lap once, recording it on the way out.
      printf '%s\n' "ESCALATE" > "$state/workers/$sfx/verdict" 2>/dev/null || true
      # A REAL ESCALATE SUPERSEDES ANY HELD TOKEN (Proofdelve ForgeOs-vee4w round two,
      # The Warden's finding 3): a held bead re-reviewed after a patch-changing
      # refresh must not land later on the earlier review's token and record.
      rm -f "$state/workers/$sfx/warden-verdict" "$state/workers/$sfx/warden-record" 2>/dev/null || true
      # AND THE TIP SHE REVIEWED (the Warden, 1.2): the pin the Keep records is the
      # tip at SIGNING, and between the escalation and the click a hand can
      # move the branch (the lw8x remedy is a hand merge of main into it). A
      # signed landing also requires the approved change to equal the REVIEWED
      # change by patch-id, so what lands is what was reviewed and what was
      # signed, not merely the latter.
      # WRITTEN FROM THE VALUE CAPTURED BEFORE THE LAUNCH (Proofdelve ForgeOs-yz7w, the Warden's
      # 2.3), not re-resolved here: this line runs after warden.sh returned and
      # after the bd write above, and the branch can move in between.
      if [ -n "$reviewed_tip" ]; then
        printf '%s\n' "$reviewed_tip" > "$state/workers/$sfx/reviewed-sha" 2>/dev/null || true
      fi
      if [ "$erc" -ne 0 ]; then
        # NOT on the Overseer's queue, whatever the verdict says: the label that
        # puts it there was never written. needs-person, because a bead that is
        # claimed, in_progress and possibly still fleet-safe is invisible to
        # every queue a person reads unless this record says so.
        worker_set_state "$state/workers/$sfx" needs-person "ESCALATE recorded, and the bd write that removes fleet-safe and applies human FAILED (exit $erc): the bead is still claimed, still in_progress and may still carry fleet-safe, so it is NOT on the Overseer's queue and its tracker state does not match the review"
        say "$bead: ESCALATE, and the bd write that puts it on the Overseer's queue FAILED (exit $erc) — the bead is still claimed and may still be fleet-safe; NOT returned, NOT on his queue"
        emit incident "Fleet recorded ESCALATE on $bead but could NOT remove fleet-safe and apply human: the bd write failed (exit $erc). The bead is still claimed, in_progress and may still carry fleet-safe, so it is NOT on the Overseer's queue and no fleet.returned was emitted for it; its tracker state does not match the review." \
          -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"ESCALATE\",\"bd_exit\":$erc,\"returned\":false}"
        return 0
      fi
      # SETTLED RATHER THAN needs-person, DELIBERATELY. The bead is on the
      # Overseer's board -- assigned to him with an ASK line since Proofdelve ForgeOs-29j3g,
      # the `human` label kept as history -- which is a place a person already
      # looks; it is not lost. needs-person is reserved for work that
      # is invisible unless this file says so.
      worker_set_state "$state/workers/$sfx" settled "ESCALATE: removed from the fleet and assigned to the Overseer ($(overseer_assignee)) with an ASK line"
      say "$bead: ESCALATE — removed from the fleet and put on the Overseer's queue"
      emit fleet.returned "$bead escalated by review to the Overseer; fleet-safe removed, human label applied; assigned to $(overseer_assignee) with an ASK line (Proofdelve ForgeOs-29j3g)" \
        -a "$fleet_actor" -s fleet -t "$bead" -p "{\"run\":\"$run_id\",\"verdict\":\"ESCALATE\"}" ;;
  esac
}

# ---------------------------------------------------------------------------
# LANDABILITY BEFORE THE REVIEW, REFRESH BEFORE THE VERIFY (Proofdelve ForgeOs-36b9,
# Regent edict 2026-09-14, Overseer present).
# ---------------------------------------------------------------------------
# THE ORDER WAS Forge -> host verify -> Warden -> `git merge --no-ff` into main,
# and a conflict with a main that had moved was discovered LAST, after the
# scarce launch (FLEET_WARDEN_CONC=1) was spent. 2026-09-13 14:59:
# Proofdelve ForgeOs-o6ky.13 was verified and reviewed on a branch that could not land.
#
# NOW, after the Forge and before the host verify:
#   1. If main is already contained in bead/<sfx>, nothing to do (`current`).
#   2. Otherwise `git merge-tree --write-tree --name-only main bead/<sfx>`
#      (the --write-tree form REPORTS conflicts; the three-argument form does
#      not, measured 2026-09-13). CONFLICT: the bead is PAGED with the
#      conflicting paths in the reason, its state is needs-person, and NO
#      verifier and NO Warden run. CLEAN: main is merged INTO the branch, in
#      the bead's own worktree, so the tree that is verified and reviewed is
#      the tree that will land, and the Warden's main...bead/<sfx> diff is the
#      bead's own work and nothing else (which also retires the sibling-lands-
#      first false-red shape, Proofdelve ForgeOs-hifw). The verify.run payload's commit
#      is the POST-refresh sha for free: the merge commit exists before
#      run_verifier() is called, and verify-impl.sh reads HEAD at run time.
#
# PAGED, NOT RETURNED, AND THE DEPARTURE FROM THE DOCKET'S LETTER IS
# DELIBERATE. The docket said "return the bead". Traced through the files: a
# returned bead is re-dispatched next pass, forge.sh reuses the worktree,
# refresh_reused_worktree() (forge.sh, Proofdelve ForgeOs-lw8x) meets the SAME conflict,
# exits 76, and reap_pass pages a person -- after spending a return counter
# tick, a launch from the hard stop, and a pass, and with a message that no
# longer names the paths. "A conflict is a person's merge to make" is lw8x's
# own rule; paging here reaches the same end state one pass sooner, cheaper,
# and with the conflicting paths in the record. The fleet never hand-assembles
# a branch whose refresh conflicts (the docket's must-not-change): on conflict
# NOTHING is merged anywhere.
#
# THE REFRESH MERGE IS forge.sh's refresh_reused_worktree(), BY THE BODY: HEAD
# must be on bead/<sfx>; a MERGE_HEAD already present is not ours to conclude
# or abort; on a failed merge, abort what we started and PROVE the back-out
# (HEAD unchanged, no MERGE_HEAD) before saying the tree is untouched. Any
# refusal here is paged for the same reason a conflict is.
#
# WHAT DOES NOT CHANGE: the deferred-merge retry (the land arm) is the merge
# alone and is not refreshed -- it was verified and reviewed on what it has;
# a parked-review resume skips the verifier by design and so skips this too;
# merge-slot semantics are untouched (this touches the bead's worktree, never
# main). Sets prelanding_result: current | refreshed | conflict | refused |
# unchecked. `unchecked` is git itself failing to answer merge-tree; it is
# said loudly and the pass proceeds in the OLD order, which is no worse than
# every run before this function existed.
prelanding_result=""
# $5 = "check" ASKS WITHOUT REFRESHING (the Warden, review of 823074e, finding 3):
# the parked-review resume was verified green on its own tip on an earlier
# run, so a refresh there would invalidate that green -- but a merge-tree
# check costs no launch, and main moving during the park could still spend
# the scarce review on a branch that cannot land. In check mode a clean
# answer is `unrefreshed` and the review proceeds on the tree that was
# verified; a conflict is paged exactly as on the verify path.
# WHO HOLDS THE CLAIM, for the pages below (the Warden, 1.7 on the 2026-09-17
# sitting): a dispatch claims for the Forge actor, a signed landing
# (signed_landing()) for the fleet actor, and the page's closing sentence used
# to say "the Forge actor" for both.
# A PARAMETER, NOT A TOP-LEVEL VARIABLE SET AND RESET AROUND ONE CALL
# (Proofdelve ForgeOs-ubgx.3 item 2.4, the Warden's own suggestion). The first shape was
# `prelanding_claimant=...` before the call and back to the default after it,
# and it cost a round on the fold: the governor harness extracts this function
# WITHOUT the top-level assignment and runs it under set -u, so a bare
# reference killed twelve of its cases. A default expansion patched that
# symptom; the shape was still a global whose correctness depended on one
# caller remembering to put it back. It is now $6, with the same default in
# the same place as $5's, so the value travels with the call and there is
# nothing to reset and nothing for an extracting harness to miss.
prelanding_refresh() {  # $1 bead, $2 sfx, $3 worktree, $4 worker dir, [$5 check], [$6 claimant]
  local bead="$1" sfx="$2" wt="$3" d="$4" mode="${5:-refresh}" br="bead/$2" out mrc before after paths cur errf
  local claimant="${6:-the Forge actor}"
  prelanding_result=""
  # THE WORKTREE IS INSPECTED FIRST, ON EVERY PATH (Proofdelve ForgeOs-tvb2; the Warden's finding
  # 4 on 823074e). These two refusals used to sit below the `current` and
  # `check` returns, so they guarded only the path that WRITES: a worktree
  # detached or mid-merge whose branch already contained main went to the
  # verifier as before, and the tree verified was not bead/X. Hoisted, the
  # sentence "the tree that is verified is the tree that will land" holds on
  # every path. A directory that is not a git worktree at all (or does not
  # exist) has no HEAD to read and REFUSES the same way: the verifier could not
  # be scoring bead/X there, and a person should look. The wording follows the
  # mode, because a parked-review worker WAS verified green on an earlier run.
  local before_stage="before verifying it" stands_wt="The work stands in its worktree UNVERIFIED and UNREVIEWED; nothing was spent on it."
  if [ "$mode" = check ]; then before_stage="before reviewing it"; stands_wt="The work stands in its worktree, VERIFIED GREEN on an earlier run and NOT REVIEWED; no review launch was spent on it."; fi
  local where
  if ! git -C "$wt" rev-parse --git-dir >/dev/null 2>&1; then
    where="not a git worktree at all"
  else
    cur="$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")"
    where="${cur:-a detached HEAD}"
  fi
  if [ "$where" != "$br" ]; then
    prelanding_result=refused
    worker_set_state "$d" needs-person "landing check refused: $wt is on '$where', not $br; a person must look before anything dispatches into it (Proofdelve ForgeOs-36b9, Proofdelve ForgeOs-tvb2)"
    say "$bead: REFUSED to proceed with $wt -- HEAD is on '$where', not $br; PAGING a person"
    page_overseer "$bead" "the fleet would not act on bead/$sfx $before_stage: the worktree $wt is on '$where', not $br, so the tree it would verify or review is not the branch that would land. Nothing was changed there. A person must look before anyone dispatches into it (Proofdelve ForgeOs-36b9, Proofdelve ForgeOs-tvb2)." "" "$stands_wt The bead is still claimed by $claimant."
    return 0
  fi
  if git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    prelanding_result=refused
    worker_set_state "$d" needs-person "landing check refused: a merge is already in progress in $wt (MERGE_HEAD present) and it is not the fleet's to conclude or abort (Proofdelve ForgeOs-36b9, Proofdelve ForgeOs-tvb2)"
    say "$bead: REFUSED to proceed with $wt -- a merge is already in progress there (MERGE_HEAD present); PAGING a person"
    page_overseer "$bead" "the fleet would not act on bead/$sfx $before_stage: a merge is already in progress in $wt (MERGE_HEAD present) and it is not the fleet's to conclude or abort. Nothing was touched. A person must resolve or abort it (Proofdelve ForgeOs-36b9, Proofdelve ForgeOs-tvb2)." "" "$stands_wt The bead is still claimed by $claimant."
    return 0
  fi
  if git -C "$root" merge-base --is-ancestor "$main_branch" "$br" 2>/dev/null; then
    prelanding_result=current; return 0
  fi
  mrc=0
  # STDERR APART FROM STDOUT (finding 5): a git warning printed first would
  # otherwise sit on line 1 and demote a real conflict to `unchecked`.
  errf="$state/logs/merge-tree-err-$bead.txt"
  out="$(git -C "$root" merge-tree --write-tree --name-only "$main_branch" "$br" 2>"$errf")" || mrc=$?
  # EXIT 1 IS TWO THINGS, MEASURED ON git 2.54: a conflict (line 1 is the
  # 40-hex oid of the merged tree, then one conflicted path per line up to a
  # blank line) and an unmergeable ref ("merge-tree: X - not something we can
  # merge", no oid). Reading the second as a conflict would page a person over
  # a missing branch with "conflicts on: <unnamed>"; it is git failing to
  # answer, so it is `unchecked` and the pass proceeds in the old order.
  if [ "$mrc" -eq 1 ] && printf '%s\n' "$out" | head -1 | grep -qE '^[0-9a-f]{40}'; then
    paths="$(printf '%s\n' "$out" | sed -n '2,/^$/p' | sed '/^$/d' | tr '\n' ' ')"
    printf '%s\n' "$out" > "$state/logs/conflict-$bead.txt"; rm -f "$errf"
    prelanding_result=conflict
    # WORDED PER MODE (the Warden, round two, finding 2): a parked-review worker WAS
    # verified green on an earlier run; saying "unverified" of it would be a
    # false record, understated in the safe direction but false.
    local done_so_far="not verified, not reviewed" stands="The Forge's work stands in its worktree UNVERIFIED and UNREVIEWED: nothing was spent on it and nothing was recorded against it." spent="the verifier or a review launch"
    if [ "$mode" = check ]; then
      done_so_far="verifier-green on an earlier run, NOT reviewed"; spent="a review launch"
      stands="The Forge's work stands in its worktree, VERIFIED GREEN on an earlier run and NOT REVIEWED: no review launch was spent on it and nothing was recorded against it."
    fi
    worker_set_state "$d" needs-person "$br conflicts with $main_branch (which moved after the branch was cut) on: ${paths:-<unnamed>}; $done_so_far, nothing merged (Proofdelve ForgeOs-36b9)"
    say "$bead: $br CONFLICTS with $main_branch on ${paths:-<unnamed>} -- found BEFORE spending $spent; PAGING a person (Proofdelve ForgeOs-36b9)"
    page_overseer "$bead" "bead/$sfx cannot land: $main_branch moved after the branch was cut and \`git merge-tree --write-tree $main_branch bead/$sfx\` reports conflicts on: ${paths:-<unnamed>}. The fleet checked this BEFORE spending $spent (Proofdelve ForgeOs-36b9), and it merged nothing. Re-dispatching would meet the same conflict in forge.sh's refresh and page again (Proofdelve ForgeOs-lw8x). Merge $main_branch into bead/$sfx by hand and re-queue it, or remove the worktree AND the branch so the next dispatch cuts fresh. merge-tree's own output is in the evidence below." "$state/logs/conflict-$bead.txt" "$stands The bead is still claimed by $claimant."
    return 0
  fi
  if [ "$mrc" -ne 0 ]; then
    prelanding_result=unchecked
    warn "$bead: \`git merge-tree --write-tree\` could not answer (exit $mrc): $(head -1 "$errf" 2>/dev/null || printf '%s' "$out" | head -1). Landability is UNCHECKED and the pass proceeds in the old order (verify, review, discover at the merge)."
    say "$bead: landability could not be checked before review (merge-tree exit $mrc); proceeding in the old order"
    return 0
  fi
  rm -f "$errf"
  if [ "$mode" = check ]; then
    prelanding_result=unrefreshed
    say "$bead: $main_branch moved since the branch was cut and merges CLEANLY (merge-tree); not refreshed here because this tree was already verified green -- the review proceeds on it (Proofdelve ForgeOs-36b9)"
    return 0
  fi
  # CLEAN. Merge main into the branch, in the bead's own worktree (HEAD and
  # MERGE_HEAD were inspected at the top; Proofdelve ForgeOs-tvb2).
  before="$(git -C "$wt" rev-parse HEAD)"
  mrc=0
  out="$(git -C "$wt" merge --no-edit -m "$bead: refresh — merge $main_branch into $br before verify (Proofdelve ForgeOs-36b9, by fleet.sh)" "$main_branch" 2>&1)" || mrc=$?
  if [ "$mrc" -eq 0 ]; then
    after="$(git -C "$wt" rev-parse HEAD)"
    prelanding_result=refreshed
    say "$bead: refreshed $wt from $main_branch: ${before:0:12} -> ${after:0:12}; the verifier and the review see the tree that will land (Proofdelve ForgeOs-36b9)"
    return 0
  fi
  # merge-tree said clean and the real merge did not: an uncommitted tracked
  # file the merge would overwrite is the likely shape. Back out and PROVE it.
  if git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    git -C "$wt" merge --abort >/dev/null 2>&1 || true
  fi
  printf '%s\n' "$out" > "$state/logs/refresh-$bead.txt"
  prelanding_result=refused
  if [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$before" ] || git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    worker_set_state "$d" needs-person "refresh of $wt from $main_branch failed (git merge exit $mrc) AND THE BACK-OUT COULD NOT BE PROVEN: HEAD was ${before:0:12} and the tree may be mid-merge (Proofdelve ForgeOs-36b9)"
    say "$bead: refresh from $main_branch FAILED (exit $mrc) and the back-out could NOT be proven -- $wt may be mid-merge; PAGING a person"
    page_overseer "$bead" "the fleet tried to refresh bead/$sfx from $main_branch before verifying it (merge-tree reported no conflict), \`git merge\` failed with exit $mrc, and the back-out could NOT be proven: HEAD was $before and $wt may be mid-merge. Do not dispatch into it until a person has looked (Proofdelve ForgeOs-36b9). git's own words are in the evidence below." "$state/logs/refresh-$bead.txt" "The worktree may be MID-MERGE. Nothing was verified or reviewed; the bead is still claimed by $claimant."
    return 0
  fi
  worker_set_state "$d" needs-person "refresh of $wt from $main_branch failed (git merge exit $mrc); the worktree is unchanged at ${before:0:12} and a person must make this merge (Proofdelve ForgeOs-36b9)"
  say "$bead: refresh from $main_branch FAILED (exit $mrc) though merge-tree saw no conflict; $wt is UNCHANGED at ${before:0:12}; PAGING a person"
  page_overseer "$bead" "the fleet tried to refresh bead/$sfx from $main_branch before verifying it: merge-tree reported no conflict but \`git merge\` in $wt failed with exit $mrc (an uncommitted tracked file the merge would overwrite is the usual shape). The worktree is UNCHANGED at $before. Make the merge by hand and re-queue it (Proofdelve ForgeOs-36b9). git's own words are in the evidence below." "$state/logs/refresh-$bead.txt" "The work stands in its worktree UNVERIFIED and UNREVIEWED; nothing was spent on it. The bead is still claimed by $claimant."
  return 0
}

# THE ORDER THE COMPLETION LANE TAKES WORKERS IN (Proofdelve ForgeOs-jfqu4.7).
# reap_pass used to walk "$state/workers"/*/ -- alphabetical by worker
# directory name -- so a P1 deploy blocker named 2md9d.3.16 waited behind a P4
# named 2md9d.1.36 because "1" sorts before "3" (measured 2026-10-16, and again
# 2026-10-20 on a P0 refactor lap). The order is now, in three tiers:
#   0. A worker that resumes at `land` (deferred-merge) or `signed`
#      (parked-signed). Either costs a merge, never a Forge launch or a review,
#      and the Mayor measured a signed, verifier-green deferred merge waiting
#      ~45 minutes behind two full verify-and-review slots (Proofdelve ForgeOs-8sd4n,
#      2026-10-21 12:2x). Oldest first. THIS IS A CHANGE TO TODAY'S RULE, made
#      at the Overseer's ask on the docket: until now a deferred merge had no
#      precedence at all and waited for its glob position.
#   1. Every other reapable worker by bead PRIORITY, lower number first.
#   2. Within one priority, by FINISH TIME, oldest first: the mtime of the
#      worker's exit file (the Forge's own end), else of its state file (when
#      it was last set aside).
# PRIORITY COMES FROM bd, in one `bd show ... --json` for every reapable bead,
# asked again after each worker reap_pass takes (Proofdelve ForgeOs-4bzvk, below). If bd
# cannot answer, the lane does NOT stop: every worker is ordered by finish time
# alone and the pass says so once (a flag file the main loop clears at the top
# of each pass: this runs inside $( ), so a variable could not remember it). A bead bd
# answers for without a priority sorts after every bead that has one.
# Prints one worker directory per line; directory names never carry spaces
# (they are bead suffixes).
reap_order() {
  local d bead ft tier ids="" prio_out="" rows="" line prio
  local -A prio_of=()
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    worker_reapable "$d" || continue
    bead="$(cat "$d/bead" 2>/dev/null || echo "")"
    [ -n "$bead" ] && ids="$ids $bead"
  done
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086 # word splitting of the id list is the point
    if prio_out="$(bd -C "$root" show $ids --json 2>/dev/null | jq -r 'if type == "array" then .[] else . end | select(. != null) | select(.id != null) | "\(.id) \(.priority // 99)"' 2>/dev/null)" && [ -n "$prio_out" ]; then
      while read -r bead prio; do
        [ -n "$bead" ] && prio_of["$bead"]="$prio"
      done <<< "$prio_out"
    elif [ ! -e "$state/.reap-order-warned" ]; then
      say "reap order: bd could not report bead priorities this pass; taking finished workers in finish-time order instead (Proofdelve ForgeOs-jfqu4.7)"
      : > "$state/.reap-order-warned" 2>/dev/null || true
    fi
  fi
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    worker_reapable "$d" || continue
    bead="$(cat "$d/bead" 2>/dev/null || echo "")"
    ft="$(stat -c %Y "$d/exit" 2>/dev/null || stat -c %Y "$d/state" 2>/dev/null || stat -c %Y "$d" 2>/dev/null || echo 0)"
    # TIERS: 0 a merge or a signed landing (no review to spend); 1 a
    # Workbench review-only branch (Proofdelve ForgeOs-9srgz: "one Warden launch at the
    # front of the reap order"); 2 every ordinary completion, by priority.
    case "$(worker_resume_at "$d")" in
      land|signed) tier=0; prio=0 ;;
      *)           tier=2; prio="${prio_of[$bead]:-99}"
                   if worker_review_only "$d"; then tier=1; prio=0; fi ;;
    esac
    case "$prio" in ''|*[!0-9]*) prio=99 ;; esac
    rows="$rows$tier $prio $ft $d"$'\n'
  done
  [ -n "$rows" ] || return 0
  printf '%s' "$rows" | sort -k1,1n -k2,2n -k3,3n -k4,4 | while read -r _ _ _ line; do printf '%s\n' "$line"; done
}

# WHAT IS REAPABLE IS THE LIFECYCLE OWNER'S ANSWER, AND SO IS WHERE TO RESUME.
# This loop no longer tests for files. It asks worker_reapable() whether to
# take a worker and worker_resume_at() where to pick it up, so a worker parked
# before its review is not verified a second time and does not spend a second
# review launch — the objection that kept Proofdelve ForgeOs-usz6 from being a one-liner.
reap_pass() {
  local d c sfx bead wt vout resume frc taken=" "
  local key full_taken=0 reap_cap="${FLEET_REAP_PER_PASS:-2}"
  case "$reap_cap" in ''|*[!0-9]*|0) reap_cap=2 ;; esac
  # ORDERED, NOT GLOBBED (Proofdelve ForgeOs-jfqu4.7): see reap_order() above. AND
  # RE-ASKED AFTER EVERY WORKER (Proofdelve ForgeOs-4bzvk, Regent docket 2026-10-22 item
  # D): the order was computed ONCE at the top of the pass and the snapshot
  # walked, 10-20 minutes per worker (verify and review), so a worker that
  # finished DURING the pass was not in it whatever its priority. Measured
  # 2026-10-22: P0 413u8.50 exited 00:45 and was passed over by a P1, a P2 and
  # a P3 from a ~00:33 snapshot. Now the head of a fresh order is taken each
  # time, skipping a worker already taken this pass (a merge that defers stays
  # reapable, and must not be retried in a loop), so a high-priority finisher
  # waits at most for the one completion in flight.
  #
  # TAKEN IS KEYED BY THE LAUNCH, NOT THE DIRECTORY (Proofdelve ForgeOs-w5xkw, Regent
  # docket 2026-10-27 item B). A bead returned and re-dispatched inside one pass
  # reuses its worker directory, so a directory key made its SECOND finish
  # invisible until the run ended (P0 mn9y3.4.1, skipped twice on 10-26). The
  # key is the directory plus its `started` stamp, which every dispatch
  # rewrites (rm -rf, then `date -Is > started`): a re-dispatch is a new entry.
  # A merge that defers keeps both, so it is still taken once per pass.
  #
  # AND THE PASS IS BOUNDED (Proofdelve ForgeOs-bzr1z). Since 4bzvk the order is re-asked
  # after every worker, and refills keep Forges finishing, so in a busy run the
  # pass never ended: phase 1 (signed landings) runs only at the TOP of a pass
  # and a merge deferred inside the pass is in `taken`, so both starved for
  # hours (297ul 3 h, 5.11.1 65 min on 10-23; three signatures on 10-27). The
  # pass now ends after FLEET_REAP_PER_PASS workers that resume at the verifier
  # or the review (default 2, the Overseer's choice at the sitting). A resume
  # at `land` or `signed` (tier 0: a merge, no review) does not count and is
  # still taken after the cap, so it is never the thing the cap delays. A pass
  # that ends this way says so, and the next pass starts with phase 1.
  while :; do
    stopping && break
    d=""
    for c in $(reap_order); do
      key="$c@$(cat "$c/started" 2>/dev/null || echo -)"
      case "$taken" in *" $key "*) continue ;; esac
      d="$c"; break
    done
    [ -n "$d" ] || break
    [ -d "$d" ] || { taken="$taken$key "; continue; }
    worker_reapable "$d" || { taken="$taken$key "; continue; }
    case "$(worker_resume_at "$d")" in
      land|signed) ;;
      *)
        if [ "$full_taken" -ge "$reap_cap" ]; then
          say "reap pass ends after $full_taken verify-or-review completion(s) (FLEET_REAP_PER_PASS=$reap_cap); $(basename "$d") and any others wait for the next pass, which lands signed beads first (Proofdelve ForgeOs-bzr1z)"
          break
        fi
        full_taken=$((full_taken + 1)) ;;
    esac
    taken="$taken$key "
    # A REAPABLE WORKER FOUND IS PROVISIONALLY A PASS THAT CHANGED STATE, AND
    # THE ONE CASE THAT IS NOT IS BACKED OUT IN THE land ARM BELOW (Proofdelve ForgeOs-dx34.11,
    # The Warden's dx34.9 finding 2, shape (a)). A merge that defers FOREVER is reapable
    # on every pass, so counting reapable-found alone reset the stall counter each
    # pass and a parked merge spun until a person stopped it. Every reapable branch
    # here writes a NEW state token (settled, needs-person, parked-review, finished)
    # or a changed defer reason -- real progress -- EXCEPT a worker that entered
    # this reap already `deferred-merge` and leaves still `deferred-merge` on the
    # SAME reason. That single case subtracts its own count in the land arm below,
    # so the counter then means what the halt message already claims -- "passes
    # changed no state". A deferral whose reason CHANGES, or a resume to any other
    # state, still counts as activity, so the detector never fires on a merge
    # making progress toward landing. This is NOT usz6's rejected deferral
    # threshold: it is dx34.9's own "changed no state" predicate applied to the
    # reap counter, and the fingerprint is the defer-reason FILE (the why), not the
    # state reason, which carries an incrementing "deferral N" that changes every
    # pass.
    local pre_state pre_defer_reason="" pre_seen=""
    pre_state="$(worker_state "$d")"
    if [ "$pre_state" = deferred-merge ]; then
      pre_defer_reason="$(cat "$d/defer-reason" 2>/dev/null || echo "")"
      pre_seen="$(cat "$d/defer-reasons-seen" 2>/dev/null || echo "")"
    fi
    pass_reaped=$((${pass_reaped:-0} + 1))
    sfx="$(basename "$d")"
    bead="$(cat "$d/bead" 2>/dev/null || echo "")"
    if [ -z "$bead" ]; then
      worker_set_state "$d" needs-person "the worker directory carries no bead file, so nothing can be resumed from it"
      say "$sfx: worker directory carries no bead id — marked NEEDS A PERSON, not silently skipped"
      continue
    fi
    wt="$root-worktrees/$sfx"
    resume="$(worker_resume_at "$d")"

    # ASKED BEFORE THE WORKER IS TAKEN IN HAND, DELIBERATELY (Proofdelve ForgeOs-feeq).
    # Reaping is free but the review at the end of it is not, and a worker set
    # aside whose review never ran is a bead claimed, in_progress and absent
    # from every queue. The state written here is what makes that outcome
    # HEALTHY AND LEGIBLE rather than merely harmless: `parked-budget` says in
    # one word that the next run resumes it and no one need investigate.
    # THE BUDGET GATES LAUNCHES, AND A DEFERRED MERGE SPENDS NONE (Proofdelve ForgeOs-usz6).
    # Retrying a merge costs a git operation and a post-merge verifier run, not
    # a seat launch, and finishing a bead that is already reviewed and green is
    # the cheapest good outcome available to an exhausted run. Gating it on the
    # budget would re-create the stranding this bead exists to remove, at the
    # one moment it is most likely to happen.
    # A SIGNED RESUME IS EXEMPT FOR THE SAME REASON A DEFERRED MERGE IS
    # (Proofdelve ForgeOs-ohsy): it dispatches no Forge and spends no review launch, so
    # the thing the budget gates is not the thing it would stop. Gating it
    # would strand a bead the Overseer has already signed at the one moment it
    # is most likely to happen, which is this budget's own recorded mistake.
    if [ "$resume" != "land" ] && [ "$resume" != "signed" ] && ! budget_left; then
      budget_stop "reaping $bead"
      worker_set_state "$d" parked-budget "the run's launch budget ran out before this worker was reaped; the next run resumes at the verifier"
      say "$bead: its Forge has finished and is PARKED FOR BUDGET. That is healthy: the next run picks it up at the verifier."
      break
    fi

    # THE DRY-RUN GUARD IS NOW ABOVE EVERY MUTATION (Proofdelve ForgeOs-w7u5, sighting 5).
    # The touch of the old marker used to sit NINE LINES ABOVE this guard (the
    # call is deliberately paraphrased here rather than quoted: a literal in a
    # comment fails a zero-tolerance grep exactly like a live instruction), so
    # a dry run
    # marked a real finished Forge's worker as done and every later real run
    # skipped it permanently — a decide-nothing mode with a durable side
    # effect. A dry run now writes no worker state at all and says where it
    # would have resumed.
    if [ "$dry" = 1 ]; then
      say "DRY-RUN would resume $bead at: $resume"
      continue
    fi

    refill_slots "before $bead is taken in hand"   # Proofdelve ForgeOs-uwjme (c)
    # ASKED AGAIN AFTER THE REFILL. The loop-top check above ran BEFORE the
    # refill, which reads the tracker and can take seconds; a stop that lands
    # inside it must not start a six-minute verifier on the way out. Measured
    # live: run 20261015T115003 took SIGTERM at 12:09:12 inside the refill
    # before 2md9d.4.13 and then verified it for six minutes while DRAINING.
    stopping && break
    worker_set_state "$d" in-hand "taken by run $run_id, resuming at $resume"

    case "$resume" in
      verify)
        frc="$(cat "$d/exit" 2>/dev/null || echo 0)"
        if worker_review_only "$d"; then
          say "$bead: a Workbench session branch queued for ONE review (--review-only); no Forge ran"
        else
          say "$bead: Forge exited $frc"
        fi
        # THE HOST, BEFORE THE FORGE'S EXIT CODE IS INTERPRETED (Proofdelve ForgeOs-g3n1).
        # A Forge that exited 1 because the disk was full is not a Forge that
        # failed, and returning it spends the return counter on the host's
        # fault -- 7gag returned two beads twice each and escalated both. The
        # worker goes back to `finished` so the next run reaps it from the
        # verifier once the host is repaired; if the session really did leave
        # broken work, that verifier is what says so, once.
        # ASKED ONLY OF A FORGE THAT EXITED NONZERO (the Warden, round one): a
        # successful session's transcript is model prose, and prose about the
        # signature is not the signature.
        if [ "$frc" -ne 0 ] && looks_env_failure "$d/forge.log"; then
          worker_set_state "$d" finished "the host failed under its Forge session (environmental, not the bead's); the next run verifies it"
          env_halt_if "$d/forge.log" "the Forge log for $bead ($d/forge.log)"
        fi
        # 76 IS forge.sh REFUSING TO DISPATCH, NOT THE FORGE FAILING (Proofdelve ForgeOs-lw8x).
        # A re-dispatched bead's worktree still exists and forge.sh now brings it
        # current with main before anything builds in it; when that merge cannot
        # be made -- a conflict, a dirty tracked file it would overwrite, a HEAD
        # off its branch -- the launcher backs out, PROVES the back-out, and exits
        # 76 before any session starts. Nothing was built, nothing was verified.
        # Re-dispatching cannot change that: the same refusal repeats. So this is
        # a person's merge, PAGED rather than returned -- a return would spend the
        # return counter on a failure that is not the Forge's and then escalate
        # anyway two passes later under a message blaming the Forge. Checked
        # before the governor reads the log, because a refusal is neither
        # back-pressure nor a healthy completion.
        if [ "$frc" -eq 76 ]; then
          worker_set_state "$d" needs-person "forge.sh refused to bring the reused worktree $wt current with main before dispatch (exit 76); no Forge session ran"
          say "$bead: forge.sh REFUSED to refresh its reused worktree $wt from main (exit 76) -- no session ran; PAGING a person (Proofdelve ForgeOs-lw8x)"
          page_overseer "$bead" "forge.sh refused to bring the reused worktree $wt current with main before dispatching (exit 76), so NO Forge session ran and nothing was built or verified this pass. Re-dispatching repeats the refusal. Merge main into bead/$sfx by hand and re-queue it, or remove the worktree AND the branch so the next dispatch cuts fresh (Proofdelve ForgeOs-lw8x). The launcher's own words are in the evidence below." "$d/forge.log" "Nothing was built, verified or reviewed this pass: the refresh backed out and the worktree stands as it was. The bead is still claimed by the Forge actor; re-queue it by hand once the branch is current."
          continue
        fi
        # Proofdelve ForgeOs-4hzq (the Warden review finding 2): EXIT 77 IS forge.sh REFUSING A
        # PROMPT OVER THE SIZE CEILING BEFORE bwrap -- no session ran, like 76.
        # It is deterministic: the prompt is rebuilt from the same bd show, so a
        # re-dispatch refuses identically. PAGE a person rather than return_to_ready
        # below, which would spend the return counter on a refusal that only
        # repeats and then escalate two passes later blaming the Forge.
        if [ "$frc" -eq 77 ]; then
          worker_set_state "$d" needs-person "forge.sh refused to dispatch $bead: its assembled prompt exceeded the size ceiling (exit 77); no Forge session ran"
          say "$bead: forge.sh REFUSED -- prompt over the size ceiling (exit 77), no session ran; PAGING a person (Proofdelve ForgeOs-4hzq)"
          page_overseer "$bead" "forge.sh refused to dispatch $bead because its assembled prompt exceeded the size ceiling (exit 77), so NO Forge session ran. Re-dispatching rebuilds the same oversized prompt and repeats the refusal. Shorten the bead (its bd show is the prompt body) -- e.g. re-file the latest round as a fresh short bead -- then re-queue it (Proofdelve ForgeOs-4hzq). The launcher's own words are in the evidence below." "$d/forge.log" "Nothing was built, verified or reviewed this pass: the launcher refused before any session started. The bead is still claimed by the Forge actor; shorten it and re-queue by hand."
          continue
        fi
        if looks_rate_limited "$d/forge.log"; then
          governor_down "forge log for $bead shows plan back-pressure"
        else
          governor_up_maybe
        fi
        if [ "$frc" -ne 0 ]; then
          worker_set_state "$d" settled "the Forge exited $frc; the bead was returned to the queue and a fresh dispatch gets a fresh worker"
          return_to_ready "$bead" "the Forge session exited $frc" "$d/forge.log"; continue
        fi
        if [ ! -d "$wt" ]; then
          worker_set_state "$d" settled "no worktree after the Forge session; the bead was returned to the queue"
          return_to_ready "$bead" "no worktree at $wt after the Forge session" "$d/forge.log"; continue
        fi
        # Proofdelve ForgeOs-4hzq(B-ii): A FORGE THAT COMMITTED NOTHING NEVER REACHES THE
        # VERIFIER. forge.sh now propagates the session exit code, so a run that
        # never started (E2BIG, exit 126) is caught by the frc check above; this
        # is the independent second guard for the other shape -- a Forge that
        # exited 0 having committed nothing. Its branch is at main, so the
        # verifier would score MAIN (green, meaningless) and the Warden would be
        # handed an empty diff (that is exactly what kbt4.4 did, 2026-09-14
        # 01:41). Gated on the branch EXISTING: a finished worker whose bead
        # branch is absent is a different case left to the verify path below
        # (and is the governor-harness 26b vacuity fixture). rev-list, never a
        # tip compare: main..bead/X counts this branch's own commits.
        if git -C "$root" rev-parse --verify --quiet "bead/$sfx" >/dev/null 2>&1 \
           && [ "$(git -C "$root" rev-list --count "main..bead/$sfx" 2>/dev/null || echo 0)" -eq 0 ]; then
          worker_set_state "$d" settled "the Forge exited 0 but committed nothing: bead/$sfx has no commits ahead of main; not verified, not reviewed"
          say "$bead: the Forge committed nothing (bead/$sfx is at main) -- returned, never verified (Proofdelve ForgeOs-4hzq)"
          return_to_ready "$bead" "the Forge session exited 0 but committed nothing to bead/$sfx (0 commits ahead of main); it was NOT verified or sent to review" "$d/forge.log"
          continue
        fi
        # Proofdelve ForgeOs-ss9d: A BRANCH WHOSE ONLY CHANGE IS UNDER fort/handoffs/ IS THE
        # ZERO-COMMIT CASE ONE COMMIT WIDER. A Forge that STOPS with a blocked
        # handoff (the u65j.4 rule working) leaves the handoff uncommitted;
        # forge.sh's stamp step then commits it, so the branch is ONE commit
        # ahead of main and the guard above does not trip -- w4fm.4.1 on
        # 2026-09-14 12:32: the host verifier ran and a Warden launch was spent
        # to say "handoff-only diff, no implementation". Every u65j.4-class stop
        # produces this shape, so the count that matters is PRODUCT change: the
        # net diff from the merge base with fort/handoffs/ excluded. Three dots,
        # not two -- after a refresh merge (lw8x on re-dispatch) the two-tip form
        # would show main's own movement as this branch's change. An empty
        # product diff is returned with its own reason; the handoff stays on the
        # branch (it is the record of the stop) and the worktree stays (forge.sh
        # reuses it). Nothing is verified or reviewed. Landability (36b9) still
        # runs for every branch that reaches the line below.
        # Proofdelve ForgeOs-nz3u: UNLESS THE BEAD DECLARED THAT ITS DELIVERABLE IS AN
        # ANSWER. vky8 (2026-09-15) measured exactly what it was asked, changed
        # no product code because none was asked for, and was returned twice
        # and escalated as abandoned; pkl9 and nf17 the next day were ordinary
        # beads whose premise proved false, so the only honest output was a
        # report, and the predicate charged the Forge for being right. The
        # guard is NOT weakened: it is consulted on something DECLARED by the
        # filer (`Deliverable: answer` in the description, deliverable_of()
        # above), never guessed from the handoff or the criteria. A declared
        # bead proceeds to the verifier and the review, where the Warden reads
        # the answer; the 4hzq zero-commit guard above still returns it (no
        # handoff at all is not an answer); and a declared bead whose Forge
        # also changed product code never reaches this branch at all.
        if git -C "$root" rev-parse --verify --quiet "bead/$sfx" >/dev/null 2>&1 \
           && [ -z "$(git -C "$root" diff --name-only "$main_branch...bead/$sfx" -- . ':!fort/handoffs' 2>/dev/null)" ]; then
          if [ "$(deliverable_of "$bead")" = answer ]; then
            say "$bead: handoff-only branch and the bead declares 'Deliverable: answer' -- the handoff IS the deliverable; proceeding to verify and review (Proofdelve ForgeOs-nz3u)"
          else
            worker_set_state "$d" settled "the Forge exited 0 with no product change: every path bead/$sfx changes is under fort/handoffs/; not verified, not reviewed"
            say "$bead: no product change -- bead/$sfx differs from main only under fort/handoffs/ (a stopped session's handoff, Proofdelve ForgeOs-ss9d); returned, never verified"
            return_to_ready "$bead" "no product change: handoff only (bead/$sfx differs from main only under fort/handoffs/, the record of a session that stopped before implementing; a bead whose deliverable is an answer declares 'Deliverable: answer' in its description, Proofdelve ForgeOs-nz3u); it was NOT verified or sent to review" "$d/forge.log"
            continue
          fi
        fi
        # LANDABILITY BEFORE THE REVIEW, REFRESH BEFORE THE VERIFY (Proofdelve ForgeOs-36b9;
        # the reasoning is on prelanding_refresh() above). A conflict or a
        # refusal has already set the worker's state and paged a person; the
        # verifier and the review are never reached for it.
        if worker_review_only "$d"; then
          prelanding_refresh "$bead" "$sfx" "$wt" "$d" refresh "the Workbench ($(workbench_assignee))"
        else
          prelanding_refresh "$bead" "$sfx" "$wt" "$d"
        fi
        case "$prelanding_result" in
          conflict|refused) continue ;;
          current|refreshed|unchecked) ;;
          *) worker_set_state "$d" needs-person "prelanding_refresh returned an unknown result '$prelanding_result', which is a defect in fleet.sh rather than in the work"
             say "$bead: prelanding check returned '$prelanding_result' -- marked NEEDS A PERSON. This is a fleet.sh defect; report it."
             continue ;;
        esac
        # THE GATE. Run here, on the host, in the bead's own worktree, and read
        # from THIS process's observed exit code. Never from anything forge.sh
        # printed.
        vout="$state/logs/verify-$bead.txt"
        say "$bead: running the host verifier in $wt"
        if host_verify "$wt" "$vout" "$d"; then
          say "$bead: verifier GREEN — sending to review"
          refill_slots "after $bead's host verifier"   # Proofdelve ForgeOs-uwjme (a)
          review_one "$bead" "$wt"
        elif signalled; then
          # Proofdelve ForgeOs-a2fx. The verifier runs in this process group, so Ctrl-C
          # kills it and it reports nonzero for a reason that has nothing to do
          # with the bead. Returning it here would charge an operator's
          # interrupt to the Forge and re-run implementation over work nobody
          # has judged. The worker goes back to `finished` rather than staying
          # in-hand, so the next run resumes it instead of finding an orphan.
          worker_set_state "$d" finished "its host verifier was stopped by SIG$stop_signal, not failed; nothing was recorded against the bead"
          say "$bead: its host verifier was STOPPED by SIG$stop_signal, not failed. Nothing is recorded against this bead and it keeps its claim; the next run verifies it again."
          break
        else
          # A RED verifier whose log names the host is the host's, not the
          # bead's (Proofdelve ForgeOs-g3n1): 7gag's wb2e went RED at dotnet-build on
          # 'tee: Disk quota exceeded'. Back to `finished` so it verifies again
          # once the disk is repaired, then halt; never returned for it.
          if looks_env_failure "$vout"; then
            worker_set_state "$d" finished "the host failed under its verifier (environmental, not the bead's); the next run verifies it again"
            env_halt_if "$vout" "the verifier log for $bead ($vout)"
          fi
          worker_set_state "$d" settled "the host verifier was RED in this bead's own worktree; the bead was returned to the queue"
          say "$bead: verifier RED — returned, never reviewed"
          return_to_ready "$bead" "the host verifier is RED in this bead's own worktree ($wt). It was NOT sent to review." "$vout"
        fi
        ;;
      land)
        # Proofdelve ForgeOs-usz6. THE RETRY IS THE MERGE ALONE. Everything it needs was
        # written down by land() before it deferred, and everything that could
        # make acting on it wrong is checked here rather than assumed.
        local lverdict="" lrecord="$d/warden-record"
        lverdict="$(cat "$d/verdict" 2>/dev/null || echo "")"
        # THE SAME SET THE FRESH-REVIEW DISPATCH USES, read from one place. This
        # arm knew two of the three tokens, so the first MERGE-PARENT-OPEN to
        # meet a dirty tree, a held merge slot or a stopping run was called
        # unusable BY NAME (Proofdelve ForgeOs-j3kp finding 1).
        if ! verdict_is_landable "$lverdict"; then
          worker_set_state "$d" needs-person "deferred at the merge with no usable stored verdict ('$lverdict'); no mechanism may act on that"
          say "$bead: deferred at the merge with no usable stored verdict — NEEDS A PERSON"
          continue
        fi
        # AN ABSENT RECORD IS NEVER AN APPROVAL, one layer further on, AND THIS
        # IS THE SECOND TRIGGER. Both verdicts that file a follow-up need the
        # stored record: on APPROVE-WITH-FINDINGS its filing gates the close, and
        # on MERGE-PARENT-OPEN it is the only carrier of the findings. Teaching
        # the arm above the third token WITHOUT teaching this one would have sent
        # a deferred MERGE-PARENT-OPEN into a path only ever exercised for the
        # two tokens it already knew, unmasking the Proofdelve ForgeOs-bzyk orphan by a
        # second route inside the fix for the first. Plain APPROVE is
        # deliberately NOT here: it files no follow-up, so it lands with or
        # without a record, and that is the case a single shared predicate
        # breaks.
        if verdict_files_followup "$lverdict" && [ ! -s "$lrecord" ]; then
          worker_set_state "$d" needs-person "deferred on $lverdict and the stored Warden record is missing or empty, so the follow-up bead that carries the findings cannot be written"
          say "$bead: deferred on $lverdict but its stored review record is gone — NEEDS A PERSON"
          continue
        fi
        if ! git -C "$root" rev-parse --verify --quiet "bead/$sfx" >/dev/null 2>&1; then
          worker_set_state "$d" needs-person "deferred at the merge and the branch bead/$sfx no longer exists, so there is nothing left to land"
          say "$bead: deferred at the merge but bead/$sfx is GONE — NEEDS A PERSON"
          continue
        fi
        # SOMEBODY MAY HAVE LANDED IT BY HAND WHILE IT WAITED. That is the
        # likeliest thing to have happened to a bead that has been sitting, and
        # re-merging an ancestor would produce a no-op merge that this file
        # would then report as a landing it performed.
        if git -C "$root" merge-base --is-ancestor "bead/$sfx" HEAD 2>/dev/null; then
          worker_set_state "$d" settled "bead/$sfx is already an ancestor of $root HEAD: somebody landed it between the deferral and this retry"
          say "$bead: already merged — somebody landed it by hand while it waited. Nothing to retry."
          continue
        fi
        say "$bead: RETRYING THE DEFERRED MERGE ALONE on the stored verdict $lverdict — the verifier is not re-run and no review launch is spent"
        land "$bead" "$lverdict" "$lrecord"
        # Proofdelve ForgeOs-dx34.11 shape (a). If this worker entered the reap already
        # deferred-merge and land() left it STILL deferred-merge on a reason it
        # has ALREADY DEFERRED ON, no state changed this pass -- back out the
        # provisional count so the stall counter is not reset by a merge that is
        # going nowhere. Any other outcome (merged and settled, deferred on a
        # genuinely NEW reason, needs-person) is real activity and keeps its count.
        #
        # "ALREADY DEFERRED ON" AND NOT "THE SAME AS LAST PASS" (Proofdelve ForgeOs-dx34.15,
        # The Warden's non-blocking finding 5 on dx34.11). The last-distinct-reason test
        # let a reason that FLAPS -- A, B, A, B, as a landable_why file list does
        # when a build writes and removes an artifact under a dirty root -- count
        # as a state change on every pass, so the counter reset every pass and the
        # perpetually parked merge masked the stall exactly as before dx34.11. The
        # fingerprint is now the SET of reasons this worker has deferred on (the
        # seen-list defer_merge keeps), so a reason counts as progress the first
        # time it is given and never again. This is NOT Proofdelve ForgeOs-usz6's rejected
        # deferral threshold: no count of deferrals decides anything here, a
        # merge deferring on its tenth NEW reason still counts as activity, and
        # what the back-out withdraws is only the claim that a repeat is progress.
        # The equality test stays beneath it for workers deferred before the
        # seen-list existed, whose list is empty.
        if [ "$pre_state" = deferred-merge ] && [ "$(worker_state "$d")" = deferred-merge ]; then
          local post_reason
          post_reason="$(cat "$d/defer-reason" 2>/dev/null || echo "")"
          if [ "$post_reason" = "$pre_defer_reason" ] || reason_seen "$(reason_key "$post_reason")" "$pre_seen"; then
            pass_reaped=$((pass_reaped - 1))
          fi
        fi
        ;;
      signed)
        # Proofdelve ForgeOs-ohsy. THE RESUME RE-ASKS THE THREE QUESTIONS; IT DOES NOT
        # TRUST THE PARK. Between the signal and this pass the approval can be
        # superseded, the branch can move and main can move under it, so the
        # state token says only WHERE to pick this worker up and never that the
        # signature still holds. signed_landing_ready() re-reads the approval
        # out of the event stream and re-compares the patch-id from scratch,
        # exactly as dispatch_pass does for a fresh signed landing -- one
        # decider, consulted from two places, which is why this arm does not
        # re-implement any part of it.
        local sig_rc=0
        signed_landing_ready "$bead" "$sfx" || sig_rc=$?
        if [ "$sig_rc" -eq 0 ]; then
          # The dispatcher's own pass-local scratch path, deliberately: it is
          # the same artifact for the same purpose, and dispatch_pass clears it
          # on entry and on exit, so this resume leaves nothing behind. A
          # second name would be a second lifetime to get wrong.
          local stset="$state/.touches-candidate"
          touch_set_of "$bead" > "$stset"
          say "$bead: resuming the SIGNED LANDING it was parked in -- the approval of ${signed_sha:0:12} still covers this tree; no Forge and no review launch"
          signed_landing "$bead" "$sfx" "$wt" "$stset"
          continue
        fi
        # NOT A FAILURE AND NOT A PAGE: the ordinary path is the correct
        # destination for a bead the signature no longer covers, and that path
        # begins at the verifier. One pass of latency, deliberately, rather
        # than a second copy of the verify-then-review tail living here.
        worker_set_state "$d" finished "the Overseer's approval no longer covers this tree (${signed_why:-no reason recorded}); resuming at the ordinary verify-then-review path instead of the landing"
        say "$bead: parked mid-signed-landing, but the signature no longer covers this tree (${signed_why:-no reason recorded}) -- back to the ORDINARY path; the next pass verifies and reviews it."
        ;;
      review)
        if [ ! -d "$wt" ]; then
          worker_set_state "$d" needs-person "parked before its review, and its worktree $wt is gone, so the green verifier result it was parked on no longer exists"
          say "$bead: parked for review but $wt is GONE — marked NEEDS A PERSON"
          continue
        fi
        # LANDABILITY IS STILL ASKED, WITHOUT A REFRESH (Proofdelve ForgeOs-36b9, the Warden's
        # finding 3 on 823074e): a conflict found here costs no launch and
        # pages; a clean answer leaves the verified tree exactly as it is.
        prelanding_refresh "$bead" "$sfx" "$wt" "$d" check
        case "$prelanding_result" in
          conflict) continue ;;
          current|unrefreshed|unchecked) ;;
          *) worker_set_state "$d" needs-person "prelanding_refresh (check) returned an unknown result '$prelanding_result', which is a defect in fleet.sh rather than in the work"
             say "$bead: prelanding check returned '$prelanding_result' -- marked NEEDS A PERSON. This is a fleet.sh defect; report it."
             continue ;;
        esac
        say "$bead: resuming AT ITS REVIEW — it was verifier-green in $wt on an earlier run, so the verifier is not re-run"
        review_one "$bead" "$wt"
        ;;
      *)
        worker_set_state "$d" needs-person "the lifecycle owner said this worker was reapable and then had no resume point for it, which is a defect in fleet.sh rather than in the work"
        say "$bead: reapable with no resume point — marked NEEDS A PERSON. This is a fleet.sh defect; report it."
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
print_status() {
  echo "fleet state: $state"
  echo "config:      $conf"
  [ -e "$halt_file" ] && { echo "HALTED:"; sed 's/^/  /' "$halt_file"; }
  local wbl
  if wbl="$(workbench_live)"; then
    echo "WORKBENCH:   a sitting is live (bead pid: $wbl); fleet beads whose files overlap its live set are HELD, the rest dispatch (Proofdelve ForgeOs-9srgz)"
  fi
  # A LIVE RUN MAKES ONE OF THESE LABELS WRONG, AND SAYING SO BEATS GUESSING.
  # worker_state calls a worker in-hand from another run ORPHANED, which is
  # right from inside a run (the flock means only one runs at a time) and wrong
  # from --status, which can be typed while a fleet is live. The check costs
  # one flock and the note costs one line.
  if flock -n 9 2>/dev/null 9>>"$state/fleet.lock"; then :; else
    echo "NOTE: a fleet run is LIVE right now. Any worker below shown as ORPHANED is"
    echo "      more likely to be IN HAND by that run; re-read this once it has ended."
  fi
  # LANDABILITY AND THE PARKED COUNT, ABOVE THE WORKER TABLE (Proofdelve ForgeOs-dx34.1).
  # A dirty tree no longer stops a run, so "why has nothing landed tonight" is a
  # question --status must answer in one line rather than leave to be inferred
  # from a column of `deferred-merge` tokens.
  local slwhy parked
  slwhy="$(landable_why)"
  parked="$(parked_merges)"
  if [ -n "$slwhy" ]; then
    echo "landable:    NO — $slwhy"
  else
    echo "landable:    yes — HEAD is on $main_branch with no uncommitted tracked source"
  fi
  if [ "$parked" -gt 0 ]; then
    echo "parked:      $parked merge(s) waiting on a landable tree. Each keeps its verdict and its"
    echo "             claim; a later pass retries the merge alone, re-running neither the verifier"
    echo "             nor a review launch."
  else
    echo "parked:      no merges are waiting on a landable tree"
  fi
  echo "workers:"
  local d
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    printf '  %-14s %-14s resume=%-7s %s\n' "$(basename "$d")" \
      "$(worker_state "$d")" "$(worker_resume_at "$d")" "$(cat "$d/bead" 2>/dev/null)"
  done
  echo "what needs a person:"
  local any=0
  for d in "$state/workers"/*/; do
    [ -d "$d" ] || continue
    if worker_needs_person "$d"; then echo "  $(worker_explain "$d")"; any=1; fi
  done
  if [ "$any" = 0 ]; then echo "  nothing."; fi
  echo "ceiling log tail:"
  tail -10 "$ceiling_log" 2>/dev/null | sed 's/^/  /'
}

# QUEUE A WORKBENCH SESSION BRANCH FOR ONE REVIEW (Proofdelve ForgeOs-9srgz).
# Writes the worker record a Mayor used to write by hand (Proofdelve ForgeOs-0o16s,
# 2026-11-09) and exits; the live run, or the next one the supervisor starts on
# its reapable count, takes it first. It launches nothing itself.
# MASKS: runnable unmasked and from the Mayor's mask (she has always been able
# to write this record by hand); refused from every other seat, the Workbench
# included, because a seat queueing its own review is not the hand-off the
# charter describes.
review_only_enqueue() {  # $1 bead
  local bead="$1" sfx wt d st status ahead dirty live
  case "${FORT_MASKED:-}" in
    ""|mayor) ;;
    *) echo "fleet.sh --review-only: REFUSED inside the '$FORT_MASKED' seat mask; the Mayor or the Overseer queues a Workbench review" >&2; return 77 ;;
  esac
  status="$(bd -C "$root" show "$bead" --json 2>/dev/null | jq -r 'if type == "array" then .[0] else . end | .status // empty' 2>/dev/null || true)"
  case "$status" in
    "") echo "fleet.sh --review-only: REFUSED -- bd does not know $bead" >&2; return 66 ;;
    closed) echo "fleet.sh --review-only: REFUSED -- $bead is closed" >&2; return 66 ;;
  esac
  sfx="${bead##*-}"; wt="$root-worktrees/$sfx"; d="$state/workers/$sfx"
  [ "$(git -C "$wt" symbolic-ref --short -q HEAD 2>/dev/null)" = "bead/$sfx" ] \
    || { echo "fleet.sh --review-only: REFUSED -- $wt is missing or not on bead/$sfx" >&2; return 66; }
  ahead="$(git -C "$root" rev-list --count "$main_branch..bead/$sfx" 2>/dev/null || echo 0)"
  [ "$ahead" -gt 0 ] || { echo "fleet.sh --review-only: REFUSED -- bead/$sfx has no commits ahead of $main_branch" >&2; return 66; }
  dirty="$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null | head -5)"
  [ -z "$dirty" ] || { printf 'fleet.sh --review-only: REFUSED -- %s has uncommitted tracked changes, which the review would not see:\n%s\n' "$wt" "$dirty" >&2; return 66; }
  if live="$(workbench_live)" && [ "${live%% *}" = "$bead" ]; then
    echo "fleet.sh --review-only: REFUSED -- the Workbench sitting on $bead is still live; end it first" >&2; return 75
  fi
  if [ -d "$d" ]; then
    st="$(worker_state "$d")"
    case "$st" in
      settled) ;;
      *) echo "fleet.sh --review-only: REFUSED -- $d already holds a worker in state '$st'; it is not this command's to replace" >&2; return 75 ;;
    esac
    rm -rf "$d"
  fi
  mkdir -p "$d" || return 70
  printf '%s\n' "$bead" > "$d/bead"
  date -Is > "$d/started"
  printf '%s\n' "review-only" > "$d/run"
  printf 'queued=%s by=%s\n' "$(date -Is)" "${FORT_MASKED:-host}" > "$d/review-only"
  # --no-renames: both names of a renamed file (the Warden, finding 2 on the docket review).
  # -z: raw paths, so a non-ASCII name is not written quoted (the Warden, round two, finding 1).
  git -C "$root" diff --name-only --no-renames -z "$main_branch...bead/$sfx" 2>/dev/null | tr '\0' '\n' > "$d/touches" || true
  printf '0\n' > "$d/exit"
  emit fleet.handed "$bead queued for ONE review of its Workbench session branch (bead/$sfx, $ahead commit(s) ahead of $main_branch): host verify, one Warden launch at the front of the reap order, merge or escalate" \
    -a "$fleet_actor" -s fleet -t "$bead" -p "{\"review_only\":true,\"commits\":$ahead}"
  echo "fleet.sh --review-only: queued $bead (bead/$sfx, $ahead commit(s), $(wc -l < "$d/touches") path(s)). The live fleet run, or the next one the supervisor starts, takes it first."
  [ -e "$halt_file" ] && echo "NOTE: the fleet is HALTED ($halt_file); nothing runs until a person removes it."
  return 0
}

if [ -n "$review_only" ]; then
  if [ -r "$conf" ]; then
    # shellcheck source=/dev/null
    . "$conf"
  fi
  : "${FLEET_LAUNCH_GRACE:=120}"
  review_only_enqueue "$review_only"; exit $?
fi

if [ "$status_only" = 1 ] || [ "$reapable_only" = 1 ]; then
  # --status DELIBERATELY RUNS BEFORE preflight, so it still works on a halted
  # or misconfigured rig — which is exactly when someone types it. print_status
  # now asks the lifecycle owner, and worker_state reads FLEET_LAUNCH_GRACE, so
  # the config is read here if it can be and defaulted loudly if it cannot.
  # Without this, `--status` on a rig with no readable config would die on an
  # unbound variable under `set -u` and report nothing at all.
  if [ -r "$conf" ]; then
    # shellcheck source=/dev/null
    . "$conf"
  else
    echo "NOTE: $conf is not readable, so the launch-grace window below is a default." >&2
  fi
  : "${FLEET_LAUNCH_GRACE:=120}"
  # --reapable IS THE SUPERVISOR'S QUESTION 4b (Proofdelve ForgeOs-dx34.18 criterion 5),
  # ANSWERED HERE SO THERE IS ONE DEFINITION OF "REAPABLE". The supervisor
  # selects and this file decides (Proofdelve ForgeOs-czhb); a second reading of the state
  # token list in fleet-supervisor.sh would be the second decider czhb forbids.
  # One number, nothing else on stdout, exit 0.
  if [ "$reapable_only" = 1 ]; then reapable_workers; exit 0; fi
  print_status; exit 0
fi

preflight
# THE LOCK IS TAKEN BEFORE THE RUN IS ANNOUNCED (Proofdelve ForgeOs-l1ef). fleet.begun
# used to be emitted first, so an instance REFUSED by the lock still wrote a
# `begun` into the stream with no `ended` behind it — the exact shape a reader
# is taught to escalate as a run that died silently, produced by the guard
# working correctly. A refused instance now emits nothing at all, which is the
# honest record of a run that never started.
#
# One fleet at a time. This is the fleet's own lock and does not replace
# forge.sh's per-worktree flock or bd's per-bead claim; all three guard
# different things.
exec 8>"$state/fleet.lock"
if ! flock -n 8; then
  echo "fleet.sh: REFUSED — another fleet run holds $state/fleet.lock" >&2
  exit 75
fi
# AFTER THE LOCK (Proofdelve ForgeOs-lzvo, the Warden's finding 5 on 025a52f): governor_init
# writes this run's start line to ceiling.log, and tools/keep/lib/fleet.mjs
# reads the LAST start line's run= as the current run. Called before the lock,
# a refused instance wrote a start line for a run that never ran.
governor_init

# EXACTLY ONE fleet.ended PER RUN, AND IT SAYS WHY (Proofdelve ForgeOs-stpx). Installed
# immediately after the lock and before fleet.begun, so the pair is balanced
# from the first announcement onward. $end_reason DEFAULTS to an undetermined
# string (Proofdelve ForgeOs-6843) and every named exit overwrites it: "drained" set at the
# drain check itself, "one pass complete (--once)" / "dry run: ..." at those
# breaks, "budget spent" from budget_stop, "halted: ..." from halt(), or
# "stalled: ..." from stall_check() through halt() (Proofdelve ForgeOs-dx34.9, which also
# adds the `stalled` flag so a reader need not parse the reason's prefix, and
# `stall_peak`, so a run that absorbed near-misses all night leaves a durable
# number where the supervisor reads -- events, not run logs; the Warden, finding 5).
# Proofdelve ForgeOs-a2fx: the distinction survives into the PAYLOAD and not only into the
# prose, because the digest and every later reader parse the payload.
trap 'emit fleet.ended "Fleet run $run_id ended after $launches launches ($end_reason)" -a "$fleet_actor" -s fleet -p "{\"run\":\"$run_id\",\"launches\":$launches,\"reason\":\"$end_reason\",\"halted\":$halted,\"stalled\":$stalled,\"stall_peak\":$stall_peak,\"interrupted\":$interrupted,\"signal\":\"$stop_signal\"}"' EXIT

say "narrative log: $narrative_log — this run survives its terminal closing (SIGHUP is ignored), so that file is where it keeps talking. Ctrl-C or kill -TERM stops it; touching $halt_file stops it too."
# `forge start $forge_conc`, not $FLEET_FORGE_START: governor_init has already
# run and the ceiling may be carried from the previous run (Proofdelve ForgeOs-xzg1).
emit fleet.begun "Fleet run $run_id begun (forge start $forge_conc, warden $FLEET_WARDEN_CONC, hard stop $FLEET_HARD_STOP)" \
  -a "$fleet_actor" -s fleet -p "{\"run\":\"$run_id\",\"dry_run\":$([ "$dry" = 1 ] && echo true || echo false)}"

# THE MID-RUN HALT CHECK (Proofdelve ForgeOs-a2fx, third fact). $FLEET_STATE/HALT was
# read at preflight and written by halt(), and NOTHING EVER READ IT AGAIN —
# so creating the halt file, which is the obvious operator reflex and the one
# this file's own error text teaches, did nothing to a running fleet. It now
# takes the same drain-then-stop path a signal takes. `$halted` is checked
# first because halt() writes that file itself and exits directly; this
# branch is for a file a PERSON created while the run was live.
# It is a FUNCTION because Proofdelve ForgeOs-fhak made stopping() read the file too, so
# the loop's `stopping && break` lines can end a run on the halt file BEFORE
# this point; each of them calls it first, and the run under --once now also
# reports a file that appeared during its one pass (it used to break before
# reaching here and record a plain end).
operator_halt_stop() {
  local local_in_flight in_flight_line in_flight_json l
  stop_requested=1
  exit_code=70
  # `halted` answers the question a later reader actually asks of this
  # payload — "did this run leave the fleet stopped?" — and the answer is
  # yes: that file is present and every later run refuses at preflight until
  # a person removes it. Who WROTE it is the other question, and the incident
  # below carries operator_halt for exactly that.
  halted=true
  set_end_reason "stopped: the halt file appeared while the run was live"
  governor_carry_reset "operator halt file"   # Proofdelve ForgeOs-xzg1
  say "HALT FILE PRESENT: $halt_file appeared during run $run_id. Stopping between passes."
  say "  Nothing further is dispatched, verified, reviewed or merged BY THIS RUN, and every later run"
  say "  refuses at preflight until that file is removed by hand."
  # MEASURED AT EMIT TIME, FROM THE LOCKS, NOT FROM THIS RUN'S BOOKKEEPING
  # (Proofdelve ForgeOs-fhak acceptance (a)). A Forge this run launched keeps running to
  # completion after the run ends; the sentence below names each one still
  # holding its launcher lock, or says that none is, and never asserts idleness
  # it did not measure.
  local_in_flight="$(forge_locks_held)"
  if [ -n "$local_in_flight" ]; then
    # THE SPACE BEFORE THE DASH IS LOAD-BEARING AND IT WAS MISSING (Proofdelve ForgeOs-ip9z
    # finding 3). `tr` turns the newlines BETWEEN entries into spaces and there
    # is none after the last one, so the final bead id ran straight into the
    # dash: "E2E-hla-- the tree is NOT quiet". This string is DURABLE EVENT
    # TEXT, read by a person deciding whether the tree is safe to work in.
    in_flight_line="FORGES STILL RUNNING under this halt, measured from live .forge.lock holders at emit time: $(printf '%s' "$local_in_flight" | tr '\n' ' ') -- the tree is NOT quiet until they finish (scripts/quiescent.sh answers when)."
    say "  IN FLIGHT (measured from live .forge.lock holders, not from this run's bookkeeping):"
    printf '%s\n' "$local_in_flight" | sed 's/^/    /' | while IFS= read -r l; do say "$l"; done
    say "  Those Forges run to completion; the tree is NOT quiet until their locks release."
  else
    in_flight_line="No Forge lock is held at emit time (measured): nothing this fleet launched is still running."
    say "  No Forge lock is held at this moment (measured); nothing this fleet launched is still running."
  fi
  in_flight_json="$(printf '%s\n' "$local_in_flight" | jq -R . | jq -sc 'map(select(length > 0))')"
  emit incident "Fleet run $run_id stopped mid-run: $halt_file appeared while it was live. This was NOT a halt() from a red main — the file was created by something else, most likely a person. Nothing further is dispatched or merged BY THIS RUN. $in_flight_line" \
    -a "$fleet_actor" -s fleet -p "{\"run\":\"$run_id\",\"launches\":$launches,\"halted\":true,\"operator_halt\":true,\"in_flight\":$in_flight_json}"
}

tmp_check() {
  local r="$root/fort/scripts/scratch-reaper.sh" out
  [ -f "$r" ] || return 0
  out="$(bash "$r" --tmp-check 2>&1 8>&-)" || true
  [ -z "$out" ] || printf '%s\n' "$out" | while IFS= read -r l; do say "  $l"; done
  return 0
}

while :; do
  # Checked first as well as last: a signal can arrive during preflight, before
  # this loop is entered at all, and a run told to stop must not do one more
  # pass on the way. A HALT FILE is a stop too (Proofdelve ForgeOs-fhak), and it owes the
  # operator-halt record before the break.
  if halt_file_present; then operator_halt_stop; break; fi
  stopping && break
  pass_dispatched=0; pass_reaped=0; pass_note=""; pass_held_unlanded=0   # Proofdelve ForgeOs-dx34.9, see stall_check()
  pass_mem_held=0   # Proofdelve ForgeOs-asad6, see stall_check()
  pass_workbench_held=0   # Proofdelve ForgeOs-9srgz, see stall_check()
  signed_tried_this_pass=""   # Proofdelve ForgeOs-jfqu4.7, see dispatch_pass() phase 1
  rm -f "$state/.np-warned"; settle_answered_workers   # Proofdelve ForgeOs-xu0mj: a new pass, so every live NEEDS A PERSON is said once again
  rm -f "$state/.reap-order-warned"   # Proofdelve ForgeOs-4bzvk: reap_order's bd-down note, once per pass
  # THE /tmp ALARM, BEFORE A FILL HALTS A VERIFY (Proofdelve ForgeOs-jfqu4.8 with
  # Proofdelve ForgeOs-lmgue, Regent docket 2026-10-22 item B). The scratch reaper owns
  # the measurement and the once-per-band-per-day incident; this asks it every
  # pass, since the hourly timer alone could miss a fill. It removes nothing,
  # and nothing it does can stop the run.
  tmp_check
  # SIGNED LANDINGS FIRST, then the completion lane, then the full pass
  # (Proofdelve ForgeOs-jfqu4.7). On a board with no stored ESCALATE this is a handful of
  # file reads and nothing else (dispatch_pass's any_signed pre-question).
  in_dispatch=1; dispatch_pass signed; in_dispatch=0
  stopping && break
  stale_signature_check   # Proofdelve ForgeOs-8gmt4: once per pass, after phase 1 has landed what it can
  reap_pass
  in_dispatch=1; dispatch_pass; in_dispatch=0   # the flag: refill_slots() inside a signed landing must not nest (Proofdelve ForgeOs-uwjme)
  if halt_file_present; then operator_halt_stop; break; fi   # Proofdelve ForgeOs-fhak: the file seen mid-pass is reported here, under --once too
  stopping && break
  # A SPENT BUDGET ENDS THE RUN, IT DOES NOT HALT IT (Proofdelve ForgeOs-feeq). No halt
  # file, no incident, and the next run starts normally.
  if [ "$end_reason" = "budget spent" ]; then
    say "run $run_id ends: the hard stop of $FLEET_HARD_STOP seat launches is spent"
    break
  fi
  # --once AND --dry-run EACH EXIT AFTER ONE PASS (Proofdelve ForgeOs-dx34.12 finding 4).
  # --dry-run without --once was the one spin the stall detector cannot see: the
  # dry branch counts the pass as dispatched, nothing is claimed, and
  # any_dispatchable() stays true forever, so a dry loop polled with no way to
  # stop it but by hand. A dry run decides everything and acts on nothing, which
  # is a report, and a report is one pass. Each sets its own end reason so the
  # trap's default (undetermined) is reserved for genuinely unexplained ends.
  if [ "$dry" = 1 ]; then set_end_reason "dry run: one pass, nothing claimed, launched or landed"; break; fi
  if [ "$once" = 1 ]; then set_end_reason "one pass complete (--once)"; break; fi
  if halt_file_present; then operator_halt_stop; break; fi
  report_parked_merges
  # NOTHING RUNNING AND NOTHING STARTABLE IS A DRAIN; A NON-EMPTY QUEUE IS NOT
  # (Proofdelve ForgeOs-czhb acceptance 7). This used to ask `bd ready` and read a non-empty
  # answer as "there is work", while dispatch_pass asked dispatchable() and
  # refused every one of those same beads -- so a queue of only-refused beads
  # polled forever, holding the exclusive run lock, and the budget could not end
  # it either because budget_left() is consulted only before a launch and there
  # were no launches. Once the supervisor lands, one wedged run would stop the
  # fleet permanently while every supervisor firing reported the normal quiet
  # outcome, because wedged and busy are indistinguishable from its side. Both
  # sides now ask any_dispatchable().
  #
  # THE STALL CHECK SHARES THIS PASS'S ANSWERS RATHER THAN ASKING AGAIN
  # (Proofdelve ForgeOs-dx34.9): live_forges() once, any_dispatchable() at most once, and
  # only when nothing is live -- a pass waiting on a Forge never consults the
  # queue, exactly as before. The two lines that follow are the ones the e2e
  # harness rewrites to build the NAIVE detector (no live-worker term) and show
  # it halting a healthy run; keep them on their own lines.
  live="$(live_forges)"; startable=unknown
  if [ "$live" -eq 0 ]; then if any_dispatchable; then startable=yes; else startable=no; fi; fi
  stall_check "$live" "$startable"
  if [ "$startable" = no ]; then
    # A REAPABLE WORKER IS WORK, AND THE DRAIN MUST SEE IT (Proofdelve ForgeOs-dx34.18).
    # OBSERVED 2026-09-11 23:36, run 20260911T222003, the first run at Forge
    # concurrency 2: 15k.6's Forge exited 0 at 23:34:53 while this loop was
    # inside one seven-minute reap pass on b0vj.53 (verifier, a synchronous
    # Warden review, merge, post-merge verifier). The pass ended, this check
    # ran, live_forges() said 0 (a finished worker is not running) and
    # any_dispatchable() said no (15k.6 is claimed, so bd ready does not list
    # it), and the run ended "drained" with 15k.6 finished and unreaped. Then
    # nothing started the run that would reap it, because the supervisor asks
    # the same question. Proofdelve ForgeOs-w7u5 made that worker VISIBLE (it was named in
    # the drain message); it did not make it COUNT. It counts here.
    #
    # THE FIX IS IN THE DRAIN CONDITION, NOT IN live_forges() OR any_dispatchable():
    # live_forges() is also the governor's slot count, so a finished worker in it
    # would eat a Forge seat; any_dispatchable() is the stall detector's
    # "startable" term, and a reapable worker is not startable work -- counting
    # it there would make a waiting merge look like a wedge. So the stall
    # counter's semantics are untouched: its no-live-Forge, startable-work, N
    # quiet passes are exactly what they were, and a pass here that finds only
    # reapable workers is a WAITING pass, said once, like the live-Forge one.
    #
    # WHAT THIS MEANS FOR A DEFERRED MERGE, STATED RATHER THAN DISCOVERED: a
    # worker parked at the merge on an unlandable tree is reapable, so the run
    # now waits for the tree instead of draining and stranding the merge until
    # somebody labels an unrelated bead. It polls at FLEET_POLL, retries the
    # merge alone each pass, emits one fleet.deferred per DISTINCT reason, and
    # report_parked_merges() names it every pass and --status names it on
    # demand. A tree that can never become landable therefore keeps the run
    # alive -- visibly -- rather than stranding the merge silently; the halt
    # file and the stop signals end it exactly as they end any run.
    reapable="$(reapable_workers)"
    if [ "$reapable" -gt 0 ]; then
      if [ "$reapable_said" != 1 ]; then
        say "not draining: nothing is startable, but $reapable worker(s) are reapable (finished, parked, or deferred at the merge) -- the next pass takes them. Said once per quiet stretch."
        reapable_said=1
      fi
    else
      set_end_reason "drained"   # Proofdelve ForgeOs-6843: the drain is decided HERE, so the reason is set HERE; the carry is at loop exit (Proofdelve ForgeOs-lzvo)
      say "queue drained after $launches launches (stall counter peak $stall_peak/$FLEET_STALL_PASSES)"
      break
    fi
  fi
  # `|| true` so a signal that kills the sleep cannot take the shell down under
  # `set -e` before report_leftovers has run. See the trap-latency note at the
  # head of this file for why the sleep stays in the foreground.
  sleep "$FLEET_POLL" || true
done
# THE CEILING IS CARRIED HERE, ONCE, FOR THE TWO ORDINARY ENDS (Proofdelve ForgeOs-xzg1,
# moved by Proofdelve ForgeOs-lzvo). A halt has already removed the carry file and exited;
# a signal or the operator's halt file leaves the file as the last ordinary end
# wrote it; --once and --dry-run are reports, not measurements.
case "$end_reason" in
  drained|"budget spent") governor_carry_out ;;
esac

report_leftovers
# THE RUN'S OUTCOME, IN ONE FILE THE SUPERVISOR CAN READ (Proofdelve ForgeOs-s49w; the Warden's
# round-one finding 3 on dx34.4). The supervisor SELECTS and this file DECIDES
# (Proofdelve ForgeOs-czhb), so the supervisor may not carry a second dispatchable(); what
# it may do is read what the run it started came to. A run it started that
# drained in seconds with zero launches did nothing, and starting another every
# two minutes is three events per interval of nothing. $FLEET_AUTOSTART is the
# unit name the supervisor passed when it started this run, empty for a run a
# person launched, so the supervisor can tell ITS run's outcome from anyone
# else's. Written on the ordinary exit path only: a halt() exits directly and
# leaves the previous run's record, which the supervisor tells apart by the
# unit name. Not in the EXIT trap, deliberately: stop-harness evaluates that
# trap string in a shell holding only the variables it reads, and the trap
# stays exactly one emit.
# landings (2026-10-06, the churn note on Proofdelve ForgeOs-owt37): the supervisor used to
# tell "did nothing" from "landed something" by DURATION, and a zero-launch drain
# on 2026-10-05 took 20-28 s against a 20 s cutoff, so ten runs started in a row.
# A count is the property; a duration was a proxy for it.
printf 'run=%s\nautostart=%s\nlaunches=%s\nlandings=%s\nreason=%s\nduration_s=%s\nended_at=%s\n' \
  "$run_id" "${FLEET_AUTOSTART:-}" "$launches" "$landings" "$end_reason" "$(( $(date +%s) - run_start_epoch ))" "$(date -Is)" \
  > "$state/last-run.outcome.tmp.$$" && mv -f "$state/last-run.outcome.tmp.$$" "$state/last-run.outcome" || true
exit "$exit_code"
