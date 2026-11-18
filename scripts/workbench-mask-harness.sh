#!/bin/bash
# workbench-mask-harness.sh — the Workbench seat's mask, measured (ForgeOs-9srgz A3).
# Usage: scripts/workbench-mask-harness.sh [workbench.sh]
#
# Sources the SHIPPED workbench.sh (its main() is guarded, so nothing launches),
# builds a fixture fort under ~/dev, calls the launcher's own wb_mask() against
# it, and probes from inside bwrap. HOST ONLY: it refuses inside a seat mask.
#
# WHAT IT ASSERTS, the docket's list: .env* (two spellings, root and session
# worktree), the Keep signing token, ~/.ssh ~/.aws ~/.azure ~/.config/gh
# unreadable; scripts/deploy-azure-staging.sh not writable (root and worktree)
# and refusing to run; fort/scripts read-only in both trees. Plus the seat's
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
# shipped file (deploy-script read-only binds dropped; --rw-tree dropped) must
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
  echo 'echo scan' > "$1/scripts/airlock-feedback-scan.sh"
  echo src > "$1/src/a.txt"
  # The real deploy script's own refusal, truncated after the guard, so a
  # broken mask runs `echo GUARD-PASSED` and nothing that touches Azure.
  # shellcheck disable=SC2016  # the fallback below is a literal guard line, written as text
  awk '{print} /^fi$/ && seen {exit} /FORT_MASKED/ {seen=1}' "$here/deploy-azure-staging.sh" > "$1/scripts/deploy-azure-staging.sh" 2>/dev/null \
    || echo 'if [[ -n "${FORT_MASKED:-}" ]]; then echo REFUSED; exit 64; fi' > "$1/scripts/deploy-azure-staging.sh"
  echo 'echo GUARD-PASSED; exit 0' >> "$1/scripts/deploy-azure-staging.sh"
}
mkfixture "$root"; mkfixture "$wt"; mkfixture "$other"; git -C "$root" init -q
mkdir -p "$fx/cfg/proofdelve"; printf 'FIXTURE-TOKEN\n' > "$fx/cfg/proofdelve/keep-signing-token"
printf 'FIXTURE-FEEDBACK-TOKEN\n' > "$fx/cfg/proofdelve/feedback-read-token"   # ForgeOs-15k.10

# The in-mask probe is a plain file in the fixture (visible inside the mask,
# since $HOME is readable), so no quoting is nested.
cat > "$fx/inmask.sh" <<'INMASK'
r="$1"; w="$2"; o="$3"; t="$4"; ft="$5"
by() { cat "$1" 2>/dev/null | wc -c; }
can() { ( : >> "$1" ) 2>/dev/null && echo yes || echo no; }
echo "env_root=$(by "$r/.env.staging.local")"
echo "env_wt=$(by "$w/.env.staging.local")"
echo "env_spelling=$(cat "$r"/.??v.staging.local 2>/dev/null | wc -c)"
echo "token=$(by "$t")"
echo "fbtoken=$(by "$ft")"
for d in .ssh .aws .azure .config/gh; do
  p="$HOME/$d"; k="dir_${d//[.\/]/_}"
  fs="$(awk -v p="$p" '$5==p {for(i=7;i<=NF;i++) if($i=="-"){print $(i+1); break}}' /proc/self/mountinfo | tail -1)"
  # known_hosts is surfaced back over the ~/.ssh tmpfs on purpose (host-key
  # pinning, 2026-08-13) and carries no credential, so it is not counted.
  echo "$k=${fs:-none}:$(ls -A "$p" 2>/dev/null | grep -cv '^known_hosts$')"
done
echo "deploy_root_w=$(can "$r/scripts/deploy-azure-staging.sh")"
echo "deploy_wt_w=$(can "$w/scripts/deploy-azure-staging.sh")"
out="$(bash "$w/scripts/deploy-azure-staging.sh" 2>&1)"
echo "deploy_run=$([ "${out#*GUARD-PASSED}" = "$out" ] && echo refused || echo ran)"
echo "scripts_root_w=$(can "$r/fort/scripts/x.sh")"
echo "scripts_wt_w=$(can "$w/fort/scripts/x.sh")"
echo "scripts_new=$( ( : > "$w/fort/scripts/new.sh" ) 2>/dev/null && echo yes || echo no)"
echo "profiles_wt_w=$(can "$w/fort/profiles/p.json")"
echo "claude_wt_w=$(can "$w/.claude/settings.json")"
echo "wt_src_w=$(can "$w/src/a.txt")"
echo "other_src_w=$(can "$o/src/a.txt")"
echo "marker=${FORT_MASKED:-}:${BEADS_ACTOR:-}"
INMASK

probe() {  # $1 subject file, $2 posture -> key=value lines from inside the mask
  ( export FORT_SANDBOX="$2" XDG_CONFIG_HOME="$fx/cfg"
    # shellcheck disable=SC1090  # the subject is a parameter by design
    source "$1" 2>/dev/null || { echo "mask=FAILED"; exit 0; }
    wb_mask "$root" "$wt" >/dev/null 2>&1 || { echo "mask=FAILED"; exit 0; }
    # shellcheck disable=SC2154  # wb_mask fills mask[]
    bwrap "${mask[@]}" -- /bin/bash "$fx/inmask.sh" "$root" "$wt" "$other" "$fx/cfg/proofdelve/keep-signing-token" "$fx/cfg/proofdelve/feedback-read-token" 2>/dev/null )
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
  check "[$posture] the feedback-read token reads empty (ForgeOs-15k.10)" "$(val "$out" fbtoken)" 0
  for d in .ssh .aws .azure .config/gh; do
    k="dir_${d//[.\/]/_}"
    if [ ! -d "$HOME/$d" ]; then echo "SKIP  [$posture] ~/$d absent on this host, so no mask can be shown for it"; skip=$((skip+1)); continue; fi
    check "[$posture] ~/$d is an empty tmpfs" "$(val "$out" "$k")" "tmpfs:0"
  done
  check "[$posture] deploy script not writable (root)" "$(val "$out" deploy_root_w)" no
  check "[$posture] deploy script not writable (session worktree)" "$(val "$out" deploy_wt_w)" no
  check "[$posture] deploy script refuses to run" "$(val "$out" deploy_run)" refused
  check "[$posture] fort/scripts read-only (root)" "$(val "$out" scripts_root_w)" no
  check "[$posture] fort/scripts read-only (session worktree)" "$(val "$out" scripts_wt_w)" no
  check "[$posture] no new file in fort/scripts (session worktree)" "$(val "$out" scripts_new)" no
  check "[$posture] fort/profiles read-only (session worktree)" "$(val "$out" profiles_wt_w)" no
  check "[$posture] .claude read-only (session worktree)" "$(val "$out" claude_wt_w)" no
  check "[$posture] VACUITY: the session worktree's own source IS writable" "$(val "$out" wt_src_w)" yes
  check "[$posture] marker and actor" "$(val "$out" marker)" "workbench:hollis"
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

# THE HUP DISPOSITION A CHILD INHERITS (Tova, finding 6 on the docket review).
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
red1="$fx/wb-red-deploy.sh"; red2="$fx/wb-red-rwtree.sh"
# shellcheck disable=SC2016  # sed programs match the launcher's literal $-spellings
sed '/"\$repo\/scripts\/deploy-azure-staging.sh" "\$wt\/scripts\/deploy-azure-staging.sh"/d; s/"\$wt\/scripts\/airlock-feedback-scan.sh" \\$/"$wt\/scripts\/airlock-feedback-scan.sh" || return $?/' "$wb" > "$red1"
# shellcheck disable=SC2016  # as above
sed 's/build_mask claude "\$repo" --rw-tree "\$wt" /build_mask claude "$repo" /' "$wb" > "$red2"
if cmp -s "$red1" "$wb"; then echo "NOT RUN  red arm 1: the generator matched nothing in $wb"; fail=$((fail+1))
else
  out="$(probe "$red1" full)"
  check "RED ARM 1 (deploy-script binds dropped): the deploy script becomes writable" "$(val "$out" deploy_wt_w)" yes
fi
if cmp -s "$red2" "$wb"; then echo "NOT RUN  red arm 2: the generator matched nothing in $wb"; fail=$((fail+1))
else
  out="$(probe "$red2" full)"
  check "RED ARM 2 (--rw-tree dropped): another worktree becomes writable" "$(val "$out" other_src_w)" yes
fi

echo "RESULT pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
