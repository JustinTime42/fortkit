#!/usr/bin/env python3
"""Which fleet-safe beads declare a blocker in PROSE and carry no bd edge for it?

The failure, measured on Proofdelve ForgeOs-vlyo.1 (the Warden, 2026-09-15): the bead's
description said it was blocked on Proofdelve ForgeOs-vlyo so the fallback message would
exist before the guard hid it. That dependency lived in a sentence, not in bd, so
the fleet dispatched it anyway and one acceptance criterion was unsatisfiable in
the tree it ran against. Her instruction: "if 'blocked on' is meant to gate
dispatch, record it as a bd dependency, not a sentence."

A prose mention is not proof of intent -- plenty of beads mention a sibling in
passing. So this reports CANDIDATES with the matched sentence, for a person to
judge. It never acts.

--expired INVERTS THE QUESTION, and it is the same parse read the other way
(Proofdelve ForgeOs-mfyq, 2026-09-21). The default mode asks "may this dispatch?" and so it
skips a gate whose bead has CLOSED, because a satisfied gate does not block
anything. That skip is correct there and it is exactly why nothing ever noticed
Proofdelve ForgeOs-aqc6.2.4: its criteria said "Deal variant once aqc6.2.3 lands" -- note the
BARE id, with no fortkit- prefix, which is why GATE_EXPIRED below exists --
aqc6.2.3 closed on 2026-09-17, and the deferral silently came due. A P1
(Proofdelve ForgeOs-sk3c.3) sat blocked behind it for weeks.

So --expired reports the branch the default mode `continue`s past: open beads
whose prose defers to a bead that has since CLOSED. Those are not blocked. They
are beads that BECAME WORKABLE, or whose scope changed, while nobody was looking.
It prints the gate's closure date beside the bead's own last-touched date,
because "gate closed after the bead was last read" is the damning shape and
"bead touched since" usually means somebody already looked. It judges neither;
both dates are printed and a person decides. Exit 0 always in this mode: an
expired deferral is a triage queue, never a gate on anything.
"""
import json
import os
import re
import subprocess
import sys

# Phrases that read as a gate rather than a reference.
GATE = re.compile(
    r"(blocked on|blocks on|depends on|after\s+\S*(?:fortkit-|\b\d)\S*\s+lands|"
    r"once\s+\S*fortkit-\S+\s+(?:lands|has landed|merges)|"
    r"must land first|requires?\s+fortkit-\S+\s+to land)",
    re.I,
)
# "This bead must land before fortkit-X" makes X a dependent of this bead;
# it does not say this bead is blocked on X. Capture the complete target span,
# not just its first id, so every comma- or "and"-separated target is checked.
MUST_LAND_BEFORE = re.compile(
    r"must land before\s+(fortkit-[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]"
    r"(?:\s*(?:,|and)\s*fortkit-[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9])*)",
    re.I,
)
# "fortkit-X must land before this bead" is subject-first prose for the same
# dependency direction as a normal gate: this bead cannot land before X.
SUBJECT_FIRST_GATE = re.compile(
    r"fortkit-[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]\s+must land before\s+this bead",
    re.I,
)
# Trailing "." and "-" are sentence punctuation, not part of an id. Without
# this, "Blocked on Proofdelve ForgeOs-vlyo." captures "Proofdelve ForgeOs-vlyo." and never matches
# the real dependency id (measured 2026-09-15, outcome (d) of the harness).
BEAD = re.compile(r"fortkit-[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]")

NONBLOCKING = (
    "tracks", "related", "parent-child", "discovered-from", "until",
    "caused-by", "validates", "relates-to", "supersedes",
)


def refuse(message):
    print("prose-blockers: %s" % message, file=sys.stderr)
    sys.exit(3)


def read_issue(command, subject, *, unknown_is_candidate=False):
    """Read one bd show response and normalize its wrapper/list shape."""
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        # bd 1.1.2 reports an absent id as rc 1, with a JSON error object on
        # stdout. Prefer that structured discriminator. Older bd output has no
        # JSON, so retain its exact stderr line as a narrow compatibility
        # fallback rather than treating every failed lookup as an unknown id.
        try:
            failed_value = json.loads(result.stdout)
        except json.JSONDecodeError:
            failed_value = None
            if (unknown_is_candidate and result.stderr.strip() ==
                    f'Error fetching {subject}: no issue found matching "{subject}"'):
                return None
        if (unknown_is_candidate and isinstance(failed_value, dict)
                and isinstance(failed_value.get("error"), str)
                and failed_value["error"].startswith("no issues found matching")):
            return None
        refuse("bd query failed for %s" % subject)
    if not result.stdout.strip():
        refuse("bd query failed for %s" % subject)
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        refuse("bd returned invalid JSON for %s" % subject)
    if isinstance(value, dict) and "data" in value:
        value = value["data"]
    if isinstance(value, list):
        if not value:
            if unknown_is_candidate:
                return None
            refuse("bd returned no record for %s" % subject)
        value = value[0]
    if not isinstance(value, dict):
        refuse("bd returned invalid record for %s" % subject)
    return value


def expired_main():
    """--expired: the full board on stdin, and NOT ONE bd call.

    Two reasons this reads the board rather than querying per bead. It is the
    whole open set (134 beads = ~47s of `bd show` at 0.35s each, measured
    2026-09-21) where the default mode queries only the handful that matched.
    And a gate named in prose is frequently written WITHOUT the `fortkit-`
    prefix -- Proofdelve ForgeOs-aqc6.2.4's own criterion says "Deal variant once aqc6.2.3
    lands" -- so a bare token has to be resolved against the board to be
    recognised at all. Holding the board makes that a dict lookup, and makes it
    SAFE: a bare token is only ever treated as a bead reference when
    `fortkit-<token>` is a real id, so no regex looseness can invent one.
    """
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

    def is_closed(bid):
        return (beads.get(bid, {}).get("status") or "").lower() in ("closed", "done")

    prefix = beads and next(iter(beads)).split("-", 1)[0] + "-"
    BARE = re.compile(r"\b([a-z0-9]{3,}(?:\.[0-9]+)+)\b", re.I)

    # GATE (shared with the default mode) requires a literal "fortkit-" inside
    # the "once X lands" form, so it does not see a deferral written with a bare
    # id. Proofdelve ForgeOs-aqc6.2.4's criterion is exactly that: "Deal variant once
    # aqc6.2.3 lands". Its harness case failed on the first run and that failure
    # is the reason this exists -- without it the bead is still found, but only
    # through an UNRELATED sentence naming a DIFFERENT bead, which would have
    # let a false claim of coverage stand. GATE itself is left untouched so the
    # dispatch mode stays byte-identical.
    GATE_EXPIRED = re.compile(
        GATE.pattern + r"|(?:once|after|when)\s+[\w.]+\s+(?:lands|has landed|merges|closed|is done)",
        re.I,
    )

    findings = 0
    for bid in sorted(beads):
        b = beads[bid]
        if (b.get("status") or "").lower() != "open":
            continue
        text = "\n".join(
            v if isinstance(v, str) else json.dumps(v)
            for v in (b.get("description"), b.get("acceptance_criteria"), b.get("comments"))
            if v)

        hits = [l.strip()[:150] for l in text.splitlines()
                if GATE_EXPIRED.search(l) and (BEAD.search(l) or BARE.search(l))]
        if not hits:
            continue

        named = set()
        for h in hits:
            for m in BEAD.finditer(h):
                named.add(m.group(0))
            for m in BARE.finditer(h):
                cand = prefix + m.group(1)
                if cand in beads:
                    named.add(cand)
        named.discard(bid)

        gone = sorted((n, (beads[n].get("updated_at") or "?")[:10])
                      for n in named if is_closed(n))
        if not gone:
            continue
        findings += 1
        print("%s   [P%s]  last touched %s"
              % (bid, b.get("priority", "?"), (b.get("updated_at") or "?")[:10]))
        for n, closed_on in gone:
            print("   deferral expired: %s closed %s" % (n, closed_on))
        for h in hits[:2]:
            print("   > %s" % h)
        print()

    # Exit 0 even with findings: an expired deferral is a triage queue for the
    # Mayor's backlog sitting, never a gate on dispatch or on anything else.
    print("%d open bead(s) whose prose defers to a bead that has since CLOSED" % findings)
    sys.exit(0)


def main():
    expired_mode = "--expired" in sys.argv[1:]
    for arg in sys.argv[1:]:
        if arg != "--expired":
            refuse("unknown argument: %s" % arg)
    if expired_mode:
        expired_main()
    root = os.environ.get("ROOT")
    if not root:
        refuse("ROOT is required")
    try:
        d = json.load(sys.stdin)
    except json.JSONDecodeError:
        refuse("stdin did not contain valid fleet-safe JSON")
    if isinstance(d, dict):
        d = d.get("data", d)
    if not isinstance(d, list):
        refuse("bd returned invalid list for fleet-safe list")

    findings = 0
    for i in d:
        if (i.get("status") or "") != "open":
            continue
        bid = i["id"]
        text = (i.get("description") or "") + "\n" + (i.get("acceptance_criteria") or "")

        hits = []
        reverse_hits = []
        for line in text.splitlines():
            if (GATE.search(line) or SUBJECT_FIRST_GATE.search(line)) and BEAD.search(line):
                hits.append(line.strip()[:150])
            if MUST_LAND_BEFORE.search(line):
                reverse_hits.append(line.strip()[:150])
        if not hits and not reverse_hits:
            continue

        # What does bd actually record as blocking?
        s = read_issue(["bd", "-C", root, "show", bid, "--json"], bid)
        blockers = set()
        for dep in (s.get("dependencies") or []):
            dt = (dep.get("dependency_type") or dep.get("type") or "").lower()
            if dt not in NONBLOCKING and (dep.get("status") or "").lower() not in ("closed", "done"):
                blockers.add(dep.get("id"))

        # A mixed line can name both a blocker and reverse dependents. The
        # latter must not be misreported as ordinary gates, so remove each
        # complete "must land before ..." span before collecting gate ids.
        named = {
            m.group(0)
            for h in hits
            for m in BEAD.finditer(MUST_LAND_BEFORE.sub("", h))
        } - {bid}

        # A GATE WHOSE BEAD HAS CLOSED IS SATISFIED, NOT MISSING. Without this the
        # check flags every bead that ever mentioned a now-finished sibling, which
        # is most of them, and a check that cries wolf on satisfied gates gets
        # ignored exactly when it finally matters.
        missing = set()
        for n in named:
            if n in blockers:
                continue
            o = read_issue(["bd", "-C", root, "show", n, "--json"], n,
                           unknown_is_candidate=True)
            if o is None:
                missing.add(n)
                print("%s" % bid)
                print("   UNKNOWN candidate named as a gate: %s" % n)
                continue
            # A GATE WHOSE BEAD HAS CLOSED IS SATISFIED, NOT MISSING, and in
            # THIS mode it is correctly skipped. `--expired` is the other half:
            # it reports exactly this branch, because a deferral that came due
            # unnoticed is its own failure (Proofdelve ForgeOs-mfyq).
            if (o.get("status") or "").lower() in ("closed", "done"):
                continue
            missing.add(n)

        missing_reverse = set()
        for h in reverse_hits:
            for span in MUST_LAND_BEFORE.findall(h):
                for target in BEAD.findall(span):
                    o = read_issue(["bd", "-C", root, "show", target, "--json"], target,
                                   unknown_is_candidate=True)
                    if o is None:
                        missing_reverse.add(target)
                        continue
                    reverse_dependencies = {
                        dep.get("id") for dep in (o.get("dependencies") or [])
                        if (dep.get("dependency_type") or dep.get("type") or "").lower()
                        not in NONBLOCKING
                    }
                    if bid not in reverse_dependencies:
                        missing_reverse.add(target)
        if missing:
            findings += 1
            print("%s" % bid)
            print("   prose names as a gate: %s" % ", ".join(sorted(missing)))
            print("   bd blocking edges:     %s" % (", ".join(sorted(blockers)) or "(none)"))
            for h in hits[:2]:
                print("   > %s" % h)
            print()
        if missing_reverse:
            findings += 1
            print("%s" % bid)
            print("   MISSING REVERSE EDGE: %s should depend on %s" %
                  (", ".join(sorted(missing_reverse)), bid))
            for h in reverse_hits[:2]:
                print("   > %s" % h)
            print()

    print("%d fleet-safe open beads with a prose gate and no matching bd edge" % findings)
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
