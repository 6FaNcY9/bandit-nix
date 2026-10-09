#!/usr/bin/env node
'use strict';
// MCP server for the mcbots Minecraft bots (stdio, JSON-RPC 2.0, no dependencies).
// Any MCP harness (Claude Code, Hermes Agent, CrewAI, ...) can read the bots' state
// and give them jobs. Everything goes through the mcbots dashboard API, so its job
// validation, protected areas, block claims and safe digging still apply; chat
// (`say`) is not offered.
//
//   MCBOTS_API=http://127.0.0.1:8095 node tools/mcbots-mcp/server.js
//   claude mcp add mcbots -e MCBOTS_API=http://127.0.0.1:8095 -- node tools/mcbots-mcp/server.js
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');

const API = (process.env.MCBOTS_API || 'http://127.0.0.1:8095').replace(/\/$/, '');
const BLUEPRINTS = process.env.BLUEPRINTS || path.join(__dirname, '../../hosts/bandit-lab/services/mcbots/blueprints');
const VERSION = '0.1.0';

const int = (d) => ({type: 'integer', description: d});
const str = (d) => ({type: 'string', description: d});
const xyz = {x: int('x'), y: int('y'), z: int('z')};
const bot = {bot: str('Bot name, e.g. bot1')};

// name -> [description, properties, required, (args) => [jobType, jobArgs] | null for non-job tools]
const TOOLS = {
  mc_state: ['All bots (online, position, health, food, activity, job, queue, inventory, last error), the supply chest and map places.', {}, [], null],
  mc_events: ['Recent bot events (job started/finished/failed, deaths, deposits). Pass the last id you saw to get only newer ones.', {since: int('Last event id seen (0 for all)')}, [], null],
  mc_blueprints: ['Saved blueprints that mc_build can place.', {}, [], null],
  mc_goto: ['Walk to x y z.', {...bot, ...xyz}, ['bot', 'x', 'y', 'z'], (a) => ['goto', {x: a.x, y: a.y, z: a.z}]],
  mc_come: ['Walk to a player.', {...bot, player: str('Player name')}, ['bot', 'player'], (a) => ['come', {player: a.player}]],
  mc_follow: ['Follow a player until stopped.', {...bot, player: str('Player name')}, ['bot', 'player'], (a) => ['follow', {player: a.player}]],
  mc_mine: ['Mine a number of blocks of one type nearby (ores at their best height). Cobblestone comes from "stone".', {...bot, block: str('Block name, e.g. stone, iron_ore'), count: int('How many')}, ['bot', 'block', 'count'], (a) => ['mine', {block: a.block, count: a.count}]],
  mc_chop: ['Chop a number of logs nearby (any wood type).', {...bot, count: int('How many logs')}, ['bot', 'count'], (a) => ['chop', {count: a.count}]],
  mc_shift: ['Work shift: mine a block (or "logs") until stopped, depositing into the chest at x y z when full.', {...bot, block: str('Block name or "logs"'), ...xyz}, ['bot', 'block', 'x', 'y', 'z'], (a) => ['shift', {block: a.block, x: a.x, y: a.y, z: a.z}]],
  mc_deposit: ['Put items into the chest at x y z (everything except tools/food/crafting stock, or only one kind).', {...bot, ...xyz, only: str('Optional: only this item, "logs" or "coal"')}, ['bot', 'x', 'y', 'z'], (a) => ['deposit', {x: a.x, y: a.y, z: a.z, ...(a.only ? {only: a.only} : {})}]],
  mc_withdraw: ['Take items out of the chest at x y z.', {...bot, item: str('Item name or "logs"'), count: int('How many'), ...xyz}, ['bot', 'item', 'count', 'x', 'y', 'z'], (a) => ['withdraw', {item: a.item, count: a.count, x: a.x, y: a.y, z: a.z}]],
  mc_craft: ['Craft items (makes a crafting table and intermediates when needed).', {...bot, item: str('Item name'), count: int('How many (max 64)')}, ['bot', 'item', 'count'], (a) => ['craft', {item: a.item, count: a.count}]],
  mc_smelt: ['Smelt items in a furnace.', {...bot, item: str('Input item, e.g. raw_iron'), count: int('How many (max 64)')}, ['bot', 'item', 'count'], (a) => ['smelt', {item: a.item, count: a.count}]],
  mc_place: ['Place one block (chest, crafting table, ...) at x y z on a solid block.', {...bot, item: str('Block name'), ...xyz}, ['bot', 'item', 'x', 'y', 'z'], (a) => ['place', {item: a.item, x: a.x, y: a.y, z: a.z}]],
  mc_guard: ['Guard a spot (x y z) or a player: fight hostile mobs within the radius until stopped.', {...bot, ...xyz, player: str('Player to guard instead of a spot'), radius: int('4-48, default 16')}, ['bot'], (a) => ['guard', {...(a.player ? {player: a.player} : {x: a.x, y: a.y, z: a.z}), ...(a.radius ? {radius: a.radius} : {})}]],
  mc_build: ['Build a saved blueprint with its origin at x y z (floor level, one above the ground); remove=true digs it back out. Missing blocks come from the supply chest.', {...bot, blueprint: str('Blueprint name from mc_blueprints'), ...xyz, remove: {type: 'boolean', description: 'Dig the blueprint back out'}}, ['bot', 'blueprint', 'x', 'y', 'z'], null],
  mc_stop: ['Stop a bot (or "all"): clears its queue and current job.', {...bot}, ['bot'], () => ['stop', {}]],
};

function toolList() {
  return Object.entries(TOOLS).map(([name, [description, properties, required]]) => ({name, description, inputSchema: {type: 'object', properties, required}}));
}

async function api(method, p, body) {
  const res = await fetch(API + p, {method, headers: body ? {'Content-Type': 'application/json', Origin: new URL(API).origin} : {}, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000)});
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

function blueprints() {
  try {
    return fs.readdirSync(BLUEPRINTS).filter((f) => f.endsWith('.json')).map((f) => {
      const bp = JSON.parse(fs.readFileSync(path.join(BLUEPRINTS, f), 'utf8'));
      return {name: f.slice(0, -5), blocks: bp.blocks?.length || 0, description: bp.description || ''};
    });
  } catch {
    return [];
  }
}

function slimState(s) {
  return {
    bots: s.bots.map((b) => ({name: b.name, online: b.online, pos: b.pos, health: b.health, food: b.food, activity: b.activity, job: b.job?.label || null, progress: b.job?.progress || null, queue: b.queue, inventory: b.inventory, freeSlots: b.freeSlots, lastError: b.lastError || null})),
    supplyChest: s.supplyChest || null,
    places: (s.places || []).map((p) => ({name: p.name, kind: p.kind, x: p.x, y: p.y, z: p.z})),
    players: (s.world?.players || []).map((p) => ({name: p.name, x: Math.round(p.x), y: Math.round(p.y), z: Math.round(p.z), dim: p.dim})),
  };
}

async function callTool(name, a = {}) {
  const t = TOOLS[name];
  if (!t) throw new Error(`unknown tool ${name}`);
  for (const k of t[2]) if (a[k] === undefined || a[k] === '') throw new Error(`missing argument: ${k}`);
  if (name === 'mc_state') return slimState(await api('GET', '/api/state'));
  if (name === 'mc_events') return api('GET', `/api/events?since=${Number(a.since) || 0}`);
  if (name === 'mc_blueprints') return blueprints();
  let job;
  if (name === 'mc_build') {
    const file = path.join(BLUEPRINTS, `${path.basename(String(a.blueprint))}.json`);
    if (!fs.existsSync(file)) throw new Error(`no blueprint "${a.blueprint}"; see mc_blueprints`);
    const bp = JSON.parse(fs.readFileSync(file, 'utf8'));
    job = ['build', {origin: {x: a.x, y: a.y, z: a.z}, blocks: bp.blocks, ...(a.remove ? {remove: true} : {})}];
  } else {
    job = t[3](a);
  }
  const bots = a.bot === 'all' ? 'all' : [String(a.bot)];
  await api('POST', '/api/job', {bots, type: job[0], args: job[1], replace: name === 'mc_stop'});
  return {ok: true, queued: `${job[0]} for ${a.bot}`, hint: 'mc_state shows progress; mc_events shows the result'};
}

// ---- JSON-RPC over stdio (one message per line) ----------------------------------
function reply(id, result, error) {
  process.stdout.write(JSON.stringify(error ? {jsonrpc: '2.0', id, error} : {jsonrpc: '2.0', id, result}) + '\n');
}

async function handle(msg) {
  const {id, method, params = {}} = msg;
  if (id === undefined) return; // notification (e.g. notifications/initialized)
  try {
    if (method === 'initialize') {
      return reply(id, {protocolVersion: params.protocolVersion || '2025-06-18', capabilities: {tools: {}}, serverInfo: {name: 'mcbots', version: VERSION}});
    }
    if (method === 'ping') return reply(id, {});
    if (method === 'tools/list') return reply(id, {tools: toolList()});
    if (method === 'tools/call') {
      try {
        const out = await callTool(params.name, params.arguments || {});
        return reply(id, {content: [{type: 'text', text: JSON.stringify(out, null, 1)}]});
      } catch (e) {
        return reply(id, {content: [{type: 'text', text: e.message}], isError: true});
      }
    }
    return reply(id, null, {code: -32601, message: `method not found: ${method}`});
  } catch (e) {
    return reply(id, null, {code: -32603, message: e.message});
  }
}

if (require.main === module) {
  readline.createInterface({input: process.stdin}).on('line', (line) => {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      return reply(null, null, {code: -32700, message: 'parse error'});
    }
    handle(msg);
  });
}

module.exports = {toolList, callTool, TOOLS};
