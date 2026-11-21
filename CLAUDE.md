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
npm run lint
npm test
fort/scripts/verify.sh
```

`fort/scripts/verify.sh` is the authoritative fail-fast verifier (a shim over
`scripts/verify-impl.sh`). It runs the lints, the typecheck, biome, vitest,
ShellCheck over the shipped shell surface, the isolation gate and the fort's
harness suite. Pass `--no-emit` (or set `CI`) to suppress event-stream writes.

## Architecture Overview

_Add a brief overview of your project architecture_

## Conventions & Patterns

- **The Bartizan viewer is retired** (Overseer, 2026-11-18, docket `fort/annals/regent-docket-2026-11-18-manyhalls-refound.txt`): the world and colony views, the `world` and `ambient` commands and the browser typecheck are gone; their specs are in `fort/annals/`. `src/cli.ts` keeps `status`, `digest`, `herald-lint` and `recall`.
- **The Overseer's board for this fort is the open beads ASSIGNED to `justin`** (since 2026-11-20, `fortkit-awlc`; the Civ Keep treats Manyhalls as it treats Proofdelve). A seat hands a bead to him with `scripts/flag-human.sh`, which assigns it and posts an `ASK: <verb> --` comment line; the fleet does the same when it holds a bead for his signature; his answer on the Keep hands the bead back. **History, kept because old beads still carry the labels:** from 2026-08-08 (Overseer adoption, from the fortkit-fci.1 proposal) until 2026-11-20, the signal was the exact label `gate-1`, `gate-2` or `gate-3`, applied by the Mayor at filing. A label alone no longer puts a bead in front of him. **Amended 2026-11-18 at the re-founding:** the fleet machinery Manyhalls runs since then does not read these labels. Its hand-off to the Overseer is a bead assigned to `justin` with an `ASK:` comment line (`scripts/flag-human.sh`), which also carries the `human` label the Keep shows. Labels applied before that date use the gate numbers of the charter of the time (1 the constitution, 2 secrets, 3 public-facing); the charter's numbers changed and the old labels were not rewritten.

## Manyhalls — the fortkit Fort

This repo is operated by an agent fort of Justin's civilization (registry: ~/.claude/civilization.json). Before any work: read fort/charter.md (gates, standing orders), fort/memory/current.md (distilled view; facts ledger in fort/memory/facts/), your seat file in fort/seats/ (session protocols + handoff schema). Work flows through beads: bd ready, claim atomically, reference bead IDs in commits, close only after verifiers green + review. The fact ledger in `fort/memory/facts/` overrides legacy `bd prime` memory guidance. Emit events via fort/scripts/emit.sh. Hard rules: never read .env*; never git add . ; path-scoped staging only. `bd` is authoritative for bead state: `.beads/issues.jsonl` is a throttled projection that can sit stale indefinitely, so any count quoted into a durable record comes from `bd`, and `bd export -o .beads/issues.jsonl` is run before a review, handoff, or commit — see `docs/specs/beads-export.md`.

**Looking something up in the fort's record** (`fortkit-efv9.13`): from the root checkout, before grepping, run `npm run -s recall -- <words> [--limit N] [--seat S] [--bead ID] [--since DATE]`. It searches facts, beads (with descriptions and close reasons), handoffs, events, annals and the civ record, ranked by how many of your words each hit contains, newest first among equals, and says how many matches it did not show. It does not cover the charter, seat files, specs or code; read those directly. A hit is a pointer: open its source before citing it. Not for the Researcher, which has no shell; not for the Warden, for whom it is not allow-listed and whose working directory is a frozen copy; nor yet for the Forge from a worktree (it indexes the directory it runs in).
