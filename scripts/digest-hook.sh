#!/bin/bash
# Stop-hook entry point for the session digest.  It only renders after every
# Forge, Warden, and verifier signal is quiet.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
digest_script="${DIGEST_SCRIPT:-$script_dir/digest.sh}"

quiescence="$("$script_dir/quiescent.sh" 2>&1)"
quiescence_status=$?
if [ "$quiescence_status" -ne 0 ]; then
  printf 'digest-hook: declined; fort is not quiescent\n'
  [ -z "$quiescence" ] || printf '%s\n' "$quiescence"
  exit 0
fi

set +e
"$digest_script"
digest_status=$?
set -e
if [ "$digest_status" -ne 0 ]; then
  printf 'digest-hook: digest could not be produced (exit %s)\n' "$digest_status"
fi

exit 0
