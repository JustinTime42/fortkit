import type { LintCheck, LintResult, LintResultKind } from "./types.ts";

// Herald's law §4 bar 5 and brand-voice.md §4 set these mechanical ceilings.
export const POST_CHAR_LIMIT = 1_800;
export const HOOK_CHAR_LIMIT = 140;
export const PARAGRAPH_SENTENCE_LIMIT = 3;

export const BANNED_PHRASES = [
  "the part I...",
  "Here's the part worth taking away",
  "What I want to draw out",
  "Three things I would ask of any...",
  "Here's the thing",
  "Let that sink in",
] as const;

export const BANNED_CLOSERS = [
  "Thoughts?",
  "Agree?",
  "Comment X if...",
  "What do you think about AI agents?",
] as const;

export const CHECK_IDS = [
  "frontmatter",
  "length",
  "hook",
  "paragraph-sentences",
  "closing-question",
  "stacked-questions",
  "em-dash",
  "dash-substitute",
  "banned-phrases",
  "invented-declared",
  "contrastive-reframe",
  "setup-line",
  "spelling",
  "shared-stake",
  "one-mechanism",
  "actionable-lesson",
  "cold-test",
] as const;

type Frontmatter = { values: Map<string, string>; invented: string[] };

function codePoints(value: string): number {
  return Array.from(value).length;
}

function parseDraft(text: string): {
  body: string;
  frontmatter: Frontmatter | null;
} {
  const normalized = text.replaceAll("\r\n", "\n");
  if (!normalized.startsWith("---\n"))
    return { body: normalized.trim(), frontmatter: null };
  const close = normalized.indexOf("\n---\n", 4);
  if (close === -1) return { body: normalized.trim(), frontmatter: null };
  const source = normalized.slice(4, close);
  const values = new Map<string, string>();
  const invented: string[] = [];
  let currentKey: string | undefined;
  for (const line of source.split("\n")) {
    const key = /^([A-Za-z][\w-]*):(?:\s*(.*))?$/.exec(line);
    if (key) {
      const name = key[1];
      if (name === undefined) continue;
      currentKey = name;
      values.set(name, key[2] ?? "");
      continue;
    }
    const item = /^\s*-\s*(.*)$/.exec(line);
    if (currentKey === "invented" && item?.[1] !== undefined) {
      invented.push(item[1].replace(/^(?:"|')|(?:"|')$/g, ""));
    }
  }
  const inlineInvented = values.get("invented");
  if (
    inlineInvented !== undefined &&
    inlineInvented !== "" &&
    inlineInvented !== "[]"
  ) {
    invented.push(
      ...inlineInvented
        .replace(/^\[|\]$/g, "")
        .split(",")
        .map((item) => item.trim().replace(/^(?:"|')|(?:"|')$/g, ""))
        .filter(Boolean),
    );
  }
  return {
    body: normalized.slice(close + 5).trim(),
    frontmatter: { values, invented },
  };
}

function postBody(body: string): string {
  return body.split(/^## Long version\s*$/m, 1)[0]?.trim() ?? "";
}

function sentenceCount(value: string): number {
  const trimmed = value.trim();
  if (trimmed === "") return 0;
  return trimmed.split(/(?<=[.!?])\s+/).filter(Boolean).length;
}

function isList(paragraph: string): boolean {
  const lines = paragraph.split("\n").filter((line) => line.trim() !== "");
  return (
    lines.length > 0 &&
    (lines.every((line) => /^\s*(?:[-*•]|\d+\.)\s+/.test(line)) ||
      lines.every(
        (line) => sentenceCount(line) <= 1 && /[.!?:]\s*$/.test(line.trim()),
      ))
  );
}

function check(id: string, result: LintResultKind, detail: string): LintCheck {
  return { id, result, detail };
}

function excerpt(value: string): string {
  return JSON.stringify(
    value.length > 120 ? `${value.slice(0, 117)}...` : value,
  );
}

export function lintDraft(text: string): LintResult {
  const parsed = parseDraft(text);
  const post = postBody(parsed.body);
  const paragraphs = post
    .split(/\n\s*\n+/)
    .filter((paragraph) => paragraph.trim() !== "");
  const hook = paragraphs[0] ?? "";
  const checks: LintCheck[] = [];
  const required = [
    "date",
    "model",
    "status",
    "sources",
    "rubric",
    "invented",
    "postable",
  ];
  const frontmatter = parsed.frontmatter;
  const missing =
    frontmatter === null
      ? required
      : required.filter((key) => !frontmatter.values.has(key));
  checks.push(
    missing.length === 0
      ? check("frontmatter", "pass", "Required frontmatter is present.")
      : check(
          "frontmatter",
          "fail",
          `Missing or malformed frontmatter: ${missing.join(", ")}.`,
        ),
  );
  const postChars = codePoints(post);
  checks.push(
    check(
      "length",
      postChars <= POST_CHAR_LIMIT ? "pass" : "fail",
      postChars <= POST_CHAR_LIMIT
        ? `${postChars} characters (target 800-1300).`
        : `${postChars} characters exceeds ${POST_CHAR_LIMIT}.`,
    ),
  );
  const hookChars = codePoints(hook);
  checks.push(
    check(
      "hook",
      hookChars <= HOOK_CHAR_LIMIT ? "pass" : "fail",
      hookChars <= HOOK_CHAR_LIMIT
        ? `${hookChars} characters.`
        : `${hookChars} characters exceeds ${HOOK_CHAR_LIMIT}: ${excerpt(hook)}.`,
    ),
  );
  const longParagraph = paragraphs.find(
    (paragraph) =>
      !isList(paragraph) && sentenceCount(paragraph) > PARAGRAPH_SENTENCE_LIMIT,
  );
  checks.push(
    check(
      "paragraph-sentences",
      longParagraph === undefined ? "pass" : "fail",
      longParagraph === undefined
        ? "No prose paragraph exceeds three sentences."
        : `Overlong paragraph: ${excerpt(longParagraph)}.`,
    ),
  );
  const lastLine =
    post
      .split("\n")
      .filter((line) => line.trim() !== "")
      .at(-1)
      ?.trim() ?? "";
  const bannedCloser =
    BANNED_CLOSERS.find(
      (closer) => closer.toLowerCase() === lastLine.toLowerCase(),
    ) ??
    (/^comment\s+\S+\s+if/i.test(lastLine) ? "Comment X if..." : undefined);
  checks.push(
    check(
      "closing-question",
      lastLine.endsWith("?") && bannedCloser === undefined ? "pass" : "fail",
      lastLine.endsWith("?") && bannedCloser === undefined
        ? "Post ends with a specific question."
        : `Invalid closing line: ${excerpt(lastLine)}.`,
    ),
  );
  const lastParagraph = paragraphs.at(-1) ?? "";
  const questionCount = (lastParagraph.match(/\?/g) ?? []).length;
  checks.push(
    check(
      "stacked-questions",
      questionCount >= 2 ? "flag" : "pass",
      questionCount >= 2
        ? `Last paragraph has ${questionCount} questions: ${excerpt(lastParagraph)}.`
        : "Last paragraph has fewer than two questions.",
    ),
  );
  const emDashCount = (post.match(/—/g) ?? []).length;
  checks.push(
    check(
      "em-dash",
      emDashCount === 0 ? "pass" : "fail",
      emDashCount === 0
        ? "No em dashes."
        : `${emDashCount} em dash(es) in ${excerpt(post)}.`,
    ),
  );
  const substitute = post.match(/ – | -- /)?.[0];
  checks.push(
    check(
      "dash-substitute",
      substitute === undefined ? "pass" : "flag",
      substitute === undefined
        ? "No spaced dash substitutes."
        : `Dash substitute ${excerpt(substitute)} found.`,
    ),
  );
  const bannedPhrase = BANNED_PHRASES.find((phrase) =>
    post.toLowerCase().includes(phrase.toLowerCase()),
  );
  checks.push(
    check(
      "banned-phrases",
      bannedPhrase === undefined ? "pass" : "fail",
      bannedPhrase === undefined
        ? "No banned phrases."
        : `Banned phrase ${excerpt(bannedPhrase)} found.`,
    ),
  );
  const missingInvented = (parsed.frontmatter?.invented ?? []).find(
    (line) => !post.includes(line),
  );
  checks.push(
    check(
      "invented-declared",
      missingInvented === undefined ? "pass" : "fail",
      missingInvented === undefined
        ? "All declared invented lines appear verbatim."
        : `Declared invented line missing: ${excerpt(missingInvented)}.`,
    ),
  );
  const reframe =
    /\b(?:not|isn't|wasn't)\b[^.!?]{0,100}\b(?:it's|it is|that'?s|that is)\b|\b\w+ isn't the problem, \w+ is\b|\bit wasn't [^.?!]+\.\s*it was\b/i.exec(
      post,
    )?.[0];
  checks.push(
    check(
      "contrastive-reframe",
      reframe === undefined ? "pass" : "flag",
      reframe === undefined
        ? "No contrastive reframe found."
        : `Possible contrastive reframe: ${excerpt(reframe)}.`,
    ),
  );
  const firstFourLines = post
    .split("\n")
    .filter((line) => line.trim() !== "")
    .slice(0, 4)
    .join("\n");
  checks.push(
    check(
      "setup-line",
      /\bAI agents?\b/i.test(firstFourLines) ? "pass" : "flag",
      /\bAI agents?\b/i.test(firstFourLines)
        ? "Setup line mentions AI agents."
        : `No AI-agents setup in first four lines: ${excerpt(firstFourLines)}.`,
    ),
  );
  const spelling =
    /\b(?:\w+ised|\w+ising|labelled|neighbour|behaviour|colour|prioritise)\b/i.exec(
      post,
    )?.[0];
  checks.push(
    check(
      "spelling",
      spelling === undefined ? "pass" : "flag",
      spelling === undefined
        ? "No listed British spellings."
        : `Possible British spelling: ${excerpt(spelling)}.`,
    ),
  );
  for (const id of [
    "shared-stake",
    "one-mechanism",
    "actionable-lesson",
    "cold-test",
  ])
    checks.push(check(id, "judgment", "Herald judgment required."));
  return {
    verdict: checks.some(({ result }) => result === "fail") ? "fail" : "pass",
    counts: { postChars, hookChars, paragraphs: paragraphs.length },
    checks,
  };
}
