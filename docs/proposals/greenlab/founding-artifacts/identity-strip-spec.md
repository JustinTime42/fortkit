# Identity-strip tooling spec (P4)

**Install-ready founding artifact.** Specifies the mechanical half of the identity
strip the Regent runs in Sitting A after copying Proofdelve into the Greenlab tree.
The LLM half is P5 (`llm-identity-pass-prompt.md`); the human failsafe is the
founding moot (Sitting A7). This document specs a host-executed script; the Regent
implements it during Sitting A (it is enforcement-adjacent and runs unmasked).

## Why it exists

Standing order 12: **architecture ports between forts; identity never does.**
Copying Proofdelve's living tree drags its citizens, bead history, incidents,
annals, and fort-specific memory into Greenlab — all of which the rule forbids
from travelling. The strip removes them. This spec is the *detection and
narrow-substitution* layer; judgment stays human.

## Posture: detect exhaustively, rewrite almost nothing

The mechanical tool is **fail-closed on detection and conservative on mutation.**

- It **detects** every literal foreign-identity token in the tree, exhaustively.
  A file it cannot read is a **finding**, never a silent skip.
- It **auto-substitutes only a narrow safelist** of unambiguous, function-critical
  tokens (below). Everything else — names, personalities, provenance comments,
  anything requiring judgment — is **flagged, never auto-edited.** A mechanical
  tool that rewrote a citizen's name inside a rationale comment could corrupt
  meaning; the rule is detect-and-flag, and let the LLM pass (P5) and the human
  decide.

## The literal detection set

Grep the copied tree for every token below. Categories drive disposition.

**Registry and repo paths (SAFELIST — auto-substitutable):**
- `~/.claude/civilization.json` → the Greenlab registry path
- absolute production repo paths: `/home/justin/dev/ForgeOs`, `/home/justin/dev/longburn`, `/home/justin/dev/WWWW`, `/home/justin/dev/fortkit`, and their `-worktrees` siblings
- These are function-critical (the tree will not operate pointing at production paths) and unambiguous, so the tool rewrites them and records each rewrite in the report.

**Bead-id prefixes (FLAG):** `ForgeOs-`, `fortkit-`, `longburn-`, `WWWW-`. Every
hit is a reference to another settlement's history; reset to a Greenlab bead or
delete the rationale. Flagged, not auto-edited, because the *surrounding sentence*
usually needs rewriting, not just the id.

**Fort names (FLAG):** `Proofdelve`, `Manyhalls`, `Farlantern`, `Kithmason`, and
the capital's civilization name once chosen.

**Citizen names and actor ids (FLAG):** the roster as of founding — full names
(`Marrek Splitstone`, `Kethra`, `Tova Marrowassay`, `Saelin Stillmere`,
`Ilva Trueglass`, `Calder Sealbroken`, `Emrith Cairnwright`, and any others in the
production registry at strip time) and their lowercase actor ids (`marrek`,
`veyra`, `kethra`, `tova`, `saelin`, `ilva`, `calder`, `emrith`). **This list is
regenerated from the live production registry and seat files at strip time, not
hardcoded** — a name added to production after this spec was written must still be
caught. The tool reads `~/.claude/civilization.json` and each fort's `fort/seats/`
to build the set.

**Edict / ceremony artifacts (FLAG):** paths under `civ/`, `fort/annals/`,
`fort/handoffs/`, `fort/memory/facts/`, `.beads/` carried in from Proofdelve —
these are records, not architecture, and mostly should not have been copied at
all; the report lists them for deletion.

## Outputs

Two artifacts, both under the Greenlab tree's strip-report directory:

1. **Machine-readable report** (JSONL, one record per hit):
   `{file, line, matched_token, category, action}` where `action` is
   `auto-substituted | flagged | unreadable`. This is the input to the P5 LLM
   pass (it reads the flagged set with full file context) and to the Sitting A
   exit-gate review.
2. **Human-readable summary:** counts by category, the full list of
   auto-substitutions made (so the Overseer can audit every rewrite), the flagged
   set, and any unreadable files. The summary is what the Overseer signs off in
   the Sitting A gate.

## Properties the tool must have

- **Exhaustive over the tree.** It walks every tracked and untracked file; binary
  files are checked for the literal set too (a name can hide in a compiled fixture).
- **Deterministic and re-runnable.** Running it twice on the same tree produces the
  same report; running it after dispositions shows the shrinking flagged set. It is
  the instrument for the "no foreign identity survived" review, so it must be
  trustworthy on repeat.
- **Read-plus-safelist-write only.** It reads everything and writes only the
  safelist substitutions and its own report. It never edits a flagged hunk.
- **Fail-closed.** An unreadable file, a walk that errors, or a safelist
  substitution that cannot be applied is a loud finding that blocks the gate, not
  a skip. The whole point is that the review can trust "the flagged set is empty"
  to mean "there is nothing left the tool can see," so the tool must never quietly
  see less than the whole tree.

## What it deliberately does not catch (hand-off to P5)

The mechanical scan finds strings. It cannot find:

- **Personality and voice** — prose written in a specific citizen's manner.
- **Implicit references** — a comment about "the finding that stopped the mill"
  that names no bead, an example that assumes Proofdelve's real-estate product,
  tone that belongs to one occupant.
- **Entangled hunks** — a launcher line that is architecture and identity at once.

These go to the LLM identity pass (P5), which reads the flagged set and the
seat/charter/prose files with full context and proposes dispositions for a human.
And because neither layer is proven complete, the founding moot (A7) is told the
tree may still carry placeholder Proofdelve identity to replace — the failsafe of
last resort, turning residual risk into a task the founding citizens own rather
than an assumption that the strip was total.
