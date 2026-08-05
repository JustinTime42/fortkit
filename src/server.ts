import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";

import { readWorld } from "./world.ts";

export const worldPage = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>fortkit world</title><style>body{margin:0;background:#17140f;color:#e8ddbf;font:16px system-ui,sans-serif}header{padding:1rem 2rem;background:#302719}main{padding:1rem;display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:1rem}.card{border:1px solid #79633d;background:#211b13;padding:1rem}.gap{color:#ffba8c}.alert{color:#ff8b7b}h2{margin-top:0}ul{padding-left:1.25rem}.muted{color:#b9aa8d}</style><header><strong>Manyhalls world view</strong> <span id="updated" class="muted"></span></header><main id="forts">Loading the registry…</main><script>const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",[String.fromCharCode(34)]:"&quot;","'":"&#39;"}[c]));const list=(title,items,klass='')=>'<h3>'+title+'</h3><ul class="'+klass+'">'+(items.length?items.map(x=>'<li>'+esc(x)+'</li>').join(''):'<li class="muted">none</li>')+'</ul>';function card(f){const git=f.git.branch||'unavailable';const drift=f.git.ahead===null?'unavailable':('ahead '+f.git.ahead+' · behind '+f.git.behind);const beads=f.beads===null?'ABSENT':('ready '+f.beads.ready);const active=f.inProgress.map(b=>b.id+(b.title?' — '+b.title:'')+' ['+(b.seat||b.assignee||'seat unknown')+'; '+(b.model||'model unknown')+']');const alerts=f.watcherAlerts.map(a=>a.ts+' — '+a.detail);return '<article class="card"><h2>'+esc(f.name)+'</h2><p>'+esc(f.present?'present':'ABSENT')+'</p><p>Git: '+esc(git)+' · '+esc(f.git.dirty===null?'state unavailable':f.git.dirty?'dirty':'clean')+' · '+esc(drift)+'</p><p>Beads: <strong>'+esc(beads)+'</strong></p>'+list('In progress',active)+list('Announcements',f.announcements)+list('Watcher alerts',alerts,'alert')+list('Source gaps',f.gaps,'gap')+'</article>'}async function load(){try{const r=await fetch('/world');const data=await r.json();document.querySelector('#forts').innerHTML=data.map(card).join('')||'<p>No registered forts found.</p>';document.querySelector('#updated').textContent='updated '+new Date().toLocaleTimeString()}catch(e){document.querySelector('#forts').textContent='World data unavailable: '+e}}load();setInterval(load,5000);</script></html>`;

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
