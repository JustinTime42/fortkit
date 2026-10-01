# 08: Phase 1 filing plan, as seam-and-fill pairs

Status: DRAFT for the Overseer, 2026-10-01. Written by the Mayor of Manyhalls
(Emrith Cairnwright) at the Overseer's request, after Phase 0 of spec 07
reported and its decisions were approved (recorded on `fortkit-2y2t.40` by the
Regent, 2026-10-01 01:44). Nothing here is filed. The intended reader is the
Mayor of the package fort (`fortkit-2y2t.40.7`) on its first day, who has none
of the conversation behind this and should not need it.

**Read first:** `07-systemic-upgrade.md` (the spec this decomposes), then the
Phase 0 beads named below. Every number here is quoted from a bead comment or
a committed assessment, with the source given; re-read the source before
copying a number into a bead.

## What this plan covers

Spec 07 section 1 (Phase 1, items 1.1 to 1.5) in full, and the parts of
section 2 (Phase 2) that Phase 0 measurements now shape: 2.1 (identity as
data, shaped by 0.1) and 2.2 (mask policy as data, shaped by 0.5). Sections 2.3
(the Gas Town bake-off) and 2.4 (seat templates as a plugin) are not shaped by
any Phase 0 number and are left out. Phase 3 items appear only under "Carried
forward".

## The pattern, restated for a stranger

From spec 07, "Implementation":

1. **A seam** is cut by a Regent sitting with the Overseer present. It defines
   the interface (a TypeScript signature or a JSON Schema), adds the call site
   in the kernel-read-only launcher behind a stub that keeps today's behaviour,
   and lands the black-box acceptance test that must go green.
2. **A fill** is done by the fort's fleet: a Forge implements the module in a
   worktree, the Warden reviews, the fleet lands it. The seam's acceptance test
   is the fill bead's criterion.
3. **A wire** is a second Regent sitting: stub removed, real module live,
   verified in a real mask in `plot` (Greenlab's test bench) before the package
   version that carries it is signed.

Every pair below names all three. A seam bead is labelled `act-regent`; a fill
bead is labelled `fleet-safe`, which is the label the fleet's dispatcher
selects on (`fleet.sh:1524`, `bd ready --limit 0 --label fleet-safe --json`).

## Which tree each piece lands in

| Tree | What it is | What lands there |
|---|---|---|
| **The package fort** (unnamed; `fortkit-2y2t.40.7`) | the settlement whose product is the fort machinery. Its RUNNING machinery is a pinned, previously signed package version. Its package SOURCE is ordinary files in its tree | every seam definition, every fill, every new package version |
| **plot** (`~/dev/greenlab/forts/plot`) | Greenlab's test bench. Nobody lives there; its state is disposable (`06-autonomous-operation.md`) | the wire step: a candidate package version is installed and proven in a real mask, including the host-only `fleet-e2e-harness.sh`, before it is signed |
| **The Greenlab capital** (`~/dev/greenlab`) | law, covenant, governor, Effect Gateway, the current factory. No product work (`06`) | host-side services only: the LiteLLM proxy (1.5) and any telemetry sink (1.4). The capital's `bin/fort-init` and `templates/` stop being edited once the package exists (open question Q2) |

## Phase 0 results, as this plan uses them

| Bead | Result (source: the bead's RESULT comment) | Where it lands below |
|---|---|---|
| `.40.1` | Greenlab's factory is a near-superset of Proofdelve. Over 125 copied files: unchanged by both 80, Proofdelve-only 3, Greenlab-only 32, both disjoint 5, **conflicting 5**, all conflicts in harnesses or lint: `scripts/queue-lint-harness.sh` (4 hunks), `scripts/verify-impl.sh`, `scripts/supervisor-harness.sh`, `scripts/scratch-reaper-harness.sh`, `scripts/queue-lint.sh` (1 each). Identity is a small share of the five-version divergence. Instrument defect `fortkit-egq8` | Pair 0 (version 1), Pair 7 (2.1) |
| `.40.2` | Grep plus a shell is the baseline: search arm 42/42 at ~6.0k tokens and 2.4 tool uses a question; `recall` 34/42 at ~17.4k. The set is grep-answerable by construction | Carried forward (Phase 3). No Phase 1 pair |
| `.40.3` | Reflink is impossible (every `.beads` is btrfs No_COW). A plain copy of Proofdelve's 1.5 G database takes 0.96 s; `bd` serves every read from it identically; writes cannot reach the real database. Live-writer consistency NOT measured and carried as an acceptance criterion | Pair 4 (1.2) |
| `.40.4` | `bd` metadata round-trips, reaches the export, filters on scalar values (not array elements), survives claim/close/reopen. `Touches:` can move into metadata as a JSON array; intersection stays in the adapter. `bd init` writes AGENTS.md, CLAUDE.md, `.claude/`, `.codex/`, `.agents/` into the directory it initialises | Pair 2 (1.3), and every fill bead's metadata |
| `.40.5` | 67 identical assertions: our capital lib 63/4 (session bus x3, no PID namespace), Proofdelve lib 66/1 (PID namespace), ai-jail 65/2, greywall 63/4. Neither tool expresses per-role postures across several trees. **Our lib stays the substrate; the suite is the portable asset.** Method and adapter: `docs/assessments/2026-09-30-phase0.5-sandbox-eval/` | Pair 6 (2.2) |
| `.40.6` | 645 memory items: scar 274, why 211, restates-code 108, record 52. Scar family 8 (`bd` output traps) belongs in the 1.3 adapter; families 2, 3, 7, 9, 10, 12 are one PreToolUse hook (Phase 3.3) | Pair 2's quirk list; the hook is carried forward |

## Facts about the starting tree that shape the pairs

Read from `~/dev/greenlab` on 2026-10-01 (capital at `fdc8225`, plot at
`92cbcaa`). Line numbers are in `greenlab/templates/...`; plot's rendered
copies of `warden.sh` (932 lines) and `fleet.sh` (4,717) have the same line
numbering. Re-read before citing; they will move.

- **There is no TypeScript anywhere in Greenlab.** plot's `package.json` is
  plain ESM, `"test": "node --test test/*.test.mjs"`, sources `src/*.mjs`.
  Spec 07 decided TypeScript for new orchestration code. So the toolchain is
  itself a seam (Pair 1) and blocks every TypeScript fill.
- **`mask-harness.sh` does not exist in Greenlab.** It lives only in the
  fortkit capital (`scripts/mask-harness.sh`). Greenlab's mask proofs are
  `tools/wall-proof/`, `fort/scripts/probe-boundaries.sh`,
  `probe-forge-masks.sh` and the Warden's smoke probes.
- **Kernel read-only in a running Greenlab fort** (covenant item 6,
  `civ/covenant.md:88-90`; binds in `templates/fort/scripts/lib/seat-sandbox.sh`):
  all of `fort/scripts/` (one bind, :524), `.claude`, `fort/profiles`,
  `.git/config` and hooks (:253), `fort/airlock/operations.json` (:269), and
  seat-dependent `fort/charter.md`, `fort/seats`, `scripts/verify-impl.sh`,
  `skills` (:322, :481). The capital is read-only to every seat (:749, :843).
- **The fleet reads `Touches:` from description prose** (`touch_set_of`,
  `fleet.sh:1748`; `touch_sets_intersect`, :1808). Until Pair 2 is wired, the
  package fort's own fleet can only see prose.
- **Concurrency on the frontier rung** is capped by the governor at
  `GOV_FRONTIER_SESSIONS_MAX=2` (`civ/governors.conf`). Plan for two fills in
  flight at once.

## How each bead carries `Touches:` (from `.40.4`)

During the bootstrap, **every fill bead carries BOTH forms**, because the
running fleet parses prose and the adapter (Pair 2) will read metadata:

```
bd create --type=task --labels=fleet-safe \
  --title="..." \
  --description="...
Touches: core/src/bd/, core/test/bd/" \
  --metadata '{"touches":["core/src/bd/","core/test/bd/"],"lane":"fleet","rung":"frontier","pair":"P2"}'
```

`touches` is an array, so `bd` cannot filter on it (the adapter intersects).
`lane`, `rung` and `pair` are scalars, so `bd list --metadata-field lane=fleet`
and `bd list --metadata-field pair=P2` work. Seam beads carry
`"lane":"regent"`. After Pair 2's wire, the prose line becomes optional; drop
it only after the adapter has been seen preferring metadata in a real dispatch.

`core/` is a proposed path (Pair 1 decides the layout). If the founding
sitting chooses another, substitute it everywhere below.

## The pairs

### Pair 0. Version 1 of the package: reconcile Proofdelve into Greenlab's factory (`.40.1`)

- **Seam (Regent, the founding sitting).** Pins v0 = Greenlab's factory at a
  named commit as the fort's running machinery (the founding is the first
  "previously signed" version, by the Overseer's approval under covenant gate
  6.3). Interface: a manifest file listing the Proofdelve changes to port, one
  row per file with its class (Proofdelve-only, disjoint, conflicting).
  Generate the list by re-running `docs/assessments/2026-09-30-phase0.1-measure.mjs`
  (fortkit repo) against v0 rather than copying the `.40.1` table, which
  prints file names truncated. Call site: none. Acceptance: every harness the package
  ships passes against the reconciled tree in plot, including the host-only
  `fleet-e2e-harness.sh`; every manifest row is marked ported or declined with
  a reason.
- **Fills (fleet, package tree, `scripts/`).**
  - P0a: `scripts/queue-lint-harness.sh` (4 conflicting hunks). `touches: ["templates/scripts/queue-lint-harness.sh"]`
  - P0b: the four one-hunk conflicts: `verify-impl.sh`, `supervisor-harness.sh`,
    `scratch-reaper-harness.sh`, `queue-lint.sh`. `touches:` those four. Note
    that `verify-impl.sh` is kernel read-only in a RUNNING fort; in the
    package tree it is template source and fleet-writable (see Q1).
  - P0c: the non-conflicting rows (Proofdelve-only and disjoint). The disjoint
    set includes `fort/seats/mayor.md`: a seat file mixes architecture and
    identity, so port per hunk and never per file (fortkit charter, standing
    order 12 by content).
- **Wire (Regent).** Sign v1 and re-pin the fort's running machinery to it.
- **Tree:** package fort; proven in plot.

### Pair 1. The TypeScript toolchain (seam only)

- **Seam (Regent, founding sitting or the first after it).** Decides the
  package layout (`core/src`, `core/test`, `core/schema` proposed), the Node
  version, how TypeScript runs (native type stripping, `node file.ts`, the
  pattern the fortkit capital uses with no bundler), `tsc --noEmit` for
  typecheck, `node --test` for tests, and the thin CLI convention by which
  bash calls a module (`core/bin/<tool> <verb> --json`). Adds the typecheck and
  test steps to the package's `verify-impl.sh` (kernel read-only to the
  running fort's Forge, so this is sitting work). Acceptance: a deliberately
  ill-typed canary module turns the verifier red, and a passing trivial module
  turns it green; canary removed in the same sitting.
- **Fill:** none. Every TypeScript fill below depends on this seam.
- **Tree:** package fort.

### Pair 2. One `bd` adapter, with `Touches:` in metadata (spec 1.3, `.40.4`, `.40.6` family 8)

- **Seam (Regent).** Interface `core/src/bd/adapter.ts`: `show(id)`,
  `list(filter)`, `ready(filter)`, `comments(id)`, `mergeSlotExists()`,
  `touches(id): string[]`, `setTouches(id, paths)`, each returning typed
  results or a typed error (never an empty value standing in for a failure).
  Thin CLI `core/bin/bd-adapter`. Call sites behind stubs that still run
  today's bash: `bead_json` (`fleet.sh:405`), `ready_candidates` (:1524),
  `touch_set_of` (:1748), `merge_slot_exists` (:2947). Acceptance: a quirk
  suite against real `bd` 1.1.2 on a throwaway database, one test per quirk,
  each red against a naive implementation first:
  - `--limit` default caps results (the "limit 100" trap);
  - `dependency_type` and `type` swapped between `show --json` and
    `list --json` (`fleet.sh:1452-1459`);
  - `merge-slot check` exits 0 whether or not a slot exists (:559-567);
  - `blocked --limit 0` returns empty;
  - comment bodies absent from `show --json`;
  - `list` hides closed beads by default;
  - `bd init` writes agent files into its directory (`.40.4`), so tests run in
    a scratch directory.
  Plus `fleet-e2e-harness.sh` unchanged and green in plot.
- **Fills.**
  - P2a: the adapter module and quirk tests. `touches: ["core/src/bd/","core/test/bd/","core/bin/bd-adapter"]`
  - P2b: `touchSetsIntersect` as a pure function with today's bash semantics
    (prefix overlap), its tests ported from the existing harness cases, and
    `touches(id)` reading metadata first, prose second, saying which it used.
    `touches: ["core/src/bd/touches.ts","core/test/bd/touches.test.ts"]`
  - P2c: the writers. `scripts/unattended-fleet/add-touches.py` and
    `retouch.py` write metadata as well as prose. `prose-blockers.py` stays
    as the lint that pushes prose into real edges (spec 1.3).
    `touches: ["templates/scripts/unattended-fleet/"]`
- **Wire (Regent).** Replace the four bash bodies with adapter calls; verify a
  real dispatch in plot chooses non-overlapping beads from metadata alone.
- **Tree:** package fort.

### Pair 3. Structured Warden verdicts (spec 1.1)

- **Seam (Regent).** First a measurement inside the sitting: whether the pinned
  `claude -p` can return output validated against a JSON Schema, or whether the
  Agent SDK is needed. Then: `core/schema/verdict.schema.json` with the verdict
  as an enum (APPROVE, APPROVE-WITH-FINDINGS, MERGE-PARENT-OPEN,
  REQUEST-CHANGES, ESCALATE), a one-line summary, and numbered findings marked
  blocking or not. Call site: the parse block in `warden.sh:864-897` (the
  marker count, the trailing-line refusal and the token `case` ladder whose
  order matters). **The stable interface is the result file:**
  `write_result()` (:576-586) keeps writing the same `{verdict,
  verdict_recorded, ...}` JSON, so the fleet's readers (`fleet.sh:3048`,
  :3712, :3735, `stored_verdict_is_signable` :2016, `verdict_is_landable`
  :2907, the resume path :4287) do not change in Phase 1. Acceptance: the
  `verdict-record-harness.sh` fixtures (`fx-trailing-prose`,
  `fx-appended-verdict`, `fx-prepended-verdict`, `fx-empty`, `fx-no-verdict`,
  `fx-bad-token`) re-expressed against the structured path still cannot
  change or forge a verdict, plus one new fixture: a schema-valid object whose
  summary contains the text `VERDICT-LINE: APPROVE` records the enum value
  only.
- **Fill.** P3a: `core/src/verdict/` (validate, map to the result file,
  render the human-readable `bd comment` record from the object) and its
  tests. `touches: ["core/src/verdict/","core/test/verdict/","core/schema/verdict.schema.json"]`
- **Wire (Regent).** Remove the awk ladder and the prompt's VERDICT-LINE
  paragraph (:455); keep the legacy fixtures as negative controls for one
  version, then retire them.
- **Tree:** package fort.

### Pair 4. The Warden's `bd` snapshot (spec 1.2, `.40.3`)

- **Seam (Regent).** Call site: the export block in `warden.sh:377-390`
  becomes a snapshot call. The Warden profile's `bd` rules point at the
  snapshot with `--readonly`. The "BEADS ACCESS" prompt paragraph (:445) and
  the inverted half of smoke probe 10 (:420, today "`bd show` MUST FAIL") are
  rewritten: `bd show` against the snapshot must SUCCEED. Acceptance, all four
  required:
  1. `bd --readonly show` succeeds in the Warden's mask against the snapshot;
  2. a write attempted in the Warden's session leaves the real database unchanged
     (row count before and after, the control `.40.3` used);
  3. **a copy taken while a writer is live** yields a database `bd` opens, or
     a loud fallback to the export; never a silent partial copy (the item
     `.40.3` did not measure);
  4. a deliberately corrupted snapshot triggers the fallback and says so (the
     fallback's own positive control).
- **Fill.** P4a: `core/src/bd/snapshot.ts`: plain copy (`--reflink=never`;
  reflink cannot work on No_COW), `embeddeddolt` plus `config.yaml` and
  `metadata.json`, directory mode 0700, taken under `embeddeddolt/.lock`,
  verified by a `--readonly show` before handing over, fallback to `bd
  export` on any failure with a message that names the failure. Tests on a
  throwaway database, including a concurrent-writer test.
  `touches: ["core/src/bd/snapshot.ts","core/test/bd/snapshot.test.ts"]`
  Cost to state in the bead: disk, not time. About 1.5 G per concurrent
  Proofdelve review; the package fort's own database is small.
- **Wire (Regent).** Live in plot; smoke probes re-run.
- **Tree:** package fort. Shares `core/src/bd/` with Pair 2, so P2a and P4a
  must not be in flight together (their `touches` intersect by design).

### Pair 5. Native telemetry (spec 1.4): measure before filing a fill

- **Seam (Regent), measurement first.** Greenlab's seats run with
  `--unshare-net`, and today nothing passes OpenTelemetry variables:
  `mask_env` starts with `--clearenv` and passes an allowlist
  (`seat-sandbox.sh:934-942`), `greenlab_isolate` filters `--setenv` (around
  :856-864), and the Warden runs with `--setting-sources ""`. A network
  exporter cannot reach a collector from inside the namespace. The sitting
  measures which route works: a file or socket exporter bound in the way the
  inference bridge is, or none. Acceptance once a route exists: for one seat
  session, the token and cost totals in the sink match what the governor
  charged for that session (a control that fails if either side is wrong).
- **Fill (only after the measurement).** P5a: `core/src/telemetry/` reader
  that summarises the sink per bead. `touches: ["core/src/telemetry/","core/test/telemetry/"]`
- **Tree:** package fort for the launcher env and the reader; the host sink
  in the Greenlab capital (an Overseer install).
- **Honest status:** this is the least ready item. If the measurement finds no
  route that keeps the network namespace, say so on the bead and do not
  weaken the mask for telemetry.

### 1.5 LiteLLM behind the bridge: not refiled

Already filed in this tracker as `fortkit-2y2t.35` (Regent, with
`fortkit-2y2t.39`'s six governor fixes inside it), and the decision (the
bridge forwards to a pinned LiteLLM proxy) is recorded there. The proxy is
host-side, so it lands in the **Greenlab capital**. The bridge change
(`templates/fort/scripts/lib/inference-bridge.py`) lands in **the package**
once the package is the factory (Q2). The package fort's Mayor files nothing
for 1.5 and tracks it as an external dependency of the DeepSeek rung.

### Pair 6. The mask suite as the portable asset, then mask policy as data (spec 2.2, `.40.5`)

- **Seam A (Regent).** Port the conformance suite into the package: the
  capital's `scripts/mask-harness.sh` plus the 67-assertion adapter from
  `docs/assessments/2026-09-30-phase0.5-sandbox-eval/`, run against the
  package's lib in plot. Acceptance: the suite runs unchanged and its expected
  failures today are recorded as such (for the capital's lib: session bus x3,
  `fortkit-y7no`; no PID namespace, `fortkit-e4q`). Then the Regent adopts the
  two defaults `.40.5` found ai-jail has and our capital lib lacks (PID
  namespace, session bus off) into the package lib; the suite goes to 67/0 or
  the residue is named.
- **Seam B (Regent).** The profile schema: one profile per seat posture (rw
  paths, ro carve-outs, masks, secret globs, env allowlist, network) as data,
  and a call site in the lib that can build the argv from a profile behind a
  flag.
- **Fill.** P6a: `core/src/mask/compile.ts`, a pure generator from profile to
  bwrap argv. Acceptance: for each of the three postures, the generated argv is
  byte-identical to what the current lib builds for the same tree, and then the
  suite is green through the generated path. `touches: ["core/src/mask/","core/test/mask/","core/schema/mask-profile.schema.json"]`
- **Wire (Regent).** Flip the flag in plot; the suite is the arbiter.
- **Tree:** package fort; proven in plot.

### Pair 7. Identity as data (spec 2.1, `.40.1`)

- **Seam (Regent).** Greenlab's factory already strips identity at founding
  (`bin/fort-init` renders `{{FORT_NAME}}`, `{{FORT_SLUG}}` and similar), so
  what remains is moving the rendered names and persona lines out of the
  launchers into a roster file read at launch. Call sites: the persona and
  name lines in the launchers' appended prompts (for example
  `fort/scripts/mayor.sh:37`). Acceptance: re-run the 0.1 measurement over
  forts rendered from the package; launcher files are identical across them,
  and only the roster differs. **Fix `fortkit-egq8` first**: the normalizer
  rewrites the capital's own bead citations and manufactured 82 lines of
  apparent drift from 4 in one file, so a re-measure before that fix will
  overstate what remains.
- **Fill.** P7a: `core/src/roster/` reader with a schema for the roster file
  and tests. `touches: ["core/src/roster/","core/test/roster/","core/schema/roster.schema.json"]`
- **Tree:** package fort.

## Order

| Wave | Regent sitting cuts | Fleet fills (max 2 in flight) |
|---|---|---|
| 0, at founding | Pair 0 seam (pin v0, manifest), Pair 1 | none until the toolchain is in |
| 1 | Pair 2 seam, Pair 3 seam (with its CLI measurement), Pair 5 measurement | P0a, P0b, P0c (bash, no toolchain needed; can start in wave 0) |
| 2 | Pair 0 wire (sign v1), Pair 4 seam, Pair 6 seam A | P2a then P2b, P2c; P3a |
| 3 | Pair 2 and 3 wires, Pair 6 seam B, Pair 7 seam (after `egq8`) | P4a (after P2a lands), P6a, P7a, P5a if the measurement allowed it |
| 4 | Pair 4, 6, 7 wires; sign the version carrying Phase 1 | none |

Dependencies to record as `bd` edges, not prose: every TypeScript fill
depends on Pair 1's seam; every fill depends on its own pair's seam; P4a
depends on P2a (shared directory); Pair 7's seam depends on `fortkit-egq8`
(cross-tracker, so record it as an external reference in the description,
since `bd` edges do not cross databases).

## Carried forward, not filed in Phase 1

- **The retrieval eval (`.40.2`).** Grep plus a shell answered 42 of 42 at
  ~6k tokens; any Phase 3 index must beat that on cost or on a cheap-model arm,
  not on hit rate. v1 is grep-answerable by construction, so the first Phase 3
  task is a v2 set drafted without search. The question set and its controls
  (`docs/eval/retrieval/` in the fortkit repo) should travel into the package
  so the baseline is scored where the index will be built.
- **The scar-to-control hook (`.40.6`).** Families 2, 3, 7, 9, 10 and 12 are
  one PreToolUse hook with a rule table (Phase 3.3), each rule shipped with a
  positive control (the scar's recorded command is refused) and a vacuity
  control. Family 8 is already absorbed by Pair 2.
- **`.40.3` and `.40.5`** are carried in full by Pairs 4 and 6.

## Open questions for the Overseer

1. **Q1. May the package fort's fleet edit launcher and mask-lib SOURCE in its
   own tree?** In a running fort those files are kernel read-only; in the
   package tree they are ordinary template files, so the mask does not stop a
   Forge. Recommended: no. Seams and wires that touch `templates/fort/scripts/`
   stay sitting work even here, and the fleet fills modules (`core/`) and
   harnesses (`templates/scripts/`) only. The package fort's charter should
   say so and its Forge's profile should enforce it if it can. Pair 0's
   harness fills are within that line; `verify-impl.sh` (P0b) is the one
   borderline file and is called out there.
2. **Q2. Does Greenlab's `templates/` and `bin/fort-init` freeze at the
   founding commit, with the package as the factory from then on?**
   Recommended: yes, otherwise `.35`'s bridge change and the package diverge in
   the first week. Greenlab's factory then becomes downstream of the package,
   as spec 4.0 already says of the capital's template.
3. **Q3. Civilization membership.** Your message calls it "its own Greenlab
   fort". `fortkit-2y2t.40.7` lists membership as still owed (item 2: Greenlab
   or production). I have read your words as deciding it for Greenlab; please
   confirm, and the Regent will record it on `.40.7`.
4. **The settlement's name** is still yours to give (covenant gate 6.3), and
   its citizens declare at its moot (8.1).
