#!/bin/bash
# Harness for the writable-skills carve (ForgeOs-yhn44, Regent sitting
# 2026-10-27, docket item D). Builds the REAL masks from the shipped lib, the
# Mayor's build_mask call and the Warden's own build_mask line (read out of
# warden.sh, the probe-boundaries.sh way), against a FIXTURE root, and asks
# `[ -w ]` of each path from inside the mask. It writes nothing: a mask that is
# broken must not be able to turn this probe into a write (the 2026-09-22
# Greenlab lesson). Not wired into verify-impl.sh: it needs bwrap, and seats
# run inside a mask already. Run it by hand on the host after any change to
# seat-sandbox.sh or warden.sh's build_mask line.
#   bash scripts/skills-carve-harness.sh [lib] [warden.sh]
# The fixture lives under /tmp, so the posture is pinned to secrets-only (the
# full posture hides /tmp behind a tmpfs, which would make every answer "ro"
# for the wrong reason). The Mayor's project carve being WRITABLE is the
# vacuity control: a fixture the mask cannot see scores ro there and fails.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
lib="${1:-$here/../fort/scripts/lib/seat-sandbox.sh}"
wl="${2:-$here/../fort/scripts/warden.sh}"
[ -f "$lib" ] && [ -f "$wl" ] || { echo "HARNESS REFUSES: lib or warden.sh missing ($lib, $wl)" >&2; exit 3; }
command -v bwrap >/dev/null || { echo "HARNESS REFUSES: no bwrap on this host" >&2; exit 3; }
[ -z "${FORT_MASKED:-}" ] || { echo "HARNESS REFUSES: run on the host, not inside a seat mask (FORT_MASKED=$FORT_MASKED)" >&2; exit 3; }
work="$(mktemp -d /tmp/skills-carve.XXXXXX)"; trap 'rm -rf "$work" "$work-worktrees"' EXIT
fx="$work"; mkdir -p "$fx/.claude/skills" "$fx/.claude/commands" "$fx/.claude/agents" "$fx/fort/profiles" "$fx-worktrees" "$work/scr"
echo '{}' > "$fx/.claude/settings.json"; git -C "$fx" init -q
# The Warden's real line, joined across continuations, as probe-boundaries.sh does.
wline="$(awk 'f==0 && /^build_mask /{f=1} f{ line=$0; cont=(line ~ /\\$/); sub(/[[:space:]]*\\$/, "", line); printf "%s ", line; if (!cont) { print ""; exit } }' "$wl")"
case "$wline" in "build_mask claude "*) ;; *) echo "HARNESS REFUSES: no column-one 'build_mask claude' line in $wl (got: ${wline:-nothing})" >&2; exit 3 ;; esac
pass=0; fail=0
answers() { # $1 lib, $2 shape -> "path=WRITABLE|ro" lines
  bash -c '
    set -uo pipefail; export FORT_SANDBOX=secrets-only
    source "$1" >/dev/null 2>&1
    fx="$3"
    if [ "$2" = warden ]; then root="$fx"; scratch="$fx/scr"; src="$fx"; keep_token="$fx/no-such-token"; eval "$4" 2>/dev/null
    else build_mask claude "$fx" 2>/dev/null; fi
    mask_env claude >/dev/null 2>&1 || true
    for p in "$fx/.claude/skills" "$fx/.claude/commands" "$fx/.claude/agents" "$fx/.claude/settings.json" "$fx/.claude" \
             "$HOME/.claude/skills" "$HOME/.claude/commands" "$HOME/.claude/plugins" "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md"; do
      r=$(bwrap "${mask[@]}" -- /bin/bash -c "[ -w \"\$1\" ] && echo WRITABLE || echo ro" _ "$p" 2>/dev/null | tail -1)
      printf "%s=%s\n" "${p/#$fx/FX}" "${r:-NO-ANSWER}"
    done' _ "$1" "$2" "$fx" "$wline"
}
check() { # $1 label, $2 answers, $3 expected "path=val" list
  local want bad=""
  for want in $3; do grep -qxF "$want" <<<"$2" || bad="$bad ${want%%=*}(want ${want#*=}, got $(grep -F "${want%%=*}=" <<<"$2" | head -1 | cut -d= -f2))"; done
  if [ -z "$bad" ]; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1 --$bad"; fail=$((fail+1)); fi
}
H="$HOME"
ro_rest="FX/.claude/agents=ro FX/.claude/settings.json=ro FX/.claude=ro $H/.claude/plugins=ro $H/.claude/settings.json=ro $H/.claude/CLAUDE.md=ro"
m="$(answers "$lib" mayor)"; w="$(answers "$lib" warden)"
check "Mayor: project and user-level skills/commands WRITABLE (the vacuity control), the rest of .claude read-only" "$m" \
  "FX/.claude/skills=WRITABLE FX/.claude/commands=WRITABLE $H/.claude/skills=WRITABLE $H/.claude/commands=WRITABLE $ro_rest"
check "Warden: nothing under .claude writable, project or user-level (she stays read-only)" "$w" \
  "FX/.claude/skills=ro FX/.claude/commands=ro $H/.claude/skills=ro $H/.claude/commands=ro $ro_rest"
# RED 1, generated: the carve bound AFTER extra_ro (the drafted patch's order).
red1="$work/lib-carve-after-extra.sh"
awk '/^  for p in "\$\{RW_CARVE\[@\]\}"; do /{carve=$0; next} {print} /^  for p in "\$\{extra_ro\[@\]\}"; do /{ if (carve!="") print carve }' "$lib" > "$red1"
if cmp -s "$red1" "$lib" || ! grep -q 'RW_CARVE\[@\]' "$red1"; then echo "  FAIL  RED 1 -- the carve-after-extra_ro variant could not be generated"; fail=$((fail+1))
else
  w1="$(answers "$red1" warden)"
  if grep -qxF "FX/.claude/skills=WRITABLE" <<<"$w1"; then echo "  PASS  RED 1: with the carve after extra_ro the Warden's project skills are WRITABLE inside her read-only checkout"; pass=$((pass+1))
  else echo "  FAIL  RED 1 -- the variant did not reopen the Warden's checkout; the Warden case cannot discriminate"; fail=$((fail+1)); fi
fi
# RED 2, generated: warden.sh without its user-level pair.
wline2="${wline//\"\$HOME\/.claude\/skills\" \"\$HOME\/.claude\/commands\"/}"
if [ "$wline2" = "$wline" ]; then echo "  FAIL  RED 2 -- warden.sh's line carries no user-level pair to remove"; fail=$((fail+1))
else
  w2="$(wline="$wline2"; bash -c "$(declare -f answers); fx='$fx'; wline=\$1; answers '$lib' warden" _ "$wline2")"
  if grep -qxF "$H/.claude/skills=WRITABLE" <<<"$w2"; then echo "  PASS  RED 2: without the pair in warden.sh the Warden can write ~/.claude/skills"; pass=$((pass+1))
  else echo "  FAIL  RED 2 -- the Warden stayed read-only without the pair; the case cannot discriminate"; fail=$((fail+1)); fi
fi
echo "RESULT $lib : $pass pass / $fail fail"
[ $fail -eq 0 ]
