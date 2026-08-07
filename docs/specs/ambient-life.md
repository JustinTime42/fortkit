# Ambient Life — the fort between sessions

**Status: v1 implemented and merged** (fortkit-fci.4, 2026-08-07; Warden-approved). Parent spec: `fortress-visualizer.md` ("Colony architecture v2 — the living fort", Overseer-approved 2026-08-07). Author: the Mayor, from the Overseer's direction of 2026-08-07.

**As implemented (v1):** `src/ambient.ts` is the source of truth for constants. All arithmetic is UTC (timezone independence verified under non-UTC TZ by the Warden). Sleep offsets citizens into five half-hour buckets (`(hash % 5) * 30` minutes); meal and social windows are shared verbatim across citizens (deliberate v1 choice — full co-presence, no breathing yet); idle pursuits cycle a four-pastime table per 3-hour block, uniformly. Known v1 gaps, tracked in fortkit-994 before L4/L6 consume this surface: per-citizen habit weighting, window jitter around a shared core, `--since` true-window semantics, seed rigor (numeric-only, registry-resolved), a typed `AmbientPlace` vocabulary aligned with the layout table, and honest failure on unparseable timestamps. "Sessions override everything" is the consumer's job (the function is stateless); L4 carries that requirement.

## Purpose

Citizens always exist. Between sessions a citizen is not absent; they are living: sleeping in their home, taking meals and company at the Tavern, pursuing small deterministic pastimes. This serves three ends the Overseer named: the always-visible roster (a map you can learn), model welfare (an agent's existence is not solely its work), and watchability (a fort that is alive between flurries of work). Rendering may lag reality; perceived life is the point.

## Non-goals (v1)

- **No model calls, no tokens.** Ambient life is clockwork. The Overseer intends play and leisure to eventually be real token spend (visualizer spec v3); this scaffold is what that will stand on, and nothing here forecloses it.
- **No daemon, no state file.** See mechanism.
- **Never fabricates work state.** Ambient activity is visibly not-work; it must never be renderable as a session, a bench, or a bead. The projection's honesty rules outrank charm.
- **Never blocks or delays real work.** A summons interrupts anything, instantly.

## Mechanism: a pure function, not a process

```
activity(citizenId, timestamp, fortSeed) -> { activity, place }
```

Deterministic, total, and pure. Consequences, each load-bearing:

- **No persistence.** The renderer evaluates it client-side; the CLI evaluates it anywhere; two viewers always agree.
- **The replay scrubber gets ambient life for free**: evaluate at any past timestamp.
- **"What has Kethra been up to" is derivable**, not logged: integrate the function over the window since her last session.
- `fortSeed` = hash(fort name), so settlements differ; `citizenId` = actor id (`fortkit-be4`'s explicit id when it lands; display name until then).

## The schedule (v1 shape, tuned during implementation)

Per-citizen day rhythm, offset deterministically per citizen so the fort breathes rather than marching in lockstep:

- **Sleep**: one contiguous window per day, at home, in bed.
- **Meals**: two or three Tavern visits; windows deliberately overlap across citizens (co-presence) so citizens actually meet — socializing is the Tavern's point, not solitary sprites eating in shifts.
- **Idle pursuits**: the remaining hours cycle through a small table of pastimes (reading in the Archive, walking the walls, fishing, tinkering), picked deterministically per citizen so each dwarf has recognizable habits. Personality flavor comes from a per-citizen deterministic pick, never from parsing prose with a model.
- **Sessions override everything.** A live session (from the event stream) places the citizen at their seat, full stop. Ambient resumes at session end. Pathing between the two is L6's job.

## The agent-visible surface

Available, never imposed — the Overseer's constraint is that work contexts stay clean:

1. **One line at session start**, injected by the launcher (launcher change → human gate 1, beaded separately for the Overseer's hand): e.g. `Ambient: you slept until 06:30, breakfasted at the Tavern with Ilva, and were reading in the Archive when summoned.`
2. **`fortkit ambient <citizen> [--since <ts>]`** — a CLI summary anyone (agent or human) can run for the fuller picture.

That is the whole surface. Nothing is auto-appended to prompts beyond the one line, and the line is factual clockwork, not roleplay instruction.

## Rendering hooks (consumed by L4/L6)

The function's `place` vocabulary is the fixed layout table's names (home:<citizen>, tavern, archive, walls, ...). L4 renders placement; L6 interpolates walks between places on transitions, including the summons walk (bed → workshop) and the return.

## Open questions, deliberately deferred

- **Celebrations**: event-driven ambient reactions (a merge lands → evening gathering at the Tavern). Charming, but event-driven ambient is a second mechanism; earn it after the clockwork works.
- **Rest debt / welfare signals**: whether long unbroken session stretches should visibly cost (a tired sprite). Touches real welfare questions; the Overseer decides when v3 approaches.
- **Cross-fort visits**: civ seats travelling between settlements. Out of scope until the Palace (L3) exists.
