#!/usr/bin/env python3
"""Which OPEN beads are held by a PROSE condition that has since been SATISFIED?

The complement of prose-blockers.py, and a different failure. That script asks
"does this prose gate lack a bd edge, so the fleet will dispatch it anyway?" This
one asks "does this prose gate still hold, or did the thing it waits for already
land, leaving a bead parked for no reason?"

WHY IT EXISTS. `bd blocked` cannot find these: it reports only OPEN dependency
edges, and a hold living in a sentence is not an edge at all. So a bead whose text
says "MUST NOT CLOSE while fortkit-X's debt stands" sits open forever after X
closes, and nothing anywhere goes red.

MEASURED, 2026-09-18, the run that motivated this file: Proofdelve ForgeOs-11tf.8 (retire
McpOAuthFacade) carried exactly that sentence about Proofdelve ForgeOs-11tf.10. 11tf.10 closed
on 2026-09-18 with a close reason stating the debt itself was gone. Every other
precondition 11tf.8 named -- 11tf.7, 11tf.12, 2ibw -- was also closed. SIX further
beads were blocked on 11tf.8 by real bd edges, two of them live bugs. One satisfied
sentence was parking seven beads, and it was found by hand while sweeping
`bd blocked` for something else.

This is this fort's ADV-0007 class ("does any parent state a requirement a child
has since reversed, with nothing saying so?") pointed at hold conditions instead of
at acceptance criteria. Four recorded instances before this file existed.

A PROSE MENTION IS NOT PROOF OF INTENT, so this reports CANDIDATES with the
matched sentence and the named bead's status, for a person to judge. IT NEVER ACTS,
and it never closes, labels or dispatches anything.

Usage:  satisfied-holds.py [--all]
        (default: open beads only; --all includes closed, for auditing)
Exit:   0 no candidates   1 candidates found   3 could not ask bd (a refusal,
        NOT a clean sweep -- the distinction Proofdelve ForgeOs-kjyj is about)
"""
import json
import re
import subprocess
import sys

# Phrases that read as a HOLD on this bead, not a passing reference to another.
# Each was drawn from real bead text in this fort rather than invented.
HOLD = re.compile(
    r"(must not close while|do not close (?:until|while)|stays? open until|"
    r"stays? open on purpose until|blocked on|blocks on|waiting on|"
    r"revisit (?:when|after)|revisit only (?:when|after)|"
    r"not until|hold(?:ing)? for|held for|parked until|"
    r"take (?:it|this) when|dispatch (?:it|this) (?:when|after)|"
    r"once\s+\S*fortkit-\S+\s+(?:lands|has landed|merges|closes)|"
    r"after\s+\S*fortkit-\S+\s+(?:lands|has landed|merges|closes))",
    re.I,
)
# IDS ARE MATCHED AGAINST THE REAL BOARD, NOT AGAINST A GUESSED PATTERN.
#
# The first version of this file used r"fortkit-[A-Za-z0-9][A-Za-z0-9._-]*" and
# found ZERO candidates on a board that contained a known one. The bug: this fort
# writes bead references BOTH ways, and the motivating instance used the bare form
# -- Proofdelve ForgeOs-11tf.8's NOTES say "while 11tf.10's enforcement debt stands", with no
# fortkit- prefix anywhere in the sentence. A prefix-only pattern cannot see it.
#
# Widening the regex to accept bare suffixes would match version numbers, section
# numbers and dotted decimals everywhere. So instead: take the suffix set from the
# board itself and look for those exact tokens. It cannot match a bead that does
# not exist, and it cannot miss a spelling the board actually uses.
BEAD_PREFIXED = re.compile(r"fortkit-([A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9])")


def id_finder(known_suffixes):
    """Return f(sentence) -> set of full bead ids named in it, either spelling."""
    # Longest first, so u65j.3.4 wins over u65j.3 and u65j on the same text.
    ordered = sorted(known_suffixes, key=len, reverse=True)
    # A bare suffix must not be preceded or followed by an id character, or
    # "56d6.1" would also match inside "56d6.10".
    bare = re.compile(
        r"(?<![A-Za-z0-9._-])(" + "|".join(re.escape(s) for s in ordered) + r")(?![A-Za-z0-9._-])"
    ) if ordered else None

    def find(sentence):
        found = set(BEAD_PREFIXED.findall(sentence))
        if bare is not None:
            found |= set(bare.findall(sentence))
        return {"fortkit-" + s for s in found}

    return find


def refuse(message):
    print("satisfied-holds: %s" % message, file=sys.stderr)
    sys.exit(3)


def board():
    """Every bead's fields from ONE bd call, plus the source we actually used.

    `bd export -o -` does NOT write JSONL to stdout on bd 1.1.2 (measured
    2026-09-18: the first line is not JSON), so this used to fall through to the
    list JSON SILENTLY. A checker that quietly changes its own data source is the
    shape this fort keeps writing down -- bd "reports success where it is costliest
    to believe" -- so the source is returned and printed.
    """
    out = subprocess.run(
        ["bd", "list", "--status", "all", "--limit", "0", "--json"],
        capture_output=True, text=True, check=False,
    )
    if out.returncode != 0 or not out.stdout.strip():
        refuse("`bd list --status all --limit 0 --json` would not answer (exit %d): %s"
               % (out.returncode, out.stderr.strip()[:160]))
    d = json.loads(out.stdout)
    if isinstance(d, dict) and "data" in d:
        d = d["data"]
    if not isinstance(d, list) or not d:
        refuse("bd list returned no rows")
    return d, "bd list --status all --json"


def comment_text(bid):
    """Comment BODIES, which no JSON row carries.

    `bd list --json` and `bd show --json` both return `comment_count` and no
    bodies (this fort's Proofdelve ForgeOs-15k.8: "a reader that trusts it sees every bead as
    undecided"). Two of the three real hold sentences measured on 2026-09-18 --
    Proofdelve ForgeOs-4tk's "Revisit when 11tf.9 lands" and Proofdelve ForgeOs-sk3c.4.3's "REVISIT WHEN
    sk3c.4 lands" -- live in COMMENTS, so a description-only sweep misses the
    majority of the class it exists for.
    """
    out = subprocess.run(
        ["bd", "comments", bid],
        capture_output=True, text=True, check=False,
    )
    if out.returncode != 0:
        return None            # reported by the caller, never silently empty
    return out.stdout or ""


def sentences(text):
    for chunk in re.split(r"(?<=[.!?])\s+|\n\n+", text or ""):
        chunk = " ".join(chunk.split())
        if chunk:
            yield chunk


def main():
    include_closed = "--all" in sys.argv[1:]
    skip_comments = "--no-comments" in sys.argv[1:]

    rows, source = board()
    status = {}
    title = {}
    for r in rows:
        bid = r.get("id")
        if bid:
            status[bid] = (r.get("status") or "").lower()
            title[bid] = r.get("title") or ""

    if not status:
        refuse("no bead ids in the board dump")

    suffixes = {b.split("fortkit-", 1)[1] for b in status if b.startswith("fortkit-")}
    names_in = id_finder(suffixes)

    scanned = [r for r in rows
               if include_closed
               or (r.get("status") or "").lower() in ("open", "in_progress")]

    # The comments pass. Only beads that HAVE comments, so the cost is bounded:
    # 55 of 159 open beads on 2026-09-18, 0.18 s each, about ten seconds.
    comments = {}
    unreadable = []
    if not skip_comments:
        with_comments = [r for r in scanned if (r.get("comment_count") or 0) > 0]
        print("satisfied-holds: reading comments on %d of %d beads (source: %s)"
              % (len(with_comments), len(scanned), source), file=sys.stderr)
        for r in with_comments:
            bid = r["id"]
            body = comment_text(bid)
            if body is None:
                unreadable.append(bid)
            else:
                comments[bid] = body

    # Two classes, reported separately, and DEDUPED BY BEAD.
    #
    # The first run of this reported Proofdelve ForgeOs-11tf.8 TWICE -- once from its NOTES and
    # once from the Mayor's own comment quoting those NOTES back. A sweep that
    # reports a bead once per matching sentence inflates its own output the more
    # carefully anyone writes about a finding, which is the wrong incentive.
    #
    # And a hold naming SEVERAL beads where only some have closed is a different,
    # weaker thing: "w4fm.1 + w4fm.10 DONE; tvm1 HELD" on Proofdelve ForgeOs-15k names two
    # closed beads and one open one, and the hold plainly still holds. Mixing that
    # in with a genuinely satisfied hold is how a report stops being read.
    strong = {}   # bid -> (title, [closed], [open], best_sentence)
    weak = {}
    for r in scanned:
        bid = r.get("id")
        if not bid:
            continue

        text = "\n\n".join(filter(None, [
            r.get("description"), r.get("notes"), r.get("design"),
            comments.get(bid),
        ]))
        for sentence in sentences(text):
            if not HOLD.search(sentence):
                continue
            named = [b for b in names_in(sentence) if b != bid]
            closed = [b for b in named if status.get(b) == "closed"]
            if not closed:
                continue
            still = [b for b in named if status.get(b) in ("open", "in_progress")]
            bucket = weak if still else strong
            # Keep the SHORTEST matching sentence: the original hold is almost
            # always terser than later prose quoting it.
            prev = bucket.get(bid)
            if prev is None or len(sentence) < len(prev[3]):
                bucket[bid] = (title.get(bid, ""), closed, still, sentence)

    for bid, (ttl, closed, still, sentence) in sorted(strong.items()):
        print("HOLD-SATISFIED  %-16s %s" % (bid, ttl[:64]))
        for b in closed:
            print("    closed blocker: %-16s %s" % (b, title.get(b, "")[:60]))
        print("    sentence: %s" % sentence[:300])
        print()

    for bid, (ttl, closed, still, sentence) in sorted(weak.items()):
        print("HOLD-PARTIAL    %-16s %s" % (bid, ttl[:64]))
        print("    (the hold names an OPEN bead too, so it probably still holds)")
        for b in closed:
            print("    closed:         %-16s %s" % (b, title.get(b, "")[:60]))
        for b in still:
            print("    STILL OPEN:     %-16s %s" % (b, title.get(b, "")[:60]))
        print("    sentence: %s" % sentence[:300])
        print()

    hits = len(strong)

    if unreadable:
        print("satisfied-holds: %d bead(s) whose comments bd would not return: %s"
              % (len(unreadable), " ".join(unreadable[:8])), file=sys.stderr)
        print("  Those beads were scanned on description/notes/design ONLY.",
              file=sys.stderr)

    coverage = "description+notes+design" if skip_comments else "description+notes+design+comments"

    if hits or weak:
        print("satisfied-holds: %d satisfied, %d partial, over %d beads (%s)."
              % (hits, len(weak), len(scanned), coverage))
        print("  Every row is a JUDGEMENT, not a finding: a sentence may mention a")
        print("  closed bead without being gated on it. HOLD-PARTIAL rows are the")
        print("  weaker class and are usually correct to leave alone.")
        sys.exit(1 if hits else 0)

    print("satisfied-holds: no candidates (%d beads scanned, %s)"
          % (len(scanned), coverage))
    if skip_comments:
        print("  --no-comments was passed, so comment-held beads were NOT checked.")
        print("  Two of the three holds measured 2026-09-18 lived in comments; a")
        print("  clean run in this mode establishes less than it looks like.")
    sys.exit(0)


if __name__ == "__main__":
    main()
