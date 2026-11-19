# templates/

What `bin/fort-init` renders into a new fort. **Generated, not hand-edited**: run
`bin/refresh-templates` and it rewrites everything here from Manyhalls's own
machinery (`fort/scripts`, `fort/profiles`, `fort/systemd`, `fort/checklists`,
`fort/airlock`, `scripts`, `.claude/agents`), with fort-specific values turned into
placeholders and Manyhalls's own product (its gate-1 paths, its Node commands, its
citizens) replaced by generic text.

Kept by hand, and not overwritten by a refresh: `fort/advisories.md`,
`fort/memory/*.mjs`, `scripts/seat-lint.mjs`, `scripts/merge-event-check.sh`,
`config/settings-permissions.json`, this file.

`fort-init` renders the trees `fort/`, `scripts/`, `claude/` (to `.claude/`) and
`docs/` whole. A file added under one of them is installed by being there.
`__FORT_SLUG__` in a file name becomes the fort's slug.

A founded fort's verifier runs every machinery step and then fails at
`product-gate`, on purpose, until the fort wires its own build and tests.
