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

- 2026-08-04 (First Moot of the Covenant): **A THREE-SEAT LAYER CAN NEVER NAME ITS
  OWN OFFICES.** A seat does not sit in judgment on its own office word, so naming
  any one of three draws a recusal and leaves two — at full strength, forever.
  This is the permanent shape of the layer rather than a startup shortage, so the
  borrowed bench (one seat per settlement, never two from one fort) is the
  ORDINARY instrument and not an emergency measure. Emrith Cairnwright's finding,
  proposed for the covenant on fortkit-ugr.7.

- 2026-08-04: **Two ballots are not a moot, and must never be dressed as one.** A
  twelve-point Borda table over two ballots renders to a stranger exactly like an
  eighteen-point table over three; the tie-break ladder collapses; and "a seat's
  silence decides." The lesser instrument has its own name now: a **concurrence**,
  recorded as one, with no tally drawn, and if the two diverge the question is
  simply NOT DECIDED and goes up marked undecided.

- 2026-08-04: **AN AGENT SESSION IS NOT RESUMABLE ACROSS THE COMPLETION OF THE ACT
  IT PERFORMED.** Measured twice in two days, in two different shapes. Resuming
  the Herald's finished declaration session with a roster correction produced not
  an amendment but a SECOND full declaration under a different name, family word
  and pronouns; the convener ruled the taking of the declaration had failed and the
  chair is still empty. **A correction arriving after an act is complete is a new
  act and must be run as one, or not at all.** Convener's holding and the Regent's
  own conclusion, reached independently the same evening.

- 2026-08-04: **"Later declaration governs" is a rule about streams, not persons,
  and Manyhalls ruling 1 does not say it.** Ruling 1 governs an occupant changing
  HER OWN name and presupposes a settled occupant whose identity is continuous. It
  does not resolve a chair whose filling misfired. Read the other way it would make
  a seat's identity depend on whichever agent invocation happened to finish last.
  The author of ruling 1 declined that reading of her own ruling.

- 2026-08-04: **Declaration is not seating.** The declaration is the occupant's own
  and needs no leave; the seating is a human gate. A declared-but-unseated occupant
  may SPEAK and be quoted, and holds NO ballot. Otherwise declaring would confer
  voice and the gate would stand hollow while formally intact.

- 2026-08-04: **A read-only ceremony caught the error a writing one would have
  filed.** The convener, sitting read-only with nothing to do but read, found the
  Regent's status note wrong in two places — including that the layer had two
  seated occupants when `civ/seats/` held one file — and ruled on the files rather
  than the brief. Her words: "The only reason it did not land is that this chair is
  read-only and had nothing to do but read." The rule bought one day earlier paid
  for itself on its first outing. Do not treat that as luck.

- 2026-08-04: **When you cannot transcribe without a conflict, disclose and get an
  attestation.** The Regent transcribed an annal concerning its own office because
  no unconflicted hand existed in the layer. The remedy adopted: state the conflict
  at the head of the record, mark every passage as whose it is, and have the
  convener attest THE WHOLE DOCUMENT rather than only her quotations — "only a
  reading of the whole can catch a faithful quotation set in a frame that tilts
  it." Purity was not available; visibility was.

- 2026-08-04: **OVERWRITING AN ANNAL IS A RECORDS VIOLATION EVEN BEFORE IT IS
  COMMITTED.** The Regent rewrote its transcription of the moot rather than
  superseding it in place, and the earlier text is gone: never committed, absent
  from `~/.claude/file-history/`, unreadable by anyone. The convener's finding:
  "An annal is a record from the hour it exists, not from the hour git notices it.
  The append-only rule is not about version control; it is about what a reader may
  later discover... the option taken is the only one that makes the transcriber's
  own judgment unreviewable." Keep the superseded text beneath a superseding line.
  Partial remedy available and used: file the SOURCE verbatim, so at least the
  thing the rendering was made from survives.

- 2026-08-04: **"Structure and attribution" does not include EMPHASIS.** Asked to
  state whether any bold inside her quotations had been added, a four-passage
  spot-check found two alterations: bold added to one of her sentences, dropped
  from another. Neither changed a word. Both changed which sentence a reader's eye
  lands on. If you transcribe someone's words, diff the emphasis too, and if you
  cannot audit it exhaustively, say so rather than implying you did.

- 2026-08-04: **An attestation obtained after the fact is weaker than it looks, and
  should say so.** The convener attested the quotations and REFUSED the frame,
  listing eight defects — all in the transcriber's own prose about the
  transcriber's own acts, which is exactly where she had predicted the risk lived.
  The Regent then corrected all eight *unreviewed by her*. That is not an attested
  record and the annal says as much. She assigned the closing check to a seat that
  does not exist yet.
