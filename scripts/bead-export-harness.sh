#!/bin/bash
# Hermetic regression harness for scripts/bead-export.sh.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
subject="${BEAD_EXPORT_SRC:-$here/bead-export.sh}"
[ -f "$subject" ] || { echo "HARNESS REFUSES: subject is missing: $subject" >&2; exit 3; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
repo="$work/repo"; stub="$work/stub"; fixture="$work/full.jsonl"
mkdir -p "$repo/.beads" "$repo/scripts" "$stub"
git -C "$repo" init -q -b main
cp -f "$subject" "$repo/scripts/bead-export.sh"; chmod 755 "$repo/scripts/bead-export.sh"

python3 - "$fixture" <<'PY'
import datetime as dt
import json
import sys

now = dt.datetime.now(dt.timezone.utc)
def timestamp(days_ago):
    return (now - dt.timedelta(days=days_ago)).isoformat().replace("+00:00", "Z")

rows=[
 {"id":"ForgeOs-old","created_at":timestamp(15),"status":"closed","closed_at":timestamp(15),"description":"old","acceptance_criteria":"old criteria","close_reason":"r"*350,"comments":[{}]},
 {"id":"ForgeOs-recent","created_at":timestamp(1),"status":"closed","closed_at":timestamp(1),"description":"recent","acceptance_criteria":"recent criteria","comments":[{}]},
 # The exporter trims only timestamps strictly older than its calculated cutoff.
 # By export time, this timestamp is microscopically older than a fresh 14-day cutoff.
 {"id":"ForgeOs-boundary","created_at":timestamp(14),"status":"closed","closed_at":timestamp(14),"description":"boundary","acceptance_criteria":"boundary criteria","comments":[{}]},
 {"id":"ForgeOs-open","created_at":timestamp(1),"status":"open","description":"open","acceptance_criteria":"open criteria","comments":[{}]}]
with open(sys.argv[1],"w") as f:
 for row in rows: f.write(json.dumps(row)+"\n")
PY

cat > "$stub/bd" <<'SH'
#!/bin/bash
if [ "${HARNESS_BD_FAIL:-0}" = 1 ]; then exit 17; fi
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then cp -f "$HARNESS_FIXTURE" "$2"; exit 0; fi
  shift
done
exit 3
SH
chmod 755 "$stub/bd"

run_export() { HARNESS_FIXTURE="$fixture" PATH="$stub:$PATH" "$repo/scripts/bead-export.sh" >/dev/null; }
valid() { python3 - "$repo/.beads/issues.jsonl" "$1" <<'PY'
import json
import sys

path, mode = sys.argv[1:]
rows = {row.get("id"): row for row in map(json.loads, open(path, encoding="utf-8"))}
expected_ids = {"ForgeOs-old", "ForgeOs-recent", "ForgeOs-boundary", "ForgeOs-open"}

try:
    if mode == "ids":
        assert set(rows) == expected_ids, f"expected ids {sorted(expected_ids)}, got {sorted(rows)}"
    elif mode == "comments":
        assert all("comments" not in row for row in rows.values()), "comments were retained"
    elif mode == "old":
        old = rows.get("ForgeOs-old", {})
        assert "description" not in old and "acceptance_criteria" not in old, "15-day bead retained details"
        assert len(old.get("close_reason", "")) == 300, "15-day close reason was not limited to 300 characters"
    elif mode == "recent":
        assert rows.get("ForgeOs-recent", {}).get("description") == "recent", "1-day bead lost its description"
    elif mode == "boundary":
        boundary = rows.get("ForgeOs-boundary", {})
        assert "description" not in boundary and "acceptance_criteria" not in boundary, "14-day boundary bead retained details"
    elif mode == "open":
        assert rows.get("ForgeOs-open", {}).get("description") == "open", "open bead lost its description"
except AssertionError as error:
    print(f"FAIL {mode}: {error}")
    raise SystemExit(1)
PY
}

pass=0; fail=0
expect_pass() {
  local label="$1"
  shift
  if "$@"; then
    echo "  PASS  $label"
    pass=$((pass+1))
  else
    echo "  FAIL  $label"
    fail=$((fail+1))
    return 1
  fi
}
run_export || { echo "HARNESS REFUSES: baseline export failed" >&2; exit 3; }
for check in ids comments old recent boundary open; do
  expect_pass "$check" valid "$check" || break
done
printf 'sentinel\n' > "$repo/.beads/issues.jsonl"
if HARNESS_BD_FAIL=1 HARNESS_FIXTURE="$fixture" PATH="$stub:$PATH" "$repo/scripts/bead-export.sh" >/dev/null 2>&1; then
  echo "  FAIL  red failed bd export returned zero"; fail=$((fail+1))
elif [ "$(cat "$repo/.beads/issues.jsonl")" = sentinel ]; then
  echo "  PASS  red failed bd export keeps old file"; pass=$((pass+1))
else
  echo "  FAIL  red failed bd export clobbers old file"; fail=$((fail+1))
fi
echo "RESULT $pass pass / $fail fail"
[ "$fail" = 0 ]
