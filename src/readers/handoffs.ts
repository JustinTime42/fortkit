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

type HandoffCandidate = Pick<HandoffSection, "file" | "seat" | "date">;

type ReadHandoffCandidate = HandoffCandidate & {
  heading: string | null;
  timestamp: number | null;
};

function handoffCandidates(files: string[]): HandoffCandidate[] {
  return files.flatMap((file) => {
    const match =
      /^([a-z0-9_-]+)-(\d{4}-\d{2}-\d{2})(?:-[a-z0-9._-]+)?\.md$/i.exec(file);
    const seat = match?.[1];
    const date = match?.[2];
    return seat === undefined || date === undefined
      ? []
      : [{ file, seat, date }];
  });
}

function handoffTimestamp(heading: string | null): number | null {
  const isoTimestamp =
    /\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\b/.exec(
      heading ?? "",
    )?.[0];
  if (isoTimestamp === undefined) return null;
  const timestamp = Date.parse(isoTimestamp);
  return Number.isNaN(timestamp) ? null : timestamp;
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
        readCandidate.file > previous.file)
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
