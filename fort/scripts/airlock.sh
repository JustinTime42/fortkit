#!/bin/bash
# Airlock — privileged operations without credential exposure.
#
# Generalises the ssh-agent pattern that fixed git inside the mask: the secret
# lives OUTSIDE the sandbox and the seat asks for an operation rather than
# receiving the credential. A seat holds a capability to REQUEST; it never holds
# a key. Every request, approval and result is an append-only file, so the record
# shows what was asked for, whether it was granted, and what happened.
#
# Verbs:
#   request <operation> --reason "..." [--commit <rev>] [--param k=v ...]   seat-side, works inside the mask
#   list [--all]                                            pending (or all) requests
#   show <id>                                               one request plus its result
#   approve <id>                                            OVERSEER ONLY, host-side; the Civ Keep's Approve button is the usual route
#   run [<id>]                                              host-side; executes requests approved IN THE STORE
#   announce <operation> --reason "..." [--commit <sha>]   OVERSEER ONLY; records a run made BY HAND
#
# The fort declares what may be run in fort/airlock/operations.json. Operation
# names are matched against that whitelist; there is no path from a request to an
# arbitrary command. Anything not declared there cannot be asked for.
#
# WHAT A COMPLETED OPERATION ANNOUNCES (Proofdelve ForgeOs-x6hq, Proofdelve ForgeOs-5fyc). `run` has
# always emitted airlock.result with the exit code; what nothing emitted was the
# category the digest and the Keep read for the action itself. Four successful
# staging deploys on 2026-08-31 produced one `deploy` event, and a fifth on
# 2026-09-17 none, because every `deploy` line in this stream was typed by a
# person after reading the result file. An operation may now declare, in
# operations.json, an `emits` block ({"category","target"}); on exit 0 `run`
# emits that category beside airlock.result (never instead of it: the event
# vocabulary is append-only), with the checkout's HEAD at run time and the
# request id in the payload. And a run made BY HAND -- the Overseer executing
# the script himself, outside the airlock -- announces itself through
# `announce`, which writes a request+result pair marked hand:true and emits the
# same category, so a hand action is not indistinguishable from the compromise
# signature the charter tells seats to escalate (5fyc; the push-by-hand half is
# the capital's fortkit-rw86 and is not here).
#
# AIRLOCK_ROOT overrides the fort root for scripts/airlock-harness.sh, which
# drives this file against a fixture fort; nothing in a seat mask can reach
# this verb's credentials whatever the root says, and `run` executes only what
# the root's own operations.json declares.
#
# WHERE APPROVAL LIVES (Proofdelve ForgeOs-72ot.1, Regent edict 2026-10-06, the Overseer's
# ruling of 2026-10-05 with the store placed at civilization level). Until this
# edit an approval was `.status = "approved"` inside the request file, and
# requests/ is seat-writable because a seat must be able to REQUEST -- so the
# record saying the Overseer approved something was writable by the seat that
# wanted it. Approval now lives in the Overseer store,
# ${XDG_STATE_HOME:-~/.local/state}/civ-keep/airlock-approvals.jsonl, which
# lib/seat-sandbox.sh binds READ-ONLY in every seat mask of every fort. Only the
# Civ Keep's Approve button (on the host) and this file's `approve` verb run on
# the host write it. A request file's .status is never read as consent again.
#
# AN APPROVAL PINS THE REQUEST'S BYTES. Each store line carries the sha256 of
# the request file as it stood when he approved it. `run` refuses when the file
# no longer hashes to that value, so a seat cannot get an approval for one
# request and then edit the file into another (a different operation, other
# params). AN APPROVAL IS SINGLE-USE, AND THAT IS RECORDED IN THE STORE TOO:
# `run` appends a consumed line for the id BEFORE it executes anything. The
# hash alone could not do it -- after a run a seat can rewrite the file back to
# its exact pre-run bytes (measured: jq re-emits them byte-identical), and the
# results/ file that says it ran is seat-writable as well.
#
# AIRLOCK_STORE overrides the store directory for scripts/airlock-harness.sh.
# A fixture root WITHOUT a fixture store is refused outright, so a harness
# that predates the store can never append its fixture approvals to the
# Overseer's real record.
#
# A PINNED OPERATION RUNS THE COMMIT HE APPROVED, NOT WHATEVER HEAD IS AT RUN
# TIME (Proofdelve ForgeOs-mbv54 item B, Regent edict 2026-10-15, the Overseer's choice of
# shape). `request` has always written `commit` (HEAD at request time) into the
# request file, and the approval hash covers it, but `run` executed the script
# from $root and so built whatever HEAD was when it ran: the fleet and the
# records commits move HEAD all day, so what deployed was rarely what he
# approved. An operation declaring "runs_from": "pinned-commit" now runs from a
# temporary DETACHED WORKTREE of the request's commit, cut under $WORK (outside
# every seat's writable grants; $HOME is read-only in every mask), and removed
# after. The commit must be a full 40-hex sha, present in this repository, and
# an ancestor of main, or the run is REFUSED and recorded as a result (exit 65)
# so it is never selected again. "Refuse when HEAD != commit" was the
# alternative and was rejected at the sitting: it would refuse nearly every
# deploy. Untracked files the script needs (the masked env file) are declared
# in the operation's "env_files" and SYMLINKED from $root into the worktree,
# never copied: no second copy of a secret exists on disk.
#
# ONE RUN AT A TIME. `run` holds $WORK/run.lock for its whole loop, so the host
# runner unit (fort/systemd/manyhalls-airlock-runner.*, which calls
# fort/scripts/airlock-runner.sh on every write to the approvals store) and a
# person typing `run` never execute side by side. The lock's descriptor (8) is
# CLOSED for the operation's script, so a script that leaves a process behind
# on purpose (preview) does not hold every later run off.
#
# SEAT-REQUESTABLE HOST OPERATIONS (Proofdelve ForgeOs-emshb, Regent docket 2026-10-22
# item A, gate 6, the Overseer's approval on the bead before any edit). Four
# additions, each read ONLY from operations.json, never from a request file:
#
#   params       {name: pattern}. Every declared param's value (absent reads
#                as "") must match its pattern WHOLE (\A(?:pattern)\z: jq's
#                ^...$ lets a trailing newline through, measured 2026-10-23);
#                a param the table does not declare, a value that is not a
#                string, or one longer than 256 is refused. `request` refuses
#                such a request before writing it, and `run` judges the
#                snapshot again (a seat can write requests/ directly), refusing
#                it as a recorded result with exit 64 before any script runs.
#   args         how params reach the script: an array of literals, "$name"
#                (that param's value as ONE argument, omitted when empty) and
#                {"when": name, "equals": value?, "args": [...]} groups. The
#                argv is built by jq and handed to the script as an array;
#                no value is ever interpolated into a shell string (standing
#                order 14: params are untrusted input).
#   path_params  params that name a file: each non-empty one must resolve
#                (realpath) to a regular file inside the run directory, or 64.
#   runs_from "bead-worktree"
#                the script runs with its cwd in the worktree of the bead the
#                `target` param names ($root-worktrees/<suffix>; main or a
#                40-hex sha run from $root), refused as 65 when that worktree
#                does not exist. The SCRIPT is still main's copy: a worktree is
#                seat-writable, and its scripts/ are not what the table
#                declared.
#   auto_run     true lets a bare `run` (the host runner) execute the request
#                with no store line. Honoured ONLY for an operation that also
#                declares requires_approval false: requires_approval true
#                always wins, so deploy-staging can never be auto-run, whatever
#                a request file or the table says about auto_run. Judged from
#                the snapshot, so a request swapped after selection to an
#                operation that is not auto is skipped, not run.
#   result_url   a regex with a named group `url`; on exit 0 the first match in
#                the run's log is recorded as the result's `url` when it is a
#                plain http URL on localhost or 127.0.0.1 (the Civ Keep shows
#                it as a link; results/ is seat-writable, so the Keep checks it
#                again before rendering).
#
# WHAT AUTO-RUN COSTS, decided at the sitting (comment on Proofdelve ForgeOs-emshb,
# 2026-10-23): host-test is not read-only. It builds and tests the named bead
# worktree, and a --mutate patch, on the host, unmasked, with Docker. That is
# the exposure the fleet's host verify already carries for every Forge branch
# (and the Mayor can write main and every worktree), so it adds a faster
# trigger, not a capability. The Overseer chose to build it as approved.
set -euo pipefail

root="${AIRLOCK_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null || echo /home/justin/dev/fortkit)}"
AIR="$root/fort/airlock"
REQ="$AIR/requests"; RES="$AIR/results"; OPS="$AIR/operations.json"
emit="$root/fort/scripts/emit.sh"
mkdir -p "$REQ" "$RES"

die() { echo "airlock: $*" >&2; exit 1; }
if [ -n "${AIRLOCK_ROOT:-}" ] && [ -z "${AIRLOCK_STORE:-}" ]; then
  die "AIRLOCK_ROOT is set without AIRLOCK_STORE: a fixture root must bring a fixture store, never the Overseer's real one"
fi
STORE="${AIRLOCK_STORE:-${XDG_STATE_HOME:-$HOME/.local/state}/civ-keep}"
APPROVALS="$STORE/airlock-approvals.jsonl"
# Where pinned worktrees are cut and the run lock lives. Under the XDG DATA dir,
# not the cache dir: ~/.cache is an rw grant in every seat mask and
# ~/.local/share is not, so no seat can edit a tree between checkout and build.
if [ -n "${AIRLOCK_ROOT:-}" ]; then WORK="${AIRLOCK_WORK:-$STORE/work}"
else WORK="${AIRLOCK_WORK:-${XDG_DATA_HOME:-$HOME/.local/share}/airlock/$(basename "$root")}"; fi
req_sha() { sha256sum "$1" | cut -d' ' -f1; }
# Approved = a store line for THIS fort root and THIS id whose pinned hash is
# the request file's hash right now. Malformed lines are skipped, never fatal:
# `fromjson?` drops a line that is not JSON and `objects` drops one that is
# JSON but not an object (a bare `5` made jq ERROR on `.repo` before
# Proofdelve ForgeOs-72ot.1.1, which failed closed for EVERY id in the store at once).
# $2, when given, is the private snapshot `run` judges (the Warden, finding A1 on the
# 2026-10-06 sitting): the hash and every field must come from ONE read of the
# request, or a seat racing the host could show one set of bytes to the field
# reads and another to the hash. jq -e over the whole store, never a pipe into
# grep -q, which under pipefail can score a match as a failure (SIGPIPE).
store_approved() {  # $1 id, [$2 snapshot] -> exit 0 when the store approves the request as it stands
  local f="${2:-$REQ/$1.json}" h
  [ -f "$APPROVALS" ] && [ -f "$f" ] || return 1
  h="$(req_sha "$f")"
  if jq -nRe --arg repo "$root" --arg id "$1" \
       '[inputs | fromjson? | objects | select(.repo == $repo and .id == $id and .consumed == true)] | length > 0' "$APPROVALS" >/dev/null 2>&1; then
    return 1
  fi
  jq -nRe --arg repo "$root" --arg id "$1" --arg h "$h" \
     '[inputs | fromjson? | objects | select(.repo == $repo and .id == $id and .requestSha256 == $h)] | length > 0' "$APPROVALS" >/dev/null 2>&1
}
have_ops() { [ -f "$OPS" ] || die "no operations.json — this fort declares no privileged operations"; }
op_field() { jq -r --arg n "$1" --arg f "$2" '.operations[] | select(.name==$n) | .[$f] // empty' "$OPS"; }
# auto_run is honoured only beside requires_approval false (emshb): an
# operation that needs his click never runs without one. Both are tested as
# JSON booleans: op_field's `// empty` turns a false into nothing.
op_auto() {
  jq -e --arg n "$1" 'any(.operations[]; .name == $n and .auto_run == true and .requires_approval == false)' "$OPS" >/dev/null 2>&1
}
# Why the request in $1 (a file) fails its operation's declared params, or
# nothing when it passes. Exit nonzero (jq failed, a malformed pattern
# included) is a refusal too: the caller fails closed.
params_why() {  # $1 request file, $2 op
  jq -r --arg n "$2" --slurpfile ops "$OPS" '
    ([$ops[0].operations[] | select(.name == $n) | .params // {}] | .[0] // {}) as $decl
    | (.params // {}) as $p
    | if ($p | type) != "object" then "params is not an object"
      else ([$p | keys[] | select($decl[.] == null)]) as $extra
      | if ($extra | length) > 0 then "undeclared param(s): \($extra | join(", "))"
        else [ $decl | to_entries[] | .key as $k | .value as $re | ($p[$k] // "") as $v
               | if ($v | type) != "string" then "param \($k) is not a string"
                 elif ($v | length) > 256 then "param \($k) is longer than 256 characters"
                 elif ($v | test("\\A(?:" + $re + ")\\z") | not) then "param \($k) does not match its declared pattern"
                 else empty end ] | .[0] // empty
        end
      end' "$1"
}
# The argv for the request in $1, NUL-terminated, into file $3.
op_argv() {  # $1 request file, $2 op, $3 out file
  jq -j --arg n "$2" --slurpfile ops "$OPS" '
    ([$ops[0].operations[] | select(.name == $n) | .args // []] | .[0] // []) as $a
    | (.params // {}) as $p
    | def el: if type == "string" then
                (if startswith("$") then ($p[.[1:]] // "" | if . == "" then empty else . end) else . end)
              elif type == "object" then
                (if (($p[.when] // "") != "") and ((.equals == null) or ($p[.when] == .equals)) then (.args[] | el) else empty end)
              else error("args element is neither a string nor a group") end;
    [$a[] | el | . + "\u0000"] | add // ""' "$1" > "$3"
}
# The `url` a run's log announces, when the operation declares result_url and
# the match is a plain local http URL; nothing otherwise.
op_url() {  # $1 op, $2 log
  local re u
  re="$(op_field "$1" result_url)"; [ -n "$re" ] && [ -f "$2" ] || return 0
  u="$(jq -Rr --arg re "$re" 'capture($re)? | .url // empty' "$2" 2>/dev/null | sed -n 1p)" || u=""
  [[ "$u" =~ ^http://(localhost|127\.0\.0\.1):[0-9]{2,5}/?$ ]] && printf '%s' "$u"
  return 0
}
op_emits() { jq -r --arg n "$1" --arg f "$2" '.operations[] | select(.name==$n) | .emits[$f] // empty' "$OPS"; }
# The declared success event for an operation (Proofdelve ForgeOs-x6hq). $1 op, $2 record
# id, $3 commit, $4 hand (true|false), $5 detail. Emits nothing for an operation
# that declares no `emits`; never emits on a nonzero exit (the caller decides).
announce_op() {
  local op="$1" id="$2" commit="$3" hand="$4" detail="$5" cat tgt
  cat="$(op_emits "$op" category)"; tgt="$(op_emits "$op" target)"
  [ -n "$cat" ] || return 0
  "$emit" "$cat" "$detail" -a overseer -s overseer -t "${tgt:-$op}" \
    -p "{\"airlock\":\"$id\",\"operation\":\"$op\",\"commit\":\"$commit\",\"hand\":$hand}" 2>/dev/null || true
}

cmd="${1:-}"; shift || true

case "$cmd" in

request)
  have_ops
  op="${1:-}"; shift || true
  [ -n "$op" ] || die "usage: airlock.sh request <operation> --reason \"...\""
  [ -n "$(op_field "$op" name)" ] || die "unknown operation '$op'. Declared: $(jq -r '.operations[].name' "$OPS" | tr '\n' ' ')"
  reason=""; params="{}"; pin=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      --commit) pin="${2:-}"; shift 2 ;;
      --param)  k="${2%%=*}"; v="${2#*=}"; params=$(jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}' <<<"$params"); shift 2 ;;
      *) die "unexpected argument '$1'" ;;
    esac
  done
  [ -n "$reason" ] || die "--reason is required: the record must say why this was asked for"
  # --commit (Proofdelve ForgeOs-mbv54) names the commit to pin when it is not HEAD, e.g.
  # a deliberate re-deploy of what staging already runs. Resolved to a full sha
  # here so the request, the Keep and the approval all carry the same 40 hex.
  if [ -n "$pin" ]; then
    commit="$(git -C "$root" rev-parse --verify --quiet "$pin^{commit}" 2>/dev/null)" || die "--commit '$pin' does not name a commit in this repository"
  else
    commit="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)"
  fi
  id="$(date +%Y%m%dT%H%M%S)-$op-$$"
  # Built aside and judged against the declared params BEFORE it is filed
  # (emshb): a request that would be refused at run time is never written.
  # The draft sits in requests/ under a dot-name `run` never globs, so the
  # rename into place is atomic and a runner fired mid-write never reads half.
  draft="$REQ/.$id.draft"
  jq -n --arg id "$id" --arg op "$op" --arg reason "$reason" --arg by "${FORT_ACTOR:-unknown}" \
        --arg seat "${FORT_SEAT:-}" --arg ts "$(date -Is)" --argjson params "$params" \
        --arg commit "$commit" \
        '{id:$id, operation:$op, reason:$reason, requested_by:$by, seat:$seat, requested_at:$ts,
          commit:$commit, params:$params, status:"pending"}' > "$draft"
  why="$(params_why "$draft" "$op")" || why="the params could not be checked against operations.json"
  if [ -n "$why" ]; then rm -f "$draft"; die "request refused, nothing filed: $why. Declared: $(jq -c --arg n "$op" '.operations[] | select(.name==$n) | .params // {}' "$OPS")"; fi
  mv "$draft" "$REQ/$id.json"
  "$emit" airlock.request "Airlock request: $op — $reason" -a "${FORT_ACTOR:-unknown}" -s "${FORT_SEAT:-}" -t "$id" 2>/dev/null || true
  echo "airlock: request $id filed (operation: $op, commit ${commit:0:12})"
  if [ "$(op_field "$op" requires_approval)" = "true" ]; then
    echo "airlock: this operation requires the Overseer. It runs only after he approves it on the Civ Keep's Airlock page (or, on the host:  fort/scripts/airlock.sh approve $id)"
  elif op_auto "$op"; then
    echo "airlock: this operation runs without approval: the host runner picks it up (one run at a time). Result: fort/airlock/results/$id.json, log beside it"
  fi
  ;;

list)
  shopt -s nullglob
  for f in "$REQ"/*.json; do
    st=$(jq -r .status "$f")
    # "approved" is displayed from the STORE, never taken from the file (72ot.1);
    # a file claiming approved without a store line reads as unapproved.
    if [ "$st" = "pending" ] || [ "$st" = "approved" ]; then
      if store_approved "$(jq -r .id "$f")"; then st=approved; else st=pending; fi
    fi
    [ "${1:-}" = "--all" ] || [ "$st" = "pending" ] || [ "$st" = "approved" ] || continue
    printf "%-10s %-16s %s\n" "$st" "$(jq -r .operation "$f")" "$(jq -r .id "$f")"
    printf "           %s\n" "$(jq -r .reason "$f")"
  done
  ;;

show)
  id="${1:?usage: airlock.sh show <id>}"
  [ -f "$REQ/$id.json" ] || die "no such request: $id"
  jq . "$REQ/$id.json"
  [ -f "$RES/$id.json" ] && { echo "--- result ---"; jq . "$RES/$id.json"; } || true
  ;;

approve)
  id="${1:?usage: airlock.sh approve <id>}"
  f="$REQ/$id.json"; [ -f "$f" ] || die "no such request: $id"
  [ "$(jq -r .status "$f")" = "pending" ] || die "request $id is $(jq -r .status "$f"), not pending"
  [ -f "$RES/$id.json" ] && die "request $id already has a result; an approval is single-use"
  # The request file is NOT rewritten: its bytes are what the approval pins.
  # From inside a seat mask this append fails on the read-only bind, which is
  # the boundary working (72ot.1).
  line="$(jq -cn --arg ts "$(date -Is)" --arg repo "$root" --arg id "$id" \
        --arg op "$(jq -r .operation "$f")" --arg h "$(req_sha "$f")" \
        '{ts:$ts, repo:$repo, id:$id, operation:$op, requestSha256:$h, actor:"justin", via:"airlock.sh"}')"
  { mkdir -p "$STORE" && printf '%s\n' "$line" >> "$APPROVALS"; } 2>/dev/null \
    || die "could not write the approval into $APPROVALS (inside a seat mask this is read-only by design: approve on the Civ Keep, or from an unmasked host shell)"
  "$emit" airlock.approved "Overseer approves $(jq -r .operation "$f"): $(jq -r .reason "$f")" -a overseer -t "$id" 2>/dev/null || true
  echo "airlock: $id approved. Run it with:  fort/scripts/airlock.sh run $id"
  ;;

run)
  have_ops
  # HOST-SIDE ONLY. This is where credentials are in scope; it must never be
  # reachable from inside a seat's mask. The guard is that a masked seat cannot
  # read the credential files this operation's script sources, so a seat running
  # this verb gets the same failure it would get running the script directly.
  mkdir -p "$WORK" || die "could not create the work directory $WORK"
  exec 8>>"$WORK/run.lock" || die "could not open $WORK/run.lock"
  flock -w "${AIRLOCK_RUN_LOCK_WAIT:-7200}" 8 || die "another airlock run held $WORK/run.lock past the wait; nothing run"
  # The snapshot and a pinned worktree are removed on EVERY exit, a die
  # included (Proofdelve ForgeOs-72ot.1.1: a die between mktemp and rm left the snapshot
  # in host /tmp).
  snap=""; wt=""
  drop_wt() {
    [ -n "$wt" ] || return 0
    git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || true
    git -C "$root" worktree prune >/dev/null 2>&1 || true
    [ ! -e "$wt" ] || echo "airlock: WARNING: the pinned worktree $wt could not be removed; remove it by hand" >&2
    wt=""
  }
  # shellcheck disable=SC2329  # invoked by the EXIT trap
  run_cleanup() { [ -z "$snap" ] || rm -f "$snap"; drop_wt; }
  trap run_cleanup EXIT
  # A refusal AFTER the approval was consumed is recorded as a result, so the
  # request is never selected again (the host runner loops until nothing is
  # left to run, and an approved request that can never run would loop it).
  refuse_run() {  # $1 id, $2 op, $3 commit, $4 why, [$5 exit code, default 65; 64 for params (emshb)]
    local code="${5:-65}"
    jq -n --arg id "$1" --arg op "$2" --arg ts "$(date -Is)" --arg commit "$3" --arg why "$4" --argjson code "$code" \
          '{id:$id, operation:$op, started_at:$ts, ended_at:$ts, exit_code:$code, refused:$why, commit:$commit, log:null}' > "$RES/$1.json"
    local t; t=$(mktemp); jq '.status = "failed"' "$REQ/$1.json" > "$t" && mv "$t" "$REQ/$1.json"
    "$emit" airlock.result "Airlock $2 for $1 REFUSED before running: $4" -a overseer -t "$1" -p "{\"exit\":$code,\"refused\":true}" 2>/dev/null || true
    echo "airlock: $2 for $1 REFUSED before running: $4" >&2
  }
  ids=(); bare=false
  if [ $# -gt 0 ]; then ids=("$1"); else
    bare=true
    shopt -s nullglob
    # Approved means approved IN THE STORE, for the bytes on disk (72ot.1), or
    # an operation the TABLE declares auto_run (emshb). A request file jq
    # cannot read is skipped, never fatal: requests/ is seat-writable, and one
    # garbage file must not stop every run. Selection is a shortlist only: the
    # snapshot below is judged again, whole.
    for f in "$REQ"/*.json; do
      i="$(jq -r '.id // empty' "$f" 2>/dev/null)" || continue
      [ -n "$i" ] || continue
      [ ! -f "$RES/$i.json" ] || continue
      if store_approved "$i" || op_auto "$(jq -r '.operation // empty' "$f" 2>/dev/null)"; then ids+=("$i"); fi
    done
  fi
  [ ${#ids[@]} -gt 0 ] || { echo "airlock: nothing approved to run"; exit 0; }
  for id in "${ids[@]}"; do
    f="$REQ/$id.json"; [ -f "$f" ] || die "no such request: $id"
    # ONE SNAPSHOT, JUDGED WHOLE (finding A1): copied once to a private file
    # the seats cannot reach, then the operation, the status, the commit and
    # the approval hash are all read from that copy.
    snap="$(mktemp)"; cp "$f" "$snap" || die "could not snapshot request $id"
    op=$(jq -r .operation "$snap"); st=$(jq -r .status "$snap"); commit=$(jq -r '.commit // empty' "$snap")
    script=$(op_field "$op" script)
    [ -n "$script" ] || die "operation '$op' is not declared in operations.json"
    [ -f "$RES/$id.json" ] && die "request $id already ran (a result exists); file a new request"
    # A bare run (the host runner) executes only what the store approved or
    # what the table declares auto_run, judged on the SNAPSHOT: a request
    # swapped after selection into an operation that is neither is skipped
    # and left for a person, never run (emshb).
    if $bare && [ "$(op_field "$op" requires_approval)" != "true" ] && ! op_auto "$op"; then
      echo "airlock: skipping $id: operation '$op' is neither approved in the store nor declared auto_run; a person runs it with: airlock.sh run $id" >&2
      rm -f "$snap"; snap=""; continue
    fi
    if [ "$(op_field "$op" requires_approval)" = "true" ] && ! store_approved "$id" "$snap"; then
      die "request $id has no Overseer approval in $APPROVALS for the request as it stands (file status '$st' is not consent; an edited request voids its approval)"
    fi
    # Consume the approval in the store BEFORE executing (72ot.1): a crash
    # mid-run then costs a re-approval, never a free second run.
    if [ "$(op_field "$op" requires_approval)" = "true" ]; then
      printf '%s\n' "$(jq -cn --arg ts "$(date -Is)" --arg repo "$root" --arg id "$id" '{ts:$ts, repo:$repo, id:$id, consumed:true, via:"airlock.sh run"}')" >> "$APPROVALS" \
        || die "could not record the approval of $id as consumed in $APPROVALS; not running it"
    fi
    # Params are judged on the snapshot and become the argv before anything
    # runs (emshb); a failure is a recorded result with exit 64.
    why="$(params_why "$snap" "$op")" || why="the params could not be checked against operations.json"
    if [ -n "$why" ]; then
      rm -f "$snap"; snap=""; refuse_run "$id" "$op" "$commit" "$why" 64; continue
    fi
    argv=()
    if ! op_argv "$snap" "$op" "$snap.argv"; then
      rm -f "$snap" "$snap.argv"; snap=""; refuse_run "$id" "$op" "$commit" "the argv could not be built from the declared args" 64; continue
    fi
    mapfile -d '' -t argv < "$snap.argv"
    target="$(jq -r '.params.target // ""' "$snap")"
    # path_params, as name/value pairs, from the SAME snapshot.
    pairs=()
    if ! jq -j --arg n "$op" --slurpfile ops "$OPS" '
      ([$ops[0].operations[] | select(.name == $n) | .path_params // []] | .[0] // []) as $pp
      | . as $r | [$pp[] | ., ($r.params[.] // "") | . + "\u0000"] | add // ""' "$snap" > "$snap.argv"; then
      rm -f "$snap" "$snap.argv"; snap=""; refuse_run "$id" "$op" "$commit" "the path params could not be read" 64; continue
    fi
    mapfile -d '' -t pairs < "$snap.argv"
    rm -f "$snap" "$snap.argv"; snap=""
    # Where the script runs from: $root, a worktree of the pinned commit, or
    # the named bead's worktree (emshb). scriptpath is main's copy except for
    # a pinned commit, whose own tree is the point.
    rundir="$root"; ran_commit="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)"
    scriptpath="$root/$script"
    if [ "$(op_field "$op" runs_from)" = "bead-worktree" ] && [ "$target" != main ] && ! [[ "$target" =~ ^[0-9a-f]{40}$ ]]; then
      bwt="${AIRLOCK_WORKTREES:-$root-worktrees}/${target#fortkit-}"
      if [ -z "$target" ] || [ ! -e "$bwt/.git" ]; then
        refuse_run "$id" "$op" "$commit" "no worktree for target '$target' at $bwt" 65; continue
      fi
      rundir="$bwt"; ran_commit="$(git -C "$bwt" rev-parse HEAD 2>/dev/null || echo unknown)"
    fi
    pbad=""; rdir="$(realpath -e -- "$rundir")"
    for ((k = 0; k + 1 < ${#pairs[@]}; k += 2)); do
      pn="${pairs[k]}"; pv="${pairs[k+1]}"
      [ -n "$pv" ] || continue
      rp="$(realpath -e -- "$rundir/$pv" 2>/dev/null)" || { pbad="param $pn names no file in the run directory"; break; }
      case "$rp" in "$rdir"/*) ;; *) pbad="param $pn resolves outside the run directory"; break ;; esac
      [ -f "$rp" ] || { pbad="param $pn is not a regular file"; break; }
    done
    if [ -n "$pbad" ]; then refuse_run "$id" "$op" "$commit" "$pbad" 64; continue; fi
    if [ "$(op_field "$op" runs_from)" = "pinned-commit" ]; then
      wt="$WORK/$id"
      if ! [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
        wt=""; refuse_run "$id" "$op" "$commit" "the request pins no full 40-hex commit (commit '$commit')"; continue
      elif ! git -C "$root" cat-file -e "$commit^{commit}" 2>/dev/null; then
        wt=""; refuse_run "$id" "$op" "$commit" "the pinned commit $commit is not in this repository"; continue
      elif ! git -C "$root" merge-base --is-ancestor "$commit" refs/heads/main 2>/dev/null; then
        wt=""; refuse_run "$id" "$op" "$commit" "the pinned commit $commit is not on main"; continue
      elif [ -e "$wt" ]; then
        wt=""; refuse_run "$id" "$op" "$commit" "the work directory $WORK/$id already exists"; continue
      elif ! git -C "$root" worktree add --detach --quiet "$wt" "$commit" >/dev/null 2>&1 \
           || [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$commit" ]; then
        drop_wt; refuse_run "$id" "$op" "$commit" "a worktree of $commit could not be cut at $WORK/$id"; continue
      elif [ ! -f "$wt/$script" ]; then
        drop_wt; refuse_run "$id" "$op" "$commit" "$script does not exist at the pinned commit"; continue
      fi
      while IFS= read -r e; do
        [ -n "$e" ] && [ -e "$root/$e" ] && ln -s "$root/$e" "$wt/$e"
      done < <(jq -r --arg n "$op" '.operations[] | select(.name==$n) | .env_files // [] | .[]' "$OPS")
      rundir="$wt"; ran_commit="$commit"; scriptpath="$wt/$script"
    fi
    echo "airlock: running $op for request $id (from $rundir at ${ran_commit:0:12})"
    log="$RES/$id.log"; start=$(date -Is); rc=0
    ( cd "$rundir" && bash "$scriptpath" "${argv[@]}" ) >"$log" 2>&1 </dev/null 8>&- || rc=$?
    drop_wt
    jq -n --arg id "$id" --arg op "$op" --arg started "$start" --arg ended "$(date -Is)" \
          --argjson rc "$rc" --arg log "$log" --arg commit "$ran_commit" \
          --arg url "$( [ "$rc" -eq 0 ] && op_url "$op" "$log" )" \
          '{id:$id, operation:$op, started_at:$started, ended_at:$ended, exit_code:$rc, log:$log, commit:$commit}
           + (if $url == "" then {} else {url:$url} end)' > "$RES/$id.json"
    tmp=$(mktemp); jq --argjson rc "$rc" '.status = (if $rc == 0 then "completed" else "failed" end)' "$f" > "$tmp" && mv "$tmp" "$f"
    "$emit" airlock.result "Airlock $op for $id exited $rc" -a overseer -t "$id" -p "{\"exit\":$rc}" 2>/dev/null || true
    echo "airlock: $op exited $rc (log: $log)"
    # The operation's own event, on success only (Proofdelve ForgeOs-x6hq). The commit is
    # what the script ran from: the pinned commit for a pinned operation
    # (mbv54), otherwise the checkout's HEAD when the run started.
    if [ "$rc" -eq 0 ]; then
      announce_op "$op" "$id" "$ran_commit" false \
        "$op completed through the airlock (request $id, exit 0) at ${ran_commit:0:12}"
    fi
  done
  ;;

announce)
  # A RUN MADE BY HAND (Proofdelve ForgeOs-5fyc). The Overseer executed the operation's
  # script himself, outside the airlock, and records it here so the stream
  # carries the action. Writes the same request+result pair `run` would have,
  # marked hand:true, and emits the operation's declared event. Nothing is
  # executed. Refuses an operation that declares no event: there is nothing
  # for it to announce.
  have_ops
  op="${1:-}"; shift || true
  [ -n "$op" ] || die "usage: airlock.sh announce <operation> --reason \"...\" [--commit <sha>]"
  [ -n "$(op_field "$op" name)" ] || die "unknown operation '$op'. Declared: $(jq -r '.operations[].name' "$OPS" | tr '\n' ' ')"
  [ -n "$(op_emits "$op" category)" ] || die "operation '$op' declares no emits block in operations.json; nothing to announce"
  reason=""; commit=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      --commit) commit="${2:-}"; shift 2 ;;
      *) die "unexpected argument '$1'" ;;
    esac
  done
  [ -n "$reason" ] || die "--reason is required: the record must say what was done by hand and why"
  [ -n "$commit" ] || commit="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)"
  id="$(date +%Y%m%dT%H%M%S)-$op-hand-$$"; ts="$(date -Is)"
  jq -n --arg id "$id" --arg op "$op" --arg reason "$reason" --arg ts "$ts" --arg commit "$commit" \
        '{id:$id, operation:$op, reason:$reason, requested_by:"overseer", seat:"overseer", requested_at:$ts,
          commit:$commit, params:{}, status:"completed", hand:true}' > "$REQ/$id.json"
  jq -n --arg id "$id" --arg op "$op" --arg ts "$ts" --arg commit "$commit" \
        '{id:$id, operation:$op, started_at:$ts, ended_at:$ts, exit_code:0, log:null, hand:true, commit:$commit}' > "$RES/$id.json"
  announce_op "$op" "$id" "$commit" true "$op done BY HAND, outside the airlock, recorded after the fact as $id: ${commit:0:8} -- $reason"
  echo "airlock: hand run of $op recorded as $id (commit ${commit:0:8})"
  ;;

*)
  echo "usage: airlock.sh {request|list|show|approve|run|announce}" >&2
  echo "  seats:    airlock.sh request <operation> --reason \"why\" [--commit <rev>] [--param k=v]" >&2
  echo "  overseer: airlock.sh list | show <id> | approve <id> | run [<id>] | announce <operation> --reason \"...\" [--commit <sha>]" >&2
  [ -f "$OPS" ] && { echo "  declared operations:" >&2; jq -r '.operations[] | "    \(.name)  — \(.description)  (approval: \(.requires_approval))"' "$OPS" >&2; }
  exit 2
  ;;
esac
