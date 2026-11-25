#!/bin/bash
# {{PROJECT}} verifier. Exit 0 only after every required quality gate passes.
#
# THE PRODUCT GATE IS A STUB. Every step that tests the fort's own machinery is
# wired and runs. The step named product-gate, the LAST one, fails until this
# fort replaces it with its own build, lint and tests: a verifier that passed
# with no product gate would be a green that means nothing.
#
# THE VERIFIER ITSELF. fort/scripts/verify.sh is a read-only shim that execs this
# file and forwards its arguments and exit status; run either, they are the same
# gate. It lives out here because fort/scripts is a whole-directory read-only
# bind in every seat mask (Shape B, fortkit-6ovg / fortkit-x9ou) and the verifier
# is the one tool in that set the fort evolves as it works.
#
# WRITE BOUNDARIES, which are the whole reason for the split:
#   Mayor    — writable. Verifier changes are Mayor work (cycle 7).
#   Forge    — READ-ONLY, by an explicit carve-out in the codex posture of
#              fort/scripts/lib/seat-sandbox.sh. Without that line this file
#              would be writable to the unattended seat, because $root is
#              read-write to it apart from the carve-outs — the wrinkle Shape B
#              would otherwise have introduced while closing a worse one.
#   Warden   — read-only for free: she passes her whole checkout as extra_ro.
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


repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# WRONG-TREE REFUSAL (Proofdelve ForgeOs-afdr). Measured 2026-08-28: the Mayor stood in
# <repo>-worktrees/sk3c.4.1 and ran {{REPO_PATH}}/fort/scripts/verify.sh
# by absolute path, as standing order 8 encourages. It exited 0, printed a normal
# green tail, and emitted verify.pass for tree={{REPO_PATH}}
# branch=main. The candidate branch was never built. Nothing downstream could
# tell that pass from a real one.
#
# repo_root above is derived from THIS FILE'S location and cwd was never
# consulted, so the habit the fort teaches (absolute paths) leads directly into
# the failure. Proofdelve ForgeOs-mlo made the wrong tree VISIBLE by naming it in the output
# and the event payload; four Mayor runs had already proved that visible is not
# the same as caught. This refuses instead.
#
# THE RULE, deliberately narrow: refuse only when the caller is standing inside a
# git worktree that is NOT the tree this verifier would score. Two real trees,
# two different answers, and the caller has demonstrably picked the wrong one. A
# caller outside any git tree (cron, /tmp, a bare shell) is making no claim about
# which tree it meant, so it is allowed through and the banner names the target.
#
# Escape hatch: VERIFY_ALLOW_TREE_MISMATCH=1 downgrades the refusal to a warning
# that is repeated at both ends of the run. It exists so a legitimate cross-tree
# invocation is possible without editing the gate; using it silently is the
# behaviour this guard was filed to stop.
# The -n test is load-bearing (Warden finding 4 on Proofdelve ForgeOs-afdr): `cd ""` is a
# no-op that returns 0, so a git exiting 0 with empty output here — the bare-repo
# case, whose behaviour has varied across git versions — would silently set
# caller_root to $PWD instead of the empty string that means "outside any git
# tree", and refuse where the stated rule says allow through.
caller_root=""
if caller_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" && [ -n "$caller_root" ]; then
  caller_root="$(cd "$caller_root" && pwd -P)"
else
  caller_root=""
fi
repo_root_real="$(cd "$repo_root" && pwd -P)"
tree_mismatch=false
if [ -n "$caller_root" ] && [ "$caller_root" != "$repo_root_real" ]; then
  tree_mismatch=true
  if [ "${VERIFY_ALLOW_TREE_MISMATCH:-0}" != "1" ]; then
    {
      printf 'verify: REFUSING TO RUN — WRONG TREE (Proofdelve ForgeOs-afdr). NOTHING WAS VERIFIED.\n'
      printf '  you are standing in : %s\n' "$caller_root"
      printf '  this verifier scores: %s\n' "$repo_root_real"
      printf 'These are different git worktrees. Run the copy that belongs to the tree you\n'
      printf 'mean to verify:\n'
      printf '  cd %s && ./fort/scripts/verify.sh\n' "$caller_root"
      printf 'If the cross-tree run is what you actually want, set VERIFY_ALLOW_TREE_MISMATCH=1.\n'
    } >&2
    exit 78
  fi
  printf 'verify: WARNING — cross-tree run permitted by VERIFY_ALLOW_TREE_MISMATCH=1.\n' >&2
  printf 'verify: standing in %s, scoring %s (Proofdelve ForgeOs-afdr).\n' "$caller_root" "$repo_root_real" >&2
fi

cd "$repo_root"

# QUIET MODE, FOR A SEAT WHOSE COMMAND WINDOW IS SMALLER THAN THIS RUN
# (Proofdelve ForgeOs-aez2; the Warden f2 on Proofdelve ForgeOs-yd3g, root on Proofdelve ForgeOs-tegq). The Forge runs
# under a 30 s per-command window and a codex output cap of a few thousand
# lines. MEASURED ON MAIN 2026-09-22: a green run of this file is 6,338 lines
# (the bead estimated ~3,400 when it was filed on 09-13; it has nearly doubled
# since). So a Terra Forge running the verifier in the foreground sees a
# truncation, cannot read the tail, and then honestly writes "no verify.pass
# observed" on a tree that is green -- four such records in one night (a1w5,
# dttr.6, dttr.7, b0vj.66) and two more on Proofdelve ForgeOs-m1qgy tonight.
#
# VERIFY_QUIET=1 changes PRESENTATION AND NOTHING ELSE. The step list, its
# order, every exit code and the verify.run/verify.pass/verify.fail events are
# identical in both modes; the harnesses are untouched. Full output still
# exists, teed to one kept log whose path is printed first and last -- the
# stream the seat reads becomes one line per step plus a verdict.
#
# THE LOG GOES UNDER THE WORKTREE, NOT TMPDIR (Proofdelve ForgeOs-z25x): a masked seat's
# TMPDIR is not a path it can read back afterwards, so a log it cannot open is
# the same as no log. .verify/ is gitignored.
verify_quiet=false
quiet_log=""
verify_step_count=0
if [ -n "${VERIFY_QUIET:-}" ] && [ "${VERIFY_QUIET}" != "0" ]; then
  verify_quiet=true
  mkdir -p "${repo_root}/.verify"
  quiet_log="${repo_root}/.verify/verify-$(date +%Y%m%dT%H%M%S)-$$.log"
  : > "$quiet_log"
  # A failing step's own output is kept beside it for the same reason.
  : "${VERIFY_STEP_LOG_DIR:=${repo_root}/.verify}"
  export VERIFY_STEP_LOG_DIR
fi

if [ "$verify_quiet" = false ]; then
  printf 'Verifying repo_root: %s\n' "$repo_root"
fi

# TREE IDENTITY IN EVERY VERIFIER EVENT (Proofdelve ForgeOs-mlo, made visible rather than
# fixed). repo_root above is derived from THIS FILE'S location, so running a
# worktree's copy verifies that worktree and running main's copy verifies main -
# and until now the emitted event said neither. Four Mayor harness runs verified
# main while believing they verified a candidate worktree, and the record could
# not tell anyone. Naming the tree is what turned a silent wrong-tree run into a
# visible one; it did not stop one, and four Mayor runs proved that visible is
# not caught. The guard above is what prevents it now (Proofdelve ForgeOs-afdr). This block
# still matters for the case the guard deliberately allows through: a caller
# outside any git tree, where the banner is the only thing naming the target.
tree_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
tree_commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ "$verify_quiet" = true ]; then
  # One line carrying what the two default banner lines carry, so quiet mode
  # loses no tree identity -- the thing Proofdelve ForgeOs-mlo and Proofdelve ForgeOs-afdr are about.
  printf 'verify: QUIET  branch %s at %s in %s\n' "$tree_branch" "$tree_commit" "$repo_root"
  printf 'verify: full output is being written to %s\n' "$quiet_log"
else
  printf 'Verifying branch %s at %s\n' "$tree_branch" "$tree_commit"
fi
# treeMismatch lives in tree_payload, not in the verify.pass payload alone, so a
# cross-tree run that FAILS or is killed mid-run still leaves the marker in the
# durable record (Warden finding 5 on Proofdelve ForgeOs-afdr). verify.run, verify.fail and
# verify.pass all carry it.
# THE HARNESS REF IS RESOLVED ONCE, HERE, AND NAMED IN EVERY VERIFY EVENT
# (Proofdelve ForgeOs-1k3d). harness_path() below reads main's copy of each instrument.
# Until 2026-09-16 it read `main:` LIVE at each step, minutes after verify.run
# named the commit under test, so a harness change landing on main mid-run was
# picked up by the later steps of a run already in flight: the fleet's post-merge
# log for 80ce8675 shows a case that exists only in 7085cc90, and the green it
# recorded was measured with an instrument the record does not name. Resolving
# main to a SHA once, before the first event, makes one run read one instrument
# set, and harnessRef in the payload lets a reader reproduce it. The instrument
# stays CURRENT main on purpose: pinning to the merge-base would run the stale
# copy a branch was cut with, which is Proofdelve ForgeOs-75hn's bug coming back.
harness_ref="$(git -C "$repo_root" rev-parse --verify main 2>/dev/null)" || {
  harness_ref=main
  echo "verify: WARNING could not resolve main to a SHA; harnesses will be read from the live ref and harnessRef records \"main\" (the Warden, 1k3d f3)" >&2
}
# DIRTY-TREE MARKER AND END-OF-RUN IDENTITY (Proofdelve ForgeOs-l3l8). Five instances in
# three days (w4fm.4.2, .4.3, .8.3, .8.4, eng3.19): a Forge runs the verifier
# BEFORE committing, or commits mid-run, and the payload names HEAD at start
# (the branch base) with treeMismatch:false, so "verified at commit X" reads as
# a clean-tree pass at X for a run whose subject was uncommitted work. Two facts
# now ride every verify event: dirtyAtStart (tracked files modified when the
# run began; untracked ignored, the fleet's landability rule) and, on the
# terminal event, commitAtEnd / dirtyAtEnd / headMoved. A reader asking "was
# <commit> verified" can now tell a pass on committed X from a pass on X plus
# edits, and a run that outlived a commit says so.
# Record files are exempt, as in fleet.sh's tree_dirty (fleet_record_paths):
# fort/events/*.jsonl and .beads/ are append-only records that are dirty in
# every live session and are not the subject of any verify.
verify_record_paths='^(\.beads/|fort/events/)'
tree_dirty_count() {  # -> number of modified TRACKED non-record files; never fails
  git -C "$repo_root" status --porcelain --untracked-files=no 2>/dev/null | sed 's/^...//' | grep -Evc "$verify_record_paths" || true
}
dirty_start_count="$(tree_dirty_count)"
dirty_at_start=false; [ "${dirty_start_count:-0}" -gt 0 ] && dirty_at_start=true
# OUTSIDE A GIT TREE THIS IS 0, NOT A DEATH (the Warden's blocking finding 1 on fortkit-ttpk,
# 2026-11-18): under pipefail a failing `git ls-files` failed the whole assignment, set -e
# ended the run before its first step with exit 128 and no message, and every Warden scratch
# copy is such a tree. The steps below say what they could not check; this line only counts.
untracked_start_count="$( { git -C "$repo_root" ls-files --others --exclude-standard -- src test 2>/dev/null || true; } | wc -l | tr -d ' ')"  # Proofdelve ForgeOs-ju6r8: recorded on every event; the untracked-source-clean step refuses the pass
tree_payload="\"tree\":\"${repo_root}\",\"branch\":\"${tree_branch}\",\"commit\":\"${tree_commit}\",\"treeMismatch\":${tree_mismatch},\"harnessRef\":\"${harness_ref:0:12}\",\"dirtyAtStart\":${dirty_at_start},\"untrackedAtStart\":${untracked_start_count:-0}"
[ "$dirty_at_start" = false ] || printf 'verify: NOTE the tree is DIRTY at start (%s tracked file(s) modified); this run scores the working tree, not commit %s alone (Proofdelve ForgeOs-l3l8)\n' "$dirty_start_count" "$tree_commit" >&2
tree_end_json() {  # -> commitAtEnd, dirtyAtEnd, headMoved for the terminal event; never fails
  local c d n
  c="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  n="$(tree_dirty_count)"
  d=false; [ "${n:-0}" -gt 0 ] && d=true
  local moved=false; [ "$c" = "$tree_commit" ] || moved=true
  printf '"commitAtEnd":"%s","dirtyAtEnd":%s,"headMoved":%s' "$c" "$d" "$moved"
}

emit_events=true
if [ "${CI:-}" != "" ]; then
  emit_events=false
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-emit) emit_events=false ;;
    *)
      echo "Usage: fort/scripts/verify.sh [--no-emit]" >&2
      exit 2
      ;;
  esac
  shift
done

emit() {
  if [ "$emit_events" = true ]; then
    local actor="${FORT_ACTOR:-harness}"
    local status=0

    if [ -n "${FORT_SEAT:-}" ]; then
      fort/scripts/emit.sh "$@" -a "$actor" -s "$FORT_SEAT" || status=$?
    else
      fort/scripts/emit.sh "$@" -a "$actor" || status=$?
    fi

    if [ "$status" -ne 0 ]; then
      printf 'WARNING: failed to emit verifier event (exit %s); continuing verification.\n' "$status" >&2
    fi
  fi
}

# A FAILING STEP'S OUTPUT IS THE ONLY THING THAT MAKES IT DIAGNOSABLE, AND UNTIL
# 2026-09-10 THIS FUNCTION THREW IT AWAY (Proofdelve ForgeOs-g0ev, acceptance 4). The
# verify.fail event carried the step name and an exit code and nothing else, so
# a red step could only be investigated by re-running it by hand and hoping it
# failed again. That cost this fort two undiagnosable failures on 2026-09-10 at
# 15:22 and 15:24; the third, at 19:24, was diagnosable ONLY because the fleet's
# post-merge path happens to keep its worktree and its own log. The pre-review
# verifier has no such luck, and it is the one that runs on every bead.
#
# The output is TEE'd, not redirected: a redirect would silence a long dotnet
# build until it finished, and the narrative log going quiet for four minutes is
# how an operator learns to stop reading it. tee reads all of its input and never
# exits early, so the step can never be signalled by it -- which matters more than
# usual here, because Proofdelve ForgeOs-g0ev WAS a step killed by SIGPIPE from a reader that
# did exit early. ${PIPESTATUS[0]} is the step's own status; $? would be tee's.
#
# The log is kept ONLY on failure. A green step deletes it, so this adds nothing
# to a clean run but one file created and removed per step.
run_step() {
  local step="$1"
  shift

  # SKIPPED BY THE TIER (Proofdelve ForgeOs-s1reg): said as SKIP, never as PASS, and listed.
  if tier_skips "$step"; then
    skipped_steps+=("$step")
    if [ "$verify_quiet" = true ]; then
      printf 'verify: %-28s SKIP      (tier %s)\n' "$step" "$verify_tier"
    else
      printf 'verify: %s SKIPPED (tier %s)\n' "$step" "$verify_tier"
    fi
    return 0
  fi

  local logdir="${VERIFY_STEP_LOG_DIR:-${TMPDIR:-/tmp}}"
  local log="${logdir}/verify-fail-${step}-$$.log"
  mkdir -p "$logdir" 2>/dev/null || true
  # A STEP MAY SAY IT SKIPPED ITS REAL WORK (Proofdelve ForgeOs-4webo, the Warden's p84gg finding
  # 3). run_step knows only exit codes, and the step runs on the left of a
  # pipeline, i.e. in a subshell, so a variable would not survive (the :362
  # lesson). A step that exits 0 having done only part of its job writes one
  # line of why into $VERIFY_STEP_SKIP_FILE; run_step then prints SKIP rather
  # than PASS and lists the step in skippedSteps. Exit codes are unchanged.
  local skipf="${logdir}/verify-skip-${step}-$$"
  rm -f "$skipf"
  export VERIFY_STEP_SKIP_FILE="$skipf"

  # set +e AROUND THE PIPELINE, DELIBERATELY. This file runs under `set -e`
  # (:18), so a bare failing pipeline would abort the shell BEFORE the line
  # below could read ${PIPESTATUS[0]} -- the status would be lost and the
  # careful reporting underneath would never run. `|| true` is NOT a substitute:
  # it is a separate simple command, and it resets PIPESTATUS.
  local started=$SECONDS
  set +e
  if [ "$verify_quiet" = true ]; then
    # tee still reads all of its input and never exits early (the SIGPIPE
    # property Proofdelve ForgeOs-g0ev turns on); only its stdout is redirected, so the
    # terminal sees nothing and both logs see everything.
    "$@" 2>&1 | tee -a "$quiet_log" >"$log"
  else
    "$@" 2>&1 | tee "$log"
  fi
  local status=${PIPESTATUS[0]}
  set -e
  local elapsed=$(( SECONDS - started ))
  verify_step_count=$(( verify_step_count + 1 ))

  if [ "$status" -eq 0 ]; then
    rm -f "$log"
    if [ -s "$skipf" ]; then
      local skipwhy; skipwhy="$(head -1 "$skipf" 2>/dev/null || true)"; rm -f "$skipf"
      skipped_steps+=("$step")
      if [ "$verify_quiet" = true ]; then
        printf 'verify: %-28s SKIP %4ds (%s)\n' "$step" "$elapsed" "$skipwhy"
      else
        printf 'verify: %s exited 0 and SKIPPED its real work: %s\n' "$step" "$skipwhy"
      fi
      return 0
    fi
    rm -f "$skipf"
    if [ "$verify_quiet" = true ]; then
      printf 'verify: %-28s PASS %4ds\n' "$step" "$elapsed"
    fi
    return 0
  else
    rm -f "$skipf"
    local end_json payload
    end_json="$(tree_end_json)"
    payload="{\"step\":\"${step}\",\"exitCode\":${status},\"log\":\"${log}\",${tree_payload},${end_json}}"
    if [ "$status" -eq 127 ]; then
      payload="{\"step\":\"${step}\",\"exitCode\":${status},\"toolMissing\":true,\"log\":\"${log}\",${tree_payload},${end_json}}"
    fi
    if [ "$verify_quiet" = true ]; then
      printf 'verify: %-28s FAIL %4ds (exit %s)\n' "$step" "$elapsed" "$status"
    fi
    echo "verify: step '${step}' FAILED (exit ${status}). Its full output is kept at ${log}" >&2
    if [ "$verify_quiet" = true ]; then
      echo "verify: the whole run's output up to this point is at ${quiet_log}" >&2
    fi
    echo "verify: last 40 lines of that step, repeated here so a reader of this stream alone can act:" >&2
    tail -40 "$log" >&2 || true
    emit verify.fail "Verifier failed at ${step} on ${tree_branch}" -p "$payload" -t "$tree_branch"
    exit "$status"
  fi
}

# THE docker FIELD. The fort this verifier came from skipped its migration tests
# when Docker was down and recorded docker:false. {{FORT_NAME}}'s gate has no step
# that needs Docker, so no run is ever filtered for want of it. The field stays
# in the verify.pass payload and the result file because fleet.sh and the
# Warden's brief read it, and here it is constant: true means no step was skipped
# for a missing host service. VERIFY_REQUIRE_DOCKER is accepted and changes nothing.
docker_available=true

# THE TIER (Proofdelve ForgeOs-s1reg item 3). VERIFY_TIER names which steps this run may
# skip, and it is CHOSEN BY THE CALLER FROM THE DIFF, never by a seat: fleet.sh's
# verify_tier_of() reads `git diff --name-only main...HEAD` in the bead's own
# worktree and sets it on the host verify. Unset means full, so every hand run,
# every seat run and the post-merge and nightly runs are unchanged.
#   full     every step.
#   docs     docs/ and fort/handoffs/ only: lints and harnesses, no build, no tests.
#   harness  scripts/ (never verify-impl.sh): the product steps are skipped.
#   web      accepted and never chosen: {{FORT_NAME}} has no web tier.
#   server   src/ and test/ only: the machinery harnesses are skipped.
# A skipped step is printed as SKIP and listed in skippedSteps on verify.pass,
# so a reader of the record sees exactly what did not run. An unknown tier is a
# refusal, never a quiet fall-back to full or to nothing.
verify_tier="${VERIFY_TIER:-full}"
case "$verify_tier" in
  full|docs|harness|web|server) ;;
  *) echo "verify: unknown VERIFY_TIER '${verify_tier}' (full|docs|harness|web|server)" >&2; exit 2 ;;
esac
# READ ONCE, THEN UNSET: the harnesses this file runs invoke verify-impl.sh on
# fixtures, and an inherited tier or result file would make those inner runs
# skip steps or write the CALLER's result file (found at the sitting's own full
# verify, b878e70d). Nothing below this line reads the environment copies.
verify_result_file="${VERIFY_RESULT_FILE:-}"
unset VERIFY_TIER VERIFY_RESULT_FILE
tier_server_steps=" product-gate "
tier_web_steps=" "
# THE FORT'S OWN MACHINERY CHECKS (Overseer 2026-11-13, test-depth-follows-risk):
# every *-harness step, shellcheck and harness-source-pins test fort/scripts,
# scripts/ and tools, never product code. fleet.sh's verify_tier_of picks web,
# server or docs only when the diff touches none of fort/ (bar handoffs),
# scripts/ or tools/keep/, so those tiers cannot have changed what these steps
# test; they skip them (about 5 of a run's ~11 minutes). The harness and full
# tiers, and the nightly full verify of main, still run every one.
tier_is_machinery_step() {  # $1 step -> 0 when it tests the fort's own machinery
  case "$1" in
    *-harness|shellcheck|harness-source-pins) return 0 ;;
    *) return 1 ;;
  esac
}
tier_skips() {  # $1 step -> 0 when this run's tier skips it
  case "$verify_tier" in
    full)    return 1 ;;
    web)     [[ "$tier_server_steps" == *" $1 "* ]] || tier_is_machinery_step "$1" ;;
    server)  [[ "$tier_web_steps" == *" $1 "* ]] || tier_is_machinery_step "$1" ;;
    docs)    [[ "$tier_server_steps$tier_web_steps" == *" $1 "* ]] || tier_is_machinery_step "$1" ;;
    harness) [[ "$tier_server_steps$tier_web_steps" == *" $1 "* ]] ;;
  esac
}
skipped_steps=()
skipped_json() {  # -> the skipped step names as a JSON array; never fails
  if [ "${#skipped_steps[@]}" -eq 0 ]; then printf '[]'; return 0; fi
  printf '%s\n' "${skipped_steps[@]}" | jq -R . | jq -sc . 2>/dev/null || printf '[]'
}

# THE STEP LIST HAS ONE SOURCE (Proofdelve ForgeOs-g5oc): the run_step calls in this file,
# read at start, plus npm-audit (a warning step that is not a run_step). Two
# hand-copied literals stood here and at the verify.pass emit until 2026-09-17;
# Proofdelve ForgeOs-roau added stranded-sweep-harness at :602 and updated neither, so a
# verify.pass told the durable record a step list it did not run (the Warden, m37a f3).
# The plan lists every run_step in the file (indented ones too) whether or not a
# condition skips it at run time, exactly as the literals did. Requires jq (already a dependency
# of every harness this file runs).
steps_json="$(grep -oE '^[[:space:]]*run_step +[A-Za-z0-9-]+' "${BASH_SOURCE[0]}" | awk '{print $2}' | awk '!seen[$0]++' | jq -R . | jq -sc '. + ["npm-audit"]')"
[ -n "$steps_json" ] || { echo "verify: could not derive the step list from ${BASH_SOURCE[0]}" >&2; exit 3; }

emit verify.run "Verifier started on ${tree_branch}" -p "{\"steps\":${steps_json},\"tier\":\"${verify_tier}\",${tree_payload}}" -t "$tree_branch"
[ "$verify_tier" = full ] || printf 'verify: TIER %s (chosen from the diff by the caller): the steps it skips are printed as SKIP and listed in skippedSteps (Proofdelve ForgeOs-s1reg)\n' "$verify_tier"
# memory-lint runs first: it takes seconds, needs no build, and a red ledger
# should fail before the expensive gates do. It enforces the fact schema, the
# per-seat core budget, superseded-by resolution, and untrusted-never-core
# (fortkit docs/specs/memory.md 4.4). Proofdelve ForgeOs-fkmm.4.
# locked-dir-clean (Proofdelve ForgeOs-x0ki). fort/scripts is kernel read-only to every
# masked seat precisely because what lives there GETS RUN by the host. An
# untracked file in it is therefore invisible to git, invisible to every review
# diff, and — if it ends in anything but .sh — invisible to the shellcheck step
# as well. All three at once.
#
# Observed, not imagined (standing order 15): fort/scripts/warden.sh.eng3.5.bak
# sat there from 2026-08-29 to 2026-08-31, mode 755, untracked, byte-identical to
# warden.sh at a18eab6 and therefore missing BOTH the eng3.5 concurrency lock and
# the u65j.3 build-server settings. It was rsynced into the Warden's scratch copy,
# so it travelled. Nothing ran it; the hazard was a person or a seat reading it as
# the live launcher, or restoring it, and silently losing three fixes at once.
# Found by the Warden reading a directory listing, which is not a gate.
#
# Deliberately ANY untracked file, not just executables: no seat can create one
# here (the mount is read-only), so anything untracked arrived from outside the
# sandbox and nobody intended it to be permanent. If a file genuinely belongs
# here, commit it; if it genuinely does not, it does not belong in a directory
# whose contents the host executes.
#
# IT MUST NOT PASS VACUOUSLY OUTSIDE A GIT TREE (Warden finding 2 on
# Proofdelve ForgeOs-u65j.3.1). The first version ran `git ls-files` unguarded. run_step
# invokes the predicate as an `if` condition, which suspends set -e inside it, so
# in a non-git directory the command substitution failed, $stray came back empty,
# the step reported GREEN and a bare `fatal: not a git repository` appeared in the
# middle of a passing run. The Warden's own scratch copy has no .git BY
# CONSTRUCTION, and :107-111 documents a caller outside any git tree as a
# SUPPORTED mode, so this was the common case and not an exotic one. It now says
# what it could not check, which is the Proofdelve ForgeOs-7gs lesson: a probe that cannot
# run must say so rather than pass.
# WIDENED TO THREE DIRECTORIES 2026-09-19 (Proofdelve ForgeOs-9vx7). Every word of the
# argument above applies to .claude/ and fort/profiles/ and the gate did not cover
# them. .claude/settings*.json is gate-6 constitution, kernel read-only to every
# seat, and READ BY THE HOST HARNESS at every session start, which is a stronger
# version of "gets run": a settings file shapes what every seat may do before any
# seat runs. fort/profiles/ is the third of the class and holds the masks
# themselves. The concrete instance that prompted this: .claude/.proven-config-version
# and .claude/proven-config.json sat untracked from 2026-08-03 to 2026-09-19,
# ruflo residue nothing in this fort put there and nothing knew read.
#
# ORDER MATTERS AND IT WAS FOLLOWED: the disposition came FIRST. The Overseer
# removed both files by hand on 2026-09-19 (no seat could; the mount is read-only
# to all of them) and said so on the bead, and all three directories were then
# measured clean of untracked files before this widening was written. A gate that
# goes red on day one and stays red is a gate somebody disables.
# A STEP THAT COULD NOT CHECK SAYS SO IN THE RECORD, NOT ONLY ON STDERR (Regent
# sitting 2026-11-20, fortkit-awlc; the Warden's finding 1 on batch 1). Printing
# NOT CHECKED and returning 0 left the step reading PASS in quiet mode and the
# verify.pass event carrying skippedSteps: []. run_step's skip file is the
# mechanism for exactly this (Proofdelve ForgeOs-4webo): one line of why, and
# the step is shown as SKIP and listed. The exit code is unchanged.
step_not_checked() {  # $1 one line of why
  if [ -n "${VERIFY_STEP_SKIP_FILE:-}" ]; then printf '%s\n' "$1" > "$VERIFY_STEP_SKIP_FILE" 2>/dev/null || true; fi
  return 0
}
locked_dirs=(fort/scripts .claude fort/profiles)

locked_dir_clean() {
  local stray d
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "verify: locked-dir-clean NOT CHECKED — not inside a git tree, so untracked" >&2
    echo "        files under ${locked_dirs[*]} cannot be enumerated here (Proofdelve ForgeOs-x0ki)." >&2
    step_not_checked "not inside a git tree"
    return 0
  fi
  # NAMED PER DIRECTORY, not as one merged list: a reader has to know WHICH
  # kernel-locked directory grew a file, because the remedy differs (a launcher
  # gets committed; ruflo residue in .claude gets deleted by the Overseer).
  local rc=0
  for d in "${locked_dirs[@]}"; do
    [ -e "$d" ] || continue
    stray="$(git ls-files --others --exclude-standard -- "$d")"
    if [ -n "$stray" ]; then
      echo "verify: untracked files in kernel-locked directory $d (Proofdelve ForgeOs-x0ki, Proofdelve ForgeOs-9vx7):" >&2
      while IFS= read -r f; do echo "  $f" >&2; done <<< "$stray"
      rc=1
    fi
  done
  if [ "$rc" != 0 ]; then
    echo "Commit them or delete them. Nothing untracked belongs where the host executes" >&2
    echo "or where the harness reads before any seat runs." >&2
    return 1
  fi
  return 0
}

run_step locked-dir-clean locked_dir_clean

# EVIDENCE LOGS BELONG UNDER evidence/, NOT AT THE REPO ROOT (Proofdelve ForgeOs-hmdo8,
# approved by the Overseer 2026-10-15). Five observed instances before this
# step existed (2md9d.3.12.1 twice, sk3c.11, 15k.18, 2md9d.2.24.3), and the
# Mayor moved fifteen by hand that morning. A bead's criteria naming evidence/
# was not enough: a Forge that writes its red-arm transcript wherever it ran
# the test leaves it at the root, and the root became the fort's evidence
# drawer. Checks tracked files AND untracked, non-ignored ones, so a Forge's
# own verify on its uncommitted tree catches the file before it is committed.
root_evidence_clean() {
  local stray
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "verify: root-evidence-clean NOT CHECKED — not inside a git tree (Proofdelve ForgeOs-hmdo8)." >&2
    step_not_checked "not inside a git tree"
    return 0
  fi
  stray="$( { git ls-files; git ls-files --others --exclude-standard; } \
    | grep -E '^[^/]*-(tests|red|green)\.txt$' | sort -u)"
  if [ -n "$stray" ]; then
    echo "verify: evidence logs at the repo root (Proofdelve ForgeOs-hmdo8):" >&2
    while IFS= read -r f; do echo "  $f" >&2; done <<< "$stray"
    echo "Move them under evidence/ (git mv <file> evidence/<file>)." >&2
    return 1
  fi
  return 0
}
run_step root-evidence-clean root_evidence_clean

# THE VERIFIED WORKTREE MUST BE THE COMMIT (Proofdelve ForgeOs-ju6r8). Measured 2026-10-21 by
# The Warden on Proofdelve ForgeOs-413u8.40: a WIP-rescued tip omitted three NEW source files,
# the committed tree failed dotnet build with 10 errors (CS0246), and the host
# verify.pass at that tip was GREEN with dirtyAtStart:false, because the files sat
# untracked in the worktree and dirtyAtStart counts tracked files only. Had the
# review approved, the fleet would have merged a commit that does not build.
# Untracked, NON-IGNORED files under the build's own inputs make the run score
# files the commit does not contain, so this step refuses the pass. Scoped to
# src/, tests/ and web/src/ deliberately: anything else untracked does not reach
# the build or the suites, and the repo root has its own guards (above). Ignored
# outputs (bin/, obj/, App_Data/, node_modules/) never count.
untracked_source_paths=(src test)
untracked_source_clean() {
  local stray
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "verify: untracked-source-clean NOT CHECKED — not inside a git tree (Proofdelve ForgeOs-ju6r8)." >&2
    step_not_checked "not inside a git tree"
    return 0
  fi
  stray="$(git ls-files --others --exclude-standard -- "${untracked_source_paths[@]}")"
  if [ -n "$stray" ]; then
    echo "verify: untracked files under ${untracked_source_paths[*]}; this run would score files commit $(git rev-parse --short HEAD) does not contain (Proofdelve ForgeOs-ju6r8):" >&2
    while IFS= read -r f; do echo "  $f" >&2; done <<< "$stray"
    echo "Commit them (git add <path>) or delete them, then verify again." >&2
    return 1
  fi
  return 0
}
run_step untracked-source-clean untracked_source_clean
run_step memory-lint node fort/memory/memory-lint.mjs

# fact-freshness (Proofdelve ForgeOs-o33d.1). ADVISORY, and deliberately NOT a run_step and
# NOT in the steps payload above. run_step turns a non-zero exit into a failed
# verify, and this must never fail one: whether a memory file is current is an
# unrelated question to whether this change is sound, and a gate that blocks a
# legitimate commit on it gets disabled the first time it does. Listing it as a
# step would also claim it as a gate in the durable event record, which is the
# Proofdelve ForgeOs-afdr class -- a payload asserting coverage the run did not have.
#
# Scoped to the change in hand rather than the whole backlog. Backlog mode
# (no range) currently reports 13 facts, which is the honest standing debt and
# exactly the wrong thing to print on every verify: thirteen unchanging lines
# become furniture, and then the one new line nobody notices. Run
# `node fort/memory/fact-freshness.mjs` by hand for the backlog.
if [ -x fort/memory/fact-freshness.mjs ] || [ -f fort/memory/fact-freshness.mjs ]; then
  freshness_range=""
  if [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" != "main" ] \
     && git rev-parse --verify --quiet main >/dev/null 2>&1; then
    freshness_range="main...HEAD"
  elif git rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
    freshness_range="HEAD~1..HEAD"
  fi
  if [ -n "$freshness_range" ]; then
    node fort/memory/fact-freshness.mjs "$freshness_range" || true
  fi
fi
# file-budget (Proofdelve ForgeOs-413u8.12, wired by Proofdelve ForgeOs-2md9d.4.48). ADVISORY for the
# same reasons as fact-freshness above: coding-standards rule 4 is the Warden's
# to enforce, so a WARN line here informs the review and never fails a verify.
# The script picks its own range (main...HEAD on a branch, HEAD~1..HEAD on main).
bash scripts/file-budget-check.sh || true
run_step seat-lint node scripts/seat-lint.mjs
run_step merge-events scripts/merge-event-check.sh
# The isolation gate (Regent sitting 2026-11-18, fortkit-ttpk, docket item I1): this
# fort's machinery was copied from another fort's, and must name none of that
# fort's runtime.
run_step isolation-check bash "$repo_root/scripts/isolation-check.sh" --root "$repo_root"
run_step isolation-check-harness env ISOLATION_CHECK_SH="$repo_root/scripts/isolation-check.sh" bash "$repo_root/scripts/isolation-check-harness.sh"
# -x follows sourced files so fort/scripts/lib/* is linted too, not skipped.
#
# scripts/*.sh JOINED THE GATE 2026-09-04 (Proofdelve ForgeOs-8zwv item 2, the Warden's finding 13
# on the covenant 4.5 review of the fleet). It had never been linted, and by then
# five of this fort's host-run scripts lived there including three fleet harnesses
# the Regent had to shellcheck BY HAND during the sitting because this line does
# not reach them. A gate that covers one of the two directories the fort actually
# runs scripts from is a gate with a shape rather than a boundary.
#
# WIDENED ONLY AFTER MEASURING WHAT IT WOULD SAY, because the fleet is enabled and
# a red post-merge verifier writes $FLEET_STATE/HALT, which stops every later run
# until a person removes it by hand. `shellcheck -x scripts/*.sh` exited 1 on five
# findings across two files before this change: an SC2015 && || chain in
# apply-u65j5.sh, and in u65j-reproduce.sh an unused `sock` plus three patterns
# that are DELIBERATE and now carry disables with their reasons — pgrep is the
# thing that file's own comments refuse (it matches its own command line, and the
# pkill form killed the calling shell on 2026-08-31), and `kill $pids` splits a
# pid list on purpose. Fixed first, then widened; `shellcheck -x scripts/*.sh`
# exits 0 as of this commit. Widening a gate before measuring it would have turned
# main red and halted the fleet on the first night, which is the opposite of what
# a gate is for.
# tools/keep/*.sh joined 2026-09-13 (the Warden finding 5 on Proofdelve ForgeOs-o6ky.6, record
# Proofdelve ForgeOs-3p3c): the Keep's install.sh and uninstall.sh are host-run by the
# Overseer and were outside every lint until then, so their bead's shellcheck
# criterion was met by hand rather than by the gate.
run_step shellcheck shellcheck -x fort/scripts/*.sh fort/scripts/lib/*.sh scripts/*.sh
# HARNESS SOURCE PINS (Proofdelve ForgeOs-fqle7, from Proofdelve ForgeOs-t2mw1; the w8iez class). Every
# harness_path step below runs from a temp copy at harness_ref, so a default derived from
# its own directory ($0, BASH_SOURCE) resolves into that temp dir and scores the
# wrong file. scripts/harness-source-pins.sh reads this file's run_step lines and
# each harness's defaults (it never executes either) and names every default that
# is self-relative and not pinned on its step. Wired only after the live run was
# clean at f668e341: 8ueq8.1 fixed the 14 findings and the checker's own false
# positives, and hc6nc/x3m5g closed a false negative first, so main did not go
# red on wiring.
run_step harness-source-pins bash "$repo_root/scripts/harness-source-pins.sh" "$repo_root/scripts/verify-impl.sh"
# THE FLEET'S OWN HARNESSES JOIN THE GATE (Proofdelve ForgeOs-l4jw, from the Warden's finding 5 on
# Proofdelve ForgeOs-dx34.1). They are the real verifier for fort/scripts/fleet.sh and until
# now NOTHING RAN THEM ON A LANDING: this file shellchecked them and never
# executed them, and the Warden's profile cannot reach a script under scripts/ at
# all, so the fort's review of its own dispatcher rested on reading plus whatever
# the sitting reported.
#
# FLEET_SH IS PINNED TO THE TREE UNDER TEST, AND THAT IS THE WHOLE TRICK. Each
# harness defaults to the ABSOLUTE path of main's fleet.sh, so run from a bead's
# worktree they would score MAIN's copy and report it as the candidate's result --
# Proofdelve ForgeOs-afdr exactly, the cross-tree class this verifier already guards with
# treeMismatch. Measured 2026-09-09 BEFORE wiring, per Proofdelve ForgeOs-8zwv's precedent
# (measure what a gate will say before widening it, because a red post-merge
# verifier writes the halt file): governor 36/0, landable 15/0, postmerge 11/0,
# stop 19/0, ~3.1s together.
#
# TWO ARE DELIBERATELY EXCLUDED, and each exclusion is a bead rather than a
# preference (a third, verdict-record-harness.sh, was excluded from 2026-09-09
# until Proofdelve ForgeOs-675g repaired it and is wired below):
#   fleet-e2e-harness.sh -- it EXECUTES fleet.sh, which refuses inside any mask
#     (fleet.sh:370, exit 64), so from a Forge or Warden session this stage would
#     be red on every landing for a reason that is not the landing's. The "stub
#     Warden never started in s4" wording this note carried until 2026-09-11 was
#     that refusal's downstream symptom, misread as the harness's own ({{BEAD_PREFIX}}-
#     g0ev); the harness now refuses up front and names the mask. It also takes
#     52s against ~3.1s for all four below. Host-side runs are the Regent's and
#     the Overseer's; the exclusion here stays.
#   dispatch-guard-harness.sh -- needs a bead-id fixture it cannot invent here
#     (Proofdelve ForgeOs-8zwv item 1, still open).
# Proofdelve ForgeOs-75hn: THE HARNESSES ARE INSTRUMENTS, NOT THE SUBJECT, so pin them to
# main and score the subject (fleet.sh / warden.sh, already pinned via FLEET_SH
# or the arg) from the worktree. A bead branch cut before a harness fix -- the
# g0ev SIGPIPE repair (bf09552) is the case that bit us -- otherwise runs the
# STALE, flaky instrument from its own worktree against green work and false-
# escalates it (Proofdelve ForgeOs-b0vj.3.2, the fleet's first false escalation; measured
# 34/40 on the stale copy vs 40/40 on main's, same fleet.sh). Same principle as
# FLEET_SH pinning (Proofdelve ForgeOs-afdr), one level up.
# THE EXCEPTION IS THE afdr CASE IN REVERSE (75hn criterion 3): if THIS bead's
# own diff changes a harness, that harness IS the subject and must be run from
# the worktree, or the bead's change would be scored by main's old copy. So:
# main's copy, UNLESS `git diff main...HEAD` touches scripts/<h>.sh.
# SCOPE, stated honestly: this protects every branch cut AFTER it lands. An
# already-cut worktree runs its OWN (old) verify-impl.sh on the pre-merge verify,
# so it must be brought current before it builds; forge.sh now does exactly that
# at re-dispatch, merging main into the reused worktree and refusing (exit 76,
# paged) when the merge cannot be made (Proofdelve ForgeOs-lw8x, 75hn's Regent-lane half).
# b0vj.3.2 was the worked example, refreshed by hand before the launcher did it.
# The post-merge verify already runs in a fresh worktree at the merged sha
# and so always had current instruments; this closes the pre-merge gap.
hdir="$(mktemp -d)"
mainrel="$(git -C "$repo_root" merge-base "$harness_ref" HEAD 2>/dev/null || echo main)"   # the subject discriminator and the instrument observe ONE main (the Warden, 1k3d f1)
harness_path() {  # $1 harness basename -> prints a path to the instrument to run
  local h="$1" wt="$repo_root/scripts/$1.sh"
  # Does this bead's own branch modify the harness? Then it is the subject. Compare the working
  # tree, not HEAD: a Forge that verifies before committing its harness edit must score its own copy
  # (Proofdelve ForgeOs-9s6y6: gbxub's in-session verify scored main's preview-harness on 11-07).
  if [ -n "$(git -C "$repo_root" diff --name-only "$mainrel" -- "scripts/$h.sh" 2>/dev/null)" ]; then
    printf '%s' "$wt"; return
  fi
  # Otherwise run main's copy, never the worktree's, so a stale one cannot flake.
  # Read from the SHA resolved at verify start, never from the live ref (1k3d).
  if git -C "$repo_root" show "$harness_ref:scripts/$h.sh" > "$hdir/$h.sh" 2>/dev/null; then
    chmod +x "$hdir/$h.sh"; printf '%s' "$hdir/$h.sh"
  else
    printf '%s' "$wt"   # new harness not yet on main: only the worktree has it
  fi
}
run_step governor-harness  env FLEET_SH="$repo_root/fort/scripts/fleet.sh" bash "$(harness_path governor-harness)"
run_step landable-harness  env FLEET_SH="$repo_root/fort/scripts/fleet.sh" bash "$(harness_path landable-harness)"
run_step postmerge-harness env FLEET_SH="$repo_root/fort/scripts/fleet.sh" bash "$(harness_path postmerge-harness)"
run_step stop-harness      env FLEET_SH="$repo_root/fort/scripts/fleet.sh" bash "$(harness_path stop-harness)"
# review-throughput-harness (Proofdelve ForgeOs-6niaz, Regent sitting 2026-11-11): finding tiers,
# FIX-FORWARD, the Workbench landing class and stacking offer, and the Forge's stamped-verify
# citation, each against the shipped launchers. The run-level FIX-FORWARD lap is fleet-e2e, host-only.
run_step review-throughput-harness env FLEET_SH="$repo_root/fort/scripts/fleet.sh" WARDEN_SH="$repo_root/fort/scripts/warden.sh" WORKBENCH_SH="$repo_root/fort/scripts/workbench.sh" FORGE_SH="$repo_root/fort/scripts/forge.sh" bash "$(harness_path review-throughput-harness)"
# VERIFY ONCE (Proofdelve ForgeOs-s1reg): the tier rules, the reuse decision and this
# file's own tier table, against the shipped code; and the nightly full verify
# that backstops both. The run-level replay is fleet-e2e-harness.sh scenario 67,
# host-only like the rest of that harness.
run_step verify-once-harness env FLEET_SH="$repo_root/fort/scripts/fleet.sh" VERIFY_IMPL_SH="$repo_root/scripts/verify-impl.sh" bash "$(harness_path verify-once-harness)"
run_step nightly-verify-harness env NIGHTLY_SH="$repo_root/fort/scripts/nightly-verify.sh" bash "$(harness_path nightly-verify-harness)"
# Node's compile cache stays off in the four launchers that carry the
# node_compile_cache block, and the block really disables it in a child node
# (Proofdelve ForgeOs-jfqu4.8 / Proofdelve ForgeOs-x1n09, Regent docket 2026-10-22 item B).
run_step node-cache-harness env NODE_CACHE_ROOT="$repo_root" bash "$(harness_path node-cache-harness)"
# A RED host verify returns the failing step, not the log's tail (Proofdelve ForgeOs-tgm5o,
# Regent docket 2026-10-22 item C): evidence_of() in fleet.sh over fixture logs.
run_step evidence-harness env FLEET_SH="$repo_root/fort/scripts/fleet.sh" bash "$(harness_path evidence-harness)"
# The supervisor harness is black-box over fort/scripts/fleet-supervisor.sh with
# its root repointed at a scratch fort (Proofdelve ForgeOs-dx34.4). Its subject comes
# via SUPERVISOR_SH (the FLEET_SH analogue), so the pinned-from-main copy still
# tests the worktree's fleet-supervisor.sh (Proofdelve ForgeOs-75hn).
run_step supervisor-harness env SUPERVISOR_SH="$repo_root/fort/scripts/fleet-supervisor.sh" bash "$(harness_path supervisor-harness)"
# The refresh harness is the instrument for Proofdelve ForgeOs-lw8x: it extracts
# refresh_reused_worktree() from fort/scripts/forge.sh and also runs the launcher
# itself, root-repointed and truncated at the refresh block, against git fixtures.
# Its subject comes via FORGE_SH, the same shape as FLEET_SH above.
run_step forge-refresh-harness env FORGE_SH="$repo_root/fort/scripts/forge.sh" bash "$(harness_path forge-refresh-harness)"
# The airlock harness (Proofdelve ForgeOs-x6hq, Proofdelve ForgeOs-5fyc) drives fort/scripts/airlock.sh
# against a fixture fort under AIRLOCK_ROOT: a completed operation announces
# itself under the category its table declares, a failed one does not, and a
# run made by hand is recordable. Subject via AIRLOCK_SH, table via AIRLOCK_OPS.
# Measured before wiring: shipped airlock.sh at f5008528 3/4 (no emit, no
# announce verb), the sitting's 7/0. Under a second.
run_step airlock-harness env AIRLOCK_SH="$repo_root/fort/scripts/airlock.sh" AIRLOCK_OPS="$repo_root/fort/airlock/operations.json" bash "$(harness_path airlock-harness)"
# bead-archive-harness (Proofdelve ForgeOs-a8yqk; wired by the Mayor 2026-11-07 on its review's finding 3): pins the
# archive-verify-then-prune tool's refusals with a red arm. Under a second, no network, no live tracker.
run_step bead-archive-harness env BEAD_ARCHIVE_SRC="$repo_root/scripts/bead-archive.sh" bash "$(harness_path bead-archive-harness)"
# The verdict-recording harness is the instrument for Proofdelve ForgeOs-9mfw.5 and it
# extracts the REAL tail of fort/scripts/warden.sh, so warden.sh is its target
# rather than fleet.sh. Excluded from 2026-09-09 to 2026-09-11 because it scored
# the shipped file 0/9 and the pre-fix file 9/0 (Proofdelve ForgeOs-675g: the e44m hoist
# moved three symbols above its extraction anchor and its only vacuity guard was
# a line count). Measured BEFORE wiring, per the precedent above: shipped
# warden.sh 18/0, warden.sh at d7b5614 16/2 failing on the e44m-hoist case, two
# anchor-drift variants REFUSE at 3 naming the symbol. ~0.5s.
run_step verdict-record-harness bash "$(harness_path verdict-record-harness)" "$repo_root/fort/scripts/warden.sh"
# scratch-reaper-harness (Proofdelve ForgeOs-2sdo, from nv0j): 24 cases on the reaper that
# sweeps dead Warden scratch and merged-and-closed worktrees; exit 3 without it.
#
# SWEEP_SH IS PINNED HERE FOR THE SAME REASON REAPER_SH IS, and it was missing
# (Proofdelve ForgeOs-w8iez, the Warden's round-two blocking finding, 2026-09-22). harness_path()
# runs MAIN's copy of an instrument out of a mktemp dir, so the harness's own
# `root="${ROOT:-$(dirname $0)/..}"` resolves to the mktemp PARENT -- /tmp. A
# harness that defaults its subject from $root therefore looks for
# /tmp/scripts/stranded-sweep.sh, does not find it, and REFUSES with exit 3;
# run_step treats any nonzero as fatal, so the verifier goes red for every bead
# that does not itself modify that harness. Measured by the Warden: "HARNESS REFUSES:
# sweep is missing: /tmp/scripts/stranded-sweep.sh", exit 3.
#
# This line is the Mayor's because scripts/verify-impl.sh is kernel read-only to
# The Forge. Two Forge rounds could not reach it, which is why w8iez came back
# twice: the defect was in the file the seat doing the work cannot write. Split
# the lanes rather than re-dispatching into a wall.
run_step scratch-reaper-harness env REAPER_SH="$repo_root/fort/scripts/scratch-reaper.sh" SWEEP_SH="$repo_root/scripts/stranded-sweep.sh" bash "$(harness_path scratch-reaper-harness)"
# loop-watchdog-harness (Proofdelve ForgeOs-dycc9, Proofdelve ForgeOs-76uob.6; Regent sitting 2026-11-16): the
# watchdog that alerts the Overseer when the Mayor goes silent or the pool stays dry.
# Fixture event streams and a stub bd; each condition true and false, the one-alert
# latch, and four generated red arms. LOOP_WATCHDOG_SH pins the subject for the
# temp-copy run (Proofdelve ForgeOs-fqle7).
run_step loop-watchdog-harness env LOOP_WATCHDOG_SH="$repo_root/fort/scripts/loop-watchdog.sh" bash "$(harness_path loop-watchdog-harness)"
# session-reap-harness (Proofdelve ForgeOs-ab495; Regent sitting 2026-11-16): forge.sh and warden.sh
# kill what a session left running under its worktree or scratch copy. Real detached
# fixture processes; bystanders and the caller must survive. Subjects pinned for the
# temp-copy run (Proofdelve ForgeOs-fqle7).
run_step session-reap-harness env -u SESSION_REAP_GRACE_S SESSION_REAP_LIB="$repo_root/fort/scripts/lib/session-reap.sh" FORGE_SH="$repo_root/fort/scripts/forge.sh" WARDEN_SH="$repo_root/fort/scripts/warden.sh" bash "$(harness_path session-reap-harness)"
# signature-source-harness (Proofdelve ForgeOs-jib0; Regent sitting 2026-11-16): only the Keep's own
# events (actor justin, seat overseer) are read as sign events by latest_approved_sha();
# a Mayor or Regent transcription neither supersedes an approval nor counts as one.
run_step signature-source-harness env FLEET_SH="$repo_root/fort/scripts/fleet.sh" bash "$(harness_path signature-source-harness)"
# workbench-merge-harness (Proofdelve ForgeOs-guue7; Regent sitting 2026-11-16): workbench.sh merges
# main into the session branch on the host before the seat starts, because the seat cannot
# once main has changed fort/scripts. Five outcomes on fixture repositories.
run_step workbench-merge-harness env WORKBENCH_SH="$repo_root/fort/scripts/workbench.sh" bash "$(harness_path workbench-merge-harness)"
# THE MASK HARNESS IS A GATE STEP ON THE HOST, AND SAYS SO WHERE IT CANNOT RUN
# (Regent sitting 2026-11-20, fortkit-awlc; the Warden's findings on 98b6dd1 and
# 7738e76). workbench-mask-harness builds a real mask
# with bwrap and read permissions from inside it: the Keep stores, other forts,
# the tokens. It refuses inside a seat mask
# (a mask cannot build a mask), and until now that meant it ran only when
# someone remembered to. On the host (the fleet's own verify, the nightly, the
# Regent) it now runs as a step. Inside a seat mask, or where bwrap is absent,
# the step prints NOT CHECKED, is recorded as SKIP (step_not_checked), and does
# not fail the run: a seat's green says nothing about these properties, and
# both its output and its verify.pass event say so.
mask_harness_step() {  # $1 harness basename, $2 the launcher it measures
  if [ -n "${FORT_MASKED:-}" ]; then
    echo "verify: $1 NOT CHECKED — this run is inside the '$FORT_MASKED' seat mask, and a mask cannot build a mask. The host verify runs it." >&2
    step_not_checked "inside the '$FORT_MASKED' seat mask"
    return 0
  fi
  if ! command -v bwrap >/dev/null 2>&1 || ! bwrap --bind / / --dev /dev -- /bin/true >/dev/null 2>&1; then
    echo "verify: $1 NOT CHECKED — bwrap is missing or user namespaces are unavailable here." >&2
    step_not_checked "bwrap or user namespaces unavailable"
    return 0
  fi
  bash "$(harness_path "$1")" "$2"
}
run_step workbench-mask-harness mask_harness_step workbench-mask-harness "$repo_root/fort/scripts/workbench.sh"
# mask-harness (fortkit-awlc, 2026-11-24): the lib's own assertion set on a
# fixture fort, including the rename rows (A4c) that show a directory holding a
# read-only path cannot be moved aside. It existed since August and no gate ran
# it; the parent-rename hole it now measures stood the whole time. It reads the
# real ~/.claude files with zero-byte appends and permission tests only.
if [ -f "$repo_root/scripts/mask-harness.sh" ]; then
  run_step mask-harness mask_harness_step mask-harness "$repo_root/fort/scripts/lib/seat-sandbox.sh"
fi
# herald-launcher-harness (fortkit-awlc, audit 2026-11-24 items 5.1 and 5.2): the
# Herald launcher's report gate and smoke gate, driven with a stub session in a
# fixture civilization under the real mask. It builds a mask, so it runs on the
# host and reads NOT CHECKED inside a seat mask. Only a fort that hosts the
# civilization layer has the launcher.
if [ -f "$repo_root/civ/scripts/herald.sh" ]; then
  run_step herald-launcher-harness mask_harness_step herald-launcher-harness "$repo_root/civ/scripts/herald.sh"
fi
# posture-rule-harness (fortkit-awlc, the Warden's finding 3 on 6527455): the
# lib's fort_posture() is the one rule for which sandbox posture is in effect,
# and nothing else under fort/scripts decides it. No mask is built.
run_step posture-rule-harness bash "$(harness_path posture-rule-harness)" "$repo_root/fort/scripts"
# branch-reaper-harness (Proofdelve ForgeOs-043u item A, from the Warden's finding 1 on
# Proofdelve ForgeOs-u1m3: "Until wired, the harness exists and nothing runs it"). It landed
# with u1m3 and nothing executed it for two days, for the same reason the sweep
# harness above went unrun: scripts/verify-impl.sh is kernel read-only to the
# Forge that wrote the harness, so a discriminating test existed that no gate ran.
# Subject via BRANCH_REAPER_SH, the same shape as SWEEP_SH and REAPER_SH.
#
# MEASURED BEFORE WIRING, per the verdict-record-harness precedent, 2026-09-19 at
# main 0c436520: shipped scripts/branch-reaper.sh scores 6 pass / 0 fail in 2.6 s.
# Mutation control: replacing the ancestry guard at branch-reaper.sh:85 with
# `if false` scores 4 pass / 2 FAIL, so the harness discriminates. WORTH RECORDING
# BECAUSE IT IS NOT THE CASE THE BEAD PREDICTED: the two that go red are the
# attached and ref-moved accounting cases, while "unmerged branch with no worktree
# still exists after refusal" stays GREEN under that mutation -- `git branch -d`
# refuses an unmerged branch on its own, so the explicit ancestry check is
# defence-in-depth behind git's own guard rather than the only thing holding that
# case. The dangerous shape u1m3 was about needs the guard removed AND -d changed
# to -D; one half of it is not enough to reach the branch.
#
# Its own lock case was an unbounded spin until Proofdelve ForgeOs-8rx8m (closed) bounded it
# with LOCK_START_TIMEOUT_SECONDS, default 5; wiring it before that landed would
# have hung the verifier rather than failed it, which is why this bead carried a
# sequencing note naming 8rx8m as a prerequisite. Verified closed before wiring.
run_step branch-reaper-harness env BRANCH_REAPER_SH="$repo_root/scripts/branch-reaper.sh" bash "$(harness_path branch-reaper-harness)"
# locked-dir-clean-harness (Proofdelve ForgeOs-9vx7). The locked-dir-clean step above has
# guarded fort/scripts since Proofdelve ForgeOs-x0ki with NO executed control, and its own
# comment records what that cost: the first version passed VACUOUSLY outside a git
# tree and the Warden found it by reading a listing. Widening it to .claude/ and
# fort/profiles/ without a test would have been the same bet twice.
#
# Its subject is THIS FILE, and it extracts the locked_dirs array and the function
# verbatim rather than holding a copy, so it cannot drift from what runs. Its red
# arms are only reachable in a temporary repository, because all three guarded
# directories are kernel read-only to every masked seat -- which is the whole reason
# they are guarded. One red arm per entry in locked_dirs, driven by the subject's own
# array, so a fourth directory added there grows the test automatically.
#
# MEASURED BEFORE WIRING, 2026-09-19: 8 pass / 0 fail in under a second. Mutation A,
# stripping $d from the header, scores 4 pass / 4 FAIL. Mutation B, restoring the
# original silent non-git return, scores 7 pass / 1 FAIL. Its FIRST version was itself
# vacuous on mutation A (8/0) because `git ls-files -- fort/scripts` prints
# `fort/scripts/stray.bak`, so the directory name arrived through the file listing
# whether or not the header named it; the assertion is now anchored to the header
# line. Recorded because a harness that had to be mutated before it could fail is the
# Proofdelve ForgeOs-8zb7 lesson happening to the instrument rather than to the subject.
run_step locked-dir-clean-harness env VERIFY_IMPL_SH="$repo_root/scripts/verify-impl.sh" bash "$(harness_path locked-dir-clean-harness)"
# untracked-source-clean-harness (Proofdelve ForgeOs-ju6r8): hermetic red arms for the step above, extracted verbatim from this file.
run_step untracked-source-clean-harness env VERIFY_IMPL_SH="$repo_root/scripts/verify-impl.sh" bash "$(harness_path untracked-source-clean-harness)"
# stranded-sweep-harness (Proofdelve ForgeOs-k5vq, wired by the Mayor under Proofdelve ForgeOs-roau
# finding 2): the harness shipped with k5vq and nothing executed it, because
# scripts/verify-impl.sh is kernel read-only to the Forge that wrote it, so a
# discriminating test existed that no gate ran. Its subject comes via SWEEP_SH,
# the same shape as FLEET_SH above. Measured BEFORE wiring, per the
# verdict-record-harness precedent: shipped stranded-sweep.sh 3 pass / 0 fail;
# a mutated branch_has_advanced() that always returns true scores 2/1, fixture 1
# catching it. Note fixtures 2 and 3 pass under that mutation -- the Warden's finding 3
# records fixture 3 as structurally vacuous, and Proofdelve ForgeOs-m37a repairs it. ~1s.
run_step stranded-sweep-harness env SWEEP_SH="$repo_root/scripts/stranded-sweep.sh" bash "$(harness_path stranded-sweep-harness)"
# The source-pin checker's own harness (Proofdelve ForgeOs-0o0k6, the Warden's finding 1 on fqle7):
# the checker gates this file since fqle7, and an edit that made it silently
# false-clean (the class d1vid, hc6nc and x3m5g each fixed by hand) would pass
# every other gate. Its checker default is self-relative, so the pin is required;
# the harness-source-pins step above would report it missing.
run_step harness-source-pins-harness env HARNESS_SOURCE_PINS_SRC="$repo_root/scripts/harness-source-pins.sh" bash "$(harness_path harness-source-pins-harness)"
# The advisory file-budget check's own harness (Proofdelve ForgeOs-413u8.12, wired by
# Proofdelve ForgeOs-2md9d.4.48): the advisory above can never fail a verify, so this is
# the only gate on whether it still reports what rule 4 asks.
run_step file-budget-check-harness env FILE_BUDGET_CHECK_SRC="$repo_root/scripts/file-budget-check.sh" bash "$(harness_path file-budget-check-harness)"
# skills-watch-harness (Proofdelve ForgeOs-wzdtr, wired by the Mayor after it landed 2026-10-27): the
# change list of skills and commands the Overseer monitors (his condition for accepting the
# Proofdelve ForgeOs-f5c5a risk). SKILLS_WATCH_SH pins the subject for the temp-copy run (Proofdelve ForgeOs-fqle7).
run_step skills-watch-harness env -u SKILLS_WATCH_RED_ARM SKILLS_WATCH_SH="$repo_root/scripts/skills-watch.sh" bash "$(harness_path skills-watch-harness)"
# bead-export-harness (Proofdelve ForgeOs-5bcsl, wired by the Mayor after it landed 2026-10-27): the
# slim tracked export drops comments and old closed beads' long text, and must keep every
# id and created_at for bead-citation-check. BEAD_EXPORT_SRC pins the subject, because the
# harness runs from a temp copy where its own dirname is the wrong place (Proofdelve ForgeOs-fqle7).
run_step bead-export-harness env BEAD_EXPORT_SRC="$repo_root/scripts/bead-export.sh" bash "$(harness_path bead-export-harness)"
# queue-lint-harness (Proofdelve ForgeOs-yn3n F5 and Proofdelve ForgeOs-zx04.1 F3, wired by the Mayor
# under Proofdelve ForgeOs-kawx, 2026-09-17): scores the Mayor's queue-lint.sh, its prose-
# blocker stage and flag-human.sh against a stubbed bd, 21 cases in ~1.3 s. The
# pinned-from-main copy defaults its three sources to $here (its own directory),
# which is the temp dir under harness_path, so every source is named explicitly
# and points at the tree under test.
# MISROUTED_SRC IS PINNED HERE FOR THE SAME REASON AS EVERY OTHER _SRC ON THIS
# LINE, and it turned main RED on 2026-09-23 before anyone added it. The harness
# defaults each source to "$here/...", where $here is the harness's OWN
# directory -- and harness_path extracts the harness from the main ref into a
# temp dir, so $here is NOT the repo's scripts/. Proofdelve ForgeOs-76uob.2 merged a
# harness needing scripts/unattended-fleet/misrouted.py, the default resolved to
# a path that does not exist, and the harness refused with "HARNESS REFUSES:
# source missing", exit 3, failing the post-merge verify at 95ea0872.
#
# THE FORGE COULD NOT HAVE FIXED THIS. This file is kernel read-only to that
# seat and Mayor-writable, so a bead that adds a harness source can pass its own
# review and still red main until the Mayor wires it. Same split-lane shape as
# Proofdelve ForgeOs-w8iez and Proofdelve ForgeOs-m1qgy. Running the harness by hand from scripts/
# hides it, because there $here IS the real directory and every default
# resolves.
run_step queue-lint-harness env QUEUE_LINT_SRC="$repo_root/scripts/queue-lint.sh" PROSE_BLOCKERS_SRC="$repo_root/scripts/unattended-fleet/prose-blockers.py" STALE_PARENTS_SRC="$repo_root/scripts/unattended-fleet/stale-parents.py" FLAG_HUMAN_SRC="$repo_root/scripts/flag-human.sh" MISROUTED_SRC="$repo_root/scripts/unattended-fleet/misrouted.py" UNSHAPED_SOURCE="$repo_root/scripts/unattended-fleet/unshaped.py" UNATTENDED_FLEET_CHECKLIST_SRC="$repo_root/fort/checklists/unattended-fleet-run.md" bash "$(harness_path queue-lint-harness)"
# dispatch-type-harness (Proofdelve ForgeOs-ogpc.1 F2, same wiring): black-box over
# fleet.sh's dispatch-type classifier with a baked fixture record, 9 cases in
# ~0.3 s; its subject comes via FLEET_SH like the four above, ROOT via env.
run_step dispatch-type-harness env ROOT="$repo_root" FLEET_SH="$repo_root/fort/scripts/fleet.sh" bash "$(harness_path dispatch-type-harness)"
# wrong-tree-guard-harness (Proofdelve ForgeOs-t5vq): re-runs the five postures of THIS
# file's wrong-tree refusal (Proofdelve ForgeOs-afdr) plus the linked-worktree case, by the
# original technique (an invalid argument dies at parse, exit 2, after the
# guard). Its subject is the live verify-impl.sh, so an edit to the prologue is
# checked by the gate it protects. RED control measured 2026-09-17: with the
# `exit 78` removed, cases 1 and 6 fail.
run_step wrong-tree-guard-harness env VERIFY_IMPL_SRC="$repo_root/scripts/verify-impl.sh" bash "$(harness_path wrong-tree-guard-harness)"
# push-ready-harness (Proofdelve ForgeOs-47mq found it unwired 2026-09-17): the push gate's
# eleven outcomes plus the ssh-agent warning, hermetic.
run_step push-ready-harness env PUSH_READY_SRC="$repo_root/scripts/push-ready.sh" bash "$(harness_path push-ready-harness)"
# Proofdelve ForgeOs-owhuw (Regent edict 2026-11-09): warden.sh clears a read-only scratch
# rig before removing it, so a Warden's own a-w inversion rig cannot kill the
# next review at launch (0o16s, 2026-11-09 15:21). Plain bash, no bwrap: safe
# in every seat mask.
run_step warden-scratch-harness env WARDEN_SH="$repo_root/fort/scripts/warden.sh" bash "$(harness_path warden-scratch-harness)"
# bead-citation-check (Proofdelve ForgeOs-x5u9): every {{BEAD_PREFIX}}-<id> cited in shipped source
# resolves against the tracked export and none predates its bead. The check
# reads .beads/issues.jsonl and refuses without it (exit 3), so it runs only
# where the export is present: a Warden scratch without .beads/ skips it and
# says so rather than going red on a file the review did not touch. Its own
# harness runs everywhere.
run_step bead-citation-harness env CITATION_CHECK_SRC="$repo_root/scripts/bead-citation-check.sh" bash "$(harness_path bead-citation-harness)"
# CITATION_UNRESOLVED=warn in the gate: the first hard-gate run (23:44 on
# 2026-09-17) halted the fleet on Proofdelve ForgeOs-ubgx.5, a bead filed that evening and
# cited in a README before the tracked export was refreshed. REISSUED still fails.
# AN EMPTY EXPORT IS NOT A REFUSAL (Regent sitting 2026-11-18, fortkit-ttpk, found by
# founding a fort and running its verifier): the check exits 3 when the export holds no
# id, which is right for a damaged export and wrong for a fort that has filed no bead
# yet. A newly founded fort is exactly that, and its verifier stopped here before it
# reached its product gate. No bead means no citation can be wrong; say so and go on.
if [ -r "$repo_root/.beads/issues.jsonl" ] && [ ! -s "$repo_root/.beads/issues.jsonl" ]; then
  echo "verify: bead-citation-check SKIPPED: .beads/issues.jsonl is empty (this fort has filed no bead yet); the harness above still ran" >&2
elif [ -r "$repo_root/.beads/issues.jsonl" ]; then
  run_step bead-citation-check env CITATION_UNRESOLVED=warn bash "$repo_root/scripts/bead-citation-check.sh" "$repo_root"
else
  echo "verify: bead-citation-check SKIPPED: no .beads/issues.jsonl in this tree (the Warden scratch shape); the harness above still ran" >&2
fi


run_step digest-harness bash "$repo_root/scripts/digest-harness.sh"
npm_audit_clean=true
if ! npm audit --audit-level=high >/dev/null 2>&1; then
  npm_audit_clean=false
  printf 'verify: WARNING npm audit reports a high advisory (not a gate here). Run: npm audit --audit-level=high\n' >&2
fi

# THE PRODUCT GATE, A STUB (see the head of this file). Replace the function body
# with this fort's own build, lint and tests, split into run_step calls of their own
# above this line if a tier should be able to skip them, and delete the stub.
product_gate_stub() {
  echo 'product-gate: NO PRODUCT GATE IS WIRED. Every machinery step above ran; this fort has not yet said how its own code is built and tested. Edit scripts/verify-impl.sh.' >&2
  return 1
}
run_step product-gate product_gate_stub
# Repeated at the tail on purpose (Proofdelve ForgeOs-afdr). The wrong-tree run this gate
# was filed for looked exactly like a good one at the bottom of the output, which
# is the only part anyone reads after a long run. treeMismatch rides into the
# verify.pass payload for the same reason docker:false does: it is the only
# coverage caveat that survives into the durable record.
if [ "$tree_mismatch" = true ]; then
  printf 'CROSS-TREE VERIFY — you were standing in %s and this scored %s (Proofdelve ForgeOs-afdr).\n' "$caller_root" "$repo_root_real" >&2
fi
if [ "$verify_quiet" = true ]; then
  printf 'verify: RESULT PASS  %s steps run (%s of them SKIPPED; tier %s) on %s at %s\n' "$verify_step_count" "${#skipped_steps[@]}" "$verify_tier" "$tree_branch" "$tree_commit"
  printf 'verify: full output: %s\n' "$quiet_log"
fi
end_json_final="$(tree_end_json)"
emit verify.pass "Verifier passed on ${tree_branch}" -p "{\"steps\":${steps_json},\"tier\":\"${verify_tier}\",\"skippedSteps\":$(skipped_json),\"docker\":${docker_available},\"npmAuditClean\":${npm_audit_clean},${tree_payload},${end_json_final}}" -t "$tree_branch"
# THE RESULT FILE (Proofdelve ForgeOs-s1reg item 1). The fleet reuses a branch verify as
# main's post-merge pass only when it knows, from THIS run and not from the
# event stream, which commit and TREE were scored, at what tier, and whether
# Docker ran. Written only on a pass and only when the caller asks; a run that
# fails or dies leaves no file, which the caller reads as "do not reuse".
if [ -n "$verify_result_file" ]; then
  printf '{"result":"pass","tier":"%s","docker":%s,"commit":"%s","tree":"%s","dirtyAtStart":%s,%s,"skippedSteps":%s}\n' \
    "$verify_tier" "$docker_available" "$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo unknown)" \
    "$(git -C "$repo_root" rev-parse 'HEAD^{tree}' 2>/dev/null || echo unknown)" "$dirty_at_start" "$end_json_final" "$(skipped_json)" \
    > "$verify_result_file" || echo "verify: WARNING could not write the result file $verify_result_file" >&2
fi
