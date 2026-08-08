# Warden verifier allowlist proposal (fortkit-hn2)

This is a gate-1 proposal only. It does **not** modify
`fort/profiles/warden-settings.json`; that file is kernel-read-only to the
Forge. The complete proposed replacement is
[`warden-settings.json.proposed`](warden-settings.json.proposed), and the
profile-only diff is [`warden-settings.diff`](warden-settings.diff).

## Diagnosis

`fort/scripts/warden.sh` deterministically launches Claude with
`--setting-sources ""` and the single Warden settings file. Nothing in the
launcher selects permissions per session.

The recorded same-day variance is instead a coverage defect exposed by command
spelling and classifier fallback. The current profile explicitly permits bare
`fort/scripts/verify.sh*`, but misses `./fort/scripts/verify.sh*` and the
Warden scratch's absolute `/tmp/warden-*/fort/scripts/verify.sh*` form. It also
omits direct `npm run typecheck`, `npm run typecheck:browser`, `npm run lint`,
and `npx biome check` rules. The existing broad `npm test*` and `shellcheck *`
rules explain sessions that could run only those individual gates.

The classifier can also decide uncovered read-only spellings differently across
sessions: Warden evidence shows that an unlisted `CI=1 fort/scripts/verify.sh
--no-emit` can run while listed-adjacent commands such as `npm run lint` are
denied. The dominant variance is therefore classifier decisions on uncovered
spellings, rather than deterministic rule mismatch alone. Explicit rules still
remove the classifier from each verifier gate, which is why this remedy stands.
The profile's existing caveat remains authoritative: the allow list is a
convenience, not a security boundary; deny rules and the kernel mask remain the
boundary.

## Covered invocation set

The proposal preserves every existing allow and deny entry, appends the live
profile's verified record, and adds only the missing documented gates and
verifier spellings. Arrays remain one rule per line so the applied profile is
Biome-compatible and reviewable.

| Gate | Explicitly covered command forms |
| --- | --- |
| Install | `npm ci` |
| Node typecheck | `npm run typecheck`, `npx tsc` |
| Browser typecheck | `npm run typecheck:browser`, `npx tsc --project tsconfig.browser.json` |
| Lint | `npm run lint`, `npx biome check .` |
| Test | `npm test`, `npm run test`, `npx vitest run` |
| ShellCheck | `shellcheck -x …` |
| Full verifier | `fort/scripts/verify.sh --no-emit`, `./fort/scripts/verify.sh --no-emit`, `/tmp/warden-<bead>/fort/scripts/verify.sh --no-emit`, and each with `CI=1` or `TZ=<zone>` prefixed |

The `/tmp/warden-<bead>/…` form is the Warden launcher's deterministic scratch
path. It is the absolute form a Warden uses while obeying standing order 4.
The proposal does not assert that other environment-variable orderings or
additional prefixes are denied: glob semantics and classifier behavior make
that a claim this artifact cannot support.

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

After application, run two consecutive fresh Warden sessions against a small,
known-green candidate. Neither transcript may rely on the other.

1. In each session, run and record the exit status for `npm ci`; `npm run
   typecheck`; `npm run typecheck:browser`; `npm run lint`; `npm test`; and
   `shellcheck -x` over the same surface as `fort/scripts/verify.sh`.
2. In that same session, run and record all six full-verifier spellings:
   `fort/scripts/verify.sh --no-emit`; `./fort/scripts/verify.sh --no-emit`;
   `/tmp/warden-<bead>/fort/scripts/verify.sh --no-emit`; and the corresponding
   three forms prefixed with `CI=1`. Run `TZ=America/Anchorage
   /tmp/warden-<bead>/fort/scripts/verify.sh --no-emit` as the documented TZ
   form.
3. Record both Warden verdict transcripts on `fortkit-hn2`. The acceptance
   criterion is satisfied only if both consecutive sessions reproduce all five
   verifier gates without a permission denial. If a command is denied, append
   its exact spelling and denial text here, then amend the proposal rather than
   depending on classifier fallback.

The test remains read-only in the Warden's scratch copy; `npm ci` may alter
only that copy's dependency directory, never the candidate checkout.
