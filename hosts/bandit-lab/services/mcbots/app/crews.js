'use strict';
// Crews, goals and bed slots chosen in the dashboard, kept in STATE_DIR/crews.json. The agent service
// reads them (GET /api/crews) and uses them instead of its env defaults (default.nix) while present.
const fs = require('node:fs');
const path = require('node:path');

const MAX_GOAL = 1000;
const MAX_CREW = 12; // as agentauth.agentStatus
const MAX_SLOT = 13; // homebed.SLOTS - 1

const map = (v, what) => {
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error(`${what} must be an object`);
  return Object.entries(v);
};

// Validates a whole input (sections left out stay as they are, null clears one) against the known names.
// `agentBots`: bots an agent may drive; `agents`: the bots that run as agents (never workers); `bots`: every bot (bed slots).
function clean(input, cur, {agentBots, agents, bots}) {
  const out = {...cur};
  for (const k of Object.keys(input || {})) if (!(k in cur)) throw new Error(`unknown section ${k}`);
  if (input.crews !== undefined) {
    out.crews = {};
    const seen = new Set();
    for (const [a, ws] of input.crews === null ? [] : map(input.crews, 'crews')) {
      if (!agentBots.includes(a)) throw new Error(`${a} is not an agent bot`);
      if (!Array.isArray(ws) || ws.length > MAX_CREW) throw new Error(`the crew of ${a} must be a list of at most ${MAX_CREW} bots`);
      for (const w of ws) {
        if (!agentBots.includes(w)) throw new Error(`${w} is not an agent bot`);
        if (agents.has(w)) throw new Error(`${w} is an agent and cannot be a worker`);
        if (seen.has(w)) throw new Error(`${w} is in two crews`);
        seen.add(w);
      }
      out.crews[a] = ws;
    }
    for (const a of Object.keys(out.crews)) if (seen.has(a)) throw new Error(`${a} is an agent and cannot be a worker`);
  }
  if (input.goals !== undefined) {
    out.goals = {};
    for (const [a, g] of input.goals === null ? [] : map(input.goals, 'goals')) {
      if (!agentBots.includes(a)) throw new Error(`${a} is not an agent bot`);
      if (typeof g !== 'string' || !g.trim() || g.length > MAX_GOAL) throw new Error(`the goal of ${a} must be 1..${MAX_GOAL} characters`);
      out.goals[a] = g.trim();
    }
  }
  if (input.slots !== undefined) {
    out.slots = {};
    const used = new Set();
    for (const [b, s] of input.slots === null ? [] : map(input.slots, 'slots')) {
      if (!bots.includes(b)) throw new Error(`unknown bot ${b}`);
      if (!Number.isInteger(s) || s < 0 || s > MAX_SLOT) throw new Error(`the bed slot of ${b} must be a whole number from 0 to ${MAX_SLOT}`);
      if (used.has(s)) throw new Error(`bed slot ${s} is taken twice`);
      used.add(s);
      out.slots[b] = s;
    }
  }
  return out;
}

class Crews {
  constructor(dir, ctx) {
    this.file = dir ? path.join(dir, 'crews.json') : null;
    this.ctx = ctx; // {agentBots, bots}
    this.data = {crews: {}, goals: {}, slots: {}};
    if (this.file) {
      try {
        this.data = clean(JSON.parse(fs.readFileSync(this.file, 'utf8')), this.data, {...ctx, agents: new Set()});
      } catch {} // missing, unreadable or invalid: the env defaults
    }
  }

  // `agents`: bots the agent service reports as agents (they may not become workers).
  set(input, agents) {
    this.data = clean(input, this.data, {...this.ctx, agents});
    if (this.file) {
      const tmp = `${this.file}.tmp`;
      fs.writeFileSync(tmp, JSON.stringify(this.data, null, 2));
      fs.renameSync(tmp, this.file);
    }
    return this.data;
  }
}

module.exports = {Crews, clean, MAX_GOAL};
