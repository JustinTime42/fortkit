# Civ Keep

One loopback dashboard over every fort of every civilization on this host, with
the Overseer's signing desk. It runs at http://127.0.0.1:7780. Proofdelve's own
Keep (http://127.0.0.1:7777) is unchanged and keeps running beside it.

Built 2026-10-03 by the Regent at the Overseer's request, from Proofdelve's Keep
(`tools/keep` at ForgeOs `dae80d8e`). `lib/graph.mjs`, `lib/drawer.js`,
`lib/markdown.mjs`, `lib/live.mjs`, `lib/events.mjs`, `lib/fleet.mjs` and
`keep.css` are copies, changed only where a `CIV KEEP` comment says so. They are
copies and not imports because this server runs unmasked with write access to
every fort's tracker, and must not execute code another fort's fleet can change.

## What it shows

- **Forts:** every entry in `~/.claude/civilization.json` (production) and
  `~/.claude/greenlab.json` (Greenlab). A newly founded fort appears at the next
  refresh. The fort picker and the strip of fort pills filter every page; the
  choice is kept in the URL (`?fort=<key>`).
- **Board** (`/`): every open bead plus the recently landed, by stage, epic (or
  fort, when all forts are shown) or priority. "needs you only" narrows it to the
  signing queue.
- **Graph** (`/graph`): Proofdelve's dependency graph, per fort or all at once.
- **Drawer:** a bead's detail, the signing desk when it needs you, and a Comment
  box on every bead.

Reads are one `bd export` per fort per minute, sequential across forts, plus each
fort's `fort/events` (today and yesterday) and, for a fleet fort, its fleet state
directory.

## What "needs you" means, per fort (`lib/forts.mjs`)

- Proofdelve, plot, Scionhall, Farlantern, Kithmason: the `human` label, or a
  latest review verdict of ESCALATE with no later decision. Same rule as
  Proofdelve's Keep (measured identical on 2026-10-03: the same ten beads).
- Manyhalls: `gate-1`, `gate-2`, `gate-3` or `human` (the capital's documented
  "waiting on the Overseer" signal).

## What the desk writes

Every write passes a per-fort allowlist (`lib/readers.mjs` `signCommand`): the
bead's own prefix, the fort's own tree as the working directory, the fort's own
`emit.sh`, and only the labels named here.

- **Fleet forts** (those with `fort/scripts/fleet.sh`: Proofdelve, plot,
  Scionhall) behave exactly like Proofdelve's desk. An unnoted Approve on a bead
  whose `bead/<suffix>` branch exists removes `human`, adds `fleet-safe`, and pins
  the branch tip in the comment and the `gate.approved` payload. Decline, Decide,
  a noted Approve, or an Approve with no branch removes `human` and adds
  `mayor-review`.
- **Plain forts** (Manyhalls, Farlantern, Kithmason) have no fleet, so every
  signature removes the fort's waiting label and adds `mayor-review`. It never
  adds `fleet-safe`.
- Every signature writes an `OVERSEER via the Civ Keep` bead comment and emits
  `gate.approved`, `gate.declined` or `decision.recorded` in that fort's stream as
  actor `justin`, seat `overseer`.
- **Comment** writes one bead comment and nothing else: no label, no event.

It cannot merge, close, dispatch, create or edit a bead.

The audit log (intent before the effects, outcome after) is
`~/.local/state/civ-keep/signatures.jsonl`; `/api/signatures` shows it.

## Install

```bash
civ/keep/install.sh
```

It refuses to run from a masked seat, creates the signing token at
`~/.config/civ-keep/signing-token` (mode 0600, never printed; read it in your own
terminal), links `systemd/civ-keep.service` into the user unit directory and
starts it. The server restarts itself when its own source changes.

Tests: `npx vitest run test/civ-keep.test.ts`.
