# Handoff: Forge 2026-08-17T09:09:51-08:00
Model: gpt-5.6-terra
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

## Launcher-observed verifier result

fort/scripts/verify.sh --no-emit, run by forge.sh after the session at 2026-08-17T09:10:02-08:00: exit 0

```


 RUN  v4.1.10 /home/justin/dev/fortkit-worktrees/opae

(node:256559) ExperimentalWarning: SQLite is an experimental feature and might change at any time
(Use `node --trace-warnings ...` to show where the warning was created)
(node:256565) ExperimentalWarning: SQLite is an experimental feature and might change at any time
(Use `node --trace-warnings ...` to show where the warning was created)

 Test Files  16 passed (16)
      Tests  187 passed (187)
   Start at  09:09:53
   Duration  3.48s (transform 1.20s, setup 0ms, import 1.91s, tests 8.04s, environment 2ms)

template-render: 10 template scripts rendered in 3 passes and linted clean; positive control went red as required.
```
