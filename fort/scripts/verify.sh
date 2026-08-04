#!/bin/bash
# Manyhalls verifier. Exit 0 only after every required quality gate passes.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
    fort/scripts/emit.sh "$@" -a kethra -s forge
  fi
}

run_step() {
  local step="$1"
  shift

  if "$@"; then
    return 0
  else
    local status=$?
    emit verify.fail "Verifier failed at ${step}" -p "{\"step\":\"${step}\",\"exitCode\":${status}}"
    exit "$status"
  fi
}

emit verify.run "Verifier started" -p '{"steps":["typecheck","lint","test","shellcheck"]}'
run_step typecheck npm run typecheck
run_step lint npm run lint
run_step test npm run test
run_step shellcheck shellcheck bin/fort-init fort/scripts/*.sh
emit verify.pass "Verifier passed" -p '{"steps":["typecheck","lint","test","shellcheck"]}'
