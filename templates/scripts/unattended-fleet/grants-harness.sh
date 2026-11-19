#!/usr/bin/env bash
# Proves grants.py fails closed while reading an Overseer-style, read-only store.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
reader="$root/scripts/unattended-fleet/grants.py"
fixture=$(mktemp -d)
temp_paths=("$fixture")

cleanup() {
  local temp_path
  for temp_path in "${temp_paths[@]}"; do
    chmod -R u+w "$temp_path" 2>/dev/null || true
    rm -rf "$temp_path"
  done
}
trap cleanup EXIT
now='2030-01-01T12:00:00Z'
future='2030-01-02T12:00:00Z'
past='2029-12-31T12:00:00Z'
pass=0 fail=0

write_records() {
  chmod -R u+w "$fixture" 2>/dev/null || true
  printf '%s\n' "$1" > "$fixture/grants.jsonl"
  printf '%s\n' "$2" > "$fixture/away.jsonl"
  chmod a-w "$fixture" "$fixture/grants.jsonl" "$fixture/away.jsonl"
}

run_case() {
  local name=$1 want_rc=$2 want_text=$3; shift 3
  set +e
  local output
  output=$({{FORT_SLUG_UPPER}}_KEEP_DIR="$fixture" GRANTS_NOW="$now" "$reader" "$@" 2>&1)
  local rc=$?
  set -e
  if [[ $rc == "$want_rc" && $output == *"$want_text"* ]]; then
    printf 'PASS %s: %s\n' "$name" "$output"; pass=$((pass + 1))
  else
    printf 'FAIL %s: rc=%s output=%s\n' "$name" "$rc" "$output"; fail=$((fail + 1))
  fi
}

grant() { printf '{"ts":"2029-12-01T00:00:00Z","op":"%s","action":"%s","bound":"%s","expires":"%s","by":"overseer"}' "$1" "$2" "$3" "$4"; }
away='{"ts":"2029-12-01T00:00:00Z","state":"away","by":"overseer"}'
back='{"ts":"2030-01-01T11:00:00Z","state":"back","by":"overseer"}'
push_bound='main, fast-forward, push-ready YES at the pushed SHA'

run_case missing-file 1 not-granted check push "$push_bound"
printf '%s\n' "$away" > "$fixture/away.jsonl"; chmod a-w "$fixture/away.jsonl"
run_case missing-grants 1 not-granted check push "$push_bound"
chmod u+w "$fixture"; printf '%s\n' '{bad json' > "$fixture/grants.jsonl"; chmod a-w "$fixture"
run_case malformed-record 1 not-granted check push "$push_bound"
write_records "$(grant grant push "$push_bound" "$past")" "$away"
run_case expired-grant 1 'grant expired' check push "$push_bound"
write_records "$(grant grant stock product-first "$future")" "$away"
run_case different-action 1 'no grant for action' check push "$push_bound"
write_records "$(grant grant push "$push_bound" "$future")" "$away"
run_case bound-exceeded 1 'bound is not allowed' check push product-first
chmod u+r "$fixture/grants.jsonl"
chmod a-r "$fixture/grants.jsonl"
run_case unreadable-file 1 'cannot read grants.jsonl' check push "$push_bound"
chmod u+r "$fixture/grants.jsonl"
write_records "$(grant grant push "$push_bound" "$future")" '{"ts":"2029-12-01T00:00:00Z","state":"maybe","by":"overseer"}'
run_case away-unknown-is-back 1 'away state unknown' check push "$push_bound"
write_records "$(grant grant push "$push_bound" "$future")" "$away"$'\n'"$back"
run_case back-expires-grant 1 'Overseer is back' check push "$push_bound"
write_records "$(grant grant push "$push_bound" "$future")"$'\n'"$(grant revoke push "$push_bound" "$future")" "$away"
run_case revoke-wins 1 'latest event is revoke' check push "$push_bound"
write_records "$(grant grant push "$push_bound" "$future")"$'\n'"$(grant grant deploy "$push_bound" "$future")" "$away"
run_case deploy-record-beside-push-grant 0 granted check push "$push_bound"
run_case deploy-remains-never-grant-shaped 1 'action is not grant-shaped' check deploy "$push_bound"
write_records "$(grant grant stock findings-only "$future")" "$away"
run_case stored-bound-narrower-than-request 1 'grant bound does not cover request' check stock product-first
write_records "$(grant grant push "$push_bound" "$future")" "$away"
run_case active-read-only-store 0 granted check push "$push_bound"
run_case away-answer 0 away away

# Red arm: invert the production expiry comparison in a disposable copy.  The
# expired fixture must become granted or this harness has not tested the guard.
red=$(mktemp)
temp_paths+=("$red")
sed 's/if not now() < expires:/if now() < expires:/' "$reader" > "$red"
chmod +x "$red"
write_records "$(grant grant push "$push_bound" "$past")" "$away"
set +e
red_output=$({{FORT_SLUG_UPPER}}_KEEP_DIR="$fixture" GRANTS_NOW="$now" "$red" check push "$push_bound" 2>&1)
red_rc=$?
set -e
if [[ $red_rc == 0 && $red_output == granted ]]; then
  printf 'RED ARM PASS expired-grant-with-inverted-comparison: %s\n' "$red_output"; pass=$((pass + 1))
else
  printf 'RED ARM FAIL rc=%s output=%s\n' "$red_rc" "$red_output"; fail=$((fail + 1))
fi

# Red arm: delete the production bound guard in a disposable copy.  A stored
# findings-only grant must then incorrectly authorize the broader request.
bound_red=$(mktemp)
temp_paths+=("$bound_red")
sed '/    if latest\["bound"\] != bound:/,/        return False, "grant bound does not cover request"/d' "$reader" > "$bound_red"
chmod +x "$bound_red"
write_records "$(grant grant stock findings-only "$future")" "$away"
set +e
bound_red_output=$({{FORT_SLUG_UPPER}}_KEEP_DIR="$fixture" GRANTS_NOW="$now" "$bound_red" check stock product-first 2>&1)
bound_red_rc=$?
set -e
if [[ $bound_red_rc == 0 && $bound_red_output == granted ]]; then
  printf 'RED ARM PASS stored-bound-narrower-without-bound-check: %s\n' "$bound_red_output"; pass=$((pass + 1))
else
  printf 'RED ARM FAIL rc=%s output=%s\n' "$bound_red_rc" "$bound_red_output"; fail=$((fail + 1))
fi

printf 'grants-harness: %d pass / %d fail\n' "$pass" "$fail"
[[ $fail == 0 ]]
