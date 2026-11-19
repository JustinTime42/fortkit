#!/bin/bash
# evidence-harness.sh -- Proofdelve ForgeOs-tgm5o (Regent docket 2026-10-22 item C): a RED
# host verify returns the failing step, not the verify log's last 60 lines.
#
# Extracts the SHIPPED evidence_of() from fort/scripts/fleet.sh (FLEET_SH
# overrides) and runs it over fixture logs shaped like the real ones: dotnet's
# `  Failed <Test> [..]` blocks with Error Message and Stack Trace, buried under
# Testcontainers lines, beside the app's own "      Failed to load deal detail."
# log line that must never read as a failing test. The real logs these were
# shaped from are named in the commit that added this file; they live in /tmp
# and the scratch reaper prunes them, so they cannot be fixtures.
#
# Refuses (exit 3) when fleet.sh has no evidence_of(): the function is new, and
# a refusal against the pre-tgm5o launcher is that file's inversion.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
subject="${FLEET_SH:-$here/../fort/scripts/fleet.sh}"
[ -s "$subject" ] || { echo "HARNESS REFUSES: no fleet.sh at $subject" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
sed -n '/^evidence_of() {/,/^}/p' "$subject" > "$work/eo.sh"
grep -q '^evidence_of() {' "$work/eo.sh" || { echo "HARNESS REFUSES: $subject defines no evidence_of()" >&2; exit 3; }
bash -n "$work/eo.sh" || { echo "HARNESS REFUSES: the extracted evidence_of() does not parse" >&2; exit 3; }
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1 -- $2"; fail=$((fail + 1)); }
ev() { bash -c "source '$work/eo.sh'; evidence_of \"\$1\"" _ "$1"; }
noise() { local i; for ((i = 0; i < $1; i++)); do printf '[testcontainers.org 00:02:%02d.10] Execute "pg_isready --host localhost" at Docker container 74f5da7fb4a1\n' "$((i % 60))"; done; }
app_noise() { printf 'info: Product.Api.DealApplicationService[0]\n      Failed to load deal detail. DealId=bbbbbbbb UserId=44444444 UserRole=Member\n'; }
block() {  # $1 test name, $2 message, $3 file:line
  printf '  Failed Product.Tests.%s [921 ms]\n  Error Message:\n   %s\n  Stack Trace:\n' "$1" "$2"
  printf '     at FluentAssertions.Execution.XUnit2TestFramework.Throw(String message)\n'
  printf '   at Product.Tests.%s() in {{REPO_PATH}}-worktrees/x/tests/Product.Tests/%s\n' "$1" "$3"
  printf -- '--- End of stack trace from previous location ---\n'
}

# 1. a full verify log: the failure is ~2000 lines above the end, noise after it
{
  noise 40; app_noise
  block 'MigrationTests.Upload_round_trips' 'System.NullReferenceException : Object reference not set to an instance of an object.' 'MigrationTests.DocumentUploads.cs:line 53'
  app_noise; noise 2000
  printf '\nFailed!  - Failed:     1, Passed:  1194, Skipped:     0, Total:  1195\n'
  printf "verify: step 'dotnet-test' FAILED (exit 1). Its full output is kept at %s/gone.log\n" "$work"
} > "$work/full.txt"
out="$(ev "$work/full.txt")"
if grep -qF 'Failed Product.Tests.MigrationTests.Upload_round_trips [921 ms]' <<<"$out" && grep -qF 'NullReferenceException' <<<"$out" \
   && grep -qF 'first frame: at Product.Tests.MigrationTests.Upload_round_trips() in {{REPO_PATH}}-worktrees/x/tests/Product.Tests/MigrationTests.DocumentUploads.cs:line 53' <<<"$out" \
   && grep -qF "verify: step 'dotnet-test' FAILED" <<<"$out" && ! grep -q 'pg_isready' <<<"$out" && ! grep -q 'Failed to load deal detail' <<<"$out"; then
  ok "a dotnet failure 2000 lines above the end is returned: test name, error message, the first frame in tests/ (file:line), the step's FAILED line; no Testcontainers line and no app 'Failed to load' line"
else no "the failing test did not reach the return" "$(printf '%s' "$out" | head -8 | tr '\n' '|' | cut -c1-300)"; fi

# 2. only the TAIL survives in the evidence: the blocks come from the kept step log it names
{ noise 20; app_noise; block 'DealDeletionTests.Deletion_removes_dependents' 'Expected rows to be empty' 'DealDeletionTests.cs:line 26'
  block 'EndpointInventoryTests.Inventory_matches' 'endpoint inventory differs from the committed snapshot' 'EndpointInventoryTests.cs:line 40'; noise 50; } > "$work/kept-dotnet.log"
{ noise 60; printf "verify: step 'dotnet-test' FAILED (exit 1). Its full output is kept at %s/kept-dotnet.log\n" "$work"; } > "$work/tail.txt"
out="$(ev "$work/tail.txt")"
if grep -qF "Failing tests (2), from $work/kept-dotnet.log" <<<"$out" && grep -qF 'DealDeletionTests.cs:line 26' <<<"$out" && grep -qF 'EndpointInventoryTests.cs:line 40' <<<"$out" && ! grep -q 'pg_isready' <<<"$out"; then
  ok "when the evidence holds only Testcontainers noise and the step's FAILED line, both failing tests come from the kept step log it names, and the return says that is where they came from"
else no "the kept step log was not read" "$(printf '%s' "$out" | head -6 | tr '\n' '|' | cut -c1-300)"; fi

# 3. a step that is not dotnet-test: its FAILED line and the tail of ITS kept log
{ printf 'src/App.tsx\n  12:3  error  Unexpected any  @typescript-eslint/no-explicit-any\n'; printf 'lint line %s\n' $(seq 1 80); printf 'X1 problem (1 error, 0 warnings)\n'; } > "$work/kept-lint.log"
{ noise 30; printf "verify: step 'web-lint' FAILED (exit 1). Its full output is kept at %s/kept-lint.log\n" "$work"; noise 5; } > "$work/lint.txt"
out="$(ev "$work/lint.txt")"
if grep -qF "verify: step 'web-lint' FAILED (exit 1)" <<<"$out" && grep -qF "of that step's kept log ($work/kept-lint.log)" <<<"$out" && grep -qF 'X1 problem (1 error, 0 warnings)' <<<"$out" && ! grep -q 'pg_isready' <<<"$out"; then
  ok "a non-dotnet step returns the verifier's own FAILED line and the tail of THAT step's kept log, not the verify log's"
else no "a non-dotnet step's evidence is not its own" "$(printf '%s' "$out" | head -4 | tr '\n' '|' | cut -c1-300)"; fi

# 4. the kept log is gone and no block is in the evidence: the old tail, said so
{ noise 70; printf "verify: step 'dotnet-test' FAILED (exit 1). Its full output is kept at %s/pruned.log\n" "$work"; } > "$work/pruned.txt"
out="$(ev "$work/pruned.txt")"
if grep -qF "kept log ($work/pruned.log) is gone. Last 60 lines of the evidence" <<<"$out" && [ "$(grep -c 'pg_isready' <<<"$out")" -le 60 ]; then
  ok "a kept log that no longer exists falls back to the evidence's last 60 lines and says why"
else no "the pruned-kept-log fallback is not as declared" "$(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi

# 5. no step was named at all (not a verify log): the old tail, said so
noise 90 > "$work/plain.txt"
out="$(ev "$work/plain.txt")"
if grep -qF 'No failing step was named in the evidence. Last 60 lines of it' <<<"$out" && [ "$(grep -c 'pg_isready' <<<"$out")" -eq 60 ]; then
  ok "evidence that names no failing step is returned as its last 60 lines, labelled as such"
else no "the plain fallback is not as declared" "$(printf '%s' "$out" | head -2 | tr '\n' '|')"; fi

# 6. an empty or absent evidence file returns nothing (the callers' old guard)
if [ -z "$(ev "$work/absent.txt")" ] && : > "$work/empty.txt" && [ -z "$(ev "$work/empty.txt")" ]; then
  ok "an absent or empty evidence file adds nothing to the return"
else no "an absent or empty evidence file printed something" "$(ev "$work/absent.txt" | head -2)"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
