# Warden verifier allowlist proposal (fortkit-hn2)

This is a gate-1 proposal only. It does **not** modify
`fort/profiles/warden-settings.json`; that file is kernel-read-only to the
Forge. The complete proposed replacement is
[`warden-settings.json.proposed`](warden-settings.json.proposed), and the
profile-only diff is [`warden-settings.diff`](warden-settings.diff).

## Diagnosis

`fort/scripts/warden.sh` deterministically launches Claude with
`--setting-sources ""` and the single Warden settings file. Its headless
default denies Bash commands not covered by that profile. The launcher does
not select permissions per session.

The observed same-day variance instead follows command spelling:

- The profile allows bare `fort/scripts/verify.sh*`, but the documented
  event-free invocation is `CI=1 fort/scripts/verify.sh --no-emit`. The latter
  starts with `CI=1`, so it does not match the bare rule.
- The verifier runs `npm run typecheck`, `npm run typecheck:browser`, and
  `npm run lint`; none has an allow rule. It also has no direct `npx biome
  check` rule, and limits Vitest to the `run` spelling.
- The existing broad `npm test*` and `shellcheck *` rules explain sessions
  that could run only those individual gates. Claude's documented classifier
  may auto-allow some unlisted read-only commands, but the profile itself says
  that fallback is not reliable. Thus a Warden's incidental command phrasing
  changes which verifier gates can run.

This is an allowlist-coverage defect plus harness prompt variance, not
launcher nondeterminism. It is grounded in the profile and launcher launch
shape; the two required in-Warden review runs below are the final empirical
confirmation.

## Covered invocation set

The proposed profile explicitly admits the verifier's five gates and the
documented read-only ways a Warden may reproduce them:

| Gate | Bare/direct form | `CI=1` / `TZ=<zone>` form |
| --- | --- | --- |
| Install | `npm ci` | `CI=1 npm ci`, `TZ=<zone> npm ci` |
| Node typecheck | `npm run typecheck`, `npx tsc` | same with prefix |
| Browser typecheck | `npm run typecheck:browser`, `npx tsc --project tsconfig.browser.json` | same with prefix |
| Lint | `npm run lint`, `npx biome check .` | same with prefix |
| Test | `npm test`, `npm run test`, `npx vitest run` | same with prefix |
| ShellCheck | `shellcheck -x …` | same with prefix |
| Full verifier | `fort/scripts/verify.sh --no-emit` | `CI=1 fort/scripts/verify.sh --no-emit`; the `TZ=<zone>` and combined `CI=1 TZ=<zone>` spellings are also covered |

`CI=1 TZ=<zone>` is explicitly covered in that order. Reversing the two
assignments, using `env`, or introducing another environment variable is not
part of the documented interface and remains intentionally ungranted. This
keeps an allow rule tied to a known executable instead of granting `*=* *`.

## Apply by the Overseer's hand

From the repository root, after Warden review of this proposal:

```bash
cp -f docs/proposals/warden-allowlist/warden-settings.json.proposed fort/profiles/warden-settings.json
```

Then validate the installed JSON before launching a review:

```bash
jq -e . fort/profiles/warden-settings.json
```

## Standing-order-5 verification

After application, run two consecutive fresh Warden sessions against a
small, known-green candidate. Neither transcript may rely on the other.

1. In each Warden prompt, require these exact commands, recording the exit
   status of each: `npm ci`; `npm run typecheck`; `npm run typecheck:browser`;
   `npm run lint`; `npm test`; and `shellcheck -x` over the same surface as
   `fort/scripts/verify.sh`.
2. In the same session require `CI=1 fort/scripts/verify.sh --no-emit` and
   `TZ=America/Anchorage npm test`. These prove the previously unlisted
   prefix spellings, while the full verifier proves every gate end to end.
3. Record both Warden verdict transcripts on fortkit-hn2. The acceptance
   criterion is satisfied only if both consecutive sessions reproduce all
   five verifier gates without a permission denial. If either command is
   denied, append its exact spelling and denial text here, then amend the
   proposal rather than depending on classifier fallback.

The test remains read-only in the Warden's scratch copy; `npm ci` may alter
only that copy's dependency directory, never the candidate checkout.
