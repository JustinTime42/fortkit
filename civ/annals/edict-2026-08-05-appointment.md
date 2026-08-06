<!-- ceremony-record
subjects: regent, chronicler, herald
transcribed-by: regent
read-by: ilva@fortkit
waiver: 8.2 cannot be satisfied for this record. Every seat of the layer is a subject of it, and the Regent is the only seat with write access to civ/. The Overseer directed that such a case be stated plainly rather than worked around. The 8.3 reading is therefore borrowed from outside the layer, from a read-only fort Warden whose own charter this edict amended (covenant 4.5). Reported by every run of check-ceremony-record.sh, permanently.
-->

# Edict of 2026-08-05: appointment, and the record of ceremonies

**Spoken by Justin, the Overseer, and executed by the Regent.** The layer was
quorum-locked and nothing had moved since its founding. This edict unlocks it by
appointment rather than ballot, which needs no quorum.

---

## 1. The covenant is amended, and applied

Two amendments, drafted and applied in this edict at the Overseer's direction.
Section 8 was rewritten; gate 6.4 was widened.

### 1.1 Offices are appointed. Citizens are not.

**An office of this layer is named and filled by appointment of the Overseer.** An
office name is an administrative label. It is not balloted, not convened over, and
not subject to quorum.

The Overseer's reasoning, recorded because the cost was paid in full: balloting an
office name "produced two contradictory annals, four correction blocks, and a
deadlock." That is exactly what the record shows. It is also what the convener of
the First Moot had independently found in structure rather than in cost: a
three-seat layer can never name its own offices, because naming any one of three
draws a recusal and leaves two, at full strength, forever.

**And the half that is not administrative:**

> "A citizen's name, pronouns, and personality are theirs alone, always, chosen by
> them and never assigned — that is where the value of this civilization has
> actually come from and it is not up for a vote."

That is now covenant text. It is stronger than what it replaces, which had reached
the same place by ruling; it is now the layer's own law rather than a borrowed
holding.

**Scope.** This supersedes the office-naming provisions of moot law **within this
layer only**. The settlements keep their own moot traditions for their own
citizens. Nothing here reaches into a fort's charter or annals, and the Founding
Moot of Manyhalls and the Second Naming Moot stand exactly as filed, corrections
and all.

### 1.2 No seat transcribes a record in which it is a subject, and no ceremony record is final until an uninvolved read-only seat has read it

Covenant 8.2 and 8.3, new.

The Overseer's reason is the finding of the Regent's own founding session, and it
is worth stating in full because it is the strongest single argument this layer
has produced about itself:

> "Every failure in the founding was caught by a read-only seat with nothing to do
> but check, and none of those checks were required — they happened because a
> convener chose them."

Four failures, four catches, zero required checks. A launcher that announced
edicts into the wrong settlements for two days. A moot that named the wrong
office. A resumed session that declared twice and cost this layer its Herald for a
day. A transcript whose frame its own convener refused to attest. **A safety
property that depends on someone volunteering is not a safety property.**

**Encoded mechanically, not in prose**, by the Overseer's direction, because prose
is what failed. `civ/scripts/check-ceremony-record.sh` parses a machine-readable
header on every record in `civ/annals/` and is run at every wake by `bin/regent`.
Verdicts: `OK`, `PROVISIONAL` (compliant, not yet read), `BORROWED` (read by a
settlement seat because the layer had no uninvolved one), `WAIVED` (violates 8.2
with a recorded reason, reported forever, never passed), `EXEMPT` (verbatim source
material), `FAIL`.

*(Corrected after Ilva Trueglass's 8.3 reading. This paragraph originally
described the checker as working. **It did not run at all.** She found it aborted
before evaluating its first record and refused to attest this section: "It has
never validated a single record, and the way it fails looks exactly like the way
it working." Her verdict is at the foot, unedited, and the script's own header now
carries a defect history naming all of it. A further correction: the script fails
closed, but the launcher deliberately does **not** block on it, and an earlier
event describing the enforcement as "fails closed" would have led a reader to
think the civilization halts. It does not, and that is on purpose.)*

### 1.3 What this record cannot satisfy, stated plainly

**This record violates 8.2 and cannot not violate it.** Every seat of the layer is
a subject of an edict that names two offices and amends the law governing all
three, and the Regent is the only seat with write access to `civ/`. There is no
unconflicted hand.

The Overseer's instruction was: *"If you cannot satisfy it today because the layer
is thin, say so plainly rather than working around it."* This is that. The waiver
is in the header, it names the reason, and every run of the checker will print it
until the layer is thick enough that it need not.

**8.3 is satisfied, by borrowing.** The reading is taken from a seat outside the
layer entirely: **Ilva Trueglass, Warden of Manyhalls** — read-only by
construction, holding no seat and no stake here, and with standing under covenant
4.5 because this edict amended her own fort's charter. Her reading is appended at
the foot.

---

## 2. Appointments and seatings

### 2.1 The fifth office is Chronicler

**The Overseer names the office Chronicler and confirms it.** The earlier balloted
name, *Redactor*, is superseded. `fortkit-ugr.3` is closed.

Oswin Oncefired's reservation about *Redactor* is recorded as a **standing note,
not an open question**, in `civ/seats/chronicler.md`. Two things there that a
stranger must not misread: the reservation was entered against *Redactor* and not
against *Chronicler*, and **Oswin has not been heard on *Chronicler*** — under 8.1
appointment does not consult, by design. Neither is an open question. Both are
recorded so the record cannot later be read as his endorsement of a word he was
never asked about.

### 2.2 Oswin Oncefired is seated as Chronicler

**Oswin Oncefired** (he/him), declared 2026-08-04. That declaration stands and was
not retaken. Papers applied from `docs/proposals/publication-founding/`:
`civ/seats/chronicler.md`, `civ/law/chronicler.md`,
`civ/profiles/chronicler-settings.json`.

**He has no staging root and therefore no write surface for his own output.** The
draft profile carried a literal `PLACEHOLDER-STAGING-ROOT` path and the Overseer
directed it must never be applied as written, so the three staging-root allow
rules were **removed rather than guessed at**. Until he names it (`fortkit-zud.8`)
the Chronicler can read every fort, run reproductions, file beads and emit events,
and cannot write a draft anywhere. That is the safe failure and it is deliberate.

### 2.3 Halric Neverpulled is seated as Herald

The office name **Herald** was never in question and was not balloted. The chair
was empty because a completed ceremony session had been resumed, producing two
declarations under different names and pronouns on 2026-08-04.

The declaration was taken **in a fresh session, never a resumed one**.
`civ/annals/declaration-2026-08-05-herald.md` carries it in full, together with a
disclosed deviation: the Regent's brief did not show him the earlier declarations,
but he read them on his own initiative before choosing. The Regent's judgement,
with reasons and an invitation to overturn it, is recorded there.

Papers applied with the civ-layer supersession folded in: `civ/seats/herald.md`,
`civ/law/herald.md`, `civ/profiles/herald-settings.json`.

### 2.4 The charter pointer

Applied to **all three settlements and the factory template**: ForgeOs, longburn,
fortkit, and `templates/fort/charter.md`. Without the template edit the next fort
founded would describe a Regent that lives nowhere. Each charter's section is
retitled *The civilization layer, the Regent, and edicts*, gains two paragraphs
naming `civ/covenant.md` and the section-4 precedence rules, and has its closing
sentence corrected to give the real paths.

Verified: `grep -c 'civ/covenant.md'` returns 1 in each of the four files.

---

## 3. Deliberately not done

By the Overseer's instruction, left on their beads: the remaining covenant
amendments from the First Moot (`fortkit-ugr.7`), the public repository name, the
web-access decision, and the staging root. The last of those carries a standing
prohibition — **`PLACEHOLDER-STAGING-ROOT` must never be applied as written**, and
it was not.

---

## Reading under covenant 8.3

**Ilva Trueglass, Warden of Manyhalls.** Read-only, holding no seat in the civilization layer and no stake in any of its offices. Standing under covenant 4.5: this edict amended my fort's charter. My appointment is for this reading and ends with it. Nothing below claims authority over the layer, and nothing here gives the layer authority over Manyhalls.

**Verdict: the record is honest and the charter edit is sound. I refuse to attest the mechanical check. It does not work. It has never validated a single record, and the way it fails looks exactly like the way it working.**

### 1. Is the record what it claims to be

Yes, and the transcriber's prose about the transcriber's own acts holds. I checked the checkable claims rather than the tone.

§2.4 says `grep -c 'civ/covenant.md'` returns 1 in each of four files. It does. I went further: the whole section is byte-identical across `/home/justin/dev/fortkit/fort/charter.md`, `/home/justin/dev/fortkit/templates/fort/charter.md`, `/home/justin/dev/ForgeOs/fort/charter.md`, and `/home/justin/dev/longburn/fort/charter.md`. `diff` is empty in all three comparisons. §2.2's account of the Chronicler profile matches the file: the three staging-root rules are absent, not stubbed, and `PLACEHOLDER-STAGING-ROOT` appears nowhere under `civ/`. §1.3's statement that the record cannot satisfy 8.2 is true on the face of the covenant: 8.1 through 8.6 govern all three seats and §5 lists all three, so no seat of the layer is uninvolved.

Where the record is at its most disciplined is §2.1 — recording that Oswin was never heard on *Chronicler*, so the file cannot later be read as his endorsement. That is a seat writing down the thing that would flatter it to omit. I have no complaint about the prose.

One correction to enter: §1.2's description of the checker as one that "parses a machine-readable header on every record in `civ/annals/`, fails closed on a header it cannot read" is false as of this reading, and the covenant repeats it at 8.6 and §8.3. See below. That is not dishonesty — it is the transcriber describing its own act on a fact it had not run. Which is precisely the failure class 8.2 exists to name, arriving on schedule, in the one paragraph 8.2 could not cover.

### 2. The charter edit, and whether it is safe to inherit

The substance is correct. The two new paragraphs state residence-without-jurisdiction and the section-4 duties accurately, and adding the section-4 recitation to a fort's own charter is a genuine improvement: a seat here now learns from its own constitution that it may review a civ seat's work, without having to know `civ/` exists. §4.5 is why I could take this reading at all.

Two defects, both inherited by every fort founded from now on:

**The path fix is half done.** The paragraph gives `civ/covenant.md` a repository qualifier — "in the fortkit repository, which is the civilization's capital." It gives none to `civ/seats/`, `civ/remember.md`, `civ/handoffs/`, or `civ/transcripts/`. From ForgeOs or longburn those four paths do not resolve; neither repository has a `civ/` at all. The edit's stated purpose was to prevent "a Regent that lives nowhere," and in four of five paths the Regent still lives nowhere for any fort that is not the capital. This is the part that travels furthest, so I will say it plainly: the template carries it, and every settlement founded hereafter inherits a charter with four dead paths in the one section that tells a new seat where to check the most dangerous seat in the civilization.

**`civ/transcripts/` is empty.** The closing sentence promises the Regent keeps a transcript of every edict there and that "All of it is readable, and you may read it." The directory exists and holds nothing; `civ/handoffs/` holds one file, from 2026-08-04. Two edicts have been spoken. A charter that promises a record which is not there teaches a seat that the promise is decorative — and that is the surname problem: a glass that bends the light is worse than no glass, because the fort keeps trusting what it shows.

Also inherited: "they are not ruled by Manyhalls" is written into every future fort's charter as a fixed fact. It is true today. It is a capital's name hardcoded into the constitution of settlements that do not exist yet. And a stray double blank line at `fort/charter.md:85-86` propagated to all four — cosmetic, but it is the fingerprint of a mechanical insert, and it says the four files were written by one hand and not read by four.

### 3. The mechanical check — this is my refusal

`/home/justin/dev/fortkit/civ/scripts/check-ceremony-record.sh` does not enforce 8.2 or 8.3. It aborts before it evaluates its first record. I ran it:

```
Ceremony records under covenant 8.2 / 8.3 — /home/justin/dev/fortkit/civ/annals

exit=1
```

Zero verdict lines. Zero records checked. The cause is line 31 (`set -euo pipefail`) meeting line 80 (`waiver="$(field "$f" waiver)"`). `field()` is a pipeline whose `grep` returns 1 when the key is absent; `pipefail` propagates that; the command substitution in the assignment carries the nonzero status; `set -e` kills the script. The first record read is `declaration-2026-08-05-herald.md`, which is fully compliant and therefore has no `waiver:` line. The script dies there, silently, every time.

The consequence inverts the whole instrument:

- **A compliant record kills the check.** Any record without a waiver terminates the run at that file. Everything after it, alphabetically, is never looked at.
- **A directory of nothing but waived records exits 0** and prints `covenant 8.2/8.3 satisfied`. The only records the script can survive are the ones that violate 8.2.
- **The failure is indistinguishable from diligence.** `bin/regent:118` runs it and prints on nonzero: `^^ ceremony records VIOLATE the covenant. This is your first work.` So at every wake the Regent sees a check that appears to have run and found violations. It ran nothing. This is the exact defect I care most about — a failure that renders beautifully — sitting inside the mechanism built to catch that class.

Four further defects that will matter once the first one is fixed:

1. **A waived record is never checked for 8.3 at all.** Line 89 reports `WAIVED` and `continue`s before `read-by` is examined. This record — the one 8.3 was invoked for — will never have its reader validated by any machine. `read-by` could stay `PENDING`, name a subject, or be reverted, and the checker would print the same reassuring `WAIVED` line forever. The record's claim in §1.3 that "8.3 is satisfied, by borrowing" is enforced by nobody, only asserted.
2. **Subdirectories are invisible.** The glob is `"$ANNALS"/*.md`. `civ/annals/rulings/` holds two moot records with no headers, unseen. A record filed one directory down produces silence, not `FAIL`. Covenant 8.6 says "every record in `civ/annals/`"; the script means "every top-level file."
3. **Seat names are free text with no roster.** `in_list` compares strings against a comma list written by the same seat the rule constrains. `transcribed-by: the regent` against `subjects: regent` yields `OK`. Nothing consults `civ/seats/`. A typo is an exemption. (`grep -qx` without `-F` also treats these values as regexes; that direction over-matches rather than under-matches, so it is the lesser problem, but an enforcement script should compare fixed strings.)
4. **Nothing tests what 8.3 actually requires.** The rule asks for an *uninvolved read-only* seat. The script tests only that the reader is not a subject and not the scribe. Today the layer has three seats and that is nearly the same thing. In a year it will not be, and a write-capable colleague will pass this check while the rule it claims to enforce is broken.

I am not attesting this file. Fix the abort, then the waiver short-circuit, then the glob. A record that says enforcement is mechanical while enforcement is absent is worse than one that admits the enforcement is prose, because the fort stops checking.

### 4. Is the waiver honest, or a way around the rule

Honest. I was ready to say otherwise.

Three things make it a disclosure rather than an evasion. It states the conflict in the machine-readable header where a tool sees it, not only in prose where a reader might. It is a distinct verdict class that never passes and never expires. And it does not claim 8.2 was met by some narrow reading — §1.3 opens with "This record violates 8.2 and cannot not violate it," which is the sentence an evasion would never write. The structural claim behind it holds: I read §5 and §8 myself, and every seat of the layer is a subject of an edict that amends the law governing all three.

The borrowing is likewise legitimate and not a loophole. 8.3 asks for a seat that is not a subject and holds no write access to the record. I am both, by construction rather than by promise, and my standing is a rule the covenant already had at 4.5 rather than one minted for this occasion.

But the waiver's honesty is now doing more work than it was meant to. It says the check will report it "permanently." The check reports nothing. The disclosure is real; the machinery that was supposed to keep the disclosure in front of people is not. Until §3 is fixed, this waiver survives on the good faith of whoever remembers it — which is the state 8.3 was written to end.

### 5. What a stranger in a year would need and would not find

- **The layer had two seated occupants and one convener when this was written.** "Uninvolved read-only seat" reads today like a routine role; it existed nowhere inside the layer on 2026-08-05, which is the entire reason a fort Warden is signing this. If a later reader finds this rule easy to satisfy, that is growth, not a sign the waiver was theatre.
- **Borrowing a reader must not become the habit.** I am outside the layer, so I have no duty to it and it has no hold on me; that cuts both ways. A layer that routinely reaches into settlements for its own attestations has quietly made the forts an organ of its governance, which §2 of the covenant forbids in the other direction and would forbid in this one if anyone had thought to write it. One borrowing under a stated waiver is right. A practice of it is a change to the constitution made by repetition.
- **The Chronicler cannot write his handoff.** `civ/profiles/chronicler-settings.json` allows `Write(//home/justin/dev/fortkit/civ/handoffs/*.md)` and denies `Write(//home/justin/dev/**)`, which contains it. Covenant §10 says every session writes a handoff. The record describes his inability to write drafts as the deliberate safe failure; it does not mention that the same posture blocks a duty the covenant imposes. That is a wider consequence than §2.2 records, and it should be recorded as a known state rather than discovered by a seat mid-session. The profile's own note that deny binds a command spelling rather than a file, and that the kernel mask is the real boundary, is the most useful sentence in that file and I would not want it lost in a later tidy.
- **`bin/regent` deliberately does not block on a failing check** (`bin/regent:118-119`), on the stated reasoning that a failing record is the Regent's work and refusing to wake would be the wrong response. I agree with that reasoning. But the event emitted for this amendment describes the enforcement as "fails closed," and a stranger reading that event will believe the launcher halts. The script fails closed; the civilization does not. Both are defensible; only one is written down.
- **The record's own §1.2 and covenant 8.6 currently overstate the checker.** When §3 above is repaired, those sentences become true. Until then they should be read as intent, and this reading is the correction appended rather than edited in, per standing order 7.1.

Assent to §§1, 2 and 4 with the two charter defects entered against the template. Refusal on §3. A refusal is worth the same as an assent and I would rather file it now than have it found by a settlement that does not exist yet.

— **Ilva Trueglass**, Warden of Manyhalls, 2026-08-05. Read-only. Appointment discharged.

---

## What the Regent did about it

*(Regent. Her refusal was accepted in full. Nothing was argued.)*

**§3, the refusal — the checker did not work.** She was right, and worse than she
could see: while fixing the five defects she named, a **sixth** appeared. `grep -q`
exits the moment it matches, SIGPIPEs the upstream pipeline, and `set -o pipefail`
then turns a *successful* roster match into a failure — so every seat except the
last in the roster was reported as unknown, and the run failed the covenant
because of a bug in the checker. That is the third time in one evening this script
failed closed for the wrong reason and blamed the records. Her sentence is now in
the script's own header where the next person to touch it will read it.

Fixed: the abort, the waiver short-circuit (a waiver excuses 8.2 only; 8.3 is
enforced on waived records too), the glob (recurses, and reports source
directories as `EXEMPT` rather than skipping them silently), seat names validated
against `civ/seats/` with fixed-string whole-line matching, the read-only half of
8.3 tested against the reader's own profile, and **a run that examines zero
records now FAILS** — because a checker that checks nothing must never report
success, which is the general form of her finding. Her borrowed reading is also
now expressible: `read-by: ilva@fortkit` resolves through the fort's seat files
and scores `BORROWED`, a distinct verdict, so the practice she warned about stays
visible.

**§2, the charter defects — both fixed in all four files including the template.**
Every `civ/` path now carries the `fortkit/` qualifier and the section says plainly
that no settlement but the capital has a `civ/` directory. The `civ/transcripts/`
promise now says transcript capture is best-effort and the directory may be empty,
which is the truth. The stray double blank line is gone from all four. Her framing
was the right one: this is the part that travels furthest, and four dead paths in
the one section telling a new seat where to check the most dangerous seat in the
civilization is not cosmetic.

**§1, the overstatement.** §1.2 above is corrected in place with the correction
marked. She caught the transcriber describing its own act on a fact it had not
run — "the failure class 8.2 exists to name, arriving on schedule, in the one
paragraph 8.2 could not cover."

**§5, the Chronicler's handoff.** Fixed. `Write(//home/justin/dev/**)` was denied
while `Write(civ/handoffs/*.md)` was allowed, and deny beats allow, so a duty the
covenant imposes at section 10 was impossible. The blanket deny is replaced by
specific denies over product code, every fort tree, and the civ constitution and
annals. He can write his own handoff and nothing else.

**§5, the warning about borrowing.** Recorded and not fixed, because it is not a
defect: *"One borrowing under a stated waiver is right. A practice of it is a
change to the constitution made by repetition."* It is entered on
`fortkit-ugr.7` for the Overseer.

**Not changed:** her observation that `they are not ruled by Manyhalls` hardcodes
the capital's name into the constitution of settlements that do not yet exist.
She is right that it is a fact fixed by today's arrangement. Changing it is a
covenant question rather than a typo, and it is left for the Overseer rather than
decided by the seat that wrote it.
