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

emit verify.run "Verifier started" -p '{"steps":["typecheck","lint","test","shellcheck"]}'
run_step typecheck npm run typecheck
run_step lint npm run lint
run_step test npm run test
# -x follows sourced files so fort/scripts/lib/* is linted too, not skipped.
run_step shellcheck shellcheck -x fort/scripts/*.sh fort/scripts/lib/*.sh
emit verify.pass "Verifier passed" -p '{"steps":["typecheck","lint","test","shellcheck"]}'
