#!/bin/bash
# signature-source-harness: which stream events fleet.sh reads as the
# Overseer's signature (ForgeOs-jib0; ruled 2026-11-14, built at the Regent
# sitting of 2026-11-16).
#
# It extracts the SHIPPED latest_approved_sha() from fleet.sh and runs it
# against fixture event streams. The property: only the Keep's own events
# (actor justin, seat overseer) are sign events. A Mayor or Regent
# transcription neither supersedes a Keep approval nor counts as one.
# The red arm is generated from the subject by removing the filter line, so
# it needs no git history and runs anywhere the subject can be read.
#
# Subject: FLEET_SH, or fort/scripts/fleet.sh beside this file's parent.
# Exit: 0 all passed; 1 a case failed or did not run; 3 refused.
# shellcheck disable=SC2016  # file-wide: single-quoted runner bodies and source patterns
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fleet="${FLEET_SH:-$here/../fort/scripts/fleet.sh}"
[ -f "$fleet" ] || { echo "HARNESS REFUSES: no subject at $fleet (set FLEET_SH)"; exit 3; }
work="$(mktemp -d "${TMPDIR:-/tmp}/signature-source-harness.XXXXXX")"
case "$work" in /*) ;; *) echo "HARNESS REFUSES: scratch dir is not absolute"; exit 3 ;; esac
trap 'rm -rf "$work"' EXIT
awk '/^latest_approved_sha\(\) \{/{f=1} f{print} f && /^}/{exit}' "$fleet" > "$work/fn.sh"
if ! grep -q '^latest_approved_sha() {' "$work/fn.sh" || ! bash -n "$work/fn.sh"; then
  echo "HARNESS REFUSES: latest_approved_sha() could not be extracted from $fleet"; exit 3
fi
pass=0; fail=0; notrun=0
ok()  { pass=$((pass+1)); echo "PASS $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1 -- $2"; }
r=""; n=0
mk() { n=$((n+1)); r="$work/root$n"; mkdir -p "$r/fort/events"; sec=0; }
ev() {  # $1 actor, $2 seat ("" = null), $3 category, $4 payload JSON (default null); each event one second after the last
  sec=$((sec+1))
  local seat='null'; [ -n "$2" ] && seat="\"$2\""
  printf '{"ts":"2026-11-16T10:00:%02d-09:00","actor":"%s","seat":%s,"category":"%s","target":"B-1","detail":"x B-2 y","payload":%s}\n' \
    "$sec" "$1" "$seat" "$3" "${4:-null}" >> "$r/fort/events/events-2026-11-16.jsonl"
}
ask() {  # $1 function file -> what latest_approved_sha prints for B-1
  root="$r" bash -c 'source "$1"; latest_approved_sha B-1' _ "$1" 2>/dev/null
}
is() { local got; got="$(ask "$work/fn.sh")"; if [ "$got" = "$2" ]; then ok "$1"; else bad "$1" "expected [$2], got [$got]"; fi; }
SHA='{"approvedSha":"abc123","branch":"bead/1"}'

mk; ev justin overseer gate.approved "$SHA"
is "1 a Keep approve is read: its sha" abc123
mk; ev justin overseer gate.approved "$SHA"; ev marrek mayor decision.recorded
is "2 a Mayor decision.recorded after a Keep approve: the approval stands" abc123
mk; ev justin overseer gate.approved "$SHA"; ev calder regent decision.recorded '{"transcribedBy":"calder"}'
is "2b a Regent decision.recorded after a Keep approve: the approval stands" abc123
mk; ev justin overseer gate.approved "$SHA"; ev justin overseer gate.declined
is "3 a Keep decline after a Keep approve still supersedes" "SUPERSEDED gate.declined 2026-11-16T10:00:02-09:00"
mk; ev justin overseer gate.approved "$SHA"; ev justin overseer decision.recorded
is "4 the Keep's own decision.recorded after its approve still supersedes" "SUPERSEDED decision.recorded 2026-11-16T10:00:02-09:00"
mk; ev marrek mayor gate.approved "$SHA"
is "5 a gate.approved the Keep did not emit is not an approval" ""
mk; ev justin overseer gate.declined; ev calder regent gate.approved "$SHA"
is "6 a transcribed gate.approved after a Keep decline does not revive the bead" "SUPERSEDED gate.declined 2026-11-16T10:00:01-09:00"
mk; ev justin "" gate.approved "$SHA"
is "7 actor justin without the overseer seat is not the Keep's shape" ""
mk; ev justin overseer gate.approved "$SHA"; ev marrek mayor gate.declined; ev marrek mayor decision.recorded
is "8 two later Mayor events of both kinds: the approval stands" abc123

# RED ARM: the subject with the filter line removed must fail case 2 (it reads the Mayor's event as the newest sign event).
filter='                if e.get("actor") != "justin" or e.get("seat") != "overseer": continue'
if [ "$(grep -cxF "$filter" "$work/fn.sh")" = 1 ]; then
  grep -vxF "$filter" "$work/fn.sh" > "$work/fn-red.sh"
  mk; ev justin overseer gate.approved "$SHA"; ev marrek mayor decision.recorded
  got="$(ask "$work/fn-red.sh")"
  case "$got" in "SUPERSEDED decision.recorded "*) ok "R1 red arm: without the filter a Mayor decision.recorded supersedes the Keep approve [$got]" ;; *) bad "R1 red arm" "the unfiltered variant gave [$got]; case 2 cannot discriminate" ;; esac
  mk; ev marrek mayor gate.approved "$SHA"
  got="$(ask "$work/fn-red.sh")"
  if [ "$got" = abc123 ]; then ok "R2 red arm: without the filter a Mayor gate.approved reads as an approval"; else bad "R2 red arm" "got [$got]"; fi
else
  notrun=$((notrun+1)); echo "NOT RUN R1/R2 -- the filter line is not in the subject in the spelling this harness removes (the cases above then fail on their own if the property is gone)"
fi
echo "RESULT signature-source-harness: $pass pass / $fail fail / $notrun not run (subject: $fleet)"
[ "$fail" = 0 ] && [ "$notrun" = 0 ]
