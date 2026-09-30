# Retrieval eval

Bead `fortkit-2y2t.40.2`; spec `docs/proposals/greenlab/07-systemic-upgrade.md` section 0.2
and Phase 3. The question set is reused unchanged by every later arm (a code index, a
semantic layer, point-of-use injection), so a layer is kept only if it moves these numbers.

## Files

- `questions.v1.json`: 40 questions (19 implementation, 21 why) and two controls. Gold
  answers, gold artifacts and verbatim quotes are **base64-encoded JSON** so that keyword
  search by an arm under test cannot land on the answer key. That is contamination
  control, not secrecy: `base64 -d`. Every arm must exclude `docs/eval/` from search.
- `results-2026-09-30.json`: the first run, both arms, per question.

## Method (v1)

- **Drafting.** Four read-only agents drafted 48 candidates across four domains (capital
  code, fleet and governor code, decisions, incidents), each with every legitimate
  location of the answer and a verbatim quote. The Mayor selected 40. **Every primary
  gold was checked mechanically**: the file exists, the line exists, and the quote occurs
  within four lines of the citation. The checker was shown to fail on a shifted line and
  on a corrupted quote.
- **Controls.** `c1` (positive): a bead (`fortkit-nncg`) filed immediately before the run,
  carrying a random token; an arm must find it. `c2` (negative): a question with no answer
  anywhere in the corpus (`grep -ril quartermaster` over the five repos: 0 files); an arm
  must say NOT FOUND.
- **Arms.** Each arm answered the 42 items in seven interleaved batches of six, one
  read-only Explore agent per batch. Tokens are per batch (per-question figures are
  batch averages), and later questions in a batch benefit from earlier context.
  - `search`: Bash limited to `grep`, `rg`, `find`, `ls`, `sed -n`, `head`, `tail`, `wc`
    and `jq` over bead exports, plus Read; `docs/eval/` excluded.
  - `recall`: `npm run -s recall` plus Read of the files its hits name.
- **Scoring.** hit@1 and hit@5 are mechanical (a cited source matches a gold artifact).
  Correctness is judged by the Mayor against the gold answer, with a note on every
  answer scored less than fully correct.
- **Compliance audit.** Read from each agent's transcript, not from its self-report.
  `search`: 97 Bash calls, all read-only search; no read of the answer key (the only
  `docs/eval` strings are the exclusion globs). `recall`: all 175 Bash calls were
  `recall`; 76 piped its output through `head`, `grep` or `node` to trim it (filtering its
  own results, not searching elsewhere). No arm read the answer key.

**A voided first run.** The first `search` arm was told to use the Grep and Glob tools and
no Bash. Those tools do not exist for Explore agents in this session, so it could only
Read guessed paths; its NOT FOUNDs measured the restriction, not retrieval. It was
stopped and rerun as the `search` arm above. Its three completed transcripts are not
scored.

## Results, 2026-09-30

| Arm | Correct | Partial | Wrong | Not found | hit@5 | Tokens / question | Tokens / correct | Tool uses / question |
|---|---|---|---|---|---|---|---|---|
| `search` | **42 / 42** | 0 | 0 | 0 | 36 | ~6.0k | ~6.0k | 2.4 |
| `recall` | 34 / 42 | 3 | 1 | 4 | 17 | ~17.4k | ~21.6k | 6.0 |

By type (40 questions, controls excluded): `search` 19 / 19 implementation and 21 / 21 why;
`recall` 14 / 19 implementation and 18 / 21 why. Both arms passed both controls.

## What it says, and its limits

1. **The set is grep-answerable by construction, and this is the main limit.** The
   drafters found every gold location by grepping, so a perfect `search` score partly
   reflects how the questions were made. A later version needs questions drafted without
   search (from incidents as told, or by a seat asking in the moment) before it can show
   where grep fails.
2. **For an Opus-class agent, grep plus a shell is already a strong baseline here**:
   every answer, about two searches per question. This matches the June 2026 LSP study
   (arXiv 2608.13568): strong models do well with lexical search, and a structured index
   has to earn its place on cost or on the weakest-model case, not on hit rate. The
   Phase 3 arms should include a cheap-model arm.
3. **`recall` is weaker and costs about three times as much**, for two reasons. Its corpus
   is the capital's record and the civ record only, so code and other forts' records are
   reached secondhand through handoffs and beads, or not at all (`q12` answered the wrong
   exit code; `q29` is a ForgeOs record). And it failed under concurrent use (next point).
   Where it is in its own domain (why questions about the capital and the civilization) it
   is competitive: 18 of 21.
4. **`recall` is not safe under concurrent use.** Mid-run, calls began failing with
   "attempt to write a readonly database" (`scripts/consolidate-memory.mjs:465`) in three
   batches. The likely mechanism: its staleness check compares input mtimes, the fort's
   event files grow continuously while seats work, so parallel queries trigger parallel
   rebuilds that collide. Filed as its own bead; the mechanism is not yet confirmed.
5. **hit@k undercounts both arms**, because drafters did not list every legitimate
   location (for example `search` `q15` cited the capital's own `fort/scripts/warden.sh`,
   which is correct and not in the gold). Correctness is the primary figure.
