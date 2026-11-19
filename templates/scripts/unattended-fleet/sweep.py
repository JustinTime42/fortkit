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

SCHEMA = "{{FORT_SLUG}}/unattended-mayor-loop/status/v1"
HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get("SWEEP_ROOT", HERE.parent.parent)).resolve()
STATE = Path(os.environ.get("MAYOR_STATUS_STATE", Path.home() / ".local/state/{{FORT_SLUG}}-mayor"))
FLEET_STATE = Path(os.environ.get("FLEET_STATE", Path.home() / ".local/state/{{FORT_SLUG}}-fleet"))
KEEP_STATE = Path(os.environ.get("MAYOR_KEEP_STATE", Path.home() / ".local/state/{{FORT_SLUG}}-keep"))


def run(args, *, stdin=None, env=None):
    try:
        kwargs = {"capture_output": True, "text": True, "cwd": ROOT, "env": env, "check": False}
        if stdin is None:
            kwargs["stdin"] = subprocess.DEVNULL
        else:
            kwargs["input"] = stdin
        return subprocess.run(args, **kwargs)
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


def run_sweep(name, rows=None):
    script = HERE / name
    result = run(
        [sys.executable, str(script)],
        stdin=json.dumps(rows) if rows is not None else None,
        env={**os.environ, "ROOT": str(ROOT)},
    )
    text = result.stdout + result.stderr
    # Every checker owns the meaning of its result.  In particular, the
    # already-merged clean message contains a number of beads *scanned*, not
    # findings, so only consume its explicit summary line.
    numbers = re.findall(r"(?m)^(\d+)\s+(?:open |candidate|HOLD|bead|unrouted|)", text)
    named = re.findall(
        r"(?m)^(?:already-merged: (\d+) findings|satisfied-holds: (\d+) satisfied,)",
        text,
    )
    findings = int(numbers[-1]) if numbers else None
    if named:
        findings = int(named[-1][0] or named[-1][1])
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
        return None, "queue-lint did not print DEPTH: " + result.stderr.strip()[:160], result
    return {"fleet_safe_unblocked": int(match.group(1)), "hours": float(match.group(2))}, None, result


def work_bit(inbox):
    if inbox is None:
        return None, ["could not ask inbox"]
    reasons = []
    if inbox["mayor_review"]:
        reasons.append("T1:%d" % inbox["mayor_review"])
    if inbox["fleet_escalated"]:
        reasons.append("T2:%d" % inbox["fleet_escalated"])
    if inbox["findings_untriaged"]:
        reasons.append("T3:%d" % inbox["findings_untriaged"])
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

    depth, error, queue_result = queue_depth()
    if error:
        errors.append(error)
    if depth is not None:
        depth["in_progress"] = sum(1 for row in (rows or []) if (row.get("status") or "") == "in_progress") if rows is not None else 0

    sweeps = {}
    for name, input_rows in (("already-merged.py", None), ("stale-parents.py", rows),
                             ("satisfied-holds.py", None), ("misrouted.py", rows)):
        result, output = run_sweep(name, input_rows)
        sweeps[name] = result
        if result["exit"] == 3:
            errors.append("%s could not ask" % name)

    headings = [line for line in queue_result.stdout.splitlines() if re.match(r"^[A-Z][A-Z /-]+ --", line)]
    health = {
        "fleet_halt": (FLEET_STATE / "HALT").exists(),
        "mayor_halt": (KEEP_STATE / "mayor-halt").exists(),
        "fleet_run_live": run(["pgrep", "-f", "{{FORT_SLUG}}-fleet-run-"]).returncode == 0,
        "disk_free_gb": round(shutil.disk_usage(ROOT).free / (1024 ** 3), 2),
        "ssh_identity": {0: True, 1: False}.get(run(["ssh-add", "-l"]).returncode),
    }
    head = run(["git", "rev-parse", "main"]).stdout.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        head = run(["git", "rev-parse", "HEAD"]).stdout.strip()
        errors.append("main head could not be read")
    exists, reasons = work_bit(inbox)
    record = {"schema": SCHEMA, "written_at": dt.datetime.now(dt.timezone.utc).isoformat(), "head": head,
              "health": health, "inbox": inbox, "depth": depth,
              "queue_lint": {"exit": queue_result.returncode if queue_result.returncode in (0, 1, 3) else 3, "headings": headings},
              "sweeps": sweeps, "work": {"exists": exists, "reasons": reasons}, "errors": errors}
    validate_record(record)
    atomic_write(record)
    print("sweep: wrote %s (work.exists=%s)" % (STATE / "status.json", json.dumps(exists)))


if __name__ == "__main__":
    main()
