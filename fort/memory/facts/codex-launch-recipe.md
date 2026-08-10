---
key: codex-launch-recipe
status: active
superseded-by: null
tier: on-demand
scope:
  seats: [mayor, forge]
  topics: [codex, launchers]
  beads: [fortkit-88u.5]
provenance:
  source: "4dc2038:fort/remember.md:5"
  declared-by: kethra
  date: 2026-08-10
  origin: trusted
---
The Codex launch recipe must run from the worktree with a workspace-write
sandbox, stdin redirected from `/dev/null` (the redirect is mandatory), and
the worktree pre-trusted via `-c 'projects."<worktree>".trust_level="trusted"'`
(the source recipe's load-bearing half, restored per Warden 88u.5 r2 f5).
