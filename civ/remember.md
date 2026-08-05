# Civilization-layer memory

Durable operational facts for the seats of `civ/`. Injected every session.
**Append only** — corrections are appended, never edited in.

Formerly `regent/remember.md`; the Regent was the layer's only seat when this
file started, and the entries below from 2026-08-04 are its alone. Later entries
should name the seat if it matters who learned it.

- 2026-08-04: The Regent office was created. It exists because the forts are deliberately unable to fix themselves: constitutions are kernel-read-only to seats, seats are masked, privileged operations go through the airlock. Something has to reach in from outside; this is it.

- 2026-08-04 (edict 2, founding the fifth seat): **`emit.sh` resolves its target event stream from the CURRENT WORKING DIRECTORY, not from the script's own path.** It walks git's common dir so a worktree appends to its main repo's stream — correct for worktrees, a trap for any cross-fort caller. Invoking `$repo/fort/scripts/emit.sh` from somewhere else writes into the CALLER's fort. `bin/regent` did exactly that from the seat's creation, so **every `edict.begun` landed in fortkit and Proofdelve and Farlantern were never told an edict had begun** (fortkit-nvk). Always `( cd "$repo" && ./fort/scripts/emit.sh ... )`. Hardening of emit.sh's contract itself is filed as fortkit-iqp and is a backport-cycle decision, not a unilateral edit.

- 2026-08-04: **`exec` at the end of a launcher silently discards the EXIT trap.** `bin/regent` ended with `exec script ...`, so its `cleanup()` never ran and the launcher had never once emitted `edict.ended`. If a trap must fire, run the child and propagate its status; do not exec. Both defects together meant the Regent's *only* safety property — that no session above the constitution is invisible — was not working in two of three forts.

- 2026-08-04: **The Regent's own launcher was outside the verifier's shell surface** (`verify.sh` lints `bin/fort-init` and `fort/scripts/*.sh`, not `bin/regent`). The most privileged script in the civilization had never been ShellChecked. Filed fortkit-1ca. Note ShellCheck emits SC2329 on a trap-invoked function; it is a false positive, and `-S warning` is clean.

- 2026-08-04: **A retired package can still be writing into the protected `.claude/` directories.** ruflo was globally retired 2026-08-03 and was found to have written `proven-config.json` / `.proven-config-version` into ALL THREE forts' `.claude/` dirs on 08-03 and 08-04, after retirement (fortkit-agf). The lesson is general and worth carrying: **`.claude/**` deny rules bind the AGENT TOOL LAYER only.** A package writing through its own process is not a tool call and passes straight through. "Configs protect themselves" is true against agent accident and inert against supply chain. Do not delete such residue on sight — it is the evidence that the writing is ongoing.

- 2026-08-04: **Verify a bead ID before writing it into source.** I wrote an invented ID into `bin/regent`'s comments before filing the bead, then had to correct it. File first, then reference.

- 2026-08-04: **The moot machinery works, and it works best when the seats are given evidence rather than conclusions.** Running a Founding Moot as independent parallel sub-sessions — each seat with only its own seat file, the moot law, and the rulings of record — produced genuine independence: all three seats coined the same office title without seeing each other. Handing them a verified fact from the record mid-moot (that the root they had converged on was another settlement's ruling name and a living Warden's family word) caused two of them to abandon their own first choice on their own reasoning. Do not ventriloquize a moot; convene one.

- 2026-08-04 (correction to the line above, same session): **convening a moot as independent sub-sessions has a failure mode I walked straight into.** My second-round brief to the convener restated the pool, the rulings sought and the ballots, and omitted WHICH OFFICE was being named. She had it right in round 1 and lost it across the round boundary; nothing re-anchored her. She then wrote the annals, emitted three events and filed a retitle bead — all describing the wrong seat, and the bead would have renamed the Overseer-approved Herald across her spec, seat file and papers. Two rules out of it: **(1) no brief is a delta on an earlier one — every round restates the subject in full, and the participant who will AUTHOR THE RECORD gets the fullest brief, not the shortest.** The independence that makes the moot genuine is exactly what stops a participant's drift being caught before it is written down. **(2) A moot participant should deliberate READ-ONLY.** The Forge and Warden used zero tools and returned text; the convener's session had full tools and wrote fort records unreviewed. The Warden seat here is read-only by construction because a review that can also write is not a review — a ceremony is the same shape. Filed as fortkit-zud.9.

- 2026-08-04: **When a subagent-seat writes into a fort, treat it as an unreviewed change, and check.** I only found the misfiled annals because a Write failed with "file has not been read yet" — the file already existed, written minutes earlier by a session I had spawned. Without that accident I would have overwritten her record, destroying it, and never learned the moot had gone wrong. **After spawning any agent with write access, diff the fort before trusting your own picture of it.**


- 2026-08-04 (edict 3, the covenant): **The civilization layer was established.**
  `civ/` stands beside `fort/` in the fortkit repository, with its own law
  (`civ/covenant.md`), seats, annals, handoffs, events, profiles and emitter. The
  Regent, the Herald, and the fifth security-publication seat moved out of the
  Manyhalls charter into it. The reasoning, worth keeping because it will be
  re-litigated: **a seat that needs root on every fort cannot derive its authority
  from one fort's constitution, and a settlement should not be asked to govern
  something it cannot constrain.** Manyhalls is the capital and hosts the layer;
  **residence is not jurisdiction.** The forts stay autonomous in their own work —
  the covenant explicitly is NOT a management layer over the Mayors (section 2),
  because that is the failure mode this shape invites.

- 2026-08-04: **`civ/scripts/emit.sh` resolves its target stream from its own
  location (`readlink -f $BASH_SOURCE`), not from `$PWD`.** This is the fix
  proposed in fortkit-iqp, implemented here first because a civ seat calls into
  three repositories in one session and cannot afford the fort emitter's
  cwd-relative contract. Verified by invoking it from `/tmp` and watching the
  event land in `civ/events/`. Use it as the reference if the fort emitters are
  ever hardened.

- 2026-08-04: **The briefing reads the covenant and the seat file rather than
  paraphrasing them.** An earlier `bin/regent` restated five standing-conduct
  bullets inline; duplicated law is what goes stale first and gets trusted
  longest. Amending the covenant now amends the briefing by construction.
