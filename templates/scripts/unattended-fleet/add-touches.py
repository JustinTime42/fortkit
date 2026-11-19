#!/usr/bin/env python3
"""Append a `Touches:` line to a bead description, and PROVE the append.

`bd update --description` REPLACES the field and still prints "Updated issue"
(fort/memory/facts/bd-output-invites-false-conclusions.md). That is the cheapest
way in this fort to break standing order 12. So this script:

  1. refuses if a `Touches:` line is already present (exit 2, no write);
  2. writes old + new, never new alone;
  3. READS BACK and asserts the entire original description is still present
     and the new line is there. A write it cannot verify is reported as a
     FAILURE even though bd said OK.

Usage:  add-touches.py <bead-id> "<path>, <path>, ..."
Exit:   0 appended and verified   2 already had one   1 failed or unverified
"""
import json
import subprocess
import sys


def bead(bid):
    out = subprocess.run(
        ["bd", "show", bid, "--json"],
        capture_output=True, text=True, check=False,
    )
    if out.returncode != 0 or not out.stdout.strip():
        print("FAIL %s: bd would not answer (%s)" % (bid, out.stderr.strip()[:120]))
        sys.exit(1)
    d = json.loads(out.stdout)
    if isinstance(d, dict) and "data" in d:
        d = d["data"]
    if isinstance(d, list):
        d = d[0]
    return d


def has_touches(desc):
    return any(l.strip().startswith("Touches:") for l in desc.splitlines())


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    bid, touches = sys.argv[1], sys.argv[2].strip()

    d = bead(bid)
    old = d.get("description") or ""

    if has_touches(old):
        print("SKIP %s: already declares a touch set" % bid)
        sys.exit(2)

    new = old.rstrip() + "\n\nTouches: " + touches + "\n"

    r = subprocess.run(
        ["bd", "update", bid, "--description", new],
        capture_output=True, text=True, check=False,
    )
    if r.returncode != 0:
        print("FAIL %s: bd update exit %d: %s" % (bid, r.returncode, r.stderr.strip()[:160]))
        sys.exit(1)

    # bd said OK. That is not evidence. Read it back.
    back = bead(bid).get("description") or ""
    lost = old.rstrip() not in back
    gained = has_touches(back)
    if lost or not gained:
        print("FAIL %s: WRITE NOT VERIFIED — original_present=%s touches_present=%s"
              % (bid, not lost, gained))
        print("      stored length %d, expected at least %d" % (len(back), len(old)))
        sys.exit(1)

    print("OK   %s  Touches: %s" % (bid, touches))
    sys.exit(0)


if __name__ == "__main__":
    main()
