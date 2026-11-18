#!/bin/bash
# Stop-hook entry point for the run digest (ForgeOs-eng3.3).
# A hook must never prevent Codex from ending a turn.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
digest_script="${DIGEST_SCRIPT:-$script_dir/digest.sh}"

# Deliberately discard the predicate's diagnostic. A busy Forge must leave this
# hook completely silent, while a stale Warden is diagnostic-only and must not
# become part of the digest output either.
if ! "$script_dir/quiescent.sh" >/dev/null 2>&1; then
  exit 0
fi

# The hook payload arrives on stdin and carries transcript_path. Read it BEFORE
# the digest runs, because the digest writes to stdout and stdin is consumed
# once. Failure here must be silent: no transcript, no supplement, and the
# deterministic half still runs (ForgeOs-eng3.11).
hook_input=""
if [ ! -t 0 ]; then
  hook_input="$(timeout 2 cat 2>/dev/null || true)"
fi
transcript_path=""
if [ -n "$hook_input" ] && command -v jq >/dev/null 2>&1; then
  transcript_path="$(printf '%s' "$hook_input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
fi

set +e
"$digest_script"
digest_status=$?
set -e

if [ "$digest_status" -ne 0 ]; then
  printf 'digest-hook: digest could not be produced (exit %s)\n' "$digest_status"
fi

# The transcript supplement runs AFTER the deterministic digest and never
# instead of it, so the floor is printed even if this is disabled, absent, slow
# or broken. It is off unless FORT_TRANSCRIPT_DIGEST=1; see that script's header
# for why a model call from an unattended Stop hook ships default-off.
if [ -n "$transcript_path" ] && [ -x "$script_dir/digest-transcript.sh" ]; then
  "$script_dir/digest-transcript.sh" "$transcript_path" || true
fi

exit 0
