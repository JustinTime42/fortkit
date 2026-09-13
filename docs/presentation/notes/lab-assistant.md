# The AI lab assistant (workshop-scaling idea)

**Problem it solves:** one facilitator can't coach ~25 people at mixed skill
levels. Precedent (higher-ed research) is clear that active instruction scales to
larger rooms when TAs absorb the real-time questions; the AI-as-TA variant adds
per-learner differentiation (scaffolding for strugglers, enrichment for advanced)
at zero marginal cost. This is the direct fix for the facilitator-ratio
constraint in facilitation.md.

**Why it's on-brand, not a gimmick:** a workshop about agent harnesses, run on a
grounded Claude assistant the presenter built, is the thesis demonstrated. "Here's
how I built the lab assistant" can be a 5-minute segment, and it ties to goal 1
(writing yourself out of the loop).

## Support tiers

- **L0 — the worksheet:** self-serve, binary-checkable steps ("did it print?
  yes/no"). Most people never ask anything.
- **L1 — the assistant:** setup help, "stuck on step 3," error decoding, concept
  questions. Absorbs the bulk of questions, in parallel, for everyone at once.
- **L2 — the humans:** Justin plus 2-3 helpers recruited from the tinkerers.
  Only what the assistant escalates or can't answer. Colored card = L2 needed.

## The risk that is also the lesson

An AI assistant will confidently hallucinate about the exact version-specific
permission behavior this workshop teaches people NOT to trust. We watched the
bushwise-session model do exactly this (overclaimed the mechanism, then walked it
back). Handle it two ways at once:

1. **Ground it hard where reliability matters.** Custom instructions: "Answer
   setup, command, version, and exercise questions ONLY from project knowledge.
   If it's not in the knowledge, say so and tell them to raise a card. Never
   invent a version number or command behavior."
2. **Make its fallibility a stated objective.** Tell participants: "This assistant
   is grounded in my notes. Ask it something outside them and it may confidently
   make something up, exactly like the demo. Learn to catch that." Liability
   becomes the lesson.

## Other risks

- **Privacy (critical for a security workshop):** warn loudly, never paste a real
  `.env` or secret into the assistant. Decoys only.
- **Crutch effect:** keep people paired so peer learning survives; the assistant
  supplements the room, it doesn't replace it.
- **Staleness:** the permission layer moves between releases. Pin the version in
  the knowledge and date it; re-check before each run.

## Distribution (the genuinely tricky part)

Everyone has a Claude subscription, but a personal Claude Project does not share
cleanly to a public crowd outside your workspace. Options, best-fit-for-a-public-
room first:

1. **Published Artifact that embeds the knowledge and calls Claude at runtime**
   (the "ask Claude" artifact capability). One URL / QR code, zero per-person
   setup, works for anyone with the link, maximally on-brand. Best IF that
   capability is enabled for the account and rate limits hold. VERIFY the
   artifact-capabilities roster before committing.
2. **Paste-in starter prompt / uploadable knowledge file** people drop into their
   OWN Claude or own Project. Universal, any plan, ~2 min per-person setup. The
   reliable fallback.
3. **Personal Project screen-shared** as a single L1 queue. Simplest to build but
   does not parallelize (one queue), so MVP only, not the goal.

**Recommendation:** build the knowledge base once (same material either way);
deliver via (1) with (2) as backup. Prototype as a Project first (fastest to
iterate instructions + knowledge), then port to the artifact.

## Knowledge base contents (most already exists in docs/presentation/)

- The demo matrix, version-pinned (demo-mechanics.md).
- The enforcement vocabulary (docs/specs/enforcement-vocabulary.md).
- The exercise worksheet (to be written).
- FAQ + common-errors-and-fixes + OS-specific notes.
- A "facts to state confidently vs. defer on" list.
- The facilitation flow, so it knows which exercise the room is on and what
  people should be seeing, and can triage escalations.

Effort: a few hours, and it doubles as Justin's own prep.

## Bonus payoffs

- **Reusable asset** the ambassadors keep for future workshops (a gift to the
  program).
- **Differentiator to mention to Kyle:** "I run it with an AI lab assistant so a
  mixed-skill room keeps moving."

## Open decisions

- Which topic the workshop lands on (gates what knowledge to load).
- Whether the artifact "ask Claude" capability is available and rate-limit-safe
  for the expected headcount.
- Whether to make "how I built this assistant" an explicit segment of the talk.
