#!/bin/bash
# Harness for fort/scripts/scratch-reaper.sh (Proofdelve ForgeOs-nv0j acceptance 4). Runs
# the SHIPPED reaper against fixtures under a scratch root, a scratch legacy
# root and a scratch git repository whose scripts/stranded-sweep.sh wrapper
# invokes the real sweep with only its bd export fixture substituted. This pins
# scratch-reaper's positional REAPABLE contract to the producer it consumes.
#
# HOW IT INVERTS. The reaper is a NEW file, so there is no pre-fix version to
# fail against; the control is that this harness REFUSES (exit 3) when the file
# it is pointed at does not exist or is not the reaper, and that the two halves
# of every discriminating pair are asserted in the same run: a 3h-old dead-lock
# copy REMOVED beside a 10-minute one KEPT, a live-lock one KEPT beside a
# dead-lock one REMOVED, a dirty worktree KEPT beside a clean one REMOVED, an
# unlisted (open-bead) worktree KEPT. A reaper that removed everything or
# nothing fails half of each pair.
set -uo pipefail
reaper="${REAPER_SH:-$(dirname "$0")/../fort/scripts/scratch-reaper.sh}"
# verify-impl.sh copies an unchanged harness to a temporary directory before
# running it.  REAPER_SH is pinned there, but a default derived from $0 would
# name /tmp/scripts/stranded-sweep.sh.  Derive the companion producer from the
# pinned reaper instead, so this harness remains correct outside its repository.
reaper_root="$(cd -- "$(dirname -- "$reaper")/../.." && pwd -P)" || {
  echo "HARNESS REFUSES: cannot resolve repository root from reaper: $reaper" >&2
  exit 3
}
sweep="${SWEEP_SH:-$reaper_root/scripts/stranded-sweep.sh}"
printf 'reaper=%s\n' "$reaper"
[ -f "$reaper" ] || { echo "HARNESS REFUSES: reaper is missing: $reaper" >&2; exit 3; }
if ! grep -q 'sweep_worktrees()' "$reaper" || ! grep -q 'sweep_scratch()' "$reaper"; then
  echo "HARNESS REFUSES: $reaper does not define sweep_scratch() and sweep_worktrees(); it is not the reaper" >&2; exit 3
fi
[ -f "$sweep" ] || { echo "HARNESS REFUSES: sweep is missing: $sweep" >&2; exit 3; }

# The verifier's normal placement is outside the repository.  This small mode
# exercises only subject discovery so the full fixture does not recursively run.
if [ "${HARNESS_OUTSIDE_REPO_PROBE:-}" = 1 ]; then
  printf 'sweep=%s\n' "$sweep"
  exit 0
fi

work="$(mktemp -d)"
# Lock holders run with their stdio CLOSED: they outlive each case and would
# otherwise hold this harness's stdout open, so `harness | tail` never ends.
lockholders=()
cleanup() { for p in "${lockholders[@]:-}"; do [ -n "$p" ] || continue; pkill -TERM -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done; chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }
# expect <description> <failure detail> -- <test args...>: one PASS or FAIL line
expect(){ local d="$1" why="$2"; shift 2; if test "$@"; then ok "$d"; else no "$d" "$why"; fi; }

# 0 copied-instrument placement: verify-impl.sh runs an unchanged harness from
# mktemp.  With only REAPER_SH pinned, its sweep must still resolve beside the
# shipped repository rather than beside the temporary copy.
outside="$work/outside"; mkdir -p "$outside"
cp -f "$0" "$outside/scratch-reaper-harness.sh"
expected_sweep="$reaper_root/scripts/stranded-sweep.sh"
probe_output="$(env -u ROOT -u SWEEP_SH HARNESS_OUTSIDE_REPO_PROBE=1 REAPER_SH="$reaper" bash "$outside/scratch-reaper-harness.sh")"; probe_rc=$?
if [ "$probe_rc" -eq 0 ] && grep -Fxq "sweep=$expected_sweep" <<<"$probe_output"; then
  ok "a harness copied outside the repo derives sweep from pinned REAPER_SH"
else
  no "outside-repo subject discovery" "rc=$probe_rc output=$probe_output"
fi

# ---- fixture repo: a "root" with a stub stranded-sweep.sh and a stub emit.sh
repo="$work/repo"; mkdir -p "$repo/scripts" "$repo/fort/scripts"
g() { git -C "$repo" -c user.email=h@h -c user.name=h "$@"; }
git init -q -b main "$repo"; echo base > "$repo/f"
# The real repo ignores .forge.lock* (.gitignore:60), so a held lock never makes
# a worktree read dirty; the fixture must say the same or the locked case is
# kept for the wrong reason (dirt) and the lock probe is never exercised.
printf '.forge.lock*\n' > "$repo/.gitignore"; g add f .gitignore; g commit -qm base
mkwt() { # $1 sfx -> a worktree on bead/$1, merged into main (ahead=0)
  g worktree add -q "$repo-worktrees/$1" -b "bead/$1" >/dev/null 2>&1
}
mkdir -p "$repo-worktrees"
mkwt clean; mkwt dirty; mkwt openbead; mkwt locked; mkwt unmerged; mkwt gone; mkwt stranded
echo dirty > "$repo-worktrees/dirty/f"
g worktree add -q --detach "$repo-worktrees/detached" HEAD
echo detached > "$repo-worktrees/detached/f"
# unmerged: the stub LISTS it as reapable (a stale or wrong list) but its branch
# carries a commit main does not have -- the reaper must re-check and keep it.
echo more > "$repo-worktrees/unmerged/f"; git -C "$repo-worktrees/unmerged" -c user.email=h@h -c user.name=h commit -qam ahead
echo stranded > "$repo-worktrees/stranded/f"; git -C "$repo-worktrees/stranded" -c user.email=h@h -c user.name=h commit -qam stranded
# gone: listed, but its directory is already missing while its branch survives
# (the rc=255 shape) -- the reaper must NAME it, not skip it silently.
g worktree remove --force "$repo-worktrees/gone"
# Every closed fixture branch predates this commit, making it a real REAPABLE
# candidate rather than an exact-tip branch the sweep intentionally suppresses.
echo main-advance >> "$repo/f"; g add f; g commit -qm main-advance
# The dirty-report filter must exclude main even when main itself is dirty.
echo main-dirty >> "$repo/f"
flock "$repo-worktrees/locked/.forge.lock" sleep 300 >/dev/null 2>&1 &
lockholders+=($!)
cat > "$repo/issues.jsonl" <<'JSON'
{"id":"{{BEAD_PREFIX}}-clean","status":"closed"}
{"id":"{{BEAD_PREFIX}}-dirty","status":"closed"}
{"id":"{{BEAD_PREFIX}}-locked","status":"closed"}
{"id":"{{BEAD_PREFIX}}-unmerged","status":"closed"}
{"id":"{{BEAD_PREFIX}}-gone","status":"closed"}
{"id":"{{BEAD_PREFIX}}-stranded","status":"open"}
{"id":"{{BEAD_PREFIX}}-padding-1","status":"open"}
{"id":"{{BEAD_PREFIX}}-padding-2","status":"open"}
{"id":"{{BEAD_PREFIX}}-padding-3","status":"open"}
{"id":"{{BEAD_PREFIX}}-padding-4","status":"open"}
{"id":"{{BEAD_PREFIX}}-padding-5","status":"open"}
JSON
cat > "$repo/scripts/stranded-sweep.sh" <<STUB
#!/bin/bash
# Wrapper: only tracker data is synthetic. REAPABLE grammar comes from the
# actual sweep, so a producer-side positional break fails this consumer harness.
out="\$("$sweep" --repo "$repo" --bd-export "$repo/issues.jsonl" --reapable)"; rc=\$?
# Exit 1 reports a stranded unit, but leaves REAPABLE and WORKTREE-DIRTY facts
# valid for the reaper to consume. Only exit 3 is a producer refusal.
[ "\$rc" -eq 0 ] || [ "\$rc" -eq 1 ] || exit "\$rc"
printf '%s\\n' "\$out"
# These two rows deliberately lie about graph state to retain the reaper's
# independent stale-list and absent-directory controls. They are derived from
# an actual REAPABLE row, never hard-code the producer's positional grammar.
template="\$(printf '%s\\n' "\$out" | grep '^REAPABLE' | head -1)" || exit 3
source_branch="\$(awk '{print \$2}' <<<"\$template")"
source_id="\$(awk '{print \$3}' <<<"\$template")"
source_wt="\$(awk '{print \$4}' <<<"\$template")"
unmerged="\$(printf '%s\\n' "\$template" | sed "s|\$source_branch|bead/unmerged|; s|\$source_id|{{BEAD_PREFIX}}-unmerged|; s|\$source_wt|worktree=$repo-worktrees/unmerged|")"
gone="\$(printf '%s\\n' "\$template" | sed "s|\$source_branch|bead/gone|; s|\$source_id|{{BEAD_PREFIX}}-gone|; s|\$source_wt|worktree=$repo-worktrees/gone|")"
printf '%s\\n' "\$unmerged" "\$gone"
exit "\$rc"
STUB
chmod +x "$repo/scripts/stranded-sweep.sh"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/emitted"\n' "$work" > "$repo/fort/scripts/emit.sh"; chmod +x "$repo/fort/scripts/emit.sh"

# The fixture intentionally has an open, unmerged bead, so the real sweep's
# normal exit is 1. Its usable REAPABLE output must still reach the reaper.
fixture_output="$("$sweep" --repo "$repo" --bd-export "$repo/issues.jsonl" --reapable)"; fixture_rc=$?
if [ "$fixture_rc" -eq 1 ] && grep -q '^REAPABLE ' <<<"$fixture_output"; then
  ok "sweep exit 1 still carries REAPABLE lines to the reaper wrapper"
else
  no "exit-1 sweep output is retained" "rc=$fixture_rc output=$fixture_output"
fi
if grep -q 'WORKTREE-DIRTY.*bead/dirty.*{{BEAD_PREFIX}}-dirty' <<<"$fixture_output" \
  && grep -q 'WORKTREE-DIRTY.*DETACHED-HEAD.*worktree=.*/detached' <<<"$fixture_output" \
  && ! grep -q 'worktree=.*/repo;' <<<"$fixture_output"; then
  ok "dirty bead and detached worktrees are reported while dirty main is excluded"
else
  no "dirty worktree report filter and detached coverage" "output=$fixture_output"
fi

# ---- fixture warden roots
wr="$work/warden"; lg="$work/legacy"; mkdir -p "$wr" "$lg"
mkscratch() { # $1 root, $2 name, $3 age-minutes, $4 lock: none|dead|live
  local d="$1/$2" lock="$1/$2.lock"
  mkdir -p "$d/bin"; echo build > "$d/bin/out"
  # A dead review's lock and log are as old as the review: age them with the
  # directory, or the reaper (which reads the review's files, not the dir) sees
  # a fixture freshly created and keeps it as young. A LIVE one is held.
  case "$4" in
    dead) : > "$lock"; : > "$lock.info"; : > "${lock%.lock}.log" ;;
    live) : > "$lock"; flock "$lock" sleep 300 >/dev/null 2>&1 & lockholders+=($!) ;;
  esac
  touch -d "-$3 minutes" "$d" "$lock" "$lock.info" "${lock%.lock}.log" 2>/dev/null
}
mkscratch "$wr" olddead   180 dead
# THE rsync -a CASE: a copy whose DIRECTORY mtime is old (rsync preserves the
# source tree's) but whose lock was taken minutes ago is a review in flight, and
# the age floor must read the review's files, not the directory. Its lock is
# dead-shaped (no holder) so ONLY the age can keep it: a reaper reading the
# directory mtime removes it and fails this case.
mkscratch "$wr" freshlock 4000 dead; touch "$wr/freshlock.lock" "$wr/freshlock.lock.info" "$wr/freshlock.log"
mkscratch "$wr" young      10 dead
mkscratch "$wr" oldlive   180 live
mkscratch "$wr" oldnolock 180 none
mkdir -p "$lg/warden-legacy/obj"; echo o > "$lg/warden-legacy/obj/x"; : > "$lg/warden-legacy.lock"; : > "$lg/warden-legacy.log"
touch -d "-200 minutes" "$lg/warden-legacy" "$lg/warden-legacy.lock" "$lg/warden-legacy.log"
echo '{"verdict_recorded":true}' > "$wr/olddead.log.result.json"; touch -d "-180 minutes" "$wr/olddead.log.result.json"
sleep 0.3   # let the flock holders take their locks

# The harness runs inside masked seats too (verify-impl.sh runs in Forge and Mayor
# masks). The reaper refuses under FORT_MASKED by design; the fixtures here are
# the harness's own temp dirs, so the marker is cleared for the subject runs only.
# Case 101 below re-asserts the refusal with the marker set (Proofdelve ForgeOs-2sdo).
run() { env -u FORT_MASKED REAPER_REPO="$repo" REAPER_WARDEN_ROOT="$wr" REAPER_LEGACY_ROOT="$lg" REAPER_MIN_AGE_MIN=120 bash "$reaper" "$@" 2>"$work/err.txt"; }

# 1 masked refusal, nothing touched
FORT_MASKED=mayor REAPER_REPO="$repo" REAPER_WARDEN_ROOT="$wr" REAPER_LEGACY_ROOT="$lg" bash "$reaper" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 64 ] && [ -d "$wr/olddead" ] && [ -d "$repo-worktrees/clean" ]; then ok "refuses under FORT_MASKED (exit 64) and removes nothing"; else no "masked refusal" "rc=$rc"; fi

# 2 --dry-run decides and removes nothing
run --dry-run; rc=$?
if [ "$rc" -eq 0 ] && [ -d "$wr/olddead" ] && [ -d "$wr/oldnolock" ] && [ -d "$repo-worktrees/clean" ] && grep -q 'WOULD REMOVE warden scratch' "$work/err.txt" && grep -q 'WOULD REMOVE worktree' "$work/err.txt"; then
  ok "--dry-run names what it would remove and removes nothing"; else no "dry run" "rc=$rc $(cat "$work/err.txt")"; fi
if [ -e "$work/emitted" ]; then no "dry run emitted an event" "$(cat "$work/emitted")"; else ok "dry run emits no event"; fi

# 3 the real sweep
run; rc=$?
expect "3h-old scratch with a dead lock is REMOVED" "still there" ! -e "$wr/olddead"
expect "10-minute-old scratch is KEPT (young)" "removed" -d "$wr/young"
expect "copy with an OLD directory mtime (rsync -a) but a FRESH lock is KEPT: the age is the review's" "removed on the directory's rsync-preserved mtime" -d "$wr/freshlock"
expect "3h-old scratch whose lock is HELD is KEPT (live)" "removed under a live lock" -d "$wr/oldlive"
expect "3h-old scratch with no lock file at all is REMOVED" "still there" ! -e "$wr/oldnolock"
expect "legacy /tmp-shaped warden-<sfx> dir with a dead lock is REMOVED" "still there" ! -e "$lg/warden-legacy"
if [ -f "$wr/olddead.log" ] && [ -f "$wr/olddead.log.result.json" ] && [ -f "$wr/olddead.lock" ]; then
  ok "the small files beside a removed copy (log, result, lock) are KEPT"; else no "small files kept" "$(ls "$wr")"; fi
if [ ! -e "$repo-worktrees/clean" ] && ! g show-ref --verify --quiet refs/heads/bead/clean; then
  ok "merged+closed CLEAN worktree is REMOVED and its branch deleted with it"; else no "clean worktree" "$(ls -d "$repo-worktrees"/* 2>/dev/null; g branch)"; fi
if [ -d "$repo-worktrees/dirty" ] && g show-ref --verify --quiet refs/heads/bead/dirty; then
  ok "merged+closed but DIRTY worktree is KEPT, branch kept"; else no "dirty kept" "removed"; fi
expect "unlisted (open-bead) worktree is KEPT" "removed" -d "$repo-worktrees/openbead"
expect "worktree whose .forge.lock is held is KEPT" "removed" -d "$repo-worktrees/locked"
if [ -d "$repo-worktrees/unmerged" ] && g show-ref --verify --quiet refs/heads/bead/unmerged && grep -q 'KEPT (branch bead/unmerged is NOT an ancestor of main)' "$work/err.txt"; then
  ok "a LISTED worktree whose branch is not an ancestor of main is KEPT with its branch: the merge is re-checked, never taken from the list"; else no "unmerged kept" "$(ls -d "$repo-worktrees"/* 2>/dev/null; grep unmerged "$work/err.txt")"; fi
if grep -q 'ABSENT DIRECTORY .*/gone but branch bead/gone remains' "$work/err.txt" && g show-ref --verify --quiet refs/heads/bead/gone && grep -q '1 listed worktree(s) ABSENT with a surviving branch' "$work/err.txt" && grep -q '"absent_dir":1' "$work/emitted"; then
  ok "a listed worktree whose directory is already gone is NAMED as the rc=255 shape, counted, carried in the removal event's payload (absent_dir=1), and its branch is left alone"; else no "absent dir reported" "$(grep -i 'gone\|ABSENT' "$work/err.txt")"; fi
expect "exit 0 when every removal succeeded" "rc=$rc $(cat "$work/err.txt")" "$rc" -eq 0
if [ -e "$work/emitted" ] && [ "$(wc -l < "$work/emitted")" -eq 1 ] && grep -q '^progress ' "$work/emitted" && grep -q '"reaped":4' "$work/emitted"; then
  ok "exactly ONE progress event, carrying reaped=4"; else no "one event" "$(cat "$work/emitted" 2>/dev/null)"; fi

# 4 a second run with nothing to do is quiet: no event, exit 0
rm -f "$work/emitted"; run; rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$work/emitted" ] && grep -q '0 removed, 0 failed' "$work/err.txt" && grep -q '1 listed worktree(s) ABSENT' "$work/err.txt"; then ok "a sweep that removes nothing emits nothing and exits 0 -- even with an absent-directory orphan still listed (journal and summary name it; no hourly event for a state the reaper cannot repair)"; else no "quiet no-op" "rc=$rc $(cat "$work/emitted" 2>/dev/null) $(cat "$work/err.txt")"; fi

# 5 THE AGE THRESHOLD DISCRIMINATES: with the floor lowered the young copy goes too
env -u FORT_MASKED REAPER_REPO="$repo" REAPER_WARDEN_ROOT="$wr" REAPER_LEGACY_ROOT="$lg" REAPER_MIN_AGE_MIN=0 bash "$reaper" >/dev/null 2>&1
expect "vacuity control: REAPER_MIN_AGE_MIN=0 removes the copy the 120 floor kept" "young survived a zero floor" ! -e "$wr/young"
expect "vacuity control: the fresh-lock copy also goes at a zero floor (it was the AGE keeping it)" "freshlock survived a zero floor" ! -e "$wr/freshlock"
expect "the live-lock copy survives even a zero floor (the lock, not the age, protects it)" "removed" -d "$wr/oldlive"

# 6 a FAILED removal is exit 1 and says so; not 'removed', not 'refused'
mkscratch "$wr" stuck 180 dead; chmod 555 "$wr/stuck"; chmod 555 "$wr"
run; rc=$?; chmod 755 "$wr" "$wr/stuck" 2>/dev/null
if [ "$rc" -eq 1 ] && grep -q 'FAILED to remove' "$work/err.txt" && grep -q '"failed":1' "$work/emitted"; then ok "a removal that fails is reported FAILED with exit 1 and in the event"; else no "failed removal" "rc=$rc $(cat "$work/err.txt") $(cat "$work/emitted" 2>/dev/null)"; fi

# 7 the worktree list refusing (exit 3) is a refusal, not a clean sweep
printf '#!/bin/bash\nexit 3\n' > "$repo/scripts/stranded-sweep.sh"
run; rc=$?
if [ "$rc" -eq 64 ] && grep -q 'REFUSED worktree sweep' "$work/err.txt" && [ -d "$repo-worktrees/dirty" ]; then ok "stranded-sweep exit 3 is a REFUSAL (exit 64) and touches no worktree"; else no "list refusal" "rc=$rc $(cat "$work/err.txt")"; fi

# ---- Proofdelve ForgeOs-jfqu4.8 sweep C: host /tmp hygiene, and the /tmp usage alarm ----
# A fixture /tmp, a fixture worktrees dir, a fixture alarm state. The worktree
# list is a stub that lists nothing, so sweeps A and B have nothing to do here.
printf '#!/bin/bash\nexit 0\n' > "$repo/scripts/stranded-sweep.sh"
tf="$work/tmpfix"; wts="$work/wts"; rs="$work/reaper-state"; ev="$repo/fort/events"
mkdir -p "$tf/sub" "$wts/livebead" "$ev" "$work/outside" "$rs"
old() { echo x > "$1"; touch -d "-9 days" "$1"; }
old "$tf/forge-oldbead.log"; echo x > "$tf/forge-freshbead.log"; old "$tf/forge-livebead.log"
old "$tf/verify-fail-dotnet-test-111.log"; old "$tf/verify-fail-web-lint-222.log"
old "$tf/other.log"; old "$tf/sub/forge-deep.log"; old "$work/outside/forge-outside.log"
printf '{"category":"verify.fail","detail":"evidence kept at /tmp/verify-fail-dotnet-test-111.log"}\n' > "$ev/events-$(date +%F).jsonl"
flock "$wts/livebead/.forge.lock" sleep 300 >/dev/null 2>&1 & lockholders+=($!)
mkdir -p "$tf/node-compile-cache/v24"; head -c 2200000 /dev/zero > "$tf/node-compile-cache/v24/blob"
sleep 0.3
run_c() { env -u FORT_MASKED REAPER_REPO="$repo" REAPER_WARDEN_ROOT="$wr" REAPER_LEGACY_ROOT="$lg" REAPER_TMP_DIR="$tf" \
  REAPER_WORKTREES="$wts" REAPER_STATE="$rs" REAPER_TMP_LOG_DAYS=7 REAPER_NODE_CACHE_MAX_MB=1 REAPER_TMP_USAGE="${USAGE:-100 1000}" \
  bash "$reaper" "$@" 2>"$work/err.txt"; }
rm -f "$work/emitted"; run_c; rc=$?
expect "C: a forge log 9 days old is REMOVED" "still there" ! -e "$tf/forge-oldbead.log"
expect "C: a fresh forge log is KEPT" "removed" -f "$tf/forge-freshbead.log"
expect "C: an old forge log whose bead's .forge.lock is HELD is KEPT" "removed under a live worker" -f "$tf/forge-livebead.log"
expect "C: an old verify-fail log that today's event stream cites is KEPT" "removed while cited" -f "$tf/verify-fail-dotnet-test-111.log"
expect "C: an old verify-fail log nothing cites is REMOVED" "still there" ! -e "$tf/verify-fail-web-lint-222.log"
expect "C: node-compile-cache over the cap with no holder is REMOVED" "still there" ! -e "$tf/node-compile-cache"
if [ -f "$tf/other.log" ] && [ -f "$tf/sub/forge-deep.log" ] && [ -f "$work/outside/forge-outside.log" ] && [ -z "$(find "$tf" -maxdepth 1 -name 'node-compile-cache.reaping-*')" ]; then
  ok "C: nothing else is touched: a non-matching log, a forge log one level down, and one in a sibling of the tmp dir all stay (acceptance 4), and no moved-aside cache is left"
else no "C: sweep C touched what it must not" "$(find "$tf" "$work/outside" 2>&1 | tr '\n' ' ')"; fi
if [ "$rc" -eq 0 ] && grep -q '"tmp_removed":3' "$work/emitted" && ! grep -q '^incident ' "$work/emitted"; then
  ok "C: the sweep exits 0 and its one progress event carries tmp_removed=3; at 10% usage no alarm is raised"
else no "C: the sweep's exit or event is not as declared" "rc=$rc $(cat "$work/emitted" 2>/dev/null)"; fi
# a cache UNDER the cap is kept, and one OVER the cap with a holder is kept
mkdir -p "$tf/node-compile-cache/v24"; echo small > "$tf/node-compile-cache/v24/small"; run_c
expect "C: node-compile-cache under the cap is KEPT" "removed under the cap" -f "$tf/node-compile-cache/v24/small"
head -c 2200000 /dev/zero > "$tf/node-compile-cache/v24/blob"
( exec 7<"$tf/node-compile-cache/v24/blob"; sleep 300 ) >/dev/null 2>&1 & lockholders+=($!); sleep 0.3
run_c
if [ -f "$tf/node-compile-cache/v24/blob" ] && grep -q 'KEPT (a process has a file open in it)' "$work/err.txt"; then
  ok "C: node-compile-cache over the cap is KEPT while a process has a file in it open"
else no "C: a held cache was removed" "$(grep -i cache "$work/err.txt")"; fi

# the alarm: once per band per day, a higher band raises again, below the floor nothing
rm -f "$work/emitted"; USAGE="850 1000" run_c --tmp-check; rc1=$?
USAGE="860 1000" run_c --tmp-check
n1=$(grep -c '^incident ' "$work/emitted" 2>/dev/null)
USAGE="960 1000" run_c --tmp-check
n2=$(grep -c '^incident ' "$work/emitted" 2>/dev/null)
rm -f "$rs/tmp-alarm"; : > "$work/emitted"; USAGE="790 1000" run_c --tmp-check
n3=$(grep -c '^incident ' "$work/emitted" 2>/dev/null)
if [ "$rc1" -eq 0 ] && [ "$n1" = 1 ] && [ "$n2" = 2 ] && [ "$n3" = 0 ]; then
  ok "alarm: 85% raises ONE incident, 86% the same day raises none, 96% raises the 95 band, and 79% raises nothing (acceptance 3)"
else no "alarm bands" "rc=$rc1 after-86%=$n1 after-96%=$n2 at-79%=$n3"; fi
if [ -f "$tf/forge-freshbead.log" ] && [ -f "$tf/node-compile-cache/v24/blob" ]; then ok "--tmp-check measures and alarms and removes nothing"; else no "--tmp-check removed something" "$(ls "$tf")"; fi

# a fixture repo with NO fixture tmp dir never touches the real /tmp
env -u FORT_MASKED -u REAPER_TMP_DIR REAPER_REPO="$repo" REAPER_WARDEN_ROOT="$wr" REAPER_LEGACY_ROOT="$lg" bash "$reaper" --dry-run 2>"$work/err.txt"
if grep -q 'a fixture repo never touches the real /tmp, so sweep C and the /tmp alarm are skipped' "$work/err.txt" && ! grep -q 'WOULD REMOVE /tmp/' "$work/err.txt"; then
  ok "REAPER_REPO without REAPER_TMP_DIR skips sweep C and the alarm, and says so (a harness predating sweep C cannot prune the host)"
else no "a fixture repo reached the real /tmp" "$(grep -i tmp "$work/err.txt" | head -3)"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ $fail -eq 0 ]
