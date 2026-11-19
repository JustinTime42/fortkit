#!/bin/bash
# verify-once-harness.sh -- Proofdelve ForgeOs-s1reg, criteria 1 (the decision half) and 4.
#
# Proves, against the SHIPPED code extracted from fleet.sh and verify-impl.sh:
#   * verify_tier_of() picks the tier from the bead's own diff, and every forced
#     path (migrations, the auth/visibility surface, fort/ other than handoffs,
#     verify-impl.sh itself, anything unknown) comes out full;
#   * verified_reusable() reuses a host verify as the post-merge pass ONLY on
#     tree equality with a full-tier, Docker, clean run, and names its reason
#     on every refusal;
#   * verify-impl.sh's tier table skips exactly the steps the tier says, and an
#     unknown tier refuses.
# The run-level replay (a real merge that runs no second verify; a merge after
# main moved that does) is scenario 67 of fleet-e2e-harness.sh.
#
# Hermetic: throwaway git repos under mktemp, no fort state read or written.
set -uo pipefail
# THE CALLER'S VERIFY ENVIRONMENT IS NOT THIS HARNESS'S (found by the sitting's
# own full verify at b878e70d): the post-merge and nightly runs set
# VERIFY_REQUIRE_DOCKER=1 and a fleet host verify sets VERIFY_TIER and
# VERIFY_RESULT_FILE, and verify-impl.sh runs this file under them. Every case
# below sets what it asserts about, so nothing is inherited.
unset VERIFY_REQUIRE_DOCKER VERIFY_TIER VERIFY_RESULT_FILE FLEET_VERIFY_TIERS FLEET_VERIFY_REUSE
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
launcher="${FLEET_SH:-$here/../fort/scripts/fleet.sh}"
vimpl="${VERIFY_IMPL_SH:-$here/verify-impl.sh}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1 -- $2"; fail=$((fail + 1)); }
# shellcheck disable=SC2254  # $2 IS a pattern on purpose; a | inside an expansion stays literal
glob() { case "$1" in $2) return 0 ;; esac; return 1; }   # $1 text, $2 a case pattern
check() { if glob "$2" "$3"; then ok "$1"; else no "$1" "$2"; fi; }   # $1 label, $2 actual, $3 pattern

awk '/^run_verifier\(\)[[:space:]]*\{/{f=1} /^verify_tier_of\(\)[[:space:]]*\{/{f=1} /^host_verify\(\)[[:space:]]*\{/{f=1}
     /^verified_reusable\(\)[[:space:]]*\{/{f=1} /^reused_tree=/{print; next}
     /^nightly_backstop_ok\(\)[[:space:]]*\{/{f=1} /^nightly_why=/{print; next}
     /^refresh_reusable\(\)[[:space:]]*\{/{f=1} /^refresh_reused_commit=/{print; next} f{print} /^\}$/{f=0}' "$launcher" > "$work/f.sh"
for sym in 'run_verifier()' 'verify_tier_of()' 'host_verify()' 'verified_reusable()' 'reused_tree='; do
  grep -qF "$sym" "$work/f.sh" || { echo "HARNESS REFUSES: $sym not extracted from $launcher" >&2; exit 3; }
done
bash -n "$work/f.sh" || { echo "HARNESS REFUSES: the extraction from $launcher does not parse" >&2; exit 3; }
# CONDITIONAL (gfuc1 A2): host_verify() that calls refresh_reusable() must have
# it extracted; an older launcher without either still runs (and fails below).
if grep -qE '(^|[^[:alnum:]_])refresh_reusable([^[:alnum:]_(]|$)' "$work/f.sh" && ! grep -q '^refresh_reusable()' "$work/f.sh"; then
  echo "HARNESS REFUSES: the extracted code calls refresh_reusable() and does not define it" >&2; exit 3
fi
# CONDITIONAL (s1reg finding 3): required only when the extracted code calls it,
# so this harness still runs, and fails, against an older launcher.
if grep -qE '(^|[^[:alnum:]_])nightly_backstop_ok([^[:alnum:]_(]|$)' "$work/f.sh" && ! grep -q '^nightly_backstop_ok()' "$work/f.sh"; then
  echo "HARNESS REFUSES: the extracted code calls nightly_backstop_ok() and does not define it" >&2; exit 3
fi
# nightly() writes one nightly outcome into $1/fort/events at $2 hours ago
# (ran:$3, default true); "" for $2 leaves the stream without one.
nightly() { # $1 root, $2 hours ago or "", [$3 ran true|false]
  mkdir -p "$1/fort/events"; rm -f "$1"/fort/events/events-*.jsonl
  [ -n "$2" ] || return 0
  local ts; ts="$(date -d "-$2 hours" -Iseconds)"
  printf '{"ts":"%s","actor":"fleet","seat":"fleet","category":"progress","detail":"Nightly full verify GREEN","payload":{"nightly":true,"ran":%s,"result":"green"}}\n' \
    "$ts" "${3:-true}" > "$1/fort/events/events-$(date -d "-$2 hours" +%F).jsonl"
}
awk '/^verify_tier="\$\{VERIFY_TIER/{f=1} f{print} /^skipped_steps=\(\)/{exit}' "$vimpl" > "$work/t.sh"
grep -q '^tier_skips()' "$work/t.sh" || { echo "HARNESS REFUSES: tier_skips() not extracted from $vimpl" >&2; exit 3; }

# --- run_step(): a successful partial step is SKIP, never PASS (Proofdelve ForgeOs-gsams)
#
# Extract the shipped function, rather than carrying a convenient copy here: its
# skip-file contract is meaningful precisely because the verifier's real runner
# observes it.  The little runner below supplies only run_step's surrounding
# state, then invokes stubs that write (or do not write) its exported file.
extract_run_step() { # $1 verifier source, $2 destination
  awk '/^run_step\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$1" > "$2"
}

extract_run_step "$vimpl" "$work/run-step.sh"
grep -q '^run_step()' "$work/run-step.sh" || { echo "HARNESS REFUSES: run_step() not extracted from $vimpl" >&2; exit 3; }
bash -n "$work/run-step.sh" || { echo "HARNESS REFUSES: extracted run_step() does not parse" >&2; exit 3; }

run_step_fixture() { # $1 verifier source, $2 skip|pass|fail -> output; caller receives its status
  local source="$1" mode="$2" extracted runner
  extracted="$work/run-step-$mode.sh"
  runner="$work/run-step-$mode-runner.sh"
  extract_run_step "$source" "$extracted"
  grep -q '^run_step()' "$extracted" || { echo "HARNESS REFUSES: run_step() not extracted from $source" >&2; return 3; }
  cat "$extracted" > "$runner"
  cat >> "$runner" <<'RUNNER'
tier_skips() { return 1; }
tree_end_json() { printf '{}'; }
emit() { :; }
tree_payload='"tree":{}'
tree_branch=harness
verify_quiet=true
quiet_log="$VERIFY_STEP_LOG_DIR/run-step-fixture-$$.log"
skipped_steps=()
verify_step_count=0
fixture_step() {
  case "$1" in
    skip) printf '%s\n' 'partial fixture work only' > "$VERIFY_STEP_SKIP_FILE" ;;
    pass) : ;;
    fail) printf '%s\n' 'failure must not be hidden by skip note' > "$VERIFY_STEP_SKIP_FILE"; return 1 ;;
  esac
}
if run_step skip-file-fixture fixture_step "$1"; then
  printf 'FIXTURE rc=0 skipped=%s\n' "${skipped_steps[*]:-}"
else
  exit $?
fi
RUNNER
  VERIFY_STEP_LOG_DIR="$work" bash "$runner" "$mode"
}

skip_fixture_passes() { # $1 verifier source; returns true only for the shipped skip outcome
  local out rc
  out="$(run_step_fixture "$1" skip 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && [[ "$out" == *'SKIP'*'partial fixture work only'* ]] && [[ "$out" == *'FIXTURE rc=0 skipped=skip-file-fixture'* ]]; then
    return 0
  fi
  return 1
}

if skip_fixture_passes "$vimpl"; then ok "run_step: a zero-exit skip-file step says SKIP and is listed"
else no "run_step: zero-exit skip-file step" "the shipped runner did not honour VERIFY_STEP_SKIP_FILE"; fi
out="$(run_step_fixture "$vimpl" pass 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [[ "$out" == *'PASS'* ]] && [[ "$out" != *'SKIP'* ]] && [[ "$out" == *'FIXTURE rc=0 skipped=' ]]; then
  ok "run_step: a zero-exit step without a skip file says PASS and is not listed"
else no "run_step: zero-exit ordinary step" "rc=$rc out=$out"; fi
out="$(run_step_fixture "$vimpl" fail 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && [[ "$out" == *'FAIL'*'(exit 1)'* ]] && [[ "$out" != *' SKIP '* ]]; then
  ok "run_step: a failing skip-file step says FAIL, never SKIP"
else no "run_step: failing skip-file step" "rc=$rc out=$out"; fi

# RED, GENERATED. Exact mutation: delete the `if [ -s "$skipf" ]; then` block
# that reads a successful step's skip file, through the following `rm -f
# "$skipf"` that resumes ordinary PASS handling. The skip fixture must then
# report PASS with an empty skipped= list, proving it depends on the shipped
# skip-file read rather than a stub.
skip_file_read_pattern='^    if [[] -s "[$]skipf" []]; then$'
remove_run_step_skip_file_read() { # $1 source, $2 destination; refuses a source without the exact target block
  if ! grep -q "$skip_file_read_pattern" "$1"; then
    echo "HARNESS REFUSES: nothing to mutate: run_step has no skip-file read block" >&2
    return 3
  fi
  awk -v skip_file_read_pattern="$skip_file_read_pattern" '
    $0 ~ skip_file_read_pattern { dropping=1; removed=1; next }
    dropping && /^    rm -f "\$skipf"([[:space:]]+#.*)?$/ { dropping=0; print; next }
    !dropping { print }
    END { if (dropping || !removed) exit 3 }
  ' "$1" > "$2"
}

skip_fixture_loses_skip_status() { # $1 verifier source; assert the specific red outcome
  local out rc
  out="$(run_step_fixture "$1" skip 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && [[ "$out" == *'PASS'* ]] && [[ "$out" != *'SKIP'* ]] && [[ "$out" == *'FIXTURE rc=0 skipped=' ]]
}

mutated_vimpl="$work/verify-impl-without-run-step-skip-file-read.sh"
if ! remove_run_step_skip_file_read "$vimpl" "$mutated_vimpl"; then
  no "RED: run_step skip-file-read removal" "nothing to mutate or exact mutation could not be made"
elif grep -q "$skip_file_read_pattern" "$mutated_vimpl"; then
  no "RED: run_step skip-file-read removal" "exact mutation did not remove the skip-file read"
elif skip_fixture_loses_skip_status "$mutated_vimpl"; then
  ok "RED: deleting run_step's skip-file read changes the fixture to PASS with an empty skipped list"
else
  no "RED: run_step skip-file-read removal" "ASSERTION FAIL: expected rc=0, PASS, and empty skipped= after the exact mutation"
fi

if refusal="$(remove_run_step_skip_file_read "$mutated_vimpl" "$work/should-not-exist.sh" 2>&1)"; then
  refusal_rc=0
else
  refusal_rc=$?
fi
if [ "$refusal_rc" -eq 3 ] && [[ "$refusal" == *'nothing to mutate'* ]]; then
  ok "RED: run_step skip-file-read removal refuses a source that already lacks the target block"
else
  no "RED: run_step skip-file-read removal refusal" "ASSERTION FAIL: expected rc=3 and nothing to mutate, rc=$refusal_rc out=$refusal"
fi

# Warden inversion C: a comment on the success-path rm must not let the
# generated mutation continue into the failure branch's rm.
inversion_c_vimpl="$work/verify-impl-inversion-c.sh"
awk -v skip_file_read_pattern="$skip_file_read_pattern" '
  $0 ~ skip_file_read_pattern { in_skip_read=1 }
  in_skip_read && /^    rm -f "\$skipf"$/ { print $0 " # inversion C"; in_skip_read=0; next }
  { print }
' "$vimpl" > "$inversion_c_vimpl"
inversion_c_mutated="$work/verify-impl-inversion-c-mutated.sh"
if ! grep -q '# inversion C' "$inversion_c_vimpl"; then
  no "RED: inversion C trailing success-path rm comment" "ASSERTION FAIL: inversion C marker did not land"
elif ! remove_run_step_skip_file_read "$inversion_c_vimpl" "$inversion_c_mutated"; then
  no "RED: inversion C trailing success-path rm comment" "ASSERTION FAIL: exact mutation could not be made"
elif skip_fixture_loses_skip_status "$inversion_c_mutated"; then
  ok "RED: inversion C trailing success-path rm comment is caught by the specific outcome"
else
  no "RED: inversion C trailing success-path rm comment" "ASSERTION FAIL: expected rc=0, PASS, and empty skipped= after inversion C"
fi

# --- the repo every tier case builds a branch in
repo="$work/repo"; git -C "$work" init -q -b main repo
git -C "$repo" config user.email h@h; git -C "$repo" config user.name H
echo base > "$repo/README.md"; git -C "$repo" add -A; git -C "$repo" commit -qm base
tier_for() { # $1 case name, then paths to change -> prints the tier verify_tier_of() returns
  local name="$1"; shift
  git -C "$repo" checkout -q -B "c-$name" main
  local p; for p in "$@"; do mkdir -p "$repo/$(dirname "$p")"; echo "$name" >> "$repo/$p"; done
  git -C "$repo" add -A; git -C "$repo" commit -qm "$name"
  bash -c "set -uo pipefail; main_branch=main; $(cat "$work/f.sh"); verify_tier_of '$repo'" 2>&1
}
expect_tier() { # $1 expected, $2 case name, rest paths
  local want="$1" name="$2"; shift 2
  local got; got="$(tier_for "$name" "$@")"
  if [ "$got" = "$want" ]; then ok "tier: $name -> $want"; else no "tier: $name" "expected $want, got '$got' for: $*"; fi
}
expect_tier docs    docs-only        docs/specs/a.md fort/handoffs/forge-2026-10-19-x.md
expect_tier docs    handoff-only     fort/handoffs/forge-2026-10-19-y.md
expect_tier server  server-only      src/digest.ts test/digest.test.ts
expect_tier harness harness-only     scripts/digest-harness.sh scripts/digest.sh
expect_tier full    server-and-harness src/a.ts scripts/a.sh
expect_tier full    gate-1           gate-1-surface/tool-a.sh
expect_tier full    verifier-itself  scripts/verify-impl.sh
expect_tier full    constitution     fort/scripts/fleet.sh
expect_tier full    fort-checklist   fort/checklists/unattended-fleet-run.md
expect_tier full    unknown-root     package.json
# Kill switch and the empty diff both fall to full.
git -C "$repo" checkout -q -B c-empty main
got="$(bash -c "set -uo pipefail; main_branch=main; $(cat "$work/f.sh"); verify_tier_of '$repo'" 2>&1)"
check "tier: an empty diff -> full" "$got" "full"
git -C "$repo" checkout -q c-docs-only
got="$(bash -c "set -uo pipefail; main_branch=main; FLEET_VERIFY_TIERS=off; $(cat "$work/f.sh"); verify_tier_of '$repo'" 2>&1)"
check "tier: FLEET_VERIFY_TIERS=off turns a docs diff into full" "$got" "full"
# s1reg-5: a file RENAMED OUT of a forced-full path, content unchanged (R100),
# must still force full; with rename detection the diff names only docs/.
git -C "$repo" checkout -q -B c-mvbase main
mkdir -p "$repo/gate-1-surface"
printf 'tool body\nline two\nline three\n' > "$repo/gate-1-surface/old-tool.sh"
git -C "$repo" add -A; git -C "$repo" commit -qm mvbase; git -C "$repo" branch -f mvmain HEAD
git -C "$repo" checkout -q -B c-mv mvmain; mkdir -p "$repo/docs"
git -C "$repo" mv gate-1-surface/old-tool.sh docs/old-tool.sh; git -C "$repo" commit -qm mv
got="$(bash -c "set -uo pipefail; main_branch=mvmain; $(cat "$work/f.sh"); verify_tier_of '$repo'" 2>&1)"
check "tier: s1reg-5 a file renamed OUT of gate-1-surface/ into docs/ forces full" "$got" "full"
sed 's/ diff --no-renames --name-only / diff --name-only /' "$work/f.sh" > "$work/f-renames.sh"
if ! cmp -s "$work/f.sh" "$work/f-renames.sh"; then
  got="$(bash -c "set -uo pipefail; main_branch=mvmain; $(cat "$work/f-renames.sh"); verify_tier_of '$repo'" 2>&1)"
  check "RED: with rename detection the same move tiers as docs -- the case above discriminates" "$got" "docs"
else no "RED: rename-detection variant" "could not be generated (sed matched nothing)"; fi
git -C "$repo" checkout -q main
got="$(bash -c "set -uo pipefail; main_branch=nosuchbranch; $(cat "$work/f.sh"); verify_tier_of '$repo'" 2>&1)"
check "tier: a diff git cannot compute -> full" "$got" "full"

# --- verify-impl.sh's tier table
skips() { bash -c "VERIFY_TIER='$1'; $(cat "$work/t.sh"); tier_skips '$2' && echo SKIP || echo RUN" 2>&1; }
row() { # $1 tier, $2 step, $3 SKIP|RUN
  local got; got="$(skips "$1" "$2")"
  if [ "$got" = "$3" ]; then ok "verify-impl tier $1: $2 $3"; else no "verify-impl tier $1: $2" "expected $3, got '$got'"; fi
}
row full    product-gate RUN;  row full    governor-harness RUN
row server  product-gate RUN;  row server  governor-harness SKIP; row server shellcheck SKIP
row docs    product-gate SKIP; row docs   shellcheck SKIP
row harness product-gate SKIP; row harness governor-harness RUN
# the fort's machinery checks skip on product tiers (test-depth-follows-risk, 2026-11-13)
row web     governor-harness SKIP; row web    shellcheck SKIP; row web   harness-source-pins SKIP
row server  queue-lint-harness SKIP; row server shellcheck SKIP
row harness shellcheck RUN;  row harness harness-source-pins RUN
row web     css-coverage RUN; row web    contract-drift RUN; row server bead-citation-check RUN
row full    governor-harness RUN; row full  shellcheck RUN
out="$(bash -c "VERIFY_TIER=bogus; $(cat "$work/t.sh")" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "unknown VERIFY_TIER 'bogus'" <<< "$out"; then ok "verify-impl: an unknown tier refuses (exit 2)"
else no "verify-impl: unknown tier" "rc=$rc out=$out"; fi

# --- verified_reusable(): a real merge in a real repo
r="$work/land"; git -C "$work" init -q -b main land
git -C "$r" config user.email h@h; git -C "$r" config user.name H
echo a > "$r/a"; git -C "$r" add -A; git -C "$r" commit -qm a
git -C "$r" checkout -q -b bead/x; echo b > "$r/b"; git -C "$r" add -A; git -C "$r" commit -qm b
vtree="$(git -C "$r" rev-parse 'HEAD^{tree}')"; vcommit="$(git -C "$r" rev-parse HEAD)"
git -C "$r" checkout -q main; git -C "$r" merge -q --no-ff bead/x -m merge
msha="$(git -C "$r" rev-parse HEAD)"
wd="$work/wd"; mkdir -p "$wd"
res() { # $1 tier, $2 docker, $3 tree, [$4 dirtyAtStart], [$5 headMoved], [$6 skipped json]
  printf '{"result":"pass","tier":"%s","docker":%s,"commit":"%s","tree":"%s","dirtyAtStart":%s,"commitAtEnd":"x","dirtyAtEnd":false,"headMoved":%s,"skippedSteps":%s}\n' \
    "$1" "$2" "$vcommit" "$3" "${4:-false}" "${5:-false}" "${6:-[]}" > "$wd/verified.json"
}
reuse() { # [$1 extra shell] -> "yes|<tree>|<commit>" or "no|<why>"
  bash -c "set -uo pipefail; root='$r'; ${1:-} $(cat "$work/f.sh")
    if verified_reusable '$wd' '$msha'; then echo \"yes|\$reused_tree|\$reused_commit\"; else echo \"no|\$reuse_why\"; fi" 2>&1
}
nightly "$r" 2
res full true "$vtree"; got="$(reuse)"
check "reuse: merged tree == verified tree, full tier, Docker -> REUSED, citing tree and commit" "$got" "yes|$vtree|$vcommit"
res web true "$vtree"; got="$(reuse)"
check "reuse: a web-tier host verify is never reused" "$got" 'no|its tier was web, not full*'
res full false "$vtree"; got="$(reuse)"
check "reuse: a Docker-less host verify is never reused (the pbkk label)" "$got" 'no*Docker*'
res full true "$(git -C "$r" rev-parse 'HEAD~1^{tree}')"; got="$(reuse)"
check "reuse: a merged tree that differs from the verified one (main moved) runs the post-merge verify" "$got" 'no*main moved*'
res full true "$vtree" true; got="$(reuse)"
check "reuse: a host verify of a dirty tree is never reused" "$got" 'no*dirty*'
res full true "$vtree" false true; got="$(reuse)"
check "reuse: a host verify whose HEAD moved mid-run is never reused" "$got" 'no*HEAD moved*'
res full true "$vtree" false false '["test"]'; got="$(reuse)"
check "reuse: a host verify that skipped a step is never reused" "$got" 'no*skipped*'
res full true "$vtree"; got="$(reuse 'FLEET_VERIFY_REUSE=off;')"
check "reuse: FLEET_VERIFY_REUSE=off runs the post-merge verify" "$got" 'no*FLEET_VERIFY_REUSE*'
rm -f "$wd/verified.json"; got="$(reuse)"
check "reuse: no recorded result (an older run, a dead verifier) -> run it" "$got" 'no*no host-verify result*'
printf 'not json\n' > "$wd/verified.json"; got="$(reuse)"
check "reuse: an unparseable result -> run it" "$got" 'no*could not be parsed*'

# s1reg finding 3: THE NIGHTLY BACKSTOP. With no nightly that ran within 36h a
# perfect host verify is not reused, and the record says why.
res full true "$vtree"
nightly "$r" "";      got="$(reuse)"; check "reuse: s1reg-3 no nightly in the stream -> not reused" "$got" 'no|no nightly backstop: *holds no nightly*'
nightly "$r" 40;      got="$(reuse)"; check "reuse: s1reg-3 the newest nightly is 40h old -> not reused" "$got" 'no|no nightly backstop: *more than 36h ago*'
nightly "$r" 2 false; got="$(reuse)"; check "reuse: s1reg-3 a nightly that could not run (ran:false) does not count" "$got" 'no|no nightly backstop:*'
nightly "$r" 40;      got="$(reuse 'FLEET_NIGHTLY_MAX_AGE_H=48;')"; check "reuse: s1reg-3 FLEET_NIGHTLY_MAX_AGE_H=48 admits a 40h-old nightly" "$got" "yes|$vtree|$vcommit"
sed '/^  if ! nightly_backstop_ok; then reuse_why=/d' "$work/f.sh" > "$work/f-nonightly.sh"
if ! cmp -s "$work/f.sh" "$work/f-nonightly.sh"; then
  nightly "$r" ""
  got="$(bash -c "set -uo pipefail; root='$r'; $(cat "$work/f-nonightly.sh")
    if verified_reusable '$wd' '$msha'; then echo yes; else echo \"no|\$reuse_why\"; fi" 2>&1)"
  check "RED: without the backstop check a verify is reused with no nightly at all -- the case above discriminates" "$got" "yes"
else no "RED: no-backstop reuse variant" "could not be generated (sed matched nothing)"; fi
nightly "$r" 2

# RED, GENERATED: the same extraction with the narrowing removed (the tier test
# disabled) must reuse the web-tier verify the shipped code refuses -- so the
# web-tier case above is the narrowing, not something else refusing.
sed 's/if d.get("tier") != "full":/if False:/' "$work/f.sh" > "$work/f-nonarrow.sh"
if ! cmp -s "$work/f.sh" "$work/f-nonarrow.sh"; then
  res web true "$vtree"
  got="$(bash -c "set -uo pipefail; root='$r'; $(cat "$work/f-nonarrow.sh")
    if verified_reusable '$wd' '$msha'; then echo yes; else echo \"no|\$reuse_why\"; fi" 2>&1)"
  check "RED: without the tier test a web-tier verify IS reused -- the case above discriminates" "$got" "yes"
else no "RED: no-narrowing variant" "could not be generated (sed matched nothing)"; fi

# --- host_verify(): removes the old record first and passes tier + result file
mkdir -p "$work/hv/fort/scripts"
cat > "$work/hv/fort/scripts/verify.sh" <<'V'
#!/bin/bash
printf 'tier=%s result=%s docker=%s\n' "${VERIFY_TIER:-unset}" "${VERIFY_RESULT_FILE:-unset}" "${VERIFY_REQUIRE_DOCKER:-unset}"
exit 1
V
chmod +x "$work/hv/fort/scripts/verify.sh"
echo stale > "$wd/verified.json"; nightly "$work/hv" 2
bash -c "set -uo pipefail; main_branch=main; root='$work/hv'; say(){ :; }; $(cat "$work/f.sh"); verify_tier_of(){ printf web; }; host_verify '$work/hv' '$work/hv.out' '$wd'" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$wd/verified.json" ] && grep -q "tier=web result=$wd/verified.json docker=unset" "$work/hv.out"; then
  ok "host_verify: the stale record is removed BEFORE the run, the verifier's own status comes back, tier and result file reach it, Docker is not required"
else no "host_verify" "rc=$rc stale=$([ -e "$wd/verified.json" ] && echo kept || echo gone) out=$(cat "$work/hv.out" 2>/dev/null)"; fi

# s1reg finding 3 on the TIER side: a web diff verifies at web with a fresh
# nightly and at full without one; a generated variant without the check stays web.
hvtier() { # $1 extracted file -> the tier that reached the stub verifier
  bash -c "set -uo pipefail; main_branch=main; root='$work/hv'; say(){ :; }; $(cat "$1"); verify_tier_of(){ printf web; }; host_verify '$work/hv' '$work/hv.out' '$wd'" >/dev/null 2>&1
  sed -n 's/^tier=\([a-z]*\) .*/\1/p' "$work/hv.out"
}
nightly "$work/hv" 2;  check "host_verify: s1reg-3 a fresh nightly keeps the diff's tier (web)" "$(hvtier "$work/f.sh")" "web"
nightly "$work/hv" "";  check "host_verify: s1reg-3 no nightly in the stream forces full" "$(hvtier "$work/f.sh")" "full"
nightly "$work/hv" 40; check "host_verify: s1reg-3 a 40h-old nightly forces full" "$(hvtier "$work/f.sh")" "full"
# shellcheck disable=SC2016  # a sed PATTERN: the $ names the launcher's own text, literally
sed 's/^  if \[ "\$tier" != full \] && ! nightly_backstop_ok; then$/  if false; then/' "$work/f.sh" > "$work/f-notier.sh"
if ! cmp -s "$work/f.sh" "$work/f-notier.sh"; then
  nightly "$work/hv" ""; check "RED: without the backstop check the tier stays web with no nightly -- the case above discriminates" "$(hvtier "$work/f-notier.sh")" "web"
else no "RED: no-backstop tier variant" "could not be generated (sed matched nothing)"; fi

# --- Proofdelve ForgeOs-gfuc1 A2: after a refresh from main, a green host verify of the
# SAME tier whose commit is an ancestor of HEAD is REUSED when everything between
# the two commits is under docs/ or fort/handoffs/, and RE-RUN otherwise.
# A real repo: bead/y verified green at web tier at commit C, then main merged in.
rr="$work/rr"; git -C "$work" init -q -b main rr
git -C "$rr" config user.email h@h; git -C "$rr" config user.name H
mkdir -p "$rr/web" "$rr/docs" "$rr/fort/scripts" "$rr/fort/handoffs"
cat > "$rr/fort/scripts/verify.sh" <<'V'
#!/bin/bash
echo VERIFIER-RAN; exit 0
V
chmod +x "$rr/fort/scripts/verify.sh"
echo a > "$rr/web/a.ts"; echo d > "$rr/docs/x.md"; printf 'fort/events/\n' > "$rr/.gitignore"
git -C "$rr" add -A; git -C "$rr" commit -qm base
git -C "$rr" checkout -q -b bead/y; echo b > "$rr/web/a.ts"; git -C "$rr" commit -qam "bead work"
rc_commit="$(git -C "$rr" rev-parse HEAD)"
rwd="$work/rwd"; mkdir -p "$rwd"; echo {{BEAD_PREFIX}}-y > "$rwd/bead"
rrec() { # $1 tier, [$2 docker], [$3 commit]
  printf '{"result":"pass","tier":"%s","docker":%s,"commit":"%s","tree":"x","dirtyAtStart":false,"commitAtEnd":"x","dirtyAtEnd":false,"headMoved":false,"skippedSteps":[]}\n' \
    "$1" "${2:-true}" "${3:-$rc_commit}" > "$rwd/verified.json"
}
# refresh(): main gains $1 (a path), then main is merged into bead/y.
refresh() { # $1 path changed on main
  git -C "$rr" checkout -q main; mkdir -p "$rr/$(dirname "$1")"; echo "m$RANDOM" >> "$rr/$1"
  git -C "$rr" add -A; git -C "$rr" commit -qm "main: $1"
  git -C "$rr" checkout -q bead/y; git -C "$rr" merge -q --no-edit main
}
rhv() { # $1 extracted file, [$2 extra shell] -> "rc=<n> ran=<yes|no> emit=<line or none>"
  rm -f "$work/rr.emit" "$work/rr.out"
  bash -c "set -uo pipefail; main_branch=main; root='$rr'; fleet_actor=fleet; run_id=R1; say(){ :; }; emit(){ printf '%s ' \"\$@\" >> '$work/rr.emit'; echo >> '$work/rr.emit'; }; ${2:-} $(cat "$1"); verify_tier_of(){ printf web; }; host_verify '$rr' '$work/rr.out' '$rwd'" >/dev/null 2>&1
  local rc=$?
  printf 'rc=%s ran=%s emit=%s' "$rc" "$(grep -q VERIFIER-RAN "$work/rr.out" 2>/dev/null && echo yes || echo no)" "$(cat "$work/rr.emit" 2>/dev/null || echo none)"
}
nightly "$rr" 2
refresh docs/x.md
rrec web; got="$(rhv "$work/f.sh")"
check "gfuc1 A2: a docs-only refresh REUSES the same-tier green: no verifier run, a verify.pass reused:true ran:false naming the verified commit" "$got" "rc=0 ran=no emit=verify.pass *differs from the one it scored only under docs/*\"ran\":false,\"reused\":true,\"refreshReuse\":true,\"sameTree\":false,*\"verifiedCommit\":\"$rc_commit\"*"
check "gfuc1 A2: the reuse event carries the worktree as \"worktree\", never as \"tree\" (warden.sh and push-ready.sh match a run of a tip by payload.tree)" "$(grep -c '"tree":' "$work/rr.emit" 2>/dev/null; true)" "0"
check "gfuc1 A2: the record is left as the run wrote it (the post-merge reuse then refuses on tree inequality and runs)" "$(grep -c "\"commit\":\"$rc_commit\"" "$rwd/verified.json" 2>/dev/null; true)" "1"
rrec server; got="$(rhv "$work/f.sh")"
check "gfuc1 A2: a record of a DIFFERENT tier is never reused" "$got" "rc=0 ran=yes emit=*"
rrec web false; got="$(rhv "$work/f.sh")"
check "gfuc1 A2: a Docker-less record is never reused" "$got" "rc=0 ran=yes emit=*"
# NOT VACUOUS (Warden finding 2, round one): a side-branch commit whose tree
# differs from HEAD only under docs/, so the ancestor test is the ONLY refusal.
git -C "$rr" checkout -q -b side bead/y; echo s >> "$rr/docs/x.md"; git -C "$rr" commit -qam side
side_commit="$(git -C "$rr" rev-parse HEAD)"; git -C "$rr" checkout -q bead/y
rrec web true "$side_commit"; got="$(rhv "$work/f.sh")"
check "gfuc1 A2: a record whose commit is not an ancestor of HEAD is never reused (its tree differs only under docs/)" "$got" "rc=0 ran=yes emit=*"
# shellcheck disable=SC2016  # a sed PATTERN naming the launcher's own text, literally
sed 's/^  if ! git -C "\$wt" merge-base --is-ancestor "\$vc" "\$head" 2>\/dev\/null; then$/  if false; then/' "$work/f.sh" > "$work/f-noanc.sh"
if ! cmp -s "$work/f.sh" "$work/f-noanc.sh"; then
  rrec web true "$side_commit"; check "RED: without the ancestor test the side-branch record IS reused -- the case above discriminates" "$(rhv "$work/f-noanc.sh")" "rc=0 ran=no emit=*"
else no "RED: no-ancestor variant" "could not be generated (sed matched nothing)"; fi
# EMPTY DELTA (Warden finding 1, round one, reproduced): a branch already
# current with main reuses its own green; the event must not promise a
# post-merge run, because the merged tree can equal the scored tree.
rrec web true "$(git -C "$rr" rev-parse HEAD)"; got="$(rhv "$work/f.sh")"
check "gfuc1 A2: an empty delta reuses, says sameTree:true and 'it scored exactly this tree', and promises no post-merge run" "$got" "rc=0 ran=no emit=verify.pass *it scored exactly this tree*\"sameTree\":true*"
check "gfuc1 A2: the retired promise 'post-merge verify still runs' is gone from the event" "$(grep -c 'still runs' "$work/rr.emit" 2>/dev/null; true)" "0"
# RECENT ONLY (the Overseer at the sitting): a 13-hour-old green re-runs; the
# event names the age and the limit; the limit is configurable.
check "gfuc1 A2: the reuse event records the green's age and the limit" "$(grep -c '"verifiedAgeS":[0-9]*,"ageLimitS":43200' "$work/rr.emit" 2>/dev/null; true)" "1"
rrec web true "$(git -C "$rr" rev-parse HEAD)"; touch -d '13 hours ago' "$rwd/verified.json"; got="$(rhv "$work/f.sh")"
check "gfuc1 A2: a green older than 12h is NOT reused, even on an empty delta" "$got" "rc=0 ran=yes emit=*"
rrec web true "$(git -C "$rr" rev-parse HEAD)"; touch -d '13 hours ago' "$rwd/verified.json"; got="$(rhv "$work/f.sh" 'FLEET_REFRESH_REUSE_MAX_AGE_H=24;')"
check "gfuc1 A2: FLEET_REFRESH_REUSE_MAX_AGE_H=24 admits the 13h-old green" "$got" "rc=0 ran=no emit=*"
rrec web true "$(git -C "$rr" rev-parse HEAD)"; got="$(rhv "$work/f.sh" 'FLEET_REFRESH_REUSE_MAX_AGE_H=0;')"
check "gfuc1 A2: FLEET_REFRESH_REUSE_MAX_AGE_H=0 turns the refresh reuse off, even for a green from this second" "$got" "rc=0 ran=yes emit=*"
# shellcheck disable=SC2016  # a sed PATTERN naming the launcher's own text, literally
sed 's/^  if \[ "\$refresh_reuse_age_s" -gt "\$refresh_reuse_limit_s" \]; then$/  if false; then/' "$work/f.sh" > "$work/f-noage.sh"
if ! cmp -s "$work/f.sh" "$work/f-noage.sh"; then
  rrec web true "$(git -C "$rr" rev-parse HEAD)"; touch -d '13 hours ago' "$rwd/verified.json"
  check "RED: without the age test the 13h-old green IS reused -- the case above discriminates" "$(rhv "$work/f-noage.sh")" "rc=0 ran=no emit=*"
else no "RED: no-age variant" "could not be generated (sed matched nothing)"; fi
rrec web; got="$(rhv "$work/f.sh" 'FLEET_VERIFY_REUSE=off;')"
check "gfuc1 A2: FLEET_VERIFY_REUSE=off re-runs" "$got" "rc=0 ran=yes emit=*"
refresh web/b.ts
rrec web; got="$(rhv "$work/f.sh")"
check "gfuc1 A2: a refresh that touches the tier (web/) RE-RUNS" "$got" "rc=0 ran=yes emit=*"
check "gfuc1 A2: and the re-run removed the old record before running" "$([ -e "$rwd/verified.json" ] && echo kept || echo gone)" "gone"
# RED, GENERATED: with the delta test disabled the web refresh IS reused, so the
# case above is the delta test and nothing else refusing.
# shellcheck disable=SC2016  # a sed PATTERN naming the launcher's own text, literally
sed 's/^      \*) refresh_reuse_why="the delta since the verified commit.*return 1 ;;$/      *) ;;/' "$work/f.sh" > "$work/f-nodelta.sh"
if ! cmp -s "$work/f.sh" "$work/f-nodelta.sh" && bash -n "$work/f-nodelta.sh" 2>/dev/null; then
  rrec web; check "RED: without the delta test a refresh touching web/ IS reused -- the case above discriminates" "$(rhv "$work/f-nodelta.sh")" "rc=0 ran=no emit=*"
else no "RED: no-delta-test variant" "could not be generated (sed matched nothing, or the variant does not parse)"; fi

# The only path that reaches host_verify() with an earlier record is a signed
# landing, and only if its worker reset keeps verified.json (source assertion:
# the find in signed_landing() excludes it).
sl="$(awk '/^signed_landing\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$launcher")"
check "gfuc1 A2: signed_landing() keeps verified.json across its worker reset" "$(grep -c -- '! -name verified.json -exec rm -rf' <<< "$sl"; true)" "1"

# --- forge_model_for(): the three routes (docket 2026-11-13 item B; Warden
# finding 7 on gfuc1: "unknown" must not read as "default").
awk '/^forge_model_route=/{print; next} /^forge_model_for\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$launcher" > "$work/fm.sh"
if grep -q '^forge_model_for()' "$work/fm.sh"; then
  fmr() { # $1 bead_has_label rc, $2 strong model -> "<model>|<route>"
    bash -c "set -uo pipefail; say(){ :; }; bead_has_label(){ return $1; }; FLEET_FORGE_MODEL=dflt; FLEET_FORGE_MODEL_STRONG='$2'; $(cat "$work/fm.sh")
      m=\$(forge_model_for B-1 > '$work/fm.out'; cat '$work/fm.out'); forge_model_for B-1 >/dev/null; echo \"\$m|\$forge_model_route\"" 2>/dev/null
  }
  check "forge_model_for: a labelled bead -> strong model, route strong" "$(fmr 0 astra)" "astra|strong"
  check "forge_model_for: an unlabelled bead -> default model, route default" "$(fmr 1 astra)" "dflt|default"
  check "forge_model_for: the tracker cannot say -> default model, route UNKNOWN (never reads as default)" "$(fmr 2 astra)" "dflt|unknown"
  check "forge_model_for: no strong model configured -> default, route default, the label not even asked" "$(fmr 0 '')" "dflt|default"
else no "forge_model_for" "not extracted from $launcher"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
