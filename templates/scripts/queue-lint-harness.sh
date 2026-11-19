#!/bin/bash
# Hermetic regression harness for Proofdelve ForgeOs-eng3.12 turn-taking checks.
set -uo pipefail

# The production default must not be inherited from a caller running this
# harness. Individual timeout cases set their value explicitly below.
unset QUEUE_LINT_BD_TIMEOUT

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
harness_source="${QUEUE_LINT_HARNESS_SRC:-$here/queue-lint-harness.sh}" # harness-source-pins: self
flag_source="${FLAG_HUMAN_SRC:-$here/flag-human.sh}"
lint_source="${QUEUE_LINT_SRC:-$here/queue-lint.sh}"
citation_source="${citation_checker_source:-$(dirname "$lint_source")/bead-citation-check.sh}"
[ -f "$citation_source" ] || citation_source="$here/bead-citation-check.sh"
# Red-arm children re-run this harness with QUEUE_LINT_SRC pointing at a mutant
# in a temp work dir, and verify-impl runs main's copy of this harness from a
# temp dir too, so neither fallback above can find the checker there. Hand the
# resolved path down instead (Proofdelve ForgeOs-e3kdp: main was red on exactly this).
export citation_checker_source="$citation_source"
# Derived from the selected lint source because recursive red arms and the
# verifier copy the pair into a temporary sibling directory; verify-impl has no
# independently wired source variable for this harness.
verify_impl_source="$(dirname "$lint_source")/verify-impl.sh"
prose_source="${PROSE_BLOCKERS_SRC:-$here/unattended-fleet/prose-blockers.py}"
# Pinned like its siblings, and it must be, because verify-impl.sh runs this
# harness against sources named by env var and copied into a temp tree -- so a
# source resolved from $here alone is ABSENT under the gate while being present
# for anyone running the harness by hand. Measured 2026-09-21: 51/51 direct,
# 46/51 under verify.sh, on the same commit (Proofdelve ForgeOs-mfyq).
parents_source="${STALE_PARENTS_SRC:-$here/unattended-fleet/stale-parents.py}"
misrouted_source="${MISROUTED_SRC:-$here/unattended-fleet/misrouted.py}"
# Derived from the selected lint source so verify-impl's extracted harness still
# reads the candidate helper without requiring a verifier-only source pin.
unshaped_source="${UNSHAPED_SOURCE:-$(dirname "$lint_source")/unattended-fleet/unshaped.py}"
[ -f "$unshaped_source" ] || unshaped_source="$here/unattended-fleet/unshaped.py"
# Deliberately derived from QUEUE_LINT_SRC: verify-impl extracts this harness
# and cannot be edited by the Forge to add a new source pin.
stale_criteria_source="$(dirname "$lint_source")/unattended-fleet/stale-criteria.py"
checklist_source="${UNATTENDED_FLEET_CHECKLIST_SRC:-$here/../fort/checklists/unattended-fleet-run.md}"
sources=("$harness_source" "$flag_source" "$lint_source" "$citation_source" "$verify_impl_source" "$prose_source" "$parents_source" "$misrouted_source" "$unshaped_source" "$stale_criteria_source" "$checklist_source")
missing_sources=()
for source in "${sources[@]}"; do
  [ -f "$source" ] || missing_sources+=("$source")
done
if [ "${#missing_sources[@]}" -ne 0 ]; then
  for source in "${missing_sources[@]}"; do
    printf 'HARNESS REFUSES: source missing: %s\n' "$source" >&2
  done
  exit 3
fi

tmp_base="$(mktemp -d)"; tmp_link="${tmp_base}-link"
ln -s "$tmp_base" "$tmp_link"
TMPDIR="$tmp_link"; export TMPDIR
work="$(mktemp -d "$TMPDIR/queue-lint.XXXXXX")"; trap 'rm -rf "$tmp_link" "$tmp_base"' EXIT
repo="$work/repo"; stub="$work/stub"; workers="$work/fleet/workers"
real_python3="$(command -v python3)"
mkdir -p "$repo/scripts/unattended-fleet" "$repo/fort/scripts" "$stub" "$workers"
cp -f "$flag_source" "$repo/scripts/flag-human.sh"
cp -f "$lint_source" "$repo/scripts/queue-lint.sh"
cp -f "$citation_source" "$repo/scripts/bead-citation-check.sh"
cp -f "$prose_source" "$repo/scripts/unattended-fleet/prose-blockers.py"
cp -f "$misrouted_source" "$repo/scripts/unattended-fleet/misrouted.py"
cp -f "$unshaped_source" "$repo/scripts/unattended-fleet/unshaped.py"
cp -f "$stale_criteria_source" "$repo/scripts/unattended-fleet/stale-criteria.py"
chmod 755 "$repo/scripts/flag-human.sh" "$repo/scripts/queue-lint.sh" "$repo/scripts/bead-citation-check.sh" "$repo/scripts/unattended-fleet/prose-blockers.py" "$repo/scripts/unattended-fleet/misrouted.py" "$repo/scripts/unattended-fleet/unshaped.py" "$repo/scripts/unattended-fleet/stale-criteria.py"
mkdir -p "$repo/src/Product.Api" "$repo/docs" "$repo/.claude" "$repo/web/src"
touch "$repo/fort/scripts/fleet.sh" "$repo/scripts/fleet-harness.sh" \
  "$repo/scripts/verify-impl.sh" \
  "$repo/docs/runbook.md" "$repo/fort/charter.md" "$repo/.claude/settings.json"
touch "$repo/web/src/App.tsx"
printf '%s\n' 'class KnownIdentifier {}' > "$repo/src/Product.Api/Program.cs"
git -C "$repo" init -q -b main
git -C "$repo" add scripts fort src docs .claude web
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -q -m base
stale_base="$(git -C "$repo" rev-parse HEAD)"
printf '// touched declared file\n' >> "$repo/src/Product.Api/Program.cs"
git -C "$repo" add src/Product.Api/Program.cs
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -q -m 'touch declared file'
stale_file="$(git -C "$repo" rev-parse HEAD)"
printf '// touched declared directory\n' > "$repo/src/Product.Api/WithinDirectory.cs"
git -C "$repo" add src/Product.Api/WithinDirectory.cs
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -q -m 'touch declared directory'
stale_directory="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b bead/{{BEAD_PREFIX}}-own "$stale_directory"
printf '// touched by own bead merge\n' >> "$repo/src/Product.Api/Program.cs"
git -C "$repo" add src/Product.Api/Program.cs
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -q -m '{{BEAD_PREFIX}}-own: work before landing'
git -C "$repo" checkout -q main
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid merge --no-ff -q bead/{{BEAD_PREFIX}}-own -m '{{BEAD_PREFIX}}-own: merged by the fleet on MERGE-PARENT-OPEN'
own_merge="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q -b bead/off-main "$stale_directory"
printf '// side branch only\n' > "$repo/src/Product.Api/SideBranch.cs"
git -C "$repo" add src/Product.Api/SideBranch.cs
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -q -m 'off-main marker'
off_main="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" checkout -q main
printf 'undeclared\n' >> "$repo/docs/runbook.md"
git -C "$repo" add docs/runbook.md
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -q -m 'touch undeclared path'

cat > "$repo/fort/scripts/emit.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HARNESS_EMITS"
EOF
chmod 755 "$repo/fort/scripts/emit.sh"
cat > "$stub/bd" <<'EOF'
#!/bin/bash
args="$*"
if [ "${HARNESS_BD_FAIL:-}" = show-gate ] && [[ "$args" == *"show {{BEAD_PREFIX}}-gate --json"* ]]; then
  echo "cannot open database" >&2; exit 1
fi
if [ "${HARNESS_BD_FAIL:-}" = comments ] && [[ "$args" == *"comments {{BEAD_PREFIX}}-dialogue --json"* ]]; then
  echo "cannot open database" >&2; exit 1
fi
if [ "${HARNESS_BD_FAIL:-}" = comments-timeout ] && [[ "$args" == *"comments {{BEAD_PREFIX}}-dialogue --json"* ]]; then
  sleep 61
fi
if [ "${HARNESS_BD_FAIL:-}" = show-unknown ] && [[ "$args" == *"show {{BEAD_PREFIX}}-unknown --json"* ]]; then
  echo 'Error fetching {{BEAD_PREFIX}}-unknown: no issue found matching "{{BEAD_PREFIX}}-unknown"' >&2
  printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'
  exit 1
fi
if [ "${HARNESS_BD_FAIL:-}" = show-unknown-plain ] && [[ "$args" == *"show {{BEAD_PREFIX}}-unknown --json"* ]]; then
  echo 'Error fetching {{BEAD_PREFIX}}-unknown: no issue found matching "{{BEAD_PREFIX}}-unknown"' >&2
  exit 1
fi
if [ "${HARNESS_BD_FAIL:-}" = show-near-miss ] && [[ "$args" == *"show {{BEAD_PREFIX}}-unknown --json"* ]]; then
  echo 'Error fetching {{BEAD_PREFIX}}-other: no issue found matching "{{BEAD_PREFIX}}-other"' >&2
  exit 1
fi
case "$args" in
  *" export -o "*)
if [ "${HARNESS_BD_FAIL:-}" = export ]; then
      echo "cannot open database" >&2; exit 1
    fi
    if [ "${HARNESS_BD_FAIL:-}" = export-invalid ]; then
      printf '%s\n' 'this is not JSONL' > "${args##* -o }"
      exit 0
    fi
    printf '%s' "$HARNESS_EXPORT_JSON" > "${args##* -o }"
    ;;
  *" update "*) printf '%s\n' "$args" >> "$HARNESS_BD_LOG" ;;
  # Proofdelve ForgeOs-29j3g: a comment's file content is kept beside the update log.
  *" comment "*" --file "*) cat "${args##* --file }" >> "$HARNESS_BD_LOG.comments" ;;
  # Legacy fixtures predate the landing-class requirement. Classify their
  # fleet-safe rows by default so they continue exercising their own predicate;
  # landing-class fixtures opt out with HARNESS_RAW_LANDING_CLASSES=1.
  # The second queue-lint board query uses --status all so DEPTH can resolve
  # bare list edges to target status and issue type without a bd show.
  *"list "*"--label-any fleet-safe"*)
    if [[ "$args" == *" --status "* ]]; then status_filter='true'; else status_filter='((.status // "open") == "open")'; fi
    printf '%s\n' "$HARNESS_FLEET_JSON" | jq -c "[.[] | select((.labels // []) | index(\"fleet-safe\")) | select($status_filter) | if env.HARNESS_RAW_LANDING_CLASSES == \"1\" or ((.labels // []) | index(\"sign-to-land\") or index(\"lands-on-review\")) then . else .labels += [\"lands-on-review\"] end]"
    ;;
  *"list --status all --limit 0 --json"*)
    printf '%s\n' "$HARNESS_OPEN_JSON" | jq -c '[.[] | if env.HARNESS_RAW_LANDING_CLASSES == "1" or (((.labels // []) | index("fleet-safe")) | not) or ((.labels // []) | index("sign-to-land") or index("lands-on-review")) then . else .labels += ["lands-on-review"] end]'
    ;;
  *"show {{BEAD_PREFIX}}-fleet --json"*) printf '%s\n' "$HARNESS_FLEET_SHOW" ;;
  *"show {{BEAD_PREFIX}}-gate --json"*) printf '%s\n' "$HARNESS_GATE_SHOW" ;;
  *"show {{BEAD_PREFIX}}-aa --json"*) printf '%s\n' "$HARNESS_A_SHOW" ;;
  *"show {{BEAD_PREFIX}}-bb --json"*) printf '%s\n' "$HARNESS_B_SHOW" ;;
  *"comments "*" --json"*) printf '%s\n' "$HARNESS_COMMENTS_JSON" ;;
  *) echo "unexpected bd command: $args" >&2; exit 9 ;;
esac
EOF
chmod 755 "$stub/bd"
real_git="$(command -v git)"
export HARNESS_REAL_GIT="$real_git"
cat > "$stub/git" <<'EOF'
#!/bin/bash
if [[ "$*" == *'rev-parse --verify abcdef0^{commit}'* ]]; then
  echo 'error: short object ID abcdef0 is ambiguous' >&2
  exit 128
fi
exec "$HARNESS_REAL_GIT" "$@"
EOF
chmod 755 "$stub/git"
cat > "$stub/python3" <<'EOF'
#!/bin/bash
if [ "${HARNESS_PYTHON_FAIL:-}" = core ] && [ "${1:-}" = -c ]; then
  exit 3
fi
if [ "${HARNESS_PYTHON_FAIL:-}" = checker ] && [[ "${1:-}" == */unattended-fleet/prose-blockers.py ]]; then
  exit 127
fi
exec "$HARNESS_REAL_PYTHON3" "$@"
EOF
chmod 755 "$stub/python3"

# sitecustomize is loaded by the same Python interpreter that executes the
# production checker. It records the timeout given to actual bd subprocesses,
# allowing the unset-default path to be observed without waiting 60 seconds.
timeout_observer="$work/timeout-observer"
mkdir -p "$timeout_observer"
cat > "$timeout_observer/sitecustomize.py" <<'EOF'
import os
import subprocess

_run = subprocess.run

def run(*args, **kwargs):
    command = args[0] if args else kwargs.get("args", [])
    if (os.environ.get("HARNESS_BD_TIMEOUT_AUDIT") and command
            and command[0] == "bd"):
        with open(os.environ["HARNESS_BD_TIMEOUT_AUDIT"], "a", encoding="utf-8") as audit:
            audit.write(f"{kwargs.get('timeout')}\n")
    return _run(*args, **kwargs)

subprocess.run = run
EOF

pass=0; fail=0
check() { if "$@"; then printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); else printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); fi; }
has() { grep -Fq -- "$2" "$3"; }

run_unshaped() {  # $1 board JSON, $2 output file, optional source override
  local source="${3:-$repo/scripts/unattended-fleet/unshaped.py}"
  (cd "$repo" && printf '%s' "$1" | ROOT="$repo" python3 "$source") >"$2" 2>&1
}

# Keep the cap fixture and its assertion in one helper.  The red-arm child
# calls this same helper, so it proves the real normal-path check rather than
# a hand-copied approximation of it.
check_unshaped_cap() {  # $1 output file
  local output="$1" cap_fixture='[' cap_id n
  for n in $(seq 1 11); do
    cap_id="$(printf '%02d' "$n")"
    cap_fixture+="{\"id\":\"{{BEAD_PREFIX}}-cap-$cap_id\",\"status\":\"open\",\"priority\":1,\"description\":\"Needs decomposition.\",\"labels\":[]},"
  done
  cap_fixture="${cap_fixture%,}]"
  run_unshaped "$cap_fixture" "$output" \
    && has unshaped-cap-count '11 open unrouted bead(s) name no file; 1 suppressed by cap 10' "$output" \
    && ! has unshaped-cap-eleven 'UNSHAPED {{BEAD_PREFIX}}-cap-11' "$output"
}

# This source-array red arm has already bypassed source preflight. Its required
# observation is the old late-open failure, so do that operation directly.
if [ "${QUEUE_LINT_MISSING_VERIFY_RED_ARM:-}" = 1 ]; then
  python3 -c 'import sys; open(sys.argv[1], encoding="utf-8")' "$verify_impl_source"
  exit $?
fi

# This red arm has one purpose: prove that removing the unshaped sitting cap
# exposes its eleventh fixture.  It used to recurse through the complete
# harness just to reach that assertion near the end, duplicating unrelated
# queue-lint cases and dominating verifier time.
if [ "${QUEUE_LINT_UNSHAPED_RED_ARM:-}" = 1 ]; then
  if check_unshaped_cap "$work/unshaped-red-arm.out"; then
    printf '  PASS  unshaped: cap suppresses the eleventh bead\n'
    exit 0
  fi
  printf '  FAIL  unshaped: cap suppresses the eleventh bead\n'
  exit 1
fi

credits_depth_red_arm() {
  local output="$1"
  has depth-red-arm-runs 'PASS  depth red arm child: valid mutant over-reports list-true unknown edge' "$output" \
    && [ "$(grep -Fc 'FAIL  depth: fleet refusal fixture reports zero' "$output")" -eq 2 ] \
    && [ "$(grep -Fc 'FAIL  depth: absent dependency target reports zero' "$output")" -eq 2 ]
}
run_lint() {
  local labels="$1" author="$2" worker_state="$3" output="$4" fail_mode="${5:-}" timeout="${6:-}"
  local -a timeout_env=()
  if [ "$#" -ge 6 ]; then
    timeout_env=("QUEUE_LINT_BD_TIMEOUT=$timeout")
  fi
  rm -rf "$workers/dialogue"
  # Worker fixtures in the shapes the fleet actually writes (eng3.15 round two):
  #   in-flight  : bead + started + run + pid, NO state file (dispatch shape)
  #   exited     : the same plus an exit file, still no state (Forge ended, not yet reaped)
  #   <token>    : bead + state "<token>|R0|fixture" (reap-pass shapes: in-hand, settled, ...)
  if [ -n "$worker_state" ]; then
    mkdir -p "$workers/dialogue"
    printf '{{BEAD_PREFIX}}-dialogue\n' > "$workers/dialogue/bead"
    case "$worker_state" in
      in-flight) printf '2026-09-16T00:00:00-08:00\n' > "$workers/dialogue/started"; printf 'R0\n' > "$workers/dialogue/run"; printf '4242\n' > "$workers/dialogue/pid" ;;
      exited)    printf '2026-09-16T00:00:00-08:00\n' > "$workers/dialogue/started"; printf 'R0\n' > "$workers/dialogue/run"; printf '4242\n' > "$workers/dialogue/pid"; printf '0\n' > "$workers/dialogue/exit" ;;
      *)         printf '%s|R0|fixture\n' "$worker_state" > "$workers/dialogue/state" ;;
    esac
  fi
  env -u QUEUE_LINT_BD_TIMEOUT "${timeout_env[@]}" HARNESS_BD_FAIL="$fail_mode" HARNESS_FLEET_JSON='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]}]' \
  HARNESS_FLEET_SHOW='{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' \
  HARNESS_GATE_SHOW='{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' \
  HARNESS_OPEN_JSON="[{\"id\":\"{{BEAD_PREFIX}}-dialogue\",\"status\":\"open\",\"labels\":$labels}]" \
  HARNESS_COMMENTS_JSON="[{\"author\":\"$author\"}]" HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
  QUEUE_LINT_SKIP_IDENTIFIER_SURFACE=1 FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" "$repo/scripts/queue-lint.sh" >"$output" 2>&1
}

run_queue_case() {
  local fleet_json="$1" open_json="$2" output="$3" raw_landing_classes="${4:-}" skip_identifier_surface="${5:-1}"
  HARNESS_FLEET_JSON="$fleet_json" \
  HARNESS_OPEN_JSON="$open_json" HARNESS_COMMENTS_JSON='[]' HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
  HARNESS_RAW_LANDING_CLASSES="$raw_landing_classes" \
  QUEUE_LINT_SKIP_IDENTIFIER_SURFACE="$skip_identifier_surface" FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" "$repo/scripts/queue-lint.sh" >"$output" 2>&1
}

run_stale_case() { # $1 fleet JSON, $2 comments JSON, $3 output, $4 bd failure mode
  local export_json
  export_json="$(printf '%s' "$1" | jq -c --argjson comments "$2" '.[] | . + {_type:"issue", comments:$comments}')" || return 3
  HARNESS_BD_FAIL="${4:-}" HARNESS_FLEET_JSON="$1" HARNESS_OPEN_JSON="$1" HARNESS_EXPORT_JSON="$export_json" HARNESS_COMMENTS_JSON="$2" \
  HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
  QUEUE_LINT_SKIP_IDENTIFIER_SURFACE=1 FLEET_STATE="$work/fleet" \
  HARNESS_REAL_PYTHON3="$real_python3" HARNESS_REAL_GIT="$real_git" PATH="$stub:$PATH" \
    "$repo/scripts/queue-lint.sh" >"$3" 2>&1
}

# Proofdelve ForgeOs-481se.1: a stale criterion is a report, not a dispatch gate. The
# base anchor precedes one declared file commit, one directory child commit,
# and one unrelated commit. A newer marker in a comment supersedes description;
# updated_at is deliberately irrelevant after a label-only change.
out="$work/stale-criteria.out"
stale_file_board="[{\"id\":\"{{BEAD_PREFIX}}-stale-file\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"updated_at\":\"2099-01-01T00:00:00Z\",\"description\":\"Checked against main $stale_base\\nTouches: src/Product.Api/Program.cs\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]}]"
run_stale_case "$stale_file_board" '[]' "$out"; stale_file_rc=$?
if [ "$stale_file_rc" -eq 0 ] && has stale-file-heading 'STALE CRITERIA' "$out" && has stale-file-sha "${stale_file:0:7} touch declared file" "$out" && ! has stale-file-unrelated 'touch undeclared path' "$out"; then
  printf '  PASS  stale criteria: declared file after anchor is reported, undeclared path is not\n'; pass=$((pass+1))
else printf '  FAIL  stale criteria: declared file after anchor is reported, undeclared path is not\n'; fail=$((fail+1)); fi
stale_dir_board="[{\"id\":\"{{BEAD_PREFIX}}-stale-directory\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"description\":\"Checked against main $stale_file\\nTouches: src/Product.Api/\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]}]"
run_stale_case "$stale_dir_board" '[]' "$out"
if has stale-dir-sha "${stale_directory:0:7} touch declared directory" "$out"; then
  printf '  PASS  stale criteria: directory Touches matches a child file\n'; pass=$((pass+1))
else printf '  FAIL  stale criteria: directory Touches matches a child file\n'; fail=$((fail+1)); fi
stale_comment_board="[{\"id\":\"{{BEAD_PREFIX}}-stale-comment\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"description\":\"Checked against main $stale_base\\nTouches: src/Product.Api/\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]}]"
run_stale_case "$stale_comment_board" "[{\"text\":\"Checked against main $own_merge\"}]" "$out"
if ! has stale-comment-clears '{{BEAD_PREFIX}}-stale-comment --' "$out"; then
  printf '  PASS  stale criteria: newer comment marker clears earlier commits\n'; pass=$((pass+1))
else printf '  FAIL  stale criteria: newer comment marker clears earlier commits\n'; fail=$((fail+1)); fi
stale_label_board="[{\"id\":\"{{BEAD_PREFIX}}-stale-label\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"updated_at\":\"2099-01-01T00:00:00Z\",\"description\":\"Touches: src/Product.Api/Program.cs\",\"labels\":[\"fleet-safe\",\"lands-on-review\",\"label-only-update\"]}]"
run_stale_case "$stale_label_board" '[]' "$out"; stale_label_rc=$?
if [ "$stale_label_rc" -eq 0 ] && has stale-label-keeps "${stale_file:0:7} touch declared file" "$out"; then
  printf '  PASS  stale criteria: label-only updated_at does not clear commits and remains exit-zero\n'; pass=$((pass+1))
else printf '  FAIL  stale criteria: label-only updated_at does not clear commits and remains exit-zero\n'; fail=$((fail+1)); fi
stale_own_board="[{\"id\":\"{{BEAD_PREFIX}}-own\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"description\":\"Checked against main $stale_directory\\nTouches: src/Product.Api/\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]}]"
run_stale_case "$stale_own_board" '[]' "$out"
if ! has stale-own-merge '{{BEAD_PREFIX}}-own --' "$out"; then
  printf '  PASS  stale criteria: own bead merge is not reported\n'; pass=$((pass+1))
else printf '  FAIL  stale criteria: own bead merge is not reported\n'; fail=$((fail+1)); fi
stale_bad_board="[{\"id\":\"{{BEAD_PREFIX}}-typo\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"description\":\"Checked against main $stale_base\\nChecked against main deadbeef1\\nTouches: src/Product.Api/Program.cs\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]},{\"id\":\"{{BEAD_PREFIX}}-ambiguous\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"description\":\"Checked against main $stale_base\\nChecked against main abcdef0\\nTouches: src/Product.Api/Program.cs\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]},{\"id\":\"{{BEAD_PREFIX}}-foreign\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"description\":\"Checked against main $stale_base\\nChecked against main aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\nTouches: src/Product.Api/Program.cs\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]},{\"id\":\"{{BEAD_PREFIX}}-off-main\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"description\":\"Checked against main $stale_base\\nChecked against main $off_main\\nTouches: src/Product.Api/Program.cs\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]}]"
run_stale_case "$stale_bad_board" '[]' "$out"; stale_bad_rc=$?
if [ "$stale_bad_rc" -eq 0 ] && has stale-bad-typo '{{BEAD_PREFIX}}-typo has invalid Checked against main deadbeef1' "$out" && has stale-bad-ambiguous '{{BEAD_PREFIX}}-ambiguous has invalid Checked against main abcdef0' "$out" && has stale-bad-foreign '{{BEAD_PREFIX}}-foreign has invalid Checked against main aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$out" && has stale-bad-off-main "{{BEAD_PREFIX}}-off-main has invalid Checked against main $off_main" "$out"; then
  printf '  PASS  stale criteria: invalid markers warn and remain exit-zero\n'; pass=$((pass+1))
else printf '  FAIL  stale criteria: invalid markers warn and remain exit-zero\n'; fail=$((fail+1)); fi
stale_export_board="[{\"id\":\"{{BEAD_PREFIX}}-stale-export\",\"status\":\"open\",\"created_at\":\"2000-01-01T00:00:00Z\",\"description\":\"Touches: src/Product.Api/Program.cs\",\"labels\":[\"fleet-safe\",\"lands-on-review\"]}]"
run_stale_case "$stale_export_board" '[]' "$out" export; stale_export_rc=$?
if [ "$stale_export_rc" -eq 0 ] && has stale-export-warning 'STALE CRITERIA UNAVAILABLE -- cannot export comment anchors' "$out" && has stale-export-depth 'DEPTH --' "$out"; then
  printf '  PASS  stale criteria: export refusal warns and still reports DEPTH\n'; pass=$((pass+1))
else printf '  FAIL  stale criteria: export refusal warns and still reports DEPTH\n'; fail=$((fail+1)); fi
run_stale_case "$stale_export_board" '[]' "$out" export-invalid; stale_export_invalid_rc=$?
if [ "$stale_export_invalid_rc" -eq 0 ] && has stale-export-invalid-warning 'STALE CRITERIA UNAVAILABLE -- Expecting value' "$out" && has stale-export-invalid-depth 'DEPTH --' "$out"; then
  printf '  PASS  stale criteria: malformed export warns and still reports DEPTH\n'; pass=$((pass+1))
else printf '  FAIL  stale criteria: malformed export warns and still reports DEPTH\n'; fail=$((fail+1)); fi

if [ "${QUEUE_LINT_STALE_ONLY:-}" = 1 ]; then
  printf 'queue-lint-harness: %d pass / %d fail\n' "$pass" "$fail"
  exit "$fail"
fi

run_queue_source_case() {  # $1 source, then run_queue_case arguments
  cp -f "$1" "$repo/scripts/queue-lint.sh"
  chmod 755 "$repo/scripts/queue-lint.sh"
  run_queue_case "$2" "$3" "$4" "${5:-}" "${6:-1}"
  local rc=$?
  # Each source case is isolated. Leaving its source in the fixture makes every
  # later case depend on call order rather than on the source it names.
  cp -f "$lint_source" "$repo/scripts/queue-lint.sh"
  chmod 755 "$repo/scripts/queue-lint.sh"
  return "$rc"
}

run_prose_case() {
  local fleet_json="$1" fleet_show="$2" gate_show="$3" output="$4" fail_mode="${5:-}" a_show="${6:-}" b_show="${7:-}"
  HARNESS_BD_FAIL="$fail_mode" HARNESS_FLEET_JSON="$fleet_json" HARNESS_FLEET_SHOW="$fleet_show" HARNESS_GATE_SHOW="$gate_show" HARNESS_A_SHOW="$a_show" HARNESS_B_SHOW="$b_show" \
  HARNESS_OPEN_JSON='[]' HARNESS_COMMENTS_JSON='[]' HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
  FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" "$repo/scripts/queue-lint.sh" >"$output" 2>&1
}

run_lint_from_root() {
  local output="$1"
  HARNESS_FLEET_JSON='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]}]' \
  HARNESS_FLEET_SHOW='{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' \
  HARNESS_OPEN_JSON='[]' HARNESS_COMMENTS_JSON='[]' HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
  FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" bash -c 'cd / && exec "$1"' _ "$repo/scripts/queue-lint.sh" >"$output" 2>&1
}

run_core_refusal() {
  local output="$1"
  HARNESS_PYTHON_FAIL=core HARNESS_FLEET_JSON='[]' HARNESS_OPEN_JSON='[]' \
  HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" "$repo/scripts/queue-lint.sh" >"$output" 2>&1
}

: > "$work/bd.log"; : > "$work/emits.log"

# The verifier sibling is deliberately derived, so cover it as a source refusal
# directly. It must fail at the up-front source gate, before Python can produce
# a FileNotFoundError from the later pin check.
if [ "${QUEUE_LINT_RED_ARM_CHILD:-}" != 1 ] && [ "${QUEUE_LINT_RED_ARM_INVERSION:-}" != 1 ]; then
derived_source_dir="$work/derived-source"
mkdir -p "$derived_source_dir"
cp -f "$lint_source" "$derived_source_dir/queue-lint.sh"
# Red arms select a copied queue-lint source. Preserve the helper at the
# selected source's derived location so these cases reach their intended
# verifier-source failure rather than failing a different source preflight.
mkdir -p "$derived_source_dir/unattended-fleet"
cp -f "$stale_criteria_source" "$derived_source_dir/unattended-fleet/stale-criteria.py"
missing_verify_out="$work/missing-verify.out"
if QUEUE_LINT_RED_ARM_CHILD=1 UNSHAPED_SOURCE="$unshaped_source" QUEUE_LINT_SRC="$derived_source_dir/queue-lint.sh" "$harness_source" >"$missing_verify_out" 2>&1; then
  printf '  FAIL  missing verify-impl source refuses before harness work\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has missing-verify-refusal "HARNESS REFUSES: source missing: $derived_source_dir/verify-impl.sh" "$missing_verify_out" \
  && ! has missing-verify-no-traceback 'FileNotFoundError' "$missing_verify_out"; then
  printf '  PASS  missing verify-impl source is a named exit-3 refusal\n'; pass=$((pass+1))
else
  printf '  FAIL  missing verify-impl source is a named exit-3 refusal\n'; cat "$missing_verify_out"; fail=$((fail+1))
fi

# RED ARM: omit the derived sibling from the source array. This proves that
# the source-array entry is what turns the later open's FileNotFoundError into
# the named exit-3 up-front refusal.
missing_verify_mutant="$work/queue-lint-harness-without-verify-source.sh"
sed "/^sources=/s/ \\\"\\\$verify_impl_source\\\"//" "$harness_source" > "$missing_verify_mutant"
chmod 755 "$missing_verify_mutant"
missing_verify_mutant_out="$work/missing-verify-mutant.out"
if QUEUE_LINT_RED_ARM_CHILD=1 QUEUE_LINT_MISSING_VERIFY_RED_ARM=1 QUEUE_LINT_HARNESS_SRC="$missing_verify_mutant" QUEUE_LINT_SRC="$derived_source_dir/queue-lint.sh" \
  FLAG_HUMAN_SRC="$flag_source" citation_checker_source="$citation_source" PROSE_BLOCKERS_SRC="$prose_source" \
  STALE_PARENTS_SRC="$parents_source" MISROUTED_SRC="$misrouted_source" \
  UNSHAPED_SOURCE="$unshaped_source" \
  UNATTENDED_FLEET_CHECKLIST_SRC="$checklist_source" "$missing_verify_mutant" >"$missing_verify_mutant_out" 2>&1; then
  printf '  FAIL  missing verify-impl red arm unexpectedly passes\n'; fail=$((fail+1))
elif has missing-verify-traceback 'FileNotFoundError' "$missing_verify_mutant_out" \
  && has missing-verify-traceback-path "$derived_source_dir/verify-impl.sh" "$missing_verify_mutant_out"; then
  printf '  PASS  missing verify-impl red arm reaches FileNotFoundError\n'; pass=$((pass+1))
else
  printf '  FAIL  missing verify-impl red arm reaches FileNotFoundError\n'; cat "$missing_verify_mutant_out"; fail=$((fail+1))
fi

# A multi-path refusal prints one complete path per line, preserving spaces in
# each path rather than joining ambiguous tokens into one line.
missing_flag_source="$work/missing flag-human.sh"
two_missing_out="$work/two-missing-sources.out"
if QUEUE_LINT_RED_ARM_CHILD=1 UNSHAPED_SOURCE="$unshaped_source" FLAG_HUMAN_SRC="$missing_flag_source" QUEUE_LINT_SRC="$derived_source_dir/queue-lint.sh" "$harness_source" >"$two_missing_out" 2>&1; then
  printf '  FAIL  two missing sources refuse\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] \
  && [ "$(grep -Fc 'HARNESS REFUSES: source missing:' "$two_missing_out")" -eq 2 ] \
  && has two-missing-flag "HARNESS REFUSES: source missing: $missing_flag_source" "$two_missing_out" \
  && has two-missing-verify "HARNESS REFUSES: source missing: $derived_source_dir/verify-impl.sh" "$two_missing_out"; then
  printf '  PASS  two missing sources print one path per line\n'; pass=$((pass+1))
else
  printf '  FAIL  two missing sources print one path per line\n'; cat "$two_missing_out"; fail=$((fail+1))
fi
fi

HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" PATH="$stub:$PATH" "$repo/scripts/flag-human.sh" {{BEAD_PREFIX}}-handback 'needs a ruling'
updates="$(wc -l < "$work/bd.log" | tr -d ' ')"
if [ "$updates" = 1 ] && has handback-adds-human '--add-label human' "$work/bd.log" && has handback-removes-mayor-review '--remove-label mayor-review' "$work/bd.log" && has handback-emits-decision 'decision.raised needs a ruling' "$work/emits.log"; then printf '  PASS  hand-back flips both labels in one update and records decision\n'; pass=$((pass+1)); else printf '  FAIL  hand-back flips both labels in one update and records decision\n'; fail=$((fail+1)); fi
# Proofdelve ForgeOs-29j3g: the same single update assigns him, and the ASK line is posted.
if has handback-assigns '--assignee justin' "$work/bd.log" && has handback-ask 'ASK: decide -- needs a ruling' "$work/bd.log.comments"; then printf '  PASS  hand-back assigns the bead to justin in that update and posts its ASK line (29j3g)\n'; pass=$((pass+1)); else printf '  FAIL  hand-back assigns the bead to justin in that update and posts its ASK line (29j3g)\n'; fail=$((fail+1)); fi
: > "$work/bd.log"; : > "$work/bd.log.comments"
HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" PATH="$stub:$PATH" "$repo/scripts/flag-human.sh" {{BEAD_PREFIX}}-handback 'run the nginx -t on the host' 'run host test'
if has handback-verb 'ASK: run host test -- run the nginx -t on the host' "$work/bd.log.comments"; then printf '  PASS  hand-back carries the named ask verb (29j3g)\n'; pass=$((pass+1)); else printf '  FAIL  hand-back carries the named ask verb (29j3g)\n'; fail=$((fail+1)); fi
if HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" PATH="$stub:$PATH" "$repo/scripts/flag-human.sh" {{BEAD_PREFIX}}-handback 'x' 'approve' 2>/dev/null; then printf '  FAIL  hand-back refuses an ask verb outside the five (29j3g)\n'; fail=$((fail+1)); else printf '  PASS  hand-back refuses an ask verb outside the five (29j3g)\n'; pass=$((pass+1)); fi

# Proofdelve ForgeOs-29j3g item 8 and the board check.
out="$work/lint.out"
multi_fleet='[{"id":"{{BEAD_PREFIX}}-multi","status":"open","description":"Touches: scripts/queue-lint.sh\nTouches: scripts/flag-human.sh","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-mid","status":"open","description":"See Touches: scripts/queue-lint.sh for the file.","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-one","status":"open","description":"Touches: scripts/queue-lint.sh, scripts/flag-human.sh","labels":["fleet-safe"]}]'
run_queue_case "$multi_fleet" '[]' "$out" || true
if has multi-heading 'TOUCHES ON MORE THAN ONE LINE' "$out" && has multi-bead '  {{BEAD_PREFIX}}-multi' "$out" && has mid-heading 'TOUCHES MID-LINE' "$out" && has mid-bead '  {{BEAD_PREFIX}}-mid' "$out" && ! has one-clean '  {{BEAD_PREFIX}}-one' "$out"; then printf '  PASS  two Touches: lines and a mid-line Touches: are flagged; one line naming two paths is not (29j3g item 8)\n'; pass=$((pass+1)); else printf '  FAIL  two Touches: lines and a mid-line Touches: are flagged; one line naming two paths is not (29j3g item 8)\n'; cat "$out"; fail=$((fail+1)); fi
board_open='[{"id":"{{BEAD_PREFIX}}-yours","status":"open","assignee":"justin","labels":[]}]'
# Proofdelve ForgeOs-1pcxp: an empty fleet-safe queue is exactly when the Overseer board
# must still be checked. Keep both red and clean empty-queue fixtures explicit.
if HARNESS_FLEET_JSON='[]' HARNESS_OPEN_JSON="$board_open" HARNESS_COMMENTS_JSON='[{"author":"fleet","text":"no reason here"}]' HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
  QUEUE_LINT_SKIP_IDENTIFIER_SURFACE=1 FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" "$repo/scripts/queue-lint.sh" >"$out" 2>&1; then
  printf '  FAIL  empty fleet-safe queue with a missing ASK is red\n'; fail=$((fail+1))
elif has noask-empty-heading 'ON HIS BOARD WITH NO ASK LINE' "$out" \
  && has noask-empty-bead '  {{BEAD_PREFIX}}-yours' "$out" \
  && has noask-empty-message 'queue-lint: no fleet-safe beads' "$out"; then
  printf '  PASS  empty fleet-safe queue still flags a justin bead with no ASK line\n'; pass=$((pass+1))
else
  printf '  FAIL  empty fleet-safe queue still flags a justin bead with no ASK line\n'; cat "$out"; fail=$((fail+1))
fi
if HARNESS_FLEET_JSON='[]' HARNESS_OPEN_JSON="$board_open" HARNESS_COMMENTS_JSON='[{"author":"fleet","text":"held\nASK: sign -- the Warden returned APPROVE"}]' HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
  QUEUE_LINT_SKIP_IDENTIFIER_SURFACE=1 FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" "$repo/scripts/queue-lint.sh" >"$out" 2>&1 \
  && has ask-empty-clean-message 'queue-lint: no fleet-safe beads' "$out" \
  && ! has ask-empty-clean-heading 'ON HIS BOARD WITH NO ASK LINE' "$out"; then
  printf '  PASS  empty fleet-safe queue with a clean Overseer board exits zero\n'; pass=$((pass+1))
else
  printf '  FAIL  empty fleet-safe queue with a clean Overseer board exits zero\n'; cat "$out"; fail=$((fail+1))
fi

# Closed is the only excluded status. Deferred work remains latent work and must
# be audited alongside every other non-closed status.
out="$work/lint.out"
status_fleet='[{"id":"{{BEAD_PREFIX}}-open","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-in-progress","status":"in_progress","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-deferred","status":"deferred","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-closed","status":"closed","description":"No touch set yet.","labels":["fleet-safe"]}]'
if run_queue_case "$status_fleet" '[]' "$out" && has fleet-status-count '3 fleet-safe workload beads (everything except closed, standing, or record)' "$out" && ! has closed-undeclared '{{BEAD_PREFIX}}-closed' "$out"; then
  printf '  PASS  fleet-safe audit excludes only closed status\n'; pass=$((pass+1))
else
  printf '  FAIL  fleet-safe audit excludes only closed status\n'; fail=$((fail+1))
fi
non_work_denominators='[{"id":"{{BEAD_PREFIX}}-work","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","lands-on-review"],"dependency_count":0,"dependencies":[]},{"id":"{{BEAD_PREFIX}}-standing","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","lands-on-review","standing"],"dependency_count":0,"dependencies":[]},{"id":"{{BEAD_PREFIX}}-record","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","lands-on-review","record"],"dependency_count":0,"dependencies":[]}]'
if run_queue_case "$non_work_denominators" "$non_work_denominators" "$out" raw \
  && has non-work-fleet-count '1 fleet-safe workload beads (everything except closed, standing, or record), 1 open workload beads' "$out" \
  && has non-work-depth 'DEPTH -- 1 fleet-safe, unblocked bead(s)' "$out"; then
  printf '  PASS  standing and record are excluded from workload denominators\n'; pass=$((pass+1))
else
  printf '  FAIL  standing and record are excluded from workload denominators\n'; fail=$((fail+1))
fi
deferred_fleet='[{"id":"{{BEAD_PREFIX}}-deferred","status":"deferred","description":"No touch set yet.","labels":["fleet-safe"]}]'
if run_queue_case "$deferred_fleet" '[]' "$out"; then
  printf '  FAIL  deferred fleet-safe bead without Touches is UNDECLARED\n'; fail=$((fail+1))
elif has deferred-undeclared '{{BEAD_PREFIX}}-deferred' "$out"; then
  printf '  PASS  deferred fleet-safe bead without Touches is UNDECLARED\n'; pass=$((pass+1))
else
  printf '  FAIL  deferred fleet-safe bead without Touches is UNDECLARED\n'; fail=$((fail+1))
fi

# Globs reserve their fixed prefix. `scripts/*-harness.sh` therefore overlaps
# the read-only verifier, and a bare `*` conservatively overlaps everything.
glob_touches='[{"id":"{{BEAD_PREFIX}}-glob","status":"open","description":"Touches: scripts/*-harness.sh","labels":["fleet-safe"]}]'
bare_touches='[{"id":"{{BEAD_PREFIX}}-bare","status":"open","description":"Touches: *","labels":["fleet-safe"]}]'
dot_github='[{"id":"{{BEAD_PREFIX}}-dot-github","status":"open","description":"Touches: .github/x","labels":["fleet-safe"]}]'
if ! run_queue_case "$glob_touches" "$glob_touches" "$out" && has glob-touches '{{BEAD_PREFIX}}-glob declares scripts/ (read-only: scripts/verify-impl.sh)' "$out"; then
  printf '  PASS  Touches glob normalises to scripts/ and refuses the Forge\n'; pass=$((pass+1))
else printf '  FAIL  Touches glob normalises to scripts/ and refuses the Forge\n'; fail=$((fail+1)); fi
if ! run_queue_case "$bare_touches" "$bare_touches" "$out" && has bare-touches '{{BEAD_PREFIX}}-bare declares  (read-only: scripts/verify-impl.sh)' "$out"; then
  printf '  PASS  bare Touches glob conservatively refuses the Forge\n'; pass=$((pass+1))
else printf '  FAIL  bare Touches glob conservatively refuses the Forge\n'; fail=$((fail+1)); fi
if ! run_queue_case "$dot_github" "$dot_github" "$out" && has dot-github-leading-dot '{{BEAD_PREFIX}}-dot-github declares .github/x' "$out" && ! has dot-github-stripped 'declares github/x' "$out"; then
  printf '  PASS  .github Touches keeps its leading dot\n'; pass=$((pass+1))
else printf '  FAIL  .github Touches keeps its leading dot\n'; fail=$((fail+1)); fi

# Proofdelve ForgeOs-a51e8: queue-lint must surface the citation check's warn-only
# identifier result on the Mayor's queue surface. The checker itself owns
# token resolution; the fixtures only prove queue-lint wires and scopes it.
# shellcheck disable=SC2016 # Backticks are literal bead fixture content.
identifier_unresolved='[{"id":"{{BEAD_PREFIX}}-identifier","status":"open","description":"Touches: scripts/queue-lint.sh\nUse `InventedIdentifier`.","labels":["fleet-safe"]}]'
# shellcheck disable=SC2016 # Backticks are literal bead fixture content.
identifier_resolved='[{"id":"{{BEAD_PREFIX}}-identifier","status":"open","description":"Touches: scripts/queue-lint.sh\nUse `KnownIdentifier`.","labels":["fleet-safe"]}]'
if run_queue_case "$identifier_unresolved" "$identifier_unresolved" "$out" '' 0 \
  && has identifiers-heading 'UNRESOLVED IDENTIFIERS -- open fleet-safe or gate-ready beads name code identifiers that do not resolve:' "$out" \
  && has identifiers-token '{{BEAD_PREFIX}}-identifier  InventedIdentifier  -- grep it before writing it' "$out"; then
  printf '  PASS  unresolved identifier warning names the fleet-safe bead and token\n'; pass=$((pass+1))
else
  printf '  FAIL  unresolved identifier warning names the fleet-safe bead and token\n'; fail=$((fail+1))
fi
if run_queue_case "$identifier_resolved" "$identifier_resolved" "$out" '' 0 \
  && ! has resolved-identifier-heading 'UNRESOLVED IDENTIFIERS' "$out"; then
  printf '  PASS  resolvable identifier produces no warning heading\n'; pass=$((pass+1))
else
  printf '  FAIL  resolvable identifier produces no warning heading\n'; fail=$((fail+1))
fi
no_identifier_surface="$work/queue-lint-no-identifier-surface.sh"
sed '/^report_unresolved_identifiers(board)$/d' "$lint_source" > "$no_identifier_surface"
if run_queue_source_case "$no_identifier_surface" "$identifier_unresolved" "$identifier_unresolved" "$out" '' 0 \
  && ! has identifiers-red-arm-heading 'UNRESOLVED IDENTIFIERS' "$out"; then
  printf '  PASS  identifier warning red arm: removed surface call prints nothing\n'; pass=$((pass+1))
else
  printf '  FAIL  identifier warning red arm: removed surface call prints nothing\n'; fail=$((fail+1))
fi

# Children inherit labels at creation. A fleet-safe child with no Touches whose
# parent is closed needs a different remedy from an ordinary undeclared bead.
inherited_fleet='[{"id":"{{BEAD_PREFIX}}-closed-parent","status":"closed","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-child","status":"open","description":"No touch set yet.","labels":["fleet-safe"],"dependencies":[{"type":"parent-child","depends_on_id":"{{BEAD_PREFIX}}-closed-parent"}]}]'
if run_queue_case "$inherited_fleet" '[]' "$out"; then
  printf '  FAIL  inherited fleet-safe child is red\n'; fail=$((fail+1))
elif has inherited-output 'LIKELY INHERITED' "$out" && has inherited-parent '{{BEAD_PREFIX}}-child <- {{BEAD_PREFIX}}-closed-parent' "$out"; then
  printf '  PASS  inherited fleet-safe child is red and names parent\n'; pass=$((pass+1))
else
  printf '  FAIL  inherited fleet-safe child is red and names parent\n'; fail=$((fail+1))
fi
open_parent_fleet='[{"id":"{{BEAD_PREFIX}}-open-parent","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-open-child","status":"open","description":"No touch set yet.","labels":["fleet-safe"],"dependencies":[{"type":"parent-child","depends_on_id":"{{BEAD_PREFIX}}-open-parent"}]}]'
if run_queue_case "$open_parent_fleet" '[]' "$out"; then
  printf '  FAIL  open-parent fleet-safe child is UNDECLARED\n'; fail=$((fail+1))
elif has open-parent-undeclared '{{BEAD_PREFIX}}-open-child' "$out" && ! has open-parent-inherited '{{BEAD_PREFIX}}-open-child <- {{BEAD_PREFIX}}-open-parent' "$out"; then
  printf '  PASS  open-parent fleet-safe child is UNDECLARED\n'; pass=$((pass+1))
else
  printf '  FAIL  open-parent fleet-safe child is UNDECLARED\n'; fail=$((fail+1))
fi

# Proofdelve ForgeOs-76uob.1: depth is supply, not another queue finding. These paired
# fixtures prove the three materially different outcomes through the wired
# script: a deep pool, no fleet-safe pool, and a fleet-safe pool held entirely
# behind open blockers. The near case in each pair must print the opposite
# depth, so a reporter that merely prints a constant or counts labels alone
# cannot satisfy the harness.
depth_deep="["
for n in $(seq 1 16); do
  [ "$n" -gt 1 ] && depth_deep+=","
  depth_deep+="{\"id\":\"{{BEAD_PREFIX}}-deep-$n\",\"status\":\"open\",\"description\":\"Touches: scripts/queue-lint.sh\",\"labels\":[\"fleet-safe\"],\"dependency_count\":0}"
done
depth_deep+="]"
depth_one='[{"id":"{{BEAD_PREFIX}}-one","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":0}]'
# Proofdelve ForgeOs-sk3c.3 was fleet-safe but blocked by Proofdelve ForgeOs-aqc6.2.4 on 2026-09-21;
# the fleet then idled for twenty hours. A label-only count would have claimed
# depth 1, even though no fleet-safe bead was dispatchable.
depth_sk3c3_blocked='[{"id":"{{BEAD_PREFIX}}-sk3c.3","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":1,"dependencies":[{"type":"blocks","depends_on_id":"{{BEAD_PREFIX}}-aqc6.2.4"}]}]'
depth_sk3c3_blocked_open='[{"id":"{{BEAD_PREFIX}}-sk3c.3","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":1,"dependencies":[{"type":"blocks","depends_on_id":"{{BEAD_PREFIX}}-aqc6.2.4"}]},{"id":"{{BEAD_PREFIX}}-aqc6.2.4","status":"open","labels":[]}]'
depth_unblocked_open='[{"id":"{{BEAD_PREFIX}}-blocked","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":0}]'

# Proofdelve ForgeOs-xnqio: DEPTH must fail closed exactly where fleet.sh dispatchable()
# does. Each fixture was depth 1 under the former label/open-slice predicate.
depth_deferred_blocker='[{"id":"{{BEAD_PREFIX}}-deferred-blocker","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":1,"dependencies":[{"type":"blocks","depends_on_id":"{{BEAD_PREFIX}}-deferred"}]}]'
depth_deferred_board='[{"id":"{{BEAD_PREFIX}}-deferred-blocker","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":1,"dependencies":[{"type":"blocks","depends_on_id":"{{BEAD_PREFIX}}-deferred"}]},{"id":"{{BEAD_PREFIX}}-deferred","status":"deferred"}]'
# bd list/export count only blocks edges. These lone non-blocks edges therefore
# carry zero even though the edge array is present and must still be inspected.
depth_unknown_edge='[{"id":"{{BEAD_PREFIX}}-unknown-edge","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":0,"dependencies":[{"type":"future-edge","depends_on_id":"{{BEAD_PREFIX}}-open"}]}]'
depth_unknown_board='[{"id":"{{BEAD_PREFIX}}-unknown-edge","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":0,"dependencies":[{"type":"future-edge","depends_on_id":"{{BEAD_PREFIX}}-open"}]},{"id":"{{BEAD_PREFIX}}-open","status":"open"}]'
depth_gate_dependency='[{"id":"{{BEAD_PREFIX}}-gated","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":0,"dependencies":[{"type":"related","depends_on_id":"{{BEAD_PREFIX}}-gate"}]}]'
depth_gate_board='[{"id":"{{BEAD_PREFIX}}-gated","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":0,"dependencies":[{"type":"related","depends_on_id":"{{BEAD_PREFIX}}-gate"}]},{"id":"{{BEAD_PREFIX}}-gate","status":"open","issue_type":"gate"}]'
depth_missing_count='[{"id":"{{BEAD_PREFIX}}-missing-count","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
# An explicitly empty edge array is dispatchable even when its summary count is
# stale. A missing array with that same nonzero count is incomplete data and
# must instead fail closed through the production `dependencies is None` branch.
depth_empty_dependencies='[{"id":"{{BEAD_PREFIX}}-empty-dependencies","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":1,"dependencies":[]}]'
depth_missing_dependencies='[{"id":"{{BEAD_PREFIX}}-missing-dependencies","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":1}]'

if run_queue_case "$depth_deep" "$depth_deep" "$out" && has depth-deep 'DEPTH -- 16 fleet-safe, unblocked bead(s); 2.0 hours at ~8 beads/hour.' "$out"; then
  printf '  PASS  depth: deep pool reports 16 beads and 2.0 hours\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: deep pool reports 16 beads and 2.0 hours\n'; fail=$((fail+1))
fi
for depth_case in "$depth_deferred_board" "$depth_unknown_board" "$depth_gate_board" "$depth_missing_count" "$depth_missing_dependencies"; do
  if run_queue_case "$depth_case" "$depth_case" "$out" && has depth-fail-closed 'DEPTH -- 0 fleet-safe, unblocked beads; queue is empty' "$out"; then
    printf '  PASS  depth: fleet refusal fixture reports zero\n'; pass=$((pass+1))
  else
    printf '  FAIL  depth: fleet refusal fixture reports zero\n'; fail=$((fail+1))
  fi
done
if run_queue_case "$depth_empty_dependencies" "$depth_empty_dependencies" "$out" \
  && has depth-empty-dependencies 'DEPTH -- 1 fleet-safe, unblocked bead(s)' "$out"; then
  printf '  PASS  depth: nonzero count with empty dependency array remains dispatchable\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: nonzero count with empty dependency array remains dispatchable\n'; fail=$((fail+1))
fi
# The list board normally supplies these targets, but a stale or incomplete
# board can omit them. Each must refuse rather than treating absent data as an
# unblocked dependency. Keep these alongside the resolved-target cases above:
# each exercises a distinct real edge form and consumes the single-row fixture.
for depth_case in "$depth_deferred_blocker" "$depth_unknown_edge" "$depth_gate_dependency"; do
  if run_queue_case "$depth_case" "$depth_case" "$out" && has depth-absent-target 'DEPTH -- 0 fleet-safe, unblocked beads; queue is empty' "$out"; then
    printf '  PASS  depth: absent dependency target reports zero\n'; pass=$((pass+1))
  else
    printf '  FAIL  depth: absent dependency target reports zero\n'; fail=$((fail+1))
  fi
done
depth_closed_blocker='[{"id":"{{BEAD_PREFIX}}-closed-blocker","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":1,"dependencies":[{"type":"blocks","depends_on_id":"{{BEAD_PREFIX}}-closed"}]}]'
depth_closed_board='[{"id":"{{BEAD_PREFIX}}-closed-blocker","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"],"dependency_count":1,"dependencies":[{"type":"blocks","depends_on_id":"{{BEAD_PREFIX}}-closed"}]},{"id":"{{BEAD_PREFIX}}-closed","status":"closed"}]'
if run_queue_case "$depth_closed_blocker" "$depth_closed_board" "$out" && has depth-closed-blocker 'DEPTH -- 1 fleet-safe, unblocked bead(s)' "$out"; then
  printf '  PASS  depth: closed blocks target remains dispatchable\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: closed blocks target remains dispatchable\n'; fail=$((fail+1))
fi
if run_queue_case "$depth_one" "$depth_one" "$out" && ! has depth-deep-pair 'DEPTH -- 16 fleet-safe, unblocked bead(s)' "$out"; then
  printf '  PASS  depth: shallow pair is not reported as deep\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: shallow pair is not reported as deep\n'; fail=$((fail+1))
fi
if run_queue_case '[]' '[]' "$out" && has depth-empty 'DEPTH -- 0 fleet-safe, unblocked beads; queue is empty' "$out"; then
  printf '  PASS  depth: empty pool reports zero in words\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: empty pool reports zero in words\n'; fail=$((fail+1))
fi
if run_queue_case "$depth_one" "$depth_one" "$out" && ! has depth-empty-pair 'queue is empty' "$out"; then
  printf '  PASS  depth: stocked pair does not say empty\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: stocked pair does not say empty\n'; fail=$((fail+1))
fi
if run_queue_case "$depth_sk3c3_blocked" "$depth_sk3c3_blocked_open" "$out" && has depth-blocked 'DEPTH -- 0 fleet-safe, unblocked beads; queue is empty' "$out"; then
  printf '  PASS  depth: every fleet-safe bead blocked reports zero\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: every fleet-safe bead blocked reports zero\n'; fail=$((fail+1))
fi
if run_queue_case "$depth_one" "$depth_unblocked_open" "$out" && ! has depth-blocked-pair 'DEPTH -- 0 fleet-safe, unblocked beads' "$out"; then
  printf '  PASS  depth: unblocked pair is not reported as zero\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: unblocked pair is not reported as zero\n'; fail=$((fail+1))
fi

# Reports must not alter the queue gate. Compare actual exit statuses on the
# same zero-depth board against a source with only the DEPTH report removed.
legacy_lint="$work/queue-lint-before-depth.sh"
awk '/# DEPTH IS A REPORT, NOT A FINDING\./ { skip=1 } /^if rc == 0:/ { skip=0 } !skip { print }' "$lint_source" > "$legacy_lint"
chmod 755 "$legacy_lint"
run_queue_source_case "$legacy_lint" "$depth_sk3c3_blocked" "$depth_sk3c3_blocked_open" "$out"; depth_before_rc=$?
# This runs between the before/after pair. It must use the real source, not
# the preceding legacy fixture, so the pair remains correct if cases move.
if run_queue_case "$depth_sk3c3_blocked" "$depth_sk3c3_blocked_open" "$out" \
  && has depth-source-restored 'DEPTH -- 0 fleet-safe, unblocked beads; queue is empty' "$out"; then
  printf '  PASS  depth: source case restores fixture before intervening case\n'; pass=$((pass+1))
else
  printf '  FAIL  depth: source case restores fixture before intervening case\n'; fail=$((fail+1))
fi
run_queue_source_case "$lint_source" "$depth_sk3c3_blocked" "$depth_sk3c3_blocked_open" "$out"; depth_after_rc=$?
if [ "$depth_before_rc" -eq "$depth_after_rc" ]; then
  printf '  PASS  depth: zero-depth exit code unchanged before/after (%d)\n' "$depth_after_rc"; pass=$((pass+1))
else
  printf '  FAIL  depth: zero-depth exit code changed before/after (%d/%d)\n' "$depth_before_rc" "$depth_after_rc"; fail=$((fail+1))
fi

# The red arm is deliberately a harness run against a source mutant, not a
# source-code inspection. The mutant restores the count-zero short circuit that
# bd list/export payloads make unsafe. The four list-true fixtures must fail;
# a crashing mutant is insufficient evidence.
if [ "${QUEUE_LINT_RED_ARM_CHILD:-}" != 1 ]; then
  mutant_lint="$work/queue-lint-count-zero-short-circuit.sh"
  awk '
    /dependencies = issue.get\("dependencies"\)/ {
      print "    if not (issue.get(\"dependency_count\") or 0): return True  # MUTANT: restores unsafe count-zero short circuit"
    }
    { print }
  ' "$lint_source" > "$mutant_lint"
  chmod 755 "$mutant_lint"
  if cmp -s "$lint_source" "$mutant_lint"; then
    printf '  FAIL  depth red arm selector did not change source\n'; fail=$((fail+1))
  else
    # Recursive runs derive this sibling from the mutant's directory. Keep the
    # source pair intact so this depth red arm reaches its intended predicate.
    cp -f "$verify_impl_source" "$work/verify-impl.sh"
    mkdir -p "$work/unattended-fleet"
    cp -f "$stale_criteria_source" "$work/unattended-fleet/stale-criteria.py"
    red_out="$work/depth-red-arm.out"
    if QUEUE_LINT_RED_ARM_CHILD=1 UNSHAPED_SOURCE="$unshaped_source" QUEUE_LINT_SRC="$mutant_lint" "$harness_source" >"$red_out" 2>&1; then
      printf '  FAIL  depth red arm: count-zero short circuit passes the harness\n'; fail=$((fail+1))
    elif credits_depth_red_arm "$red_out"; then
      printf '  PASS  depth red arm: count-zero short circuit fails all four list-true fixtures\n'; pass=$((pass+1))
    else
      printf '  FAIL  depth red arm: count-zero short circuit did not fail all four list-true fixtures\n'; fail=$((fail+1))
    fi
    # A SyntaxError makes the child red, but must not satisfy the four-fixture
    # predicate that credits the real count-zero-short-circuit red arm.
    broken_lint="$work/queue-lint-syntax-error.sh"
    sed 's/return True  # MUTANT: restores unsafe count-zero short circuit/return not valid python  # MUTANT: syntax error/' "$mutant_lint" > "$broken_lint"
    chmod 755 "$broken_lint"
    # The recursive harness derives its verifier sibling from QUEUE_LINT_SRC.
    # Preserve that sibling in the mutant directory so this older depth control
    # continues to exercise its intended SyntaxError observation point.
    cp -f "$verify_impl_source" "$work/verify-impl.sh"
    broken_out="$work/depth-red-arm-broken.out"
    if QUEUE_LINT_RED_ARM_CHILD=1 UNSHAPED_SOURCE="$unshaped_source" QUEUE_LINT_SRC="$broken_lint" "$harness_source" >"$broken_out" 2>&1; then
      printf '  FAIL  depth red arm control: SyntaxError passes the harness\n'; fail=$((fail+1))
    elif credits_depth_red_arm "$broken_out"; then
      printf '  FAIL  depth red arm control: SyntaxError was credited as a wrong answer\n'; fail=$((fail+1))
    elif has depth-red-arm-crash 'FAIL  depth red arm child: mutant must run and over-report list-true unknown edge' "$broken_out"; then
      printf '  PASS  depth red arm control: SyntaxError is not credited as a wrong answer\n'; pass=$((pass+1))
    else
      printf '  FAIL  depth red arm control: SyntaxError was not distinguished from a wrong answer\n'; fail=$((fail+1))
    fi

    # Mutate the actual fail-closed branch for an absent edge array. Require a
    # byte change first, so a reformatted production line cannot silently evade
    # this red arm.
    refuse_lint="$work/queue-lint-refuse-branch-true.sh"
    sed 's/return not (issue.get("dependency_count") or 0)/return True  # MUTANT: accepts nonzero count without dependency array/' "$lint_source" > "$refuse_lint"
    chmod 755 "$refuse_lint"
    if cmp -s "$lint_source" "$refuse_lint"; then
      printf '  FAIL  depth red arm refuse selector did not change source\n'; fail=$((fail+1))
    else
      refuse_out="$work/depth-red-arm-refuse-branch.out"
      if QUEUE_LINT_RED_ARM_CHILD=1 UNSHAPED_SOURCE="$unshaped_source" QUEUE_LINT_SRC="$refuse_lint" "$harness_source" >"$refuse_out" 2>&1; then
        printf '  FAIL  depth red arm: refuse branch returning True passes the harness\n'; fail=$((fail+1))
      elif has depth-red-arm-refuse 'FAIL  depth: fleet refusal fixture reports zero' "$refuse_out"; then
        printf '  PASS  depth red arm: refuse branch returning True fails fleet-refusal fixture\n'; pass=$((pass+1))
      else
        printf '  FAIL  depth red arm: refuse branch mutation did not fail fleet-refusal fixture\n'; fail=$((fail+1))
      fi
    fi
  fi
  if [ "${QUEUE_LINT_RED_ARM_INVERSION:-}" != 1 ]; then
    # Reformat the production predicate so the exact selector misses. The child
    # must fail closed and identify the selector rather than a wrong number.
    # Its inversion guard is a harness terminator: something below depth 1
    # breaks today, but the failure is not isolated and an environment limit is
    # not a safe guard. Levels 2-4 are consistent with the non-idempotent sed
    # unbalancing the source; level 5 collapses differently and remains unexplained.
    reformatted_lint="$work/queue-lint-reformatted-depth.sh"
    sed 's/dependencies = issue.get("dependencies")/dependencies=issue.get("dependencies")/' "$lint_source" > "$reformatted_lint"
    chmod 755 "$reformatted_lint"
    reformatted_out="$work/depth-red-arm-selector.out"
    if QUEUE_LINT_RED_ARM_INVERSION=1 UNSHAPED_SOURCE="$unshaped_source" QUEUE_LINT_SRC="$reformatted_lint" "$harness_source" >"$reformatted_out" 2>&1; then
      printf '  FAIL  depth red arm selector: reformatted predicate passes the harness\n'; fail=$((fail+1))
    elif has depth-red-arm-selector 'FAIL  depth red arm selector did not change source' "$reformatted_out"; then
      printf '  PASS  depth red arm selector: reformatted predicate names selector failure\n'; pass=$((pass+1))
    else
      printf '  FAIL  depth red arm selector: reformatted predicate did not name selector failure\n'; fail=$((fail+1))
    fi
    # Each credit guard must discriminate independently. First remove only the
    # child-run marker while retaining exact fixture counts.
    marker_unguarded_harness="$work/queue-lint-harness-no-run-marker.sh"
    awk '
      /^  has depth-red-arm-runs / {
        print "  true \\"
        next
      }
      { print }
    ' "$harness_source" > "$marker_unguarded_harness"
    chmod 755 "$marker_unguarded_harness"
    marker_unguarded_out="$work/depth-red-arm-no-run-marker.out"
    if QUEUE_LINT_RED_ARM_INVERSION=1 QUEUE_LINT_HARNESS_SRC="$marker_unguarded_harness" FLAG_HUMAN_SRC="$flag_source" QUEUE_LINT_SRC="$broken_lint" citation_checker_source="$citation_source" \
        PROSE_BLOCKERS_SRC="$prose_source" STALE_PARENTS_SRC="$parents_source" MISROUTED_SRC="$misrouted_source" UNSHAPED_SOURCE="$unshaped_source" UNATTENDED_FLEET_CHECKLIST_SRC="$checklist_source" "$marker_unguarded_harness" >"$marker_unguarded_out" 2>&1; then
      printf '  FAIL  depth red arm control: removed run marker passes the harness\n'; fail=$((fail+1))
    elif has depth-red-arm-marker 'PASS  depth red arm control: SyntaxError is not credited as a wrong answer' "$marker_unguarded_out"; then
      printf '  PASS  depth red arm control: exact fixture counts reject SyntaxError without run marker\n'; pass=$((pass+1))
    else
      printf '  FAIL  depth red arm control: exact fixture counts did not reject SyntaxError without run marker\n'; fail=$((fail+1))
    fi

    # Then loosen only the exact counts. The syntax-error child lacks the run
    # marker, so the marker alone must still reject it.
    count_unguarded_harness="$work/queue-lint-harness-loose-counts.sh"
    awk '
      /grep -Fc '\''FAIL  depth: (fleet refusal fixture reports zero|absent dependency target reports zero)'\''/ {
        sub(/-eq 2/, "-ge 2")
      }
      { print }
    ' "$harness_source" > "$count_unguarded_harness"
    chmod 755 "$count_unguarded_harness"
    count_unguarded_out="$work/depth-red-arm-loose-counts.out"
    if QUEUE_LINT_RED_ARM_INVERSION=1 QUEUE_LINT_HARNESS_SRC="$count_unguarded_harness" FLAG_HUMAN_SRC="$flag_source" QUEUE_LINT_SRC="$broken_lint" citation_checker_source="$citation_source" \
        PROSE_BLOCKERS_SRC="$prose_source" STALE_PARENTS_SRC="$parents_source" MISROUTED_SRC="$misrouted_source" UNSHAPED_SOURCE="$unshaped_source" UNATTENDED_FLEET_CHECKLIST_SRC="$checklist_source" "$count_unguarded_harness" >"$count_unguarded_out" 2>&1; then
      printf '  FAIL  depth red arm control: loosened counts pass the harness\n'; fail=$((fail+1))
    elif has depth-red-arm-counts 'PASS  depth red arm control: SyntaxError is not credited as a wrong answer' "$count_unguarded_out"; then
      printf '  PASS  depth red arm control: run marker rejects SyntaxError with loosened counts\n'; pass=$((pass+1))
    else
      printf '  FAIL  depth red arm control: run marker did not reject SyntaxError with loosened counts\n'; fail=$((fail+1))
    fi
  fi
elif run_queue_case "$depth_unknown_board" "$depth_unknown_board" "$out" \
  && has depth-red-arm-number 'DEPTH -- 1 fleet-safe, unblocked bead(s)' "$out"; then
  printf '  PASS  depth red arm child: valid mutant over-reports list-true unknown edge\n'; pass=$((pass+1))
else
  printf '  FAIL  depth red arm child: mutant must run and over-report list-true unknown edge\n'; fail=$((fail+1))
fi

# The depth red-arm children prove exactly the assertion above.  Continuing
# through the unrelated queue, stale, and backlog fixtures made each child a
# second full harness run (and multiplied the verifier's wall time) without
# adding coverage: parent runs execute every one of those fixtures themselves.
# Keep the child's own summary so the parent can still inspect its verdict.
if { [ "${QUEUE_LINT_RED_ARM_CHILD:-}" = 1 ] && [ -z "${QUEUE_LINT_HARNESS_SRC:-}" ]; } \
  || [ "${QUEUE_LINT_RED_ARM_INVERSION:-}" = 1 ]; then
  printf 'queue-lint-harness: %d pass / %d fail\n' "$pass" "$fail"
  exit "$fail"
fi

# Proofdelve ForgeOs-2ll5.1: export freshness. Three outcomes: no export file -> clean with a
# note; an export holding every open id -> clean, "export fresh"; an export missing
# an open id -> EXPORT STALE finding naming it. The fixture repo has no .beads by
# default, so every other case below runs in the first outcome.
out="$work/lint.out"
if run_lint '[]' harness "" "$out" && has export-absent-note 'freshness not checked' "$out"; then
  printf '  PASS  no tracked export -> clean, says so\n'; pass=$((pass+1))
else
  printf '  FAIL  no tracked export -> clean, says so\n'; fail=$((fail+1))
fi
mkdir -p "$repo/.beads"
printf '{"id":"{{BEAD_PREFIX}}-dialogue"}\n' > "$repo/.beads/issues.jsonl"
if run_lint '[]' harness "" "$out" && has export-fresh 'export fresh' "$out"; then
  printf '  PASS  export holds every open id -> clean, export fresh\n'; pass=$((pass+1))
else
  printf '  FAIL  export holds every open id -> clean, export fresh\n'; fail=$((fail+1))
fi
printf '{"id":"{{BEAD_PREFIX}}-other"}\n{"torn\n' > "$repo/.beads/issues.jsonl"
if run_lint '[]' harness "" "$out"; then
  printf '  FAIL  export missing an open id -> EXPORT STALE\n'; fail=$((fail+1))
elif has export-stale 'EXPORT STALE -- 1 open bead' "$out" && has export-stale-names '  {{BEAD_PREFIX}}-dialogue' "$out"; then
  printf '  PASS  export missing an open id -> EXPORT STALE, names it\n'; pass=$((pass+1))
else
  printf '  FAIL  export missing an open id -> EXPORT STALE\n'; fail=$((fail+1))
fi
rm -rf "$repo/.beads"

# standing and record are workload exclusions, never a global mute. These
# probes exercise checks owned by queue-lint itself, rather than misrouted.py.
standing_undeclared='[{"id":"{{BEAD_PREFIX}}-standing-undeclared","status":"open","description":"No touch set yet.","labels":["fleet-safe","lands-on-review","standing"]}]'
if ! run_queue_case "$standing_undeclared" "$standing_undeclared" "$out" raw \
  && has standing-undeclared 'UNDECLARED' "$out" \
  && has standing-undeclared-id '{{BEAD_PREFIX}}-standing-undeclared' "$out"; then
  printf '  PASS  standing bead remains UNDECLARED when Touches is absent\n'; pass=$((pass+1))
else
  printf '  FAIL  standing bead remains UNDECLARED when Touches is absent\n'; fail=$((fail+1))
fi
mkdir -p "$repo/.beads"
printf '{"id":"{{BEAD_PREFIX}}-other"}\n' > "$repo/.beads/issues.jsonl"
standing_export='[{"id":"{{BEAD_PREFIX}}-standing-export","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","lands-on-review","standing"]}]'
if ! run_queue_case "$standing_export" "$standing_export" "$out" raw \
  && has standing-export 'EXPORT STALE -- 1 open bead' "$out" \
  && has standing-export-id '{{BEAD_PREFIX}}-standing-export' "$out"; then
  printf '  PASS  standing bead remains EXPORT STALE when absent from export\n'; pass=$((pass+1))
else
  printf '  FAIL  standing bead remains EXPORT STALE when absent from export\n'; fail=$((fail+1))
fi
rm -rf "$repo/.beads"

if run_lint '["mayor-review"]' {{MAYOR_ID}} settled "$out"; then
  printf '  FAIL  stalled dialogue is red\n'; fail=$((fail+1))
elif has stalled-output '{{BEAD_PREFIX}}-dialogue has mayor-review' "$out"; then
  printf '  PASS  stalled dialogue is red\n'; pass=$((pass+1))
else
  printf '  FAIL  stalled dialogue names bead\n'; fail=$((fail+1))
fi
if run_lint '["mayor-review"]' {{MAYOR_ID}} settled "$out" comments; then
  printf '  FAIL  comments bd outage refuses with exit 3\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has comments-query-refusal 'comments query for {{BEAD_PREFIX}}-dialogue failed' "$out"; then
  printf '  PASS  comments bd outage refuses with exit 3\n'; pass=$((pass+1))
else
  printf '  FAIL  comments bd outage refuses with exit 3\n'; fail=$((fail+1))
fi
if run_lint '["mayor-review"]' {{MAYOR_ID}} settled "$out" comments-timeout 1; then
  printf '  FAIL  valid QUEUE_LINT_BD_TIMEOUT=1 preserves timeout refusal exit 3\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has comments-timeout-refusal 'comments query for {{BEAD_PREFIX}}-dialogue failed' "$out"; then
  printf '  PASS  valid QUEUE_LINT_BD_TIMEOUT=1 preserves timeout refusal exit 3\n'; pass=$((pass+1))
else
  printf '  FAIL  valid QUEUE_LINT_BD_TIMEOUT=1 preserves timeout refusal exit 3\n'; fail=$((fail+1))
fi
for timeout in abc '' 0 -1 inf nan 1e400; do
  if run_lint '["mayor-review"]' {{MAYOR_ID}} settled "$out" comments "$timeout"; then
    printf '  FAIL  invalid QUEUE_LINT_BD_TIMEOUT=%q refuses with exit 3\n' "$timeout"; fail=$((fail+1))
  elif [ "$?" -eq 3 ] && has invalid-timeout "invalid QUEUE_LINT_BD_TIMEOUT value: $timeout" "$out"; then
    printf '  PASS  invalid QUEUE_LINT_BD_TIMEOUT=%q refuses with exit 3\n' "$timeout"; pass=$((pass+1))
  else
    printf '  FAIL  invalid QUEUE_LINT_BD_TIMEOUT=%q refuses with exit 3\n' "$timeout"; fail=$((fail+1))
  fi
done
timeout_audit="$work/bd-timeouts.log"
: > "$timeout_audit"
if HARNESS_BD_TIMEOUT_AUDIT="$timeout_audit" PYTHONPATH="$timeout_observer${PYTHONPATH:+:$PYTHONPATH}" \
  run_lint '["mayor-review"]' {{FORGE_ID}} '' "$out" \
  && [ "$(sort -u "$timeout_audit")" = "60.0" ]; then
  printf '  PASS  unset QUEUE_LINT_BD_TIMEOUT keeps the 60-second default\n'; pass=$((pass+1))
else
  printf '  FAIL  unset QUEUE_LINT_BD_TIMEOUT keeps the 60-second default\n'; fail=$((fail+1))
fi
if run_lint '["mayor-review","human"]' {{MAYOR_ID}} '' "$out"; then
  printf '  FAIL  both labels is red\n'; fail=$((fail+1))
elif has both-label-output '{{BEAD_PREFIX}}-dialogue carries human and mayor-review' "$out"; then
  printf '  PASS  both labels is red\n'; pass=$((pass+1))
else
  printf '  FAIL  both labels names bead\n'; fail=$((fail+1))
fi
# Proofdelve ForgeOs-c1066 / Proofdelve ForgeOs-0q0i: fleet.sh:1264-1267 refuses fleet-safe beads
# carrying human or fleet-escalated. Keep this list beside the audit so a new
# label-based refusal there gets reviewed here instead of quietly inflating depth.
fleet_human='[{"id":"{{BEAD_PREFIX}}-contradiction","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","human"]}]'
fleet_escalated='[{"id":"{{BEAD_PREFIX}}-escalated","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","fleet-escalated"]}]'
fleet_only='[{"id":"{{BEAD_PREFIX}}-fleet-only","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
human_only='[{"id":"{{BEAD_PREFIX}}-human-only","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["human"]}]'
if run_queue_case "$fleet_human" "$fleet_human" "$out"; then
  printf '  FAIL  fleet-safe plus human is red\n'; fail=$((fail+1))
elif has fleet-human-output '{{BEAD_PREFIX}}-contradiction carries fleet-safe and human' "$out"; then
  printf '  PASS  fleet-safe plus human is red\n'; pass=$((pass+1))
else
  printf '  FAIL  fleet-safe plus human names bead\n'; fail=$((fail+1))
fi
if run_queue_case "$fleet_escalated" "$fleet_escalated" "$out"; then
  printf '  FAIL  fleet-safe plus fleet-escalated is red\n'; fail=$((fail+1))
elif has fleet-escalated-output '{{BEAD_PREFIX}}-escalated carries fleet-safe and fleet-escalated' "$out"; then
  printf '  PASS  fleet-safe plus fleet-escalated is red and names the label\n'; pass=$((pass+1))
else
  printf '  FAIL  fleet-safe plus fleet-escalated names the label\n'; fail=$((fail+1))
fi
for fixture in fleet_only human_only; do
  case "$fixture" in
    fleet_only) fleet="$fleet_only"; open="$fleet_only" ;;
    human_only) fleet="$fleet_only"; open="$human_only" ;;
  esac
  if run_queue_case "$fleet" "$open" "$out"; then
    printf '  PASS  %s is clean\n' "$fixture"; pass=$((pass+1))
  else
    printf '  FAIL  %s is clean\n' "$fixture"; fail=$((fail+1))
  fi
done

# Proofdelve ForgeOs-qqjml: fleet.sh refuses fleet-safe work without an explicit landing
# class, but a fleet skip is not a queue diagnosis. The complete board already
# supplied to queue-lint also makes the pre-approval gate-ready shape visible.
unclassified_fleet='[{"id":"{{BEAD_PREFIX}}-unclassified","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
unclassified_in_progress='[{"id":"{{BEAD_PREFIX}}-unclassified-in-progress","status":"in_progress","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
unclassified_closed='[{"id":"{{BEAD_PREFIX}}-unclassified-closed","status":"closed","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
review_classified='[{"id":"{{BEAD_PREFIX}}-unclassified","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","lands-on-review"]}]'
sign_classified='[{"id":"{{BEAD_PREFIX}}-unclassified","status":"in_progress","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","sign-to-land"]}]'
unclassified_plain='[{"id":"{{BEAD_PREFIX}}-plain","status":"open","description":"Touches: scripts/queue-lint.sh","labels":[]}]'
unclassified_gate_ready='[{"id":"{{BEAD_PREFIX}}-gate-ready","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["gate-ready"]}]'
both_landing_classes='[{"id":"{{BEAD_PREFIX}}-both-classes","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","sign-to-land","lands-on-review"]}]'
fleet_safe_gate_ready='[{"id":"{{BEAD_PREFIX}}-fleet-gate-ready","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","gate-ready"]}]'
if run_queue_case "$unclassified_fleet" "$unclassified_fleet" "$out" 1; then
  printf '  FAIL  unclassified fleet-safe bead is red\n'; fail=$((fail+1))
elif grep -Eq '^UNCLASSIFIED FLEET-SAFE -- .*neither sign-to-land nor lands-on-review' "$out" && has unclassified-fleet-name '  {{BEAD_PREFIX}}-unclassified' "$out"; then
  printf '  PASS  unclassified fleet-safe bead is red, named, and diagnosed\n'; pass=$((pass+1))
else
  printf '  FAIL  unclassified fleet-safe bead is red, named, and diagnosed\n'; fail=$((fail+1))
fi
if run_queue_case "$unclassified_in_progress" "$unclassified_in_progress" "$out" 1; then
  printf '  FAIL  unclassified in_progress fleet-safe bead is red\n'; fail=$((fail+1))
elif has unclassified-in-progress-heading 'UNCLASSIFIED FLEET-SAFE' "$out" && has unclassified-in-progress-name '{{BEAD_PREFIX}}-unclassified-in-progress' "$out"; then
  printf '  PASS  unclassified in_progress fleet-safe bead is red and named\n'; pass=$((pass+1))
else
  printf '  FAIL  unclassified in_progress fleet-safe bead is red and named\n'; fail=$((fail+1))
fi
if run_queue_case "$unclassified_closed" "$unclassified_closed" "$out" 1 \
  && ! has unclassified-closed '{{BEAD_PREFIX}}-unclassified-closed' "$out"; then
  printf '  PASS  unclassified closed fleet-safe bead is clean\n'; pass=$((pass+1))
else
  printf '  FAIL  unclassified closed fleet-safe bead is clean\n'; fail=$((fail+1))
fi
for fixture in review_classified sign_classified; do
  case "$fixture" in
    review_classified) board="$review_classified" ;;
    sign_classified) board="$sign_classified" ;;
  esac
  if run_queue_case "$board" "$board" "$out" 1; then
    printf '  PASS  %s fleet-safe bead is clean\n' "$fixture"; pass=$((pass+1))
  else
    printf '  FAIL  %s fleet-safe bead is clean\n' "$fixture"; fail=$((fail+1))
  fi
done
if run_queue_case '[]' "$unclassified_plain" "$out" 1 && ! has unclassified-plain '{{BEAD_PREFIX}}-plain' "$out"; then
  printf '  PASS  unclassified bead without fleet-safe or gate-ready is not reported\n'; pass=$((pass+1))
else
  printf '  FAIL  unclassified bead without fleet-safe or gate-ready is not reported\n'; fail=$((fail+1))
fi
if run_queue_case '[]' "$unclassified_gate_ready" "$out" 1; then
  printf '  FAIL  unclassified gate-ready bead is red\n'; fail=$((fail+1))
elif has unclassified-gate-heading 'UNCLASSIFIED GATE-READY' "$out" && has unclassified-gate-name '  {{BEAD_PREFIX}}-gate-ready' "$out"; then
  printf '  PASS  unclassified gate-ready bead is red and named\n'; pass=$((pass+1))
else
  printf '  FAIL  unclassified gate-ready bead is red and named\n'; fail=$((fail+1))
fi
if run_queue_case "$both_landing_classes" "$both_landing_classes" "$out" 1 \
  && has both-landing-heading 'LANDING CLASS WARNING' "$out" \
  && has both-landing-name '{{BEAD_PREFIX}}-both-classes carries sign-to-land and lands-on-review; fleet resolves it to sign-to-land' "$out"; then
  printf '  PASS  both landing classes warns and exits clean\n'; pass=$((pass+1))
else
  printf '  FAIL  both landing classes warns and exits clean\n'; fail=$((fail+1))
fi
if ! run_queue_case "$fleet_safe_gate_ready" "$fleet_safe_gate_ready" "$out" 1 \
  && has fleet-gate-ready-fleet-heading 'UNCLASSIFIED FLEET-SAFE -- fleet-safe takes precedence over gate-ready because fleet dispatch requires a landing class:' "$out" \
  && ! has fleet-gate-ready-gate-heading 'UNCLASSIFIED GATE-READY' "$out"; then
  printf '  PASS  fleet-safe gate-ready bead appears once under fleet-safe because dispatch requires a class\n'; pass=$((pass+1))
else
  printf '  FAIL  fleet-safe gate-ready bead appears once under fleet-safe because dispatch requires a class\n'; fail=$((fail+1))
fi
if run_queue_case "$review_classified" "$review_classified" "$out" 1 \
  && has landing-clean-summary 'all landing classes declared' "$out"; then
  printf '  PASS  clean summary names landing-class check\n'; pass=$((pass+1))
else
  printf '  FAIL  clean summary names landing-class check\n'; fail=$((fail+1))
fi

# RED ARM: deleting the landing-class report must make the unclassified
# fleet-safe fixture clean. This exercises the wired script, not its spelling.
no_landing_class_lint="$work/queue-lint-no-landing-class.sh"
awk '/^# LANDING CLASS --/{ skip=1 } /^# THE BACKLOG SITTING TRIGGER/{ skip=0 } !skip { print }' "$lint_source" > "$no_landing_class_lint"
chmod 755 "$no_landing_class_lint"
if run_queue_source_case "$no_landing_class_lint" "$unclassified_fleet" "$unclassified_fleet" "$out" 1 \
  && has landing-red-clean 'queue-lint: 1 fleet-safe workload beads' "$out" \
  && ! has landing-red-heading 'UNCLASSIFIED FLEET-SAFE' "$out"; then
  printf '  PASS  landing-class red arm: deleted check makes unclassified fixture clean\n'; cat "$out"; pass=$((pass+1))
else
  printf '  FAIL  landing-class red arm: deleted check did not make fixture clean\n'; cat "$out"; fail=$((fail+1))
fi

# RED ARMS: each status boundary must be observable through an unclassified
# fixture, not just stated in active_landing_statuses.
open_only_landing_lint="$work/queue-lint-open-only-landing.sh"
sed 's/{"open", "in_progress"}/{"open"}/' "$lint_source" > "$open_only_landing_lint"
chmod 755 "$open_only_landing_lint"
if run_queue_source_case "$open_only_landing_lint" "$unclassified_in_progress" "$unclassified_in_progress" "$out" 1 \
  && ! has in-progress-status-red-arm 'UNCLASSIFIED FLEET-SAFE' "$out"; then
  printf '  PASS  landing-class red arm: open-only statuses miss in_progress fixture\n'; cat "$out"; pass=$((pass+1))
else
  printf '  FAIL  landing-class red arm: open-only statuses did not miss in_progress fixture\n'; cat "$out"; fail=$((fail+1))
fi
closed_included_landing_lint="$work/queue-lint-closed-included-landing.sh"
sed 's/{"open", "in_progress"}/{"open", "in_progress", "closed"}/' "$lint_source" > "$closed_included_landing_lint"
chmod 755 "$closed_included_landing_lint"
if ! run_queue_source_case "$closed_included_landing_lint" "$unclassified_closed" "$unclassified_closed" "$out" 1 \
  && has closed-status-red-arm 'UNCLASSIFIED FLEET-SAFE' "$out" \
  && has closed-status-red-arm-name '{{BEAD_PREFIX}}-unclassified-closed' "$out"; then
  printf '  PASS  landing-class red arm: including closed status reports closed fixture\n'; cat "$out"; pass=$((pass+1))
else
  printf '  FAIL  landing-class red arm: including closed status did not report closed fixture\n'; cat "$out"; fail=$((fail+1))
fi

for fixture in 'human:["human"]:{{MAYOR_ID}}:' 'in-flight-worker (no state file):["mayor-review"]:{{MAYOR_ID}}:in-flight' 'in-hand-worker:["mayor-review"]:{{MAYOR_ID}}:in-hand' 'other-author:["mayor-review"]:{{FORGE_ID}}:'; do
  IFS=: read -r name labels author worker <<< "$fixture"
  if run_lint "$labels" "$author" "$worker" "$out"; then printf '  PASS  %s is clean\n' "$name"; pass=$((pass+1)); else printf '  FAIL  %s is clean\n' "$name"; fail=$((fail+1)); fi
done
# A worker that is NOT live must not exempt the bead: settled (the escalated-then-answered
# shape this lint was filed for) and exited-not-yet-reaped both report the stall.
for fixture in 'settled-worker:settled' 'exited-worker (exit file, no state):exited'; do
  IFS=: read -r name worker <<< "$fixture"
  if run_lint '["mayor-review"]' {{MAYOR_ID}} "$worker" "$out"; then printf '  FAIL  %s still reports the stall\n' "$name"; fail=$((fail+1)); elif has x '{{BEAD_PREFIX}}-dialogue has mayor-review' "$out"; then printf '  PASS  %s still reports the stall\n' "$name"; pass=$((pass+1)); else printf '  FAIL  %s names the bead\n' "$name"; fail=$((fail+1)); fi
done

# The prose blocker has required discriminators. They run through the
# wired queue-lint script, with only bd stubbed, so this proves integration.
prose_fleet='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"Blocked on {{BEAD_PREFIX}}-gate.\nTouches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
prose_plain='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"Related to {{BEAD_PREFIX}}-gate.\nTouches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
prose_before='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"This bead must land before {{BEAD_PREFIX}}-gate.\nTouches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
prose_mixed='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"Blocked on {{BEAD_PREFIX}}-aa; must land before {{BEAD_PREFIX}}-bb.\nTouches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
prose_subject_first='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"{{BEAD_PREFIX}}-gate must land before this bead.\nTouches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
prose_before_many='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"This bead must land before {{BEAD_PREFIX}}-aa and {{BEAD_PREFIX}}-bb.\nTouches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
if run_prose_case "$prose_fleet" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out"; then
  printf '  FAIL  prose gate without bd edge is red\n'; fail=$((fail+1))
elif has prose-gate-output '> Blocked on {{BEAD_PREFIX}}-gate.' "$out"; then
  printf '  PASS  prose gate without bd edge is red and quoted\n'; pass=$((pass+1))
else
  printf '  FAIL  prose gate without bd edge quotes the sentence\n'; fail=$((fail+1))
fi
if run_prose_case "$prose_fleet" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[{"id":"{{BEAD_PREFIX}}-gate","dependency_type":"blocks","status":"open"}]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out"; then
  printf '  PASS  prose gate with bd edge is clean\n'; pass=$((pass+1))
else
  printf '  FAIL  prose gate with bd edge is clean\n'; fail=$((fail+1))
fi
if run_prose_case "$prose_plain" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out"; then
  printf '  PASS  passing bead mention is clean\n'; pass=$((pass+1))
else
  printf '  FAIL  passing bead mention is clean\n'; fail=$((fail+1))
fi
if run_prose_case "$prose_before" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open","dependencies":[{"id":"{{BEAD_PREFIX}}-fleet","dependency_type":"blocks","status":"open"}]}' "$out"; then
  printf '  PASS  must land before with reverse bd edge is clean\n'; pass=$((pass+1))
else
  printf '  FAIL  must land before with reverse bd edge is clean\n'; fail=$((fail+1))
fi
if run_prose_case "$prose_before" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open","dependencies":[]}' "$out"; then
  printf '  FAIL  must land before without reverse bd edge is red\n'; fail=$((fail+1))
elif has prose-reverse-output 'MISSING REVERSE EDGE: {{BEAD_PREFIX}}-gate should depend on {{BEAD_PREFIX}}-fleet' "$out"; then
  printf '  PASS  must land before without reverse bd edge names missing reverse edge\n'; pass=$((pass+1))
else
  printf '  FAIL  must land before without reverse bd edge names missing reverse edge\n'; fail=$((fail+1))
fi
if run_prose_case "$prose_mixed" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out" '' '{"id":"{{BEAD_PREFIX}}-aa","status":"open"}' '{"id":"{{BEAD_PREFIX}}-bb","status":"open","dependencies":[{"id":"{{BEAD_PREFIX}}-fleet","dependency_type":"blocks","status":"open"}]}' ; then
  printf '  FAIL  mixed gate and reverse prose reports only the gate\n'; fail=$((fail+1))
elif has prose-mixed-gate 'prose names as a gate: {{BEAD_PREFIX}}-aa' "$out" \
  && ! has prose-mixed-not-both-gates 'prose names as a gate: {{BEAD_PREFIX}}-aa, {{BEAD_PREFIX}}-bb' "$out" \
  && ! has prose-mixed-not-reverse 'MISSING REVERSE EDGE: {{BEAD_PREFIX}}-bb' "$out"; then
  printf '  PASS  mixed gate and reverse prose reports only the gate\n'; pass=$((pass+1))
else
  printf '  FAIL  mixed gate and reverse prose reports only the gate\n'; cat "$out"; fail=$((fail+1))
fi
if run_prose_case "$prose_subject_first" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out"; then
  printf '  FAIL  subject-first must-land-before is reported as a gate\n'; fail=$((fail+1))
elif has prose-subject-first 'prose names as a gate: {{BEAD_PREFIX}}-gate' "$out"; then
  printf '  PASS  subject-first must-land-before is reported as a gate\n'; pass=$((pass+1))
else
  printf '  FAIL  subject-first must-land-before is reported as a gate\n'; cat "$out"; fail=$((fail+1))
fi
if run_prose_case "$prose_before_many" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out" '' '{"id":"{{BEAD_PREFIX}}-aa","status":"open","dependencies":[{"id":"{{BEAD_PREFIX}}-fleet","dependency_type":"blocks","status":"open"}]}' '{"id":"{{BEAD_PREFIX}}-bb","status":"open","dependencies":[]}' ; then
  printf '  FAIL  multi-id must-land-before reports every missing reverse edge\n'; fail=$((fail+1))
elif has prose-before-many 'MISSING REVERSE EDGE: {{BEAD_PREFIX}}-bb should depend on {{BEAD_PREFIX}}-fleet' "$out"; then
  printf '  PASS  multi-id must-land-before reports every missing reverse edge\n'; pass=$((pass+1))
else
  printf '  FAIL  multi-id must-land-before reports every missing reverse edge\n'; cat "$out"; fail=$((fail+1))
fi
prose_first='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"{{BEAD_PREFIX}}-gate must land first.\nTouches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
if run_prose_case "$prose_first" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out"; then
  printf '  FAIL  must land first without bd edge is red\n'; fail=$((fail+1))
elif has prose-first-output 'prose names as a gate: {{BEAD_PREFIX}}-gate' "$out"; then
  printf '  PASS  must land first without bd edge remains a gate\n'; pass=$((pass+1))
else
  printf '  FAIL  must land first without bd edge remains a gate\n'; fail=$((fail+1))
fi
if run_prose_case "$prose_fleet" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"closed"}' "$out"; then
  printf '  PASS  prose gate with closed bead is clean\n'; pass=$((pass+1))
else
  printf '  FAIL  prose gate with closed bead is clean\n'; fail=$((fail+1))
fi
if run_prose_case "$prose_fleet" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out" show-gate; then
  printf '  FAIL  bd outage refuses\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has prose-query-refusal 'prose-blockers: bd query failed for {{BEAD_PREFIX}}-gate' "$out"; then
  printf '  PASS  bd outage refuses with exit 3\n'; pass=$((pass+1))
else
  printf '  FAIL  bd outage refuses with exit 3\n'; fail=$((fail+1))
fi
unknown_fleet='[{"id":"{{BEAD_PREFIX}}-fleet","status":"open","description":"Blocked on {{BEAD_PREFIX}}-unknown.\nTouches: scripts/queue-lint.sh","labels":["fleet-safe"]}]'
if run_prose_case "$unknown_fleet" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{}' "$out" show-unknown; then
  printf '  FAIL  unknown prose gate is red\n'; fail=$((fail+1))
elif [ "$?" -eq 1 ] && has unknown-candidate 'UNKNOWN candidate named as a gate: {{BEAD_PREFIX}}-unknown' "$out"; then
  printf '  PASS  JSON unknown prose gate is an UNKNOWN candidate with exit 1\n'; pass=$((pass+1))
else
  printf '  FAIL  JSON unknown prose gate reports an UNKNOWN candidate with exit 1\n'; fail=$((fail+1))
fi
if run_prose_case "$unknown_fleet" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{}' "$out" show-unknown-plain; then
  printf '  FAIL  plain unknown prose gate is red\n'; fail=$((fail+1))
elif [ "$?" -eq 1 ] && has unknown-candidate 'UNKNOWN candidate named as a gate: {{BEAD_PREFIX}}-unknown' "$out"; then
  printf '  PASS  plain unknown prose gate is an UNKNOWN candidate with exit 1\n'; pass=$((pass+1))
else
  printf '  FAIL  plain unknown prose gate reports an UNKNOWN candidate with exit 1\n'; fail=$((fail+1))
fi
if run_prose_case "$unknown_fleet" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{}' "$out" show-near-miss; then
  printf '  FAIL  near-miss unknown stderr refuses\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has near-miss-refusal 'prose-blockers: bd query failed for {{BEAD_PREFIX}}-unknown' "$out"; then
  printf '  PASS  near-miss unknown stderr refuses with exit 3\n'; pass=$((pass+1))
else
  printf '  FAIL  near-miss unknown stderr refuses with exit 3\n'; fail=$((fail+1))
fi
if HARNESS_PYTHON_FAIL=checker run_prose_case "$prose_plain" '{"id":"{{BEAD_PREFIX}}-fleet","status":"open","dependencies":[]}' '{"id":"{{BEAD_PREFIX}}-gate","status":"open"}' "$out"; then
  printf '  FAIL  prose checker exit 127 refuses\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has prose-checker-127 'queue-lint: prose-blockers failed with exit 127' "$out"; then
  printf '  PASS  prose checker exit 127 refuses with exit 3\n'; pass=$((pass+1))
else
  printf '  FAIL  prose checker exit 127 refuses with exit 3\n'; fail=$((fail+1))
fi
if run_core_refusal "$out"; then
  printf '  FAIL  core queue refusal exits 3\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has core-refusal 'queue-lint: core queue checks refused with exit 3' "$out"; then
  printf '  PASS  core queue refusal names stage and exit 3\n'; pass=$((pass+1))
else
  printf '  FAIL  core queue refusal names stage and exit 3\n'; fail=$((fail+1))
fi
if run_lint_from_root "$out"; then
  printf '  PASS  queue lint works outside the checkout\n'; pass=$((pass+1))
else
  printf '  FAIL  queue lint works outside the checkout\n'; fail=$((fail+1))
fi
chmod 644 "$repo/scripts/unattended-fleet/prose-blockers.py"
if run_lint '[]' {{FORGE_ID}} '' "$out"; then
  printf '  PASS  prose checker does not require execute bit\n'; pass=$((pass+1))
else
  printf '  FAIL  prose checker does not require execute bit\n'; fail=$((fail+1))
fi
# ---------------------------------------------------------------------------
# THE BACKLOG SLICE (Proofdelve ForgeOs-mfyq). These two checks read a whole board on
# stdin and make NO bd calls, so they need no stub: the board IS the input.
# Every case below is a PAIR -- the shape that must be reported and the nearest
# shape that must NOT be -- because a reporter that reports everything
# establishes nothing (Proofdelve ForgeOs-8zb7).
chmod 755 "$repo/scripts/unattended-fleet/prose-blockers.py"
cp -f "$parents_source" "$repo/scripts/unattended-fleet/stale-parents.py"
chmod 755 "$repo/scripts/unattended-fleet/stale-parents.py"

run_expired() {  # $1 board JSON, $2 output file
  printf '%s' "$1" | ROOT="$repo" HARNESS_REAL_PYTHON3="$real_python3" \
    python3 "$repo/scripts/unattended-fleet/prose-blockers.py" --expired >"$2" 2>&1
}
run_parents() {  # $1 board JSON, $2 output file
  printf '%s' "$1" | python3 "$repo/scripts/unattended-fleet/stale-parents.py" >"$2" 2>&1
}
run_misrouted() {  # $1 board JSON, $2 output file
  (cd "$repo" && printf '%s' "$1" | ROOT="$repo" python3 "$repo/scripts/unattended-fleet/misrouted.py") >"$2" 2>&1
}
run_misrouted_from_subdirectory() {  # $1 board JSON, $2 output file
  (cd "$repo/fort" && printf '%s' "$1" | ROOT="$repo" python3 "$repo/scripts/unattended-fleet/misrouted.py") >"$2" 2>&1
}
run_misrouted_with_root() {  # $1 ROOT, $2 board JSON, $3 output file
  (cd "$repo" && printf '%s' "$2" | ROOT="$1" python3 "$repo/scripts/unattended-fleet/misrouted.py") >"$3" 2>&1
}
run_misrouted_from_root_with_source() {  # $1 source, $2 board JSON, $3 output file
  (cd "$repo" && printf '%s' "$2" | ROOT="$repo" python3 "$1") >"$3" 2>&1
}
run_misrouted_from_subdirectory_with_source() {  # $1 source, $2 board JSON, $3 output file
  (cd "$repo/fort" && printf '%s' "$2" | ROOT="$repo" python3 "$1") >"$3" 2>&1
}
run_misrouted_without_git() {  # $1 board JSON, $2 output file
  local no_git="$work/no-git-root"
  mkdir -p "$no_git"
  (cd "$no_git" && printf '%s' "$1" | ROOT="$no_git" python3 "$repo/scripts/unattended-fleet/misrouted.py") >"$2" 2>&1
}
run_backlog() {  # $1 board JSON, $2 output file
  local export_json
  export_json="$(printf '%s' "$1" | jq -c '.[]')" || return 3
  (cd "$repo" && HARNESS_EXPORT_JSON="$export_json" HARNESS_FLEET_JSON='[]' HARNESS_OPEN_JSON='[]' \
    HARNESS_COMMENTS_JSON='[]' HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
    FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" \
      "$repo/scripts/queue-lint.sh" --backlog) >"$2" 2>&1
}
run_backlog_from_subdirectory() {  # $1 board JSON, $2 output file
  local export_json
  export_json="$(printf '%s' "$1" | jq -c '.[]')" || return 3
  (cd "$repo/fort" && HARNESS_EXPORT_JSON="$export_json" HARNESS_FLEET_JSON='[]' HARNESS_OPEN_JSON='[]' \
    HARNESS_COMMENTS_JSON='[]' HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
    FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" \
      "$repo/scripts/queue-lint.sh" --backlog) >"$2" 2>&1
}
run_backlog_export_refusal() {  # $1 output file
  HARNESS_BD_FAIL=export HARNESS_FLEET_JSON='[]' HARNESS_OPEN_JSON='[]' \
  HARNESS_COMMENTS_JSON='[]' HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" \
  FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" \
    "$repo/scripts/queue-lint.sh" --backlog >"$1" 2>&1
}

# A failed live export is an infrastructure refusal, not evidence that the
# board contains a queue finding. Keep exit 3 so an unreadable board still
# blocks a misleading gate, but make the failure class visible to the reader.
if run_backlog_export_refusal "$out"; then
  printf '  FAIL  backlog: unreadable board refuses with exit 3\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has backlog-export-refusal 'INFRASTRUCTURE REFUSAL: bd export refused; cannot read the board' "$out"; then
  printf '  PASS  backlog: unreadable board is named as infrastructure refusal\n'; pass=$((pass+1))
else
  printf '  FAIL  backlog: unreadable board is named as infrastructure refusal\n'; fail=$((fail+1))
fi

# (a) a gate that has CLOSED is the finding; the identical board with that gate
#     still OPEN must stay silent. This is the exact branch the default mode
#     skips, so the pair proves the two modes really are opposites.
exp_closed='[{"id":"{{BEAD_PREFIX}}-a","status":"open","description":"Blocked on {{BEAD_PREFIX}}-gate."},{"id":"{{BEAD_PREFIX}}-gate","status":"closed"}]'
exp_open='[{"id":"{{BEAD_PREFIX}}-a","status":"open","description":"Blocked on {{BEAD_PREFIX}}-gate."},{"id":"{{BEAD_PREFIX}}-gate","status":"open"}]'
run_expired "$exp_closed" "$out"
if has expired-closed-reported 'deferral expired: {{BEAD_PREFIX}}-gate' "$out"; then
  printf '  PASS  expired: a CLOSED prose gate is reported\n'; pass=$((pass+1))
else printf '  FAIL  expired: a CLOSED prose gate is reported\n'; fail=$((fail+1)); fi
run_expired "$exp_open" "$out"
if has expired-open-silent '0 open bead(s)' "$out"; then
  printf '  PASS  expired: an OPEN prose gate is NOT reported\n'; pass=$((pass+1))
else printf '  FAIL  expired: an OPEN prose gate is NOT reported\n'; fail=$((fail+1)); fi

# (b) the aqc6.2.4 case: the gate is named WITHOUT the {{BEAD_PREFIX}}- prefix. Bare
#     resolution is what makes that visible at all.
bare_hit='[{"id":"{{BEAD_PREFIX}}-a","status":"open","acceptance_criteria":"Deal variant once aqc6.2.3 lands."},{"id":"{{BEAD_PREFIX}}-aqc6.2.3","status":"closed"}]'
run_expired "$bare_hit" "$out"
if has expired-bare 'deferral expired: {{BEAD_PREFIX}}-aqc6.2.3' "$out"; then
  printf '  PASS  expired: a bare id resolving to a closed bead is reported\n'; pass=$((pass+1))
else printf '  FAIL  expired: a bare id resolving to a closed bead is reported\n'; fail=$((fail+1)); fi

# (c) THE SAFETY PROPERTY, and the reason bare matching is allowed at all: a
#     dotted token that is NOT a real bead id must never be invented into one.
bare_miss='[{"id":"{{BEAD_PREFIX}}-a","status":"open","acceptance_criteria":"Fixed once App.tsx.1355 lands."},{"id":"{{BEAD_PREFIX}}-other","status":"closed"}]'
run_expired "$bare_miss" "$out"
if has expired-bare-safe '0 open bead(s)' "$out"; then
  printf '  PASS  expired: a bare token matching no bead is NOT invented\n'; pass=$((pass+1))
else printf '  FAIL  expired: a bare token matching no bead is NOT invented\n'; fail=$((fail+1)); fi

# (d) a parent whose children are ALL closed is the finding; ONE open child
#     must silence it.
par_all='[{"id":"{{BEAD_PREFIX}}-p","status":"open","title":"parent"},{"id":"{{BEAD_PREFIX}}-p.1","status":"closed"},{"id":"{{BEAD_PREFIX}}-p.2","status":"closed"}]'
par_one='[{"id":"{{BEAD_PREFIX}}-p","status":"open","title":"parent"},{"id":"{{BEAD_PREFIX}}-p.1","status":"closed"},{"id":"{{BEAD_PREFIX}}-p.2","status":"open"}]'
run_parents "$par_all" "$out"
if has parents-all '{{BEAD_PREFIX}}-p ' "$out"; then
  printf '  PASS  parents: all children closed is reported\n'; pass=$((pass+1))
else printf '  FAIL  parents: all children closed is reported\n'; fail=$((fail+1)); fi
run_parents "$par_one" "$out"
if has parents-one '0 open bead(s)' "$out"; then
  printf '  PASS  parents: one open child silences it\n'; pass=$((pass+1))
else printf '  FAIL  parents: one open child silences it\n'; fail=$((fail+1)); fi

# (e) DEFERRED IS NOT CLOSED. Deferred work is latent work, so a parent whose
#     remaining child is merely deferred still has something outstanding.
par_def='[{"id":"{{BEAD_PREFIX}}-p","status":"open","title":"parent"},{"id":"{{BEAD_PREFIX}}-p.1","status":"deferred"}]'
run_parents "$par_def" "$out"
if has parents-deferred '0 open bead(s)' "$out"; then
  printf '  PASS  parents: a DEFERRED child is not treated as closed\n'; pass=$((pass+1))
else printf '  FAIL  parents: a DEFERRED child is not treated as closed\n'; fail=$((fail+1)); fi

# `standing` and `record` are classes of intentionally open, non-work beads.
# The standing pair is the red arm: removing only its label changes the report.
par_standing='[{"id":"{{BEAD_PREFIX}}-standing","status":"open","title":"standing parent","labels":["standing"]},{"id":"{{BEAD_PREFIX}}-standing.1","status":"closed"}]'
par_record='[{"id":"{{BEAD_PREFIX}}-record","status":"open","title":"record parent","labels":["record"]},{"id":"{{BEAD_PREFIX}}-record.1","status":"closed"}]'
par_unlabelled='[{"id":"{{BEAD_PREFIX}}-standing","status":"open","title":"standing parent","labels":[]},{"id":"{{BEAD_PREFIX}}-standing.1","status":"closed"}]'
run_parents "$par_standing" "$out"
standing_excluded=$(has parents-standing-excluded '0 open bead(s)' "$out" && echo yes || echo no)
run_parents "$par_unlabelled" "$out"
standing_reported=$(has parents-standing-relabelled '{{BEAD_PREFIX}}-standing ' "$out" && echo yes || echo no)
if [ "$standing_excluded" = yes ] && [ "$standing_reported" = yes ]; then
  printf '  PASS  parents: removing standing label changes the reported count\n'; pass=$((pass+1))
else printf '  FAIL  parents: removing standing label changes the reported count\n'; fail=$((fail+1)); fi
run_parents "$par_record" "$out"
if has parents-record-excluded '0 open bead(s)' "$out"; then
  printf '  PASS  parents: record-labelled parent is excluded\n'; pass=$((pass+1))
else printf '  FAIL  parents: record-labelled parent is excluded\n'; fail=$((fail+1)); fi

# (f) neither check may ever turn the queue red: both are triage queues.
run_expired "$exp_closed" "$out"; exp_rc=$?
run_parents "$par_all" "$out"; par_rc=$?
if [ "$exp_rc" -eq 0 ] && [ "$par_rc" -eq 0 ]; then
  printf '  PASS  backlog checks exit 0 even with findings\n'; pass=$((pass+1))
else printf '  FAIL  backlog checks exit 0 even with findings (got %d/%d)\n' "$exp_rc" "$par_rc"; fail=$((fail+1)); fi

# (g) a malformed board REFUSES rather than reporting an empty, reassuring zero.
run_parents 'not json' "$out"; mal_rc=$?
if [ "$mal_rc" -eq 3 ] && has parents-refuse 'stale-parents:' "$out"; then
  printf '  PASS  parents: malformed board refuses with exit 3\n'; pass=$((pass+1))
else printf '  FAIL  parents: malformed board refuses with exit 3\n'; fail=$((fail+1)); fi

# Proofdelve ForgeOs-76uob.2: Gate-6-only work is a routing question. These fixtures use
# the helper directly because the backlog wrapper only supplies the fresh board.
# The checklist is prose, but its Gate 3/5/6 bullet declares this small,
# backtick-quoted set. Parse only that bounded declaration and compare sets, so
# wrapping and order cannot hide drift in either direction.
check_gate_path_pin() {  # $1 misrouted source, $2 checklist source
  python3 - "$1" "$2" <<'PY'
import ast
import re
import sys

code_source, checklist_source = sys.argv[1:]
tree = ast.parse(open(code_source, encoding="utf-8").read())
for node in tree.body:
    if isinstance(node, ast.Assign) and any(
        isinstance(target, ast.Name) and target.id == "GATE_PATHS"
        for target in node.targets
    ):
        code_paths = set(ast.literal_eval(node.value))
        break
else:
    raise SystemExit("misrouted pin: GATE_PATHS missing from code")

lines = open(checklist_source, encoding="utf-8").read().splitlines()
for index, line in enumerate(lines):
    if line.startswith("- **Gate 3, 5, 6**"):
        bullet = [line]
        for continuation in lines[index + 1:]:
            if continuation.startswith("- "):
                break
            bullet.append(continuation)
        checklist_paths = set(re.findall(r"`([^`]+)`", "\n".join(bullet)))
        break
else:
    raise SystemExit("misrouted pin: Gate 3, 5, 6 checklist bullet missing")

code_only = sorted(code_paths - checklist_paths)
checklist_only = sorted(checklist_paths - code_paths)
if code_only or checklist_only:
    if code_only:
        print("misrouted pin: code-only: " + ", ".join(code_only))
    if checklist_only:
        print("misrouted pin: checklist-only: " + ", ".join(checklist_only))
    raise SystemExit(1)
PY
}

# verify-impl extracts this harness to a temporary directory. Every dependency
# whose default is relative to $here must therefore be explicitly passed on the
# queue-lint-harness run_step. Keep the declaration and the wire checked
# together: adding a new *_SRC default cannot merge with an unwired verifier.
check_verifier_source_pins() {  # $1 harness source, $2 verify-impl source
  python3 - "$1" "$2" <<'PY'
import re
import sys

harness, verifier = (open(path, encoding="utf-8").read() for path in sys.argv[1:])
declared = re.findall(r'^[a-z_]+="\$\{([A-Z][A-Z0-9_]*_SRC)', harness, re.MULTILINE)
# QUEUE_LINT_HARNESS_SRC selects the executable itself; harness_path supplies
# that path. The remaining declarations are files this executable reads.
required = [name for name in declared if name != "QUEUE_LINT_HARNESS_SRC"]
step = next((line for line in verifier.splitlines()
             if line.startswith("run_step queue-lint-harness ")), None)
if step is None:
    raise SystemExit("verifier source pins: queue-lint-harness run_step missing")
missing = [name for name in required if not re.search(rf'(?<![A-Z0-9_]){re.escape(name)}=', step)]
if missing:
    raise SystemExit("verifier source pins: missing: " + ", ".join(missing))
PY
}
check_verifier_does_not_set_stale_only() {  # $1 verify-impl source
  python3 - "$1" <<'PY'
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    if "QUEUE_LINT_STALE_ONLY=" in line:
        raise SystemExit("verifier stale-only pin: queue-lint-harness sets QUEUE_LINT_STALE_ONLY")
PY
}
if [ "${QUEUE_LINT_RED_ARM_INVERSION:-}" != 1 ]; then
  pin_out="$work/verifier-source-pins.out"
  if check_verifier_source_pins "$harness_source" "$verify_impl_source" >"$pin_out" 2>&1; then
    printf '  PASS  verifier: every queue harness source default is pinned\n'; pass=$((pass+1))
  else
    printf '  FAIL  verifier: every queue harness source default is pinned\n'; cat "$pin_out"; fail=$((fail+1))
  fi
  fake_verify_impl="$work/verify-impl-missing-misrouted.sh"
  sed 's/MISROUTED_SRC="[^"]*" //' "$verify_impl_source" > "$fake_verify_impl"
  if ! check_verifier_source_pins "$harness_source" "$fake_verify_impl" >"$pin_out" 2>&1 \
    && has verifier-source-pin-red-arm 'verifier source pins: missing: MISROUTED_SRC' "$pin_out"; then
    printf '  PASS  verifier: missing MISROUTED_SRC red arm names it\n'; pass=$((pass+1))
  else
    printf '  FAIL  verifier: missing MISROUTED_SRC red arm names it\n'; cat "$pin_out"; fail=$((fail+1))
  fi
  if check_verifier_does_not_set_stale_only "$verify_impl_source"; then
    printf '  PASS  verifier: queue-lint harness does not set QUEUE_LINT_STALE_ONLY\n'; pass=$((pass+1))
  else
    printf '  FAIL  verifier: queue-lint harness does not set QUEUE_LINT_STALE_ONLY\n'; fail=$((fail+1))
  fi
  stale_only_verify="$work/verify-impl-stale-only.sh"
  cp -f "$verify_impl_source" "$stale_only_verify"
  printf '\nexport QUEUE_LINT_STALE_ONLY=1\n' >> "$stale_only_verify"
  if ! check_verifier_does_not_set_stale_only "$stale_only_verify" >"$pin_out" 2>&1 \
    && has verifier-stale-only-red-arm 'verifier stale-only pin: queue-lint-harness sets QUEUE_LINT_STALE_ONLY' "$pin_out"; then
    printf '  PASS  verifier: stale-only red arm is refused\n'; pass=$((pass+1))
  else
    printf '  FAIL  verifier: stale-only red arm is refused\n'; cat "$pin_out"; fail=$((fail+1))
  fi
fi

pin_out="$work/misrouted-pin.out"
if check_gate_path_pin "$misrouted_source" "$checklist_source" >"$pin_out" 2>&1; then
  printf '  PASS  misrouted: gate-6 paths are pinned to the checklist list\n'; pass=$((pass+1))
else
  printf '  FAIL  misrouted: gate-6 paths are pinned to the checklist list\n'; cat "$pin_out"; fail=$((fail+1))
fi

# Opposite-direction red arms prove that the pin names the drifting member,
# rather than merely failing on malformed extraction.
fake_gate_source="$work/misrouted-extra-gate.py"
cp -f "$misrouted_source" "$fake_gate_source"
sed -i 's|    "scripts/verify-impl.sh",|    "scripts/verify-impl.sh",\n    "fort/fake-seventh/",|' "$fake_gate_source"
if ! check_gate_path_pin "$fake_gate_source" "$checklist_source" >"$pin_out" 2>&1 \
  && has misrouted-pin-code-only 'misrouted pin: code-only: fort/fake-seventh/' "$pin_out"; then
  printf '  PASS  misrouted: code-only gate path red arm names drift\n'; pass=$((pass+1))
else
  printf '  FAIL  misrouted: code-only gate path red arm names drift\n'; cat "$pin_out"; fail=$((fail+1))
fi
fake_checklist="$work/unattended-fleet-run-extra.md"
cp -f "$checklist_source" "$fake_checklist"
# shellcheck disable=SC2016 # Backticks are literal Markdown fixture content.
sed -i '/`scripts\/verify-impl.sh`)/s|`scripts/verify-impl.sh`)|`scripts/verify-impl.sh`, `fort/fake-seventh/`)|' "$fake_checklist"
if ! check_gate_path_pin "$misrouted_source" "$fake_checklist" >"$pin_out" 2>&1 \
  && has misrouted-pin-checklist-only 'misrouted pin: checklist-only: fort/fake-seventh/' "$pin_out"; then
  printf '  PASS  misrouted: checklist-only gate path red arm names drift\n'; pass=$((pass+1))
else
  printf '  FAIL  misrouted: checklist-only gate path red arm names drift\n'; cat "$pin_out"; fail=$((fail+1))
fi
mis_gate='[{"id":"{{BEAD_PREFIX}}-gate","status":"open","description":"Touches: fort/scripts/fleet.sh","labels":[]}]'
mis_routed='[{"id":"{{BEAD_PREFIX}}-gate","status":"open","description":"Touches: fort/scripts/fleet.sh","labels":["mayor-lane"]}]'
mis_human='[{"id":"{{BEAD_PREFIX}}-human","status":"open","description":"Touches: fort/scripts/fleet.sh","labels":["human"]}]'
mis_standing='[{"id":"{{BEAD_PREFIX}}-standing","status":"open","description":"Touches: fort/scripts/fleet.sh","labels":["standing"]}]'
mis_record='[{"id":"{{BEAD_PREFIX}}-record","status":"open","description":"Touches: fort/scripts/fleet.sh","labels":["record"]}]'
mis_split='[{"id":"{{BEAD_PREFIX}}-split","status":"open","description":"Touches: fort/scripts/fleet.sh, src/Product.Api/Program.cs","labels":[]}]'
mis_split_script='[{"id":"{{BEAD_PREFIX}}-split-script","status":"open","description":"Touches: fort/scripts/fleet.sh, scripts/fleet-harness.sh","labels":[]}]'
mis_split_docs='[{"id":"{{BEAD_PREFIX}}-split-docs","status":"open","description":"Touches: fort/scripts/fleet.sh, docs/runbook.md","labels":[]}]'
mis_product='[{"id":"{{BEAD_PREFIX}}-product","status":"open","description":"Touches: src/Product.Api/Program.cs","labels":[]}]'
# shellcheck disable=SC2016 # Backticks are fixture content, not command substitution.
mis_narrative='[{"id":"{{BEAD_PREFIX}}-narrative","status":"open","description":"Incident quoted `fort/scripts/fleet.sh`.\nTouches: src/Product.Api/Program.cs","labels":[]}]'
# shellcheck disable=SC2016 # Backticks are fixture content, not command substitution.
mis_touches_wins='[{"id":"{{BEAD_PREFIX}}-touches-wins","status":"open","description":"Incident quoted `src/Product.Api/Program.cs`.\nTouches: fort/scripts/fleet.sh","labels":[]}]'
mis_unshaped='[{"id":"{{BEAD_PREFIX}}-unshaped","status":"open","description":"Repair fort/scripts/fleet.sh before/after review.verdict Proofdelve ForgeOs-dx34.1.","labels":[]}]'
mis_false_tokens='[{"id":"{{BEAD_PREFIX}}-false-tokens","status":"open","description":"Touches: fort/scripts/fleet.sh e.g. before/after Proofdelve ForgeOs-dx34.1 review.verdict fleet.sh","labels":[]}]'
run_misrouted "$mis_gate" "$out"
if has misrouted-gate 'MISROUTED {{BEAD_PREFIX}}-gate -- gate-6 only: fort/scripts/' "$out"; then
  printf '  PASS  misrouted: unrouted gate-6-only Touches is reported\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: unrouted gate-6-only Touches is reported\n'; fail=$((fail+1)); fi
run_misrouted_from_subdirectory "$mis_gate" "$out"
if has misrouted-subdirectory 'MISROUTED {{BEAD_PREFIX}}-gate -- gate-6 only: fort/scripts/' "$out"; then
  printf '  PASS  misrouted: subdirectory invocation reports the same gate-6 bead\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: subdirectory invocation reports the same gate-6 bead\n'; fail=$((fail+1)); fi
if run_misrouted_with_root "$repo/fort" "$mis_gate" "$out"; then
  printf '  FAIL  misrouted: subdirectory ROOT refuses with exit 3\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has misrouted-subdirectory-root "ROOT is not the git repository root: $repo/fort" "$out"; then
  printf '  PASS  misrouted: subdirectory ROOT refuses with exit 3 and names ROOT\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: subdirectory ROOT refuses with exit 3 and names ROOT\n'; fail=$((fail+1)); fi
if run_misrouted_without_git "$mis_gate" "$out"; then
  printf '  FAIL  misrouted: no-git ROOT refuses with exit 3\n'; fail=$((fail+1))
elif [ "$?" -eq 3 ] && has misrouted-no-git-root "ROOT $work/no-git-root" "$out"; then
  printf '  PASS  misrouted: no-git ROOT refuses with exit 3 and names ROOT\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: no-git ROOT refuses with exit 3 and names ROOT\n'; fail=$((fail+1)); fi

# RED ARM: restoring bare git ls-files reaches the original cwd defect. The
# explicit-root source reports in either directory; the weakened source only
# sees the fixture's partial fort/ tree from the subdirectory.
bare_misrouted="$work/misrouted-bare-git.py"
sed 's/\["git", "-C", root, "ls-files"\]/["git", "ls-files"]/' "$misrouted_source" > "$bare_misrouted"
if run_misrouted_from_root_with_source "$bare_misrouted" "$mis_gate" "$out" \
  && has misrouted-bare-root 'MISROUTED {{BEAD_PREFIX}}-gate -- gate-6 only: fort/scripts/' "$out"; then
  printf '  PASS  misrouted: bare-git red arm still passes from fixture root\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: bare-git red arm still passes from fixture root\n'; fail=$((fail+1)); fi
if run_misrouted_from_subdirectory_with_source "$bare_misrouted" "$mis_gate" "$out" \
  && has misrouted-bare-subdirectory '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: bare-git red arm fails from fixture subdirectory\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: bare-git red arm fails from fixture subdirectory\n'; fail=$((fail+1)); fi
run_misrouted "$mis_routed" "$out"
if has misrouted-routed '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: mayor-lane gate-6 work is not reported\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: mayor-lane gate-6 work is not reported\n'; fail=$((fail+1)); fi
run_misrouted "$mis_human" "$out"
if has misrouted-human-routed '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: human-only gate-6 work is not reported\n'; pass=$((pass+1))
else
  printf '  FAIL  misrouted: human-only gate-6 work is not reported\n'; fail=$((fail+1))
fi
for fixture in mis_standing mis_record; do
  case "$fixture" in
    mis_standing) board="$mis_standing"; label="standing" ;;
    mis_record) board="$mis_record"; label="record" ;;
  esac
  run_misrouted "$board" "$out"
  if has "misrouted-$label-reported" "MISROUTED {{BEAD_PREFIX}}-$label -- gate-6 only: fort/scripts/" "$out"; then
    printf '  PASS  misrouted: %s bead remains reported\n' "$label"; pass=$((pass+1))
  else
    printf '  FAIL  misrouted: %s bead remains reported\n' "$label"; fail=$((fail+1))
  fi
done
run_misrouted "$mis_split" "$out"
if has misrouted-split '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: mixed gate-6 and product Touches is not reported\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: mixed gate-6 and product Touches is not reported\n'; fail=$((fail+1)); fi
run_misrouted "$mis_split_script" "$out"
if has misrouted-split-script '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: mixed gate-6 and writable script Touches is not reported\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: mixed gate-6 and writable script Touches is not reported\n'; fail=$((fail+1)); fi
run_misrouted "$mis_split_docs" "$out"
if has misrouted-split-docs '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: mixed gate-6 and docs Touches is not reported\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: mixed gate-6 and docs Touches is not reported\n'; fail=$((fail+1)); fi
run_misrouted "$mis_product" "$out"
if has misrouted-product '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: product-only Touches is not reported\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: product-only Touches is not reported\n'; fail=$((fail+1)); fi
run_misrouted "$mis_narrative" "$out"
if has misrouted-narrative '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: product Touches overrides quoted gate-6 narrative\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: product Touches overrides quoted gate-6 narrative\n'; fail=$((fail+1)); fi
run_misrouted "$mis_touches_wins" "$out"
if has misrouted-touches-wins 'MISROUTED {{BEAD_PREFIX}}-touches-wins -- gate-6 only: fort/scripts/' "$out"; then
  printf '  PASS  misrouted: gate-6 Touches overrides quoted product narrative\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: gate-6 Touches overrides quoted product narrative\n'; fail=$((fail+1)); fi
run_misrouted "$mis_unshaped" "$out"
if has misrouted-unshaped '0 open unrouted gate-6-only bead(s)' "$out"; then
  printf '  PASS  misrouted: unshaped prose is not classified\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: unshaped prose is not classified\n'; fail=$((fail+1)); fi
run_misrouted "$mis_false_tokens" "$out"
if has misrouted-false-tokens 'MISROUTED {{BEAD_PREFIX}}-false-tokens -- gate-6 only: fort/scripts/' "$out"; then
  printf '  PASS  misrouted: untracked Touches tokens do not hide gate work\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: untracked Touches tokens do not hide gate work\n'; fail=$((fail+1)); fi
if run_backlog "$mis_gate" "$out" && has misrouted-backlog-heading '=== MISROUTED GATE-6 WORK' "$out" \
  && has misrouted-backlog-report 'MISROUTED {{BEAD_PREFIX}}-gate -- gate-6 only: fort/scripts/' "$out"; then
  printf '  PASS  misrouted: runs only in the exit-zero backlog slice\n'; pass=$((pass+1))
else printf '  FAIL  misrouted: runs only in the exit-zero backlog slice\n'; fail=$((fail+1)); fi

# Proofdelve ForgeOs-76uob.3: this is the Mayor's stockable slice, not a route choice.
# Prose counts only exact files or slash-bearing directory prefixes: bare
# repository directory words are ordinary English, not scope declarations.
unshaped_plain='[{"id":"{{BEAD_PREFIX}}-plain","status":"open","priority":1,"description":"Needs decomposition.","labels":[]}]'
unshaped_path='[{"id":"{{BEAD_PREFIX}}-path","status":"open","priority":0,"description":"Touches web/src/App.tsx","labels":[]}]'
unshaped_routed='[{"id":"{{BEAD_PREFIX}}-routed","status":"open","priority":0,"description":"Needs decomposition.","labels":["mayor-lane"]}]'
unshaped_epic='[{"id":"{{BEAD_PREFIX}}-epic","status":"open","issue_type":"epic","priority":0,"description":"Needs decomposition.","labels":[]}]'
unshaped_version='[{"id":"{{BEAD_PREFIX}}-version","status":"open","priority":1,"description":"Regression since 1.2.3.","labels":[]}]'
unshaped_initials='[{"id":"{{BEAD_PREFIX}}-initials","status":"open","priority":1,"description":"N.B. confirm scope.","labels":[]}]'
run_unshaped "$unshaped_plain" "$out"
if has unshaped-plain 'UNSHAPED {{BEAD_PREFIX}}-plain -- P1, no criteria' "$out"; then
  printf '  PASS  unshaped: unrouted bead naming no file is reported\n'; pass=$((pass+1))
else printf '  FAIL  unshaped: unrouted bead naming no file is reported\n'; fail=$((fail+1)); fi
run_unshaped "$unshaped_path" "$out"
if has unshaped-path '0 open unrouted bead(s) name no file' "$out"; then
  printf '  PASS  unshaped: tracked web path is not reported\n'; pass=$((pass+1))
else printf '  FAIL  unshaped: tracked web path is not reported\n'; fail=$((fail+1)); fi
run_unshaped "$unshaped_routed" "$out"
if has unshaped-routed '0 open unrouted bead(s) name no file' "$out"; then
  printf '  PASS  unshaped: routed bead naming no file is not reported\n'; pass=$((pass+1))
else printf '  FAIL  unshaped: routed bead naming no file is not reported\n'; fail=$((fail+1)); fi
run_unshaped "$unshaped_epic" "$out"
if has unshaped-epic '0 open unrouted bead(s) name no file; 0 suppressed by cap 10; 1 epics excluded' "$out"; then
  printf '  PASS  unshaped: epic is excluded and counted\n'; pass=$((pass+1))
else printf '  FAIL  unshaped: epic is excluded and counted\n'; fail=$((fail+1)); fi
for case in \
  'web:web session' 'docs:docs match' 'tests:tests' 'scripts:scripts' \
  'tools:tools' 'fort:fort is ready' 'src:src'; do
  IFS=: read -r spelling prose <<< "$case"
  board="[{\"id\":\"{{BEAD_PREFIX}}-bare-$spelling\",\"status\":\"open\",\"priority\":1,\"description\":\"$prose\",\"labels\":[]}]"
  run_unshaped "$board" "$out"
  if has "unshaped-bare-$spelling" "UNSHAPED {{BEAD_PREFIX}}-bare-$spelling" "$out"; then
    printf '  PASS  unshaped: bare %s prose word is not a path\n' "$spelling"; pass=$((pass+1))
  else printf '  FAIL  unshaped: bare %s prose word is not a path\n' "$spelling"; fail=$((fail+1)); fi
done
for dotted in version initials; do
  case "$dotted" in
    version) board="$unshaped_version" ;;
    initials) board="$unshaped_initials" ;;
  esac
  run_unshaped "$board" "$out"
  if has "unshaped-$dotted" "UNSHAPED {{BEAD_PREFIX}}-$dotted" "$out"; then
    printf '  PASS  unshaped: dotted %s is not a file\n' "$dotted"; pass=$((pass+1))
  else printf '  FAIL  unshaped: dotted %s is not a file\n' "$dotted"; fail=$((fail+1)); fi
done

if check_unshaped_cap "$out"; then
  printf '  PASS  unshaped: cap suppresses the eleventh bead\n'; pass=$((pass+1))
else printf '  FAIL  unshaped: cap suppresses the eleventh bead\n'; fail=$((fail+1)); fi
if [ "${QUEUE_LINT_UNSHAPED_RED_ARM:-}" != 1 ] && [ "${QUEUE_LINT_RED_ARM_INVERSION:-}" != 1 ]; then
  mutant="$work/unshaped-without-cap.py"
  sed 's/findings\[:SITTING_CAP\]/findings/' "$unshaped_source" > "$mutant"
  if QUEUE_LINT_UNSHAPED_RED_ARM=1 UNSHAPED_SOURCE="$mutant" "$harness_source" >"$work/unshaped-red-arm.out" 2>&1; then
    printf '  FAIL  unshaped red arm: uncapped slice passes the harness\n'; fail=$((fail+1))
  elif has unshaped-red-arm 'FAIL  unshaped: cap suppresses the eleventh bead' "$work/unshaped-red-arm.out"; then
    printf '  PASS  unshaped red arm: uncapped slice fails the harness\n'; pass=$((pass+1))
  else
    printf '  FAIL  unshaped red arm: uncapped slice did not fail its cap fixture\n'; cat "$work/unshaped-red-arm.out"; fail=$((fail+1))
  fi
fi
run_backlog "$unshaped_plain" "$out"
root_backlog="$(cat "$out")"
run_backlog_from_subdirectory "$unshaped_plain" "$out"
if [ "$root_backlog" = "$(cat "$out")" ] && has unshaped-backlog 'UNSHAPED {{BEAD_PREFIX}}-plain' "$out"; then
  printf '  PASS  unshaped: backlog output is identical from a subdirectory\n'; pass=$((pass+1))
else printf '  FAIL  unshaped: backlog output is identical from a subdirectory\n'; fail=$((fail+1)); fi

# Proofdelve ForgeOs-n1wbd: a Declined bead re-released without a lap, and a Touches token
# that is not a path. The event stream is a fixture under the fixture repo, removed
# afterwards so no other case sees it.
mkdir -p "$repo/fort/events"
dec_fleet='[{"id":"{{BEAD_PREFIX}}-dec","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","sign-to-land"]}]'
dec_events() {  # $1 category of the LAST decision on {{BEAD_PREFIX}}-dec
  printf '%s\n' '{"ts":"2026-10-21T22:00:00-08:00","actor":"justin","category":"gate.approved","target":"{{BEAD_PREFIX}}-dec","detail":"approve"}' \
    '{"ts":"2026-10-21T22:05:00-08:00","actor":"fleet","category":"gate.declined","target":"{{BEAD_PREFIX}}-dec","detail":"not his"}' \
    "{\"ts\":\"2026-10-21T22:10:00-08:00\",\"actor\":\"justin\",\"category\":\"$1\",\"target\":\"{{BEAD_PREFIX}}-dec\",\"detail\":\"x\"}" \
    > "$repo/fort/events/events-2026-10-21.jsonl"
}
out="$work/declined.out"
dec_events gate.declined
run_queue_case "$dec_fleet" "$dec_fleet" "$out"
if has declined-flagged 'DECLINED ESCALATE RE-RELEASED WITHOUT A LAP' "$out" && has declined-names '  {{BEAD_PREFIX}}-dec' "$out"; then
  printf '  PASS  declined: fleet-safe after a Decline with no lap is flagged\n'; pass=$((pass+1))
else printf '  FAIL  declined: fleet-safe after a Decline with no lap is flagged\n'; cat "$out"; fail=$((fail+1)); fi
dec_board='[{"id":"{{BEAD_PREFIX}}-dec","status":"open","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-dec.1","status":"open","labels":["fleet-safe"]}]'
run_queue_case "$dec_fleet" "$dec_board" "$out"
if ! has declined-lap 'DECLINED ESCALATE' "$out"; then
  printf '  PASS  declined: an open child lap clears it\n'; pass=$((pass+1))
else printf '  FAIL  declined: an open child lap clears it\n'; fail=$((fail+1)); fi
dec_closed_lap='[{"id":"{{BEAD_PREFIX}}-dec","status":"open","labels":["fleet-safe"]},{"id":"{{BEAD_PREFIX}}-dec.1","status":"closed","labels":[]}]'
run_queue_case "$dec_fleet" "$dec_closed_lap" "$out"
if has declined-closed-lap 'DECLINED ESCALATE' "$out"; then
  printf '  PASS  declined: a CLOSED lap does not clear it\n'; pass=$((pass+1))
else printf '  FAIL  declined: a CLOSED lap does not clear it\n'; fail=$((fail+1)); fi
dec_events gate.approved
run_queue_case "$dec_fleet" "$dec_fleet" "$out"
if ! has declined-approved 'DECLINED ESCALATE' "$out"; then
  printf '  PASS  declined: a later Approve by him clears it (a fleet-actor decline never counts)\n'; pass=$((pass+1))
else printf '  FAIL  declined: a later Approve by him clears it (a fleet-actor decline never counts)\n'; fail=$((fail+1)); fi
dec_events gate.declined
mutant="$work/queue-lint-without-declined.sh"
sed 's/^if declined_no_lap:$/if False:/' "$lint_source" > "$mutant"
if grep -q '^if False:$' "$mutant"; then
  run_queue_source_case "$mutant" "$dec_fleet" "$dec_fleet" "$out"
  if ! has declined-red-arm 'DECLINED ESCALATE' "$out"; then
    printf '  PASS  declined red arm: without the check the Declined bead goes unflagged\n'; pass=$((pass+1))
  else printf '  FAIL  declined red arm: without the check the Declined bead goes unflagged\n'; fail=$((fail+1)); fi
else printf '  FAIL  declined red arm: mutation anchor not found in the subject\n'; fail=$((fail+1)); fi
rm -rf "$repo/fort/events"
nonpath_fleet='[{"id":"{{BEAD_PREFIX}}-np","status":"open","description":"Touches: scripts/queue-lint.sh (new file)","labels":["fleet-safe","lands-on-review"]},{"id":"{{BEAD_PREFIX}}-ok","status":"open","description":"Touches: scripts/queue-lint.sh, docs","labels":["fleet-safe","lands-on-review"]}]'
run_queue_case "$nonpath_fleet" "$nonpath_fleet" "$out"
if has nonpath-flag '{{BEAD_PREFIX}}-np declares (new' "$out" && has nonpath-flag2 '{{BEAD_PREFIX}}-np declares file)' "$out" && ! has nonpath-ok '{{BEAD_PREFIX}}-ok declares' "$out"; then
  printf '  PASS  touches: (new file) tokens are flagged, plain paths and a bare directory are not\n'; pass=$((pass+1))
else printf '  FAIL  touches: (new file) tokens are flagged, plain paths and a bare directory are not\n'; cat "$out"; fail=$((fail+1)); fi

# PROMPT SIZE (Proofdelve ForgeOs-2tz10): an open fleet-safe bead whose description and
# comments pass the limit is flagged from one bd export; a closed one is not.
size_fleet='[{"id":"{{BEAD_PREFIX}}-big","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","lands-on-review"]},{"id":"{{BEAD_PREFIX}}-small","status":"open","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","lands-on-review"]},{"id":"{{BEAD_PREFIX}}-shut","status":"closed","description":"Touches: scripts/queue-lint.sh","labels":["fleet-safe","lands-on-review"]}]'
size_long="$(printf 'x%.0s' $(seq 1 300))"
size_export="$(printf '{"id":"{{BEAD_PREFIX}}-big","status":"open","description":"d","comments":[{"text":"%s"}]}\n{"id":"{{BEAD_PREFIX}}-small","status":"open","description":"d","comments":[{"text":"short"}]}\n{"id":"{{BEAD_PREFIX}}-shut","status":"closed","description":"d","comments":[{"text":"%s"}]}' "$size_long" "$size_long")"
run_size_case() {  # $1 lint source, $2 output
  HARNESS_FLEET_JSON="$size_fleet" HARNESS_OPEN_JSON="$size_fleet" HARNESS_EXPORT_JSON="$size_export" HARNESS_COMMENTS_JSON='[]' \
  HARNESS_BD_LOG="$work/bd.log" HARNESS_EMITS="$work/emits.log" QUEUE_LINT_PROMPT_LIMIT=100 \
  QUEUE_LINT_SKIP_IDENTIFIER_SURFACE=1 FLEET_STATE="$work/fleet" HARNESS_REAL_PYTHON3="$real_python3" PATH="$stub:$PATH" "$1" >"$2" 2>&1
}
run_size_case "$repo/scripts/queue-lint.sh" "$out"
if has size-flag '{{BEAD_PREFIX}}-big -- 301 characters' "$out" && ! has size-small '{{BEAD_PREFIX}}-small --' "$out" && ! has size-closed '{{BEAD_PREFIX}}-shut --' "$out"; then
  printf '  PASS  prompt size: an open fleet-safe bead past the limit is flagged, small and closed ones are not\n'; pass=$((pass+1))
else printf '  FAIL  prompt size: an open fleet-safe bead past the limit is flagged, small and closed ones are not\n'; cat "$out"; fail=$((fail+1)); fi
mutant="$repo/scripts/queue-lint-without-size.sh"
sed 's/^    if n > limit: print/    if False: print/' "$lint_source" > "$mutant"; chmod 755 "$mutant"
if grep -q '^    if False: print' "$mutant"; then
  run_size_case "$mutant" "$out"
  if has size-red-arm-ran 'queue-lint' "$out" && ! has size-red-arm '{{BEAD_PREFIX}}-big --' "$out"; then
    printf '  PASS  prompt size red arm: without the comparison the oversized bead goes unflagged\n'; pass=$((pass+1))
  else printf '  FAIL  prompt size red arm: without the comparison the oversized bead goes unflagged\n'; fail=$((fail+1)); fi
else printf '  FAIL  prompt size red arm: mutation anchor not found in the subject\n'; fail=$((fail+1)); fi
rm -f "$mutant"

printf 'queue-lint-harness: %d pass / %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
