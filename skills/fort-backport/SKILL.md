---
name: fort-backport
description: Propagate a proven fort improvement to every fort in the civilization plus the fort-init factory templates. Use when the user says "backport X", "propagate this to all forts", "run a backport cycle", or invokes /fort-backport. Reads ~/.claude/civilization.json for the fort list; applies per-fort transforms, commits each repo, emits events, updates the fortkit-or2 ledger.
---

# Fort Backport — civilization-wide upgrade propagation

You are executing one cycle of the fort upgrade pipeline (stage 3 "propagate" + stage 4 "codify" + stage 5 "ledger"). Canonical copy of this skill: `~/dev/fortkit/skills/fort-backport/SKILL.md`.

## Preconditions (check, don't assume)
1. The change is PROVEN: it landed in its origin fort through that fort's own gates (verifiers/Warden/Overseer). Never backport an unproven idea — "an order the factory does not yet obey is a claim without a green run."
2. The user invoking this skill IS the Overseer approval each fort's constitution gate requires. State in each commit that it was applied under Overseer direction.
3. Identify precisely: WHAT changed (files + transform), WHERE it came from (fort + bead/commit), WHY (one line of evidence).

## Step 1 — enumerate the forts
```bash
jq -c '.forts[]' ~/.claude/civilization.json
```
Per fort derive: `REPO` (`.repo`), `WT="$REPO-worktrees"`, `PROJECT` (`.project`). Skip the origin fort for changes it already has (verify, don't assume — check the actual file).

## Artifact classes that propagate (not just code)

1. **Scripts** (`fort/scripts/*.sh`) — patch by hunk, never overwrite: launchers diverge structurally per fort.
2. **Config** (`.claude/settings.json`, profiles) — targeted `jq` only.
3. **Prompt/behavioral law** — seat prompts inside launchers, seat-file protocols, verdict vocabularies, review discipline. A seat's *prompt* is as propagatable as its code, and a defect in it (e.g. a reviewer with unbounded blocking scope) reproduces in every fort running a copy.
4. **Charter law** — threat models, standing orders, gates. Append as amendments with their originating incident.
5. **Structure** (`bin/fort-init` additions).

**Ship fixes WITH the component, never after.** If a fort doesn't have the machinery yet (e.g. no `warden.sh` outside Proofdelve), the fix isn't a follow-up backport — it's a precondition of the first delivery. A component with a known open defect does not flow; fix it at origin, then ship the corrected version everywhere at once. The factory's entire value is that settlement N+1 never inherits a bug settlement N already found.

## Step 2 — apply to each live fort
Write ONE parameterized transform, apply per-fort with substitutions. By artifact type:
- **`.claude/settings.json`**: targeted `jq` edits ONLY (set specific keys, `+ [...] | unique` for arrays). NEVER wholesale-replace or shallow-merge (`jq -s '.[0] * .[1]'` clobbers arrays and hooks). Preserve the `bd prime` SessionStart hook and the PermissionRequest telemetry hook. Deny rules always win over allow — additions to allow cannot open denied paths. Validate: `jq -e . file`.
- **`fort/scripts/*.sh`**: sed/patch, then `bash -n` each script. Remember each fort's scripts carry that fort's citizens' names — never overwrite identity lines with another fort's.
- **Charter/standing orders**: append as amendment WITH the incident that caused it (amendment rule). Never renumber existing orders; never rewrite history sections.
- **NEVER touch**: `fort/events/*.jsonl` (append-only, emit-only), `fort/handoffs/*` (other seats' records), seat files' History/Laurels, `.env*`.

After applying in each fort:
```bash
cd "$REPO"   # cwd discipline: verify with pwd — the cwd trap has bitten twice
fort/scripts/emit.sh charter.amended "<one-line description of the upgrade>" -a overseer
git add <exact paths>   # path-scoped only, never 'git add .'
git commit -m "<summary>

<evidence line: source fort, bead, telemetry>

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git remote | grep -q origin && git push -q origin main   # push only where a remote exists
```

## Step 3 — codify into the factory
In `~/dev/fortkit`:
- Apply the same transform to `templates/` using placeholders, never concrete values: `{{REPO_PATH}}` (repo abs path; worktrees = `{{REPO_PATH}}-worktrees`), `{{PROJECT}}`, `{{FORT_NAME}}`, `{{DATE}}`, `{{FOUNDING_SPEC}}`, `{{PURPOSE}}`.
- Structural additions (new dirs, new files at founding) go in `bin/fort-init` (then `bash -n bin/fort-init`).
- Identity content in templates must be `{{UNFILLED}}` placeholders — a fort must never inherit another settlement's citizen (fortkit-fd2).
- Commit in fortkit.

## Step 4 — ledger
`bd` is cwd-sensitive — run from the fortkit repo:
```bash
cd /home/justin/dev/fortkit
bd update fortkit-or2 --append-notes "<date>: CYCLE — <what flowed>, <from where/evidence>, applied to <forts> + templates. Still inbound: <check the known-inbound list and update it>."
```

## Step 5 — verify and report
- Re-check one changed value per fort (`jq -e`/grep the actual files — verification by `tail` has produced false negatives before; use `grep -c` or explicit key reads).
- Report a table: fort | files changed | committed | pushed | evented.
- Note to user: permission/mode changes require a session restart in each fort to take effect; the telemetry loop (`fort/telemetry/prompts.jsonl`) will confirm prompt-reduction claims — silence in telemetry while prompts continue means the hook broke, not success.

## Known pitfalls (all earned, none hypothetical)
- Shell cwd resets between calls on errors; `bd` follows cwd — beads have been created in the wrong fort this way.
- ForgeOs currently has the only git remote; longburn/fortkit are local-only (securing remotes is an open human bead).
- Session-visible config changes don't affect already-running seat sessions.
- If the transform touches gate-listed constitution files in a fort whose Warden is active, prefer filing a bead in that fort over silent application — this skill's Overseer invocation covers routine config; contested changes deserve the fort's own review.
