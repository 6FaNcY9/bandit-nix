'use strict';
// The agent service's bearer token (H5, AGENT-HANDOFF.md CX-5): a machine principal that may read
// state and events and give its own bots the jobs the Mindcraft translator produces - nothing else
// (no "all", no other bots, no keeper/settings/places/debug, chests only the supply chest).
const crypto = require('node:crypto');

const hash = (s) => crypto.createHash('sha256').update(String(s)).digest();
const AGENT_JOBS = new Set(['stop', 'come', 'follow', 'goto', 'mine', 'chop', 'shift', 'guard', 'deposit', 'withdraw', 'stock', 'craft', 'smelt', 'place', 'build', 'excavate', 'shaft', 'level', 'seal', 'hunt', 'bed', 'homebed', 'grave', 'treefarm', 'tidy']);
const CHEST_JOBS = new Set(['deposit', 'withdraw', 'stock', 'shift']);
// The problem solver (tools/mcagents/solver.js) may also command the plan's roster bots, with this menu only
// (mirrored in tools/mcagents/solver.js MENU_JOBS and tested). Chest jobs use the supply chest; goto and seal
// only a place or zone of the map, never a coordinate of the model's own.
const SOLVER_JOBS = new Set(['rearm', 'deposit', 'withdraw', 'craft', 'smelt', 'mine', 'chop', 'tidy', 'goto', 'seal']);
const SOLVER_CHEST = new Set(['rearm', 'deposit', 'withdraw', 'tidy']);
const SOLVER_JOB_GAP_MS = 3 * 60000, SOLVER_JOBS_PER_HOUR = 10, SOLVER_FRESH_S = 60, SOLVER_SKIPS_PER_HOUR = 3;

// Server-side rate limit of the solver per key (a bot, or 'plan' for skips).
class SolverLimiter {
  constructor({now = Date.now, gapMs = SOLVER_JOB_GAP_MS, perHour = SOLVER_JOBS_PER_HOUR} = {}) {
    Object.assign(this, {now, gapMs, perHour, stamps: new Map()});
  }

  // Why `key` may not act now, or null; a null records the action.
  take(key, {gapMs = this.gapMs, perHour = this.perHour} = {}) {
    const t = this.now();
    const s = (this.stamps.get(key) || []).filter((x) => t - x < 3600000);
    this.stamps.set(key, s);
    if (s.length && t - s.at(-1) < gapMs) return `solver: ${key} got a solver job less than ${Math.round(gapMs / 60000)} min ago`;
    if (s.length >= perHour) return `solver: ${key} reached ${perHour} solver actions this hour`;
    s.push(t);
    return null;
  }
}
const sameBox = (a, b) => ['x1', 'y1', 'z1', 'x2', 'y2', 'z2'].every((k) => Number(a?.[k]) === Number(b?.[k]));

// null: no bearer sent (human path); true/false: a bearer was sent and does / does not match.
function bearerMatches(header, tokenHash) {
  if (header === undefined) return null;
  const m = /^Bearer ([\w-]{32,128})$/.exec(String(header));
  return !!(m && tokenHash && crypto.timingSafeEqual(hash(m[1]), tokenHash));
}

const agentEndpoint = (method, path) => (method === 'GET' && (path === '/api/state' || path === '/api/events' || path === '/api/crews' || path === '/api/storage/find' || path.startsWith('/api/scan/'))) || (method === 'POST' && (path === '/api/job' || path === '/api/solver' || path === '/api/decision' || path === '/api/agentstatus'));

// The agent's self-description for the dashboard's Agents section: a cleaned status, or {error}.
function agentStatus({agent, goal, workers, role}, {agentBots}) {
  if (!agentBots.includes(agent)) return {error: 'agent must be an agent bot'};
  if (typeof goal !== 'string' || (role !== undefined && typeof role !== 'string')) return {error: 'goal and role must be strings'};
  if (!Array.isArray(workers) || workers.length > 12 || !workers.every((w) => agentBots.includes(w))) return {error: 'workers must be at most 12 agent bot names'}; // a fixed domain: free names would grow the dashboard's per-worker rows (Codex R4-6)
  return {agent, goal: goal.slice(0, 1000), workers, role: (role || '').slice(0, 40)};
}

// Why the solver may not send this job to a roster bot, or null (and then the action is counted).
function solverRefusal({bots, type, args, replace}, {agentBots, supplyChest, roster = [], places = [], jobOf = () => null, limiter}) {
  if (bots.length !== 1) return 'solver: one bot per job';
  const bot = bots[0];
  if (agentBots.includes(bot) || !roster.includes(bot)) return `solver: ${bot} is not a plan roster bot`;
  if (!SOLVER_JOBS.has(type)) return `solver: job ${type} is not on the solver menu`;
  const a = args || {};
  if (SOLVER_CHEST.has(type) && (!supplyChest || (type !== 'tidy' || a.x !== undefined) && (a.x !== supplyChest.x || a.y !== supplyChest.y || a.z !== supplyChest.z))) return 'solver: chest jobs use the supply chest';
  if (type === 'goto' && !places.some((p) => p.x === Number(a.x) && p.y === Number(a.y) && p.z === Number(a.z))) return 'solver: goto only to a named place';
  if (type === 'seal' && !places.some((p) => p.box && sameBox(p.box, {x1: a.x1, y1: a.y1, z1: a.z1, x2: a.x2, y2: a.y2, z2: a.z2}))) return 'solver: seal only a named zone';
  if (replace === true && jobOf(bot)?.runningS < SOLVER_FRESH_S) return `solver: ${bot} got its job less than ${SOLVER_FRESH_S} s ago, no replace`;
  return limiter ? limiter.take(bot) : 'solver: no rate limiter';
}

// POST /api/solver {action: note|escalate|skip, bot, text, objective} -> {kind, bot, text, skip?} for the server to apply, or {error}.
function solverAction({action, bot, text, objective}, {agentBots, roster = [], blocked = [], limiter}) {
  if (!['note', 'escalate', 'skip'].includes(action)) return {error: 'solver action must be note, escalate or skip'};
  if (typeof text !== 'string' || !text.trim()) return {error: 'solver: text required'};
  if (action !== 'skip' && !roster.includes(bot) && !agentBots.includes(bot) && bot !== 'base') return {error: `solver: ${bot} is not a roster bot`};
  const line = `solver: ${text.replace(/\s+/g, ' ').trim().slice(0, 200)}`; // model text: one short line on the phone
  if (action === 'note') {
    const refused = limiter?.take(`${bot}:note`, {gapMs: 0, perHour: 60});
    return refused ? {error: refused} : {kind: 'info', bot, text: line};
  }
  if (action === 'escalate') {
    const refused = limiter?.take(`${bot}:escalate`);
    return refused ? {error: refused} : {kind: 'alert', bot, text: line};
  }
  if (!blocked.includes(objective)) return {error: 'solver: that objective is not parked or blocked'};
  const refused = limiter?.take('plan', {gapMs: 0, perHour: SOLVER_SKIPS_PER_HOUR});
  return refused ? {error: refused} : {kind: 'info', bot: 'plan', text: line, skip: objective};
}

// Why the agent may not send this job, or null.
function agentJobRefusal({bots, type, args, replace, solver}, policy) {
  const {agentBots, supplyChest} = policy;
  if (solver === true && Array.isArray(bots) && bots.length === 1 && !agentBots.includes(bots[0])) return solverRefusal({bots, type, args, replace}, policy);
  if (!Array.isArray(bots) || !bots.length) return 'agents must name their bots';
  const other = bots.find((b) => !agentBots.includes(b));
  if (other !== undefined) return `${other} is not an agent bot`;
  if (!AGENT_JOBS.has(type)) return `job ${type} is not allowed for agents`;
  if (CHEST_JOBS.has(type)) {
    const a = args || {};
    if (!supplyChest || a.x !== supplyChest.x || a.y !== supplyChest.y || a.z !== supplyChest.z) return 'agents may only use the supply chest';
  }
  return null;
}

const validBackend = (backend) => typeof backend === 'string' && /^[a-zA-Z0-9_.:\[\]-]{1,128}$/.test(backend);

module.exports = {SolverLimiter, solverAction, SOLVER_JOBS, validBackend, agentStatus, hash, bearerMatches, agentEndpoint, agentJobRefusal, AGENT_JOBS};
