#!/usr/bin/env node
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const {WebSocketServer} = require('ws');
const {loadConfig} = require('./config');
const {BotRunner, keptOf, VALIDATE} = require('./bots');
const {WorldModel, startBlueMap} = require('./world');
const {WINDOW_MS} = require('./debug');
const {Hub, RemoteRunner, createWorkerServer} = require('./hub');
const {EventLog} = require('./events');
const {NtfyNotifier} = require('./notify');
const {Keeper} = require('./keeper');
const {botView} = require('./view');
const {scanAround} = require('./scan');
const {Alerts, chestWarnings} = require('./alerts');
const {Settings} = require('./settings');
const {Places} = require('./places');
const {Projects, PROJECTS} = require('./projects');
const {Crews} = require('./crews');
const agentauth = require('./agentauth');
const {Slayer} = require('./slayer');

const cfg = loadConfig();
const log = (who, msg) => console.log(`${new Date().toISOString()} [${who}] ${msg}`);
const world = new WorldModel();
const notifier = new NtfyNotifier();
const events = new EventLog({onAdd: (e) => notifier.event(e)});
// What the LLM agents said and chose (POST /api/decision from the agent service), kept apart so
// they never push job events out of the 200-entry event log.
const decisions = new EventLog();
const slayer = new Slayer({url: cfg.slayerUrl, cmd: cfg.slayerStatusCmd, decisions});
const agentStatuses = new Map(); // agent -> its last POST /api/agentstatus (goal, workers, role, t)
const stopBlueMap = startBlueMap(world, cfg.bluemapUrl, log);
const runners = new Map(cfg.names.map((n) => [n, new BotRunner(n, {host: cfg.mcHost, port: cfg.mcPort, log, world, protectedAreas: cfg.protectedAreas, supplyChest: cfg.supplyChest, loginSeed: cfg.loginSeed, hostLabel: cfg.hostLabel, onEvent: (b, k, t) => events.add(b, k, t)})]));
const settings = new Settings(process.env.STATE_DIR || '');
const projects = new Projects(process.env.STATE_DIR || '');
const crews = new Crews(process.env.STATE_DIR || '', {agentBots: cfg.agentBots, bots: cfg.names});
for (const r of runners.values()) r.getSettings = () => settings.get(r.name);
const page = fs.readFileSync(path.join(__dirname, 'public', 'index.html'));
// The page is one file with inline script and style: allow exactly those two
// bodies by hash and nothing else (no CDN, no eval, no other origin).
const sha = (re) => `'sha256-${require('node:crypto').createHash('sha256').update(String(page).match(re)?.[1] ?? '').digest('base64')}'`;
const CSP = `default-src 'none'; script-src ${sha(/<script>([\s\S]*?)<\/script>/)}; style-src ${sha(/<style>([\s\S]*?)<\/style>/)}; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`;
// Remote workers register themselves in `runners` (see hub.js), so the
// dashboard, /api/state and /api/debug list them next to the lab's bots.
const hub = cfg.workerToken ? new Hub({world, runners, token: cfg.workerToken, workers: cfg.hubWorkers, log, protectedAreas: cfg.protectedAreas, supplyChest: cfg.supplyChest, events, settings}) : null;
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
const jobsFile = process.env.STATE_DIR ? path.join(process.env.STATE_DIR, 'jobs.json') : null;
// A worker's bots report their own list (hub.js), so bot16-bot18 survive a hub restart too.
const keptJobs = () => {
  const out = {};
  for (const r of runners.values()) {
    const list = r instanceof RemoteRunner ? r.kept : keptOf(r);
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
    if (!r) continue; // a remote bot whose worker has not connected yet: the 5 min window decides
    const remote = r instanceof RemoteRunner;
    if (!r.online || (remote ? r.snap.dead : r.dead)) continue;
    delete toResume[name];
    if (remote && (r.snap.job || r.snap.queue.length)) continue; // the worker kept playing through the hub restart
    if (remote) r.kept = list; // keep them in the saved file until the worker's next status reports them
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
const peer = (req) => String(req.socket?.remoteAddress || '').replace(/^::ffff:/, '');
const authorized = (req) => {
  if (!cfg.allowed.length) return true;
  if (cfg.trustedProxies.length && !cfg.trustedProxies.includes(peer(req))) return false;
  return cfg.allowed.includes(req.headers['tailscale-user-login']);
};
const agentTokenHash = cfg.agentToken ? agentauth.hash(cfg.agentToken) : null;
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
const state = () => ({now: Date.now(), lastEventId: events.lastId, keeper: keeper?.state() || null, bots: [...runners.values()].map((r) => ({...r.snapshot(), settings: settings.get(r.name)})), world: world.snapshot(), protectedAreas: cfg.protectedAreas, supplyChest, places: places.list, projects: projects.view(), chest: world.stock && {warnings: chestWarnings(world.stock.items, world.stock.free)}});

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
  const url = new URL(req.url, 'http://x');
  // A request with a bearer is the agent service (H5) and nothing else: a wrong token never falls
  // back to the human path, and the token only reaches state, events and its own bots' jobs.
  const agent = agentauth.bearerMatches(req.headers.authorization, agentTokenHash);
  if (agent === false || (agent && !agentauth.agentEndpoint(req.method, url.pathname))) return json(403, {error: 'forbidden'});
  if (!agent && !authorized(req)) {
    if (req.headers['tailscale-user-login']) log('auth', `refused a Tailscale identity from ${peer(req)} (not a trusted proxy)`);
    return json(403, {error: 'forbidden'});
  }
  if (req.method === 'GET' && url.pathname === '/') return send(200, 'text/html; charset=utf-8', page);
  if (req.method === 'GET' && url.pathname === '/api/state') return json(200, state());
  if (req.method === 'GET' && url.pathname === '/api/events') return json(200, {lastId: events.lastId, events: events.since(Number(url.searchParams.get('since')) || 0)});
  if (req.method === 'GET' && url.pathname === '/api/decisions') return json(200, {lastId: decisions.lastId, events: decisions.since(Number(url.searchParams.get('since')) || 0)});
  if (req.method === 'GET' && url.pathname === '/api/slayer') return json(200, slayer.view());
  if (req.method === 'POST' && url.pathname === '/api/decision') {
    if (!agent) return json(403, {error: 'forbidden'}); // only the agent service reports decisions
    try {
      const {bot, text, backend = 'lab'} = await readJson(req);
      if (!cfg.agentBots.includes(bot) || typeof text !== 'string') throw new Error('bot must be an agent bot, text a string');
      if (!agentauth.validBackend(backend)) throw new Error('backend must be a name of at most 128 characters');
      decisions.add(bot, 'info', text.replace(/\s+/g, ' ').trim()).backend = backend;
      return json(200, {ok: true});
    } catch (e) {
      return json(400, {error: e.message});
    }
  }
  if (req.method === 'POST' && url.pathname === '/api/agentstatus') {
    if (!agent) return json(403, {error: 'forbidden'});
    try {
      const st = agentauth.agentStatus(await readJson(req), {agentBots: cfg.agentBots});
      if (st.error) throw new Error(st.error);
      agentStatuses.set(st.agent, {...st, t: Date.now()});
      return json(200, {ok: true});
    } catch (e) {
      return json(400, {error: e.message});
    }
  }
  if (req.method === 'GET' && url.pathname === '/api/crews') return json(200, crews.data);
  if (req.method === 'GET' && url.pathname === '/api/agents') return json(200, [...agentStatuses.values()]);
  if (req.method === 'GET' && url.pathname === '/api/world') return json(200, world.snapshot());
  const vm = req.method === 'GET' && /^\/api\/view\/(\w{1,16})\.png$/.exec(url.pathname);
  if (vm) {
    const r = runners.get(vm[1]);
    if (r instanceof RemoteRunner) {
      r.wantView(); // the worker answers within a second or two; meanwhile its last frame
      if (!r.viewFrame) return send(404, 'text/plain', 'no view yet (asked the worker)');
      res.writeHead(200, {'Content-Type': 'image/png', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
      return res.end(r.viewFrame.body);
    }
    if (!r || !r.bot?.entity || !r.online) return send(404, 'text/plain', 'no view (offline)');
    // One frame per bot, shared by all viewers, at most every 1 s or 4x its render time
    // (counted from the end of the render), and never more than 150 ms of rendering.
    const now = Date.now();
    const f = r.viewFrame;
    if (!f || now - f.t > Math.max(1000, 4 * f.ms)) {
      const body = botView(r.bot, {w: 256, h: 144, deadline: now + 150});
      r.viewFrame = {t: Date.now(), ms: Date.now() - now, body};
    }
    res.writeHead(200, {'Content-Type': 'image/png', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff'});
    return res.end(r.viewFrame.body);
  }
  const sm = req.method === 'GET' && /^\/api\/scan\/(\w{1,16})$/.exec(url.pathname);
  if (sm) {
    if (agent && !cfg.agentBots.includes(sm[1])) return json(403, {error: 'not an agent bot'}); // the agent token reaches its own bots only
    const r = runners.get(sm[1]);
    if (!r || !r.online) return json(404, {error: 'offline or unknown bot'});
    try {
      const scan = r instanceof RemoteRunner ? await r.askScan() : r.bot?.entity ? scanAround(r.bot) : null;
      return scan ? json(200, scan) : json(503, {error: 'no scan (the worker did not answer)'});
    } catch (e) {
      return json(500, {error: e.message});
    }
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
      if (!r) throw new Error('unknown bot');
      const now = settings.set(bot, input);
      // A remote bot's worker gets them now, or with its welcome when it comes back.
      const away = r instanceof RemoteRunner && !r.conn;
      if (r instanceof RemoteRunner) r.pushSettings(now);
      events.add(bot, 'info', `settings: ${Object.entries(input || {}).map(([k, v]) => `${k} ${v}`).join(', ')}${away ? ' (applies when its worker reconnects)' : ''}`);
      broadcast();
      return json(200, now);
    } catch (e) {
      return json(400, {error: e.message});
    }
  }
  if (req.method === 'POST' && url.pathname === '/api/crews') {
    if (!sameOrigin(req) || !String(req.headers['content-type']).startsWith('application/json')) return json(403, {error: 'bad origin'});
    try {
      const input = await readJson(req);
      const data = crews.set(input, new Set([...agentStatuses.keys(), ...Object.keys(crews.data.crews)]));
      events.add('crews', 'info', `crews edited: ${Object.keys(input).join(', ')}`);
      return json(200, data);
    } catch (e) {
      return json(400, {error: e.message});
    }
  }
  // Pause/Stop end a bot's project (the running one, else the queued ones); Resume queues the last one again.
  if (req.method === 'POST' && url.pathname === '/api/project') {
    if (!sameOrigin(req) || !String(req.headers['content-type']).startsWith('application/json')) return json(403, {error: 'bad origin'});
    try {
      const {bot, action} = await readJson(req);
      const r = runners.get(bot);
      const p = projects.get(bot);
      if (!r) throw new Error('unknown bot');
      if (action === 'resume') {
        if (!p) throw new Error('no project to resume');
        r.enqueue(p.type, p.args);
        projects.note(bot, p.type, p.args);
      } else if (action === 'pause' || action === 'stop') {
        const s = r.snapshot();
        if (PROJECTS.has(s.job?.type)) {
          r.enqueue('stop'); // clears the queue too
          delete toResume[bot];
        } else {
          s.queue.forEach((label, i) => PROJECTS.has(label.split(' ')[0]) && r.enqueue('remove', {id: s.queueIds[i]}));
          if (toResume[bot]) toResume[bot] = toResume[bot].filter((j) => !PROJECTS.has(j.type));
        }
        if (action === 'stop') projects.forget(bot);
        else projects.pause(bot);
        const saveErr = saveJobs(true);
        if (saveErr) throw new Error(`stopped, but the stopped state could not be saved (${saveErr})`);
      } else throw new Error('action must be pause, resume or stop');
      broadcast();
      return json(200, {ok: true});
    } catch (e) {
      return json(400, {error: e.message});
    }
  }
  if (req.method === 'POST' && url.pathname === '/api/job') {
    if (!sameOrigin(req) || !String(req.headers['content-type']).startsWith('application/json')) return json(403, {error: 'bad origin'});
    try {
      const {bots, type, args, replace} = await readJson(req);
      const refused = agent && agentauth.agentJobRefusal({bots, type, args}, {agentBots: cfg.agentBots, supplyChest});
      if (refused) return json(403, {error: refused});
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
          if (stopping) {
            delete toResume[r.name]; // its saved jobs must not come back after a restart or reconnect
            projects.pause(r.name);
          }
          if (PROJECTS.has(type)) projects.note(r.name, type, VALIDATE[type](args || {}));
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
// Alerts for the lead agent (alerts.js), from what a local bot in the overworld sees.
const alerts = new Alerts({events});
const alertTick = setInterval(() => {
  try {
    alerts.checkChest(world.stock);
    notifier.chest(world.stock, world.stock && chestWarnings(world.stock.items, world.stock.free));
    notifier.tick();
    const r = [...runners.values()].find((x) => !(x instanceof RemoteRunner) && x.online && x.bot?.entity && /overworld/.test(x.bot.game?.dimension || ''));
    if (!r || !supplyChest) return;
    const {Vec3} = require('vec3');
    alerts.check({
      chestBlock: r.bot.blockAt(new Vec3(supplyChest.x, supplyChest.y, supplyChest.z))?.name ?? null,
      timeOfDay: r.bot.time?.timeOfDay,
      hostiles: world.hostilesNear(supplyChest.x, supplyChest.z, 'overworld', 16),
    }, supplyChest);
  } catch (e) {
    log('alerts', `error: ${e.message}`);
  }
}, 5000);

slayer.start();
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
  clearInterval(alertTick);
  slayer.stop();
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
