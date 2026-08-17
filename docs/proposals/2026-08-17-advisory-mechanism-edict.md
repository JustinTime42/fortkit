# Edict draft: the advisory mechanism, and one visit to the factory

**Drafted by** Emrith Cairnwright, Mayor of Manyhalls, 2026-08-17.
**For** the Regent, attended, with the Overseer present throughout.
**Bead of record** `fortkit-p5mr.10`. Parent epic `fortkit-p5mr`.

---

## Why this is a Regent sitting at all

Every item below edits `civ/` or `bin/`. Both are kernel read-only to every masked
seat in the capital, the Forge included: `fort/scripts/lib/seat-sandbox.sh` binds
them above the per-seat `case`, so the guard applies to both branches and reaches
the Forge's worktree deliberately. No seat of this fort can do any of this work.
That is the whole reason it is here, and it is worth checking each item against
that list rather than assuming: the seat that should logically do a piece of
fort-machinery work is frequently not the seat that can.

## Standing context, to be read before starting

**Standing order 13 became law in both charters today** (`d912302`, corrected at
`6fdb5f6`), with the Overseer's approval on `fortkit-p5mr.6` and `charter.amended`
emitted twice. Everything below implements it. If any instruction here contradicts
that order, **the order wins and the contradiction is a finding**, not a detail to
smooth over.

The order in one line: adoption is pull and declining is an answer; defects travel
as advisories, which are service bulletins and never instructions; what a fort owes
an advisory is an answer, not compliance.

**What this replaces.** A parity instrument was designed and killed the same day. Its
manifest of declared divergences would have been a claim about the code, and claims
drifting from their subjects is this fort's worst measured failure class. Its second
flaw was an inverted incentive: divergence-as-defect makes the best-adapted fort raise
the loudest alarm. Do not rebuild it under another name.

---

## Item 1 — the advisory registry `fortkit-p5mr.1`

**Tree:** `civ/advisories/` · **Gate:** 1

Create the directory and a README defining the schema in the words a stranger needs.

Frontmatter: `id`, `type` (defect | feature | gotcha), `title`, `origin` (fort + bead
id), `raised`, `severity`, `status` (open | superseded), `supersedes` /
`superseded-by`.

Body sections, all required, in this order:

```
WHAT IT IS
APPLICABILITY            <- mandatory
CHECK (optional)         <- exact command, only where the implementation is shared
WHY IT MATTERS
WHAT THE ORIGIN FORT DID
WHAT YOU MIGHT CONSIDER  <- never an instruction
```

**APPLICABILITY IS MANDATORY AND THE EXACT CHECK IS THE OPTIONAL CONVENIENCE.** This
inverts an earlier draft of this bead and is the Overseer's correction. Forts
implement features their own way, so a literal grep returning nothing in a fort that
built its own version has established *nothing*, and recording that as an all-clear
would make the registry lie. The applicability section states the **failure mode** and
the **conditions** under which it bites, written so a Mayor can judge it against an
implementation the author has never seen.

**Four result states, not three:**

| state | meaning |
|---|---|
| `present` | the condition is here |
| `absent` | checked, **and** this fort carries the shared implementation |
| `divergent-implementation` | this fort does it its own way; an exact check is uninformative |
| `not-applicable` | this fort does not have the thing at all |

`divergent-implementation` is mandatory. Omitting it is what would have made the
mechanism lie.

**Use "service bulletin", not "recall", in the vocabulary.** Aviation draws exactly the
distinction the Overseer drew: an airworthiness directive names a part and mandates
replacement; a service bulletin reports a failure with its conditions and a fix and
leaves applicability to the operator. This registry issues the latter, and the words
should say so on their face.

**Free confirmation worth taking in passing, not as a gate:** the Overseer has stated
that elder Mayors can read the capital's `civ/`. Nobody has run it from the far side.
`cat` a `civ/` file from inside a Proofdelve or Farlantern seat while you are unmasked
and the answer costs nothing.

---

## Item 2 — seed the registry `fortkit-p5mr.5`

**Tree:** `civ/advisories/` · Mayor drafts the text, Regent writes the files

A registry founded empty is one nobody visits. Six advisories from today's findings,
each with its cross-fort result already recorded on its bead:

| type | bead | substance |
|---|---|---|
| defect | `i50s` | `--dangerously-skip-permissions` does **not** bypass deny rules; 3 of 4 `mayor.sh` copies assert it does. **ForgeOs is the unaffected fort, so the negative control is free.** |
| defect | `ypv1` | `Bash(find *)` on the Warden allow list while `rm`/`mv`/`cp`/`chmod`/`ln` are denied. Load-bearing: the charter's `3jv7` residual names that deny set as its sole mitigation. |
| defect | `3539` | `FORT_MASKED` absent from every `researcher.sh`. |
| gotcha | `6xjy` | Deny binds under the flag, but Bash path enforcement is verb-pattern matching: `rm` is refused where a `>` redirect and `find -delete` are not. |
| gotcha | `uj3q` | Claim-subject drift, and the falsification test. |
| feature | `x508` | The seat-file lint. Offered, not pushed. |

**Every seed needs its applicability section written, not just its grep.** All six
looked like exact checks when they were hand-run, and that was an artefact of every
target having a shared origin. Worked examples for the two hardest are on
`fortkit-p5mr.5`.

Two of the six are `gotcha`, and that type earns its place: they are not defects in
any fort and could not be expressed as one. They are things that will cost the next
seat a measurement if nobody wrote them down.

---

## Item 3 — the covenant half `fortkit-p5mr.7`

**Tree:** `civ/covenant.md` · **Gate:** 1

Establish at civilization level: the registry exists and is readable by every fort;
**any fort may raise an advisory** and origin attribution survives transcription; an
advisory never binds a settlement.

**And name the write boundary explicitly**, because it is a consequence of the
isolation this civilization deliberately chose and the next seat will otherwise
rediscover it as a bug: no fort can write into another fort's tree, and `civ/` is
kernel read-only to every masked seat, **so an elder fort cannot file its own
advisory.** It files a bead in its own tracker and says so; the capital's Mayor or the
Regent transcribes. Covenant section 4 already binds civilization seats acting *inside*
a settlement; this is the opposite direction and the covenant has no vocabulary for it.

**Why this is not tidiness.** `fortkit-6fga` exists because standing order 12 lived in
the capital and the template and in *neither* elder fort, so the law governing porting
did not reach the forts being ported to. The same failure is available here. The
covenant is the one document all three settlements are already beneath.

**Take `fortkit-ugr.7` in the same sitting.** It is open, it amends the same file, and
two separate edits to one constitutional document is worse than one.

---

## Item 4 — one visit to `bin/fort-init`, three changes

**Tree:** `bin/` · beads `fortkit-bucl` (+ `fortkit-e69p`), `fortkit-p5mr.2`, `fortkit-byhp`

These are grouped because they touch the same file and it would be wasteful to open it
three times. They are otherwise independent.

**4a. Install `seat-lint` — `fortkit-bucl`, and it must land with `fortkit-e69p`.**
Placement is decided: `templates/scripts/seat-lint.mjs` → `scripts/seat-lint.mjs`,
matching the capital. **Not** `templates/fort/memory/`, which is where the Forge
reasonably guessed from `memory-lint`'s precedent. Strict coupling: the `fort-init`
line without the file is a `cp` of nothing; the file and verifier step without the line
kills every founded fort's verifier. The Regent can write `templates/` as well as
`bin/`, so doing both halves here is simpler than landing one and dispatching the other.

**4b. Install the advisory ledger — `fortkit-p5mr.2`'s factory half.** Standing order 13
now tells every fort to record answers in `fort/advisories.md`. That file does not
exist and the factory does not create it, so a fort founded right now receives a
constitutional instruction to write to a file it does not have.

**4c. Stop swallowing a founding failure — `fortkit-byhp`.** `bin/fort-init:255-260` runs
`node fort/memory/consolidate-memory.mjs` under `||` and downgrades any failure to a
stderr WARNING. **So a fort can be founded exit 0 without its distilled view**, and then
starts every session blind to its own state while founding reports success. That is the
same shape as the `status.sh` defect `fortkit-8t5u` was filed over: an artifact the
factory produces and runs unattended, whose failure nothing goes red for. The cheaper
and better repair is the smoke asserting `fort/memory/current.md` exists and is
non-trivial, which also covers a silent partial write — and that half is Forge lane and
does not need this sitting.

**The standing rule these three illustrate, worth putting in the sitting record:**
`bin/fort-init` **enumerates** its artifacts (`:89-126`); it does not copy trees. Any
bead adding a `templates/` file is incomplete without a paired `fort-init` line, and
that pairing crosses a lane boundary every time. Third occurrence in two days:
`fortkit-naju` (four Researcher templates in zero enumerated lists), `fortkit-bucl`,
and now the ledger.

**Trap for anything that founds a fort:** `fort-init` writes the registry to
`$HOME/.claude/civilization.json`, which is kernel read-only, so founding from a masked
seat fails EROFS. Pass `FORT_REGISTRY` at a writable path
(`seat-sandbox.sh:264-271`).

---

## Gates, records, and close-out

- **Gate 1 items** (`civ/advisories/`, `civ/covenant.md`): the Overseer's approval
  recorded on the relevant bead **before** the edit, not after.
- Emit `edict.begun` and `edict.ended` into this fort's event stream (covenant 4).
- **Do not close these beads in the sitting.** Standing order 9 makes review the gate and
  Ilva will have seen none of it. `fortkit-wg8w.2` got this right and left itself open
  deliberately; do the same.
- **Re-read every `path:line` you cite at the time of writing.** Two of the last three
  sittings produced a citation that had drifted (`fortkit-bjd8`, `fortkit-obva`), and
  today a charter clause was found citing two line numbers that were both comment lines.

## What not to do

- Do not converge any fort toward any other. That is the repealed policy.
- Do not make the advisory check mandatory, or treat a `no match` as an all-clear.
- Do not build a manifest of declared divergences.
- Do not resume Band 3 as written; `fortkit-wg8w` still encodes the rejected model and
  carries a comment saying so.
