# Outreach to the organizers

**Who:** Kyle and Blythe Easterly, Delve Group — run the Anchorage AK Claude
meetup (~20–30 people).

**Channel:** whatever they already use with attendees (Meetup message tool,
Discord/Slack, or email). LinkedIn DM is the fallback since Delve Group is a
business. Reach out while the evening is fresh.

**Medium:** LinkedIn DM to **Kyle** (already connected, prior contact). Short and
warm, not an email. Kyle and Blythe co-run it as ambassadors and are partners/
spouses, so no need to address both or offer to "loop Blythe in" — that's a given.

**Posture:** it's a note to someone he knows. First message has ONE job: a yes,
plus slot length and OS split. Lead with the concrete demo (strongest, most
repeatable thing), then a menu that explicitly flexes (one or a combination,
demo or full workshop) so Kyle can match it to the group.

**Known facts (don't ask these):** everyone brings a laptop; everyone's already a
Claude user. So the laptop question is dropped and the exercise can assume
hands-on. OS mix is still unknown and still matters (bwrap is Linux-only).

**Hold back until after he says yes / for the call:** the Hugging Face framing
(great for the talk, too much for a DM), the ambassador-leverage questions
(content templates, API credits), the disclosure heads-up (guardrails failing
live), and the open findings (y7no, oygr). See organizer-conversation.md; the
disclosure item is a gate-3 decision plus a tone call for the ambassadors.

## Message (current version — LinkedIn DM to Kyle)

This version leads with the three harness goals (autonomy / security / context)
rather than a single demo, and adds a "rarely done hands-on" line to justify the
workshop format. The autonomy-first framing tested better than a security-first
lead: "writes me out of the loop so I stay in flow" is felt by every Claude Code
user, where "orchestration" reads abstract.

> Hi Kyle,
>
> Thanks for hosting another excellent Claude meetup, both presentations were
> great. You mentioned wanting more presenters, and I've got something that might
> fit. Before I put time into it I'd like your read on what would land with the
> group.
>
> Over the last couple of months I've built a fairly elaborate harness around
> Claude Code and Codex with a few main goals:
>
> 1. Agent autonomy that writes me out of the primary loop. I feed in specs,
>    decisions, and unblock things as needed, and the harness continuously works
>    on whatever work is available asynchronously. This prevents the agonizing
>    waiting between LLM turns and allows me to stay in flow.
> 2. Security and safety. Permissions rules are entirely inadequate for true
>    production level, business critical software. I have demos ready showing
>    claude code defeating its own permission safeguards and engaging in risky
>    behavior. Despite cautionary tales like the OpenAI/HuggingFace fiasco and
>    others, we still are mostly focused on showing off what our agents can do.
>    In many ways a bigger flex is proving what our agents CAN'T do. I've been
>    doing research in tighter, provable, granular security guardrails like
>    kernel-level sandboxing and would love to show how we can have incredibly
>    capable agents without compromising safety and data security.
> 3. Context management and cross-session continuity: how the agents remember
>    what matters, forget what's stale, and hand off to the next session without
>    drift. Using a combination of databases, markdown files, and vector stores,
>    along with skills and hooks, we can ensure that we can start a new
>    conversation without losing critical context.
>
> Some of these topics have been covered in previous meetups, but not often in a
> really hands-on way that empowers participants to really get their hands dirty
> working and learning how to put these topics into practice.
>
> I would be happy to do a demo or workshop of one or more of these topics if you
> think they'd be helpful and interesting to the group.
>
> Justin

**Suggested tweak (not yet applied):** the "hands-on" paragraph has "really"
twice and stacks "hands-on" with "get their hands dirty." Tighter: "Some of these
topics have come up in previous meetups, but rarely in a hands-on way that lets
participants actually put them into practice."

**Optional polish (trivial):** "Permission rules" (not "Permissions rules");
capitalize "Claude Code".

**Accuracy note:** "defeating its own permission safeguards" is the corrected
claim. The earlier "bypassing all built-in safety systems" overclaimed; what we
have measured is the deny rule + auto-mode classifier defeated via glob, plus the
social-engineering bypass. Keep the softened wording.

Prose check: zero em-dashes; the "what our agents can do / CAN'T do" contrast is
the thesis, stated once, not the banned reframe.

## Optional line if pitching the "what agents can't do" hook harder

> Since the OpenAI/Hugging Face incident and Anthropic's own disclosures,
> everyone's showing what their agents can do. I'd like to show what mine can't,
> and how I know.

## Optional line to settle the depth question

> One thing I noticed: most of the talks so far have been about what people
> built, not much on how they keep Claude on the rails or keep context from
> going stale. Is that because the group hasn't wanted it, or because nobody's
> offered? I'd want to pitch this at whichever level the room is actually at.

## What we need back from them (drives everything downstream)

1. Slot length (20 min vs 75+ min are different deliverables).
2. Do people bring laptops? (decides workshop vs demo)
3. OS mix Mac/Linux/Windows (decides whether bwrap is a live step or laptop-only)
4. Audience depth: mostly claude.ai users, daily Claude Code users, or
   hook/settings tinkerers? (Format A assumes the last group is >= a third)
5. Which angle interests them for the group.

## My open questions for Justin (once organizers answer)

- Disclosure: is fortkit public? Comfortable showing open security beads and the
  Claude Code behaviour change at an event Anthropic staff may attend? (my read:
  it's the best material and the framing is easy, but it's gate 3 and yours)
- Deliverable: slides, a clone-able workshop kit repo, or both? (kit = a Forge
  lane + Warden review; slides = a spec + Mayor)
- How much culture to show: zero, a hook, or a theme?
- Dry run against me? And should the Researcher pull what others have presented
  on agent sandboxing so you don't duplicate a talk they've seen?
