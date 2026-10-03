#!/usr/bin/env bash
# Install the Civ Keep as a systemd user service (civ/keep/README.md).
# Run from the canonical capital checkout, by the Overseer or the Regent:
# never from a masked seat, because the service runs unmasked.
set -euo pipefail

if [[ -n "${FORT_MASKED:-}" ]]; then
  echo "Refusing to install the Civ Keep from a masked seat (FORT_MASKED=$FORT_MASKED)." >&2
  exit 64
fi

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
unit_source="$here/systemd/civ-keep.service"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/civ-keep"
token_path="$config_dir/signing-token"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/civ-keep"

mkdir -p "$state_dir"
chmod 700 "$state_dir"

# The token is written and never printed: a secret on a terminal ends up in
# scrollback and in agent transcripts. Read it from the mode-0600 file.
if [[ ! -s "$token_path" ]]; then
  mkdir -p "$config_dir"
  chmod 700 "$config_dir"
  ( umask 077; node -e "process.stdout.write(require('node:crypto').randomBytes(32).toString('hex') + '\n')" > "$token_path" )
  chmod 600 "$token_path"
  echo "Signing token created at $token_path (mode 0600). It is not printed here."
fi

mkdir -p "$unit_dir"
ln -sfn "$unit_source" "$unit_dir/civ-keep.service"
systemctl --user daemon-reload
systemctl --user enable --now civ-keep.service
systemctl --user restart civ-keep.service

echo "Civ Keep: http://127.0.0.1:7780"
