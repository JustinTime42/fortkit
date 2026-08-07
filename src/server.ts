import { readFileSync } from "node:fs";
import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";

import { readWorld } from "./world.ts";

export const worldPage = readFileSync(
  new URL("./world-page.html", import.meta.url),
  "utf8",
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
      const pathname = new URL(request.url ?? "/", "http://localhost").pathname;
      if (pathname === "/world") {
        response.writeHead(200, {
          "content-type": "application/json; charset=utf-8",
        });
        response.end(JSON.stringify(await projectWorld(registryPath)));
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
