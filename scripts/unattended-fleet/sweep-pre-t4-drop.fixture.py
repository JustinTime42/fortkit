#!/usr/bin/env python3
"""Write the no-model Mayor-lane status report.  This script only reads bd."""
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCHEMA = "manyhalls/unattended-mayor-loop/status/v1"
HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get("SWEEP_ROOT", HERE.parent.parent)).resolve()
STATE = Path(os.environ.get("MAYOR_STATUS_STATE", Path.home() / ".local/state/manyhalls-mayor"))
FLEET_STATE = Path(os.environ.get("FLEET_STATE", Path.home() / ".local/state/manyhalls-fleet"))
KEEP_STATE = Path(os.environ.get("MAYOR_KEEP_STATE", Path.home() / ".local/state/manyhalls-keep"))


def run(args, *, stdin=None, env=None):
    try:
        return subprocess.run(args, input=stdin, capture_output=True, text=True, cwd=ROOT, env=env, check=False)
    except OSError as exc:
        return subprocess.CompletedProcess(args, 3, "", str(exc))


def board():
    result = run(["bd", "-C", str(ROOT), "list", "--status", "all", "--limit", "0", "--json"])
    if result.returncode or not result.stdout.strip():
        raise RuntimeError("bd list would not answer: " + result.stderr.strip()[:160])
    value = json.loads(result.stdout)
    value = value.get("data", value) if isinstance(value, dict) else value
    if not isinstance(value, list):
        raise RuntimeError("bd list returned a non-list board")
    return value


def count(rows, label):
    return sum(1 for row in rows if (row.get("status") or "open") != "closed" and label in (row.get("labels") or []))


def has_return_label(row):
    return any(re.fullmatch(r"fleet-return-[0-9]+", label or "")
               for label in (row.get("labels") or []))


def stockable_rows(rows):
    """The triage input is its documented open, dispatchable candidate slice.

    Its ``with both`` total is the mechanical-preparation count used by T4.  Do
    not feed it the complete board: closed, already fleet-safe, and explicitly
    human/Mayor-routed beads are not candidates to stock.
    """
    excluded = {"fleet-safe", "human", "fleet-escalated", "mayor-review"}
    return [row for row in rows
            if (row.get("status") or "open") == "open"
            and not excluded.intersection(row.get("labels") or [])
            and not has_return_label(row)]


def run_sweep(name, rows=None):
    script = HERE / name
    result = run(
        [sys.executable, str(script)],
        stdin=json.dumps(rows) if rows is not None else None,
        env={**os.environ, "ROOT": str(ROOT)},
    )
    text = result.stdout + result.stderr
    # Every existing checker ends with a numeric summary; retain its own result
    # rather than duplicating checker-specific predicates here.
    numbers = re.findall(r"(?m)^(\d+)\s+(?:open |candidate|HOLD|bead|unrouted|)", text)
    named = re.search(r"(?:already-merged|satisfied-holds):\s*(?:none of the |)(\d+)|satisfied-holds:\s*(\d+) satisfied", text)
    findings = int(numbers[-1]) if numbers else None
    if named:
        findings = int(named.group(1) or named.group(2))
    if findings is None and result.returncode == 0:
        findings = 0
    return {"exit": result.returncode if result.returncode in (0, 1, 3) else 3,
            "findings": findings}, text


def queue_depth():
    result = run([str(ROOT / "scripts/queue-lint.sh")])
    match = re.search(
        r"DEPTH -- (\d+) fleet-safe, unblocked bead(?:\(s\)|s)?(?:; |; queue is empty \()"
        r"(?:queue is empty \()?([0-9.]+) hours", result.stdout)
    if not match:
        return None, "queue-lint did not print DEPTH: " + result.stderr.strip()[:160]
    return {"fleet_safe_unblocked": int(match.group(1)), "hours": float(match.group(2))}, None


def work_bit(inbox, depth, stockable, errors):
    if inbox is None:
        return None, ["could not ask inbox"]
    if depth is None or stockable is None:
        return None, ["could not ask T4: " + "; ".join(errors)]
    reasons = []
    if inbox["mayor_review"]:
        reasons.append("T1:%d" % inbox["mayor_review"])
    if inbox["fleet_escalated"]:
        reasons.append("T2:%d" % inbox["fleet_escalated"])
    if inbox["findings_untriaged"]:
        reasons.append("T3:%d" % inbox["findings_untriaged"])
    if depth["hours"] < 1 and stockable > 0:
        reasons.append("T4:%d" % stockable)
    forced = os.environ.get("SWEEP_FORCE_WORK_EXISTS")
    if forced in ("0", "1"):
        return forced == "1", reasons + ["TEST-FORCED"]
    return bool(reasons), reasons


def atomic_write(record):
    STATE.mkdir(parents=True, exist_ok=True)
    target = STATE / "status.json"
    fd, tmp_name = tempfile.mkstemp(prefix="status.json.", suffix=".tmp", dir=STATE)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(record, out, sort_keys=True, separators=(",", ":"))
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp_name, target)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def validate_value(value, schema, path="$"):
    """Small validator for this checked-in, dependency-free JSON Schema subset."""
    kinds = schema.get("type")
    if kinds:
        kinds = kinds if isinstance(kinds, list) else [kinds]
        matches = {
            "object": isinstance(value, dict), "array": isinstance(value, list),
            "string": isinstance(value, str), "integer": isinstance(value, int) and not isinstance(value, bool),
            "number": isinstance(value, (int, float)) and not isinstance(value, bool),
            "boolean": isinstance(value, bool), "null": value is None,
        }
        if not any(matches.get(kind, False) for kind in kinds):
            raise ValueError("%s has wrong type" % path)
    if "const" in schema and value != schema["const"]:
        raise ValueError("%s does not match const" % path)
    if "pattern" in schema and not re.fullmatch(schema["pattern"], value):
        raise ValueError("%s does not match pattern" % path)
    if "minimum" in schema and value < schema["minimum"]:
        raise ValueError("%s is below minimum" % path)
    if isinstance(value, dict):
        required = set(schema.get("required", []))
        if not required.issubset(value):
            raise ValueError("%s is missing required fields" % path)
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False and not set(value).issubset(properties):
            raise ValueError("%s has unexpected fields" % path)
        for key, item in value.items():
            child = properties.get(key, schema.get("additionalProperties"))
            if isinstance(child, dict):
                validate_value(item, child, path + "." + key)
    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for index, item in enumerate(value):
            validate_value(item, schema["items"], "%s[%d]" % (path, index))


def validate_record(record):
    with (ROOT / "docs/specs/unattended-mayor-loop.status.schema.json").open(encoding="utf-8") as source:
        schema = json.load(source)
    validate_value(record, schema)


def main():
    errors = []
    try:
        rows = board()
        inbox = {
            "mayor_review": count(rows, "mayor-review"),
            "fleet_escalated": count(rows, "fleet-escalated"),
            "fleet_return": sum(1 for row in rows if (row.get("status") or "open") != "closed" and has_return_label(row)),
            "gate_ready": count(rows, "gate-ready"),
            "human": count(rows, "human"),
            "findings_untriaged": sum(1 for row in rows if (row.get("status") or "open") == "open" and (row.get("title") or "").startswith("Triage the findings from the fleet-merged review")),
        }
    except (RuntimeError, json.JSONDecodeError) as exc:
        rows, inbox = None, None
        errors.append(str(exc))

    depth, error = queue_depth()
    if error:
        errors.append(error)
    if depth is not None:
        depth["in_progress"] = sum(1 for row in (rows or []) if (row.get("status") or "") == "in_progress") if rows is not None else 0

    triage = run([sys.executable, str(HERE / "triage.py")], stdin=json.dumps(stockable_rows(rows)) if rows is not None else None)
    stockable_match = re.search(r"(\d+) with both", triage.stdout)
    stockable = int(stockable_match.group(1)) if triage.returncode == 0 and stockable_match else None
    if stockable is None:
        errors.append("triage.py could not derive stockable")

    sweeps = {}
    for name, input_rows in (("already-merged.py", None), ("stale-parents.py", rows),
                             ("satisfied-holds.py", None), ("misrouted.py", rows)):
        result, output = run_sweep(name, input_rows)
        sweeps[name] = result
        if result["exit"] == 3:
            errors.append("%s could not ask" % name)

    queue_result = run([str(ROOT / "scripts/queue-lint.sh")])
    headings = [line for line in queue_result.stdout.splitlines() if re.match(r"^[A-Z][A-Z /-]+ --", line)]
    health = {
        "fleet_halt": (FLEET_STATE / "HALT").exists(),
        "mayor_halt": (KEEP_STATE / "mayor-halt").exists(),
        "fleet_run_live": run(["pgrep", "-f", "manyhalls-fleet-run-"]).returncode == 0,
        "disk_free_gb": round(shutil.disk_usage(ROOT).free / (1024 ** 3), 2),
        "ssh_identity": {0: True, 1: False}.get(run(["ssh-add", "-l"]).returncode),
    }
    head = run(["git", "rev-parse", "main"]).stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        head = run(["git", "rev-parse", "HEAD"]).stdout.strip()
        errors.append("main head could not be read")
    exists, reasons = work_bit(inbox, depth, stockable, errors)
    record = {"schema": SCHEMA, "written_at": dt.datetime.now(dt.timezone.utc).isoformat(), "head": head,
              "health": health, "inbox": inbox, "depth": depth,
              "queue_lint": {"exit": queue_result.returncode if queue_result.returncode in (0, 1, 3) else 3, "headings": headings},
              "sweeps": sweeps, "work": {"exists": exists, "reasons": reasons}, "errors": errors}
    validate_record(record)
    atomic_write(record)
    print("sweep: wrote %s (work.exists=%s)" % (STATE / "status.json", json.dumps(exists)))


if __name__ == "__main__":
    main()
