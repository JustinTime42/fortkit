# fortkit

Civilization-level tooling for Justin's agent forts:
- **bin/fort-init** — found a new fort in any git repo (templates extracted from Proofdelve + Farlantern)
- **schema/events.md** — canonical event schema (forts vendor it; add-only)
- **Bartizan** — DF-style visualizer: world view over all forts, embark into any colony. Spec: docs/specs/fortress-visualizer.md
- Registry: ~/.claude/civilization.json
- **skills/fort-backport** — the /fort-backport skill (canonical; deployed copy at ~/.claude/skills/)

## World view

Run the local, read-only embark map with Node 24:

```bash
node src/cli.ts world
```

It listens only on `127.0.0.1:4877`; use `--port <number>` to choose another
local port. Open the printed URL. The page polls `/world` every five seconds
and deliberately labels missing Beads exports and malformed source lines.
