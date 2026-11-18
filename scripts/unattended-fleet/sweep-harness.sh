#!/bin/bash
# Hermetic regression harness for the no-model Mayor sweep.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source="${SWEEP_SRC:-$here/sweep.py}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
repo="$work/repo"; stub="$work/stub"; state="$work/state"
mkdir -p "$repo/scripts/unattended-fleet" "$repo/docs/specs" "$stub" "$state"
cp -f "$source" "$repo/scripts/unattended-fleet/sweep.py"
for s in triage.py already-merged.py stale-parents.py satisfied-holds.py misrouted.py; do cp -f "$here/$s" "$repo/scripts/unattended-fleet/$s"; done
cp -f "$here/../../docs/specs/unattended-mayor-loop.status.schema.json" "$repo/docs/specs/"
mkdir -p "$repo/scripts"
cat > "$repo/scripts/queue-lint.sh" <<'EOF'
#!/bin/sh
printf 'queue-lint\n' >> "${QUEUE_LOG:?}"
if [ "${DEPTH_COUNT:-0}" = 0 ]; then
  printf 'DEPTH -- 0 fleet-safe, unblocked beads; queue is empty (0.0 hours at ~8 beads/hour).\n'
else
  printf 'DEPTH -- %s fleet-safe, unblocked bead(s); %s hours at ~8 beads/hour.\n' "$DEPTH_COUNT" "${DEPTH_HOURS:-2.0}"
fi
EOF
chmod +x "$repo/scripts/queue-lint.sh"
git -C "$repo" init -q -b main; git -C "$repo" add .; git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit -qm base
cat > "$stub/bd" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${BD_LOG:?}"
case " $* " in
  *" list "*) [ "${BD_DOWN:-}" = 1 ] && exit 3; printf '%s\n' "${BOARD_JSON:?}" ;;
  *" comments "*) printf '[]\n' ;;
  *) printf 'WRITE OR UNKNOWN ATTEMPT: %s\n' "$*" | tee -a "${BD_LOG:?}" >&2; exit 99 ;;
esac
EOF
printf '#!/bin/sh\nexit 1\n' > "$stub/ssh-add"; printf '#!/bin/sh\nexit 1\n' > "$stub/pgrep"
chmod +x "$stub/bd" "$stub/ssh-add" "$stub/pgrep"
if refusal_output="$(BD_LOG="$work/bd-refusal.log" "$stub/bd" update fortkit-test --notes forbidden 2>&1)"; then
  echo 'FAIL bd stub accepted a write command'; exit 1
else
  refusal_exit=$?
fi
[ "$refusal_exit" = 99 ] || { echo "FAIL bd stub refusal exit was $refusal_exit, expected 99"; exit 1; }
printf '%s\n' "$refusal_output" | grep -Fqx 'WRITE OR UNKNOWN ATTEMPT: update fortkit-test --notes forbidden' || {
  echo 'FAIL bd stub did not print its refusal marker'; exit 1
}
grep -Fqx 'WRITE OR UNKNOWN ATTEMPT: update fortkit-test --notes forbidden' "$work/bd-refusal.log" || {
  echo 'FAIL bd stub did not record its refusal marker'; exit 1
}
run_case() {
  if BOARD_JSON="$1" DEPTH_COUNT="${2:-0}" DEPTH_HOURS="${3:-2.0}" BD_LOG="$work/bd.log" QUEUE_LOG="$work/queue.log" MAYOR_STATUS_STATE="$state" SWEEP_ROOT="$repo" PATH="$stub:$PATH" python3 "$repo/scripts/unattended-fleet/sweep.py" 2>>"$work/stderr.log"; then
    return 0
  else
    status=$?
    cat "$work/stderr.log" >&2
    return "$status"
  fi
}
read_work() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["work"]["exists"])' "$state/status.json"; }
read_reasons() { python3 -c 'import json,sys; print("\\n".join(json.load(open(sys.argv[1]))["work"]["reasons"]))' "$state/status.json"; }
read_misrouted_exit() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sweeps"]["misrouted.py"]["exit"])' "$state/status.json"; }
read_sweep_findings() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sweeps"][sys.argv[2]]["findings"])' "$state/status.json" "$1"; }
write_sweep_fixture() {
  cat > "$repo/scripts/unattended-fleet/satisfied-holds.py" <<'EOF'
#!/usr/bin/env python3
import os
import sys
print(os.environ["SATISFIED_HOLDS_OUTPUT"], file=sys.stderr)
sys.exit(int(os.environ.get("SATISFIED_HOLDS_EXIT", "0")))
EOF
}
mayor='[{"id":"fortkit-r","status":"open","labels":["mayor-review"],"title":"review","description":"Touches: x"}]'
empty='[]'
stockable='[{"id":"fortkit-stockable","status":"open","labels":[],"title":"needs prep","description":"Touches: scripts/unattended-fleet/sweep.py\n\n## Acceptance\n\n- A criterion."}]'
already_merged='[{"id":"fortkit-a1","status":"open","labels":["fleet-safe"],"title":"first landed fixture","description":"Touches: x"},{"id":"fortkit-b2","status":"open","labels":["fleet-safe"],"title":"second landed fixture","description":"Touches: x"}]'
run_case "$mayor"
[ "$(read_work)" = True ] && echo 'PASS mayor-review fixture sets work bit' || { echo 'FAIL mayor-review fixture sets work bit'; exit 1; }
if [ "${HARNESS_T4_RESTORATION_PROBE:-}" != 1 ]; then
  rm -f "$work/queue.log"
  run_case "$mayor"
  [ "$(wc -l < "$work/queue.log")" = 1 ] && echo 'PASS queue-lint runs once per sweep' || { echo 'FAIL queue-lint did not run exactly once per sweep'; exit 1; }
fi
run_case "$empty" 16 2.0
[ "$(read_work)" = False ] && echo 'PASS empty inbox at DEPTH above an hour clears work bit' || { echo 'FAIL empty inbox did not clear work bit'; exit 1; }
run_case "$empty"
[ "$(read_work)" = False ] && echo 'PASS literal empty-queue DEPTH clears work bit' || { echo 'FAIL literal empty-queue DEPTH did not clear work bit'; exit 1; }
run_case "$stockable"
[ "$(read_work)" = False ] && ! read_reasons | grep -Fq 'T4:' && echo 'PASS thin depth with only a stockable bead does not set T4' || { echo 'FAIL thin depth stockable fixture set work or T4'; exit 1; }
write_sweep_fixture
SATISFIED_HOLDS_OUTPUT='satisfied-holds: no candidates (0 beads scanned, description+notes+design+comments)' run_case "$already_merged"
already_merged_findings="$(read_sweep_findings already-merged.py)"
[ "$already_merged_findings" = 0 ] && echo 'PASS real already-merged clean fixture reports zero findings' || { echo "FAIL real already-merged clean fixture did not report zero findings (got $already_merged_findings)"; exit 1; }
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit --allow-empty -qm 'fortkit-a1: merged by the fleet on fixture verdict'
git -C "$repo" -c user.name=harness -c user.email=harness@example.invalid commit --allow-empty -qm 'fortkit-b2: merged by the fleet on fixture verdict'
SATISFIED_HOLDS_OUTPUT='satisfied-holds: no candidates (0 beads scanned, description+notes+design+comments)' run_case "$already_merged"
already_merged_findings="$(read_sweep_findings already-merged.py)"
[ "$already_merged_findings" = 2 ] && echo 'PASS real already-merged two-hit fixture reports two findings' || { echo "FAIL real already-merged two-hit fixture did not report two findings (got $already_merged_findings)"; exit 1; }
SATISFIED_HOLDS_EXIT=1 SATISFIED_HOLDS_OUTPUT='satisfied-holds: 3 bead(s) whose comments bd would not return: fortkit-a fortkit-b fortkit-c
satisfied-holds: 1 satisfied, 0 partial, over 4 beads (description+notes+design+comments).' run_case "$empty"
[ "$(read_sweep_findings satisfied-holds.py)" = 1 ] && echo 'PASS satisfied-holds comment-refusal fixture reports one finding' || { echo 'FAIL satisfied-holds comment-refusal fixture did not report one finding'; exit 1; }
if [ "${HARNESS_T4_RESTORATION_PROBE:-}" != 1 ]; then
  pre_t4_fixture="$here/sweep-pre-t4-drop.fixture.py"
  pre_t4_fixture_sha256='7f75fd78534e2475b26953eb2d6b980b90e8e82c911a620eed0c7c638f46e60a'
  actual_pre_t4_fixture_sha256="$(sha256sum "$pre_t4_fixture" | awk '{print $1}')"
  [ "$actual_pre_t4_fixture_sha256" = "$pre_t4_fixture_sha256" ] || {
    echo "FAIL RED arm: pre-T4 fixture sha256 $actual_pre_t4_fixture_sha256, expected $pre_t4_fixture_sha256"; exit 1
  }
  if pre_t4_fixture_output="$(HARNESS_T4_RESTORATION_PROBE=1 SWEEP_SRC="$pre_t4_fixture" "$here/sweep-harness.sh" 2>&1)"; then
    echo 'FAIL RED arm: pre-initf.2.1 T4 lines unexpectedly passed'; exit 1
  fi
  printf '%s\n' "$pre_t4_fixture_output" | sed 's/^/ |/'
  printf '%s\n' "$pre_t4_fixture_output" | grep -Fq 'FAIL thin depth stockable fixture set work or T4' || {
    echo 'FAIL RED arm: pre-initf.2.1 T4 lines did not fail the stockable fixture'; exit 1
  }
  echo 'RED arm: pre-initf.2.1 T4 lines make the stockable fixture fail as required (fixture 9510b775~1:sweep.py)'
fi
[ "$(read_misrouted_exit)" = 0 ] && echo 'PASS misrouted sweep receives explicit ROOT' || { echo 'FAIL misrouted sweep did not receive explicit ROOT'; exit 1; }
missing_root_source="$work/sweep-without-misrouted-root.py"
sed 's/env={\*\*os.environ, "ROOT": str(ROOT)}/env=os.environ/' "$source" > "$missing_root_source"
ROOT= SWEEP_ROOT="$repo" BOARD_JSON="$empty" BD_LOG="$work/bd.log" QUEUE_LOG="$work/queue.log" MAYOR_STATUS_STATE="$state" PATH="$stub:$PATH" python3 "$missing_root_source"
if [ "$(read_misrouted_exit)" = 3 ]; then
  echo 'RED arm: missing misrouted ROOT handoff exits 3 as required'
else
  echo 'FAIL RED arm: missing misrouted ROOT handoff did not exit 3'; exit 1
fi
# Isolate this arm from the harness's stdin if sweep.py regresses.
BD_DOWN=1 BOARD_JSON="$empty" BD_LOG="$work/bd.log" QUEUE_LOG="$work/queue.log" MAYOR_STATUS_STATE="$state" SWEEP_ROOT="$repo" PATH="$stub:$PATH" timeout 10 python3 "$repo/scripts/unattended-fleet/sweep.py" </dev/null
[ "$(read_work)" = None ] && echo 'PASS bd refusal writes could-not-ask, never no-work' || { echo 'FAIL bd refusal became no-work'; exit 1; }
SWEEP_FORCE_WORK_EXISTS=0 BOARD_JSON="$mayor" BD_LOG="$work/bd.log" QUEUE_LOG="$work/queue.log" MAYOR_STATUS_STATE="$state" SWEEP_ROOT="$repo" PATH="$stub:$PATH" python3 "$repo/scripts/unattended-fleet/sweep.py"
[ "$(read_work)" = True ] && echo 'PASS production sweep ignores SWEEP_FORCE_WORK_EXISTS' || { echo 'FAIL production sweep read SWEEP_FORCE_WORK_EXISTS'; exit 1; }
forced_source="$work/sweep-force-work-exists.py"
sed '/def work_bit(inbox):/a\    return False, ["TEST-FORCED"]' "$source" > "$forced_source"
cp -f "$forced_source" "$repo/scripts/unattended-fleet/sweep.py"
BOARD_JSON="$mayor" BD_LOG="$work/bd.log" QUEUE_LOG="$work/queue.log" MAYOR_STATUS_STATE="$state" SWEEP_ROOT="$repo" PATH="$stub:$PATH" python3 "$repo/scripts/unattended-fleet/sweep.py"
[ "$(read_work)" = False ] && echo 'PASS harness-only source seam forces work bit' || { echo 'FAIL harness-only source seam did not force work bit'; exit 1; }
cp -f "$source" "$repo/scripts/unattended-fleet/sweep.py"
cat > "$repo/scripts/unattended-fleet/satisfied-holds.py" <<'EOF'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

Path(os.environ["SATISFIED_HOLDS_STDIN_MARKER"]).touch()
sys.stdin.read()
print("satisfied-holds: 0 satisfied, 0 partial, over 0 beads (description+notes+design+comments).")
EOF
chmod +x "$repo/scripts/unattended-fleet/satisfied-holds.py"
stdin_marker="$work/satisfied-holds-stdin.marker"
# The write probes recurse into this harness with injected source.  Run the
# stdin control only in the parent so the red arm isolates stdin, not a write.
if [ "${HARNESS_WRITE_PROBE:-}" != 1 ]; then
  if { yes || :; } | timeout 10 env SATISFIED_HOLDS_STDIN_MARKER="$stdin_marker" BOARD_JSON="$empty" BD_LOG="$work/bd.log" QUEUE_LOG="$work/queue.log" MAYOR_STATUS_STATE="$state" SWEEP_ROOT="$repo" PATH="$stub:$PATH" python3 "$repo/scripts/unattended-fleet/sweep.py"; then
    [ -f "$stdin_marker" ] && [ -f "$state/status.json" ] && echo 'PASS stdin-reading checker executes with DEVNULL and writes a record' || { echo 'FAIL stdin-reading checker did not execute or write a record'; exit 1; }
  else
    echo 'FAIL stdin-reading checker blocked or sweep failed'; exit 1
  fi
  stdin_inherited_source="$repo/scripts/unattended-fleet/sweep-inherits-stdin.py"
  sed 's/            kwargs\["stdin"\] = subprocess.DEVNULL/            pass/' "$source" > "$stdin_inherited_source"
  rm -f "$stdin_marker"
  if { yes || :; } | timeout 10 env SATISFIED_HOLDS_STDIN_MARKER="$stdin_marker" BOARD_JSON="$empty" BD_LOG="$work/bd.log" QUEUE_LOG="$work/queue.log" MAYOR_STATUS_STATE="$state" SWEEP_ROOT="$repo" PATH="$stub:$PATH" python3 "$stdin_inherited_source"; then
    echo 'FAIL RED arm: stdin-inheriting sweep unexpectedly passed'; exit 1
  else
    stdin_probe_exit=$?
  fi
  if [ -f "$stdin_marker" ]; then stdin_marker_present=1; else stdin_marker_present=0; fi
  [ "$stdin_probe_exit" = 124 ] && [ "$stdin_marker_present" = 1 ] && echo 'RED arm: reverting sweep.py stdin=DEVNULL times out after the Python stdin stub starts as required' || {
    echo "FAIL RED arm: stdin-inheriting sweep exit was $stdin_probe_exit; stdin stub marker present=$stdin_marker_present"; exit 1
  }
fi
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["schema"] == "manyhalls/unattended-mayor-loop/status/v1"; assert isinstance(d["errors"], list)' "$state/status.json"
if grep -Fq 'WRITE OR UNKNOWN ATTEMPT:' "$work/bd.log" "$work/stderr.log"; then
  echo "FAIL bd stub refusal marker reached${HARNESS_WRITE_PROBE_NAME:+ for $HARNESS_WRITE_PROBE_NAME}"; exit 1
fi
if awk '{ i = 1; while ($i == "-C") i += 2; if ($i != "list" && $i != "comments") exit 1 }' "$work/bd.log"; then
  :
else
  echo 'FAIL bd stub log includes a non-read command'; exit 1
fi
echo 'PASS status record is schema-shaped and bd stub recorded only reads'
# Skip the write-arm loop inside a write-probe child so the probe does not
# recurse.
if [ "${HARNESS_WRITE_PROBE:-}" != 1 ]; then
  for write_arm in \
    'injected bare bd write|["bd", "update", "fortkit-test", "--notes", "forbidden"]' \
    'injected -C bd write|["bd", "-C", str(ROOT), "update", "X"]'; do
    write_name="${write_arm%%|*}"
    write_args="${write_arm#*|}"
    write_source="$work/sweep-writes.py"
    cp -f "$source" "$write_source"
    sed -i "/def main():/a\\    run($write_args)" "$write_source"
    if write_output="$(HARNESS_WRITE_PROBE=1 HARNESS_WRITE_PROBE_NAME="$write_name" SWEEP_SRC="$write_source" "$here/sweep-harness.sh" 2>&1)"; then
      echo "FAIL RED arm: $write_name unexpectedly passed"; exit 1
    fi
    printf '%s\n' "$write_output" | sed 's/^/ |/'
    printf '%s\n' "$write_output" | grep -Fqx "FAIL bd stub refusal marker reached for $write_name" || {
      echo "FAIL RED arm: $write_name injection broke before its refusal marker"; exit 1
    }
  done
  echo 'RED arm: injected bare and -C bd writes fail through their distinct refusal markers as required'
fi
