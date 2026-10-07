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

type Frontmatter = {
  values: Map<string, string>;
  invented: string[];
  malformed: string[];
};

function codePoints(value: string): number {
  return Array.from(value).length;
}

function parseQuoted(value: string): string | undefined {
  if (value.startsWith('"') && value.endsWith('"'))
    return value.slice(1, -1).replaceAll('\\"', '"');
  if (value.startsWith("'") && value.endsWith("'"))
    return value.slice(1, -1).replaceAll("''", "'");
  return value.includes('"') || value.includes("'") ? undefined : value;
}

function parseInlineList(value: string): string[] | undefined {
  if (!value.startsWith("[") || !value.endsWith("]")) return undefined;
  const items: string[] = [];
  let current = "";
  let quote: '"' | "'" | undefined;
  for (let index = 1; index < value.length - 1; index += 1) {
    const character = value[index];
    if (character === undefined) continue;
    if (quote !== undefined) {
      current += character;
      if (character === quote) {
        if (quote === "'" && value[index + 1] === "'") {
          current += "'";
          index += 1;
        } else quote = undefined;
      }
    } else if (character === '"' || character === "'") {
      quote = character;
      current += character;
    } else if (character === ",") {
      const item = parseQuoted(current.trim());
      if (item === undefined) return undefined;
      items.push(item);
      current = "";
    } else current += character;
  }
  if (quote !== undefined) return undefined;
  const item = parseQuoted(current.trim());
  return item === undefined ? undefined : [...items, item].filter(Boolean);
}

/**
 * Deliberately small YAML subset: scalars, block lists, and inline quoted
 * lists. It decodes YAML's '' and \" escapes; unsupported lines fail safely.
 */
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
  const malformed: string[] = [];
  let currentKey: string | undefined;
  for (const line of source.split("\n")) {
    if (line.trim() === "") continue;
    const key = /^([A-Za-z][\w-]*):(?:\s*(.*))?$/.exec(line);
    if (key) {
      const name = key[1];
      if (name === undefined) continue;
      currentKey = name;
      values.set(name, key[2] ?? "");
      continue;
    }
    const nestedKey = /^ {2}([A-Za-z][\w-]*):\s*(.*)$/.exec(line);
    if (
      nestedKey?.[1] !== undefined &&
      currentKey !== undefined &&
      values.get(currentKey) === ""
    ) {
      // The Herald's rubric is a one-level mapping. Nested values are not
      // otherwise interpreted, but recognizing them keeps the subset strict.
      continue;
    }
    const item = /^\s*-\s*(.*)$/.exec(line);
    if (item?.[1] === undefined || currentKey === undefined) {
      malformed.push(line);
      continue;
    }
    const parsedItem = parseQuoted(item[1].trim());
    if (parsedItem === undefined) malformed.push(line);
    else if (currentKey === "invented") invented.push(parsedItem);
  }
  const inlineInvented = values.get("invented");
  if (
    inlineInvented !== undefined &&
    inlineInvented !== "" &&
    inlineInvented !== "[]"
  ) {
    const parsedItems = parseInlineList(inlineInvented);
    if (parsedItems === undefined)
      malformed.push(`invented: ${inlineInvented}`);
    else invented.push(...parsedItems);
  }
  return {
    body: normalized.slice(close + 5).trim(),
    frontmatter: { values, invented, malformed },
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

function excerpt(value: string, start = 0, length = value.length): string {
  const before = Math.max(0, start - 40);
  const after = Math.min(value.length, start + length + 40);
  return JSON.stringify(
    `${before > 0 ? "…" : ""}${value.slice(before, after)}${after < value.length ? "…" : ""}`,
  );
}

function normalizedForMatch(value: string): string {
  return value.replace(/[\u2018\u2019\u201c\u201d]/g, (character) =>
    character === "\u2018" || character === "\u2019" ? "'" : '"',
  );
}

function allMatches(post: string, matcher: RegExp): RegExpExecArray[] {
  return Array.from(post.matchAll(matcher));
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
  const malformed = frontmatter?.malformed ?? [];
  checks.push(
    missing.length === 0 && malformed.length === 0
      ? check("frontmatter", "pass", "Required frontmatter is present.")
      : check(
          "frontmatter",
          "fail",
          `Missing or malformed frontmatter: ${[...missing, ...malformed.map((line) => excerpt(line))].join(", ")}.`,
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
  const longParagraphs = paragraphs.filter(
    (paragraph) =>
      !isList(paragraph) && sentenceCount(paragraph) > PARAGRAPH_SENTENCE_LIMIT,
  );
  checks.push(
    check(
      "paragraph-sentences",
      longParagraphs.length === 0 ? "pass" : "fail",
      longParagraphs.length === 0
        ? "No prose paragraph exceeds three sentences."
        : `${longParagraphs.length} overlong paragraph(s): ${longParagraphs.map((paragraph) => excerpt(paragraph)).join(", ")}.`,
    ),
  );
  const lastLine =
    post
      .split("\n")
      .filter((line) => line.trim() !== "")
      .at(-1)
      ?.trim() ?? "";
  const normalizedLastLine = normalizedForMatch(lastLine).toLowerCase();
  const bannedCloser =
    BANNED_CLOSERS.find((closer) =>
      new RegExp(
        `\\b${normalizedForMatch(closer)
          .replace(/\.\.\.$/, "")
          .replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`,
        "i",
      ).test(normalizedLastLine),
    ) ??
    (/\bcomment\s+\S+\s+if[^?]*\?$/i.test(normalizedLastLine)
      ? "Comment X if..."
      : undefined);
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
  const emDashes = allMatches(post, /—/g);
  checks.push(
    check(
      "em-dash",
      emDashes.length === 0 ? "pass" : "fail",
      emDashes.length === 0
        ? "No em dashes."
        : `${emDashes.length} em dash(es): ${emDashes.map((match) => excerpt(post, match.index, 1)).join(", ")}.`,
    ),
  );
  const substitute = / – | -- /.exec(post);
  checks.push(
    check(
      "dash-substitute",
      substitute === null ? "pass" : "flag",
      substitute === null
        ? "No spaced dash substitutes."
        : `Dash substitute ${excerpt(post, substitute.index, substitute[0].length)} found.`,
    ),
  );
  const normalizedPost = normalizedForMatch(post).toLowerCase();
  const bannedPhrases = BANNED_PHRASES.flatMap((phrase) => {
    const normalized = normalizedForMatch(phrase)
      .toLowerCase()
      .replace(/(?:\.\.\.|…)$/u, "");
    const prefix = /(?:\.\.\.|…)$/u.test(phrase);
    return allMatches(
      normalizedPost,
      new RegExp(
        `${normalized.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}${prefix ? "\\b" : ""}`,
        "g",
      ),
    );
  });
  checks.push(
    check(
      "banned-phrases",
      bannedPhrases.length === 0 ? "pass" : "fail",
      bannedPhrases.length === 0
        ? "No banned phrases."
        : `${bannedPhrases.length} banned phrase(s): ${bannedPhrases.map((match) => excerpt(post, match.index, match[0].length)).join(", ")}.`,
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
    /\b(?:not|isn't|wasn't)\b[^.!?]{0,100},\s*\b(?:it's|it is|that'?s|that is)\b|\b\w+ isn't the problem,\s*\w+ is\b|\bit wasn't [^.?!]+\.\s*it was\b/i.exec(
      normalizedForMatch(post),
    );
  checks.push(
    check(
      "contrastive-reframe",
      reframe === null ? "pass" : "flag",
      reframe === null
        ? "No contrastive reframe found."
        : `Possible contrastive reframe: ${excerpt(post, reframe.index, reframe[0].length)}.`,
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
    /\b(?:labelled|labelling|neighbours?|behaviours?|colours?|favours?|honours?|centres?|catalogues?|(?:prioritis|deprioritis|organis|realis|recognis|optimis|summaris|analys|apologis|categoris|minimis|maximis)(?:e|ed|ing))\b/i.exec(
      post,
    );
  checks.push(
    check(
      "spelling",
      spelling === null ? "pass" : "flag",
      spelling === null
        ? "No listed British spellings."
        : `Possible British spelling: ${excerpt(post, spelling.index, spelling[0].length)}.`,
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
