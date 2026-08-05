import { readFile } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";

import type { RegistryFort } from "../types.ts";

type RegistryDocument = {
  forts?: unknown;
};

export async function readRegistry(
  registryPath: string,
): Promise<RegistryFort[]> {
  return (await readRegistryEntries(registryPath)).flatMap((entry) =>
    entry.path === null ? [] : [{ name: entry.name, path: entry.path }],
  );
}

export type RegistryEntry = {
  name: string;
  path: string | null;
};

export async function readRegistryEntries(
  registryPath: string,
): Promise<RegistryEntry[]> {
  let document: RegistryDocument;
  try {
    document = JSON.parse(
      await readFile(registryPath, "utf8"),
    ) as RegistryDocument;
  } catch {
    return [];
  }

  if (!Array.isArray(document.forts)) {
    return [];
  }

  return document.forts.flatMap<RegistryEntry>((entry, index) => {
    if (typeof entry !== "object" || entry === null) {
      return [{ name: `[malformed registry entry ${index + 1}]`, path: null }];
    }
    const fort = entry as Record<string, unknown>;
    const path = typeof fort.repo === "string" ? fort.repo : null;
    const name =
      typeof fort.fort_name === "string"
        ? fort.fort_name
        : typeof fort.project === "string"
          ? fort.project
          : null;

    return path === null || name === null
      ? [{ name: `[malformed registry entry ${index + 1}]`, path: null }]
      : [
          {
            name,
            path: isAbsolute(path)
              ? path
              : resolve(dirname(registryPath), path),
          },
        ];
  });
}
