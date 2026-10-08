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
const {NAME_RE, VALIDATE} = require('./bots');

const PROTOCOL = 1;
const MAX_FRAME = 256 * 1024;
const HELLO_MS = 5000;
const HEARTBEAT_MS = 10000;
const STALE_MS = 30000; // no frame and no pong for this long: the worker is gone
const MAX_BOTS_PER_WORKER = 8;
const MAX_REMOTE_BOTS = 16;
const MAX_CLAIMS_PER_BOT = 8;
const AUTH_FAILS = 20; // per minute, then 429 until the window passes
const KEY_RE = /^[a-z_]{1,32}:-?\d{1,9},-?\d{1,4},-?\d{1,9}$/;
const HOST_RE = /^[\w.-]{1,40}$/;
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
    job: job && {label: str(job.label, 160), progress: str(job.progress, 160)},
    queue: list(s.queue, 20, (q) => str(q, 160)),
    inventory: list(s.inventory, 80, (q) => str(q, 60)),
    inventoryKinds: int(s.inventoryKinds),
    lastError: str(s.lastError, 300),
    pullbacks: int(s.pullbacks),
  };
}

function cleanDebug(d) {
  d = obj(d) || {};
  const job = obj(d.job);
  const phys = obj(d.physics);
  const pf = obj(d.pathfinder);
  const corr = obj(d.corrections) || {};
  const err = obj(d.lastError);
  return {
    pos: vec(d.pos),
    dimension: optStr(d.dimension, 32),
    job: job && {id: int(job.id), type: str(job.type, 32), args: cleanArgs(job.args), status: str(job.status, 16), progress: str(job.progress, 160), runningS: num(job.runningS)},
    queue: list(d.queue, 20, (q) => str(q, 160)),
    combat: optStr(d.combat, 32),
    physics: phys && {onGround: bool(phys.onGround), collidedHorizontally: bool(phys.collidedHorizontally), velocity: vec(phys.velocity), controls: list(phys.controls, 8, (c) => str(c, 16))},
    pathfinder: pf && {moving: bool(pf.moving), mining: bool(pf.mining), building: bool(pf.building), goal: optStr(pf.goal, 48)},
    positions: list(d.positions, 130, (p) => ({agoS: num(p?.agoS), x: num(p?.x), y: num(p?.y), z: num(p?.z)})),
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

  // Same contract as BotRunner.enqueue: validate here, run on the worker.
  enqueue(type, args = {}, {replace = false} = {}) {
    if (!this.conn) throw new Error(`${this.name} is offline (its worker is not connected)`);
    let clean = {};
    if (type !== 'stop') {
      if (!VALIDATE[type]) throw new Error(`unknown job type: ${type}`);
      clean = VALIDATE[type](args || {});
    }
    this.conn.ws.send(JSON.stringify({t: 'job', bot: this.name, type, args: clean, replace: replace === true}));
  }
}

class Hub {
  constructor({world, runners, token, log = () => {}, protectedAreas = [], supplyChest = null, now = Date.now}) {
    if (typeof token !== 'string' || !/^[\w-]{32,128}$/.test(token)) throw new Error('worker token must be 32..128 characters of [A-Za-z0-9_-]');
    this.world = world;
    this.runners = runners;
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
    if (this.throttled()) return deny(429, 'Too Many Requests');
    if (!this.tokenOk(req.headers.authorization)) {
      this.fails.push(this.now());
      return deny(401, 'Unauthorized');
    }
    this.wss.handleUpgrade(req, socket, head, (ws) => this.onConnection(ws));
  }

  onConnection(ws) {
    const conn = {ws, hello: false, host: '', bots: new Set(), alive: true, lastMsg: this.now()};
    this.conns.add(conn);
    const helloTimer = setTimeout(() => !conn.hello && ws.close(4000, 'hello timeout'), HELLO_MS);
    ws.on('pong', () => {
      conn.alive = true;
      conn.lastMsg = this.now();
    });
    ws.on('message', (data, isBinary) => {
      if (isBinary) return ws.close(1003, 'text frames only');
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
          r.lastSeen = this.now();
        }
        return;
      case 'observe':
        return this.observe(conn, m);
      case 'claim': {
        const by = conn.bots.has(m.by) ? m.by : null;
        const key = String(m.key);
        let ok = false;
        if (by && KEY_RE.test(key)) {
          const held = [...this.world.claims.values()].filter((c) => c.by === by).length;
          ok = (held < MAX_CLAIMS_PER_BOT || this.world.claims.get(key)?.by === by) && this.world.claim(by, key);
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
    const fresh = names.filter((n) => !this.runners.has(n)).length;
    if (this.runners.size - this.local.size + fresh > MAX_REMOTE_BOTS) return this.refuse(conn, 'too many remote bots');
    // A reconnect replaces the old connection (it may be a dead NAT mapping).
    for (const n of names) {
      const old = this.runners.get(n)?.conn;
      if (old && old !== conn) old.ws.close(4001, 'replaced by a new connection');
    }
    conn.hello = true;
    conn.host = host;
    conn.bots = new Set(names);
    for (const n of names) {
      let r = this.runners.get(n);
      if (!r) {
        r = new RemoteRunner(n, this.now);
        this.runners.set(n, r);
      }
      r.conn = conn;
      r.host = host;
      r.lastSeen = this.now();
      r.snap = {...r.snap, online: false};
    }
    conn.ws.send(JSON.stringify({t: 'welcome', v: PROTOCOL, protectedAreas: this.protectedAreas, supplyChest: this.supplyChest}));
    this.log('hub', `worker ${host} connected: ${names.join(', ')}`);
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

module.exports = {Hub, RemoteRunner, createWorkerServer, cleanSnapshot, cleanDebug, PROTOCOL, KEY_RE};
