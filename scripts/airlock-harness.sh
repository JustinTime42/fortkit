#!/bin/bash
# Airlock harness (Proofdelve ForgeOs-x6hq, Proofdelve ForgeOs-5fyc). Drives the REAL
# fort/scripts/airlock.sh (or AIRLOCK_SH=<candidate>) against a FIXTURE fort
# under AIRLOCK_ROOT: a git repo with its own operations.json, a stub emit.sh
# that logs every event as one line, and stub operation scripts that exit 0 or
# 1. No real request, result or event is touched. Asserts the property the two
# beads are about: a completed operation announces itself under the category
# its table declares, a failed one does not, an operation that declares nothing
# announces nothing, and a run made by hand is recordable and legible as one.
# Against the pre-x6hq airlock.sh the `deploy` cases FAIL (it emits only
# airlock.result) and `announce` is an unknown verb (exit 2): the positive
# control. Refuses (exit 3) when the fixture cannot be built.
# Proofdelve ForgeOs-mbv54 (Regent edict 2026-10-15) adds cases 12-17: a pinned operation
# runs the approved commit whatever HEAD has become, refuses a bad pin as a
# recorded result, and the host runner (fort/scripts/airlock-runner.sh, or
# AIRLOCK_RUNNER_SH) runs only store-approved requests; and Proofdelve ForgeOs-72ot.1.1
# adds 18-20 (the snapshot race by a jq shim, non-object store lines, the
# snapshot trap).
set -uo pipefail
here="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
AIRLOCK_SH="${AIRLOCK_SH:-$here/fort/scripts/airlock.sh}"
[ -f "$AIRLOCK_SH" ] || { echo "HARNESS REFUSES: no airlock.sh at $AIRLOCK_SH" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# A LAUNCHER THAT DOES NOT HONOUR AIRLOCK_ROOT MUST NEVER BE RUN HERE AS IS: it
# would file requests and results in the REAL fort/airlock and emit into the
# real stream (the 2026-08-06 Herald-smoke scar: a probe seeding the record it
# probes). The pre-x6hq file is that launcher. So it is RENDERED to scratch
# with its root line repointed at the fixture (the mayor.sh probe pattern,
# 2026-08-13), asserted to have exactly one such line, and driven from there --
# which is what lets the RED-before be a FAIL rather than a refusal.
# shellcheck disable=SC2016  # the single quotes are the point: literal source spellings of airlock.sh's own root= line
if ! grep -q 'AIRLOCK_ROOT' "$AIRLOCK_SH"; then
  n=$(grep -c '^root="\$(git -C ' "$AIRLOCK_SH"); [ "$n" -eq 1 ] || { echo "HARNESS REFUSES: $AIRLOCK_SH honours no AIRLOCK_ROOT and has $n root= lines to repoint (expected 1)" >&2; exit 3; }
  sed 's|^root="\$(git -C .*$|root="$AIRLOCK_ROOT"|' "$AIRLOCK_SH" > "$work/airlock-repointed.sh"
  grep -q '^root="\$AIRLOCK_ROOT"$' "$work/airlock-repointed.sh" || { echo "HARNESS REFUSES: the root repoint did not land" >&2; exit 3; }
  echo "note: $AIRLOCK_SH honours no AIRLOCK_ROOT (pre-x6hq); driving a scratch copy with root= repointed at the fixture"
  AIRLOCK_SH="$work/airlock-repointed.sh"
fi
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }

mkfix() { # $1 name -> prints fixture root
  local r="$work/$1"
  mkdir -p "$r/fort/airlock" "$r/fort/scripts" "$r/scripts"
  git -C "$r" init -q -b main; git -C "$r" config user.email h@h; git -C "$r" config user.name H
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/emitted"\n' "$r" > "$r/fort/scripts/emit.sh"; chmod +x "$r/fort/scripts/emit.sh"
  printf '#!/bin/bash\necho ran-ok\nexit 0\n' > "$r/scripts/op-ok.sh"
  printf '#!/bin/bash\necho ran-bad\nexit 1\n' > "$r/scripts/op-bad.sh"
  # A pinned operation's script reports what tree it ran from (mbv54).
  # shellcheck disable=SC2016  # literal $(...) written into the fixture script
  printf '#!/bin/bash\necho "head=$(git rev-parse HEAD)"\necho "marker=$(cat marker.txt)"\n[ -L .env.fix ] && echo "envlink=$(cat .env.fix)"\necho "pwd=$PWD"\nexit 0\n' > "$r/scripts/op-pin.sh"
  echo X > "$r/marker.txt"
  # Proofdelve ForgeOs-emshb: an operation script that reports exactly what reached it.
  # shellcheck disable=SC2016  # literal $... written into the fixture script
  printf '#!/bin/bash\necho "pwd=$PWD"\necho "script=$0"\necho "argc=$#"\nfor a in "$@"; do printf "arg=[%%s]\\n" "$a"; done\n[ -e /proc/$$/fd/8 ] && echo "fd8=OPEN" || echo "fd8=closed"\necho "preview: ${FIX_URL:-http://localhost:5173}"\nexit 0\n' > "$r/scripts/op-args.sh"
  cat > "$r/fort/airlock/operations.json" <<'J'
{"operations":[
 {"name":"hostcheck","script":"scripts/op-args.sh","requires_approval":false,"auto_run":true,"runs_from":"bead-worktree","params":{"target":"main|(fortkit-)?[a-z0-9]+(\\.[0-9]+)*","filter":"[A-Za-z0-9._~=!&|() ]{1,200}","mutate":"(([A-Za-z0-9_][A-Za-z0-9._-]*/)*[A-Za-z0-9_][A-Za-z0-9._-]*\\.patch)?"},"path_params":["mutate"],"args":["$target","$filter",{"when":"mutate","args":["--mutate","$mutate"]}],"description":"fixture: host-test shaped"},
 {"name":"show","script":"scripts/op-args.sh","requires_approval":true,"runs_from":"bead-worktree","params":{"target":"main|(fortkit-)?[a-z0-9]+(\\.[0-9]+)*","keep_data":"(true|false)?"},"args":["$target",{"when":"keep_data","equals":"true","args":["--keep-data"]}],"result_url":"^preview: (?<url>http://\\S+)$","description":"fixture: preview shaped"},
 {"name":"greedy","script":"scripts/op-ok.sh","requires_approval":true,"auto_run":true,"description":"fixture: declares auto_run beside requires_approval true"},
 {"name":"deploy-ok","script":"scripts/op-ok.sh","requires_approval":true,"emits":{"category":"deploy","target":"staging"},"description":"fixture"},
 {"name":"deploy-bad","script":"scripts/op-bad.sh","requires_approval":true,"emits":{"category":"deploy","target":"staging"},"description":"fixture"},
 {"name":"scan","script":"scripts/op-ok.sh","requires_approval":false,"description":"fixture: declares no emits"},
 {"name":"deploy-pin","script":"scripts/op-pin.sh","requires_approval":true,"runs_from":"pinned-commit","env_files":[".env.fix"],"emits":{"category":"deploy","target":"staging"},"description":"fixture: pinned"}
]}
J
  git -C "$r" add -A >/dev/null; git -C "$r" commit -qm base
  printf '%s' "$r"
}
# Every fixture brings its own Overseer store (Proofdelve ForgeOs-72ot.1): AIRLOCK_STORE
# points inside the fixture, so no case can append to the real civ-keep record.
air() { AIRLOCK_ROOT="$1" AIRLOCK_STORE="$1/.store" AIRLOCK_WORKTREES="$1-wt" FORT_ACTOR="emrith" FORT_SEAT=mayor bash "$AIRLOCK_SH" "${@:2}"; }
cat_events() { local r="$1" c="$2"; grep -c "^$c " "$r/emitted" 2>/dev/null || true; }   # the CATEGORY at column one, never the word
last_id() { find "$1/fort/airlock/requests" -maxdepth 1 -name '*.json' -printf '%f\n' 2>/dev/null | sort | tail -1 | sed 's/\.json$//'; }

# 1. a completed operation with an emits block announces itself under its category, beside airlock.result
r=$(mkfix f1) || exit 3
air "$r" request deploy-ok --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null; air "$r" run "$id" >/dev/null 2>&1
head=$(git -C "$r" rev-parse HEAD)
if [ "$(cat_events "$r" deploy)" -eq 1 ] && [ "$(cat_events "$r" airlock.result)" -eq 1 ] \
   && grep -q "^deploy .* -a overseer .* -t staging .*\"airlock\":\"$id\".*\"commit\":\"$head\".*\"hand\":false" "$r/emitted" \
   && [ "$(jq -r .status "$r/fort/airlock/requests/$id.json")" = completed ]; then
  ok "x6hq: a completed deploy-shaped operation emits ONE deploy event (actor overseer, target from the table, the request id, the checkout's HEAD, hand:false) beside airlock.result, and the request reads completed"
else no "x6hq: the completed operation did not announce itself" "deploy=$(cat_events "$r" deploy) result=$(cat_events "$r" airlock.result) $(grep '^deploy' "$r/emitted" 2>/dev/null | head -1)"; fi

# 2. a FAILED operation emits airlock.result and NOT its category (a failed deploy is not a deploy)
r=$(mkfix f2) || exit 3
air "$r" request deploy-bad --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null; air "$r" run "$id" >/dev/null 2>&1
if [ "$(cat_events "$r" deploy)" -eq 0 ] && grep -q '^airlock.result .*"exit":1' "$r/emitted" && [ "$(jq -r .status "$r/fort/airlock/requests/$id.json")" = failed ]; then
  ok "x6hq: a FAILED operation emits airlock.result with exit 1 and NO deploy event, and the request reads failed"
else no "x6hq: a failed operation announced itself, or lost its result" "deploy=$(cat_events "$r" deploy) $(grep '^airlock.result' "$r/emitted" 2>/dev/null)"; fi

# 3. an operation that declares no emits announces nothing beyond airlock.result (feedback-scan's shape)
r=$(mkfix f3) || exit 3
air "$r" request scan --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" run "$id" >/dev/null 2>&1
if [ "$(cat_events "$r" deploy)" -eq 0 ] && [ "$(cat_events "$r" airlock.result)" -eq 1 ] && [ "$(jq -r .status "$r/fort/airlock/requests/$id.json")" = completed ]; then
  ok "x6hq: an operation with no emits block completes with airlock.result alone (the vocabulary is only widened where the table says so)"
else no "x6hq: an undeclared operation announced something, or did not complete" "deploy=$(cat_events "$r" deploy) result=$(cat_events "$r" airlock.result)"; fi

# 4. a run made BY HAND is recordable: announce writes a request+result pair marked hand:true and emits the category
r=$(mkfix f4) || exit 3
out=$(air "$r" announce deploy-ok --reason "deployed by hand from the terminal" --commit deadbeefcafe 2>&1); rc=$?
id=$(last_id "$r" 2>/dev/null)
if [ "$rc" -eq 0 ] && [ -n "$id" ] && [ "$(jq -r .hand "$r/fort/airlock/requests/$id.json")" = true ] && [ "$(jq -r .hand "$r/fort/airlock/results/$id.json")" = true ] \
   && [ "$(jq -r .exit_code "$r/fort/airlock/results/$id.json")" = 0 ] && [ "$(cat_events "$r" deploy)" -eq 1 ] \
   && grep -q '^deploy .*BY HAND.*deadbeef.*"commit":"deadbeefcafe","hand":true' "$r/emitted" && [ "$(cat_events "$r" airlock.result)" -eq 0 ]; then
  ok "5fyc: announce records a hand run as a request+result pair marked hand:true (no airlock.result: nothing ran here) and emits the deploy event saying BY HAND with the named commit"
else no "5fyc: a hand run was not recorded as one" "rc=$rc id=$id out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200) deploy=$(cat_events "$r" deploy)"; fi
# 4b. and the hand record is legible from list --all and show. Captured, then
# tested: `air ... | grep -q` under pipefail scores a MATCH as failure when grep
# exits early and SIGPIPEs the producer (civ/remember.md, 2026-08-05).
lst="$(air "$r" list --all 2>/dev/null)"; shw="$(air "$r" show "$id" 2>/dev/null)"
if [ "$rc" -eq 0 ] && grep -q "completed  deploy-ok" <<<"$lst" && [ "$(grep -c '"hand": true' <<<"$shw")" -eq 2 ]; then
  ok "5fyc: the hand run appears in list --all as completed and show prints hand:true on both halves"
else no "5fyc: the hand record is not legible through list/show" "$(air "$r" list --all 2>&1 | head -2 | tr '\n' '|')"; fi

# 5. announce refuses an operation that declares nothing, and refuses without --reason
r=$(mkfix f5) || exit 3
air "$r" announce scan --reason x >/dev/null 2>&1; rc1=$?; air "$r" announce deploy-ok >/dev/null 2>&1; rc2=$?
if [ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ] && [ "$(find "$r/fort/airlock/requests" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)" -eq 0 ]; then
  ok "5fyc: announce refuses an operation with no emits block (rc $rc1) and refuses without --reason (rc $rc2), writing no record either way"
else no "5fyc: announce accepted what it should refuse" "rc1=$rc1 rc2=$rc2 records=$(find "$r/fort/airlock/requests" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l)"; fi

# 6. the shipped table: deploy-staging declares deploy/staging, feedback-scan declares nothing
ops_table="${AIRLOCK_OPS:-$here/fort/airlock/operations.json}"
if [ "$(jq -r '.operations | length' "$ops_table" 2>/dev/null)" = 0 ]; then
  ok "operations.json: Manyhalls ships the table with no operation (the mechanism is installed and nothing is permitted)"
else no "operations.json: the shipped table is not empty" "$(jq -c '[.operations[].name]' "$ops_table" 2>&1)"; fi

# --- Proofdelve ForgeOs-72ot.1: approval lives in the Overseer store, never in the request file ---
# Each forgery case asserts the OPERATION DID NOT RUN (no result file, no
# ran-ok in any log), not merely a nonzero exit: a refusal printed after the
# script executed would score as a pass on exit code alone.
ran() { [ -f "$1/fort/airlock/results/$2.json" ]; }

# 7. a seat forges .status=approved in its own request file: run must refuse and execute nothing
r=$(mkfix g1) || exit 3
air "$r" request deploy-ok --reason "fixture" >/dev/null; id=$(last_id "$r")
f="$r/fort/airlock/requests/$id.json"; jq '.status="approved" | .approved_by="overseer" | .approved_at="2026-10-06T00:00:00-08:00"' "$f" > "$f.t" && mv "$f.t" "$f"
air "$r" run "$id" >/dev/null 2>&1; rc=$?; air "$r" run >/dev/null 2>&1; rc2=$?
if [ "$rc" -ne 0 ] && ! ran "$r" "$id" && [ "$(cat_events "$r" deploy)" -eq 0 ]; then
  ok "72ot.1: a request file forged to status approved is REFUSED by run <id> (rc $rc) and by bare run (rc $rc2), and the operation never executed"
else no "72ot.1: a forged file status was honoured" "rc=$rc rc2=$rc2 result=$(ran "$r" "$id" && echo present || echo absent) deploy=$(cat_events "$r" deploy)"; fi

# 8. positive control: a store approval for the bytes on disk IS honoured (or case 7 proves nothing)
r=$(mkfix g2) || exit 3
air "$r" request deploy-ok --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null 2>&1
lst="$(air "$r" list 2>/dev/null)"; air "$r" run >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ran "$r" "$id" && grep -q "approved   deploy-ok" <<<"$lst" && [ "$(jq -r .status "$r/fort/airlock/requests/$id.json")" = completed ] \
   && [ "$(jq -r 'select(.requestSha256) | .requestSha256 | length' "$r/.store/airlock-approvals.jsonl" 2>/dev/null | head -1)" = 64 ] \
   && [ "$(jq -r 'select(.consumed == true) | .id' "$r/.store/airlock-approvals.jsonl" 2>/dev/null)" = "$id" ]; then
  ok "72ot.1: an approval written to the store pins a 64-hex request hash, list shows it approved, bare run executes it, and the store records it consumed"
else no "72ot.1: a genuine store approval was not honoured" "rc=$rc result=$(ran "$r" "$id" && echo present || echo absent) list=$(printf '%s' "$lst" | head -1)"; fi

# 9. approve, then the seat edits the request (operation swapped): the approval is void
r=$(mkfix g3) || exit 3
air "$r" request scan --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null 2>&1
f="$r/fort/airlock/requests/$id.json"; jq '.operation="deploy-ok"' "$f" > "$f.t" && mv "$f.t" "$f"
air "$r" run "$id" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && ! ran "$r" "$id" && [ "$(cat_events "$r" deploy)" -eq 0 ]; then
  ok "72ot.1: a request edited after approval (operation swapped to one that needs approval) is REFUSED: the approval pins the bytes"
else no "72ot.1: an edited request ran on an old approval" "rc=$rc result=$(ran "$r" "$id" && echo present || echo absent)"; fi

# 10. an approval is single-use: after a run, re-pending the file does not re-arm it
r=$(mkfix g4) || exit 3
air "$r" request deploy-ok --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null 2>&1; air "$r" run "$id" >/dev/null 2>&1
f="$r/fort/airlock/requests/$id.json"; rm -f "$r/fort/airlock/results/$id.json"; jq '.status="pending"' "$f" > "$f.t" && mv "$f.t" "$f"
before=$(cat_events "$r" deploy); air "$r" run "$id" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && [ "$(cat_events "$r" deploy)" -eq "$before" ]; then
  ok "72ot.1: an approval does not survive its run: the file re-pended and its result deleted is still refused (rc $rc)"
else no "72ot.1: an approval replayed" "rc=$rc deploys before=$before after=$(cat_events "$r" deploy)"; fi

# 11. a fixture root without a fixture store is refused, so no harness can write the real store
r=$(mkfix g5) || exit 3
AIRLOCK_ROOT="$r" FORT_ACTOR="emrith" FORT_SEAT=mayor bash "$AIRLOCK_SH" list >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then ok "72ot.1: AIRLOCK_ROOT without AIRLOCK_STORE is refused (rc $rc)"
else no "72ot.1: a fixture root ran against the default store" "rc=$rc"; fi

# --- Proofdelve ForgeOs-mbv54: the pinned commit, the host runner, and Proofdelve ForgeOs-72ot.1.1 ---
RUNNER_SH="${AIRLOCK_RUNNER_SH:-$(dirname "$AIRLOCK_SH")/airlock-runner.sh}"
[ -f "$RUNNER_SH" ] || RUNNER_SH="$here/fort/scripts/airlock-runner.sh"
# env -u FORT_MASKED: verify-impl.sh runs this harness inside seat masks too,
# and the runner refuses under the marker (the Warden, finding 1 on the mbv54 review;
# the scratch-reaper-harness.sh:183 pattern). Case 16 calls the runner directly.
runner() { env -u FORT_MASKED AIRLOCK_ROOT="$1" AIRLOCK_STORE="$1/.store" AIRLOCK_WORKTREES="$1-wt" AIRLOCK_SH="$AIRLOCK_SH" bash "$RUNNER_SH" "${@:2}"; }
movehead() { echo Y > "$1/marker.txt"; git -C "$1" commit -qam "move HEAD to Y"; }

# 12. a pinned operation approved at X runs X after HEAD moved to Y; Y never runs (criterion 2, the shape the Overseer chose)
r=$(mkfix p1) || exit 3
printf 'fixture-env\n' > "$r/.env.fix"
x=$(git -C "$r" rev-parse HEAD)
air "$r" request deploy-pin --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null 2>&1
movehead "$r"; y=$(git -C "$r" rev-parse HEAD)
air "$r" run "$id" >/dev/null 2>&1; rc=$?
log="$r/fort/airlock/results/$id.log"
if [ "$rc" -eq 0 ] && grep -qx "head=$x" "$log" 2>/dev/null && grep -qx "marker=X" "$log" && ! grep -q "$y" "$log" \
   && [ "$(jq -r .commit "$r/fort/airlock/results/$id.json")" = "$x" ] && [ "$(jq -r .exit_code "$r/fort/airlock/results/$id.json")" = 0 ] \
   && grep -q "^deploy .*\"commit\":\"$x\"" "$r/emitted" && [ "$(git -C "$r" rev-parse HEAD)" = "$y" ] \
   && [ ! -e "$r/.store/work/$id" ] && ! git -C "$r" worktree list | grep -q "/work/$id"; then
  ok "mbv54 B: approved at X, HEAD moved to Y: the run built X (log, result and deploy event all name X, never Y), main's HEAD is untouched, and the pinned worktree is gone after"
else no "mbv54 B: the pinned run did not run exactly the approved commit" "rc=$rc $(tr '\n' '|' < "$log" 2>/dev/null) result.commit=$(jq -r .commit "$r/fort/airlock/results/$id.json" 2>/dev/null) x=${x:0:8} y=${y:0:8}"; fi
# 12b. the declared env file reaches the pinned tree as a SYMLINK to the root's copy, never a copy
if grep -qx "envlink=fixture-env" "$log" 2>/dev/null; then
  ok "mbv54 B: an env_files entry is symlinked from the root into the pinned worktree (the script read it through a link; no second copy of the secret)"
else no "mbv54 B: the env file did not reach the pinned tree as a link" "$(tr '\n' '|' < "$log" 2>/dev/null)"; fi

# 13. a pinned commit NOT on main is refused, recorded as a result (exit 65), consumed, and never re-selected
r=$(mkfix p2) || exit 3
git -C "$r" checkout -q -b side; echo S > "$r/marker.txt"; git -C "$r" commit -qam side
air "$r" request deploy-pin --reason "fixture" >/dev/null; id=$(last_id "$r"); git -C "$r" checkout -q main
air "$r" approve "$id" >/dev/null 2>&1; air "$r" run >/dev/null 2>&1; rc=$?
again="$(air "$r" run 2>&1)"
if [ "$rc" -eq 0 ] && [ "$(jq -r .exit_code "$r/fort/airlock/results/$id.json" 2>/dev/null)" = 65 ] \
   && jq -e '.refused | test("not on main")' "$r/fort/airlock/results/$id.json" >/dev/null 2>&1 \
   && [ ! -f "$r/fort/airlock/results/$id.log" ] && [ "$(cat_events "$r" deploy)" -eq 0 ] \
   && grep -q '^airlock.result .*REFUSED.*"refused":true' "$r/emitted" && [ "$again" = "airlock: nothing approved to run" ]; then
  ok "mbv54 B: a pin to a commit off main is REFUSED before anything runs (result exit 65, reason recorded, airlock.result says REFUSED, no deploy event) and the next run finds nothing"
else no "mbv54 B: an off-main pin was not refused cleanly" "rc=$rc result=$(jq -c . "$r/fort/airlock/results/$id.json" 2>/dev/null) again=$again"; fi

# 13b. a pin that is not a full 40-hex sha is refused the same way (a seat wrote 'unknown', or a short sha)
r=$(mkfix p3) || exit 3
air "$r" request deploy-pin --reason "fixture" >/dev/null; id=$(last_id "$r")
f="$r/fort/airlock/requests/$id.json"; jq '.commit = "abc1234"' "$f" > "$f.t" && mv "$f.t" "$f"
air "$r" approve "$id" >/dev/null 2>&1; air "$r" run "$id" >/dev/null 2>&1
if [ "$(jq -r .exit_code "$r/fort/airlock/results/$id.json" 2>/dev/null)" = 65 ] && [ "$(cat_events "$r" deploy)" -eq 0 ]; then
  ok "mbv54 B: a pin that is not a full 40-hex sha is refused (exit 65), even with a valid approval"
else no "mbv54 B: a short or malformed pin ran" "$(jq -c . "$r/fort/airlock/results/$id.json" 2>/dev/null)"; fi

# 13c. request --commit pins a named commit (resolved to the full sha) and the run builds it; an unknown rev is refused at request time
r=$(mkfix p4) || exit 3
x=$(git -C "$r" rev-parse HEAD); movehead "$r"
air "$r" request deploy-pin --reason "fixture" --commit "${x:0:8}" >/dev/null; id=$(last_id "$r")
air "$r" request deploy-pin --reason "fixture" --commit nosuchrev >/dev/null 2>&1; rcbad=$?
air "$r" approve "$id" >/dev/null 2>&1; air "$r" run "$id" >/dev/null 2>&1
if [ "$(jq -r .commit "$r/fort/airlock/requests/$id.json")" = "$x" ] && grep -qx "marker=X" "$r/fort/airlock/results/$id.log" 2>/dev/null \
   && [ "$rcbad" -ne 0 ] && [ "$(find "$r/fort/airlock/requests" -name '*.json' | wc -l)" -eq 1 ]; then
  ok "mbv54 B: request --commit <short> pins the full sha of an older commit and the run builds it; an unknown rev is refused before any request is written"
else no "mbv54 B: request --commit did not pin as named" "commit=$(jq -r .commit "$r/fort/airlock/requests/$id.json" 2>/dev/null) rcbad=$rcbad"; fi

# 14. the runner executes a store-approved request with no typed id, then stops when nothing is left
r=$(mkfix q1) || exit 3
air "$r" request deploy-ok --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null 2>&1
out="$(runner "$r" 2>&1)"; rc=$?
out2="$(runner "$r" 2>&1)"; rc2=$?
if [ "$rc" -eq 0 ] && ran "$r" "$id" && [ "$(cat_events "$r" deploy)" -eq 1 ] && grep -qx 'airlock: nothing approved to run' <<<"$out" \
   && [ "$rc2" -eq 0 ] && [ "$out2" = "airlock: nothing approved to run" ]; then
  ok "mbv54 A: the runner ran the store-approved request with no id, looped until nothing was left, and a second firing ran nothing (a consumed approval does not run twice)"
else no "mbv54 A: the runner did not run the approved request exactly once" "rc=$rc rc2=$rc2 deploys=$(cat_events "$r" deploy) out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"; fi

# 15. the runner does NOT run a requires_approval:false request (feedback-scan's shape, Proofdelve ForgeOs-jhc6p) nor a forged-status one
r=$(mkfix q2) || exit 3
air "$r" request scan --reason "fixture" >/dev/null; sid=$(last_id "$r"); sleep 1
air "$r" request deploy-ok --reason "fixture" >/dev/null; fid=$(last_id "$r")
f="$r/fort/airlock/requests/$fid.json"; jq '.status="approved"' "$f" > "$f.t" && mv "$f.t" "$f"
runner "$r" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ! ran "$r" "$sid" && ! ran "$r" "$fid" && [ "$(cat_events "$r" airlock.result)" -eq 0 ]; then
  ok "mbv54 A: the runner leaves an unapproved requires_approval:false request (a scan) and a seat-forged 'approved' request alone: neither ran"
else no "mbv54 A: the runner ran something no store line approved" "rc=$rc scan=$(ran "$r" "$sid" && echo RAN || echo no) forged=$(ran "$r" "$fid" && echo RAN || echo no)"; fi

# 16. the runner refuses inside a seat mask
r=$(mkfix q3) || exit 3
FORT_MASKED=mayor AIRLOCK_ROOT="$r" AIRLOCK_STORE="$r/.store" AIRLOCK_SH="$AIRLOCK_SH" bash "$RUNNER_SH" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 64 ]; then ok "mbv54 A: the runner refuses under FORT_MASKED (exit 64)"
else no "mbv54 A: the runner ran under FORT_MASKED" "rc=$rc"; fi

# 17. the shipped units: the path unit watches exactly the store airlock.sh reads, and starts the service that runs the runner
# Beside the launcher under test, not $here: verify-impl.sh copies this harness
# out of the repo before running it, so $here is not the fort there.
sysd="${AIRLOCK_SYSTEMD:-$(cd -- "$(dirname -- "$AIRLOCK_SH")/../systemd" 2>/dev/null && pwd -P)}"
if grep -qE '^PathModified=/.+/\.local/state/civ-keep/airlock-approvals\.jsonl$' "$sysd/manyhalls-airlock-runner.path" 2>/dev/null \
   && grep -qx 'Unit=manyhalls-airlock-runner.service' "$sysd/manyhalls-airlock-runner.path" \
   && grep -qx 'Unit=manyhalls-airlock-runner.service' "$sysd/manyhalls-airlock-runner.timer" \
   && grep -q '^ExecStart=.*/fort/scripts/airlock-runner.sh$' "$sysd/manyhalls-airlock-runner.service"; then
  ok "mbv54 A: the path unit watches the approvals store airlock.sh reads and fires the runner service; the timer fires the same service"
else no "mbv54 A: the shipped units or table do not wire the runner as designed" "$(grep -h -E '^(PathModified|Unit|ExecStart)=' "$sysd"/manyhalls-airlock-runner.* 2>&1 | tr '\n' '|')"; fi

# 18. Proofdelve ForgeOs-72ot.1.1 (2): the request-snapshot race. A jq shim swaps the
# approved bytes back in right after the operation field is read from the
# request file. airlock.sh before be140bb2 read the operation from the file and
# then hashed the file, so it judged two byte sets and ran deploy-bad on
# deploy-ok's approval; the one-snapshot run reads both from one private copy.
r=$(mkfix race) || exit 3
air "$r" request deploy-ok --reason "fixture" >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null 2>&1
f="$r/fort/airlock/requests/$id.json"; cp "$f" "$work/race-approved.json"
jq '.operation="deploy-bad"' "$f" > "$f.t" && mv "$f.t" "$f"
mkdir -p "$work/shim"; realjq="$(command -v jq)"
cat > "$work/shim/jq" <<SH
#!/bin/bash
"$realjq" "\$@"; rc=\$?
case " \$* " in *" .operation $r/fort/airlock/requests/"*) cp "$work/race-approved.json" "$f" ;; esac
exit \$rc
SH
chmod +x "$work/shim/jq"
PATH="$work/shim:$PATH" air "$r" run "$id" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && ! ran "$r" "$id" && ! grep -rqs ran-bad "$r/fort/airlock/results/"; then
  ok "72ot.1.1: a request swapped between the field read and the hash is judged as ONE byte set and refused (the approved bytes restored behind the read do not lend their approval)"
else no "72ot.1.1: the snapshot race ran an operation on another request's approval" "rc=$rc result=$(ran "$r" "$id" && echo present || echo absent)"; fi

# 19. Proofdelve ForgeOs-72ot.1.1 (3): a store line that is valid JSON but not an object is skipped, not fatal for every id
r=$(mkfix nonobj) || exit 3
air "$r" request deploy-ok --reason "fixture" >/dev/null; id=$(last_id "$r")
mkdir -p "$r/.store"; printf '5\n"text"\n[1]\n' > "$r/.store/airlock-approvals.jsonl"
air "$r" approve "$id" >/dev/null 2>&1; air "$r" run "$id" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ran "$r" "$id"; then
  ok "72ot.1.1: non-object JSON lines in the store (5, a string, an array) are skipped and a genuine approval after them is honoured"
else no "72ot.1.1: a non-object store line disabled approvals" "rc=$rc"; fi

# 20. Proofdelve ForgeOs-72ot.1.1 (3): a die after the snapshot leaves nothing in TMPDIR
r=$(mkfix snaptrap) || exit 3
air "$r" request deploy-ok --reason "fixture" >/dev/null; id=$(last_id "$r")
mkdir -p "$work/tmpd"; TMPDIR="$work/tmpd" air "$r" run "$id" >/dev/null 2>&1; rc=$?
left=$(find "$work/tmpd" -mindepth 1 | wc -l)
if [ "$rc" -ne 0 ] && [ "$left" -eq 0 ]; then
  ok "72ot.1.1: run dying on an unapproved request after taking its snapshot leaves no snapshot behind in TMPDIR"
else no "72ot.1.1: the snapshot survived a die" "rc=$rc left=$left"; fi

# --- Proofdelve ForgeOs-emshb: declared params, bead-worktree runs, auto_run, result_url ---
# Every refusal case asserts the script NEVER RAN (no log, no result log line),
# and each has a control that runs the same shape and shows it does.
forge_params() { local f="$1/fort/airlock/requests/$2.json"; jq --argjson p "$3" '.params = $p' "$f" > "$f.t" && mv "$f.t" "$f"; }
res() { jq -r "$3" "$1/fort/airlock/results/$2.json" 2>/dev/null; }

# 21. a forged injection param is refused at run time, recorded as exit 64, before any script runs
r=$(mkfix e1) || exit 3
air "$r" request hostcheck --reason fixture --param target=main --param 'filter=A~1' >/dev/null; id=$(last_id "$r")
forge_params "$r" "$id" '{"target":"oye5y;id","filter":"A~1"}'
runner "$r" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(res "$r" "$id" .exit_code)" = 64 ] && res "$r" "$id" .refused | grep -q 'param target' \
   && [ ! -f "$r/fort/airlock/results/$id.log" ] && grep -q '^airlock.result .*REFUSED.*"exit":64' "$r/emitted"; then
  ok "emshb: a seat-forged target 'oye5y;id' is refused by the runner as a recorded result (exit 64, reason names the param) and no script ran"
else no "emshb: the injection param was not refused before running" "rc=$rc result=$(jq -c . "$r/fort/airlock/results/$id.json" 2>/dev/null) log=$([ -f "$r/fort/airlock/results/$id.log" ] && echo present || echo absent)"; fi
# 21b. a value with a trailing newline is refused too (jq's ^...$ would have let it through)
r=$(mkfix e1b) || exit 3
air "$r" request hostcheck --reason fixture --param target=main --param 'filter=A~1' >/dev/null; id=$(last_id "$r")
forge_params "$r" "$id" '{"target":"main\n","filter":"A~1"}'
runner "$r" >/dev/null 2>&1
if [ "$(res "$r" "$id" .exit_code)" = 64 ] && [ ! -f "$r/fort/airlock/results/$id.log" ]; then
  ok "emshb: a value with a trailing newline ('main\\n') is refused (patterns are matched whole, \\A...\\z)"
else no "emshb: a trailing newline slipped past the pattern" "$(jq -c . "$r/fort/airlock/results/$id.json" 2>/dev/null)"; fi
# 21c. CONTROL: the same request with valid params runs with NO approval line, and each param reaches the script as ONE argument
r=$(mkfix e1c) || exit 3
air "$r" request hostcheck --reason fixture --param target=main --param 'filter=A|B&(C) D' >/dev/null; id=$(last_id "$r")
runner "$r" >/dev/null 2>&1; rc=$?; log="$r/fort/airlock/results/$id.log"
if [ "$rc" -eq 0 ] && [ "$(res "$r" "$id" .exit_code)" = 0 ] && grep -qx 'argc=2' "$log" && grep -qx 'arg=\[main\]' "$log" \
   && grep -qx 'arg=\[A|B&(C) D\]' "$log" && grep -qx "script=$r/scripts/op-args.sh" "$log" && grep -qx "pwd=$r" "$log" \
   && ! grep -qs "\"id\":\"$id\"" "$r/.store/airlock-approvals.jsonl"; then
  ok "emshb control: a valid auto_run request runs from the runner with no store line; argv is exactly [main] [A|B&(C) D] (two arguments, the filter whole), from main's script, cwd \$root for target main"
else no "emshb control: the valid auto_run request did not run as declared" "rc=$rc $(tr '\n' '|' < "$log" 2>/dev/null)"; fi

# 22. request refuses a bad or undeclared param before writing anything; CONTROL: a valid one is written
r=$(mkfix e2) || exit 3
air "$r" request hostcheck --reason fixture --param 'target=oye5y;id' --param 'filter=A~1' >/dev/null 2>&1; rc1=$?
air "$r" request hostcheck --reason fixture --param target=main --param 'filter=A~1' --param extra=1 >/dev/null 2>&1; rc2=$?
n0=$(find "$r/fort/airlock/requests" -maxdepth 1 -name '*.json' | wc -l)
air "$r" request hostcheck --reason fixture --param target=oye5y --param 'filter=A~1' >/dev/null 2>&1; rc3=$?
n1=$(find "$r/fort/airlock/requests" -maxdepth 1 -name '*.json' | wc -l)
if [ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ] && [ "$n0" -eq 0 ] && [ "$rc3" -eq 0 ] && [ "$n1" -eq 1 ] \
   && [ -z "$(find "$r/fort/airlock/requests" -name '.*draft')" ]; then
  ok "emshb: request refuses 'oye5y;id' (rc $rc1) and an undeclared param (rc $rc2) writing nothing; control: a valid request is written (and no draft is left behind)"
else no "emshb: request-time validation did not hold" "rc1=$rc1 rc2=$rc2 rc3=$rc3 files before=$n0 after=$n1"; fi

# 23. runs_from bead-worktree: cwd is the named bead's worktree, the script is MAIN's copy, the run lock is closed for it
r=$(mkfix e3) || exit 3
mkdir -p "$r-wt/oye5y/.git" "$r-wt/oye5y/scripts"; printf '#!/bin/bash\necho WORKTREE-COPY\n' > "$r-wt/oye5y/scripts/op-args.sh"
air "$r" request hostcheck --reason fixture --param target=fortkit-oye5y --param 'filter=A~1' >/dev/null; id=$(last_id "$r")
runner "$r" >/dev/null 2>&1; log="$r/fort/airlock/results/$id.log"
if grep -qx "pwd=$r-wt/oye5y" "$log" 2>/dev/null && grep -qx "script=$r/scripts/op-args.sh" "$log" && ! grep -q WORKTREE-COPY "$log" && grep -qx 'fd8=closed' "$log"; then
  ok "emshb: a bead-worktree operation runs with cwd in \$root-worktrees/oye5y, executes main's script (never the worktree's seat-writable copy), and does not inherit the run lock (fd 8 closed)"
else no "emshb: the bead-worktree run was not as declared" "$(tr '\n' '|' < "$log" 2>/dev/null)"; fi
# 23b. a target with no worktree is refused (65), nothing runs
air "$r" request hostcheck --reason fixture --param target=nosuch --param 'filter=A~1' >/dev/null; id=$(last_id "$r")
runner "$r" >/dev/null 2>&1
if [ "$(res "$r" "$id" .exit_code)" = 65 ] && [ ! -f "$r/fort/airlock/results/$id.log" ]; then
  ok "emshb: a bead-worktree operation whose target has no worktree is refused as a recorded result (exit 65), nothing ran"
else no "emshb: a missing worktree did not refuse" "$(jq -c . "$r/fort/airlock/results/$id.json" 2>/dev/null)"; fi

# 24. a path param must resolve to a file INSIDE the run directory; CONTROL: a real one inside passes as two arguments
r=$(mkfix e4) || exit 3
mkdir -p "$r-wt/oye5y/.git" "$r-wt/oye5y/red"; echo patch > "$r-wt/oye5y/red/arm.patch"; ln -s "$work/outside.patch" "$r-wt/oye5y/evil.patch"; echo x > "$work/outside.patch"
air "$r" request hostcheck --reason fixture --param target=oye5y --param 'filter=A~1' --param mutate=red/arm.patch >/dev/null; ok_id=$(last_id "$r"); sleep 1
air "$r" request hostcheck --reason fixture --param target=oye5y --param 'filter=A~1' --param mutate=evil.patch >/dev/null; bad_id=$(last_id "$r")
runner "$r" >/dev/null 2>&1
if grep -qx 'arg=\[--mutate\]' "$r/fort/airlock/results/$ok_id.log" 2>/dev/null && grep -qx 'arg=\[red/arm.patch\]' "$r/fort/airlock/results/$ok_id.log" \
   && [ "$(res "$r" "$bad_id" .exit_code)" = 64 ] && res "$r" "$bad_id" .refused | grep -q 'outside' && [ ! -f "$r/fort/airlock/results/$bad_id.log" ]; then
  ok "emshb: a mutate patch symlinked to a file outside the worktree is refused (64, 'resolves outside'); control: red/arm.patch inside it reaches the script as --mutate red/arm.patch"
else no "emshb: path_params did not hold" "ok=$(tr '\n' '|' < "$r/fort/airlock/results/$ok_id.log" 2>/dev/null) bad=$(jq -c . "$r/fort/airlock/results/$bad_id.json" 2>/dev/null)"; fi

# 25. a preview-shaped operation does NOT run without an approval line; CONTROL: approved, it runs and the result carries the URL
r=$(mkfix e5) || exit 3
air "$r" request show --reason fixture --param target=main --param keep_data=true >/dev/null; id=$(last_id "$r")
runner "$r" >/dev/null 2>&1
before=$([ -f "$r/fort/airlock/results/$id.json" ] && echo RAN || echo no)
air "$r" approve "$id" >/dev/null 2>&1; runner "$r" >/dev/null 2>&1
if [ "$before" = no ] && [ "$(res "$r" "$id" .exit_code)" = 0 ] && [ "$(res "$r" "$id" .url)" = "http://localhost:5173" ] \
   && grep -qx 'arg=\[--keep-data\]' "$r/fort/airlock/results/$id.log"; then
  ok "emshb: a requires_approval preview request is NOT run by the runner without a store line; once approved it runs (keep_data=true reaches it as --keep-data) and the result records url http://localhost:5173"
else no "emshb: the preview gate or its URL did not hold" "before=$before result=$(jq -c . "$r/fort/airlock/results/$id.json" 2>/dev/null)"; fi
# 25b. a URL that is not local http is not recorded (results/ is seat-writable; the Keep checks again)
r=$(mkfix e5b) || exit 3
air "$r" request show --reason fixture --param target=main >/dev/null; id=$(last_id "$r"); air "$r" approve "$id" >/dev/null 2>&1
FIX_URL='http://evil.example:80/x' runner "$r" >/dev/null 2>&1
if [ "$(res "$r" "$id" .exit_code)" = 0 ] && [ "$(res "$r" "$id" '.url // "none"')" = none ]; then
  ok "emshb: a result_url match that is not http://localhost or 127.0.0.1 is not recorded"
else no "emshb: a non-local URL was recorded" "$(jq -c . "$r/fort/airlock/results/$id.json" 2>/dev/null)"; fi

# 26. auto_run forged into a deploy request runs nothing, and auto_run beside requires_approval true in the TABLE runs nothing; CONTROL: approved, it runs
r=$(mkfix e6) || exit 3
air "$r" request deploy-ok --reason fixture >/dev/null; did=$(last_id "$r")
f="$r/fort/airlock/requests/$did.json"; jq '.auto_run = true | .requires_approval = false' "$f" > "$f.t" && mv "$f.t" "$f"; sleep 1
air "$r" request greedy --reason fixture >/dev/null; gid=$(last_id "$r")
runner "$r" >/dev/null 2>&1; rc26=$?
d1=$(ran "$r" "$did" && echo RAN || echo no); g1=$(ran "$r" "$gid" && echo RAN || echo no)
air "$r" approve "$gid" >/dev/null 2>&1; runner "$r" >/dev/null 2>&1
if [ "$rc26" -eq 0 ] && [ "$d1" = no ] && [ "$g1" = no ] && [ "$(cat_events "$r" deploy)" -eq 0 ] && [ "$(res "$r" "$gid" .exit_code)" = 0 ]; then
  ok "emshb: a deploy request with auto_run forged into the FILE does not run, and a table operation declaring auto_run beside requires_approval true does not run unapproved; control: approved, that one runs"
else no "emshb: auto_run bypassed approval, or the runner died on an unapproved request it should never have selected" "rc=$rc26 deploy=$d1 greedy-before=$g1 greedy-after=$(res "$r" "$gid" .exit_code)"; fi

# 27. a request swapped AFTER selection into an operation that is neither approved nor auto is skipped, not run (the snapshot is judged)
r=$(mkfix e7) || exit 3
air "$r" request hostcheck --reason fixture --param target=main --param 'filter=A~1' >/dev/null; id=$(last_id "$r")
f="$r/fort/airlock/requests/$id.json"
mkdir -p "$work/shim7"; realjq="$(command -v jq)"
cat > "$work/shim7/jq" <<SH
#!/bin/bash
"$realjq" "\$@"; rc=\$?
case " \$* " in *" .operation // empty $f "*) "$realjq" '.operation = "scan" | .params = {}' "$f" > "$f.t" && mv "$f.t" "$f" ;; esac
exit \$rc
SH
chmod +x "$work/shim7/jq"
out="$(PATH="$work/shim7:$PATH" runner "$r" 2>&1)"
if ! ran "$r" "$id" && grep -q "skipping $id" <<<"$out" && [ "$(jq -r .operation "$f")" = scan ]; then
  ok "emshb: a request selected as auto_run and swapped to 'scan' before the snapshot is skipped (no result) and left for a person"
else no "emshb: a swapped request ran unattended" "result=$(ran "$r" "$id" && echo RAN || echo no) op=$(jq -r .operation "$f") out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-200)"; fi

# 28. the shipped table. The source fort asserted its own operations here; Manyhalls
# ships none, so what is asserted is the one property that must hold of any table:
# no operation pairs auto_run with requires_approval.
if [ "$(jq -r '[.operations[] | select(.requires_approval == true and .auto_run == true)] | length' "$ops_table")" = 0 ]; then
  ok "emshb: operations.json: no operation pairs auto_run with requires_approval"
else no "emshb: an operation pairs auto_run with requires_approval" "$(jq -c '.operations[] | {name, requires_approval, auto_run}' "$ops_table" | tr '\n' ' ')"; fi

# 29. the shipped units: the path unit also watches requests/ (an auto_run request needs no click to fire it) and the service lets a preview outlive the run
unitroot="$(sed -n 's/^WorkingDirectory=//p' "$sysd/manyhalls-airlock-runner.service" 2>/dev/null)"
if [ -n "$unitroot" ] && grep -qx "PathChanged=$unitroot/fort/airlock/requests" "$sysd/manyhalls-airlock-runner.path" 2>/dev/null \
   && grep -qx 'KillMode=process' "$sysd/manyhalls-airlock-runner.service"; then
  ok "emshb: the runner's path unit fires on a new request in fort/airlock/requests, and its service is KillMode=process (measured 2026-10-23: the default control-group kills a detached preview at unit exit)"
else no "emshb: the units do not carry the emshb wiring" "$(grep -h -E '^(PathChanged|PathModified|KillMode)=' "$sysd"/manyhalls-airlock-runner.* 2>&1 | tr '\n' '|')"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
