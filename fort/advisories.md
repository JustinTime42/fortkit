# Advisories — Manyhalls' answers

This fort's answers to civilization advisories, under standing order 13. Established
2026-08-17 on `fortkit-p5mr.2`, later than it should have been: **both elder forts had
a ledger before the capital did, under a law the capital wrote.**

**An advisory is a service bulletin, never an instruction.** Nothing here records
compliance. It records that this fort looked, what it found, and what it decided.
"Present, and we are not fixing it, because our design makes it moot" is a complete
and good answer. The only failure state is an advisory nobody answered, because that
is indistinguishable from one nobody saw.

**This fort sits on the privileged side of the raising asymmetry.** The registry is in
this repository, so Manyhalls can file directly and no other settlement can. The
second failure state is therefore ours: **the candidate nobody transcribed**, which
from the raising fort's end is indistinguishable from one never raised.

## Result states

| Result | Means |
|---|---|
| `present` | The condition is here. |
| `absent` | Checked, **and** this fort carries the shared implementation. |
| `divergent-implementation` | This fort does it its own way; an exact check is uninformative and a Mayor assessed applicability directly. |
| `not-applicable` | This fort does not have the thing at all. |
| `unresolved` | It is the **advisory's own claim** that is unsettled, not this fort's position. |

A clean exact check in a fort that built its own version is `divergent-implementation`,
never `absent`.

## Answers

Most of these originated here, which is a reason for care rather than for confidence:
the origin fort is the one most likely to record "we already knew" and skip the check.

| Advisory | Checked | Result | Decision | Bead |
|---|---|---|---|---|
| `ADV-0001` bypass flag does not disable deny | 2026-08-17 | **present** | Fixed. Origin fort. `mayor.sh:44` asserted the flag bypasses deny lists; measured false in a live masked session. Proofdelve's wording was the correct one and ours was not. | `fortkit-i50s` |
| `ADV-0002` Warden deny set is verb-incomplete | 2026-08-17 | **present** | Open, and widened by the Regent's seeding from two copies to **four** — every fort and the template. `Bash(find *)` is on the allow list while `rm`/`mv`/`cp`/`chmod`/`ln` are denied. Repair is REGENT lane (`fort/profiles/` is kernel read-only to every seat here). Do not fix by adding `find` to the deny list: that treats the instance and leaves the class. | `fortkit-ypv1` |
| `ADV-0003` `FORT_MASKED` missing from `researcher.sh` | 2026-08-17 | **present** | Open. This fort has the Researcher seat and its launcher sets no mask marker, so the guard covers three seats of four. Live `fort/scripts/` is Regent lane; the template half is Forge. | `fortkit-3539` |
| `ADV-0004` Bash path enforcement is verb-pattern matching | 2026-08-17 | **present** | Accepted as a property of the harness, not a defect to repair here. Measured in this fort: `rm` on a deny-listed path refused, while `>` redirect and `find -delete` reached it. Feeds `ADV-0002`'s class argument. | `fortkit-6xjy` |
| `ADV-0005` claim-subject drift | 2026-08-17 | **present** | Permanent. Six instances by this seat on the day it was raised, every one caught by a control independent of the author and none by care. Treated as a standing condition with controls, not a bug with a fix. | `fortkit-uj3q` |
| `ADV-0006` seat-file lint | 2026-08-17 | **absent** | Origin fort; the lint runs here as verifier step 2 and is now installed into every founded fort. Offered to the elder forts, not pushed. | `fortkit-x508` |
| `ADV-0007` check field briefly mandatory | 2026-08-17 | **present** | Resolved before it cost anything. Raised by Farlantern, transcribed here. SO7 correction appended to `fortkit-p5mr` and the child bead retitled, because a stale title is read before any correction inside a bead. | `fortkit-p5mr` |

## Candidates this fort has raised

Not applicable in the usual sense: this fort files directly. Recorded here so the
column is not mistaken for an empty obligation.

| Candidate | Filed | Transcribed to | Status |
|---|---|---|---|
| _(none — Manyhalls files directly; see the raising asymmetry above)_ | | | |

## Candidates this fort has RECEIVED and owes transcription for

**This is the capital's own failure state and belongs to no one else.**

| From | Their bead | Transcribed to | Status |
|---|---|---|---|
| Farlantern | `longburn-5mnw` | `fortkit-881h` | transcribed, origin attribution intact, closed |
| Farlantern | `longburn-439f` | `ADV-0007` | transcribed 2026-08-17 |
