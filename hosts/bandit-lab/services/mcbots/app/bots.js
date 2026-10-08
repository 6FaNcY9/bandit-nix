'use strict';
// One BotRunner per bot: connection lifecycle plus a sequential job queue.
// Adding a job type = add one entry to JOBS and one to VALIDATE; nothing else
// changes. Most jobs are thin wrappers around the vendored Mindcraft skills
// (see mindcraft.js); chase/rearm/deposit/say are our own orchestration.
const mineflayer = require('mineflayer');
const {goals} = require('mineflayer-pathfinder');
const {Vec3} = require('vec3');
const mindcraft = require('./mindcraft');
const {Combat} = require('./combat');
const {normDim, deadlineMs} = require('./world');

const NAME_RE = /^bot[0-9]{1,2}$/; // BotGate's pattern (Velocity plugin)
const LOGIN_GAP_MS = 4500; // Velocity rate-limits logins
const GOTO_TIMEOUT_MS = 90000;
const SKILL_TIMEOUT_MS = 120000; // default cap for one skill call
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
const itemName = (v, what = 'item') => {
  if (!/^[a-z_]{1,48}$/.test(v || '')) throw new Error(`${what} must be a name like oak_planks`);
  return v;
};
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
  craft: (a) => ({item: itemName(a.item), count: num(a.count ?? 1, 1, 64, 'count')}),
  smelt: (a) => ({item: itemName(a.item), count: num(a.count ?? 1, 1, 64, 'count')}),
  place: (a) => ({block: itemName(a.block, 'block'), ...xyz(a)}),
  'collect-drops': () => ({}),
  sleep: () => ({}),
  surface: () => ({}),
  'dig-down': (a) => ({distance: num(a.distance ?? 5, 1, 32, 'distance')}),
  deposit: xyz,
  rearm: xyz,
  say: (a) => {
    const text = String(a.text ?? '').trim();
    if (!text || text.length > 200) throw new Error('text must be 1..200 characters');
    if (text.startsWith('/')) throw new Error('commands are not allowed');
    return {text};
  },
};

class Cancelled extends Error {}

class BotRunner {
  constructor(name, {host, port, log, world, protectedAreas = [], supplyChest = null}) {
    this.name = name;
    this.world = world;
    this.combat = {busy: false, epoch: 0}; // replaced by a Combat per connection
    this.host = host;
    this.protectedAreas = protectedAreas;
    this.supplyChest = supplyChest;
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

  async connect() {
    if (this.stopped) return;
    try {
      await mindcraft.load(); // the skill library must be ready before the first job
    } catch (e) {
      this.log(this.name, `skills failed to load: ${e.message}`);
      return this.schedule(BACKOFF_CAP);
    }
    if (this.stopped) return;
    this.log(this.name, `connecting to ${this.host}:${this.port}`);
    const bot = mineflayer.createBot({host: this.host, port: this.port, username: this.name, auth: 'offline', version: '26.1', hideErrors: true});
    this.bot = bot;
    mindcraft.attach(bot, this.protectedAreas);
    bot.once('login', () => mindcraft.load(bot.version).catch((e) => this.log(this.name, `skills: ${e.message}`)));
    let spawnedAt = 0;
    this.combat = new Combat(this);
    bot.once('spawn', () => {
      spawnedAt = Date.now();
      this.online = true;
      const mv = mindcraft.safeMovements(bot);
      bot.pathfinder.setMovements(mv);
      bot.collectBlock.movements = mv;
      this.log(this.name, 'spawned');
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
    if (b) b.interrupt_code = true; // skills poll this in their loops
    try {
      if (b?.isSleeping) b.wake().catch(() => {});
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
        if (process.env.MCBOTS_DEBUG) console.log(e.stack);
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

// Run one Mindcraft skill: its failures are returned as `false` plus a message
// in bot.output; here they become exceptions. Every call has a deadline that
// interrupts the skill (they poll bot.interrupt_code and stop the pathfinder).
async function skill(r, job, name, args = [], {timeout = SKILL_TIMEOUT_MS} = {}) {
  guard(job);
  const bot = r.bot;
  const {skills} = await mindcraft.load();
  bot.output = '';
  bot.interrupt_code = false;
  let timedOut = false;
  const deadline = setTimeout(() => {
    timedOut = true;
    bot.interrupt_code = true;
    bot.pathfinder?.stop();
    if (bot.isSleeping) bot.wake().catch(() => {});
  }, timeout);
  try {
    const ok = await skills[name](bot, ...args);
    guard(job);
    if (timedOut) throw new Error(`${name} timed out after ${Math.round(timeout / 1000)} s`);
    if (ok === false) throw new Error(bot.output.trim().split('\n').slice(-2).join(' ') || `${name} failed`);
    return bot.output;
  } finally {
    clearTimeout(deadline);
    bot.interrupt_code = false;
  }
}

async function goNear(r, job, x, y, z, dist, {brave = false} = {}) {
  guard(job);
  // Unreachable goals make the pathfinder retry partial paths forever, so
  // every walk has a deadline.
  let timedOut = false;
  const deadline = setTimeout(() => {
    timedOut = true;
    r.bot.interrupt_code = true;
    r.bot?.pathfinder.stop();
  }, GOTO_TIMEOUT_MS);
  try {
    // Something else (combat, a block update) can stop the path mid-walk; walk
    // again instead of failing the job, unless the deadline or a stop hit.
    for (let tries = 0; ; tries++) {
      try {
        if (!brave) await waitSafe(r, job, x, z);
        await skill(r, job, 'goToPosition', [x, y, z, dist], {timeout: GOTO_TIMEOUT_MS});
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

// mine/chop: one block per skill call, so a combat interruption resumes with
// the count already collected. The skill digs its target directly (no
// pathfinder veto), so blocks inside protected areas are passed as `exclude`.
async function collect(r, job, isWanted, count, what) {
  const {bot} = r;
  let got = job.collected || 0;
  while (got < count) {
    await waitCalm(r, job);
    const found = bot.findBlocks({matching: (blk) => isWanted(blk.name), maxDistance: 64, count: 256});
    const protectedPos = found.filter((p) => mindcraft.inArea(r.protectedAreas, p.x, p.z));
    const near = found.find((p) => !protectedPos.includes(p));
    if (!near) throw new Error(`no ${what} within 64 blocks outside protected areas (collected ${got}/${count})`);
    await waitSafe(r, job, near.x, near.z);
    await skill(r, job, 'collectBlock', [bot.blockAt(near).name, 1, protectedPos.length ? protectedPos : null]);
    job.collected = ++got;
    job.progress = `${got}/${count}`;
  }
}

// Skills that place or break blocks next to the bot (crafting table, furnace,
// dig-down, place) do not go through the pathfinder veto, so refuse them for
// the bot standing, or the target lying, inside a protected area.
function refuseProtected(r, x, z, what) {
  if (mindcraft.inArea(r.protectedAreas, Math.floor(x), Math.floor(z))) {
    throw new Error(`${what}: ${Math.floor(x)} ${Math.floor(z)} is inside a protected area`);
  }
}
const refuseHere = (r, what) => refuseProtected(r, r.bot.entity.position.x, r.bot.entity.position.z, what);

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

  mine(r, job) {
    const b = job.args.block; // also accepts the short names coal/iron/... like the skill does
    const wanted = new Set([b, `deepslate_${b}`, `${b}_ore`, `deepslate_${b}_ore`, ...(b === 'dirt' ? ['grass_block'] : []), ...(b === 'cobblestone' ? ['stone'] : [])]);
    return collect(r, job, (n) => wanted.has(n), job.args.count, b);
  },

  chop: (r, job) => collect(r, job, (n) => n.endsWith('_log'), job.args.count, 'logs'),

  async craft(r, job) {
    refuseHere(r, 'craft');
    await skill(r, job, 'craftRecipe', [job.args.item, job.args.count]);
    job.progress = `crafted ${job.args.item}`;
  },

  async smelt(r, job) {
    refuseHere(r, 'smelt');
    const {item, count} = job.args;
    // The skill waits for the furnace: allow about 10 s per item.
    await skill(r, job, 'smeltItem', [item, count], {timeout: 60000 + count * 11000});
    job.progress = `smelted ${item}`;
  },

  async place(r, job) {
    const {block, x, y, z} = job.args;
    refuseProtected(r, x, z, 'place');
    await skill(r, job, 'placeBlock', [block, x, y, z, 'bottom', true]);
  },

  async 'collect-drops'(r, job) {
    await skill(r, job, 'pickupNearbyItems');
  },

  async sleep(r, job) {
    const t = r.bot.time?.timeOfDay;
    if (t !== undefined && t < 12542) throw new Error('it is daytime, beds only work at night (or in thunder)');
    await skill(r, job, 'goToBed', [], {timeout: 600000});
  },

  async surface(r, job) {
    await skill(r, job, 'goToSurface');
  },

  async 'dig-down'(r, job) {
    refuseHere(r, 'dig-down');
    await skill(r, job, 'digDown', [job.args.distance]);
  },

  async deposit(r, job) {
    const {bot} = r;
    const {x, y, z} = job.args;
    await goNear(r, job, x, y, z, 3);
    const block = bot.blockAt(new Vec3(x, y, z));
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

  // Visit every chest/barrel within 6 blocks of the supply point and take
  // what is missing: best armour per slot, a sword, an axe, a pickaxe, a totem
  // for the off-hand and food up to 32; then wear/hold it.
  async rearm(r, job) {
    const {bot} = r;
    const {x, y, z} = job.args;
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
    await bot.armorManager.equipAll().catch(() => {}); // mineflayer-armor-manager wears the best piece per slot
    const totem = bot.inventory.items().find((i) => i.name === 'totem_of_undying');
    if (totem) await bot.equip(totem, 'off-hand').catch(() => {});
    const sword = best(bot.inventory.items(), /_sword$/);
    if (sword) await bot.equip(sword, 'hand').catch(() => {});
    const worn = ['head', 'torso', 'legs', 'feet'].filter((s) => bot.inventory.slots[bot.getEquipmentDestSlot(s)]).length;
    const off = bot.inventory.slots[bot.getEquipmentDestSlot('off-hand')]?.name;
    job.progress = `armour ${worn}/4, ${sword?.name || 'no sword'}, off-hand ${off || 'empty'}, food ${foodCount()}`;
  },

  async say(r, job) {
    r.bot.chat(job.args.text);
  },
};

module.exports = {BotRunner, NAME_RE, VALIDATE, TOOL_RE};
