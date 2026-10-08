'use strict';
require('./itemfix'); // must load before mineflayer
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
// Kept on deposit: what a bot needs to craft a replacement tool or light a mine.
const KEEP_RE = /^(stick|[a-z_]+_planks|coal|charcoal|torch|crafting_table|furnace)$/;
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
  say: (a) => {
    const text = String(a.text ?? '').trim();
    if (!text || text.length > 200) throw new Error('text must be 1..200 characters');
    if (text.startsWith('/')) throw new Error('commands are not allowed');
    return {text};
  },
};

class Cancelled extends Error {}

class BotRunner {
  constructor(name, {host, port, log, world, protectedAreas = [], supplyChest = null, loginSeed = null}) {
    this.name = name;
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
    require('./crafting').fixCraftTiming(bot);
    unwedge(bot);
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
      this.lastError = 'died';
      this.cancel();
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
  // replace: drop the queue and the running job first, so a click means "do
  // this now" instead of waiting behind earlier clicks.
  enqueue(type, args = {}, {replace = false} = {}) {
    if (replace && type !== 'stop') {
      this.queue = [];
      this.cancel();
    }
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
      b?.stopDigging?.();
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
      inventory: top.map(([n, c]) => `${n} x${c}`),
      inventoryKinds: top.length,
      lastError: this.lastError,
    };
  }
}


// Pathing uses mineflayer's default movement (it may dig and pillar outside
// bases). Inside protected areas (player bases) it neither digs nor places.
// A custom unbreakable-block list made the pathfinder plan routes it then
// refused to walk (2026-10-08), so protection is by area only.
// A bot can end up a hair from a wall where client and server collision
// disagree: the server then pulls it back every tick (~20 forced moves/s) and
// the pathfinder never gets moving again. Re-centre it in its block when that
// starts (seen after stopping a mining job in a 1-wide pit, 2026-10-08).
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

async function goNear(r, job, x, y, z, dist, {brave = false, goal = null} = {}) {
  guard(job);
  // Unreachable goals make the pathfinder retry partial paths
  // forever, so every walk has a deadline.
  let timedOut = false;
  const deadline = setTimeout(() => {
    timedOut = true;
    r.bot?.pathfinder.stop();
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
  await goNear(r, job, pos.x, pos.y, pos.z, 4, {goal: new goals.GoalLookAtBlock(pos, bot.world, {reach: 4})});
  guard(job);
  block = bot.blockAt(pos);
  if (!block || block.name.endsWith('air')) return;
  await bot.tool.equipForBlock(block, {}).catch(() => {});
  await bot.dig(block, true);
  // Walk over the drops near the block (items merge and fly a little).
  await sleep(400);
  const drops = Object.values(bot.entities).filter((e) => e.name === 'item' && e.position.distanceTo(pos) <= 4);
  for (const d of drops) {
    guard(job);
    await goNear(r, job, d.position.x, d.position.y, d.position.z, 0.8).catch(() => {});
  }
}

async function collect(r, job, matching, count, what) {
  const {bot} = r;
  const ids = matching.map((n) => bot.registry.blocksByName[n]?.id).filter((i) => i !== undefined);
  if (!ids.length) throw new Error(`unknown block: ${what}`);
  let got = job.collected || 0; // survives a combat interruption + resume
  while (got < count) {
    await waitCalm(r, job);
    // Nearest block that no other bot is working on, so bots spread out
    // instead of all walking to the same ore.
    const dim = normDim(bot.game?.dimension);
    const keyOf = (p) => `${dim}:${p.x},${p.y},${p.z}`;
    const pos = bot.findBlocks({matching: ids, maxDistance: 64, count: 48})
      .find((p) => !r.world?.claimedByOther(r.name, keyOf(p)));
    if (!pos) throw new Error(`no free ${what} within 64 blocks (collected ${got}/${count})`);
    const key = keyOf(pos);
    r.world?.claim(r.name, key);
    await waitSafe(r, job, pos.x, pos.z);
    try {
      await digAt(r, job, pos);
    } catch (e) {
      guard(job);
      throw e;
    } finally {
      r.world?.release(r.name, key);
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
    await goNear(r, job, x, y, z, 3);
    const block = bot.blockAt(new (require('vec3').Vec3)(x, y, z));
    if (!block || !/chest|barrel/.test(block.name)) throw new Error(`no chest at ${x} ${y} ${z} (found ${block?.name})`);
    const chest = await bot.openContainer(block);
    try {
      let moved = 0;
      for (const it of bot.inventory.items()) {
        guard(job);
        if (TOOL_RE.test(it.name) || KEEP_RE.test(it.name) || bot.registry.foodsByName[it.name]) continue;
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

  // Visit every chest/barrel within 6 blocks of the supply point and take
  // what is missing: best armour per slot, a sword, an axe, a pickaxe, a totem
  // for the off-hand and food up to 32; then wear/hold it.
  async rearm(r, job) {
    const {bot} = r;
    const {x, y, z} = job.args;
    const Vec3 = require('vec3').Vec3;
    const centre = new Vec3(x, y, z);
    const ids = ['chest', 'trapped_chest', 'barrel'].map((n) => bot.registry.blocksByName[n]?.id).filter((i) => i !== undefined);
    await goNear(r, job, x, y, z, 3, {brave: true}); // getting armour is the safety step
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
      await goNear(r, job, pos.x, pos.y, pos.z, 3, {brave: true});
      const box = await bot.openContainer(bot.blockAt(pos));
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
    for (;;) {
      guard(job);
      if (bot.inventory.emptySlotCount() < 4) {
        job.progress = `depositing (${total} so far)`;
        await JOBS.deposit(r, sub({args: {x: job.args.x, y: job.args.y, z: job.args.z}}));
        if (bot.inventory.emptySlotCount() < 4) throw new Error('inventory still full after depositing (chest full?)');
        continue;
      }
      if (!logs && !bot.inventory.items().some((i) => i.name.endsWith('_pickaxe'))) {
        job.progress = 'crafting a pickaxe';
        try {
          await crafting.ensureItem(r, sub({}), 'stone_pickaxe', 1);
        } catch {
          await crafting.ensureItem(r, sub({}), 'wooden_pickaxe', 1);
        }
      }
      const round = sub({});
      await collect(r, round, matching, 8, job.args.block);
      total += 8;
      job.progress = `${total} ${job.args.block} mined`;
    }
  },

  async say(r, job) {
    r.bot.chat(job.args.text);
  },
};

module.exports = {BotRunner, NAME_RE, VALIDATE, TOOL_RE, JOBS};
