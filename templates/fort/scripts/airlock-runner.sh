#!/bin/bash
# Airlock host runner (Proofdelve ForgeOs-mbv54 item A, Regent edict 2026-10-15, the
# Overseer present). Fired by fort/systemd/{{FORT_SLUG}}-airlock-runner.path on
# every write to the Overseer's approvals store, and by
# {{FORT_SLUG}}-airlock-runner.timer as a safety net; runs `airlock.sh run` with
# NO id until it reports nothing left, then exits.
#
# WHAT THIS ADDS, AND WHAT IT DOES NOT. It removes the one typed command from a
# staging deploy: the Mayor requests, he clicks Approve in the Civ Keep, and
# this runs it. `run` with no id selects requests approved IN THE STORE for
# the bytes on disk (airlock.sh, the 72ot.1 rules; the store is read-only in
# every seat mask), AND, since Proofdelve ForgeOs-emshb (Regent sitting 2026-10-23),
# requests for an operation operations.json declares `auto_run` beside
# requires_approval false: host-test and preview-stop. FOR THOSE TWO A REQUEST
# A SEAT WRITES STARTS A RUN with no click, by the Overseer's decision recorded
# on Proofdelve ForgeOs-emshb (host-test executes the named worktree's code on the host,
# with Docker). Everything else still needs his click. An operation declared
# requires_approval:false WITHOUT auto_run (feedback-scan) is NOT run by this
# unit: it is never selected, so a scan still needs a person's
# `airlock.sh run <id>` (scripts/airlock-harness.sh pins both).
#
# WHY A LOOP AND A TIMER (measured 2026-10-15 with a transient path unit): a
# path unit fires on the store's creation and on each append, but an append
# made WHILE the service is still running is dropped and never re-fires. A
# deploy takes minutes, so an approval clicked during one would wait for the
# next click. So: loop until `run` finds nothing, and let the timer catch the
# last window between the final empty check and exit.
#
# Refuses under FORT_MASKED (exit 64): this executes operations that source
# credentials, and it must never be started from a seat.
set -euo pipefail
if [ -n "${FORT_MASKED:-}" ]; then
  echo "airlock-runner: REFUSED - masked seat session (FORT_MASKED=${FORT_MASKED}); this runs on the host only" >&2
  exit 64
fi
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
airlock="${AIRLOCK_SH:-$here/airlock.sh}"
max="${AIRLOCK_RUNNER_MAX_PASSES:-20}"
for ((pass = 1; pass <= max; pass++)); do
  rc=0; out="$(bash "$airlock" run 2>&1)" || rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -ne 0 ]; then
    echo "airlock-runner: airlock.sh run exited $rc on pass $pass; stopping (see the lines above)" >&2
    exit "$rc"
  fi
  if grep -qx 'airlock: nothing approved to run' <<<"$out"; then
    exit 0
  fi
done
echo "airlock-runner: still finding approved requests after $max passes; stopping so the journal shows it" >&2
exit 1
