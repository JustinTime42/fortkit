#!/bin/bash
# session-reap-harness: the instrument for fort/scripts/lib/session-reap.sh and
# its two call sites (Proofdelve ForgeOs-ab495; Regent sitting 2026-11-16).
#
# It starts real detached processes under a fixture "worktree" and runs the
# SHIPPED session_reap() on it: those under the directory must be gone, those
# outside it (including one in a sibling directory sharing its prefix) must
# survive, and the caller and its ancestors are never touched. The case that
# passes "/" runs with `kill` replaced by a logging function, so a regression
# there cannot signal anything.
#
# Subjects: SESSION_REAP_LIB, FORGE_SH, WARDEN_SH, or the files beside this
# file's parent. Exit: 0 all passed; 1 a case failed or did not run; 3 refused.
# shellcheck disable=SC2016  # file-wide: the single-quoted strings are stub bodies and source assertions on the launchers' own $-bearing lines
set -uo pipefail
# NOTHING THIS HARNESS STARTS OUTLIVES IT (Regent sitting 2026-11-19, fortkit-awlc).
# Its fixtures start long sleeps (lock holders, processes for a reaper to find).
# Killing the pid that was started is not enough: `flock f sleep 300` and
# `bash -c 'sleep 300; :'` leave the sleep behind as an orphan, and 20 of those
# were found holding the fleet's run lock after a verifier run. Every process
# this harness starts inherits FORT_HARNESS_TAG, and the EXIT trap kills every
# process that carries it, whoever its parent is by then.
export FORT_HARNESS_TAG="fh-$$-$RANDOM"
reap_tagged() {
  local p pid
  for p in /proc/[0-9]*; do
    pid="${p#/proc/}"
    [ "$pid" = "$$" ] && continue
    if grep -qzx "FORT_HARNESS_TAG=$FORT_HARNESS_TAG" "$p/environ" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null; fi
  done
  return 0
}
unset SESSION_REAP_GRACE_S
here="$(cd "$(dirname "$0")" && pwd)"
lib="${SESSION_REAP_LIB:-$here/../fort/scripts/lib/session-reap.sh}"
forge="${FORGE_SH:-$here/../fort/scripts/forge.sh}"
warden="${WARDEN_SH:-$here/../fort/scripts/warden.sh}"
for f in "$lib" "$forge" "$warden"; do [ -f "$f" ] || { echo "HARNESS REFUSES: no subject at $f"; exit 3; }; done
grep -q '^session_reap() {' "$lib" || { echo "HARNESS REFUSES: no session_reap() in $lib"; exit 3; }
work="$(mktemp -d "${TMPDIR:-/tmp}/session-reap-harness.XXXXXX")"
case "$work" in /*) ;; *) echo "HARNESS REFUSES: scratch dir is not absolute"; exit 3 ;; esac
started=()
cleanup() { local p; for p in "${started[@]:-}"; do [ -n "$p" ] && kill -KILL "$p" 2>/dev/null; done; reap_tagged; rm -rf "$work"; }
trap cleanup EXIT
pass=0; fail=0; notrun=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1 -- $2"; }
alive() { kill -0 "$1" 2>/dev/null && [ "$(awk '{print $3}' "/proc/$1/stat" 2>/dev/null)" != Z ]; }
spawn() {  # $1 cwd, rest: command -> sets $pid to a detached (setsid) process
  local cwd="$1"; shift
  # exec, so $! is the process itself and no wrapper shell is left holding the cwd
  ( cd "$cwd" && exec setsid "$@" ) >/dev/null 2>&1 &
  pid=$!; started+=("$pid")
  disown "$pid" 2>/dev/null || true   # no job notice when it is killed
  local i=0; while ! kill -0 "$pid" 2>/dev/null && [ $i -lt 20 ]; do sleep 0.05; i=$((i+1)); done
}
reap() {  # $1 lib, rest: args to session_reap -> output in $work/out, count in $count
  local l="$1"; shift
  count="$(bash -c 'source "$1"; shift; session_reap "$@" > "$OUT" 2>&1; echo "$session_reap_count"' _ "$l" "$@" 2>/dev/null)"
}
export OUT="$work/out"
wt="$work/wt/abc1"; sib="$work/wt/abc1-other"; mkdir -p "$wt/web" "$sib" "$work/elsewhere"; : > "$wt/web/side.vite.mjs"

# 1. cwd under the worktree.
spawn "$wt/web" sleep 300; p_cwd="$pid"
# 2. an argument that is a path under the worktree, cwd elsewhere.
spawn "$work/elsewhere" tail -f "$wt/web/side.vite.mjs"; p_arg="$pid"
# 3. --flag=<path under the worktree>, cwd elsewhere.
spawn "$work/elsewhere" bash -c 'sleep 300; :' _ "--contentRoot=$wt"; p_eq="$pid"
# 4. bystanders: cwd elsewhere; cwd in a sibling directory that shares the prefix; an argument naming the sibling.
spawn "$work/elsewhere" sleep 300; p_out="$pid"
spawn "$sib" sleep 300; p_sib="$pid"
: > "$sib/file"; spawn "$work/elsewhere" tail -f "$sib/file"; p_sibarg="$pid"
# 5. one that ignores SIGTERM.
spawn "$wt" bash -c 'trap "" TERM; sleep 300; :'; p_stub="$pid"
sleep 0.3
if alive "$p_cwd" && alive "$p_arg" && alive "$p_eq" && alive "$p_out" && alive "$p_sib" && alive "$p_sibarg" && alive "$p_stub"; then ok "0 positive control: every fixture process is alive before the reap"
else bad "0 positive control" "a fixture process did not start; nothing below means anything"; fi

# RED ARM FIRST: a reaper that does nothing leaves them alive (the bead's own red arm).
noop="$work/noop-lib.sh"; printf 'session_reap_count=0\nsession_reap() { session_reap_count=0; return 0; }\n' > "$noop"
reap "$noop" harness "$wt"
if alive "$p_cwd" && alive "$p_arg"; then ok "R1 red arm: with the reap skipped the leftover processes survive"
else bad "R1 red arm" "processes died without a reap; the cases below cannot discriminate"; fi

# 6. the caller and its ancestors are never reaped, even when their own command line names the worktree.
out6="$(SESSION_REAP_GRACE_S=1 bash -c 'source "$1"; session_reap harness "$2" > "$OUT" 2>&1; echo "survived $session_reap_count"' _ "$lib" "$wt" "$wt/in-my-own-argv" 2>/dev/null)"
count="${out6#survived }"
case "$out6" in "survived "*) ok "6 the calling shell, whose own argv names the worktree, survives its own reap" ;; *) bad "6 caller survives" "got [$out6]" ;; esac
if [ "$count" = 5 ]; then ok "1-3,5 five processes signalled (cwd, argument, --flag=path, the TERM-ignorer and its child)"; else bad "count" "expected 5, got [$count]: $(cat "$OUT")"; fi
sleep 0.3
if ! alive "$p_cwd"; then ok "1 the process with its cwd under the worktree is gone"; else bad "1 cwd" "pid $p_cwd survived"; fi
if ! alive "$p_arg"; then ok "2 the process with an argument under the worktree is gone"; else bad "2 argument" "pid $p_arg survived"; fi
if ! alive "$p_eq"; then ok "3 the process with --flag=<worktree> is gone"; else bad "3 flag" "pid $p_eq survived"; fi
if ! alive "$p_stub"; then ok "5 the process that ignored SIGTERM was killed after the grace period"; else bad "5 TERM-ignorer" "pid $p_stub survived"; fi
if grep -q "ignored SIGTERM" "$OUT"; then ok "5b the log says which process needed SIGKILL"; else bad "5b" "no SIGKILL line in: $(cat "$OUT")"; fi
if alive "$p_out"; then ok "4 a process outside the worktree survives"; else bad "4 bystander" "pid $p_out was killed"; fi
if alive "$p_sib" && alive "$p_sibarg"; then ok "4b processes in or naming a sibling directory that shares the prefix survive"; else bad "4b prefix" "a sibling-directory process was killed"; fi
if [ "$(grep -c "reaped leftover process $p_cwd " "$OUT")" = 1 ]; then ok "7 the log names each reaped pid with its cwd and command"; else bad "7 log" "$(cat "$OUT")"; fi

# 8. nothing left: a second reap signals nothing.
reap "$lib" harness "$wt"
if [ "$count" = 0 ]; then ok "8 a second reap finds nothing"; else bad "8" "count [$count]"; fi

# 9. UNUSABLE DIRECTORIES REAP NOTHING. kill is a logging function here, so a regression cannot signal anything.
klog="$work/kill.log"; : > "$klog"
c9="$(KLOG="$klog" bash -c 'kill() { echo "$*" >> "$KLOG"; }; source "$1"; session_reap harness "/" "" "relative/dir" "//" > /dev/null 2>&1; echo "$session_reap_count"' _ "$lib" 2>/dev/null)"
if [ "$c9" = 0 ] && [ ! -s "$klog" ]; then ok "9 '/', the empty string and a relative path match no process (kill stubbed)"; else bad "9" "count [$c9], would have signalled: $(head -3 "$klog" | tr '\n' ';')"; fi

# 10. THE CALL SITES.
fn="$(awk '/^forge_reap_leftovers\(\) \{/{f=1} f{print} f && /^}/{exit}' "$forge")"
if [ -z "$fn" ]; then notrun=$((notrun+1)); echo "NOT RUN 10 -- no forge_reap_leftovers() in $forge"
else
  runfn() {  # $1 session_launched -> prints "<count of emits>"; reaps under $wt
    EM="$work/emit.log" bash -c 'source "$1"; emit="$4"; wt="$2"; bead=B-1; session_launched="$3"; leftovers_reaped=0
'"$fn"'
forge_reap_leftovers; forge_reap_leftovers' _ "$lib" "$wt" "$1" "$work/emit-stub.sh" >/dev/null 2>&1
  }
  printf '#!/bin/bash\necho "$1" >> "$EM"\n' > "$work/emit-stub.sh"; chmod +x "$work/emit-stub.sh"; : > "$work/emit.log"
  spawn "$wt" sleep 300; p10="$pid"; sleep 0.2
  runfn 0
  if alive "$p10" && [ ! -s "$work/emit.log" ]; then ok "10 forge.sh: a launcher that never launched its session reaps nothing"; else bad "10" "the process died or an event was emitted before any session"; fi
  runfn 1; sleep 0.2
  if ! alive "$p10" && [ "$(grep -c '^progress$' "$work/emit.log")" = 1 ]; then ok "10b forge.sh: after a launched session it reaps once and emits ONE progress event across two calls"; else bad "10b" "alive=$(alive "$p10" && echo yes || echo no) emits=$(cat "$work/emit.log" | tr '\n' ' ')"; fi
fi
if [ "$(grep -c '^session_launched=1$' "$forge")" = 1 ] && [ "$(grep -A1 '^session_launched=1$' "$forge" | tail -1 | grep -c 'bwrap .* codex exec')" = 1 ]; then ok "10c forge.sh marks the session launched on the line before the codex launch"; else bad "10c" "session_launched=1 is not immediately above the bwrap codex line"; fi
if grep -q '^forge_reap_leftovers ' "$forge" || grep -q '^forge_reap_leftovers$' "$forge"; then
  a="$(grep -n '^forge_reap_leftovers' "$forge" | grep -v '() {' | head -1 | cut -d: -f1)"; b="$(grep -n 'stamp_forge_handoff "\$handoff"' "$forge" | head -1 | cut -d: -f1)"; c="$(grep -n '^rc=\${PIPESTATUS\[0\]}' "$forge" | head -1 | cut -d: -f1)"
  if [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] && [ "$c" -lt "$a" ] && [ "$a" -lt "$b" ]; then ok "10d forge.sh reaps after the session returns and before the handoff is stamped"; else bad "10d" "call at line [$a], session end [$c], stamp [$b]"; fi
else bad "10d" "forge.sh never calls forge_reap_leftovers at top level"; fi
if grep -q "^trap 'forge_reap_leftovers || true; " "$forge"; then ok "10e forge.sh's EXIT trap repeats the reap for a launcher that dies mid-session"; else bad "10e" "the EXIT trap does not call forge_reap_leftovers"; fi
wex="$(awk '/^warden_on_exit\(\) \{/{f=1} f{print} f && /^}/{exit}' "$warden")"
r="$(printf '%s\n' "$wex" | grep -n '^  session_reap warden.sh "\$scratch" || true$' | cut -d: -f1)"; cl="$(printf '%s\n' "$wex" | grep -n '^  clear_scratch "\$scratch"' | cut -d: -f1)"
if [ -n "$r" ] && [ -n "$cl" ] && [ "$r" -lt "$cl" ]; then ok "11 warden.sh reaps under its scratch copy in the EXIT trap, before the copy is removed"; else bad "11" "session_reap line [$r], clear_scratch line [$cl]"; fi
if [ "$(grep -c '^ *session_reap ' "$warden")" = 1 ]; then ok "11b warden.sh has exactly one reap call, and it names only the scratch copy (never the candidate worktree)"; else bad "11b" "$(grep -n '^ *session_reap ' "$warden" | tr '\n' ';')"; fi

echo "RESULT session-reap-harness: $pass pass / $fail fail / $notrun not run (lib: $lib)"
[ "$fail" = 0 ] && [ "$notrun" = 0 ]
