#!/bin/bash
# Manyhalls verifier. Exit 0 only after every required quality gate passes.
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
  local base="$HOME/.claude/skills" src name dst bad=0 checked=0 gcd canonical
  if [ ! -d "$base" ]; then
    printf 'skills-install: SKIPPED — %s does not exist, so nothing here is installed.\n' "$base" >&2
    return 0
  fi
  # THE INSTALLED SYMLINK CAN ONLY EVER POINT AT ONE CHECKOUT (fortkit-52vf.9, Warden
  # blocking finding 1). The first version of this step compared readlink -f "$dst"
  # against readlink -f "$src", and $src resolves against the CURRENT tree — so the
  # comparison was false in every checkout except /home/justin/dev/fortkit, this step is
  # 2 of 7, and typecheck/lint/test/shellcheck never ran. It reported failure having
  # verified almost nothing, and the lane it broke is the FORGE's: forge.sh runs
  # `cd "$wt" && ./fort/scripts/verify.sh` in a worktree, so every Forge bead would have
  # drawn a red launcher-observed verifier and standing order 9 could never be satisfied
  # from a worktree. A false red rather than a false green, and still a broken verifier.
  #
  # Resolve the CANONICAL checkout from git's common dir, so a worktree compares against
  # the same target the canonical checkout does instead of against itself.
  gcd="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -z "$gcd" ] || [ ! -d "$gcd" ]; then
    printf 'skills-install: SKIPPED — %s is not a git checkout, so the canonical repository cannot be resolved and an installed symlink cannot be attributed to it.\n' "$PWD" >&2
    return 0
  fi
  canonical="$(cd "$gcd/.." && pwd)" || {
    printf 'skills-install: SKIPPED — could not resolve the canonical checkout from %s.\n' "$gcd" >&2
    return 0
  }
  for src in skills/*/; do
    [ -d "$src" ] || continue
    name="$(basename "$src")"; dst="$base/$name"; checked=$((checked+1))
    if [ ! -L "$dst" ]; then
      printf 'skills-install: %s is NOT a symlink — an installed copy can diverge from its reviewed source (fortkit-4n8c).\n' "$dst" >&2
      bad=1; continue
    fi
    if [ "$(readlink -f "$dst")" != "$canonical/skills/$name" ]; then
      printf 'skills-install: %s -> %s, expected %s\n' "$dst" "$(readlink "$dst")" "$canonical/skills/$name" >&2
      bad=1
    fi
  done
  if [ "$checked" -eq 0 ]; then
    printf 'skills-install: FAILED — examined zero skills under skills/, so this step proved nothing.\n' >&2
    return 1
  fi
  return "$bad"
}

# fortkit-8ib, Overseer ruling 2026-08-13: LINT THE RENDERED OUTPUT, not just the
# templates. The raw templates have been on the shellcheck surface since fortkit-ddvo
# and they pass clean — but a template passing shellcheck does NOT prove that
# SUBSTITUTING its placeholders yields valid bash, and substitution is what every
# founded fort actually runs. The declined alternative was a
# `# shellcheck disable=SC1083` header in each template, which silences the
# placeholder warning and leaves the shipped artifact unchecked.
#
# THE DEADLINE THIS ANSWERS WAS REAL: fortkit-0po6 adds a {{HOME}} placeholder to
# render() and fortkit-fd2 adds {{PLACEHOLDER}} personality tokens to the seat
# files. Both land in files this step covers, and the strategy had to exist before
# the mechanism, not after its first casualty.
#
# WHY THIS DOES NOT REUSE bin/fort-init's render(). Sharing one substitution table
# between the factory and the verifier is the better design and it is NOT AVAILABLE
# TO THIS SEAT: bin/ is kernel read-only to every masked seat
# (fort/scripts/lib/seat-sandbox.sh:187-203), so extracting render() is Regent work.
# What this step proves is therefore the rendered SHAPE, not the factory's VALUES.
# fortkit-domm proves the values, against a really-founded fort. Two layers, and the
# labels are named here because "the templates lint" and "the factory renders
# correctly" are adjacent claims that this bead already lost the distinction between
# once (fortkit-uj3q).
#
# TWO PASSES, because the space pass is the failure mode placeholders introduce:
# an unquoted {{REPO_PATH}} parses fine against /home/justin/dev/fortkit and becomes
# two arguments the moment a path contains a space. Static analysis catches that only
# if the value it sees has one.
#
# ZERO FILES CHECKED IS A FAILURE, NEVER A PASS, and the positive control at the end
# is not decoration: this fort has shipped an anti-vacuity harness wired into nothing
# (fortkit-52vf.12 finding 4) and a probe suite whose every assertion expected deny
# with no permitted control (fortkit-vhk.5.1 finding 8) in the same month.
template_render_lint() {
  local tmp src name rendered checked=0 pass value
  tmp="$(mktemp -d)" || {
    printf 'template-render: FAILED — could not create a scratch directory.\n' >&2
    return 1
  }

  for pass in plain spaced; do
    case "$pass" in
      plain)  value="/home/fortkeeper/dev/scratchfort" ;;
      spaced) value="/home/fort keeper/dev/scratch fort" ;;
    esac
    for src in templates/fort/scripts/*.sh templates/fort/scripts/lib/*.sh templates/scripts/*.sh; do
      [ -f "$src" ] || continue
      name="$(basename "$src")"
      rendered="$tmp/$pass-$name"
      # Generic substitution: ANY {{TOKEN}} becomes the pass value, so a placeholder
      # added tomorrow is covered without editing this list.
      sed -E "s|\{\{[A-Z_]+\}\}|$value|g" "$src" > "$rendered"
      if grep -q '{{' "$rendered"; then
        printf 'template-render: %s still contains an unsubstituted placeholder after rendering — the token spelling does not match [A-Z_]+.\n' "$rendered" >&2
        rm -rf "$tmp"; return 1
      fi
      [ "$pass" = plain ] && checked=$((checked+1))
    done
  done

  if [ "$checked" -eq 0 ]; then
    printf 'template-render: FAILED — rendered zero template scripts, so this step proved nothing.\n' >&2
    rm -rf "$tmp"; return 1
  fi

  if ! shellcheck -x -s bash "$tmp"/*.sh >&2; then
    printf 'template-render: FAILED — %s template scripts rendered, and the rendered output does not pass shellcheck.\n' "$checked" >&2
    rm -rf "$tmp"; return 1
  fi

  # POSITIVE CONTROL. A clean sweep above means nothing unless this step can go red.
  # shellcheck disable=SC2016  # the literal $1 IS the defect being planted; expanding it here
  # would write this verifier's own positional argument into the control and the control would
  # then pass, which is the exact failure this block exists to detect.
  printf '#!/bin/bash\ncd $1\n' > "$tmp/control.sh"
  if shellcheck -x -s bash "$tmp/control.sh" >/dev/null 2>&1; then
    printf 'template-render: FAILED — the positive control passed shellcheck, so a green above proves nothing about the rendered output.\n' >&2
    rm -rf "$tmp"; return 1
  fi

  printf 'template-render: %s template scripts rendered in 2 passes and linted clean; positive control went red as required.\n' "$checked" >&2
  rm -rf "$tmp"
  return 0
}

emit verify.run "Verifier started" -p '{"steps":["memory-lint","skills-install","typecheck","browser-typecheck","lint","test","shellcheck","template-render"]}'
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
# templates/scripts/*.sh joined 2026-08-13 (fortkit-n3bk finding 4): E2b created
# templates/scripts/verify-impl.sh in the same sitting that put the SHIPPED
# scripts/*.sh on the surface, and the factory's copy was left off it — the same
# class as fortkit-ddvo, one directory over. The factory's verifier is the one
# every future fort inherits, so it is exactly the copy that must not rot.
run_step shellcheck shellcheck -x bin/fort-init bin/regent fort/scripts/*.sh fort/scripts/lib/*.sh templates/fort/scripts/*.sh templates/fort/scripts/lib/*.sh templates/scripts/*.sh civ/scripts/*.sh scripts/*.sh
run_step template-render template_render_lint
emit verify.pass "Verifier passed" -p '{"steps":["memory-lint","skills-install","typecheck","browser-typecheck","lint","test","shellcheck","template-render"]}'
