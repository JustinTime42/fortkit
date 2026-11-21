#!/usr/bin/env python3
"""mk-templates-hand.py <manyhalls-root> <templates-out> <previous templates/fort/charter.md>

The templates that are not a mechanical rendering of Manyhalls's files: the
charter, the four seat files and the product-gate stub. Each is still DERIVED
from Manyhalls's file, so a rule added there reaches the factory at the next
refresh; what differs is named in the lists below.
"""
import os, re, sys

SRC, OUT = sys.argv[1], sys.argv[2]
OLD_TEMPLATE = open(sys.argv[3], encoding="utf-8").read().split("\n")   # the factory charter before this refresh
UNF_NAME = "{{UNFILLED — set at the Founding Moot}}"
UNF_PERS = "{{UNFILLED — the founder writes this at the moot; a fort must never inherit another settlement's citizen}}"


def read(rel):
    return open(os.path.join(SRC, rel), encoding="utf-8").read()


def write(rel, t):
    assert "\x00" not in t
    p = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w", encoding="utf-8").write(t)


def sub1(t, old, new, count=1):
    assert t.count(old) == count, (old[:70], t.count(old))
    return t.replace(old, new)


def between(t, start, end, new):
    assert t.count(start) == 1, (start[:70], t.count(start))
    i = t.index(start); j = t.index(end, i + len(start))
    return t[:i] + new + t[j:]


def common(t):
    t = t.replace("/home/justin/dev/fortkit-worktrees", "{{REPO_PATH}}-worktrees").replace("fortkit-worktrees/", "<repo>-worktrees/")
    t = t.replace("the fortkit fort", "the {{PROJECT}} fort")
    t = t.replace("manyhalls", "{{FORT_SLUG}}").replace("Manyhalls", "{{FORT_NAME}}")
    for a, b in (("emrith", "{{MAYOR_ID}}"), ("kethra", "{{FORGE_ID}}"), ("ilva", "{{WARDEN_ID}}"), ("dunmar", "{{WORKBENCH_ID}}")):
        t = re.sub(r"(?<![A-Za-z0-9])" + a + r"(?![A-Za-z0-9])", b, t)
    return t


def seat(name, office):
    t = read(f"fort/seats/{name}.md")
    t = re.sub(r"^\*\*Held by: [^\n]*$", "**Held by:** " + UNF_NAME, t, count=1, flags=re.M)
    t = re.sub(r"^\*\*Personality[^\n]*$", "**Personality (in their own words):** " + UNF_PERS, t, count=1, flags=re.M)
    i = t.index("## History")
    t = t[:i] + f"## History\n\n- {{{{DATE}}}}: Seat founded at the founding of the {{{{PROJECT}}}} fort. Occupant chosen at the Founding Moot.\n\n## Laurels\n\n(External recognition lands here, unranked.)\n"
    t = t.replace("(the factory and the civilization's tooling: `bin/`, `civ/`, `templates/`, `schema/`, `skills/`: gate 1)", "(the gate-1 paths the charter names)")
    t = t.replace("`bin/`, `civ/`, `templates/`, `schema/` and `skills/` are the factory and the civilization's tooling (gate 1); `fort/` and `.claude/` are this fort's constitution (gate 6).", "The charter names this fort's gate-1 paths; `fort/` and `.claude/` are its constitution (gate 6).")
    t = t.replace("touches gate-1 surface (`bin/`, `civ/`, `templates/`, `schema/`, `skills/`) or the fort's constitution (gate 6)", "touches a gate-1 path the charter names or the fort's constitution (gate 6)")
    t = t.replace("that touches gate-1 surface (`bin/`, `civ/`, `templates/`, `schema/`, `skills/`) or the fort's constitution (gate 6)", "that touches a gate-1 path the charter names or the fort's constitution (gate 6)")
    t = t.replace("In a fresh worktree run `npm ci` first. Then `npm run typecheck`, `npx biome check` on the files you changed, and `npx vitest run` on the test files you added or changed and the ones covering the code you changed.", "Install dependencies first in a fresh worktree, then run this project's build or typecheck, its lint on the files you changed, and the tests you added or changed and the ones covering the code you changed. (Name the commands here once this fort has wired its product gate.)")
    t = t.replace("drives its targeted typecheck, lint and tests green", "drives its targeted build, lint and tests green")
    t = t.replace("The factory and the civilization's tooling (`bin/`, `civ/`, `templates/`, `schema/`, `skills/`: gate 1) and the fort's constitution (gate 6) may be written", "The gate-1 paths the charter names and the fort's constitution (gate 6) may be written")
    t = t.replace("touches gate-1 surface (`bin/`, `civ/`, `templates/`, `schema/`, `skills/`) or the fort's constitution (gate 6)", "touches a gate-1 path the charter names or the fort's constitution (gate 6)")
    t = t.replace(" (the posture Manyhalls ships)", "").replace(", the posture Manyhalls ships)", ")")
    return common(t)


for n in ("mayor", "forge", "warden", "workbench"):
    t = seat(n, n)
    assert "Emrith" not in t and "Kethra" not in t and "Ilva" not in t and "Dunmar" not in t, n
    assert "npm " not in t and "vitest" not in t and "bin/`" not in t, (n, "Manyhalls's own commands or gate-1 paths survived into the seat template")
    write(f"fort/seats/{n}.md", t)

# ---------------------------------------------------------------- charter
c = read("fort/charter.md")
c = between(c, "# Manyhalls Charter", "## Purpose",
            "# {{FORT_NAME}} Charter — the {{PROJECT}} Fort\n\nFounded {{DATE}} via fort-init. Founding spec: {{FOUNDING_SPEC}}. The machinery this fort runs on (launchers, mask library, profiles, fleet, verifier, airlock) is the factory's, which was generated from Manyhalls's on 2026-11-18. Generic law below is scar-tested in the forts it came from; project-specific gates and orders must be earned by this fort's own failures and added by amendment.\n\n")
# fortkit-mc0m.6.1: the Overseer sentence is rendered HERE and nowhere else. A purpose
# passed to fort-init says what the fort is for and must not restate it.
c = between(c, "## Purpose\n", "> **Posture note.**",
            "## Purpose\n\n{{PURPOSE}}\n\nOne human (Justin, the Overseer) provides intent, approves designs, reviews gated changes, and owns all human-gated actions.\n\n")
c = between(c, "> **Posture note.**", "## Human gates",
            "> **Posture note.** The posture of this fort is the one word in `fort/scripts/sandbox-posture`. In `secrets-only` every seat has a writable `$HOME` and checkouts, the shared `/tmp`, the network and the Docker socket, and the Forge runs Codex with `--sandbox danger-full-access`; in `full` seats run with a read-only `$HOME` and the Forge's sandbox is `workspace-write`. **Unchanged in both postures:** every human gate below; the kernel read-only carve-outs (`fort/scripts`, `fort/profiles`, `.claude`, `.git/config` and hooks, `fort/airlock/operations.json`, the Overseer's approval stores, the Warden's real checkout); the inode masks on every secret spelling, the credential directories and the Keep signing token; the user-manager sockets. Docker is root-equivalent and can reach what is masked; the launcher prompts forbid that and name it the compromise signature.\n\n")
c = between(c, "1. The factory and the civilization's tooling", "2. (Vacant.",
            "1. (Yours to define. Gate 1 is this fort's most expensive surface: the paths where a mistake is a security hole or travels furthest. Name them here, and name the same paths in the `gate-1-surface/*` arms of `fort/scripts/fleet.sh` and `fort/scripts/warden.sh`, which match nothing until you do. A bead touching them is filed `sign-to-land`.)\n{{EXTRA_GATES}}\n")
c = sub1(c, "2. (Vacant. In the fort this machinery came from, gate 2 is data migrations; Manyhalls has none.)", "2. (Vacant until this fort has data migrations: in the fort this machinery came from, gate 2 is migrations that mutate data.)")
c = sub1(c, ", whose operations table Manyhalls ships empty; adding an operation is a gate-6 change.", ", whose operations table ships empty; adding an operation is a gate-6 change.")
c = sub1(c, "5. (Vacant. In the fort this machinery came from, gate 5 is a product decision.)", "5. (Vacant: reserved for a product decision that is the Overseer's alone.)")
c = between(c, "No residual is recorded here yet.", "**Explicitly out of scope:", "No residual is recorded here yet. A residual is admitted here only with a measurement attached.\n\n")
c = sub1(c, "(cycle 6, 2026-08-04, carried forward)", "(cycle 6 of the forts this law came from)")
c = sub1(c, "(cycle 7, 2026-08-08, `fortkit-i4y`, carried forward)", "(cycle 7, `fortkit-i4y`)")
c = between(c, "Carried word for word from the charter this machinery came with", "From the Overseer's own instructions:",
            "Carried from the charters this machinery came with, because the machinery cites them by number. Four numbers are vacant: they were product law of another fort and have no subject here. Their numbers stay vacant so every citation still resolves.\n\n")
c = sub1(c, "4. (Vacant; see above. In Manyhalls the spec is the arbiter all the same: specs live in `docs/specs/`, and spec, code and docs drift is flagged rather than silently followed.)", "4. (Vacant; see above. The spec is the arbiter all the same: spec, code and docs drift is flagged rather than silently followed.)")
# Orders 16 and 17: the factory's own generic text (the old template's 12 and 13), renumbered
# to what the machinery cites. Manyhalls's copies carry its own worked examples and citizens.
oldt = OLD_TEMPLATE
def old_order(n, new):
    # The previous template carries these orders as 16 and 17 (or, before the 2026-11-18
    # refresh, as 12 and 13). Read whichever is there.
    hits = [k for k, l in enumerate(oldt) if l.startswith(f"{new}. **")] or [k for k, l in enumerate(oldt) if l.startswith(f"{n}. **")]
    n = new if oldt[hits[0]].startswith(f"{new}. ") else n
    i = hits[0]
    j = i + 1
    while j < len(oldt) and (oldt[j].startswith("    ") or (oldt[j].strip() == "" and j + 1 < len(oldt) and oldt[j + 1].startswith("    "))):
        j += 1
    return f"{new}. " + "\n".join(oldt[i:j]).rstrip()[len(f"{n}. "):]
i = c.index("16. **Architecture ports between forts; identity never does.**"); j = c.index("## Seats")
c = c[:i] + old_order(12, 16) + "\n" + old_order(13, 17) + "\n{{EXTRA_ORDERS}}\n\n" + c[j:]
c = between(c, "| Mayor | Design, triage", "Fleet: `fort/scripts/fleet.sh`",
            "| Mayor | Design, triage, decomposition, specs; the seat the Overseer talks to | Claude Code (`fort/scripts/mayor.sh`): Opus → Fable (hard architecture) | specs, beads, docs — never product code |\n| Forge | Implementation in isolated worktrees | Codex CLI (`fort/scripts/forge.sh`); the models are the two lines in `fort/scripts/fleet.conf` | product code in its worktree |\n| Workbench | Implementation WITH the Overseer present; his interactive session (`fort/scripts/workbench.sh`) | Claude Code, attended only, never scheduled | product code on its session branch |\n| Warden | Review, read-only toward the real checkout by construction | Claude Code (`fort/scripts/warden.sh`): Opus → **block and page the Overseer** (never degrades below frontier) | review verdicts only |\n\nOccupants: (unnamed — the Founding Moot seats them; until then actor ids are the seat offices). The fort's name is pending the moot.\n\n**The Regent** is a seat of the civilization, not of this fort. It is named here because it is the seat above this fort's constitution: the only one that lands changes to this fort's kernel read-only machinery (gate 6), by edict, with the Overseer present.\n\n")
c = between(c, "Fleet: `fort/scripts/fleet.sh`", "Merge flow:",
            "Fleet: `fort/scripts/fleet.sh` dispatches `fleet-safe` beads to Forges, runs the host verifier, launches the Warden, and lands on her verdict or holds for the Overseer's signature (`sign-to-land`). **It ships disabled** (`FLEET_ENABLED=0` in `fort/scripts/fleet.conf`) and no timer in `fort/systemd/` is installed; enabling either is the Overseer's decision.\n\n")
c = between(c, "Work state: Beads", "Handoffs: `fort/handoffs/`",
            "Work state: Beads (`bd ready`; `bd` is authoritative and `.beads/issues.jsonl` is a projection). Operational facts: the facts ledger at `fort/memory/facts/`, one fact per file, whose distilled view is `fort/memory/current.md`, regenerated by `fort/memory/consolidate-memory.mjs` and linted by `fort/memory/memory-lint.mjs`. ")
c = sub1(c, " Laurels: `fort/laurels/`.", "")
c = common(c)
assert "Emrith" not in c and "Proofdelve's, at" not in c
write("fort/charter.md", c)

# ---------------------------------------------------------------- product-gate stub
v = read("scripts/verify-impl.sh")
v = sub1(v, "# Manyhalls verifier. Exit 0 only after every required quality gate passes.", "# {{PROJECT}} verifier. Exit 0 only after every required quality gate passes.\n#\n# THE PRODUCT GATE IS A STUB. Every step that tests the fort's own machinery is\n# wired and runs. The step named product-gate, the LAST one, fails until this\n# fort replaces it with its own build, lint and tests: a verifier that passed\n# with no product gate would be a green that means nothing.")
v = sub1(v, 'tier_server_steps=" npm-deps typecheck lint test "', 'tier_server_steps=" product-gate "')
v = sub1(v, "run_step memory-lint node scripts/memory-lint.mjs", "run_step memory-lint node fort/memory/memory-lint.mjs")
a = v.index("# THE PRODUCT GATE (Manyhalls: Node 24 + TypeScript)."); b = v.index("# The isolation gate (Regent sitting 2026-11-18")
v = v[:a] + "run_step seat-lint node scripts/seat-lint.mjs\nrun_step merge-events scripts/merge-event-check.sh\n" + v[b:]
a = v.index("TEMPLATE_SH=("); b = v.index("run_step template-render template_render_lint\n") + len("run_step template-render template_render_lint\n")
v = v[:a] + v[b:]
a = v.index("# The template scripts are NOT in this list"); b = v.index("run_step shellcheck shellcheck -x bin/fort-init")
v = v[:a] + v[b:]
v = sub1(v, "run_step shellcheck shellcheck -x bin/fort-init bin/regent bin/refresh-templates fort/scripts/*.sh fort/scripts/lib/*.sh civ/scripts/*.sh scripts/*.sh", "run_step shellcheck shellcheck -x fort/scripts/*.sh fort/scripts/lib/*.sh scripts/*.sh")
v = sub1(v, "run_step beads-export scripts/beads-export-check.sh\n",
         "# THE PRODUCT GATE, A STUB (see the head of this file). Replace the function body\n# with this fort's own build, lint and tests, split into run_step calls of their own\n# above this line if a tier should be able to skip them, and delete the stub.\nproduct_gate_stub() {\n  echo 'product-gate: NO PRODUCT GATE IS WIRED. Every machinery step above ran; this fort has not yet said how its own code is built and tested. Edit scripts/verify-impl.sh.' >&2\n  return 1\n}\nrun_step product-gate product_gate_stub\n")
# The Forge's gate-1 bind and its harness are Manyhalls's alone (mk-templates.py does
# not ship scripts/forge-gate1-mask-harness.sh), so the factory's verifier must not
# call it. The workbench mask harness is shipped and its step stays.
v = sub1(v, 'run_step forge-gate1-mask-harness mask_harness_step forge-gate1-mask-harness "$repo_root/fort/scripts/forge.sh"\n', "")
v = sub1(v, "workbench-mask-harness and forge-gate1-mask-harness build a real mask", "workbench-mask-harness builds a real mask")
v = sub1(v, "the tokens, the gate-1 surface, the ssh agent. They refuse inside a seat mask", "the tokens. It refuses inside a seat mask")
v = sub1(v, "(a mask cannot build a mask), and until now that meant they ran only when", "(a mask cannot build a mask), and until now that meant it ran only when")
v = sub1(v, "Regent) they now run as steps. Inside a seat mask, or where bwrap is absent,", "Regent) it now runs as a step. Inside a seat mask, or where bwrap is absent,")
v = sub1(v, "# THE MASK HARNESSES ARE GATE STEPS ON THE HOST, AND SAY SO WHERE THEY CANNOT RUN", "# THE MASK HARNESS IS A GATE STEP ON THE HOST, AND SAYS SO WHERE IT CANNOT RUN")
v = v.replace("/home/justin/dev/fortkit", "{{REPO_PATH}}").replace("/home/justin", "{{HOME}}")
v = common(v)
v = re.sub(r"fortkit-(?![a-z0-9{])", "{{BEAD_PREFIX}}-", v)
write("scripts/verify-impl.sh", v)
os.chmod(os.path.join(OUT, "scripts/verify-impl.sh"), 0o755)
print("hand templates written")
