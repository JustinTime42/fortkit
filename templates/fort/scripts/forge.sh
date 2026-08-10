#!/bin/bash
# TEMPLATE — rendered by fort-init. Actor ids are seat-office names until the moot.
# shellcheck disable=SC1083
# Launch the Forge seat on a bead, in an isolated worktree, with event emission.
# Usage: fort/scripts/forge.sh <bead-id> [model]   (model defaults to gpt-5.6-terra per ladder)
# Encodes the hard-won headless-codex recipe: stdin MUST be </dev/null, worktree MUST be trusted.
set -euo pipefail
bead="$1"; model="${2:-gpt-5.6-terra}"
root="{{REPO_PATH}}"
emit="$root/fort/scripts/emit.sh"
suffix="${bead##*-}"
wt="{{REPO_PATH}}-worktrees/$suffix"

bd update "$bead" --claim -a forge >/dev/null 2>&1 || true
"$emit" bead.claimed "The Forge claims $bead" -a forge -s forge -t "$bead"

if [ ! -d "$wt" ]; then
  git -C "$root" worktree add "$wt" -b "bead/$suffix" >/dev/null
fi

# Concurrency guard (fortkit-6ps): one launcher per worktree, enforced by flock.
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

# Kernel mask layer: seat-sandbox.sh owns every shared protection. Forge adds
# only its measured deltas: worktree .env* coverage, its local .claude config,
# and its worktree constitution paths. SSH_AUTH_SOCK is passed through when set,
# but its socket is masked to /dev/null, so no agent identities are available.
mask=()
# shellcheck source=fort/scripts/lib/seat-sandbox.sh
# shellcheck disable=SC1091  # resolved at runtime; build_mask fills mask[]
source "$root/fort/scripts/lib/seat-sandbox.sh"
if ! require_bwrap; then
  "$emit" incident "Forge launch refused: bwrap missing, kernel mask layer unavailable" -s forge -t "$bead"
  exit 78
fi
build_mask codex "$root" --env-root "$wt" --mask-ssh-auth-sock "$wt/.claude" \
  "$wt/fort/charter.md" "$wt/fort/seats" "$wt/fort/profiles" "$wt/fort/scripts"
mask_env codex

"$emit" session.start "The Forge begins work on $bead ($model)" -a forge -s forge -t "$bead" -p "{\"model\":\"$model\"}"
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
  "You are the holder of the Forge seat of the {{PROJECT}} fort (see fort/seats/forge.md). Read AGENTS.md, fort/charter.md, fort/remember.md, fort/seats/forge.md in this directory, then implement this bead and drive verifiers green. Do not merge, push, or touch .env*/deploy scripts. Commit path-scoped with message starting '$bead: '. Report what you did, verification results, and surprises.

BEAD:
$desc" </dev/null 2>&1) | tee "/tmp/forge-$suffix.log" | tail -30
rc=${PIPESTATUS[0]}
set -e
"$emit" session.end "The Forge's session on $bead ended (exit $rc)" -a forge -s forge -t "$bead" -p "{\"exit\":$rc,\"log\":\"/tmp/forge-$suffix.log\"}"
echo "--- forge.sh: session ended (exit $rc). Worktree: $wt  Log: /tmp/forge-$suffix.log"
echo "--- Next: harness verifies (build+test in $wt), Warden reviews, then merge."
