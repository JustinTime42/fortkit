#!/usr/bin/env python3
"""Fleet-readiness triage over open beads.

Reads `bd list --status open --limit 0 --json` on stdin and reports, per bead,
what is missing before it could be marked fleet-safe. Reports; never acts.

Columns:
  T  has a `Touches:` line in the description  (absent => claims whole repo)
  A  has acceptance criteria (bd field or an Acceptance heading in the body)
  L  current labels of interest
"""
import json
import re
import sys

GATE_WORDS = re.compile(
    r"\b(auth|authz|authn|oauth|workos|authkit|token|scope|consent|"
    r"permission|role|owner|tenant|org fence|cross-org|visibility|"
    r"migration|deploy|azure|staging|secret)\b",
    re.I,
)

def field(d, *names):
    for n in names:
        v = d.get(n)
        if v:
            return v
    return ""

def main():
    raw = sys.stdin.read().strip()
    if not raw or raw == "null":
        print("no beads")
        return
    d = json.loads(raw)
    if isinstance(d, dict):
        d = d.get("data", d)

    want = set(sys.argv[1:])
    rows = []
    for i in d:
        bid = i["id"]
        if want and not any(bid.startswith(w) for w in want):
            continue
        desc = field(i, "description") or ""
        acc = field(i, "acceptance", "acceptance_criteria") or ""
        labels = i.get("labels") or []
        has_touch = any(l.strip().startswith("Touches:") for l in desc.splitlines())
        has_acc = bool(acc.strip()) or bool(
            re.search(r"^#+\s*acceptance|^\*\*acceptance", desc, re.I | re.M)
        )
        gate_hits = sorted({m.group(0).lower() for m in GATE_WORDS.finditer(
            (i.get("title") or "") + " " + desc[:1200])})
        rows.append({
            "id": bid,
            "p": i.get("priority"),
            "title": (i.get("title") or "")[:78],
            "T": has_touch,
            "A": has_acc,
            "labels": [l for l in labels if l in (
                "fleet-safe", "human", "fleet-escalated", "mayor-review",
                "fleet-return-1", "fleet-return-2")],
            "gate": gate_hits[:4],
            "dlen": len(desc),
        })

    rows.sort(key=lambda r: (r["p"] if r["p"] is not None else 9, r["id"]))
    print("%-22s %-2s %-1s %-1s %-11s %s" % ("ID", "P", "T", "A", "LABELS", "TITLE"))
    for r in rows:
        print("%-22s P%-1s %s %s %-11s %s%s" % (
            r["id"], r["p"],
            "T" if r["T"] else ".",
            "A" if r["A"] else ".",
            ",".join(r["labels"])[:11],
            r["title"],
            ("   [gate? %s]" % " ".join(r["gate"])) if r["gate"] else "",
        ))
    print()
    print("%d beads; %d with Touches, %d with acceptance, %d with both"
          % (len(rows),
             sum(1 for r in rows if r["T"]),
             sum(1 for r in rows if r["A"]),
             sum(1 for r in rows if r["T"] and r["A"])))

if __name__ == "__main__":
    main()
