---
key: cycle13-write-boundaries
status: active
superseded-by: null
tier: core
scope:
  seats: [all]
  topics: [seat-sandbox, constitution, charter, verifier, forge.sh]
  beads: [fortkit-i4y, fortkit-6ovg, fortkit-52vf.9]
provenance:
  source: "fort/charter.md gate 1 + 'Prose gates' as amended 2026-08-12 (cycle 13, fortkit-52vf.9); supersedes cycle7-write-boundaries; Warden blocking finding 2 on that edict"
  declared-by: emrith
  date: 2026-08-12
  origin: trusted
---
attended seats (Mayor, Warden) have fort/charter.md and fort/seats/ PROSE-gated
(Overseer prior approval on the amendment bead, charter.amended emitted), NOT
kernel-RO. kernel-RO to every masked seat: fort/profiles/, .claude/ (including
civilization.json, skills/, commands/, plugins/), host-executed scripts —
fort/scripts/ WHOLE, WITH NO verify.sh EXCEPTION — bin/, civ/scripts/,
civ/profiles/, .git/config + .git/hooks. The verifier the fort evolves is
scripts/verify-impl.sh: writable to the Mayor, kernel-RO to the Forge by an
explicit carve-out, RO to the Warden because she binds her whole checkout.
fort/scripts/verify.sh is only a shim and exits 70 if the implementation is
missing. The Forge alone keeps the full lock, charter and seats included.
Masks bind AT LAUNCH: a change here reaches no session already running.
