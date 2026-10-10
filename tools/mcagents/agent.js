#!/usr/bin/env node
'use strict';
// LLM agents for the mcbots framework (experiment, 2026-10-10). Each agent is a
// Minecraft-tuned model (Andy-4.2 via Ollama) that decides WHAT one bot does next;
// the mcbots dashboard API does the walking, digging and fighting with all its
// safety rules. The model speaks Mindcraft's command language (the format it was
// trained on); translate() maps each command to an mcbots job or answers it as a
// query. Unknown or unsafe commands (!newAction writes code) are refused.
//
//   OLLAMA_URL=http://127.0.0.1:11434 API=http://127.0.0.1:8097 \
//   AGENTS='bot11=Collect stone and logs and put them in the chest.;bot12=...' node agent.js
//
// Every model call and its outcome is appended to LOG (JSONL), the raw material for
// a later fine-tune. No dependencies: Node 22 fetch only.
const fs = require('node:fs');
const path = require('node:path');

const OLLAMA_URL = process.env.OLLAMA_URL || 'http://127.0.0.1:11434';
const MODEL = process.env.MODEL || 'andy-4.2'; // Andy-4.2 (Mar 2026, Qwen3.5-9B), Andy 2.0 License
const API = process.env.API || 'http://127.0.0.1:8097';
const LOG = process.env.LOG ?? path.join(process.cwd(), 'mcagents.jsonl'); // LOG= (empty) logs no model calls
// Dashboard bearer for the lab's agent service (H5): AGENT_TOKEN_FILE, or the systemd credential.
const TOKEN_FILE = process.env.AGENT_TOKEN_FILE || (process.env.CREDENTIALS_DIRECTORY ? path.join(process.env.CREDENTIALS_DIRECTORY, 'dashboard-token') : '');
const TOKEN = TOKEN_FILE ? fs.readFileSync(TOKEN_FILE, 'utf8').trim() : '';
const assigner = new Map(); // worker -> the agent that gave it its last order
const BLUEPRINTS = process.env.BLUEPRINTS || path.join(__dirname, '../../hosts/bandit-lab/services/mcbots/blueprints');
// Off by default: with 4 agents on one GPU, reasoning took 20-30 s per decision (live 2026-10-10)
// and chose the same commands as the 0.6 s answers. THINK=1 turns it on.
const THINK = process.env.THINK === '1';
const TICK_MS = 3000;
// The brain thinks rarely: only on an event, a message, or this check-in while a routine runs / the bot idles.
const CHECKIN_MS = Number(process.env.CHECKIN_MS) || 600000;
const MAX_DECISIONS_PER_MIN = Number(process.env.MAX_DECISIONS_PER_MIN) || 12; // model calls per minute, all agents together
const STATS_MS = Number(process.env.STATS_MS) || 600000;
const MAX_QUERIES = 4; // query rounds (!stats, !inventory ...) before the model must act
const HISTORY = 24; // messages kept per agent

// ---- Mindcraft command language -------------------------------------------------
// Same syntax as Mindcraft (src/agent/commands/index.js): !name or !name("a", 1, ...).
const COMMAND_RE = /!(\w+)(?:\(([^)]*)\))?/;
const ARG_RE = /-?\d+(?:\.\d+)?|true|false|"[^"]*"|'[^']*'/g;

// !assign("bot2", "!collectBlocks(\"iron_ore\", 32)") carries a whole command, quotes and brackets
// included, so it is cut by hand: the worker, then everything up to the line's last ")".
function parseAssign(clean) {
  const at = clean.indexOf('!assign(');
  if (at < 0) return null;
  const line = clean.slice(at + 8).split('\n')[0];
  const w = line.match(/^\s*["']?(\w+)["']?\s*,\s*/);
  const end = line.lastIndexOf(')');
  if (!w || end < w[0].length) return null;
  let inner = line.slice(w[0].length, end).trim();
  if (/^["']/.test(inner)) {
    inner = inner.slice(1);
    if (/["']$/.test(inner)) inner = inner.slice(0, -1); // the closing quote of a quoted command
  }
  return {name: 'assign', args: [w[1], inner.replace(/\\"/g, '"').replace(/\\'/g, "'")]};
}

function parseCommand(text) {
  const clean = String(text).replace(/<think>[\s\S]*?<\/think>/g, '');
  const assign = parseAssign(clean);
  if (assign) return assign;
  const m = clean.match(COMMAND_RE);
  if (!m) return null;
  const args = (m[2] || '').match(ARG_RE) || [];
  return {name: m[1], args: args.map((a) => (/^["']/.test(a) ? a.slice(1, -1) : a === 'true' ? true : a === 'false' ? false : Number(a)))};
}

// Commands offered to the model, in Mindcraft's doc format. Only what mcbots can do safely.
const DOCS = {
  stats: ['Get your bot\'s location, health, hunger, and time of day.', {}],
  inventory: ['Get your bot\'s inventory.', {}],
  entities: ['Get the nearby players and entities.', {}],
  savedPlaces: ['List all saved locations.', {}],
  stop: ['Force stop all actions and commands that are currently executing.', {}],
  goToPlayer: ['Go to the given player.', {player_name: ['string', 'The name of the player to go to.'], closeness: ['number', 'How close to get to the player.']}],
  followPlayer: ['Endlessly follow the given player.', {player_name: ['string', 'name of the player to follow.'], follow_dist: ['number', 'The distance to follow from.']}],
  goToCoordinates: ['Go to the given x, y, z location.', {x: ['number', 'The x coordinate.'], y: ['number', 'The y coordinate.'], z: ['number', 'The z coordinate.'], closeness: ['number', 'How close to get to the location.']}],
  rememberHere: ['Save the current location with a given name.', {name: ['string', 'The name to remember the location as.']}],
  goToRememberedPlace: ['Go to a saved location.', {name: ['string', 'The name of the location to go to.']}],
  collectBlocks: ['Collect the nearest blocks of a given type.', {type: ['string', 'The block type to collect.'], num: ['number', 'The number of blocks to collect.']}],
  startShift: ['Start a work shift: endlessly collect a block type (or logs) and put it in the base chest whenever the inventory fills. It never ends by itself; end it with !stop.', {type: ['string', 'The block type to collect, or logs.']}],
  guardHere: ['Stand guard where you are: fight every hostile within the radius. It never ends by itself; end it with !stop.', {radius: ['number', 'How far from here to guard (4-48).']}],
  afkHere: ['Stop and wait here until another bot writes to you. Use it when there is nothing left to do.', {}],
  putInChest: ['Put the given item in the base chest.', {item_name: ['string', 'The name of the item to put in the chest.'], num: ['number', 'The number of items to put in the chest.']}],
  takeFromChest: ['Take the given items from the base chest.', {item_name: ['string', 'The name of the item to take.'], num: ['number', 'The number of items to take.']}],
  viewChest: ['View the items/counts of the base chest.', {}],
  craftRecipe: ['Craft the given recipe a given number of times.', {recipe_name: ['string', 'The name of the output item to craft.'], num: ['number', 'The number of items to craft.']}],
  smeltItem: ['Smelt the given item the given number of times.', {item_name: ['string', 'The name of the input item to smelt.'], num: ['number', 'The number of times to smelt the item.']}],
  placeHere: ['Place a given block in the current location. Do NOT use to build structures, only use for single blocks.', {type: ['string', 'The block type to place.']}],
  buildBlueprint: ['Build a saved blueprint with its origin at x, y, z (one above the ground). Use this for every structure.', {name: ['string', 'The blueprint name.'], x: ['number', 'The x coordinate.'], y: ['number', 'The y coordinate.'], z: ['number', 'The z coordinate.']}],
  startConversation: ['Start a conversation with a bot. (FOR OTHER BOTS ONLY)', {player_name: ['string', 'The name of the player to send the message to.'], message: ['string', 'The message to send.']}],
  endConversation: ['End the conversation with the given bot. (FOR OTHER BOTS ONLY)', {player_name: ['string', 'The name of the player to end the conversation with.']}],
  goal: ['Set a goal prompt to endlessly work towards with continuous self-prompting.', {selfPrompt: ['string', 'The goal prompt.']}],
  endGoal: ['Call when you have accomplished your goal. It will stop self-prompting and the current action.', {}],
};

const ASSIGN_DOC = ['Give one of your workers (a bot that cannot think) ONE command, for example !assign("bot12", "!collectBlocks(\\"cobblestone\\", 32)"). It reports back when done. Only action commands (collect, startShift, putInChest, craft, goTo...) work.', {bot_name: ['string', 'The worker to command.'], command: ['string', 'The command for the worker, in quotes.']}];

function commandDocs(blueprints = [], workers = []) {
  let docs = '\n*COMMAND DOCS\n You can use the following commands to perform actions and get information about the world. \n    Use the commands with the syntax: !commandName or !commandName("arg1", 1.2, ...) if the command takes arguments.\n\n    Do not use codeblocks. Use double quotes for strings. Only use one command in each response, trailing commands and comments will be ignored.\n';
  for (const [name, [desc, params]] of Object.entries(DOCS)) {
    docs += `!${name}: ${desc}\n`;
    if (Object.keys(params).length) {
      docs += 'Params:\n';
      for (const [p, [type, d]] of Object.entries(params)) docs += `${p}: (${type}) ${d}\n`;
    }
  }
  if (workers.length) docs += `!assign: ${ASSIGN_DOC[0]}\nParams:\nbot_name: (string) ${ASSIGN_DOC[1].bot_name[1]}\ncommand: (string) ${ASSIGN_DOC[1].command[1]}\nYour workers: ${workers.join(', ')}\n`;
  if (blueprints.length) docs += `Blueprints you can build: ${blueprints.join(', ')}\n`;
  return docs + '*\n';
}

// Global cap on model calls per minute (sliding window): a decision takes one, each further query
// round inside it another (MC-4: one decision could make five calls). Agents over the cap wait.
class Budget {
  constructor(perMin) {
    Object.assign(this, {perMin, stamps: []});
  }

  take(now = Date.now()) {
    this.stamps = this.stamps.filter((t) => now - t < 60000);
    if (this.stamps.length >= this.perMin) return false;
    this.stamps.push(now);
    return true;
  }
}

// Why a bot's brain should be asked now: 'message' | 'event' | 'checkin' | null. `a.wake` is set by
// job results, deaths and respawns; a message prompts even while the bot works; a plain running job
// (not a routine) is never interrupted.
function promptReason(a, bot, now, checkinMs = CHECKIN_MS) {
  if (!bot?.online || bot.dead) return null;
  if (a.inbox.length) return 'message';
  if (a.afk || !a.goal) return null;
  const free = (!bot.job && !bot.queue.length) || isRoutine(bot.job);
  if (!free) return null;
  if (a.wake) return 'event';
  return now - a.lastDecisionAt >= checkinMs ? 'checkin' : null;
}

// Jobs that never end by themselves. A bot running one is busy, not "needs a prompt".
const ROUTINES = new Set(['shift', 'guard', 'follow']);
const isRoutine = (job) => !!job && ROUTINES.has(job.type);

const LOG_TYPES = /_log$|^logs?$|^wood$/;
const ORE_DROPS = {coal_ore: 'coal', iron_ore: 'raw_iron', gold_ore: 'raw_gold', copper_ore: 'raw_copper', diamond_ore: 'diamond', emerald_ore: 'emerald', lapis_ore: 'lapis_lazuli', redstone_ore: 'redstone', nether_quartz_ore: 'quartz', nether_gold_ore: 'gold_nugget'};

// Mindcraft command -> {job: [type, args]} | {query: name} | {local: name} | {refuse: why}.
// `ctx` = {pos, supplyChest, places}.
function translate(cmd, ctx) {
  const a = cmd.args;
  const chest = ctx.supplyChest;
  const n = (v, d) => (Number.isFinite(v) && v > 0 ? Math.min(Math.round(v), 2048) : d);
  switch (cmd.name) {
    case 'stats': case 'inventory': case 'entities': case 'savedPlaces': case 'help':
      return {query: cmd.name};
    case 'stop': case 'stay': return {job: ['stop', {}]};
    case 'goToPlayer': return {job: ['come', {player: String(a[0] ?? '')}]};
    case 'followPlayer': return {job: ['follow', {player: String(a[0] ?? '')}]};
    case 'goToCoordinates': return {job: ['goto', {x: a[0], y: a[1], z: a[2]}]};
    case 'collectBlocks': case 'collectBlock': {
      const type = String(a[0] ?? '').replace(/^minecraft:/, '');
      if (LOG_TYPES.test(type)) return {job: ['chop', {count: n(a[1], 1)}]};
      return {job: ['mine', {block: type === 'cobblestone' ? 'stone' : type, count: n(a[1], 1)}]};
    }
    case 'startShift': {
      if (!chest) return {refuse: 'There is no base chest yet.'};
      const type = String(a[0] ?? '').replace(/^minecraft:/, '');
      if (!type) return {refuse: 'Say what to collect, for example !startShift("logs").'};
      return {job: ['shift', {block: LOG_TYPES.test(type) ? 'logs' : type === 'cobblestone' ? 'stone' : type, ...chest}]};
    }
    case 'guardHere':
      if (!ctx.pos) return {refuse: 'Position unknown.'};
      return {job: ['guard', {x: ctx.pos[0], y: ctx.pos[1], z: ctx.pos[2], radius: Math.max(4, Math.min(n(a[0], 16), 48))}]};
    case 'afkHere': return {local: 'afkHere'};
    case 'assign': return {local: 'assign'};
    case 'putInChest':
      if (!chest) return {refuse: 'There is no base chest yet.'};
      return {job: ['deposit', {...chest, only: String(a[0] ?? '')}]};
    case 'takeFromChest':
      if (!chest) return {refuse: 'There is no base chest yet.'};
      return {job: ['withdraw', {...chest, item: String(a[0] ?? ''), count: n(a[1], 1)}]};
    case 'viewChest':
      if (!chest) return {refuse: 'There is no base chest yet.'};
      return {job: ['stock', {...chest}]};
    case 'craftRecipe': case 'craftItem': return {job: ['craft', {item: String(a[0] ?? ''), count: Math.min(n(a[1], 1), 64)}]};
    case 'smeltItem': {
      // Andy-4.2 kept "smelting" the coal_ore it had just mined (live 2026-10-10): say what the ore gave.
      const item = String(a[0] ?? '').replace(/^minecraft:/, '');
      const drop = ORE_DROPS[item.replace(/^deepslate_/, '')];
      if (drop) return {refuse: `Mining ${item} gives ${drop}; ore blocks are never smelted.${drop.startsWith('raw_') ? ` Smelt ${drop} instead.` : ''}`};
      return {job: ['smelt', {item, count: Math.min(n(a[1], 1), 64)}]};
    }
    case 'placeHere':
      if (!ctx.pos) return {refuse: 'Position unknown.'};
      return {job: ['place', {item: String(a[0] ?? ''), x: ctx.pos[0], y: ctx.pos[1], z: ctx.pos[2]}]};
    case 'goToRememberedPlace': {
      const p = (ctx.places || {})[String(a[0] ?? '')];
      return p ? {job: ['goto', {x: p.x, y: p.y, z: p.z}]} : {refuse: `No saved place called "${a[0]}".`};
    }
    case 'buildBlueprint': return {local: 'buildBlueprint'};
    case 'rememberHere': case 'startConversation': case 'endConversation': case 'goal': case 'endGoal':
      return {local: cmd.name};
    case 'newAction': return {refuse: 'Writing code is not allowed here. Use the commands, and !buildBlueprint for structures.'};
    default: return {refuse: `Command !${cmd.name} is not available here.`};
  }
}

// !assign(worker, command): the brain gives a scripted worker one job. Only bots in `workers` (never an
// LLM agent) and only plain job commands (no queries, no !assign, no blueprints). -> {worker, job, replace} | {refuse}.
function assignJob(cmd, workers, state, places = {}) {
  const [name, text] = [String(cmd.args[0] ?? ''), String(cmd.args[1] ?? '')];
  if (!workers.has(name)) return {refuse: `${name || 'That bot'} cannot be assigned. Your workers: ${[...workers].join(', ') || 'none'}.`};
  const bot = state.bots.find((b) => b.name === name);
  if (!bot?.online || bot.dead) return {refuse: `${name} is not available right now.`};
  const inner = parseCommand(text);
  if (!inner) return {refuse: 'The second argument must be a command, for example "!collectBlocks(\\"cobblestone\\", 32)".'};
  const t = translate(inner, {pos: bot.pos, supplyChest: state.supplyChest, places});
  if (t.refuse) return {refuse: t.refuse};
  if (!t.job) return {refuse: `!${inner.name} cannot be assigned. Use an action command such as !collectBlocks or !startShift.`};
  // A routine never ends, so a new order replaces it; a plain job finishes first and the order queues behind it.
  return {worker: name, job: t.job, replace: isRoutine(bot.job)};
}

function workersText(workers, state) {
  const lines = [...workers].map((w) => state.bots.find((b) => b.name === w)).filter((b) => b?.online).map((b) => `- ${b.name}: ${b.job ? b.job.label : 'idle'}`);
  return lines.length ? `YOUR WORKERS (use !assign)\n${lines.join('\n')}\n` : '';
}

// ---- Mindcraft-style status texts ------------------------------------------------
function statsText(bot, state) {
  const others = state.bots.filter((b) => b.name !== bot.name && b.online).map((b) => b.name);
  const players = (state.world?.players || []).map((p) => p.name);
  return `STATS\n- Position: x: ${bot.pos?.[0]}, y: ${bot.pos?.[1]}, z: ${bot.pos?.[2]}\n- Health: ${bot.health} / 20\n- Hunger: ${bot.food} / 20\n- Current Action: ${bot.job ? bot.job.label : 'Idle'}\n- Nearby Human Players: ${players.join(', ') || 'None.'}\n- Nearby Bot Players: ${others.join(', ') || 'None.'}\n${state.supplyChest ? `- Base chest: x: ${state.supplyChest.x}, y: ${state.supplyChest.y}, z: ${state.supplyChest.z}\n` : ''}`;
}

function inventoryText(bot) {
  const items = (bot.inventory || []).map((s) => s.match(/^(.+) x(\d+)$/)).filter(Boolean).map((m) => `- ${m[1]}: ${m[2]}`);
  return `INVENTORY\n${items.join('\n') || ': Nothing'}\n`;
}

function entitiesText(bot, state) {
  const near = (o) => bot.pos && Math.hypot(o.x - bot.pos[0], o.z - bot.pos[2]) < 32;
  const players = (state.world?.players || []).filter(near).map((p) => `- Human player: ${p.name}`);
  const mobs = {};
  for (const m of (state.world?.mobs || []).filter(near)) mobs[m.name] = (mobs[m.name] || 0) + 1;
  return `NEARBY_ENTITIES\n${[...players, ...Object.entries(mobs).map(([k, c]) => `- entities: ${c} ${k}(s)`)].join('\n') || 'None'}\n`;
}

// ---- one agent per bot -----------------------------------------------------------
class Agent {
  constructor(name, goal, team) {
    Object.assign(this, {name, goal, team, history: [], inbox: [], places: {}, memory: '', lastCommand: '', failures: 0,
      wake: true, wakeAt: 0, lastDecisionAt: 0, decisions: 0, modelMs: 0, workers: new Set()});
  }

  system(state, bot) {
    const self = this.goal ? `YOUR CURRENT ASSIGNED GOAL: "${this.goal}"` : '';
    return `You are an AI Minecraft bot named ${this.name} that can converse with players, see, move, mine, build, and interact with the world by using commands.\n${self} Be a friendly, casual, effective, and efficient robot. Be very brief in your responses, don't apologize constantly, don't give instructions or make lists unless asked, and don't refuse requests. Don't pretend to act, use commands immediately when requested. Do NOT say this: 'Sure, I've stopped. *stops*', instead say this: 'Sure, I'll stop. !stop'. Respond only as ${this.name}, never output '(FROM OTHER BOT)' or pretend to be someone else. If you have nothing to say or do, respond with an just a tab '\t'. This is extremely important to me, take a deep breath and have fun :)\nSummarized memory:'${this.memory}'\n${statsText(bot, state)}\n${inventoryText(bot)}\n${workersText(this.workers, state)}${commandDocs(blueprintNames(), [...this.workers])}\nConversation Begin:`;
  }

  push(role, content) {
    this.history.push({role, content});
    if (this.history.length > HISTORY) this.history.splice(0, this.history.length - HISTORY);
  }
}

// After the same command failed twice in a row (a blueprint spot on a hill, live 2026-10-10,
// was retried over and over), tell the model plainly to change something.
function repeatHint(cmd) {
  return `${cmd} has failed twice in a row with the same result. Do not repeat it. Change something: another location a few blocks away (for a build: flat ground, y one above the ground), another item, or ask another bot with !startConversation.`;
}

function blueprintNames() {
  try {
    return fs.readdirSync(BLUEPRINTS).filter((f) => f.endsWith('.json') && f !== 'base-v1.json').map((f) => f.slice(0, -5));
  } catch {
    return [];
  }
}

// Origin and the bearer only go to the dashboard (its cross-site guard and the agent token);
// Ollama refuses foreign origins with 403 and must never see the token.
async function http(method, url, body) {
  const dash = url.startsWith(`${API}/`);
  const headers = {...(body ? {'Content-Type': 'application/json'} : {}), ...(dash && body ? {Origin: new URL(API).origin} : {}), ...(dash && TOKEN ? {Authorization: `Bearer ${TOKEN}`} : {})};
  const res = await fetch(url, {method, headers, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(dash ? 20000 : 180000)});
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

async function think(agent, state, bot) {
  const t0 = Date.now();
  // Qwen-based models (Andy-4.2) allow one system message, first; later "system" lines
  // (job results, self-prompts) go in as user turns marked SYSTEM, as Mindcraft does for such models.
  const messages = [{role: 'system', content: agent.system(state, bot)},
    ...agent.history.map((m) => (m.role === 'system' ? {role: 'user', content: `SYSTEM: ${m.content}`} : m))];
  const out = await http('POST', `${OLLAMA_URL}/api/chat`, {model: MODEL, messages, stream: false, think: THINK, options: {num_ctx: 8192, temperature: 0.6}});
  if (!out.message) throw new Error(`model: ${out.error || 'no answer'}`);
  agent.modelMs += Date.now() - t0;
  const text = String(out.message.content || '').replace(/<think>[\s\S]*?<\/think>/g, '').trim();
  if (LOG) fs.appendFileSync(LOG, JSON.stringify({t: new Date().toISOString(), agent: agent.name, ms: Date.now() - t0, messages, thinking: out.message.thinking || '', reply: text}) + '\n');
  return text;
}

async function sendJob(name, type, args, replace = false) {
  return http('POST', `${API}/api/job`, {bots: [name], type, args, replace});
}

// One decision: let the model talk until it starts an action (or gives up after MAX_QUERIES).
// The caller took the budget for the first model call; every later round waits for its own.
async function decide(agent, agents, getState, budget) {
  for (let round = 0; round <= MAX_QUERIES; round++) {
    while (round > 0 && !budget.take()) await new Promise((r) => setTimeout(r, 1000));
    const state = await getState();
    const bot = state.bots.find((b) => b.name === agent.name);
    if (!bot?.online) return;
    const reply = await think(agent, state, bot);
    agent.push('assistant', reply || '\t');
    const cmd = parseCommand(reply);
    console.log(`[${agent.name}] ${reply.slice(0, 160).replace(/\n/g, ' ')}`);
    if (!cmd) return; // just talk
    const ctx = {pos: bot.pos, supplyChest: state.supplyChest, places: {...Object.fromEntries((state.places || []).map((p) => [p.name, p])), ...agent.places}};
    const t = translate(cmd, ctx);
    if (t.refuse) {
      agent.push('system', t.refuse);
      continue;
    }
    if (t.query) {
      const q = {stats: () => statsText(bot, state), inventory: () => inventoryText(bot), entities: () => entitiesText(bot, state),
        savedPlaces: () => `Saved place names: ${Object.keys(ctx.places).join(', ') || 'none'}`, help: () => commandDocs(blueprintNames(), [...agent.workers])}[t.query];
      agent.push('system', q());
      continue;
    }
    if (t.local) {
      const a = cmd.args;
      if (t.local === 'rememberHere') {
        agent.places[String(a[0])] = {x: bot.pos[0], y: bot.pos[1], z: bot.pos[2]};
        agent.push('system', `Location saved as "${a[0]}".`);
        continue;
      }
      if (t.local === 'startConversation') {
        const to = agents.get(String(a[0]));
        if (!to) agent.push('system', `${a[0]} is not a bot here. Bots: ${[...agents.keys()].join(', ')}`);
        else to.inbox.push(`${agent.name}: (FROM OTHER BOT)${a[1] ?? ''}`);
        return;
      }
      if (t.local === 'endConversation') return;
      if (t.local === 'assign') {
        const as = assignJob(cmd, agent.workers, state, ctx.places);
        if (as.refuse) {
          agent.push('system', as.refuse);
          continue;
        }
        try {
          await sendJob(as.worker, ...as.job, as.replace);
        } catch (e) {
          agent.push('system', `Code output: Assignment to ${as.worker} failed. ${e.message}`);
          continue;
        }
        assigner.set(as.worker, agent.name);
        // Idle workers left: ask again right away (a shift never reports back, so nothing else would wake the foreman).
        if (state.bots.some((b) => b.name !== as.worker && agent.workers.has(b.name) && b.online && !b.dead && !b.job && !b.queue?.length && !assigner.has(b.name))) {
          agent.wake = true;
          agent.wakeAt ||= Date.now();
        }
        agent.push('system', `Assigned to ${as.worker}: ${as.job[0]} ${JSON.stringify(as.job[1])}. It reports back when done.`);
        return;
      }
      if (t.local === 'afkHere' || t.local === 'endGoal') {
        // Go quiet only once the bot has really stopped (MC-4): a failed Stop would leave a shift
        // running with nobody watching. Instead the brain is asked again.
        try {
          await sendJob(agent.name, 'stop', {});
        } catch (e) {
          agent.push('system', `Code output: Stop failed (${e.message}); your current action is still running. Try again.`);
          agent.wake = true;
          agent.wakeAt ||= Date.now();
          return;
        }
        if (t.local === 'afkHere') agent.afk = true; // no more prompts until a message comes
        else agent.goal = '';
        return;
      }
      if (t.local === 'goal') {
        agent.goal = String(a[0] ?? '');
        return;
      }
      if (t.local === 'buildBlueprint') {
        let bp;
        try {
          bp = JSON.parse(fs.readFileSync(path.join(BLUEPRINTS, `${path.basename(String(a[0]))}.json`), 'utf8'));
        } catch {
          agent.push('system', `No blueprint called "${a[0]}". Blueprints: ${blueprintNames().join(', ')}`);
          continue;
        }
        t.job = ['build', {origin: {x: a[1], y: a[2], z: a[3]}, blocks: bp.blocks}];
      }
    }
    const same = reply.match(COMMAND_RE)[0];
    if (same !== agent.lastCommand) agent.failures = 0;
    agent.lastCommand = same;
    try {
      await sendJob(agent.name, ...t.job);
    } catch (e) {
      agent.push('system', `Code output: Action failed. ${e.message}`);
      continue;
    }
    return;
  }
}

async function main() {
  const spec = (process.env.AGENTS || '').split(';').map((s) => s.trim()).filter(Boolean);
  if (!spec.length) throw new Error('AGENTS must be "bot11=goal;bot12=goal"');
  const agents = new Map();
  for (const s of spec) {
    const [name, goal = ''] = s.split('=');
    agents.set(name.trim(), new Agent(name.trim(), goal.trim(), null));
  }
  const workers = new Set((process.env.WORKERS || '').split(',').map((w) => w.trim()).filter((w) => /^\w+$/.test(w) && !agents.has(w)));
  for (const a of agents.values()) a.workers = workers;
  // The dashboard may still be starting (the lab restarts mcbots and this service together): wait.
  let lastEventId;
  for (;;) {
    try {
      lastEventId = (await http('GET', `${API}/api/events?since=0`)).lastId || 0;
      break;
    } catch (e) {
      console.error(`dashboard not reachable yet (${e.cause?.code || e.message}); retrying in 10 s`);
      await new Promise((r) => setTimeout(r, 10000));
    }
  }
  const getState = () => http('GET', `${API}/api/state`);
  const busy = new Set();
  const budget = new Budget(MAX_DECISIONS_PER_MIN);
  const t0 = Date.now();
  console.log(`agents: ${[...agents.keys()].join(', ')} model ${MODEL} via ${OLLAMA_URL}, bots via ${API}, log ${LOG}; check-in ${CHECKIN_MS / 1000} s, cap ${MAX_DECISIONS_PER_MIN} model calls/min`);
  setInterval(() => {
    const h = (Date.now() - t0) / 3600000;
    for (const a of agents.values()) console.log(`stats [${a.name}] ${a.decisions} decisions in ${(h * 60).toFixed(0)} min (${(a.decisions / h).toFixed(1)}/h), model time ${(a.modelMs / 1000).toFixed(0)} s (${((a.modelMs / 3600000 / h) * 100).toFixed(1)} % of the time)`);
  }, STATS_MS).unref();
  for (;;) {
    try {
      // Job results become "Code output" lines, as Mindcraft reports them, and wake the brain.
      const ev = await http('GET', `${API}/api/events?since=${lastEventId}`);
      lastEventId = ev.lastId;
      for (const e of ev.events) {
        const boss = agents.get(assigner.get(e.bot));
        if (boss && /^(finished|failed|gave up|stopped)/.test(e.text)) {
          boss.push('system', `Worker ${e.bot}: ${e.text}`);
          boss.wake = true;
          boss.wakeAt ||= Date.now();
        } else if (boss && (e.kind === 'death' || e.kind === 'respawn')) boss.push('system', `Worker ${e.bot}: ${e.text}`);
        const a = agents.get(e.bot);
        if (!a) continue;
        if (e.kind === 'death' || e.kind === 'respawn') {
          a.push('system', `Event: ${e.text}`);
          a.wake = true;
          a.wakeAt ||= Date.now();
          continue;
        }
        if (!/^(finished|failed|gave up|stopped)/.test(e.text)) continue;
        a.push('system', `Code output:\n${e.text}`);
        a.failures = /^failed/.test(e.text) ? a.failures + 1 : 0;
        if (a.failures >= 2) a.push('system', repeatHint(a.lastCommand));
        a.wake = true;
        a.wakeAt ||= Date.now();
      }
      const state = await getState();
      const now = Date.now();
      const ready = [];
      for (const agent of agents.values()) {
        if (busy.has(agent.name)) continue;
        const bot = state.bots.find((b) => b.name === agent.name);
        const why = promptReason(agent, bot, now);
        if (why) ready.push([agent, why, bot]);
      }
      ready.sort((x, y) => (x[0].wakeAt || x[0].lastDecisionAt) - (y[0].wakeAt || y[0].lastDecisionAt)); // longest waiting first
      for (const [agent, why, bot] of ready) {
        if (!budget.take(now)) break; // over the cap: the rest wait for a later tick
        if (why === 'message') {
          agent.afk = false;
          while (agent.inbox.length) agent.push('user', agent.inbox.shift());
        } else if (why === 'checkin') {
          agent.push('system', `Check-in: ${bot.job ? `you have been running "${bot.job.label}" for a while (use !stop first to change it)` : 'you are idle'}. Continue your goal: "${agent.goal}". If all is well reply with just a tab.`);
        } else agent.push('system', `You are self-prompting with the goal: "${agent.goal}". Respond:`);
        Object.assign(agent, {wake: false, wakeAt: 0, lastDecisionAt: now});
        agent.decisions++;
        busy.add(agent.name);
        // One model call at a time per agent; agents run side by side (Ollama queues them).
        decide(agent, agents, getState, budget).catch((e) => console.error(`[${agent.name}] ${e.message}`)).finally(() => busy.delete(agent.name));
      }
    } catch (e) {
      console.error(`tick: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, TICK_MS));
  }
}

if (require.main === module) main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});

module.exports = {decide, Agent, parseCommand, translate, commandDocs, statsText, inventoryText, repeatHint, isRoutine, Budget, promptReason, assignJob, workersText};
