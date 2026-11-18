#!/bin/bash
# node-cache-harness.sh -- ForgeOs-jfqu4.8 / ForgeOs-x1n09 (Regent docket
# 2026-10-22 item B): Node's on-disk compile cache is OFF in every fleet, Forge,
# nightly and verifier run.
#
# Asserts, against the SHIPPED files (NODE_CACHE_ROOT overrides the repo root):
#   1. each of the four launchers carries exactly one node_compile_cache block,
#      and the four blocks are byte-identical;
#   2. the block, sourced into a shell whose environment ALREADY names a cache
#      directory, makes a child node's module.enableCompileCache() report
#      DISABLED and write nothing: not under TMPDIR, not in the named directory
#      (x1n09 criterion 3: the env reaches a child node process; the disable
#      switch wins over the named directory, which is why the block does not
#      also unset it);
#   3. CONTROL: the same child with the block left out reports a cache and
#      writes TMPDIR/node-compile-cache, so case 2 is not passing because this
#      host's node never caches at all.
# Writes only under its own mktemp directory.
set -uo pipefail
# The verifier that runs this harness has the block applied to ITSELF, so the
# variables are in this process's environment; every case sets its own.
unset NODE_DISABLE_COMPILE_CACHE NODE_COMPILE_CACHE
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${NODE_CACHE_ROOT:-$here/..}"
files=(fort/scripts/fleet.sh fort/scripts/forge.sh fort/scripts/nightly-verify.sh scripts/verify-impl.sh)
command -v node >/dev/null 2>&1 || { echo "HARNESS REFUSES: no node on PATH" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1 -- $2"; fail=$((fail + 1)); }

block_of() {  # $1 file -> the block between the markers, inclusive
  sed -n '/^# >>> node_compile_cache:/,/^# <<< node_compile_cache$/p' "$1"
}

# 1. one block per file, all byte-identical
first=""; bad=""
for f in "${files[@]}"; do
  [ -f "$root/$f" ] || { bad="$bad $f:missing"; continue; }
  n="$(grep -c '^# >>> node_compile_cache:' "$root/$f")"
  [ "$n" = 1 ] || { bad="$bad $f:$n-blocks"; continue; }
  block_of "$root/$f" > "$work/$(basename "$f").block"
  if [ -z "$first" ]; then first="$work/$(basename "$f").block"
  elif ! cmp -s "$first" "$work/$(basename "$f").block"; then bad="$bad $f:differs"; fi
done
if [ -z "$bad" ] && [ -s "$first" ]; then
  ok "fleet.sh, forge.sh, nightly-verify.sh and verify-impl.sh each carry exactly one node_compile_cache block, byte-identical"
else
  no "the node_compile_cache blocks are missing or diverged" "${bad:-empty block}"
  echo; echo "RESULT $pass pass / $fail fail (cases 2-3 need a block to source; not run)"; exit 1
fi

# A probe a child node runs: enable the cache, compile one module, report.
mkdir -p "$work/app"
echo 'module.exports = 1;' > "$work/app/m.js"
cat > "$work/app/probe.js" <<'JS'
const m = require("node:module");
const r = m.enableCompileCache();
const s = m.constants.compileCacheStatus;
require("./m.js");
if (m.flushCompileCache) m.flushCompileCache();
console.log(`status=${Object.keys(s).find((k) => s[k] === r.status)}`);
JS
# t and named are set by the CALLER: probe runs inside $( ), so anything it
# assigned would die with that subshell.
probe() {  # $1 1 to source the block first -> prints status=...; reads t (TMPDIR) and named
  mkdir -p "$t"
  # The parent environment already names a cache directory, and the block's
  # switch must still win.
  if [ "$1" = 1 ]; then
    # A real newline after the block: $( ) strips the trailing one, and the
    # block ends on a comment line that would swallow anything after a `;`.
    env TMPDIR="$t" NODE_COMPILE_CACHE="$named" bash -c "$(cat "$first")"$'\n'"cd '$work/app' && node probe.js" 2>/dev/null
  else
    env TMPDIR="$t" bash -c "cd '$work/app' && node probe.js" 2>/dev/null
  fi
}

# 2. the block disables the cache in a child node and nothing is written
t="$work/on-tmp"; named="$work/on-named"; out="$(probe 1)"
left="$(find "$t" "$named" -mindepth 1 2>/dev/null | wc -l)"
if [ "$out" = "status=DISABLED" ] && [ "$left" -eq 0 ]; then
  ok "with the block sourced (and NODE_COMPILE_CACHE already set by the parent), a child node's enableCompileCache() reports DISABLED and writes nothing under TMPDIR or the named directory"
else no "the block did not disable the cache in a child node" "out=$out entries written=$left"; fi

# 3. CONTROL: without the block, the same child caches into TMPDIR
t="$work/off-tmp"; named="$work/off-named"; out="$(probe 0)"
if [ "$out" = "status=ENABLED" ] && [ -d "$t/node-compile-cache" ]; then
  ok "control: without the block the same child reports ENABLED and writes \$TMPDIR/node-compile-cache (so case 2 measures the block, not a node that never caches)"
else no "control: this node does not cache by default, so case 2 measured nothing" "out=$out dir=$([ -d "$t/node-compile-cache" ] && echo present || echo absent)"; fi

echo; echo "RESULT $pass pass / $fail fail"
[ "$fail" -eq 0 ]
