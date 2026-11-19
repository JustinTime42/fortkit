#!/bin/bash
# bead-citation-harness.sh -- proves scripts/bead-citation-check.sh in its three
# outcomes, hermetically: a throwaway git tree, a synthetic export, the real
# script copied in. Clean -> 0; an unresolved cite -> 1 naming it; a cite whose
# commit predates the bead by more than an hour -> 1 REISSUED; no export -> 3.
# It also proves identifier precision: dotted references resolve both type and
# member, invented types warn, bare identifiers need two capitalised words, and
# identifier-search failures or absent paths remain warning-only. The source
# subject lives under src/ while fixture text stays here, so it cannot resolve
# an invented token from prose.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1 (exit $3)"; pass=$((pass+1)); else echo "  FAIL  $1 (expected $2, got $3)"; fail=$((fail+1)); fi; }
has() { grep -Fq -- "$1" "$2"; }
expect_out() { # name pattern...
  local name="$1"; shift; local ok=1
  for pat in "$@"; do has "$pat" "$tmp/out" || ok=0; done
  if [ "$ok" = 1 ]; then echo "  PASS  $name"; pass=$((pass+1)); else echo "  FAIL  $name"; fail=$((fail+1)); fi
}
check_source="${CITATION_CHECK_SRC:-$here/bead-citation-check.sh}"
repo="$tmp/repo"; mkdir -p "$repo/bin" "$repo/scripts" "$repo/src" "$repo/.beads"   # bin/ is outside the scanned set: the script cites real beads in its own comments
cp -f "$check_source" "$repo/bin/bead-citation-check.sh"; chmod +x "$repo/bin/bead-citation-check.sh"
git -C "$repo" init -q -b main
printf '// see fortkit-good and fortkit-early\n' > "$repo/src/a.cs"
printf 'public class DealApplicationService { public void CreateUserAsync() {} }\n' > "$repo/src/DealApplicationService.cs"
printf 'public interface IWorkOsAuthKitClient {}\n' > "$repo/src/IWorkOsAuthKitClient.cs"
GIT_AUTHOR_DATE='2026-09-01T12:00:00-08:00' GIT_COMMITTER_DATE='2026-09-01T12:00:00-08:00' git -C "$repo" -c user.name=h -c user.email=h@h add -A >/dev/null && GIT_AUTHOR_DATE='2026-09-01T12:00:00-08:00' GIT_COMMITTER_DATE='2026-09-01T12:00:00-08:00' git -C "$repo" -c user.name=h -c user.email=h@h commit -q -m one
export_path="$repo/.beads/issues.jsonl"
run() { (cd "$repo" && PATH="$repo/bin:$PATH" bin/bead-citation-check.sh "$repo" >"$tmp/out" 2>&1; echo $?); }
run_check() { local check_src="$1"; cp -f "$check_src" "$repo/bin/bead-citation-check.sh"; chmod +x "$repo/bin/bead-citation-check.sh"; run; }
# 1 no export -> refusal
rm -f "$export_path";                                                                   check "1 no export -> refuse"            3 "$(run)"
# 2 clean: both ids exist, created before (or within an hour of) the citing commit
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n' > "$export_path"
check "2 all resolve, none predates -> clean" 0 "$(run)"; expect_out "2b clean line" "all resolve"
# 3 unresolved: drop fortkit-good from the export
printf '{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n' > "$export_path"
check "3 unresolved cite -> 1"            1 "$(run)"; expect_out "3b names it" "UNRESOLVED" "fortkit-good"
# 4 reissued: fortkit-early created two days after the commit that cites it
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-03T20:30:00Z"}\n' > "$export_path"
check "4 cite predates bead by 2 days -> 1"  1 "$(run)"; expect_out "4b names it" "REISSUED" "fortkit-early"
# 3b the verifier mode: UNRESOLVED warns and exits 0, and still names the id
printf '{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n' > "$export_path"
check "3b unresolved in warn mode -> 0"  0 "$( (cd "$repo" && CITATION_UNRESOLVED=warn bin/bead-citation-check.sh "$repo" >"$tmp/out" 2>&1; echo $?) )"; expect_out "3c warn mode still names it" "UNRESOLVED (warning" "fortkit-good"
# 4b REISSUED still fails in warn mode
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-03T20:30:00Z"}\n' > "$export_path"
check "4c reissued in warn mode -> still 1"  1 "$( (cd "$repo" && CITATION_UNRESOLVED=warn bin/bead-citation-check.sh "$repo" >"$tmp/out" 2>&1; echo $?) )"
# 5 allowlist: the reissued id recorded -> clean again
printf 'fortkit-early  recorded fixture\n' > "$repo/scripts/bead-citation-allow.txt"
check "5 allowlisted finding -> clean"    0 "$(run)"
# 6 identifier references: a real dotted type/member pair is silent; an
# invented type on a real member warns without changing citation-check status.
# shellcheck disable=SC2016 # Fixture text deliberately contains Markdown backticks.
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n{"id":"fortkit-real","status":"open","description":"Use `DealApplicationService.CreateUserAsync`.","acceptance_criteria":""}\n' > "$export_path"
check "6 real identifier -> clean" 0 "$(run)"; if ! grep -Fq "UNRESOLVED IDENTIFIERS" "$tmp/out"; then echo "  PASS  6b real identifier is silent"; pass=$((pass+1)); else echo "  FAIL  6b real identifier is silent"; fail=$((fail+1)); fi
# shellcheck disable=SC2016 # Fixture text deliberately contains Markdown backticks.
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n{"id":"fortkit-invented","status":"open","description":"Use `AnyInventedType.CreateUserAsync`.","acceptance_criteria":""}\n' > "$export_path"
check "7 invented dotted type -> warning only" 0 "$(run)"; expect_out "7b names invented dotted token and advice" "fortkit-invented" "AnyInventedType.CreateUserAsync" "grep it before writing it"
# RED arm: restoring terminal-only dotted resolution makes the invented type
# silent, demonstrating that the first-segment check is the protective arm.
red_check="$tmp/terminal-only-check.sh"
python3 - "${CITATION_CHECK_SRC:-$here/bead-citation-check.sh}" "$red_check" <<'PY'
import sys
source, target = sys.argv[1:]
text = open(source, encoding="utf-8").read()
old = 'symbols = (token.split(".", 1)[0], token.rsplit(".", 1)[-1]) if "." in token else (token,)'
new = 'symbols = (token.rsplit(".", 1)[-1],)'
assert old in text
open(target, "w", encoding="utf-8").write(text.replace(old, new))
PY
check "7c RED arm terminal-only invented type -> clean" 0 "$(run_check "$red_check")"; if ! grep -Fq "UNRESOLVED IDENTIFIERS" "$tmp/out"; then echo "  PASS  7d RED arm makes invented type silent"; pass=$((pass+1)); else echo "  FAIL  7d RED arm makes invented type silent"; fail=$((fail+1)); fi
cp -f "$check_source" "$repo/bin/bead-citation-check.sh"; chmod +x "$repo/bin/bead-citation-check.sh"
# shellcheck disable=SC2016 # Fixture text deliberately contains Markdown backticks.
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n{"id":"fortkit-camel","status":"open","description":"Use `InventedIdentifier`, `CurrentStage`, `ArchivedAt`, and `NormalizeEmailRequired`.","acceptance_criteria":""}\n' > "$export_path"
check "8 two-word camel identifiers -> warning only" 0 "$(run)"; expect_out "8b names InventedIdentifier" "fortkit-camel" "InventedIdentifier"; expect_out "8c names CurrentStage" "CurrentStage"; expect_out "8d names ArchivedAt" "ArchivedAt"; expect_out "8e names NormalizeEmailRequired" "NormalizeEmailRequired"
# Interface-prefixed and acronym-run names are identifier shapes too. The real
# interface must remain silent, while both invented specimens are reported.
# shellcheck disable=SC2016 # Fixture text deliberately contains Markdown backticks.
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n{"id":"fortkit-prefix","status":"open","description":"Use `IInventedWidgetService`, `OAuthInventedStore`, and `IWorkOsAuthKitClient`.","acceptance_criteria":""}\n' > "$export_path"
check "8f interface and acronym identifiers -> warning only" 0 "$(run)"; expect_out "8g names IInventedWidgetService" "fortkit-prefix" "IInventedWidgetService"; expect_out "8h names OAuthInventedStore" "OAuthInventedStore"; if ! grep -Fq "IWorkOsAuthKitClient" "$tmp/out"; then echo "  PASS  8i real IWorkOsAuthKitClient is silent"; pass=$((pass+1)); else echo "  FAIL  8i real IWorkOsAuthKitClient is silent"; fail=$((fail+1)); fi
# RED arm: restoring y08kk's narrowed form makes both new shapes disappear.
red_check="$tmp/y08kk-narrowed-check.sh"
python3 - "${CITATION_CHECK_SRC:-$here/bead-citation-check.sh}" "$red_check" <<'PY'
import sys
source, target = sys.argv[1:]
text = open(source, encoding="utf-8").read()
old = r'[A-Z](?:[a-z0-9]+|(?=[A-Z]))(?:[A-Z]+(?=[A-Z][a-z]|$)|[A-Z][a-z0-9]+)+'
new = r'[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+'
assert old in text
open(target, "w", encoding="utf-8").write(text.replace(old, new))
PY
check "8j RED arm y08kk narrowed form -> clean" 0 "$(run_check "$red_check")"; if ! grep -Fq "IInventedWidgetService" "$tmp/out" && ! grep -Fq "OAuthInventedStore" "$tmp/out"; then echo "  PASS  8k RED arm makes both invented shapes silent"; pass=$((pass+1)); else echo "  FAIL  8k RED arm makes both invented shapes silent"; fail=$((fail+1)); fi
cp -f "$check_source" "$repo/bin/bead-citation-check.sh"; chmod +x "$repo/bin/bead-citation-check.sh"
# shellcheck disable=SC2016 # Fixture text deliberately contains Markdown backticks.
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n{"id":"fortkit-prose","status":"open","description":"`Origin`, `Spa`, and `Lax` are prose; PKCE uses `S256` (Proofdelve ForgeOs-sk3c.22).","acceptance_criteria":""}\n' > "$export_path"
check "9 Origin Spa Lax and S256 are ignored -> clean" 0 "$(run)"; if ! grep -Fq "UNRESOLVED IDENTIFIERS" "$tmp/out"; then echo "  PASS  9b Origin Spa Lax and S256 are silent"; pass=$((pass+1)); else echo "  FAIL  9b Origin Spa Lax and S256 are silent"; fail=$((fail+1)); fi
# An identifier-search failure and an empty path list both warn, skip the pass,
# and retain exit 0. The git wrapper leaves every non-grep command real.
real_git="$(command -v git)"
# shellcheck disable=SC2016 # The wrapper must preserve $1 and $@ for its own shell.
printf '#!/bin/bash\nif [ "$1" = grep ]; then echo forced-grep-failure >&2; exit 42; fi\nexec "%s" "$@"\n' "$real_git" > "$repo/bin/git"; chmod +x "$repo/bin/git"
# shellcheck disable=SC2016 # Fixture text deliberately contains Markdown backticks.
printf '{"id":"fortkit-good","created_at":"2026-09-01T19:30:00Z"}\n{"id":"fortkit-early","created_at":"2026-09-01T20:30:00Z"}\n{"id":"fortkit-grep","status":"open","description":"Use `NormalizeEmailRequired`.","acceptance_criteria":""}\n' > "$export_path"
check "10 forced identifier grep failure -> clean" 0 "$(run)"; expect_out "10b forced grep failure warns" "git grep failed for NormalizeEmailRequired" "forced-grep-failure"
rm -f "$repo/bin/git"
mv -f "$repo/src" "$repo/src-hidden"
check "11 empty identifier search paths -> clean" 0 "$(run)"; expect_out "11b empty identifier search paths warns" "identifier search paths absent; skipping identifier pass"
echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
