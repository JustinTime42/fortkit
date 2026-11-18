#!/bin/bash
# Harness for forge.sh's reused-worktree refresh (Proofdelve ForgeOs-lw8x) and, from
# 2026-09-13, its handoff stamp (Proofdelve ForgeOs-mdwx; the STAMP-LEVEL section at the
# foot). The refresh half: tests the
# SHIPPED refresh_reused_worktree(), extracted from the real launcher, against
# git fixtures that put a bead worktree in each state the function
# discriminates -- and then the SHIPPED LAUNCHER ITSELF, truncated at the line
# after the refresh block so nothing past it (bd, bwrap, codex) can run, to
# prove the refusal happens before any session starts. Refuses on an empty
# extraction. FORGE_SH overrides the launcher under test so the pre-fix file can
# be scored as a positive control: against it the two launcher-level cases FAIL
# (the stale instrument runs, unrefreshed) and the harness then REFUSES the
# function-level cases, because the function does not exist there.
set -uo pipefail
launcher="${FORGE_SH:-$(dirname "$0")/../fort/scripts/forge.sh}"
printf 'launcher=%s\n' "$launcher"
[ -f "$launcher" ] || { echo "HARNESS REFUSES: launcher is missing: $launcher" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok(){ echo "  PASS  $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1 -- $2"; fail=$((fail+1)); }

# --------------------------------------------------------------------------
# FIXTURES. A fort whose verifier is the real Shape B resolution: a shim under
# fort/scripts that execs scripts/verify-impl.sh IN THE TREE THE SHIM LIVES IN
# (Proofdelve ForgeOs-afdr). v1 is committed, a bead worktree is cut, then main moves to v2.
# So "which instrument does the worktree's own verify.sh run" is the property.
mkfort() {  # $1 name -> prints root; worktree at <root>-worktrees/xyz on bead/xyz, main at v2
  local r="$work/$1"
  git init -q "$r"; git -C "$r" config user.email h@x; git -C "$r" config user.name harness
  mkdir -p "$r/fort/scripts" "$r/scripts"
  # shellcheck disable=SC2016  # single quotes are the point: this is the SHIM's text, expanded when the shim runs
  printf '#!/bin/bash\nset -euo pipefail\nrepo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"\nexec "$repo_root/scripts/verify-impl.sh" "$@"\n' > "$r/fort/scripts/verify.sh"
  printf '#!/bin/bash\necho "INSTRUMENT v1"\n' > "$r/scripts/verify-impl.sh"
  chmod +x "$r/scripts/verify-impl.sh" "$r/fort/scripts/verify.sh"
  echo one > "$r/subject.txt"; echo lib > "$r/lib.txt"
  git -C "$r" add -A; git -C "$r" commit -qm v1; git -C "$r" branch -M main
  git -C "$r" worktree add -q "$r-worktrees/xyz" -b bead/xyz
  printf '#!/bin/bash\necho "INSTRUMENT v2"\n' > "$r/scripts/verify-impl.sh"
  git -C "$r" commit -qam "main: instrument v2"
  printf '%s' "$r"
}
instrument(){ ( cd "$1" && ./fort/scripts/verify.sh ) 2>&1; }
clean_tree(){ [ -z "$(git -C "$1" status --porcelain --untracked-files=no)" ] && ! git -C "$1" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; }

# 0 THE MEASUREMENT (lw8x criterion 1), before any code under test is touched:
# a reused worktree runs the OLD instrument and a fresh cut runs the new one.
r=$(mkfort m0)
if [ "$(instrument "$r-worktrees/xyz")" = "INSTRUMENT v1" ] && [ "$(instrument "$r")" = "INSTRUMENT v2" ]; then
  ok "measurement: the reused worktree runs INSTRUMENT v1 while main runs v2 -- the stale-instrument reuse is real"
else no "measurement fixture" "wt=$(instrument "$r-worktrees/xyz") main=$(instrument "$r")"; fi
git -C "$r" worktree add -q "$r-worktrees/fresh" -b bead/fresh
if [ "$(instrument "$r-worktrees/fresh")" = "INSTRUMENT v2" ]; then ok "measurement: a freshly cut worktree runs v2"; else no "fresh cut" "$(instrument "$r-worktrees/fresh")"; fi
git -C "$r" worktree remove --force "$r-worktrees/xyz"
if ! git -C "$r" worktree add "$r-worktrees/xyz" -b bead/xyz >/dev/null 2>&1; then
  ok "measurement: re-cutting a removed worktree fails because the branch outlives the directory (the rc=255 claim)"
else no "re-cut should fail" "it succeeded"; fi

# --------------------------------------------------------------------------
# LAUNCHER-LEVEL: the shipped forge.sh, root repointed at a fixture, TRUNCATED
# at the line after the refresh block, with a stub emit.sh and FORGE_SMOKE=1
# (which skips the bd claim). Everything before the refresh runs for real: the
# cut-or-reuse block, the flock, the lock.info write. Everything after it is
# replaced by one echo, so the property "exit 76 before any session" is
# measured rather than argued. On the PRE-FIX launcher there is no refresh
# block, so the truncation point is the line after the lock.info write and the
# case reads "continued, stale" -- which is the defect, and FAILS here.
mk_trunc() {  # $1 fixture root -> prints path of the truncated launcher
  local r="$1" t cut
  t="$work/$(basename "$r")-forge.sh"
  cut=$(awk '/^if \[ "\$reused_worktree" = 1 \]; then$/{f=1} f && /^fi$/{print NR; exit}' "$launcher")
  if [ -z "$cut" ]; then
    cut=$(awk '/^printf .\{"pid":%d,"bead":"%s","model":"%s","started":"%s"\}/{print NR; exit}' "$launcher")
  fi
  [ -n "$cut" ] || { echo "HARNESS REFUSES: cannot find a truncation point in $launcher" >&2; exit 3; }
  head -n "$cut" "$launcher" | sed "s|^root=\"/home/justin/dev/fortkit\"$|root=\"$r\"|; s|^wt=\"/home/justin/dev/fortkit-worktrees/\$suffix\"$|wt=\"$r-worktrees/\$suffix\"|" > "$t"
  grep -q "^root=\"$r\"$" "$t" || { echo "HARNESS REFUSES: root= substitution did not land" >&2; exit 3; }
  grep -q "^wt=\"$r-worktrees/\$suffix\"$" "$t" || { echo "HARNESS REFUSES: wt= substitution did not land" >&2; exit 3; }
  printf 'echo LAUNCHER-CONTINUED\nexit 0\n' >> "$t"
  chmod +x "$t"
  printf '#!/bin/bash\nprintf "EMIT %%s\\n" "$*" >> "%s/emitted"\n' "$r" > "$r/fort/scripts/emit.sh"; chmod +x "$r/fort/scripts/emit.sh"
  printf '%s' "$t"
}
# L1 stale worktree, no conflict: the launcher continues AND the worktree now runs v2
r=$(mkfort l1); t=$(mk_trunc "$r")
out=$(FORGE_SMOKE=1 "$t" fortkit-xyz 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q LAUNCHER-CONTINUED <<<"$out" && [ "$(instrument "$r-worktrees/xyz")" = "INSTRUMENT v2" ]; then
  ok "launcher: a stale reused worktree is refreshed before the session point -- its own verify.sh now runs INSTRUMENT v2"
else no "launcher: stale worktree not refreshed" "rc=$rc instrument=$(instrument "$r-worktrees/xyz") out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
# L2 conflict: exit 76, no LAUNCHER-CONTINUED, an incident emitted, tree untouched
r=$(mkfort l2); t=$(mk_trunc "$r")
echo conflict-on-bead > "$r-worktrees/xyz/subject.txt"; git -C "$r-worktrees/xyz" commit -qam "bead edit"
echo conflict-on-main > "$r/subject.txt"; git -C "$r" commit -qam "main edit"
before=$(git -C "$r-worktrees/xyz" rev-parse HEAD)
out=$(FORGE_SMOKE=1 "$t" fortkit-xyz 2>&1); rc=$?
if [ "$rc" -eq 76 ] && ! grep -q LAUNCHER-CONTINUED <<<"$out" \
   && [ "$(git -C "$r-worktrees/xyz" rev-parse HEAD)" = "$before" ] && clean_tree "$r-worktrees/xyz" \
   && grep -q 'EMIT incident forge.sh REFUSED' "$r/emitted" 2>/dev/null; then
  ok "launcher: a conflicting refresh exits 76 BEFORE the session point, emits an incident, and leaves the worktree at $before, clean"
else no "launcher: conflict handling" "rc=$rc head=$(git -C "$r-worktrees/xyz" rev-parse HEAD) before=$before clean=$(clean_tree "$r-worktrees/xyz" && echo y || echo n) emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|') out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi
# L3 VACUITY CONTROL: a fresh dispatch (no worktree yet) cuts and continues; nothing refuses
r=$(mkfort l3); t=$(mk_trunc "$r"); git -C "$r" worktree remove --force "$r-worktrees/xyz"; git -C "$r" branch -qD bead/xyz
out=$(FORGE_SMOKE=1 "$t" fortkit-xyz 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q LAUNCHER-CONTINUED <<<"$out" && [ -d "$r-worktrees/xyz" ] \
   && [ "$(instrument "$r-worktrees/xyz")" = "INSTRUMENT v2" ] && ! grep -q REFUSED "$r/emitted" 2>/dev/null; then
  ok "vacuity control: a fresh dispatch cuts its worktree and continues -- the refresh refuses nothing it should not"
else no "vacuity control: fresh dispatch" "rc=$rc out=$(printf '%s' "$out" | tr '\n' '|' | cut -c1-300)"; fi

# --------------------------------------------------------------------------
# FUNCTION-LEVEL: the extracted refresh_reused_worktree() against each state.
awk '/^refresh_reused_worktree\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$launcher" > "$work/fn.sh"
n=$(wc -l < "$work/fn.sh")
if [ "$n" -lt 10 ]; then
  echo "HARNESS REFUSES the function-level cases: refresh_reused_worktree() is not in $launcher (extracted $n lines)" >&2
  echo "RESULT: $pass pass / $fail fail before the refusal"
  exit 3
fi
bash -n "$work/fn.sh" || { echo "HARNESS REFUSES: extracted function does not parse" >&2; exit 3; }
call(){ # $1 wt, $2 branch, $3 base -> rc; stdout+stderr in $work/call.out
  bash -c "set -uo pipefail; bead=fortkit-xyz; $(cat "$work/fn.sh"); refresh_reused_worktree \"\$@\"" _ "$1" "$2" "$3" > "$work/call.out" 2>&1
}
# F1 ancestor branch (no bead commits): fast-forward, no merge commit, HEAD == main
r=$(mkfort f1); w="$r-worktrees/xyz"
call "$w" bead/xyz main; rc=$?
if [ "$rc" -eq 0 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$(git -C "$r" rev-parse main)" ] && [ "$(instrument "$w")" = "INSTRUMENT v2" ] && grep -q 'refreshed' "$work/call.out"; then
  ok "F1: a branch strictly behind main FAST-FORWARDS to main (direction (c)'s case, with no recut and no merge commit)"
else no "F1 fast-forward" "rc=$rc $(cat "$work/call.out")"; fi
# F2 diverged, clean: a merge commit with both parents; bead work kept; instrument current
r=$(mkfort f2); w="$r-worktrees/xyz"
echo bead-work > "$w/lib.txt"; git -C "$w" commit -qam "bead edit lib"; before=$(git -C "$w" rev-parse HEAD)
call "$w" bead/xyz main; rc=$?
after=$(git -C "$w" rev-parse HEAD); p1=$(git -C "$w" rev-parse HEAD^1 2>/dev/null); p2=$(git -C "$w" rev-parse HEAD^2 2>/dev/null)
if [ "$rc" -eq 0 ] && [ "$p1" = "$before" ] && [ "$p2" = "$(git -C "$r" rev-parse main)" ] \
   && [ "$(cat "$w/lib.txt")" = bead-work ] && [ "$(instrument "$w")" = "INSTRUMENT v2" ] \
   && git -C "$w" log -1 --format=%s | grep -q 'Proofdelve ForgeOs-lw8x, by forge.sh'; then
  ok "F2: a diverged branch gets ONE merge commit (parents: its old HEAD, main), keeps its own work, runs v2, and the commit message names the launcher"
else no "F2 clean merge" "rc=$rc p1=$p1 p2=$p2 before=$before after=$after $(cat "$work/call.out")"; fi
# F3 conflict: 76, HEAD unchanged, no MERGE_HEAD, no markers, tree clean
r=$(mkfort f3); w="$r-worktrees/xyz"
echo bead-side > "$w/subject.txt"; git -C "$w" commit -qam "bead subject"
echo main-side > "$r/subject.txt"; git -C "$r" commit -qam "main subject"
before=$(git -C "$w" rev-parse HEAD)
call "$w" bead/xyz main; rc=$?
if [ "$rc" -eq 76 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && clean_tree "$w" \
   && ! grep -q '^<<<<<<<' "$w/subject.txt" && [ "$(cat "$w/subject.txt")" = bead-side ] \
   && grep -q 'UNCHANGED' "$work/call.out" && grep -q 'CONFLICT' "$work/call.out"; then
  ok "F3: a conflicting merge returns 76, is backed out (HEAD unchanged, no MERGE_HEAD, no markers), and prints git's own CONFLICT line"
else no "F3 conflict" "rc=$rc head=$(git -C "$w" rev-parse HEAD) before=$before $(cat "$work/call.out" | tr '\n' '|')"; fi
# F4 dirty tracked file the merge would overwrite: refuse, dirt preserved byte-for-byte
r=$(mkfort f4); w="$r-worktrees/xyz"
printf '#!/bin/bash\necho "UNCOMMITTED forge edit"\n' > "$w/scripts/verify-impl.sh"; dirt=$(sha256sum "$w/scripts/verify-impl.sh")
before=$(git -C "$w" rev-parse HEAD)
call "$w" bead/xyz main; rc=$?
if [ "$rc" -eq 76 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && [ "$(sha256sum "$w/scripts/verify-impl.sh")" = "$dirt" ] \
   && ! git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
  ok "F4: a dirty tracked file the merge would overwrite makes it refuse (76) with the dirt preserved byte-for-byte"
else no "F4 dirty overwrite" "rc=$rc $(cat "$work/call.out" | tr '\n' '|')"; fi
# F5 already current: no-op, rc 0, HEAD unchanged
r=$(mkfort f5); w="$r-worktrees/xyz"; git -C "$w" merge -q --no-edit main >/dev/null 2>&1; before=$(git -C "$w" rev-parse HEAD)
call "$w" bead/xyz main; rc=$?
if [ "$rc" -eq 0 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && grep -q 'already contains' "$work/call.out"; then
  ok "F5: a worktree already containing main is a no-op (rc 0, HEAD unchanged)"
else no "F5 already current" "rc=$rc $(cat "$work/call.out")"; fi
# F6 detached HEAD: refuse, unchanged
r=$(mkfort f6); w="$r-worktrees/xyz"; git -C "$w" checkout -q --detach; before=$(git -C "$w" rev-parse HEAD)
call "$w" bead/xyz main; rc=$?
if [ "$rc" -eq 76 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && grep -q 'detached HEAD' "$work/call.out"; then
  ok "F6: a detached HEAD refuses (76) and names it"
else no "F6 detached" "rc=$rc $(cat "$work/call.out")"; fi
# F7 wrong branch checked out in the worktree: refuse, unchanged
r=$(mkfort f7); w="$r-worktrees/xyz"; git -C "$w" checkout -q -b other; before=$(git -C "$w" rev-parse HEAD)
call "$w" bead/xyz main; rc=$?
if [ "$rc" -eq 76 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && grep -q "on 'other', not bead/xyz" "$work/call.out"; then
  ok "F7: a worktree on the wrong branch refuses (76) and names both branches"
else no "F7 wrong branch" "rc=$rc $(cat "$work/call.out")"; fi
# F8 base ref that does not exist: refuse, unchanged
r=$(mkfort f8); w="$r-worktrees/xyz"; before=$(git -C "$w" rev-parse HEAD)
call "$w" bead/xyz no-such-branch; rc=$?
if [ "$rc" -eq 76 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] && clean_tree "$w"; then
  ok "F8: a base ref that does not resolve refuses (76) with the tree unchanged"
else no "F8 missing base" "rc=$rc $(cat "$work/call.out")"; fi
# F3b the Warden's finding 1: a worktree that ALREADY carries MERGE_HEAD on entry (a
# Forge left a conflicted `git merge main` and stopped) is refused WITHOUT the
# pre-existing merge being aborted -- the merge is not this launcher's to
# conclude, and aborting it then reporting "UNCHANGED" would hide a person's
# in-progress work. HEAD unchanged, MERGE_HEAD still present after.
r=$(mkfort f3b); w="$r-worktrees/xyz"
echo bead-side > "$w/subject.txt"; git -C "$w" commit -qam "bead subject"
echo main-side > "$r/subject.txt"; git -C "$r" commit -qam "main subject"
git -C "$w" merge --no-edit main >/dev/null 2>&1 || true   # leaves a conflict + MERGE_HEAD
before=$(git -C "$w" rev-parse HEAD)
git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 || { echo "  FAIL  F3b setup did not leave MERGE_HEAD"; fail=$((fail+1)); }
call "$w" bead/xyz main; rc=$?
if [ "$rc" -eq 76 ] && [ "$(git -C "$w" rev-parse HEAD)" = "$before" ] \
   && git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && grep -q 'a merge is already in progress' "$work/call.out"; then
  ok "F3b (finding 1): a pre-existing MERGE_HEAD is refused (76) WITHOUT being aborted -- HEAD unchanged, the in-progress merge left intact for a person"
else no "F3b pre-existing merge" "rc=$rc head=$(git -C "$w" rev-parse HEAD) mh=$(git -C "$w" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && echo present || echo GONE) $(cat "$work/call.out" | tr '\n' '|')"; fi

# F9 REFUSAL DISCRIMINATES: the same F3 fixture with the conflict REMOVED refreshes (the 76 is not unconditional)
r=$(mkfort f9); w="$r-worktrees/xyz"
echo bead-side > "$w/lib.txt"; git -C "$w" commit -qam "bead lib"
echo main-side > "$r/subject.txt"; git -C "$r" commit -qam "main subject"
call "$w" bead/xyz main; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$w/subject.txt")" = main-side ] && [ "$(cat "$w/lib.txt")" = bead-side ]; then
  ok "F9: two branches editing DIFFERENT files merge cleanly -- the refusal fires on conflicts, not on divergence"
else no "F9 divergence without conflict" "rc=$rc $(cat "$work/call.out")"; fi

# ==========================================================================
# STAMP-LEVEL (Proofdelve ForgeOs-mdwx): the three functions the handoff stamp became --
# forge_verify_line, forge_stamp_header, stamp_forge_handoff -- extracted from
# the shipped launcher and scored one case per observed class: (a) a malformed
# line 1 is normalised rather than refused, (b) a dirty tracked handoff commits
# its header only, (c) the verify outcome is stamped from a fixture stream.
# Refuses (exit 3) when the launcher does not define them, which is the honest
# result against a pre-mdwx launcher: unmeasured, never passed. Every case is
# a PROPERTY of the output (what line 1 says, what HEAD holds, which word the
# Verify line carries), not a spelling of the function's prose.
stamp_fns=(forge_verify_line forge_stamp_header stamp_forge_handoff)
awk '$0 ~ "^forge_seat_observed\\(\\)[[:space:]]*\\{" {p=1} p{print} p && /^\}$/{exit}' "$launcher" > "$work/seat.sh"   # Proofdelve ForgeOs-y4rg: may be empty against a pre-y4rg launcher
awk '$0 ~ "^forge_stamp_commit_warn\\(\\)[[:space:]]*\\{" {p=1} p{print} p && /^\}$/{exit}' "$launcher" > "$work/warn.sh"   # Proofdelve ForgeOs-lp2: a callee of stamp_forge_handoff; may be empty against a pre-lp2 launcher, and the lp2 WARNING case then FAILs rather than the whole section refusing
: > "$work/stamp.sh"
for f in "${stamp_fns[@]}"; do
  awk -v fn="$f" '$0 ~ ("^" fn "\\(\\)[[:space:]]*\\{") {p=1} p{print} p && /^\}$/{exit}' "$launcher" >> "$work/stamp.sh"
done
for f in "${stamp_fns[@]}"; do
  if ! grep -qE "^$f\\(\\)[[:space:]]*\\{" "$work/stamp.sh"; then
    echo "HARNESS REFUSES the stamp cases: $f() is not defined in $launcher (pre-Proofdelve ForgeOs-mdwx launcher); classes a/b/c are UNMEASURED, not passed" >&2
    echo "RESULT: $pass pass / $fail fail before the refusal"
    exit 3
  fi
done
bash -n "$work/stamp.sh" || { echo "HARNESS REFUSES: extracted stamp functions do not parse" >&2; exit 3; }
cat "$work/seat.sh" >> "$work/stamp.sh"
cat "$work/warn.sh" >> "$work/stamp.sh"

# Fixture: a worktree-shaped repo with a handoffs dir, a stub emit.sh that logs
# its argv, and an events dir the launcher reads. $1 name -> prints root.
mkstamp() {
  local r="$work/stamp-$1"
  git init -q "$r"; git -C "$r" config user.email h@x; git -C "$r" config user.name harness
  mkdir -p "$r/fort/handoffs" "$r/fort/scripts" "$r/fort/events"
  printf '#!/bin/bash\nprintf "EMIT %%s\\n" "$*" >> "%s/emitted"\n' "$r" > "$r/fort/scripts/emit.sh"; chmod +x "$r/fort/scripts/emit.sh"
  echo base > "$r/base.txt"; git -C "$r" add -A; git -C "$r" commit -qm base
  printf '%s' "$r"
}
# One event line in the fort's shape; $1 root $2 day $3 ts $4 category $5 tree $6 extra-payload-json
ev() { printf '{"ts":"%s","actor":"harness","seat":null,"category":"%s","target":"bead/x","detail":"d","payload":{"steps":[],"tree":"%s"%s}}\n' "$3" "$4" "$5" "$6" >> "$1/fort/events/events-$2.jsonl"; }
stamp() {  # $1 root $2 handoff -> runs the shipped stamp against the fixture
  # shellcheck source=/dev/null
  ( source "$work/stamp.sh"; stamp_forge_handoff "$2" "$1" fortkit-xyz gpt-5.6-terra "2026-09-13T10:00:00-08:00" "$1/fort/events" "$1/fort/scripts/emit.sh" ) >"$work/stamp.out" 2>&1
}
body='## State of work
work.
## Verified facts
- none
## Next actions
- next
## Open risks / questions
- none
## Failed attempts
- none
'

# ---- class (a): line 1 without the word Forge is NORMALISED, not refused
r=$(mkstamp a1); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s' "$body" > "$h"
stamp "$r" "$h"
if [ "$(sed -n 1p "$h" | cut -c1-17)" = "# Handoff: Forge " ] && [ "$(sed -n 2p "$h")" = "Model: gpt-5.6-terra" ] && sed -n 3p "$h" | grep -q '^Verify: ' \
   && grep -q '"repaired":"line1"' "$r/emitted" && [ "$(sed -n 4p "$h")" = "## State of work" ]; then
  ok "S-a1: line 1 lacking the word Forge is rewritten to '# Handoff: Forge <ts>', Model: takes the launcher's rung, a Verify: line follows, and the repair is recorded in the handoff.written payload"
else no "S-a1 normalise line 1" "$(head -4 "$h" | tr '\n' '|') emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi

r=$(mkstamp a2); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '%s' "$body" > "$h"       # no header at all: the seat started at the first heading
stamp "$r" "$h"
if [ "$(sed -n 1p "$h" | cut -c1-17)" = "# Handoff: Forge " ] && [ "$(sed -n 2p "$h")" = "Model: gpt-5.6-terra" ] && sed -n 3p "$h" | grep -q '^Verify: ' \
   && [ "$(sed -n 4p "$h")" = "## State of work" ] && grep -q '"repaired":"line1,model"' "$r/emitted"; then
  ok "S-a2: a handoff with no header at all gets the three header lines INSERTED above its first line, which is kept; repaired=line1,model"
else no "S-a2 headerless handoff" "$(head -4 "$h" | tr '\n' '|') emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi

r=$(mkstamp a3); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s' "$body" > "$h"
stamp "$r" "$h"
if [ "$(sed -n 2p "$h")" = "Model: gpt-5.6-terra" ] && grep -q '"repaired":""' "$r/emitted" && [ "$(grep -c '^Model:' "$h")" -eq 1 ] && [ "$(grep -c '^# Handoff:' "$h")" -eq 1 ]; then
  ok "S-a3 (vacuity): a well-formed header is stamped in place -- one header line, one Model: line, repaired is empty"
else no "S-a3 well-formed header" "$(head -3 "$h" | tr '\n' '|') emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi

# ---- class (b): the stamp commit carries the HEADER ONLY when the seat left the file dirty
r=$(mkstamp b1); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s' "$body" > "$h"
git -C "$r" add -A; git -C "$r" commit -qm "fortkit-xyz: handoff"
printf '\nthis update is intentionally uncommitted\n' >> "$h"
stamp "$r" "$h"
head_copy="$(git -C "$r" show HEAD:fort/handoffs/forge-2026-09-13-xyz.md)"
if ! grep -q 'intentionally uncommitted' <<<"$head_copy" && printf '%s' "$head_copy" | sed -n 2p | grep -q '^Model: gpt-5.6-terra' \
   && grep -q 'intentionally uncommitted' "$h" && [ "$(sed -n 2p "$h")" = "Model: gpt-5.6-terra" ] \
   && [ "$(git -C "$r" status --porcelain -- fort/handoffs)" = " M fort/handoffs/forge-2026-09-13-xyz.md" ] \
   && git -C "$r" log -1 --format=%B | grep -q 'header only' && grep -q '"dirtyWhenStamped":true' "$r/emitted"; then
  ok "S-b1: a tracked handoff with unstaged post-stop edits -- HEAD gains the stamped header and NOT the uncommitted paragraph; the working copy keeps the paragraph, stamped, still unstaged; the message says header only"
else no "S-b1 header-only commit" "HEAD=$(printf '%s' "$head_copy" | tr '\n' '|') wt=$(head -3 "$h" | tr '\n' '|') status=$(git -C "$r" status --porcelain -- fort/handoffs) msg=$(git -C "$r" log -1 --format=%s)"; fi

r=$(mkstamp b2); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s' "$body" > "$h"     # untracked: the seat never committed it
stamp "$r" "$h"
if git -C "$r" ls-files --error-unmatch fort/handoffs/forge-2026-09-13-xyz.md >/dev/null 2>&1 && [ -z "$(git -C "$r" status --porcelain -- fort/handoffs)" ] \
   && git -C "$r" log -1 --format=%B | grep -q 'committed whole' && grep -q '"dirtyWhenStamped":false' "$r/emitted"; then
  ok "S-b2: an UNTRACKED handoff is committed whole by the launcher and the message says so (nothing was swept: the seat had committed nothing)"
else no "S-b2 untracked handoff" "status=$(git -C "$r" status --porcelain -- fort/handoffs) msg=$(git -C "$r" log -1 --format=%s)"; fi

r=$(mkstamp b3); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s' "$body" > "$h"
git -C "$r" add -A; git -C "$r" commit -qm "fortkit-xyz: handoff"
echo other > "$r/base.txt"     # a DIFFERENT dirty file must not be swept either
stamp "$r" "$h"
if [ "$(git -C "$r" diff HEAD~1 HEAD --stat -- . | grep -c '|')" -eq 1 ] && git -C "$r" diff HEAD~1 HEAD --name-only | grep -q '^fort/handoffs/' \
   && [ "$(git -C "$r" status --porcelain -- base.txt)" = " M base.txt" ]; then
  ok "S-b3: a clean tracked handoff commits its header diff alone; a dirty SIBLING file is untouched by the stamp commit"
else no "S-b3 clean handoff, dirty sibling" "$(git -C "$r" diff HEAD~1 HEAD --stat | tr '\n' '|') status=$(git -C "$r" status --porcelain | tr '\n' '|')"; fi

# ---- class (c): the Verify: line comes from the event stream, keyed on tree + time
# shellcheck source=/dev/null
vline() { ( source "$work/stamp.sh"; forge_verify_line "$1" "2026-09-13T10:00:00-08:00" "$2/fort/events" ) 2>/dev/null; }
r=$(mkstamp c1)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.pass "$r" ',"docker":false,"commit":"abc1234"'
v="$(vline "$r" "$r")"
case "$v" in "Verify: PASS 2026-09-13T10:06:00-08:00 commit abc1234 docker:false"*) ok "S-c1: a verify.run followed by verify.pass for THIS tree stamps 'Verify: PASS <ts> commit <sha> docker:false'" ;; *) no "S-c1 pass" "$v" ;; esac

# jdpb3: a pass on a dirty / moving tree names NO commit and says why (the push-ready rule); a clean pass still does
r=$(mkstamp c1d)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.pass "$r" ',"docker":false,"commit":"abc1234","dirtyAtStart":true,"headMoved":true,"commitAtEnd":"fee11dbc"'
v="$(vline "$r" "$r")"
case "$v" in "Verify: PASS 2026-09-13T10:06:00-08:00 commit NONE -- NOT A VERDICT for any commit (dirtyAtStart:true headMoved:true; started at abc1234, commitAtEnd fee11dbc"*) ok "jdpb3: a pass with dirtyAtStart/headMoved stamps 'commit NONE -- NOT A VERDICT', naming the markers and both commits, never 'commit abc1234'" ;; *) no "jdpb3 not-a-verdict pass" "$v" ;; esac
r=$(mkstamp c1e)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.fail "$r" ',"step":"dotnet-test","exitCode":1,"commit":"abc1234","dirtyAtEnd":true,"dirtyAtStart":false,"headMoved":false'
v="$(vline "$r" "$r")"
case "$v" in "Verify: FAIL 2026-09-13T10:06:00-08:00 at dotnet-test (exit 1) commit NONE -- NOT A VERDICT for any commit (dirtyAtEnd:true;"*) ok "jdpb3: a FAIL on a tree dirtied during the run names no commit either, and false markers are not listed" ;; *) no "jdpb3 not-a-verdict fail" "$v" ;; esac

r=$(mkstamp c2)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.fail "$r" ',"step":"dotnet-test","exitCode":1,"commit":"abc1234"'
v="$(vline "$r" "$r")"
case "$v" in "Verify: FAIL 2026-09-13T10:06:00-08:00 at dotnet-test (exit 1)"*) ok "S-c2: a paired verify.fail stamps 'Verify: FAIL <ts> at <step> (exit N)'" ;; *) no "S-c2 fail" "$v" ;; esac

r=$(mkstamp c3)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run "$r" ',"commit":"abc1234"'
v="$(vline "$r" "$r")"
case "$v" in "Verify: NO-OUTCOME -- verify.run started 2026-09-13T10:05:00-08:00"*) ok "S-c3: a verify.run with no verify.pass/fail after it stamps NO-OUTCOME (the 'no verify.pass was emitted' claim, made by the launcher only when it is true)" ;; *) no "S-c3 no outcome" "$v" ;; esac

r=$(mkstamp c4)
ev "$r" 2026-09-13 2026-09-13T09:00:00-08:00 verify.run  "$r" ',"commit":"old0000"'     # before launch
ev "$r" 2026-09-13 2026-09-13T09:01:00-08:00 verify.pass "$r" ',"docker":true,"commit":"old0000"'
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r-other" ',"commit":"abc1234"'   # another tree
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.pass "$r-other" ',"docker":true,"commit":"abc1234"'
# the grep-trap control: an event whose DETAIL names this tree but whose payload.tree is another
printf '{"ts":"2026-09-13T10:07:00-08:00","actor":"fleet","seat":"fleet","category":"verify.pass","target":"fortkit-xyz","detail":"green in %s","payload":{"tree":"%s-other"}}\n' "$r" "$r" >> "$r/fort/events/events-2026-09-13.jsonl"
v="$(vline "$r" "$r")"
case "$v" in "Verify: NO-RUN -- "*) ok "S-c4: a pass BEFORE launch, a pass for ANOTHER tree, and a pass whose detail merely names this tree all count for nothing -- NO RUN (keyed on payload.tree and the launch timestamp)" ;; *) no "S-c4 negative controls" "$v" ;; esac

r=$(mkstamp c5)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.fail "$r" ',"step":"web-test","exitCode":1,"commit":"abc1234"'
ev "$r" 2026-09-14 2026-09-14T00:10:00-08:00 verify.run  "$r" ',"commit":"def5678"'   # the newest run, across midnight
ev "$r" 2026-09-14 2026-09-14T00:11:00-08:00 verify.pass "$r" ',"docker":false,"commit":"def5678"'
v="$(vline "$r" "$r")"
case "$v" in "Verify: PASS 2026-09-14T00:11:00-08:00 commit def5678"*) ok "S-c5: the NEWEST verify.run wins and its outcome is read across a midnight file boundary (an earlier red run does not stick)" ;; *) no "S-c5 newest run across midnight" "$v" ;; esac

r=$(mkstamp c6); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.pass "$r" ',"docker":false,"commit":"abc1234"'
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s\nno verify.pass was emitted, I think.\n' "$body" > "$h"
stamp "$r" "$h"
if [ "$(sed -n 3p "$h" | cut -c1-13)" = "Verify: PASS " ] && grep -q '"verify":"PASS"' "$r/emitted"; then
  ok "S-c6: end to end -- a seat's prose saying no verify.pass was emitted sits beneath a launcher header line saying PASS, and the payload carries verify=PASS"
else no "S-c6 end to end" "$(head -3 "$h" | tr '\n' '|') emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi

# ---- round-two folds (the Warden's non-blocking findings on 71a4576)
r=$(mkstamp d1); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s\nVerify: I could not tell.\n' "$body" > "$h"   # a BODY line beginning Verify:
stamp "$r" "$h"
if [ "$(sed -n 3p "$h" | cut -c1-8)" = "Verify: " ] && grep -q '^Verify: I could not tell\.$' "$h" && [ "$(grep -c '^Verify:' "$h")" -eq 2 ]; then
  ok "S-d1 (f1): a seat sentence beginning Verify: in the BODY is left alone; the launcher's Verify: line is inserted in the header block"
else no "S-d1 body Verify: line" "$(grep -n '^Verify:' "$h" | tr '\n' '|')"; fi

r=$(mkstamp d2); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
printf '{"ts":"2026-09-13T10:06:00-08:00","actor":"harness","seat":null,"category":"verify.fail","target":"bead/x","detail":"d","payload":{"tree":"%s","step":"a\\nInjected: line","exitCode":1,"commit":"abc1234"}}\n' "$r" >> "$r/fort/events/events-2026-09-13.jsonl"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s' "$body" > "$h"
stamp "$r" "$h"
if [ "$(sed -n 3p "$h" | cut -c1-13)" = "Verify: FAIL " ] && ! grep -q '^Injected:' "$h" && [ "$(sed -n 4p "$h")" = "## State of work" ]; then
  ok "S-d2 (f6): a backslash-n inside a forged step name does not become a header line (values reach awk via ENVIRON, not -v)"
else no "S-d2 escape injection" "$(head -5 "$h" | tr '\n' '|')"; fi

r=$(mkstamp d3); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
: > "$h"    # an EMPTY handoff: the transform cannot complete a header and must refuse, touching nothing
stamp "$r" "$h"; rc=$?
leftovers=$(find "$r/fort/handoffs" -mindepth 1 ! -name 'forge-2026-09-13-xyz.md' | wc -l)
if [ "$rc" -ne 0 ] && [ ! -s "$h" ] && [ ! -e "$r/emitted" ] && [ "$leftovers" -eq 0 ]; then
  ok "S-d3 (f7): an empty handoff is REFUSED (rc=$rc) -- file untouched, nothing emitted, no temp file left in fort/handoffs"
else no "S-d3 refusal path" "rc=$rc size=$(wc -c < "$h") emitted=$([ -e "$r/emitted" ] && cat "$r/emitted") leftovers=$leftovers"; fi

r=$(mkstamp d4)
v="$(vline "$r" "$r")"
case "$(printf '%s' "$v" | awk '{print $2}')" in NO-RUN) ok "S-d4 (f2): the second word of the Verify: line is a single token (NO-RUN here), so the payload field is queryable" ;; *) no "S-d4 token" "$v" ;; esac


# ---- Proofdelve ForgeOs-y4rg: the launcher RECONCILES the seat's observation with the stream
# The seat writes `Seat-observed: PASS|FAIL|NONE-SEEN <ts>` in the header block;
# forge_verify_line takes it as a 4th argument and the Verify: line says whether
# the stream agrees, SUPERSEDES it (the outcome landed after the seat looked) or
# CONTRADICTS it. Against a pre-y4rg launcher the 4th argument is ignored and
# every case below FAILS -- the positive control; nothing here refuses.
# shellcheck source=/dev/null
vline4() { ( source "$work/stamp.sh"; forge_verify_line "$1" "2026-09-13T10:00:00-08:00" "$2/fort/events" "$3" ) 2>/dev/null; }
r=$(mkstamp y1)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:05:50-08:00 verify.pass "$r" ',"docker":false,"commit":"abc1234"'
v="$(vline4 "$r" "$r" "NONE-SEEN 2026-09-13T10:05:12-08:00")"
case "$v" in "Verify: PASS 2026-09-13T10:05:50-08:00 commit abc1234"*"SUPERSEDES the seat's Seat-observed: NONE-SEEN 2026-09-13T10:05:12-08:00 (the outcome landed 38 s after the seat looked)"*) ok "y4rg-1: seat NONE-SEEN then stream PASS -> the line says SUPERSEDES and names the 38 s gap (the 5eej r2 shape)" ;; *) no "y4rg-1 supersedes" "$v" ;; esac
if [ "$(printf '%s' "$v" | wc -l)" -eq 0 ]; then ok "y4rg-1b: the reconciled line is still ONE line"; else no "y4rg-1b one line" "$v"; fi

r=$(mkstamp y2)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
v="$(vline4 "$r" "$r" "NONE-SEEN 2026-09-13T10:05:12-08:00")"
case "$v" in "Verify: NO-OUTCOME -- "*"Seat-observed: NONE-SEEN 2026-09-13T10:05:12-08:00 agrees; nothing is established"*) ok "y4rg-2: seat NONE-SEEN and stream NO-OUTCOME -> agrees, nothing established (the refusal SURVIVES; no silent upgrade)" ;; *) no "y4rg-2 refusal survives" "$v" ;; esac

r=$(mkstamp y3)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.pass "$r" ',"docker":true,"commit":"abc1234"'
v="$(vline4 "$r" "$r" "PASS 2026-09-13T10:06:00-08:00")"
case "$v" in "Verify: PASS 2026-09-13T10:06:00-08:00"*"agrees with the seat's Seat-observed: PASS 2026-09-13T10:06:00-08:00"*) ok "y4rg-3: seat PASS and stream PASS -> agrees" ;; *) no "y4rg-3 agrees" "$v" ;; esac

r=$(mkstamp y4)
v="$(vline4 "$r" "$r" "PASS 2026-09-13T10:06:00-08:00")"
case "$v" in "Verify: NO-RUN -- "*"CONTRADICTS the seat's Seat-observed: PASS 2026-09-13T10:06:00-08:00; the stream is authoritative"*) ok "y4rg-4: seat claims PASS, stream has NO RUN -> CONTRADICTS, stream authoritative (the threat-2 shape, mdwx f6)" ;; *) no "y4rg-4 contradicts" "$v" ;; esac

r=$(mkstamp y5)
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:06:00-08:00 verify.fail "$r" ',"step":"dotnet-test","exitCode":1,"commit":"abc1234"'
v="$(vline4 "$r" "$r" "")"
case "$v" in "Verify: FAIL 2026-09-13T10:06:00-08:00 at dotnet-test (exit 1)"*"the seat recorded no Seat-observed line"*) ok "y4rg-5: no token at all -> the line says so; the stream outcome is unchanged" ;; *) no "y4rg-5 absent token" "$v" ;; esac

# end to end through stamp_forge_handoff: the token is read from the HEADER BLOCK
# only, the payload carries seatObserved and seatContradiction, and a Seat-observed
# line in the BODY is ignored (same header/body rule as mdwx f1).
r=$(mkstamp y6); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
ev "$r" 2026-09-13 2026-09-13T10:05:00-08:00 verify.run  "$r" ',"commit":"abc1234"'
ev "$r" 2026-09-13 2026-09-13T10:05:50-08:00 verify.pass "$r" ',"docker":false,"commit":"abc1234"'
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\nSeat-observed: NONE-SEEN 2026-09-13T10:05:12-08:00\n%s\nSeat-observed: PASS 2026-09-13T10:05:50-08:00\n' "$body" > "$h"
stamp "$r" "$h"
if grep -q '^Verify: PASS .*SUPERSEDES the seat.s Seat-observed: NONE-SEEN 2026-09-13T10:05:12-08:00' "$h" && grep -q '"seatObserved":"NONE-SEEN"' "$r/emitted" && grep -q '"seatContradiction":false' "$r/emitted"; then
  ok "y4rg-6: end to end -- the header token is read (the body's later Seat-observed: PASS is ignored), the Verify: line reconciles, the payload carries seatObserved=NONE-SEEN and seatContradiction=false"
else no "y4rg-6 end to end" "$(grep -n '^Verify:\|^Seat-observed:' "$h" | tr '\n' '|') emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi

r=$(mkstamp y7); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\nSeat-observed: PASS 2026-09-13T10:06:00-08:00\n%s' "$body" > "$h"
stamp "$r" "$h"
if grep -q '^Verify: NO-RUN .*CONTRADICTS' "$h" && grep -q '"seatContradiction":true' "$r/emitted"; then
  ok "y4rg-7: end to end -- a seat PASS with no run on the stream sets seatContradiction=true in handoff.written"
else no "y4rg-7 contradiction flag" "$(grep -n '^Verify:' "$h" | tr '\n' '|') emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi

# ---- Proofdelve ForgeOs-eng3.18: the Seat-observed WORD is validated; a malformed line is
# MALFORMED, never a CONTRADICTION, and the payload word is one of five literals.
# Against the pre-eng3.18 launcher: e1 scores CONTRADICTS (the threat-2 flag on
# a typo), e2's quoted word breaks the -p JSON and the event is never emitted.
r=$(mkstamp e1); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\nSeat-observed: NONESEEN 2026-09-13T10:05:12-08:00\n%s' "$body" > "$h"
stamp "$r" "$h"
if grep -q '^Verify: NO-RUN .*MALFORMED' "$h" && grep -q '"seatObserved":"MALFORMED"' "$r/emitted" && grep -q '"seatContradiction":false' "$r/emitted"; then
  ok "eng3.18-1: NONESEEN (a typo) -> Verify: names MALFORMED, seatObserved=MALFORMED, seatContradiction=false"
else no "eng3.18-1 malformed word" "$(grep -n '^Verify:' "$h" | tr '\n' '|') emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi

r=$(mkstamp e2); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\nSeat-observed: "NONE-SEEN" 2026-09-13T10:05:12-08:00\n%s' "$body" > "$h"
stamp "$r" "$h"
if grep -q '"seatObserved":"MALFORMED"' "$r/emitted" 2>/dev/null && grep -q 'handoff.written' "$r/emitted"; then
  ok "eng3.18-2: a double-quoted word -> the handoff.written event IS emitted (stub records it), seatObserved=MALFORMED"
else no "eng3.18-2 quoted word still emits" "emitted=$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi

r=$(mkstamp e3); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\nSeat-observed: PASS 2026-09-13T10:06:00-08:00\n%s' "$body" > "$h"
stamp "$r" "$h"
if grep -q '^Verify: NO-RUN .*CONTRADICTS' "$h" && grep -q '"seatContradiction":true' "$r/emitted"; then
  ok "eng3.18-3: a genuine contradiction (seat PASS, stream NO-RUN) still sets seatContradiction=true (y4rg-7 unchanged)"
else no "eng3.18-3 genuine contradiction" "$(grep -n '^Verify:' "$h" | tr '\n' '|')"; fi

# ---- Proofdelve ForgeOs-lp2: a tolerated stamp-commit failure WARNS, never aborts, never
# silent. Fixture: a pre-commit hook that refuses, the shape agk r2 f2 named.
# Property: the stamp lands on disk, the launcher's stderr carries a WARNING
# naming the bead, handoff.written is still emitted, and the function returns 0.
# Against a pre-lp2 launcher the commit fails SILENTLY (`|| true`) and the
# WARNING case FAILs -- the positive control; the other three pass either way
# and are here to show the fix did not trade the silence for an abort.
r=$(mkstamp lp2a); h="$r/fort/handoffs/forge-2026-09-13-xyz.md"
printf '#!/bin/sh\necho "hook refuses" >&2; exit 1\n' > "$r/.git/hooks/pre-commit"; chmod +x "$r/.git/hooks/pre-commit"
printf '# Handoff: Forge 2026-09-13T00:47:00-08:00\nModel: GPT-5\n%s' "$body" > "$h"
# shellcheck source=/dev/null
( source "$work/stamp.sh"; stamp_forge_handoff "$h" "$r" fortkit-xyz gpt-5.6-terra "2026-09-13T10:00:00-08:00" "$r/fort/events" "$r/fort/scripts/emit.sh" ) >"$work/lp2.out" 2>"$work/lp2.err"; lp2_rc=$?
if grep -q 'WARNING handoff stamp .*failed for fortkit-xyz' "$work/lp2.err"; then
  ok "lp2: a refused stamp commit WARNS on stderr and names the bead (not silent)"
else no "lp2: the refused stamp commit was silent" "stderr=$(tr '\n' '|' < "$work/lp2.err")"; fi
if [ "$lp2_rc" -eq 0 ] && grep -q '^Verify: ' "$h"; then
  ok "lp2: the stamp still lands on disk and the function returns 0 (warn, not abort)"
else no "lp2: the stamp aborted or did not land" "rc=$lp2_rc $(grep -n '^Verify:' "$h" | tr '\n' '|')"; fi
if grep -q 'handoff.written' "$r/emitted"; then ok "lp2: handoff.written is still emitted after the refused commit"; else no "lp2: no handoff.written" "$(cat "$r/emitted" 2>/dev/null | tr '\n' '|')"; fi
if ! git -C "$r" cat-file -e HEAD:fort/handoffs/forge-2026-09-13-xyz.md 2>/dev/null; then
  ok "lp2: the fixture's refusal was real -- HEAD does not carry the handoff after the hook refused (the WARNING describes a true state; the file is staged, not committed)"
else no "lp2: the hook did not refuse" "HEAD carries the handoff; the fixture measured nothing"; fi
# uyu f3 (folded here per the bead's notes): the launcher's handoff instruction
# is NOT appended onto the bead's text. Property: nothing in the launcher
# appends to desc, and the prompt carries a labelled launcher section.
if ! grep -q '^  desc+=' "$launcher" && grep -q '^  handoff_instruction="Before you finish' "$launcher" && grep -q '^LAUNCHER INSTRUCTION -- from forge.sh' "$launcher"; then
  ok "lp2/uyu-f3: the handoff instruction travels in its own labelled LAUNCHER INSTRUCTION section, never appended onto the bead text"
else no "lp2/uyu-f3: the fort instruction still rides inside \$desc" "desc+= lines: $(grep -c '^  desc+=' "$launcher")"; fi

# ---- Proofdelve ForgeOs-4hzq(A): the prompt-size guard refuses before bwrap -----------
# The prompt now travels on stdin, so this ceiling is a backstop. Against a
# pre-4hzq forge.sh (FORGE_SH=<old>) the function is absent and these three
# report FAIL -- the positive control.
if grep -qE '^guard_prompt_size\(\)[[:space:]]*\{' "$launcher" && grep -q '^PROMPT_CEILING=' "$launcher"; then
  eval "$(grep -m1 '^PROMPT_CEILING=' "$launcher"; grep -m1 -E '^guard_prompt_size\(\)[[:space:]]*\{' "$launcher")"
  if guard_prompt_size "a short prompt"; then ok "4hzq(A): a small prompt is accepted"; else no "4hzq(A): small prompt rejected" "guard refused a short prompt"; fi
  big="$(head -c "$((PROMPT_CEILING + 1))" /dev/zero | tr '\0' x)"
  if guard_prompt_size "$big"; then no "4hzq(A): an oversized prompt was accepted" "guard passed ${#big} bytes > $PROMPT_CEILING"; else ok "4hzq(A): a prompt over the ${PROMPT_CEILING}-char ceiling is refused"; fi
  # shellcheck disable=SC2016  # a grep PATTERN: the $ is literal, not an expansion
  gl="$(grep -n 'guard_prompt_size "\$prompt"' "$launcher" | head -1 | cut -d: -f1)"
  # shellcheck disable=SC2016  # a grep PATTERN: literal, not an expansion
  bl="$(grep -n 'bwrap "\${mask\[@\]}" -- codex exec' "$launcher" | head -1 | cut -d: -f1)"
  if [ -n "$gl" ] && [ -n "$bl" ] && [ "$gl" -lt "$bl" ]; then ok "4hzq(A): the size guard is consulted before the bwrap/codex-exec call (line $gl < $bl)"; else no "4hzq(A): the guard is not before bwrap" "guard line '${gl:-none}', bwrap line '${bl:-none}'"; fi
else
  no "4hzq(A): a small prompt is accepted" "this forge.sh has no guard_prompt_size/PROMPT_CEILING (pre-4hzq launcher)"
  no "4hzq(A): a prompt over the ceiling is refused" "pre-4hzq launcher"
  no "4hzq(A): the size guard is consulted before bwrap" "pre-4hzq launcher"
fi

# ---- Proofdelve ForgeOs-nz3u: the deliverable declaration reaches the Forge prompt -----
# The fleet half (fleet.sh lets a declared handoff-only bead proceed) is the
# governor harness's nz3u cases and e2e scenario 56. This is the launcher half:
# forge_deliverable_of() reads the rendered bead, and the prompt carries the
# labelled DELIVERABLE section only on a declared bead and never on a smoke.
# Against a pre-nz3u forge.sh (FORGE_SH=<old>) the function is absent and all
# three report FAIL -- the positive control.
if grep -qE '^forge_deliverable_of\(\)[[:space:]]*\{' "$launcher"; then
  eval "$(awk '/^forge_deliverable_of\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$launcher")"
  d1="$(printf 'DESCRIPTION\n\n  Touches: fort/\n  Deliverable: answer\n\nACCEPTANCE' | forge_deliverable_of)"
  d2="$(printf '  Deliverable:   Answer  \n' | forge_deliverable_of)"
  d3="$(printf 'the deliverable: answer is prose, not a line\nTouches: x\n' | forge_deliverable_of)"
  d4="$(printf 'Deliverable: diff\n' | forge_deliverable_of)"
  if [ "$d1" = answer ] && [ "$d2" = answer ] && [ -z "$d3" ] && [ "$d4" = diff ]; then
    ok "nz3u: forge_deliverable_of reads a 'Deliverable: <word>' LINE off the rendered bead (indented, case-folded), not prose that mentions the word"
  else no "nz3u: forge_deliverable_of parsing" "d1=[$d1] d2=[$d2] d3=[$d3] d4=[$d4]"; fi
  # the section is gated on the literal 'answer' AND on not being a smoke, and the prompt carries it.
  # Later sections may follow it on that line (Proofdelve ForgeOs-6niaz added the FIX-FORWARD lap section);
  # the property is that the deliverable section is in the prompt after the launcher section.
  # shellcheck disable=SC2016  # the single quotes are the point: these are source assertions on forge.sh's own $-bearing lines
  if grep -q '^if \[ "\${FORGE_SMOKE:-0}" != "1" \] && \[ "\$(printf .%s\\n. "\$desc" | forge_deliverable_of)" = answer \]; then$' "$launcher" \
     && grep -q '^\$desc\$launcher_section\$deliverable_section\(\$[a-z_]*\)*"$' "$launcher" \
     && grep -q "^This bead's deliverable is an answer. Write it in your handoff. Do not change product code in order to have a diff." "$launcher"; then
    ok "nz3u: the DELIVERABLE section is gated on the literal 'answer' and on not being a smoke, carries the approved sentence, and is appended to the prompt after the launcher section"
  else no "nz3u: the deliverable section is missing, ungated, or not in the prompt" "gate=$(grep -c 'forge_deliverable_of)" = answer' "$launcher") tail=$(grep -c 'launcher_section.deliverable_section' "$launcher") sentence=$(grep -c "deliverable is an answer. Write it in your handoff" "$launcher")"; fi
  # the section is NOT appended onto desc (the lp2/uyu-f3 property, kept)
  if ! grep -q '^  desc+=' "$launcher"; then ok "nz3u: the deliverable sentence travels in its own labelled section, never appended onto the bead text (lp2/uyu-f3 kept)"
  else no "nz3u: something appends to desc again" "$(grep -n '^  desc+=' "$launcher")"; fi
else
  no "nz3u: forge_deliverable_of parses the declaration" "this forge.sh has no forge_deliverable_of (pre-nz3u launcher): a declared bead's Forge is never told its deliverable is an answer"
  no "nz3u: the DELIVERABLE section is in the prompt" "pre-nz3u launcher"
  no "nz3u: the section is not appended onto desc" "pre-nz3u launcher"
fi

# ---- Proofdelve ForgeOs-4hzq(B): the session exit code is propagated ------------------
# Structural: the launcher's last executable line is `exit "$rc"`. Against a
# pre-4hzq forge.sh this is the trailing echo -- the positive control.
last_exec="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$launcher" | tail -1)"
# shellcheck disable=SC2016  # 'exit "$rc"' and the labels are LITERALS compared/printed, not expansions
if [ "$last_exec" = 'exit "$rc"' ]; then ok '4hzq(B): forge.sh ends by propagating the session exit code (exit "$rc")'; else no '4hzq(B): forge.sh does not end with exit "$rc"' "last executable line: $last_exec"; fi
# Plumbing invariant (launcher-independent): the fleet dispatch child writes the
# child's exit status to $wdir/exit, so a Forge that exits 126 is recorded as 126.
wd="$work/wexit"; mkdir -p "$wd"; sr="$work/stubroot/fort/scripts"; mkdir -p "$sr"
printf '#!/bin/bash\nexit 126\n' > "$sr/forge.sh"; chmod +x "$sr/forge.sh"
# shellcheck disable=SC2016  # the single-quoted body is the CHILD's script; $1..$4 are its positionals, not this shell's
( nohup setsid bash -c 'echo $$ > "$3/pid"; "$1/fort/scripts/forge.sh" "$2" "$4" >"$3/forge.log" 2>&1; echo $? > "$3/exit"' _ "$work/stubroot" fortkit-x "$wd" m >/dev/null 2>&1 & )
for _ in $(seq 1 60); do [ -s "$wd/exit" ] && break; sleep 0.1; done
if [ "$(cat "$wd/exit" 2>/dev/null)" = 126 ]; then ok "4hzq(B): a Forge that exits 126 is recorded as 126 in \$wdir/exit (fleet dispatch child)"; else no "4hzq(B): exit 126 not recorded" "got '$(cat "$wd/exit" 2>/dev/null)'"; fi

# ---- Proofdelve ForgeOs-pwu6: the FORGE_SMOKE completeness gate ------------------------
# forge_smoke_score() and FORGE_SMOKE_EXPECTED are extracted from the launcher
# and run against fixture transcripts. Against a pre-pwu6 forge.sh (FORGE_SH=<old>)
# both are absent and every case here reports FAIL -- the positive control; the
# 2026-09-14 16:01 transcript shape (probes 1-8 and 23, no terminator, exit 0)
# is fixture (b). Each case asserts the PROPERTY (the return code and the
# counts), never the table's wording.
if grep -qE '^forge_smoke_score\(\)[[:space:]]*\{' "$launcher" && grep -q '^  FORGE_SMOKE_EXPECTED=' "$launcher"; then
  awk '$0 ~ "^forge_smoke_score\\(\\)[[:space:]]*\\{" {p=1} p{print} p && /^\}$/{exit}' "$launcher" > "$work/smoke.sh"
  grep -m1 '^  FORGE_SMOKE_EXPECTED=' "$launcher" >> "$work/smoke.sh"
  bash -n "$work/smoke.sh" || { echo "HARNESS REFUSES: extracted forge_smoke_score does not parse" >&2; exit 3; }
  # shellcheck disable=SC1091  # the extracted function, generated at run time
  source "$work/smoke.sh"
  smoke_pass=0; smoke_fail=0; smoke_missing=""; smoke_complete=0   # set by the extracted function; declared so shellcheck sees them
  smoke_fixture() {  # $1 out, $2 probe numbers, $3 verdict word, $4 1=terminator
    local n; : > "$1"
    for n in $2; do printf 'PROBE %s: some evidence -> %s  \n' "$n" "$3" >> "$1"; done
    [ "$4" = 1 ] && echo 'FORGE-SMOKE-COMPLETE' >> "$1"; return 0
  }
  sm_all="$FORGE_SMOKE_EXPECTED"
  smoke_fixture "$work/sm-a.log" "$sm_all" PASS 1
  if forge_smoke_score "$work/sm-a.log" >/dev/null && [ "$smoke_pass" -eq 23 ] && [ "$smoke_missing" = "" ] && [ "$smoke_complete" -eq 1 ]; then
    ok "pwu6-a: a transcript with every probe line and the terminator is COMPLETE (23 PASS, 0 missing)"
  else no "pwu6-a: complete transcript" "pass=$smoke_pass missing=[$smoke_missing] complete=$smoke_complete"; fi
  smoke_fixture "$work/sm-b.log" "1 2 3 4 5 6 7 8 23" PASS 0
  echo "I did not run probes 9-22 because they conflict with the Forge's mandatory safety boundaries." >> "$work/sm-b.log"
  if ! forge_smoke_score "$work/sm-b.log" >/dev/null && [ "${smoke_missing# }" = "9 10 11 12 13 14 15 16 17 18 19 20 21 22" ] && [ "$smoke_complete" -eq 0 ]; then
    ok "pwu6-b: the 2026-09-14 16:01 shape (probes 1-8 and 23, no terminator) is INCOMPLETE and names 9-22"
  else no "pwu6-b: the declined-probes transcript" "rc=$? missing=[$smoke_missing] complete=$smoke_complete"; fi
  smoke_fixture "$work/sm-c.log" "$sm_all" PASS 0
  if ! forge_smoke_score "$work/sm-c.log" >/dev/null && [ "$smoke_missing" = "" ] && [ "$smoke_complete" -eq 0 ]; then
    ok "pwu6-c: every probe line but no terminator is INCOMPLETE (the terminator is load-bearing, not decoration)"
  else no "pwu6-c: missing terminator" "missing=[$smoke_missing] complete=$smoke_complete"; fi
  smoke_fixture "$work/sm-d.log" "$sm_all" PASS 1
  sed -i 's/^PROBE 9: some evidence -> PASS  $/PROBE 9: worktree deploy script byte-count=16236 -> FAIL  /' "$work/sm-d.log"
  if forge_smoke_score "$work/sm-d.log" >/dev/null && [ "$smoke_fail" -eq 1 ] && [ "$smoke_pass" -eq 22 ] && [ "$smoke_missing" = "" ]; then
    ok "pwu6-d: a probe reporting FAIL is tabled as FAIL, not missing, and the run is COMPLETE (a FAIL is the instrument working)"
  else no "pwu6-d: FAIL line" "pass=$smoke_pass fail=$smoke_fail missing=[$smoke_missing]"; fi
  smoke_fixture "$work/sm-e.log" "$sm_all" PASS 1
  sed -i 's/^PROBE 9: some evidence -> PASS  $/PROBE 9: -> PASS was expected but the append succeeded -> FAIL/' "$work/sm-e.log"
  if forge_smoke_score "$work/sm-e.log" >/dev/null && [ "$smoke_fail" -eq 1 ]; then
    ok "pwu6-e: the verdict is the word after the LAST arrow; evidence text containing '-> PASS' cannot flip a FAIL"
  else no "pwu6-e: last-arrow verdict" "pass=$smoke_pass fail=$smoke_fail"; fi
  # structural: the gate is consulted in the smoke branch and exits 66 before the ordinary session.end
  # shellcheck disable=SC2016  # grep PATTERNS: literals, not expansions
  sl="$(grep -n 'if ! forge_smoke_score "/tmp/forge-\$suffix.log"; then' "$launcher" | head -1 | cut -d: -f1)"
  # shellcheck disable=SC2016  # grep PATTERN: literal, not an expansion
  el="$(grep -n '^"\$emit" session.end "the Forge.s session on \$bead ended (exit \$rc)"' "$launcher" | head -1 | cut -d: -f1)"
  x66="$(awk -v s="$sl" 'NR>s && /^    exit 66$/ {print NR; exit}' "$launcher")"
  if [ -n "$sl" ] && [ -n "$el" ] && [ -n "$x66" ] && [ "$sl" -lt "$x66" ] && [ "$x66" -lt "$el" ]; then
    ok "pwu6-f: the smoke gate (line $sl) exits 66 (line $x66) before the ordinary session.end (line $el)"
  else no "pwu6-f: gate placement" "score line '${sl:-none}', exit 66 '${x66:-none}', session.end '${el:-none}'"; fi
else
  for c in a b c d e f; do no "pwu6-$c" "this forge.sh has no forge_smoke_score/FORGE_SMOKE_EXPECTED (pre-pwu6 launcher)"; done
fi

# ---- Proofdelve ForgeOs-mdwx.1 + Proofdelve ForgeOs-9x3vj: the seat is told how to SEE its gate ----
# GENERATED-RIGHT, not source-right: the launcher's own handoff_instruction line
# is evaluated with stand-in values and the TEXT THE SEAT RECEIVES is asserted.
# Properties: the gate runs quiet, in the foreground, under a stated timeout;
# backgrounding is forbidden; a missing RESULT line is NO OUTCOME and never a
# pass; and the false "~30 s window" sentence is gone. Against the pre-edict
# launcher (git show 1d2719da:fort/scripts/forge.sh) the first four FAIL: the
# RED arm 9x3vj and mdwx.1 criterion 2 ask for.
hi_line="$(grep -m1 '^  handoff_instruction="Before you finish' "$launcher")"
if [ -n "$hi_line" ]; then
  # shellcheck disable=SC2034,SC2154  # the stand-ins are read by the eval'd line, which assigns handoff_instruction
  hi="$(expected_handoff=/x/h.md root=/x/root wt=/x/wt; eval "${hi_line#  }"; printf '%s' "$handoff_instruction")"
  # Proofdelve ForgeOs-gfuc1 A1/A3 (Regent sitting 2026-11-13): the Forge no longer runs
  # the full gate. These cases replace mdwx.1's "run it quiet and timed" ones,
  # whose subject is retired; the no-background and no-outcome-is-never-a-pass
  # rules carry over to the targeted run. Against the pre-gfuc1 launcher the
  # first, third, fourth and fifth FAIL.
  if grep -qF 'do NOT run fort/scripts/verify.sh in any form' <<<"$hi" && ! grep -qF 'VERIFY_QUIET=1 bash fort/scripts/verify.sh' <<<"$hi"; then ok "gfuc1 A1: the seat is told NOT to run the full gate, and the full-gate command is gone from what it reads"
  else no "gfuc1 A1: the generated instruction still tells the seat to run verify.sh" "$(grep -oF 'VERIFY_QUIET=1 bash fort/scripts/verify.sh' <<<"$hi" | head -1)"; fi
  if grep -qF 'NEVER background it' <<<"$hi"; then ok "9x3vj: the seat is told never to background its targeted run (a detached child is killed when its command returns, measured)"
  else no "9x3vj: backgrounding is not forbidden" "a detach-and-poll seat reads nothing in this sandbox"; fi
  if grep -qF 'npx vitest run <the test files you added or changed' <<<"$hi" && grep -qF 'npm run typecheck' <<<"$hi" && grep -qF 'never the unfiltered suite' <<<"$hi"; then ok "gfuc1 A1: the seat is told to run the TARGETED checks: typecheck, and vitest on the touched test files, never the unfiltered suite"
  else no "gfuc1 A1: no targeted-test instruction" "missing in the generated text"; fi
  if grep -qF 'HOW MUCH TESTING THE BEAD CARRIES FOLLOWS ITS RISK' <<<"$hi"; then ok "gfuc1 A1: the seat is told how much testing the bead carries follows its risk"
  else no "gfuc1 A1: no test-depth rule" "missing in the generated text"; fi
  if grep -qF "'Seat-observed: NONE-SEEN <output of date -Is>'" <<<"$hi" && grep -qF "'Targeted: PASS <commands>" <<<"$hi" && grep -qF 'never the gate' <<<"$hi"; then ok "gfuc1 A1: the header carries Seat-observed: NONE-SEEN (the Verify: reconcile stays truthful) and a separate Targeted: line that is never the gate"
  else no "gfuc1 A1: header lines" "Seat-observed NONE-SEEN / Targeted: not both asked for"; fi
  if grep -qF 'run npm ci FIRST' <<<"$hi" && grep -qF 'Report the FINAL run of each command' <<<"$hi"; then ok "gfuc1 trial fold: a fresh worktree installs dependencies first, and Targeted: reports the final run naming any earlier red"
  else no "gfuc1 trial fold" "the npm ci / final-run instruction is missing"; fi
  if grep -qF 'run that harness too, and shellcheck -x every .sh you changed' <<<"$hi"; then ok "gfuc1 trial fold: a script change runs its harness and shellcheck before the session ends (the cheap host checks a targeted test run cannot see)"
  else no "gfuc1 trial fold: harness" "the script-harness check is not in the targeted set"; fi
  if ! grep -qF '(~30 s)' <<<"$hi"; then ok "9x3vj: the unmeasured '~30 s window' claim is gone from what the seat reads"
  else no "9x3vj: the seat is still told its window is ~30 s" "measured false 2026-10-06 (200 s foreground returned)"; fi
  # The secrets-only posture rewrites one prompt sentence by exact match; if the
  # sentence and its pattern drift apart the rewrite silently does nothing.
  pl="$(grep -m1 '^prompt="You are ' "$launcher")"
  # shellcheck disable=SC2016  # literal launcher text
  pat="$(grep -m1 'prompt="${prompt//"Do not push (mechanically blocked)' "$launcher" | sed 's/^  prompt="\${prompt\/\/"//; s#"/".*##')"
  if [ -n "$pat" ] && grep -qF -- "$pat" <<<"$pl"; then ok "gfuc1 A1: the secrets-only posture's push sentence still matches the prompt it rewrites"
  else no "gfuc1 A1: the posture rewrite no longer matches its sentence" "pattern=${pat:0:80}"; fi
else no "mdwx.1" "no handoff_instruction line in $launcher"; fi

# --------------------------------------------------------------------------
# WIP RESCUE (Proofdelve ForgeOs-gvhhk). The SHIPPED forge_rescue_wip(), extracted, run
# against worktrees in each state its acceptance names. "Handoff-only" is read
# with fleet.sh's own predicate (the ss9d diff, fort/handoffs excluded), so a
# PASS here means the fleet would no longer call the branch "no product change".
# Each RED arm is a generated variant of the function, executed.
# --------------------------------------------------------------------------
awk '/^forge_rescue_wip\(\)[[:space:]]*\{/{f=1} f{print} f && /^\}$/{exit}' "$launcher" > "$work/rescue.sh"
if [ "$(wc -l < "$work/rescue.sh")" -lt 10 ]; then
  for c in "rescues tracked work on a handoff-only branch" "a clean handoff-only worktree stays handoff-only" "an untracked artifact is not work" "a dirty handoff alone is not rescued" "a mid-merge worktree is left alone" "the start-of-session rescue runs before the refresh"; do
    no "gvhhk: $c" "this forge.sh has no forge_rescue_wip(): a session's uncommitted work is left behind"
  done
else
  bash -n "$work/rescue.sh" || { echo "HARNESS REFUSES: forge_rescue_wip() does not parse" >&2; exit 3; }
  mkrescue() { # $1 name -> root; worktree <root>-worktrees/wip on bead/wip carrying ONE handoff-only commit
    local r="$work/$1"
    git init -q "$r"; git -C "$r" config user.email h@x; git -C "$r" config user.name harness
    mkdir -p "$r/fort/handoffs" "$r/src"; echo one > "$r/src/a.cs"; echo two > "$r/src/b.cs"
    echo keep > "$r/fort/handoffs/.keep"   # git tracks no empty directory: without a file the worktree has no fort/handoffs
    git -C "$r" add -A; git -C "$r" commit -qm base; git -C "$r" branch -M main
    git -C "$r" worktree add -q "$r-worktrees/wip" -b bead/wip
    printf '# Handoff: Forge\nModel: x\n' > "$r-worktrees/wip/fort/handoffs/forge-wip.md"
    git -C "$r-worktrees/wip" add -A; git -C "$r-worktrees/wip" commit -qm "E2E-wip: stamp handoff attribution from launcher record"
    printf '%s' "$r"
  }
  product_diff(){ git -C "$1" diff --name-only "main...bead/wip" -- . ':!fort/handoffs'; }
  rescue_run() { # $1 fn file, $2 worktree, $3 when -> prints wip_rescued=<n> files=<n> on the last line
    # shellcheck disable=SC2016  # single quotes are the point: expanded by the inner shell
    bash -c 'set -euo pipefail; source "$1"; forge_rescue_wip "$2" E2E-wip "$3"; echo "wip_rescued=$wip_rescued files=$wip_files"' _ "$1" "$2" "$3" 2>&1
  }
  # RED variants, generated.
  sed 's/^  \[ "\${#paths\[@\]}" -gt 0 \] || return 0$/  return 0/' "$work/rescue.sh" > "$work/rescue-none.sh"
  sed "s#  mapfile -t paths < <(git -C \"\$wt\" diff --name-only HEAD -- . ':(exclude)fort/handoffs' 2>/dev/null)#  mapfile -t paths < <(git -C \"\$wt\" ls-files --modified --others --exclude-standard 2>/dev/null)#; s#  if git -C \"\$wt\" commit -q#  if git -C \"\$wt\" add -- \"\${paths[@]}\" \&\& git -C \"\$wt\" commit -q#" "$work/rescue.sh" > "$work/rescue-all.sh"
  sed "s#  mapfile -t paths < <(git -C \"\$wt\" diff --name-only HEAD -- . ':(exclude)fort/handoffs' 2>/dev/null)#  mapfile -t paths < <(git -C \"\$wt\" diff --name-only HEAD 2>/dev/null)#" "$work/rescue.sh" > "$work/rescue-hoff.sh"
  for v in none all hoff; do cmp -s "$work/rescue.sh" "$work/rescue-$v.sh" && no "gvhhk: RED variant $v could not be generated" "sed matched nothing"; done

  # A. the 2026-09-22 shape: handoff-only branch, tracked work dirty in the worktree.
  r=$(mkrescue g1); wt="$r-worktrees/wip"; echo changed >> "$wt/src/a.cs"; git -C "$wt" rm -q src/b.cs
  out="$(rescue_run "$work/rescue.sh" "$wt" end)"; subj="$(git -C "$wt" log -1 --format=%s)"; body="$(git -C "$wt" log -1 --format=%B)"
  if grep -q 'wip_rescued=1 files=2' <<<"$out" && [ -n "$(product_diff "$r")" ] && clean_tree "$wt" \
     && grep -q '^E2E-wip: WIP RESCUED BY forge.sh, not the Forge' <<<"$subj" && grep -q '^Forge-WIP-Rescue: end$' <<<"$body"; then
    ok "gvhhk: a handoff-only branch with dirty tracked work (an edit and a deletion) is rescued as a labelled WIP commit -- the fleet's ss9d predicate no longer reads it as 'no product change'"
  else no "gvhhk: rescue of tracked work" "out=$out subj=$subj product=$(product_diff "$r" | tr '\n' ' ')"; fi
  r=$(mkrescue g1r); wt="$r-worktrees/wip"; echo changed >> "$wt/src/a.cs"
  rescue_run "$work/rescue-none.sh" "$wt" end >/dev/null
  if [ -z "$(product_diff "$r")" ]; then ok "gvhhk RED: with the rescue removed the same worktree stays handoff-only -- the stranded-work shape"
  else no "gvhhk RED: rescue removed" "product diff appeared anyway"; fi
  # B. criterion 4: a genuinely empty session stays empty.
  r=$(mkrescue g2); wt="$r-worktrees/wip"; before="$(git -C "$wt" rev-parse HEAD)"
  out="$(rescue_run "$work/rescue.sh" "$wt" end)"
  if grep -q 'wip_rescued=0' <<<"$out" && [ "$(git -C "$wt" rev-parse HEAD)" = "$before" ] && [ -z "$(product_diff "$r")" ]; then
    ok "gvhhk: a clean worktree on a handoff-only branch commits nothing -- the ss9d 'no product change' return still fires"
  else no "gvhhk: clean worktree" "out=$out"; fi
  # C. criterion 5: an untracked run artifact is not work.
  r=$(mkrescue g3); wt="$r-worktrees/wip"; echo log > "$wt/verification-1.log"; mkdir -p "$wt/artifacts"; echo x > "$wt/artifacts/out.bin"
  out="$(rescue_run "$work/rescue.sh" "$wt" end)"
  if grep -q 'wip_rescued=0' <<<"$out" && [ -z "$(product_diff "$r")" ]; then ok "gvhhk: untracked run artifacts (verification-*.log, artifacts/**) trigger no rescue and are never committed"
  else no "gvhhk: untracked artifact" "out=$out"; fi
  r=$(mkrescue g3r); wt="$r-worktrees/wip"; echo log > "$wt/verification-1.log"
  rescue_run "$work/rescue-all.sh" "$wt" end >/dev/null
  if [ -n "$(product_diff "$r")" ]; then ok "gvhhk RED: a rescue that takes untracked files commits the verification log as product change"
  else no "gvhhk RED: untracked variant" "nothing was committed; the case cannot see the difference"; fi
  # D. the handoff's own rule (mdwx): a dirty handoff alone is not the work.
  r=$(mkrescue g4); wt="$r-worktrees/wip"; echo "more prose" >> "$wt/fort/handoffs/forge-wip.md"
  out="$(rescue_run "$work/rescue.sh" "$wt" end)"
  if grep -q 'wip_rescued=0' <<<"$out" && ! git -C "$wt" diff --quiet -- fort/handoffs/forge-wip.md; then ok "gvhhk: a dirty handoff alone is not rescued and its edits stay unstaged (the mdwx rule holds)"
  else no "gvhhk: dirty handoff" "out=$out"; fi
  r=$(mkrescue g4r); wt="$r-worktrees/wip"; echo "more prose" >> "$wt/fort/handoffs/forge-wip.md"
  rescue_run "$work/rescue-hoff.sh" "$wt" end >/dev/null
  if git -C "$wt" diff --quiet -- fort/handoffs/forge-wip.md; then ok "gvhhk RED: without the handoff exclusion the handoff's body edits are swept into a commit"
  else no "gvhhk RED: handoff exclusion" "the variant left it unstaged too"; fi
  # E. a mid-merge worktree is not the launcher's to commit.
  r=$(mkrescue g5); wt="$r-worktrees/wip"; echo main-side > "$r/src/a.cs"; git -C "$r" commit -qam "main moves"
  echo branch-side > "$wt/src/a.cs"; git -C "$wt" commit -qam "branch edit"; git -C "$wt" merge main >/dev/null 2>&1 || true
  before="$(git -C "$wt" rev-parse HEAD)"; out="$(rescue_run "$work/rescue.sh" "$wt" end)"
  if git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null && [ "$(git -C "$wt" rev-parse HEAD)" = "$before" ] && grep -q 'mid-merge' <<<"$out"; then
    ok "gvhhk: a worktree mid-merge is left exactly as found and the launcher says why"
  else no "gvhhk: mid-merge" "out=$out"; fi
  # F. criterion 6: the killed-session case is rescued at the NEXT dispatch, BEFORE the refresh.
  if awk '/^forge_rescue_wip "\$wt" "\$bead" start|then forge_rescue_wip "\$wt" "\$bead" start; fi$/{s=NR} /^  refresh_reused_worktree "\$wt"/{r=NR} END{exit !(s && r && s < r)}' "$launcher"; then
    ok "gvhhk: a reused worktree is rescued at session START, above the refresh merge -- a killed session's work is committed before the merge could refuse on it"
  else no "gvhhk: start-of-session rescue" "no forge_rescue_wip ... start call above refresh_reused_worktree in $launcher"; fi
fi

echo "RESULT: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
