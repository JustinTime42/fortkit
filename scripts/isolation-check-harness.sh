#!/usr/bin/env bash
# isolation-check-harness.sh: scripts/isolation-check.sh, measured on fixtures.
#
# The gate exists because Manyhalls's machinery was copied from another fort
# (Regent sitting 2026-11-18, fortkit-ttpk). A gate that passes everything and a
# gate that works print the same line on a clean tree, so each case below builds
# its own tree: one that must pass, and four that must not.
#
# usage: isolation-check-harness.sh        (ISOLATION_CHECK_SH names the subject)
set -uo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
subject="${ISOLATION_CHECK_SH:-$here/isolation-check.sh}"
[ -r "$subject" ] || { echo "HARNESS REFUSES: no subject at $subject" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1 -- $2"; fail=$((fail + 1)); }
# The forbidden spellings are assembled here so this file never contains one.
src_fort="proof""delve"; src_proj="Forge""Os"
mk() {  # $1 name, $2 line -> a tree whose one machinery file carries that line
  mkdir -p "$work/$1/fort/scripts"
  printf '#!/bin/bash\n%s\n' "$2" > "$work/$1/fort/scripts/a.sh"
  printf '%s' "$work/$1"
}
run() { bash "$subject" --root "$1" 2>&1; }

r="$(mk clean 'echo hello')"; out="$(run "$r")"; rc=$?
if [ "$rc" -eq 0 ] && grep -q 'clean (1 files examined)' <<<"$out"; then ok "a clean tree passes and says how many files it examined"
else no "clean tree" "rc=$rc out=$out"; fi

r="$(mk statedir "state=\$HOME/.local/state/${src_fort}-fleet")"; out="$(run "$r")"; rc=$?
if [ "$rc" -eq 1 ] && grep -q '^fort/scripts/a.sh:2:' <<<"$out"; then ok "RED: the source fort's state directory fails, naming the file and line"
else no "state directory" "rc=$rc out=$out"; fi

r="$(mk repopath "cd /home/x/dev/${src_proj}/fort")"; out="$(run "$r")"; rc=$?
if [ "$rc" -eq 1 ]; then ok "RED: the source fort's repository path fails"
else no "repository path" "rc=$rc out=$out"; fi

r="$(mk citation "# measured there (Proofdelve ${src_proj}-abc.1), carried here")"; out="$(run "$r")"; rc=$?
if [ "$rc" -eq 0 ]; then ok "a bead citation kept as provenance passes"
else no "provenance citation" "rc=$rc out=$out"; fi

r="$(mk both "# (Proofdelve ${src_proj}-abc.1) state=${src_fort}-fleet")"; out="$(run "$r")"; rc=$?
if [ "$rc" -eq 1 ]; then ok "RED: an identifier beside a citation still fails (the citation is removed, not the line)"
else no "identifier beside a citation" "rc=$rc out=$out"; fi

r="$(mk bare "bd show ${src_proj}-abc")"; out="$(run "$r")"; rc=$?
if [ "$rc" -eq 1 ]; then ok "RED: a bead id of the source fort WITHOUT the provenance prefix fails"
else no "unprefixed id" "rc=$rc out=$out"; fi

mkdir -p "$work/empty"; out="$(run "$work/empty")"; rc=$?
if [ "$rc" -eq 3 ]; then ok "a tree with no machinery file is refused (exit 3), never reported clean"
else no "empty tree" "rc=$rc out=$out"; fi

echo "RESULT isolation-check-harness: $pass pass / $fail fail"
[ "$fail" -eq 0 ]
