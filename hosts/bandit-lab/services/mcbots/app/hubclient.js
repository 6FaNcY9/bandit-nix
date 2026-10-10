'use strict';
// Worker side of the hub protocol (hub.js): runs the bots on this machine,
// reports their status to the lab dashboard, takes jobs from it, and asks the
// hub for every block reservation. When the hub is unreachable, reservations
// are refused (digging jobs stop with an error) rather than guessed.
const WebSocket = require('ws');
const {WorldModel} = require('./world');
const {BotRunner, keptOf} = require('./bots');
const {Settings} = require('./settings');
const {PROTOCOL} = require('./hub');

const CLAIM_TIMEOUT_MS = 3000;
const REPORT_MS = 1000;
const BACKOFF_START = 1000;
const BACKOFF_CAP = 30000;

// World model of a worker process: the hub's picture (players, other bots'
// mobs/blocks, claims) is mirrored in, own observations are sent up, and
// claims are only granted by the hub.
class RemoteWorld extends WorldModel {
  constructor(opts) {
    super(opts);
    this.mine = new Set(); // bot names running in this process
    this.link = null; // {send} while the hub connection is up
    this.waiting = new Map(); // claim id -> resolve
    this.seq = 0;
    this.outMobs = new Map();
    this.outBlocks = new Map();
    this.gone = new Set();
    this.outStock = null;
  }

  get unreachable() {
    return !this.link;
  }

  attach(send) {
    this.link = {send};
  }

  detach() {
    this.link = null;
    for (const resolve of this.waiting.values()) resolve(false);
    this.waiting.clear();
  }

  claim(by, key) {
    if (!this.link) return Promise.resolve(false);
    if (this.claimedByOther(by, key)) {
      this.count(by, 'refused'); // mirror says taken
      return Promise.resolve(false);
    }
    const id = ++this.seq;
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.waiting.delete(id);
        this.count(by, 'timedOut');
        resolve(false);
      }, CLAIM_TIMEOUT_MS);
      this.waiting.set(id, (ok) => {
        clearTimeout(timer);
        this.count(by, ok ? 'granted' : 'refused');
        if (ok) this.claims.set(key, {by, t: this.now()});
        resolve(ok);
      });
      this.link.send({t: 'claim', id, key, by});
    });
  }

  claimResult(id, ok) {
    const done = this.waiting.get(id);
    if (!done) return;
    this.waiting.delete(id);
    done(ok);
  }

  release(by, key) {
    super.release(by, key);
    this.link?.send({t: 'release', key, by});
  }

  noteMob(by, e, dim) {
    super.noteMob(by, e, dim);
    const {x, y, z} = e.position;
    this.outMobs.set(`${dim}:${e.id}`, {id: e.id, type: e.name, x, y, z, dim, by});
  }

  noteBlock(by, type, pos, dim) {
    super.noteBlock(by, type, pos, dim);
    this.outBlocks.set(`${dim}:${pos.x},${pos.y},${pos.z}`, {type, x: pos.x, y: pos.y, z: pos.z, dim, by});
  }

  noteStock(by, items) {
    super.noteStock(by, items);
    this.outStock = {by, items};
  }

  forgetMob(id) {
    super.forgetMob(id);
    for (const k of this.outMobs.keys()) if (k.endsWith(`:${id}`)) this.outMobs.delete(k);
    this.gone.add(id);
  }

  // One batched frame per report interval instead of one per observation.
  flush() {
    if (!this.link || !(this.outMobs.size || this.outBlocks.size || this.gone.size || this.outStock)) return;
    this.link.send({t: 'observe', mobs: [...this.outMobs.values()], blocks: [...this.outBlocks.values()], gone: [...this.gone], stock: this.outStock});
    this.outStock = null;
    this.outMobs.clear();
    this.outBlocks.clear();
    this.gone.clear();
  }

  // The hub's picture replaces everything that did not come from our bots.
  applyShared(msg) {
    const t = this.now();
    const ago = (o) => t - (Number.isFinite(o.age) ? o.age * 1000 : 0);
    this.setPlayers((Array.isArray(msg.players) ? msg.players : []).map(({age, t: _t, ...p}) => p));
    for (const [k, m] of this.mobs) if (!this.mine.has(m.by)) this.mobs.delete(k);
    for (const [k, b] of this.blocks) if (!this.mine.has(b.by)) this.blocks.delete(k);
    for (const m of Array.isArray(msg.mobs) ? msg.mobs : []) {
      if (!this.mine.has(m.by)) this.mobs.set(`${m.dim}:${m.id}`, {...m, t: ago(m)});
    }
    for (const b of Array.isArray(msg.blocks) ? msg.blocks : []) {
      if (!this.mine.has(b.by)) this.blocks.set(`${b.dim}:${b.x},${b.y},${b.z}`, {...b, t: ago(b)});
    }
    for (const [k, c] of this.claims) if (!this.mine.has(c.by)) this.claims.delete(k);
    for (const c of Array.isArray(msg.claims) ? msg.claims : []) {
      if (!this.mine.has(c.by)) this.claims.set(c.key, {by: c.by, t});
    }
    if (msg.bluemap && typeof msg.bluemap === 'object') this.bluemap = {...msg.bluemap, t: ago(msg.bluemap)};
  }
}

class HubClient {
  constructor({url, token, names, mcHost, mcPort, loginSeed = null, hostLabel, log, makeRunner, wsOptions = {}}) {
    this.url = url;
    this.token = token;
    this.names = names;
    this.hostLabel = hostLabel;
    this.log = log;
    this.wsOptions = wsOptions;
    this.world = new RemoteWorld();
    this.world.mine = new Set(names);
    this.settings = new Settings(''); // in memory: the hub keeps them and sends them with every welcome
    this.outEvents = []; // dashboard events waiting for the next status frame (capped)
    const onEvent = (bot, kind, text) => {
      this.outEvents.push({bot, kind, text});
      if (this.outEvents.length > 100) this.outEvents.shift();
    };
    this.makeRunner = makeRunner || ((name, {protectedAreas, supplyChest}) => new BotRunner(name, {host: mcHost, port: mcPort, log, world: this.world, protectedAreas, supplyChest, loginSeed, hostLabel, onEvent}));
    this.runners = [];
    this.ws = null;
    this.stopped = false;
    this.backoff = BACKOFF_START;
    this.retry = null;
    this.reporter = null;
  }

  start() {
    this.connect();
  }

  connect() {
    if (this.stopped) return;
    this.log('hub', `connecting to ${this.url}`);
    const ws = new WebSocket(this.url, {headers: {Authorization: `Bearer ${this.token}`}, handshakeTimeout: 10000, maxPayload: 1 << 20, ...this.wsOptions});
    this.ws = ws;
    ws.on('open', () => ws.send(JSON.stringify({t: 'hello', v: PROTOCOL, host: this.hostLabel, bots: this.names})));
    ws.on('message', (data) => {
      let m;
      try {
        m = JSON.parse(String(data));
      } catch {
        return;
      }
      try {
        this.handle(m);
      } catch (e) {
        this.log('hub', `bad frame from hub: ${e.message}`);
      }
    });
    ws.on('unexpected-response', (_req, res) => {
      this.log('hub', `hub refused the connection: HTTP ${res.statusCode}${res.statusCode === 401 ? ' (wrong token?)' : ''}`);
      res.resume();
      ws.terminate(); // with this handler ws leaves the socket open; close it so the retry below runs
    });
    ws.on('error', (e) => this.log('hub', `connection error: ${e.message}`));
    ws.on('close', (code, reason) => {
      if (this.ws !== ws) return;
      this.ws = null;
      this.world.detach();
      clearInterval(this.reporter);
      this.log('hub', `disconnected (${code} ${String(reason || '')}); retry in ${Math.round(this.backoff / 1000)}s`);
      if (this.stopped) return;
      this.retry = setTimeout(() => this.connect(), this.backoff);
      this.backoff = Math.min(this.backoff * 2, BACKOFF_CAP);
    });
  }

  send(msg) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(msg));
  }

  handle(m) {
    switch (m?.t) {
      case 'welcome':
        this.backoff = BACKOFF_START;
        this.world.attach((msg) => this.send(msg));
        for (const n of this.names) this.setSettings(n, m.settings?.[n]);
        if (!this.runners.length) {
          const opts = {protectedAreas: Array.isArray(m.protectedAreas) ? m.protectedAreas : [], supplyChest: m.supplyChest || null};
          this.runners = this.names.map((n) => this.makeRunner(n, opts));
          for (const r of this.runners) r.getSettings = () => this.settings.get(r.name);
          for (const r of this.runners) r.start();
        }
        clearInterval(this.reporter);
        this.reporter = setInterval(() => this.report(), REPORT_MS);
        this.report();
        this.log('hub', `connected as ${this.hostLabel}: ${this.names.join(', ')}`);
        return;
      case 'error':
        this.log('hub', `hub says: ${m.message}`);
        return;
      case 'claim_result':
        return this.world.claimResult(m.id, m.ok === true);
      case 'world':
        return this.world.applyShared(m);
      case 'settings':
        return this.setSettings(m.bot, m.settings);
      case 'job': {
        const r = this.runners.find((x) => x.name === m.bot);
        if (!r) return;
        try {
          r.enqueue(String(m.type), m.args || {}, {replace: m.replace === true});
        } catch (e) {
          this.log(r.name, `job from hub rejected: ${e.message}`);
        }
        return;
      }
      default:
    }
  }

  // Same rules as the hub's (settings.clean): a bad value is refused, the old settings stay.
  setSettings(name, input) {
    if (!this.names.includes(name) || !input) return;
    try {
      this.settings.set(name, input);
    } catch (e) {
      this.log(name, `settings from hub rejected: ${e.message}`);
    }
  }

  report() {
    this.send({t: 'status', bots: this.runners.map((r) => ({...r.snapshot(), debug: r.debug(), kept: keptOf(r)})), events: this.outEvents.splice(0)});
    this.world.flush();
  }

  stop() {
    this.stopped = true;
    clearTimeout(this.retry);
    clearInterval(this.reporter);
    for (const r of this.runners) r.shutdown();
    this.ws?.close(1000, 'worker stopped');
  }
}

module.exports = {RemoteWorld, HubClient};
