'use strict';
// The plan (R7): one ordered list of objectives (plan-config.js) that the hub works through without
// any LLM, so it keeps going when every model backend is down.
//
// Like the keeper it is data driven and restart safe: what is done is re-read from the world (chest
// stock, blocks, bot inventories) and from what the plan itself saw finish, which is kept in
// STATE_DIR/plan.json. It starts switched off after every restart. It only ever
//   - gives a job chain to an IDLE roster bot through enqueue(..., {replace: false}),
//   - or, for a keeper-driven objective, borrows the Keeper (its quotas, the base chest, the roster)
//     and gives it back when the objective ends, so one scheduler touches idle bots at a time.
// It never replaces or stops a running job. A step that cannot go on is parked (later steps need it)
// or skipped; the dashboard shows both and can retry or skip by hand.
const fs = require('node:fs');
const {have, idle, IDLE_MS} = require('./keeper');

const MIN_HOLD_MS = 60000; // a slot stays taken this long after a bot got it, whatever the bot does
const RETRY_MS = 10 * 60 * 1000; // a slot whose chain failed waits this long
const MAX_FAILS = 3; // failed chains per objective before it counts as blocked
const TIMEOUT_MS = 4 * 3600 * 1000; // enabled time on one objective before it counts as blocked
const MIN_STRIP = 3; // a shaft strip is at least 3 wide

// ---- pure helpers (tested in test.js with plain objects) ----

// A role's jobs as [[type, args], ...]: `jobs`, or the `job`/`args` shorthand.
const jobsOf = (role) => role.jobs || [[role.job, role.args || {}]];

// The width of a split role's box along its axis (from the first job that has one).
function width(role) {
  const a = jobsOf(role).map(([, args]) => args).find((x) => x && typeof x === 'object' && x[`${role.split}1`] !== undefined);
  return a ? a[`${role.split}2`] - a[`${role.split}1`] + 1 : Infinity;
}

// Strip i of n of a box {x1,x2,...} cut along `axis`: disjoint and covering, the first strips one wider.
function strip(args, axis, i, n) {
  const lo = args[`${axis}1`], w = args[`${axis}2`] - lo + 1;
  const base = Math.floor(w / n), extra = w % n;
  const start = lo + i * base + Math.min(i, extra);
  return {...args, [`${axis}1`]: start, [`${axis}2`]: start + base + (i < extra ? 1 : 0) - 1};
}

// Every slot of an objective's roles, for these roster names: {key, role, ri, i, n, bot|null}.
function slotsOf(obj, names) {
  const out = [];
  (obj.roles || []).forEach((role, ri) => {
    if (role.each) {
      [...names].sort().forEach((bot, i, all) => out.push({key: `${ri}:${bot}`, role, ri, i, n: all.length, bot}));
      return;
    }
    const n = Math.max(1, Math.min(role.count || 1, role.split ? Math.floor(width(role) / MIN_STRIP) : Infinity));
    for (let i = 0; i < n; i++) out.push({key: `${ri}:${i}`, role, ri, i, n, bot: null});
  });
  return out;
}

// The job chain of one slot for one bot.
function chainOf({role, i, n}, bot, roster) {
  return jobsOf(role).map(([type, a]) => {
    const args = typeof a === 'function' ? a({bot, i, n, roster}) : role.split && a[`${role.split}1`] !== undefined ? strip(a, role.split, i, n) : a;
    return [type, {...args}];
  });
}

// Does this slot entry still count as taken? A done slot, a slot waiting to retry, and a slot whose bot is
// busy, or got its chain less than minHoldMs ago, are taken; an offline or dead bot frees it (after the hold).
function holds(e, snaps, now, minHoldMs) {
  if (!e) return false;
  if (e.done || (e.retryAt ?? 0) > now) return true;
  if (now - e.at < minHoldMs) return true;
  const s = snaps.get(e.bot);
  return !!s && s.online && !s.dead && !idle(s);
}

// Fill the EMPTY slots of an objective from IDLE roster bots, never replacing anything. `assigned` is
// Map<slotKey, {bot, at, done?, retryAt?}> for this objective and gets the new holders. Returns
// Map<bot, [[type, args], ...]>. opts.idleSince (Map bot -> since) makes a bot wait IDLE_MS first.
function assignRoles(obj, snaps, assigned, now, minHoldMs = MIN_HOLD_MS, opts = {}) {
  const roster = [...snaps.keys()];
  const taken = new Set([...assigned.values()].filter((e) => e.bot && !e.done && holds(e, snaps, now, minHoldMs)).map((e) => e.bot));
  const free = roster.filter((b) => idle(snaps.get(b)) && !taken.has(b) && (!opts.idleSince || now - (opts.idleSince.get(b) ?? now) >= IDLE_MS)).sort();
  const out = new Map();
  for (const slot of slotsOf(obj, roster)) {
    if (holds(assigned.get(slot.key), snaps, now, minHoldMs)) continue;
    const bot = slot.bot ? (free.includes(slot.bot) && !out.has(slot.bot) ? slot.bot : null) : free.find((b) => !out.has(b));
    if (!bot) continue;
    out.set(bot, chainOf(slot, bot, roster));
    assigned.set(slot.key, {bot, at: now});
  }
  return out;
}

// Is the objective done? Keeper-driven: every quota is in the chest (fresh numbers only). Direct: all
// its slots ended without an error, or its own done(ctx) says so.
function objectiveDone(obj, ctx) {
  if (obj.keeper) return !!ctx.stock?.items && obj.keeper.every(([item, want]) => have(ctx.stock.items, item) >= want);
  const slots = slotsOf(obj, [...ctx.snaps.keys()]);
  if (slots.length && slots.every((s) => ctx.results.get(`${obj.id}#${s.key}`)?.ok)) return true;
  return !!obj.done?.(ctx);
}

// What to work on now. Objectives before `idx` are closed. An objective waits for its `needs`; a blocked
// one (ctx.blocked: id -> why) is parked when it says so and a later objective needs it, else skipped.
// Returns {idx (objectives.length: nothing to run), parked: [ids], done: [ids newly found done],
// skipped: [ids given up], note}. ctx.completed and ctx.skipped are Sets of closed ids.
function nextIndex(objectives, idx, ctx) {
  const closed = new Set([...ctx.completed, ...ctx.skipped]);
  const res = {idx: objectives.length, parked: [], done: [], skipped: [], note: ''};
  const notes = [];
  for (let i = idx; i < objectives.length; i++) {
    const o = objectives[i];
    if (closed.has(o.id) || !o.needs.every((n) => closed.has(n))) continue;
    if (objectiveDone(o, ctx)) {
      res.done.push(o.id);
      closed.add(o.id);
      continue;
    }
    const why = ctx.blocked.get(o.id);
    if (!why) {
      res.idx = i;
      break;
    }
    if (o.onBlocked === 'park' && objectives.slice(i + 1).some((x) => x.needs.includes(o.id))) {
      res.parked.push(o.id);
      notes.push(`${o.id} parked: ${why}`);
    } else {
      res.skipped.push(o.id);
      closed.add(o.id);
      notes.push(`${o.id} skipped: ${why}`);
    }
  }
  res.note = notes.join('; ');
  return res;
}

// A chain failed if its bot logged an error after the chain was given.
const failedSince = (s, at, now) => !!s?.lastError && s.lastErrorAgoS != null && now - s.lastErrorAgoS * 1000 >= at;

// ---- the scheduler ----

class Plan {
  constructor({runners, world, keeper = null, places = null, events = null, objectives, roster, chest = null, file = null, blockAt = null, now = Date.now, log = () => {}}) {
    this.runners = runners;
    this.world = world;
    this.keeper = keeper;
    this.places = places;
    this.events = events;
    this.objectives = objectives;
    this.roster = roster;
    this.chest = chest; // {x,y,z}: the chest keeper objectives work on
    this.file = file;
    this.blockAt = blockAt || ((x, y, z) => this.probe(x, y, z));
    this.now = now;
    this.log = log;
    this.enabled = false;
    this.completed = new Set();
    this.skipped = new Set();
    this.blocked = new Map(); // id -> why
    this.fails = new Map(); // id -> failed chains
    this.started = new Map(); // id -> since when it has been the current one while enabled
    this.assigned = new Map(); // id -> Map<slotKey, entry>
    this.results = new Map(); // `${id}#${slotKey}` -> {ok, at, bot}
    this.idleSince = new Map();
    this.borrowed = null; // what the keeper had before the plan took it
    this.stockFrom = 0; // chest numbers older than this are about another chest
    this.cur = null;
    this.parked = [];
    this.note = '';
    this.dirty = false;
    this.load();
  }

  say(text) {
    this.log('plan', text);
    this.events?.add('plan', 'info', text);
  }

  // ---- persistence: STATE_DIR/plan.json ----
  load() {
    if (!this.file) return;
    let d;
    try {
      d = JSON.parse(fs.readFileSync(this.file, 'utf8'));
    } catch {
      return; // none saved
    }
    const ids = new Set(this.objectives.map((o) => o.id));
    const known = (list) => (Array.isArray(list) ? list.filter((id) => ids.has(id)) : []);
    this.completed = new Set(known(d.completed));
    this.skipped = new Set(known(d.skipped));
    for (const [id, n] of Object.entries(d.fails || {})) if (ids.has(id) && Number.isInteger(n)) this.fails.set(id, n);
    for (const [id, why] of Object.entries(d.blocked || {})) if (ids.has(id) && typeof why === 'string') this.blocked.set(id, why);
    for (const [id, slots] of Object.entries(d.assigned || {})) if (ids.has(id)) this.assigned.set(id, new Map(Object.entries(slots)));
    for (const [k, v] of Object.entries(d.results || {})) if (ids.has(k.split('#')[0])) this.results.set(k, v);
  }

  save() {
    this.dirty = false;
    if (!this.file) return;
    const obj = (m) => Object.fromEntries(m);
    const data = {completed: [...this.completed], skipped: [...this.skipped], fails: obj(this.fails), blocked: obj(this.blocked), assigned: Object.fromEntries([...this.assigned].map(([id, m]) => [id, obj(m)])), results: obj(this.results)};
    try {
      fs.writeFileSync(`${this.file}.tmp`, JSON.stringify(data));
      fs.renameSync(`${this.file}.tmp`, this.file);
    } catch (e) {
      this.log('plan', `could not save: ${e.message}`);
    }
  }

  // ---- switches ----
  setEnabled(on) {
    if (this.enabled === !!on) return;
    this.enabled = !!on;
    this.started.clear(); // the clock for "no progress" runs only while switched on
    if (!this.enabled) this.giveBack();
    this.say(this.enabled ? 'plan on' : 'plan off (bots finish what they are doing; use Stop to end it)');
    if (this.dirty) this.save();
  }

  find(id) {
    const o = this.objectives.find((x) => x.id === id);
    if (!o) throw new Error(`no objective called ${id}`);
    return o;
  }

  skip(id) {
    this.find(id);
    this.skipped.add(id);
    this.blocked.delete(id);
    this.dirty = true;
    this.say(`${id} skipped by hand`);
    this.advance();
    if (this.dirty) this.save();
  }

  retry(id) {
    this.find(id);
    this.skipped.delete(id);
    this.completed.delete(id);
    this.blocked.delete(id);
    this.fails.delete(id);
    this.started.delete(id);
    for (const [k, e] of this.assigned.get(id) || []) if (!e.done) this.assigned.get(id).delete(k);
    this.dirty = true;
    this.say(`${id} will be tried again`);
    this.advance();
    if (this.dirty) this.save();
  }

  // ---- observing ----
  snapshots() {
    const snaps = new Map();
    for (const name of this.roster) {
      let s = null;
      try {
        s = this.runners.get(name)?.snapshot() || null;
      } catch {} // a bot that cannot be read counts as offline
      snaps.set(name, s || {name, online: false, dead: false, job: null, queue: [], inventory: []});
    }
    return snaps;
  }

  // The block at x,y,z as seen by any online local roster bot that has the chunk loaded.
  probe(x, y, z) {
    const {Vec3} = require('vec3');
    for (const name of this.roster) {
      const r = this.runners.get(name);
      try {
        if (r?.online && r.bot?.blockAt) {
          const b = r.bot.blockAt(new Vec3(x, y, z));
          if (b) return b.name;
        }
      } catch {}
    }
    return null;
  }

  // The chest numbers, only once the keeper works on the plan's chest and a bot has counted it since.
  trustedStock() {
    const st = this.world.stock;
    return this.borrowed && st && st.t >= this.stockFrom ? st : null;
  }

  ctx(snaps) {
    return {world: this.world, stock: this.trustedStock(), places: this.places, keeper: this.keeper, snaps, results: this.results, roster: this.roster, completed: this.completed, skipped: this.skipped, blocked: this.blocked, blockAt: this.blockAt};
  }

  // ---- the loop ----
  tick() {
    if (!this.enabled) return;
    const t = this.now();
    const snaps = this.snapshots();
    for (const [name, s] of snaps) {
      if (idle(s)) this.idleSince.has(name) || this.idleSince.set(name, t);
      else this.idleSince.delete(name);
    }
    this.collect(snaps, t);
    this.advance(snaps, t);
    const o = this.cur;
    if (o?.keeper && this.keeper) this.driveKeeper(o);
    else if (o) this.assign(o, snaps, t);
    if (this.dirty) this.save();
  }

  // A chain is over when its bot is idle again (after having been seen busy, or after the hold): closed
  // if it logged no error since, else retried after RETRY_MS (and counted).
  collect(snaps, t) {
    const o = this.cur;
    if (!o || o.keeper) return;
    const slots = this.assigned.get(o.id);
    for (const [key, e] of slots || []) {
      if (e.done || !e.bot || e.retryAt) continue; // a failed slot waits for its retry (assignRoles overwrites it)
      const s = snaps.get(e.bot);
      if (s && !idle(s)) e.seen = true;
      // a chain can start and fail between two ticks, so a bot idle after the hold counts as ended too
      if (!(idle(s) && (e.seen || t - e.at >= MIN_HOLD_MS))) continue;
      if (failedSince(s, e.at, t)) {
        this.fails.set(o.id, (this.fails.get(o.id) || 0) + 1);
        slots.set(key, {...e, retryAt: t + RETRY_MS, seen: false});
        this.say(`${e.bot} did not finish ${o.id} (${String(s.lastError).slice(0, 80)}); trying again in ${RETRY_MS / 60000} min`);
      } else {
        e.done = true;
        this.results.set(`${o.id}#${key}`, {ok: true, at: t, bot: e.bot});
        this.say(`${e.bot} finished its part of ${o.id}`);
      }
      this.dirty = true;
    }
  }

  // Is the current objective stuck? Then it is blocked (parked or skipped by nextIndex).
  blockIfStuck(cur, t) {
    if (this.blocked.has(cur.id)) return false;
    const why = !this.roster.length ? 'the roster is empty'
      : cur.keeper && !this.keeper ? 'no keeper to run the quotas'
      : cur.keeper && !this.chest ? 'no base chest is configured'
      : (this.fails.get(cur.id) || 0) >= MAX_FAILS ? `${this.fails.get(cur.id)} chains failed`
      : t - (this.started.get(cur.id) ?? t) > (cur.timeoutMs ?? TIMEOUT_MS) ? 'no progress for hours'
      : null;
    if (!why) return false;
    this.blocked.set(cur.id, why);
    this.dirty = true;
    this.say(`${cur.id} is blocked: ${why}`);
    return true;
  }

  // Pick the objective to work on: close what is done, block what is stuck, move on.
  advance(snaps = this.snapshots(), t = this.now()) {
    if (!this.enabled) return this.cur;
    for (let pass = 0; pass < 2; pass++) {
      const r = nextIndex(this.objectives, 0, this.ctx(snaps));
      for (const id of r.done) {
        this.completed.add(id);
        this.say(`${id} is done`);
      }
      for (const id of r.skipped) {
        this.skipped.add(id);
        this.say(`${id} is skipped: ${this.blocked.get(id)}`);
      }
      if (r.done.length || r.skipped.length) this.dirty = true;
      this.parked = r.parked;
      this.note = r.note;
      const next = this.objectives[r.idx] || null;
      if (next?.id !== this.cur?.id) {
        if (this.cur?.keeper) this.giveBack();
        this.cur = next;
        if (next) {
          this.started.set(next.id, t);
          this.say(`working on ${next.id}: ${next.label}`);
        } else this.say(r.parked.length ? `plan stalled: ${r.parked.join(', ')} parked` : 'plan finished');
      }
      if (!this.cur || !this.blockIfStuck(this.cur, t)) break;
    }
    return this.cur;
  }

  assign(o, snaps, t) {
    const slots = this.assigned.get(o.id) || this.assigned.set(o.id, new Map()).get(o.id);
    for (const [bot, chain] of assignRoles(o, snaps, slots, t, MIN_HOLD_MS, {idleSince: this.idleSince})) {
      const r = this.runners.get(bot);
      try {
        for (const [type, args] of chain) r.enqueue(type, args, {replace: false});
        this.say(`${bot}: ${o.id} (${chain.map(([type]) => type).join(', ')})`);
      } catch (e) {
        r.enqueue('stop', {}, {});
        for (const [k, v] of slots) if (v.bot === bot) slots.set(k, {...v, retryAt: t + RETRY_MS});
        this.fails.set(o.id, (this.fails.get(o.id) || 0) + 1);
        this.say(`could not give ${bot} the job: ${e.message}`);
      }
      this.dirty = true;
    }
  }

  // ---- borrowing the keeper ----
  driveKeeper(o) {
    const k = this.keeper;
    if (k.enabled && !this.borrowed) {
      this.note = 'standing orders are switched on by hand: the plan waits until they are off';
      return;
    }
    if (!this.borrowed) {
      this.borrowed = {quotas: k.quotas, chest: k.chest, site: k.site, runners: k.runners};
      this.world.stock = null; // the numbers on file are about another chest
      this.stockFrom = this.now();
      k.site = null;
    }
    // places.json can move the keeper's chest (applyPlaces); the plan's chest wins while it owns it
    k.quotas = o.keeper;
    k.chest = this.chest;
    k.runners = new Map(this.roster.filter((n) => this.runners.has(n)).map((n) => [n, this.runners.get(n)]));
    if (!k.enabled) k.setEnabled(true);
  }

  giveBack() {
    const b = this.borrowed, k = this.keeper;
    if (!b || !k) return;
    this.borrowed = null;
    k.setEnabled(false);
    Object.assign(k, b);
    this.world.stock = null;
  }

  // ---- for the dashboard ----
  status(o) {
    if (this.completed.has(o.id)) return 'done';
    if (this.skipped.has(o.id)) return 'skipped';
    if (this.parked.includes(o.id)) return 'parked';
    return o.id === this.cur?.id ? 'active' : 'upcoming';
  }

  progress(o, snaps) {
    if (this.completed.has(o.id)) return 1;
    if (o.keeper) {
      const items = this.trustedStock()?.items;
      return items ? o.keeper.reduce((s, [item, want]) => s + Math.min(1, have(items, item) / want), 0) / o.keeper.length : 0;
    }
    const slots = slotsOf(o, [...snaps.keys()]);
    return slots.length ? slots.filter((s) => this.results.get(`${o.id}#${s.key}`)?.ok).length / slots.length : 0;
  }

  state() {
    const snaps = this.snapshots();
    const objectives = this.objectives.map((o) => ({id: o.id, label: o.label, kind: o.keeper ? 'keeper' : 'roles', status: this.status(o), pct: Math.round(100 * this.progress(o, snaps)), why: this.blocked.get(o.id) || ''}));
    const cur = this.cur;
    let note = this.note;
    if (cur?.keeper) {
      const items = this.trustedStock()?.items;
      const short = cur.keeper.filter(([item, want]) => !items || have(items, item) < want).map(([item, want]) => `${item} ${items ? have(items, item) : '?'}/${want}`);
      note = [short.length ? `short: ${short.join(', ')}` : '', this.keeper?.enabled && !this.borrowed ? this.note : ''].filter(Boolean).join('; ');
    }
    const held = new Map();
    for (const [id, m] of this.assigned) for (const e of m.values()) if (e.bot && !e.done && id === cur?.id && holds(e, snaps, this.now(), MIN_HOLD_MS)) held.set(e.bot, id);
    return {
      available: true,
      enabled: this.enabled,
      roster: this.roster,
      finished: !cur && !this.parked.length && this.objectives.every((o) => this.completed.has(o.id) || this.skipped.has(o.id)),
      pct: Math.round((100 * this.objectives.filter((o) => this.completed.has(o.id) || this.skipped.has(o.id)).length) / this.objectives.length),
      current: cur && {id: cur.id, label: cur.label, kind: cur.keeper ? 'keeper' : 'roles', pct: Math.round(100 * this.progress(cur, snaps)), note},
      bots: this.roster.map((bot) => ({bot, online: !!snaps.get(bot)?.online, role: cur?.keeper ? (this.keeper?.work && [...this.keeper.work.values()].some((w) => w.bot === bot) ? `${cur.id}: fetching for the chest` : '') : held.get(bot) || ''})),
      objectives,
      upcoming: objectives.filter((o) => o.status === 'upcoming').map((o) => o.id),
      parked: objectives.filter((o) => o.status === 'parked').map((o) => ({id: o.id, why: o.why})),
      note: this.note,
    };
  }
}

module.exports = {Plan, assignRoles, objectiveDone, nextIndex, slotsOf, strip, MIN_HOLD_MS, RETRY_MS, MAX_FAILS, TIMEOUT_MS};
