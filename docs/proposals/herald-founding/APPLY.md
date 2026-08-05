# Applying the Herald founding papers (fortkit-r6x.3, gate 1)

Three artifacts, applied by the Overseer's hand. Emrith verifies each after
application (standing order 5).

1. **Seat file:**
   `cp docs/proposals/herald-founding/seat-herald.md fort/seats/herald.md`
2. **Permission profile:**
   `cp docs/proposals/herald-founding/herald-settings.json fort/profiles/herald-settings.json`
3. **Charter:** apply the two edits in `charter-amendment.md` to
   `fort/charter.md` (a table row and an occupants-paragraph append; manual,
   since the charter is prose).

Then tell Emrith; she verifies all three, records it on fortkit-r6x.3, and
the moot (r6x.5) and launcher (r6x.4) unblock.

Design notes for review:

- **WebFetch/WebSearch and curl are denied.** The Herald writes from the
  record only (spec section 5); the "novel" bar is judged from training
  knowledge and her own prior drafts, not live browsing. If a real morning
  proves web context necessary, that is a spec amendment with the untrusted-
  input order applied, not a quiet allow.
- **No bd mutations.** Story ideas needing follow-up go in the report's "For
  the Overseer" section; the Mayor files any beads. One writer per record.
- **The vault is outside every repo**, so drafts never transit git and a bad
  draft cannot page the Warden. The report is the review surface, and the
  reviewer is you.
