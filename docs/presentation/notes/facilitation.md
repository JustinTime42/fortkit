# How to run this: facilitation playbook

Synthesized from Anthropic's Community Ambassadors program, general Claude Code
workshop guidance (which is mostly written for paid team onboarding), and our
own material. The key adaptation: the standard guidance assumes a 3-hour paid
team session of 8-12 people doing real backlog work. Ours is a public meetup,
~20-30 mixed people, one evening slot, topic is security/harness not "learn to
use Claude Code." Principles port; the agenda does not.

## The ambassador angle (chase this first)

The Anchorage meetup is almost certainly run under the **Claude Community
Ambassadors** program (it exists specifically to "lead local meetups, run
workshops and demos"). That means Kyle and Blythe likely have, from Anthropic:
- **Event funding, swag, and promotion** through Anthropic's channels.
- **Ready-to-use content** (slide templates, demo material) you may be able to
  align with or borrow from.
- **Monthly API credits** to power demos, which matters if participants need to
  run Claude Code live.
- A **private ambassador Slack** where they can ask Anthropic questions.
- Early access to pre-release features and Builders Council feedback sessions.

Action items:
- Ask the organizers directly: are you ambassadors, is there Anthropic content
  I should align with, and can the program help with API credits / a room /
  promotion for a hands-on session?
- Justin could apply to the program himself (hands-on Claude Code experience is
  exactly the bar). Not required to present, but a natural fit and it comes with
  the content library and credits. https://claude.com/community/ambassadors

## What to expect (meetup realities, not a paid training)

- **Facilitator ratio is the hard constraint.** Quality 1:1 coaching drops above
  ~12 people per facilitator; you may face 25 with one of you. You cannot coach
  them individually. Design around it (below), don't fight it.
- **Setup friction eats time.** Some attendees won't have Claude Code installed,
  wrong Node version, auth not working. Unresolved, this consumes a
  disproportionate share of a short slot.
- **OS split is unknown and matters.** The bwrap kernel-mask exercise is
  Linux-only. Keep the *core* exercise OS-agnostic; make bwrap an optional track.
- **Mixed intent.** Some attendees build; some are curious users who've never
  opened settings.json. Include a level-0 rung that works for them.
- **Short slot.** Evening meetups usually give a speaker 30-60 min, not 3 hours.
  Compress hard; pick one exercise, not three.
- **Live demo can change under you.** Model behavior and the permission layer
  move between releases. Record a backup (see demo-mechanics.md).

## Design principles that DO port from the guidance

- **Cap non-interactive lecture at ~20% of the slot.** For 60 min that's ~12 min
  of talking, tops, before hands go on keyboards.
- **Live demo: don't over-rehearse; narrate the decision points.** Our demo is a
  guardrail *failing*, so a surprise is on-theme. When something behaves
  unexpectedly, think out loud. That visible reasoning is the actual lesson.
- **Exercise 1 must produce visible output the least technical person can reach
  in ~15-20 min.** Invisible outcomes demotivate. "I watched my own deny rule get
  bypassed on my own laptop" is visible and visceral.
- **Pair mixed skill levels** (one more technical, one less) for peer teaching.
- **Give skeptics the hardest task**: "find a bypass I didn't show." Channel
  resistance into stress-testing; they leave more convinced than passive folks.
- **Stretch task for fast finishers** so the tinkerers don't stall out.
- **Debrief + harvest.** Collect the bypasses people found and the ceremony they
  found in their own configs into a shared doc. That artifact is the takeaway.
- **Colored-card help signal** removes the awkwardness of raising a hand, and
  lets you triage a big room.

## Recommended run-of-show (tune to the actual slot)

Assumes ~60 min, ~25 people, laptops open. Scale down for a 30-min slot by
dropping to the demo + Exercise 1 only.

1. **Hook + threat model (10 min, talk).** The "what your agents can't do" frame,
   the Hugging Face / Anthropic-three-incidents context, and the level-0 ask:
   write a 3-line ranked threat model for your own Claude use. Works for browser
   users too.
2. **Live demo (10 min).** The two-act bypass: glob beats both filter layers,
   then the model is talked into using it. Punchline: the kernel mask is immune
   to both. Play the recorded backup if the room's setup isn't ready.
3. **Exercise 1 — "bypass your own deny rule" (20 min, hands-on).** Everyone
   plants a decoy `.env`, adds the `Read(./.env)` deny, and tries to read it three
   ways. They see the glob bypass on their own machine. Binary, self-checking
   ("did it print? yes/no"), OS-agnostic, no coaching required. Pairs help each
   other. Stretch: find a fourth bypass; Linux users try the bwrap byte-count fix.
4. **Exercise 2 — "find the ceremony" (10 min, if time).** Open your own
   CLAUDE.md / settings and tag each control by the enforcement vocabulary (wall
   / fence / prose gate / tripwire). Find one control that stops nothing and one
   threat with no control.
5. **Debrief + harvest (10 min).** Collect the bypasses and the ceremony people
   found. Land the thesis: agent-level permission rules are best-effort defense
   in depth; enforce at the OS/container level; keep secrets off the reachable
   filesystem. One commitment each: harden one real thing this week.

## Pre-workshop checklist to send attendees (~48h before)

Adapt the standard Claude Code setup list, kept minimal because the exercise is
config-level, not build-level:
- Claude Code installed and launching; auth/login working (or API key set).
- Node 18+ if relevant to their install (`node --version`).
- A throwaway scratch directory they don't mind messing with.
- Bring the exercise's copy-paste snippet: the `Read(./.env)` deny for
  `settings.json` and the `mktemp` decoy-env one-liner (from demo-mechanics.md).
- Explicit warning: use a DECOY secret, never a real `.env`.
- A no-install fallback: if Claude Code isn't working, pair with someone whose
  is, and still do the threat-model and find-the-ceremony parts on paper.

## Failure modes to pre-empt (from the guidance, mapped to us)

| Risk | Prevention |
|---|---|
| Too much slide time | Hard-cap talk at ~20% of the slot; one demo, not five |
| Setup eats the room | Pre-send checklist; recorded demo backup; pairing fallback |
| One facilitator, big room | Self-checking exercise; recruit 2-3 helpers from the tinkerers; colored cards |
| bwrap doesn't run on Mac/Windows | Core exercise is OS-agnostic; bwrap is an optional Linux stretch |
| Live demo misbehaves | Recorded backup against decoy keys; narrate surprises as the lesson |
| No lasting effect | Debrief harvest doc + one concrete "harden this week" commitment |

## Sources

- Claude Community Ambassadors — https://claude.com/community/ambassadors
- Claude Code best practices — https://code.claude.com/docs/en/best-practices
- "How to Run a Claude Code Workshop" (AdVenture Media) — team-onboarding
  structure, facilitation tips, failure modes
- claudeworkshop.com — mixed-skill pairing, colored cards, skeptic handling
