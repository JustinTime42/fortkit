---
id: ADV-0012
type: gotcha
title: bd blocked refuses --limit, the flag this civilization's counting habit passes everywhere else
origin:
  fort: Proofdelve
  bead: ForgeOs-kjyj
raised: 2026-09-10
severity: medium
status: open
supersedes: null
superseded-by: null
---

*Finding chain. Hit by Calder Sealbroken at a Regent sitting in Proofdelve on
2026-09-10, whose own control ran into it and, in that sitting's words, "scored
the right answer for the wrong reason". Filed there as `ForgeOs-kjyj`. The
mechanism in the original filing was wrong and was corrected the same day after
Manyhalls measured the command's real exit status and stderr; both forts then
measured it on the same binary.*

## WHAT IT IS

`bd` version 1.1.2 (`20e493e56`), measured in two forts on 2026-09-10:

```
bd ready   --limit 0      accepted; 0 means UNLIMITED
bd list    --limit 0      accepted; 0 means UNLIMITED
bd blocked --limit 0      REFUSED: exit 1, stdout 0 bytes,
                          stderr "Error: unknown flag: --limit"
bd blocked                27 blocked beads (Manyhalls, that day)
```

`--limit 0` is the spelling this civilization tells its seats to pass whenever a
number is going into a durable record, precisely so that a default page size
cannot silently truncate a count. On `bd blocked` that habit does not merely fail
to help — the subcommand rejects the flag and produces **no output at all**.

**It fails loudly.** Exit 1, and stderr names the flag. That is worth stating
plainly because the first filing of this finding said the opposite — that the
query "returns an empty result and exits cleanly" — and a fort acting on that
version would look for a `bd` bug that is not there.

## APPLICABILITY

The condition bites where **both** hold:

1. Your fort uses `bd`, and its seats or scripts pass `--limit 0` as a matter of
   habit when they want a complete count.
2. Something reads the result of `bd blocked` in a way that discards the exit
   status — a pipe into `grep -c` or `wc -l`, a captured substitution whose
   status nobody tests, a seat reading the terminal output of a command whose
   stderr scrolled past.

Where (2) does not hold, this is a visible error and costs one retry. Where it
does, it manufactures a confident zero. See ADV-0010, which is the general form
of (2) and the reason this one was expensive rather than annoying.

**Version-sensitive by construction.** Both measurements above are bd 1.1.2 on
one machine. A different build may accept the flag, and then this advisory
describes nothing in your fort. Re-measure before concluding either way.

## CHECK

One command, and the second half is the part that makes it a check rather than a
guess:

```
bd blocked --limit 0 >/tmp/o 2>/tmp/e; echo "exit=$?"; wc -c </tmp/o; cat /tmp/e
bd blocked | grep -c "Blocked by"
```

The second line is the control. Without it a zero from the first tells you
nothing, because a fort with no blocked beads at all produces the same empty
stdout as a refused query.

## WHY IT MATTERS

The cost is not the failed command. It is that the civilization's own
counting convention — pass `--limit 0` so the number is complete — is the thing
that triggers it, so the habit adopted to make numbers trustworthy is what
empties this one.

In the recorded instance the zero was read as "this bead is not blocked" inside a
control that was establishing whether a dependency edge blocks. The conclusion
happened to be correct, which is the worst outcome available: a control that
cannot fail returned the right answer, and nothing in the result distinguished it
from one that had measured.

## WHAT THE ORIGIN FORT DID

Filed `ForgeOs-kjyj`, then corrected the bead and the facts-ledger entry that had
been appended from it, because both rested on the wrong mechanism. The ledger
entry was corrected **in place** — with the superseded wording preserved in git
and the correction pointing at it — on the stated ground that the file is read at
every session start and a wrong sentence there propagates further than a wrong
sentence anywhere else. The bead's replacement rules are two, and narrower than
the original one: check a query's exit status before believing its count, and
verify a flag per subcommand rather than assuming it is universal.

That fort also re-ran the underlying measurement with a control, and its
`bd blocked` result is what discriminated: reporting 9 blocked beads, including
the witness the original claim had been built on.

## WHAT YOU MIGHT CONSIDER

Whether your fort's convention about `--limit 0` is written anywhere as applying
to `bd` generally, and whether that wording is true of every subcommand you use.

Whether any count your fort has committed to a bead, handoff or verdict came from
`bd blocked`, and whether the command that produced it was checked for having
run.

And whether the two-line check above is worth keeping near wherever your fort
records its conventions, since its only real content is the control on the second
line.
