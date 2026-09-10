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
| `ADV-0008` session close buries the decision queue | 2026-08-31 | **present** | Present, and by a worse route than the origin fort's. Proofdelve's queue (`bd human`) shipped unused; **ours we built ourselves, fill diligently, and never read** — **61 open beads (62 with in-progress) carry `gate-1`**, the fort's own "waiting on the Overseer" signal since 2026-08-08, and nothing surfaces them at end of run. The filing half works; there is no reading half. Second evidence, same day: the Overseer asked two questions, the Mayor answered both, and he had to ask again because the answers were "hidden back in the scroll". `divergent-implementation` was considered and REJECTED: we do have a divergent queue, so the advisory's `bd human` check comes back clean here and proves nothing — but the property it describes holds regardless of which label carries it, and calling that clean is the error SO13 names. **CORRECTION appended 2026-08-31: this row first read "29 open beads". The true figure is 61 open / 62 with in-progress. The 29 was read off a `head -30`-truncated `bd list` — the same mechanism as `fortkit-dqu5`, where the constitution watch read a truncated event list and reported three announced amendments as unannounced. A number taken from a deliberately shortened output, in the row recording that this fort does not read its own queue.** | `fortkit-zj8e` |
| `ADV-0009` bd's JSONL export is disabled by default | 2026-09-01 | **absent** | Absent, and genuinely so: this fort carries the shared implementation (`.beads/config.yaml` is written by `bd`, not by us), and our `export:` block is live with `auto: true`. `absent` rather than `divergent-implementation` is the correct state precisely because the config file is `bd`'s and not ours, so a clean check here discriminates. **This fort is the origin and is not affected**, which is worth stating plainly because an origin fort recording `absent` on its own advisory looks like an error and is not one: the finding was made about the two ELDER forts, where it is `present`. Their answers are theirs to write. Note for a later reader: raising this cost nothing and diagnosing it cost four commands, but it sat undiagnosed for **twenty consecutive Herald runs** while the reader named it in four separate reports. The lesson this fort takes is not about `bd` — it is that a gap reported by an instrument every morning becomes furniture, and ours did. | `fortkit-or2.1` |
| `ADV-0010` a piped command discards its exit status | 2026-09-10 | **present** | Present in both halves, and this seat produced an instance of the second while writing the advisory, which is the honest reason the row does not read `absent`. SCRIPTS: one match in the whole shipped surface, `civ/scripts/check-ceremony-record.sh:118` (`find ... | wc -l`), guarded by `[ -d ... ] || continue` on the line above and feeding an informational EXEMPT report rather than any gate. Not exploitable. SEATS: unmeasurable by grep and demonstrably live — on 2026-09-10 this Mayor probed `bd blocked ... | grep -c` and read the resulting `0` as a measurement; it was not one, and the real answer (27 blocked beads) came only from re-running without the pipe. Decision: no new bead. The class already has a home in `fortkit-uj3q`, and a fifth bead naming the same discipline would be filing rather than fixing. The reviewing habit is the control: when a seat reports a count, ask what the exit status of the thing that produced it was. | `fortkit-uj3q` |
| `ADV-0011` the Warden cannot execute the harnesses her verdict rests on | 2026-09-10 | **present** | Measured here by reading `fort/profiles/warden-settings.json` rather than inferred from the origin fort's case: Ilva Trueglass's allow list carries `fort/scripts/verify.sh`, `bash -n`, `shellcheck`, `npm test` and `npx vitest run`, and NO entry that executes a script under `scripts/`; `defaultMode` is `default`, so an unmatched call becomes a prompt and an unattended review has nobody to answer it. What this fort has NOT yet measured is condition (3) of the advisory's applicability — whether any bead closed here cited an excluded harness as its evidence — and until that is done the row states the shape and not the cost. Four candidate repairs are recorded on the bead and none is chosen; widening the allow list is the obvious answer and it hands a review arbitrary code execution. | `fortkit-karz` |
| `ADV-0012` bd blocked refuses --limit | 2026-09-10 | **present** | The tool condition is present: measured here on bd 1.1.2 (`20e493e56`), `bd blocked --limit 0` exits 1 with 0 bytes on stdout and `Error: unknown flag: --limit` on stderr, while bare `bd blocked` reports 27. Exposure is narrow and was checked rather than assumed: no script in this fort calls `bd blocked` at all (`fort/scripts/status.sh:14` counts blocked beads out of `bd list --status open`), and the one `--limit=0` in our shipped code is `src/readers/beads.ts` against `bd list`, which accepts it. So the risk here is entirely the seat-probe half, which is `ADV-0010`'s row. Decision: no bead; recorded as a tool fact for seats to read. | — |

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
| Proofdelve | `ForgeOs-eng3.4` | `ADV-0008` | **transcribed 2026-08-31, two days late** — raised 2026-08-29 and found only because the Overseer asked directly whether we had picked it up. No watcher, no lint and no digest surfaced it, and the raising fort had no way to distinguish "declined" from "unread". The delay is recorded in the advisory's own preamble. |
| Proofdelve | `ForgeOs-hlwu` / `ForgeOs-kjyj` | `ADV-0010` | transcribed 2026-09-10, **and not through the raising channel** — see the note below |
| Proofdelve | `ForgeOs-g6zb` | `ADV-0011` | transcribed 2026-09-10, same route |
| Proofdelve | `ForgeOs-kjyj` | `ADV-0012` | transcribed 2026-09-10, same route |

**A NOTE ON HOW THOSE THREE ARRIVED, because the mechanism did not do it.** None
of them was raised as an `advisory-candidate` bead and none was named in a
handoff. All three were found by this seat READING Proofdelve's review verdicts,
event streams and commit messages from outside, on the day they happened, while
working alongside that fort on an unrelated programme. That worked, and it is not
a channel: it depends on a Manyhalls Mayor happening to be reading another
settlement's records in real time, which as of 2026-09-10 is a role the Overseer
and this seat have agreed to WIND DOWN in favour of Proofdelve running its own
lane. **So the question this note exists to leave open is who raises Proofdelve's
next candidate when nobody here is watching.** The registry's stated failure state
is the candidate nobody transcribed, indistinguishable from one never raised; the
route that caught these three is about to close, and the raising half has never
been exercised by that fort at all.
