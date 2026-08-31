# The control register

Status: v1, fortkit-4ah3.2. Author: Emrith Cairnwright (Mayor), 2026-08-29.
Vocabulary: `docs/specs/enforcement-vocabulary.md` (Overseer-approved 2026-08-29).
Lint that keeps this honest: `scripts/control-lint.mjs` (fortkit-4ah3.3). It
checks every citation against a recorded SHA-256 fingerprint of its cited line.
Fingerprint recording is explicit and single-control:
`node scripts/control-lint.mjs --record <control-key>`. The recorder re-reads
that control's cited line and refuses an unresolved citation; it never bulk
accepts the register's current state.

**WHEN NOT TO REACH FOR `--record`, and this sentence is the whole control.**
Re-recording is for a citation that **legitimately moved** — the implementing
line shifted because the file above it changed, and the citation was updated to
follow it. It is **never** for a citation that went red. A red `control-lint` is
the register telling you a claim no longer matches its subject; re-recording it
makes the claim true by moving the goalposts, and the fort has `fortkit-x1n`
open about a test defanged the same way. **If you did not first establish that
the cited line is still the right line, you are not recording, you are
silencing.** Raised as Warden round-2 finding 3 on `fortkit-4ah3.2`: the
recorder's design already resists this — it is single-control, explicit, refuses
an unresolved citation, and never bulk-accepts the register's current state —
which is why this is one sentence of documentation rather than a hole.

## Corrections to v1 (appended 2026-08-31, not edited in silently)

Warden round 1 on `fortkit-4ah3.2` returned REQUEST-CHANGES. What changed here,
so a reader comparing this file to the 2026-08-29 handoff is not left guessing
which number is wrong:

- **Finding 6 said 27 `falsified-by: null`; the measured value was 26.** Found
  by the Forge while building `control-lint`, not by the author and not by the
  review. It now reads 28, because repairing finding 1(c) moved two Researcher
  fences from a falsifier that cannot run to an honest `null`. The 27 was the
  third miscount this author put into this register's own prose, in a document
  whose argument is against unfalsifiable claims.
- **Five `implements:` citations pointed at the wrong line** (blocking finding
  1). The three charter entries were a constant +36 — measured against one
  rendering and written under another's label. `fort/charter.md` is byte-
  identical since `4a54e92`, so this was authoring error and not drift.
- **`falsifier-researcher-probe` had no implementing artifact at all** and is
  now `status: absent`. The probe exists in the factory only.
- **`status` is now a defined field** with legal values, per finding 2.

**A defect this repair exposed and did not fix:** eight entries cite line `:1`,
and seven of those are a shebang or an opening brace. A shebang never changes,
so `control-lint`'s fingerprint over it can never fire, and the citation names
the FILE rather than the control. Roughly one entry in six is green by
construction. Filed rather than patched, because choosing the right line for
each is authoring work, not a sweep.

## Granularity, which A1 deliberately left open

**A control is a mechanism that can fail independently of its neighbours, and
for which a single falsification question can be posed.**

That rule decides the cases that were ambiguous. The Warden's 37 deny entries
are ONE control, because they fail together and share one question ("does the
tool layer refuse writes?"). The ten verifier stages are TEN, because any one
can break while the others pass. A `--ro-bind` loop is not a control; the set of
paths it binds for a stated purpose is.

Under this rule v1 registered **45 controls** on 2026-08-29 and **46** from
2026-08-31, when `control-lint` was registered alongside the stages it checks. A different rule would give a
different number, and the number is not the point: what the register buys is the
ability to ask which KINDS the fort is short of, and to be told when a citation
stops resolving.

## Fields

- `kind` — one of the eight primitives. `control-lint` fails on an unknown kind.
- `refuses` / `detects` — one line, in the fort's own terms.
- `implements` — `file:line`, READ not recalled. Checked by `control-lint`.
- `falsified-by` — the control key that would go red if this one silently
  stopped working, or `null`. **A null is legal and reported, never failed.**
  A control with no falsifier is a fact about the fort.
- `status` — `active` (this fort runs it today) or `absent` (something
  authoritative claims it and the tree does not have it). Added 2026-08-31 on
  Warden round-1 finding 2: five entries carried `status: active` over bodies
  saying, in capitals, that the control was not built. The machine field and the
  human prose disagreed inside one file, and `status` is the field `control-lint`
  and `rule.fired` will read. **`absent` is not a defect to be cleared. It is the
  register doing its job**, and the four absent tripwires are the charter's four
  named watchers (`fortkit-5v82`).

## What v1 found

Recorded as measurements, each with the command that produced it.

1. **`fort/charter.md:81` names four watchers and none of them exist.** It lists
   push-drift, test-count monotonicity, secrets scan, config checksums. Measured
   by `systemctl --user list-timers --all` on 2026-08-29: the only fortkit-related
   timers are `herald.timer` and `fortkit-drift-watch.timer`, and drift-watch is
   a cross-fort file-drift scanner, not any of the four. The charter's phrasing
   ("added as earned") may have meant these as a plan; a reader cannot tell, and
   that ambiguity in the constitution is the finding.
2. **The nightly consolidation cron does not exist.** `docs/specs/memory.md:61`
   and `:216` both state that a nightly watcher-cron regenerates and commits the
   tracked memory artifacts. Zero such timers exist.
3. **And the view was in fact stale.** Measured, not inferred: `current.md` was
   last committed 2026-08-25 while `facts/` last changed 2026-08-13, and running
   `node scripts/consolidate-memory.mjs .` on 2026-08-29 CHANGED the file. Every
   seat is instructed to read that file at session start and it carries the
   header "Generated ...; do not edit". `docs/specs/memory.md:224` names this
   exact risk, a "stale authoritative-looking" artifact, and it had arrived.
4. **The fort has one governor and no latch of its own.** The only latch it
   relies on is `bd`'s bead lease (`fort/charter.md:83`), which belongs to the
   tracker rather than to Manyhalls.
5. **Two ratchets are made of prose** (`ratchet-append-only-records`,
   `ratchet-event-categories-add-only`): nothing mechanical prevents either
   reversal.
6. **28 of the 45 controls had `falsified-by: null` as of 2026-08-29**, and
   **29 of 46 do as of 2026-08-31** — the register gained its own checker
   (`falsifier-control-lint`, itself unfalsified). Both figures are dated
   because item 6 previously carried none while item 7 did, in the document
   whose argument is against claims outliving their subjects (Warden finding
   9 on `fortkit-4ah3.9`).

   **The unfalsified set includes the entire secret-masking path.**
   `wall-secret-file-mask` states its own uncovered limit
   in `seat-sandbox.sh:140-148`: a directory named `environments~` or `.env.d`
   is not descended into, so secret files inside one are readable in every mask.
   That limit is recorded there and is now registered rather than buried in a
   comment.
7. **The kind tally. Measured 2026-08-29 at 45 controls:** 13 falsifiers,
   11 walls, 6 tripwires, 6 prose gates, 5 fences, 2 ratchets, 1 latch (borrowed),
   1 governor. The fort is rich in refusals and proofs and poor in bounds and
   held states, which is what A1 predicted from the vocabulary alone.
   **Re-measured 2026-08-31 at 46: 14 falsifiers**, the rest unchanged.
8. **`tripwire-constitution-watch` has no script of its own.** The fortkit-9sa
   watch lives inside `civ/scripts/herald.sh`, so the fort's constitutional
   alarm is a passenger on the publication seat and stops when the Herald does.
   `fortkit-dqu5` is its open defect.
