'use strict';
// Standing orders: keep the supply chest stocked without anyone clicking.
//
// Quotas (item -> wanted amount) are declared in default.nix (KEEPER_QUOTAS).
// What is in the chest is known from the last bot that opened it (world.stock,
// reported by `deposit`, `withdraw` and `stock` jobs). Every few seconds, while
// switched on, the keeper
//   1. asks an idle bot to count the chest when the numbers are missing or old,
//   2. for the first quota below its target with nobody on it, gives an idle
//      bot a short job chain (chop/mine ..., deposit) through the same enqueue()
//      the dashboard uses, so everything a human can see or stop works here too.
// It starts switched off after every restart and never takes a bot that has a
// job or a queue. A bot that finishes without raising the stock puts that item
// on a cooldown, so a missing ore never turns into a loop.
const MAX_BOTS = 2; // bots the keeper may use at once
const IDLE_MS = 10000; // a bot must be idle this long before it is taken
const STOCK_MAX_AGE_MS = 15 * 60 * 1000;
const COOLDOWN_MS = 10 * 60 * 1000; // after a chain that did not raise the stock
const ASSIGN_TIMEOUT_MS = 30 * 60 * 1000;
const MAX_JOB = 64; // items per chain: short chains, fresh numbers in between

const KINDS = {
  logs: (n) => n.endsWith('_log'),
  coal: (n) => n === 'coal' || n === 'charcoal',
};
const matcher = (key) => KINDS[key] || ((n) => n === key);
const have = (items, key) => Object.entries(items || {}).filter(([n]) => matcher(key)(n)).reduce((s, [, c]) => s + c, 0);

// How to make `n` more of a quota item: [[jobType, args], ...] or {blocked: why}.
// `c` is the chest {x,y,z}; `stock` the chest contents.
const PLANS = {
  logs: (n, c) => [['chop', {count: n}], ['deposit', {...c, only: 'logs'}]],
  cobblestone: (n, c) => [['mine', {block: 'stone', count: n}], ['deposit', {...c, only: 'cobblestone'}]],
  coal: (n, c) => [['mine', {block: 'coal_ore', count: n}], ['deposit', {...c, only: 'coal'}]],
  // 1 coal + 1 stick make 4 torches; sticks need planks, planks need a log.
  torch: (n, c, stock) => {
    const coal = Math.ceil(n / 4);
    if (have(stock, 'coal') < coal) return {blocked: `needs ${coal} coal in the chest first`};
    if (have(stock, 'logs') < 1) return {blocked: 'needs a log in the chest (for the sticks)'};
    return [['withdraw', {item: 'coal', count: coal, ...c}], ['withdraw', {item: 'logs', count: Math.ceil(n / 32), ...c}], ['craft', {item: 'torch', count: n}], ['deposit', {...c, only: 'torch'}]];
  },
};
const WORKSITE = new Set(['chop', 'mine']); // jobs that start with a walk to the work site, when one is set

class Keeper {
  constructor({runners, world, chest, quotas, site = null, events = null, now = Date.now, log = () => {}}) {
    this.runners = runners;
    this.world = world;
    this.chest = chest; // {x,y,z} of the supply chest, or null: nothing to keep
    this.quotas = quotas; // [[item, want]]
    this.site = site;
    this.events = events;
    this.now = now;
    this.log = log;
    this.enabled = false;
    this.work = new Map(); // item -> {bot, n, at, before, seen}
    this.counting = null; // {bot, at}: a bot is on its way to count the chest
    this.cooldown = new Map(); // item -> until
    this.notes = new Map(); // item -> why nothing is happening
    this.idleSince = new Map();
  }

  say(text) {
    this.log('keeper', text);
    this.events?.add('keeper', 'info', text);
  }

  setEnabled(on) {
    if (on && !this.chest) throw new Error('no supply chest is configured, so there is nothing to keep stocked');
    if (this.enabled === !!on) return;
    this.enabled = !!on;
    this.work.clear();
    this.counting = null;
    this.cooldown.clear();
    this.say(this.enabled ? 'standing orders on' : 'standing orders off (bots finish what they are doing; use Stop to end it)');
  }

  snap(r) {
    try {
      return r.snapshot();
    } catch {
      return null;
    }
  }

  idle(s) {
    return !!s && s.online && !s.dead && !s.job && !s.queue.length;
  }

  tick() {
    if (!this.enabled) return;
    const t = this.now();
    const snaps = new Map();
    for (const r of this.runners.values()) {
      const s = this.snap(r);
      snaps.set(r.name, s);
      if (this.idle(s)) this.idleSince.has(r.name) || this.idleSince.set(r.name, t);
      else this.idleSince.delete(r.name);
    }
    const stock = this.world.stock;
    this.finish(snaps, t, stock);

    const busy = new Set([...this.work.values()].map((w) => w.bot).concat(this.counting ? [this.counting.bot] : []));
    const free = () => [...this.runners.values()].filter((r) => !busy.has(r.name) && this.idle(snaps.get(r.name)) && t - (this.idleSince.get(r.name) ?? t) >= IDLE_MS)[0];

    // 1. numbers missing or old: have a bot read the chest
    if (!stock || t - stock.t > STOCK_MAX_AGE_MS) {
      if (!this.counting && busy.size < MAX_BOTS) {
        const r = free();
        if (r) this.assign(r, [['stock', {...this.chest}]], () => (this.counting = {bot: r.name, at: t}), 'counting what is in the supply chest');
      }
      return;
    }
    // 2. the first quota that is short and has nobody on it
    this.notes.clear();
    for (const [item, want] of this.quotas) {
      const missing = want - have(stock.items, item) - (this.work.get(item)?.n || 0);
      if (missing <= 0) continue;
      if (this.work.has(item)) continue;
      if ((this.cooldown.get(item) || 0) > t) {
        this.notes.set(item, `no progress last time, retrying in ${Math.ceil((this.cooldown.get(item) - t) / 60000)} min`);
        continue;
      }
      const plan = PLANS[item];
      if (!plan) {
        this.notes.set(item, 'the keeper has no way to make this');
        continue;
      }
      const n = Math.min(missing, MAX_JOB);
      const jobs = plan(n, this.chest, stock.items);
      if (!Array.isArray(jobs)) {
        this.notes.set(item, jobs.blocked);
        continue;
      }
      if (busy.size >= MAX_BOTS) {
        this.notes.set(item, 'waiting for a free bot');
        continue;
      }
      const r = free();
      if (!r) {
        this.notes.set(item, 'waiting for an idle bot');
        continue;
      }
      const chain = this.site && WORKSITE.has(jobs[0][0]) ? [['goto', {...this.site}], ...jobs] : jobs;
      this.assign(r, chain, () => {
        this.work.set(item, {bot: r.name, n, at: t, before: have(stock.items, item), seen: false});
        busy.add(r.name);
      }, `${r.name}: ${item} ${have(stock.items, item)}/${want}, fetching ${n} (${jobs[0][0]} ...)`);
    }
  }

  assign(r, chain, onOk, text) {
    try {
      for (const [type, args] of chain) r.enqueue(type, args, {replace: false});
    } catch (e) {
      r.enqueue('stop', {}, {});
      this.say(`could not give ${r.name} the job: ${e.message}`);
      return;
    }
    onOk();
    this.say(text);
  }

  // A chain is over when its bot is idle again (after having been seen busy), offline, or too slow.
  finish(snaps, t, stock) {
    if (this.counting) {
      const s = snaps.get(this.counting.bot);
      if ((stock && stock.t >= this.counting.at) || t - this.counting.at > 5 * 60 * 1000 || !s?.online) this.counting = null;
    }
    for (const [item, w] of [...this.work]) {
      const s = snaps.get(w.bot);
      if (s && !this.idle(s)) w.seen = true;
      const over = (w.seen && this.idle(s)) || !s?.online || t - w.at > ASSIGN_TIMEOUT_MS || (!w.seen && t - w.at > 60000);
      if (!over) continue;
      this.work.delete(item);
      // The deposit at the end of every chain re-reads the chest, so a newer stock tells the result.
      const after = stock && stock.t > w.at ? have(stock.items, item) : null;
      if (after !== null && after <= w.before) {
        this.cooldown.set(item, t + COOLDOWN_MS);
        this.say(`${w.bot} is done with ${item}, but the chest did not get more (${w.before} -> ${after}); trying something else for ${COOLDOWN_MS / 60000} min`);
      } else this.say(`${w.bot} is done with ${item}${after !== null ? ` (${w.before} -> ${after} in the chest)` : ''}`);
    }
  }

  state() {
    const stock = this.world.stock;
    const t = this.now();
    return {
      available: !!this.chest,
      enabled: this.enabled,
      chest: this.chest,
      site: this.site,
      stockAgeS: stock ? Math.round((t - stock.t) / 1000) : null,
      stockBy: stock?.by || null,
      quotas: this.quotas.map(([item, want]) => {
        const w = this.work.get(item);
        return {item, want, have: stock ? have(stock.items, item) : null, bot: w?.bot || null, fetching: w?.n || 0, note: w ? '' : this.notes.get(item) || ''};
      }),
      counting: this.counting?.bot || null,
    };
  }
}

// "logs:64,cobblestone:128" -> [['logs', 64], ['cobblestone', 128]]
function parseQuotas(text) {
  const out = [];
  for (const part of String(text || '').split(',').map((x) => x.trim()).filter(Boolean)) {
    const m = /^([a-z_]{1,32}):(\d{1,4})$/.exec(part);
    if (!m || +m[2] < 1 || +m[2] > 1728) throw new Error(`bad KEEPER_QUOTAS entry: ${part} (use item:amount, 1..1728)`);
    if (out.some(([i]) => i === m[1])) throw new Error(`duplicate KEEPER_QUOTAS item: ${m[1]}`);
    out.push([m[1], +m[2]]);
  }
  return out;
}

module.exports = {Keeper, parseQuotas, PLANS, have, MAX_BOTS, IDLE_MS, COOLDOWN_MS, STOCK_MAX_AGE_MS};
