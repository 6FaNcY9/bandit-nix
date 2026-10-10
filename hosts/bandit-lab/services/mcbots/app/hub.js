'use strict';
// Central hub (runs in the lab container next to the lab's own bots). Remote
// workers - a laptop running `mcbots-worker bot5` - connect over a WebSocket,
// authenticate with a shared token and then appear in the same runner table
// the dashboard already reads: online state, host, last-seen, status, debug
// data. The hub owns the shared world model and is the only place where block
// reservations are decided, so a lab bot and a laptop bot never dig the same
// block. Jobs the dashboard sends to a remote bot are forwarded to its worker.
//
// Trust model: the worker port is published by `tailscale serve` (tailnet only,
// never Funnel) and every connection needs the bearer token. A worker may only
// act for the bot names it announced in its hello, never for the lab's bots,
// and everything it sends is re-validated and size-capped here.
const crypto = require('node:crypto');
const http = require('node:http');
const {WebSocketServer} = require('ws');
const {NAME_RE, VALIDATE, KEEP} = require('./bots');
const {clean: cleanEvent} = require('./events');

const PROTOCOL = 1;
const MAX_FRAME = 256 * 1024;
const HELLO_MS = 5000;
const HEARTBEAT_MS = 10000;
const FORGET_MS = 3600000; // offline remote bots are dropped after this
const STALE_MS = 30000; // no frame and no pong for this long: the worker is gone
const MAX_BOTS_PER_WORKER = 8;
const MAX_REMOTE_BOTS = 16;
const MAX_CLAIMS_PER_BOT = 8;
const MAX_CONNS = 24; // authenticated sockets, hello or not
const MAX_MSGS_PER_S = 200; // a real worker sends a handful per second
const AUTH_FAILS = 20; // per minute, then 429 until the window passes
const KEY_RE = /^[a-z_]{1,32}:-?\d{1,9},-?\d{1,4},-?\d{1,9}$/;
const HOST_RE = /^[\w.-]{1,40}$/;
const WID_RE = /^[0-9a-f]{32}$/;
const RESUME_MS = 300000; // a restarted worker's bot has this long to log in before its old jobs are dropped
const BLOCK_RE = /^[a-z_]{1,48}$/;

// ---- sanitizers: nothing a worker sends is trusted ----
const str = (v, n) => (typeof v === 'string' ? v.slice(0, n) : '');
const optStr = (v, n) => (v == null ? null : str(v, n));
const num = (v) => (Number.isFinite(v) ? v : null);
const int = (v) => (Number.isInteger(v) && v >= 0 ? Math.min(v, 1e9) : 0);
const bool = (v) => v === true;
const vec = (v) => (Array.isArray(v) && v.length === 3 && v.every(Number.isFinite) ? v.slice() : null);
const list = (v, n, f) => (Array.isArray(v) ? v.slice(0, n).map(f) : []);
const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : null);
const cleanArgs = (a) => Object.fromEntries(Object.entries(obj(a) || {}).slice(0, 8).map(([k, v]) => [str(k, 24), typeof v === 'number' && Number.isFinite(v) ? v : str(String(v), 200)]));

function cleanSnapshot(s) {
  s = obj(s) || {};
  const job = obj(s.job);
  return {
    online: bool(s.online),
    health: num(s.health),
    food: num(s.food),
    pos: vec(s.pos),
    dimension: optStr(s.dimension, 32),
    combat: optStr(s.combat, 32),
    job: job && {label: str(job.label, 160), progress: str(job.progress, 160), type: str(job.type, 32), done: int(job.done), total: int(job.total), runningS: int(job.runningS)},
    activity: str(s.activity, 200),
    dead: bool(s.dead),
    tool: obj(s.tool) && {name: str(s.tool.name, 48), max: int(s.tool.max), left: num(s.tool.left)},
    freeSlots: num(s.freeSlots),
    queue: list(s.queue, 20, (q) => str(q, 160)),
    queueIds: list(s.queueIds, 20, int),
    inventory: list(s.inventory, 80, (q) => str(q, 60)),
    inventoryKinds: int(s.inventoryKinds),
    lastError: str(s.lastError, 300),
    lastErrorAgoS: num(s.lastErrorAgoS),
    pullbacks: int(s.pullbacks),
  };
}

// The jobs a worker's bot would want back after a restart, re-validated like any job (the hub saves them).
function cleanKept(v) {
  return list(v, 20, (j) => {
    try {
      return KEEP.has(j?.type) ? {type: j.type, args: VALIDATE[j.type](obj(j.args) || {})} : null;
    } catch {
      return null;
    }
  }).filter(Boolean);
}

function cleanDebug(d) {
  d = obj(d) || {};
  const job = obj(d.job);
  const phys = obj(d.physics);
  const pf = obj(d.pathfinder);
  const corr = obj(d.corrections) || {};
  const err = obj(d.lastError);
  const claims = obj(d.claims) || {};
  return {
    pos: vec(d.pos),
    dimension: optStr(d.dimension, 32),
    job: job && {id: int(job.id), type: str(job.type, 32), args: cleanArgs(job.args), status: str(job.status, 16), progress: str(job.progress, 160), runningS: num(job.runningS)},
    queue: list(d.queue, 20, (q) => str(q, 160)),
    combat: optStr(d.combat, 32),
    physics: phys && {onGround: bool(phys.onGround), collidedHorizontally: bool(phys.collidedHorizontally), velocity: vec(phys.velocity), controls: list(phys.controls, 8, (c) => str(c, 16))},
    pathfinder: pf && {moving: bool(pf.moving), mining: bool(pf.mining), building: bool(pf.building), goal: optStr(pf.goal, 48)},
    positions: list(d.positions, 130, (p) => ({agoS: num(p?.agoS), x: num(p?.x), y: num(p?.y), z: num(p?.z)})),
    claims: {granted: int(claims.granted), refused: int(claims.refused), timedOut: int(claims.timedOut)},
    corrections: {total: int(corr.total), last30s: int(corr.last30s), lastAgoS: num(corr.lastAgoS)},
    lastError: err && {message: str(err.message, 300), agoS: num(err.agoS)},
  };
}

// A remote bot, shaped like a BotRunner for server.js and the dashboard.
class RemoteRunner {
  constructor(name, now = Date.now) {
    this.name = name;
    this.now = now;
    this.host = '';
    this.conn = null;
    this.lastSeen = 0;
    this.snap = cleanSnapshot(null);
    this.dbg = cleanDebug(null);
    this.resume = null; // {jobs, until}: KEEP jobs to queue again after the worker restarted
    this.kept = []; // what the worker last said should survive a hub restart (server.js saves it)
  }

  get online() {
    return !!this.conn && this.snap.online;
  }

  start() {}

  shutdown() {
    this.conn?.ws.close(1001, 'hub shutting down');
  }

  snapshot() {
    const live = !!this.conn;
    return {
      name: this.name,
      remote: true,
      connected: live,
      host: this.host,
      lastSeen: this.lastSeen,
      ...this.snap,
      online: this.online,
      ...(live ? {} : {job: null, queue: [], combat: null, pullbacks: 0}),
    };
  }

  debug() {
    const live = !!this.conn;
    return {
      name: this.name,
      remote: true,
      connected: live,
      host: this.host,
      lastSeen: this.lastSeen,
      ...this.dbg,
      online: this.online,
      ...(live ? {} : {job: null, queue: [], combat: null, physics: null, pathfinder: null}),
    };
  }

  // Settings are validated and stored by the caller (Settings.set); the worker validates again.
  pushSettings(settings) {
    this.conn?.ws.send(JSON.stringify({t: 'settings', bot: this.name, settings}));
  }

  // Same contract as BotRunner.enqueue: validate here, run on the worker.
  enqueue(type, args = {}, {replace = false} = {}) {
    if (!this.conn) throw new Error(`${this.name} is offline (its worker is not connected)`);
    if (type === 'stop' || replace === true) this.kept = []; // the next status frame is up to a second away
    let clean = {};
    if (type === 'remove') clean = {id: int(Number(args?.id))};
    else if (type !== 'stop') {
      if (!VALIDATE[type]) throw new Error(`unknown job type: ${type}`);
      clean = VALIDATE[type](args || {});
    }
    this.conn.ws.send(JSON.stringify({t: 'job', bot: this.name, type, args: clean, replace: replace === true}));
  }
}

class Hub {
  constructor({world, runners, token, log = () => {}, protectedAreas = [], supplyChest = null, now = Date.now, events = null, settings = null}) {
    this.events = events; // EventLog of the dashboard (optional)
    this.settings = settings; // Settings store of the dashboard (optional): sent to a worker with its welcome
    if (typeof token !== 'string' || !/^[\w-]{32,128}$/.test(token)) throw new Error('worker token must be 32..128 characters of [A-Za-z0-9_-]');
    this.world = world;
    this.runners = runners;
    this.owners = new Map(); // remote bot name -> who first announced it
    this.local = new Set(runners.keys()); // the lab's own bots: never claimable by a worker
    this.tokenHash = crypto.createHash('sha256').update(token).digest();
    this.log = log;
    this.protectedAreas = protectedAreas;
    this.supplyChest = supplyChest;
    this.now = now;
    this.conns = new Set();
    this.fails = [];
    this.wss = new WebSocketServer({noServer: true, maxPayload: MAX_FRAME});
    this.beat = setInterval(() => this.heartbeat(), HEARTBEAT_MS);
    this.beat.unref?.();
  }

  // ---- connection admission ----
  tokenOk(header) {
    const m = /^Bearer (\S{16,200})$/.exec(String(header || ''));
    if (!m) return false;
    const given = crypto.createHash('sha256').update(m[1]).digest();
    return crypto.timingSafeEqual(given, this.tokenHash);
  }

  throttled() {
    const t = this.now();
    this.fails = this.fails.filter((x) => t - x < 60000);
    return this.fails.length >= AUTH_FAILS;
  }

  upgrade(req, socket, head) {
    const deny = (code, text) => {
      socket.write(`HTTP/1.1 ${code} ${text}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
      socket.destroy();
    };
    let path;
    try {
      path = new URL(req.url, 'http://x').pathname;
    } catch {
      return deny(400, 'Bad Request');
    }
    if (path !== '/worker') return deny(404, 'Not Found');
    // The token is checked first: a wrong one counts towards the failure window
    // (then 429), but someone guessing never locks the real worker out.
    if (!this.tokenOk(req.headers.authorization)) {
      if (this.throttled()) return deny(429, 'Too Many Requests');
      this.fails.push(this.now());
      return deny(401, 'Unauthorized');
    }
    if (this.conns.size >= MAX_CONNS) return deny(503, 'Service Unavailable');
    this.wss.handleUpgrade(req, socket, head, (ws) => this.onConnection(ws));
  }

  onConnection(ws) {
    const conn = {ws, hello: false, host: '', bots: new Set(), alive: true, lastMsg: this.now(), winStart: this.now(), winCount: 0};
    this.conns.add(conn);
    const helloTimer = setTimeout(() => !conn.hello && ws.close(4000, 'hello timeout'), HELLO_MS);
    ws.on('pong', () => {
      conn.alive = true;
      conn.lastMsg = this.now();
    });
    ws.on('message', (data, isBinary) => {
      if (isBinary) return ws.close(1003, 'text frames only');
      const t = this.now();
      if (t - conn.winStart >= 1000) {
        conn.winStart = t;
        conn.winCount = 0;
      }
      if (++conn.winCount > MAX_MSGS_PER_S) return ws.close(1008, 'too many messages');
      let m;
      try {
        m = JSON.parse(String(data));
      } catch {
        return ws.close(1007, 'bad json');
      }
      if (!obj(m)) return ws.close(1007, 'bad frame');
      conn.alive = true;
      conn.lastMsg = this.now();
      try {
        this.handle(conn, m);
      } catch (e) {
        this.log('hub', `closing ${conn.host || 'unknown worker'}: ${e.message}`);
        ws.close(1008, String(e.message).slice(0, 100));
      }
    });
    ws.on('close', () => {
      clearTimeout(helloTimer);
      this.drop(conn);
    });
    ws.on('error', () => {});
  }

  refuse(conn, why) {
    conn.ws.send(JSON.stringify({t: 'error', message: why}));
    conn.ws.close(4003, why.slice(0, 100));
  }

  // ---- messages from a worker ----
  handle(conn, m) {
    if (m.t === 'hello') return this.hello(conn, m);
    if (!conn.hello) throw new Error('hello first');
    switch (m.t) {
      case 'status':
        for (const b of list(m.bots, MAX_BOTS_PER_WORKER, (x) => x)) {
          const r = this.owned(conn, obj(b)?.name);
          if (!r) continue;
          r.snap = cleanSnapshot(b);
          r.dbg = cleanDebug(b.debug);
          if (this.resumeKept(r) === 'none') r.kept = cleanKept(b.kept);
          r.lastSeen = this.now();
        }
        for (const e of list(m.events, 50, (x) => cleanEvent(x, conn.bots))) if (e) this.events?.add(e.bot, e.kind, e.text);
        return;
      case 'observe':
        return this.observe(conn, m);
      case 'claim': {
        const by = conn.bots.has(m.by) ? m.by : null;
        const key = String(m.key);
        let ok = false;
        if (by && KEY_RE.test(key)) {
          ok = (this.world.held(by) < MAX_CLAIMS_PER_BOT || this.world.claims.get(key)?.by === by) && this.world.claim(by, key);
        }
        conn.ws.send(JSON.stringify({t: 'claim_result', id: int(m.id), ok}));
        return;
      }
      case 'release':
        if (conn.bots.has(m.by) && KEY_RE.test(String(m.key))) this.world.release(m.by, String(m.key));
        return;
      case 'ping':
        conn.ws.send(JSON.stringify({t: 'pong'}));
        return;
      default:
        // Unknown types are ignored so a newer worker can talk to an older hub.
    }
  }

  // A worker restarted alone (the hub stayed up): its bots start with no queue while the hub still has
  // their KEEP jobs. Queue them again once the bot is online and idle, like server.js does at hub start.
  // 'wait': keep the old list for now; 'resumed': just sent; 'none': nothing pending (adopt the worker's list).
  resumeKept(r) {
    if (!r.resume) return 'none';
    if (this.now() > r.resume.until || r.snap.job || r.snap.queue.length) { // gave up, or the worker kept playing (a plain reconnect)
      r.resume = null;
      return 'none';
    }
    if (!r.snap.online || r.snap.dead) return 'wait';
    const {jobs} = r.resume;
    r.resume = null;
    for (const j of jobs) {
      try {
        r.enqueue(j.type, j.args);
        this.events?.add(r.name, 'info', `resumed after worker restart: ${j.type}`);
      } catch {} // an entry the validator refuses is dropped
    }
    return 'resumed';
  }

  owned(conn, name) {
    if (typeof name !== 'string' || !conn.bots.has(name)) return null;
    const r = this.runners.get(name);
    return r?.conn === conn ? r : null;
  }

  hello(conn, m) {
    if (conn.hello) throw new Error('duplicate hello');
    if (m.v !== PROTOCOL) return this.refuse(conn, `protocol ${PROTOCOL} required`);
    const host = typeof m.host === 'string' && HOST_RE.test(m.host) ? m.host : 'worker';
    const names = Array.isArray(m.bots) ? [...new Set(m.bots)] : [];
    if (!names.length || names.length > MAX_BOTS_PER_WORKER || names.some((n) => typeof n !== 'string' || !NAME_RE.test(n))) {
      return this.refuse(conn, 'bots must be 1..8 names like bot5');
    }
    const lab = names.filter((n) => this.local.has(n));
    if (lab.length) return this.refuse(conn, `${lab.join(', ')} run in the lab`);
    // A bot name belongs to the worker that first announced it (until the hub restarts): the same worker
    // may reconnect, another one holding the shared token may not announce or replace it. A worker is
    // known by `wid` (derived from its own login seed) or, from an older worker, by its host label.
    const who = WID_RE.test(m.wid) ? `k:${m.wid}` : `h:${host}`;
    const taken = names.filter((n) => (this.owners.get(n) || who) !== who);
    if (taken.length) return this.refuse(conn, `${taken.join(', ')} ${taken.length > 1 ? 'are' : 'is'} taken by another worker`);
    const fresh = names.filter((n) => !this.runners.has(n)).length;
    if (this.runners.size - this.local.size + fresh > MAX_REMOTE_BOTS) return this.refuse(conn, 'too many remote bots');
    // A reconnect replaces the old connection (it may be a dead NAT mapping).
    for (const n of names) {
      const old = this.runners.get(n)?.conn;
      if (old && old !== conn) {
        old.bots.delete(n); // the stale socket may still deliver frames: it no longer speaks for n
        old.ws.close(4001, 'replaced by a new connection');
      }
    }
    for (const n of names) this.owners.set(n, who);
    conn.hello = true;
    conn.host = host;
    conn.bots = new Set(names);
    for (const n of names) {
      let r = this.runners.get(n);
      if (!r) {
        r = new RemoteRunner(n, this.now);
        this.runners.set(n, r);
      }
      if (r.kept.length && !r.resume) r.resume = {jobs: r.kept, until: this.now() + RESUME_MS};
      r.conn = conn;
      r.host = host;
      r.lastSeen = this.now();
      r.snap = {...r.snap, online: false};
    }
    const settings = this.settings ? Object.fromEntries(names.map((n) => [n, this.settings.get(n)])) : {};
    conn.ws.send(JSON.stringify({t: 'welcome', v: PROTOCOL, protectedAreas: this.protectedAreas, supplyChest: this.supplyChest, settings}));
    this.log('hub', `worker ${host} connected: ${names.join(', ')}`);
    for (const n of names) this.events?.add(n, 'hub', `worker ${host} connected`);
  }

  observe(conn, m) {
    const first = [...conn.bots][0];
    const by = (v) => (conn.bots.has(v) ? v : first);
    for (const x of list(m.mobs, 200, (v) => obj(v) || {})) {
      if (![x.id, x.x, x.y, x.z].every(Number.isFinite) || !BLOCK_RE.test(String(x.type))) continue;
      this.world.noteMob(by(x.by), {id: x.id, name: x.type, position: {x: x.x, y: x.y, z: x.z}}, str(x.dim, 32) || 'overworld');
    }
    for (const x of list(m.blocks, 100, (v) => obj(v) || {})) {
      if (![x.x, x.y, x.z].every(Number.isInteger) || !BLOCK_RE.test(String(x.type))) continue;
      this.world.noteBlock(by(x.by), x.type, {x: x.x, y: x.y, z: x.z}, str(x.dim, 32) || 'overworld');
    }
    for (const id of list(m.gone, 200, (v) => v)) if (Number.isFinite(id)) this.world.forgetMob(id);
    // What a worker's bot saw in the supply chest (the keeper plans from it).
    const st = obj(m.stock);
    if (st) {
      const items = Object.fromEntries(Object.entries(obj(st.items) || {}).slice(0, 80).filter(([k, v]) => BLOCK_RE.test(k) && Number.isInteger(v) && v >= 0).map(([k, v]) => [k, Math.min(v, 1e6)]));
      this.world.noteStock(by(st.by), items);
    }
  }

  // ---- hub to workers ----
  broadcastWorld() {
    const live = [...this.conns].filter((c) => c.hello && c.ws.readyState === 1);
    if (!live.length) return;
    const w = this.world.snapshot();
    const msg = JSON.stringify({t: 'world', players: w.players, mobs: w.mobs, blocks: w.blocks, claims: w.claims, bluemap: w.bluemap});
    for (const c of live) c.ws.send(msg);
  }

  heartbeat() {
    const t = this.now();
    // A remote bot whose worker has been away for an hour leaves the list (and frees its name slot).
    for (const [n, r] of this.runners) {
      if (r instanceof RemoteRunner && !r.conn && t - r.lastSeen > FORGET_MS) {
        this.runners.delete(n);
        this.events?.add(n, 'hub', 'offline for over an hour: removed from the list');
      }
    }
    for (const c of this.conns) {
      if (!c.alive && t - c.lastMsg > STALE_MS) {
        c.ws.terminate();
        continue;
      }
      c.alive = false;
      try {
        c.ws.ping();
      } catch {}
    }
  }

  drop(conn) {
    this.conns.delete(conn);
    for (const n of conn.bots) {
      const r = this.runners.get(n);
      if (r?.conn !== conn) continue; // already taken over by a newer connection
      r.conn = null;
      r.snap = {...r.snap, online: false};
      this.world.releaseAll(n);
      this.log('hub', `worker ${conn.host}: ${n} offline`);
      this.events?.add(n, 'hub', `worker ${conn.host} disconnected`);
    }
  }

  close() {
    clearInterval(this.beat);
    for (const c of this.conns) c.ws.close(1001, 'hub shutting down');
  }
}

// The worker port serves nothing but the WebSocket upgrade on /worker.
function createWorkerServer(hub) {
  const server = http.createServer((req, res) => {
    res.writeHead(404, {'Content-Type': 'text/plain', 'X-Content-Type-Options': 'nosniff'});
    res.end('not found\n');
  });
  server.on('upgrade', (req, socket, head) => hub.upgrade(req, socket, head));
  return server;
}

module.exports = {Hub, RemoteRunner, createWorkerServer, cleanSnapshot, cleanDebug, PROTOCOL, KEY_RE, FORGET_MS};
