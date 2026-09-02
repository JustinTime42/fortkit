import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

import type { LastHandoff } from "../types.ts";

export type HandoffSection = {
  file: string;
  seat: string;
  date: string;
  heading: string;
  body: string;
};

export type HandoffSectionIndex = {
  id: string;
  fort: string;
  file: string;
  date: string;
  seat: string;
  bead: string | null;
  section: string;
  bodyIncluded: boolean;
};

export type HandoffCandidate = Pick<HandoffSection, "file" | "seat" | "date">;

type ReadHandoffCandidate = HandoffCandidate & {
  heading: string | null;
  timestamp: number | null;
};

/** Parses fort handoff filenames, including the Regent's compact T-stamp form. */
export function parseHandoffFilename(file: string): HandoffCandidate | null {
  const match =
    /^([a-z0-9_-]+)-(\d{4}-\d{2}-\d{2})(?:T\d{6}(?:-[a-z0-9._-]+)?|(?:-[a-z0-9._-]+)?)\.md$/i.exec(
      file,
    );
  const seat = match?.[1];
  const date = match?.[2];
  return seat === undefined || date === undefined ? null : { file, seat, date };
}

function handoffCandidates(files: string[]): HandoffCandidate[] {
  return files.flatMap((file) => {
    const candidate = parseHandoffFilename(file);
    return candidate === null ? [] : [candidate];
  });
}

function handoffTimestamp(heading: string | null): number | null {
  const timestampParts =
    /\b(\d{4}-\d{2}-\d{2}T)~{0,2}(\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2}))\b/.exec(
      heading ?? "",
    );
  if (timestampParts === null) return null;
  const timestamp = Date.parse(`${timestampParts[1]}${timestampParts[2]}`);
  return Number.isNaN(timestamp) ? null : timestamp;
}

function filenameTiebreak(
  candidate: ReadHandoffCandidate,
  previous: ReadHandoffCandidate,
): boolean {
  const plainFilename = (handoff: ReadHandoffCandidate) =>
    `${handoff.seat}-${handoff.date}.md`;
  const candidateIsSuffixed = candidate.file !== plainFilename(candidate);
  const previousIsSuffixed = previous.file !== plainFilename(previous);
  if (candidateIsSuffixed !== previousIsSuffixed) return candidateIsSuffixed;
  return candidate.file > previous.file;
}

async function readHandoffCandidate(
  directory: string,
  candidate: HandoffCandidate,
): Promise<ReadHandoffCandidate> {
  try {
    const firstLine = (await readFile(join(directory, candidate.file), "utf8"))
      .split(/\r?\n/, 1)[0]
      ?.trim();
    const heading =
      firstLine?.startsWith("#") === true
        ? firstLine.replace(/^#+\s*/, "")
        : null;
    return { ...candidate, heading, timestamp: handoffTimestamp(heading) };
  } catch {
    return { ...candidate, heading: null, timestamp: null };
  }
}

/** Reads the newest handoff heading for each seat without treating filenames as paths. */
export async function readLatestHandoffs(
  directory: string,
): Promise<Map<string, string | null> | null> {
  let files: string[];
  try {
    files = await readdir(directory);
  } catch {
    return null;
  }
  const latest = new Map<string, ReadHandoffCandidate>();
  for (const candidate of handoffCandidates(files)) {
    const readCandidate = await readHandoffCandidate(directory, candidate);
    const previous = latest.get(candidate.seat.toLocaleLowerCase());
    if (
      previous === undefined ||
      readCandidate.date > previous.date ||
      (readCandidate.date === previous.date &&
        (readCandidate.timestamp ?? Number.NEGATIVE_INFINITY) >
          (previous.timestamp ?? Number.NEGATIVE_INFINITY)) ||
      (readCandidate.date === previous.date &&
        readCandidate.timestamp === previous.timestamp &&
        filenameTiebreak(readCandidate, previous))
    ) {
      latest.set(candidate.seat.toLocaleLowerCase(), readCandidate);
    }
  }
  const handoffs = new Map<string, string | null>();
  for (const [seat, candidate] of latest) {
    handoffs.set(seat, candidate.heading);
  }
  return handoffs;
}

export async function readLastHandoff(
  directory: string,
): Promise<LastHandoff | null> {
  let files: string[];
  try {
    files = await readdir(directory);
  } catch {
    return null;
  }

  const candidates = handoffCandidates(files);
  candidates.sort((left, right) => right.date.localeCompare(left.date));
  const candidate = candidates[0];
  if (candidate === undefined) {
    return null;
  }
  let firstLine: string;
  try {
    firstLine =
      (await readFile(join(directory, candidate.file), "utf8")).split(
        /\r?\n/,
        1,
      )[0] ?? "";
  } catch {
    return null;
  }
  return {
    seat: candidate.seat,
    date: candidate.date,
    title: firstLine.startsWith("#") ? firstLine.replace(/^#+\s*/, "") : null,
  };
}

export async function readHandoffSections(
  directory: string,
): Promise<HandoffSection[] | null> {
  let files: string[];
  try {
    files = await readdir(directory);
  } catch {
    return null;
  }

  const candidates = handoffCandidates(files).sort((left, right) =>
    left.file.localeCompare(right.file),
  );

  const sections: HandoffSection[] = [];
  for (const candidate of candidates) {
    let contents: string;
    try {
      contents = await readFile(join(directory, candidate.file), "utf8");
    } catch {
      continue;
    }
    const headings = [...contents.matchAll(/^##\s+(.+)$/gm)];
    for (const [index, heading] of headings.entries()) {
      const next = headings[index + 1];
      const start = (heading.index ?? 0) + heading[0].length;
      const end = next?.index ?? contents.length;
      sections.push({
        file: candidate.file,
        seat: candidate.seat,
        date: candidate.date,
        heading: heading[1]?.trim() ?? "",
        body: contents.slice(start, end).trim(),
      });
    }
  }
  return sections;
}

function beadFromHandoffFile(
  file: string,
  seat: string,
  date: string,
): string | null {
  const suffix = file
    .replace(new RegExp(`^${seat}-${date}(?:-|\\.md$)`, "i"), "")
    .replace(/\.md$/i, "")
    .replace(/-(?:r|round)\d+$/i, "");
  const bead = suffix.replace(/^fortkit-/i, "");
  return /^(?=.{3,}$)(?=.*[a-z])(?=.*\d)[a-z0-9]+(?:\.[a-z0-9]+)*$/i.test(bead)
    ? `fortkit-${suffix.replace(/^fortkit-/i, "")}`
    : null;
}

/** Produces stable, body-free references for every section in a handoff window. */
export function indexHandoffSections(
  fort: string,
  sections: HandoffSection[],
  bodyCount = 0,
): HandoffSectionIndex[] {
  const occurrences = new Map<string, number>();
  return sections.map((section, index) => {
    const bead = beadFromHandoffFile(section.file, section.seat, section.date);
    const key = `${section.file}\u0000${section.heading}`;
    const occurrence = occurrences.get(key) ?? 0;
    occurrences.set(key, occurrence + 1);
    const id = [
      fort,
      section.file,
      section.date,
      section.seat,
      bead ?? "",
      section.heading,
      occurrence,
    ]
      .map(encodeURIComponent)
      .join(":");
    return {
      id,
      fort,
      file: section.file,
      date: section.date,
      seat: section.seat,
      bead,
      section: section.heading,
      bodyIncluded: index < bodyCount,
    };
  });
}
