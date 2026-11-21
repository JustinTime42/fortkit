#!/bin/bash
# forge-gate1-mask-harness.sh: the Forge cannot write the ROOT checkout's gate-1
# surface (templates/, schema/, skills/, civ/), and can write its own worktree's
# (Regent sitting 2026-11-19, fortkit-ttpk).
# Usage: scripts/forge-gate1-mask-harness.sh [forge.sh]
#
# Evaluates the SHIPPED forge.sh's own mask lines (from the keep_token line to
# seat_build_env) against a fixture fort under ~/dev, and reads permissions from
# inside bwrap. Nothing is written from inside the mask. HOST ONLY: it refuses
# inside a seat mask, so it is not a verifier step (the verifier runs in masks).
#
# TWO PROPERTIES. (1) The four root directories are read-only. (2) A secret-named
# file under them still reads EMPTY: a subtree bind laid after the lib's secret
# masks would cover them (the Warden's blocking finding on f083518), so a decoy
# .env.local under the root's civ/ must read 0 bytes from inside the mask.
#
# CONTROLS. Vacuity: the worktree's own templates/ IS writable, so a mask that
# refuses everything cannot pass; and the decoy is non-empty on the host. Red arm
# 1: the gate-1 paths dropped, and the root's templates/ is writable. Red arm 2:
# the same paths appended as --ro-bind lines AFTER build_mask, and the decoy
# reads in full.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
forge="${1:-$here/../fort/scripts/forge.sh}"
lib="$(dirname "$forge")/lib/seat-sandbox.sh"
[ -f "$forge" ] && [ -f "$lib" ] || { echo "HARNESS REFUSES: forge.sh or its lib missing ($forge, $lib)" >&2; exit 3; }
command -v bwrap >/dev/null || { echo "HARNESS REFUSES: no bwrap on this host" >&2; exit 3; }
[ -z "${FORT_MASKED:-}" ] || { echo "HARNESS REFUSES: run on the host, not inside a seat mask (FORT_MASKED=$FORT_MASKED)" >&2; exit 3; }

fx="$(mktemp -d "$HOME/dev/.forge-gate1.XXXXXX")" || { echo "HARNESS REFUSES: cannot make a fixture under ~/dev" >&2; exit 3; }
trap 'chmod -R u+w "$fx" 2>/dev/null; rm -rf "$fx"' EXIT
root="$fx/repo"; wt="$root-worktrees/b1"
for t in "$root" "$wt"; do
  mkdir -p "$t/fort/scripts/lib" "$t/templates" "$t/schema" "$t/skills" "$t/civ" "$t/src" "$t/.claude" "$t/fort/profiles"
  cp "$lib" "$t/fort/scripts/lib/seat-sandbox.sh"
done
git -C "$root" init -q
mkdir -p "$root/civ/keep"; printf 'FIXTURE-NOT-A-SECRET\n' > "$root/civ/keep/.env.local"
printf 'FIXTURE-NOT-A-SECRET\n' > "$root/src/.env.local"
decoy_host="$(wc -c < "$root/civ/keep/.env.local")"
printf '{"civilization":"fixture","forts":[{"project":"repo","repo":"%s","fort_name":"Fixturefort"}]}\n' "$root" > "$fx/registry.json"
cat > "$fx/in.sh" <<'IN'
r="$1"; w="$2"
c() { [ -w "$1" ] && echo yes || echo no; }
for d in templates schema skills civ; do echo "root_$d=$(c "$r/$d")"; echo "wt_$d=$(c "$w/$d")"; done
echo "root_src=$(c "$r/src")"
echo "decoy_civ=$(cat "$r/civ/keep/.env.local" 2>/dev/null | wc -c)"
echo "decoy_src=$(cat "$r/src/.env.local" 2>/dev/null | wc -c)"
echo "agent=$(cat "$3/ssh-agent.socket" 2>/dev/null | wc -c)"
IN

# The launcher's own mask lines, cut from the subject. Refuse on an empty cut.
block_of() { sed -n '/^keep_token=/,/^seat_build_env/p' "$1"; }
# A STAND-IN AGENT SOCKET (Regent sitting 2026-11-20, fortkit-awlc). The lib masks the
# well-known per-user agent sockets under XDG_RUNTIME_DIR whether or not the launching
# shell has SSH_AUTH_SOCK. A plain file stands in for the socket: masked, it reads 0
# bytes. Every probe here runs WITHOUT SSH_AUTH_SOCK, the case that used to mask nothing.
mkdir -p "$fx/run"; printf 'FIXTURE-AGENT\n' > "$fx/run/ssh-agent.socket"
agent_host="$(wc -c < "$fx/run/ssh-agent.socket")"
probe() {  # $1 forge.sh, $2 posture, [$3 lib] -> key=value lines
  local b use_lib="${3:-$lib}"; b="$(block_of "$1")"
  [ -n "$b" ] || { echo "cut=EMPTY"; return; }
  # shellcheck disable=SC2030,SC2031  # each probe sets its own environment in its own subshell
  ( export FORT_SANDBOX="$2" FORT_REGISTRY="$fx/registry.json" XDG_RUNTIME_DIR="$fx/run"
    unset SSH_AUTH_SOCK
    mask=()
    # shellcheck disable=SC1090  # the lib beside the subject (or a red-arm copy), by design
    source "$use_lib" 2>/dev/null || { echo "mask=FAILED"; exit 0; }
    # shellcheck disable=SC2034  # root, wt and bead are read by the evaluated block
    bead=fixture-b1
    eval "$b" >/dev/null 2>&1 || { echo "mask=FAILED"; exit 0; }
    bwrap "${mask[@]}" -- /bin/bash "$fx/in.sh" "$root" "$wt" "$fx/run" 2>/dev/null )
}
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1 ($2)"; pass=$((pass+1)); else echo "FAIL  $1 (got '$2', want '$3')"; fail=$((fail+1)); fi; }
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

for posture in full secrets-only; do
  out="$(probe "$forge" "$posture")"
  case "$out" in *cut=EMPTY*|*mask=FAILED*) echo "FAIL  [$posture] the mask block could not be cut or built ($out)"; fail=$((fail+1)); continue ;; esac
  for d in templates schema skills civ; do
    check "[$posture] the ROOT checkout's $d/ is read-only to the Forge" "$(val "$out" "root_$d")" no
  done
  check "[$posture] VACUITY: the Forge's own worktree templates/ IS writable" "$(val "$out" wt_templates)" yes
  check "[$posture] a secret-named file under the root's civ/ reads empty" "$(val "$out" decoy_civ)" 0
  check "[$posture] and one under the root's src/ reads empty (the lib's own sweep)" "$(val "$out" decoy_src)" 0
  check "[$posture] the agent socket is masked with NO SSH_AUTH_SOCK in the launching environment" "$(val "$out" agent)" 0
done
check "VACUITY: the decoy is non-empty on the host" "$([ "$decoy_host" -gt 0 ] && echo yes || echo no)" yes

# RED ARM 1: the gate-1 paths never reach build_mask.
red="$fx/forge-red.sh"
# shellcheck disable=SC2016  # the sed program matches the launcher's literal $-spelling
sed 's/ "\${gate1_ro\[@\]}"$//' "$forge" > "$red"
if cmp -s "$red" "$forge"; then echo "NOT RUN  red arm 1: the gate-1 argument was not found on the build_mask line of $forge"; fail=$((fail+1))
else
  out="$(probe "$red" secrets-only)"
  check "RED ARM 1 (gate-1 paths dropped, secrets-only): the root's templates/ becomes writable" "$(val "$out" root_templates)" yes
fi
# RED ARM 2: the same paths appended AFTER build_mask, the form first shipped.
red2="$fx/forge-red2.sh"
# shellcheck disable=SC2016  # as above; the appended line is literal launcher text
sed -e 's/ "\${gate1_ro\[@\]}"$//' -e '/^build_mask codex /a for g1 in "${gate1_ro[@]}"; do mask+=(--ro-bind "$g1" "$g1"); done' "$forge" > "$red2"
if cmp -s "$red2" "$red"; then echo "NOT RUN  red arm 2: could not append after the build_mask line"; fail=$((fail+1))
else
  out="$(probe "$red2" secrets-only)"
  check "RED ARM 2 (paths appended after build_mask): the root's templates/ is read-only" "$(val "$out" root_templates)" no
  check "RED ARM 2: and the decoy secret under civ/ reads in full" "$(val "$out" decoy_civ)" "$decoy_host"
fi
# RED ARM 3: the lib without its well-known-socket loop masks only what SSH_AUTH_SOCK
# names, and with the variable unset that is nothing.
redlib="$fx/lib-red.sh"
sed '/^    local agent_sock agent_run=/,/^    done$/d' "$lib" > "$redlib"
if cmp -s "$redlib" "$lib"; then echo "NOT RUN  red arm 3: the agent-socket loop was not found in $lib"; fail=$((fail+1))
else
  out="$(probe "$forge" secrets-only "$redlib")"
  check "RED ARM 3 (the lib's agent-socket loop removed): the stand-in agent reads in full" "$(val "$out" agent)" "$agent_host"
fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
