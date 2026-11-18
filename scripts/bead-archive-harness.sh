#!/bin/bash
# Hermetic regression harness for scripts/bead-archive.sh.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; subject="${BEAD_ARCHIVE_SRC:-$here/bead-archive.sh}"
[ -f "$subject" ] || { echo "HARNESS REFUSES: subject is missing: $subject" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
repo="$work/repo"; stub="$work/stub"; state="$work/state.jsonl"
mkdir -p "$repo/.beads" "$repo/scripts" "$repo/fort/annals" "$stub"; git -C "$repo" init -q -b main
git -C "$repo" config user.email harness@example.test
git -C "$repo" config user.name harness
subject_to_run="$subject"
if [ "${BEAD_ARCHIVE_SKIP_DRY_PAYLOAD_CHECK:-0}" = 1 ] || [ "${BEAD_ARCHIVE_SKIP_COMMIT_GATE:-0}" = 1 ] || [ "${BEAD_ARCHIVE_SKIP_PRUNE_SUMMARY:-0}" = 1 ] || [ "${BEAD_ARCHIVE_SKIP_RETRY_DEDUP:-0}" = 1 ] || [ "${BEAD_ARCHIVE_SKIP_RETRY_SUMMARY:-0}" = 1 ] || [ "${BEAD_ARCHIVE_SKIP_EMPTY_SELECTION:-0}" = 1 ]; then
  subject_to_run="$work/bead-archive-inverted.sh"
  cp -f "$subject" "$subject_to_run"
  [ "${BEAD_ARCHIVE_SKIP_DRY_PAYLOAD_CHECK:-0}" != 1 ] || sed -i '/^[[:space:]]*verify_archive "[$]archive_payload" exact$/d' "$subject_to_run"
  [ "${BEAD_ARCHIVE_SKIP_COMMIT_GATE:-0}" != 1 ] || sed -i '/^[[:space:]]*if \[ -n "[$](git -C "[$]root" status --porcelain -- "[$]archive_relative")" \]; then/,/^[[:space:]]*fi$/d' "$subject_to_run"
  [ "${BEAD_ARCHIVE_SKIP_PRUNE_SUMMARY:-0}" != 1 ] || sed -i '/^[[:space:]]*printf '\''bead-archive: prune failed after %s ids; remaining ids: %s\\n'\''/d' "$subject_to_run"
  [ "${BEAD_ARCHIVE_SKIP_RETRY_SUMMARY:-0}" != 1 ] || sed -i '/^[[:space:]]*printf '\''bead-archive: archived %s beads to %s (%s bytes appended; appended ids: %s) and pruned verified ids\\n'\''/d' "$subject_to_run"
  [ "${BEAD_ARCHIVE_SKIP_RETRY_SUMMARY:-0}" != 1 ] || sed -i '/^[[:space:]]*printf '\''bead-archive: appended %s bytes for ids: %s\\n'\''/d' "$subject_to_run"
  [ "${BEAD_ARCHIVE_SKIP_EMPTY_SELECTION:-0}" != 1 ] || sed -i '/^if \[ "[$]selected_count" -eq 0 \]; then$/,/^fi$/d' "$subject_to_run"
  if [ "${BEAD_ARCHIVE_SKIP_RETRY_DEDUP:-0}" = 1 ]; then
    # shellcheck disable=SC2016 # The copied subject must expand $work at runtime.
    sed -i '/^[[:space:]]*prepare_append_payload "[$]archive_file" "[$]archive_payload" "[$]appended_ids_file"$/a\  archive_payload="$work/archive.jsonl.gz"' "$subject_to_run"
  fi
fi
cp -f "$subject_to_run" "$repo/scripts/bead-archive.sh"; chmod 755 "$repo/scripts/bead-archive.sh"
python3 - "$state" <<'PY'
import datetime as dt,json,sys
now=dt.datetime.now(dt.timezone.utc)
def row(bead_id,status,days,labels=[]):
 stamp=(now-dt.timedelta(days=days)).isoformat().replace('+00:00','Z'); r={'id':bead_id,'status':status,'created_at':stamp,'labels':labels,'comments':[{'body':'kept'}],'dependencies':[]}
 if status=='closed': r['closed_at']=stamp
 return r
with open(sys.argv[1],'w') as f:
 for r in [row('old','closed',61),row('new','closed',2),row('open','open',61),row('pinned','closed',61,['pinned']),row('record','closed',61,['record']),row('standing','closed',61,['standing'])]: f.write(json.dumps(r)+'\n')
PY
cat > "$stub/bd" <<'SH'
#!/bin/bash
set -euo pipefail
while [ "$#" -gt 0 ] && { [ "$1" = -C ] || [ "$1" = --directory ]; }; do shift 2; done
command="$1"; shift
case "$command" in
 export) while [ "$#" -gt 0 ]; do if [ "$1" = -o ] || [ "$1" = --output ]; then cp -f "$HARNESS_STATE" "$2"; exit 0; fi; shift; done; cat "$HARNESS_STATE";;
 prune) pattern=""; while [ "$#" -gt 0 ]; do if [ "$1" = --pattern ]; then pattern="$2"; shift 2; else shift; fi; done
  if [ "${HARNESS_FAIL_PRUNE_ID:-}" = "$pattern" ]; then exit 79; fi
  python3 - "$HARNESS_STATE" "$pattern" <<'PY'
import json,sys
path,pattern=sys.argv[1:]; rows=[json.loads(x) for x in open(path) if x.strip()]
with open(path,'w') as f:
 for row in rows:
  if not (row.get('id')==pattern and row.get('status')=='closed'): f.write(json.dumps(row)+'\n')
PY
  ;;
 *) echo "unexpected bd command: $command" >&2; exit 3;; esac
SH
chmod 755 "$stub/bd"
cat > "$stub/gzip" <<'SH'
#!/bin/bash
if [ "${HARNESS_MUTATE_GZIP:-0}" = 1 ] && [ "$1" = -c ]; then
  /usr/bin/gzip "$@" | /usr/bin/gzip -cd | sed 's/"kept"/"changed"/' | /usr/bin/gzip -c
else
  exec /usr/bin/gzip "$@"
fi
SH
chmod 755 "$stub/gzip"
cat > "$stub/cat" <<'SH'
#!/bin/bash
if [ "${HARNESS_CORRUPT_APPEND:-0}" = 1 ] && [[ "$1" == */append.jsonl.gz ]]; then
  /bin/cat "$1"
  printf 'corrupt appended archive'
else
  exec /bin/cat "$@"
fi
SH
chmod 755 "$stub/cat"
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }; no(){ echo "  FAIL  $1"; fail=$((fail+1)); }
has(){ python3 - "$state" "$1" <<'PY'
import json,sys
print(any(json.loads(x).get('id')==sys.argv[2] for x in open(sys.argv[1]) if x.strip()))
PY
}
run(){ HARNESS_STATE="$state" PATH="$stub:$PATH" "$repo/scripts/bead-archive.sh" --older-than 60d "$@"; }
run --dry-run > "$work/dry.out"
if [ "$(has old)" = True ] && [ ! -e "$repo/fort/annals/beads-archive-$(date -u +%Y-%m).jsonl.gz" ]; then ok 'dry-run keeps tracker and annals unchanged'; else no 'dry-run mutated tracker or annals'; fi
if HARNESS_MUTATE_GZIP=1 run --dry-run > "$work/dry-payload.out" 2>&1; then no 'dry-run payload mismatch returns nonzero'; else ok 'dry-run payload mismatch returns nonzero'; fi
run > "$work/commit-gate.out" 2>&1 && no 'commit gate returns nonzero before pruning'
if [ "$(has old)" = True ] && rg -F "git -C \"$repo\" add -- \"fort/annals/beads-archive-$(date -u +%Y-%m).jsonl.gz\"" "$work/commit-gate.out" >/dev/null; then ok 'commit gate preserves ids and prints path-scoped commit command'; else no 'commit gate preserves ids and prints path-scoped commit command'; fi
if ! rg -F 'No such file or directory' "$work/commit-gate.out" >/dev/null; then ok 'first archive run has no missing archive-file noise'; else no 'first archive run has no missing archive-file noise'; fi
git -C "$repo" add -- "fort/annals/beads-archive-$(date -u +%Y-%m).jsonl.gz"
git -C "$repo" commit -qm 'archive closed beads'
python3 - "$state" <<'PY'
import json,sys
path=sys.argv[1]; rows=[json.loads(line) for line in open(path) if line.strip()]
for row in rows:
 if row['id']=='old': row['comments'].append({'body':'changed after archive'})
rows.append({'id':'crossed','status':'closed','closed_at':'2020-01-01T00:00:00Z','labels':[],'comments':[]})
with open(path,'w') as output:
 for row in rows: output.write(json.dumps(row)+'\n')
PY
run > "$work/crossed-commit-gate.out" 2>&1 && no 'retry with newly eligible bead returns to commit gate'
archive="$repo/fort/annals/beads-archive-$(date -u +%Y-%m).jsonl.gz"
git -C "$repo" add -- "$archive"
if ! git -C "$repo" diff --cached --quiet; then git -C "$repo" commit -qm 'archive crossed candidate'; fi
if run > "$work/crossed-retry.out" 2>&1; then
 if [ "$(has old)" = False ] && [ "$(has crossed)" = False ] && [ "$(has new)" = True ] && [ "$(has open)" = True ] && [ "$(has pinned)" = True ] && [ "$(has record)" = True ] && [ "$(has standing)" = True ]; then ok 'only eligible old closed beads are pruned'; else no 'eligible selection preserves newer, open, pinned, record, and standing beads'; fi
 if gzip -cd "$archive" | python3 -c 'import json,sys; rows=[json.loads(x) for x in sys.stdin]; old=[row for row in rows if row["id"]=="old"]; assert [row["id"] for row in rows]==["old","old","crossed"]; assert old[-1]["comments"][-1]=={"body":"changed after archive"}' ; then ok 'changed archived record appends current row and prunes on retry'; else no 'changed archived record appends current row and prunes on retry'; fi
 if command grep -E 'appended [1-9][0-9]* bytes for ids: old crossed' "$work/crossed-commit-gate.out" >/dev/null; then ok 'retry summary names appended ids and reports appended bytes'; else no 'retry summary names appended ids and reports appended bytes'; fi
else
 no 'changed archived record appends current row and prunes on retry'
 no 'retry summary names appended ids and reports appended bytes'
fi
empty_state="$work/empty-state.jsonl"; : > "$empty_state"
empty_repo="$work/empty-repo"; mkdir -p "$empty_repo/.beads" "$empty_repo/scripts" "$empty_repo/fort/annals"; git -C "$empty_repo" init -q -b main
cp -f "$repo/scripts/bead-archive.sh" "$empty_repo/scripts/bead-archive.sh"; chmod 755 "$empty_repo/scripts/bead-archive.sh"
git -C "$empty_repo" config user.email harness@example.test; git -C "$empty_repo" config user.name harness
git -C "$empty_repo" add -- scripts/bead-archive.sh; git -C "$empty_repo" commit -qm 'add archive script'
if HARNESS_STATE="$empty_state" PATH="$stub:$PATH" "$empty_repo/scripts/bead-archive.sh" --older-than 60d > "$work/empty.out" 2>&1 && [ ! -e "$empty_repo/fort/annals/beads-archive-$(date -u +%Y-%m).jsonl.gz" ] && [ -z "$(git -C "$empty_repo" status --porcelain)" ]; then ok 'empty eligible set exits zero without archive or git changes'; else no 'empty eligible set exits zero without archive or git changes'; fi
nonempty_empty_state="$work/nonempty-empty-state.jsonl"
python3 - "$nonempty_empty_state" <<'PY'
import datetime as dt, json, sys
now = dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00', 'Z')
rows = [
 {'id':'too-new','status':'closed','closed_at':now,'labels':[]},
 {'id':'pinned-old','status':'closed','closed_at':'2020-01-01T00:00:00Z','labels':['pinned']},
 {'id':'still-open','status':'open','created_at':'2020-01-01T00:00:00Z','labels':[]},
]
with open(sys.argv[1], 'w') as output:
 for row in rows: output.write(json.dumps(row) + '\n')
PY
if HARNESS_STATE="$nonempty_empty_state" PATH="$stub:$PATH" "$empty_repo/scripts/bead-archive.sh" --older-than 60d > "$work/nonempty-empty.out" 2>&1 && [ ! -e "$empty_repo/fort/annals/beads-archive-$(date -u +%Y-%m).jsonl.gz" ] && [ -z "$(git -C "$empty_repo" status --porcelain)" ]; then ok 'non-empty export with no eligible beads exits without archive or git changes'; else no 'non-empty export with no eligible beads exits without archive or git changes'; fi
python3 - "$state" <<'PY'
import json,sys
with open(sys.argv[1],'a') as f:
 for bead_id in ['partial-first','partial-fail','partial-last']:
  f.write(json.dumps({'id':bead_id,'status':'closed','closed_at':'2020-01-01T00:00:00Z','labels':[],'comments':[]})+'\n')
PY
run > "$work/partial-commit-gate.out" 2>&1 && no 'partial prune archive commit gate returns nonzero'
git -C "$repo" add -- "$archive"
if ! git -C "$repo" diff --cached --quiet; then git -C "$repo" commit -qm 'archive partial prune candidate'; fi
if HARNESS_FAIL_PRUNE_ID=partial-fail run > "$work/partial-prune.out" 2>&1; then no 'partial prune failure returns nonzero'; elif rg -F 'prune failed after 1 ids; remaining ids: partial-fail partial-last' "$work/partial-prune.out" >/dev/null && [ "$(has partial-first)" = False ] && [ "$(has partial-fail)" = True ] && [ "$(has partial-last)" = True ]; then ok 'partial prune reports pruned and remaining ids'; else no 'partial prune reports pruned and remaining ids'; fi
python3 - "$state" <<'PY'
import json,sys
with open(sys.argv[1],'a') as f: f.write(json.dumps({'id':'failure-old','status':'closed','closed_at':'2020-01-01T00:00:00Z','labels':[],'comments':[]})+'\n')
PY
if HARNESS_CORRUPT_APPEND=1 run > "$work/failure.out" 2>&1; then no 'verification failure returns nonzero'; elif [ "$(has failure-old)" = True ] && rg -F 'truncate back to byte offset' "$work/failure.out" >/dev/null; then ok 'verification failure reports recovery offset and prunes nothing'; else no 'verification failure reports recovery offset and prunes nothing'; fi
if [ "${BEAD_ARCHIVE_SKIP_DRY_PAYLOAD_CHECK:-0}" != 1 ] && [ "${BEAD_ARCHIVE_SKIP_COMMIT_GATE:-0}" != 1 ] && [ "${BEAD_ARCHIVE_SKIP_PRUNE_SUMMARY:-0}" != 1 ] && [ "${BEAD_ARCHIVE_SKIP_RETRY_DEDUP:-0}" != 1 ] && [ "${BEAD_ARCHIVE_SKIP_RETRY_SUMMARY:-0}" != 1 ] && [ "${BEAD_ARCHIVE_SKIP_EMPTY_SELECTION:-0}" != 1 ]; then
  control_red() {
    local toggle="$1" log="$2" assertion="$3" label="$4"
    if env "$toggle"=1 BEAD_ARCHIVE_SRC="$subject" bash "$0" > "$log" 2>&1; then
      no "CONTROL RED $label removal made the harness pass"
    elif rg -F "FAIL  $assertion" "$log" >/dev/null && command grep -E '^RESULT [0-9]+ pass / [0-9]+ fail$' "$log" >/dev/null; then
      ok "CONTROL RED $label removal makes its assertion fail and prints RESULT tally"
    else
      no "CONTROL RED $label removal did not produce its assertion and RESULT tally"
    fi
  }
  control_red BEAD_ARCHIVE_SKIP_DRY_PAYLOAD_CHECK "$work/red-payload.out" 'dry-run payload mismatch returns nonzero' 'payload check'
  control_red BEAD_ARCHIVE_SKIP_COMMIT_GATE "$work/red-commit-gate.out" 'commit gate preserves ids and prints path-scoped commit command' 'commit gate'
  control_red BEAD_ARCHIVE_SKIP_PRUNE_SUMMARY "$work/red-prune-summary.out" 'partial prune reports pruned and remaining ids' 'prune summary'
  control_red BEAD_ARCHIVE_SKIP_RETRY_DEDUP "$work/red-retry-dedup.out" 'changed archived record appends current row and prunes on retry' 'retry dedup'
  control_red BEAD_ARCHIVE_SKIP_RETRY_SUMMARY "$work/red-retry-summary.out" 'retry summary names appended ids and reports appended bytes' 'retry summary'
  control_red BEAD_ARCHIVE_SKIP_EMPTY_SELECTION "$work/red-empty-selection.out" 'empty eligible set exits zero without archive or git changes' 'empty selection'
  control_red BEAD_ARCHIVE_SKIP_EMPTY_SELECTION "$work/red-nonempty-empty-selection.out" 'non-empty export with no eligible beads exits without archive or git changes' 'non-empty export selection'
fi
echo "RESULT $pass pass / $fail fail"; [ "$fail" -eq 0 ]
