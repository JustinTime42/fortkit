#!/usr/bin/env python3
"""mk-templates.py <manyhalls-root> <templates-out> <bd export .jsonl, or a file of bead ids>

Generate the factory's machinery templates FROM MANYHALLS (docket T10): every
fort-specific value becomes a fort-init placeholder, and the hunks that are
Manyhalls's own product (its gate-1 paths, its Node commands, its citizens)
become generic text. Charter, seat files, advisories, the settings fragment and
the product-gate stub are written by hand and are not produced here.

Placeholders rendered by bin/fort-init:
  {{REPO_PATH}} {{HOME}} {{PROJECT}} {{FORT_NAME}} {{FORT_SLUG}} {{FORT_SLUG_UPPER}}
  {{BEAD_PREFIX}} {{KEEP_ID}} {{MAYOR_ID}} {{FORGE_ID}} {{WARDEN_ID}} {{WORKBENCH_ID}}
"""
import os, re, shutil, sys

SRC, OUT, IDS = sys.argv[1], sys.argv[2], sys.argv[3]
if IDS.endswith(".jsonl"):   # a bd export: one issue per line
    import json
    real_ids = set()
    for _line in open(IDS, encoding="utf-8"):
        if _line.strip():
            try:
                real_ids.add(json.loads(_line)["id"])
            except (ValueError, KeyError):
                pass
else:
    real_ids = set(l.strip() for l in open(IDS) if l.strip())
if not real_ids:
    sys.exit("mk-templates: no bead ids read from " + IDS + "; every citation would be rewritten as a fixture id")

TREES = ["fort/scripts", "fort/profiles", "fort/systemd", "fort/checklists", "scripts", ".claude/agents"]
FILES = ["fort/airlock/README.md", "fort/airlock/operations.json", "fort/airlock/requests/.gitkeep",
         "fort/airlock/results/.gitkeep", "fort/events/README.md",
         "docs/specs/unattended-mayor-loop.status.schema.json"]
# Manyhalls-only, or written by hand for the factory: never generated.
SKIP = {
    "scripts/consolidate-memory.mjs", "scripts/consolidate-laurels.mjs", "scripts/memory-lint.mjs",
    "scripts/beads-export-check.sh", "scripts/mask-harness.sh", "scripts/run-pixellab-trial.mjs",
    "scripts/run-pixellab-trial.d.mts", "scripts/verify-impl.sh", "scripts/seat-lint.mjs",
    "scripts/merge-event-check.sh", "scripts/control-fingerprints.json", "scripts/control-lint.mjs",
}
GATE1 = "bin/*|civ/*|templates/*|schema/*|skills/*"
GATE1_RE = r"bin/\*|civ/\*|templates/\*|schema/\*|skills/\*"
SENT = "gate-1-surface"

# (file or None for every file, exact old, new). Each must match at least once somewhere.
SPECIAL = [
    # gate-1 paths: Manyhalls's are the factory and the civilization tooling; a new fort names its own.
    (None, GATE1 + ") printf 'full'; return 0 ;;", SENT + "/*) printf 'full'; return 0 ;;"),
    (None, GATE1 + ")", SENT + "/*)"),
    (None, GATE1_RE + ")", SENT + r"/\*)"),
    (None, "is gate-1 surface (the factory and the civilization tooling)", "is gate-1 surface"),
    # Fixture paths that stand for a gate-1 file, EACH SCOPED TO THE HARNESS THAT USES IT: an
    # unscoped rule here once rewrote "$repo/bin" in a harness where bin/ is where it installs
    # the script under test, and a founded fort's verifier died at exit 127 for it.
    ("scripts/verify-once-harness.sh", "bin/fort-init", SENT + "/tool-a.sh"),
    ("scripts/review-throughput-harness.sh", "bin/fort-init", SENT + "/tool-a.sh"),
    ("scripts/verify-once-harness.sh", "bin/old-tool.sh", SENT + "/old-tool.sh"),
    ("scripts/verdict-record-harness.sh", "bin/tool.sh", SENT + "/tool.sh"),
    ("scripts/fleet-e2e-harness.sh", "bin/tool.sh", SENT + "/tool.sh"),
    ("scripts/verdict-record-harness.sh", '"$br/bin"', '"$br/' + SENT + '"'),
    ("scripts/verify-once-harness.sh", '"$repo/bin"', '"$repo/' + SENT + '"'),
    ("scripts/fleet-e2e-harness.sh", 'wg1/bin"', "wg1/" + SENT + '"'),
    ("scripts/verify-once-harness.sh", "renamed OUT of bin/ into docs/", "renamed OUT of " + SENT + "/ into docs/"),
    ("scripts/verdict-record-harness.sh", "a bin/ change is FULL", "a gate-1 path change is FULL"),
    ("scripts/verify-once-harness.sh", "expect_tier full    civ-tooling      civ/scripts/herald.sh\nexpect_tier full    templates        templates/fort/charter.md\nexpect_tier full    schema           schema/events.md\n", ""),
    ("scripts/verify-once-harness.sh", "expect_tier full    factory          ", "expect_tier full    gate-1           "),
    ("scripts/verify-once-harness.sh", "row full    test         RUN;  row full    governor-harness RUN\nrow server  test         RUN;  row server  governor-harness SKIP; row server shellcheck SKIP\nrow docs    typecheck    SKIP; row docs    npm-deps    SKIP; row docs   shellcheck SKIP\n",
     "row full    product-gate RUN;  row full    governor-harness RUN\nrow server  product-gate RUN;  row server  governor-harness SKIP; row server shellcheck SKIP\nrow docs    product-gate SKIP; row docs   shellcheck SKIP\n"),
    ("scripts/verify-once-harness.sh", "row harness test         SKIP; row harness governor-harness RUN; row harness typecheck SKIP\n", "row harness product-gate SKIP; row harness governor-harness RUN\n"),
    ("fort/scripts/fleet.sh", "#   full, forced: scripts/verify-impl.sh; the factory and the civilization's\n#     tooling (bin/, civ/, templates/, schema/, skills/: charter gate 1, what\n#     a change there DOES reaches every fort); fort/ other than fort/handoffs/",
     "#   full, forced: scripts/verify-impl.sh; this fort's gate-1 paths (the\n#     " + SENT + "/* arm below is where the fort names them; until it does, the\n#     arm matches nothing); fort/ other than fort/handoffs/"),
    ("fort/scripts/fleet.sh", "#   server:  src/ and test/ (plus docs): the TypeScript product.", "#   server:  src/ and test/ (plus docs): the product."),
    ("fort/scripts/fleet.sh", "#   Both of server/harness at once is full. Manyhalls has no web tier: the", "#   Both of server/harness at once is full. There is no web tier: the"),
    ("fort/scripts/fleet.sh", "   # Manyhalls has no migrations directory; the collapse below never fires", "   # no migrations directory is named for this fort; the collapse below never fires"),
    ("fort/scripts/warden.sh", "  # Manyhalls has no in-file gate surface a path list cannot see (the source\n  # fort's symbol belt over its SPA session gate is not carried): gate 1 here is\n  # whole directories, named above.\n",
     "  # No in-file gate surface is declared for this fort: gate 1 is whole paths,\n  # named above (the " + SENT + "/* arm, which matches nothing until the fort\n  # names its own).\n"),
    # prompts: Manyhalls's commands and gates
    ("fort/scripts/forge.sh", "read fort/charter.md BEFORE touching anything outside src/, test/, scripts/ and docs/, and before ANY change under bin/, civ/, templates/, schema/ or skills/ (the factory and the civilization's tooling: a change there reaches every fort) or under fort/ and .claude/ (this fort's constitution)",
     "read fort/charter.md BEFORE touching anything outside src/, test/, scripts/ and docs/, and before ANY change to a gate-1 path the charter names or under fort/ and .claude/ (this fort's constitution)"),
    ("fort/scripts/forge.sh", "npm ci FIRST when the worktree has no node_modules, then typecheck, lint and the vitest files your change touches (the handoff instruction below says exactly what to run).",
     "the project's own build, lint and the tests your change touches (the handoff instruction below says what to run)."),
    ("fort/scripts/forge.sh", "A fresh worktree has no node_modules: run npm ci FIRST. Then npm run typecheck, npx biome check <the files you changed>, and the TESTS FOR WHAT YOU CHANGED: npx vitest run <the test files you added or changed, and the test files that cover the code you changed> (never the unfiltered suite).",
     "A fresh worktree has no installed dependencies: install them FIRST. Then run this project's build or typecheck, its lint on the files you changed, and the TESTS FOR WHAT YOU CHANGED: the test files you added or changed, and the ones that cover the code you changed (never the unfiltered suite). fort/seats/forge.md names the commands once this fort has wired its product gate."),
    ("fort/scripts/forge.sh", "gated work (charter gates 1 and 6) keeps", "gated work (the charter's human gates) keeps"),
    ("fort/scripts/forge.sh", "scripts/consolidate-memory.mjs parses", "fort/memory/consolidate-memory.mjs parses"),
    ("fort/scripts/forge.sh", "5) [ -d node_modules ] || npm ci >/dev/null 2>&1 ; echo ci-exit=\\$?\n6) npm run typecheck 2>&1 | tail -3\n7) npx vitest run test/cli.test.ts 2>&1 | tail -6   (report the pass/fail counts)\n",
     "5) command -v git node jq ; echo tools-exit=\\$?\n6) git status --porcelain | head -3 ; echo status-exit=\\$?\n7) node -e 'process.stdout.write(String(6*7))' ; echo node-exit=\\$?   (no product gate is wired in a newly founded fort; this only shows the toolchain runs)\n"),
    ("fort/scripts/forge.sh", '  --add-dir "$HOME/.npm" \\\n', '  --add-dir "$HOME/.npm" \\\n'),
    ("fort/scripts/warden.sh", "which is fort/scripts/verify.sh: the lints, typecheck, biome, vitest, shellcheck and the harness suite.", "which is fort/scripts/verify.sh: the lints, shellcheck, the harness suite and whatever product gate this fort has wired."),
    ("fort/scripts/warden.sh", "run the legs directly and report each one's outcome: npm ci | npm run typecheck | npm run lint | npm test. State explicitly whether node_modules existed in cwd BEFORE you started and whether npm ci succeeded: the launcher's copy EXCLUDES node_modules and nothing restores it, so this fort depends on that install.",
     "say which stage was refused and stop. State explicitly whether node_modules existed in cwd BEFORE you started: the launcher's copy EXCLUDES it and nothing restores it."),
    ("fort/scripts/warden.sh", "Reproduce verifiers yourself in cwd when code changed (npm ci first: the copy carries no node_modules).", "Reproduce verifiers yourself in cwd when code changed (install dependencies first: the copy carries none)."),
    ("fort/scripts/warden.sh", "ESCALATE (mandatory for the factory and the civilization tooling per gate 1, and the fort constitution per gate 6)", "ESCALATE (mandatory for the gate-1 paths the charter names, and the fort constitution per gate 6)"),
    ("fort/scripts/workbench.sh", "Gates are unchanged: the factory and the civilization tooling (bin/, civ/, templates/, schema/, skills/) and the fort's constitution may be written", "Gates are unchanged: the gate-1 paths the charter names and the fort's constitution may be written"),
    ("fort/scripts/mayor.sh", " Anything public-facing (publishing, releases, domains, external accounts) is his alone (charter gate 3).", " Anything public-facing (publishing, releases, domains, external accounts) is his alone."),
    # posture prose
    (None, "SANDBOX POSTURE: secrets-only (Manyhalls ships the posture its machinery came with; Overseer decision 2026-11-18, fortkit-ttpk). ", "SANDBOX POSTURE: secrets-only (the one word in fort/scripts/sandbox-posture). "),
    # persona: a founded fort has offices until its moot
    ("fort/scripts/forge.sh", "You are Kethra Anvilmark (she/her), holder of the Forge seat of Manyhalls, the fortkit fort.", "You hold the Forge seat of {{FORT_NAME}}, the {{PROJECT}} fort."),
    ("fort/scripts/warden.sh", "You are Ilva Trueglass (she/her), holder of the Warden seat of Manyhalls, the fortkit fort.", "You hold the Warden seat of {{FORT_NAME}}, the {{PROJECT}} fort."),
    ("fort/scripts/mayor.sh", "You are Emrith Cairnwright (she/her), Mayor of Manyhalls, the fortkit fort —", "You are the Mayor of {{FORT_NAME}}, the {{PROJECT}} fort —"),
    ("fort/scripts/workbench.sh", "You are Dunmar Trestle (they/them), the Workbench of Manyhalls, the fortkit fort:", "You are the Workbench of {{FORT_NAME}}, the {{PROJECT}} fort:"),
    ("fort/scripts/lib/seat-sandbox.sh", "# ***** FORT-LOCAL. MANYHALLS'S CITIZENS. NEVER PORT THIS FUNCTION. *****\n# Emrith Cairnwright, Kethra Anvilmark and Ilva Trueglass hold seats in THIS\n# settlement and no other.",
     "# ***** FORT-LOCAL. THIS FORT'S CITIZENS. NEVER PORT THIS FUNCTION. *****\n# The actor ids below are this settlement's and no other's. A fort founded by the\n# factory carries its seat offices here until its Founding Moot names citizens."),
    ("fort/scripts/lib/seat-sandbox.sh", "# Manyhalls's build is Node and needs none. The function stays because every\n# launcher calls it; the fort this lib came from set its compiler-server\n# switches here.", "# A newly founded fort sets none. The function stays because every launcher\n# calls it; a fort whose toolchain leaves build servers running sets its\n# switches here."),
    # the agent gate binds every session in a founded fort (the capital's carve is Manyhalls's alone)
    ("fort/scripts/agent-gate.sh", None, None),
    # fleet.conf: a founded fort ships disabled and small, without Manyhalls's reasons
    ("fort/scripts/fleet.conf", "# MANYHALLS SHIPS THIS AT 0 (Regent sitting 2026-11-18, fortkit-ttpk). The fleet was\n# transplanted and has never run here. Turning it on is the Overseer's decision, and\n# on this host it comes after the shared-host rules of the re-founding docket: the two\n# fleets' memory gates each see only their own workers (S1), and the model quota is\n# shared (S2). The values below are deliberately small for the same reason; the fort\n# this file came from ran START=4 MAX=4, two Warden slots and a hard stop of 36.\n",
     "# A FOUNDED FORT SHIPS THIS AT 0. The fleet has never run here. Turning it on is the\n# Overseer's decision. Every fleet on a host shares its memory and its model quota,\n# and each fleet's memory gate sees only its own workers, so the values below start\n# small.\n"),
    ("fort/airlock/README.md", None, None),
    ("fort/systemd/README.md", None, None),
    ("fort/checklists/unattended-fleet-run.md", None, None),
    ("fort/checklists/fleet-eligible-bead.md", None, None),
    ("scripts/host-test.sh", "    [ -d node_modules ] || npm ci\n    npm run typecheck\n    read -r -a filter_words <<< \"$filter\"\n    npx vitest run \"${filter_words[@]}\"\n",
     "    # No product test runner is wired in a newly founded fort. Name this fort's\n    # runner here before an airlock operation points at this script.\n    read -r -a filter_words <<< \"$filter\"\n    echo \"host-test: no product test runner is wired in this fort (filter: ${filter_words[*]})\" >&2\n    exit 69\n"),
    ("scripts/host-test.sh", "'<vitest file filter>' [--mutate patch]\n# The filter is handed to `npx vitest run` as file-name filters (space separated).", "'<test filter>' [--mutate patch]\n# The filter is handed to this fort's test runner once one is wired below."),
    ("fort/scripts/fleet-supervisor.sh", 'fleet_tools="bd codex node npm git jq flock python3 claude"', 'fleet_tools="bd codex node git jq flock python3 claude"'),
    ("fort/scripts/status.sh", "# Manyhalls fort status: fast, read-only.", "# Fort status: fast, read-only."),
    ("scripts/forge-refresh-harness.sh", "grep -qF 'npx vitest run <the test files you added or changed' <<<\"$hi\" && grep -qF 'npm run typecheck' <<<\"$hi\" && grep -qF 'never the unfiltered suite'", "grep -qF 'the test files you added or changed' <<<\"$hi\" && grep -qF 'never the unfiltered suite'"),
    ("scripts/forge-refresh-harness.sh", "grep -qF 'run npm ci FIRST' <<<\"$hi\"", "grep -qF 'install them FIRST' <<<\"$hi\""),
    ("fort/airlock/operations.json", "Manyhalls ships this table EMPTY (Regent sitting 2026-11-18, fortkit-ttpk): the mechanism", "A founded fort ships this table EMPTY: the mechanism"),
    (None, "Emrith Cairnwright of Manyhalls", "Emrith Cairnwright of \x01MH\x01"),
    # identity the general rules do not reach (the Warden's finding 7, review 2 on fortkit-ttpk)
    ("fort/airlock/README.md", "~/.local/share/airlock/fortkit/<id>", "~/.local/share/airlock/{{PROJECT}}/<id>"),
    ("fort/systemd/manyhalls-nightly-verify.timer", " (an hour after Proofdelve's nightly on this host)", ""),
]
NOTE_RE = re.compile(r"\n> \*\*(?:Manyhalls, 2026-11-18|Carried from Proofdelve at Manyhalls's re-founding)[^\n]*\n(?:> [^\n]*\n)+")
GATE_CARVE_RE = re.compile(r"# MANYHALLS: SEATS ONLY\..*?\n\[ -n \"\$\{FORT_MASKED:-\}\$\{FORT_SEAT_UNMASKED:-\}\" \] \|\| exit 0\n", re.S)

ACTORS = [("emrith", "{{MAYOR_ID}}"), ("kethra", "{{FORGE_ID}}"), ("ilva", "{{WARDEN_ID}}"), ("dunmar", "{{WORKBENCH_ID}}")]
used = [0] * len(SPECIAL)


def bead(m):
    full = "fortkit-" + m.group(1)
    cand = full
    while cand not in real_ids and "." in cand:
        cand = cand.rsplit(".", 1)[0]
    if cand in real_ids:
        return full            # a real bead of the capital: a citation, valid from any fort
    return "{{BEAD_PREFIX}}-" + m.group(1)


def transform(rel, t):
    for i, (f, old, new) in enumerate(SPECIAL):
        if old is None or (f is not None and f != rel):
            continue
        if old in t:
            used[i] += t.count(old)
            t = t.replace(old, new)
    if rel in ("fort/airlock/README.md", "fort/systemd/README.md", "fort/checklists/unattended-fleet-run.md",
               "fort/checklists/fleet-eligible-bead.md"):
        t, n = NOTE_RE.subn("\n", t)
        assert n == 1, (rel, "re-founding note", n)
    if rel == "fort/scripts/fleet.conf":
        # A founded fort ships its fleet DISABLED whatever Manyhalls runs. Found
        # 2026-11-19: with Manyhalls's fleet enabled for a test, a regeneration
        # wrote FLEET_ENABLED=1 into the factory.
        t, n = re.subn(r"(?m)^FLEET_ENABLED=[01]$", "FLEET_ENABLED=0", t)
        assert n == 1, (rel, "FLEET_ENABLED", n)
    if rel == "fort/scripts/agent-gate.sh":
        t, n = GATE_CARVE_RE.subn("", t)
        assert n == 1, (rel, "capital carve", n)
    # paths first
    t = t.replace("/home/justin/dev/fortkit-worktrees", "{{REPO_PATH}}-worktrees")
    t = t.replace("/home/justin/dev/fortkit", "{{REPO_PATH}}")
    t = t.replace("~/dev/fortkit/", "{{REPO_PATH}}/").replace("$HOME/dev/fortkit-host-test", "$HOME/dev/{{FORT_SLUG}}-host-test")
    t = t.replace("/home/justin", "{{HOME}}")
    # the Keep's id for this fort
    t = re.sub(r'(fort\\?"\s*:\s*\\?")fortkit(\\?")', r"\1{{KEEP_ID}}\2", t)
    t = re.sub(r'(get\("fort"\) (?:!=|==) ")fortkit(")', r"\1{{KEEP_ID}}\2", t)
    t = t.replace('lines carry fort "fortkit"', 'lines carry fort "{{KEEP_ID}}"')
    # names
    t = t.replace("the fortkit fort", "the {{PROJECT}} fort")
    t = t.replace("MANYHALLS", "{{FORT_SLUG_UPPER}}").replace("manyhalls", "{{FORT_SLUG}}")
    if rel != "fort/scripts/lib/seat-sandbox.sh":
        t = t.replace("Manyhalls", "{{FORT_NAME}}")
    # bead ids: the capital's real ones stay as citations; fixtures and constructed ids take the fort's prefix
    t = re.sub(r"fortkit-([a-z0-9]+(?:\.[0-9a-z]+)*)", bead, t)
    t = re.sub(r"fortkit-(?![a-z0-9{])", "{{BEAD_PREFIX}}-", t)
    for a, b in ACTORS:
        t = re.sub(r"(?<![A-Za-z0-9])" + a + r"(?![A-Za-z0-9])", b, t)
    return t.replace("\x01MH\x01", "Manyhalls")


def want(rel):
    return rel not in SKIP


count = 0
for tree in TREES:
    for r, _, fs in os.walk(os.path.join(SRC, tree)):
        for f in fs:
            rel = os.path.relpath(os.path.join(r, f), SRC)
            if want(rel):
                FILES.append(rel)
for rel in sorted(set(FILES)):
    src = os.path.join(SRC, rel)
    out_rel = rel.replace(".claude/", "claude/", 1) if rel.startswith(".claude/") else rel
    out_rel = out_rel.replace("fort/systemd/manyhalls-", "fort/systemd/__FORT_SLUG__-")
    dst = os.path.join(OUT, out_rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    try:
        t = open(src, encoding="utf-8").read()
    except UnicodeDecodeError:
        shutil.copy2(src, dst); count += 1; continue
    n = transform(rel, t)
    assert "\x00" not in n and "\x01" not in n
    open(dst, "w", encoding="utf-8").write(n)
    shutil.copymode(src, dst)
    count += 1
unused = [(SPECIAL[i][0], (SPECIAL[i][1] or "")[:60]) for i, u in enumerate(used) if u == 0 and SPECIAL[i][1] is not None]
print("files written:", count)
if unused:
    print("SPECIAL RULES THAT MATCHED NOTHING (the tree moved under the generator):")
    for u in unused:
        print("  ", u)
    sys.exit(1)
