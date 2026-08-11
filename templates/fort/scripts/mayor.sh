#!/bin/bash
# TEMPLATE — rendered by fort-init; {{PLACEHOLDERS}} resolved at founding.
# Actor ids are seat-office names (mayor/forge/warden) until the Founding Moot
# renames them — a fort must never inherit another settlement's citizen (fortkit-ebm/fd2).
# shellcheck disable=SC1083  # template placeholders read as literal braces
# Talk to the Mayor. Usage: fort/scripts/mayor.sh  (add an alias: alias mayor (global launcher finds any fort))
REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo {{REPO_PATH}})"
cd "$REPO" || exit 1
fort/scripts/emit.sh session.start "The Overseer summons the Mayor" -a mayor -s mayor 2>/dev/null || true
trap 'fort/scripts/emit.sh session.end "The Mayor'\''s audience with the Overseer ends" -a mayor -s mayor 2>/dev/null || true' EXIT
# Kernel mask layer (civilization cycle 4). Permission rules bind a SPELLING,
# not a file (measured, Proofdelve 21f.8): .e"n"v and .??v reach the same inode
# and no deny rule binds either. bwrap masks the inode, so every spelling of a
# masked path reads empty — including spellings nobody has thought of. This is
# what lets an interactive seat run with few or no prompts and still have a
# boundary. ~/.claude stays readable (this runtime's own credentials, this
# project's auto-memory, the session transcripts); its CONFIG is read-only so a
# session cannot rewrite the rules for the next one.
#
# ESCAPE HATCH: MAYOR_NO_MASK=1 runs unmasked. Needed today only for pushing —
# ~/.ssh is masked, so key-file auth cannot work inside (agent-held identities
# still sign; run `ssh-add` if you want push from inside the mask). Every
# unmasked launch emits an event, so the record shows which sessions ran
# without a kernel boundary.
mask=()
# shellcheck source=fort/scripts/lib/seat-sandbox.sh
# shellcheck disable=SC1091  # resolved at runtime; build_mask fills mask[]
source "$REPO/fort/scripts/lib/seat-sandbox.sh"
launch=(claude --append-system-prompt "You are the Mayor of the {{PROJECT}} fort (see fort/seats/mayor.md) — the design, triage, and decomposition seat, and the seat Justin talks to. Follow fort/seats/mayor.md exactly: session-start protocol (read fort/charter.md, fort/memory/current.md (distilled view; facts ledger in fort/memory/facts/), latest fort/handoffs/mayor-*.md, then bd ready and bd list), the standing orders in the charter, and the consensual handoff protocol at session end. You write specs, beads, and docs — never product code. When Justin gives intent, decompose it into a bead tree and present it for approval before filing. When he asks for status, use bd and fort/handoffs/ and answer concretely. You may run git push and deploy commands, but they are gated by prose, not by the sandbox: ASK JUSTIN FIRST, every time, and say exactly what you intend to push or deploy and why. Never push or deploy on your own initiative.")
if [ "${MAYOR_NO_MASK:-0}" = "1" ]; then
  fort/scripts/emit.sh incident "Mayor launched UNMASKED (MAYOR_NO_MASK=1) — no kernel boundary this session" -a mayor -s mayor 2>/dev/null || true
  exec "${launch[@]}"
fi
require_bwrap || exit $?
# PROMPT-FREE, BECAUSE THE KERNEL IS THE BOUNDARY (cycle 5, layer 3).
# --dangerously-skip-permissions bypasses ALL permission checks including the
# deny lists, so the mask is the only thing standing between this session and
# the disk. That is exactly why it is passed AFTER require_bwrap succeeds and
# never on the MAYOR_NO_MASK path above: no kernel boundary, no flag. With the
# filesystem scoped (layer 1) what remains reachable is this repo, its
# worktrees, ~/.claude, /tmp and the toolchain caches — all under git or
# disposable. Unmasked sessions keep the full prompt-and-deny behaviour.
launch+=(--dangerously-skip-permissions)
build_mask claude "$REPO"
mask_env claude
export FORT_MASKED=1
mask+=(--setenv FORT_MASKED 1)
exec bwrap "${mask[@]}" -- "${launch[@]}"

