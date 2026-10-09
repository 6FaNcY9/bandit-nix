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
const {EventLog} = require('./events');
const {Keeper} = require('./keeper');
const {botView} = require('./view');
const {Settings} = require('./settings');
const {Places} = require('./places');

const cfg = loadConfig();
const log = (who, msg) => console.log(`${new Date().toISOString()} [${who}] ${msg}`);
const world = new WorldModel();
const events = new EventLog();
const stopBlueMap = startBlueMap(world, cfg.bluemapUrl, log);
const runners = new Map(cfg.names.map((n) => [n, new BotRunner(n, {host: cfg.mcHost, port: cfg.mcPort, log, world, protectedAreas: cfg.protectedAreas, supplyChest: cfg.supplyChest, loginSeed: cfg.loginSeed, hostLabel: cfg.hostLabel, onEvent: (b, k, t) => events.add(b, k, t)})]));
const settings = new Settings(process.env.STATE_DIR || '');
for (const r of runners.values()) r.getSettings = () => settings.get(r.name);
const page = fs.readFileSync(path.join(__dirname, 'public', 'index.html'));
// The page is one file with inline script and style: allow exactly those two
// bodies by hash and nothing else (no CDN, no eval, no other origin).
const sha = (re) => `'sha256-${require('node:crypto').createHash('sha256').update(String(page).match(re)?.[1] ?? '').digest('base64')}'`;
const CSP = `default-src 'none'; script-src ${sha(/<script>([\s\S]*?)<\/script>/)}; style-src ${sha(/<style>([\s\S]*?)<\/style>/)}; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;
// Remote workers register themselves in `runners` (see hub.js), so the
// dashboard, /api/state and /api/debug list them next to the lab's bots.
const hub = cfg.workerToken ? new Hub({world, runners, token: cfg.workerToken, log, protectedAreas: cfg.protectedAreas, supplyChest: cfg.supplyChest, events}) : null;
const workerServer = hub ? createWorkerServer(hub) : null;

// tailscale serve sets Tailscale-User-Login for tailnet users. When
// ALLOWED_TS_LOGINS is set, nothing is served without it.
// Standing orders: only with a supply chest and at least one quota; switched off at every start.
const keeper = cfg.keeperQuotas.length ? new Keeper({runners, world, chest: cfg.supplyChest, quotas: cfg.keeperQuotas, site: cfg.keeperSite, events, log}) : null;
// Map markers: the first 'supply' place is the supply chest for every bot, the
// hub's workers and the keeper; the first 'site' place is where the keeper works.
const places = new Places(process.env.STATE_DIR || '');
let supplyChest = cfg.supplyChest;
function applyPlaces() {
  const s = places.first('supply'), site = places.first('site');
  supplyChest = s ? {x: s.x, y: s.y, z: s.z} : cfg.supplyChest;
  for (const r of runners.values()) if (!(r instanceof RemoteRunner)) r.supplyChest = supplyChest;
  if (hub) hub.supplyChest = supplyChest;
  if (keeper) {
    keeper.chest = supplyChest;
    keeper.site = site ? {x: site.x, y: site.y, z: site.z} : cfg.keeperSite;
  }
}
applyPlaces();

// Long jobs survive a restart (deploys restart the container): every 5 s the
// running and queued shift/guard/mine/chop jobs go to STATE_DIR/jobs.json and
// are queued again at start; a mine/chop keeps only what is left of its count.
const KEEP = new Set(['shift', 'guard', 'mine', 'chop']);
const jobsFile = process.env.STATE_DIR ? path.join(process.env.STATE_DIR, 'jobs.json') : null;
const keptJobs = () => {
  const out = {};
  for (const r of runners.values()) {
    if (r instanceof RemoteRunner) continue;
    const list = [r.current, ...r.queue].filter((j) => j && !j.cancelled && KEEP.has(j.type)).map((j) => {
      const args = {...j.args};
      if (args.count && j.collected) args.count = Math.max(1, args.count - j.collected);
      return {type: j.type, args};
    });
    if (list.length) out[r.name] = list;
  }
  return out;
};
// Saved jobs wait until their bot is online (a job started before the login fails at once).
let toResume = {};
if (jobsFile) {
  try {
    toResume = JSON.parse(fs.readFileSync(jobsFile, 'utf8'));
  } catch {} // none saved
}
const resumeUntil = Date.now() + 300000; // a bot still away after 5 min starts with no job
function resumeJobs() {
  if (Date.now() > resumeUntil) toResume = {};
  for (const [name, list] of Object.entries(toResume)) {
    const r = runners.get(name);
    if (!r || r instanceof RemoteRunner) {
      delete toResume[name];
      continue;
    }
    if (!r.online || r.dead) continue;
    delete toResume[name];
    for (const j of list) {
      try {
        r.enqueue(j.type, j.args);
        events.add(name, 'info', `resumed after restart: ${j.type}`);
      } catch {} // an entry the validator refuses is dropped
    }
  }
}
// What the file holds: running/queued jobs, plus jobs still waiting for their bot to log in.
let jobsSaved = '';
function saveJobs(force = false) {
  if (!jobsFile) return null;
  const now = JSON.stringify({...toResume, ...keptJobs()});
  if (!force && now === jobsSaved) return null;
  try {
    fs.writeFileSync(`${jobsFile}.tmp`, now);
    fs.renameSync(`${jobsFile}.tmp`, jobsFile);
    jobsSaved = now;
    return null;
  } catch (e) {
    log('jobs', `could not save: ${e.message}`);
    return e.message;
  }
}
const jobsTimer = jobsFile ? setInterval(() => {
  resumeJobs();
  saveJobs();
}, 2000) : null;
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
const state = () => ({now: Date.now(), lastEventId: events.lastId, keeper: keeper?.state() || null, bots: [...runners.values()].map((r) => ({...r.snapshot(), settings: r instanceof RemoteRunner ? null : settings.get(r.name)})), world: world.snapshot(), protectedAreas: cfg.protectedAreas, supplyChest, places: places.list});

function readJson(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (c) => {
      body += c;
      if (body.length > 8192) { // a 75-block build blueprint is ~3-5 KB
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

// BlueMap low-res tiles (top half colour, bottom half height) for the map,
// fetched server-side so the page stays same-origin. Small in-memory cache.
const TILE_RE = /^\/api\/tile\/(world|world_the_nether|world_the_end)\/([1-3])\/x(-?\d{1,5})\/z(-?\d{1,5})\.png$/;
const tiles = new Map(); // path -> {t, body|null}
async function tile(rel) {
  const hit = tiles.get(rel);
  if (hit && Date.now() - hit.t < 300000) return hit.body;
  let body = null;
  try {
    const r = await fetch(`${cfg.bluemapUrl}/maps/${rel}`, {signal: AbortSignal.timeout(5000)});
    if (r.ok) body = Buffer.from(await r.arrayBuffer());
  } catch {}
  tiles.delete(rel);
  tiles.set(rel, {t: Date.now(), body});
  if (tiles.size > 400) tiles.delete(tiles.keys().next().value); // ponytail: FIFO cap, ~400 tiles x ~300 KB worst case
  return body;
}

const server = http.createServer(async (req, res) => {
  const send = (code, type, body) => {
    res.writeHead(code, {'Content-Type': type, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': CSP, 'Referrer-Policy': 'no-referrer'});
    res.end(body);
  };
  const json = (code, obj) => send(code, 'application/json', JSON.stringify(obj));
  if (!authorized(req)) return json(403, {error: 'forbidden'});
  const url = new URL(req.url, 'http://x');
  if (req.method === 'GET' && url.pathname === '/') return send(200, 'text/html; charset=utf-8', page);
  if (req.method === 'GET' && url.pathname === '/api/state') return json(200, state());
  if (req.method === 'GET' && url.pathname === '/api/events') return json(200, {lastId: events.lastId, events: events.since(Number(url.searchParams.get('since')) || 0)});
  if (req.method === 'GET' && url.pathname === '/api/world') return json(200, world.snapshot());
  const vm = req.method === 'GET' && /^\/api\/view\/(\w{1,16})\.png$/.exec(url.pathname);
  if (vm) {
    const r = runners.get(vm[1]);
    if (!r || r instanceof RemoteRunner || !r.bot?.entity || !r.online) return send(404, 'text/plain', 'no view (offline or remote worker)');
    const now = Date.now(); // ponytail: one frame per bot per 700 ms, shared by all viewers
    if (!r.viewFrame || now - r.viewFrame.t > 700) r.viewFrame = {t: now, body: botView(r.bot, {w: 256, h: 144})};
    res.writeHead(200, {'Content-Type': 'image/png', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
    return res.end(r.viewFrame.body);
  }
  const tm = req.method === 'GET' && cfg.bluemapUrl && TILE_RE.exec(url.pathname);
  if (tm) {
    const body = await tile(`${tm[1]}/tiles/${tm[2]}/x${tm[3]}/z${tm[4]}.png`);
    if (!body) return send(404, 'text/plain', 'no tile');
    res.writeHead(200, {'Content-Type': 'image/png', 'Cache-Control': 'max-age=300', 'X-Content-Type-Options': 'nosniff'});
    return res.end(body);
  }
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
  if (req.method === 'GET' && url.pathname === '/api/keeper') return json(200, keeper ? keeper.state() : {available: false});
  if (req.method === 'POST' && url.pathname === '/api/keeper') {
    if (!sameOrigin(req) || !String(req.headers['content-type']).startsWith('application/json')) return json(403, {error: 'bad origin'});
    try {
      if (!keeper) throw new Error('standing orders are not configured (needs SUPPLY_CHEST and KEEPER_QUOTAS)');
      const {enabled} = await readJson(req);
      if (typeof enabled !== 'boolean') throw new Error('enabled must be true or false');
      keeper.setEnabled(enabled);
      broadcast();
      return json(200, keeper.state());
    } catch (e) {
      return json(400, {error: e.message});
    }
  }
  if (req.method === 'POST' && url.pathname === '/api/places') {
    if (!sameOrigin(req) || !String(req.headers['content-type']).startsWith('application/json')) return json(403, {error: 'bad origin'});
    try {
      const {action, place, name} = await readJson(req);
      if (action === 'set') events.add('map', 'info', `marker ${places.set(place).name} (${place.kind}) at ${place.x} ${place.y} ${place.z}`);
      else if (action === 'delete') { places.remove(name); events.add('map', 'info', `marker ${name} removed`); }
      else throw new Error('action must be set or delete');
      applyPlaces();
      broadcast();
      return json(200, {places: places.list, supplyChest});
    } catch (e) {
      return json(400, {error: e.message});
    }
  }
  if (req.method === 'POST' && url.pathname === '/api/settings') {
    if (!sameOrigin(req) || !String(req.headers['content-type']).startsWith('application/json')) return json(403, {error: 'bad origin'});
    try {
      const {bot, settings: input} = await readJson(req);
      const r = runners.get(bot);
      if (!r || r instanceof RemoteRunner) throw new Error('unknown bot (laptop workers keep their own settings)');
      const now = settings.set(bot, input);
      events.add(bot, 'info', `settings: ${Object.entries(input || {}).map(([k, v]) => `${k} ${v}`).join(', ')}`);
      broadcast();
      return json(200, now);
    } catch (e) {
      return json(400, {error: e.message});
    }
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
      const stopping = type === 'stop' || replace === true;
      for (const r of targets) {
        try {
          r.enqueue(type, args || {}, {replace: replace === true});
          if (stopping) delete toResume[r.name]; // its saved jobs must not come back after a restart or reconnect
        } catch (e) {
          errors.push(`${r.name}: ${e.message}`); // one bot failing must not keep the others from getting the job
        }
      }
      // Stop all is authoritative here, not in the browser: standing orders off first
      // (they would hand idle bots new work), then every pending recovery dropped.
      let keeperOff = false;
      if (all && type === 'stop') {
        toResume = {};
        if (keeper?.enabled) {
          keeper.setEnabled(false);
          keeperOff = true;
        }
      }
      broadcast();
      if (errors.length) throw new Error(errors.join('; '));
      // Persist the stopped state before saying so; the bots are stopped either way.
      const saveErr = stopping ? saveJobs(true) : null;
      const unreached = all ? [...runners.values()].filter((r) => r instanceof RemoteRunner && !r.conn).map((r) => r.name) : [];
      if (saveErr) return json(500, {error: `stopped, but the stopped state could not be saved (${saveErr}): saved jobs may come back after a restart`, unreached});
      return json(200, {ok: true, keeperOff, unreached});
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
const keeperTick = setInterval(() => {
  try {
    keeper?.tick();
  } catch (e) {
    log('keeper', `error: ${e.message}`);
  }
}, 5000);

server.listen(cfg.port, cfg.host, () => {
  log('dashboard', `listening on ${cfg.host}:${cfg.port} (${cfg.allowed.length ? `tailscale logins: ${cfg.allowed.join(',')}` : 'local only'})`);
  for (const r of runners.values()) r.start();
});
workerServer?.listen(cfg.workerPort, cfg.workerHost, () => log('hub', `workers: ws on ${cfg.workerHost}:${cfg.workerPort}/worker (bearer token required)`));

let closing = false;
function shutdown() {
  if (closing) return;
  closing = true;
  clearInterval(jobsTimer); // first: stopping the bots cancels their jobs, which must not be saved
  clearInterval(tick);
  clearInterval(keeperTick);
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
