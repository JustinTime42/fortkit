# Proposed amendment: Herald law, the weekly arc

Bead: fortkit-r6x.8.6 (gate-1). Drafted by the Mayor 2026-10-07 from the
adopted spec `docs/specs/herald-arc.md` (Overseer approval 2026-10-07, Warden
APPROVE-WITH-FINDINGS, findings applied). Target: `civ/law/herald.md`. It
amends like the charter (law section 10): Warden review of this text, then the
Overseer's signature, then applied with `charter.amended`. The launcher mode,
lock and timer follow by Regent edict and are not law.

## Change 1: section 3, outputs, append to the vault layout

> - `rewrites/YYYY-MM-DD-<slug>.md`: cold-reader rewrites of older drafts,
>   frontmatter as for any draft plus `rewrite_of:` naming the original. The
>   original file is never edited.
> - `reports/arc-YYYY-MM-DD.md`: one per weekly arc run (section 9a). The
>   `arc-` prefix is load-bearing: the daily run takes its window from the
>   newest report named exactly `YYYY-MM-DD.md` and ignores every other name.
>   *(Added 2026-10-07, fortkit-r6x.8.6.)*

## Change 2: section 7, the volume paragraph, replaced whole

Current text: "Until the weekly arc mode exists (fortkit-r6x.8.6), at most one
draft per run, and only a story that would rank in the week's top three."

> At most one draft per daily run, and only a story that would rank in the top
> three of the newest arc report's ranking, or, before the first arc run, in the
> Herald's own judgment of the week's top three. The cap is permanent; the arc
> run gives it a reference. *(Amended 2026-10-07, fortkit-r6x.8.6.)*

## Change 3: new section 9a, inserted after section 9

> ## 9a. The weekly arc
>
> Once a week, in arc mode, the Herald does three things, any of which may be
> zero:
>
> 1. **One arc draft, or none,** at `drafts/YYYY-MM-DD-arc-<slug>.md` with
>    `kind: arc` and `window:` in its frontmatter: a post about a stretch of
>    time, normally the week, with a trajectory and a turn (where things
>    stood, what broke or was hard, what is different now). A list of the
>    week's incidents is not an arc. All five bars of section 4 apply. Novel is
>    judged against prior arc drafts as well as daily ones, and a daily story
>    may appear only as one beat of a larger shape. The one-mechanism rule of
>    the brand-voice document relaxes to two concrete examples, each with at
>    most one mechanism; every other limit stands.
> 2. **The ranking:** the top three drafts to post in the coming week, in
>    order, one line each on why. Eligible: a file in `drafts/` or `rewrites/`
>    whose `status` is exactly `draft` and that no file in `rewrites/` names in
>    `rewrite_of:`. Nothing posted, spiked or superseded is eligible.
> 3. **Up to two backlog rewrites** into `rewrites/`, under the same bars.
>
> **Window:** from the `Digest window` end of the newest `reports/arc-*.md` to
> now; if there is none, or its window cannot be parsed, the last seven days,
> with the fallback named under Gaps. **Inputs** are those of section 2, plus
> the window's daily reports and drafts. A prior Herald report is a pointer to
> the record, never the record itself; section 5 applies unchanged.
>
> **The report** is `reports/arc-YYYY-MM-DD.md` with sections: Window, Arc
> candidates considered (scored), Draft filed, Ranking for the coming week,
> Backlog rewrites, Gaps and anomalies, For the Overseer. Section 8's guarantee
> holds: a report every run, a crash stub if need be. If the turn cap cuts the
> run short, the report comes before the draft and the rewrites.
>
> **Never two at once.** A daily run and an arc run never work the vault at the
> same time. The launcher enforces this with a lock; if the Herald ever finds
> evidence of a concurrent run, it is an anomaly reported by name.
> *(Added 2026-10-07, fortkit-r6x.8.6, Overseer decision.)*
