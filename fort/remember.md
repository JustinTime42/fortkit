# fortkit operational facts (inject every session)

- Fort founded 2026-08-03 via fort-init; fort name pending the Founding Moot.
- Founding spec: docs/specs/fortress-visualizer.md
- Codex launch recipe: cd into the worktree, --sandbox workspace-write -c 'projects."<worktree>".trust_level="trusted"' -m <model> "<prompt>" </dev/null — the stdin redirect is mandatory.
- No verifiers yet: CI-from-commit-one should be an early bead.
- 2026-08-04: `fort/scripts/verify.sh` is the authoritative verifier, superseding
  the earlier no-verifiers note. It runs TypeScript typecheck, Biome lint,
  Vitest tests, and ShellCheck in that order; `--no-emit` (and `CI`) suppresses
  event emission.

## Seat machinery (added 2026-08-04, backport cycles 3-4)

- **Warden reviews are launched, not improvised**: `fort/scripts/warden.sh <bead-id> <ref-range> [candidate-dir] [model]`. The seat is read-only BY CONSTRUCTION (restricted tool set, `--setting-sources ""` + fort/profiles/warden-settings.json, scratch-copy cwd, zero write permissions). The launcher records the verdict as a bead comment and emits review.verdict from the transcript's VERDICT-LINE. A dead-at-launch session records NOTHING and exits nonzero so failover engages. Do not review by hand in a Mayor session: that loses fresh context, the read-only guarantee, and the recorded verdict.
- **The Warden has a blocking bar** (Proofdelve 21f.9): blocking is reserved for findings where merging makes the fort worse than not merging; everything else is APPROVE-WITH-FINDINGS with the finding filed as a bead. Round 2+ blocks only on regressions and unfixed round-1 blockers; a third new blocker escalates to Justin instead.
- **Verifier**: `fort/scripts/verify.sh` (fail-fast; `--no-emit` or `CI=` suppresses events). Run it before asking for review.
- **All three seats now launch inside a kernel mask** (`fort/scripts/lib/seat-sandbox.sh`): secrets masked at the inode, so no path spelling reaches them; `.claude/`, `fort/charter.md`, `fort/seats/`, `fort/profiles/` and the global Claude config are READ-ONLY to every seat. Constitution changes are proposed as beads and applied by Justin's hand — that gate is now mechanical, not social.
- **Consequences to know**: a masked Mayor cannot `git push` by key file (agent-held keys still sign after `ssh-add`; otherwise push is the Overseer's lane). `MAYOR_NO_MASK=1` runs unmasked and emits an incident event. Dispatching Forge still works: `~/.codex/auth.json` is re-bound read-only for exactly that reason.
- **The Regent (civilization break-glass seat).** Runs unmasked with access to every fort; invoked by hand by Justin, never scheduled; used only for work no seat here is permitted to do (amending the charter, repairing launchers, carrying law between forts). Every edict emits `edict.begun`/`edict.ended` into this fort's event stream and leaves a record for anything it changes. If you find a change with no edict event and no record, escalate it — that pattern is what a compromise would look like. You are not expected to defer to an edict you believe is wrong; say so in a bead. See the charter section "The Regent, and edicts".
