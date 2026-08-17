# Handoff: Forge 2026-08-17T09:09:23-08:00
Model: GPT-5 (Codex)

## State of work

- `fortkit-hgbe` remains IN_PROGRESS as instructed. The factory template now
  denies Mayor `Edit` access to `{{HOME}}/.codex/**`, and a founded-fort test
  locks the rendered rule down.

## Verified facts

- `templates/config/settings-permissions.json` adds exactly
  `Edit({{HOME}}/.codex/**)`, scoped to the Mayor's writable Codex directory
  rather than copying the Warden's `Edit(**)` rule.
- A real fort founded at `/tmp/fortkit-hgbe-XeTioo` contains
  `Edit(/tmp/fortkit-hgbe-XeTioo/founder-home/.codex/**)` at
  `.claude/settings.json:102`; the exact required basic `grep -rn
  '{{[A-Z_]*}}'` scan returned no matches.
- `test/shell.test.ts` founds a fort with an explicit absolute `HOME` and
  asserts the generated deny plus no resolved-token residue. Its focused run:
  8 passed.

## Next actions

1. Warden: review the path-scoped `fortkit-hgbe` commit.
2. Mayor: merge after approval and close the bead only after merge.

## Open risks / questions

- The full authoritative verifier reaches type checks and lint but ends red on
  seven unrelated `test/seats.test.ts` assertions. Each receives exit code 1
  from `scripts/seat-lint.mjs` but an empty captured `stderr`, despite the
  script's diagnostics being emitted with `console.error`; the focused new test
  is green. This was present independently of the changed template/test paths.

## Failed attempts

- The first full verifier stopped at formatting; the regression test was
  formatted and the second run passed type checks and lint before exposing the
  unrelated seat-lint failures.
- An extended-regex placeholder scan overmatched intentionally non-token moot
  placeholders. The bead's exact basic `grep` command returned zero matches.
