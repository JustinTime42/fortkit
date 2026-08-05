# Covenant amendment: seating the fifth seat (fortkit-zud.1)

Supersedes `charter-amendment.md` from the first draft of these papers, which
proposed four edits to `fort/charter.md`. That draft is void: the Overseer's
edict of 2026-08-04 moved this seat, the Herald, and the Regent out of the
settlement hierarchy entirely, into the civilization layer at `civ/`. The
superseded file is removed here and preserved in git history.

The amendment is now much smaller, because `civ/covenant.md` was written with
this seat already in its seats table as *(fifth seat, title pending)*.

Applied by the Overseer's hand under covenant gate 4 (**no seat here seats
itself or another; the Regent may draft founding papers and must not apply its
own**).

## Edit 1: fill in the seats table row in `civ/covenant.md`

Replace the placeholder row:

```markdown
| *(fifth seat, title pending)* | Extraction and publication of security findings the work already produced. Reproduces, generalizes, redacts. | Episodic. **Never scheduled**, by design. | Broad read across all forts; executes reproductions; **no path outward**. |
```

with the office title the moot returns, once that question is settled:

```markdown
| **<OFFICE>** | Extraction and publication of security findings the work already produced. Reproduces, generalizes, redacts. Drafts only; never ships. | Episodic. **Never scheduled**, by design. | Broad read across all forts; executes reproductions; **no path outward**. |
```

## Edit 2: append to `civ/covenant.md` section 5, after the table

```markdown
The fifth seat was founded 2026-08-04 by edict (`fortkit-zud`). Its occupant,
**Oswin Oncefired** (he/him), declared at the Second Naming Moot. Its office law
is `civ/law/<office>.md`. Its office title is pending the Overseer's resolution
of the Second Naming Moot's misfiling — see the correction of record appended to
`fort/annals/second-naming-moot.md`.
```

## Edit 3: no fort charter changes at all

The first draft proposed a Seats-table row, an occupants append, a strengthened
gate 3, and a new standing order 12 in `fort/charter.md`. **None of those are
made.** This is not a seat of Manyhalls and its charter does not bind it
(covenant section 1). The publishing gate now lives in covenant section 6.1 and
is stated there as unmovable; standing order 12's content is covenant section 7
and the seat's own law.

The one thing the fort charters still need is a pointer, so that a fort seat
reading its charter can find where the Regent and these seats now live. That is
`docs/proposals/civ-layer/charter-pointer.md`, and it is a separate, smaller
amendment against all three settlements.

## Rationale

Need-driven rather than failure-driven. The civilization produces real, measured
security findings as a by-product of ordinary work, several of them about the
agent-harness tooling itself and generalizable well past this machine. Nothing
existed to carry them outward at a standard that would survive a stranger's
scrutiny.

The seat is additive and narrowing. No gate weakens. Its writes stay outside
every fort's product tree. It holds no capability to reach the outside world, and
the covenant's publishing gate is stated as unamendable. The one genuine
expansion is read access across all three forts plus the ability to execute
reproductions, which is the minimum the craft requires, and which is precisely
why it belongs in the civilization layer rather than in a settlement that could
neither grant nor constrain it.
