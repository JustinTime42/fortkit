# fortkit operational facts (inject every session)

- Fort founded 2026-08-03 via fort-init; fort name pending the Founding Moot.
- Founding spec: docs/specs/fortress-visualizer.md
- Codex launch recipe: cd into the worktree, --sandbox workspace-write -c 'projects."<worktree>".trust_level="trusted"' -m <model> "<prompt>" </dev/null — the stdin redirect is mandatory.
- No verifiers yet: CI-from-commit-one should be an early bead.
- 2026-08-04: `fort/scripts/verify.sh` is the authoritative verifier, superseding
  the earlier no-verifiers note. It runs TypeScript typecheck, Biome lint,
  Vitest tests, and ShellCheck in that order; `--no-emit` (and `CI`) suppresses
  event emission.
