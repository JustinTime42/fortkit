# Handoff: Forge 2026-08-17T09:10:00-08:00
Model: gpt-5.6
## State of work

- `fortkit-opae` remains in progress for Warden review and Mayor closure. Factory charter and Mayor-seat prose now describe Shape B, with no `verify.sh` write carve-out.

## Verified facts

- `templates/fort/charter.md:13` now says `fort/scripts/` is read-only whole, `fort/scripts/verify.sh` is a shim, and `scripts/verify-impl.sh` is Mayor-writable and Forge/Warden read-only in their respective masks.
- `templates/fort/seats/mayor.md:14` now directs verifier changes to `scripts/verify-impl.sh`, says `fort/scripts/verify.sh` is a read-only shim, and preserves the Forge restriction.
- A real fort founded at `/tmp/fortkit-opae-founded.UPi7Td` rendered both Shape B statements. A grep for the two retired carve-out claims (`with verify.sh alone re-granted writable` and `verify.sh is writable to the Mayor`) found neither.
- `npm test -- test/shell.test.ts` passed, including the existing founding smoke (7 tests).

## Next actions

1. Warden review this scoped factory-prose change.
2. Mayor closes `fortkit-opae` only after review and merge.
3. `fortkit-domm` can extend its founding smoke with these rendered-prose assertions as planned.

## Open risks / questions

- The full authoritative verifier is red on seven unrelated `test/seats.test.ts` cases under the project-pinned Node `v24.14.0`. `child_process.execFile(process.execPath, ["-e", "console.log(123)"])` exits 0 with empty stdout in this environment, whereas `node -e 'console.log(123)'` prints normally. The seat-lint tests use `execFile` and consequently receive empty diagnostics. The other 15 test files passed (180 tests).

## Failed attempts

- The initial negative grep allowed text after a `verify.sh` reference to match the correct later `verify-impl.sh` writable statement. It was narrowed to the two retired Shape A claims before recording the founded-fort result.
- A verifier run inside the throwaway founded fort stopped at `tsc: command not found` because its fixture intentionally has no installed dependencies. The repository-level verifier was run after `npm ci`; its only failures are the unrelated seat-lint runtime issue above.
