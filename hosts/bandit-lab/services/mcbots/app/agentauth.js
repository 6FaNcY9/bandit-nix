'use strict';
// The agent service's bearer token (H5, AGENT-HANDOFF.md CX-5): a machine principal that may read
// state and events and give its own bots the jobs the Mindcraft translator produces - nothing else
// (no "all", no other bots, no keeper/settings/places/debug, chests only the supply chest).
const crypto = require('node:crypto');

const hash = (s) => crypto.createHash('sha256').update(String(s)).digest();
const AGENT_JOBS = new Set(['stop', 'come', 'follow', 'goto', 'mine', 'chop', 'shift', 'guard', 'deposit', 'withdraw', 'stock', 'craft', 'smelt', 'place', 'build', 'excavate', 'shaft', 'level', 'hunt', 'bed', 'homebed', 'grave']);
const CHEST_JOBS = new Set(['deposit', 'withdraw', 'stock', 'shift']);

// null: no bearer sent (human path); true/false: a bearer was sent and does / does not match.
function bearerMatches(header, tokenHash) {
  if (header === undefined) return null;
  const m = /^Bearer ([\w-]{32,128})$/.exec(String(header));
  return !!(m && tokenHash && crypto.timingSafeEqual(hash(m[1]), tokenHash));
}

const agentEndpoint = (method, path) => (method === 'GET' && (path === '/api/state' || path === '/api/events')) || (method === 'POST' && (path === '/api/job' || path === '/api/decision' || path === '/api/agentstatus'));

// The agent's self-description for the dashboard's Agents section: a cleaned status, or {error}.
function agentStatus({agent, goal, workers, role}, {agentBots}) {
  if (!agentBots.includes(agent)) return {error: 'agent must be an agent bot'};
  if (typeof goal !== 'string' || (role !== undefined && typeof role !== 'string')) return {error: 'goal and role must be strings'};
  if (!Array.isArray(workers) || workers.length > 12 || !workers.every((w) => agentBots.includes(w))) return {error: 'workers must be at most 12 agent bot names'}; // a fixed domain: free names would grow the dashboard's per-worker rows (Codex R4-6)
  return {agent, goal: goal.slice(0, 500), workers, role: (role || '').slice(0, 40)};
}

// Why the agent may not send this job, or null.
function agentJobRefusal({bots, type, args}, {agentBots, supplyChest}) {
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

module.exports = {agentStatus, hash, bearerMatches, agentEndpoint, agentJobRefusal, AGENT_JOBS};
