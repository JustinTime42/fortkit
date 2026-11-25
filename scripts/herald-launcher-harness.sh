#!/bin/bash
# herald-launcher-harness.sh: the Herald launcher's report gate and smoke gate
# (fortkit-awlc, the audit of 2026-11-24, items 5.1 and 5.2).
# Usage: scripts/herald-launcher-harness.sh [herald.sh]
#
# WHAT IT MEASURES. civ/scripts/herald.sh decides after a session whether a
# report was filed, and on a smoke whether the probes passed. Both gates used
# to be weaker than they read:
#   - the report gate asked only "is the report file non-empty", so a session
#     that died was recorded as "report filed" whenever a file was already on
#     disk (the crash stub of an earlier rung, or an earlier run's report);
#   - the smoke gate asked only for the SMOKE-COMPLETE marker, so a probe that
#     printed FAIL, or never printed, still exited 0.
#
# HOW. The SHIPPED launcher is copied into a fixture civilization under ~/.cache
# with its lock and log paths repointed there (exactly one line each, asserted),
# the real mask library beside it, a stub emitter that logs, and a stub `claude`
# first on PATH whose behaviour a mode file selects. The real bwrap and the real
# mask run. HOME is the fixture's, so nothing is written to the real one, and
# the vault is a fixture, never the Overseer's. No model runs and nothing is
# emitted to a real stream.
#
# RED AND GREEN. Run against the launcher as it was before the repair
# (git show 6ecb78f:civ/scripts/herald.sh) this scores 4 pass / 3 fail: the
# three cases named (repair) below fail. Against the repaired launcher, 7 / 0.
#
# HOST ONLY: a mask cannot build a mask. scripts/verify-impl.sh runs it through
# mask_harness_step, which records NOT CHECKED inside a seat mask.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
subject="${1:-$here/../civ/scripts/herald.sh}"
[ -f "$subject" ] || { echo "HARNESS REFUSES: no launcher at $subject" >&2; exit 3; }
repo="$(cd "$(dirname "$subject")/../.." && pwd)"
lib="$repo/fort/scripts/lib/seat-sandbox.sh"
[ -f "$lib" ] || { echo "HARNESS REFUSES: no mask library at $lib" >&2; exit 3; }
command -v bwrap >/dev/null || { echo "HARNESS REFUSES: no bwrap on this host" >&2; exit 3; }
[ -z "${FORT_MASKED:-}" ] || { echo "HARNESS REFUSES: run on the host, not inside a seat mask (FORT_MASKED=$FORT_MASKED)" >&2; exit 3; }

fx="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/herald-harness.XXXXXX")" || { echo "HARNESS REFUSES: cannot make a fixture directory" >&2; exit 3; }
trap 'rm -rf "$fx"' EXIT
mkdir -p "$fx/root/civ/scripts" "$fx/root/civ/profiles" "$fx/root/fort/scripts/lib" "$fx/bin" "$fx/home" "$fx/cfg" "$fx/run" "$fx/vault/reports"
cp "$lib" "$fx/root/fort/scripts/lib/seat-sandbox.sh"
[ -f "$repo/fort/scripts/sandbox-posture" ] && cp "$repo/fort/scripts/sandbox-posture" "$fx/root/fort/scripts/sandbox-posture"
[ -f "$repo/civ/profiles/herald-settings.json" ] && cp "$repo/civ/profiles/herald-settings.json" "$fx/root/civ/profiles/herald-settings.json"
printf '{"forts":[]}\n' > "$fx/registry.json"

# The launcher, with its lock and its log inside the fixture: the real lock is
# the one a real Herald run holds, and a harness must never wait on it.
launcher="$fx/root/civ/scripts/herald.sh"
sed -e "s|^lockfile=\"/tmp/herald-|lockfile=\"$fx/lock-|" -e "s|^log=\"/tmp/herald-|log=\"$fx/log-|" "$subject" > "$launcher"
chmod +x "$launcher"
[ "$(grep -c "^lockfile=\"$fx/lock-" "$launcher")" = 1 ] || { echo "HARNESS REFUSES: expected one lockfile= line to repoint in $subject" >&2; exit 3; }
[ "$(grep -c "^log=\"$fx/log-" "$launcher")" = 1 ] || { echo "HARNESS REFUSES: expected one log= line to repoint in $subject" >&2; exit 3; }
if grep -n '/tmp/herald-' "$launcher" | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then
  echo "HARNESS REFUSES: the launcher still names /tmp/herald- outside a comment; the fixture would touch the real lock or log" >&2; exit 3
fi

# The emitter: one line per call, category first.
cat > "$fx/root/civ/scripts/emit.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$fx/emit.log"
EOF
chmod +x "$fx/root/civ/scripts/emit.sh"

# The session: a mode file says what it does. The environment is cleared by the
# mask, so the mode cannot travel in a variable.
today="$(date +%F)"
report="$fx/vault/reports/$today.md"
cat > "$fx/bin/claude" <<EOF
#!/bin/bash
cat >/dev/null
case "\$(cat "$fx/mode")" in
  die)   echo "session died before writing anything"; exit 1 ;;
  write) printf '# Herald report: fixture\n\nwritten by the session\n' > "$report"; echo "report written"; exit 0 ;;
  smoke-ok)      for n in 1 2 3 4 5 6 7 8 9 10; do echo "PROBE \$n: PASS (fixture)"; done; echo; echo SMOKE-COMPLETE ;;
  smoke-fail)    for n in 1 2 3 5 6 7 8 9 10; do echo "PROBE \$n: PASS (fixture)"; done; echo "PROBE 4: FAIL (fixture: the read succeeded)"; echo; echo SMOKE-COMPLETE ;;
  smoke-missing) for n in 1 2 3 4 5 6 8 9 10; do echo "PROBE \$n: PASS (fixture)"; done; echo; echo SMOKE-COMPLETE ;;
esac
EOF
chmod +x "$fx/bin/claude"

run() { # <mode> [smoke] -> sets rc; output in $fx/out
  printf '%s\n' "$1" > "$fx/mode"
  : > "$fx/emit.log"
  ( cd "$fx/root" && env -u FORT_MASKED HOME="$fx/home" XDG_CONFIG_HOME="$fx/cfg" XDG_RUNTIME_DIR="$fx/run" XDG_CACHE_HOME="$fx/home/.cache" \
      FORT_REGISTRY="$fx/registry.json" HERALD_VAULT="$fx/vault" HERALD_SMOKE="${2:+1}" PATH="$fx/bin:$PATH" \
      "$launcher" > "$fx/out" 2>&1 )
  rc=$?
}
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1 -- $2"; }
emitted() { grep -c "$1" "$fx/emit.log" 2>/dev/null || true; }

echo "=== herald-launcher-harness: $subject ==="

# VACUITY CONTROL: the fixture can register a filed report at all. Without it
# every "exit 65" below would be satisfied by a launcher that always says 65.
rm -f "$report"; run write
if [ "$rc" = 0 ] && grep -q 'written by the session' "$report" 2>/dev/null && [ "$(emitted '"report_filed":true')" = 1 ]; then
  ok "control: a session that writes its report is recorded as filed (exit 0)"
else bad "control: a session that writes its report is recorded as filed" "exit $rc; $(tail -2 "$fx/out" | tr '\n' ' ')"; fi

rm -f "$report"; run die
if [ "$rc" = 65 ] && [ -s "$report" ] && [ "$(emitted '^incident ')" = 1 ]; then
  ok "no report on disk and a dead session: crash stub written, incident, exit 65"
else bad "no report on disk and a dead session: crash stub, incident, exit 65" "exit $rc; incidents $(emitted '^incident ')"; fi

# The stub the last case wrote is still on disk: this is the second rung dying.
stub_sha="$(sha256sum "$report" | cut -d' ' -f1)"; run die
if [ "$rc" = 65 ] && [ "$(sha256sum "$report" | cut -d' ' -f1)" = "$stub_sha" ] && [ "$(emitted '^incident ')" = 1 ] && [ "$(emitted '"report_filed":true')" = 0 ]; then
  ok "(repair) an earlier rung's stub on disk and a dead session: NOT recorded as filed; incident, exit 65, the file untouched"
else bad "(repair) an earlier rung's stub on disk and a dead session is not recorded as filed" "exit $rc; incidents $(emitted '^incident '); report_filed:true lines $(emitted '"report_filed":true')"; fi

run write
if [ "$rc" = 0 ] && grep -q 'written by the session' "$report" && [ "$(emitted '"report_filed":true')" = 1 ]; then
  ok "an earlier rung's stub on disk and a session that writes: recorded as filed (exit 0)"
else bad "an earlier rung's stub on disk and a session that writes is recorded as filed" "exit $rc"; fi

run smoke-ok smoke
if [ "$rc" = 0 ]; then ok "smoke: ten PASS lines and the marker exit 0"
else bad "smoke: ten PASS lines and the marker exit 0" "exit $rc; $(tail -2 "$fx/out" | tr '\n' ' ')"; fi

run smoke-fail smoke
if [ "$rc" = 1 ] && grep -q 'PROBE 4: FAIL' "$fx/out"; then ok "(repair) smoke: a probe that prints FAIL fails the smoke (exit 1) and the line is named"
else bad "(repair) smoke: a probe that prints FAIL fails the smoke" "exit $rc"; fi

run smoke-missing smoke
if [ "$rc" = 65 ] && grep -q 'INCOMPLETE' "$fx/out"; then ok "(repair) smoke: a probe with no line makes the smoke INCOMPLETE (exit 65)"
else bad "(repair) smoke: a probe with no line makes the smoke INCOMPLETE" "exit $rc"; fi

echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
