import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

import type { LastHandoff } from "../types.ts";

export async function readLastHandoff(
  directory: string,
): Promise<LastHandoff | null> {
  let files: string[];
  try {
    files = await readdir(directory);
  } catch {
    return null;
  }

  const candidates = files.flatMap((file) => {
    const match = /^([a-z0-9_-]+)-(\d{4}-\d{2}-\d{2})\.md$/i.exec(file);
    const seat = match?.[1];
    const date = match?.[2];
    return seat === undefined || date === undefined
      ? []
      : [{ file, seat, date }];
  });
  candidates.sort((left, right) => right.date.localeCompare(left.date));
  const candidate = candidates[0];
  if (candidate === undefined) {
    return null;
  }
  const firstLine =
    (await readFile(join(directory, candidate.file), "utf8")).split(
      /\r?\n/,
      1,
    )[0] ?? "";
  return {
    seat: candidate.seat,
    date: candidate.date,
    title: firstLine.startsWith("#") ? firstLine.replace(/^#+\s*/, "") : null,
  };
}
