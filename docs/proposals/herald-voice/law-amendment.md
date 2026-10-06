# Proposed amendment: Herald law, "Postable" and declared stakes

Bead: fortkit-r6x.8.2 (gate-1). Proposed by the Mayor 2026-10-06.
Target: `civ/law/herald.md` sections 3, 4, 5, 6, and `civ/seats/herald.md`
Laurels. Law section 10: amends "like the charter", so Warden review, then
the Overseer applies or directs it applied.

## The need (law section 10 asks for one)

Measured 2026-10-06 against all 61 drafts in the vault: 44 exceed LinkedIn's
3,000-character post limit (median 3,835; August median ~3,070, September
~4,390), so section 3's "ready to paste" is unmet for most of them. 2 of 61 end
on a question. No brand-voice document existed for any of the 54 runs. The
Overseer's own post analysis (Obsidian Vault/Sifa/brand-voice/) finds his
technical posts without a personal stake are his weakest. Overseer decisions
the same day: adopt a craft bar; allow invented personal stakes, declared, for
him to edit before posting (provisional); raise the bar on volume.

## Changes

**Section 3, drafts bullet.** After "Body is the post text, ready to paste."
add: "Ready to paste means it clears bar 5. A draft may carry a `## Long
version` section after the post; bar 5 does not apply to it and it is never
part of what gets posted. Frontmatter gains `invented:` (section 5) and
`postable:` (one line per bar-5 check with its result)."

**Section 4, add bar 5:**

> 5. **Postable.** The post (excluding any long version) is at most 1,500
>    characters with a hook of at most 140; no paragraph exceeds three
>    sentences; it ends on a question a practitioner could answer about their
>    own work; zero em-dashes; zero contrastive reframes; none of the banned
>    phrases in the brand-voice document. Thresholds other than these come
>    from the brand-voice document. A story that clears bars 1-4 and fails 5
>    is rewritten until it passes, or spiked with the reason in the report.

Amend the opening line "only if it clears all four bars" to "all five bars".

**Section 5, append:**

> **The declared-stake exception** (Overseer decision 2026-10-06,
> provisional). The Overseer's personal stake in a story, meaning his reaction
> to it or what it cost him, may be invented when the record carries none.
> Every invented line is quoted exactly under the draft's `invented:`
> frontmatter key and counted in the report. Nothing else is exempt: figures,
> quotations, incidents and outcomes trace to the record as above. An invented
> line not declared is a defect of the same weight as an untraced figure.

**Section 6, replace the last bullet** ("Anything presented as the Overseer's
opinion...") with:

> - Anything presented as the Overseer's opinion that the record does not
>   support him holding, **unless declared under section 5's stake exception.**
>   The exception covers his reaction and stake in a story, not positions on
>   people, companies, or public questions.

**Section 6, voice constraints:** change "the 'that's not X, that's Y' reframe
at most once per piece and preferably zero" to "zero contrastive reframes
('not X, it's Y' in any wording); LinkedIn demotes the construction as of May
2026".

**Volume (new paragraph at the end of section 7):** "Until the weekly arc mode
exists (fortkit-r6x.8.6), at most one draft per run, and only a story that
would rank in the week's top three."

**`civ/seats/herald.md`, Laurels:** replace "Engagement metrics on published
posts belong to the Overseer's judgment, not this file, until a real need says
otherwise." with "Engagement metrics on published posts are an input to the
Herald from fortkit-r6x.8.5 onward; they inform his judgment and never move a
rubric bar, which only the Overseer moves."

## Out of scope here

The lint script (r6x.8.3), the long-version format details (r6x.8.4), and the
arc mode's own law section (r6x.8.6) amend separately.
