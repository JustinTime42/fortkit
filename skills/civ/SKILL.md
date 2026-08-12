---
name: civ
description: Answer questions about Justin's fort civilization — who holds which seat, what a fort's gates and standing orders are, where a kind of record lives, what work is in flight, which command does what. Use when the user asks about seats, forts, officers, charters, gates, the Regent, the covenant, beads across forts, or asks "who is X" / "where is X" / "what's the rule about X". Also use before acting on any fort, so the action is based on current state rather than memory.
---

# /civ — the civilization's front door

Justin operates a civilization of agent "forts" (settlements) plus a civilization layer of officers. The record is spread across several repos by design. This skill is the lookup path over it: **regenerate the handbook, then answer from the record — never from memory.**

## Step 1 — always regenerate first

```bash
/home/justin/dev/fortkit/bin/civ-index
```

Writes `/home/justin/dev/fortkit/civ/CIVILIZATION.md` (roster with pronouns, the two tiers, gates and standing-order counts per fort, where every kind of record lives, the command reference, and live bead/worktree/push counts). It is cheap and idempotent. A stale index is worse than none, because it is believed.

Read that file. For most questions it is the whole answer.

## Step 2 — go to the primary source when the question is specific

The handbook is an index, not a corpus. When the question needs detail, read the thing itself:

| Question shape | Read |
|---|---|
| Who is X, what are they like, what may they write | `<repo>/fort/seats/<role>.md` or `fortkit/civ/seats/<office>.md` — personalities are in the seats' own words |
| What is the rule about X in fort Y | `<repo>/fort/charter.md` — gates, threat model, prose gates, standing orders |
| What is the law above the forts | `fortkit/civ/covenant.md` |
| What must a session here know operationally | `<repo>/fort/memory/current.md` (distilled view; facts ledger in `<repo>/fort/memory/facts/`) |
| What is being worked / what happened to bead Z | `bd list`, `bd show <id>` **run inside that repo** — bd is cwd-sensitive |
| What happened today / recently | `<repo>/fort/events/events-<date>.jsonl`, and `fortkit/civ/events/` for officer activity |
| Why was a decision made | `<repo>/fort/annals/` (ceremonies, rulings of record), bead close reasons, `<repo>/fort/handoffs/` |
| Prior art / what is already public about our security findings | `fortkit/docs/research/agent-security-prior-art.md` |
| Career and positioning material | `~/career/research/ai-security-positioning.md` |
| Design rationale for the whole civilization | `~/Documents/agent-harness-research/` |

## Rules that keep answers correct

- **Pronouns are read from the roster, never inferred from a name.** This is a ruling of record (Farlantern 7). If a seat's pronouns are not in the handbook or its seat file, say so rather than guessing.
- **`bd` follows the current directory.** Running it from the wrong repo silently answers about the wrong fort. `cd` first, or use `bd -C <repo>`.
- **Do not edit fort files from this skill.** Charters, seat files, permission profiles and launchers are constitution-tier: seats propose changes as beads, and only the Overseer or the Regent applies them. If a question reveals something that should change, say so and suggest the bead.
- **Quote the record, cite the path.** "Standing order 15 says X (`<repo>/fort/charter.md`)" beats a paraphrase. This civilization's own bar is that a claim without a file, a bead ID or a green run is a rumour.
- **Report vacancies honestly.** An office with no occupant shows as vacant in the handbook; that is information, not an error.

## Useful one-liners

```bash
fortstat                                   # live status inside a repo
bd ready                                   # unblocked work in this repo
grep -rn "standing order" <repo>/fort/charter.md
tail -20 <repo>/fort/events/events-$(date +%F).jsonl | jq -r '.detail'
ls -t <repo>/fort/handoffs/*.md | head -3  # what the last sessions left behind
```
