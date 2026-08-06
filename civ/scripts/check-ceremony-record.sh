#!/bin/bash
# Enforces covenant 8.2 and 8.3 mechanically, because prose is what failed.
#
# 8.2  No seat may transcribe a record in which it is a subject.
# 8.3  No ceremony record is final until an uninvolved read-only seat has read
#      it against the covenant.
#
# Every failure in the founding of this layer was caught by a read-only seat with
# nothing to do but check, and NOT ONE of those checks was required by any rule.
# A safety property that depends on someone volunteering is not a safety property.
#
# Record header, in every ceremony record under civ/annals/:
#
#   <!-- ceremony-record
#   subjects: regent, chronicler
#   transcribed-by: regent
#   read-by: chronicler          (or PENDING)
#   waiver: <reason>             (optional; downgrades an 8.2 FAIL, never hides it)
#   -->
#
# Verdicts:
#   OK           8.2 clean, and an uninvolved seat has read it
#   PROVISIONAL  8.2 clean, read-by PENDING. Not final. Not a fail.
#   WAIVED       violates 8.2 with a recorded reason. Reported every run, forever.
#                A waiver excuses 8.2 ONLY. 8.3 is still enforced on it.
#   BORROWED     read under 8.3 by a seat borrowed from a settlement, because the
#                layer had no uninvolved seat of its own. Visible on purpose: one
#                borrowing is right, a practice of it changes the constitution by
#                repetition.
#   EXEMPT       verbatim source material, not a ceremony record (see SOURCE_DIRS)
#   FAIL         8.2 violation with no waiver, 8.3 violation, or unparseable header
#
# Exit: 0 if no FAIL. PROVISIONAL, WAIVED and EXEMPT never fail the run; they are
# printed so they cannot be quietly forgotten.
#
# DEFECT HISTORY, kept because this script's own failures are the point:
#   2026-08-05, found by Ilva Trueglass, Warden of Manyhalls, reading under 8.3.
#   She refused to attest the edict that introduced this script. Five defects:
#   (1) `field()` was a pipeline whose grep returns 1 when a key is absent;
#       under `set -euo pipefail` that killed the run at the first record with no
#       waiver — i.e. at the first COMPLIANT record. A directory of nothing but
#       waived records exited 0 and printed "satisfied". Her words: "The failure
#       is indistinguishable from diligence."
#   (2) a WAIVED record `continue`d before read-by was examined, so the one rule
#       the waiver was not excusing went unchecked.
#   (3) the glob was `*.md`, so any record one directory down was invisible
#       rather than FAIL.
#   (4) seat names were free text: `transcribed-by: the regent` against
#       `subjects: regent` passed. A typo was an exemption.
#   (5) nothing tested the "read-only" half of 8.3.
set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
CIV="$(cd "$(dirname "$SELF")/.." && pwd)"
ANNALS="$CIV/annals"

# Verbatim source material filed alongside the records: briefs, raw deliveries,
# as-returned text. Not ceremonies, so not header-bearing — but COUNTED and
# reported, never silently skipped (defect 3).
SOURCE_DIRS="sources rulings briefs"

fails=0; total=0; exempt=0

# Roster computed ONCE, never hardcoded, read from civ/seats/.
ROSTER=""
for _s in "$CIV/seats"/*.md; do
  [ -e "$_s" ] || continue
  ROSTER="$ROSTER$(basename "$_s" .md)"$'\n'
done
roster() { printf '%s' "$ROSTER"; }

# Membership tests are PURE BASH, deliberately. An earlier revision used
# `roster | grep -qxF`, and `grep -q` exits the moment it matches, SIGPIPEs the
# upstream pipeline, and `set -o pipefail` then turns a SUCCESSFUL MATCH into a
# nonzero return. Every seat except the last in the roster was reported as
# unknown. That is the third time in one evening this script has failed closed
# for the wrong reason and reported it as a violation of the covenant rather
# than a bug in itself. Defect (6), found by the Regent while fixing (1)-(5).

field() { # $1=file $2=key -> value, lowercased, or empty. Never fails (defect 1).
  { sed -n '/<!-- ceremony-record/,/-->/p' "$1" \
      | grep -i "^[[:space:]]*$2:" \
      | head -1 | cut -d: -f2- \
      | tr '[:upper:]' '[:lower:]' \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; } || true
}

split_list() { printf '%s' "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | { grep -v '^$' || true; }; }
contains_line() { # $1=needle $2=newline-separated haystack; fixed-string, whole-line
  [[ $'\n'"$2"$'\n' == *$'\n'"$1"$'\n'* ]]
}
in_list() { [ -n "$2" ] || return 1; contains_line "$1" "$(split_list "$2")"; }
known_seat() { contains_line "$1" "$ROSTER"; }

# 8.3 asks for a READ-ONLY seat, not merely a different one (defect 5). A seat's
# profile is the evidence. No profile means unmasked, which is not read-only.
writes_annals() { # $1=seat -> 0 if it can write civ/annals, i.e. NOT read-only
  local prof="$CIV/profiles/$1-settings.json"
  [ -f "$prof" ] || return 0
  jq -e '[.permissions.allow[]? | select(test("Write|Edit")) | select(test("civ/annals|civ/\\*\\*|dev/\\*\\*"))] | length > 0' \
     "$prof" >/dev/null 2>&1
}

report() { printf '  %-12s %-46s %s\n' "$1" "$2" "$3"; }

records() { # every .md under civ/annals except the verbatim source dirs
  local -a prune=()
  for d in $SOURCE_DIRS; do prune+=( -path "$ANNALS/$d" -prune -o ); done
  find "$ANNALS" "${prune[@]}" -name '*.md' -type f -print | sort
}

echo "Ceremony records under covenant 8.2 / 8.3 — $ANNALS"
echo "  roster: $(roster | tr '\n' ' ')"
echo

for d in $SOURCE_DIRS; do
  [ -d "$ANNALS/$d" ] || continue
  n=$(find "$ANNALS/$d" -type f | wc -l)
  exempt=$((exempt + n))
  report EXEMPT "$d/" "$n verbatim source file(s), not ceremony records"
done

while IFS= read -r f; do
  total=$((total + 1))
  name="${f#"$ANNALS"/}"

  if ! grep -q '<!-- ceremony-record' "$f"; then
    report FAIL "$name" "no ceremony-record header (8.6)"
    fails=$((fails + 1)); continue
  fi

  subjects="$(field "$f" subjects)"
  scribe="$(field "$f" transcribed-by)"
  reader="$(field "$f" read-by)"
  waiver="$(field "$f" waiver)"

  if [ -z "$scribe" ] || [ -z "$subjects" ] || [ -z "$reader" ]; then
    report FAIL "$name" "header missing subjects, transcribed-by or read-by"
    fails=$((fails + 1)); continue
  fi

  bad_name=""
  for s in $(split_list "$subjects") "$scribe"; do
    known_seat "$s" || bad_name="$s"
  done
  if [ -n "$bad_name" ]; then
    report FAIL "$name" "'$bad_name' is not a seat in civ/seats/ (8.6)"
    fails=$((fails + 1)); continue
  fi

  # --- 8.2 -------------------------------------------------------------------
  verdict=OK; note="transcribed by $scribe"
  if in_list "$scribe" "$subjects"; then
    if [ -z "$waiver" ]; then
      report FAIL "$name" "8.2: '$scribe' is a subject of the record it transcribed"
      fails=$((fails + 1)); continue
    fi
    verdict=WAIVED; note="8.2 waived: $scribe transcribed its own record"
  fi

  # --- 8.3 --- enforced even on a WAIVED record: a waiver excuses 8.2 only ----
  if [ "$reader" = "pending" ]; then
    [ "$verdict" = "OK" ] && verdict=PROVISIONAL
    report "$verdict" "$name" "$note; 8.3: not yet read by an uninvolved seat"
    continue
  fi
  # A reader may be BORROWED from a settlement, written `<seat>@<fort>`. The
  # layer is three seats and every one of them is a subject of anything that
  # amends the covenant, so borrowing is sometimes the only way to satisfy 8.3.
  # It is a distinct verdict so it stays visible: Ilva Trueglass, who took the
  # first borrowed reading, warned that "a layer that routinely reaches into
  # settlements for its own attestations has quietly made the forts an organ of
  # its governance... One borrowing under a stated waiver is right. A practice of
  # it is a change to the constitution made by repetition."
  borrowed=""
  if [[ "$reader" == *@* ]]; then
    rseat="${reader%@*}"; rfort="${reader#*@}"
    # Fort seat files are named by OFFICE (mayor.md, warden.md), not by occupant,
    # so match the declared occupant's given name inside the file.
    rfile="$(grep -ril "^\*\*Held by: *\**$rseat" \
              "/home/justin/dev/$rfort/fort/seats/" 2>/dev/null | head -1 || true)"
    if [ -z "$rfile" ]; then
      report FAIL "$name" "8.3: borrowed reader '$reader' names no occupant in $rfort/fort/seats/"
      fails=$((fails + 1)); continue
    fi
    borrowed=" (borrowed from $rfort: $(basename "$rfile" .md))"
    [ "$verdict" = "WAIVED" ] || verdict=BORROWED
  elif ! known_seat "$reader"; then
    report FAIL "$name" "8.3: reader '$reader' is not a seat in civ/seats/ and is not written <seat>@<fort>"
    fails=$((fails + 1)); continue
  fi
  if in_list "$reader" "$subjects"; then
    report FAIL "$name" "8.3: reader '$reader' is a subject of the record"
    fails=$((fails + 1)); continue
  fi
  if [ "$reader" = "$scribe" ]; then
    report FAIL "$name" "8.3: reader and transcriber are the same seat"
    fails=$((fails + 1)); continue
  fi
  # The read-only half of 8.3. For a civ seat, the evidence is its own profile.
  # For a BORROWED settlement seat the evidence is structural: no fort seat has a
  # write path into civ/ at all — the layer is not in any fort's surface — so
  # being outside the layer IS the read-only guarantee, and it is a guarantee by
  # construction rather than by promise.
  if [ -z "$borrowed" ] && writes_annals "$reader"; then
    report FAIL "$name" "8.3: reader '$reader' is not read-only over civ/annals"
    fails=$((fails + 1)); continue
  fi

  report "$verdict" "$name" "$note; read by $reader$borrowed"
done < <(records)

echo
echo "  $total ceremony record(s), $exempt exempt source file(s), $fails failing"
if [ "$total" -eq 0 ]; then
  echo "  FAIL: no ceremony records were examined. A checker that checks nothing"
  echo "        must never report success (Ilva Trueglass, 8.3 reading, 2026-08-05:"
  echo "        'the failure is indistinguishable from diligence')."
  exit 1
fi
[ "$fails" -eq 0 ] || { echo "  covenant 8.2/8.3 VIOLATED"; exit 1; }
echo "  covenant 8.2/8.3 satisfied (PROVISIONAL, WAIVED and EXEMPT are reported, not passed)"
