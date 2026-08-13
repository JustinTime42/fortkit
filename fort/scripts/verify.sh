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

# fortkit-4n8c. The skills this repo ships are LOADED from ~/.claude/skills, and
# they were installed as independent untracked COPIES. That already bit twice: a
# bead was closed after grepping the copy the session had just edited while the
# repo still carried the retired reference (fortkit-4b9q), and the E2 mask
# harness appended two bytes to the INSTALLED /civ skill, which then ran as
# instruction for eight hours because no control in this fort looks anywhere but
# the repository. E2b replaced the copies with symlinks; this step is what stops
# a later hand-install quietly putting a copy back.
#
# SKIPPING IS ANNOUNCED, NEVER SILENT: on a machine with no installed skill
# surface (CI, a fresh clone) there is nothing to check, and a checker that
# checks nothing must never report success without saying so.
skills_install_check() {
  local base="$HOME/.claude/skills" src name dst bad=0 checked=0
  if [ ! -d "$base" ]; then
    printf 'skills-install: SKIPPED — %s does not exist, so nothing here is installed.\n' "$base" >&2
    return 0
  fi
  for src in skills/*/; do
    [ -d "$src" ] || continue
    name="$(basename "$src")"; dst="$base/$name"; checked=$((checked+1))
    if [ ! -L "$dst" ]; then
      printf 'skills-install: %s is NOT a symlink — an installed copy can diverge from its reviewed source (fortkit-4n8c).\n' "$dst" >&2
      bad=1; continue
    fi
    if [ "$(readlink -f "$dst")" != "$(readlink -f "$src")" ]; then
      printf 'skills-install: %s -> %s, expected %s\n' "$dst" "$(readlink "$dst")" "$(readlink -f "$src")" >&2
      bad=1
    fi
  done
  if [ "$checked" -eq 0 ]; then
    printf 'skills-install: FAILED — examined zero skills under skills/, so this step proved nothing.\n' >&2
    return 1
  fi
  return "$bad"
}

emit verify.run "Verifier started" -p '{"steps":["memory-lint","skills-install","typecheck","browser-typecheck","lint","test","shellcheck"]}'
run_step memory-lint node scripts/memory-lint.mjs
run_step skills-install skills_install_check
run_step typecheck npm run typecheck
run_step browser-typecheck npm run typecheck:browser
run_step lint npm run lint
run_step test npm run test
# -x follows sourced files so fort/scripts/lib/* is linted too, not skipped.
# civ/scripts and bin/regent joined the surface 2026-08-06 (fortkit-1ca: the
# most privileged scripts in the civilization had never been ShellChecked).
# templates/fort/scripts/lib/*.sh joined 2026-08-12 (fortkit-ddvo): the shipped
# lib was linted and the FACTORY's copy of it was not — and the factory copy is
# the one every future fort is founded on. scripts/*.sh joined with it, so the
# repo's own tooling (mask-harness.sh, verify-impl.sh) is on the surface too.
run_step shellcheck shellcheck -x bin/fort-init bin/regent fort/scripts/*.sh fort/scripts/lib/*.sh templates/fort/scripts/*.sh templates/fort/scripts/lib/*.sh civ/scripts/*.sh scripts/*.sh
emit verify.pass "Verifier passed" -p '{"steps":["memory-lint","skills-install","typecheck","browser-typecheck","lint","test","shellcheck"]}'
