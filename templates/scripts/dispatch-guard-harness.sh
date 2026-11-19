#!/bin/bash
# Harness for fleet.sh's dispatch guard (Proofdelve ForgeOs-9mfw.2).
#
# It tests the SHIPPED function against REAL bd state, extracted from the real
# launcher by anchors, and it exists because the first draft's gate guard was
# INERT and its probe could not tell: `bd ready` had already excluded the gated
# bead, so the whole pass produced the right answer for the wrong reason. Here
# the guard is the only thing deciding, so each verdict is attributable to it.
#
# Usage: scripts/dispatch-guard-harness.sh <yes-bead> <human-bead> <gated-bead>
#
# IT NEEDS FIXTURES AND WILL FAIL LOUDLY WITHOUT THEM. The three beads must be
# OPEN and labelled: the first `fleet-safe` only, the second `fleet-safe` plus
# `human`, the third `fleet-safe` with an open `bd gate create --blocks` against
# it. Pass beads that are merely convenient and every case reports "not labelled
# fleet-safe", which looks like three failures and is three bad fixtures. File
# throwaway probe beads, run, then close them and resolve the gate.
# Refuses (exit 3) when the extraction is incomplete, PER SYMBOL (Proofdelve ForgeOs-675g,
# the class Proofdelve ForgeOs-w7u5 argued for): the anchors are the fragile part, and a
# line count is not a vacuity control. Until 675g this file lifted everything
# from bead_json() down to dispatchable() -- 718 lines at 5cf27de, most of it
# preflight, governor and worker code the guard never calls, referencing symbols
# nobody defined -- and guarded it with `-lt 20`. A drifted anchor that still
# produced twenty lines of the wrong code would have scored as guard failures.
set -uo pipefail
root="${ROOT:-$(cd -- "$(dirname -- "$0")/.." && pwd -P)}"
launcher="${FLEET_SH:-$root/fort/scripts/fleet.sh}"
printf 'launcher=%s\n' "$launcher"
[ -f "$launcher" ] || { echo "HARNESS REFUSES: launcher is missing: $launcher" >&2; exit 3; }
[ $# -eq 3 ] || { echo "usage: $0 <yes-bead> <human-bead> <gated-bead>" >&2; exit 2; }

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# Each function by its own anchors, so the extraction is exactly the subject.
fn() { awk -v name="$1" '$0 ~ ("^" name "\\(\\)[[:space:]]*\\{") {f=1} f{print} f && /^\}$/ {exit}' "$launcher"; }
{ fn bead_json; fn dispatchable; } > "$work/fns.sh"
for sym in bead_json dispatchable; do
  grep -qE "^$sym\(\)[[:space:]]*\{" "$work/fns.sh" \
    || { echo "HARNESS REFUSES: $sym() is not in the extraction from $launcher" >&2; exit 3; }
done
# Every launcher function the extracted code CALLS must be defined in it.
# Called-but-not-defined is always a defect in the instrument, never in the
# guard; it would surface as "command not found" inside a case and be scored
# as the guard refusing. Name it and stop instead.
while read -r callee; do
  if grep -qE "(^|[^[:alnum:]_])$callee([^[:alnum:]_(]|\$)" "$work/fns.sh" \
     && ! grep -qE "^$callee\(\)[[:space:]]*\{" "$work/fns.sh"; then
    echo "HARNESS REFUSES: the extracted guard code CALLS $callee() and does not define it (from $launcher)" >&2; exit 3
  fi
done < <(grep -oE '^[a-z_]+\(\)[[:space:]]*\{' "$launcher" | sed -E 's/\(\)[[:space:]]*\{$//' | sort -u)   # whitespace-tolerant: fleet.sh has four `name()  {` definitions (the Warden, 675g f2)
echo "extracted $(wc -l < "$work/fns.sh") lines of shipped guard code (bead_json, dispatchable) from $launcher"

pass=0; fail=0
run() {  # $1 label, $2 bead, $3 expect yes|no, $4 substring the reason must contain ("-" for none)
  local out rc
  out="$(bash -c "set -uo pipefail; root='$root'; $(cat "$work/fns.sh"); dispatchable '$2' 2>&1")"
  rc=$?
  local got; [ $rc -eq 0 ] && got=yes || got=no
  if [ "$got" != "$3" ]; then
    echo "  FAIL  $1 ($2): got $got want $3 -- $out"; fail=$((fail+1)); return
  fi
  if [ "$4" != "-" ] && ! grep -q "$4" <<<"$out"; then
    echo "  FAIL  $1 ($2): verdict $got correct but reason does not mention '$4' -- $out"; fail=$((fail+1)); return
  fi
  echo "  PASS  $1 ($2): $got${out:+ -- $out}"; pass=$((pass+1))
}

# The first case is the VACUITY CONTROL. Without it a guard that refused
# everything would score a clean sweep on the three refusal cases.
run "dispatchable (vacuity control)" "$1" yes "-"
run "human label refused"            "$2" no  "human label"
run "open gate refused"              "$3" no  "open gate"
run "unknown bead refused"           "{{BEAD_PREFIX}}-nosuchbead" no "-"

echo
echo "RESULT $pass pass / $fail fail"
[ $fail -eq 0 ]
