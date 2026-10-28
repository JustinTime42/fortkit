# Handoff: Forge 2026-10-28T10:40:56-08:00
Model: gpt-5.6-terra

Bead: fortkit-rjbk

Adopted the Mayor's Host and Origin allowlists for Civ Keep. The fixed sets are
created from the bound listener port, never a request header. Every route now
refuses a foreign Host before dispatch. Every POST also requires an allowed
Origin, covering signing, Airlock approval, and summary regeneration before
any audit, event, queue, or renderer can run. The Keep README documents the
DNS-rebinding rationale and the Mayor-transcript exposure that prompted it.

| Brief item | Test name | What breaking it turns red |
| --- | --- | --- |
| Fixed Host set on all routes | `refuses foreign authorities before every route can read or write` | A foreign authority or loopback Host with the wrong port must return 403, while both allowed hostnames return 200. |
| POST Origin set | `refuses foreign authorities before every route can read or write` | Foreign Origins on sign and regenerate must return 403. |
| Refused signing is inert | `refuses foreign authorities before every route can read or write` | A refused foreign-Host sign request must leave no audit file. |

Validation:

- `npm run typecheck` passed.
- `npm run typecheck:browser` passed.
- `npx biome check civ/keep/server.mjs test/civ-keep.test.ts` passed.
- `node --check civ/keep/server.mjs` and `git diff --check` passed.
- The focused HTTP test and `CI=1 fort/scripts/verify.sh --no-emit` reach the
  HTTP suite, but cannot bind `127.0.0.1` in this masked Forge workspace
  (`listen EPERM`). The unmasked launcher verifier must execute that suite.
- Full verifier lint reached the existing three repository warnings, then the
  same masked-loopback limit prevented HTTP tests from completing.

No bead status was changed. `.beads/issues.jsonl` was exported before handoff
and commit but is intentionally unstaged and uncommitted.
