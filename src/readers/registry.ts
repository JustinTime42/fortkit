import { readFile } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";

import type { RegistryFort } from "../types.ts";

type RegistryDocument = {
  forts?: unknown;
};

export async function readRegistry(
  registryPath: string,
): Promise<RegistryFort[]> {
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

  return document.forts.flatMap((entry) => {
    if (typeof entry !== "object" || entry === null) {
      return [];
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
      ? []
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
