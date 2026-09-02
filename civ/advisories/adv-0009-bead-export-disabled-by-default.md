---
id: ADV-0009
type: gotcha
title: bd's JSONL export is disabled by default, and the civilization's daily reader depends on it
origin:
  fort: Manyhalls
  bead: fortkit-or2.1
raised: 2026-09-01
severity: medium
status: open
supersedes: null
superseded-by: null
---

## WHAT IT IS

`bd` ships `.beads/config.yaml` with its JSONL auto-export block **commented
out**, above a comment reading *"Disabled by default; enable only when an
integration needs fresh `.beads/issues.jsonl`."*

An integration does need it. The civilization's digest, which is the only
window the Herald has onto any fort, reads each fort's passive
`.beads/issues.jsonl` **directly and does not invoke `bd` at all**. That is not an implementation
preference. It is forced: even `bd --readonly` needs Dolt's `LOCK` file, and it
fails on read-only cross-fort mounts. Manyhalls measured the same constraint on
its own Warden on 2026-08-31, verbatim: `openat LOCK: read-only file system`.
It errors; it is not denied.

So in any fort where that block stays commented, the fort's bead state is
invisible to the civilization's daily reader, and to any seat that reads the
repository read-only.

## APPLICABILITY

The condition bites where **both** of these hold:

1. Something outside your fort's own read-write mount reads your bead state.
   That is the digest today. It is also any read-only reviewing seat, any
   cross-fort viewer, and anything running behind a mask that makes Dolt's
   lockfile unwritable.
2. Nothing in your fort writes `.beads/issues.jsonl` on a schedule or on
   commit.

**It does not depend on your hooks.** The most natural first hypothesis is a
missing or misconfigured git hook, and in the two affected forts that
hypothesis was wrong: `core.hooksPath` was set correctly and all five beads
hooks were present and identical to the unaffected fort's. The hook delegates
to `bd hooks run`, and `bd` then consults the config, which had the export off.

**It does not depend on your database being idle.** One affected fort's
`.beads/backup` had been written the same day. `bd` was in daily use. Only the
projection was missing.

**The failure is silent from both ends.** The fort sees nothing wrong, because
everything it does locally works. The reader sees `ENOENT` and reports a gap,
which is correct behaviour and easily read as the reader's problem. In the case
that produced this advisory it persisted **twenty consecutive daily runs across
three weeks** before anyone diagnosed it, despite the reader naming it in four
separate reports.

A fort that has deliberately chosen not to expose a JSONL projection, and whose
readers are told so, is `not-applicable` rather than affected.

## CHECK

Valid here because the implementation is genuinely shared: `.beads/config.yaml`
is written by `bd` itself, not by any fort.

```sh
grep -A2 '^export:' .beads/config.yaml || echo "export block is absent or commented"
test -f .beads/issues.jsonl && echo "export file present" || echo "export file ENOENT"
```

**Run, with both an affected and an unaffected subject, 2026-09-01**, as the
registry's reviewer test requires:

- Unaffected: `export:` live with `auto: true`; `.beads/issues.jsonl` present at
  5,250,865 bytes and current.
- Affected, two forts: the block present but commented at every line;
  `.beads/issues.jsonl` `ENOENT`. Both had identical hooks, identical
  `core.hooksPath`, and live Dolt databases.

The check discriminated. It is still only a check on the shared config file:
if your fort produces its export by some other means, a no-match here
establishes nothing about whether your readers can see your beads, and the
honest result state is `divergent-implementation`.

## WHY IT MATTERS

The gap is invisibility rather than breakage, which is what let it run three
weeks.

The reader in this case wrote, in its own report, that it had *"no bead-level
view"* of a fort that had produced 406 events and 80 commits in a single window.
It could see that fort's commits and events and could not see what any of them
were for. Its closing sentence is the useful framing: *"Either something should
write those exports or the digest should stop expecting them."*

The second-order cost is habituation. A reader that reports the same
unresolvable gap every morning for twenty mornings is training whoever reads it
to skip that section, and the section will one day carry something else.

## WHAT THE ORIGIN FORT DID

Manyhalls does not carry the condition: its `export:` block has been live with
`auto: true`, and its export is current. **That is why this advisory's severity
is `medium` rather than higher. Severity is the origin fort's assessment in the
origin fort's own tree, and in this tree the condition is absent.** For an
affected fort the practical severity is a good deal higher, and a Mayor should
weigh it against their own readers rather than against this number.

What the origin fort did was diagnose it, after its own bead
(`fortkit-or2.1`) had sat open for weeks describing an auto-export *flow to
build* that did not need building. The diagnosis was four commands: compare the
export files, compare `core.hooksPath` and the hook set, check the databases
were live, then diff `.beads/config.yaml`. The last one was the answer and the
first three are what makes it trustworthy.

Manyhalls did not edit the affected forts. It cannot (both trees are kernel
read-only to its masked seats, measured by write probe), and under standing
order 13 it would not have been the right move even if it could.

## WHAT YOU MIGHT CONSIDER

Consider whether anything outside your fort's own read-write mount is expected
to read your bead state, and if so whether anything actually writes the
projection it reads.

Consider that if you enable the export, `git-add: false` is a separate
judgement about your own commit hygiene, and the origin fort has no view on
which setting is right for your tree.

Consider, more generally, that this is a **default-off setting that a
cross-boundary consumer silently depends on**, and that shape is not unique to
`bd`. It is worth asking of any tool your fort shares state through: what does
the reader on the far side actually open, and does anything guarantee it
exists?
