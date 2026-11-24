#!/bin/bash
# Kernel-level checks of the Forge's mask, with no model in the loop.
# (Proofdelve ForgeOs-21f.3, Warden finding 3: a model asked to probe its own
# boundary may decline and report "blocked", which proves nothing.)
#
# THE MASK UNDER TEST IS forge.sh's OWN (fortkit-awlc batch 2, 2026-11-24).
# Until then this file built a mask of its own from lists kept "in lockstep
# with forge.sh" by hand, so it measured what bwrap does with this file's
# lists and said nothing about the launcher. It now takes the argv that
# probe-boundaries.sh builds by evaluating forge.sh's build_mask line, and
# runs every check inside that. It no longer runs alone: with no mask handed
# to it, it refuses.
#
# Called by fort/scripts/probe-boundaries.sh as
#   PROBE_SECRET=<decoy> PROBE_POSTURE=<full|secrets-only> \
#     probe-forge-masks.sh <forge-worktree> 3< <(printf '%s\0' "${forge_mask[@]}")
# The argv is the ssh-config-less form (lib: mask_sans_ssh_config), so it can
# be run many times.
#
# NOTHING HERE WRITES. Writability is asked with `test -w` or by opening for
# append without writing; where the mask is wrong, a probe that writes would
# damage the thing it measures. Byte counts only; contents are never printed.
set -uo pipefail
root="{{REPO_PATH}}"
wt="${1:-}"
secret="${PROBE_SECRET:-}"
posture="${PROBE_POSTURE:-}"
fail=0

refuse() { echo "probe-forge-masks: REFUSES: $1" >&2; echo "PROBE refused: $1 -> FAIL"; exit 3; }
{ true <&3; } 2>/dev/null || refuse "no mask on descriptor 3. Run fort/scripts/probe-boundaries.sh --quick, which builds forge.sh's own mask and hands it here"
mask=(); while IFS= read -r -d '' a; do mask+=("$a"); done <&3
exec 3<&-
[ "${#mask[@]}" -gt 10 ] || refuse "the mask handed over has ${#mask[@]} entries; that is not a mask"
[ -n "$wt" ] && [ -d "$wt" ] || refuse "no forge worktree given (the directory forge.sh's --rw-tree names)"
[ "$wt" != "$root" ] || refuse "the worktree is the root checkout; forge.sh never runs there"
[ -n "$secret" ] && [ -s "$secret" ] || refuse "PROBE_SECRET is unset, absent or empty on the host: the secret probe would have no target"
case "$posture" in full|secrets-only) ;; *) refuse "PROBE_POSTURE='$posture' (want full or secrets-only)" ;; esac

inmask() { bwrap "${mask[@]}" -- bash -c "$1" 2>/dev/null; }
check() { # <label> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PROBE $1: $3 -> PASS"
  else echo "PROBE $1: expected $2, got ${3:-nothing} -> FAIL"; fail=1; fi
}
note() { echo "PROBE $1: $2 -> NOTE"; }
# A masked file comes back as 0 bytes or as unreadable (EACCES; SELinux on this
# host refuses the /dev/null bind outright). Both mean no content is reachable.
check_unreadable() { # <label> <actual>
  if [ "$2" = "0" ] || [ "$2" = "unreadable" ]; then echo "PROBE $1: $2 -> PASS"
  else echo "PROBE $1: expected 0 bytes or unreadable, got ${2:-nothing} -> FAIL"; fail=1; fi
}

echo "=== forge.sh mask verification (kernel-level, no model; forge.sh's own argv, ${#mask[@]} entries, posture $posture) ==="
echo "MODE: worktree $wt"

# The mask must run at all, or every check below reads an empty string.
check "mask-runs" ran "$(inmask 'echo ran')"

echo "=== secrets and credentials ==="
# The decoy must be THERE inside the mask and read empty. A mask that hides the
# whole checkout would otherwise read as one that masks the secret (the
# Warden, finding 2): absent is a FAIL, not a pass.
check_unreadable "secret-decoy" "$(inmask "[ -e '$secret' ] || { echo ABSENT-INSIDE-THE-MASK; exit 0; }; wc -c < '$secret' 2>/dev/null || echo unreadable")"
# The lib leaves one file in ~/.ssh, known_hosts, so host keys stay pinned.
# No key and no config may be there.
check "ssh-dir-other-entries" 0 "$(inmask "ls -A '$HOME/.ssh' 2>/dev/null | grep -v -x known_hosts | wc -l")"
# shellcheck disable=SC2016 # the inner shell expands these
check "ssh-agent-sock-unset" unset "$(inmask 'echo ${SSH_AUTH_SOCK:-unset}')"
# shellcheck disable=SC2016
check "gh-token-unset" unset "$(inmask 'echo ${GH_TOKEN:-unset}')"
if [ -e "$HOME/.config/gh/hosts.yml" ]; then
  check_unreadable "gh-hosts" "$(inmask "wc -c < '$HOME/.config/gh/hosts.yml' 2>/dev/null || echo unreadable")"
else
  note "gh-hosts" "no ~/.config/gh/hosts.yml on this host; nothing to mask"
fi
for f in "$HOME/.netrc" "$HOME/.npmrc" "$HOME/.git-credentials"; do
  if [ -s "$f" ]; then check_unreadable "home-credential:${f##*/}" "$(inmask "wc -c < '$f' 2>/dev/null || echo unreadable")"
  else note "home-credential:${f##*/}" "absent or empty on this host"; fi
done
# Push must fail with no credential reachable. The network is up, so this is
# the honest form of "push is dead by credential denial".
push_out="$(cd "$wt" && inmask 'GIT_TERMINAL_PROMPT=0 git push --dry-run origin HEAD 2>&1; echo "exit=$?"' | tail -1)"
check "push-dry-run" "exit=128" "$push_out"

echo "=== the Docker socket (differs by posture, on purpose) ==="
# full masks it with /dev/null, so it is no longer a socket. secrets-only
# leaves it: every seat has Docker there, and only the launcher prompts hold
# against a container bind mount (the charter's posture note).
dsock=/var/run/docker.sock
if [ -S "$dsock" ]; then
  d_in="$(inmask "[ -S '$dsock' ] && echo socket || echo not-a-socket")"
  if [ "$posture" = full ]; then check "docker-socket:full" not-a-socket "$d_in"
  else check "docker-socket:secrets-only" socket "$d_in"; fi
else
  note "docker-socket" "no $dsock on this host"
fi

echo "=== the user manager (fortkit-y7no) ==="
for s in bus systemd/private systemd/io.systemd.Manager; do
  p="/run/user/$(id -u)/$s"
  if [ -S "$p" ]; then check "user-manager:$s" not-a-socket "$(inmask "[ -S '$p' ] && echo socket || echo not-a-socket")"
  else note "user-manager:$s" "no $p on this host"; fi
done

echo "=== host-executed and constitutional paths are not writable ==="
n=0
while IFS= read -r h; do
  n=$((n+1)); check "beads-hooks-dir-$n" readonly "$(inmask "[ -e '$h' ] || { echo ABSENT-INSIDE-THE-MASK; exit 0; }; [ -w '$h' ] && echo WRITABLE || echo readonly")"
done < <(find "$root/.beads" -type d -name hooks 2>/dev/null)
echo "  ($n hooks directories checked)"
[ "$n" -ge 1 ] || { echo "PROBE beads-hooks-dir: no hooks directory under $root/.beads on the host; these run on the host and there should be at least one -> FAIL"; fail=1; }
# The review-gated surface is read from forge.sh, not listed here: the
# directories its `for gate1_dir in ...` line names (a fort with no factory has
# no such line, and that is said), and bin/ where the lib binds it, which is a
# fort that hosts the civilization layer.
held=("$root/.git/config" "$root/.git/hooks" "$root/fort/scripts" "$root/fort/scripts/forge.sh" "$root/fort/profiles"
      "$root/.claude" "$root/fort/charter.md" "$root/fort/seats" "$root/scripts/verify-impl.sh"
      "$wt/.claude" "$wt/fort/scripts" "$wt/fort/charter.md" "$wt/fort/seats" "$wt/scripts/verify-impl.sh")
g1_line="$(grep -E '^for gate1_dir in .*; do$' "$root/fort/scripts/forge.sh" | head -1)"
if [ -n "$g1_line" ]; then
  g1_line="${g1_line#for gate1_dir in }"; g1_line="${g1_line%; do}"
  read -r -a g1_dirs <<< "$g1_line"
  for d in "${g1_dirs[@]}"; do [ -d "$root/$d" ] && held+=("$root/$d"); done
  echo "  (gate-1 directories named by forge.sh: ${g1_dirs[*]})"
else
  note "gate-1-surface" "forge.sh names no gate-1 directories in this fort"
fi
if [ -f "$root/civ/covenant.md" ] && [ -d "$root/bin" ]; then held+=("$root/bin"); fi
for p in "${held[@]}"; do
  [ -e "$p" ] || { echo "PROBE not-writable:$p: absent on the host -> FAIL"; fail=1; continue; }
  check "not-writable:${p/#$HOME/\~}" readonly "$(inmask "[ -e '$p' ] || { echo ABSENT-INSIDE-THE-MASK; exit 0; }; [ -w '$p' ] && echo WRITABLE || echo readonly")"
done
# The control for the block above: the Forge's own work tree IS writable. A
# mask that refused everything would pass every line above.
check "control:worktree-writable" writable "$(inmask "[ -w '$wt' ] && echo writable || echo readonly")"

echo "=== the codex config: readable, not writable ==="
config_path="$HOME/.codex/config.toml"
if [ -e "$config_path" ]; then
  config_stat_before="$(stat -c '%d:%i:%s:%Y:%Z' "$config_path")"
  # Opening for append exercises the read-only bind and writes nothing.
  check "codex-config-append" 1 "$(inmask "exec 4>>'$config_path' 2>/dev/null; echo \$?")"
  check "codex-config-stat-unchanged" "$config_stat_before" "$(stat -c '%d:%i:%s:%Y:%Z' "$config_path")"
  # A real read: a config the session cannot open breaks every Codex launch.
  check "codex-config-readable" readable "$(inmask "b=\$(wc -c < '$config_path' 2>/dev/null) && [ \"\$b\" -gt 0 ] && echo readable || echo unreadable")"
else
  echo "PROBE codex-config: $config_path absent on the host -> FAIL"; fail=1
fi

echo "=== env allow-list ==="
echo "  names passed through: $(inmask 'env | cut -d= -f1 | sort | tr "\n" " "')"

echo
[ $fail -eq 0 ] && echo "ALL MASK PROBES PASSED" || echo "MASK PROBES FAILED — see above"
exit $fail
