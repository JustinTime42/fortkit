# Prep sheet: the conversation with Kyle & Blythe

Kyle and Blythe Easterly (Delve Group) are the Anchorage Claude Community
Ambassadors. Most logistics and program-leverage answers live with them. This
sheet arms the conversation: questions grouped by purpose, each with *why it
matters* and *my current default* so you're never asking blind, plus a short list
of what's already decided so you can speak with a plan in hand.

Order to run the conversation: (1) confirm they're interested at all, (2) the
audience read, (3) logistics, (4) program leverage, (5) the disclosure heads-up.

---

## 0. What's already done (say this, so it lands as "prepared, not fishing")

- A clear thesis: "everyone shows what their agents can do; I'll show what mine
  can't, and how I know," anchored to the OpenAI/Hugging Face incident and
  Anthropic's own three disclosures.
- A live, reproducible demo: a permission deny rule failing on the current
  Claude Code version, and the kernel-sandbox fix that holds. Recorded backup.
- A hands-on exercise that works on any laptop: attendees watch their own deny
  rule get bypassed on their own machine, then classify the controls in their
  own config. Self-checking, no 1:1 coaching required.
- A facilitation plan sized for a big mixed room (pairing, helpers, stretch
  tasks, a debrief harvest). See facilitation.md.

Ask for their read on it. You're bringing a plan to pressure-test, not a blank.

## 1. Are they even interested? (the gating question)

- Is a nuts-and-bolts / security-and-harness talk something you'd want on the
  calendar, and is it right for this group?
  - *Why:* everything else is moot if no. Also surfaces whether the room wants
    depth or stays high-level.
  - *My read:* they asked for more presenters and prefer workshops, so a
    hands-on session is squarely what they want; the open question is depth.

## 2. Audience read (only they know this)

- What's the rough skill mix: mostly claude.ai users, daily Claude Code users,
  or people who've tuned settings.json and hooks?
  - *Why:* decides how much the hands-on exercise can assume. My format assumes
    at least a third can run Claude Code; if it's mostly browser users, the
    exercise shifts toward threat-modeling on paper.
- You mentioned wanting more presenters. Most talks so far have been "what I
  built," not much on how people keep Claude on the rails or context fresh. Is
  that because the group hasn't wanted the how, or because nobody's offered?
  - *Why:* directly answers the depth question and whether this topic fills a gap
    or misses the room.
- Any topics that have clearly landed well or fallen flat before?
  - *Why:* free calibration from people who've watched this exact room react.

## 3. Logistics (only they know this)

- How long a slot? (20 min vs 60+ min are different deliverables.)
  - *Default:* I've built a 60-min run-of-show that compresses to 30 (demo +
    one exercise).
- Do people usually bring laptops and open them during sessions?
  - *Why:* decides workshop vs demo. *Default:* if unsure, I design so the demo
    stands alone and the exercise is a bonus for those who brought a laptop.
- OS mix, roughly: Mac / Linux / Windows?
  - *Why:* the kernel-sandbox exercise is Linux-only. *Default:* core exercise is
    OS-agnostic; bwrap is a Linux-only stretch track regardless.
- Headcount you expect, and would I be the only one up front?
  - *Why:* 20-30 with one facilitator is above the coaching ratio; I'll recruit
    helpers and use self-checking exercises, but I want to know the number.
- Room and A/V: projector/HDMI, screen for a terminal, reliable wifi, power at
  seats?
  - *Why:* a live terminal demo needs a readable screen and, for the exercise,
    wifi that survives 25 people hitting the API. Power at seats matters for a
    hands-on hour.
- What's the cadence and how far out is the next open slot?
  - *Why:* sets the prep timeline and whether I aim for the next one or a later
    one with more runway.

## 4. Program leverage (the ambassador angle)

- Since you're ambassadors: is there Anthropic-provided content, slide
  templates, or a workshop format I should align with or can reuse?
  - *Why:* saves work and keeps it consistent with what the program expects.
- The exercise has ~25 people running Claude Code at once. Can the program's API
  credits or an Anthropic resource cover that, or should people use their own
  accounts?
  - *Why:* a room full of live API calls needs a cost/auth answer. *Default:*
    attendees use their own auth; the exercise is cheap (a few small calls).
- Is there anything the program wants from a session like this: feedback capture,
  a particular framing, a shout-out, photos, a writeup?
  - *Why:* ambassadors report back to Anthropic; knowing what they need makes you
    an easy speaker to say yes to.
- Swag / promotion: anything I should feed into the event listing or social push?

## 5. The disclosure heads-up (raise it yourself, don't spring it)

- The honest version of this talk shows Anthropic's built-in guardrails *failing*
  live (a deny rule bypassed, the auto-mode classifier missed), before showing
  the fix. It's constructive (defense-in-depth, Anthropic is actively hardening
  this per their changelog), but it's pointed. At an ambassador-run,
  Anthropic-affiliated event, are you comfortable with a critical-but-constructive
  security talk, and is there framing you'd want?
  - *Why:* this is the one item that could be awkward if sprung. Ambassadors have
    a relationship with Anthropic; give them the call on tone and depth. Better
    to raise it now than surprise the room.
  - *Related, still your (Justin's) decision:* whether to name specific open
    findings and the exact version behavior. My read: it's the strongest
    material and the framing is easy, but confirm the room and the relationship
    are fine with it first.

---

## After they answer, these unlock

- Final format and run-of-show (slot + laptops + OS).
- Whether to build the clone-able workshop kit or just slides + demo.
- The attendee setup gist (send ~48h ahead).
- Whether a dry run against me is worth doing, and when.
