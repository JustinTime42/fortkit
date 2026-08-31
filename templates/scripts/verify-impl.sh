#!/bin/bash
# {{PROJECT}} verifier — fill in the fort's own gates below. Exit 0 only after every required quality gate passes.
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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

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

run_step() {
  local step="$1"
  shift

  if "$@"; then
    return 0
  else
    local status=$?
    local payload="{\"step\":\"${step}\",\"exitCode\":${status}}"
    if [ "$status" -eq 127 ]; then
      payload="{\"step\":\"${step}\",\"exitCode\":${status},\"toolMissing\":true}"
    fi
    emit verify.fail "Verifier failed at ${step}" -p "$payload"
    exit "$status"
  fi
}

merge_event_check() {
  # The Forge ports the checker before the Regent can add fort-init's explicit
  # copy line. A fort founded in that narrow interval must not inherit a
  # verifier that fails on every run; announce the unavailable factory artifact
  # instead. Once the copy line lands, this same stage runs the fence from the
  # fort's first merge without another verifier edit.
  if [ ! -x scripts/merge-event-check.sh ]; then
    printf 'merge-event-check: SKIPPED — factory has not yet installed scripts/merge-event-check.sh.\n' >&2
    return 0
  fi
  scripts/merge-event-check.sh
}

emit verify.run "Verifier started" -p '{"steps":["seat-lint","merge-events","typecheck","lint","test","shellcheck"]}'
# THE ROSTER'S THREE RULES, run every session rather than once at founding: no two
# actor ids one keystroke apart, no other settlement's citizen in a Held-by or
# Personality line, no unfilled placeholder surviving once the moot has named this
# fort. (That last rule is stated here WITHOUT writing a brace pair, deliberately: the
# render lint refuses any brace literal whose token spelling is not [A-Z_]+, and a
# comment quoting the thing it describes fails a zero-tolerance check exactly like a
# live instruction. This fort has now paid for that class five times.)
# It is in the VERIFIER and not in the factory because the factory runs ONCE per fort
# while roster edits happen forever afterward, at every moot and every reseating.
#
# A CORRECTLY FOUNDED FORT PASSES THIS ON DAY ZERO WHILE STILL FULL OF PLACEHOLDERS.
# Before the moot the registry carries "fort_name": null, which is the signal that
# placeholders are legal; rules 2 and 3 then announce a SKIP and exit 0. That skip is
# correct behaviour, and a founding smoke that reads it as a failure would be wrong.
run_step seat-lint node scripts/seat-lint.mjs
# Every merge after the factory's audit checkpoint must have an append-only
# merge event. This travels with the template so a new fort has the fence from
# its first merge, rather than discovering the omission in a later digest.
run_step merge-events merge_event_check
run_step typecheck npm run typecheck
run_step lint npm run lint
run_step test npm run test
# -x follows sourced files so fort/scripts/lib/* is linted too, not skipped.
run_step shellcheck shellcheck -x fort/scripts/*.sh fort/scripts/lib/*.sh
emit verify.pass "Verifier passed" -p '{"steps":["seat-lint","merge-events","typecheck","lint","test","shellcheck"]}'
