# Civ Keep: a bounded, streamed read of each fort's tracker, and loud staleness

Bead: `fortkit-8bvu` (children `.1` to `.5`). Author: Emrith Cairnwright, Mayor
of Manyhalls, 2026-11-07. Source draft: Proofdelve's Mayor,
`/home/justin/dev/ForgeOs/fort/drafts/keep-export-reader.md` (same day). The
Overseer approved the Mayor's assessment of that draft, including every gap fix
below, on 2026-11-07; the approval is recorded on `fortkit-8bvu`.

## 1. The observed failure

`refreshFort` in `civ/keep/server.mjs` ran `bd export` through `command()`
(`lib/readers.mjs`, `execFile`) with `maxBuffer: 64 MiB`, buffered the whole
export, and `parseExport` kept every bead in full. On 2026-11-07 Proofdelve's
export reached 64.2 MB. Every refresh failed with "stdout maxBuffer length
exceeded"; the fort went `stale: true` at 16:16Z and the board served that
snapshot for about six hours. An approved bead stayed in the Overseer's queue
and a newly assigned ask never appeared. The only signal was the small `STALE`
badge in the nav.

Interim (in place, committed under `fortkit-8bvu`): `maxBuffer` raised to
256 MiB. Proofdelve's sizes on the day: non-closed beads 2.3 MB, closed beads
61.8 MB, of which 46 MB is comments. The export grows with closed history, so
any fixed buffer is a date on which this recurs.

## 2. What the Keep needs from the export

| Data | Consumer |
|---|---|
| Every non-closed bead, in full | board, graph, drawer, needs-you, Mayor summary |
| Beads closed within the graph's window (`closedHours`, at most 168 h) in full | graph and board (`lib/graph.mjs`) |
| `status` of every dependency target | `openBlockers` (`lib/graph.mjs:80`) treats a target missing from `byId` as NOT closed, so dropping an old closed bead would block its dependents |
| `dependencies` of every bead | `dependencyGroups` (`lib/graph.mjs:374`) scans every bead for reverse edges (an epic's children, what a bead blocks); `ancestors` (`lib/graph.mjs:89`) climbs parent edges through closed epics |
| `title` of any cited bead | Mayor summary facts (`lib/mayor-summary-extract.mjs:195`, `:340`) and the drawer's dependency list |

## 3. The change

### 3.1 Stream, do not buffer (`fortkit-8bvu.2`)

A new `readExport(fort, options)` in `lib/readers.mjs` spawns `bd export` in
`fort.repo` and reads stdout line by line (`readline` over `child.stdout`).
There is no `maxBuffer`; memory is bounded by what is kept, not by the export.

The reader MUST:

- **drain stderr** into a bounded buffer (keep the last 4 KiB for the error
  message). An unread stderr pipe fills at about 64 KB and the child blocks.
- **handle the child's `error` event** (for example `ENOENT` when `bd` is not on
  PATH) and reject with that error, never hang.
- **keep a timeout.** The buffered runner had 30 s (`readers.mjs:24`). Default
  60 s, overridable; on expiry kill the child (SIGTERM, then SIGKILL after 5 s)
  and reject with "bd export timed out after N s".
- **reject on a non-zero exit** with the exit code and the stderr tail, so
  `entry.error` stays a useful one-line message.
- count unparseable lines and records without `id` into `skipped`, as now.

Return value: `{ byId, skipped, digest }`. `parseExport(text)` stays exported
and applies the same bounding rule (3.2), so a text path and the stream path
cannot disagree.

### 3.2 Keep a bounded view

For each parsed record, with `cutoff = now - KEEP_CLOSED_FULL_DAYS` (14 days,
a module constant; comfortably above the graph's 168 h maximum):

- not closed, or closed at or after the cutoff, or `closed_at` missing or
  unparseable: keep the record in full (unknown age errs toward keeping);
- otherwise keep a **stub**:
  `{ id, status: "closed", closed_at, title, issue_type, dependencies, trimmed: true }`.

The stub drops description, design, acceptance criteria, notes, comments,
close reason and labels. It keeps `dependencies` and `title` because the
consumers in section 2 read them; they are small next to comments. Dependency
resolution, epic membership, reverse-edge listings, prefix detection and
summary fact titles stay exact.

### 3.3 Digest over the stream

`entry.exportDigest` feeds the Mayor summary's input fingerprint
(`server.mjs:481`). Compute it with `hash.update(chunk)` over the **raw stdout
chunks**, not over re-joined lines, so it is byte-identical to the old
`sha256(text)` and deployment does not cause one spurious summary update.
A test pins this equality.

### 3.4 The seam for tests

`createCivKeep` today takes `options.run`, and existing tests inject
`run: async () => ""`. Add `options.readExport` (default: the real streaming
reader). `refreshFort` calls `options.readExport` when given; when only
`options.run` is given (the existing tests), it falls back to
`parseExport(await run("bd", ["export"], ...))`, so no existing test changes.
The real reader is tested against a **fake `bd` script on PATH** that writes
lines, so the actual child-process path is exercised.

### 3.5 Loud staleness (`fortkit-8bvu.3`)

- Each fort entry gains `staleSince`: set to now on the first failed refresh
  after a success (or at boot), cleared on success. Exposed in `/api/forts` and
  in the graph payload's per-fort stale list (`staleForts` gains
  `{ name, staleSince, error, refreshedAt }` objects; keep the existing
  name-string field shape compatible or update both pages in the same change).
- When a fort has been stale for more than 10 minutes, **both** `board.html` and
  `graph.html` show a full-width banner under the nav, one line per fort:
  "{Fort} data is stale since {refreshedAt or 'never read'}: {error}". The nav
  badge stays.
- The fort strip's needs-you count for a stale fort carries a warning mark and a
  title explaining that the count may be out of date.
- **One `keep.stale` event per stale episode**, emitted to the **civ stream**
  through `civ/scripts/emit.sh` (actor `keep`, target the fort key, payload
  `{ fort, staleSince, error }`) when the 10-minute threshold is crossed, and one
  `keep.fresh` when the episode ends. Not to the fort's own stream: the Keep
  never writes into a fort's tree on its own initiative (Overseer decision,
  2026-11-07). The emitter is injectable (`options.emitCiv`) for tests.

### 3.6 Trimmed beads in the drawer (`fortkit-8bvu.4`)

`/api/bead/:id` on a stub returns it with `trimmed: true`. `lib/drawer.js`
renders, in place of the description section, a notice: "Closed more than 14
days ago; details are trimmed from the Keep's view. `bd show <id>` in the
fort has the full record." Fetching the full bead on demand is out of scope.

*Amended 2026-11-07 by the Mayor after the Warden's review of `.4`
(APPROVE-WITH-FINDINGS, findings 1-3), within the Overseer's approval of this
epic.* A trimmed drawer must not state anything the stub does not know:

- **Header:** no created or updated times and no priority chip (the stub has
  none; rendering them gave "NaNh ago" and "?"). Show "Closed {relative
  closed_at}" instead. Any drawer, trimmed or not, skips a time it does not have
  rather than printing NaN.
- **Sections:** only the notice and Dependencies render. Acceptance criteria,
  Notes, Comments (and its comment box) and Close reason are omitted, because
  "None." under Comments is false for a bead whose comments were trimmed.
- **The window:** the notice's "14" comes from the payload, not a second
  constant: `/api/bead/:id` carries `trimmedAfterDays` (from
  `KEEP_CLOSED_FULL_DAYS`) on a trimmed bead.

## 4. Tests (in `test/civ-keep.test.ts`, existing pattern)

1. A fake `bd` writing more than 64 MiB of lines refreshes without error, and
   `byId` holds the expected count.
2. An old closed dependency still counts as closed: its dependent is not
   `blocked` and `needsYou` matches the full-record result.
3. A closed bead older than the window has no `comments` or `description` in
   `byId` and carries `trimmed: true`; one inside the window keeps everything.
4. An open epic's drawer lists an old closed child (`dependencyGroups`).
5. The streamed digest equals `sha256` of the whole output.
6. Failure paths: non-zero exit, `ENOENT`, timeout (fake `bd` that sleeps),
   and a fake `bd` that writes >64 KB to stderr all reject without hanging.
7. A failed refresh sets `staleSince`; past 10 minutes (injected `now`) the
   payload carries the banner state and exactly one `keep.stale` is emitted
   across several further failures; a recovered refresh clears it and emits
   `keep.fresh`.

The Forge cannot open listening sockets in its sandbox; the Mayor runs the
Keep test file before review.

## 5. Acceptance and retirement of the interim (`fortkit-8bvu.5`)

Warden review of `.2` to `.4`. Then the live Keep stays fresh against the real
Proofdelve export through several refresh cycles, with resident memory recorded
before and after. Then the 256 MiB `maxBuffer` is gone with the buffered path,
and Proofdelve's Mayor is told the Keep no longer has an export size limit, so
`QUEUE_LINT_EXPORT_LIMIT_MB` in their `scripts/queue-lint.sh` can be retired or
re-aimed at their own budget.
