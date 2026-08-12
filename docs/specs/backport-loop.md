# The Backport Loop: qualification rubric + drift watcher

Status: DRAFT — pending Overseer approval on fortkit-or2.2.
Author: Emrith Cairnwright (Mayor), 2026-08-10.
Bead: fortkit-or2.2 (parent fortkit-or2). Implementation: or2.3 (watcher,
Forge), or2.4 (install/schedule/first run, gate-1), or2.5 (duplicate-work
triage, consumes §2's rubric).

This spec captures WHAT and WHY. Interfaces (the watcher's report shape, its
test contracts) belong in code under or2.3, constrained by this spec.

## 1. Purpose, and the observed failures that justify it

fort-init is a snapshot that ages. Five backport cycles have already run by
hand (recorded in fortkit-or2's notes), and the /fort-backport skill executes
a cycle mechanically — but nothing DETECTS that a cycle is needed. Standing
order 11 requires observed failures, and there are three:

1. **Convergent duplicate work.** Manyhalls tk9 and Proofdelve 22g solved the
   same class (verify.sh npm-ci bootstrap) in parallel; Manyhalls vn8 and
   Proofdelve agk/uyu solved handoff model-stamping in parallel. Two forts
   paid twice for one lesson because neither could see the other's fix.
2. **Undetected live defect.** The defective emitter class (fortkit-ebm:
   launch scripts emitting as another fort's citizens) was live in two forts
   for over a day with no mechanical detection.
3. **Propagation destroyed a fix** (or2 pipeline lesson, cycle 6): a
   validated fix was overwritten by the sync command meant to spread it, and
   the commit message asserted behaviour the shipped code lacked. Detection
   after propagation cannot be optional.

The loop this spec completes: **watcher detects → bead classifies → Mayor
triages → /fort-backport executes → watcher verifies the propagation stuck.**

## 2. The qualification rubric — what makes a change backport-grade

A change qualifies for propagation (fort → template + sibling forts) only if
all of the following hold:

1. **Proven at origin.** Landed through the originating fort's own gates:
   verifiers green, review passed, merged — and live-verified where the class
   is behavioural (a launcher change is proven by a launch, not by a merge).
2. **Class-generic.** It fixes a class every fort has, not a condition of the
   origin fort. Test: can the receiving fort's incident be described without
   naming the origin fort? Fort-specific values (names, paths, rosters) must
   already be factored behind the normalization layer (§3.2).
3. **Ships with its originating incident.** The propagated bead cites the
   incident or finding that motivated it, so a receiving fort can weigh the
   evidence rather than trust the origin's conclusion.
4. **Ships WITH its component** (the 21f.9 rule, cycle 3): behavioural and
   prose law travels together with the machinery it governs. No fort receives
   a component without the discipline that was learned on it, and no fort
   receives discipline for machinery it does not have.
5. **Baked at origin.** A new convention holds at its origin fort for at
   least one backport cycle before it flows (the gate-labels precedent,
   2026-08-08: adopted at origin, deliberately held). Bug fixes are exempt;
   conventions and process law are not.

**Classification** (applies to every finding, human-decided at triage):

- **backport** — a fort improved on the template. The template learns, and
  the change is offered to sibling forts.
- **upgrade-offer** — the template improved (usually via a prior backport
  from elsewhere). Receiving forts MAY adopt; nothing is ever force-pushed,
  and the receiving fort's own gates and review apply in full. Coming from
  the capital is not an exemption from being wrong (covenant §4 spirit).
- **regression** — a fort silently lost something the template ships
  (the cycle-6 failure class). Highest urgency: this is a fix destroyed or
  a protection dropped, and it files at P1.
- **local-by-design** — recorded divergence a fort chose through its own
  gates. Suppressed from future reports via the allowlist (§3.4), with the
  authorizing bead recorded in the allowlist entry.

## 3. Drift watcher mechanics

### 3.1 Surfaces, per registered fort

The registry is `~/.claude/civilization.json` (fort name, repo path). For
each registered fort, diff against `templates/` in the fortkit repo:

| Fort surface | Template counterpart | Comparison |
|---|---|---|
| `fort/scripts/*.sh`, `fort/scripts/lib/*.sh` | `templates/fort/scripts/` | byte diff after normalization |
| `.claude/settings.json` permission core | `templates/config/settings-permissions.json` | structural: template's deny/allow entries present |
| `fort/charter.md` | `templates/fort/charter.md` | structural: template-shipped standing orders + numbered human-gate lines + threat-model + gate headings present (fingerprint = each order's/gate's first sentence; amended 2026-08-10, fortkit-or2.7 — gate headings alone left a deleted gate invisible, and Warden or2.3 r1/r2 verified gate first-sentences match even amended charters) |
| `fort/seats/*.md` | `templates/fort/seats/` | structural: required protocol headings present |
| `fort/profiles/*` | `templates/fort/profiles/` | byte diff after normalization |

Prose sections a fort amends by design (charter purpose, seat occupants,
history) are outside the compared set. The charter comparison detects LOSS
(a standing order or gate the template ships that a fort no longer carries),
never text mutation — amendment is the charter's normal life.

### 3.2 Normalization

Before any diff, apply a per-fort substitution map derived from the registry
and the fort's roster: fort name, repo path, actor ids. Files differing only
under substitution are NOT drift. The placeholder mechanism itself is
fortkit-8ib's open decision; until it lands, the v1 map is built from the
registry entry plus the charter's occupants line, and 8ib's resolution
supersedes this paragraph.

### 3.3 Output — beads, never edits

The watcher is read-only toward every fort. Its only writes are:

1. **Beads filed in fortkit** (the capital's tracker), one per drifted file
   per fort, carrying: fort, path, direction of newer-ness (mtime + git log
   of both sides), a unified diff excerpt (capped, path-scoped), and a
   suggested classification (§2) — suggestion only; the Mayor classifies at
   triage, the Overseer rules on anything gate-shaped.
2. **One `drift.scan` event** per run in Manyhalls' stream (category added to
   `schema/events.md` in or2.3 — categories are add-only): payload counts
   forts scanned, files compared, findings filed, findings suppressed,
   sources unreadable. (E7, 2026-08-12, add-only: `findingsCommented`,
   `findingsDeferred`, `allowlistLapsed`.)
3. **Comments appended to drift beads already open**, added by E7 — see the
   amendment below. Still never an edit: bead descriptions are written once,
   at filing, and every later observation is an appended comment.

Discipline carried over from the memory work: an unreadable fort, file, or
registry entry is a DISCLOSED gap in the report and the event payload, never
a silent skip; and re-runs must not re-file — each finding carries a stable
fingerprint (fort + path + both content hashes), and an open drift bead with
the same fingerprint suppresses filing. Closed-without-action beads act as
one-shot suppressions; permanent suppression requires an allowlist entry.

**AMENDED 2026-08-12 by edict E7 of fortkit-52vf (bead fortkit-52vf.8),
against an observed failure. The paragraph above stands as the record of what
was specified; this amendment supersedes its identity rule.** "A stable
fingerprint (fort + path + both content hashes)" is not stable — it is stable
against *time* and churns against *content*, and drift IS content changing.
Measured: one Regent edict rewrote templates between two scheduled runs, and
the second run re-filed 16 findings it had already filed, taking the open
drift backlog from 29 beads to 51 (fortkit-zvz2).

The identity of a finding is **(fort, path)** and nothing else. The content
fingerprint survives as a CHANGE DETECTOR on an already-filed finding:

| State | Action |
|---|---|
| open bead with this identity, same fingerprint | suppress |
| open bead with this identity, different fingerprint | **append a comment** to that bead carrying the new fingerprint, reason and diff — never a second bead |
| no open bead, but a closed one carrying this exact fingerprint | suppress once (the one-shot rule above, unchanged) |
| no open bead, and the finding is `not-yet-propagated` | DEFER: disclosed in the report and event payload, no bead (§2 amendment below) |
| otherwise | file |

Appending rather than skipping is the load-bearing half: a file that drifts
FURTHER after its bead is filed would otherwise keep a stale diff on record
with nobody told. It also satisfies standing order 7 natively — the record
grows and nothing is edited in place.

Beads filed from 2026-08-12 carry an explicit `Drift identity: <sha256 of
fort\0path>` line. The 51 beads filed before that date carry their identity
only in their title, which the watcher has always written as
`Drift: <fort> <path>`, and the matcher falls back to it. **Ruled:** a
migration pass rewriting 51 descriptions was rejected as an in-place edit of
records. Disclosed residual — rewording a legacy Drift title during triage
breaks that bead's match and the next run files a fresh one; the window
closes as the legacy beads close.

**Classification amendment (fortkit-or2.8), same edict.** An absent file is
not automatically a `regression`. A regression means a fort LOST something it
had, and the watcher now asks the fort's own git history:

- absent + the path appears in the fort's history → `regression`
- absent + no history under that path → `not-yet-propagated`
- absent + history unreadable → `regression`, and a disclosed gap

`not-yet-propagated` findings are deferred rather than filed when no bead
already tracks them. Their propagation is tracked by fortkit-vhk.7, and for
the capital the state is permanent by design: Manyhalls IS the template
source and its `fort/scripts` is installed by the Overseer's hand, so it will
show absences forever. A watcher that files an unfixable bead every run
trains its fort to ignore it, which is the habituation failure that retired
the ruflo hooks. Defect 2 of or2.8 needs no capital special case: the history
rule covers it.

### 3.4 The allowlist

`civ/drift-allowlist.json` (tracked, reviewed like any change): entries of
(fort, path, content-hash, authorizing bead, date). An entry suppresses
exactly one content state — if the file changes again, the drift resurfaces.
This is how `local-by-design` divergence stays visible-but-quiet without the
watcher going blind to future changes.

**RULING 2026-08-12, edict E7.** The content-hash pin is DELIBERATE and is
KEPT: an allowlist entry must not go on suppressing a file that has changed
into something nobody approved. What was wrong is that the lapse was silent —
a suppression the fort had authorized simply stopped applying, and the
finding returned wearing no explanation. A lapsed entry (same fort and path,
different content-hash) is now REPORTED: in the run report's `lapsed` array,
in the `drift.scan` payload as `allowlistLapsed`, and on stderr where the
journal will carry it. The finding still resurfaces, exactly as before.

## 4. Placement and trigger

- **The script**: `civ/scripts/drift-watch.mjs` — civilization-level
  machinery living in the capital, Node (matching the deterministic-tooling
  precedent of consolidate-memory.mjs; testable under vitest), no model, no
  network. `civ/scripts/` is kernel-read-only to masked seats, which is
  correct: the watcher is enforcement-layer surface.
- **Authoring path**: the Forge authors it in a worktree with tests (or2.3);
  the kernel-RO of `civ/scripts/` applies to the INSTALLED copy at the fort
  root, not to the worktree file the Forge edits on its branch — same shape
  as every reviewed change to that surface. Verify.sh's lint/test cover it;
  ShellCheck is not applicable to .mjs and Biome is.
- **Trigger**: systemd user timer, daily, `Persistent=true` — the Herald H7
  shape. Unit files ship as proposals in `civ/systemd/` and the Overseer
  installs (or2.4, gate-1). The units carry the lessons Warden 88u.5 r2 f11
  recorded: `[Unit] Description`, explicit `Environment=PATH` pinning the
  nvm-installed node, and no commit step — this watcher tracks nothing that
  needs committing (beads and events are its record).
- **Attended fallback**: the script runs identically by hand from an
  unmasked shell; or2.4's first live run is exactly that, before any timer
  is installed.

## 5. What the watcher is NOT

- Not an editor: it never modifies any fort, any template, or any config.
- Not a decider: classification in a filed bead is a suggestion; the rubric
  is applied by the Mayor at triage and gated changes go to the Overseer.
- Not a scheduler of work: it files evidence. /fort-backport remains the
  executor, invoked by a human-approved cycle.
- Not a model: deterministic script, cron-triggered ("crons watch, models
  act" — charter watcher doctrine).

## 6. Acceptance for or2.3 (the implementation bead)

1. Fixture-based tests: a synthetic registry + two fixture forts prove
   detection of each classification input (fort-newer, template-newer,
   template-loss in charter, normalized-identical → no finding), fingerprint
   suppression across two runs, allowlist suppression and its content-hash
   expiry, and unreadable-fort gap disclosure.
2. A dry-run mode (`--dry-run`) prints the report without filing beads or
   emitting events — or2.4's first live run uses it in front of the
   Overseer.
3. `drift.scan` added to `schema/events.md` (add-only).
4. Bead filing is idempotent under concurrent runs (single-instance guard is
   acceptable; the 6ps flock precedent).
5. verify.sh green with the new tests; the spec's §3 tables are the review
   checklist for the Warden.

## 7. Out of scope for v1 (each needs an observed failure to promote)

- Diffing beyond the §3.1 surfaces (docs, viewer code, seat prompts beyond
  headings).
- Automatic classification (the rubric stays human-applied).
- Cross-fort duplicate-WORK detection — that is or2.5's lane, over beads
  rather than files, sharing §2's rubric and the registry sweep.
- Any propagation action from the watcher itself.
