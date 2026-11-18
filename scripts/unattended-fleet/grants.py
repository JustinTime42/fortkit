#!/usr/bin/env python3
"""Read, but never modify, the Overseer-owned grant and away records.

Usage:
  grants.py away
  grants.py check <action> <bound>

``check`` prints ``granted`` and exits zero only when the replayed record
authorizes that exact action and bound right now.  Every parse or read failure
answers ``not-granted``.  The records are deliberately not created here: they
belong to the Keep, outside every seat's write reach.
"""
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_STORE = Path.home() / ".local/state/proofdelve-keep"
GRANT_ACTIONS = {
    "push": {"main, fast-forward, push-ready YES at the pushed SHA"},
    "halt-recovery": {"STALL halts only, cause recorded on the run bead"},
    "stock": {"product-first", "findings-only"},
}
# These names must never become an allowlist entry. Checking the request
# explicitly prevents it from being treated as a different-action grant; stray
# records are intentionally ignored (see ForgeOs-initf.4).
NEVER_GRANT_SHAPED = {
    "deploy", "sign", "gate-1-landing", "gate-2-landing",
    "gate-5-landing", "gate-6-landing", "clear-red-main-halt",
}


class RecordError(ValueError):
    pass


def store_dir():
    return Path(os.environ.get("PROOFDELVE_KEEP_DIR", DEFAULT_STORE))


def now():
    value = os.environ.get("GRANTS_NOW")
    if value:
        return parse_time(value, "GRANTS_NOW")
    return datetime.now(timezone.utc)


def parse_time(value, field):
    if not isinstance(value, str):
        raise RecordError("%s is not a timestamp" % field)
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as error:
        raise RecordError("%s is not an ISO timestamp" % field) from error
    if parsed.tzinfo is None:
        raise RecordError("%s has no timezone" % field)
    return parsed.astimezone(timezone.utc)


def read_jsonl(path, validator):
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise RecordError("cannot read %s: %s" % (path.name, error.strerror)) from error
    if not lines:
        raise RecordError("%s is empty" % path.name)
    records = []
    for number, line in enumerate(lines, 1):
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise RecordError("%s line %d is not JSON" % (path.name, number)) from error
        records.append(validator(value, path.name, number))
    return records


def require_object(value, filename, number, fields, optional=()):
    if not isinstance(value, dict):
        raise RecordError("%s line %d is not an object" % (filename, number))
    allowed = set(fields) | set(optional)
    if set(value) - allowed or not set(fields) <= set(value):
        raise RecordError("%s line %d has the wrong fields" % (filename, number))
    return value


def grant_record(value, filename, number):
    value = require_object(value, filename, number,
                           ("ts", "op", "action", "bound", "expires", "by"))
    parse_time(value["ts"], "%s line %d ts" % (filename, number))
    parse_time(value["expires"], "%s line %d expires" % (filename, number))
    if value["op"] not in ("grant", "revoke"):
        raise RecordError("%s line %d has an invalid op" % (filename, number))
    if not all(isinstance(value[field], str) and value[field]
               for field in ("action", "bound", "by")):
        raise RecordError("%s line %d has an invalid string field" % (filename, number))
    return value


def away_record(value, filename, number):
    value = require_object(value, filename, number, ("ts", "state", "by"), ("until",))
    parse_time(value["ts"], "%s line %d ts" % (filename, number))
    if value["state"] not in ("away", "back"):
        raise RecordError("%s line %d has an invalid state" % (filename, number))
    if not isinstance(value["by"], str) or not value["by"]:
        raise RecordError("%s line %d has an invalid by" % (filename, number))
    if "until" in value:
        parse_time(value["until"], "%s line %d until" % (filename, number))
    return value


def away_state():
    try:
        events = read_jsonl(store_dir() / "away.jsonl", away_record)
        return events[-1]["state"], None
    except RecordError as error:
        # Unknown is back: no model is permitted to infer absence as away.
        return "back", str(error)


def check(action, bound):
    if action not in GRANT_ACTIONS:
        if action in NEVER_GRANT_SHAPED or action.startswith("gate-"):
            return False, "action is not grant-shaped"
        return False, "unknown action"
    if bound not in GRANT_ACTIONS[action]:
        return False, "bound is not allowed for action"
    state, away_error = away_state()
    if away_error:
        return False, "away state unknown (%s)" % away_error
    if state != "away":
        return False, "Overseer is back"
    try:
        events = read_jsonl(store_dir() / "grants.jsonl", grant_record)
    except RecordError as error:
        return False, str(error)
    matching = [event for event in events if event["action"] == action]
    if not matching:
        return False, "no grant for action"
    latest = matching[-1]
    if latest["op"] != "grant":
        return False, "latest event is revoke"
    if latest["bound"] != bound:
        return False, "grant bound does not cover request"
    try:
        expires = parse_time(latest["expires"], "expires")
    except RecordError as error:
        return False, str(error)
    if not now() < expires:
        return False, "grant expired"
    return True, "active grant"


def main(argv):
    if argv == ["away"]:
        state, _ = away_state()
        print(state)
        return 0
    if len(argv) == 3 and argv[0] == "check":
        granted, reason = check(argv[1], argv[2])
        print("granted" if granted else "not-granted: %s" % reason)
        return 0 if granted else 1
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
