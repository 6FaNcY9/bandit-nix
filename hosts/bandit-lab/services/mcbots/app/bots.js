'use strict';
require('./itemfix'); // must load before mineflayer
require('./digfix');
// One BotRunner per bot: connection lifecycle plus a sequential job queue.
// Adding a job type (crafting, building, ...) = add one entry to JOBS and one
// to VALIDATE; nothing else changes.
const mineflayer = require('mineflayer');
const {pathfinder, Movements, goals} = require('mineflayer-pathfinder');
const {Vec3} = require('vec3');
const {plugin: collectBlock} = require('mineflayer-collectblock');
const {Combat, AVOID_FOOD, deathCause} = require('./combat');
require('./physicsfix');
const {cacheGetBlock} = require('./pathcache');
const {BotTrace, SAMPLE_MS, round} = require('./debug');
const {normDim, deadlineMs, insideAreas, shouldFight} = require('./world');
const buildJob = require('./build');
const huntJob = require('./hunt');
const gravesJob = require('./graves');
const treeFarmJob = require('./treefarm');
const homebedJob = require('./homebed');
const levelJob = require('./level');
const tidyJob = require('./tidy');

const NAME_RE = /^bot[0-9]{1,2}$/; // BotGate's pattern (Velocity plugin)
const LOGIN_GAP_MS = 4500; // Velocity rate-limits logins
const GOTO_TIMEOUT_MS = 90000;
const BACKOFF_START = 5000;
const BACKOFF_CAP = 300000;
// Kept on deposit: what a bot needs to craft a replacement tool or light a mine.
// Natural ground an excavation may remove; never placed blocks (cobblestone is a wall).
const NATURAL = /^(stone|deepslate|dirt|grass_block|coarse_dirt|rooted_dirt|podzol|mud|clay|gravel|sand|red_sand|andesite|diorite|granite|tuff|calcite|dripstone_block|[a-z_]*_ore|short_grass|tall_grass|fern|large_fern|[a-z_]*_flower|dandelion|poppy|moss_block|moss_carpet|glow_lichen|cave_vines|cave_vines_plant)$/;
const KEEP_RE = /^(stick|[a-z_]+_planks|coal|charcoal|torch|crafting_table|furnace)$/;
const FOOD_BELOW = 14; // fetch food from the supply chest when hungry and carrying none
const FOOD_RETRY_MS = 600000; // an empty chest is not worth a walk every minute
const RESUMABLE = new Set(['mine', 'chop', 'shift', 'goto', 'deposit', 'follow', 'come', 'guard', 'build', 'excavate', 'shaft', 'level', 'hunt', 'bed', 'homebed', 'treefarm', 'tidy']);
// Long jobs that survive a restart (see keptOf, saved by server.js, reported by workers).
const KEEP = new Set(['shift', 'guard', 'mine', 'chop', 'build', 'excavate', 'shaft', 'level', 'hunt', 'homebed', 'treefarm']); // a resumed build/excavate skips what is done
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

// The running and queued jobs of a runner that a restart should bring back; a mine/chop keeps only what is left of its count.
const keptOf = (r) => [r.current, ...(r.queue || [])].filter((j) => j && !j.cancelled && KEEP.has(j.type)).map((j) => {
  const args = {...j.args};
  if (args.count && j.collected) args.count = Math.max(1, args.count - j.collected);
  return {type: j.type, args};
});

// Normalise and validate job arguments (throws on bad input).
const VALIDATE = {
  goto: xyz,
  follow: player,
  come: player,
  // Guard a spot (x,y,z) or a player: fight every hostile within radius of it.
  guard: (a) => ({...(a.player ? player(a) : xyz(a)), radius: num(a.radius ?? 16, 4, 48, 'radius')}),
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
  // Collect the dropped items within `radius` of x,y,z (default: the supply chest) and deposit them there.
  tidy: (a) => ({...(a.x !== undefined ? xyz(a) : {}), radius: num(a.radius ?? 16, 2, 32, 'radius')}),
  grave: xyz, // where the bot died; AxGraves keeps the loot in a grave there
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
  // A box to dig out (an underground room): two corners, at most 9x9 wide and 5 high.
  excavate: (a) => {
    const p = xyz({x: a.x1, y: a.y1, z: a.z1}), q = xyz({x: a.x2, y: a.y2, z: a.z2});
    const box = {x1: Math.min(p.x, q.x), y1: Math.min(p.y, q.y), z1: Math.min(p.z, q.z), x2: Math.max(p.x, q.x), y2: Math.max(p.y, q.y), z2: Math.max(p.z, q.z)};
    if (box.x2 - box.x1 > 8 || box.z2 - box.z1 > 8 || box.y2 - box.y1 > 4) throw new Error('a room is at most 9 x 9 blocks and 5 high');
    return box;
  },
  // A shaft down to bedrock: a square of up to 16 x 16 from y `top` (default 80) to `bottom`
  // (default -59, the lowest layer without bedrock), with a staircase left along its walls.
  shaft: (a) => {
    const p = xyz({x: a.x1, y: a.top ?? 80, z: a.z1}), q = xyz({x: a.x2, y: a.bottom ?? -59, z: a.z2});
    const box = {x1: Math.min(p.x, q.x), z1: Math.min(p.z, q.z), x2: Math.max(p.x, q.x), z2: Math.max(p.z, q.z), top: Math.max(p.y, q.y), bottom: Math.max(-59, Math.min(p.y, q.y))};
    if (box.x2 - box.x1 > 15 || box.z2 - box.z1 > 15 || box.x2 - box.x1 < 2 || box.z2 - box.z1 < 2) throw new Error('a shaft is 3 x 3 to 16 x 16 blocks');
    return box;
  },
  // Mining at one height of a shaft (the shaft job's box and top/bottom): `y` is the tunnels' feet level,
  // `length` the main tunnels (4-64) and `branch` the side branches (0-16) every 3rd block.
  level: (a) => {
    const box = VALIDATE.shaft(a);
    const y = num(a.y, box.bottom + 1, box.top - 1, 'y');
    return {x1: box.x1, z1: box.z1, x2: box.x2, z2: box.z2, top: box.top, y, length: num(a.length ?? 32, 4, 64, 'length'), branch: num(a.branch ?? 8, 0, 16, 'branch')};
  },
  // A wall around a shaft (the box of the shaft job), one block outside it on the ground.
  rim: (a) => {
    const box = VALIDATE.shaft(a);
    if (!/^[a-z_]{1,48}$/.test(a.item ?? 'cobblestone_wall')) throw new Error('item must be a block name');
    return {x1: box.x1, z1: box.z1, x2: box.x2, z2: box.z2, top: box.top, item: a.item ?? 'cobblestone_wall'};
  },
  // Blueprint {origin, blocks: [{x,y,z,block}], remove?}; protected areas are
  // checked again when the job runs (the hub and workers may differ).
  build: (a) => {
    const plan = buildJob.validate(a);
    const o = plan.origin;
    return {origin: o, blocks: plan.blocks.map((b) => ({x: b.x - o.x, y: b.y - o.y, z: b.z - o.z, block: b.block})), remove: plan.remove};
  },
  // Kill (shear) `count` animals of one kind within `radius` of x,y,z and pick the drops up.
  hunt: (a) => {
    if (!Object.hasOwn(huntJob.ANIMALS, a.animal)) throw new Error(`animal must be one of ${Object.keys(huntJob.ANIMALS).join(', ')}`);
    return {animal: a.animal, count: num(a.count ?? 1, 1, 32, 'count'), ...xyz(a), radius: num(a.radius ?? 24, 4, 64, 'radius')};
  },
  // A bed with its foot at x,y,z and its head one block towards `facing`; sets the spawn point.
  bed: (a) => {
    if (!Object.hasOwn(huntJob.FACING, a.facing)) throw new Error('facing must be north, south, east or west');
    return {...xyz(a), facing: a.facing};
  },
  // The bot's own bed slot in the storage rooms: `slot` 0..13, else x,y,z(,facing), else its place in the crew.
  homebed: (a) => {
    if (a.x !== undefined) {
      const facing = a.facing ?? 'north';
      if (!Object.hasOwn(huntJob.FACING, facing)) throw new Error('facing must be north, south, east or west');
      return {...xyz(a), facing};
    }
    return a.slot === undefined ? {} : {slot: num(a.slot, 0, homebedJob.SLOTS - 1, 'slot')};
  },
  // Plant and chop trees in an area of at most 24 x 24 until stopped; logs go to the supply chest.
  treefarm: treeFarmJob.farmBox,
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
const jobLabel = (j) => `${j.type} ${Object.values(j.args).map((v) => (Array.isArray(v) ? `${v.length} blocks` : v && typeof v === 'object' ? `at ${at(v)}` : v)).join(' ')}`;

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
    bot.once('spawn', () => guardDigs(this, bot)); // bot.dig exists only once the plugins loaded
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
      const mv = safeMovements(bot, this.protectedAreas, this);
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
      // Death messages are only logged, never obeyed.
      const cause = deathCause(this.name, msg);
      if (cause) this.deathCause = {cause, t: Date.now()};
      if (!this.password || authed) return;
      if (/not registered|use \/register/i.test(msg)) bot.chat(`/register ${this.password} ${this.password}`);
      else if (/use \/login|already registered/i.test(msg)) bot.chat(`/login ${this.password}`);
      else if (/logged in successfully|registered successfully|already logged in/i.test(msg)) {
        authed = true;
        this.log(this.name, 'logged in to VeloAuth');
      } else if (/incorrect password/i.test(msg)) {
        // Retrying cannot fix a wrong password, and VeloAuth then blocks the source IP, which every
        // bot of this container shares (2026-10-10: bot6, registered once by a local stage, locked
        // out the lab crew's address). Give up until mcbots restarts.
        this.lastError = 'VeloAuth: wrong password for this bot name - gave up; unregister the name or rename the bot, then restart mcbots';
        this.log(this.name, this.lastError);
        this.shutdown();
      }
    });
    bot.on('entityGone', (e) => this.world.forgetMob(e.id));
    bot.on('death', () => {
      this.dead = true;
      this.lastError = 'died';
      const p = bot.entity?.position;
      const why = this.deathCause && Date.now() - this.deathCause.t < 5000 ? `: ${this.deathCause.cause}` : '';
      this.deathCause = null;
      this.emit('death', `died${p ? ` at ${Math.round(p.x)} ${Math.round(p.y)} ${Math.round(p.z)}` : ''}${why}`);
      const was = this.current && !this.current.cancelled ? this.current : null; // a job the user stopped stays stopped
      this.cancel();
      this.resumeLater(was, 'died');
      // Re-equip from the supply chest first thing after respawning.
      if (this.supplyChest) this.queue.unshift({id: ++this.jobSeq, type: 'rearm', args: this.supplyChest, status: 'queued'});
      // ... and then fetch the loot from the grave AxGraves made, before the interrupted job goes on.
      const spot = gravesJob.graveAfterDeath({pos: p, dim: bot.game?.dimension, chest: this.supplyChest, areas: this.protectedAreas, jobType: this.current?.type, queued: this.queue});
      if (spot) this.queue.splice(1, 0, {id: ++this.jobSeq, type: 'grave', args: spot, status: 'queued'});
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
    this.cancelEpoch = (this.cancelEpoch || 0) + 1; // guardDigs: an equip that began before this must not go on to dig or place
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

  // The floor under the supply chest and the cells next to it (where bots stand) hold the base up: no
  // job removes them (Codex R4-3).
  supportsChest(x, y, z) {
    const c = this.supplyChest;
    return !!c && y === c.y - 1 && Math.abs(x - c.x) <= 1 && Math.abs(z - c.z) <= 1;
  }

  // Cells no dig may remove, whoever asks (digAt, a walk, the pathfinder): the chest's floor and the
  // stair steps of the running shaft (Codex R4-3, R4-4).
  reserved(x, y, z) {
    return this.supportsChest(x, y, z) || !!this.keepCells?.has(`${x},${y},${z}`);
  }

  async pump() {
    if (this.current || !this.queue.length) return;
    if (this.dead) return; // the respawn handler pumps again
    if (!this.online && this.queue[0].resume) return; // resumed jobs wait for the reconnect
    const job = (this.current = this.queue.shift());
    job.status = 'running';
    this.digOnly = ['excavate', 'shaft', 'level'].includes(job.type) ? NATURAL : job.type === 'treefarm' ? treeFarmJob.DIG_ONLY : null; // the walk to the room may dig natural ground only (Codex R3-1)
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
    else if (job.status === 'done') this.emit('done', `finished: ${jobLabel(job)}${job.noop ? ' - already complete' : ''} (${took} s)`);
    else if (job.status === 'stopped') this.emit('stop', `stopped: ${jobLabel(job)}`);
    else this.emit('fail', `failed: ${jobLabel(job)} - ${this.lastError.replace(/^\w+: /, '')}`);
    this.current = null;
    this.digOnly = null;
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
    if (this.combat.busy) return {hunt: `fighting ${this.combat.target?.name || 'a hostile mob'}`, retreat: 'retreating to heal', creeper: 'backing off a creeper'}[this.combat.mode] || 'fighting';
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

// Blocks the pathfinder may place under itself to climb out of a shaft (the default
// list is only dirt, cobblestone, netherrack); the first one a bot carries is used.
const PILLAR_BLOCKS = ['cobblestone', 'cobbled_deepslate', 'dirt', 'netherrack', 'andesite', 'diorite', 'granite', 'tuff', 'stone', 'deepslate'];

function safeMovements(bot, areas, runner = null) {
  const mv = new Movements(bot);
  // Bots speak 26.1 to a 26.2 server through ViaBackwards; sprinting, parkour
  // jumps and diagonal corner-cutting make the server reject the move and pull
  // the bot back (277 corrections in 15 s vs 0 without them, 2026-10-08).
  mv.allowSprinting = false;
  mv.allowParkour = false;
  mv.allow1by1towers = true;
  mv.getMoveDiagonal = () => {};
  mv.scafoldingBlocks = PILLAR_BLOCKS.map((n) => bot.registry.itemsByName[n]?.id).filter((id) => id !== undefined);
  const inside = (blk) => insideAreas(areas, blk.position.x, blk.position.z);
  const veto = (blk) => (inside(blk) ? 100 : 0);
  const held = (blk) => (runner?.reserved?.(blk.position.x, blk.position.y, blk.position.z) ? 100 : 0);
  mv.exclusionAreasBreak = [veto, held, (blk) => (runner?.digOnly && !runner.digOnly.test(blk.name) ? 100 : 0)];
  mv.exclusionAreasPlace = [veto];
  // Every block change counts up, so the path cache never answers from before it.
  if (bot.blockVersion === undefined) {
    bot.blockVersion = 0;
    bot.on('blockUpdate', () => bot.blockVersion++);
    bot.on('chunkColumnLoad', () => bot.blockVersion++);
  }
  return cacheGetBlock(mv, Date.now, () => bot.blockVersion);
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
// give it up to 10 s to move on or die (reports expire), then go anyway. A bot that can fight does not wait.
async function waitSafe(r, job, x, z) {
  if (r.combat?.fit?.()) return; // armed and healthy: combat clears the mob when it comes close
  const dim = normDim(r.bot.game?.dimension);
  for (let i = 0; i < 10 && r.world.hostilesNear(x, z, dim, 8).length; i++) {
    job.progress = 'waiting: hostile near target';
    job.t.doing = 'waiting: a hostile mob is near the target';
    await waitCalm(r, job);
    await sleep(1000);
  }
}

// Long walks (respawn at world spawn -> work site, ~225 blocks) go in legs of
// LEG blocks: one 90 s deadline and one path search cannot cover that far.
const LEG = 48;
async function goNear(r, job, x, y, z, dist, opts = {}) {
  // A goal above (a chest on the surface seen from a mine; 12 levels already failed, bot2 at Y 51 under
  // the chest at Y 63) gets no path in one search, so the
  // bot climbs first, 16 levels per walk, digging its own stairs (bot1, bot2 and bot3 were
  // stranded underground with "No path" on the lab, 2026-10-10).
  // Only under a roof: out in the open a hill is ordinary walking, and climbing first would build pillars.
  const covered = () => {
    const p = r.bot.entity.position.floored();
    for (let dy = 2; dy <= Math.min(20, y - p.y); dy++) if (r.bot.blockAt(p.offset(0, dy, 0))?.boundingBox === 'block') return true;
    return false;
  };
  for (let i = 0; i < 8 && r.bot?.entity && y - r.bot.entity.position.y > 4 && covered(); i++) {
    const p = r.bot.entity.position;
    const up = Math.min(Math.floor(y), Math.floor(p.y) + 16);
    await goLeg(r, job, p.x, up, p.z, 2, {...opts, goal: new goals.GoalY(up), doing: `climbing to Y ${up} towards ${at({x, y, z})}`});
  }
  for (let i = 0; i < 20 && !opts.goal && r.bot?.entity; i++) {
    const p = r.bot.entity.position, d = Math.hypot(x - p.x, z - p.z);
    if (d <= LEG + 16) break;
    const lx = p.x + ((x - p.x) * LEG) / d, lz = p.z + ((z - p.z) * LEG) / d;
    await goLeg(r, job, lx, y, lz, 4, {...opts, goal: new goals.GoalNearXZ(lx, lz, 4), doing: opts.doing || `walking to ${at({x, y, z})}`});
  }
  return goLeg(r, job, x, y, z, dist, opts);
}

async function goLeg(r, job, x, y, z, dist, {brave = false, goal = null, doing = null} = {}) {
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
// Why digging pos would hurt the bot, or null: a fluid would flow in (water
// drowns, lava burns), or the bot stands on it and would fall more than 3.
const FLUID = /^(water|lava|bubble_column)$/;
function unsafeDig(bot, pos) {
  for (const d of [[0, 1, 0], [1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1], [0, -1, 0]]) {
    const n = bot.blockAt(pos.offset(...d))?.name || '';
    if (FLUID.test(n) || bot.blockAt(pos.offset(...d))?.getProperties?.().waterlogged) return `${n || 'waterlogged block'} next to it`;
  }
  const feet = bot.entity.position.floored();
  if (pos.x === feet.x && pos.z === feet.z && pos.y < feet.y) {
    for (let y = pos.y - 1, fall = 1; ; y--, fall++) {
      const b = bot.blockAt(pos.offset(0, y - pos.y, 0));
      if (!b) return 'unknown blocks below';
      if (FLUID.test(b.name)) return `${b.name} below`;
      if (b.boundingBox === 'block') break;
      if (fall > 3) return `a drop of more than 3 below`;
    }
  }
  return null;
}

// Plug water and lava next to a target with rubble (an idea from the Jarvis plugin):
// each fluid neighbour gets a cobblestone (or other junk block) placed against the
// target's face towards it. true when every neighbour got filled.
const FILLER = ['cobblestone', 'cobbled_deepslate', 'dirt', 'netherrack', 'andesite', 'diorite', 'granite', 'tuff', 'stone'];
// A permitted target does not authorise changes to its neighbours: a fluid block
// inside a protected area is never filled (the target is then left unmined), and
// a stop is honoured between the asynchronous steps.
async function sealFluids(r, job, pos) {
  const {bot} = r;
  const target = bot.blockAt(pos);
  if (!target) return false;
  const dirs = [[0, 1, 0], [1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1], [0, -1, 0]];
  // Decide before touching anything: one forbidden neighbour means no sealing at all.
  for (const d of dirs) {
    const n = bot.blockAt(pos.offset(...d));
    if (n && FLUID.test(n.name) && insideAreas(r.protectedAreas, n.position.x, n.position.z)) return false;
  }
  for (const d of dirs) {
    guard(job);
    const n = bot.blockAt(pos.offset(...d));
    if (!n || !FLUID.test(n.name)) continue;
    const fill = bot.inventory.items().find((i) => FILLER.includes(i.name));
    if (!fill) return false;
    await bot.equip(fill, 'hand').catch(() => {});
    guard(job);
    await bot.placeBlock(target, new Vec3(...d)).catch(() => {});
    await sleep(250);
    guard(job);
    if (FLUID.test(bot.blockAt(pos.offset(...d))?.name || '')) return false;
    r.emit('info', `sealed ${n.name} at ${at(n.position)} with ${fill.name}`);
  }
  return true;
}

// One line for the "got no answer" events: what the server's dig timing depends on.
function digWhy(bot, block, pos) {
  const e = bot.entity;
  const effects = Object.values(e.effects || {}).map((f) => bot.registry.effects?.[f.id]?.name || f.id).join(',') || 'none';
  const t = bot.digTime ? bot.digTime(block) : '?';
  return `held ${bot.heldItem?.name || 'nothing'}, onGround ${e.onGround}, inWater ${!!e.isInWater}, effects ${effects}, dist ${e.position.distanceTo(pos.offset(0.5, 0.5, 0.5)).toFixed(1)}, est ${Math.round(t)} ms`;
}

// Every dig goes through bot.dig - digAt's and the pathfinder's own (it digs its stairs and tunnels by
// itself, after an awaited equip that a Stop or a path reset does not cancel: Codex R2-2). So the last
// checks sit here: no dig for a stopped job, inside a protected area, or next to a fluid (digAt seals
// fluids first; the pathfinder never does).
//
// The pathfinder awaits bot.equip before it digs or places scaffolding, and a Stop or a path reset
// does not cancel that await (Codex R2-2, R3-2). So an equip that finishes after a Stop (any equip), or
// after a path reset (the pathfinder's own), fails and marks the next dig as stale; placements are
// checked again right before they happen.
function guardDigs(runner, bot) {
  const dig = bot.dig.bind(bot);
  const equip = bot.equip.bind(bot);
  const placeBlock = bot.placeBlock.bind(bot);
  const lookAt = bot.lookAt?.bind(bot);
  let resets = 0, stale = false, looking = null;
  for (const ev of ['path_reset', 'goal_updated', 'path_stop']) bot.on?.(ev, () => resets++);
  const mark = () => ({stops: runner.cancelEpoch || 0, before: resets, own: bot.pathfinder?.isMining?.() || bot.pathfinder?.isBuilding?.()});
  const moved = (m) => (runner.cancelEpoch || 0) !== m.stops || (m.own && resets !== m.before);
  bot.equip = async (...args) => {
    const m = mark();
    const done = await equip(...args);
    if (moved(m)) {
      stale = true;
      setImmediate(() => { stale = false; }); // the pathfinder's dig follows in the same microtask chain
      throw new Error('Equip aborted: the job was stopped or the path was reset');
    }
    return done;
  };
  // Mineflayer's own dig and placeBlock await lookAt before the packet goes out, so a Stop or a path
  // reset in that await would still start the dig or placement (Codex R2-2, R3-2). The wrappers below
  // leave their context for the lookAt call they make synchronously; lookAt re-checks it when the look is done.
  if (lookAt) {
    bot.lookAt = async (...args) => {
      const c = looking;
      await lookAt(...args);
      const why = c && (moved(c.m) || runner.current?.cancelled ? `${c.verb} aborted: the job was stopped or the path was reset` : c.recheck());
      if (why) throw new Error(why);
    };
  }
  const withLook = (verb, fn, recheck) => (...args) => {
    looking = {verb, m: mark(), recheck: () => recheck(...args)};
    try { return fn(...args); } finally { looking = null; }
  };
  const digRefusal = (block) => {
    const p = block?.position;
    if (runner.current?.cancelled || stale) return 'Digging aborted: the job was stopped';
    if (p && insideAreas(runner.protectedAreas, p.x, p.z)) return 'Digging aborted: protected area';
    if (p && runner.reserved?.(p.x, p.y, p.z)) return 'Digging aborted: that block holds up the base or a shaft step';
    const live = p && bot.blockAt(p);
    if (p && (!live || live.name !== block.name || (block.stateId !== undefined && live.stateId !== block.stateId))) return 'Digging aborted: the block changed';
    // A walk may dig only what the job allows (excavate: natural ground, never its own walls).
    if (runner.digOnly && bot.pathfinder?.isMining?.() && !runner.digOnly.test(block.name)) return `Digging aborted: ${block.name} is not part of the job`;
    const danger = p && unsafeDig(bot, p); // a fluid next to it, or a drop of more than 3 below the bot
    return danger ? `Digging aborted: ${danger}` : null;
  };
  const placeRefusal = (ref, face) => {
    const p = ref?.position && face ? ref.position.plus(face) : null;
    if (runner.current?.cancelled || stale) return 'Placing aborted: the job was stopped';
    if (p && insideAreas(runner.protectedAreas, p.x, p.z)) return 'Placing aborted: protected area';
    return null;
  };
  const nativeDig = withLook('Digging', dig, digRefusal);
  bot.dig = (block, ...rest) => {
    const why = digRefusal(block);
    return why ? Promise.reject(new Error(why)) : nativeDig(block, ...rest);
  };
  const nativePlace = withLook('Placing', placeBlock, placeRefusal);
  bot.placeBlock = (ref, face, ...rest) => {
    const why = placeRefusal(ref, face);
    return why ? Promise.reject(new Error(why)) : nativePlace(ref, face, ...rest);
  };
}

// true only when this bot dug the block; false when it was gone already, changed, or the dig got
// no answer. expect(name) says which block may be dug (default: the one there now); it is checked
// again after every walk and equip, so a block swapped meanwhile (a player's torch) stays.
async function digAt(r, job, pos, expect = null) {
  const {bot} = r;
  let block = bot.blockAt(pos);
  if (!block || block.name.endsWith('air')) return false;
  const first = block.name;
  const want = expect || ((n) => n === first);
  if (!want(block.name)) return false;
  const tools = block.harvestTools ? Object.keys(block.harvestTools).map(Number) : null;
  if (tools && !bot.inventory.items().some((i) => tools.includes(i.type))) {
    // Name the tools: "a pickaxe" sent a stone-pickaxe bot back to gold ore (lab, 2026-10-10).
    const names = tools.map((t) => bot.registry.items[t]?.name).filter(Boolean).sort();
    throw new Error(`needs a tool that can harvest ${block.name}: ${names.join(', ') || 'a pickaxe'}`);
  }
  await goNear(r, job, pos.x, pos.y, pos.z, 4, {goal: new goals.GoalLookAtBlock(pos, bot.world, {reach: 4}), doing: `walking to ${block.name} near ${at(pos)}${tally(job)}`});
  guard(job);
  block = bot.blockAt(pos);
  if (!block || block.name.endsWith('air') || !want(block.name)) return false;
  let danger = unsafeDig(bot, pos);
  if (danger && / next to it$/.test(danger) && (await sealFluids(r, job, pos))) danger = unsafeDig(bot, pos);
  if (danger) throw new Error(`unsafe: ${danger}`);
  job.t.doing = `mining ${block.name}${tally(job)} near ${at(pos)}`;
  // A dig the server never answers hangs forever: give it 25 s, then try another block.
  // A fight ends a dig on purpose (see Combat.fight): wait until it is over and dig again.
  // Resolves true when the server never answered, false when dug, null when the block is gone.
  const attempt = async () => {
    for (let tries = 0; ; tries++) {
      await bot.tool.equipForBlock(block, {}).catch(() => {});
      guard(job); // a Stop during the equip must not dig
      block = bot.blockAt(pos);
      if (!block || block.name.endsWith('air') || !want(block.name)) return null;
      let digTimer;
      try {
        return await Promise.race([bot.dig(block, true).then(() => false), new Promise((res) => (digTimer = setTimeout(() => res(true), 25000)))]);
      } catch (e) {
        if (!/Digging aborted/.test(e.message) || tries >= 3 || Date.now() - (r.combat?.lastFight || 0) > 2000) throw e;
        while (Date.now() - (r.combat?.lastFight || 0) < 1500) {
          guard(job);
          await sleep(250);
        }
      } finally {
        clearTimeout(digTimer);
      }
    }
  };
  let gave = await attempt();
  if (gave === null) return false;
  if (gave) {
    bot.stopDigging();
    const why = digWhy(bot, block, pos);
    block = bot.blockAt(pos);
    if (block && !block.name.endsWith('air')) {
      // Safety net: the server needs 5x-25x longer while the bot is airborne or in water; settle, then dig once more.
      r.emit('info', `digging ${block.name} at ${at(pos)} got no answer, trying once more: ${why}`);
      for (let i = 0; i < 12 && (!bot.entity.onGround || bot.entity.isInWater); i++) {
        guard(job);
        await sleep(250);
      }
      gave = await attempt();
      if (gave === null) return false;
    }
    if (gave) {
      bot.stopDigging();
      r.emit('info', `digging ${block.name} at ${at(pos)} got no answer: skipped (${digWhy(bot, block, pos)})`);
      return false;
    }
  }
  // Walk over the drops near the block (items merge and fly a little).
  await sleep(400);
  const drops = Object.values(bot.entities).filter((e) => e.name === 'item' && e.position.distanceTo(pos) <= 4);
  for (const d of drops) {
    guard(job);
    await goNear(r, job, d.position.x, d.position.y, d.position.z, 0.8, {doing: 'picking up the drops'}).catch(() => {});
  }
  if (/_log$/.test(block.name)) await replant(r, pos, block.name).catch(() => {});
  return true;
}

// Where a log came off dirt or grass, plant the matching sapling again (the
// forest around a shift's chest was felled bare within a day). Not in protected areas.
const SOIL = new Set(['dirt', 'grass_block', 'podzol', 'coarse_dirt', 'rooted_dirt', 'moss_block', 'mud']);
async function replant(r, pos, logName) {
  const {bot} = r;
  const sapling = bot.inventory.items().find((i) => i.name === logName.replace(/_log$/, '_sapling'));
  const below = bot.blockAt(pos.offset(0, -1, 0));
  if (!sapling || !below || !SOIL.has(below.name) || insideAreas(r.protectedAreas, pos.x, pos.z)) return;
  if (!bot.blockAt(pos)?.name.endsWith('air') || bot.entity.position.distanceTo(pos) > 4.5) return;
  await bot.equip(sapling, 'hand');
  await bot.placeBlock(below, new Vec3(0, 1, 0)).catch(() => {});
  await sleep(250);
  if (/_sapling$/.test(bot.blockAt(pos)?.name || '')) r.emit('info', `replanted ${sapling.name} at ${at(pos)}`);
}

// Report the supply chest's contents to the shared picture (the keeper plans from it).
const isSupply = (r, c) => !!r.supplyChest && r.supplyChest.x === c.x && r.supplyChest.y === c.y && r.supplyChest.z === c.z;
function noteStock(r, job, chest) {
  if (!isSupply(r, job.args)) return;
  const items = {};
  for (const it of chest.containerItems()) items[it.name] = (items[it.name] || 0) + it.count;
  r.world?.noteStock(r.name, items, Number.isInteger(chest.inventoryStart) ? chest.inventoryStart - chest.containerItems().length : null); // the container's slots minus the stacks in it
}
// "64 cobblestone, 12 coal, 3 more kinds": what a deposit put in, biggest first (an event is 200 characters).
function depositList(byName) {
  const all = Object.entries(byName).sort((a, b) => b[1] - a[1]);
  return [...all.slice(0, 4).map(([n, c]) => `${c} ${n}`), ...(all.length > 4 ? [`${all.length - 4} more kinds`] : [])].join(', ');
}
// "logs" stands for every kind of log; anything else is an exact item name.
const itemMatcher = (what) => (what === 'logs' ? (n) => n.endsWith('_log') : what === 'wool' ? (n) => n.endsWith('_wool') : what === 'coal' ? (n) => n === 'coal' || n === 'charcoal' : (n) => n === what);

// A chest cannot be opened with a solid block on top. The pathfinder builds with
// dirt (which grows grass)/cobblestone/stone/netherrack, and a chest it bridged over stayed shut
// for the bots (2026-10-08): clear that kind of cover, report anything else.
const SCAFFOLD = /^(dirt|grass_block|cobblestone|stone|netherrack)$/; // dirt turns into grass in the light
// The left half's partner lies clockwise of `facing`, the right half's counter-clockwise (read off
// double chests on the live server, 2026-10-10: north-facing left at x, right at x+1).
const PARTNER_STEP = {north: [1, 0], south: [-1, 0], east: [0, 1], west: [0, -1]};
function partnerOf(bot, block) {
  const {type, facing} = block.getProperties?.() || {};
  const step = PARTNER_STEP[facing];
  if (!step || (type !== 'left' && type !== 'right')) return null;
  const s = type === 'left' ? 1 : -1;
  const b = bot.blockAt(block.position.offset(s * step[0], 0, s * step[1]));
  const q = b?.name === block.name && b.getProperties?.();
  return q && q.facing === facing && q.type === (type === 'left' ? 'right' : 'left') ? b : null;
}
async function openChest(r, job, block) {
  const {bot} = r;
  // A double chest stays shut when either half is covered. Its partner is the one block that the
  // half's left/right and facing point to (a single chest or another pair beside it is not one).
  const partner = partnerOf(bot, block);
  for (const half of /chest/.test(block.name) ? [block, partner].filter(Boolean) : []) {
    guard(job); // a Stop between the covers digs nothing more
    const p = half.position.offset(0, 1, 0);
    const above = bot.blockAt(p);
    if (!above || above.boundingBox !== 'block') continue;
    if (!SCAFFOLD.test(above.name) || insideAreas(r.protectedAreas, p.x, p.z)) throw new Error(`${block.name} at ${at(half.position)} is covered by ${above.name}`);
    job.t.doing = `clearing ${above.name} off the chest`;
    r.emit('info', `chest at ${at(half.position)} was covered by ${above.name}: digging it away`);
    const cover = above.name;
    if (!(await digAt(r, job, p, (name) => name === cover))) throw new Error(`could not clear ${cover} off the chest at ${at(half.position)}`);
  }
  guard(job);
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
// A shaft's stair step must hold: gravel or sand would fall once the layer below is dug, and air,
// water or lava is no step. Replace it with cobblestone while the block under it still stands.
const LOOSE = /^(air|cave_air|gravel|sand|red_sand|water|lava)$/;
async function fixStep(r, job, x, y, z) {
  const Vec3 = require('vec3').Vec3;
  const b = r.bot.blockAt(new Vec3(x, y, z));
  if (!b || !LOOSE.test(b.name)) return;
  try {
    if (/sand|gravel/.test(b.name)) await digAt(r, job, b.position, (n) => n === b.name);
    await JOBS.place(r, child(job, {type: 'place', args: {item: 'cobblestone', x, y, z}}));
  } catch (e) {
    guard(job);
    r.emit('info', `stair step at ${x} ${y} ${z} not fixed: ${e.message.slice(0, 80)}`);
  }
}

// A box that would dig the ground under the supply chest fails before it digs anything.
function refuseSupport(r, {x1, z1, x2, z2, y1, y2}) {
  for (let x = x1; x <= x2; x++) for (let z = z1; z <= z2; z++) for (let y = y1; y <= y2; y++) {
    if (r.supportsChest?.(x, y, z)) throw new Error(`${x} ${y} ${z} holds up the supply chest`);
  }
}

// The cells of a layer in growing squares from one of its corners (0-3), so bots that start at
// different corners dig apart until they meet; corner -1 (a room) goes row by row.
function layerOrder(x1, z1, x2, z2, corner) {
  const cx = corner & 1 ? x2 : x1, cz = corner & 2 ? z2 : z1;
  const cells = [];
  for (let x = x1; x <= x2; x++) for (let z = z1; z <= z2; z++) cells.push([x, z]);
  const d = ([x, z]) => Math.max(Math.abs(x - cx), Math.abs(z - cz)) * 1000 + Math.abs(x - cx) + Math.abs(z - cz);
  return corner < 0 ? cells : cells.sort((a, b) => d(a) - d(b));
}

// The edge cells of a box in walking order; layer k of a shaft keeps cell k (mod the ring) as its step.
function stairRing(x1, z1, x2, z2) {
  const ring = [];
  for (let x = x1; x < x2; x++) ring.push({x, z: z1});
  for (let z = z1; z < z2; z++) ring.push({x: x2, z});
  for (let x = x2; x > x1; x--) ring.push({x, z: z2});
  for (let z = z2; z > z1; z--) ring.push({x: x1, z});
  return ring;
}

const child = (job, extra = {}) => Object.assign(Object.create(job), {collected: 0, progress: '', ...extra});

// Keep a long job going without the owner: replace a broken pickaxe, fetch food
// when hungry and carrying none, empty a full inventory. Called before every
// block of collect(); the helpers below may call collect themselves (logs for
// a new pickaxe), hence the guard.
// Torches: where the block light at the bot's feet is below TORCH_BELOW, put a
// torch there (it shines 14, so they land about every 7 blocks and nothing in
// between gets back to light 0, where monsters spawn). Out of torches: craft 4
// when there is coal or charcoal (sticks come from planks).
const TORCH_BELOW = 7;
// A shaft gets a wall torch every 8 blocks of depth; its rim wall one every 6 blocks.
const shaftTorchDue = (top, y) => top - y > 0 && (top - y) % 8 === 0;
const rimTorchDue = (placed) => placed > 0 && placed % 6 === 0;
// `wall`: a shaft or rim torch - placed even where the light is still fine (it lights the way down), on
// a wall only (a floor torch would be dug away with the next layer), and never blocks the dig.
async function lightUp(r, job, ids = [], {wall = false} = {}) {
  const {bot} = r;
  if (!(r.getSettings?.().torches ?? true) || r.combat.busy || bot.currentWindow) return;
  if (Date.now() - (r.torchAt || 0) < 3000) return;
  const feet = bot.entity.position.floored();
  const here = bot.blockAt(feet), below = bot.blockAt(feet.offset(0, -1, 0));
  if (!here || here.name !== 'air' && here.name !== 'cave_air' || !below || below.boundingBox !== 'block' || (!wall && (here.light ?? 15) >= TORCH_BELOW)) return;
  if (insideAreas(r.protectedAreas, feet.x, feet.z)) return;
  // The client's light data lags behind a fresh torch: also count torches close by.
  const torchIds = ['torch', 'wall_torch'].map((n) => bot.registry.blocksByName[n]?.id).filter((id) => id !== undefined);
  if (bot.findBlock({matching: torchIds, maxDistance: 5})) return;
  r.torchAt = Date.now();
  if (!bot.inventory.items().some((i) => i.name === 'torch')) {
    if (!bot.inventory.items().some((i) => i.name === 'coal' || i.name === 'charcoal') || Date.now() - (r.torchCraftAt || 0) < 300000) return;
    r.torchCraftAt = Date.now(); // one try per 5 min, so a missing recipe input cannot stall the job
    await crafting.ensureItem(r, child(job), 'torch', 4);
    guard(job);
  }
  const torch = bot.inventory.items().find((i) => i.name === 'torch');
  if (!torch) return;
  // On a wall at head height when there is one (digging down or along a
  // tunnel leaves it alone), else on the floor at the bot's feet.
  const head = feet.offset(0, 1, 0);
  let ref = null, face = null, spot = feet;
  // Never on a block of the job's target type: digging it next drops the torch.
  if (['air', 'cave_air'].includes(bot.blockAt(head)?.name)) {
    for (const d of [new Vec3(1, 0, 0), new Vec3(-1, 0, 0), new Vec3(0, 0, 1), new Vec3(0, 0, -1)]) {
      const w = bot.blockAt(head.plus(d));
      if (w && w.boundingBox === 'block' && !ids.includes(w.type) && !insideAreas(r.protectedAreas, w.position.x, w.position.z)) { ref = w; face = d.scaled(-1); spot = head; break; }
    }
  }
  if (!ref) {
    if (wall || ids.includes(below.type)) return; // the floor itself is a target: it would fall off
    ref = below; face = new Vec3(0, 1, 0);
  }
  const held = bot.heldItem;
  await bot.equip(torch, 'hand');
  await bot.placeBlock(ref, face).catch(() => {}); // placeBlock may time out waiting for the update; check the world instead
  await sleep(250);
  if (!/torch$/.test(bot.blockAt(spot)?.name || '')) throw new Error(`torch at ${at(spot)} did not stay`);
  r.emit('info', `placed a torch at ${at(spot)} (light was ${here.light})`);
  if (held && held.name !== 'torch') await bot.equip(held, 'hand').catch(() => {});
}

// Stone and dirt that ore and log jobs dig through (an idea from the Jarvis plugin):
// keep one stack of cobblestone for torches, crafting and patching, throw the rest
// away so the bot goes to the chest for ore, not for rubble.
const JUNK = new Set(['cobblestone', 'cobbled_deepslate', 'dirt', 'gravel', 'granite', 'diorite', 'andesite', 'tuff', 'netherrack', 'calcite', 'dripstone_block', 'rooted_dirt', 'leaf_litter']);
const jobWants = (job, item) => [job.args?.block, job.args?.item].some((n) => n && (n === item || (item === 'cobblestone' && n === 'stone')));
async function tossJunk(r, job) {
  const {bot} = r;
  // one stack of pillar material is kept: cobblestone first, else the first scaffold block carried
  const held = bot.inventory.items().map((i) => i.name);
  const keep = PILLAR_BLOCKS.find((n) => held.includes(n));
  let kept = false;
  for (const it of bot.inventory.items()) {
    if (!JUNK.has(it.name) || jobWants(job, it.name)) continue;
    if (it.name === keep && !kept) { kept = true; continue; }
    await bot.tossStack(it).catch(() => {});
    guard(job);
  }
}

// Armour in the inventory goes on at once; no walk to a chest needed.
async function wearArmour(r) {
  const {bot} = r;
  for (const [re, slot] of [[/_helmet$/, 'head'], [/_chestplate$/, 'torso'], [/_leggings$/, 'legs'], [/_boots$/, 'feet']]) {
    if (bot.inventory.slots[bot.getEquipmentDestSlot(slot)]) continue;
    const it = bot.inventory.items().find((i) => re.test(i.name));
    if (it) await bot.equip(it, slot).catch(() => {});
  }
}

// Chopping by hand is slow: make a stone (else wooden) axe from what the bot
// carries, at most one try per 5 min.
// Make a stone (else wooden) axe or shovel once the job digs blocks that tool is for; equipForBlock
// then picks it. One try per kind every 5 minutes, failures only cost the slower dig.
async function getTool(r, job, kind) {
  const {bot} = r;
  const tried = (r.toolTriedAt ||= {});
  if (bot.inventory.items().some((i) => i.name.endsWith(`_${kind}`)) || Date.now() - (tried[kind] || 0) < 300000) return;
  tried[kind] = Date.now();
  for (const item of [`stone_${kind}`, `wooden_${kind}`]) {
    try {
      await crafting.ensureItem(r, child(job), item, 1);
      r.emit('info', `made a ${item} for digging`);
      return;
    } catch (e) {
      guard(job);
    }
  }
}
const toolFor = (bot, id) => {
  const b = bot.registry.blocks[id];
  if (/_(log|stem)$/.test(b?.name || '') || /mineable\/axe/.test(b?.material || '')) return 'axe';
  return /mineable\/shovel/.test(b?.material || '') ? 'shovel' : null;
};

async function upkeep(r, job, ids) {
  if (job.t.upkeep) return;
  job.t.upkeep = true;
  const shown = {done: job.t.done, total: job.t.total};
  try {
    const {bot} = r;
    await lightUp(r, job, ids).catch((e) => { guard(job); r.emit('info', `no torch placed: ${e.message.slice(0, 80)}`); });
    await wearArmour(r);
    for (const kind of new Set(ids.map((id) => toolFor(bot, id)).filter(Boolean))) await getTool(r, job, kind);
    const need = ids.find((id) => !canHarvest(bot, id));
    if (need !== undefined) await replacePickaxe(r, job);
    if (bot.food < FOOD_BELOW && r.supplyChest && !bot.inventory.items().some((i) => edible(bot, i)) && Date.now() - (r.foodTriedAt || 0) > FOOD_RETRY_MS) {
      r.foodTriedAt = Date.now();
      r.emit('info', `hungry (food ${bot.food}) and no food: fetching some from the supply chest`);
      await JOBS.rearm(r, child(job, {type: 'rearm', args: r.supplyChest})).catch((e) => {
        guard(job);
        r.emit('info', `no food fetched: ${e.message}`); // keep working; the retry timer asks again later
      });
      // The chest had none: hunt for it. Same 10-minute timer, so at most one hunt per bot per 10 minutes.
      if (!bot.inventory.items().some((i) => edible(bot, i))) await huntFood(r, job);
    }
    if (bot.inventory.emptySlotCount() < 4 && !jobWants(job, 'cobblestone')) await tossJunk(r, job);
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

// Hungry and the supply chest has no food: hunt two cows or pigs (chickens too when there is fuel to cook
// them) within 24 blocks, then cook the meat if there is fuel, else it is eaten raw (beef, porkchop).
async function huntFood(r, job) {
  const {bot} = r;
  const p = bot.entity.position.floored();
  const fuel = (meat, n) => !!craftingLib.fuelFor(bot, meat, n);
  const animal = huntJob.foodAnimal(Object.values(bot.entities), {x: p.x, y: p.y, z: p.z, radius: 24, areas: r.protectedAreas, done: new Set(), me: bot.entity.position}, fuel('beef', 2));
  if (!animal) return r.emit('info', 'hungry: no cow, pig or cookable chicken within 24 blocks to hunt');
  r.emit('info', `hungry: hunting ${animal}s for food`);
  try {
    await hunt(r, child(job, {type: 'hunt', args: {animal, count: 2, x: p.x, y: p.y, z: p.z, radius: 24}}));
  } catch (e) {
    guard(job);
    r.emit('info', `food hunt: ${e.message.slice(0, 100)}`); // fewer than two found is still food
  }
  const meat = huntJob.MEAT[animal], n = Math.min(craftingLib.count(bot, meat), 6);
  if (n && fuel(meat, n)) await crafting.smelt(r, child(job, {type: 'smelt'}), meat, n).catch((e) => { guard(job); r.emit('info', `could not cook the ${meat}: ${e.message.slice(0, 80)}`); });
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

// Dig down (or climb) into the ore's Y band, 16 levels per walk so every leg
// fits the walk deadline. The pathfinder digs the stairs and never into fluids.
async function toBand(r, job, band, what) {
  const {bot} = r;
  const target = Math.round((band[0] + band[1]) / 2);
  for (let leg = 0; leg < 12 && outside(band, bot.entity.position.y) > 2; leg++) {
    const y = bot.entity.position.y > target ? Math.max(target, Math.floor(bot.entity.position.y) - 16) : Math.min(target, Math.floor(bot.entity.position.y) + 16);
    const p = bot.entity.position;
    await goNear(r, job, p.x, y, p.z, 2, {goal: new goals.GoalY(y), doing: `digging down to Y ${target} for ${what} (now Y ${Math.floor(p.y)})`});
  }
}

// Tunnel EXPLORE_STEP blocks sideways at the same height, a new direction each time.
async function explore(r, job, what, n, leash = LEASH) {
  const {bot} = r;
  const dirs = [[1, 0], [0, 1], [-1, 0], [0, -1]];
  const p = bot.entity.position;
  // The first direction (bots spread out) whose target is allowed: next to spawn protection every
  // try used to end at once and a chop failed in a second (bot18, 2026-10-10).
  const ok = ([dx, dz]) => {
    const x = Math.floor(p.x) + dx * EXPLORE_STEP, z = Math.floor(p.z) + dz * EXPLORE_STEP;
    return !insideAreas(r.protectedAreas, x, z) && !(job.type === 'shift' && Math.hypot(x - job.args.x, z - job.args.z) > leash); // shifts stay near the chest
  };
  const start = n + (r.name.charCodeAt(r.name.length - 1) || 0);
  const dir = [0, 1, 2, 3].map((i) => dirs[(start + i) % 4]).find(ok);
  if (!dir) return;
  const [dx, dz] = dir;
  const x = Math.floor(p.x) + dx * EXPLORE_STEP, z = Math.floor(p.z) + dz * EXPLORE_STEP;
  r.emit('info', `no ${what} left in reach: tunnelling ${EXPLORE_STEP} blocks to ${x} ${Math.floor(p.y)} ${z}`);
  await goNear(r, job, x, Math.floor(p.y), z, 3, {doing: `tunnelling to new ${what} ground near ${x} ${Math.floor(p.y)} ${z}`}).catch((e) => {
    guard(job);
    r.emit('info', `tunnel stopped: ${e.message.slice(0, 80)}`);
  });
}

// Where each ore is densest in 26.2 (the 1.18 distribution): bots mine inside
// these Y bands, digging down (or up) to them first.
const ORE_BAND = {coal_ore: [40, 130], iron_ore: [0, 40], copper_ore: [30, 70], gold_ore: [-30, -5], lapis_ore: [-15, 15], redstone_ore: [-60, -45], diamond_ore: [-60, -45], emerald_ore: [100, 250]};
const outside = (band, y) => (band ? Math.max(0, band[0] - y, y - band[1]) : 0);
const EXPLORE_STEP = 32;
const LEASH = 64; // blocks a shift may work from its chest (128 for logs: forests thin out)
const WOOD_LEASH = 128;
const EXPLORE_MAX = 6;

// Torches need wood (2 planks, or a log). A deep miner carries coal but never chops, so it runs dry.
const needsWood = (items) => {
  const sum = (re) => items.filter((i) => re.test(i.name)).reduce((n, i) => n + i.count, 0);
  return sum(/_log$/) < 2 && sum(/_planks$/) < 8;
};
// Take 4 logs from the supply chest when short; a chest without logs is an info event, not a failure.
// `force` skips the retry timer (rearm is already at the chest).
async function fetchWood(r, job, force) {
  if (!r.supplyChest || !needsWood(r.bot.inventory.items())) return;
  if (!force && Date.now() - (r.woodTriedAt || 0) < FOOD_RETRY_MS) return;
  if (!force) r.woodTriedAt = Date.now();
  try {
    await JOBS.withdraw(r, child(job, {type: 'withdraw', args: {item: 'logs', count: 4, ...r.supplyChest}}));
    r.emit('info', 'took logs from the supply chest for torches');
  } catch (e) {
    guard(job);
    r.emit('info', `no logs fetched for torches: ${e.message.slice(0, 80)}`);
  }
}

async function collect(r, job, matching, count, what) {
  const {bot} = r;
  // An ore below Y 0 is the deepslate variant: mining iron_ore also takes deepslate_iron_ore.
  const names = matching.flatMap((n) => (/^[a-z]+_ore$/.test(n) ? [n, `deepslate_${n}`] : [n]));
  const ids = names.map((n) => bot.registry.blocksByName[n]?.id).filter((i) => i !== undefined);
  if (!ids.length) throw new Error(`unknown block: ${what}`);
  const ore = names.some((n) => n.endsWith('_ore'));
  const wood = names.every((n) => /_(log|stem)$/.test(n));
  const leash = wood ? WOOD_LEASH : LEASH;
  const range = ore || wood ? 128 : 64; // the bot sees every block within its view distance (no anti-xray)
  const band = bot.game?.dimension?.endsWith('overworld') !== false ? ORE_BAND[matching.find((n) => ORE_BAND[n])] : null;
  let explored = 0, descents = 0;
  if (names.some((n) => ORE_BAND[n.replace(/^deepslate_/, '')])) await fetchWood(r, job);
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
    // Ores: nearest first, so a vein is finished before the next one. Stone and
    // logs: digging down costs a staircase and leads into dark caves, so a block
    // below the bot counts 2 extra per level.
    const me = bot.entity.position;
    const cost = (p) => p.distanceTo(me) + (ore ? 4 * outside(band, p.y) : 2 * Math.max(0, Math.floor(me.y) - p.y));
    let found = bot.findBlocks({matching: ids, maxDistance: range, count: 64}).sort((a, b) => cost(a) - cost(b));
    // Ore job, nothing inside the band near enough, and the bot is not in the band: go there first.
    if (band && descents < 2 && outside(band, me.y) > 4 && !found.some((p) => !outside(band, p.y) && p.distanceTo(me) <= 48)) {
      descents++; // twice at most, then mine what is in reach
      await toBand(r, job, band, what);
      continue;
    }
    // A shift works around its own chest: never more than LEASH blocks away from it.
    const anchor = job.type === 'shift' ? job.args : null;
    if (anchor && Math.hypot(me.x - anchor.x, me.z - anchor.z) > leash - 8) { // e.g. respawned at world spawn
      await goNear(r, job, anchor.x, anchor.y, anchor.z, 3, {doing: `walking back to the shift's chest ${at(anchor)}`});
      continue;
    }
    if (anchor) found = found.filter((p) => Math.hypot(p.x - anchor.x, p.z - anchor.z) <= leash);
    for (const p of found) {
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
    if (!pos) {
      // Mined out around here: tunnel on at the same height and look again.
      if ((ore || wood) && explored < EXPLORE_MAX) {
        explored++;
        await explore(r, job, what, explored, leash);
        continue;
      }
      throw new Error(`no free ${what} within ${range} blocks (collected ${got}/${count}${explored ? `, searched ${explored} more spots` : ''})`);
    }
    try {
      await waitSafe(r, job, pos.x, pos.z);
      if (!(await digAt(r, job, pos))) {
        r.skip.set(key, Date.now() + 300000); // not dug by us: do not count it, try another block
        continue;
      }
      misses = 0;
    } catch (e) {
      guard(job);
      // One block nobody can walk to (or whose dig was aborted by a block update, e.g. falling
      // gravel) must not end a long job: skip it for 5 min, give up after 5 in a row.
      if (/^unsafe: /.test(e.message)) { // never counts towards giving up: there is other ore
        r.skip.set(key, Date.now() + 1800000);
        r.emit('info', `left a ${what} block at ${at(pos)}: ${e.message}`);
        continue;
      }
      if (!/could not reach|Digging aborted/.test(e.message) || ++misses > 5) throw e;
      for (const [k, until] of r.skip) if (until < Date.now()) r.skip.delete(k);
      r.skip.set(key, Date.now() + 300000);
      // The rest of that vein sits behind the same water or wall: skip it too,
      // or each of its blocks costs another full walk timeout.
      if (/could not reach/.test(e.message)) for (const q of found) if (q.distanceTo(pos) <= 4) r.skip.set(keyOf(q), Date.now() + 300000);
      r.emit('info', `skipped a ${what} block (${e.message.slice(0, 40)}) at ${at(pos)}`);
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

const craftingLib = require('./crafting');
const crafting = craftingLib.makeCrafting({goNear, guard});
// A build takes what it lacks from the supply chest (the withdraw job, with the chest's position).
const buildWithdraw = (r, job, item, count) => JOBS.withdraw(r, child(job, {type: 'withdraw', args: {item, count, ...r.supplyChest}}));
// ... and gathers the rest itself (mine, chop, smelt jobs as children of the build).
const buildRunJob = (r, job, type, args) => JOBS[type](r, child(job, {type, args}));
const buildContext = (r) => {
  const {bot} = r;
  const held = (re) => bot.inventory.items().filter((i) => re.test(i.name)).reduce((n, i) => n + i.count, 0);
  return {
    furnace: !!craftingLib.nearBlock(bot, 'furnace'),
    wood: held(/_log$/) >= 1 || held(/_planks$/) >= 4 || !!craftingLib.nearBlock(bot, 'crafting_table'),
    hasFuel: (n) => !!craftingLib.fuelFor(bot, 'cobblestone', n),
  };
};
const build = buildJob.makeBuild({goNear, guard, sleep, goals, digAt, withdraw: buildWithdraw, runJob: buildRunJob, gatherContext: buildContext});

const {grave} = gravesJob.makeGraves({goNear, guard, sleep, deposit: (r, job) => JOBS.deposit(r, child(job, {type: 'deposit', args: r.supplyChest}))});
const {hunt, bed} = huntJob.makeHunt({goNear, guard, sleep, goals, waitCalm, crafting, at});

const {homebed} = homebedJob.makeHomebed({goNear, guard, sleep, goals, crafting, run: buildRunJob, at, digAt, NATURAL});

const tidy = tidyJob.makeTidy({goNear, guard, sleep, waitCalm, at, deposit: (r, job) => JOBS.deposit(r, child(job, {type: 'deposit', args: r.supplyChest}))});

const {level} = levelJob.makeLevel({goNear, waitCalm, guard, sleep, digAt, upkeep, NATURAL, stairRing, at});

const {treefarm} = treeFarmJob.makeTreeFarm({
  goNear, guard, sleep, digAt, waitCalm, at,
  deposit: (r, job) => JOBS.deposit(r, child(job, {type: 'deposit', args: {...r.supplyChest, only: 'logs'}})),
  withdraw: (r, job, item, count) => JOBS.withdraw(r, child(job, {type: 'withdraw', args: {item, count, ...r.supplyChest}})),
});

const JOBS = {
  tidy,
  grave,
  treefarm,
  homebed,
  level,
  hunt,
  bed,
  goto: (r, job) => goNear(r, job, job.args.x, job.args.y, job.args.z, 1),

  // Walks to the player (live entity when tracked, else the BlueMap position)
  // and is done within 3 blocks.
  come: (r, job) => chase(r, job, false),

  follow: (r, job) => chase(r, job, true),

  // Runs until stopped: hunts hostiles within the radius (combat does the
  // hitting once it is close), else walks back to the post or the player.
  guard: async (r, job) => {
    const {bot} = r;
    const {radius, player: name} = job.args;
    let goal = null; // what the pathfinder chases: a mob entity, or 'post'
    let epoch = r.combat.epoch;
    try {
      for (;;) {
        guard(job);
        if (!r.online) throw new Error('bot went offline');
        await waitCalm(r, job);
        if (epoch !== r.combat.epoch) { epoch = r.combat.epoch; goal = null; } // combat replaced our goal
        const me = bot.entity.position;
        let post = job.args;
        if (name) {
          const e = bot.players[name]?.entity;
          const p = e ? e.position : r.world.player(name);
          if (!p) throw new Error(`${name} is not visible and not on the map (offline, or BlueMap unavailable)`);
          post = {x: p.x, y: p.y, z: p.z};
        }
        const foe = Object.values(bot.entities)
          .filter((e) => e !== bot.entity && e.position && shouldFight(e) && Math.hypot(e.position.x - post.x, e.position.z - post.z) <= radius && Math.abs(e.position.y - post.y) < 16)
          .sort((a, b) => a.position.distanceTo(me) - b.position.distanceTo(me))[0];
        if (foe) {
          job.progress = `fighting ${foe.name}`;
          job.t.doing = `fighting ${foe.name} ${Math.round(foe.position.distanceTo(me))} blocks away`;
          if (goal !== foe) { bot.pathfinder.setGoal(new goals.GoalFollow(foe, 2), true); goal = foe; }
        } else if (Math.hypot(me.x - post.x, me.z - post.z) > Math.max(3, radius / 3)) {
          job.progress = 'returning to post';
          job.t.doing = name ? `staying with ${name}` : `walking back to the post ${at(post)}`;
          if (goal !== 'post' || !bot.pathfinder.isMoving()) { bot.pathfinder.setGoal(new goals.GoalNear(post.x, post.y, post.z, 2)); goal = 'post'; }
        } else {
          job.progress = 'all quiet';
          job.t.doing = `guarding ${name || at(post)}, radius ${radius}: all quiet`;
          if (goal) { bot.pathfinder.setGoal(null); goal = null; }
        }
        await sleep(500);
      }
    } finally {
      if (goal) bot.pathfinder.setGoal(null);
    }
  },

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
      const byName = {};
      const only = job.args.only && itemMatcher(job.args.only);
      for (const it of bot.inventory.items()) {
        guard(job);
        if (only ? !only(it.name) : TOOL_RE.test(it.name) || KEEP_RE.test(it.name) || bot.registry.foodsByName[it.name]) continue;
        try {
          await chest.deposit(it.type, it.metadata, it.count);
          moved += it.count;
          byName[it.name] = (byName[it.name] || 0) + it.count;
          job.progress = `${moved} items`;
        } catch (e) {
          throw new Error(`chest full or deposit failed after ${moved} items: ${e.message}`);
        }
      }
      if (moved) r.emit('deposit', `deposited ${depositList(byName)} at ${place(r, job.args)}`);
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
      // One failed withdrawal (inventory full, another bot took the last one) never ends the visit:
      // the rest of the gear, the food and the equip step below still happen. A Stop does end it.
      const take = async (what, item, n) => {
        try {
          await box.withdraw(item.type, item.metadata, n);
        } catch (e) {
          guard(job);
          r.emit('info', `re-arm: could not take ${what}: ${e.message.slice(0, 80)}`);
        }
        guard(job); // a Stop between withdrawals takes nothing more (the chest still closes)
      };
      try {
        for (const re of WANT) {
          const have = best(mine(), re);
          const offer = best(box.containerItems(), re);
          if (offer && (!have || tier(offer.name) > tier(have.name))) await take(offer.name, offer, 1);
        }
        const food = box.containerItems().filter((i) => isFood(i.name)).sort((a, b) => (b.name === 'golden_carrot') - (a.name === 'golden_carrot'))[0];
        if (food && foodCount() < 32) await take(food.name, food, Math.min(32 - foodCount(), food.count));
        // A spare pickaxe and 2 logs (table + sticks for a stone pickaxe): a pickaxe that breaks deep
        // underground otherwise strands the bot - no wood there, and the way up by hand is "No path"
        // (bot2 and bot3, 2026-10-10). Last, so they never take a slot the food needs.
        const count = (re) => bot.inventory.items().filter((i) => re.test(i.name)).reduce((n, i) => n + i.count, 0);
        const spare = best(box.containerItems(), /_pickaxe$/);
        if (spare && count(/_pickaxe$/) < 2) await take(spare.name, spare, 1);
        const log = box.containerItems().find((i) => /_log$/.test(i.name));
        if (log && count(/_log$/) < 2) await take(log.name, log, Math.min(2 - count(/_log$/), log.count));
      } finally {
        box.close();
      }
    }
    // Logs would go back into the chest with the next deposit; planks are kept (KEEP_RE). Only the
    // two spare logs: a woodcutter's load stays logs.
    const carried = bot.inventory.items().filter((i) => /_log$/.test(i.name));
    const noPlanks = [];
    for (const log of carried.reduce((n, i) => n + i.count, 0) <= 2 ? carried : []) {
      const planks = bot.registry.itemsByName[log.name.replace(/_log$/, '_planks')];
      const recipe = planks && bot.recipesFor(planks.id, null, 1, null)[0];
      guard(job); // no craft after a Stop (Codex R2-3)
      const have = () => bot.inventory.items().filter((i) => i.type === planks?.id).reduce((n, i) => n + i.count, 0);
      const before = recipe ? have() : 0;
      let why = recipe ? '' : 'no recipe';
      if (recipe) await craftingLib.holding(r, () => bot.craft(recipe, log.count, null)).catch((e) => { why = e.message.slice(0, 60); });
      guard(job);
      if (recipe && !why && have() <= before) why = 'nothing crafted';
      if (why) noPlanks.push(`${log.name}: ${why}`);
    }
    guard(job);
    if (noPlanks.length) r.emit('info', `re-arm: no planks (${noPlanks.join('; ')})`);
    // A failed equip is tolerated; a Stop is not: none starts after it, whichever equip it lands in (Codex R2-3).
    const wear = async (it, slot) => {
      guard(job);
      await bot.equip(it, slot).catch(() => {});
      guard(job);
    };
    for (const [re, slot] of [[/_helmet$/, 'head'], [/_chestplate$/, 'torso'], [/_leggings$/, 'legs'], [/_boots$/, 'feet']]) {
      const it = best(bot.inventory.items(), re);
      if (it) await wear(it, slot);
    }
    const totem = bot.inventory.items().find((i) => i.name === 'totem_of_undying');
    if (totem) await wear(totem, 'off-hand');
    const sword = best(bot.inventory.items(), /_sword$/);
    if (sword) await wear(sword, 'hand');
    const worn = ['head', 'torso', 'legs', 'feet'].filter((s) => bot.inventory.slots[bot.getEquipmentDestSlot(s)]).length;
    const off = bot.inventory.slots[bot.getEquipmentDestSlot('off-hand')]?.name;
    await fetchWood(r, job, true);
    job.progress = `armour ${worn}/4, ${sword?.name || 'no sword'}, off-hand ${off || 'empty'}, food ${foodCount()}${noPlanks.length ? ', no planks' : ''}`;
  },

  build: (r, job) => build(r, job),
  // Dig out a box top-down (an underground room). Only natural ground goes: anything a player or a
  // bot placed (cobblestone walls, chests, torches, planks ...) stays, and so do protected areas.
  async excavate(r, job) {
    const {bot} = r;
    const {x1, y1, z1, x2, y2, z2} = job.args;
    for (const [x, z] of [[x1, z1], [x1, z2], [x2, z1], [x2, z2]]) if (insideAreas(r.protectedAreas, x, z)) throw new Error(`${x} ${z} is inside a protected area`);
    refuseSupport(r, {x1, z1, x2, z2, y1, y2});
    const Vec3 = require('vec3').Vec3;
    const dim = normDim(bot.game?.dimension);
    const total = (x2 - x1 + 1) * (y2 - y1 + 1) * (z2 - z1 + 1);
    let left = 0, dug = 0;
    job.t.total = total;
    for (let y = y2; y >= y1; y--) {
      for (const [x, z] of layerOrder(x1, z1, x2, z2, job.args.corner ?? -1)) {
        {
          guard(job);
          if (job.args.keep && x === job.args.keep.x && z === job.args.keep.z) continue; // a shaft's stair step
          const pos = new Vec3(x, y, z);
          const b = bot.blockAt(pos);
          if (!b) { left++; continue; } // not loaded is not dug (a shaft resumed right after login "finished" in 0 s)
          if (b.boundingBox === 'empty' || !NATURAL.test(b.name)) continue;
          const k = `${dim}:${x},${y},${z}`;
          if (r.world && !(await r.world.claim(r.name, k))) {
            left++;
            continue;
          }
          try {
            await upkeep(r, job, [b.type]);
            job.t.doing = `digging out the room at ${x1} ${y1} ${z1}`;
            if (await digAt(r, job, pos, (n) => n === b.name)) dug++;
            else left++;
          } finally {
            r.world?.release(r.name, k);
          }
          const done = total - left;
          job.progress = `room ${x1} ${y1} ${z1}: layer y ${y}`;
          job.t.done = done;
        }
      }
    }
    if (left) throw new Error(`${left} blocks of the room were not dug (held by another bot, unloaded, unreachable or unsafe)`);
    job.noop = !dug; // nothing natural left to dig: the event says "already complete"
  },

  // Dig a shaft one layer at a time (the excavate loop on a 1-high box), leaving one block per layer
  // along the walls so the steps spiral down. Blocks next to lava/water, held by another bot or
  // unreachable are left; a layer is retried twice (another bot may still be digging it).
  async shaft(r, job) {
    const {x1, z1, x2, z2, top, bottom} = job.args;
    const ring = stairRing(x1, z1, x2, z2);
    // Walk over first: far away (after a login or a death) the shaft's chunks are not loaded yet.
    await goNear(r, job, (x1 + x2) >> 1, Math.floor(r.bot.entity.position.y), z1 - 2, 4, {doing: 'walking to the shaft'});
    // ponytail: the start corner comes from the name's char-code sum mod 4 (bot3/bot17/bot18 get three
    // different ones); two bots can still share a corner.
    const corner = [...r.name].reduce((n, c) => n + c.charCodeAt(0), 0) % 4;
    refuseSupport(r, {x1, z1, x2, z2, y1: bottom, y2: top});
    let skipped = 0;
    job.t.total = top - bottom + 1;
    // Walking (the pathfinder digs natural ground) must not remove the steps left standing (Codex R4-4).
    r.keepCells = new Set(Array.from({length: top - bottom + 1}, (_, i) => { const k = ring[i % ring.length]; return `${k.x},${top - i},${k.z}`; }));
    try {
      for (let y = top; y >= bottom; y--) {
        const keep = ring[(top - y) % ring.length];
        let dugHere = false;
        for (let pass = 1; ; pass++) {
          guard(job);
          const layer = child(job, {type: 'excavate', args: {x1, y1: y, z1, x2, y2: y, z2, keep, corner}});
          try {
            await JOBS.excavate(r, layer);
            dugHere ||= !layer.noop;
            break;
          } catch (e) {
            guard(job);
            if (!/were not dug/.test(e.message)) throw e;
            if (pass === 3) { skipped += Number(e.message.split(' ')[0]) || 0; break; }
            await sleep(2000);
          }
        }
        // Only a layer this bot dug ground from: above the surface every step is air (2026-10-10: bot3
        // built a floating stair of cobblestone over the shaft).
        if (dugHere) await fixStep(r, job, keep.x, y, keep.z);
        // Every 8 layers a torch on the wall beside the stair step (the box edge, so a wall is there). Only when
        // the bot already carries light; a dark shaft never stops the dig.
        if (dugHere && shaftTorchDue(top, y) && r.bot.inventory.items().some((i) => /^(torch|coal|charcoal)$/.test(i.name))) {
          await goNear(r, job, keep.x, y + 1, keep.z, 0, {goal: new goals.GoalBlock(keep.x, y + 1, keep.z), doing: `walking to the stair at y ${y} for a torch`})
            .then(() => lightUp(r, job, [], {wall: true}))
            .catch((e) => { guard(job); r.emit('info', `no shaft torch at y ${y}: ${e.message.slice(0, 80)}`); });
        }
        Object.assign(job.t, {total: top - bottom + 1, done: top - y + 1}); // excavate borrowed the counters
        job.progress = `shaft ${x1} ${z1}: down to y ${y}${skipped ? `, ${skipped} blocks left (unsafe or unreachable)` : ''}`;
      }
    } finally {
      r.keepCells = null;
    }
    if (skipped) throw new Error(`the shaft reached y ${bottom} but ${skipped} blocks were left (unsafe, unreachable or not loaded)`);
  },

  // A wall on the ground around a shaft so nobody walks into it, with a gap where the stairs meet
  // the ground. Cells that are blocked, unsupported or protected are left out.
  async rim(r, job) {
    const {bot} = r;
    const {x1, z1, x2, z2, top, item} = job.args;
    const Vec3 = require('vec3').Vec3;
    await goNear(r, job, (x1 + x2) >> 1, Math.floor(bot.entity.position.y), z1 - 2, 3, {doing: 'walking to the shaft'});
    const ground = (x, z) => {
      for (let y = Math.floor(bot.entity.position.y) + 12; y > -60; y--) {
        const b = bot.blockAt(new Vec3(x, y, z));
        if (!b) return null;
        if (b.boundingBox === 'block' && !b.name.endsWith('_leaves') && !b.name.endsWith('_log')) return y;
      }
      return null;
    };
    const cells = stairRing(x1 - 1, z1 - 1, x2 + 1, z2 + 1).map((c) => ({...c, y: ground(c.x, c.z)}));
    const ys = cells.map((c) => c.y).filter((y) => y !== null).sort((a, b) => a - b);
    if (!ys.length) throw new Error('the ground around the shaft is not loaded');
    // ponytail: the stair step at the median ground height marks the entrance; uneven ground may move it a block.
    const steps = stairRing(x1, z1, x2, z2);
    const k = (top - ys[ys.length >> 1]) % steps.length;
    const near = (c, s) => Math.abs(c.x - s.x) <= 1 && Math.abs(c.z - s.z) <= 1;
    const gap = (c) => near(c, steps[k]) || near(c, steps[(k + 1) % steps.length]);
    let placed = 0, skipped = 0;
    job.t.total = cells.length;
    for (const [i, c] of cells.entries()) {
      guard(job);
      job.t.done = i;
      if (c.y === null || gap(c)) continue;
      try {
        await JOBS.place(r, child(job, {type: 'place', args: {item, x: c.x, y: c.y + 1, z: c.z}}));
        placed++;
        // A torch on top of every 6th wall block, when the bot already carries one (never crafted here).
        if (rimTorchDue(placed) && r.bot.inventory.items().some((i) => i.name === 'torch')) await JOBS.place(r, child(job, {type: 'place', args: {item: 'torch', x: c.x, y: c.y + 2, z: c.z}})).catch((e) => guard(job));
      } catch (e) {
        guard(job);
        skipped++;
      }
    }
    job.progress = `wall around the shaft: ${placed} placed, ${skipped} left out`;
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
    guard(job); // a Stop during the equip must not place anything
    await bot.placeBlock(below, new Vec3(0, 1, 0)).catch(() => {}); // 26.x may not echo the update in time
    for (let i = 0; i < 20 && bot.blockAt(at)?.name !== item; i++) await sleep(100);
    if (bot.blockAt(at)?.name !== item) throw new Error(`placing ${item} did not take`);
    r.emit('info', `placed ${item} at ${x} ${y} ${z}`);
  },

  async say(r, job) {
    r.bot.chat(job.args.text);
  },
};

module.exports = {lightUp, shaftTorchDue, rimTorchDue, explore, layerOrder, stairRing, BotRunner, NAME_RE, VALIDATE, KEEP, keptOf, TOOL_RE, JOBS, unsafeDig, sealFluids, Cancelled, needsWood, digAt, openChest, guardDigs, safeMovements, tossJunk, NATURAL, partnerOf, depositList};
