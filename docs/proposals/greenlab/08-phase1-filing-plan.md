# 08: Phase 1 filing plan, as seam-and-fill pairs

Status: REVISED 2026-10-01 after the Overseer settled every open question
(recorded on `fortkit-2y2t.40.7` by the Regent, comments of 20:46, 20:52 and
21:22). Written by the Mayor of Manyhalls (Emrith Cairnwright) at the
Overseer's request, after Phase 0 of spec 07 reported. Nothing here is filed.
**The intended reader is Wren Quicksow, Mayor of Scionhall, on her first day**,
who has none of the conversation behind this and should not need it. She files
Phase 1 in Scionhall's own tracker from this document.

**Read first:** `07-systemic-upgrade.md` (the spec this decomposes, in the
fortkit repo next to this file), Scionhall's charter
(`~/dev/greenlab/forts/scionhall/fort/charter.md`, especially the release rule
and the accepted residual), then the Phase 0 beads named below. Every number
here is quoted from a bead comment or a committed assessment, with the source
given; re-read the source before copying a number into a bead.

## Decided before this revision

- **The package fort is Scionhall**, in the Greenlab civilization, at
  `~/dev/greenlab/forts/scionhall`. **Release v0 is its founding commit
  `a25e99b`**, pinned under the Overseer's founding approval. Its seats come
  from the Greenlab roster: Wren Quicksow (Mayor, she/her), Bex Hardgraft
  (Forge, they/them), Silas Chaffwinnow (Warden, he/him), Cass Brambleway
  (Researcher, they/them).
- **Q1, YES (against both seats' recommendation; the Overseer accepts the
  risk):** Scionhall's fleet may edit launcher and mask-lib SOURCE in its
  package tree. Recorded as an accepted residual in Scionhall's charter. It is
  bounded by the charter's release rules 2 to 4: the fleet edits source only;
  Scionhall's RUNNING machinery stays a pinned signed release, kernel read-only
  to its seats, and its fleet never runs from its own working tree (rule 4);
  nothing reaches any fort except through a signed release (rule 2) and that
  fort's own adoption bead (rule 3). The charter asks a Warden reviewing a
  release to weight launcher and mask changes accordingly.
- **Q2, YES:** Greenlab's factory (`greenlab/templates`, `greenlab/bin/fort-init`)
  is frozen at Scionhall's founding. The package in Scionhall's tree is the
  factory from now on; factory fixes, including `fortkit-2y2t.40.8` (hyphenated
  slugs), are made in Scionhall and released.

## What this plan covers

Spec 07 section 1 (Phase 1, items 1.1 to 1.5) in full, and the parts of
section 2 (Phase 2) that Phase 0 measurements now shape: 2.1 (identity as
data, shaped by 0.1) and 2.2 (mask policy as data, shaped by 0.5). Sections 2.3
(the Gas Town bake-off) and 2.4 (seat templates as a plugin) are not shaped by
any Phase 0 number and are left out. Phase 3 items appear only under "Carried
forward".

## The pattern, as it applies in Scionhall

Spec 07 ("Implementation") splits work into a seam, a fill and a wire, and
made the seam and the wire Regent sittings because in an ordinary fort the
call site sits in a kernel-read-only launcher. **In Scionhall that reason
mostly falls away (Q1):** the launchers and mask lib being changed are package
SOURCE, ordinary files the fleet may edit, while the machinery Scionhall
actually runs is a pinned release the fleet cannot touch. So:

1. **A seam** (interface, call site behind a stub that keeps today's
   behaviour, and the acceptance test) is a **fleet bead** in Scionhall. It is
   still filed and landed BEFORE its fill, as its own bead, so the Warden
   reviews the interface before anything is built against it (spec, then
   interface, then test, then implementation).
2. **A fill** is a fleet bead: a Forge implements the module, the Warden
   reviews, the fleet lands it. The seam's acceptance test is its criterion.
3. **A wire in source** (stub removed, real module called) is a **fleet bead**.
4. **What stays Regent work** is anything needing a host-side or unmasked act:
   installs and systemd units; measurements of the host or of a seat's
   namespace; and **the real-mask proof in plot**, where a candidate package is
   installed into Greenlab's test bench and run in real masks, including the
   host-only `fleet-e2e-harness.sh` and the mask suite. That proof is also
   what release rule 2 requires before the Overseer signs.
5. **What stays the Overseer's:** signing a release, and bumping Scionhall's
   own pin (charter, "Gates, as they apply here").

Labels: fleet beads carry `fleet-safe`, which is the label the dispatcher
selects on (`fleet.sh:1524`, `bd ready --limit 0 --label fleet-safe --json`).
Regent beads carry `act-regent`. A few items are the Mayor's own (a
measurement or a verifier edit) and are marked so.

## Which tree each piece lands in

| Tree | What it is | What lands there |
|---|---|---|
| **Scionhall** (`~/dev/greenlab/forts/scionhall`) | the package fort. Its running machinery is release v0, pinned. Its package SOURCE is ordinary files in its tree | every seam, fill and source wire; every new release |
| **plot** (`~/dev/greenlab/forts/plot`) | Greenlab's test bench. Nobody lives there; its state is disposable (`06-autonomous-operation.md`) | the Regent's real-mask proof of a candidate release before it is signed |
| **The Greenlab capital** (`~/dev/greenlab`) | law, covenant, governor, Effect Gateway. No product work. Its factory is frozen (Q2) | host-side services only: the LiteLLM proxy (1.5) and any telemetry sink (1.4) |

## Phase 0 results, as this plan uses them

| Bead | Result (source: the bead's RESULT comment) | Where it lands below |
|---|---|---|
| `.40.1` | Greenlab's factory is a near-superset of Proofdelve. Over 125 copied files: unchanged by both 80, Proofdelve-only 3, Greenlab-only 32, both disjoint 5, **conflicting 5**, all conflicts in harnesses or lint: `scripts/queue-lint-harness.sh` (4 hunks), `scripts/verify-impl.sh`, `scripts/supervisor-harness.sh`, `scripts/scratch-reaper-harness.sh`, `scripts/queue-lint.sh` (1 each). Identity is a small share of the five-version divergence. Instrument defect `fortkit-egq8` | Pair 0 (version 1), Pair 7 (2.1) |
| `.40.2` | Grep plus a shell is the baseline: search arm 42/42 at ~6.0k tokens and 2.4 tool uses a question; `recall` 34/42 at ~17.4k. The set is grep-answerable by construction | Carried forward (Phase 3). No Phase 1 pair |
| `.40.3` | Reflink is impossible (every `.beads` is btrfs No_COW). A plain copy of Proofdelve's 1.5 G database takes 0.96 s; `bd` serves every read from it identically; writes cannot reach the real database. Live-writer consistency NOT measured and carried as an acceptance criterion | Pair 4 (1.2) |
| `.40.4` | `bd` metadata round-trips, reaches the export, filters on scalar values (not array elements), survives claim/close/reopen. `Touches:` can move into metadata as a JSON array; intersection stays in the adapter. `bd init` writes AGENTS.md, CLAUDE.md, `.claude/`, `.codex/`, `.agents/` into the directory it initialises | Pair 2 (1.3), and every fleet bead's metadata |
| `.40.5` | 67 identical assertions: our capital lib 63/4 (session bus x3, no PID namespace), Proofdelve lib 66/1 (PID namespace), ai-jail 65/2, greywall 63/4. Neither tool expresses per-role postures across several trees. **Our lib stays the substrate; the suite is the portable asset.** Method and adapter: `docs/assessments/2026-09-30-phase0.5-sandbox-eval/` (fortkit repo) | Pair 6 (2.2) |
| `.40.6` | 645 memory items: scar 274, why 211, restates-code 108, record 52. Scar family 8 (`bd` output traps) belongs in the 1.3 adapter; families 2, 3, 7, 9, 10, 12 are one PreToolUse hook (Phase 3.3) | Pair 2's quirk list; the hook is carried forward |

## Facts about the starting tree that shape the pairs

Read on 2026-10-01. Line numbers are in `greenlab/templates/...` (capital at
`fdc8225`, the frozen factory); plot's rendered `warden.sh` (932 lines) and
`fleet.sh` (4,717) share the numbering, and so should Scionhall's v0 copies.
Re-read before citing; they will move once Scionhall edits its source.

- **Scionhall's tree does not yet contain the package source.** At `04593e7`
  it holds the running fort as fort-init rendered it (`fort/`, `scripts/`,
  `schema/`, `tools/`) and no `templates/` or `bin/fort-init`, although the
  founding papers say the package source "starts as Greenlab's factory". Pair
  0 begins by importing it.
- **There is no TypeScript anywhere in Greenlab.** plot's `package.json` is
  plain ESM, `"test": "node --test test/*.test.mjs"`, sources `src/*.mjs`.
  Spec 07 decided TypeScript for new orchestration code, so the toolchain
  (Pair 1) blocks every TypeScript fill.
- **`mask-harness.sh` does not exist in Greenlab.** It lives only in the
  fortkit capital (`scripts/mask-harness.sh`). Greenlab's mask proofs are
  `tools/wall-proof/`, `fort/scripts/probe-boundaries.sh`,
  `probe-forge-masks.sh` and the Warden's smoke probes.
- **Kernel read-only in a running Greenlab fort** (covenant item 6,
  `civ/covenant.md:88-90`; binds in `templates/fort/scripts/lib/seat-sandbox.sh`):
  all of `fort/scripts/` (one bind, :524), `.claude`, `fort/profiles`,
  `.git/config` and hooks (:253), `fort/airlock/operations.json` (:269), and
  seat-dependent `fort/charter.md`, `fort/seats`, `scripts/verify-impl.sh`,
  `skills` (:322, :481). In Scionhall these binds protect the RUNNING copy.
  Whether they also catch the same names under `templates/` is unmeasured; the
  first fleet bead measures it (Pair 0).
- **The fleet reads `Touches:` from description prose** (`touch_set_of`,
  `fleet.sh:1748`; `touch_sets_intersect`, :1808). Scionhall runs v0, so until
  a release carrying Pair 2 is signed AND Scionhall's pin is bumped to it, its
  own fleet can only see prose.
- **Concurrency on the frontier rung** is capped by the governor at
  `GOV_FRONTIER_SESSIONS_MAX=2` (`civ/governors.conf`). Plan for two fleet
  beads in flight at once.

## How each bead carries `Touches:` (from `.40.4`)

**Every fleet bead carries BOTH forms** until Scionhall runs a release whose
fleet reads metadata, because the running fleet parses prose and the adapter
(Pair 2) will read metadata:

```
bd create --type=task --labels=fleet-safe \
  --title="..." \
  --description="...
Touches: core/src/bd/, core/test/bd/" \
  --metadata '{"touches":["core/src/bd/","core/test/bd/"],"lane":"fleet","rung":"frontier","pair":"P2"}'
```

`touches` is an array, so `bd` cannot filter on it (the adapter intersects).
`lane`, `rung` and `pair` are scalars, so `bd list --metadata-field lane=fleet`
and `bd list --metadata-field pair=P2` work. Regent beads carry
`"lane":"regent"`, the Mayor's own `"lane":"mayor"`.

**Paths.** The package source is proposed to sit at the top of Scionhall's
tree with the factory's own layout (`templates/`, `bin/fort-init`), so every
`templates/...` path below is valid as written, plus `core/` for TypeScript
(`core/src`, `core/test`, `core/schema`, `core/bin`). The import bead (P0-import)
fixes the layout; if it chooses another, substitute it everywhere below.

## The pairs

### Pair 0. Version 1 of the package: import the factory, reconcile Proofdelve (`.40.1`)

- **P0-import (fleet, first bead filed).** Copy the frozen factory
  (`~/dev/greenlab/templates` and `bin/fort-init` at `fdc8225`, readable from
  a Scionhall mask) into Scionhall's tree. Acceptance: a recursive diff against
  the frozen factory is empty; the Forge reports whether it could write
  `templates/fort/scripts/`, `templates/fort/profiles/` and
  `templates/.claude/` (if any is kernel read-only, stop and report: Q1 then
  needs a mask change, which is Regent work). `touches: ["templates/","bin/"]`
- **P0-manifest (Mayor).** Re-run `docs/assessments/2026-09-30-phase0.1-measure.mjs`
  (fortkit repo, read-only) against the imported source and write the list of
  Proofdelve changes to port, one row per file with its class (Proofdelve-only,
  disjoint, conflicting). Do not copy the `.40.1` table, which prints file
  names truncated.
- **Fills (fleet).**
  - P0a: `templates/scripts/queue-lint-harness.sh` (4 conflicting hunks).
  - P0b: the four one-hunk conflicts: `templates/scripts/verify-impl.sh`,
    `supervisor-harness.sh`, `scratch-reaper-harness.sh`, `queue-lint.sh`.
  - P0c: the non-conflicting rows. The disjoint set includes
    `fort/seats/mayor.md`: a seat file mixes architecture and identity, so port
    per hunk and never per file (fortkit charter, standing order 12 by
    content).
  Acceptance for all three: every harness the package ships passes in
  Scionhall's verifier against the source; every manifest row is marked ported
  or declined with a reason.
- **Regent:** the plot proof of the candidate v1, including host-only
  `fleet-e2e-harness.sh`. **Overseer:** signs v1 (release rule 2), and bumps
  Scionhall's pin to it when ready (a separate act).

### Pair 1. The TypeScript toolchain

- **Seam and fill (fleet, one bead).** `core/` layout, `package.json` scripts,
  `tsconfig.json`, the Node version, native type stripping (`node file.ts`,
  the pattern the fortkit capital uses with no bundler), `tsc --noEmit` for
  typecheck, `node --test` for tests, and the thin-CLI convention by which bash
  calls a module (`core/bin/<tool> <verb> --json`). Adds the same steps to the
  package's `templates/scripts/verify-impl.sh` so every fort that adopts the
  release runs them. Acceptance: a deliberately ill-typed canary module turns
  the verifier red and is then removed.
  `touches: ["core/","package.json","tsconfig.json","templates/scripts/verify-impl.sh"]`
- **Mayor:** add the typecheck and test steps to Scionhall's OWN
  `scripts/verify-impl.sh` (Mayor-writable under a prose rule in a Greenlab
  fort, kernel read-only to the Forge), so the fleet's TypeScript is checked at
  every merge rather than only at release. Same canary.
- **Regent:** none.

### Pair 2. One `bd` adapter, with `Touches:` in metadata (spec 1.3, `.40.4`, `.40.6` family 8)

- **Seam (fleet).** Interface `core/src/bd/adapter.ts`: `show(id)`,
  `list(filter)`, `ready(filter)`, `comments(id)`, `mergeSlotExists()`,
  `touches(id): string[]`, `setTouches(id, paths)`, each returning typed
  results or a typed error, never an empty value standing in for a failure.
  Thin CLI `core/bin/bd-adapter`. Call sites in the package's
  `templates/fort/scripts/fleet.sh` behind stubs that still run today's bash:
  `bead_json` (:405), `ready_candidates` (:1524), `touch_set_of` (:1748),
  `merge_slot_exists` (:2947). Acceptance: a quirk suite against real `bd`
  1.1.2 on a throwaway database, one test per quirk, each red against a naive
  implementation first:
  - `--limit` default caps results (the "limit 100" trap);
  - `dependency_type` and `type` swapped between `show --json` and
    `list --json` (`fleet.sh:1452-1459`);
  - `merge-slot check` exits 0 whether or not a slot exists (:559-567);
  - `blocked --limit 0` returns empty;
  - comment bodies absent from `show --json`;
  - `list` hides closed beads by default;
  - `bd init` writes agent files into its directory (`.40.4`), so tests run in
    a scratch directory.
  `touches: ["core/src/bd/adapter.ts","core/bin/bd-adapter","core/test/bd/","templates/fort/scripts/fleet.sh"]`
- **Fills (fleet).**
  - P2a: the adapter implementation behind the seam's interface.
    `touches: ["core/src/bd/","core/test/bd/"]`
  - P2b: `touchSetsIntersect` as a pure function with today's bash semantics
    (prefix overlap), its tests ported from the existing harness cases, and
    `touches(id)` reading metadata first, prose second, saying which it used.
    `touches: ["core/src/bd/touches.ts","core/test/bd/touches.test.ts"]`
  - P2c: the writers. `templates/scripts/unattended-fleet/add-touches.py` and
    `retouch.py` write metadata as well as prose. `prose-blockers.py` stays
    as the lint that pushes prose into real edges (spec 1.3).
    `touches: ["templates/scripts/unattended-fleet/"]`
- **Wire in source (fleet).** P2w: replace the four bash bodies in
  `templates/fort/scripts/fleet.sh` with adapter calls.
  `touches: ["templates/fort/scripts/fleet.sh"]`
- **Regent:** the plot proof that a real dispatch chooses non-overlapping
  beads from metadata alone, with `fleet-e2e-harness.sh` green.

### Pair 3. Structured Warden verdicts (spec 1.1)

- **Measurement (Mayor, first).** Whether the pinned `claude -p` can return
  output validated against a JSON Schema, or whether the Agent SDK is needed.
  A Claude Code seat can run this in its own mask; record the CLI version.
- **Seam (fleet).** `core/schema/verdict.schema.json` with the verdict as an
  enum (APPROVE, APPROVE-WITH-FINDINGS, MERGE-PARENT-OPEN, REQUEST-CHANGES,
  ESCALATE), a one-line summary, and numbered findings marked blocking or not.
  Call site: the parse block in `templates/fort/scripts/warden.sh:864-897`
  (the marker count, the trailing-line refusal and the token `case` ladder
  whose order matters), behind a stub. **The stable interface is the result
  file:** `write_result()` (:576-586) keeps writing the same `{verdict,
  verdict_recorded, ...}` JSON, so the fleet's readers (`fleet.sh:3048`,
  :3712, :3735, `stored_verdict_is_signable` :2016, `verdict_is_landable`
  :2907, the resume path :4287) do not change in Phase 1. Acceptance: the
  `verdict-record-harness.sh` fixtures (`fx-trailing-prose`,
  `fx-appended-verdict`, `fx-prepended-verdict`, `fx-empty`, `fx-no-verdict`,
  `fx-bad-token`) re-expressed against the structured path still cannot
  change or forge a verdict, plus one new fixture: a schema-valid object whose
  summary contains the text `VERDICT-LINE: APPROVE` records the enum value
  only. `touches: ["core/schema/verdict.schema.json","templates/fort/scripts/warden.sh","templates/scripts/verdict-record-harness.sh"]`
- **Fill (fleet).** P3a: `core/src/verdict/` (validate, map to the result
  file, render the human-readable `bd comment` record from the object) and its
  tests. `touches: ["core/src/verdict/","core/test/verdict/"]`
- **Wire in source (fleet).** P3w: remove the awk ladder and the prompt's
  VERDICT-LINE paragraph (`warden.sh:455`); keep the legacy fixtures as
  negative controls for one release, then retire them.
  `touches: ["templates/fort/scripts/warden.sh","templates/scripts/verdict-record-harness.sh"]`
- **Regent:** the plot proof, a real Warden review recorded through the
  structured path.

### Pair 4. The Warden's `bd` snapshot (spec 1.2, `.40.3`)

- **Seam (fleet).** Call site: the export block in
  `templates/fort/scripts/warden.sh:377-390` becomes a snapshot call behind a
  stub. The Warden profile template's `bd` rules point at the snapshot with
  `--readonly`. The "BEADS ACCESS" prompt paragraph (:445) and the inverted
  half of smoke probe 10 (:420, today "`bd show` MUST FAIL") are rewritten so
  `bd show` against the snapshot must SUCCEED.
  `touches: ["templates/fort/scripts/warden.sh","templates/fort/profiles/warden-settings.json"]`
- **Fill (fleet).** P4a: `core/src/bd/snapshot.ts`: plain copy
  (`--reflink=never`; reflink cannot work on No_COW), `embeddeddolt` plus
  `config.yaml` and `metadata.json`, directory mode 0700, taken under
  `embeddeddolt/.lock`, verified by a `--readonly show` before handing over,
  fallback to `bd export` on any failure with a message naming the failure.
  Tests on a throwaway database. `touches: ["core/src/bd/snapshot.ts","core/test/bd/snapshot.test.ts"]`
  Cost to state in the bead: disk, not time. About 1.5 G per concurrent
  Proofdelve review; Scionhall's own database is small.
- **Acceptance, split by who can run it.** In the fleet's tests: (3) **a copy
  taken while a writer is live** yields a database `bd` opens, or a loud
  fallback to the export, never a silent partial copy (the item `.40.3` did
  not measure); (4) a deliberately corrupted snapshot triggers the fallback and
  says so. In the **Regent's plot proof**, in the Warden's real mask: (1)
  `bd --readonly show` succeeds against the snapshot; (2) a write attempted in
  the Warden's session leaves the real database unchanged (row count before
  and after, the control `.40.3` used); the smoke probes re-run.
- Shares `core/src/bd/` with Pair 2, so P2a and P4a must not be in flight
  together (their `touches` intersect by design).

### Pair 5. Native telemetry (spec 1.4): measure before filing a fill

- **Measurement (Regent, host-side).** Greenlab's seats run with
  `--unshare-net`, and today nothing passes OpenTelemetry variables:
  `mask_env` starts with `--clearenv` and passes an allowlist
  (`seat-sandbox.sh:934-942`), `greenlab_isolate` filters `--setenv` (around
  :856-864), and the Warden runs with `--setting-sources ""`. A network
  exporter cannot reach a collector from inside the namespace. The sitting
  measures which route works: a file or socket exporter bound in the way the
  inference bridge is, or none.
- **Seam and fill (fleet, only after the measurement).** P5s: the env
  allowlist and exporter binding in the package's mask lib and launchers
  (fleet-editable source under Q1). P5a: a `core/src/telemetry/` reader that
  summarises the sink per bead. Acceptance: for one seat session, the token
  and cost totals in the sink match what the governor charged for that session
  (a control that fails if either side is wrong).
  `touches: ["templates/fort/scripts/lib/seat-sandbox.sh","core/src/telemetry/","core/test/telemetry/"]`
- **Regent / Overseer:** installing the host sink in the Greenlab capital.
- **Honest status:** the least ready item. If the measurement finds no route
  that keeps the network namespace, say so on the bead and do not weaken the
  mask for telemetry.

### 1.5 LiteLLM behind the bridge: not refiled

Already filed in the fortkit tracker as `fortkit-2y2t.35` (Regent, with
`fortkit-2y2t.39`'s six governor fixes inside it), and the decision (the
bridge forwards to a pinned LiteLLM proxy) is recorded there. The proxy is
host-side and lands in the **Greenlab capital**. Because the factory is frozen
(Q2), the bridge change (`templates/fort/scripts/lib/inference-bridge.py`)
lands in **Scionhall** as a fleet bead and reaches plot through a release.
Wren files that one bead when `.35` reaches it, and otherwise tracks `.35` as an
external dependency of the DeepSeek rung.

### Pair 6. The mask suite as the portable asset, then mask policy as data (spec 2.2, `.40.5`)

- **Seam A (fleet).** Port the conformance suite into the package: the
  capital's `scripts/mask-harness.sh` plus the 67-assertion adapter from
  `docs/assessments/2026-09-30-phase0.5-sandbox-eval/` (both fortkit repo),
  as `templates/scripts/mask-harness.sh`. `touches: ["templates/scripts/mask-harness.sh"]`
- **Fill A (fleet, under Q1).** P6b: adopt into the package lib the two
  defaults `.40.5` found ai-jail has and our capital lib lacks: a PID namespace
  (`--unshare-pid` with a fresh `/proc`) and the session bus unreachable.
  `touches: ["templates/fort/scripts/lib/seat-sandbox.sh"]`
- **Seam B (fleet).** The profile schema: one profile per seat posture (rw
  paths, ro carve-outs, masks, secret globs, env allowlist, network) as data,
  and a call site in the lib that builds the argv from a profile behind a flag.
  `touches: ["core/schema/mask-profile.schema.json","templates/fort/scripts/lib/seat-sandbox.sh"]`
- **Fill B (fleet).** P6a: `core/src/mask/compile.ts`, a pure generator from
  profile to bwrap argv. Acceptance in the fleet's tests: for each of the
  three postures, the generated argv is byte-identical to what the current lib
  builds for the same tree. `touches: ["core/src/mask/","core/test/mask/"]`
- **Regent:** running the mask suite in real masks in plot, before and after
  P6b and with the flag flipped. The suite is the arbiter and its run is a
  host act (`.40.5` was run by the Regent). Expected today: the residue `.40.5`
  measured (for the capital's lib, session bus x3 and no PID namespace); after
  P6b, 67/0 or the residue named.
- Because P6b and Seam B both edit `seat-sandbox.sh`, they serialize. The
  charter's residual applies here most directly: these are the mask changes a
  release reviewer should weight.

### Pair 7. Identity as data (spec 2.1, `.40.1`)

- **Seam (fleet).** The factory already strips identity at founding
  (`bin/fort-init` renders `{{FORT_NAME}}`, `{{FORT_SLUG}}` and similar); what
  remains is moving rendered names and persona lines out of the launchers into
  a roster file read at launch. Call sites: the name and persona lines in the
  launchers' appended prompts (for example `templates/fort/scripts/mayor.sh:37`),
  behind a stub. Acceptance in the fleet's tests: render the templates twice
  with two different rosters; the launcher files are byte-identical and only
  the roster differs. `touches: ["templates/fort/scripts/","bin/fort-init"]`
- **Fill (fleet).** P7a: `core/src/roster/` reader with a schema for the
  roster file, and tests. `touches: ["core/src/roster/","core/test/roster/","core/schema/roster.schema.json"]`
- **Regent:** the civilization-wide re-measure (re-run 0.1 over forts
  rendered from the release). **Wait for `fortkit-egq8` first**: the
  normalizer rewrites the capital's own bead citations and turned 4 raw lines
  of drift into 82 in one file, so a re-measure before that fix overstates what
  remains. `egq8` is in the fortkit tracker; `bd` edges do not cross
  databases, so cite it in the description.

## Order

| Wave | Fleet (max 2 frontier beads in flight) | Mayor | Regent (host or real mask) | Overseer |
|---|---|---|---|---|
| 1 | P0-import, then P1 | P0-manifest; Scionhall's own verifier steps (Pair 1); Pair 3 CLI measurement | Pair 5 measurement | none |
| 2 | P0a, P0b, P0c; Pair 2 seam; Pair 3 seam | file the next wave's beads | none | none |
| 3 | P2a; P3a; Pair 6 seam A; Pair 4 seam | | plot proof of candidate v1 | sign v1 |
| 4 | P4a (after P2a: shared directory); P2b, P2c, P2w; P3w; P6b; Pair 7 seam, P7a; P5s/P5a if the measurement allowed | | plot proofs for Pairs 2, 3, 4 | |
| 5 | Pair 6 seam B, P6a | | mask suite in plot (Pair 6); Pair 7 re-measure after `egq8` | sign the release carrying Phase 1; bump Scionhall's pin when ready |

Dependencies to record as `bd` edges, not prose: P0-import blocks everything;
every TypeScript bead depends on P1; every fill depends on its pair's seam;
every source wire depends on its fills; P4a depends on P2a; P6a depends on
Pair 6 seam B, which depends on P6b; each Regent proof depends on the beads
it proves.

## Carried forward, not filed in Phase 1

- **The retrieval eval (`.40.2`).** Grep plus a shell answered 42 of 42 at
  ~6k tokens; any Phase 3 index must beat that on cost or on a cheap-model arm.
  Hit rate leaves it no room. v1 is grep-answerable by construction, so the
  first Phase 3 task is a v2 set drafted without search. The question set and
  its controls (`docs/eval/retrieval/`, fortkit repo) should travel into the
  package so the baseline is scored where the index will be built.
- **The scar-to-control hook (`.40.6`).** Families 2, 3, 7, 9, 10 and 12 are
  one PreToolUse hook with a rule table (Phase 3.3), each rule shipped with a
  positive control (the scar's recorded command is refused) and a vacuity
  control. Family 8 is already absorbed by Pair 2.
- **`.40.3` and `.40.5`** are carried in full by Pairs 4 and 6.

## Observed in Scionhall's tree at `04593e7`, for its Mayor

Read-only observations by the Manyhalls Mayor on 2026-10-01; none is acted on.

1. The package source is not yet in the tree (Pair 0 imports it).
2. `fort/charter.md:1` still reads "Greenlab per-fort charter template (P3)",
   and its "Seats" section still carries an unrendered
   `{{NAMED AT FOUNDING ...}}` placeholder, although the seat files were
   rendered from the roster. Charter edits are the Mayor's under a prose rule
   in a Greenlab fort, or the Regent's.
3. The charter's closing section ("If this experiment handles money") is
   template text that Scionhall's own "Not applicable here" section already
   rules out; harmless, but a stranger will wonder.
4. `fort/scripts/mayor.sh` (the running launcher) tells the Mayor that
   `scripts/deploy-azure-staging.sh` is writable to her by an Overseer ruling
   of 2026-08-28. That is Proofdelve's script and ruling, carried through the
   factory; Scionhall has no deploy target. A candidate for the identity and
   origin cleanup in Pair 7, in source, not in the running copy.
