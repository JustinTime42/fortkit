#!/usr/bin/env python3
"""Which fleet-safe beads have ALREADY had their work merged into main?

The failure this catches, measured 2026-09-15 on ForgeOs-7hxc: the Mayor read a
bead as "open, has criteria, no touch set", marked it fleet-safe, and the fleet
spent two Forge launches discovering that the fix was already on main. It then
returned twice ("no product change: handoff only") and escalated.

The tell is free and mechanical: the fleet writes a commit
`<bead-id>: merged by the fleet on <verdict>` when it lands one. A fleet-safe
bead that already has such a commit on main is a bead whose work is done, and
re-dispatching it buys nothing.

A MERGE-PARENT-OPEN verdict is the interesting case: the work merged and the
bead stayed open on purpose, usually for a decision. That is a Mayor question,
not a Forge dispatch.

Reports; changes nothing. Exit 0 clean, 1 findings, 3 could not ask.
"""
import json
import subprocess
import sys


def main():
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True).stdout.strip()
    out = subprocess.run(
        ["bd", "-C", root, "list", "--label-any", "fleet-safe", "--limit", "0", "--json"],
        capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        print("bd would not answer", file=sys.stderr)
        sys.exit(3)
    d = json.loads(out.stdout)
    if isinstance(d, dict):
        d = d.get("data", d)

    findings = []
    for i in d:
        bid = i["id"]
        if (i.get("status") or "") != "open":
            continue
        log = subprocess.run(
            ["git", "-C", root, "log", "main", "--oneline",
             "--grep=^%s: merged by the fleet" % bid.replace(".", r"\.")],
            capture_output=True, text=True).stdout.strip()
        if log:
            findings.append((bid, log.splitlines()[0]))

    if findings:
        print("ALREADY MERGED -- fleet-safe, but the fleet has already landed this work:")
        for bid, line in findings:
            print("  %-22s %s" % (bid, line))
        print()
        print("Each of these is a Mayor question (why is it still open?), not a dispatch.")
        print("already-merged: %d findings" % len(findings))
        sys.exit(1)
    print("already-merged: none of the %d fleet-safe beads has a merge commit on main" % len(d))
    sys.exit(0)


if __name__ == "__main__":
    main()
