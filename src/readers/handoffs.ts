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

function handoffCandidates(files: string[]): HandoffCandidate[] {
  return files.flatMap((file) => {
    const match = /^([a-z0-9_-]+)-(\d{4}-\d{2}-\d{2})\.md$/i.exec(file);
    const seat = match?.[1];
    const date = match?.[2];
    return seat === undefined || date === undefined
      ? []
      : [{ file, seat, date }];
  });
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
