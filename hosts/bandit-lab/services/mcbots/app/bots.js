'use strict';
require('./itemfix'); // must load before mineflayer
// One BotRunner per bot: connection lifecycle plus a sequential job queue.
// Adding a job type (crafting, building, ...) = add one entry to JOBS and one
// to VALIDATE; nothing else changes.
const mineflayer = require('mineflayer');
const {pathfinder, Movements, goals} = require('mineflayer-pathfinder');
const {plugin: collectBlock} = require('mineflayer-collectblock');
const {Combat, AVOID_FOOD} = require('./combat');
require('./physicsfix');
const {BotTrace, SAMPLE_MS, round} = require('./debug');
const {normDim, deadlineMs, insideAreas} = require('./world');

const NAME_RE = /^bot[0-9]{1,2}$/; // BotGate's pattern (Velocity plugin)
const LOGIN_GAP_MS = 4500; // Velocity rate-limits logins
const GOTO_TIMEOUT_MS = 90000;
const BACKOFF_START = 5000;
const BACKOFF_CAP = 300000;
// Kept on deposit: what a bot needs to craft a replacement tool or light a mine.
const KEEP_RE = /^(stick|[a-z_]+_planks|coal|charcoal|torch|crafting_table|furnace)$/;
const FOOD_BELOW = 14; // fetch food from the supply chest when hungry and carrying none
const FOOD_RETRY_MS = 600000; // an empty chest is not worth a walk every minute
const RESUMABLE = new Set(['mine', 'chop', 'shift', 'goto', 'deposit', 'follow', 'come']);
const MAX_INTERRUPTIONS = 3; // deaths/disconnects of one job before it is given up
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
  // `only` (optional): put just that kind into the chest, even what a normal
  // deposit keeps (coal, torches); used by the keeper.
  deposit: (a) => {
    if (a.only !== undefined && !/^[a-z_]{1,48}$/.test(a.only)) throw new Error('only must be an item name like torch, or logs');
    return {...xyz(a), ...(a.only ? {only: a.only} : {})};
  },
  rearm: xyz,
  craft: (a) => {
    if (!/^[a-z_]{1,48}$/.test(a.item || '')) throw new Error('item must be an item name like stone_pickaxe');
    return {item: a.item, count: num(a.count ?? 1, 1, 64, 'count')};
  },
  smelt: (a) => {
    if (!/^[a-z_]{1,48}$/.test(a.item || '')) throw new Error('item must be what goes in, like raw_iron');
    return {item: a.item, count: num(a.count ?? 1, 1, 64, 'count')};
  },
  // Work shift: mine a block (or "logs") until stopped, depositing into the
  // chest at x,y,z whenever the inventory fills up.
  shift: (a) => {
    if (!/^[a-z_]{1,48}$/.test(a.block || '')) throw new Error('block must be a block name like stone, or logs');
    return {block: a.block, ...xyz(a)};
  },
  stock: xyz, // read what is in the chest (the keeper's inventory count)
  withdraw: (a) => {
    if (!/^[a-z_]{1,48}$/.test(a.item || '')) throw new Error('item must be an item name like coal, or logs');
    return {item: a.item, count: num(a.count ?? 1, 1, 1728, 'count'), ...xyz(a)};
  },
  place: (a) => {
    if (!/^[a-z_]{1,48}$/.test(a.item || '')) throw new Error('item must be a block name like chest');
    return {item: a.item, ...xyz(a)};
  },
  say: (a) => {
    const text = String(a.text ?? '').trim();
    if (!text || text.length > 200) throw new Error('text must be 1..200 characters');
    if (text.startsWith('/')) throw new Error('commands are not allowed');
    return {text};
  },
};

class Cancelled extends Error {}

const at = (c) => `${Math.round(c.x)} ${Math.round(c.y)} ${Math.round(c.z)}`;
// "the supply chest" when x,y,z is the configured one, else the coordinates.
const place = (r, c) => (r.supplyChest && r.supplyChest.x === c.x && r.supplyChest.y === c.y && r.supplyChest.z === c.z ? 'the supply chest' : at(c));
const jobLabel = (j) => `${j.type} ${Object.values(j.args).join(' ')}`;

class BotRunner {
  constructor(name, {host, port, log, world, protectedAreas = [], supplyChest = null, loginSeed = null, hostLabel = '', onEvent = null}) {
    this.name = name;
    this.onEvent = onEvent; // (bot, kind, text) -> dashboard event log
    this.dead = false;
    this.skip = new Map(); // block key -> time until which collect() leaves it alone
    this.conflicts = {n: 0, at: 0};
    this.hostLabel = hostLabel; // machine this bot runs on, shown in the dashboard
    this.lastSeen = 0;
    this.world = world;
    this.combat = {busy: false, epoch: 0}; // replaced by a Combat per connection
    this.host = host;
    this.protectedAreas = protectedAreas;
    this.supplyChest = supplyChest;
    // VeloAuth account password, derived per bot from a shared seed.
    this.password = loginSeed ? require('node:crypto').createHash('sha256').update(`${loginSeed}:${name}`).digest('hex').slice(0, 32) : null;
    this.port = port;
    this.log = log;
    this.bot = null;
    this.online = false;
    this.queue = [];
    this.current = null;
    this.trace = new BotTrace();
    this.lastError = '';
    this.backoff = BACKOFF_START;
    this.timer = null;
    this.stopped = false; // process shutdown
    this.jobSeq = 0;
  }

  // lastError lives in the trace so the debug panel knows when it happened.
  get lastError() {
    return this.trace.error?.message || '';
  }

  set lastError(v) {
    this.trace.setError(v);
  }

  start() {
    this.schedule(0);
  }

  emit(kind, text) {
    try {
      this.onEvent?.(this.name, kind, text);
    } catch {}
  }

  // Several bots digging one area refuse each other's blocks all the time;
  // report that as one event per 15 s, not one per refusal.
  conflict() {
    const c = this.conflicts;
    c.n++;
    if (Date.now() - c.at < 15000) return;
    this.emit('claim', `${c.n} block${c.n > 1 ? 's' : ''} skipped: another bot is working on ${c.n > 1 ? 'them' : 'it'}`);
    c.n = 0;
    c.at = Date.now();
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
    require('./crafting').fixCraftTiming(bot);
    unwedge(bot);
    bot.on('forcedMove', () => this.trace.correction());
    const sampler = setInterval(() => {
      this.trace.sample(bot.entity?.position);
      if (this.online) this.lastSeen = Date.now();
    }, SAMPLE_MS);
    sampler.unref();
    bot.once('end', () => clearInterval(sampler));
    let spawnedAt = 0;
    this.combat = new Combat(this);
    bot.once('spawn', () => {
      spawnedAt = Date.now();
      this.online = true;
      const mv = safeMovements(bot, this.protectedAreas);
      bot.pathfinder.setMovements(mv);
      // Unbounded searches toward buried targets ran the bot process out of
      // memory (2026-10-08); cap planning time and radius.
      bot.pathfinder.thinkTimeout = 4000;
      bot.pathfinder.searchRadius = 80;
      bot.collectBlock.movements = mv;
      this.log(this.name, 'spawned');
      this.emit('connect', 'joined the game');
      this.pump(); // a job kept across a disconnect continues now
    });
    // After a death the next spawn is the respawn; a stale "died" is not an error any more.
    bot.on('spawn', () => {
      if (!this.dead) return;
      this.dead = false;
      if (this.lastError === 'died') this.lastError = '';
      this.emit('respawn', 'respawned');
      this.pump(); // nothing runs while dead
    });
    // VeloAuth holds players without a Minecraft account until /login (or
    // /register the first time). Prompts are matched in English.
    let authed = false;
    bot.on('spawn', () => {
      if (!authed && this.password) setTimeout(() => !authed && bot.chat(`/login ${this.password}`), 1500);
    });
    // The holding area sends no normal spawn, so answer its prompts directly.
    bot.on('messagestr', (msg) => {
      if (!this.password || authed) return;
      if (/not registered|use \/register/i.test(msg)) bot.chat(`/register ${this.password} ${this.password}`);
      else if (/use \/login|already registered/i.test(msg)) bot.chat(`/login ${this.password}`);
      else if (/logged in successfully|registered successfully|already logged in/i.test(msg)) {
        authed = true;
        this.log(this.name, 'logged in to VeloAuth');
      } else if (/incorrect password/i.test(msg)) this.lastError = 'VeloAuth: wrong password for this bot name';
    });
    bot.on('entityGone', (e) => this.world.forgetMob(e.id));
    bot.on('death', () => {
      this.dead = true;
      this.lastError = 'died';
      const p = bot.entity?.position;
      this.emit('death', `died${p ? ` at ${Math.round(p.x)} ${Math.round(p.y)} ${Math.round(p.z)}` : ''}`);
      const was = this.current && !this.current.cancelled ? this.current : null; // a job the user stopped stays stopped
      this.cancel();
      this.resumeLater(was, 'died');
      // Re-equip from the supply chest first thing after respawning.
      if (this.supplyChest) this.queue.unshift({id: ++this.jobSeq, type: 'rearm', args: this.supplyChest, status: 'queued'});
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
      this.dead = false;
      if (spawnedAt) this.emit('disconnect', `left the game (${why})`); // failed connection attempts are not news
      this.combat.stop();
      const was = this.current && !this.current.cancelled ? this.current : null; // a job the user stopped stays stopped
      this.cancel();
      this.resumeLater(was, 'disconnected');
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
  // replace: drop the queue and the running job first, so a click means "do
  // this now" instead of waiting behind earlier clicks.
  enqueue(type, args = {}, {replace = false} = {}) {
    if (replace && type !== 'stop' && type !== 'remove') {
      this.queue = [];
      this.cancel();
    }
    if (type === 'stop') {
      this.queue = [];
      this.cancel();
      return;
    }
    if (type === 'remove') {
      this.queue = this.queue.filter((j) => j.id !== Number(args.id)); // queued jobs only; "stop" ends the running one
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
      b?.pathfinder?.setGoal(null); // stop() alone is ignored while no path is active, and goto() then never settles
      b?.collectBlock?.cancelTask().catch(() => {});
      b?.stopDigging?.();
    } catch {}
  }

  // A job cut short by a death or a disconnect goes back to the front of the
  // queue (after the re-arm), keeps its progress (job.collected) and walks back
  // to where it was working first. A job that keeps killing the bot is dropped.
  resumeLater(j, why) {
    if (!j || !RESUMABLE.has(j.type)) return;
    j.interrupted = true;
    const n = (j.interruptions || 0) + 1;
    if (n > MAX_INTERRUPTIONS) {
      this.emit('fail', `gave up: ${jobLabel(j)} (${why} ${n} times)`);
      return;
    }
    const area = j.t?.area || j.startPos;
    this.queue.unshift({...j, status: 'queued', cancelled: false, interrupted: false, interruptions: n, resume: area || true, t: undefined});
  }

  async pump() {
    if (this.current || !this.queue.length) return;
    if (this.dead) return; // the respawn handler pumps again
    if (!this.online && this.queue[0].resume) return; // resumed jobs wait for the reconnect
    const job = (this.current = this.queue.shift());
    job.status = 'running';
    job.startedAt = Date.now();
    job.progress = '';
    job.t = {doing: '', done: 0, total: 0, open: false}; // live detail; sub-jobs share it through the prototype
    const p = this.bot?.entity?.position;
    job.startPos ||= p ? {x: Math.round(p.x), y: Math.round(p.y), z: Math.round(p.z)} : null;
    this.emit('job', `${job.resume ? 'resumed' : 'started'}: ${jobLabel(job)}`);
    try {
      if (!this.online) throw new Error('bot is offline');
      if (job.resume) {
        const at = job.resume;
        job.resume = null;
        if (at.x !== undefined) {
          try {
            await goNear(this, job, at.x, at.y, at.z, 6, {doing: 'returning to the job area'});
          } catch (e) {
            if (job.cancelled) throw e; // a stop wins; a failed walk back just starts from here
          }
        }
      }
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
    const took = Math.round((Date.now() - job.startedAt) / 1000);
    if (job.interrupted) this.emit('info', `interrupted: ${jobLabel(job)} (it continues after the respawn/reconnect)`);
    else if (job.status === 'done') this.emit('done', `finished: ${jobLabel(job)} (${took} s)`);
    else if (job.status === 'stopped') this.emit('stop', `stopped: ${jobLabel(job)}`);
    else this.emit('fail', `failed: ${jobLabel(job)} - ${this.lastError.replace(/^\w+: /, '')}`);
    this.current = null;
    setImmediate(() => this.pump());
  }

  snapshot() {
    const b = this.bot;
    const inv = {};
    if (this.online) for (const it of b.inventory.items()) inv[it.name] = (inv[it.name] || 0) + it.count;
    const top = Object.entries(inv).sort((a, c) => c[1] - a[1]);
    const label = jobLabel;
    return {
      name: this.name,
      host: this.hostLabel,
      lastSeen: this.online ? Date.now() : this.lastSeen,
      online: this.online,
      health: this.online ? b.health : null,
      food: this.online ? b.food : null,
      pos: this.online && b.entity ? ['x', 'y', 'z'].map((k) => Math.round(b.entity.position[k])) : null,
      dimension: this.online ? normDim(b.game?.dimension) : null,
      combat: this.combat.mode || null,
      job: this.current && {label: label(this.current), progress: this.current.progress, type: this.current.type, done: this.current.t?.done || 0, total: this.current.t?.total || 0, runningS: Math.round((Date.now() - (this.current.startedAt || Date.now())) / 1000)},
      activity: this.activity(),
      dead: this.dead,
      tool: this.tool(),
      freeSlots: this.online ? b.inventory.emptySlotCount() : null,
      queue: this.queue.map(label),
      queueIds: this.queue.map((j) => j.id),
      inventory: top.map(([n, c]) => `${n} x${c}`),
      inventoryKinds: top.length,
      lastError: this.lastError,
      lastErrorAgoS: this.trace.error ? Math.round((Date.now() - this.trace.error.t) / 1000) : null,
      pullbacks: this.trace.recentCorrections(),
    };
  }

  // One plain-language line for the dashboard: what is this bot doing now?
  activity() {
    if (!this.online) return this.lastSeen ? 'offline' : 'connecting...';
    if (this.dead) return 'dead - respawning';
    if (this.combat.busy) return `fighting or retreating (${this.combat.mode || 'combat'})`;
    const j = this.current;
    if (!j) return this.queue.length ? 'starting the next job' : 'idle - no job';
    return j.t?.doing || `${jobLabel(j)} ${j.progress || ''}`.trim();
  }

  // Held tool and what is left of it (durability), or null with empty hands.
  tool() {
    const it = this.online && this.bot.heldItem;
    if (!it) return null;
    const max = this.bot.registry.itemsByName[it.name]?.maxDurability || 0;
    return {name: it.name, max, left: max ? Math.max(0, max - (it.durabilityUsed || 0)) : null};
  }

  // Everything needed to see why a bot is not moving (GET /api/debug).
  debug() {
    const b = this.bot, e = b?.entity, j = this.current;
    const live = this.online && !!e;
    const pf = live && b.pathfinder;
    return {
      name: this.name,
      host: this.hostLabel,
      lastSeen: this.online ? Date.now() : this.lastSeen,
      online: this.online,
      pos: live ? ['x', 'y', 'z'].map((k) => round(e.position[k])) : null,
      dimension: live ? normDim(b.game?.dimension) : null,
      job: j && {id: j.id, type: j.type, args: j.args, status: j.status, progress: j.progress || '', runningS: round((Date.now() - (j.startedAt || Date.now())) / 1000, 1)},
      queue: this.queue.map(jobLabel),
      combat: this.combat.mode || null,
      claims: this.world?.claimStats(this.name) || {granted: 0, refused: 0, timedOut: 0},
      physics: live ? {onGround: !!e.onGround, collidedHorizontally: !!e.isCollidedHorizontally, velocity: ['x', 'y', 'z'].map((k) => round(e.velocity?.[k], 3)), controls: Object.keys(b.controlState || {}).filter((k) => b.controlState[k])} : null,
      pathfinder: pf ? {moving: !!pf.isMoving?.(), mining: !!pf.isMining?.(), building: !!pf.isBuilding?.(), goal: pf.goal?.constructor?.name || null} : null,
      ...this.trace.snapshot(),
    };
  }
}


// Pathing uses mineflayer's default movement (it may dig and pillar outside
// bases). Inside protected areas (player bases) it neither digs nor places.
// A custom unbreakable-block list made the pathfinder plan routes it then
// refused to walk (2026-10-08), so protection is by area only.
// Safety net behind physicsfix.js (the cause of the wall/step wedge: the
// client stopped exactly flush against blocks and the server refused that):
// if a bot is still pulled back every tick (~20 forced moves/s), re-centre it
// in its block (seen after stopping a mining job in a 1-wide pit, 2026-10-08).
function unwedge(bot) {
  let times = [];
  bot.on('forcedMove', () => {
    const now = Date.now();
    times = times.filter((t) => now - t < 1000);
    times.push(now);
    if (times.length < 10) return;
    times = [];
    const pos = bot.entity.position;
    const feet = bot.blockAt(pos.floored());
    const head = bot.blockAt(pos.floored().offset(0, 1, 0));
    if (feet?.boundingBox !== 'empty' || head?.boundingBox !== 'empty') return;
    pos.x = Math.floor(pos.x) + 0.5;
    pos.z = Math.floor(pos.z) + 0.5;
  });
}

function safeMovements(bot, areas) {
  const mv = new Movements(bot);
  // Bots speak 26.1 to a 26.2 server through ViaBackwards; sprinting, parkour
  // jumps and diagonal corner-cutting make the server reject the move and pull
  // the bot back (277 corrections in 15 s vs 0 without them, 2026-10-08).
  mv.allowSprinting = false;
  mv.allowParkour = false;
  mv.getMoveDiagonal = () => {};
  const inside = (blk) => insideAreas(areas, blk.position.x, blk.position.z);
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
    job.t.doing = 'waiting: a hostile mob is near the target';
    await waitCalm(r, job);
    await sleep(1000);
  }
}

async function goNear(r, job, x, y, z, dist, {brave = false, goal = null, doing = null} = {}) {
  guard(job);
  if (job.t) job.t.doing = doing || `walking to ${at({x, y, z})}`;
  // Unreachable goals make the pathfinder retry partial paths
  // forever, so every walk has a deadline.
  let timedOut = false;
  const deadline = setTimeout(() => {
    timedOut = true;
    r.bot?.pathfinder.stop();
    r.bot?.pathfinder.setGoal(null); // makes a pending goto() reject; stop() alone left one hanging for minutes (2026-10-08)
  }, GOTO_TIMEOUT_MS);
  try {
    // Something else (combat, a block update) can stop the path mid-walk; walk
    // again instead of failing the job, unless the deadline or a stop hit.
    for (let tries = 0; ; tries++) {
      try {
        if (!brave) await waitSafe(r, job, x, z);
        await r.bot.pathfinder.goto(goal || new goals.GoalNear(x, y, z, dist));
        return;
      } catch (e) {
        guard(job);
        if (timedOut || tries >= 3) {
          throw new Error(`could not reach ${Math.round(x)} ${Math.round(y)} ${Math.round(z)}: ${e.message}`);
        }
        await sleep(1000);
      }
    }
  } finally {
    clearTimeout(deadline);
  }
}

// Mine one block and pick up what drops. Replaces mineflayer-collectblock,
// which froze the bot process (synchronous loop until out of memory) when
// asked to mine stone without a pickaxe (2026-10-08).
async function digAt(r, job, pos) {
  const {bot} = r;
  let block = bot.blockAt(pos);
  if (!block || block.name.endsWith('air')) return;
  const tools = block.harvestTools ? Object.keys(block.harvestTools).map(Number) : null;
  if (tools && !bot.inventory.items().some((i) => tools.includes(i.type))) {
    throw new Error(`needs a tool that can harvest ${block.name} (for stone and ore: a pickaxe)`);
  }
  await goNear(r, job, pos.x, pos.y, pos.z, 4, {goal: new goals.GoalLookAtBlock(pos, bot.world, {reach: 4}), doing: `walking to ${block.name} near ${at(pos)}${tally(job)}`});
  guard(job);
  block = bot.blockAt(pos);
  if (!block || block.name.endsWith('air')) return;
  job.t.doing = `mining ${block.name}${tally(job)} near ${at(pos)}`;
  await bot.tool.equipForBlock(block, {}).catch(() => {});
  // A dig the server never answers hangs forever: give it 25 s, then try another block.
  let digTimer;
  const gave = await Promise.race([bot.dig(block, true).then(() => false), new Promise((res) => (digTimer = setTimeout(() => res(true), 25000)))]);
  clearTimeout(digTimer);
  if (gave) {
    bot.stopDigging();
    r.emit('info', `digging ${block.name} at ${at(pos)} got no answer: skipped`);
    return;
  }
  // Walk over the drops near the block (items merge and fly a little).
  await sleep(400);
  const drops = Object.values(bot.entities).filter((e) => e.name === 'item' && e.position.distanceTo(pos) <= 4);
  for (const d of drops) {
    guard(job);
    await goNear(r, job, d.position.x, d.position.y, d.position.z, 0.8, {doing: 'picking up the drops'}).catch(() => {});
  }
}

// Report the supply chest's contents to the shared picture (the keeper plans from it).
const isSupply = (r, c) => !!r.supplyChest && r.supplyChest.x === c.x && r.supplyChest.y === c.y && r.supplyChest.z === c.z;
function noteStock(r, job, chest) {
  if (!isSupply(r, job.args)) return;
  const items = {};
  for (const it of chest.containerItems()) items[it.name] = (items[it.name] || 0) + it.count;
  r.world?.noteStock(r.name, items);
}
// "logs" stands for every kind of log; anything else is an exact item name.
const itemMatcher = (what) => (what === 'logs' ? (n) => n.endsWith('_log') : what === 'coal' ? (n) => n === 'coal' || n === 'charcoal' : (n) => n === what);

// A chest cannot be opened with a solid block on top. The pathfinder builds with
// dirt (which grows grass)/cobblestone/stone/netherrack, and a chest it bridged over stayed shut
// for the bots (2026-10-08): clear that kind of cover, report anything else.
const SCAFFOLD = /^(dirt|grass_block|cobblestone|stone|netherrack)$/; // dirt turns into grass in the light
async function openChest(r, job, block) {
  const {bot} = r;
  const p = block.position.offset(0, 1, 0);
  const above = bot.blockAt(p);
  if (/chest/.test(block.name) && above && above.boundingBox === 'block') {
    if (!SCAFFOLD.test(above.name) || insideAreas(r.protectedAreas, p.x, p.z)) throw new Error(`${block.name} at ${at(block.position)} is covered by ${above.name}`);
    job.t.doing = `clearing ${above.name} off the chest`;
    r.emit('info', `chest at ${at(block.position)} was covered by ${above.name}: digging it away`);
    await bot.dig(above, true);
  }
  return bot.openContainer(block);
}

// Where a job may empty the inventory: a shift's own chest, else the supply chest.
const chestOf = (r, job) => (job.type === 'shift' ? {x: job.args.x, y: job.args.y, z: job.args.z} : r.supplyChest);
const edible = (bot, it) => bot.registry.foodsByName[it.name] && !AVOID_FOOD.has(it.name);
const canHarvest = (bot, id) => {
  const tools = bot.registry.blocks[id]?.harvestTools;
  return !tools || bot.inventory.items().some((i) => tools[i.type]);
};
// A child job: shares cancellation with `job`, has its own counters and arguments.
const child = (job, extra = {}) => Object.assign(Object.create(job), {collected: 0, progress: '', ...extra});

// Keep a long job going without the owner: replace a broken pickaxe, fetch food
// when hungry and carrying none, empty a full inventory. Called before every
// block of collect(); the helpers below may call collect themselves (logs for
// a new pickaxe), hence the guard.
async function upkeep(r, job, ids) {
  if (job.t.upkeep) return;
  job.t.upkeep = true;
  const shown = {done: job.t.done, total: job.t.total};
  try {
    const {bot} = r;
    const need = ids.find((id) => !canHarvest(bot, id));
    if (need !== undefined) await replacePickaxe(r, job);
    if (bot.food < FOOD_BELOW && r.supplyChest && !bot.inventory.items().some((i) => edible(bot, i)) && Date.now() - (r.foodTriedAt || 0) > FOOD_RETRY_MS) {
      r.foodTriedAt = Date.now();
      r.emit('info', `hungry (food ${bot.food}) and no food: fetching some from the supply chest`);
      await JOBS.rearm(r, child(job, {type: 'rearm', args: r.supplyChest})).catch((e) => {
        guard(job);
        r.emit('info', `no food fetched: ${e.message}`); // keep working; the retry timer asks again later
      });
    }
    if (bot.inventory.emptySlotCount() < 2) {
      const chest = chestOf(r, job);
      if (!chest) throw new Error('inventory is full and there is no supply chest to deposit into');
      await JOBS.deposit(r, child(job, {type: 'deposit', args: chest}));
      if (bot.inventory.emptySlotCount() < 2) throw new Error('inventory still full after depositing (chest full?)');
    }
  } finally {
    job.t.upkeep = false;
    Object.assign(job.t, shown); // helper jobs borrowed the counters
  }
}

// No tool that can harvest: craft a stone pickaxe, else a wooden one (chopping
// logs first when there is no wood), else take one from the supply chest.
async function replacePickaxe(r, job) {
  const {bot} = r;
  job.t.doing = 'replacing the pickaxe';
  r.emit('info', 'no pickaxe left: making a new one');
  const has = () => bot.inventory.items().some((i) => i.name.endsWith('_pickaxe'));
  let why = '';
  for (const item of ['stone_pickaxe', 'wooden_pickaxe']) {
    try {
      await crafting.ensureItem(r, child(job), item, 1);
      if (has()) return;
    } catch (e) {
      guard(job);
      why = e.message;
    }
  }
  const logs = Object.keys(bot.registry.blocksByName).filter((n) => n.endsWith('_log'));
  if (!bot.inventory.items().some((i) => /_log$/.test(i.name))) { // planks alone (2 of the 3 needed) are no reason to stay without a pickaxe
    try {
      await collect(r, child(job), logs, 3, 'logs');
      await crafting.ensureItem(r, child(job), 'wooden_pickaxe', 1);
      if (has()) return;
    } catch (e) {
      guard(job);
      why = e.message;
    }
  }
  if (r.supplyChest) {
    try {
      await JOBS.rearm(r, child(job, {type: 'rearm', args: r.supplyChest}));
    } catch (e) {
      guard(job);
      why = e.message;
    }
    if (has()) return;
  }
  throw new Error(`no pickaxe and could not make one: ${why}`);
}

async function collect(r, job, matching, count, what) {
  const {bot} = r;
  const ids = matching.map((n) => bot.registry.blocksByName[n]?.id).filter((i) => i !== undefined);
  if (!ids.length) throw new Error(`unknown block: ${what}`);
  let got = job.collected || 0; // survives a combat interruption + resume
  let misses = 0;
  if (!job.t.open) Object.assign(job.t, {done: got, total: count});
  while (got < count) {
    await waitCalm(r, job);
    await upkeep(r, job, ids);
    // Nearest block that no other bot is working on, so bots spread out
    // instead of all walking to the same ore.
    const dim = normDim(bot.game?.dimension);
    const keyOf = (p) => `${dim}:${p.x},${p.y},${p.z}`;
    // A reservation is only valid once the shared table granted it: on a
    // remote worker the hub decides (one round trip), so a lab bot and a
    // laptop bot never dig the same block.
    if (r.world?.unreachable) throw new Error('hub unreachable: not digging without block reservations');
    let pos = null;
    let key = null;
    for (const p of bot.findBlocks({matching: ids, maxDistance: 64, count: 48})) {
      if ((r.skip.get(keyOf(p)) || 0) > Date.now()) continue; // could not get there lately
      // Digging a target is direct (not pathfinder), so protection is checked here too.
      if (insideAreas(r.protectedAreas, p.x, p.z)) continue;
      const k = keyOf(p);
      if (r.world && !(await r.world.claim(r.name, k))) {
        r.conflict();
        continue;
      }
      pos = p;
      key = k;
      job.t.area = {x: p.x, y: p.y, z: p.z}; // where a resumed job walks back to
      break;
    }
    if (!pos) throw new Error(`no free ${what} within 64 blocks (collected ${got}/${count})`);
    try {
      await waitSafe(r, job, pos.x, pos.z);
      await digAt(r, job, pos);
      misses = 0;
    } catch (e) {
      guard(job);
      // One block nobody can walk to must not end a long job: skip it for 5 min, give up after 5 in a row.
      if (!/could not reach/.test(e.message) || ++misses > 5) throw e;
      for (const [k, until] of r.skip) if (until < Date.now()) r.skip.delete(k);
      r.skip.set(key, Date.now() + 300000);
      r.emit('info', `skipped a ${what} block that cannot be reached (${at(pos)})`);
      continue;
    } finally {
      r.world?.release(r.name, key);
    }
    job.collected = ++got;
    job.progress = `${got}/${count}`;
    if (!job.t.open) Object.assign(job.t, {done: got, total: count});
  }
}

// " 12/32" for jobs that count their blocks, else "".
const tally = (job) => (job.t?.total ? ` ${job.t.done}/${job.t.total}` : '');
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
        // A dynamic GoalFollow never started walking with our movement
        // settings (2026-10-08); a fixed GoalNear re-issued whenever the player
        // has moved does.
        const d = dist3(me, e.position);
        maxDist = Math.max(maxDist, d);
        if (!follow && d <= 3) return;
        if (d > 3 && (mode !== 'entity' || !bot.pathfinder.isMoving() || dist3(goalAt, e.position) > 2)) {
          bot.pathfinder.setGoal(new goals.GoalNear(e.position.x, e.position.y, e.position.z, 2));
          mode = 'entity';
          goalAt = e.position.clone();
        }
        job.progress = `${follow ? 'following' : 'tracking'}, ${Math.round(d)} blocks`;
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

const crafting = require('./crafting').makeCrafting({goNear, guard});

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
    await goNear(r, job, x, y, z, 3, {doing: `walking to ${place(r, job.args)} to deposit`});
    job.t.doing = `depositing at ${place(r, job.args)}`;
    const block = bot.blockAt(new (require('vec3').Vec3)(x, y, z));
    if (!block || !/chest|barrel/.test(block.name)) throw new Error(`no chest at ${x} ${y} ${z} (found ${block?.name})`);
    const chest = await openChest(r, job, block);
    try {
      let moved = 0;
      const only = job.args.only && itemMatcher(job.args.only);
      for (const it of bot.inventory.items()) {
        guard(job);
        if (only ? !only(it.name) : TOOL_RE.test(it.name) || KEEP_RE.test(it.name) || bot.registry.foodsByName[it.name]) continue;
        try {
          await chest.deposit(it.type, it.metadata, it.count);
          moved += it.count;
          job.progress = `${moved} items`;
        } catch (e) {
          throw new Error(`chest full or deposit failed after ${moved} items: ${e.message}`);
        }
      }
      if (moved) r.emit('deposit', `deposited ${moved} items at ${place(r, job.args)}`);
      noteStock(r, job, chest);
    } finally {
      chest.close();
    }
  },

  // Open the chest and report what is in it; changes nothing.
  async stock(r, job) {
    const {bot} = r;
    const {x, y, z} = job.args;
    await goNear(r, job, x, y, z, 3, {doing: `walking to ${place(r, job.args)} to count its contents`});
    const block = bot.blockAt(new (require('vec3').Vec3)(x, y, z));
    if (!block || !/chest|barrel/.test(block.name)) throw new Error(`no chest at ${x} ${y} ${z} (found ${block?.name})`);
    job.t.doing = `counting what is in ${place(r, job.args)}`;
    const chest = await openChest(r, job, block);
    try {
      noteStock(r, job, chest);
    } finally {
      chest.close();
    }
  },

  // Take up to `count` of an item (or "logs") out of the chest.
  async withdraw(r, job) {
    const {bot} = r;
    const {x, y, z, item, count} = job.args;
    await goNear(r, job, x, y, z, 3, {doing: `walking to ${place(r, job.args)} to take ${item}`});
    const block = bot.blockAt(new (require('vec3').Vec3)(x, y, z));
    if (!block || !/chest|barrel/.test(block.name)) throw new Error(`no chest at ${x} ${y} ${z} (found ${block?.name})`);
    job.t.doing = `taking ${item} from ${place(r, job.args)}`;
    const chest = await openChest(r, job, block);
    try {
      let taken = 0;
      const match = itemMatcher(item);
      for (const it of chest.containerItems().filter((i) => match(i.name))) {
        guard(job);
        if (taken >= count) break;
        const n = Math.min(count - taken, it.count);
        await chest.withdraw(it.type, it.metadata, n);
        taken += n;
        job.progress = `${taken}/${count}`;
      }
      if (!taken) throw new Error(`no ${item} in the chest`);
      noteStock(r, job, chest);
    } finally {
      chest.close();
    }
  },

  // Visit every chest/barrel within 6 blocks of the supply point and take
  // what is missing: best armour per slot, a sword, an axe, a pickaxe, a totem
  // for the off-hand and food up to 32; then wear/hold it.
  async rearm(r, job) {
    const {bot} = r;
    const {x, y, z} = job.args;
    const Vec3 = require('vec3').Vec3;
    const centre = new Vec3(x, y, z);
    const ids = ['chest', 'trapped_chest', 'barrel'].map((n) => bot.registry.blocksByName[n]?.id).filter((i) => i !== undefined);
    await goNear(r, job, x, y, z, 3, {brave: true, doing: `walking to ${place(r, job.args)} to re-arm`}); // getting armour is the safety step
    const spots = bot.findBlocks({matching: ids, point: centre, maxDistance: 6, count: 64});
    if (!spots.length) throw new Error(`no chests within 6 blocks of ${x} ${y} ${z}`);
    const tier = (n) => ['wooden', 'leather', 'golden', 'stone', 'chainmail', 'iron', 'diamond', 'netherite'].findIndex((t) => n.startsWith(t));
    const best = (items, re) => items.filter((i) => re.test(i.name)).sort((a, b) => tier(b.name) - tier(a.name))[0];
    const mine = () => [...bot.inventory.items(), ...['head', 'torso', 'legs', 'feet', 'off-hand'].map((s) => bot.inventory.slots[bot.getEquipmentDestSlot(s)]).filter(Boolean)];
    const WANT = [/_helmet$/, /_chestplate$/, /_leggings$/, /_boots$/, /_sword$/, /_axe$/, /_pickaxe$/, /^totem_of_undying$/];
    const isFood = (n) => bot.registry.foodsByName[n] && !/rotten|spider_eye|poisonous|pufferfish|chorus|golden_apple/.test(n);
    const foodCount = () => bot.inventory.items().filter((i) => isFood(i.name)).reduce((n, i) => n + i.count, 0);
    const opened = new Set();
    for (const pos of spots) {
      guard(job);
      // A double chest is two blocks but one inventory; skip the second half.
      if ([...opened].some((k) => pos.distanceTo(k) <= 1.01)) continue;
      opened.add(pos);
      job.t.doing = `re-arming from ${place(r, job.args)}`;
      await goNear(r, job, pos.x, pos.y, pos.z, 3, {brave: true, doing: job.t.doing});
      const box = await openChest(r, job, bot.blockAt(pos));
      try {
        for (const re of WANT) {
          const have = best(mine(), re);
          const offer = best(box.containerItems(), re);
          if (offer && (!have || tier(offer.name) > tier(have.name))) await box.withdraw(offer.type, offer.metadata, 1);
        }
        const food = box.containerItems().filter((i) => isFood(i.name)).sort((a, b) => (b.name === 'golden_carrot') - (a.name === 'golden_carrot'))[0];
        if (food && foodCount() < 32) await box.withdraw(food.type, food.metadata, Math.min(32 - foodCount(), food.count));
      } finally {
        box.close();
      }
    }
    for (const [re, slot] of [[/_helmet$/, 'head'], [/_chestplate$/, 'torso'], [/_leggings$/, 'legs'], [/_boots$/, 'feet']]) {
      const it = best(bot.inventory.items(), re);
      if (it) await bot.equip(it, slot).catch(() => {});
    }
    const totem = bot.inventory.items().find((i) => i.name === 'totem_of_undying');
    if (totem) await bot.equip(totem, 'off-hand').catch(() => {});
    const sword = best(bot.inventory.items(), /_sword$/);
    if (sword) await bot.equip(sword, 'hand').catch(() => {});
    const worn = ['head', 'torso', 'legs', 'feet'].filter((s) => bot.inventory.slots[bot.getEquipmentDestSlot(s)]).length;
    const off = bot.inventory.slots[bot.getEquipmentDestSlot('off-hand')]?.name;
    job.progress = `armour ${worn}/4, ${sword?.name || 'no sword'}, off-hand ${off || 'empty'}, food ${foodCount()}`;
  },

  craft: (r, job) => crafting.ensureItem(r, job, job.args.item, crafting.count(r.bot, job.args.item) + job.args.count),

  smelt: (r, job) => crafting.smelt(r, job, job.args.item, job.args.count),

  async shift(r, job) {
    const {bot} = r;
    const logs = job.args.block === 'logs';
    const matching = logs ? Object.keys(bot.registry.blocksByName).filter((n) => n.endsWith('_log')) : [job.args.block];
    // Sub-jobs share cancellation with the shift (prototype) but keep their own
    // progress, so one stop ends everything.
    const sub = (extra) => Object.assign(Object.create(job), extra);
    let total = 0;
    job.t.open = true; // no end: the dashboard shows a count, not a bar
    for (;;) {
      guard(job);
      if (bot.inventory.emptySlotCount() < 4) {
        job.progress = `depositing (${total} so far)`;
        await JOBS.deposit(r, sub({args: {x: job.args.x, y: job.args.y, z: job.args.z}}));
        if (bot.inventory.emptySlotCount() < 4) throw new Error('inventory still full after depositing (chest full?)');
        continue;
      }
      const round = sub({});
      await collect(r, round, matching, 8, job.args.block);
      total += 8;
      job.progress = `${total} ${job.args.block} mined`;
      job.t.done = total;
    }
  },

  // Put one block (a chest, a crafting table, ...) at x,y,z on top of a solid
  // block; crafts it first when the bot has none and a recipe exists.
  async place(r, job) {
    const {bot} = r;
    const {item, x, y, z} = job.args;
    if (insideAreas(r.protectedAreas, x, z)) throw new Error(`${x} ${z} is inside a protected area`);
    const Vec3 = require('vec3').Vec3;
    const at = new Vec3(x, y, z);
    if (bot.blockAt(at)?.name === item) return; // already there
    await crafting.ensureItem(r, job, item, 1);
    await goNear(r, job, x, y, z, 3, {goal: new goals.GoalPlaceBlock(at, bot.world, {range: 4}), doing: `walking to ${x} ${y} ${z} to place ${item}`});
    const below = bot.blockAt(at.offset(0, -1, 0));
    const here = bot.blockAt(at);
    if (!below || below.boundingBox !== 'block') throw new Error(`nothing solid under ${x} ${y} ${z}`);
    if (here && here.boundingBox !== 'empty') throw new Error(`${here.name} is in the way at ${x} ${y} ${z}`);
    job.t.doing = `placing ${item} at ${x} ${y} ${z}`;
    await bot.equip(bot.inventory.items().find((i) => i.name === item), 'hand');
    await bot.placeBlock(below, new Vec3(0, 1, 0)).catch(() => {}); // 26.x may not echo the update in time
    for (let i = 0; i < 20 && bot.blockAt(at)?.name !== item; i++) await sleep(100);
    if (bot.blockAt(at)?.name !== item) throw new Error(`placing ${item} did not take`);
    r.emit('info', `placed ${item} at ${x} ${y} ${z}`);
  },

  async say(r, job) {
    r.bot.chat(job.args.text);
  },
};

module.exports = {BotRunner, NAME_RE, VALIDATE, TOOL_RE, JOBS};
