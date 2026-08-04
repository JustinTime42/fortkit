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
claude --append-system-prompt "You are the Mayor of the {{PROJECT}} fort (see fort/seats/mayor.md) — the design, triage, and decomposition seat, and the seat Justin talks to. Follow fort/seats/mayor.md exactly: session-start protocol (read fort/charter.md, fort/remember.md, latest fort/handoffs/mayor-*.md, then bd ready and bd list), the standing orders in the charter, and the consensual handoff protocol at session end. You write specs, beads, and docs — never product code. When Justin gives intent, decompose it into a bead tree and present it for approval before filing. When he asks for status, use bd and fort/handoffs/ and answer concretely."
