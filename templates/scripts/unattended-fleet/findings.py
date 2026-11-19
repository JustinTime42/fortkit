#!/usr/bin/env python3
"""Print the Findings section of each named triage bead, compactly.

Triage beads carry a whole Warden review verbatim. The Mayor's job is deciding
which findings deserve beads, and that decision is made from the Findings
section, not from the scope read or the criteria walk.
"""
import json
import re
import subprocess
import sys

LIMIT = int(sys.argv[1]) if sys.argv[1].isdigit() else 2200
ids = sys.argv[2:] if sys.argv[1].isdigit() else sys.argv[1:]

for bid in ids:
    out = subprocess.run(["bd", "show", bid, "--json"],
                         capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        print("### %s  (bd would not answer)\n" % bid)
        continue
    d = json.loads(out.stdout)
    if isinstance(d, dict) and "data" in d:
        d = d["data"]
    if isinstance(d, list):
        d = d[0]
    t = d.get("description") or ""
    title = d.get("title") or ""
    m = re.search(r"\*\*Findings?[.:\*]", t)
    body = t[m.start():m.start() + LIMIT] if m else t[-LIMIT:]
    print("#" * 78)
    print("### %s  %s" % (bid, title[:70]))
    print("#" * 78)
    print(body)
    print()
