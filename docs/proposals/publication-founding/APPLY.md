# Applying the fifth seat's founding papers (fortkit-zud.1, covenant gate 4)

Drafted by the Regent under edict 2026-08-04. **Nothing here has been applied.**
Five artifacts, applied by the Overseer's hand. `<office>` is the title the
Second Naming Moot returned; substitute it lowercase in filenames and
capitalised in prose.

1. **Seat file:**
   `cp docs/proposals/publication-founding/seat-file.md civ/seats/<office>.md`
2. **Seat law:**
   `mkdir -p civ/law && cp docs/proposals/publication-founding/seat-spec.md civ/law/<office>.md`
3. **Permission profile:**
   `cp docs/proposals/publication-founding/seat-settings.json civ/profiles/<office>-settings.json`
4. **Covenant:** apply the two edits in `covenant-amendment.md` by hand (a seats-table
   row and a section-5 append). NO fort charter edits are made — see that file.
5. **Extraction plan:** `extraction-plan.md` stays where it is. It is a working
   document for the seat, not a constitution file.

Verification is NOT Emrith's. She is the Mayor of a settlement and has no
jurisdiction over a civilization seat (covenant section 1: residence is not
jurisdiction). The Regent verifies the application on its next wake and records
it on `fortkit-zud.1`; the occupant verifies his own access schedule on his first
run and files anything that does not match.

## Decisions the Overseer must make before or during application

These are collected on **fortkit-zud.8** and should not be inherited by default.

1. **The staging root.** The profile carries the literal string `PLACEHOLDER-STAGING-ROOT`
   and MUST NOT be applied as-is. It must be replaced with the chosen path in
   `seat-settings.json` (three allow rules) and in the
   seat file.
2. **Web access.** The draft profile denies `curl` and `wget` and does **not**
   allow `WebFetch`/`WebSearch`, matching the Herald. The argument for allowing
   them: the "already publicly known" bar genuinely cannot be judged offline, and
   at least one finding's corroboration is an upstream issue tracker. The
   argument against: web content is threat 2, prompt injection via untrusted
   content, and this seat holds broad read access across every fort — a worse
   combination than the Herald's. My own lean is to allow `WebSearch` only, deny
   `WebFetch`, and rely on standing order 8. But it is a real trade and it is
   yours.
3. **The public repo name** for artifact 1. Proposed: `holdfast` (recommended),
   `leashcheck`, `agent-sandbox-probe`. **Availability is unverified** and
   checking it precedes creating anything.
4. **Whether LOCAL-verdict findings may become labelled experience reports**, or
   whether LOCAL means silent.

## Design notes for review

- **The profile is wider than the Herald's on reads and narrower on reach.** He
  must read every fort's internals and run reproductions, which she must never
  do; he holds no path to the outside world, denying `gh`, `git remote`,
  `git push`, `git init`, `npm publish`, `ssh`, `scp`, `rsync` and `curl`.
- **`git add` and `git commit` are denied**, deliberately. His outputs live in a
  staging root outside every repo, so nothing he makes needs to transit git. The
  record corrections he owes under the REFUTED verdict go through `bd comment`
  and `emit.sh`, which are allowed, and through the Mayor for anything larger.
- **`bd create` and `bd comment` are allowed; `bd close` and `bd update` are
  denied.** He may file and annotate; he may not close another seat's work or
  overwrite a field. This also honours the near-miss recorded in the Mayor's
  2026-08-04-d handoff, that `bd update --notes` replaces rather than appends.
- **No timer, and that is the design.** See the seat law, section 9.
- **The same caveat as the Warden and Herald profiles applies and is written into
  the file's own comment**: deny rules bind a command spelling rather than a
  file, measured six-for-six in this civilization, so the profile is policy and
  the kernel mask is the boundary.
