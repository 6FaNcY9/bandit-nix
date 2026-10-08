#!/usr/bin/env node
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const {WebSocketServer} = require('ws');
const {loadConfig} = require('./config');
const {BotRunner} = require('./bots');
const {WorldModel, startBlueMap} = require('./world');
const {WINDOW_MS} = require('./debug');
const {Hub, RemoteRunner, createWorkerServer} = require('./hub');

const cfg = loadConfig();
const log = (who, msg) => console.log(`${new Date().toISOString()} [${who}] ${msg}`);
const world = new WorldModel();
const stopBlueMap = startBlueMap(world, cfg.bluemapUrl, log);
const runners = new Map(cfg.names.map((n) => [n, new BotRunner(n, {host: cfg.mcHost, port: cfg.mcPort, log, world, protectedAreas: cfg.protectedAreas, supplyChest: cfg.supplyChest, loginSeed: cfg.loginSeed, hostLabel: cfg.hostLabel})]));
const page = fs.readFileSync(path.join(__dirname, 'public', 'index.html'));
// Remote workers register themselves in `runners` (see hub.js), so the
// dashboard, /api/state and /api/debug list them next to the lab's bots.
const hub = cfg.workerToken ? new Hub({world, runners, token: cfg.workerToken, log, protectedAreas: cfg.protectedAreas, supplyChest: cfg.supplyChest}) : null;
const workerServer = hub ? createWorkerServer(hub) : null;

// tailscale serve sets Tailscale-User-Login for tailnet users. When
// ALLOWED_TS_LOGINS is set, nothing is served without it.
const authorized = (req) => !cfg.allowed.length || cfg.allowed.includes(req.headers['tailscale-user-login']);
// Cross-site guard: browsers send Origin on POST/WS; it must match Host.
const sameOrigin = (req) => {
  const o = req.headers.origin;
  if (!o) return true;
  try {
    return new URL(o).host === req.headers.host;
  } catch {
    return false;
  }
};
const state = () => ({now: Date.now(), bots: [...runners.values()].map((r) => r.snapshot()), world: world.snapshot(), protectedAreas: cfg.protectedAreas, supplyChest: cfg.supplyChest});

function readJson(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (c) => {
      body += c;
      if (body.length > 4096) {
        reject(new Error('body too large'));
        req.destroy();
      }
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(body));
      } catch {
        reject(new Error('invalid JSON'));
      }
    });
  });
}

const server = http.createServer(async (req, res) => {
  const send = (code, type, body) => {
    res.writeHead(code, {'Content-Type': type, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
    res.end(body);
  };
  const json = (code, obj) => send(code, 'application/json', JSON.stringify(obj));
  if (!authorized(req)) return json(403, {error: 'forbidden'});
  const url = new URL(req.url, 'http://x');
  if (req.method === 'GET' && url.pathname === '/') return send(200, 'text/html; charset=utf-8', page);
  if (req.method === 'GET' && url.pathname === '/api/state') return json(200, state());
  if (req.method === 'GET' && url.pathname === '/api/world') return json(200, world.snapshot());
  if (req.method === 'GET' && url.pathname === '/api/debug') {
    const bots = [...runners.values()].map((r) => {
      try {
        return r.debug();
      } catch (e) {
        return {name: r.name, error: String(e.message || e)};
      }
    });
    // Reservation counters summed per worker host (remote bots only).
    const workers = {};
    for (const b of bots) {
      if (!b.remote || !b.claims) continue;
      const w = (workers[b.host] ||= {bots: [], granted: 0, refused: 0, timedOut: 0});
      w.bots.push(b.name);
      for (const k of ['granted', 'refused', 'timedOut']) w[k] += b.claims[k];
    }
    return json(200, {generatedAt: new Date().toISOString(), generatedAtMs: Date.now(), windowS: WINDOW_MS / 1000, bots, workers});
  }
  if (req.method === 'POST' && url.pathname === '/api/job') {
    if (!sameOrigin(req) || !String(req.headers['content-type']).startsWith('application/json')) return json(403, {error: 'bad origin'});
    try {
      const {bots, type, args, replace} = await readJson(req);
      // "all" skips remote bots whose worker is away, so a Stop reaches every
      // bot that can still hear it; naming an offline bot is an error.
      const all = bots === 'all';
      const targets = all ? [...runners.values()].filter((r) => !(r instanceof RemoteRunner) || r.conn) : (Array.isArray(bots) ? bots : []).map((n) => runners.get(n));
      if (!targets.length || targets.includes(undefined)) throw new Error('unknown bot');
      const errors = [];
      for (const r of targets) {
        try {
          r.enqueue(type, args || {}, {replace: replace === true});
        } catch (e) {
          errors.push(`${r.name}: ${e.message}`); // one bot failing must not keep the others from getting the job
        }
      }
      broadcast();
      if (errors.length) throw new Error(errors.join('; '));
      return json(200, {ok: true});
    } catch (e) {
      return json(400, {error: e.message});
    }
  }
  return json(404, {error: 'not found'});
});

const wss = new WebSocketServer({noServer: true});
server.on('upgrade', (req, socket, head) => {
  if (!authorized(req) || !sameOrigin(req) || req.url !== '/ws') {
    socket.write('HTTP/1.1 403 Forbidden\r\nConnection: close\r\n\r\n');
    return socket.destroy();
  }
  wss.handleUpgrade(req, socket, head, (ws) => ws.send(JSON.stringify(state())));
});
function broadcast() {
  if (!wss.clients.size) return;
  const msg = JSON.stringify(state());
  for (const c of wss.clients) if (c.readyState === 1) c.send(msg);
}
const tick = setInterval(() => {
  broadcast();
  hub?.broadcastWorld();
}, 1000);

server.listen(cfg.port, cfg.host, () => {
  log('dashboard', `listening on ${cfg.host}:${cfg.port} (${cfg.allowed.length ? `tailscale logins: ${cfg.allowed.join(',')}` : 'local only'})`);
  for (const r of runners.values()) r.start();
});
workerServer?.listen(cfg.workerPort, cfg.workerHost, () => log('hub', `workers: ws on ${cfg.workerHost}:${cfg.workerPort}/worker (bearer token required)`));

let closing = false;
function shutdown() {
  if (closing) return;
  closing = true;
  clearInterval(tick);
  stopBlueMap();
  hub?.close();
  for (const r of runners.values()) r.shutdown();
  for (const c of wss.clients) c.close();
  server.close();
  workerServer?.close();
  setTimeout(() => process.exit(0), 500);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
