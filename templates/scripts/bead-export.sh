#!/bin/bash
# Refresh the tracked, reader-safe projection of the live Beads export.
set -uo pipefail

CLOSED_BEAD_RETENTION_DAYS=14
CLOSE_REASON_MAX_CHARACTERS=300

root="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)" || exit 3
beads_dir="$root/.beads"
target="$beads_dir/issues.jsonl"
[ -d "$beads_dir" ] || { echo "bead-export: missing $beads_dir" >&2; exit 3; }

full_export="$(mktemp "$beads_dir/.issues.full.XXXXXX")" || exit 3
slim_export="$(mktemp "$beads_dir/.issues.slim.XXXXXX")" || { rm -f "$full_export"; exit 3; }
cleanup() { rm -f "$full_export" "$slim_export"; }
trap cleanup EXIT

if ! bd -C "$root" export -o "$full_export"; then
  echo "bead-export: bd export failed; leaving $target untouched" >&2
  exit 1
fi

if ! python3 - "$full_export" "$slim_export" "$CLOSED_BEAD_RETENTION_DAYS" "$CLOSE_REASON_MAX_CHARACTERS" <<'PY'
import datetime as dt
import json
import sys

source, destination, retention_days, close_reason_limit = sys.argv[1:]
retention = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=int(retention_days))

def parse_timestamp(value):
    if not isinstance(value, str):
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None

with open(source, encoding="utf-8") as input_file, open(destination, "w", encoding="utf-8") as output_file:
    for line_number, line in enumerate(input_file, start=1):
        if not line.strip():
            continue
        try:
            bead = json.loads(line)
        except json.JSONDecodeError as error:
            raise SystemExit(f"bead-export: invalid JSON from bd export at line {line_number}: {error}")
        bead.pop("comments", None)
        closed_at = parse_timestamp(bead.get("closed_at"))
        if bead.get("status") == "closed" and closed_at is not None and closed_at < retention:
            bead.pop("description", None)
            bead.pop("acceptance_criteria", None)
            close_reason = bead.get("close_reason")
            if isinstance(close_reason, str):
                bead["close_reason"] = close_reason[:int(close_reason_limit)]
        output_file.write(json.dumps(bead, separators=(",", ":"), ensure_ascii=False))
        output_file.write("\n")
PY
then
  echo "bead-export: could not slim export; leaving $target untouched" >&2
  exit 1
fi

mv -f "$slim_export" "$target"
echo "bead-export: refreshed $target"
