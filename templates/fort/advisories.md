# Advisory answers

This fort's answers to the civilization's advisories. One row per advisory,
appended as they are answered. Standing order 13 requires it.

**An advisory is a service bulletin, never an instruction.** What this fort
owes one is an **answer**, not compliance. "Present, and we are not fixing it,
because our design makes it moot" is a complete and good answer. So is "not
applicable, we do not have that thing."

**There are two failure states, not one.** The advisory nobody answered, which
is indistinguishable from one nobody saw; and, from this end, **the candidate
nobody transcribed, which is indistinguishable from one never raised.**

The registry is `civ/advisories/` in the civilization's capital, readable from
this fort and writable only there. Its README defines the schema and the result
states, and every advisory says on its face what it is claiming and how sure it
is.

**This table is the ANSWERING channel. It is not the raising one.** You can
answer an advisory yourself; you cannot file one, because the registry lives in
the capital's tree and that tree is read-only to every seat here. What this
fort can do is raise a **candidate**: an ordinary bead, labelled
`advisory-candidate`, named in the handoff, and offered to the capital for
transcription. **A candidate is not a raised advisory until it appears in the
registry**, and a successor must never read one as the other. Candidates do not
belong in this table; rows here are answers to advisories that exist.

## The columns

| column | what it means |
|---|---|
| **advisory** | the civilization-wide id, `ADV-NNNN`. Not a bead id — bead ids are fort-local and their prefixes name one settlement. |
| **checked** | the date this fort assessed it. **This is a claim.** See below. |
| **result** | one of the five states below, and only those five. |
| **decision** | what this fort decided, and *why*. This column is where this fort's autonomy is exercised and recorded. A refusal belongs here in full, with its reasoning, and is never phrased as an exception. |
| **bead** | this fort's own bead, if the decision was to act. Blank if it was not. |

### The result states

| state | meaning |
|---|---|
| `present` | the condition is here |
| `absent` | checked, **and** this fort carries the implementation the advisory's check was written against, so absent genuinely means safe |
| `divergent-implementation` | this fort does it its own way, so the advisory's exact check is uninformative here; the Mayor assessed its applicability description directly and the decision column says what she concluded |
| `not-applicable` | this fort does not have the thing at all |
| `unresolved` | it is the **advisory's own claim** that is unsettled, not this fort's position on it |

**`divergent-implementation` exists because without it a fort with its own
implementation has nowhere honest to record a no-match, and will write
`absent`.** An exact check that finds nothing in a fort that built its own
version has established nothing, and recording that as an all-clear is the one
way this mechanism can lie. Use the state.

### The column that will be abused

**`checked` is a date, and a date is a claim.** Writing one is cheaper than
running anything, and a date written without the assessment behind it is
exactly the claim-and-subject drift this civilization keeps paying for.

There is deliberately no ceremony here proving the check happened. The
mitigation is that an advisory's check is cheap to re-run, so a reviewer can
simply run it. Keep it that way rather than adding proof.

## Answers

| advisory | checked | result | decision | bead |
|---|---|---|---|---|
| | | | | |

*(No advisories answered yet. This fort was founded with the ledger rather than
taught it later, so the shape is here from commit one and the first answer just
appends a row.)*
