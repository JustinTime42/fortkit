# Scionhall and Manyhalls compared: what to keep from each

Written 2026-11-24 by the Regent (Calder Sealbroken, session
2026-11-22T135150, model fable) at the Overseer's request: "a really thorough
audit of scionhall and manyhalls ... I'm interested in keeping the best of
both ... scionhall was attempting to create fort infra as a versioned package
for easy deployment to new products."

## How this was made, and how far to trust it

- Four read-only audit agents, one each on: Scionhall's package design and
  state; the running machinery of both forts, feature by feature; the two
  civilization layers (Greenlab and production); the two factories. They ran
  no tests and launched nothing. Their findings are read from source, beads
  and event records.
- The Regent measured two of their claims (section 5) and holds the other
  measurements of Manyhalls from the same day
  (`2026-11-24-manyhalls-gold-standard-audit.md`).
- Scionhall is at `~/dev/greenlab/forts/scionhall`. Its bead states were read
  from its export of 2026-10-28. A Scionhall Mayor session was started on
  2026-11-24 at 19:33, so its state may have moved since.

## 1. The short answer

- **Manyhalls has the better working fort.** It carries a newer copy of the
  fleet (122 fleet functions against 92), a larger verifier (56 steps against
  33, 45 harnesses against 26), the Workbench seat, the nightly verify, the
  signing desk's landing classes, and everything Proofdelve learned between
  late September and mid November.
- **Scionhall has the better boundary and the only release design.** Its
  sandbox hides the home directory instead of listing what to protect, and it
  designed, and partly built, a package with a manifest, a release review, a
  founding proof and a pin.
- **Neither can upgrade a fort that already exists**, and neither records
  which release a fort was founded from.
- **Scionhall never cut a release.** No tag, no manifest file; its package
  still says version 0.0.0. Its first release candidate failed its own
  founding proof on 2026-10-19 and the fix round stopped one bead short.

## 2. What Scionhall designed, and how far it got

The package is `core/` + `templates/` + `bin/`: the fort skeleton (launchers,
fleet, sandbox library, signing desk, harnesses, checklists, seat files), a
small typed library, a founder and a manifest tool.

The intended life of a release:
1. Edit the package source through the fleet, while the fort itself runs the
   last signed release.
2. Cut a candidate. Review it in six areas plus an integration pass.
3. Found a throwaway fort from the candidate and run everything in it.
4. Tag it, write a manifest of file hashes, and have the Overseer sign.
5. Pin: render the release for an existing fort into a scratch directory,
   diff it against what the fort runs, and copy it over by hand.

Built and tested: the manifest tool (generate, verify, fails closed on a
missing or extra file); the founder with a roster check before any write; a
render-only mode for an existing fort; identity as a data file
(`roster.json`), proven by founding twice and getting byte-identical
launchers; the typed tracker adapter and structured Warden verdicts (unit
tested, never run end to end); a "templates leg" in the verifier that renders
a throwaway fort and lints and runs harnesses on the result.

Specified only: the tag and manifest file, the signature, the pin, any
upgrade tool, three-way merge of local changes (the spec names Copier),
cryptographic signing.

What stopped it:
- The founding proof failed: the founded fort's own verifier was red (51 lint
  findings in rendered files) and its end-to-end fleet harness was red (the
  fixture forts lacked a roster). Seven fixes merged the same day.
  `scionhall-7cl.150` is still open and is the last blocker before a new
  candidate.
- The pin would have reverted three fixes made to the running fort whose
  package halves never landed. That question (`scionhall-7cl.18`) has waited
  on the Overseer since 2026-10-28.
- Cost: about 163 beads and 710 commits toward a first release.

## 3. The running machinery, side by side

Manyhalls has and Scionhall lacks:
- verify tiers, reuse of the post-merge verify, and the nightly full verify;
- landing classes (`sign-to-land`, `lands-on-review`), the Keep's audit
  checked before a signed landing, stale-signature handling;
- the fix-forward verdict and tiered findings;
- reap order by priority, the memory gate, the supervisor's back-off probe;
- the Workbench seat; the loop watchdog; the airlock runner;
- work-in-progress rescue and leftover-process reaping after a Forge session;
- the subagent allowlist hook; the ssh client config passed through a pipe;
- posture-aware smokes, the boundary probe as adapted this week.

Scionhall has and Manyhalls lacks:
- **the home-directory inversion** (`greenlab_isolate`): `$HOME` is an empty
  tmpfs and only an allowlist is put back; it fails closed and checks its own
  output;
- **a scrub of credential-shaped environment variables**; **a process
  namespace**; **private `/run/user` and `/var/tmp`**; each seat sees only its
  own runtime's login;
- **a wall-clock cap on Forge sessions**, with a harness. Manyhalls has no
  Forge timeout at all;
- a model ladder that climbs one rung per return;
- frontier-session leases: a cap on concurrent subscription sessions across
  forts, with back-off after a rate limit;
- the Warden's scratch copy made by `git archive` of the reviewed commit, not
  a copy of the working tree;
- a test-registration check: a test file that registers no test turns the
  verifier red (written after a model deleted its tests to go green);
- `emit.sh` resolving its stream from its own location, not the working
  directory (the defect behind this civilization's oldest recorded incident);
- the bead tracker reachable from a masked Forge in the full posture
  (`DOLT_ROOT_PATH`);
- the release manifest, the roster-as-data, the templates leg.

Tried in Greenlab and not worth keeping as built:
- The local-model Forge (Hermes with 7B models): no bead was completed
  honestly in any run.
- The Effect Gateway: well tested (45 of 45) and never used; its one grant
  expired on 2026-10-24. Its journal design answers a known gap in the airlock
  (ADV-0013) and is worth keeping as a pattern.
- "Tripwire" review, where a green bead merges first and is reviewed after:
  it conflicts with the signing desk and gate 1.

## 4. The two factories

| | Manyhalls | Scionhall |
|---|---|---|
| Founds into | an existing product repository | only `~/dev/greenlab/forts/<slug>` |
| Templates come from | a generator that derives them from the running fort | hand-kept source beside a running copy |
| Day zero | uncommitted; verifier red at one stub step by design | committed; product steps pass as "not run" |
| Seat identity | hand-edited into package files after the moot | a data file the launchers read |
| Refuses before writing | yes, thoroughly | yes, plus a roster check |
| Release identity | none | manifest tool built; nothing cut |
| Upgrade | none | render-only mode built; the rest specified |

Recorded failures of each approach:
- Generating from a live fort copies its live state into the factory (the
  fleet was once shipped enabled; model choices and the posture are still
  copied), reverts a fix made directly to a template, and depends on about 60
  exact-text rules. Nothing makes regeneration happen.
- Hand-kept templates beside a running copy drift from it, and the package
  passed every gate and failed in the first fort founded from it.
- Both put per-fort configuration inside package files (gate paths, model
  choices, the product's own verifier step, `fleet.conf`). Any re-render
  overwrites it. This is the same defect as Scionhall's pin-revert.

## 5. Two things found along the way, both measured

1. **Scionhall's timers are still running.** `scionhall-scratch-reaper.timer`
   fires hourly and removes any `/tmp/warden-*` directory older than two hours
   with no lock held, whichever fort left it. On 2026-11-24 it removed
   leftovers from Proofdelve's and Manyhalls's Wardens. So far that is
   residue; a long review using such a directory would lose it.
   `scionhall-fleet-supervisor.timer` also still fires every two minutes.
2. **In the `secrets-only` posture a Manyhalls seat can write the host's
   startup files and Greenlab's control files.** Measured from a Mayor mask
   with permission tests only: `~/.bashrc`, `~/.local/bin`,
   `~/.config/systemd/user`, the Greenlab capital (`bin/governor`, its
   ceilings, its sandbox library), its spending ledger and its stored logins
   are all writable. Registered forts' repositories are read-only as intended.
   So `secrets-only` stops accidents and hides secrets; it is not a wall
   against a seat that has been steered. Scionhall's inversion is the wall.

## 6. Recommendation: one fort, one package

Keep Manyhalls as the fort and the capital. Bring over from Scionhall, in
this order:

A. **Cheap and self-contained** (days, Regent work, each with its harness):
   1. the Forge wall-clock cap;
   2. `emit.sh` resolving from its own location, merged with Manyhalls's
      argument checks;
   3. the credential-variable scrub;
   4. the process namespace and private `/run/user` (already open here as
      `fortkit-e4q` and `fortkit-tmym`);
   5. `DOLT_ROOT_PATH` for the Forge;
   6. the Warden's copy by `git archive`;
   7. the test-registration check, ported to vitest.

B. **The boundary** (a design sitting, then a build): the home-directory
   inversion as a third posture beside `full` and `secrets-only`, with an
   allowlist for what production seats need (toolchains, the fort, its state,
   the seat's own login, read access to other forts for the digest). This is
   what makes the fort safe to show and to teach from.

C. **The package** (the larger project; decide its shape before building):
   1. Per-fort data first. Move gate paths, models, fleet sizes, the posture,
      seat identity and the product's verifier step out of package files into
      one per-fort data file and one per-fort script. Without this every
      upgrade overwrites local choices.
   2. A release is a tag, a manifest of hashes (Scionhall's tool), and the
      Overseer's signature.
   3. A lock file in each founded fort recording the release and the hash of
      every package-owned file as rendered. A verifier step that compares the
      two replaces the drift watcher.
   4. An upgrade command: render the old release, render the new one, merge
      three ways against the fort's tree, apply on a branch as that fort's own
      bead, run its verifier, rewrite the lock.
   5. A release proof run on the host: found a throwaway fort with the real
      founder and run its whole verifier, the end-to-end harness, the mask
      harness and one real review.
   6. Keep Manyhalls's generator as the way to import from a running fort into
      the package, reviewed like any change; stop using it as the release
      mechanism.

D. **Greenlab itself**: stop Scionhall's two timers; answer or close
   `scionhall-7cl.18`; decide whether Greenlab is retired (its forts reaped to
   bundles, as it did with its own throwaways) or kept as the place where the
   package is built. Building the package in Manyhalls avoids keeping two
   lineages current.

## 7. What was not checked

No test, harness or probe of Scionhall was run. The plot fort and the bundled
throwaway forts were not opened. Per-harness case counts were not compared.
Whether production's `.env` files in other forts are readable from a
Manyhalls seat was inferred from code and not measured.
