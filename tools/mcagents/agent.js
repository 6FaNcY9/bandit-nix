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
const {modelRequest, modelReply} = require('./model-protocol');

const OLLAMA_URL = process.env.OLLAMA_URL || 'http://127.0.0.1:11434';
const ANDY_URL_2 = process.env.ANDY_URL_2 || '';
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
  digShaft: ['Dig a square shaft straight down to bedrock from corner x1, z1 to x2, z2 (at most 16 x 16), leaving stairs along its walls, so the crew reaches every level without digging everywhere. Natural ground only; it takes long, give it to workers.', {x1: ['number', 'The x of one corner.'], z1: ['number', 'The z of one corner.'], x2: ['number', 'The x of the opposite corner.'], z2: ['number', 'The z of the opposite corner.']}],
  digRoom: ['Dig out a room (natural ground only, placed blocks stay) from corner x, y, z: width along x, length along z, height up. At most 9 x 9 x 5. Use it for an underground base.', {x: ['number', 'The x coordinate of the corner.'], y: ['number', 'The floor y.'], z: ['number', 'The z coordinate of the corner.'], width: ['number', 'Blocks along x, 1-9.'], length: ['number', 'Blocks along z, 1-9.'], height: ['number', 'Blocks up, 1-5.']}],
  placeBlockAt: ['Place one block (for example a chest) at x, y, z; it needs a solid block below.', {type: ['string', 'The block type to place.'], x: ['number', 'The x coordinate.'], y: ['number', 'The y coordinate.'], z: ['number', 'The z coordinate.']}],
  huntAnimals: ['Hunt animals near where you stand and collect the drops (a sheep is sheared when you have shears). Use it for wool: a bed needs 3 wool of one colour.', {type: ['string', 'sheep, cow, pig or chicken.'], num: ['number', 'How many animals, 1-32.']}],
  setHomeBed: ['Get your own bed so every death sends you back to the base: you take your slot in the storage room, fetch 3 wool (base chest, else sheep nearby) and logs if you lack them, craft the bed, place it and sleep or click it. Give it once, it needs no arguments.', {}],
  placeBed: ['Make a bed from 3 wool of one colour and 3 planks if you have none, place it with its foot at x, y, z and its head one block towards the facing, and sleep or click it so your respawn point is there. It needs 2 free blocks with solid ground below.', {x: ['number', 'The x coordinate of the foot.'], y: ['number', 'The y coordinate.'], z: ['number', 'The z coordinate of the foot.'], facing: ['string', 'north, south, east or west: where the head of the bed points.']}],
  collectGrave: ['Fetch the loot of a grave (the items a bot dropped by dying) at x, y, z, where the bot died: walks there, sneaks and right-clicks the grave, then puts everything except tools, armour and food into the base chest. Only the owner of a grave can take it.', {x: ['number', 'The x coordinate of the death.'], y: ['number', 'The y coordinate.'], z: ['number', 'The z coordinate.']}],
  buildBlueprint: ['Build a saved blueprint with its origin at x, y, z (one above the ground). Use this for every structure.', {name: ['string', 'The blueprint name.'], x: ['number', 'The x coordinate.'], y: ['number', 'The y coordinate.'], z: ['number', 'The z coordinate.']}],
  startConversation: ['Start a conversation with a bot. (FOR OTHER BOTS ONLY)', {player_name: ['string', 'The name of the player to send the message to.'], message: ['string', 'The message to send.']}],
  endConversation: ['End the conversation with the given bot. (FOR OTHER BOTS ONLY)', {player_name: ['string', 'The name of the player to end the conversation with.']}],
  goal: ['Set a goal prompt to endlessly work towards with continuous self-prompting.', {selfPrompt: ['string', 'The goal prompt.']}],
  endGoal: ['Call when you have accomplished your goal. It will stop self-prompting and the current action.', {}],
};

const ASSIGN_DOC = ['Give one of your workers (a bot that cannot think) ONE command, for example !assign("bot12", "!collectBlocks(\\"cobblestone\\", 32)"). It reports back when done. Commands a worker understands: !startShift("coal") (keeps collecting into the base chest; one of logs, cobblestone, coal, raw_iron, raw_gold), !collectBlocks("iron_ore", 32), !putInChest("coal", 20), !craftRecipe("stick", 4), !smeltItem("raw_iron", 8), !huntAnimals("sheep", 6), !placeBed(x, y, z, "north"), !setHomeBed, !digRoom(...), !digShaft(...), !goToCoordinates(...).', {bot_name: ['string', 'The worker to command.'], command: ['string', 'The command for the worker, in quotes.']}];

const BASE_DOC = ['Get the state of the base: each worker with its job and last result, what the base chest held when last counted, and what is already built or dug.', {}];

// A foreman (an agent with workers) gets few commands: the workers do the gathering, crafting and smelting.
const FOREMAN = new Set(['assign', 'baseStatus', 'buildBlueprint', 'digRoom', 'digShaft', 'huntAnimals', 'placeBed', 'setHomeBed', 'placeBlockAt', 'viewChest', 'stats', 'inventory', 'goToCoordinates', 'stop', 'startConversation']);
const GATHERING = new Set(['collectBlocks', 'collectBlock', 'startShift']);
// Project jobs run until done; the owner decides who works on them (lab 2026-10-10: the lead pulled a worker off the shaft).
const PROJECTS = {shaft: 'digging the shaft', excavate: 'digging a room', build: 'building', grave: 'collecting its grave'};
const isProject = (job) => !!job && Object.hasOwn(PROJECTS, job.type);
// The lead is the foreman whose goal is gathering (the builder bot2 has workers too, but may dig). ponytail: keyword test on the goal text, a !goal that avoids these words slips through.
const leadsGathering = (a) => a.workers.size > 0 && /gather|collect|mine|chop|\blogs?\b|wood|cobble|coal|iron/i.test(a.goal);

function commandDocs(blueprints = [], workers = []) {
  let docs = '\n*COMMAND DOCS\n You can use the following commands to perform actions and get information about the world. \n    Use the commands with the syntax: !commandName or !commandName("arg1", 1.2, ...) if the command takes arguments.\n\n    Do not use codeblocks. Use double quotes for strings. Only use one command in each response, trailing commands and comments will be ignored.\n';
  for (const [name, [desc, params]] of Object.entries(DOCS)) {
    if (workers.length && !FOREMAN.has(name)) continue;
    docs += `!${name}: ${desc}\n`;
    if (Object.keys(params).length) {
      docs += 'Params:\n';
      for (const [p, [type, d]] of Object.entries(params)) docs += `${p}: (${type}) ${d}\n`;
    }
  }
  if (workers.length) docs += `!assign: ${ASSIGN_DOC[0]}\nParams:\nbot_name: (string) ${ASSIGN_DOC[1].bot_name[1]}\ncommand: (string) ${ASSIGN_DOC[1].command[1]}\nYour workers: ${workers.join(', ')}\n!baseStatus: ${BASE_DOC[0]}\n`;
  if (blueprints.length) docs += `Blueprints you can build: ${blueprints.join(', ')}\n`;
  return docs + '*\n';
}

const TALK_WINDOW_MS = 300000, TALK_MAX = 6; // messages one bot may send another per window

// Global cap on model calls per minute (sliding window): a decision takes one, each further query
// round inside it another (MC-4: one decision could make five calls). Agents over the cap wait.
class Budget {
  constructor(perMin) {
    Object.assign(this, {perMin, stamps: []});
  }

  take(now = Date.now()) {
    if (!this.free(now)) return false;
    this.stamps.push(now);
    return true;
  }

  free(now = Date.now()) {
    this.stamps = this.stamps.filter((t) => now - t < 60000);
    return this.stamps.length < this.perMin;
  }
}

// Why a bot's brain should be asked now: 'message' | 'event' | 'checkin' | null. `a.wake` is set by
// job results, deaths and respawns; a message prompts even while the bot works; a plain running job
// (not a routine) is never interrupted.
function promptReason(a, bot, now, checkinMs = CHECKIN_MS, idle = 0) {
  if (!bot?.online || bot.dead) return null;
  if (a.inbox.length) return 'message';
  if (a.afk || !a.goal) return null;
  // A foreman with idle workers is asked even while its own job runs (walking back after a death,
  // building): orders cost it nothing (lab 2026-10-10: workers idled while bot1 re-armed).
  if (a.wake && idle) return 'workers';
  const free = (!bot.job && !bot.queue.length) || isRoutine(bot.job);
  if (!free) return null;
  if (a.wake) return 'event';
  return now - a.lastDecisionAt >= checkinMs ? 'checkin' : null;
}

// Jobs that never end by themselves. A bot running one is busy, not "needs a prompt".
const ROUTINES = new Set(['shift', 'guard', 'follow']);
const isRoutine = (job) => !!job && ROUTINES.has(job.type);

const LOG_TYPES = /_log$|^logs?$|^wood$/;
// What the model says for an ore -> the block ("coal" made a lab shift fail: unknown block, 2026-10-10).
const ORES = new Set(['coal', 'iron', 'gold', 'copper', 'diamond', 'emerald', 'lapis', 'redstone']);
const blockOf = (t) => (t === 'cobblestone' ? 'stone' : ORES.has(t.replace(/^raw_/, '')) ? `${t.replace(/^raw_/, '')}_ore` : t);
// "raw_logs", "minecraft:oak_log", "raw_coal" -> what the bots know (live 2026-10-10: "unknown block: raw_logs").
const clean = (v) => String(v ?? '').replace(/^minecraft:/, '').replace(/^raw_(?=logs?$|wood$)/, '');
// "pickaxe" alone failed as an unknown item; stone tools need only cobblestone and sticks.
const itemOf = (v) => { const t = clean(v); return /^(pickaxe|axe|sword|shovel|hoe)$/.test(t) ? `stone_${t}` : t; };
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
      const type = clean(a[0]);
      if (LOG_TYPES.test(type)) return {job: ['chop', {count: n(a[1], 1)}]};
      return {job: ['mine', {block: blockOf(type), count: n(a[1], 1)}]};
    }
    case 'startShift': {
      if (!chest) return {refuse: 'There is no base chest yet.'};
      const type = clean(a[0]);
      if (!type) return {refuse: 'Say what to collect, for example !startShift("logs").'};
      return {job: ['shift', {block: LOG_TYPES.test(type) ? 'logs' : blockOf(type), ...chest}]};
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
    case 'craftRecipe': case 'craftItem': return {job: ['craft', {item: itemOf(a[0]), count: Math.min(n(a[1], 1), 64)}]};
    case 'smeltItem': {
      // Andy-4.2 kept "smelting" the coal_ore it had just mined (live 2026-10-10): say what the ore gave.
      const item = String(a[0] ?? '').replace(/^minecraft:/, '');
      const drop = ORE_DROPS[item.replace(/^deepslate_/, '')];
      if (drop) return {refuse: `Mining ${item} gives ${drop}; ore blocks are never smelted.${drop.startsWith('raw_') ? ` Smelt ${drop} instead.` : ''}`};
      return {job: ['smelt', {item, count: Math.min(n(a[1], 1), 64)}]};
    }
    case 'digShaft': {
      const [x1, z1, x2, z2] = a.slice(0, 4).map((v) => Math.round(Number(v)));
      if (![x1, z1, x2, z2].every(Number.isFinite) || Math.abs(x2 - x1) > 15 || Math.abs(z2 - z1) > 15 || Math.abs(x2 - x1) < 2 || Math.abs(z2 - z1) < 2) return {refuse: 'Use !digShaft(x1, z1, x2, z2) with sides of 3-16 blocks.'};
      return {job: ['shaft', {x1, z1, x2, z2}]};
    }
    case 'digRoom': {
      const [x, y, z] = a.slice(0, 3).map(Number);
      const [w, l, h] = a.slice(3, 6).map((v) => Math.round(Number(v)));
      if (![x, y, z, w, l, h].every(Number.isFinite) || w < 1 || l < 1 || h < 1 || w > 9 || l > 9 || h > 5) return {refuse: 'Use !digRoom(x, y, z, width, length, height) with width and length 1-9 and height 1-5.'};
      return {job: ['excavate', {x1: x, y1: y, z1: z, x2: x + w - 1, y2: y + h - 1, z2: z + l - 1}]};
    }
    case 'huntAnimals': {
      if (!ctx.pos) return {refuse: 'Position unknown.'};
      const animal = String(a[0] ?? '').replace(/^minecraft:/, '').toLowerCase().replace(/^(cow|pig|chicken)s$/, '$1');
      if (!['sheep', 'cow', 'pig', 'chicken'].includes(animal)) return {refuse: 'Use !huntAnimals(type, num) with type sheep, cow, pig or chicken.'};
      return {job: ['hunt', {animal, count: Math.min(n(a[1], 1), 32), x: ctx.pos[0], y: ctx.pos[1], z: ctx.pos[2], radius: 24}]};
    }
    case 'placeBed': {
      const facing = String(a[3] ?? '').toLowerCase();
      if (![a[0], a[1], a[2]].every((v) => Number.isFinite(Number(v))) || !['north', 'south', 'east', 'west'].includes(facing)) return {refuse: 'Use !placeBed(x, y, z, facing) with facing north, south, east or west.'};
      return {job: ['bed', {x: Number(a[0]), y: Number(a[1]), z: Number(a[2]), facing}]};
    }
    case 'setHomeBed': return {job: ['homebed', {}]};
    case 'collectGrave':
      if (![a[0], a[1], a[2]].every((v) => Number.isFinite(Number(v)))) return {refuse: 'Use !collectGrave(x, y, z) with the coordinates where the bot died.'};
      return {job: ['grave', {x: Math.round(a[0]), y: Math.round(a[1]), z: Math.round(a[2])}]};
    case 'placeBlockAt':
      if (![a[1], a[2], a[3]].every((v) => Number.isFinite(Number(v)))) return {refuse: 'Use !placeBlockAt(type, x, y, z).'};
      return {job: ['place', {item: String(a[0] ?? ''), x: Number(a[1]), y: Number(a[2]), z: Number(a[3])}]};
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
  if (resting(name)) return {refuse: `${name} is resting after two identical failures (${stuckWorkers.get(name).reason}). Give the work to another worker.`};
  if (isProject(bot.job)) return {refuse: `${name} is ${PROJECTS[bot.job.type]}${bot.job.progress ? ` (${bot.job.progress.replace(/^[^:]*: /, '')})` : ''}; pick an idle worker.`};
  const inner = parseCommand(text);
  if (!inner) return {refuse: 'The second argument must be a command, for example "!collectBlocks(\\"cobblestone\\", 32)".'};
  const t = translate(inner, {pos: bot.pos, supplyChest: state.supplyChest, places});
  if (t.refuse) return {refuse: t.refuse};
  if (!t.job) return {refuse: `!${inner.name} cannot be assigned. Use an action command such as !collectBlocks or !startShift.`};
  // A routine never ends, so a new order replaces it; a plain job finishes first and the order queues behind it.
  return {worker: name, job: t.job, replace: isRoutine(bot.job)};
}

// Consecutive failures of one job type with the same reason ("failed: build at ... - could not reach X").
function trackError(a, text) {
  const m = /^failed: (\w+) .* - (.*)$/.exec(text);
  if (!m) {
    if (/^(finished|stopped)/.test(text)) a.errStreak = 0;
    return;
  }
  const reason = m[2].replace(/-?\d+/g, '#'); // "22 blocks left" and "10 blocks left" are one reason
  a.errStreak = m[1] === a.lastErrType && reason === a.lastErrReason ? (a.errStreak || 0) + 1 : 1;
  Object.assign(a, {lastErrType: m[1], lastErrReason: reason});
}

// A foreman's workers: WORKERS_<name> (each agent its own crew, e.g. a lead and a builder), else WORKERS.
// Agents are never workers.
const workersOf = (env, name, agents) => new Set((env[`WORKERS_${name}`] ?? env.WORKERS ?? '').split(',').map((w) => w.trim()).filter((w) => /^\w+$/.test(w) && !agents.has(w)));

// Online workers with nothing to do: the foreman is woken for them (at most every 30 s). A worker that
// logs in after the foreman's first round sends no event, so it waited for the 10-minute check-in (lab).
// A worker whose last two orders failed for the same reason (stuck without a pickaxe underground) does
// not wake the foreman for 5 minutes: it reassigned bot2 every 30 s on the lab, each order failing at once.
const stuckWorkers = new Map(); // name -> {reason, count, at}
function noteWorker(name, text, now = Date.now()) {
  const m = /^failed: \w+ .* - (.*)$/.exec(text);
  if (!m) return stuckWorkers.delete(name);
  const reason = m[1].replace(/-?\d+/g, '#');
  const prev = stuckWorkers.get(name);
  stuckWorkers.set(name, {reason, count: prev?.reason === reason ? prev.count + 1 : 1, at: now});
}
const resting = (name, now = Date.now()) => {
  const s = stuckWorkers.get(name);
  return !!s && s.count >= 2 && now - s.at < 300000;
};
const idleWorkers = (workers, state, now = Date.now()) => state.bots.filter((b) => workers.has(b.name) && b.online && !b.dead && !b.job && !b.queue?.length && !resting(b.name, now)).map((b) => b.name);

// Each worker with its job, its last result and, after two identical failures, a "stuck" note.
function workersText(workers, state, last = new Map()) {
  const lines = [...workers].map((w) => state.bots.find((b) => b.name === w)).filter((b) => b?.online).map((b) => {
    const l = last.get(b.name);
    const p = b.job?.progress || '';
    const job = !isProject(b.job) ? b.job?.label : `${p.includes(': ') ? p.replace(': ', ', ') : [b.job.label, p].filter(Boolean).join(', ')} (project, keep)`;
    return `- ${b.name}: ${job || 'idle'}${l ? ` (last: ${l.slice(0, 100)})` : ''}${resting(b.name) ? ' STUCK: failed twice the same way, give it a different job later' : ''}`;
  });
  return lines.length ? `YOUR WORKERS (use !assign)\n${lines.join('\n')}\n` : '';
}

// ---- what the base looks like: the chest as last counted, what is built or dug ----
const sinceText = (s) => (s < 90 ? `${s} s` : `${Math.round(s / 60)} min`);

function baseLine(agent, state) {
  const s = state.world?.stock;
  const items = s && Object.entries(s.items).sort((a, b) => a[1] - b[1]).slice(0, 8).map(([n, c]) => `${n} ${c}`);
  const chest = s ? `${items.length ? `(lowest first) ${items.join(', ')}` : 'empty'} (counted ${sinceText(s.age)} ago)` : 'not counted yet (!viewChest)';
  const done = [...agent.done].slice(-8);
  return `BASE: chest ${chest}. Already done: ${done.length ? done.join('; ') : 'nothing built or dug yet'}.\n`;
}

const baseStatusText = (agent, state) => `BASE STATUS\n${workersText(agent.workers, state, agent.last)}${baseLine(agent, state)}`;

// A job's identity in the dashboard's label ("build at 1 2 3 22 blocks false", "excavate 1 2 3 7 8 9") and a
// short name for the foreman. Same key from what we sent and from the "finished" event.
function jobKey(type, a) {
  const r = (v) => Math.round(Number(v));
  if (type === 'build') return `build ${r(a.origin.x)} ${r(a.origin.y)} ${r(a.origin.z)} ${a.blocks.length}`;
  if (type === 'excavate') return `excavate ${[a.x1, a.y1, a.z1, a.x2, a.y2, a.z2].map(r).join(' ')}`;
  return null;
}
const eventKey = (text) => {
  const m = /^(?:finished|failed|stopped|gave up): (?:build at (-?\d+) (-?\d+) (-?\d+) (\d+) blocks|excavate ((?:-?\d+ ?){6})\b)/.exec(text);
  return !m ? null : m[5] ? `excavate ${m[5].trim()}` : `build ${m[1]} ${m[2]} ${m[3]} ${m[4]}`;
};
function jobName(type, a, blueprint) {
  if (type === 'build') return `built ${blueprint} at ${Math.round(a.origin.x)} ${Math.round(a.origin.y)} ${Math.round(a.origin.z)}`;
  return `dug room ${Math.round(a.x1)} ${Math.round(a.y1)} ${Math.round(a.z1)} ${a.x2 - a.x1 + 1}x${a.z2 - a.z1 + 1}x${a.y2 - a.y1 + 1}`;
}
// The refusal for a part that already finished (the model copies its last command whatever the result
// says), for the foreman's own jobs and for the ones it assigns.
const alreadyDone = (agent, job, blueprint) => {
  const part = jobKey(job[0], job[1]) && jobName(job[0], job[1], blueprint);
  return part && agent.done.has(part) ? `Refused: already done (${part}). Do the next part, or something else.` : null;
};
// Remember what we sent (per key, oldest first: one bot runs its jobs in order); when its "finished" event
// comes (also "already complete"), that part counts as done. A failed one is just forgotten.
const noteSent = (agent, job, blueprint) => {
  const key = jobKey(job[0], job[1] || {});
  if (key) agent.sent.set(key, [...(agent.sent.get(key) || []), jobName(job[0], job[1], blueprint)]);
};
const DONE_MAX = 200; // the prompt shows 8; ponytail: a part finished longer ago than this may be built again
const noteFinished = (agent, text) => {
  const key = eventKey(text);
  const pending = key && agent.sent.get(key);
  const name = pending?.shift();
  if (pending && !pending.length) agent.sent.delete(key); // no empty key stays behind
  if (name && text.startsWith('finished')) {
    agent.done.delete(name); // newest last
    agent.done.add(name);
    if (agent.done.size > DONE_MAX) agent.done.delete(agent.done.values().next().value);
  }
};

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

const DEPOSIT_RE = /^\w+ put .+ into the base chest$/;
const WORKER_RULES = 'Rules: when you carry items for your goal, put them into the base chest with !putInChest before you start something else. Smelting needs fuel (coal). For gathering, prefer !startShift: it keeps going and fills the base chest by itself.';
const FOREMAN_RULES = 'Rules: you lead, your workers do the work. Give gathering, crafting and smelting to workers with !assign (for gathering prefer !startShift); you only build, dig and place. The BASE line shows the chest and what is already done: never build or dig a finished part again, and when a result says "already complete" move on to the next part. A STUCK worker needs a different job, not the same order. Smelting needs coal.';

// ---- one agent per bot -----------------------------------------------------------
class Agent {
  constructor(name, goal, team) {
    Object.assign(this, {name, goal, team, history: [], inbox: [], places: {}, memory: '', lastCommand: '', failures: 0,
      wake: true, wakeAt: 0, lastDecisionAt: 0, decisions: 0, modelMs: 0, workers: new Set(),
      sent: new Map(), done: new Set(), last: new Map(), talk: new Map()}); // sent/done: build and dig jobs by key; last: a worker's last result
  }

  // Mindcraft's prompt has an example answer "Sure, I'll stop. !stop"; Andy-4.2 copied it whenever it was
  // unsure (the lab lead bot answered nothing else for minutes, 2026-10-10), so it is left out.
  system(state, bot) {
    const self = this.goal ? `YOUR CURRENT ASSIGNED GOAL: "${this.goal}"` : '';
    const rules = this.workers.size ? FOREMAN_RULES : WORKER_RULES;
    return `You are an AI Minecraft bot named ${this.name} that can converse with players, see, move, mine, build, and interact with the world by using commands.\n${self} ${rules} Be a friendly, casual, effective, and efficient robot. Be very brief in your responses, don't apologize constantly, don't give instructions or make lists unless asked, and don't refuse requests. Don't pretend to act, use commands immediately when requested. Respond only as ${this.name}, never output '(FROM OTHER BOT)' or pretend to be someone else. If you have nothing to say or do, respond with an just a tab '\t'. This is extremely important to me, take a deep breath and have fun :)\nSummarized memory:'${this.memory}'\n${statsText(bot, state)}\n${inventoryText(bot)}\n${this.workers.size ? baseLine(this, state) : ''}${workersText(this.workers, state, this.last)}${commandDocs(blueprintNames(), [...this.workers])}\nConversation Begin:`;
  }

  // "bot3 put 64 cobblestone into the base chest": only the last three stay in the history.
  pushDeposit(line) {
    this.push('system', line);
    const dep = (m) => m.role === 'system' && DEPOSIT_RE.test(m.content);
    let extra = this.history.filter(dep).length - 3;
    this.history = this.history.filter((m) => !dep(m) || extra-- <= 0);
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

const modelBackends = new Map();
function backends() {
  const ollamaUrl = process.env.OLLAMA_URL || OLLAMA_URL;
  const andyUrl2 = process.env.ANDY_URL_2 || ANDY_URL_2;
  const urls = [[ollamaUrl, 'ollama'], ...(andyUrl2 ? [[andyUrl2, 'openai']] : [])];
  return urls.map(([url, api], index) => {
    const key = `${api}:${url}`;
    if (!modelBackends.has(key)) modelBackends.set(key, {url, api, inflight: 0, health: null});
    const backend = modelBackends.get(key);
    backend.number = index + 1;
    return backend;
  });
}

async function healthy(backend) {
  // Ollama returns 404 for /health; /api/tags is its cheap 1-second health probe.
  if (backend.number === 1 && !(process.env.ANDY_URL_2 || ANDY_URL_2)) return true;
  const now = Date.now();
  if (backend.health && now - backend.health.at < 10000) {
    backend.health.ok = await backend.health.promise;
    return backend.health.ok;
  }
  const path = backend.api === 'ollama' ? '/api/tags' : '/health';
  backend.health = {at: now, promise: fetch(`${backend.url.replace(/\/$/, '')}${path}`, {signal: AbortSignal.timeout(1000)})
    .then((res) => res.ok).catch(() => false)};
  backend.health.ok = await backend.health.promise;
  return backend.health.ok;
}

async function callModel(messages) {
  const all = backends(), available = [], unavailable = [];
  for (const backend of all) (await healthy(backend) ? available : unavailable).push(backend);
  // Backend 2 wins ties because it is the offloaded, faster GPU.
  available.sort((a, b) => a.inflight - b.inflight || b.number - a.number);
  // A cached health failure must not prevent request-level fallback after the
  // other backend errors or times out.
  unavailable.sort((a, b) => a.inflight - b.inflight || b.number - a.number);
  const candidates = available.concat(unavailable);
  const failures = [];
  for (const backend of candidates) {
    backend.inflight++;
    try {
      const data = await http('POST', `${backend.url.replace(/\/$/, '')}${backend.api === 'ollama' ? '/api/chat' : '/v1/chat/completions'}`,
        modelRequest(backend.api, {model: MODEL, messages, sampling: SAMPLING, think: THINK}));
      return {text: modelReply(backend.api, data), backend: backend.number};
    } catch (error) { failures.push(error); }
    finally { backend.inflight--; }
  }
  throw failures[0] || new Error('No healthy model backend');
}

// Every model call with its full prompt and reply: the data set for a later LoRA fine-tune. Kept at
// most ~2 x 50 MB (the current file and one rotated copy).
function logCall(line) {
  try {
    if (fs.statSync(LOG).size > 50e6) fs.renameSync(LOG, `${LOG}.1`);
  } catch {} // no file yet
  fs.appendFileSync(LOG, line);
}

// The model card's sampling for Andy-4.2 (Ollama's own defaults differ: top_k 40, top_p 0.9, repeat_penalty 1.1).
const SAMPLING = {num_ctx: 8192, temperature: 0.6, top_k: 20, top_p: 0.95, min_p: 0, repeat_penalty: 1.0};

async function think(agent, state, bot) {
  const t0 = Date.now();
  // Qwen-based models (Andy-4.2) allow one system message, first; later "system" lines
  // (job results, self-prompts) go in as user turns marked SYSTEM, as Mindcraft does for such models.
  const messages = [{role: 'system', content: agent.system(state, bot)},
    ...agent.history.map((m) => (m.role === 'system' ? {role: 'user', content: `SYSTEM: ${m.content}`} : m))];
  const out = await callModel(messages);
  agent.modelMs += Date.now() - t0;
  const text = String(out.text || '').replace(/<think>[\s\S]*?<\/think>/g, '').trim();
  if (LOG) logCall(JSON.stringify({t: new Date().toISOString(), agent: agent.name, ms: Date.now() - t0, messages, backend: out.backend, reply: text}) + '\n');
  return out;
}

async function sendJob(name, type, args, replace = false) {
  return http('POST', `${API}/api/job`, {bots: [name], type, args, replace});
}

// One decision: let the model talk until it starts an action (or gives up after MAX_QUERIES).
// Every model call takes its budget right before it starts, after the (possibly slow) state fetch.
async function decide(agent, agents, getState, budget) {
  for (let round = 0; round <= MAX_QUERIES; round++) {
    const state = await getState();
    const bot = state.bots.find((b) => b.name === agent.name);
    if (!bot?.online) return;
    while (!budget.take()) await new Promise((r) => setTimeout(r, 1000));
    const answer = await think(agent, state, bot);
    const reply = answer.text;
    agent.push('assistant', reply || '\t');
    const cmd = parseCommand(reply);
    console.log(`[${agent.name}] ${reply.slice(0, 160).replace(/\n/g, ' ')}`);
    if (TOKEN) http('POST', `${API}/api/decision`, {bot: agent.name, text: reply.slice(0, 200) || '(nothing to do)', backend: answer.backend}).catch(() => {}); // the dashboard's "Agent decisions"
    if (!cmd) return; // just talk
    const same = reply.match(COMMAND_RE)[0];
    // A foreman may gather too (the owner, 2026-10-10: bot1 stood around); idle workers still wake it every 30 s.
    if (agent.workers.size && !FOREMAN.has(cmd.name) && !GATHERING.has(cmd.name)) {
      agent.push('system', `Refused: !${cmd.name} is not one of your commands. Yours: ${[...FOREMAN, ...GATHERING].map((c) => `!${c}`).join(', ')}.`);
      continue;
    }
    if (agent.workers.size && cmd.name === 'baseStatus') {
      agent.push('system', baseStatusText(agent, state));
      continue;
    }
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
        const text = String(a[1] ?? '').toLowerCase().replace(/\W+/g, ' ').trim();
        const sent = (agent.talk.get(a[0]) || []).filter((m) => Date.now() - m.at < TALK_WINDOW_MS);
        if (!to) agent.push('system', `${a[0]} is not a bot here. Bots: ${[...agents.keys()].join(', ')}`);
        else if (to === agent) agent.push('system', 'Not sent: you cannot talk to yourself.');
        // Two agents answered "done" to each other until the whole model budget was gone (R3-3): the same
        // words twice in a row, or more than TALK_MAX messages per window, end the exchange.
        else if (sent.at(-1)?.text === text || sent.length >= TALK_MAX) agent.push('system', `Not sent: ${a[0]} already has that message, or you have talked a lot. Go on with your work.`);
        else {
          agent.talk.set(a[0], [...sent, {at: Date.now(), text}]);
          to.inbox.push(`${agent.name}: (FROM OTHER BOT)${a[1] ?? ''}`);
        }
        return;
      }
      if (t.local === 'endConversation') return;
      if (t.local === 'assign') {
        const as = assignJob(cmd, agent.workers, state, ctx.places);
        if (as.refuse) {
          agent.push('system', as.refuse);
          continue;
        }
        const done = alreadyDone(agent, as.job);
        if (done) {
          agent.push('system', done);
          continue;
        }
        try {
          await sendJob(as.worker, ...as.job, as.replace);
        } catch (e) {
          agent.push('system', `Code output: Assignment to ${as.worker} failed. ${e.message}`);
          continue;
        }
        assigner.set(as.worker, agent.name);
        noteSent(agent, as.job);
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
    if (['shaft', 'excavate'].includes(t.job[0]) && leadsGathering(agent)) {
      agent.push('system', 'Refused: you lead, you do not dig. Give it to a worker with !assign.');
      continue;
    }
    if (same !== agent.lastCommand) agent.failures = 0;
    // Andy-4.2 ignored the repeat hint and sent one failing command eight times (live 2026-10-10).
    if (same === agent.lastCommand && agent.failures >= 2) {
      agent.push('system', `Refused: ${same} failed ${agent.failures} times in a row (${agent.lastFailure || 'same error'}). Do something different.`);
      continue;
    }
    // The lead bot tried all eight base parts in a row, each failing on the same unreachable chest (lab).
    if (agent.errStreak >= 2 && t.job[0] === agent.lastErrType) {
      agent.push('system', `Refused: ${t.job[0]} jobs failed ${agent.errStreak} times in a row with the same error (${agent.lastFailure}). Fix that cause first, or do something else.`);
      continue;
    }
    // The lead bot "built" the eight finished base parts again and again (lab 2026-10-10); the model copies
    // its last command whatever the result says.
    const done = alreadyDone(agent, t.job, String(cmd.args[0]));
    if (done) {
      agent.push('system', done);
      continue;
    }
    agent.lastCommand = same;
    try {
      // A routine never ends, so a job queued behind it would never start (bot2 had two stone shifts
      // queued, live 2026-10-10): the new order replaces it, as !assign does for workers.
      await sendJob(agent.name, ...t.job, isRoutine(bot.job) || (bot.queue || []).some((label) => ROUTINES.has(String(label).split(" ")[0])));
    } catch (e) {
      agent.push('system', `Code output: Action failed. ${e.message}`);
      continue;
    }
    noteSent(agent, t.job, String(cmd.args[0]));
    return;
  }
}

// One dashboard event: job results become "Code output" lines, as Mindcraft reports them, and wake the brain.
function onEvent(agents, e) {
  // Alerts (mcbots alerts.js: supply chest gone, night, mobs at the base) go to every foreman.
  if (e.kind === 'alert') {
    for (const a of agents.values()) {
      if (!a.workers.size) continue;
      a.push('system', `ALERT: ${e.text}`);
      a.wake = true;
      a.wakeAt ||= Date.now();
    }
    return;
  }
  const boss = agents.get(assigner.get(e.bot));
  const put = boss && e.kind === 'deposit' && /^deposited (.+) at the supply chest$/.exec(e.text);
  if (put) boss.pushDeposit(`${e.bot} put ${put[1]} into the base chest`); // news, not a reason to wake
  if (boss && /^(finished|failed|gave up|stopped)/.test(e.text)) {
    noteWorker(e.bot, e.text);
    boss.last.set(e.bot, e.text);
    noteFinished(boss, e.text);
    boss.push('system', `Worker ${e.bot}: ${e.text}`);
    boss.wake = true;
    boss.wakeAt ||= Date.now();
  } else if (boss && (e.kind === 'death' || e.kind === 'respawn')) boss.push('system', `Worker ${e.bot}: ${e.text}`);
  const a = agents.get(e.bot);
  if (!a) return;
  if (e.kind === 'death' || e.kind === 'respawn') {
    a.push('system', `Event: ${e.text}`);
    a.wake = true;
    a.wakeAt ||= Date.now();
    return;
  }
  if (!/^(finished|failed|gave up|stopped)/.test(e.text)) return;
  a.push('system', `Code output:\n${e.text}`);
  noteFinished(a, e.text);
  a.failures = /^failed/.test(e.text) ? a.failures + 1 : 0;
  if (a.failures) a.lastFailure = e.text.replace(/^failed: /, '').slice(0, 160);
  trackError(a, e.text);
  if (a.failures >= 2) a.push('system', repeatHint(a.lastCommand));
  a.wake = true;
  a.wakeAt ||= Date.now();
}

async function main() {
  const spec = (process.env.AGENTS || '').split(';').map((s) => s.trim()).filter(Boolean);
  if (!spec.length) throw new Error('AGENTS must be "bot11=goal;bot12=goal"');
  const agents = new Map();
  for (const s of spec) {
    const [name, goal = ''] = s.split('=');
    agents.set(name.trim(), new Agent(name.trim(), goal.trim(), null));
  }
  for (const a of agents.values()) a.workers = workersOf(process.env, a.name, agents);
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
  // Tell the dashboard's Agents section who we are and whom we lead; failures only logged.
  const postStatus = () => {
    if (!TOKEN) return;
    for (const a of agents.values()) http('POST', `${API}/api/agentstatus`, {agent: a.name, goal: a.goal, workers: [...a.workers].slice(0, 12), role: a.workers.size ? 'foreman' : 'solo'}).catch((e) => console.error(`agentstatus failed: ${e.message}`));
  };
  postStatus();
  setInterval(postStatus, 30000).unref();
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
      for (const e of ev.events) onEvent(agents, e);
      const state = await getState();
      const now = Date.now();
      const ready = [];
      for (const agent of agents.values()) {
        if (busy.has(agent.name)) continue;
        const bot = state.bots.find((b) => b.name === agent.name);
        const idle = agent.workers.size ? idleWorkers(agent.workers, state) : [];
        if (idle.length && now - agent.lastDecisionAt > 30000) {
          agent.wake = true;
          agent.wakeAt ||= now;
        }
        const why = promptReason(agent, bot, now, CHECKIN_MS, idle.length);
        if (why) ready.push([agent, why, bot]);
      }
      ready.sort((x, y) => (x[0].wakeAt || x[0].lastDecisionAt) - (y[0].wakeAt || y[0].lastDecisionAt)); // longest waiting first
      for (const [agent, why, bot] of ready) {
        if (!budget.free(now)) break; // over the cap: the rest wait for a later tick (decide() takes the budget)
        if (why === 'message') {
          agent.afk = false;
          while (agent.inbox.length) agent.push('user', agent.inbox.shift());
        } else if (why === 'checkin') {
          agent.push('system', `Check-in: ${bot.job ? `you have been running "${bot.job.label}" for a while (use !stop first to change it)` : 'you are idle'}. Continue your goal: "${agent.goal}". If all is well reply with just a tab.`);
        } else if (why === 'workers') {
          agent.push('system', `Idle workers: ${idleWorkers(agent.workers, state).join(', ')}. Give each an order with !assign; your own action${bot.job ? ` (${bot.job.label})` : ''} keeps running.`);
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

module.exports = {SAMPLING, decide, Agent, workersOf, idleWorkers, noteWorker, trackError, parseCommand, translate, commandDocs, statsText, inventoryText, repeatHint, isRoutine, Budget, promptReason, assignJob, workersText, assigner, onEvent, baseStatusText, baseLine, noteSent, noteFinished, alreadyDone, callModel, healthy};
