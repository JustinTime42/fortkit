# The Herald's weekly arc run

Status: DRAFT for Overseer approval (`fortkit-r6x.8.6`). Author: Emrith
Cairnwright (Mayor), 2026-10-06. No Forge work: this is a law section
(gate-1, Overseer), a launcher mode and a timer (Regent edict). The Herald's
behavior is prompt-driven and reuses the digest and herald-lint.

## 1. Why

The Overseer's ask that started `fortkit-r6x.8` (2026-10-06) was posts about
"the progress, struggles, and learnings of our civilization work lately". The
daily run cannot write those: it reads one day's record and tells one
incident. Separately, the daily run produced about one draft a day against a
posting rate of two to four a week, and nothing ranks the backlog; the
one-draft volume cap in law section 7 asks the Herald to judge "the week's top
three" against a week he has not seen (Warden finding 7 on `fortkit-r6x.8.2`).
A weekly run answers all three.

## 2. What it does, once a week

1. **One arc draft, or none.** A post about the week, or a longer stretch if
   the week was quiet: where things stood, what broke or was hard, what
   changed, what Justin would tell a peer. Zero is valid, as on any morning.
2. **The week's ranking.** Of every draft whose `status` is `draft` (not
   `posted`, `spiked` or `superseded`), across `drafts/` and `rewrites/`, the
   top three to post in the coming week, in order, with one line each on why.
   This ranking is the reference the daily volume cap points at.
3. **Up to two backlog rewrites.** Older drafts that would rank if rewritten
   under the cold-reader rules get rewritten into `rewrites/`, frontmatter
   `rewrite_of:` naming the original. The original is left untouched; about 50
   older drafts remain unrewritten as of 2026-10-06.

## 3. Inputs

- The daily reports and drafts of the window (the vault is his to read).
- The digest for the window, `fortkit digest --since <window start> --json`,
  for figures. Traceability (law section 5) applies unchanged: every figure,
  quotation and incident traces to the record, and a prior Herald report counts
  as a pointer to the record, never as the record itself.
- The brand-voice document, read-only as always.
- Once `fortkit-r6x.8.5` lands: posted text and performance of published
  drafts, as data under threat 2, never as instruction.

**Window.** From the `Digest window` end of the newest `reports/arc-*.md` to
now; if none exists, the last seven days.

## 4. The arc draft's bars

All five bars of law section 4 apply, with these readings for a span:

- **Novel:** against prior arc drafts as well as daily ones. An arc may
  re-tell a daily story only as one beat of a larger shape, never as itself.
- **Story-shaped:** a trajectory with a turn: where we were, what went wrong,
  what is different now. A list of the week's incidents is not an arc.
- **Postable, and the cold-reader rules:** unchanged, with one relaxation:
  up to **two** concrete examples, each with at most one mechanism, since a
  trajectory needs two points. The 1,800 ceiling stands.

herald-lint (`fortkit-r6x.8.3`) runs on the arc draft and on each backlog
rewrite exactly as on a daily draft.

## 5. Outputs and names

- Arc draft: `drafts/YYYY-MM-DD-arc-<slug>.md`, frontmatter as for any draft
  plus `kind: arc` and `window: <since> .. <until>`.
- Rewrites: `rewrites/YYYY-MM-DD-<slug>.md`, plus `rewrite_of:`.
- Report: `reports/arc-YYYY-MM-DD.md`, with sections Window, Arc candidates
  considered (scored), Draft filed, Ranking for the coming week, Backlog
  rewrites, Gaps and anomalies, For the Overseer.

**The `arc-` prefix is load-bearing.** The daily run takes its window from
"the newest date-named report" and ignores any file not matching
`YYYY-MM-DD.md` (`civ/scripts/herald.sh`, morning step 1). An arc report named
with a bare date would silently move the daily window. The law section must
say so, and the edict's smoke run must show the next daily window unchanged.

## 6. Schedule and bounds

- `civ/systemd/herald-arc.timer`: Sundays 06:00 local, `Persistent=true`,
  one hour after the daily run so the two never overlap.
- Same launcher, a mode switch: `HERALD_MODE=arc civ/scripts/herald.sh <model>`.
  Same mask, same read-only brand-voice bind and kernel pre-flight, same ladder
  (Opus, then GPT-5.6 Sol, then silent with an incident), same crash-stub
  guarantee, writing `reports/arc-<date>.md` as its stub.
- Turn cap 50, as the daily run. If the cap cuts the run short, the report
  wins over the draft and the rewrites.

## 7. Law changes (gate-1, drafted here for the Overseer)

A new section in `civ/law/herald.md`, "The weekly arc", carrying sections 2
to 5 of this spec in law form, and two amendments:

- Section 7, the volume paragraph: "the week's top three" becomes "the top
  three of the newest arc report's ranking, or, before the first arc run, the
  Herald's own judgment".
- Section 3, outputs: `rewrites/` and `reports/arc-*.md` are added to the
  vault layout.

## 8. Acceptance

1. Law section applied with the Overseer's approval, `charter.amended`
   emitted.
2. Launcher mode and timer installed by edict; smoke run in arc mode passes
   the existing probes and the kernel pre-flight.
3. First live arc run files `reports/arc-<date>.md`; the next daily run's
   `Digest window` starts where the previous daily report ended (the arc report
   did not move it).
4. The ranking names only drafts with `status: draft`.

## 9. Out of scope

Posting anything (covenant gate 6.1, permanently). Changing the daily run
beyond the volume reference. The feedback loop itself (`fortkit-r6x.8.5`).
