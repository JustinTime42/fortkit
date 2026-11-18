#!/bin/bash
# nightly-verify.sh -- one FULL verify of main, with Docker required, on the host
# (ForgeOs-s1reg item 2; the Overseer approved the design on the bead,
# 2026-10-19, before any edit).
#
# WHY IT EXISTS. Since s1reg the fleet verifies a bead ONCE: a host verify picked
# by tier from the bead's diff, and a post-merge run only when main moved or the
# host verify could not stand for main (fleet.sh, verified_reusable()). Tiers
# skip steps by design, and a reused pass re-tests nothing. This run is the
# backstop for both: every night, main at its current tip, every step, Docker
# required, in a fresh worktree so nothing in $root's working tree is scored.
#
# A RED MAIN HALTS THE FLEET, EXACTLY AS A POST-MERGE RED DOES. The halt file is
# written, a fleet run in flight sees it between passes and stops, the
# supervisor starts nothing, and a person removes it by hand. The failed
# worktree is KEPT and named: it is the evidence.
#
# FOUR OUTCOMES, NOT TWO (postmerge_verify()'s rule):
#   0   green        main is green at that commit; the worktree is removed.
#   1   red          main is red; halt file written, worktree kept, incident.
#   69  unrunnable   nothing was measured (no main, no worktree; or the
#                    verifier ran and measured nothing: Docker down, a refusal,
#                    a harness refusing -- verify_unrunnable()); incident, NO
#                    halt -- the next night is free to try. It emits ran:false,
#                    so it does not count as a nightly outcome for fleet.sh.
#   75  busy         another nightly holds the lock; nothing done.
#   130/143 interrupted by a signal: not a verdict; no halt, worktree kept.
#   64  refused inside a seat mask (FORT_MASKED): this is a host act.
#
# It runs whether or not a fleet run is live, deliberately: a run can last
# eight hours, and a nightly that waited for an idle fleet would rarely run.
set -uo pipefail
if [ -n "${FORT_MASKED:-}" ]; then
  echo "nightly-verify.sh: REFUSED inside a seat mask (FORT_MASKED=$FORT_MASKED). The nightly verify is a host act: its timer, or a person." >&2
  exit 64
fi

# >>> node_compile_cache: KEEP BYTE-IDENTICAL in fort/scripts/fleet.sh, fort/scripts/forge.sh, fort/scripts/nightly-verify.sh and scripts/verify-impl.sh (scripts/node-cache-harness.sh compares them)
# NODE'S ON-DISK COMPILE CACHE IS OFF for every fleet, Forge, nightly and
# verifier run (ForgeOs-jfqu4.8 with ForgeOs-lmgue and ForgeOs-x1n09, Regent
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
echo "$(basename "$0"): Node compile cache disabled for this run (NODE_DISABLE_COMPILE_CACHE=1, ForgeOs-jfqu4.8)" >&2
# <<< node_compile_cache
root="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
state="${FLEET_STATE:-$HOME/.local/state/proofdelve-fleet}"
halt_file="$state/HALT"
mkdir -p "$state/logs"
stamp="$(date +%Y%m%dT%H%M%S)"
log="$state/logs/nightly-verify-$stamp.txt"
emit() { ( cd "$root" && ./fort/scripts/emit.sh "$@" ) || true; }

exec 9>>"$state/nightly-verify.lock"
if ! flock -n 9; then
  echo "nightly-verify.sh: another nightly verify holds $state/nightly-verify.lock; nothing done." >&2
  exit 75
fi

stop_signal=""
# shellcheck disable=SC2329  # invoked by the traps below
on_signal() { stop_signal="$1"; }
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

# >>> verify_unrunnable: KEEP BYTE-IDENTICAL in fort/scripts/fleet.sh and fort/scripts/nightly-verify.sh (nightly-verify-harness.sh compares them)
# UNRUNNABLE IS NOT RED (ForgeOs-s1reg finding 4, Tova's review of docket
# ForgeOs-x7ojh). A nonzero exit from the verifier used to read as "main is
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
#     instrument OR the code it extracts having changed shape (Tova's finding
#     2 on docket ForgeOs-zw3q5), so the words below say "read the step log"
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

sha="$(git -C "$root" rev-parse --verify --quiet refs/heads/main 2>/dev/null)" || sha=""
if [ -z "$sha" ]; then
  echo "nightly-verify.sh: main could not be resolved in $root; nothing measured." | tee "$log" >&2
  emit incident "Nightly verify COULD NOT RUN: main could not be resolved in $root. Nothing was measured; this is NOT a red main and no halt file was written. Evidence: $log" -a fleet -s fleet -p "{\"nightly\":true,\"ran\":false}"
  exit 69
fi
wt="$root-worktrees/nightly-$stamp"
if [ -e "$wt" ] || ! git -C "$root" worktree add --detach "$wt" "$sha" > "$log" 2>&1; then
  echo "nightly-verify.sh: could not create the worktree $wt at $sha; nothing measured. Evidence: $log" >&2
  emit incident "Nightly verify COULD NOT RUN at $sha: the worktree $wt could not be created. Nothing was measured; this is NOT a red main and no halt file was written. Evidence: $log" -a fleet -s fleet -p "{\"nightly\":true,\"ran\":false,\"commit\":\"$sha\"}"
  exit 69
fi

echo "nightly-verify.sh: full verify of main at ${sha:0:12} in $wt (Docker required); log $log"
( cd "$wt" && VERIFY_TIER=full VERIFY_REQUIRE_DOCKER=1 ./fort/scripts/verify.sh ) >> "$log" 2>&1
rc=$?

if [ "$rc" -eq 0 ]; then
  git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || true
  echo "nightly-verify.sh: GREEN at ${sha:0:12}; worktree removed."
  emit progress "Nightly full verify GREEN at $sha (every step, Docker required, fresh worktree, removed after)" -a fleet -s fleet -p "{\"nightly\":true,\"ran\":true,\"result\":\"green\",\"commit\":\"$sha\"}"
  exit 0
fi
if [ -n "$stop_signal" ]; then
  echo "nightly-verify.sh: STOPPED by SIG$stop_signal before it concluded; not a verdict. Worktree kept at $wt." >&2
  emit incident "Nightly verify of $sha was STOPPED by SIG$stop_signal before it concluded. Not a verdict about main; no halt file was written. Worktree kept at $wt" -a fleet -s fleet -p "{\"nightly\":true,\"ran\":false,\"signal\":\"$stop_signal\",\"commit\":\"$sha\"}"
  [ "$stop_signal" = INT ] && exit 130
  exit 143
fi
if verify_unrunnable "$log" "$rc"; then
  git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || true
  echo "nightly-verify.sh: UNRUNNABLE at ${sha:0:12} (exit $rc): $unrunnable_why. Not a measured red; no halt. Evidence: $log" >&2
  emit incident "Nightly verify UNRUNNABLE at $sha (exit $rc): $unrunnable_why. This is not a measured red (nor a green) and no halt file was written; read the log, since an instrument refusal can still mean the code changed. Evidence: $log" -a fleet -s fleet -p "{\"nightly\":true,\"ran\":false,\"result\":\"unrunnable\",\"commit\":\"$sha\",\"exitCode\":$rc}"
  exit 69
fi
why="the nightly full verify is RED at $sha (exit $rc) -- main is red. Evidence: $log; the worktree it failed in is KEPT at $wt. Remove this file by hand once main is green (ForgeOs-s1reg)."
if [ -e "$halt_file" ]; then
  printf '%s\n' "ALSO: $why" >> "$halt_file"
else
  printf '%s\n' "$why" > "$halt_file"
fi
echo "nightly-verify.sh: RED at ${sha:0:12} (exit $rc). The fleet is HALTED: $halt_file. Worktree kept at $wt." >&2
emit incident "NIGHTLY VERIFY RED at $sha (exit $rc): main is red under a full, Docker-required verify. The fleet is HALTED by $halt_file. Evidence: $log; worktree KEPT at $wt" -a fleet -s fleet -p "{\"nightly\":true,\"ran\":true,\"result\":\"red\",\"commit\":\"$sha\",\"exitCode\":$rc,\"worktree\":\"$wt\"}"
exit 1
