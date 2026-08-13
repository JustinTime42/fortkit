#!/bin/bash
# E2 mask harness (fortkit-52vf.3). Deterministic, no model involved.
#
# Builds a synthetic fort under $HOME with the real directory layout, sources a
# CANDIDATE seat-sandbox.sh, builds the mask for each caller posture, and asserts
# every intended mount property directly.
#
# BYTE COUNTS, NOT EXIT CODES, on every secret assertion: the lib's own header
# warns a /dev/null bind may yield EACCES rather than empty on SELinux hosts, so
# an exit-status probe passes while the file is readable.
#
# Usage: e2-harness.sh <candidate-lib> [probe-root]
set -uo pipefail

LIB="${1:?usage: e2-harness.sh <candidate-lib> [probe-root]}"
ROOT="${2:-$HOME/dev/e2probe}"
WTS="$ROOT-worktrees"
PASS=0; FAIL=0; declare -a FAILURES=()

ok()   { printf '  PASS  %-58s %s\n' "$1" "${2:-}"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL  %-58s %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); FAILURES+=("$1 :: ${2:-}"); }

# ---------------------------------------------------------------- fixture ----
build_fixture() {
  # Refuse to operate anywhere but the probe path — this function deletes.
  case "$ROOT" in *e2probe) : ;; *) echo "refusing: probe root must end in e2probe (got $ROOT)"; exit 2 ;; esac
  rm -rf "$ROOT" "$WTS" 2>/dev/null
  mkdir -p "$ROOT"/{fort/scripts/lib,fort/profiles,fort/seats,bin,civ/scripts,civ/profiles,.claude,sub,src,scripts,skills/civ}
  for s in verify.sh mayor.sh warden.sh emit.sh; do
    printf '#!/bin/bash\n# probe %s\n' "$s" > "$ROOT/fort/scripts/$s"; chmod +x "$ROOT/fort/scripts/$s"
  done
  # Shape B (fortkit-6ovg / fortkit-x9ou): the verifier's IMPLEMENTATION lives
  # outside the locked directory, and skills/ is the source the installed
  # ~/.claude/skills symlinks point at (fortkit-4n8c). Both are new fixture
  # surfaces because both are new write boundaries.
  printf '#!/bin/bash\n# probe verify-impl\n' > "$ROOT/scripts/verify-impl.sh"; chmod +x "$ROOT/scripts/verify-impl.sh"
  printf '# probe skill\n' > "$ROOT/skills/civ/SKILL.md"
  cp "$LIB" "$ROOT/fort/scripts/lib/seat-sandbox.sh"
  printf '{}\n'            > "$ROOT/fort/profiles/warden-settings.json"
  printf '{}\n'            > "$ROOT/.claude/settings.json"
  printf '# charter\n'     > "$ROOT/fort/charter.md"
  printf '# mayor\n'       > "$ROOT/fort/seats/mayor.md"
  printf '#!/bin/bash\n'   > "$ROOT/bin/regent";            chmod +x "$ROOT/bin/regent"
  printf '#!/bin/bash\n'   > "$ROOT/civ/scripts/emit.sh";   chmod +x "$ROOT/civ/scripts/emit.sh"
  printf '{}\n'            > "$ROOT/civ/profiles/regent.json"
  printf '# covenant\n'    > "$ROOT/civ/covenant.md"
  printf 'work\n'          > "$ROOT/src/app.ts"

  # Secret canaries. Each has a KNOWN nonzero byte count on the host; each must
  # read ZERO bytes inside the mask. The first is the canonical spelling; the
  # rest are the editor residues fortkit-2kub found unmasked.
  printf 'SECRET=canonical-32-bytes-of-junk\n' > "$ROOT/.env.staging.local"
  printf 'SECRET=kate-swap-residue-2kub-obs\n' > "$ROOT/..env.staging.local.kate-swp"
  printf 'SECRET=emacs-lock-file-residue-xx\n' > "$ROOT/.#env.local"
  printf 'SECRET=emacs-autosave-residue-xxx\n' > "$ROOT/#env.local#"
  printf 'SECRET=vim-swap-for-a-dotfile-xxxx\n' > "$ROOT/.envrc.swp"
  printf 'SECRET=vim-swap-two-dot-form-xxxxx\n' > "$ROOT/..env.staging.local.swp"
  printf 'SECRET=editor-backup-tilde-xxxxxxx\n' > "$ROOT/env.local~"
  printf 'SECRET=depth-one-canonical-xxxxxxx\n' > "$ROOT/sub/.env.local"
  printf 'SECRET=depth-one-kate-residue-xxxx\n' > "$ROOT/sub/..env.local.kate-swp"

  git -C "$ROOT" init -q
  git -C "$ROOT" config user.email probe@local; git -C "$ROOT" config user.name probe
  git -C "$ROOT" add -A >/dev/null 2>&1
  git -C "$ROOT" commit -qm probe >/dev/null 2>&1
  mkdir -p "$WTS"
  git -C "$ROOT" worktree add -q "$WTS/wt1" -b wt1 >/dev/null 2>&1
  git -C "$ROOT" worktree add -q "$WTS/wt2" -b wt2 >/dev/null 2>&1
  printf 'SECRET=worktree-secret-canary-xxxx\n' > "$WTS/wt1/.env.local"
  printf 'SECRET=worktree-kate-residue-xxxxx\n' > "$WTS/wt1/..env.local.kate-swp"
}

# --------------------------------------------------------------- helpers -----
# run <mask-array-name> <shell-snippet> -> prints output, returns child status
inmask() { bwrap "${mask[@]}" -- bash -c "$1" 2>&1; }

# Assert a path is NOT writable-through-content (append must fail).
#
# ZERO-BYTE APPEND, NOT `printf x` (fortkit-qbq2, 2026-08-12). Four of this
# function's callers target REAL global files, not fixture copies — A8a-A8d point
# at $HOME/.claude/{civilization.json,skills/civ/SKILL.md,commands/park.md,
# plugins/installed_plugins.json}, because the 5sk carve-outs bind those exact
# paths and a fixture copy would not test them. With `printf x` this function
# APPENDED A BYTE to each one whenever the path was writable — which is precisely
# the positive-control case — so the harness corrupted the real civilization
# registry and the real plugin manifest into invalid JSON, and the Regent could
# not launch at all (exit 5, no output). The harness damaged the system exactly
# when it was proving it discriminates.
#
# `printf '' >>` still fails EROFS on a read-only bind, because open(O_WRONLY|
# O_APPEND) is refused before any write happens, and it writes NOTHING when the
# path is writable. Verified by hand the same day on a kernel-RO path.
assert_ro() {
  local label="$1" path="$2" out
  out="$(inmask "printf '' >> '$path' && echo WROTE || echo BLOCKED:\$?")"
  case "$out" in
    *WROTE*)   bad "$label" "APPEND SUCCEEDED — path is writable" ;;
    *BLOCKED*) ok  "$label" "append blocked" ;;
    *)         bad "$label" "unexpected: $out" ;;
  esac
}
assert_rw() {
  local label="$1" path="$2" out
  out="$(inmask "printf x >> '$path' && echo WROTE || echo BLOCKED:\$?")"
  case "$out" in
    *WROTE*)   ok  "$label" "append succeeded (expected)" ;;
    *)         bad "$label" "APPEND BLOCKED but should be writable: $out" ;;
  esac
}
# Assert a directory does NOT accept a new file.
assert_no_newfile() {
  local label="$1" dir="$2" out
  out="$(inmask "touch '$dir/.e2-newfile' && echo CREATED || echo BLOCKED:\$?")"
  case "$out" in
    *CREATED*) bad "$label" "NEW FILE CREATED in $dir" ;;
    *)         ok  "$label" "new file blocked" ;;
  esac
}
# Assert a DIRECTORY cannot be renamed out from under its own contents.
#
# THIS IS THE ASSERTION THAT POISONED A WHOLE RUN, AND THE REASON IT DID
# (fortkit-x9ou, correction of record 2026-08-12). The first version of it
# called assert_immovable, which does `mv` and never moves the path back —
# correct for a mount point, where the mv always fails and no restore is ever
# needed, and catastrophic for a directory where the mv SUCCEEDS. It left
# fort/scripts renamed for the rest of the run: A5 through A10 then failed
# against a stale mask, and worse, several later assertions PASSED VACUOUSLY,
# because "append blocked" and "new file blocked" are trivially true of a path
# that is gone. Only A1-A4 and the assertion itself were trustworthy.
#
# So this version restores the fixture, VERIFIES the restore, and if the restore
# fails it aborts the entire run rather than printing numbers nobody can trust.
# A harness that cannot restore what it moved has no business continuing.
assert_dir_immovable() {
  local label="$1" dir="$2"
  inmask "mv '$dir' '$dir.moved' >/dev/null 2>&1" >/dev/null
  if [ -e "$dir.moved" ] || [ ! -d "$dir" ]; then
    mv "$dir.moved" "$dir" 2>/dev/null
    if [ -d "$dir" ] && [ ! -e "$dir.moved" ]; then
      bad "$label" "RENAME SUCCEEDED — the directory is not a mount point (fixture restored)"
    else
      printf '\n  ****  FIXTURE RESTORE FAILED: %s is not back in place.\n' "$dir" >&2
      printf '  ****  Every assertion after this point would be VACUOUS. ABORTING (fortkit-x9ou).\n\n' >&2
      exit 3
    fi
  else
    ok "$label" "rename refused — the directory is itself a mount point"
  fi
}
# Assert a path cannot be unlinked or renamed over (mount-point property).
assert_immovable() {
  local label="$1" path="$2" u m
  u="$(inmask "rm -f '$path' >/dev/null 2>&1 && echo YES || echo NO")"
  m="$(inmask "mv '$path' '$path.moved' >/dev/null 2>&1 && echo YES || echo NO")"
  if [ "$u" = NO ] && [ "$m" = NO ]; then ok "$label" "unlink refused, rename refused"
  else bad "$label" "unlink=$u rename=$m — a mount point should refuse both"; fi
}
# THE SECRET ASSERTION: byte count, never exit code.
assert_zero_bytes() {
  # `cat 2>/dev/null | wc -c` is ALWAYS numeric: 0 for a /dev/null bind, 0 for
  # EACCES, N for a readable file. Never scored on exit status — the lib's
  # header warns a masked file yields EACCES on SELinux hosts rather than empty,
  # so an exit-status probe passes while the file is readable.
  local label="$1" path="$2" n host
  n="$(inmask "cat '$path' 2>/dev/null | wc -c" | tr -d ' \n')"
  host="$(wc -c < "$path" 2>/dev/null || echo 0)"
  if [ "$host" -le 0 ] 2>/dev/null; then bad "$label" "FIXTURE BROKEN: host file is $host bytes"; return; fi
  if [ "$n" = "0" ]; then ok  "$label" "0 bytes in mask / $host on host"
  else                    bad "$label" "READ $n BYTES (host $host) — NOT MASKED"
  fi
}

# ============================================================== postures =====
echo "=== E2 mask harness — candidate: $LIB"
build_fixture
# shellcheck disable=SC1090
source "$LIB"

echo
echo "--- A. MAYOR posture:  build_mask claude \$root"
mask=(); build_mask claude "$ROOT" || { echo "build_mask FAILED"; exit 1; }
# SHAPE B: the Mayor's editable verifier is scripts/verify-impl.sh, OUTSIDE the
# locked directory. These two assertions are the whole point of the reshape —
# `sed -i` and `git checkout` are the two operations that failed for a cycle
# under the cycle-7 arrangement while `test -w` reported TRUE.
impl="$ROOT/scripts/verify-impl.sh"
sha_before="$(sha256sum "$impl" | cut -d' ' -f1)"
out="$(inmask "sed -i 's/\r\$//' '$impl' && echo SEDOK || echo SEDFAIL:\$?")"
sha_after="$(sha256sum "$impl" | cut -d' ' -f1)"
if [ "$out" = "SEDOK" ] && [ "$sha_before" = "$sha_after" ]; then
  ok "A1 6ovg verify-impl.sh: sed -i (sibling + rename) works" "content identical after"
else bad "A1 6ovg verify-impl.sh: sed -i works" "$out (sha $sha_before -> $sha_after)"; fi
out="$(inmask "cd '$ROOT' && printf '\n' >> scripts/verify-impl.sh && git checkout -- scripts/verify-impl.sh && echo CHECKOUTOK || echo CHECKOUTFAIL:\$?")"
sha_after="$(sha256sum "$impl" | cut -d' ' -f1)"
if [[ "$out" == *CHECKOUTOK* ]] && [ "$sha_before" = "$sha_after" ]; then
  ok "A2 6ovg verify-impl.sh: git checkout replaces it" "restored, sha matches"
else bad "A2 6ovg verify-impl.sh: git checkout replaces it" "$out (sha $sha_after)"; fi
assert_ro "A2b SHAPE B: the verify.sh SHIM is read-only"  "$ROOT/fort/scripts/verify.sh"
assert_rw "A2c skills/ writable for an attended seat (prose gate, 4n8c)" "$ROOT/skills/civ/SKILL.md"
assert_ro        "A3 mayor.sh not writable"            "$ROOT/fort/scripts/mayor.sh"
assert_immovable "A4 mayor.sh not unlinkable/renamable" "$ROOT/fort/scripts/mayor.sh"
assert_ro        "A5 lib/seat-sandbox.sh not writable"  "$ROOT/fort/scripts/lib/seat-sandbox.sh"
# A4b — THE MEASUREMENT SHAPE A FAILED AND SHAPE B EXISTS FOR. Under Shape A
# this printed `unlink=NO rename=YES`: the FILES were mount points and the
# DIRECTORY was not, so a seat could rename fort/scripts aside and have
# ~/.local/bin/mayor exec its replacement on the host, unmasked (fortkit-x9ou).
assert_dir_immovable "A4b fort/scripts DIRECTORY not renamable" "$ROOT/fort/scripts"
# A6 — INVERTED BY SHAPE B. This asserted the disclosed new-file hole was OPEN.
# There is no hole now: the directory is a single read-only bind again.
assert_no_newfile "A6 SHAPE B: no new file in fort/scripts"    "$ROOT/fort/scripts"
assert_ro "A7a fort/profiles not writable"  "$ROOT/fort/profiles/warden-settings.json"
assert_ro "A7b .claude not writable"        "$ROOT/.claude/settings.json"
assert_ro "A7c bin/ not writable"           "$ROOT/bin/regent"
assert_ro "A7d civ/scripts not writable"    "$ROOT/civ/scripts/emit.sh"
assert_ro "A7e civ/profiles not writable"   "$ROOT/civ/profiles/regent.json"
assert_ro "A7f .git/config not writable"    "$ROOT/.git/config"
assert_rw "A7g src/ IS writable (real work)" "$ROOT/src/app.ts"
assert_ro "A8a 5sk ~/.claude/civilization.json RO" "$HOME/.claude/civilization.json"
assert_ro "A8b 5sk ~/.claude/skills RO"            "$HOME/.claude/skills/civ/SKILL.md"
assert_ro "A8c 5sk ~/.claude/commands RO"          "$HOME/.claude/commands/park.md"
assert_ro "A8d 5sk ~/.claude/plugins RO"           "$HOME/.claude/plugins/installed_plugins.json"
out="$(inmask "touch '$HOME/.claude/teams/.e2-probe' && echo CREATED || echo BLOCKED")"
if [ "$out" = "CREATED" ]; then
  ok "A8e ~/.claude/teams STILL WRITABLE (harness state)" "deliberate"
  rm -f "$HOME/.claude/teams/.e2-probe"
else
  bad "A8e ~/.claude/teams still writable" "$out — masked launches will break"
fi
assert_zero_bytes "A9a 2kub .env.staging.local"             "$ROOT/.env.staging.local"
assert_zero_bytes "A9b 2kub ..env.staging.local.kate-swp"   "$ROOT/..env.staging.local.kate-swp"
assert_zero_bytes "A9c 2kub .#env.local (emacs lock)"       "$ROOT/.#env.local"
assert_zero_bytes "A9d 2kub #env.local# (emacs autosave)"   "$ROOT/#env.local#"
assert_zero_bytes "A9e 2kub .envrc.swp (vim)"               "$ROOT/.envrc.swp"
assert_zero_bytes "A9f 2kub ..env.staging.local.swp (vim)"  "$ROOT/..env.staging.local.swp"
assert_zero_bytes "A9g 2kub env.local~ (backup)"            "$ROOT/env.local~"
assert_zero_bytes "A9h 2kub sub/.env.local (depth 1)"       "$ROOT/sub/.env.local"
assert_zero_bytes "A9i 2kub sub/..env.local.kate-swp"       "$ROOT/sub/..env.local.kate-swp"
assert_rw "A10 1q9 Mayor keeps \$root-worktrees writable"   "$WTS/wt1/src/app.ts"

echo
echo "--- B0. MEASUREMENT, not an assertion: the Warden call AS IT SHIPS TODAY"
echo "        (build_mask claude \$root \$root \$src — no \$root-worktrees argument)."
echo "        NO LIB CHANGE CAN CLOSE THIS; only warden.sh passing the tree can."
mask=(); build_mask claude "$ROOT" "$ROOT" "$ROOT"
out="$(inmask "printf x >> '$WTS/wt1/fort/scripts/mayor.sh' && echo WRITABLE || echo blocked")"
echo "        worktree fort/scripts/mayor.sh under today's Warden call: $out"
out="$(inmask "touch '$WTS/wt1/bin/e2-newfile' && echo WRITABLE || echo blocked")"
echo "        worktree bin/ under today's Warden call:                  $out"

echo
echo "--- B. WARDEN posture: build_mask claude \$root \$root \$src \$root-worktrees"
mask=(); build_mask claude "$ROOT" "$ROOT" "$ROOT" "$WTS" || { echo "build_mask FAILED"; exit 1; }
assert_ro "B1a 6ovg verify.sh shim RO for the Warden"       "$ROOT/fort/scripts/verify.sh"
assert_ro "B1b 6ovg verify-impl.sh RO for the Warden"       "$ROOT/scripts/verify-impl.sh"
assert_ro "B1c skills/ RO for the Warden (whole checkout)"  "$ROOT/skills/civ/SKILL.md"
assert_no_newfile "B2 6ovg hole ABSENT for the Warden"      "$ROOT/fort/scripts"
assert_ro "B3a 1q9 worktree fort/scripts not writable"      "$WTS/wt1/fort/scripts/mayor.sh"
assert_no_newfile "B3b 1q9 worktree fort/scripts no newfile" "$WTS/wt1/fort/scripts"
assert_ro "B3c 1q9 worktree bin/ not writable"              "$WTS/wt1/bin/regent"
assert_ro "B3d 1q9 worktree civ/scripts not writable"       "$WTS/wt1/civ/scripts/emit.sh"
assert_ro "B3e 1q9 whole worktree tree RO for the Warden"   "$WTS/wt1/src/app.ts"
assert_zero_bytes "B4a worktree secret masked"              "$WTS/wt1/.env.local"
assert_zero_bytes "B4b worktree kate residue masked"        "$WTS/wt1/..env.local.kate-swp"

echo
echo "--- C. FORGE posture:  build_mask codex \$root --rw-tree \$wt"
mask=(); build_mask codex "$ROOT" --rw-tree "$WTS/wt1" || { echo "build_mask FAILED"; exit 1; }
assert_rw "C1 1q9 declared worktree src IS writable"        "$WTS/wt1/src/app.ts"
assert_ro "C2a 1q9 declared worktree fort/scripts RO"       "$WTS/wt1/fort/scripts/mayor.sh"
assert_no_newfile "C2b 1q9 declared worktree scripts dir RO" "$WTS/wt1/fort/scripts"
assert_ro "C2c 1q9 NEW: worktree bin/ RO (was writable)"    "$WTS/wt1/bin/regent"
assert_ro "C2d 1q9 NEW: worktree civ/scripts RO"            "$WTS/wt1/civ/scripts/emit.sh"
assert_ro "C2e 1q9 worktree charter RO (codex keeps lock)"  "$WTS/wt1/fort/charter.md"
assert_ro "C3 1q9 OTHER worktree not writable at all"       "$WTS/wt2/src/app.ts"
assert_ro "C4a codex: \$root verify.sh RO (whole-dir lock)" "$ROOT/fort/scripts/verify.sh"
assert_no_newfile "C4b codex: no new-file hole at \$root"   "$ROOT/fort/scripts"
# THE WRINKLE SHAPE B WOULD HAVE OPENED. repo scripts/ rides the $root grant,
# so without an explicit carve-out the unattended seat could edit the verifier
# that judges its own work. Same for skills/, which is session-executed
# instruction the Forge cannot ask permission to change.
assert_ro "C4c codex: verify-impl.sh RO (the Shape B wrinkle)" "$ROOT/scripts/verify-impl.sh"
assert_ro "C4d codex: \$root skills/ RO (unattended lock)"    "$ROOT/skills/civ/SKILL.md"
assert_ro "C4e codex: declared worktree verify-impl.sh RO"     "$WTS/wt1/scripts/verify-impl.sh"
assert_zero_bytes "C5a --rw-tree sweeps worktree secrets"   "$WTS/wt1/.env.local"
assert_zero_bytes "C5b --rw-tree sweeps worktree residue"   "$WTS/wt1/..env.local.kate-swp"
n="$(inmask "cat '$HOME/.claude/settings.json' 2>/dev/null | wc -c" | tr -d ' \n')"
if [ "$n" = "0" ]; then ok "C6 codex: ~/.claude masked entirely" "0 bytes in mask"
else bad "C6 codex: ~/.claude masked entirely" "read $n bytes"; fi

echo
echo "--- D. RESEARCHER posture: build_mask claude \$root --env-root \$wts \$root \$wts"
mask=(); build_mask claude "$ROOT" --env-root "$WTS" "$ROOT" "$WTS" || { echo "build_mask FAILED"; exit 1; }
assert_ro "D1 whole \$root RO"                              "$ROOT/src/app.ts"
assert_ro "D2 whole \$root-worktrees RO"                    "$WTS/wt1/src/app.ts"
assert_ro "D3 verify.sh shim RO"                            "$ROOT/fort/scripts/verify.sh"
assert_ro "D4 verify-impl.sh RO"                            "$ROOT/scripts/verify-impl.sh"

echo
echo "=============================================================="
printf 'E2 HARNESS: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then printf '  %s\n' "${FAILURES[@]}"; fi
exit $(( FAIL > 0 ? 1 : 0 ))
