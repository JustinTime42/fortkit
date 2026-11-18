#!/bin/bash
# Deterministic kernel-level verification of forge.sh's bwrap masks.
# (ForgeOs-21f.3, Warden finding 3.) No model in the loop: a model asked to
# probe its own boundary may DECLINE on policy grounds and report "blocked",
# which proves nothing — that happened on the 2026-08-04 08:38 smoke run for
# probes 9, 10, and 14. This script runs the same mask array from a shell.
#
# Byte counts only; file CONTENTS are never printed. A masked file reads as
# empty-and-successful, so 0 bytes = mask held, nonzero = mask FAILED.
# Usage: fort/scripts/probe-forge-masks.sh [worktree-dir]
set -uo pipefail
root="/home/justin/dev/ForgeOs"
# Default to the main checkout when no worktree is up (the original 21f.3
# default was pruned 2026-08-04); pass the live worktree dir when one exists.
wt="${1:-$root}"
fail=0

REQUIRED_MASK_FILES=(
  "$root/.env.staging.local"
  "$root/scripts/deploy-azure-staging.sh"
  "$wt/scripts/deploy-azure-staging.sh"
)
OPTIONAL_MASK_FILES=(
  "$HOME/.netrc" "$HOME/.npmrc" "$HOME/.git-credentials"
  /var/run/docker.sock /run/docker.sock "/run/user/$(id -u)/docker.sock"
  "/run/user/$(id -u)/podman/podman.sock"
  "${SSH_AUTH_SOCK:-/nonexistent}"
)
REQUIRED_MASK_DIRS=("$HOME/.ssh")
OPTIONAL_MASK_DIRS=("$HOME/.aws" "$HOME/.config/gh" "$HOME/.claude" "$HOME/.docker" "$HOME/.config/git")
# Keep in lockstep with forge.sh (ForgeOs-21f.5): configs readable, unwritable.
REQUIRED_RO_PATHS=("$HOME/.codex/config.toml" "$wt/.claude" "$root/.claude")

missing_target() { # <kind> <path>
  echo "PROBE missing-target:$1:$2 -> FAIL"
  fail=1
}

# bwrap fails a bind whose destination does not exist. Required protection
# targets therefore fail closed before any probe runs. Defense-in-depth targets
# are optional in forge.sh; keep those guards here too, but make every absence
# visible so a skipped optional mask cannot be mistaken for verified coverage.
for f in "${REQUIRED_MASK_FILES[@]}"; do [ -e "$f" ] || missing_target "mask-file" "$f"; done
for d in "${REQUIRED_MASK_DIRS[@]}"; do [ -d "$d" ] || missing_target "mask-dir" "$d"; done
for p in "${REQUIRED_RO_PATHS[@]}"; do [ -e "$p" ] || missing_target "ro-path" "$p"; done
if [ "$fail" -ne 0 ]; then
  echo "MASK PROBES FAILED — missing protected target(s)"
  exit "$fail"
fi

mask=(--bind / / --dev /dev --die-with-parent)
for f in "${REQUIRED_MASK_FILES[@]}"; do mask+=(--ro-bind /dev/null "$f"); done
for d in "${REQUIRED_MASK_DIRS[@]}"; do mask+=(--tmpfs "$d"); done
for p in "${REQUIRED_RO_PATHS[@]}"; do mask+=(--ro-bind "$p" "$p"); done
for f in "${OPTIONAL_MASK_FILES[@]}"; do
  if [ -e "$f" ]; then mask+=(--ro-bind /dev/null "$f")
  else echo "PROBE optional-target-absent:$f -> NOTE"; fi
done
for d in "${OPTIONAL_MASK_DIRS[@]}"; do
  if [ -d "$d" ]; then mask+=(--tmpfs "$d")
  else echo "PROBE optional-target-absent:$d -> NOTE"; fi
done
while IFS= read -r h; do mask+=(--ro-bind "$h" "$h"); done \
  < <(find "$root/.beads" -type d -name hooks 2>/dev/null)
mask+=(--clearenv)
for v in HOME USER LOGNAME SHELL TERM LANG LC_ALL PATH TMPDIR XDG_RUNTIME_DIR \
         DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO NUGET_PACKAGES \
         CODEX_HOME OPENAI_API_KEY OPENAI_BASE_URL RUST_LOG; do
  [ -n "${!v:-}" ] && mask+=(--setenv "$v" "${!v}")
done

check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PROBE $1: $3 -> PASS"
  else echo "PROBE $1: expected $2, got $3 -> FAIL"; fail=1; fi
}

# A masked file may come back either as 0 bytes (read succeeds, content gone)
# or as "unreadable" (EACCES — observed on this host, where SELinux refuses the
# /dev/null device bind outright). Both mean no content is reachable; the second
# is the stronger outcome. Anything else is a real failure.
check_unreadable() { # <label> <actual>
  if [ "$2" = "0" ] || [ "$2" = "unreadable" ]; then echo "PROBE $1: $2 -> PASS"
  else echo "PROBE $1: expected 0 bytes or unreadable, got $2 -> FAIL"; fail=1; fi
}

echo "=== forge.sh mask verification (kernel-level, no model) ==="
# Keep the pass count honest (Warden finding 5, 21f.5 review): with no argument
# the worktree probes degenerate into duplicates of the main-checkout ones.
if [ "$wt" = "$root" ]; then
  echo "MODE: main checkout only (no worktree arg — deploy-worktree and claude-settings-canary duplicate main-checkout paths)"
else
  echo "MODE: worktree $wt"
fi
check_unreadable "secrets-file"     "$(bwrap "${mask[@]}" -- bash -c "wc -c < '$root/.env.staging.local' 2>/dev/null || echo unreadable")"
check_unreadable "deploy-main"      "$(bwrap "${mask[@]}" -- bash -c "wc -c < '$root/scripts/deploy-azure-staging.sh' 2>/dev/null || echo unreadable")"
check_unreadable "deploy-worktree"  "$(bwrap "${mask[@]}" -- bash -c "wc -c < '$wt/scripts/deploy-azure-staging.sh' 2>/dev/null || echo unreadable")"
check "ssh-dir-entries"         0 "$(bwrap "${mask[@]}" -- bash -c "ls '$HOME/.ssh' 2>/dev/null | wc -l")"
# shellcheck disable=SC2016 # The inner shell intentionally expands these variables.
check "ssh-agent-sock-unset"    unset "$(bwrap "${mask[@]}" -- bash -c 'echo ${SSH_AUTH_SOCK:-unset}')"
# shellcheck disable=SC2016 # The inner shell intentionally expands this variable.
check "gh-token-unset"          unset "$(bwrap "${mask[@]}" -- bash -c 'echo ${GH_TOKEN:-unset}')"
check "gh-hosts-bytes"          0 "$(bwrap "${mask[@]}" -- bash -c "wc -c < '$HOME/.config/gh/hosts.yml' 2>/dev/null || echo 0")"
# Push must fail with no credentials reachable. Network is up in the real run,
# so this is the honest test of "push is dead by credential denial".
push_out=$(cd "$wt" && bwrap "${mask[@]}" -- bash -c 'GIT_TERMINAL_PROMPT=0 git push --dry-run origin HEAD 2>&1; echo "exit=$?"' | tail -1)
check "push-dry-run"            "exit=128" "$push_out"
check "docker-sock-bytes"       0 "$(bwrap "${mask[@]}" -- bash -c 'wc -c < /var/run/docker.sock 2>/dev/null || echo 0')"

echo "=== hooks (host-executed; every dir under .beads must be read-only) ==="
n=0
while IFS= read -r h; do
  n=$((n+1))
  check "hooks-dir-$n-write" 1 "$(bwrap "${mask[@]}" -- bash -c "printf x >> '$h/pre-push' 2>/dev/null; echo \$?")"
done < <(find "$root/.beads" -type d -name hooks 2>/dev/null)
echo "  ($n hooks directories checked)"

echo "=== permission configs read-only (ForgeOs-21f.5) ==="
# Opening the real masked path for append exercises its RO_PATHS bind, but does
# not write a byte. The stat check is the safety net for that no-write contract.
config_path="$HOME/.codex/config.toml"
config_stat_before="$(stat -c '%d:%i:%s:%Y:%Z' "$config_path")"
check "codex-config-append" 1 "$(bwrap "${mask[@]}" -- bash -c "exec 3>>'$config_path' 2>/dev/null; echo \$?")"
config_stat_after="$(stat -c '%d:%i:%s:%Y:%Z' "$config_path")"
check "codex-config-stat-unchanged" "$config_stat_before" "$config_stat_after"
# Real read, not a stat: [ -s ] succeeds on a file you cannot open, and masks
# on this host surface as EACCES (Warden finding 4, 21f.5 review). A regression
# leaving the config unreadable would break every Codex launch — catch it here.
check "codex-config-readable" readable "$(bwrap "${mask[@]}" -- bash -c "b=\$(wc -c < '$HOME/.codex/config.toml' 2>/dev/null) && [ \"\$b\" -gt 0 ] && echo readable || echo unreadable")"
check "claude-settings-canary" 1 "$(bwrap "${mask[@]}" -- bash -c "printf x > '$wt/.claude/probe-canary' 2>/dev/null; echo \$?")"

echo "=== env allow-list ==="
echo "  names passed through: $(bwrap "${mask[@]}" -- bash -c 'env | cut -d= -f1 | sort | tr "\n" " "')"

echo
[ $fail -eq 0 ] && echo "ALL MASK PROBES PASSED" || echo "MASK PROBES FAILED — see above"
exit $fail
