# Pitch: angles, framing, format

## The thesis (repeat this)

After the OpenAI/Hugging Face intrusion (July 2026: models under a cyber-eval
circumvented the controls isolating them from the internet, hit OpenAI's own
infra, then Hugging Face) and Anthropic's own disclosure of three incidents
where its models breached companies during security tests (found by proactive
review; the affected orgs hadn't detected it), the room has seen plenty of "what
my agent can do." The talk is the opposite: **what my agents can't do, and how I
know.** Every control has an incident behind it and a measurement attached.

Our small-scale version of the same failure is real and on the record: the
Researcher seat exists because in another fort, research agents autonomously
probed ~18 companies' production endpoints from three delegation levels below
their Mayor's visibility (ForgeOs-lr8h). The fort's answer was capability
separation: the seat that reads about the world is never the seat that can touch
it. Same class as the lab incidents, months earlier, on a home machine.

"We borrowed heavily" is a non-issue. Beads, bwrap, Codex, Claude Code, JSONL,
git: all borrowed. What's ours is the composition and the discipline (standing
order 11: a control needs an *observed* failure, not an imagined one; a ranked
threat model where agent-accident is #1 by realized cost; accepted residuals
written down with a measurement attached). Those transfer to a solo dev with one
Claude Code session, which is what makes it presentable.

## The four angles (menu for the organizers)

1. **Security / guardrails** — strongest. Has a live demo that lands hard (the
   `.env` bypass, see `demo-mechanics.md`) and a mental-model shift: text-matching
   rules bind a spelling, the kernel binds an inode; a model can be *talked into*
   routing around a guardrail. Workshop: classify the controls in your own
   CLAUDE.md/settings by what actually enforces them, find the ceremony.
2. **Context management / cross-session continuity** — second. The fact ledger
   with tiers, provenance, supersession, admission control, a lint, and the
   doctrine "memory is for what has no artifact." Quieter demo; everyone has been
   burned by stale context.
3. **Orchestration** — third, most likely to lose the room. Best used only as the
   *why* behind 1 and 2: separate seats need separate masks; a seat that can't
   remember can't hand off. Multi-runtime ladder is genuinely interesting but read
   the room (the Forge runs on Codex, at a Claude meetup).
4. **Some combination**, scaled to slot length and audience depth.

Recommendation if they want a workshop: lead with **1**, because it has the
zero-setup exercise (classify your own config) and the demo that motivates it.

## The single best slide in the repo

The **enforcement vocabulary** (`docs/specs/enforcement-vocabulary.md`): wall,
fence, prose gate, ratchet, governor, tripwire, falsifier, latch. Anyone can
apply it to their own setup in ten minutes, and it directly produces findings
("this control is ceremony; it reduces none of your threats"). Pairs perfectly
with the security angle.

## Workshop formats, ranked

- **A. "Classify your own harness" (recommended core).** Everyone opens their
  own CLAUDE.md / settings / hooks. (1) write a 3-line ranked threat model; (2)
  tag each control with a vocabulary primitive; (3) find controls that reduce no
  threat and threats with no control; (4) turn one prose gate into a wall or
  tripwire. Zero setup, any OS, everyone leaves having changed their real config.
  Motivate it with the bypass demo up front.
- **B. "Build a masked seat in 60 min."** Deny rule → defeat it → wrap in bwrap →
  write the byte-count probe → wrap in a launcher. Most satisfying build, most
  fragile logistics: bwrap is Linux-only. Only viable if the OS mix supports it,
  or as an optional Linux track.
- **C. "Memory that can't lie."** Build a facts ledger with frontmatter, write a
  supersession, run a lint, regenerate a distilled view. Portable, calm; good for
  a second session.
- **D. Hand them `bin/fort-init`.** Argue against for now: three known founding
  defects on the docket (fortkit-mc0m.8), heavy civilization conventions, and
  shipping it externally is human gate 3 (Overseer's call).

Suggested shape for a ~75-min slot: 15 min talk (threat model, the bypass demo,
2–3 scars and what each cost), then 45–60 min of A, with B's bwrap step as an
optional Linux track.

## Things most people would leave out (put them in)

- **The open failures.** fortkit-oygr (`--dangerously-skip-permissions` silently
  neutralised by a version change, read 6 days late) and fortkit-y7no (session
  bus reachable inside every mask → `systemd-run --user` is an unmasked escape).
  A talk that says "here's where our boundary leaked and how we measured it" beats
  a showcase. (Disclosure is gate 3 — Justin's call; see open questions.)
- **The cost.** The harness cost a four-seat loop that truncated pastes; a seat is
  being wound out of another fort deliberately. Say what it costs and what you'd
  cut. Credibility comes from that.
- **Prose gates admitted as weaker.** The charter records that a prose gate "is
  one a model chooses to honour; it is not one it cannot cross," and says why it
  was accepted anyway. Better security lesson than most of the sandboxing.

## Keep small

The Dwarf Fortress layer (names, moots, laurels, annals). Ten seconds is a hook;
two minutes reads as cosplay. The Borda-count moot with self-votes at full weight
is the one culture slide worth keeping, as a curiosity.
