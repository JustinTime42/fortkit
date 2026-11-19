#!/usr/bin/env python3
"""Report mainline changes which may have invalidated a ready bead's scope.

The caller supplies already-normalised Touches tokens.  Keeping parsing in
queue-lint means this checker cannot quietly diverge from its dispatch lint.
"""
import datetime as dt
import json
import os
import re
import subprocess
import sys

MARKER = re.compile(r"Checked against main ([0-9a-fA-F]{7,40})")


def refuse(message):
    print("stale-criteria: " + message, file=sys.stderr)
    sys.exit(3)


def git(root, *args):
    result = subprocess.run(["git", "-C", root, *args], capture_output=True,
                            text=True, timeout=60)
    if result.returncode:
        refuse("git %s failed: %s" % (args[0], result.stderr.strip()[:160]))
    return result.stdout


def anchors_newest_first(bead):
    text = "\n".join([bead.get("description") or ""] + bead.get("comments", []))
    return reversed(MARKER.findall(text))


def matches(path, touches):
    return any(not touch or path.startswith(touch)
               for touch in touches)


def marker_on_mainline(root, marker, mainline):
    """Resolve a marker without letting bad human text refuse queue-lint."""
    result = subprocess.run(["git", "-C", root, "rev-parse", "--verify", marker + "^{commit}"],
                            capture_output=True, text=True, timeout=60)
    if result.returncode:
        return None
    resolved = result.stdout.strip()
    return resolved if resolved in mainline else None


def main():
    if len(sys.argv) != 2:
        refuse("expected repository root")
    root = sys.argv[1]
    try:
        beads = json.load(sys.stdin)
    except json.JSONDecodeError:
        refuse("stdin did not contain valid bead data")
    if not isinstance(beads, list):
        refuse("bead data was not a list")

    # One mainline walk for every bead, rather than a pathspec call per Touches
    # entry. First-parent retains main's landing history, including merge diffs.
    # Refresh merges are on bead branches, not this line. Every first-parent
    # commit whose subject starts with `<bead-id>:` is skipped below.
    raw = git(root, "log", "main", "--first-parent", "--format=%H%x00%h%x00%ct%x00%s", "--name-only")
    commits, current = [], None
    for line in raw.splitlines():
        fields = line.split("\0")
        if len(fields) == 4:
            if current:
                commits.append(current)
            current = {"sha": fields[0], "short": fields[1], "timestamp": int(fields[2]),
                       "subject": fields[3], "paths": []}
        elif current and line:
            current["paths"].append(line)
    if current:
        commits.append(current)

    mainline = {commit["sha"] for commit in commits}
    findings = []
    for bead in beads:
        touches = bead.get("touches") or []
        if not touches:
            continue
        cutoff_sha = None
        created = None
        for marker in anchors_newest_first(bead):
            resolved = marker_on_mainline(root, marker, mainline)
            if resolved:
                cutoff_sha = resolved
                break
            print("STALE CRITERIA WARNING -- %s has invalid Checked against main %s; falling back." %
                  (bead["id"], marker))
        if cutoff_sha is None:
            try:
                created = dt.datetime.fromisoformat((bead.get("created_at") or "").replace("Z", "+00:00")).timestamp()
            except ValueError:
                continue

        changes = []
        for commit in commits:
            if cutoff_sha and commit["sha"] == cutoff_sha:
                break
            if created is not None and commit["timestamp"] <= created:
                break
            if commit["subject"].startswith(bead["id"] + ":"):
                continue
            if any(matches(path, touches) for path in commit["paths"]):
                changes.append(commit)
        if changes:
            findings.append((len(changes), bead["id"], changes))

    if findings:
        print("STALE CRITERIA -- main has changed declared Touches since this bead was checked:")
        for count, bead_id, changes in sorted(findings, key=lambda item: (-item[0], item[1])):
            sample = "; ".join("%s %s" % (c["short"], c["subject"]) for c in changes[:3])
            print("  %s -- %d commit(s): %s" % (bead_id, count, sample))
        print("  Re-read the bead against main, then add 'Checked against main <sha>'.")
    sys.exit(0)


if __name__ == "__main__":
    main()
