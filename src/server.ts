import { readFileSync } from "node:fs";
import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import { stripTypeScriptTypes } from "node:module";

import { readColony } from "./colony-reader.ts";
import { readWorld } from "./world.ts";

const worldPageTemplate = readFileSync(
  new URL("./world-page.html", import.meta.url),
  "utf8",
);
const worldPageScript = readFileSync(
  new URL("./world-page.ts", import.meta.url),
  "utf8",
);
const colonyPageTemplate = readFileSync(
  new URL("./colony-page.html", import.meta.url),
  "utf8",
);
const colonyPageScript = readFileSync(
  new URL("./colony-page.ts", import.meta.url),
  "utf8",
);
const colonyLayoutScript = readFileSync(
  new URL("./colony-layout.ts", import.meta.url),
  "utf8",
);
const ambientScript = readFileSync(
  new URL("./ambient.ts", import.meta.url),
  "utf8",
);

const worldPageScriptMarker = "<!-- world-page-script -->";
const colonyPageScriptMarker = "<!-- colony-page-script -->";

function composePage(
  template: string,
  script: string,
  marker: string,
  pageName: string,
): string {
  if (!template.includes(marker)) {
    throw new Error(`${pageName} page template is missing its script marker`);
  }
  const scriptTag = `<script>\n${stripTypeScriptTypes(script, { mode: "strip" })}</script>`;
  // A replacement callback preserves literal $ sequences in browser source.
  return template.replace(marker, () => scriptTag);
}

function stripModuleSyntax(source: string): string {
  return stripTypeScriptTypes(source, { mode: "strip" })
    .replace(/^\s*import\b[\s\S]*?(?:\bfrom\s+)?["'][^"']+["'];?\s*$/gm, "")
    .replace(
      /^\s*export\s+(?=(?:const|let|var|function|class|async\s+function)\b)/gm,
      "",
    );
}

function assertClassicScript(source: string): void {
  if (/^\s*(?:import|export)\b/m.test(source)) {
    throw new Error("Colony page composition left ESM module syntax");
  }
}

export function composeWorldPage(template: string, script: string): string {
  const composedScript = stripModuleSyntax(script);
  assertClassicScript(composedScript);
  return composePage(template, composedScript, worldPageScriptMarker, "World");
}

export function composeColonyPage(template: string, script: string): string {
  // The page is served as one classic script. Inline its browser-clean shared
  // modules before the entry point, removing only their ESM syntax.
  const shared = [colonyLayoutScript, ambientScript]
    .map(stripModuleSyntax)
    .join("\n");
  const composedScript = `${shared}\n${stripModuleSyntax(script)}`;
  assertClassicScript(composedScript);
  return composePage(
    template,
    composedScript,
    colonyPageScriptMarker,
    "Colony",
  );
}

export const worldPage = composeWorldPage(worldPageTemplate, worldPageScript);
export const colonyPage = composeColonyPage(
  colonyPageTemplate,
  colonyPageScript,
);

type WorldReader = (registryPath: string) => ReturnType<typeof readWorld>;

export function allowedHost(host: string | undefined): boolean {
  return /^(localhost|127\.0\.0\.1)(?::\d+)?$/.test(host ?? "");
}

export function createWorldHandler(
  registryPath: string,
  projectWorld: WorldReader = readWorld,
) {
  return async (request: IncomingMessage, response: ServerResponse) => {
    if (!allowedHost(request.headers.host)) {
      response.writeHead(403, {
        "content-type": "application/json; charset=utf-8",
      });
      response.end(JSON.stringify({ error: "Forbidden host" }));
      return;
    }
    try {
      const requestUrl = new URL(request.url ?? "/", "http://localhost");
      const { pathname } = requestUrl;
      if (pathname === "/world") {
        response.writeHead(200, {
          "content-type": "application/json; charset=utf-8",
        });
        response.end(JSON.stringify(await projectWorld(registryPath)));
        return;
      }
      if (pathname === "/colony") {
        const fort = requestUrl.searchParams.get("fort");
        const colony =
          fort === null ? null : await readColony(registryPath, fort);
        if (colony === null) {
          response.writeHead(404, {
            "content-type": "application/json; charset=utf-8",
          });
          response.end(JSON.stringify({ error: "Colony not found" }));
          return;
        }
        response.writeHead(200, {
          "content-type": "application/json; charset=utf-8",
        });
        response.end(JSON.stringify(colony));
        return;
      }
      if (pathname === "/colony-view") {
        response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        response.end(colonyPage);
        return;
      }
      if (pathname === "/") {
        response.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        response.end(worldPage);
        return;
      }
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("Not found\n");
    } catch {
      response.writeHead(500, {
        "content-type": "application/json; charset=utf-8",
      });
      response.end(JSON.stringify({ error: "World data unavailable" }));
    }
  };
}

export function createWorldServer(registryPath: string) {
  const server = createServer(createWorldHandler(registryPath));
  server.on("error", (error) => {
    console.error(`fortkit world server error: ${error.message}`);
  });
  return server;
}
