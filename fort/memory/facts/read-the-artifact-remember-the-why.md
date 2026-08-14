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
  source: "Overseer ruling 2026-08-13 in Mayor session B, after four instances of one error class in a single session; diagnosis and counter-hypothesis on fortkit-uj3q"
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
