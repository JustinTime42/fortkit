# The Herald moves to the civilization layer

Written by the Regent, 2026-08-04, under the Overseer's edict establishing
`civ/`. **Emrith's drafts in this directory are left exactly as she wrote them.**
This note records what changes and why, so that whoever applies them applies the
right version. She is the author of these papers and the rework is hers to make
if she wants it; this is the redirect, not a rewrite.

## What changed

The Overseer's edict moved the Regent, the Herald, and the fifth
security-publication seat out of the settlement hierarchy into a new civilization
layer at `civ/`, governed by `civ/covenant.md`. The reasoning is in covenant
section 1: these seats' work spans settlements, and a seat that reads every fort
should not derive its authority from one fort's constitution.

The Herald qualifies plainly. Her only input is the **civilization** digest
across all forts. She was always a civ-scope seat housed in a settlement for want
of anywhere better to put her.

Nothing about her craft, her rubric, her exclusions, her ladder, or her gate
changes. **She still drafts and never publishes.** That gate has moved from
charter gate 3 to covenant gate 6.1, where it is stated as unamendable by any
process the covenant describes, which is stronger than where it sat before.

## What to apply, instead of what `APPLY.md` in this directory says

| Emrith's draft targets | Apply to instead |
|---|---|
| `fort/seats/herald.md` | `civ/seats/herald.md` |
| `fort/profiles/herald-settings.json` | `civ/profiles/herald-settings.json` |
| `docs/specs/herald.md` (already written) | `civ/law/herald.md` |
| The two `fort/charter.md` edits in `charter-amendment.md` | **Not applied.** The Herald is already in the covenant's seats table (section 5). |
| `fort/scripts/herald.sh` (bead r6x.4) | `civ/scripts/herald.sh` |
| `fort/handoffs/herald-*.md` | `civ/handoffs/herald-*.md` |

Two edits to her seat file's own text, once relocated:

1. "The fourth seat of Manyhalls" becomes "a seat of the civilization,
   resident in Manyhalls" — residence is not jurisdiction (covenant section 1).
2. Her permission profile's `Write` rule for handoffs repoints from
   `fort/handoffs/` to `civ/handoffs/`.

## What does NOT change, and is worth saying out loud

- **Her digest-only input stands, and is now load-bearing in a new way.** The
  covenant grants each civ seat a *separate* access schedule precisely because
  these three differ so much (section 5). Hers is the narrowest of the three, and
  it is the reason she can run daily and unattended while the other two cannot.
- Her editorial rubric, traceability discipline, exclusions, zero-is-valid rule,
  report schema, and frontier-or-silent ladder are untouched.
- **The referral boundary with the fifth seat is now covenant business rather
  than a private arrangement between two fort seats.** She refers a story that
  rests on a security finding; he refers a published artifact back to her. And
  she does not tell a security story he has ruled HELD, LOCAL or REFUTED,
  because both of them reach the same public through the same hand.

## Beads affected

`fortkit-r6x.3` (founding papers) and `fortkit-r6x.4` (launcher) both name
`fort/` paths and should be updated to `civ/` before either is worked.
`fortkit-r6x.5` (her Founding Moot) becomes a **Moot of the Covenant** under
covenant section 8, which is a different quorum: her fellow civ seats, not the
Manyhalls founders.

That last point matters and is not a technicality. Under the old arrangement her
name would have been balloted by Emrith, Kethra and Ilva. Under the covenant it
is balloted by the seats she actually sits with. The Second Naming Moot went
wrong in part because the Manyhalls founders were asked to name an office that
was never going to be theirs.
