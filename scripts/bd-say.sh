#!/usr/bin/env bash
# bd-say.sh — write bd field text FROM A FILE and prove it landed.
#
# WHY THIS EXISTS (Proofdelve ForgeOs-ptfdx, and three siblings on 2026-09-21/22).
# Four times in two days, bd field text built as an INLINE shell argument was
# mangled before bd ever saw it: backticks executed and ate two terms from the
# Proofdelve ForgeOs-iuhnd record; an apostrophe then backticks broke a python -c block;
# `$(...)` plus `$?` shipped an acceptance criterion reading "exit 127"; and
# backticks ate two identifiers from a Proofdelve ForgeOs-8ge4 diagnosis FORTY MINUTES
# after the Mayor committed a memory fact telling itself never to do this.
#
# The fact was correct, recent, and load-bearing, and it lost to the habit of
# typing a short comment directly. Prose does not enforce. This does two things
# prose cannot:
#   1. There is no inline form. Text comes from a file or the call fails.
#   2. It READS THE FIELD BACK and fails if what bd stored is not what was sent.
#      `bd update` prints "✓ Updated issue" whether or not it stored anything,
#      and --description/--notes/--design/--acceptance all REPLACE rather than
#      append, so a silent truncation looks identical to a success.
#
# Usage:
#   scripts/bd-say.sh comment    <bead-id> <file>
#   scripts/bd-say.sh acceptance <bead-id> <file>   # REPLACES
#   scripts/bd-say.sh design     <bead-id> <file>   # REPLACES
#   scripts/bd-say.sh notes      <bead-id> <file>   # REPLACES
#   scripts/bd-say.sh acceptance-append <bead-id> <file>   # keeps what is there
#   scripts/bd-say.sh design-append     <bead-id> <file>
#   scripts/bd-say.sh notes-append      <bead-id> <file>
#
# WHY THE APPEND MODE EXISTS (Proofdelve ForgeOs-dgnjj, measured on the author 2026-09-22).
# The replace modes above are the whole hazard. A caller who wants to ADD a
# paragraph has to read the field, append, and write the result back -- and the
# read is the part nothing was checking. I wrote such a helper, read the field
# with `bd list --json` under the key `acceptance`, and got an empty string,
# because that output names it `acceptance_criteria`. The append produced only
# the new paragraph and this script faithfully replaced the acceptance criteria
# of four beads with it, reported success, and was right to: what was sent is
# what was stored. A transport check cannot see that the caller sent the wrong
# thing.
#
# So the read-modify-write lives HERE now, where the key spelling is already
# known, and it REFUSES on an empty read. An append onto nothing is a replace,
# and a caller who means to replace has a mode that says so.
#
# Exit: 0 wrote and verified; 2 usage; 3 refused before writing; 4 wrote but the
# read-back did not match (the dangerous case — the bead is now in an unknown
# state and the operator must look).
set -uo pipefail

usage() { sed -n '2,28p' "$0" >&2; exit 2; }
[ "$#" -eq 3 ] || usage
field="$1"; bead="$2"; src="$3"

append=false
case "$field" in
  comment|acceptance|design|notes) ;;
  acceptance-append|design-append|notes-append) append=true; field="${field%-append}" ;;
  *) echo "bd-say: unknown field '$field'" >&2; usage ;;
esac
[ -f "$src" ] || { echo "bd-say: REFUSED, no such file: $src" >&2; exit 3; }
[ -s "$src" ] || { echo "bd-say: REFUSED, file is empty: $src" >&2; exit 3; }

# THE ONE PLACE THAT KNOWS THE KEY SPELLING. bd's JSON calls the acceptance
# field `acceptance_criteria`; `design` and `notes` are themselves. Both the
# read-back below and the append mode go through here, so there is no second
# spelling to get wrong.
read_field() {  # $1 bead, $2 field -> prints stored text, empty if absent
  bd show "$1" --json 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);d=d[0] if isinstance(d,list) else d;print(d.get('${2/acceptance/acceptance_criteria}') or '')"
}

# APPEND: read, refuse on empty, no-op if already present, otherwise build the
# combined text and fall through to the ordinary write and read-back.
if [ "$append" = true ]; then
  current="$(read_field "$bead" "$field")"
  if [ -z "$(printf '%s' "$current" | tr -d '[:space:]')" ]; then
    echo "bd-say: REFUSED, $bead $field is empty; an append onto nothing is a replace." >&2
    echo "  If you mean to replace it, use: bd-say.sh $field $bead <file>" >&2
    exit 3
  fi
  add_first="$(grep -m1 -v '^[[:space:]]*$' "$src" || true)"
  add_last="$(grep -v '^[[:space:]]*$' "$src" | tail -1 || true)"
  if printf '%s' "$current" | grep -qF -- "$add_first" && printf '%s' "$current" | grep -qF -- "$add_last"; then
    echo "bd-say: $bead $field already carries this text; nothing written."
    exit 0
  fi
  combined="$(mktemp)"; trap 'rm -f "$combined"' EXIT
  { printf '%s\n' "$current"; cat "$src"; } > "$combined"
  prefix_probe="$current"
  src="$combined"
fi

# A probe of the text as it will be stored. Taken BEFORE the write so a failure
# here costs nothing; these are the first and last non-blank lines plus the
# length, which together catch a truncation at either end.
first="$(grep -m1 -v '^[[:space:]]*$' "$src" || true)"
last="$(grep -v '^[[:space:]]*$' "$src" | tail -1 || true)"
want_len="$(wc -c < "$src" | tr -d ' ')"
[ -n "$first" ] || { echo "bd-say: REFUSED, file has no non-blank line: $src" >&2; exit 3; }

case "$field" in
  comment)    bd comment "$bead" "$(cat "$src")" >/dev/null 2>&1 ;;
  acceptance) bd update  "$bead" --acceptance="$(cat "$src")" >/dev/null 2>&1 ;;
  design)     bd update  "$bead" --design="$(cat "$src")" >/dev/null 2>&1 ;;
  notes)      bd update  "$bead" --notes="$(cat "$src")" >/dev/null 2>&1 ;;
esac
wrc=$?

# THE READ-BACK. bd's own success line is not evidence (Proofdelve ForgeOs-15k.8: bd show
# --json returns comment_count and no bodies, so comments are read with
# `bd comments`). Both anchors must be present in what bd actually stored.
got="$(
  if [ "$field" = comment ]; then
    bd comments "$bead" --json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print((d[-1].get("text") or "") if d else "")'
  else
    read_field "$bead" "$field"
  fi
)"

if [ -z "$got" ] || ! printf '%s' "$got" | grep -qF -- "$first" || ! printf '%s' "$got" | grep -qF -- "$last"; then
  echo "bd-say: WROTE BUT READ-BACK FAILED on $bead ($field). bd exit was $wrc." >&2
  echo "  sent $want_len bytes; stored $(printf '%s' "$got" | wc -c | tr -d ' ') bytes." >&2
  echo "  first line present: $(printf '%s' "$got" | grep -qF -- "$first" && echo yes || echo NO)" >&2
  echo "  last  line present: $(printf '%s' "$got" | grep -qF -- "$last"  && echo yes || echo NO)" >&2
  echo "  The bead is in an unknown state. Look at it before writing again." >&2
  exit 4
fi

# AN APPEND HAS ONE MORE THING TO PROVE than a replace: that it did not replace.
# The anchors above only show the NEW text arrived, which is exactly what was
# true in the incident that caused this mode to exist.
if [ "$append" = true ]; then
  got_now="$(read_field "$bead" "$field")"
  if ! printf '%s' "$got_now" | grep -qF -- "$(printf '%s' "$prefix_probe" | grep -m1 -v '^[[:space:]]*$')"; then
    echo "bd-say: APPENDED BUT THE ORIGINAL TEXT IS GONE on $bead ($field)." >&2
    echo "  The bead is in an unknown state. Look at it before writing again." >&2
    exit 4
  fi
fi

echo "bd-say: $bead $field written and verified ($want_len bytes, both anchors present)"
