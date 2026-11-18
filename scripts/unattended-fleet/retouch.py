#!/usr/bin/env python3
"""Replace a bead's Touches: line and PROVE the replacement.

Same contract as add-touches.py / append-block.py: bd update --description
REPLACES the field and still prints "Updated issue", so an unverified write is
the cheapest way here to break standing order 12. This one also asserts that
the OLD value is gone, which an append-only helper never has to.
"""
import json, re, subprocess, sys

def desc(bid):
    out = subprocess.run(["bd","show",bid,"--json"],capture_output=True,text=True)
    d = json.loads(out.stdout)
    i = d if isinstance(d,dict) else d[0]
    if isinstance(i,dict) and "data" in i: i = i["data"]
    return i.get("description") or ""

def touches(text):
    for l in text.splitlines():
        m = re.match(r"\s*Touches:\s*(.*?)\s*$", l)
        if m: return m.group(1)
    return None

bid, new, note = sys.argv[1], sys.argv[2], sys.argv[3]
old_desc = desc(bid)
old = touches(old_desc)
if old is None:
    print(f"FAIL {bid}: no Touches line to replace"); sys.exit(1)
if old == new:
    print(f"SKIP {bid}: already '{new}'"); sys.exit(2)
lines = old_desc.splitlines()
out = []
done = False
for l in lines:
    if not done and re.match(r"\s*Touches:\s*(.*?)\s*$", l):
        out.append(f"Touches: {new}")
        out.append("")
        out.append(note)
        done = True
    else:
        out.append(l)
new_desc = "\n".join(out)
subprocess.run(["bd","update",bid,"--description",new_desc],capture_output=True,text=True)
back = desc(bid)
bt = touches(back)
errs = []
if bt != new: errs.append(f"read-back Touches is '{bt}', wanted '{new}'")
# NOT `old in back`: the new value can CONTAIN the old as a prefix substring
# (tests/ForgeOS.Tests -> tests/ForgeOS.Tests/FooTests.cs), which made this
# check fire on four correct writes on 2026-09-19. Count the Touches LINES and
# compare the PARSED value instead.
n_touch = sum(1 for l in back.splitlines() if re.match(r"\s*Touches:", l))
if n_touch != 1: errs.append(f"{n_touch} Touches lines after the write, wanted exactly 1")
if note.splitlines()[0] not in back: errs.append("the note did not arrive")
# every non-Touches line of the original must survive
for l in old_desc.splitlines():
    if re.match(r"\s*Touches:", l): continue
    if l.strip() and l not in back:
        errs.append(f"original line lost: {l[:60]!r}"); break
if errs:
    print(f"FAIL {bid}: " + "; ".join(errs)); sys.exit(1)
print(f"OK   {bid}: '{old}' -> '{new}'")
