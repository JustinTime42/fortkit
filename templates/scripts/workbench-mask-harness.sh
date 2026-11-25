#!/bin/bash
# workbench-mask-harness.sh — the Workbench seat's mask, measured (Proofdelve ForgeOs-9srgz A3).
# Usage: scripts/workbench-mask-harness.sh [workbench.sh]
#
# Sources the SHIPPED workbench.sh (its main() is guarded, so nothing launches),
# builds a fixture fort under ~/dev, calls the launcher's own wb_mask() against
# it, and probes from inside bwrap. HOST ONLY: it refuses inside a seat mask.
#
# WHAT IT ASSERTS, the docket's list: .env* (two spellings, root and session
# worktree), the Keep signing token, ~/.ssh ~/.aws ~/.azure ~/.config/gh
# unreadable; fort/scripts read-only in both trees. Plus the seat's
# marker and actor, and the narrowing (another worktree is read-only) in the
# `full` posture, where $HOME is read-only; under secrets-only $HOME is writable
# by design and the narrowing does not hold, which is reported as such.
#
# NO REAL SECRET IS READ. The .env and token assertions run on FIXTURE files
# (XDG_CONFIG_HOME points at the fixture). The four credential directories are
# asserted by the mount table alone (a tmpfs at that path, and an empty
# listing); nothing inside them is opened. An absent host directory cannot be
# masked (the lib's binds are existence-guarded) and is reported SKIP, never PASS.
# ~/.ssh may show known_hosts and nothing else (the lib surfaces it on purpose).
#
# CONTROLS. Vacuity: the session worktree's own source IS writable, so a mask
# that refuses everything cannot pass. Red arms: two variants generated from the
# shipped file (the Keep token's mask dropped; --rw-tree dropped) must
# each FAIL the assertion that names them.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
wb="${1:-$here/../fort/scripts/workbench.sh}"
lib="$(dirname "$wb")/lib/seat-sandbox.sh"
[ -f "$wb" ] && [ -f "$lib" ] || { echo "HARNESS REFUSES: workbench.sh or its lib missing ($wb, $lib)" >&2; exit 3; }
command -v bwrap >/dev/null || { echo "HARNESS REFUSES: no bwrap on this host" >&2; exit 3; }
[ -z "${FORT_MASKED:-}" ] || { echo "HARNESS REFUSES: run on the host, not inside a seat mask (FORT_MASKED=$FORT_MASKED)" >&2; exit 3; }
grep -q '^wb_mask()' "$wb" || { echo "HARNESS REFUSES: no wb_mask() in $wb" >&2; exit 3; }

fx="$(mktemp -d "$HOME/dev/.wb-harness.XXXXXX")" || { echo "HARNESS REFUSES: cannot make a fixture under ~/dev" >&2; exit 3; }
trap 'chmod -R u+w "$fx" 2>/dev/null; rm -rf "$fx"' EXIT
root="$fx/repo"; wt="$root-worktrees/wbx"; other="$root-worktrees/other"
mkfixture() {  # $1 tree
  mkdir -p "$1/fort/scripts/lib" "$1/fort/profiles" "$1/.claude" "$1/scripts" "$1/src"
  cp "$lib" "$1/fort/scripts/lib/seat-sandbox.sh"
  echo 'echo x' > "$1/fort/scripts/x.sh"; echo '{}' > "$1/fort/profiles/p.json"; echo '{}' > "$1/.claude/settings.json"
  printf 'FIXTURE-NOT-A-SECRET\n' > "$1/.env.staging.local"
  echo src > "$1/src/a.txt"
  # a host-executed script the lib binds read-only in the ROOT checkout, so
  # scripts/ is a directory with something protected inside it (the rename rows)
  printf '#!/bin/bash\n' > "$1/scripts/digest-hook.sh"
}
mkfixture "$root"; mkfixture "$wt"; mkfixture "$other"; git -C "$root" init -q
mkdir -p "$fx/cfg/civ-keep"; printf 'FIXTURE-TOKEN\n' > "$fx/cfg/civ-keep/signing-token"
# A FOREIGN FORT (Regent sitting 2026-11-18, fortkit-ttpk; the Warden's findings 2 to 4):
# another fort in the registry, with its repo, its worktrees directory and a Keep token of
# its own, none of which this fort's seat may write or read. The registry is a fixture
# (FORT_REGISTRY), so the lib reads this one and not the host's.
foreign="$fx/foreign"; mkdir -p "$foreign/src" "$foreign-worktrees/b1" "$fx/cfg/otherfort"
echo src > "$foreign/src/a.txt"; echo src > "$foreign-worktrees/b1/a.txt"
printf 'FIXTURE-FOREIGN-TOKEN\n' > "$fx/cfg/otherfort/keep-signing-token"
printf 'FIXTURE-FOREIGN-FEEDBACK\n' > "$fx/cfg/otherfort/feedback-read-token"
printf '{"civilization":"fixture","forts":[{"project":"repo","repo":"%s","fort_name":"Fixturefort"},{"project":"foreign","repo":"%s","fort_name":"Otherfort"}]}\n' "$root" "$foreign" > "$fx/registry.json"

# The in-mask probe is a plain file in the fixture (visible inside the mask,
# since $HOME is readable), so no quoting is nested.
cat > "$fx/inmask.sh" <<'INMASK'
r="$1"; w="$2"; o="$3"; t="$4"; f="$5"; ft="$6"
by() { cat "$1" 2>/dev/null | wc -c; }
can() { ( : >> "$1" ) 2>/dev/null && echo yes || echo no; }
echo "env_root=$(by "$r/.env.staging.local")"
echo "env_wt=$(by "$w/.env.staging.local")"
echo "env_spelling=$(cat "$r"/.??v.staging.local 2>/dev/null | wc -c)"
echo "token=$(by "$t")"
for d in .ssh .aws .azure .config/gh; do
  p="$HOME/$d"; k="dir_${d//[.\/]/_}"
  fs="$(awk -v p="$p" '$5==p {for(i=7;i<=NF;i++) if($i=="-"){print $(i+1); break}}' /proc/self/mountinfo | tail -1)"
  # known_hosts is surfaced back over the ~/.ssh tmpfs on purpose (host-key
  # pinning, 2026-08-13) and carries no credential, so it is not counted.
  echo "$k=${fs:-none}:$(ls -A "$p" 2>/dev/null | grep -cv '^known_hosts$')"
done
echo "foreign_repo_w=$(can "$f/src/a.txt")"
echo "foreign_wt_w=$(can "$f-worktrees/b1/a.txt")"
echo "foreign_token=$(by "$ft/keep-signing-token")"
echo "foreign_feedback=$(by "$ft/feedback-read-token")"
echo "scripts_root_w=$(can "$r/fort/scripts/x.sh")"
echo "scripts_wt_w=$(can "$w/fort/scripts/x.sh")"
echo "scripts_new=$( ( : > "$w/fort/scripts/new.sh" ) 2>/dev/null && echo yes || echo no)"
echo "profiles_wt_w=$(can "$w/fort/profiles/p.json")"
echo "claude_wt_w=$(can "$w/.claude/settings.json")"
echo "wt_src_w=$(can "$w/src/a.txt")"
echo "other_src_w=$(can "$o/src/a.txt")"
echo "marker=${FORT_MASKED:-}:${BEADS_ACTOR:-}"
# THE RENAME ROWS (fortkit-awlc, the Warden's finding 1 on dc2b26e). A read-only
# bind protects a path, not the directory holding it: before the lib pinned the
# ancestors, `mv scripts scripts.aside; mkdir scripts` put a seat's own file at
# a path the host runs. Each directory that holds something protected must
# refuse to be renamed. A rename that succeeds is undone at once, here, so the
# fixture is whole for every later row; src/ holds nothing protected and is the
# control: it MUST move, or "refused" would be true of a mask that refuses all.
mvtest() { if mv "$1" "$1.aside" 2>/dev/null; then mv "$1.aside" "$1" 2>/dev/null; echo moved; else echo refused; fi; }
echo "ren_fort=$(mvtest "$r/fort")"
echo "ren_scripts=$(mvtest "$r/scripts")"
echo "ren_git=$(mvtest "$r/.git")"
echo "ren_wt_fort=$(mvtest "$w/fort")"
echo "ren_tokdir=$(mvtest "$(dirname "$t")")"
echo "ren_src=$(mvtest "$r/src")"
echo "scripts_still_w=$( ( : > "$r/scripts/.pin-probe" ) 2>/dev/null && rm -f "$r/scripts/.pin-probe" && echo yes || echo no)"
INMASK

probe() {  # $1 subject file, $2 posture -> key=value lines from inside the mask
  # shellcheck disable=SC2030,SC2031  # each probe sets its own environment in its own subshell, by design
  ( export FORT_SANDBOX="$2" XDG_CONFIG_HOME="$fx/cfg" FORT_REGISTRY="${3-$fx/registry.json}"
    # shellcheck disable=SC1090  # the subject is a parameter by design
    source "$1" 2>/dev/null || { echo "mask=FAILED"; exit 0; }
    wb_mask "$root" "$wt" >/dev/null 2>&1 || { echo "mask=FAILED"; exit 0; }
    # shellcheck disable=SC2154  # wb_mask fills mask[]
    bwrap "${mask[@]}" -- /bin/bash "$fx/inmask.sh" "$root" "$wt" "$other" "$fx/cfg/civ-keep/signing-token" "$foreign" "$fx/cfg/otherfort" 2>/dev/null )
}

pass=0; fail=0; skip=0
check() {  # $1 label, $2 got, $3 want (exact)
  if [ "$2" = "$3" ]; then echo "PASS  $1 ($2)"; pass=$((pass+1)); else echo "FAIL  $1 (got '$2', want '$3')"; fail=$((fail+1)); fi
}
val() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

for posture in full secrets-only; do
  out="$(probe "$wb" "$posture")"
  [ "$(val "$out" mask)" = FAILED ] && { echo "FAIL  [$posture] wb_mask could not build the mask"; fail=$((fail+1)); continue; }
  check "[$posture] .env in the root reads empty" "$(val "$out" env_root)" 0
  check "[$posture] .env in the session worktree reads empty" "$(val "$out" env_wt)" 0
  check "[$posture] .env by another spelling reads empty" "$(val "$out" env_spelling)" 0
  check "[$posture] the Keep signing token reads empty" "$(val "$out" token)" 0
  check "[$posture] fort/ (holding fort/scripts) cannot be renamed aside" "$(val "$out" ren_fort)" refused
  check "[$posture] scripts/ (holding a host-executed script) cannot be renamed aside" "$(val "$out" ren_scripts)" refused
  check "[$posture] .git/ (holding config and hooks) cannot be renamed aside" "$(val "$out" ren_git)" refused
  check "[$posture] the session worktree's fort/ cannot be renamed aside" "$(val "$out" ren_wt_fort)" refused
  check "[$posture] the signing token's directory cannot be renamed aside" "$(val "$out" ren_tokdir)" refused
  check "[$posture] CONTROL: src/, which holds nothing protected, CAN be renamed" "$(val "$out" ren_src)" moved
  check "[$posture] CONTROL: a file can still be created in the pinned scripts/" "$(val "$out" scripts_still_w)" yes
  for d in .ssh .aws .azure .config/gh; do
    k="dir_${d//[.\/]/_}"
    if [ ! -d "$HOME/$d" ]; then echo "SKIP  [$posture] ~/$d absent on this host, so no mask can be shown for it"; skip=$((skip+1)); continue; fi
    check "[$posture] ~/$d is an empty tmpfs" "$(val "$out" "$k")" "tmpfs:0"
  done
  check "[$posture] a FOREIGN fort's repository is read-only" "$(val "$out" foreign_repo_w)" no
  check "[$posture] a FOREIGN fort's worktrees are read-only" "$(val "$out" foreign_wt_w)" no
  check "[$posture] a FOREIGN fort's Keep token reads empty" "$(val "$out" foreign_token)" 0
  check "[$posture] a FOREIGN fort's feedback token reads empty" "$(val "$out" foreign_feedback)" 0
  check "[$posture] fort/scripts read-only (root)" "$(val "$out" scripts_root_w)" no
  check "[$posture] fort/scripts read-only (session worktree)" "$(val "$out" scripts_wt_w)" no
  check "[$posture] no new file in fort/scripts (session worktree)" "$(val "$out" scripts_new)" no
  check "[$posture] fort/profiles read-only (session worktree)" "$(val "$out" profiles_wt_w)" no
  check "[$posture] .claude read-only (session worktree)" "$(val "$out" claude_wt_w)" no
  check "[$posture] VACUITY: the session worktree's own source IS writable" "$(val "$out" wt_src_w)" yes
  check "[$posture] marker and actor" "$(val "$out" marker)" "workbench:{{WORKBENCH_ID}}"
  if [ "$posture" = full ]; then
    check "[full] another worktree is read-only (the --rw-tree narrowing)" "$(val "$out" other_src_w)" no
  else
    echo "INFO  [secrets-only] another worktree writable=$(val "$out" other_src_w): \$HOME is writable in this posture by design, so the narrowing is a full-posture property"
  fi
done

# THE LAUNCHER REFUSES INSIDE ANY SEAT MASK (attended only). Exercised on the
# shipped file with a marker set; the refusal is hoisted above everything, so
# no bead, worktree or event is touched.
rout="$(FORT_MASKED=forge bash "$wb" 2>&1)"; rrc=$?
check "launcher refuses inside a seat mask (exit)" "$rrc" 77
check "launcher names the mask in its refusal" "$(printf '%s' "$rout" | grep -c "inside the 'forge' seat mask")" 1

# THE HUP DISPOSITION A CHILD INHERITS (the Warden, finding 6 on the docket review).
# The launcher must survive a dropped terminal, but the session it runs must
# NOT: an ignored HUP (`trap '' HUP`) is inherited by every child, a caught one
# is reset to the default. Runs the shipped trap line in a shell, starts a
# child, and reads bit 0 (SIGHUP) of the child's SigIgn mask.
hup_child_ignores() {  # $1 file -> "yes" | "no" | "none"
  local line
  line="$(grep -m1 -E "^[[:space:]]*trap [^ ]+ HUP" "$1" | sed 's/#.*//')"
  [ -n "$line" ] || { echo none; return; }
  # shellcheck disable=SC2016  # the $ belong to the inner shell
  bash -c "$line"'
    sleep 30 & p=$!
    m=$(awk "/^SigIgn/{print \$2}" /proc/$p/status); kill $p 2>/dev/null
    [ $(( 0x$m & 1 )) -eq 1 ] && echo yes || echo no'
}
check "the session launched under the HUP trap does NOT inherit an ignored HUP" "$(hup_child_ignores "$wb")" no
hupred="$fx/wb-red-hup.sh"
sed -E "s/^([[:space:]]*)trap [^ ]+ HUP/\1trap '' HUP/" "$wb" > "$hupred"
if cmp -s "$hupred" "$wb"; then echo "NOT RUN  red arm 3: the HUP generator matched nothing"; fail=$((fail+1))
else check "RED ARM 3 (trap '' HUP): the child inherits an ignored HUP" "$(hup_child_ignores "$hupred")" yes; fi

# RED ARMS, generated from the shipped file.
red1="$fx/wb-red-token.sh"; red2="$fx/wb-red-rwtree.sh"
# shellcheck disable=SC2016  # sed programs match the launcher's literal $-spellings
sed 's/ --mask-file "\$keep_token"//' "$wb" > "$red1"
# shellcheck disable=SC2016  # as above
sed 's/build_mask claude "\$repo" --rw-tree "\$wt" /build_mask claude "$repo" /' "$wb" > "$red2"
if cmp -s "$red1" "$wb"; then echo "NOT RUN  red arm 1: the generator matched nothing in $wb"; fail=$((fail+1))
else
  # The token is masked twice: by name in the launcher, and by the lib's glob over every
  # Keep and feedback token. Both are dropped here (the lib's from the fixture's own copy,
  # which is the one wb_mask sources), or the arm could not go red.
  # shellcheck disable=SC2016  # the sed program matches the lib's literal $-spelling
  sed -i 's/if \[ -f "\$tok" \]; then MASK_FILES+=("\$tok"); fi/:/' "$root/fort/scripts/lib/seat-sandbox.sh"
  if cmp -s "$root/fort/scripts/lib/seat-sandbox.sh" "$lib"; then echo "NOT RUN  red arm 1: the lib's token glob was not found to drop"; fail=$((fail+1))
  else
    out="$(probe "$red1" full)"
    check "RED ARM 1 (the launcher's token mask AND the lib's token glob dropped): the token becomes readable" "$([ "$(val "$out" token)" -gt 0 ] 2>/dev/null && echo yes || echo no)" yes
    check "RED ARM 1: and so does a foreign fort's token" "$([ "$(val "$out" foreign_token)" -gt 0 ] 2>/dev/null && echo yes || echo no)" yes
  fi
  cp "$lib" "$root/fort/scripts/lib/seat-sandbox.sh"
fi
if cmp -s "$red2" "$wb"; then echo "NOT RUN  red arm 2: the generator matched nothing in $wb"; fail=$((fail+1))
else
  out="$(probe "$red2" full)"
  check "RED ARM 2 (--rw-tree dropped): another worktree becomes writable" "$(val "$out" other_src_w)" yes
fi

# RED ARM 4: with no registry to read, the foreign fort is not known to be one, and in
# secrets-only (a writable /) its repository is writable. This is what the lib's
# registry read buys, and what the full posture gets from its read-only HOME instead.
out="$(probe "$wb" secrets-only /nonexistent/registry.json)"
check "RED ARM 4 (no registry, secrets-only): the foreign fort's repository becomes writable" "$(val "$out" foreign_repo_w)" yes

# THE OVERSEER'S KEEP STORES (the Warden's blocking finding 1 and finding 4, review 2,
# fortkit-ttpk). fleet.sh and scripts/unattended-fleet read ~/.local/state/{{FORT_SLUG}}-keep
# as his record, and ~/.local/state is writable to every seat, so a store that does not
# exist at launch is one a seat can create and seed. Measured under a FIXTURE HOME, so
# the lib's own mkdir lands in the fixture and the red arm (which leaves the store
# creatable) cannot touch the host's. Nothing is written from inside the mask: the probe
# reads permissions only. otherfort-keep stands for another fort's store, which the
# lib's glob must bind without being told its name.
cat > "$fx/inkeep.sh" <<'INKEEP'
s="$HOME/.local/state"
st() { if [ ! -e "$1" ]; then [ -w "$(dirname "$1")" ] && echo creatable || echo absent; elif [ -w "$1" ]; then echo writable; else echo held; fi; }
echo "keep_own=$(st "$s/{{FORT_SLUG}}-keep")"
echo "keep_civ=$(st "$s/civ-keep")"
echo "keep_other=$(st "$s/otherfort-keep")"
echo "state_w=$( [ -w "$s" ] && echo yes || echo no)"
INKEEP
probe_keep() {  # $1 subject, $2 posture, $3 fixture HOME -> key=value lines
  # shellcheck disable=SC2030,SC2031  # each probe sets its own environment in its own subshell, by design
  ( export HOME="$3" FORT_SANDBOX="$2" XDG_CONFIG_HOME="$fx/cfg" FORT_REGISTRY="$fx/registry.json"
    mkdir -p "$HOME/.local/state/otherfort-keep"
    # shellcheck disable=SC1090  # the subject is a parameter by design
    source "$1" 2>/dev/null || { echo "mask=FAILED"; exit 0; }
    wb_mask "$root" "$wt" >/dev/null 2>&1 || { echo "mask=FAILED"; exit 0; }
    bwrap "${mask[@]}" -- /bin/bash "$fx/inkeep.sh" 2>/dev/null )
}
for posture in full secrets-only; do
  out="$(probe_keep "$wb" "$posture" "$fx/home-$posture")"
  [ "$(val "$out" mask)" = FAILED ] && { echo "FAIL  [$posture] wb_mask could not build the mask under a fixture HOME"; fail=$((fail+1)); continue; }
  check "[$posture] this fort's own Keep store exists and is read-only, though the host never had one" "$(val "$out" keep_own)" held
  check "[$posture] the Civ Keep store is read-only" "$(val "$out" keep_civ)" held
  check "[$posture] another fort's Keep store is read-only, unnamed by the lib" "$(val "$out" keep_other)" held
  check "[$posture] VACUITY: ~/.local/state itself IS writable" "$(val "$out" state_w)" yes
done
# RED ARM 5: the lib without its own-store line. The store is then absent at launch, the
# glob has nothing to bind, and a seat could create it.
# shellcheck disable=SC2016  # the sed program matches the lib's literal $-spelling
sed -i 's| "\$HOME/.local/state/{{FORT_SLUG}}-keep"; do|; do|' "$root/fort/scripts/lib/seat-sandbox.sh"
if cmp -s "$root/fort/scripts/lib/seat-sandbox.sh" "$lib"; then echo "NOT RUN  red arm 5: the lib's own-store line was not found to drop"; fail=$((fail+1))
else
  out="$(probe_keep "$wb" secrets-only "$fx/home-red5")"
  check "RED ARM 5 (the lib's own-store line dropped): a seat could create this fort's Keep store" "$(val "$out" keep_own)" creatable
  check "RED ARM 5: the stores that do exist stay read-only (the glob still binds them)" "$(val "$out" keep_other)" held
fi
cp "$lib" "$root/fort/scripts/lib/seat-sandbox.sh"

echo "RESULT pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
