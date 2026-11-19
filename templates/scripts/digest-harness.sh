#!/bin/bash
# Hermetic regression harness for digest.sh (Proofdelve ForgeOs-eng3.7). It runs the
# shipped script in a throwaway git repository with synthetic Beads and events.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mode="${1:-}"
case "$mode" in
  --measure-real|--measure-synthetic)
    shift
    ;;
  *)
    mode=""
    ;;
esac
target="${1:-${DIGEST_SRC:-$here/digest.sh}}"
[ -f "$target" ] || { printf 'HARNESS REFUSES: digest source not found: %s\n' "$target" >&2; exit 3; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
repo="$work/repo"
fixture_tmpdir="$work/digest-tmp"
mkdir -p "$repo/scripts" "$repo/fort/events" "$repo/fort/scripts" "$work/stub" "$fixture_tmpdir"
cp -f "$target" "$repo/scripts/digest.sh"
cp -f "$here/flag-human.sh" "$repo/scripts/flag-human.sh"
cp -f "$here/unflag-human.sh" "$repo/scripts/unflag-human.sh"
chmod 755 "$repo/scripts/digest.sh"
chmod 755 "$repo/scripts/flag-human.sh" "$repo/scripts/unflag-human.sh"
cat > "$repo/fort/scripts/emit.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$HARNESS_EMITS"
[ "${HARNESS_EMIT_FAIL:-}" != 1 ]
EOF
chmod 755 "$repo/fort/scripts/emit.sh"

git -C "$repo" init -q -b main
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -q --allow-empty -m base
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -q --allow-empty -m unpushed
git -C "$repo" update-ref refs/remotes/origin/main HEAD~1

# Captured from `bd human list --json`, Proofdelve ForgeOs-2ibw.2, 2026-09-16. This
# shape deliberately has no dependencies or parent key.
cat > "$work/human.json" <<'EOF'
[
  {"id":"Proofdelve ForgeOs-2ibw.2","title":"2ibw.2: MEASURE whether a live MCP access token carries client_id (Overseer, staging)","description":"Spec constraint 2 and Decision 4 (docs/specs/mcp-permissions-v1.md). The OAuth\ngrant resolver (Proofdelve ForgeOs-2ibw.6) needs client_id at request time. The ledger\nrecords client_id on a WEB-LOGIN token (fort/memory/facts/workos-issuer-and-\naudience-per-role.md, \"Claims and lifetime\") and does not confirm it on an MCP\ntoken. No seat can complete an OAuth login, so this is the Overseer's hand on\nstaging.\n\nHOW: connect Claude (or any MCP client) to staging, capture one access token\nfrom the /oauth/token exchange or from a request's Authorization header, and\ndecode the JWT payload (base64url of the middle segment; do not paste the token\nitself anywhere durable). Record the CLAIM NAMES present, not the values.\n\nWHY IT MATTERS: if client_id is present, .6 reads it in OnTokenValidated. If\nabsent, .6 records sid -> client_id at the facade's token proxy instead\n(Decision 4, second design). The bead for .6 is blocked on this one so the Forge\ndoes not guess.\n\nTouches: fort/memory/facts/","acceptance_criteria":"1. A comment on this bead lists the claim names of one live MCP access token\n   from staging, and states whether client_id is among them, and for a CIMD\n   client whether its value is the client metadata URL.\n2. fort/memory/facts/workos-issuer-and-audience-per-role.md \"Claims and\n   lifetime\" is amended with that measurement and its date (Mayor may do this\n   from the comment).\n3. Proofdelve ForgeOs-2ibw.6's description is amended by the Mayor to name which of\n   Decision 4's two designs applies.","status":"open","priority":1,"issue_type":"task","owner":"justincase18@msn.com","created_at":"2026-09-16T06:19:16Z","created_by":"{{MAYOR_ID}}","updated_at":"2026-09-16T06:19:16Z","labels":["human"]},
  {"id":"{{BEAD_PREFIX}}-offset","title":"offset","status":"open","created_at":"2026-09-14T00:30:00+01:00"},
  {"id":"{{BEAD_PREFIX}}-utc","title":"utc","status":"open","created_at":"2026-09-14T00:00:00Z"},
  {"id":"{{BEAD_PREFIX}}-later","title":"later","status":"open","created_at":"2026-09-15T00:00:00Z"},
  {"id":"{{BEAD_PREFIX}}-raised","title":"raised during this run","status":"open","created_at":"2026-09-14T00:00:00Z"},
  {"id":"{{BEAD_PREFIX}}-answered","title":"two raises, answer between them","status":"open","created_at":"2026-09-14T00:00:00Z"},
  {"id":"{{BEAD_PREFIX}}-answered-later","title":"answer after its only raise","status":"open","created_at":"2026-09-14T00:00:00Z"},
  {"id":"{{BEAD_PREFIX}}-pre-wrapper","title":"pre-wrapper decision","status":"open","created_at":"2026-09-16T01:00:00Z"},
  {"id":"{{BEAD_PREFIX}}-null","title":"null","status":"open","created_at":null}
]
EOF
# The stub reproduces bd's default 50-row cap. Its real captured row appears
# at position 51, proving that a full-board parent lookup needs --limit 0.
printf '[\n' > "$work/list.json"
for row in {1..50}; do
  printf '  {"id":"{{BEAD_PREFIX}}-filler-%s","status":"open"},\n' "$row" >> "$work/list.json"
done
# Captured from `bd list --status all --json`, Proofdelve ForgeOs-2ibw.2, 2026-09-16.
# Unlike the human-list row above, this real list row carries the parent edge.
cat >> "$work/list.json" <<'EOF'
  {"id":"Proofdelve ForgeOs-2ibw.2","title":"2ibw.2: MEASURE whether a live MCP access token carries client_id (Overseer, staging)","description":"Spec constraint 2 and Decision 4 (docs/specs/mcp-permissions-v1.md). The OAuth\ngrant resolver (Proofdelve ForgeOs-2ibw.6) needs client_id at request time. The ledger\nrecords client_id on a WEB-LOGIN token (fort/memory/facts/workos-issuer-and-\naudience-per-role.md, \"Claims and lifetime\") and does not confirm it on an MCP\ntoken. No seat can complete an OAuth login, so this is the Overseer's hand on\nstaging.\n\nHOW: connect Claude (or any MCP client) to staging, capture one access token\nfrom the /oauth/token exchange or from a request's Authorization header, and\ndecode the JWT payload (base64url of the middle segment; do not paste the token\nitself anywhere durable). Record the CLAIM NAMES present, not the values.\n\nWHY IT MATTERS: if client_id is present, .6 reads it in OnTokenValidated. If\nabsent, .6 records sid -> client_id at the facade's token proxy instead\n(Decision 4, second design). The bead for .6 is blocked on this one so the Forge\ndoes not guess.\n\nTouches: fort/memory/facts/","acceptance_criteria":"1. A comment on this bead lists the claim names of one live MCP access token\n   from staging, and states whether client_id is among them, and for a CIMD\n   client whether its value is the client metadata URL.\n2. fort/memory/facts/workos-issuer-and-audience-per-role.md \"Claims and\n   lifetime\" is amended with that measurement and its date (Mayor may do this\n   from the comment).\n3. Proofdelve ForgeOs-2ibw.6's description is amended by the Mayor to name which of\n   Decision 4's two designs applies.","status":"open","priority":1,"issue_type":"task","owner":"justincase18@msn.com","created_at":"2026-09-16T06:19:16Z","created_by":"{{MAYOR_ID}}","updated_at":"2026-09-16T06:19:16Z","labels":["human"],"dependencies":[{"issue_id":"Proofdelve ForgeOs-2ibw.2","depends_on_id":"Proofdelve ForgeOs-2ibw","type":"parent-child","created_at":"2026-09-15T22:19:15Z","created_by":"{{MAYOR_ID}}","metadata":"{}"}],"dependency_count":0,"dependent_count":1,"comment_count":0,"parent":"Proofdelve ForgeOs-2ibw"}
]
EOF
{
  printf '[\n'
  printf '  {"id":"{{BEAD_PREFIX}}-verdict","title":"verdict fixture","status":"in_progress"},\n'
  for row in {2..60}; do
    printf '  {"id":"{{BEAD_PREFIX}}-in-progress-%s","title":"in progress %s","status":"in_progress"}' "$row" "$row"
    [ "$row" -eq 60 ] || printf ','
    printf '\n'
  done
  printf ']\n'
} > "$work/in-progress.json"
printf '%s\n' '[{"id":"Proofdelve ForgeOs-2ibw","labels":["human"]}]' > "$work/parent.json"

cat > "$work/stub/bd" <<'EOF'
#!/bin/bash
args="$*"
case "$args" in
  *" update "*)
    printf '%s\n' "$args" >> "$HARNESS_BD_LOG"
    if [[ "$args" == *"--add-label human"* && "${HARNESS_BD_FAIL_RESTORE:-}" = 1 ]]; then
      exit 17
    fi
    ;;
  # Proofdelve ForgeOs-29j3g: flag-human posts its ASK line as a comment before the update.
  *" comment "*" --file "*) cat "${args##* --file }" >> "$HARNESS_BD_LOG.comments" ;;
  *"human list --json"*) cat "$HARNESS_FIXTURES/human.json" ;;
  *"list --status all --limit 0 --json"*) cat "$HARNESS_FIXTURES/list.json" ;;
  *"list --status all --json"*) jq '.[0:50]' "$HARNESS_FIXTURES/list.json" ;;
  *"list --status=in_progress --limit 0 --json"*) cat "$HARNESS_FIXTURES/in-progress.json" ;;
  *"list --status=in_progress --json"*) jq '.[0:50]' "$HARNESS_FIXTURES/in-progress.json" ;;
  *"list --status=open --limit 0 --json"*) printf "[]\n" ;;
  *"list --status=open --json"*) printf "[]\n" ;;
  *"show Proofdelve ForgeOs-2ibw --json"*) cat "$HARNESS_FIXTURES/parent.json" ;;
  *) printf "unexpected bd command: %s\n" "$args" >&2; exit 9 ;;
esac
EOF
chmod 755 "$work/stub/bd"

pass=0; fail=0
check_contains() {
  local name="$1" needle="$2" file="$3"
  if grep -Fq -- "$needle" "$file"; then
    printf '  PASS  %s\n' "$name"; pass=$((pass + 1))
  else
    printf '  FAIL  %s\n' "$name"; fail=$((fail + 1))
  fi
}

run_digest() {
  local output="$1"; shift
  (cd "$repo" && PATH="$work/stub:$PATH" HARNESS_FIXTURES="$work" TMPDIR="$fixture_tmpdir" scripts/digest.sh "$@") > "$output"
}

run_digest_script() {
  local script="$1" output="$2"; shift 2
  (cd "$repo" && PATH="$work/stub:$PATH" HARNESS_FIXTURES="$work" TMPDIR="$fixture_tmpdir" "$script" "$@") > "$output"
}

measure_digest() {
  local name="$1" root="$2" script="$3" output="$4" log="$5" start_ns end_ns elapsed_ns elapsed_ms jq_count bd_count
  start_ns="$(date +%s%N)"
  (cd "$root" && PATH="$work/counting-stub:$PATH" HARNESS_FIXTURES="$work" TMPDIR="$fixture_tmpdir" "$script" --since 2026-01-01T00:00:00Z) > "$output"
  end_ns="$(date +%s%N)"
  elapsed_ns=$((end_ns - start_ns))
  elapsed_ms=$((elapsed_ns / 1000000))
  jq_count="$(grep -Fc 'jq' "$log" || true)"
  bd_count="$(grep -Fc 'bd' "$log" || true)"
  printf 'MEASURE %s: wall_ms=%s jq=%s bd=%s\n' "$name" "$elapsed_ms" "$jq_count" "$bd_count"
}

if [ -n "$mode" ]; then
  real_jq="$(command -v jq)"
  real_bd="$(command -v bd)"
  if [ "$mode" = "--measure-synthetic" ]; then
    real_bd="$work/stub/bd"
  fi
  mkdir -p "$work/counting-stub"
  cat > "$work/counting-stub/jq" <<EOF
#!/bin/bash
printf '%s\\n' jq >> "\$HARNESS_EXEC_LOG"
exec "$real_jq" "\$@"
EOF
  cat > "$work/counting-stub/bd" <<EOF
#!/bin/bash
printf '%s\\n' bd >> "\$HARNESS_EXEC_LOG"
exec "$real_bd" "\$@"
EOF
  chmod 755 "$work/counting-stub/jq" "$work/counting-stub/bd"
  case "$mode" in
    --measure-real)
      exec_log="$work/real.exec"
      HARNESS_EXEC_LOG="$exec_log" measure_digest real "$here/.." "$target" "$work/real.out" "$exec_log"
      ;;
    --measure-synthetic)
      synthetic_stream="$repo/fort/events/events-2026-09-16.jsonl"
      for row in {1..50000}; do
        printf '{"ts":"2026-09-16T01:00:00Z","category":"other","detail":"synthetic"}\n'
      done > "$synthetic_stream"
      printf 'STREAM %s\n' "$synthetic_stream"
      wc -l "$synthetic_stream"
      exec_log="$work/synthetic.exec"
      HARNESS_EXEC_LOG="$exec_log" measure_digest synthetic-50000 "$repo" "$repo/scripts/digest.sh" "$work/synthetic.out" "$exec_log"
      ;;
  esac
  exit 0
fi

printf 'TMPDIR before digest:\n'
ls -la "$fixture_tmpdir"

# The wrappers must resolve the primary checkout from a linked worktree, not
# write to that worktree's Beads snapshot. The fake bd records its complete
# argument string so the root is an assertion rather than an inference.
wrapper_tree="$work/wrapper-worktree"
git -C "$repo" worktree add -q -b wrapper-fixture "$wrapper_tree"
mkdir -p "$wrapper_tree/scripts"
cp -f "$repo/scripts/flag-human.sh" "$wrapper_tree/scripts/flag-human.sh"
cp -f "$repo/scripts/unflag-human.sh" "$wrapper_tree/scripts/unflag-human.sh"
wrapper_log="$work/wrapper-bd.log"
wrapper_emits="$work/wrapper.emits"
HARNESS_BD_LOG="$wrapper_log" HARNESS_EMITS="$wrapper_emits" \
  FORT_ACTOR=justin FORT_SEAT=overseer \
  PATH="$work/stub:$PATH" "$wrapper_tree/scripts/flag-human.sh" {{BEAD_PREFIX}}-flag 'needs review'
if grep -Fq -- "-C $repo update {{BEAD_PREFIX}}-flag --remove-label mayor-review --add-label human" "$wrapper_log"; then
  printf '  PASS  flag-human writes the label through the main tracker from a worktree\n'; pass=$((pass + 1))
else
  printf '  FAIL  flag-human writes the label through the main tracker from a worktree\n'; fail=$((fail + 1))
fi
if grep -Fq -- "-C $repo update {{BEAD_PREFIX}}-flag --remove-label mayor-review --add-label human --assignee justin" "$wrapper_log" \
   && grep -Fq 'ASK: decide -- needs review' "$wrapper_log.comments"; then
  printf '  PASS  flag-human assigns justin in the same update and posts the ASK line first (29j3g)\n'; pass=$((pass + 1))
else
  printf '  FAIL  flag-human assigns justin in the same update and posts the ASK line first (29j3g)\n'; fail=$((fail + 1))
fi
if grep -Fq -- 'decision.raised needs review -a justin -s overseer -t {{BEAD_PREFIX}}-flag' "$wrapper_emits"; then
  printf '  PASS  flag-human honors FORT_ACTOR and FORT_SEAT\n'; pass=$((pass + 1))
else
  printf '  FAIL  flag-human honors FORT_ACTOR and FORT_SEAT\n'; fail=$((fail + 1))
fi
# The DEFAULT case unsets the identity it asserts the default of: a verifier run
# under FORT_ACTOR (a Regent's, emitting under its own name) otherwise makes this
# case measure the caller (found 2026-10-19 at the docket Proofdelve ForgeOs-x7ojh verify).
env -u FORT_ACTOR -u FORT_SEAT HARNESS_BD_LOG="$wrapper_log" HARNESS_EMITS="$wrapper_emits" \
  PATH="$work/stub:$PATH" "$wrapper_tree/scripts/flag-human.sh" {{BEAD_PREFIX}}-default 'default actor'
if grep -Fq -- 'decision.raised default actor -a {{MAYOR_ID}} -s mayor -t {{BEAD_PREFIX}}-default' "$wrapper_emits"; then
  printf '  PASS  flag-human defaults actor and seat to {{MAYOR_ID}} and mayor\n'; pass=$((pass + 1))
else
  printf '  FAIL  flag-human defaults actor and seat to {{MAYOR_ID}} and mayor\n'; fail=$((fail + 1))
fi
HARNESS_BD_LOG="$wrapper_log" HARNESS_EMITS="$wrapper_emits" \
  FORT_ACTOR=justin FORT_SEAT=overseer \
  PATH="$work/stub:$PATH" "$wrapper_tree/scripts/unflag-human.sh" {{BEAD_PREFIX}}-unflag 'answer recorded'
if grep -Fq -- "-C $repo update {{BEAD_PREFIX}}-unflag --remove-label human --assignee {{MAYOR_ID}}" "$wrapper_log" && \
  grep -Fq -- 'decision.answered answer recorded -a justin -s overseer -t {{BEAD_PREFIX}}-unflag' "$wrapper_emits"; then
  printf '  PASS  unflag-human writes through the main tracker and honors FORT_ACTOR and FORT_SEAT\n'; pass=$((pass + 1))
else
  printf '  FAIL  unflag-human writes through the main tracker and honors FORT_ACTOR and FORT_SEAT\n'; fail=$((fail + 1))
fi
restore_stderr="$work/restore.stderr"
HARNESS_BD_LOG="$wrapper_log" HARNESS_EMITS="$wrapper_emits" HARNESS_BD_FAIL_RESTORE=1 HARNESS_EMIT_FAIL=1 \
  PATH="$work/stub:$PATH" "$wrapper_tree/scripts/unflag-human.sh" {{BEAD_PREFIX}}-restore 'answer' > /dev/null 2>"$restore_stderr"
restore_status=$?
if [ "$restore_status" -ne 3 ]; then
  printf '  FAIL  unflag-human restore failure returns exit 3\n'; fail=$((fail + 1))
elif grep -Fq '{{BEAD_PREFIX}}-restore; label is absent and decision.answered was not recorded' "$restore_stderr"; then
  printf '  PASS  unflag-human restore failure names the bead and label-without-event state\n'; pass=$((pass + 1))
else
  printf '  FAIL  unflag-human restore failure names the bead and label-without-event state\n'; fail=$((fail + 1))
fi

# The digest event establishes a quiet window. eng3.3.1 intentionally makes
# this an entirely quiet no-op, including no digest.emitted event.
printf '%s\n' '{"ts":"2026-09-15T00:00:00Z","category":"digest.emitted","detail":"previous digest"}' > "$repo/fort/events/events-2026-09-15.jsonl"
quiet="$work/quiet.out"
HARNESS_EMITS="$work/quiet.emits" run_digest "$quiet"
if [ ! -s "$quiet" ] && [ ! -s "$work/quiet.emits" ]; then
  printf '  PASS  quiet window prints zero bytes and emits no digest.emitted event\n'; pass=$((pass + 1))
else
  printf '  FAIL  quiet window prints zero bytes and emits no digest.emitted event\n'; fail=$((fail + 1))
fi

# An explicit --since is an intentional digest request, not a Stop-hook quiet
# turn. It exercises every standing property without weakening eng3.3.1.
standing="$work/standing.out"
HARNESS_EMITS="$work/standing.emits" run_digest "$standing" --since 2026-09-15T00:00:00Z
check_contains 'standing inherited suspect is surfaced' '1 may be inherited labels: Proofdelve ForgeOs-2ibw.2' "$standing"
oldest_line="$(grep -F 'Also standing:' "$standing")"
case "$oldest_line" in
  *'oldest: {{BEAD_PREFIX}}-offset ('*', {{BEAD_PREFIX}}-utc ('*)
  printf '  PASS  standing trio names offset before UTC and excludes null timestamp\n'; pass=$((pass + 1))
  ;;
  *)
  printf '  FAIL  standing trio names offset before UTC and excludes null timestamp\n'; fail=$((fail + 1))
  ;;
esac

# A verdict containing each formerly TSV-escaped byte must reach the digest
# unchanged. The same stream also exercises both missing TROUBLE categories.
# shellcheck disable=SC2016 # JSON fixture must preserve literal backticks.
printf '%s\n' \
  '{"ts":"2026-09-16T00:10:00Z","category":"decision.raised","target":"{{BEAD_PREFIX}}-raised","detail":"raised during this run"}' \
  '{"ts":"2026-09-16T00:12:00Z","category":"decision.raised","target":"{{BEAD_PREFIX}}-answered","detail":"later raise by epoch"}' \
  '{"ts":"2026-09-16T00:11:00Z","category":"decision.raised","target":"{{BEAD_PREFIX}}-answered","detail":"backdated raise later in stream order"}' \
  '{"ts":"2026-09-16T00:11:30Z","category":"decision.answered","target":"{{BEAD_PREFIX}}-answered","detail":"answer between the two raises by epoch"}' \
  '{"ts":"2026-09-16T00:12:30Z","category":"decision.raised","target":"{{BEAD_PREFIX}}-answered-later","detail":"only raise before answer"}' \
  '{"ts":"2026-09-16T00:12:45Z","category":"decision.answered","target":"{{BEAD_PREFIX}}-answered-later","detail":"answer after only raise"}' \
  '{"ts":"2026-09-16T01:00:00Z","category":"review.verdict","target":"{{BEAD_PREFIX}}-verdict","detail":"verdict \"quote\" `backtick` ~tilde~ \\path\tfirst\nsecond\rthird"}' \
  '{"ts":"2026-09-16T01:01:00Z","category":"incident.corrected","detail":"incident corrected"}' \
  '{"ts":"2026-09-16T01:02:00Z","category":"verify.blocked","detail":"verify blocked"}' > "$repo/fort/events/events-2026-09-16.jsonl"
events="$work/events.out"
run_digest "$events" --since 2026-09-15T12:00:00Z
check_contains 'pre-window bead raised during this run is listed' '{{BEAD_PREFIX}}-raised [open] raised during this run' "$events"
# This answer-tracking control removes answer handling from a copy. The
# later-answered bead must become outstanding, proving the control is red.
answered_removed_script="$repo/scripts/digest-answer-removed.sh"
# shellcheck disable=SC2016 # sed and grep match literal shell syntax.
sed '/decision\.answered) last_answered_epoch\["\$target"\]="\$event_epoch" ;;/d' \
  "$repo/scripts/digest.sh" > "$answered_removed_script"
chmod 755 "$answered_removed_script"
# shellcheck disable=SC2016 # grep matches literal shell syntax.
if grep -Fq 'decision.answered) last_answered_epoch["$target"]="$event_epoch" ;;' "$answered_removed_script"; then
  printf '  FAIL  answered-fixture control did not remove answer handling\n'; fail=$((fail + 1))
else
  answered_removed="$work/answered-removed.out"
  run_digest_script "$answered_removed_script" "$answered_removed" --since 2026-09-15T12:00:00Z
  if grep -Fq '{{BEAD_PREFIX}}-answered-later [open] answer after its only raise' "$answered_removed"; then
    printf '  CONTROL RED  later-answered decision is outstanding without answer tracking\n'
    printf '  PASS  answer-tracking control is RED when answer handling is removed\n'; pass=$((pass + 1))
  else
    printf '  FAIL  answer-tracking control is RED when answer handling is removed\n'; fail=$((fail + 1))
  fi
fi
# With answer tracking, the later-answered bead must be absent from every
# outstanding section. This is the green half of the answer-tracking control.
if grep -Fq '{{BEAD_PREFIX}}-answered-later' "$events"; then
  printf '  FAIL  answer-tracking control is GREEN with answer handling\n'; fail=$((fail + 1))
else
  printf '  CONTROL GREEN  later-answered decision is absent with answer tracking\n'
  printf '  PASS  answer-tracking control is GREEN with answer handling\n'; pass=$((pass + 1))
fi
# This distinct control proves that the two-raise fixture chooses the maximum
# raise epoch, even when its answer appears later in stream order.
if grep -Fq '{{BEAD_PREFIX}}-answered [open] two raises, answer between them' "$events"; then
  printf '  PASS  max-epoch decision remains outstanding\n'; pass=$((pass + 1))
else
  printf '  FAIL  max-epoch decision remains outstanding\n'; fail=$((fail + 1))
fi
check_contains 'max-epoch decision is excluded from the standing count' 'Also standing: 4 blocked on you' "$events"
check_contains 'pre-wrapper bead uses the creation-date fallback note' '{{BEAD_PREFIX}}-pre-wrapper [open] pre-wrapper decision (no raise event; by creation date)' "$events"
expected_detail=$'    verdict "quote" `backtick` ~tilde~ \\path\tfirst\nsecond\rthird'
actual_detail="$(sed -n '/^  {{BEAD_PREFIX}}-verdict: /{n;p;n;p;}' "$events")"
if [ "$actual_detail" = "$expected_detail" ]; then
  printf '  PASS  verdict detail round-trips quote, backtick, tilde, tab, newline, CR and backslash\n'; pass=$((pass + 1))
else
  printf '  FAIL  verdict detail round-trips quote, backtick, tilde, tab, newline, CR and backslash\n'; fail=$((fail + 1))
fi
check_contains 'trouble includes incident.corrected' 'incident corrected' "$events"
check_contains 'trouble includes verify.blocked' 'verify blocked' "$events"

# Prove the 60-row fixture rejects the default cap before checking the
# production query's explicit --limit 0 escape hatch.
default_limit_script="$repo/scripts/digest-default-limit.sh"
sed 's/list --status=in_progress --limit 0 --json/list --status=in_progress --json/' \
  "$repo/scripts/digest.sh" > "$default_limit_script"
chmod 755 "$default_limit_script"
if cmp -s "$repo/scripts/digest.sh" "$default_limit_script"; then
  printf '  FAIL  default-limit copy did not change\n'
  exit 1
fi
default_limit="$work/default-limit.out"
run_digest_script "$default_limit_script" "$default_limit" --since 2026-09-15T12:00:00Z
if grep -Fq '{{BEAD_PREFIX}}-in-progress-60: in progress 60' "$default_limit"; then
  printf '  FAIL  default 50-row cap unexpectedly renders row 60\n'; fail=$((fail + 1))
else
  printf '  PASS  default-limit copy omits row 60\n'; pass=$((pass + 1))
fi
check_contains 'in-flight listing includes row 60 beyond the default cap' '{{BEAD_PREFIX}}-in-progress-60: in progress 60' "$events"

printf 'TMPDIR after full digest runs:\n'
ls -la "$fixture_tmpdir"
if [ -z "$(find "$fixture_tmpdir" -mindepth 1 -maxdepth 1 -type f -print -quit)" ]; then
  printf '  PASS  digest temp files are removed after full runs\n'; pass=$((pass + 1))
else
  printf '  FAIL  digest temp files are removed after full runs\n'; fail=$((fail + 1))
fi

printf 'RESULT %s pass / %s fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
