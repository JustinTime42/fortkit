#!/usr/bin/env python3
"""Which OPEN beads have had every one of their children closed?

THE FAILURE, measured three times in this fort and twice in one week
(ForgeOs-mfyq, 2026-09-21):

  ForgeOs-sk3c.8   held ForgeOs-sk3c.2.2, the fort's then-highest-priority bead,
                   shut. Its description named three missing things and all
                   three had landed under its own children. The Mayor read the
                   description rather than the routes and planned a dispatch on
                   it. This is the worked example behind capital advisory
                   ADV-0007.
  ForgeOs-sk3c.13  closed 2026-09-19 as already-fixed, found only because its
                   cited lines pointed at unrelated code.
  ForgeOs-sk3c.2   closed 2026-09-21. Both children closed 2026-08-31, every one
                   of its five PROVE items evidenced verbatim in the close
                   reason of ForgeOs-sk3c.2.2 -- and because an open dependency
                   makes a bead invisible to `bd ready`, and the fleet dispatches
                   from `bd ready`, it kept ForgeOs-sk3c.3 (P1, the signup UI)
                   structurally undispatchable for three weeks. Nobody noticed,
                   because a bead that is merely INVISIBLE looks exactly like a
                   bead nobody has got to yet.

WHY A PARENT IS NOT AUTO-CLOSED, and why this reports rather than acts: a parent
may legitimately hold work of its own that no child covers. Beads labelled
`standing` or `record` are intentionally open but are not outstanding work, so
this report excludes those classes. An all-children-closed parent is otherwise a
QUESTION for a person ("is anything of yours left?"), never a verdict.

HIERARCHY IS READ FROM THE ID, not from bd edges, and that is deliberate. This
fort's ids encode the tree (ForgeOs-aqc6.2.4.1 is a child of ForgeOs-aqc6.2.4),
the encoding is what `bd create --parent` produces, and reading it costs zero bd
calls against a board of 1600. The check needs the WHOLE board rather than the
open slice, because "every child closed" is unanswerable without the closed ones.

Reads the full board as JSON on stdin. Reports and never acts. Exit 0 always:
this is a triage queue for the Mayor's backlog sitting, not a gate on dispatch.
"""
import json
import sys


EXCLUDED_LABELS = {"standing", "record"}


def refuse(message):
    print("stale-parents: %s" % message, file=sys.stderr)
    sys.exit(3)


def main():
    for arg in sys.argv[1:]:
        refuse("unknown argument: %s" % arg)
    try:
        board = json.load(sys.stdin)
    except json.JSONDecodeError:
        refuse("stdin did not contain valid board JSON")
    if isinstance(board, dict):
        board = board.get("data", board)
    if not isinstance(board, list):
        refuse("bd returned invalid list for the board")

    beads = {}
    for b in board:
        if not isinstance(b, dict) or "id" not in b:
            refuse("board contained a record with no id")
        beads[b["id"]] = b

    # A closed-or-deferred child is "not outstanding". Deferred is deliberately
    # NOT counted as closed: deferred work is latent work, and a parent whose
    # remaining children are merely deferred still has something outstanding.
    children = {}
    for bid in beads:
        if "." not in bid:
            continue
        parent = bid.rsplit(".", 1)[0]
        if parent in beads:
            children.setdefault(parent, []).append(bid)

    findings = 0
    for pid in sorted(children):
        parent = beads[pid]
        if (parent.get("status") or "").lower() != "open":
            continue
        if EXCLUDED_LABELS.intersection(parent.get("labels") or []):
            continue
        kids = children[pid]
        if not all((beads[k].get("status") or "").lower() == "closed" for k in kids):
            continue
        findings += 1
        print("%s   [P%s]  (%d child(ren), all closed)"
              % (pid, parent.get("priority", "?"), len(kids)))
        print("   %s" % (parent.get("title") or "")[:96])
        print("   last touched %s" % (parent.get("updated_at") or "?")[:10])
        print()

    print("%d open bead(s) whose every child is closed" % findings)
    sys.exit(0)


if __name__ == "__main__":
    main()
