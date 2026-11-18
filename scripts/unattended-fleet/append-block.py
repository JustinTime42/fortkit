#!/usr/bin/env python3
"""Append a block of text to a bead description, and PROVE the append.

Same contract and same reason as add-touches.py: `bd update --description`
REPLACES the field and still prints "Updated issue"
(fort/memory/facts/bd-output-invites-false-conclusions.md), so an unverified
write is the cheapest way in this fort to break standing order 12.

This is add-touches.py generalised from one line to an arbitrary block, written
2026-09-18 during the fourth unattended run, because stocking a bead means
folding criteria and an Overseer decision into it, not only a touch set.

  1. refuses if the block's first non-blank line is already present (exit 2,
     no write) -- the idempotence guard, so a re-run after a compaction cannot
     double-append;
  2. writes old + block, never block alone;
  3. READS BACK and asserts the whole original description survived and the
     block arrived. A write it cannot verify is a FAILURE even though bd said OK.

Usage:  append-block.py <bead-id> <file-holding-the-block>
Exit:   0 appended and verified   2 already present   1 failed or unverified
"""
import json
import re
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


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    bid, path = sys.argv[1], sys.argv[2]

    with open(path) as fh:
        block = fh.read().strip("\n")
    if not block.strip():
        print("FAIL %s: block file %s is empty" % (bid, path))
        sys.exit(1)

    marker = next(l.strip() for l in block.splitlines() if l.strip())

    d = bead(bid)
    old = d.get("description") or ""

    if marker in old:
        print("SKIP %s: already carries %r" % (bid, marker[:60]))
        sys.exit(2)

    # A SECOND `Touches:` LINE IS A TRAP, NOT A DUPLICATE (measured 2026-09-19 on
    # ForgeOs-mi7.1). fleet.sh's touch_set_of() breaks on the FIRST match, so a
    # second line is silently ignored: a later hand edits the one they can see and
    # the dispatcher keeps using the other. Refuse, and say which lines collide.
    block_touches = [l.strip() for l in block.splitlines() if re.match(r"\s*Touches:", l)]
    old_touches = [l.strip() for l in old.splitlines() if re.match(r"\s*Touches:", l)]
    if block_touches and old_touches:
        print("FAIL %s: the block carries a Touches: line and the bead already has one; "
              "nothing was written." % bid)
        for l in old_touches:
            print("      on the bead: %s" % l)
        for l in block_touches:
            print("      in the block: %s" % l)
        print("      Use scripts/unattended-fleet/retouch.py to CHANGE the existing line,")
        print("      or drop the Touches: line from the block.")
        sys.exit(1)

    new = old.rstrip() + "\n\n" + block + "\n"

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
    gained = marker in back
    if lost or not gained:
        print("FAIL %s: WRITE NOT VERIFIED — original_present=%s block_present=%s"
              % (bid, not lost, gained))
        print("      stored length %d, expected at least %d" % (len(back), len(old)))
        sys.exit(1)

    print("OK   %s  appended %d chars (%r)" % (bid, len(block), marker[:50]))
    sys.exit(0)


if __name__ == "__main__":
    main()
