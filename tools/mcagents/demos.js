'use strict';
// Demonstrations from the deterministic crew (owner, 2026-10-11): every job of a plan/keeper/solver-driven
// roster bot that FINISHES becomes one training row {kind: 'demo', messages: [system, user, assistant]}: the
// compact bot-state prompt the agents use, captured when the job STARTED, and the Mindcraft command that is
// the inverse of agent.js translate() for that job. Failed or stopped jobs write nothing. Runs inside the
// mcagents service (it polls /api/events and /api/state); agent.js feeds feed(events, state, now).
const {createHash} = require('node:crypto');

const SCAN_GAP_MS = 30000; // at most one scan per bot in this time; a later job reuses the last one
const PENDING_MAX = 4; // started jobs per bot that await a result
const SEEN_MAX = 4000;
const STALE_MS = 3600000; // a job with no result by then is forgotten

// ---- label -> job ---------------------------------------------------------------------------
// The dashboard's event label is "<type> <arg values in order>" (mcbots bots.js jobLabel); the events carry
// no args, so they are rebuilt per type, in the shape translate() produces. Unknown types and shapes -> null.
function labelJob(type, rest) {
  const w = String(rest || '').trim().split(/\s+/).filter(Boolean);
  const n = w.map(Number);
  const nums = (from, to) => n.slice(from, to).every(Number.isFinite) && w.slice(from, to).length === to - from;
  switch (type) {
    case 'mine': return w.length === 2 && nums(1, 2) ? ['mine', {block: w[0], count: n[1]}] : null;
    case 'chop': return w.length === 1 && nums(0, 1) ? ['chop', {count: n[0]}] : null;
    case 'craft': case 'smelt': return w.length === 2 && nums(1, 2) ? [type, {item: w[0], count: n[1]}] : null;
    case 'withdraw': return w.length === 5 && nums(1, 5) ? ['withdraw', {x: n[2], y: n[3], z: n[4], item: w[0], count: n[1]}] : null;
    case 'deposit': return (w.length === 3 || w.length === 4) && nums(0, 3) ? ['deposit', {x: n[0], y: n[1], z: n[2], only: w[3] ?? ''}] : null;
    case 'shift': return w.length === 4 && nums(1, 4) ? ['shift', {block: w[0], x: n[1], y: n[2], z: n[3]}] : null;
    case 'shaft': case 'treefarm': return w.length >= 4 && nums(0, 4) ? [type, {x1: n[0], z1: n[1], x2: n[2], z2: n[3]}] : null;
    case 'seal': return w.length === 6 && nums(0, 6) ? ['seal', {x1: n[0], z1: n[1], x2: n[2], z2: n[3], y1: n[4], y2: n[5]}] : null;
    case 'goto': return w.length === 3 && nums(0, 3) ? ['goto', {x: n[0], y: n[1], z: n[2]}] : null;
    case 'tidy': return w.length === 4 && nums(0, 4) ? ['tidy', {x: n[0], y: n[1], z: n[2], radius: n[3]}] : null;
    case 'homebed': return ['homebed', {}];
    default: return null; // rearm, wheatfarm, stock, place, ... have no Mindcraft command
  }
}

// ---- job -> command (inverse of agent.js translate()) -----------------------------------------
const arg = (v) => (typeof v === 'number' ? String(v) : JSON.stringify(String(v)));
const call = (name, ...a) => `!${name}${a.length ? `(${a.join(', ')})` : ''}`;
const int = (v, max = 2048) => Number.isInteger(v) && v > 0 && v <= max;
const mcBlock = (b) => (b === 'stone' ? 'cobblestone' : b); // the model says cobblestone; translate maps it back to stone

// ctx: {places: [{name, x, y, z}], pos: [x, y, z] | null}. -> '!command(...)' | null
function inverse([type, a], ctx = {}) {
  switch (type) {
    case 'mine': return int(a.count) && a.block ? call('collectBlocks', arg(mcBlock(a.block)), a.count) : null;
    case 'chop': return int(a.count) ? call('collectBlocks', arg('logs'), a.count) : null;
    case 'deposit': return a.only ? call('putInChest', arg(a.only)) : null; // a deposit of everything has no equivalent
    case 'withdraw': return int(a.count) && a.item ? call('takeFromChest', arg(a.item), a.count) : null;
    case 'craft': return int(a.count, 64) && a.item ? call('craftRecipe', arg(a.item), a.count) : null;
    case 'smelt': return int(a.count, 64) && a.item ? call('smeltItem', arg(a.item), a.count) : null;
    case 'shaft': return call('digShaft', a.x1, a.z1, a.x2, a.z2);
    case 'treefarm': return call('tendTreeFarm', a.x1, a.z1, a.x2, a.z2);
    case 'seal': return call('sealArea', a.x1, a.z1, a.x2, a.z2, a.y1, a.y2);
    case 'shift': return a.block ? call('startShift', arg(mcBlock(a.block))) : null;
    case 'homebed': return call('setHomeBed');
    case 'goto': {
      const p = (ctx.places || []).find((q) => q.name && q.x === a.x && q.y === a.y && q.z === a.z);
      return p ? call('goToRememberedPlace', arg(p.name)) : null; // a bare coordinate walk is not a named place
    }
    case 'tidy': { // !collectDrops tidies around where the bot STANDS: only the same spot teaches that
      const near = ctx.pos && Math.hypot(ctx.pos[0] - a.x, ctx.pos[2] - a.z) <= 8;
      return near && int(a.radius, 32) ? call('collectDrops', a.radius) : null;
    }
    default: return null;
  }
}

const norm = (v) => (v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, norm(v[k])])) : v);
const sameJob = (x, y) => JSON.stringify(norm(x)) === JSON.stringify(norm(y));

// The command, but only when agent.js translate() turns it back into exactly this job (and does not refuse it).
function commandFor(job, ctx, {translate, parseCommand}) {
  const text = inverse(job, ctx);
  const cmd = text && parseCommand(text);
  if (!cmd) return null;
  const a = job[1];
  const chest = a.x !== undefined && ['deposit', 'withdraw', 'shift'].includes(job[0]) ? {x: a.x, y: a.y, z: a.z} : ctx.chest;
  const places = Object.fromEntries((ctx.places || []).map((p) => [p.name, p]));
  const t = translate(cmd, {pos: job[0] === 'tidy' ? [a.x, a.y, a.z] : ctx.pos, supplyChest: chest, places});
  return t.job && sameJob(t.job, job) ? text : null;
}

// ---- recording -----------------------------------------------------------------------------
const bucket = (n) => Math.floor(Math.log2(1 + n));
// Same job, same coarse state: the command, the item kinds held (with a count bucket) and the objective.
function dedupeKey(command, bot, objective) {
  const inv = (bot.inventory || []).map((s) => /^(.+) x(\d+)$/.exec(s)).filter(Boolean).map((m) => `${m[1]}:${bucket(Number(m[2]))}`).sort();
  return createHash('sha256').update(JSON.stringify([command, inv, objective?.id || ''])).digest('hex').slice(0, 20);
}

function snapshot(state, bot) {
  const p = state.plan?.current;
  return {
    bot: {...bot, job: null, queue: []}, // it is idle when the question is asked: no label that gives the answer away
    state: {bots: state.bots.map((b) => ({name: b.name, online: b.online})), supplyChest: state.supplyChest, world: {players: [], stock: state.world?.stock}, places: state.places || []},
    objective: p ? {id: p.id, label: p.label, kind: p.kind} : null,
  };
}

class DemoRecorder {
  // deps: {fetchScan(bot), makeContext({bot, state, objective, scan}) -> {system, user}, verify(job, ctx) -> command | null,
  //        logCall(line), agents: Set (LLM agents are not demonstrators), isSolverJob(bot, at) -> bool, now}
  constructor(deps) {
    Object.assign(this, {deps, pending: new Map(), scans: new Map(), seen: new Set(), seq: 0, run: Date.now().toString(36), stats: {written: 0, duplicate: 0, skipped: 0}});
  }

  scanFor(bot, now) {
    const old = this.scans.get(bot);
    if (old && now - old.at < SCAN_GAP_MS) return old.promise;
    const promise = Promise.resolve(this.deps.fetchScan(bot)).catch(() => '');
    this.scans.set(bot, {at: now, promise});
    return promise;
  }

  // One tick: the new events and the state fetched right after them. Resolves when the rows are written; never rejects.
  async feed(events, state, now = Date.now()) {
    const roster = new Set((state.plan?.roster || []).filter((n) => !this.deps.agents.has(n)));
    const done = [];
    for (const e of events) {
      if (!roster.has(e.bot)) continue;
      const list = (this.pending.get(e.bot) || []).filter((p) => now - p.at < STALE_MS);
      this.pending.set(e.bot, list);
      if (e.kind === 'death') { list.length = 0; continue; }
      if (e.kind === 'job') {
        const m = /^started: (\w+)(.*)$/.exec(e.text);
        const job = m && labelJob(m[1], m[2]);
        const bot = state.bots.find((b) => b.name === e.bot);
        // A result in the same batch means the state is no longer the state at the start: no row.
        const same = events.some((x) => x.id > e.id && x.bot === e.bot && ['done', 'fail', 'stop'].includes(x.kind));
        if (!m || !job || !bot?.online || same) { if (m) list.push({type: m[1], rest: m[2].trim(), skip: true, at: now}); continue; }
        list.push({type: m[1], rest: m[2].trim(), job, at: now, snap: snapshot(state, bot), scan: this.scanFor(e.bot, now), source: this.deps.isSolverJob?.(e.bot, now) ? 'solver' : state.plan?.current?.kind === 'keeper' ? 'keeper' : 'plan'});
        if (list.length > PENDING_MAX) list.shift();
        continue;
      }
      if (!['done', 'fail', 'stop'].includes(e.kind)) continue;
      const m = /^(?:finished|failed|stopped|gave up): (\w+) ?(.*?)(?: - already complete)?(?: \(\d+ s\))?$/.exec(e.text);
      const i = m ? list.findIndex((p) => p.type === m[1]) : -1;
      if (i < 0) continue;
      const p = list.splice(i, 1)[0];
      if (e.kind === 'done' && !p.skip && m[2] === p.rest && !/already complete/.test(e.text)) done.push([e.bot, p]);
    }
    for (const [bot, p] of done) await this.write(bot, p).catch((err) => console.error(`[demos] ${err.message}`));
  }

  async write(bot, p) {
    const {deps} = this;
    const {snap} = p;
    const ctx = {places: snap.state.places, pos: snap.bot.pos, chest: snap.state.supplyChest};
    const command = deps.verify(p.job, ctx);
    if (!command) return void this.stats.skipped++;
    const key = dedupeKey(command, snap.bot, snap.objective);
    if (this.seen.has(key)) return void this.stats.duplicate++;
    this.seen.add(key);
    if (this.seen.size > SEEN_MAX) this.seen.delete(this.seen.values().next().value);
    const scan = await p.scan;
    const {system, user} = deps.makeContext({bot: snap.bot, state: snap.state, objective: snap.objective, scan});
    const row = {kind: 'demo', t: new Date().toISOString(), id: `demo-${this.run}-${++this.seq}`, source: p.source, bot, job: `${p.type} ${p.rest}`.trim(), key,
      messages: [{role: 'system', content: system}, {role: 'user', content: user}, {role: 'assistant', content: command}]};
    deps.logCall(JSON.stringify(row) + '\n');
    this.stats.written++;
  }
}

module.exports = {DemoRecorder, labelJob, inverse, commandFor, sameJob, dedupeKey, snapshot, SCAN_GAP_MS};
