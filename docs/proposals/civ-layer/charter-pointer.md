# Charter amendment: point the settlements at the civilization layer

Drafted by the Regent, 2026-08-04, under the edict establishing `civ/`. Applied
by the Overseer's hand: charter files are gate 1 in every settlement, and the
Regent does not apply its own constitutional changes (covenant gate 4).

**One edit, identical in all three settlements.** The section currently titled
`## The Regent, and edicts` exists verbatim in `fort/charter.md` in ForgeOs
(Proofdelve), longburn (Farlantern), and fortkit (Manyhalls), and in
`templates/fort/charter.md` so that every future settlement is founded with it.

## Why the edit is small

The existing section is still true. It tells a fort's seats what an edict is,
that edicts are legitimate and rare, that they are never silent, that a seat is
not expected to defer, and that an unexplained change with no edict event should
be escalated as a security signal. None of that changes.

What changes is only that the Regent no longer lives in a settlement's
hierarchy, and a seat reading its charter should be able to find where it does
live. Two paragraphs are added and one sentence is corrected.

## The edit

**Retitle** the section:

```markdown
## The civilization layer, the Regent, and edicts
```

**Insert** at the top of that section, before the existing first paragraph:

```markdown
Some seats of this civilization are not seats of any settlement. They work across
forts, or above what a fort may do to itself, or point outward at the world, and
they are governed by their own law: `civ/covenant.md`, in the fortkit repository,
which is the civilization's capital. They reside there; they are not ruled by
Manyhalls, and this charter does not bind them. Their seats and access schedules
are in `civ/seats/`, readable by anyone.

What binds them toward this fort is covenant section 4: a civilization seat
acting inside a settlement honours that settlement's human gates, announces
itself in this fort's own event stream at the start and end of its work, never
emits as one of this fort's citizens, and may have its changes reviewed by this
fort's Warden against this fort's standards of evidence. Coming from above is not
an exemption from being wrong.
```

**Correct** the closing sentence of the section, which currently reads:

```markdown
The Regent keeps memory, handoffs and a transcript of every edict, exactly as the
seats here do. Its record is readable, and you may read it.
```

to:

```markdown
The Regent keeps memory, handoffs and a transcript of every edict, exactly as the
seats here do — in `civ/remember.md`, `civ/handoffs/`, and `civ/transcripts/`,
alongside its own seat file and its own record of failures. All of it is readable,
and you may read it.
```

## Also apply to the factory

`templates/fort/charter.md` takes the same edit, so that settlements founded
after today are founded knowing where the civilization layer is. Without that,
the next fort out of `fort-init` gets a charter describing a Regent that lives
nowhere.

## Verification after application (standing order 5)

```bash
for r in /home/justin/dev/ForgeOs /home/justin/dev/longburn /home/justin/dev/fortkit; do
  echo "-- $r"; grep -c "civ/covenant.md" "$r/fort/charter.md"
done
grep -c "civ/covenant.md" /home/justin/dev/fortkit/templates/fort/charter.md
```

Each should print 1. Then the Mayor of each settlement records the verification
on the tracking bead, per standing order 5.
