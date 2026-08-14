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

# NO SIGNAL TRAP HERE, DELIBERATELY, AND THIS IS THE THIRD ATTEMPT AT THE SAME
# COSMETIC FIX (fortkit-8ib, Warden findings 6/r1 and 1/r2). The observation being
# declined: template_render_lint's scratch tree survives an interrupt. It cleans up
# explicitly on all five of its return paths, so this only ever concerns SIGINT or
# SIGTERM mid-step, and the residue is one directory under $TMPDIR.
#
# WHAT THE TWO ATTEMPTS COST, both measured rather than reasoned:
#   1. `trap ... RETURN` inside the function. A RETURN trap PERSISTS past the
#      function that sets it and fires again on the next function return, where
#      $tmp is unbound; `set -u` turned MAIN RED.
#   2. `trap '... rm -rf ...' INT TERM` at script level, handler with no `exit`.
#      A signal handler that does not exit makes the script NON-TERMINATING on that
#      signal: bash defers it, runs it, and resumes. Measured on the real artifact —
#      `CI=1 timeout --foreground --signal=TERM 3 fort/scripts/verify.sh --no-emit`
#      ran every remaining step to completion and `timeout` exited 124. Before that
#      commit, bash's default disposition terminated the script. THE VERIFIER IS RUN
#      BY forge.sh AND warden.sh, so a launcher that cannot TERM it is a worse defect
#      than the leak, by a wide margin.
#
# The correct idiom exists (`trap 'cleanup; exit 143' INT TERM`) and is one line. It
# is declined anyway: two regressions in two rounds, in the fort's own gate, to stop
# a temp directory outliving a Ctrl-C. If someone later wants it, the requirement is
# that the handler EXITS and that a TERM test is added alongside it — not the trap on
# its own, which is what failed twice.

# THE TEMPLATE SHELL SURFACE, DEFINED ONCE (Warden finding 3 on fortkit-8ib).
# Two steps lint these files — the raw shellcheck leg and template_render_lint — and
# this fort has been bitten three times by exactly one such list going stale:
# fortkit-ddvo (the lib on the surface, the factory's copy of it not),
# fortkit-n3bk finding 4 (templates/scripts/ left off in the sitting that created it),
# and fortkit-8ib's own SO7 correction (a bead asserting a gap that two passenger
# fixes had already closed). Adding a second enumeration would have doubled that
# surface, so there is one. Globs expand HERE, after the cd to repo_root, so both
# consumers see the identical file list rather than two lists that agree today.
TEMPLATE_SH=(templates/fort/scripts/*.sh templates/fort/scripts/lib/*.sh templates/scripts/*.sh)

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
# THREE PASSES, and the distinguishing case for each is recorded here BECAUSE THE
# FIRST VERSION OF THIS COMMENT RECORDED ONE THAT DOES NOT DISTINGUISH ANYTHING
# (Warden finding 1 on fortkit-8ib, measured with ShellCheck 0.11.0 and re-measured
# before this edit). A later reader who tests the recorded example, finds no
# difference between passes, and deletes one has been misled by this comment rather
# than by the code — which is the fortkit-uj3q class landing in the very block that
# cites it.
#   plain   a normal path. The baseline.
#   spaced  a path containing spaces. THE CASE THAT DISTINGUISHES IT IS A TEST
#           EXPRESSION, NOT A bare cd: `[ -d /home/fort keeper/x ]` is SC1072/SC1073,
#           a hard parse error, while the plain value lints clean. The originally
#           recorded example, `cd {{REPO_PATH}}`, draws SC2164 in BOTH passes and
#           therefore demonstrates nothing about this pass at all.
#   empty   the empty string. bin/fort-init:27-29 renders {{EXTRA_GATES}} and
#           {{EXTRA_ORDERS}} to EMPTY, so a path value is not what the factory
#           actually substitutes for every token. An empty render turns `cd {{X}}`
#           into a bare `cd` and `foo {{X}} bar` into a different command, and
#           neither path pass can see it. This pass is here for the tokens
#           fortkit-0po6 and fortkit-fd2 are about to add; it catches nothing today.
#
# TWO PLACEHOLDERS IN THE SHIPPED TEMPLATES ARE UNQUOTED IN EXECUTABLE POSITION,
# which is worth stating exactly because the round-2 version of this comment claimed
# the opposite (Warden finding 2 on fortkit-8ib, verified here before rewriting):
#   templates/fort/scripts/status.sh:5   ... || echo {{REPO_PATH}})
#   templates/fort/scripts/mayor.sh:14   ... || echo {{REPO_PATH}})
# Both sit inside a $( ), which opens a FRESH quoting context — the enclosing double
# quotes do not carry into it. So the spaced pass is exercising a real unquoted
# placeholder in shipped code right now, not a hypothetical future one. ShellCheck
# does not flag either (a multi-word literal argument to `echo` is legal), which is
# why the step is green over them in all three passes; the point is that the pass
# this comment justifies has a live subject.
#
# Pass values must contain no `&`, `\` or `|`: they are interpolated into the
# replacement half of `s|...|$value|g`, where all three are special — `|` because it
# is the delimiter (Warden finding 3 on fortkit-8ib; bin/fort-init's own render()
# makes the same delimiter choice). All three current values are controlled literals.
#
# ZERO FILES CHECKED IS A FAILURE, NEVER A PASS, and the positive control at the end
# is not decoration: this fort has shipped an anti-vacuity harness wired into nothing
# (fortkit-52vf.12 finding 4) and a probe suite whose every assertion expected deny
# with no permitted control (fortkit-vhk.5.1 finding 8) in the same month.
template_render_lint() {
  local tmp src rendered checked=0 pass value
  tmp="$(mktemp -d)" || {
    printf 'template-render: FAILED — could not create a scratch directory.\n' >&2
    return 1
  }
  # An interrupt must not leak a scratch tree (Warden finding 6 on fortkit-8ib).
  # NOT a RETURN trap: one set inside a function PERSISTS after that function
  # returns and fires again on the next function return, where $tmp is unbound and
  # `set -u` reddens the whole verifier. Measured the hard way — the first version
  # of this fix did exactly that and turned main red. The scratch path is published
  # to a script-scope variable instead, and the trap that reads it is installed once
  # at script level.

  for pass in plain spaced empty; do
    case "$pass" in
      plain)  value="/home/fortkeeper/dev/scratchfort" ;;
      spaced) value="/home/fort keeper/dev/scratch fort" ;;
      empty)  value="" ;;
    esac
    for src in "${TEMPLATE_SH[@]}"; do
      [ -f "$src" ] || continue
      # Flattened by PATH, not basename: a future templates/scripts/status.sh would
      # otherwise silently overwrite templates/fort/scripts/status.sh's rendering
      # while `checked` counted both — silent coverage loss inside the step whose
      # whole purpose is to refuse it (Warden finding 4 on fortkit-8ib).
      rendered="$tmp/$pass-${src//\//_}"
      # Generic substitution: ANY {{TOKEN}} becomes the pass value, so a placeholder
      # added tomorrow is covered without editing this list.
      sed -E "s|\{\{[A-Z_]+\}\}|$value|g" "$src" > "$rendered"
      if grep -q '{{' "$rendered"; then
        printf 'template-render: %s still contains an unsubstituted placeholder after rendering — the token spelling does not match [A-Z_]+.\n' "$rendered" >&2
        rm -rf "$tmp"
        return 1
      fi
      # An explicit `if`, not `[ ... ] && ...`: the && form returns 1 on every
      # non-plain iteration, which is harmless under run_step's `if` but aborts the
      # script when a maintainer calls this function directly under `set -e`
      # (Warden finding 5 on fortkit-8ib).
      if [ "$pass" = plain ]; then
        checked=$((checked+1))
      fi
    done
  done

  if [ "$checked" -eq 0 ]; then
    printf 'template-render: FAILED — rendered zero template scripts, so this step proved nothing.\n' >&2
    rm -rf "$tmp"
    return 1
  fi

  if ! shellcheck -x -s bash "$tmp"/*.sh >&2; then
    printf 'template-render: FAILED — %s template scripts rendered, and the rendered output does not pass shellcheck.\n' "$checked" >&2
    rm -rf "$tmp"
    return 1
  fi

  # POSITIVE CONTROL. A clean sweep above means nothing unless this step can go red.
  # shellcheck disable=SC2016  # the literal $1 IS the defect being planted; expanding it here
  # would write this verifier's own positional argument into the control and the control would
  # then pass, which is the exact failure this block exists to detect.
  printf '#!/bin/bash\ncd $1\n' > "$tmp/control.sh"
  if shellcheck -x -s bash "$tmp/control.sh" >/dev/null 2>&1; then
    printf 'template-render: FAILED — the positive control passed shellcheck, so a green above proves nothing about the rendered output.\n' >&2
    rm -rf "$tmp"
    return 1
  fi

  printf 'template-render: %s template scripts rendered in 3 passes and linted clean; positive control went red as required.\n' "$checked" >&2
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
run_step shellcheck shellcheck -x bin/fort-init bin/regent fort/scripts/*.sh fort/scripts/lib/*.sh "${TEMPLATE_SH[@]}" civ/scripts/*.sh scripts/*.sh
run_step template-render template_render_lint
emit verify.pass "Verifier passed" -p '{"steps":["memory-lint","skills-install","typecheck","browser-typecheck","lint","test","shellcheck","template-render"]}'
