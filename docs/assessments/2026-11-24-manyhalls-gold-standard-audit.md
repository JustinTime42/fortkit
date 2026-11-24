# Manyhalls against its own specs and constitution: audit of 2026-11-24

Written by the Regent (Calder Sealbroken, session 2026-11-22T135150, model
fable) for bead `fortkit-awlc`, on the Overseer's instruction of 2026-11-23:
"get fortkit/manyhalls up to gold standard and fully tested", so the fort can
be used as an example and for teaching.

## How this was made, and how far to trust it

- Five read-only audit agents each took a group of documents and checked every
  mechanical claim against the tree at `60b6a5e`. They ran no tests and
  launched nothing. Their verdicts come from reading code.
- The Regent spot-checked eight of the most consequential claims against the
  files (marked **checked** below) and measured the mask separately with the
  boundary probe and both smokes the same day.
- Bead states were read from `.beads/issues.jsonl`, not from `bd`.
- Line numbers are as of `60b6a5e` and will drift.

## 1. The headline

1. **The machinery works and is tested.** The verifier is green (288 vitest
   tests, the harness suite), the fleet has landed beads end to end, and as of
   today the boundary probe and both smokes run clean in Manyhalls.
2. **The documents around it are behind.** Of 15 files in `docs/specs/`, none
   is both current and fully implemented. The fleet Manyhalls now runs has no
   specification in this repository at all.
3. **The constitution is mostly true.** 147 mechanical claims in the charter
   and seat files: 103 true, 9 false, 25 held only by prose, 6 stale, 4
   unchecked.
4. **`secrets-only` holds less than the seat files say.** In this posture the
   Forge can write the whole root checkout and the fleet's state; the Workbench
   can write `main`; and several scripts the host runs unmasked are writable by
   masked seats. Secrets, credentials, the constitution's kernel paths and
   other forts stay held.

## 2. What `secrets-only` does and does not hold (measured)

Measured 2026-11-24 by `fort/scripts/probe-boundaries.sh` (exit 0; 82 pass,
49 gap, 0 fail) and by `FORGE_SMOKE` and `WARDEN_SMOKE` from inside live
sessions.

Held in both postures:
- every `.env*` spelling to depth four, the credential directories, the Keep
  and feedback tokens, the ssh agent for the Forge, the user-manager sockets;
- `fort/scripts`, `fort/profiles`, `.claude`, `.git/config`, `.git/hooks`,
  `.beads` hooks, `bin/`, `civ/scripts`, `civ/profiles`, the approval stores;
- for the Forge: the root checkout's `templates/`, `schema/`, `skills/`,
  `civ/`, the charter, the seat files and `scripts/verify-impl.sh`;
- for the Warden: her whole real checkout;
- other registered forts (read-only).

Open in `secrets-only`, by the Overseer's posture decision:
- `/tmp` is the host's and is shared by every seat;
- `$HOME` is writable, so `~/.local/state` (the fleet's HALT file, worker
  records) and `~/.local/share/manyhalls/warden` (review records and the result
  files the fleet gates landings on) are writable from every seat;
- Docker is reachable, and Docker is root;
- the Forge runs with Codex's own sandbox off, so the root checkout itself
  (its `src/`, `scripts/`, `.git/refs/heads`) is writable to it. The Forge
  seat file says it writes "in its own worktree only". That is true in `full`
  and is a rule the Forge keeps, not a wall, here.

Not posture-related, and not written down anywhere before this audit:
- **Host-executed code that masked seats can write** (**checked**). The charter
  says every host-executed script is kernel read-only (`fort/charter.md:130`).
  These are not:
  - `civ/keep/server.mjs` and `civ/keep/lib/`: `civ-keep.service` is a symlink
    into the repository and runs the Keep unmasked; the Keep holds the signing
    token. Writable to the Mayor and the Workbench.
  - `scripts/consolidate-memory.mjs` and `scripts/consolidate-laurels.mjs`:
    `consolidate.timer` runs them unmasked at 03:00 and commits. Writable to
    the Mayor and Workbench, and to the Forge in `secrets-only`.
  - `scripts/digest-hook.sh`: a Stop hook in `.claude/settings.json`, which
    fires in unmasked sessions too.
  - `skills/` reaches `~/.claude/skills` by symlink and is loaded by unmasked
    sessions. (Read-only to the Forge; writable to the Mayor and Workbench by
    the 2026-11-23 decision that user-level skills are writable.)
- **The Workbench is not kept off `main`** in either posture: the root
  checkout is writable to it and its ssh agent is forwarded. "Never main" and
  "never push" are prose.
- **`MAYOR_NO_MASK=1`** launches an unmasked Mayor (`fort/scripts/mayor.sh:38`,
  **checked**). It emits an incident. The charter says the Regent is the only
  seat that changes kernel-read-only machinery.
- **The Warden's push** is held by her profile's deny rule only; her ssh agent
  is forwarded.

## 3. The constitution: what is false or stale

False (9), each needs either the code or the sentence changed:
- `charter.md:130`: every host-executed script is read-only. See above.
- `charter.md:22,91`: the Regent is the only seat that lands kernel-RO changes
  (`MAYOR_NO_MASK`).
- `charter.md:20`: a new secret file is enumerated in both layers. The signing
  token, `~/.azure` and `~/.config/gh` are masked at the kernel and absent from
  `.claude/settings.json` and the Warden profile.
- `charter.md:85`, `forge.md:11`: the Forge writes only in its worktree (false
  in `secrets-only`).
- Standing order 12: archive is "committed and pushed, and only then pruned".
  `scripts/bead-archive.sh` requires a commit, never a push.
- Standing order 14a: never dispatch research agents from a bypass session.
  The Mayor and Workbench always run with skip-permissions; the real control is
  the agent allowlist hook, which the order does not mention.
- `forge.md:17`: the host verifier runs the full gate on the tip. Host verifies
  are tiered; the nightly run is the full one.
- `mayor.md:32`: the heartbeat line is carried in the unattended-run checklist.
  It is not.

Stale (6): `charter.md:95` "no Manyhalls timer was enabled" (the nightly
verify timer has run since 2026-11-20, **checked**); `charter.md:15` on which
gates the machinery cites; standing order 16's line citation; `mayor.md:14`
(the token is masked now); `mayor.md:42` (cites order 17 for a rule it does not
contain); `mayor.md:60` (a `fleet.sh` line number).

Held only by prose (25): the gate-1 and gate-6 "never lands unreviewed" rules
on the Forge lane (the hold works on the `sign-to-land` label; a mislabelled
bead lands on APPROVE), `charter.amended` on every edit, path-scoped staging,
model ladders for the Mayor, and others. This is the fort's design, but the
documents should say which rules are walls and which are rules.

Also: `schema/events.md` says event files are gitignored (they are tracked) and
cites standing order 13 for advisories (it is 17); several live event
categories (`fleet.*`, `loop.heartbeat`, `dispatch.refused`) are not listed.

## 4. The specs, one line each

| Spec | State | What it needs |
|---|---|---|
| `herald-lint.md` | Adopted, built, tested | Six small test and comment gaps |
| `herald-arc.md` | Adopted, built, live | Amend the lock section to match the code (`/tmp` lock, 40 minutes); a lock harness; smoke should fail on a FAIL line |
| `herald.md` | A superseded 2026-08-04 draft; the real law is `civ/law/herald.md` | Mark superseded or retire |
| `civ-keep-export-reader.md` | Built, tested, seen working live | Trimmed drawer prints "Unassigned"; two UI pieces untested; the 60 s timeout fired live on 2026-11-23 |
| `civ-keep-mayor-summary.md` | Built, heavily tested | Live acceptance (`fortkit-t7vz.6`) never recorded; about a dozen spec-versus-code differences; nine open follow-ups |
| `beads-export.md` | Adopted; partly out of date | Two export shapes now conflict (see 5.3); the freshness check never runs in automated verifies |
| `memory.md` | Storage half built and tested; delivery half (section 7) mostly not built | Status line is wrong (approved 2026-08-10); per-seat delivery (`fortkit-88u.6`) is the missing piece |
| `backport-loop.md` | Watcher live, now reporting false drift | The normalizer knows 4 template tokens; the regenerated factory uses 12 (**checked**) |
| `laurels.md` | Storage and rendering live; delivery and lint not built | Roster still has `researcher` and lacks `workbench` (**checked**) |
| `enforcement-vocabulary.md` | Obsolete: governs a register retired on 2026-11-18 | Retire to `fort/annals/` |
| `law.md` | Never built; its problem was partly solved by the re-founding rewrite | Decide: retire, or re-derive |
| `researcher-seat.md` | Obsolete: seat retired | Retire, with its beads and remnants |
| `continuous-fleet.md` | A pointer to Proofdelve's spec, which is itself historical | One line saying Manyhalls now runs the machinery |
| `wwww-founding.md` | Another fort's founding spec, byte-identical to its own copy | Archive or replace with a pointer |
| `unattended-mayor-loop.status.schema.json` | A live contract with no prose spec here | Bring the spec over, or point at it |

Five specs still say "DRAFT, pending approval" on beads that were closed as
approved months ago.

## 5. Defects found along the way

1. **Herald crash check** (`civ/scripts/herald.sh:216`, **checked**): the
   launcher treats any non-empty report file as "this run filed a report". If
   the first rung crashes and writes its stub, a second rung that also dies is
   recorded as a success with `report_filed:true`. A same-day rerun has the
   same blind spot. The second rung has never run.
2. **Herald smoke** greps only for `SMOKE-COMPLETE`, so a probe that prints
   FAIL still exits 0.
3. **Two bead-export shapes.** `scripts/queue-lint.sh` tells seats to refresh
   with `scripts/bead-export.sh`, which writes a slim export; the verifier's
   `beads-export` step compares against a full `bd export`. Following the lint's
   advice turns the verifier red.
4. **The `beads-export` freshness step skips in every worktree**, and the
   branch, post-merge and nightly verifies all run in worktrees, so it only
   fires in a hand run on the root checkout. Its skips read as PASS.
5. **Drift watcher false positives**: 27 drift beads filed on 2026-11-20, 11 of
   them against Manyhalls itself, whose templates are generated from Manyhalls.
6. **Keep run records**: `latest.json` is written before `runs/`; if the second
   write fails the two disagree.
7. **`fort/remember.md` is 0 bytes**; the spec and the other forts have a
   pointer stub.
8. **`fort/systemd/README.md` and two checklists** say no Manyhalls unit is
   installed; one is.
9. **`skills/fort-backport/SKILL.md`** tells a seat to hand-edit `templates/`,
   which are now generated.

## 6. What "gold standard" still needs, in order

A. **Decisions that are the Overseer's** (nothing below is built until he
   rules):
   1. Is `secrets-only` the posture this example fort teaches with, knowing
      section 2? The alternative is `full`, which the probe shows is intact
      (88 pass, 0 fail) and which has not run a fleet here.
   2. Should host-executed code be made read-only to masked seats (the Keep,
      the consolidation scripts, the digest hook)? This is a lib change of a
      few lines plus a harness case.
   3. Should the Workbench be kept off `main` by a wall?
   4. Which specs to retire (section 4 proposes four) and which to finish.

B. **Regent work** (kernel-read-only or civ files):
   1. The Herald crash check and smoke (5.1, 5.2).
   2. The drift watcher's normalizer (5.5), or switch it off for Manyhalls.
   3. Whatever A.2 and A.3 decide.
   4. Batch 3 of `fortkit-awlc`: the reaper (after a dry run), the supervisor,
      the watchdog, each on his word.
   5. A Workbench posture in the boundary probe; the smokes under `full`.

C. **Mayor work** (prose and non-gated code, by bead):
   1. Correct the nine false and six stale constitution sentences (gate 6
      prose: his approval on the bead first).
   2. Write the missing document: what the fleet is and how a bead moves
      through it. For a teaching fort this is the largest gap.
   3. Spec housekeeping: status lines, standing-order numbers, the retirements.
   4. Memory delivery per seat (`fortkit-88u.6`), laurels roster, the export
      shape, `fort/remember.md`.
   5. The backlog: 469 open beads, many describing replaced machinery.

D. **Tests still missing**: a Workbench sitting run for real; a fleet run under
   the supervisor; the Herald launcher's crash paths; the Keep's two untested
   UI pieces; `fortkit-t7vz.6`.
