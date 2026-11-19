#!/usr/bin/env python3
"""Report a Mayor-sized slice of open beads with neither route nor file scope."""
import json
import os
import subprocess
import sys


# Ten is a Mayor afternoon: enough candidates to stock, not another 62-bead read.
SITTING_CAP = 10
ROUTING_LABELS = {
    "mayor-lane", "gate-ready", "regent-docket", "standing", "record", "human",
}


def refuse(message):
    print("unshaped: %s" % message, file=sys.stderr)
    sys.exit(3)


def repository_root():
    root = os.environ.get("ROOT")
    if not root:
        refuse("ROOT is required to validate prose paths")
    root = os.path.abspath(root)
    try:
        git_root = subprocess.run(
            ["git", "-C", root, "rev-parse", "--show-toplevel"],
            check=True, text=True, capture_output=True,
        ).stdout.strip()
        if not os.path.samefile(root, git_root):
            refuse("ROOT is not the git repository root: %s" % root)
    except (OSError, subprocess.CalledProcessError):
        refuse("git refused for ROOT %s; cannot validate prose paths" % root)
    return root


def tracked_paths(root):
    try:
        output = subprocess.run(
            ["git", "-C", root, "ls-files"], check=True, text=True, capture_output=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        refuse("git ls-files refused for ROOT %s; cannot validate file names" % root)
    return set(output.splitlines())


def bead_text(bead):
    fields = ("title", "description", "acceptance_criteria", "design", "notes")
    return "\n".join(value for field in fields if isinstance(
        (value := bead.get(field)), str
    ))


def names_file(text, files):
    """Prose needs an exact path, or a slash-bearing tracked directory prefix."""
    for raw in text.split():
        token = raw.strip("`'\"()[]{}<>,;:!?.")
        if not token:
            continue
        if token in files:
            return True
        if "/" in token:
            prefix = token.rstrip("/") + "/"
            if any(path.startswith(prefix) for path in files):
                return True
    return False


def priority_key(bead):
    try:
        return int(bead.get("priority", 4))
    except (TypeError, ValueError):
        return 4


def has_acceptance(bead):
    return bool((bead.get("acceptance_criteria") or "").strip())


def main():
    if sys.argv[1:]:
        refuse("unknown argument: %s" % sys.argv[1])
    try:
        board = json.load(sys.stdin)
    except json.JSONDecodeError:
        refuse("stdin did not contain valid board JSON")
    if isinstance(board, dict):
        board = board.get("data", board)
    if not isinstance(board, list):
        refuse("bd returned invalid list for the board")

    files = tracked_paths(repository_root())
    findings = []
    epics_excluded = 0
    for bead in board:
        if not isinstance(bead, dict) or not bead.get("id"):
            refuse("board contained a record with no id")
        if (bead.get("status") or "open") != "open":
            continue
        if ROUTING_LABELS.intersection(bead.get("labels") or []):
            continue
        if names_file(bead_text(bead), files):
            continue
        if bead.get("issue_type") == "epic" or bead.get("type") == "epic":
            epics_excluded += 1
            continue
        findings.append(bead)

    findings.sort(key=lambda bead: (priority_key(bead), not has_acceptance(bead), bead["id"]))
    shown = findings[:SITTING_CAP]
    for bead in shown:
        criteria = "criteria" if has_acceptance(bead) else "no criteria"
        print("UNSHAPED %s -- P%d, %s" % (bead["id"], priority_key(bead), criteria))
    suppressed = len(findings) - len(shown)
    print("%d open unrouted bead(s) name no file; %d suppressed by cap %d; %d epics excluded" % (
        len(findings), suppressed, SITTING_CAP, epics_excluded
    ))
    sys.exit(0)


if __name__ == "__main__":
    main()
