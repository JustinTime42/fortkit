# fortkit

Civilization-level tooling for Justin's agent forts:
- **bin/fort-init** — found a new fort in any git repo (templates extracted from Proofdelve + Farlantern)
- **schema/events.md** — canonical event schema (forts vendor it; add-only)
- **fort/** — Manyhalls, the fort that maintains fort architecture: the launchers, seat mask, fleet, verifier and airlock a settlement runs on, and their harnesses (`fort/charter.md`)
- **civ/** — the civilization layer: covenant, seats, the Civ Keep, the Herald and Chronicler
- Registry: ~/.claude/civilization.json
- **skills/fort-backport** — the /fort-backport skill (canonical; deployed copy at ~/.claude/skills/)

## Verify

```bash
npm ci
fort/scripts/verify.sh
```

The Bartizan viewer (world and colony views) was retired on 2026-11-18; its spec is
kept at `fort/annals/fortress-visualizer-spec-retired-2026-11-18.md`.
