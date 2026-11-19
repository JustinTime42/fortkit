#!/bin/bash
# Archive closed Beads before pruning them from the live tracker.
set -euo pipefail

DEFAULT_RETENTION="60d"
root="$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)"
retention="$DEFAULT_RETENTION"
dry_run=0
usage() { echo "usage: scripts/bead-archive.sh [--older-than 60d] [--dry-run]" >&2; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --older-than) [ "$#" -ge 2 ] || { usage; exit 2; }; retention="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
case "$retention" in *[!0-9dw]|""|*[dw]*[dw]*) echo "bead-archive: --older-than must be N, Nd, or Nw" >&2; exit 2;; esac

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
export_file="$work/export.jsonl"; selected_file="$work/selected.jsonl"; ids_file="$work/ids"; archive_payload="$work/archive.jsonl.gz"
bd -C "$root" export -o "$export_file"
before_size="$(wc -c < "$export_file" | tr -d ' ')"
python3 - "$export_file" "$selected_file" "$ids_file" "$retention" <<'PY'
import datetime as dt, json, re, sys
source, selected, ids, age = sys.argv[1:]
match = re.fullmatch(r"(\d+)([dw]?)", age)
if not match: raise SystemExit("bead-archive: invalid retention")
cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=int(match.group(1)) * (7 if match.group(2) == "w" else 1))
def timestamp(value):
    if not isinstance(value, str): return None
    try: result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError: return None
    return result if result.tzinfo else result.replace(tzinfo=dt.timezone.utc)
with open(source, encoding="utf-8") as input_file, open(selected, "w", encoding="utf-8") as output_file, open(ids, "w", encoding="utf-8") as id_file:
    for number, line in enumerate(input_file, 1):
        if not line.strip(): continue
        try: bead = json.loads(line)
        except json.JSONDecodeError as error: raise SystemExit(f"bead-archive: invalid export JSON at line {number}: {error}")
        labels, closed_at = set(bead.get("labels") or []), timestamp(bead.get("closed_at"))
        if bead.get("status") == "closed" and closed_at and closed_at < cutoff and not labels.intersection({"pinned", "record", "standing"}):
            output_file.write(json.dumps(bead, separators=(",", ":"), ensure_ascii=False) + "\n")
            id_file.write(str(bead["id"]) + "\n")
PY
selected_count="$(wc -l < "$ids_file" | tr -d ' ')"
if [ "$selected_count" -eq 0 ]; then
  printf 'bead-archive: selected 0 beads; nothing to archive or prune\n'
  exit 0
fi
gzip -c "$selected_file" > "$archive_payload"
payload_size="$(wc -c < "$archive_payload" | tr -d ' ')"
verify_archive() {
  local archive="$1"
  local require_exact_count="$2"
  python3 - "$archive" "$selected_file" "$ids_file" "$require_exact_count" <<'PY'
import collections, gzip, json, sys
archive, selected, ids, require_exact_count = sys.argv[1:]
expected = [line.strip() for line in open(ids, encoding="utf-8") if line.strip()]
expected_rows = {str(row["id"]): row for row in (json.loads(line) for line in open(selected, encoding="utf-8") if line.strip())}
rows=[]
with gzip.open(archive, "rt", encoding="utf-8") as stream:
    for number, line in enumerate(stream, 1):
        if line.strip():
            try: rows.append(json.loads(line))
            except json.JSONDecodeError as error: raise SystemExit(f"bead-archive: archive JSON invalid at line {number}: {error}")
actual=collections.Counter(str(row.get("id", "")) for row in rows)
if require_exact_count == "exact" and len(rows) != len(expected): raise SystemExit(f"bead-archive: archive count {len(rows)} does not match selected count {len(expected)}")
for bead_id in expected:
    if require_exact_count == "exact" and actual[bead_id] != 1: raise SystemExit(f"bead-archive: archived id {bead_id} appears {actual[bead_id]} times")
    matching_rows = [row for row in rows if str(row.get("id", "")) == bead_id]
    if not matching_rows: raise SystemExit(f"bead-archive: archived id {bead_id} is missing")
    if matching_rows[-1] != expected_rows[bead_id]: raise SystemExit(f"bead-archive: last archived id {bead_id} does not match its exported record")
print(f"bead-archive: verified {len(expected)} selected records; last occurrence matches current export")
PY
}
verify_archive "$archive_payload" exact
if [ "$dry_run" -eq 1 ]; then
  printf 'bead-archive: dry-run selected %s beads; archive payload %s bytes; would prune:\n' "$selected_count" "$payload_size"
  sed 's/^/  /' "$ids_file"
  printf 'bead-archive: export size before %s bytes; after %s bytes (dry-run)\n' "$before_size" "$before_size"
  exit 0
fi
month="$(date -u +%Y-%m)"; archive_file="$root/fort/annals/beads-archive-$month.jsonl.gz"
archive_relative="fort/annals/beads-archive-$month.jsonl.gz"
mkdir -p "$(dirname "$archive_file")"
prepare_append_payload() {
  local archive="$1"
  local append_payload="$2"
  local append_ids="$3"
  python3 - "$archive" "$selected_file" "$append_payload" "$append_ids" <<'PY'
import collections, gzip, json, sys
archive, selected, append_payload, append_ids = sys.argv[1:]
selected_rows = [json.loads(line) for line in open(selected, encoding="utf-8") if line.strip()]
archived = collections.defaultdict(list)
with gzip.open(archive, "rt", encoding="utf-8") as stream:
    for number, line in enumerate(stream, 1):
        if line.strip():
            try: archived[str(json.loads(line).get("id", ""))].append(json.loads(line))
            except json.JSONDecodeError as error: raise SystemExit(f"bead-archive: archive JSON invalid at line {number}: {error}")
append_rows = []
for row in selected_rows:
    matches = archived[str(row["id"])]
    if not matches or matches[-1] != row: append_rows.append(row)
if append_rows:
    with gzip.open(append_payload, "wt", encoding="utf-8") as output:
        for row in append_rows: output.write(json.dumps(row, separators=(",", ":"), ensure_ascii=False) + "\n")
else:
    open(append_payload, "wb").close()
with open(append_ids, "w", encoding="utf-8") as output:
    for row in append_rows: output.write(str(row["id"]) + "\n")
PY
}
appended_ids_file="$ids_file"
if [ -f "$archive_file" ]; then
  archive_payload="$work/append.jsonl.gz"
  appended_ids_file="$work/append-ids"
  prepare_append_payload "$archive_file" "$archive_payload" "$appended_ids_file"
fi
append_offset="0"
appended_size="0"
if [ -s "$archive_payload" ]; then
  appended_size="$(wc -c < "$archive_payload" | tr -d ' ')"
  append_offset="$({ wc -c < "$archive_file"; } 2>/dev/null || printf '0')"
  cat "$archive_payload" >> "$archive_file"
fi
if ! verify_archive "$archive_file" appended; then
  printf 'bead-archive: appended archive verification failed for %s; truncate back to byte offset %s to recover\n' "$archive_file" "$append_offset" >&2
  exit 1
fi
appended_ids="$(paste -sd ' ' "$appended_ids_file")"
[ -n "$appended_ids" ] || appended_ids="(none)"
printf 'bead-archive: appended %s bytes for ids: %s\n' "$appended_size" "$appended_ids"
if [ -n "$(git -C "$root" status --porcelain -- "$archive_relative")" ]; then
  printf 'bead-archive: archive must be committed before pruning; run: git -C "%s" add -- "%s" && git -C "%s" commit -m "Archive closed Beads for %s" -- "%s"\n' "$root" "$archive_relative" "$root" "$month" "$archive_relative" >&2
  exit 1
fi
pruned_count=0
remaining_ids=()
while IFS= read -r bead_id; do
  [ -z "$bead_id" ] && continue
  if bd -C "$root" prune --older-than "$retention" --pattern "$bead_id" --force </dev/null; then
    pruned_count=$((pruned_count + 1))
  else
    remaining_ids+=("$bead_id")
    while IFS= read -r remaining_id; do [ -z "$remaining_id" ] || remaining_ids+=("$remaining_id"); done
    printf 'bead-archive: prune failed after %s ids; remaining ids: %s\n' "$pruned_count" "${remaining_ids[*]}" >&2
    exit 1
  fi
done < "$ids_file"
after_export="$work/after-export.jsonl"; bd -C "$root" export -o "$after_export"
after_size="$(wc -c < "$after_export" | tr -d ' ')"
printf 'bead-archive: archived %s beads to %s (%s bytes appended; appended ids: %s) and pruned verified ids\n' "$selected_count" "$archive_file" "$appended_size" "$appended_ids"
printf 'bead-archive: export size before %s bytes; after %s bytes\n' "$before_size" "$after_size"
