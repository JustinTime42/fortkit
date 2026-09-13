# Anchorage Claude Meetup — presentation / workshop prep

Working directory for a possible talk or workshop at the Anchorage, AK Claude
meetup (run by Kyle and Blythe Easterly of Delve Group; ~20–30 attendees). The
direction is not decided yet. This dir holds the raw thinking, the demo
material, and the outreach so we can refine it as the idea develops.

Status as of 2026-09-12: **pre-pitch.** Justin plans to run the idea past the
organizers first to gauge interest and get slot length, laptop/OS mix, and
audience depth before committing to a direction.

## The one-line thesis

Everyone is showing what their agents *can* do. The interesting flex, after the
OpenAI/Hugging Face incident and Anthropic's own three disclosures, is showing
what your agents **can't** do, and how you know. The talk is the sequence of
measured failures that forced each control into existence.

## Contents

- `notes/pitch.md` — the angles (security / context / orchestration), the
  framing, audience and format thinking, what to keep small.
- `notes/outreach.md` — the message to the organizers (final draft) and the
  questions we need them to answer.
- `notes/demo-mechanics.md` — the technical heart: the `.env` guardrail bypass,
  what the current version catches vs misses, the two-layer architecture, the
  changelog history, the two-act demo structure, and the caveats that keep the
  live demo from backfiring.
- `transcripts/bushwise-bypass-2026-09-11.md` — the demo-replay artifact
  (redacted). The verbatim `.raw.jsonl` beside it is **gitignored** because it
  carries live-looking keys.

## Handling note (important for a security talk specifically)

The raw bushwise transcript contains `service_role` JWTs and Google Maps keys
that got read out during the bypass demo. Justin states they are dead/decoy. The
committed transcript redacts them to placeholders; the unredacted `.raw.jsonl`
is gitignored. Before any public showing, confirm those keys are actually rotated
server-side (the JWT `exp` decodes to 2036, so they are not time-expired), or
re-record the demo against fresh decoy keys. Don't let the security talk leak a
secret.
