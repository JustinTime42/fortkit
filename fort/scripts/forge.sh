#!/bin/bash
# Launch Kethra Anvilmark (Forge seat) on a bead, in an isolated worktree, with event emission.
# Usage: fort/scripts/forge.sh <bead-id> [model]   (model defaults to gpt-5.6-terra per ladder)
# Encodes the hard-won headless-codex recipe: stdin MUST be </dev/null, worktree MUST be trusted.
set -euo pipefail
bead="$1"; model="${2:-gpt-5.6-terra}"
root="/home/justin/dev/fortkit"
emit="$root/fort/scripts/emit.sh"
suffix="${bead##*-}"
wt="/home/justin/dev/fortkit-worktrees/$suffix"

bd update "$bead" --claim -a kethra >/dev/null 2>&1 || true
"$emit" bead.claimed "Kethra claims $bead" -a kethra -s forge -t "$bead"

if [ ! -d "$wt" ]; then
  git -C "$root" worktree add "$wt" -b "bead/$suffix" >/dev/null
fi

# Concurrency guard (fortkit-6ps): one launcher per worktree, enforced by flock.
# The 2026-08-04 double-launch incident: a dead-looking (but live) launcher was
# relaunched and two sessions worked the same worktree for 4 minutes.
lock="$wt/.forge.lock"
exec 9>"$lock"
if ! flock -n 9; then
  holder=$(cat "$lock.info" 2>/dev/null || echo "holder info unavailable")
  echo "forge.sh: REFUSED — $wt already has a live launcher: $holder" >&2
  "$emit" incident "Second forge launch on $bead refused by lock (holder: $holder)" -s forge -t "$bead"
  exit 75
fi
printf '{"pid":%d,"bead":"%s","model":"%s","started":"%s"}\n' "$$" "$bead" "$model" "$(date -Is)" > "$lock.info"
trap 'rm -f "$lock.info"' EXIT

# ---------------------------------------------------------------------------
# Kernel mask layer (backported from Proofdelve 21f.3/21f.5, 2026-08-04).
# Codex's Linux sandbox does NOT enforce deny-read (upstream openai/codex#11316,
# proven bypassable by Proofdelve's smoke test), so policy alone is not a
# boundary. bwrap is: --bind / / passes the filesystem through with a fresh
# /dev, then each sensitive path is shadowed. bwrap applies operations in order
# and fails on missing targets, hence the existence guards.
#
# A masked FILE reads as EMPTY-AND-SUCCESSFUL, not as an error — any probe must
# assert byte counts and never trust an "access denied" narration. On SELinux
# hosts the /dev/null device bind may instead yield EACCES; both are correct.
MASK_FILES=(
  "$HOME/.netrc" "$HOME/.npmrc" "$HOME/.git-credentials"
  /var/run/docker.sock /run/docker.sock "/run/user/$(id -u)/docker.sock"
  "/run/user/$(id -u)/podman/podman.sock"
  "${SSH_AUTH_SOCK:-/nonexistent}"
)
# Any secret file this fort acquires goes in MASK_FILES *and* in any policy
# deny list — the BOTH-LISTS rule. There are no such files here yet; add them
# with the secret, not after it.
for envf in "$root"/.env* "$wt"/.env*; do
  [ -e "$envf" ] && MASK_FILES+=("$envf")
done
# KNOWN EXCEPTION: ~/.codex is NOT masked — Codex runs inside this sandbox and
# reads its own auth.json from there, so masking it breaks the launch. Since
# 21f.5 config.toml is bound read-only below, closing the append vector while
# leaving token refresh working.
MASK_DIRS=("$HOME/.ssh" "$HOME/.aws" "$HOME/.config/gh" "$HOME/.claude" "$HOME/.docker" "$HOME/.config/git")
# Permission configs must protect themselves: policy is advisory on Linux, so
# kernel enforcement is here or nowhere. A poisoned settings.json in the
# worktree would otherwise govern any later Claude session launched there.
RO_PATHS=("$HOME/.codex/config.toml" "$wt/.claude" "$root/.claude")

mask=(--bind / / --dev /dev --die-with-parent)
for f in "${MASK_FILES[@]}"; do
  [ -e "$f" ] && mask+=(--ro-bind /dev/null "$f")
done
for d in "${MASK_DIRS[@]}"; do
  [ -d "$d" ] && mask+=(--tmpfs "$d")
done
for pth in "${RO_PATHS[@]}"; do
  [ -e "$pth" ] && mask+=(--ro-bind "$pth" "$pth")
done
# Git hooks under .beads run on the HOST, unsandboxed, on the next commit or
# push in the main checkout — writable .beads is a host RCE escape. Re-bound
# read-only AFTER the .beads --add-dir grant. CLASS fix, not one path: there
# are at least two such directories (.beads/hooks and dolt's git-remote-cache
# repo.git/hooks), so every hooks dir under .beads is caught by construction.
while IFS= read -r h; do
  mask+=(--ro-bind "$h" "$h")
done < <(find "$root/.beads" -type d -name hooks 2>/dev/null)
# Environment is an ALLOW-LIST, not a deny-list: enumerated unsets leave AWS_*,
# GIT_SSH_COMMAND, and anything sourced from a secrets file in the launching
# shell. Failure mode if a name is missing is loud (Codex cannot auth), never
# silently insecure.
mask+=(--clearenv)
for v in HOME USER LOGNAME SHELL TERM LANG LC_ALL PATH TMPDIR XDG_RUNTIME_DIR \
         CODEX_HOME OPENAI_API_KEY OPENAI_BASE_URL RUST_LOG npm_config_cache; do
  [ -n "${!v:-}" ] && mask+=(--setenv "$v" "${!v}")
done
if ! command -v bwrap >/dev/null 2>&1; then
  echo "forge.sh: REFUSED — bwrap not found; the kernel mask layer is the boundary, policy alone is not" >&2
  "$emit" incident "Forge launch refused: bwrap missing, kernel mask layer unavailable" -s forge -t "$bead"
  exit 78
fi
# ---------------------------------------------------------------------------

"$emit" session.start "Kethra begins work on $bead ($model)" -a kethra -s forge -t "$bead" -p "{\"model\":\"$model\"}"
desc=$(bd show "$bead" 2>/dev/null || echo "See bead $bead")
set +e
(cd "$wt" && bwrap "${mask[@]}" -- codex exec --sandbox workspace-write \
  -c "projects.\"$wt\".trust_level=\"trusted\"" \
  --add-dir "$root/.git/objects" \
  --add-dir "$root/.git/refs/heads/bead" \
  --add-dir "$root/.git/logs/refs/heads/bead" \
  --add-dir "$root/.git/worktrees/$suffix" \
  --add-dir "$root/.beads" \
  --add-dir "$root/fort/events" \
  -m "$model" \
  "You are Kethra Anvilmark (she/her), holder of the Forge of Manyhalls, the fortkit fort. Read AGENTS.md, fort/charter.md, fort/remember.md, fort/seats/forge.md in this directory, then implement this bead and drive verifiers green. Do not merge, push, or touch .env*/deploy scripts. Commit path-scoped with message starting '$bead: '. Emit work.begun and work.ended events via fort/scripts/emit.sh at the edges of your work. Never close the bead or change its status: the Mayor closes it after review and merge. Report what you did, verification results, and surprises.

BEAD:
$desc" </dev/null 2>&1) | tee "/tmp/forge-$suffix.log" | tail -30
rc=${PIPESTATUS[0]}
set -e
"$emit" session.end "Kethra's session on $bead ended (exit $rc)" -a kethra -s forge -t "$bead" -p "{\"exit\":$rc,\"log\":\"/tmp/forge-$suffix.log\"}"
echo "--- forge.sh: session ended (exit $rc). Worktree: $wt  Log: /tmp/forge-$suffix.log"
echo "--- Next: harness verifies (build+test in $wt), Warden reviews, then merge."
