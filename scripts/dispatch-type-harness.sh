#!/bin/bash
# THE DEPENDENCY-TYPE HALF OF fleet.sh's DISPATCH GUARD (ForgeOs-czhb).
#
# It runs the SHIPPED bead_json() + dispatchable(), extracted from the launcher by
# anchors, against bd records — and it exists because the sitting that fixed
# ForgeOs-czhb proved its acceptance with an ad-hoc script that lived nowhere.
# Tova Marrowassay's covenant-4.5 review of that sitting said so in terms: the
# nine-case result was "not committed anywhere", so nobody could re-execute it.
# This is that script, committed.
#
# WHY THE RECORDS ARE BAKED IN RATHER THAN QUERIED. `bd` cannot run from the
# Warden's mask at all — embedded Dolt opens the database read-write even to
# serve a read, and .beads is bound read-only, so every invocation dies at LOCK
# (ForgeOs-rydv's neighbourhood). A harness that shelled out to bd would be
# unrunnable by the one seat whose job is to re-run it. The four REAL records
# below were captured from this tracker with `bd show <id> --json` on 2026-09-10
# and trimmed to the fields dispatchable() reads; re-capture them the same way if
# the beads move.
#
# ONE FIELD IS EDITED, AND IT IS DISCLOSED BECAUSE IT MATTERS: `labels` is set to
# ["fleet-safe","lands-on-review"] on every record (lands-on-review since
# ForgeOs-vee4w round two, whose classification check also sits above the
# dependency branch; SYN-unclassified below is the one record without it). That gate sits ABOVE the dependency branch in
# dispatchable(), so without it no specimen reaches the loop under test at all
# and every case would report "not labelled fleet-safe". Every `dependencies`
# array is exactly what bd returned.
#
# THE FIVE SYN- RECORDS ARE SYNTHETIC ON PURPOSE: no bead in this tracker carries
# an absent, empty or unrecognised dependency type, and a guard whose fail-closed
# default is never exercised is a guard shown only not to fire.
#
# Usage:  scripts/dispatch-type-harness.sh [launcher]   # $1, else FLEET_SH, else $ROOT/fort/scripts/fleet.sh (ROOT defaults to the tree this file lives in)
# Inversion:  git show a2acdbe:fort/scripts/fleet.sh > /tmp/pre.sh
#             scripts/dispatch-type-harness.sh /tmp/pre.sh    # must score 2/7
# Refuses (exit 3) on an empty extraction or a missing dispatchable().
set -uo pipefail
root="${ROOT:-$(cd -- "$(dirname -- "$0")/.." && pwd -P)}"
launcher="${1:-${FLEET_SH:-$root/fort/scripts/fleet.sh}}"
printf 'launcher=%s\n' "$launcher"
[ -f "$launcher" ] || { echo "HARNESS REFUSES: launcher is missing: $launcher" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/rec"

# the records, one per line: <id><TAB><json>
while IFS=$'\t' read -r id js; do
  [ -n "$id" ] || continue
  printf '%s\n' "$js" > "$work/rec/$id.json"
done <<'RECORDS'
ForgeOs-b0vj.23	{"id":"ForgeOs-b0vj.23","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":1,"dependencies":[{"id":"ForgeOs-b0vj","status":"open","issue_type":"epic","dependency_type":"parent-child"}]}
ForgeOs-s2lx	{"id":"ForgeOs-s2lx","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":1,"dependencies":[{"id":"ForgeOs-j3kp","status":"open","issue_type":"task","dependency_type":"discovered-from"}]}
ForgeOs-5md6	{"id":"ForgeOs-5md6","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":1,"dependencies":[{"id":"ForgeOs-b0vj.4.2","status":"closed","issue_type":"task","dependency_type":"blocks"}]}
ForgeOs-aqc6.2.3	{"id":"ForgeOs-aqc6.2.3","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":4,"dependencies":[{"id":"ForgeOs-91p2.18","status":"closed","issue_type":"bug","dependency_type":"blocks"},{"id":"ForgeOs-aqc6.2.1","status":"closed","issue_type":"task","dependency_type":"blocks"},{"id":"ForgeOs-aqc6.2","status":"open","issue_type":"feature","dependency_type":"parent-child"},{"id":"ForgeOs-aqc6.2.8","status":"open","issue_type":"feature","dependency_type":"blocks"}]}
SYN-untyped	{"id":"SYN-untyped","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":1,"dependencies":[{"id":"SYN-parent","status":"open","issue_type":"task"}]}
SYN-unknown	{"id":"SYN-unknown","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":1,"dependencies":[{"id":"SYN-parent","status":"open","issue_type":"task","dependency_type":"quantum-entangles"}]}
SYN-empty	{"id":"SYN-empty","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":1,"dependencies":[{"id":"SYN-parent","status":"open","issue_type":"task","dependency_type":""}]}
SYN-gate-pc	{"id":"SYN-gate-pc","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":1,"dependencies":[{"id":"SYN-gate","status":"open","issue_type":"gate","dependency_type":"parent-child"}]}
SYN-unclassified	{"id":"SYN-unclassified","status":"open","labels":["fleet-safe"],"dependency_count":0,"dependencies":[]}
SYN-listkey	{"id":"SYN-listkey","status":"open","labels":["fleet-safe","lands-on-review"],"dependency_count":1,"dependencies":[{"id":"SYN-parent","status":"open","issue_type":"task","type":"parent-child"}]}
RECORDS

# A stub bd that serves ONLY `show`, because that is the only call bead_json()
# makes. Anything else answers `null`, so a guard that reached for another
# subcommand would fail closed here rather than quietly succeed.
cat > "$work/bin/bd" <<'B'
#!/bin/bash
a=("$@"); [ "${a[0]:-}" = "-C" ] && a=("${a[@]:2}")
[ "${a[0]:-}" = "show" ] || { echo null; exit 0; }
f="$REC/${a[1]}.json"; [ -f "$f" ] && cat "$f" || echo null
B
chmod +x "$work/bin/bd"; export PATH="$work/bin:$PATH" REC="$work/rec"

awk '/^bead_json\(\)[[:space:]]*\{/{f=1} f{print} /^dispatchable\(\)[[:space:]]*\{/{g=1} g&&/^\}$/{f=0;g=0}' \
  "$launcher" > "$work/fns.sh"
lines=$(wc -l < "$work/fns.sh")
[ "$lines" -ge 20 ] || { echo "HARNESS REFUSES: extracted only $lines lines from $launcher" >&2; exit 3; }
for sym in bead_json dispatchable; do
  grep -qE "^$sym\(\)" "$work/fns.sh" \
    || { echo "HARNESS REFUSES: $sym() is not in the extraction" >&2; exit 3; }
done
echo "extracted $lines lines of shipped guard code from $launcher"

pass=0; fail=0
run() { # $1 label, $2 bead, $3 expect yes|no, $4 substring the reason must contain ("-" = none), [$5 second argument to dispatchable]
  local out rc got
  out="$(bash -c "set -uo pipefail; root='/nonexistent'; $(cat "$work/fns.sh"); dispatchable '$2' '${5:-}' 2>&1")"; rc=$?
  [ $rc -eq 0 ] && got=yes || got=no
  if [ "$got" != "$3" ]; then
    echo "  FAIL  $1 [$2]: got $got want $3 -- $out"; fail=$((fail+1)); return; fi
  if [ "$4" != "-" ] && ! grep -q -- <<<"$out" "$4"; then
    echo "  FAIL  $1 [$2]: verdict $got correct but reason lacks '$4' -- $out"; fail=$((fail+1)); return; fi
  echo "  PASS  $1 [$2]: $got${out:+ -- $out}"; pass=$((pass+1))
}

echo "--- REAL records, captured from the live tracker ---"
# Cases 1 and 2 are the DISPATCH side and are this file's vacuity controls: a
# guard that refused everything would sweep all seven refusal cases below.
run "1 parent-child edge to an OPEN bead DISPATCHES"        ForgeOs-b0vj.23  yes "-"
run "2 discovered-from edge to an OPEN bead DISPATCHES"     ForgeOs-s2lx     yes "-"
run "3 blocks edge to a CLOSED bead DISPATCHES"             ForgeOs-5md6     yes "-"
# Case 4 carries FOUR edges -- two closed blocks, an OPEN parent-child, and an
# OPEN blocks -- so it also proves the loop does not stop at the first open edge.
# The pre-fix file refuses it naming ForgeOs-aqc6.2, the parent-child one.
run "4 blocks edge to an OPEN bead REFUSES, past an open parent-child" \
                                                            ForgeOs-aqc6.2.3 no  "aqc6.2.8"
echo "--- synthetic: shapes bd has not produced in this tracker ---"
run "5 an absent type REFUSES (bd dep add defaults to blocks)" SYN-untyped  no "records no type"
run "6 an unrecognised type REFUSES"                          SYN-unknown  no "not a known non-blocking type"
run "7 an empty-string type REFUSES"                          SYN-empty    no "records no type"
run "8 a GATE refuses whatever its edge type says"            SYN-gate-pc  no "open gate"
# bd reports the type under `dependency_type` on `show` and under `type` on
# `list`, each leaving the other null (ForgeOs-v30w). The guard reads both, and
# this is the case that says so.
run "9 the bd-list key spelling is honoured too"              SYN-listkey  yes "-"

# ForgeOs-vee4w round two: the Mayor's classification is positive. An unlabelled
# bead is refused on an ordinary dispatch and passes on a signed landing, where
# his signature is the gate.
run "10 a bead carrying neither landing class REFUSES"        SYN-unclassified no "unclassified"
run "11 the same bead PASSES on a signed landing"             SYN-unclassified yes "-" signed

echo
echo "RESULT $pass pass / $fail fail"
[ $fail -eq 0 ]
