#!/usr/bin/env python3
"""Report open, un-routed beads whose work is exclusively gate-6 work.

The backlog sitting needs a mechanical question, not an automatic lane choice:
if a bead names only paths the Forge cannot write, a Mayor or Regent must decide
where it belongs.  Read the full board as JSON on stdin; print findings only and
exit zero when the board is valid.
"""
import json
import os
import subprocess
import sys


# Routing labels alone answer the routing question. `standing` and `record`
# classify non-work backlog entries, but must not hide a gate-6 routing finding.
ROUTING_LABELS = {"mayor-lane", "regent-docket", "human"}
GATE_PATHS = (
    "fort/scripts/",
    "fort/profiles/",
    "fort/charter.md",
    "fort/seats/",
    ".claude/",
    "scripts/verify-impl.sh",
)

def refuse(message):
    print("misrouted: %s" % message, file=sys.stderr)
    sys.exit(3)


def touches_line(description):
    for line in description.splitlines():
        if line.strip().startswith("Touches:"):
            return line.split("Touches:", 1)[1]
    return None


def repository_root():
    root = os.environ.get("ROOT")
    if not root:
        refuse("ROOT is required to validate Touches paths")
    root = os.path.abspath(root)
    if not os.path.isdir(root):
        refuse("ROOT is not a directory: %s" % root)
    try:
        git_root = subprocess.run(
            ["git", "-C", root, "rev-parse", "--show-toplevel"],
            check=True, text=True, capture_output=True
        ).stdout.strip()
        if not os.path.samefile(root, git_root):
            refuse("ROOT is not the git repository root: %s" % root)
    except (OSError, subprocess.CalledProcessError):
        refuse("git refused for ROOT %s; cannot validate Touches paths" % root)
    return root


def tracked_paths(root):
    try:
        output = subprocess.run(
            ["git", "-C", root, "ls-files"], check=True, text=True, capture_output=True
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        refuse("git ls-files refused for ROOT %s; cannot validate Touches paths" % root)
    return set(output.splitlines())


def path_tokens(touches, files):
    """Return declared Touches tokens that name a tracked path or its prefix."""
    paths = set()
    for raw in touches.split():
        # Bead authors conventionally separate Touches with commas.  This is
        # token punctuation, not path recognition: the resulting token still
        # has to be a tracked file or a prefix of one.
        token = raw.strip("`'\"()[]{}<>,;")
        if not token:
            continue
        prefix = token.rstrip("/") + "/"
        if token in files or any(path.startswith(prefix) for path in files):
            paths.add(token)
    return sorted(paths)


def gate_path(path):
    for protected in GATE_PATHS:
        if path == protected.rstrip("/") or path.startswith(protected):
            return protected
    return None


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

    root = repository_root()
    files = tracked_paths(root)
    findings = []
    for bead in board:
        if not isinstance(bead, dict) or not bead.get("id"):
            refuse("board contained a record with no id")
        if (bead.get("status") or "open") != "open":
            continue
        if ROUTING_LABELS.intersection(bead.get("labels") or []):
            continue

        description = bead.get("description") or ""
        touched = touches_line(description)
        # Touches is the declared source of scope. A bead without it is
        # unshaped, not evidence that prose can be safely classified.
        if touched is None:
            continue
        paths = path_tokens(touched, files)
        if not paths:
            continue
        gates = [gate_path(path) for path in paths]
        if all(gates):
            findings.append((bead["id"], sorted(set(gates))))

    for bead_id, gates in sorted(findings):
        print("MISROUTED %s -- gate-6 only: %s" % (bead_id, ", ".join(gates)))
    print("%d open unrouted gate-6-only bead(s)" % len(findings))
    sys.exit(0)


if __name__ == "__main__":
    main()
