# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:6cd5cc61 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->


## Build & Test

```bash
npm ci
npm run typecheck
npm run typecheck:browser
npm run lint
npm test
fort/scripts/verify.sh
```

`fort/scripts/verify.sh` is the authoritative fail-fast verifier. It runs
the Node typecheck, the browser typecheck (page scripts against
`tsconfig.browser.json`), lint, test, then ShellCheck over the shipped shell
surface. Pass `--no-emit` (or set `CI`) to suppress event-stream writes.

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

- **Browser page scripts live in checked TypeScript modules** (e.g. `src/world-page.ts`), type-checked and linted like all other source, and composed into their HTML shell at server startup via `stripTypeScriptTypes` at an HTML comment marker. No bundler, no runtime dependencies. Decided on fortkit-b18 (Overseer, 2026-08-07); the colony renderer and any future page follow the same pattern. Hardening items for the pattern are tracked in fortkit-12z.
- **The viewer product is named Bartizan** (Overseer decision, fortkit-zgp, 2026-08-07). CLI command names are unchanged.
- **Gate labels are the single "waiting on the Overseer" signal** (Overseer adoption, 2026-08-08, from the fortkit-fci.1 proposal): any open bead waiting at a human gate carries the exact label `gate-1`, `gate-2`, or `gate-3`; the Mayor applies it at filing. A standing decision carried in a handoff becomes a bead with a gate label. `bd human` stays unused until its flags reach the export. The Keep renders these labels; its prose-cue heuristic is transitional and retires.

## Manyhalls — the fortkit Fort

This repo is operated by an agent fort of Justin's civilization (registry: ~/.claude/civilization.json). Before any work: read fort/charter.md (gates, standing orders), fort/memory/current.md (distilled view; facts ledger in fort/memory/facts/), your seat file in fort/seats/ (session protocols + handoff schema). Work flows through beads: bd ready, claim atomically, reference bead IDs in commits, close only after verifiers green + review. The fact ledger in `fort/memory/facts/` overrides legacy `bd prime` memory guidance. Emit events via fort/scripts/emit.sh. Hard rules: never read .env*; never git add . ; path-scoped staging only.
