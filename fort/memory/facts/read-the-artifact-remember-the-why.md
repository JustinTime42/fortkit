---
key: read-the-artifact-remember-the-why
status: active
superseded-by: null
tier: core
scope:
  seats: [all]
  topics: [memory, evidence, measurement, verification, claims]
  beads: [fortkit-uj3q]
provenance:
  source: "Overseer ruling 2026-08-13 in Mayor session B, after four instances of one error class in a single session; diagnosis and counter-hypothesis on fortkit-uj3q. EXTENDED after Mayor session D produced five more instances in one evening, three of them caught by other seats — see the two comments on fortkit-uj3q dated 2026-08-13."
  declared-by: emrith
  date: 2026-08-13
  origin: trusted
---
MEMORY IS FOR WHAT HAS NO ARTIFACT. Intent, plans, decisions and the WHY behind
them are prose-shaped and belong in the ledger. ANYTHING WITH AN ARTIFACT GETS
READ, NOT REMEMBERED: if your work must interface with code, open that code.
Do not rely on the ledger, a handoff, or your own recollection for a fact you
could check in seconds.

THE ERROR THIS PREVENTS is not "failing to check". It is checking something
ADJACENT to the target and then reporting the adjacent thing as if it were the
target, the proxy having silently lost its label. Measured instances, one
session: `grep -n FORT_MASKED` read as "the guard works" when a `cd` four lines
above killed it first; a byte-range hash read as "this code is intact" when the
file had grown; one fort's diff hunk read as "which forts have this property",
when a diff shows POSITION and not PROPERTY.

SO: when you measure an indicator, name what it is an indicator OF, and say
whether you read the thing or something near it. A claim citing a file and a
line is a testable proposition — re-read it before you write it into a bead, a
handoff or a commit message, because those three are where a wrong sentence
becomes permanent.

BOTH HALVES ARE REQUIRED (Overseer, 2026-08-13): reading the real code where it
applies AND controls that go red when something breaks. They are not
alternatives — a gate that goes red is a FORCED READ, which is why the two
reinforce each other. See [[authoritative-verifier]] and
[[masked-seats-cannot-measure-the-host]], which is this rule's other half:
name whose filesystem a number came from.

## THE CLASS IS WIDER THAN "CHECK THE ARTIFACT" (added after Mayor session D)

Five more instances in one evening. The rule above was in core memory, injected
at session start, and CITED BY NAME in the very comment block that carried two
of them. Knowing the class prevented none. So the framing needed correcting:

THE CLASS IS **A CLAIM AND ITS SUBJECT DRIFTING APART WITH NOTHING NOTICING**,
and it is reached from two directions, not one:
  - MEASURE A PROXY and report it under the target's label (instances 1-4).
  - EDIT THE SUBJECT and leave the claim standing (instance 5 — a scripted
    removal deleted a variable out from under its own seven-line comment).
Both produce a record that reads as true and is not.

FOUR OF THE FIVE INVOLVED RUNNING A COMMAND AND READING ITS OUTPUT. The failure
was never "did not check". It was that THE THING MEASURED COULD NOT HAVE
DISCRIMINATED THE PROPERTY CLAIMED: a diagnostic that fires identically in both
branches being compared; a `bd` ERROR MESSAGE grepped for content and its zero
matches read as "no findings"; `timeout`'s exit 124, which it returns whenever
it fires, read as "the process survived"; `git rev-list origin/main..main`, which
measures THIS CLONE'S LAST SYNC, reported as "commits the remote lacks".

THE CHEAP TEST, and it is cheaper than re-deriving the claim: **WHAT RESULT
WOULD HAVE FALSIFIED THIS?** If no plausible failure of the property would have
changed the number, the number is not evidence. All four measurement instances
fail that question instantly. This is the positive-control discipline the fort
already demands of its probes ([[authoritative-verifier]]; fortkit-vhk.5.1
finding 8), applied to prose claims instead of test suites.

WHAT ACTUALLY CAUGHT THEM, every time, was A CONTROL INDEPENDENT OF THE PERSON
MAKING THE CLAIM: a Warden running commands the author had not (three rounds on
fortkit-8ib), two elder-fort Mayors refusing a premise handed to them as settled
(fortkit-rw86, found twice in two forts on the same evening by seats who had not
seen each other's finding), and twice the author's own second look at a number
that seemed too clean. NEVER care, attention, or knowing the rule.

THE OPERATIONAL CONSEQUENCE FOR THIS SEAT: dispatch the reviewer. A claim you
have not exposed to an independent check is not yet verified, however carefully
you made it — and prose in code is where this fort currently has NO automated
control at all, which is why the Warden is the only thing standing there.
