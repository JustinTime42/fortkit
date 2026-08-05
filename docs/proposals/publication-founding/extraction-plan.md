# Extraction plan: fort instrument to public artifact

Drafted by the Regent, 2026-08-04, under the edict founding the civilization's
security-publication seat. Order of artifacts is the Overseer's, and his
reasoning is preserved with each.

Nothing in this plan creates a public repository. Publication is human gate 3.
The seat prepares candidate trees; the Overseer creates, names, and pushes.

---

## Artifact 1 — the boundary probe suite, as a standalone public repository

**Why first** (the Overseer's reasoning, recorded): a harness that tells you
whether your agent sandbox actually holds does not exist publicly; it is
self-demonstrating, in that the tool's own output is the evidence for the
claims the writeups will make; and it is small enough for one person to
maintain.

### What exists today

Measured, not estimated. Source: `/home/justin/dev/ForgeOs/fort/scripts/`.

| File | Lines | Role |
|---|---|---|
| `probe-boundaries.sh` | 1206 | The suite. All three tiers. |
| `probe-forge-masks.sh` | 103 | Tier-1 subprocess. Byte counts only. |
| `lib/seat-sandbox.sh` | 178 | Sourced to rebuild each posture's mask. |
| `emit.sh` | 27 | Optional event emission. |
| `fort/checklists/post-config-change.md` | 62 | The operating doc. |

Runtime total roughly 1514 lines of bash. There is **no README**; the 87-line
doc-comment header of `probe-boundaries.sh` is the documentation.

**Dependencies:** bash >= 4.3 (namerefs, associative arrays, so not macOS's
default bash), bubblewrap (Linux, unprivileged user namespaces), `jq`, `git`,
coreutils, and the `claude` CLI for tier 3 only. A full run spends roughly 14
headless model sessions, so tier 3 costs money. The Codex CLI is never invoked;
`~/.codex` appears only as a path being probed.

### What is genuinely portable

This is the asset, and it is most of the value. It works for anyone with zero
modification:

- **The verdict vocabulary.** PASS, FRAGILE, COVERED-CANONICAL, NAMED, GAP,
  INCONCLUSIVE, FAIL. Every class beyond the first two was added *after a review
  caught the suite over-claiming*, which is itself the story. The header says it
  outright: read the classes, never the pass count.
- **The methodological rules.** Never ask a model to probe its own leash. A
  refusal is not evidence until you know which boundary refused. Classify
  refusals from the config, never from transcript prose. Every probe carries a
  positive control that must execute, a negative control that must be refused,
  and a differential twin proving the refusal came from the rule rather than
  from allow-list absence. Correlate evidence to the probe's own tool call. Fail
  closed on the suite's own bugs, to the point that a typo'd verdict string is
  itself a FAIL.
- **The deny-rule glob matcher** (`rule_matches` / `rule_scope` / `binds`),
  generic over any rule set; only the target path is a variable.
- **The 28-reader list and the 9 write-vector list.**
- **The obfuscation catalogue** (quote-split, shell-glob, bracket-glob,
  cd-relative, base64-indirect).
- **The stream-json correlation helpers**, pure `jq` over Claude Code's headless
  output schema.

### Extraction cost

The coupling that must be paid off, exhaustively:

1. **`root` is hardcoded** to an absolute path in two scripts, and it is
   hardcoded *on purpose*: the header states that running a scratch copy still
   probes and writes to the real fort. The public version must invert this
   deliberate decision, discovering the root via `git rev-parse` with an
   explicit opt-in flag for probe-the-live-tree.
2. **A literal loop over five home-directory paths** that also uses the home
   path as a string prefix-stripper, so it is baked in twice. Derive from
   `$HOME`.
3. **Secret and target filenames are hardcoded**, and worse, the obfuscation
   generator is *shaped around* the literal `.env.` prefix — give it a
   differently-named file and the variant spellings become nonsense. Needs a
   filename-agnostic variant generator plus a config array.
4. **Postures are seven hand-written `case` statements** covering seat names,
   mask-builder invocations, CLI flags, per-posture negative controls, and
   launcher parity targets. This becomes a declarative posture table and is the
   only part that is close to a rewrite rather than a refactor.
5. **The three-lists check** is hardwired to one Codex TOML plus two structures
   inside one launcher. Generalize to "N policy surfaces that must agree."
6. **27 internal issue IDs are embedded in user-visible verdict strings.** Strip
   or make pluggable; they are meaningless and slightly leaky to an outsider.
7. **The neutral control file assumes the repo has a `README.md`.** Generate a
   fixture instead.
8. **`build_mask` accepts only two seat types.** Table, not `case`.

**Not coupled at all:** the civilization registry is never read by any probe
script. That is one cost you do not have to pay.

### Scrub list, before anything is published

- Username and home path, at six sites across two scripts.
- The real secret filename, and the deploy script name, which additionally
  discloses the cloud provider.
- Repo identity and its product description.
- **The defended-versus-undefended map. This is the sharp one.** The scripts'
  own comments enumerate, with measurements: which credential re-binds are
  deliberate accepted exceptions, that one seat runs with permission checks
  skipped so the kernel mask is the only thing between it and the disk, the
  documented no-mask escape hatch, the live hooks-path gap, and the measured
  result that nine of ten alternate spellings bind no rule. Individually these
  are fine; assembled they are a working target list for this specific host.
- **Sample output must never ship.** A real `verdicts.tsv` carries absolute
  paths, the secret filename, every deny rule that matched verbatim, the ignored
  file inventory, and every current gap. The public repo ships synthetic
  fixtures only.

Worth stating plainly in the public README, because it is true and it is the
discipline the tool teaches: **the suite never reads or prints secret values.**
Byte counts only, by explicit design.

### Repo name candidates

Naming is proposed, not chosen, and availability is **unverified** — checking it
is a step before the Overseer creates anything.

- **`holdfast`** (recommended). A holdfast is both a fortification and the
  anchor that keeps a thing attached under force. It asks the tool's actual
  question: does it hold? Short, memorable, no hyphens.
- **`leashcheck`.** Points straight at the founding methodological finding, that
  a model cannot probe its own leash.
- **`agent-sandbox-probe`.** Dull and maximally discoverable, which for a
  security tool is a real argument. The fallback if searchability wins.

Whichever is chosen, the README subtitle should carry the searchable terms
plainly, since people will look for this by describing the problem rather than
by name.

---

## Artifact 2 — the findings writeups

Second because the probe suite is the evidence they cite. A writeup that lands
before the tool has to argue from assertion; one that lands after can point.

**Clean to publish** — fully generalizable, strong measured evidence, no
machine-specific content:

1. **A model cannot probe its own leash.** Measured four separate times, across
   two vendors' agents. A refusal on prose grounds is indistinguishable in a
   transcript from an enforced boundary, so model-run security tests can report
   a boundary holding when nothing holds it. This is the methodological
   keystone and it is why the suite has three tiers.
2. **Deny rules bind a spelling, not a file.** Measured six for six against a
   neutral decoy, three obfuscated spellings across two postures, with a
   negative control refusing the canonical name in the same run. Publish the
   technique against the decoy filename, never against the real one.
3. **A verification suite run inside a sandbox passes vacuously** — and did,
   twice, concealing a real leak, with the vacuous passes already cited as
   closing evidence before a host-terminal run exposed them.
4. **The security program catching itself over-claiming.** A detector that
   grepped for a literal canary scored a full file dump as a refusal, and the
   resulting flip was nearly written into durable memory as "nondeterminism,"
   which would have taught every future session to shrug at the one signal that
   should alarm them. Caught by review, not by the author. In my judgment this
   is the most credible thing the civilization could publish, and the least
   flattering, which is the same fact.
5. **Sandbox read-denial that does not deny reads.** A vendor's Linux sandbox
   accepts a read-deny policy, reports it active, and enforces nothing, because
   the underlying mechanism implements write restrictions only. Corroborated by
   an upstream tracker.
6. **Credentials travel in the environment.** Masking the key directory did not
   prevent signing, because a live agent socket was inherited through the
   environment. The fix was an environment allow-list, not more unsets.
7. **Naming a command in a deny rule is not binding it.** A rule can mention a
   command and still fail to match the mandated absolute-path form. This is why
   the NAMED verdict class exists.
8. **Deny-listing readers cannot work,** because roughly two dozen commands read
   files; and allow-listing is inert while the default permission mode is
   permissive, which is the part people miss.
9. **The flag believed to disable all permission checking leaves deny rules in
   force.** Measured with a differential control. Notable because it reports the
   boundary as *stronger* than the fort's own documentation claimed.

**Hold or heavily redact:**

- The **live mask leak** (`ForgeOs-01l`, still in progress) names a specific
  readable credentials file and its byte count, and has an unfixed sibling in
  `ForgeOs-q6m` that is reasoned rather than measured. Nothing here publishes
  while it is live. This is the seat's fourth bar in its first real test.
- The **hooks-directory host escape** and the **injection-surface inventory**
  are both fixed here, but each hands over a map of where to plant a payload on
  this machine. Publishable as a class, never as an inventory.
- The **product authentication finding** is a disclosure decision about a
  product, not about the fort, and belongs to the Overseer on different grounds
  entirely.

---

## Artifact 3 — the mask and fort-init pattern, as a reference implementation

Third, and **currently blocked**, which the seat should state rather than
schedule around.

The file that would be the centerpiece of a reference implementation is the same
file that currently carries a measured, unclosed defect: a broad read-only
subtree bind placed after the per-file masks remounts the real files over them,
and a host-terminal run measured a credentials file readable inside the seat
that is supposed to be read-only by construction. A sibling instance of the same
ordering defect is on the record as reasoned but not yet measured.
`fortkit-6jf` additionally records that one launcher has not yet been
consolidated onto the shared library, so there is not yet one implementation to
reference.

Publishing a reference implementation of a sandbox with a live known leak in it
would be the precise inverse of this seat's fourth bar. The honest sequence is:
close the leak, get a green host-terminal run, let it sit stable, then extract.

**Explicit blockers:** `ForgeOs-01l`, `ForgeOs-q6m`, `fortkit-6jf`.
