# Handoff: Forge 2026-10-28T10:50:02-08:00
Model: gpt-5.6-terra

## State of work

`fortkit-rjbk` remains in progress for Mayor review. The Host allowlist server
implementation in `e3e0994` was already applied before every router branch.
Round two corrects its test: Undici `fetch` derives Host from its URL and did
not transmit the foreign authority. The test now uses `node:http`, which sends
the explicit Host header unchanged, and checks every route branch.

## Verified facts

| Brief item | Test name | What breaking it turns red |
| --- | --- | --- |
| Every route rejects a foreign Host before work | `refuses foreign authorities before every route can read or write` | Removing the router's first Host guard makes the page, static, API, event stream, or POST request return a non-403 result. |
| Both fixed allowed Hosts work; wrong loopback port fails | `refuses foreign authorities before every route can read or write` | Changing the listener-derived allowlist rejects `127.0.0.1:<bound-port>` or `localhost:<bound-port>`, or accepts `127.0.0.1:7780` on an ephemeral listener. |
| POST Origins use the same fixed set | `refuses foreign authorities before every route can read or write` | Removing the shared Origin guard lets foreign-Origin signing or regeneration return something other than 403. |
| Refused signing has no audit side effect | `refuses foreign authorities before every route can read or write` | Moving the Host guard after signing creates the audit file. |

`npm run typecheck`, `npm run typecheck:browser`, `npx biome check
test/civ-keep.test.ts`, `node --check civ/keep/server.mjs`, and `git diff
--check` passed.

The focused HTTP test is unexecuted by the Forge: this masked workspace cannot
bind loopback. `npx vitest run test/civ-keep.test.ts -t 'refuses foreign
authorities before every route can read or write'` fails with `listen EPERM:
operation not permitted 127.0.0.1`, then its expected 5-second timeout. The
launcher verifier is the evidence for HTTP behaviour. `CI=1
fort/scripts/verify.sh --no-emit` completed typechecks and lint (three existing
warnings) before entering Vitest; its HTTP run could not finish within this
workspace's execution window for the same bind restriction.

## Next actions

1. Run `CI=1 fort/scripts/verify.sh --no-emit` from the unmasked launcher.
2. Obtain Warden review, then Mayor review and merge if approved.

## Open risks / questions

The test's HTTP assertions await launcher execution. No application-code risk
was found in the Host guard: it precedes every dispatch path in
`civ/keep/server.mjs`.

## Failed attempts

The first implementation test used `fetch(..., { headers: { Host: ... } })`.
Node's Fetch client did not send that foreign Host, so the assertion expected
403 while the server correctly received the URL authority and returned 200.

## Launcher-observed verifier result

fort/scripts/verify.sh --no-emit, run by forge.sh after the session at 2026-10-28T10:51:19-08:00: exit 1

```
    2096|     "refuses to report a founding whose distilled view failed to gener…
    2097|     async () => {

⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[9/10]⎯

 FAIL  test/shell.test.ts > fort-init > refuses to report a founding whose distilled view failed to generate (fortkit-byhp)
Error: ENOTEMPTY: directory not empty, rmdir '/tmp/fortkit-shell-iASi3b/fort/scripts'
⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯⎯[10/10]⎯


 Test Files  1 failed | 20 passed (21)
      Tests  8 failed | 318 passed (326)
   Start at  10:50:10
   Duration  68.70s (transform 9.32s, setup 0ms, import 12.56s, tests 126.36s, environment 2ms)

```
