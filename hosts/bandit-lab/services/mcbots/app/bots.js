'use strict';
// One BotRunner per bot: connection lifecycle plus a sequential job queue.
// Adding a job type (crafting, building, ...) = add one entry to JOBS and one
// to VALIDATE; nothing else changes.
const mineflayer = require('mineflayer');
const {pathfinder, Movements, goals} = require('mineflayer-pathfinder');
const {plugin: collectBlock} = require('mineflayer-collectblock');
const {Combat} = require('./combat');
const {normDim, deadlineMs} = require('./world');

const NAME_RE = /^bot[0-9]{1,2}$/; // BotGate's pattern (Velocity plugin)
const LOGIN_GAP_MS = 4500; // Velocity rate-limits logins
const GOTO_TIMEOUT_MS = 90000;
const BACKOFF_START = 5000;
const BACKOFF_CAP = 300000;
const TOOL_RE = /_(pickaxe|axe|shovel|hoe|sword)$|^(shears|bow|crossbow|fishing_rod|shield|trident|flint_and_steel|elytra)$/;

// Global login stagger shared by all runners in this process.
let nextLogin = 0;
function loginDelay() {
  const t = Math.max(Date.now(), nextLogin);
  nextLogin = t + LOGIN_GAP_MS;
  return t - Date.now();
}

const num = (v, lo, hi, what) => {
  const n = Number(v);
  if (!Number.isFinite(n) || n < lo || n > hi) throw new Error(`${what} must be a number in ${lo}..${hi}`);
  return Math.floor(n);
};
const xyz = (a) => ({x: num(a.x, -3e7, 3e7, 'x'), y: num(a.y, -64, 320, 'y'), z: num(a.z, -3e7, 3e7, 'z')});
const player = (a) => {
  if (!/^\w{1,16}$/.test(a.player || '')) throw new Error('player must be a valid Minecraft name');
  return {player: a.player};
};

// Normalise and validate job arguments (throws on bad input).
const VALIDATE = {
  goto: xyz,
  follow: player,
  come: player,
  mine: (a) => {
    if (!/^[a-z_]{1,48}$/.test(a.block || '')) throw new Error('block must be a block name like iron_ore');
    return {block: a.block, count: num(a.count ?? 1, 1, 2048, 'count')};
  },
  chop: (a) => ({count: num(a.count ?? 1, 1, 2048, 'count')}),
  deposit: xyz,
  say: (a) => {
    const text = String(a.text ?? '').trim();
    if (!text || text.length > 200) throw new Error('text must be 1..200 characters');
    if (text.startsWith('/')) throw new Error('commands are not allowed');
    return {text};
  },
};

class Cancelled extends Error {}

class BotRunner {
  constructor(name, {host, port, log, world, protectedAreas = []}) {
    this.name = name;
    this.world = world;
    this.combat = {busy: false, epoch: 0}; // replaced by a Combat per connection
    this.host = host;
    this.protectedAreas = protectedAreas;
    this.port = port;
    this.log = log;
    this.bot = null;
    this.online = false;
    this.queue = [];
    this.current = null;
    this.lastError = '';
    this.backoff = BACKOFF_START;
    this.timer = null;
    this.stopped = false; // process shutdown
    this.jobSeq = 0;
  }

  start() {
    this.schedule(0);
  }

  schedule(ms) {
    if (this.stopped) return;
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.connect(), ms + loginDelay());
  }

  connect() {
    if (this.stopped) return;
    this.log(this.name, `connecting to ${this.host}:${this.port}`);
    const bot = mineflayer.createBot({host: this.host, port: this.port, username: this.name, auth: 'offline', version: '26.1', hideErrors: true});
    this.bot = bot;
    bot.loadPlugin(pathfinder);
    bot.loadPlugin(collectBlock);
    let spawnedAt = 0;
    this.combat = new Combat(this);
    bot.once('spawn', () => {
      spawnedAt = Date.now();
      this.online = true;
      const mv = safeMovements(bot, this.protectedAreas);
      bot.pathfinder.setMovements(mv);
      bot.collectBlock.movements = mv;
      this.log(this.name, 'spawned');
    });
    bot.on('entityGone', (e) => this.world.forgetMob(e.id));
    bot.on('death', () => {
      this.lastError = 'died';
      this.cancel();
    });
    bot.on('error', (e) => {
      this.lastError = String(e.message || e);
      this.log(this.name, `error: ${this.lastError}`);
    });
    bot.on('kicked', (reason) => {
      this.lastError = `kicked: ${typeof reason === 'string' ? reason : JSON.stringify(reason)}`.slice(0, 300);
      this.log(this.name, this.lastError);
      if (/too fast|throttl/i.test(this.lastError)) this.backoff = Math.max(this.backoff, 30000);
    });
    bot.once('end', (why) => {
      this.online = false;
      this.combat.stop();
      this.cancel();
      this.bot = null;
      if (spawnedAt && Date.now() - spawnedAt > 60000) this.backoff = BACKOFF_START;
      const wait = this.backoff;
      this.backoff = Math.min(this.backoff * 2, BACKOFF_CAP);
      this.log(this.name, `disconnected (${why}); reconnect in ${Math.round(wait / 1000)}s`);
      this.schedule(wait);
    });
    // Chat is never a command source: no 'chat'/'whisper' listeners exist.
  }

  shutdown() {
    this.stopped = true;
    clearTimeout(this.timer);
    this.queue = [];
    this.cancel();
    this.bot?.quit();
  }

  // ---- jobs ----
  enqueue(type, args = {}) {
    if (type === 'stop') {
      this.queue = [];
      this.cancel();
      return;
    }
    if (!VALIDATE[type]) throw new Error(`unknown job type: ${type}`);
    const job = {id: ++this.jobSeq, type, args: VALIDATE[type](args), status: 'queued'};
    this.queue.push(job);
    this.pump();
  }

  cancel() {
    if (this.current) this.current.cancelled = true;
    const b = this.bot;
    try {
      b?.pathfinder?.stop();
      b?.collectBlock?.cancelTask().catch(() => {});
    } catch {}
  }

  async pump() {
    if (this.current || !this.queue.length) return;
    const job = (this.current = this.queue.shift());
    job.status = 'running';
    job.progress = '';
    try {
      if (!this.online) throw new Error('bot is offline');
      for (let tries = 0; ; tries++) {
        const epoch = this.combat.epoch;
        try {
          await JOBS[job.type](this, job);
          break;
        } catch (e) {
          // Combat took over the pathfinder mid-job (retreat / creeper): wait
          // until calm, then resume instead of failing.
          if (job.cancelled || this.combat.epoch === epoch || tries >= 5) throw e;
          await waitCalm(this, job);
        }
      }
      job.status = job.cancelled ? 'stopped' : 'done';
    } catch (e) {
      job.status = job.cancelled ? 'stopped' : 'failed';
      if (!job.cancelled) {
        this.lastError = `${job.type}: ${e.message}`;
        this.log(this.name, this.lastError);
      }
    }
    this.current = null;
    if (job.cancelled) this.queue = [];
    setImmediate(() => this.pump());
  }

  snapshot() {
    const b = this.bot;
    const inv = {};
    if (this.online) for (const it of b.inventory.items()) inv[it.name] = (inv[it.name] || 0) + it.count;
    const top = Object.entries(inv).sort((a, c) => c[1] - a[1]);
    const label = (j) => `${j.type} ${Object.values(j.args).join(' ')}`;
    return {
      name: this.name,
      online: this.online,
      health: this.online ? b.health : null,
      food: this.online ? b.food : null,
      pos: this.online && b.entity ? ['x', 'y', 'z'].map((k) => Math.round(b.entity.position[k])) : null,
      dimension: this.online ? normDim(b.game?.dimension) : null,
      combat: this.combat.mode || null,
      job: this.current && {label: label(this.current), progress: this.current.progress},
      queue: this.queue.map(label),
      inventory: top.slice(0, 8).map(([n, c]) => `${n} x${c}`),
      inventoryKinds: top.length,
      lastError: this.lastError,
    };
  }
}


// Pathing may dig only natural terrain (never planks, glass, cobblestone or
// anything else players place) and may pillar with dirt/cobblestone it
// carries. Inside protected areas (player bases) it neither digs nor places.
const NATURAL = new Set(['dirt', 'grass_block', 'coarse_dirt', 'rooted_dirt', 'podzol', 'mycelium', 'mud',
  'sand', 'red_sand', 'gravel', 'clay', 'stone', 'deepslate', 'granite', 'diorite', 'andesite', 'tuff',
  'calcite', 'netherrack', 'snow', 'snow_block', 'short_grass', 'tall_grass', 'fern', 'large_fern', 'dead_bush']);
function safeMovements(bot, areas) {
  const mv = new Movements(bot);
  mv.canDig = true;
  for (const b of bot.registry.blocksArray) {
    if (!NATURAL.has(b.name) && !b.name.endsWith('_leaves')) mv.blocksCantBreak.add(b.id);
  }
  mv.scafoldingBlocks = ['dirt', 'cobblestone'].map((n) => bot.registry.itemsByName[n].id);
  const inside = (blk) => areas.some(([x1, z1, x2, z2]) =>
    blk.position.x >= x1 && blk.position.x <= x2 && blk.position.z >= z1 && blk.position.z <= z2);
  const veto = (blk) => (inside(blk) ? 100 : 0);
  mv.exclusionAreasBreak = [veto];
  mv.exclusionAreasPlace = [veto];
  return mv;
}

// ---- job implementations: (runner, job) => Promise; throw on failure ----
const guard = (job) => {
  if (job.cancelled) throw new Cancelled('stopped');
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Jobs pause while combat has the pathfinder (retreating from a hostile).
async function waitCalm(r, job) {
  while (r.combat.busy) {
    guard(job);
    await sleep(300);
  }
  guard(job);
}

// Another bot reported a hostile within 8 blocks of where we are headed:
// give it up to 10 s to move on or die (reports expire), then go anyway.
async function waitSafe(r, job, x, z) {
  const dim = normDim(r.bot.game?.dimension);
  for (let i = 0; i < 10 && r.world.hostilesNear(x, z, dim, 8).length; i++) {
    job.progress = 'waiting: hostile near target';
    await waitCalm(r, job);
    await sleep(1000);
  }
}

async function goNear(r, job, x, y, z, dist) {
  guard(job);
  // Unreachable goals make the pathfinder retry partial paths
  // forever, so every walk has a deadline.
  const deadline = setTimeout(() => r.bot?.pathfinder.stop(), GOTO_TIMEOUT_MS);
  try {
    await waitSafe(r, job, x, z);
    await r.bot.pathfinder.goto(new goals.GoalNear(x, y, z, dist));
  } catch (e) {
    guard(job);
    throw new Error(`could not reach ${Math.round(x)} ${Math.round(y)} ${Math.round(z)}: ${e.message}`);
  } finally {
    clearTimeout(deadline);
  }
}

async function collect(r, job, matching, count, what) {
  const {bot} = r;
  const ids = matching.map((n) => bot.registry.blocksByName[n]?.id).filter((i) => i !== undefined);
  if (!ids.length) throw new Error(`unknown block: ${what}`);
  let got = job.collected || 0; // survives a combat interruption + resume
  while (got < count) {
    await waitCalm(r, job);
    const pos = bot.findBlocks({matching: ids, maxDistance: 64, count: 1})[0];
    if (!pos) throw new Error(`no ${what} within 64 blocks (collected ${got}/${count})`);
    await waitSafe(r, job, pos.x, pos.z);
    try {
      await bot.collectBlock.collect(bot.blockAt(pos));
    } catch (e) {
      guard(job);
      throw e;
    }
    job.collected = ++got;
    job.progress = `${got}/${count}`;
  }
}

const dist3 = (a, p) => Math.hypot(a.x - p.x, a.y - p.y, a.z - p.z);

// come/follow. Entity tracking only reaches the server's tracking range, so a
// farther player is approached via BlueMap's position (same dimension only)
// and the live entity takes over once it is visible. `stop` cancels the job.
async function chase(r, job, follow) {
  const {bot} = r;
  const name = job.args.player;
  const start = Date.now();
  let maxDist = 0;
  let mode = null; // what the current pathfinder goal chases
  let goalAt = null;
  let epoch = r.combat.epoch;
  try {
    for (;;) {
      guard(job);
      if (!r.online) throw new Error('bot went offline');
      await waitCalm(r, job);
      if (epoch !== r.combat.epoch) {
        epoch = r.combat.epoch;
        mode = null; // combat replaced our goal; re-issue it
      }
      const me = bot.entity.position;
      const e = bot.players[name]?.entity;
      if (e) {
        if (mode !== 'entity') {
          bot.pathfinder.setGoal(new goals.GoalFollow(e, 2), true);
          mode = 'entity';
          job.progress = follow ? 'following' : 'tracking';
        }
        maxDist = Math.max(maxDist, dist3(me, e.position));
        if (!follow && dist3(me, e.position) <= 3) return;
      } else {
        const p = r.world.player(name);
        if (!p) throw new Error(`${name} is not visible and not on the map (offline, or BlueMap unavailable)`);
        const dim = normDim(bot.game?.dimension);
        if (p.dim !== dim) throw new Error(`${name} is in ${p.dim}, the bot is in ${dim}`);
        const d = Math.hypot(me.x - p.x, me.z - p.z);
        maxDist = Math.max(maxDist, d);
        if (!follow && d <= 3) return;
        if (mode !== 'map' || Math.hypot(goalAt.x - p.x, goalAt.z - p.z) > 4) {
          bot.pathfinder.setGoal(new goals.GoalNearXZ(p.x, p.z, 2));
          mode = 'map';
          goalAt = p;
          job.progress = `to map position, ${Math.round(d)} blocks`;
        }
      }
      if (!follow && Date.now() - start > deadlineMs(maxDist)) {
        throw new Error(`could not reach ${name} within ${Math.round(deadlineMs(maxDist) / 1000)} s`);
      }
      await sleep(500);
    }
  } finally {
    r.bot?.pathfinder?.stop();
  }
}

const JOBS = {
  goto: (r, job) => goNear(r, job, job.args.x, job.args.y, job.args.z, 1),

  // Walks to the player (live entity when tracked, else the BlueMap position)
  // and is done within 3 blocks.
  come: (r, job) => chase(r, job, false),

  follow: (r, job) => chase(r, job, true),

  mine: (r, job) => collect(r, job, [job.args.block], job.args.count, job.args.block),

  chop: (r, job) =>
    collect(r, job, Object.keys(r.bot.registry.blocksByName).filter((n) => n.endsWith('_log')), job.args.count, 'logs'),

  async deposit(r, job) {
    const {bot} = r;
    const {x, y, z} = job.args;
    await goNear(r, job, x, y, z, 3);
    const block = bot.blockAt(new (require('vec3').Vec3)(x, y, z));
    if (!block || !/chest|barrel/.test(block.name)) throw new Error(`no chest at ${x} ${y} ${z} (found ${block?.name})`);
    const chest = await bot.openContainer(block);
    try {
      let moved = 0;
      for (const it of bot.inventory.items()) {
        guard(job);
        if (TOOL_RE.test(it.name) || bot.registry.foodsByName[it.name]) continue;
        try {
          await chest.deposit(it.type, it.metadata, it.count);
          moved += it.count;
          job.progress = `${moved} items`;
        } catch (e) {
          throw new Error(`chest full or deposit failed after ${moved} items: ${e.message}`);
        }
      }
    } finally {
      chest.close();
    }
  },

  async say(r, job) {
    r.bot.chat(job.args.text);
  },
};

module.exports = {BotRunner, NAME_RE, VALIDATE, TOOL_RE};
