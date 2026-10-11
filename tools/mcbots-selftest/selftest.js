#!/usr/bin/env node
'use strict';
// mcbots self-test: runs every job primitive on bot10 in the SANDBOX server and verifies the result by
// world / inventory state (never by the job's own "done" text). Usage: node selftest.js [testName...]
// Needs: tailnet access to the dashboard, `ssh bandit-lab` (docker exec on the container minecraft-sandbox ONLY).
const {execFile} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const B = process.env.MCBOTS_URL || 'https://bandit-lab.tail7facc9.ts.net:8445';
const BOT = 'bot10';
const CONTAINER = 'minecraft-sandbox'; // never anything else: `minecraft` is the real server
const CX = 3000, CZ = 3000, FLOOR = 64, R = 20; // test site: stone slab y 30..64, air above, x/z CX/CZ +- R
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const SSH = ['-o', 'ControlMaster=auto', '-o', `ControlPath=${path.join(os.tmpdir(), 'mcst-%C')}`, '-o', 'ControlPersist=300'];

function rcon(cmd) {
  if (cmd.includes("'")) throw new Error(`no single quotes in rcon commands: ${cmd}`);
  return new Promise((res, rej) => {
    execFile('ssh', [...SSH, 'bandit-lab', `docker exec ${CONTAINER} rcon-cli '${cmd}'`], {timeout: 60000}, (e, out, err) => {
      if (e) return rej(new Error(`rcon failed (${cmd}): ${e.message} ${err}`));
      res(out.replace(/\x1b\[[0-9;]*m/g, '').trim());
    });
  });
}
const api = async (p, init) => {
  const r = await fetch(B + p, init);
  return {status: r.status, body: await r.json().catch(() => ({}))};
};
const postJob = (body) => api('/api/job', {method: 'POST', headers: {'Content-Type': 'application/json', Origin: B}, body: JSON.stringify(body)});
const botState = async () => (await api('/api/state')).body.bots?.find((b) => b.name === BOT);

// fill in <=32768-block pieces; returns the number of blocks changed
async function box(x1, y1, z1, x2, y2, z2, block, extra = '') {
  const d = [x2 - x1, y2 - y1, z2 - z1];
  if ((d[0] + 1) * (d[1] + 1) * (d[2] + 1) > 32768) {
    const i = d.indexOf(Math.max(...d)), lo = [x1, y1, z1], hi = [x2, y2, z2], m = lo[i] + (d[i] >> 1);
    const a = [...hi]; a[i] = m;
    const b = [...lo]; b[i] = m + 1;
    return (await box(...lo, ...a, block, extra)) + (await box(...b, ...hi, block, extra));
  }
  const out = await rcon(`fill ${x1} ${y1} ${z1} ${x2} ${y2} ${z2} ${block} ${extra}`.trim());
  return Number(/filled (\d+)/.exec(out)?.[1] || 0);
}
// number of `block` blocks in a box (destructive: they become barrier, so call it last)
const countBlocks = (x1, y1, z1, x2, y2, z2, block) => box(x1, y1, z1, x2, y2, z2, 'minecraft:barrier', `replace ${block}`);
const isBlock = async (x, y, z, block) => /Test passed/.test(await rcon(`execute if block ${x} ${y} ${z} ${block}`));
const have = async (item) => Number(/Found (\d+)/.exec(await rcon(`clear ${BOT} ${item.startsWith('#') ? item : 'minecraft:' + item} 0`))?.[1] || 0);
const pos = async () => (await rcon(`data get entity ${BOT} Pos`)).match(/-?\d+\.\d+(?=d)/g).map(Number);
const chestCount = async (x, y, z, item) => Number(/: (\d+)$/.exec(await rcon(`data get block ${x} ${y} ${z} Items[{id:"minecraft:${item}"}].count`))?.[1] || 0);

async function resetSite() {
  await box(CX - R, 30, CZ - R, CX + R, FLOOR, CZ + R, 'minecraft:stone');
  await box(CX - R, FLOOR + 1, CZ - R, CX + R, FLOOR + 46, CZ + R, 'minecraft:air');
  await rcon(`kill @e[type=!player,x=${CX},y=${FLOOR},z=${CZ},distance=..70]`);
}

// stop whatever bot10 does and wait until it is idle
async function idle() {
  await postJob({bots: [BOT], type: 'stop'});
  for (let i = 0; i < 20; i++) {
    const s = await botState();
    if (s && !s.job && !(s.queue || []).length) return;
    await sleep(1000);
  }
}

async function prep({inv = [], at = [CX, FLOOR + 1, CZ], setup} = {}) {
  const s = await botState();
  if (!s?.online) throw new Error(`${BOT} is not online`);
  await idle();
  await rcon('time set day');
  await rcon('weather clear');
  await resetSite();
  await rcon(`clear ${BOT}`);
  await rcon(`tp ${BOT} ${at.join(' ')}`);
  await rcon(`effect give ${BOT} minecraft:resistance 600 4 true`);
  await rcon(`effect give ${BOT} minecraft:instant_health 1 10 true`);
  await rcon(`effect give ${BOT} minecraft:saturation 10 5 true`);
  for (const [item, n] of inv) await rcon(`give ${BOT} minecraft:${item} ${n}`);
  if (setup) await setup();
  await sleep(3000); // chunks to the bot, entities settled
}

// Post a job and wait for bot10's done/fail event. `until` (async -> bool) ends the wait early by stopping the job.
async function job(type, args, {timeout = 180000, until} = {}) {
  const t0 = Date.now();
  let since = (await api('/api/events?since=0')).body.lastId || 0;
  const r = await postJob({bots: [BOT], type, args});
  if (r.status !== 200) return {status: 'rejected', text: r.body.error || `HTTP ${r.status}`, ms: Date.now() - t0, events: []};
  const events = [];
  let status = null, text = '';
  const stop = async () => { await postJob({bots: [BOT], type: 'stop'}); await sleep(2500); };
  while (!status) {
    await sleep(1500);
    const e = (await api(`/api/events?since=${since}`)).body;
    since = e.lastId ?? since;
    for (const ev of e.events || []) {
      if (ev.bot !== BOT) continue;
      events.push(`${ev.kind}: ${ev.text}`);
      if (ev.kind === 'done' || ev.kind === 'fail') { status = ev.kind; text = ev.text; }
    }
    if (status) break;
    if (until && await until().catch(() => false)) { status = 'until'; await stop(); break; }
    if (Date.now() - t0 > timeout) { status = 'timeout'; await stop(); break; }
  }
  return {status, text, ms: Date.now() - t0, events: events.slice(-12)};
}

// ---------------------------------------------------------------- tests
const P = (x, y, z) => `${x} ${y} ${z}`;
const TESTS = [];
const test = (name, opts, fn) => TESTS.push({name, ...(typeof opts === 'function' ? {fn: opts} : {opts, fn})});
const near = (p, x, y, z, d, dy = 2) => Math.hypot(p[0] - x, p[2] - z) <= d && Math.abs(p[1] - y) <= dy;
const fmt = (p) => p.map((n) => n.toFixed(1)).join(',');

test('goto_flat', async (t) => {
  await t.prep({at: [CX - 15, 65, CZ]});
  const p0 = await pos();
  t.job = await job('goto', {x: CX + 15, y: 65, z: CZ});
  const p = await pos();
  t.check('moved 30 blocks to target', near(p, CX + 15, 65, CZ, 2.5), `start ${fmt(p0)} end ${fmt(p)}`);
});

test('goto_out_of_pit', async (t) => {
  await t.prep({inv: [['cobblestone', 32], ['iron_pickaxe', 1]], at: [CX, 59, CZ], setup: async () => {
    await box(CX - 1, 59, CZ - 1, CX + 1, 64, CZ + 1, 'minecraft:air'); // 3x3 pit, 6 deep (floor y 58)
  }});
  t.job = await job('goto', {x: CX + 8, y: 65, z: CZ});
  const p = await pos();
  t.check('out of the pit, at the target on the surface', near(p, CX + 8, 65, CZ, 2.5) && p[1] >= 64.9, `end ${fmt(p)}`);
});

test('goto_up_shaft', async (t) => {
  await t.prep({inv: [['cobblestone', 64], ['iron_pickaxe', 1]], at: [CX, 65, CZ], setup: async () => {
    // 3x3 open shaft, walls of stone around it up to y 90; bot at its bottom, target 15 above
    await box(CX - 2, 65, CZ - 2, CX + 2, 90, CZ + 2, 'minecraft:stone');
    await box(CX - 1, 65, CZ - 1, CX + 1, 90, CZ + 1, 'minecraft:air');
  }});
  t.job = await job('goto', {x: CX, y: 80, z: CZ});
  const p = await pos();
  t.check('bot at y~80 inside the shaft', near(p, CX, 80, CZ, 2.5, 1.5), `end ${fmt(p)}`);
});

test('mine_stone', async (t) => {
  await t.prep({inv: [['wooden_pickaxe', 1]]});
  t.job = await job('mine', {block: 'stone', count: 5});
  const n = await have('cobblestone');
  t.check('>=5 cobblestone in inventory', n >= 5, `cobblestone=${n}`);
});

// iron_ore only counts inside its band (y 0..40, bots.js ORE_BAND): a staircase ramp leads from the surface down to y 40
// where two iron ore blocks sit in the end wall. The bot starts at the ramp's top.
const ironSetup = (table) => async () => {
  for (let k = 0; k <= 24; k++) await box(CX - 18 + k, 64 - k, CZ, CX - 18 + k, 66 - k, CZ, 'minecraft:air');
  await rcon(`setblock ${CX + 7} 40 ${CZ} minecraft:iron_ore`);
  await rcon(`setblock ${CX + 7} 41 ${CZ} minecraft:iron_ore`);
  if (table) await rcon(`setblock ${CX - 17} 66 ${CZ + 1} minecraft:crafting_table`);
};
const IRON_AT = [CX - 18, 65, CZ];
test('mine_iron_upgrade', {timeout: 240000}, async (t) => {
  await t.prep({at: IRON_AT, inv: [['wooden_pickaxe', 1], ['cobblestone', 10], ['stick', 4]], setup: ironSetup(false)});
  t.job = await job('mine', {block: 'iron_ore', count: 2}, {timeout: 240000});
  const n = await have('raw_iron');
  t.check('>=2 raw_iron (bot made itself a stone pickaxe, no table around)', n >= 2, `raw_iron=${n} stone_pickaxe=${await have('stone_pickaxe')}`);
});
test('mine_iron_upgrade_table', {timeout: 240000}, async (t) => {
  await t.prep({at: IRON_AT, inv: [['wooden_pickaxe', 1], ['cobblestone', 10], ['stick', 4]], setup: ironSetup(true)});
  t.job = await job('mine', {block: 'iron_ore', count: 2}, {timeout: 240000});
  const n = await have('raw_iron');
  t.check('>=2 raw_iron (crafting table 2 blocks away)', n >= 2, `raw_iron=${n} stone_pickaxe=${await have('stone_pickaxe')}`);
});

test('mine_iron_upgrade_planks', {timeout: 240000}, async (t) => {
  await t.prep({at: IRON_AT, inv: [['wooden_pickaxe', 1], ['cobblestone', 10], ['stick', 4], ['oak_planks', 4]], setup: ironSetup(false)});
  t.job = await job('mine', {block: 'iron_ore', count: 2}, {timeout: 240000});
  const n = await have('raw_iron');
  t.check('>=2 raw_iron (4 planks in inventory for a table)', n >= 2, `raw_iron=${n} stone_pickaxe=${await have('stone_pickaxe')}`);
});

test('chop', async (t) => {
  await t.prep({setup: async () => {
    await box(CX + 4, 68, CZ - 2, CX + 8, 71, CZ + 2, 'minecraft:oak_leaves[persistent=true]');
    await box(CX + 6, 65, CZ, CX + 6, 70, CZ, 'minecraft:oak_log');
  }});
  t.job = await job('chop', {count: 3});
  const n = await have('#minecraft:logs');
  t.check('>=3 logs in inventory', n >= 3, `logs=${n}`);
});

test('craft_stick', async (t) => {
  await t.prep({inv: [['oak_planks', 2]]});
  t.job = await job('craft', {item: 'stick', count: 4});
  const n = await have('stick');
  t.check('>=4 sticks', n >= 4, `sticks=${n} planks left=${await have('oak_planks')}`);
});
test('craft_planks', async (t) => {
  await t.prep({inv: [['oak_log', 2]]});
  t.job = await job('craft', {item: 'oak_planks', count: 4});
  const n = await have('oak_planks');
  t.check('>=4 oak_planks', n >= 4, `planks=${n}`);
});
test('craft_torch', async (t) => {
  await t.prep({inv: [['coal', 1], ['stick', 1]]});
  t.job = await job('craft', {item: 'torch', count: 4});
  const n = await have('torch');
  t.check('>=4 torches', n >= 4, `torches=${n}`);
});
test('craft_crafting_table', async (t) => {
  await t.prep({inv: [['oak_planks', 4]]});
  t.job = await job('craft', {item: 'crafting_table', count: 1});
  const n = await have('crafting_table');
  t.check('crafting_table in inventory', n >= 1, `crafting_table=${n}`);
});
test('craft_stone_pickaxe', async (t) => {
  await t.prep({inv: [['cobblestone', 3], ['stick', 2], ['oak_planks', 4]]});
  t.job = await job('craft', {item: 'stone_pickaxe', count: 1});
  const n = await have('stone_pickaxe');
  t.check('stone_pickaxe in inventory (no table nearby, planks to make one)', n >= 1, `stone_pickaxe=${n}`);
});

test('craft_stone_pickaxe_table', async (t) => {
  await t.prep({inv: [['cobblestone', 3], ['stick', 2]], setup: async () => { await rcon(`setblock ${CX + 2} 65 ${CZ} minecraft:crafting_table`); }});
  t.job = await job('craft', {item: 'stone_pickaxe', count: 1});
  const n = await have('stone_pickaxe');
  t.check('stone_pickaxe in inventory (table 2 blocks away)', n >= 1, `stone_pickaxe=${n}`);
});
test('craft_wooden_pickaxe_planks', async (t) => {
  await t.prep({inv: [['oak_planks', 8], ['stick', 2]]});
  t.job = await job('craft', {item: 'wooden_pickaxe', count: 1});
  const n = await have('wooden_pickaxe');
  t.check('wooden_pickaxe in inventory (8 planks, bot builds its own table)', n >= 1, `wooden_pickaxe=${n} planks=${await have('oak_planks')} table=${await have('crafting_table')}`);
});

test('smelt_no_furnace', {timeout: 240000}, async (t) => {
  await t.prep({inv: [['raw_iron', 2], ['coal', 3], ['cobblestone', 8], ['oak_planks', 4]]});
  t.job = await job('smelt', {item: 'raw_iron', count: 2}, {timeout: 240000});
  const n = await have('iron_ingot');
  t.check('2 iron_ingot (bot had to make a table and furnace)', n >= 2, `iron_ingot=${n} raw_iron=${await have('raw_iron')}`);
});
test('smelt_with_furnace', {timeout: 240000}, async (t) => {
  await t.prep({inv: [['raw_iron', 2], ['coal', 3]], setup: async () => { await rcon(`setblock ${CX + 2} 65 ${CZ} minecraft:furnace`); }});
  t.job = await job('smelt', {item: 'raw_iron', count: 2}, {timeout: 240000});
  const n = await have('iron_ingot');
  t.check('2 iron_ingot (furnace 2 blocks away)', n >= 2, `iron_ingot=${n} raw_iron=${await have('raw_iron')}`);
});

test('deposit', async (t) => {
  const c = [CX + 6, 65, CZ - 2];
  await t.prep({inv: [['cobblestone', 20], ['dirt', 10], ['wooden_pickaxe', 1]], setup: async () => { await rcon(`setblock ${P(...c)} minecraft:chest`); }});
  t.job = await job('deposit', {x: c[0], y: c[1], z: c[2]});
  const inChest = await chestCount(...c, 'cobblestone');
  t.check('cobblestone in chest', inChest === 20, `chest cobblestone=${inChest} dirt=${await chestCount(...c, 'dirt')}`);
  t.check('bot keeps pickaxe, lost cobblestone', (await have('wooden_pickaxe')) === 1 && (await have('cobblestone')) === 0, `pick=${await have('wooden_pickaxe')} cobble=${await have('cobblestone')}`);
});

test('withdraw', async (t) => {
  const c = [CX + 6, 65, CZ - 2];
  await t.prep({setup: async () => { await rcon(`setblock ${P(...c)} minecraft:chest{Items:[{Slot:0b,id:"minecraft:coal",count:16}]}`); }});
  t.job = await job('withdraw', {item: 'coal', count: 10, x: c[0], y: c[1], z: c[2]});
  const got = await have('coal'), left = await chestCount(...c, 'coal');
  t.check('10 coal in inventory, 6 left in chest', got === 10 && left === 6, `inventory coal=${got} chest coal=${left}`);
});

test('place_cobblestone', async (t) => {
  await t.prep({inv: [['cobblestone', 1]]});
  t.job = await job('place', {item: 'cobblestone', x: CX + 3, y: 65, z: CZ + 3});
  t.check('cobblestone at target', await isBlock(CX + 3, 65, CZ + 3, 'minecraft:cobblestone'), 'block check');
});
test('place_crafting_table', async (t) => {
  await t.prep({inv: [['crafting_table', 1]]});
  t.job = await job('place', {item: 'crafting_table', x: CX + 3, y: 65, z: CZ + 3});
  t.check('crafting_table at target', await isBlock(CX + 3, 65, CZ + 3, 'minecraft:crafting_table'), 'block check');
});

test('tidy', async (t) => {
  await t.prep({setup: async () => {
    await rcon(`summon minecraft:item ${CX + 4} 65 ${CZ} {Item:{id:"minecraft:cobblestone",count:5}}`);
    await rcon(`summon minecraft:item ${CX - 4} 65 ${CZ + 4} {Item:{id:"minecraft:dirt",count:3}}`);
    await rcon(`summon minecraft:item ${CX} 65 ${CZ - 7} {Item:{id:"minecraft:coal",count:2}}`);
  }});
  const all = async () => (await have('cobblestone')) >= 5 && (await have('dirt')) >= 3 && (await have('coal')) >= 2;
  // the job then walks to the base supply chest (4000 blocks away): stop it as soon as everything is picked up
  t.job = await job('tidy', {x: CX, y: 65, z: CZ, radius: 12}, {until: all});
  const inv = `cobble=${await have('cobblestone')} dirt=${await have('dirt')} coal=${await have('coal')}`;
  const left = await rcon(`kill @e[type=item,x=${CX},y=65,z=${CZ},distance=..20]`);
  t.check('all 3 stacks picked up, none left on the ground', (await all()) && /No entity/.test(left), `${inv}; ground: ${left}`);
});

test('hunt_sheep', {timeout: 240000}, async (t) => {
  await t.prep({inv: [['stone_sword', 1]], setup: async () => {
    for (const [dx, dz] of [[6, 6], [8, 5], [7, 8]]) await rcon(`summon minecraft:sheep ${CX + dx} 65 ${CZ + dz} {PersistenceRequired:1b}`);
  }});
  t.job = await job('hunt', {animal: 'sheep', count: 2, x: CX + 7, y: 65, z: CZ + 6, radius: 16}, {timeout: 240000});
  const meat = await have('mutton'), wool = await have('#minecraft:wool');
  const left = await rcon(`kill @e[type=sheep,x=${CX},y=65,z=${CZ},distance=..40]`);
  t.check('mutton+wool picked up, <=1 sheep left of 3', meat >= 1 && wool >= 1 && (/Killed (\d+)/.exec(left)?.[1] || 0) <= 1, `mutton=${meat} wool=${wool}; remaining: ${left}`);
});

test('guard', {timeout: 150000}, async (t) => {
  // guard only walks to the mob; the hitting is combat.js, which needs settings.defend, a sword and 2 armour pieces
  const was = (await botState()).settings?.defend;
  const setDefend = (v) => api('/api/settings', {method: 'POST', headers: {'Content-Type': 'application/json', Origin: B}, body: JSON.stringify({bot: BOT, settings: {defend: v}})});
  await setDefend(true);
  try {
    await t.prep({inv: [['stone_sword', 1], ['iron_helmet', 1], ['iron_chestplate', 1]], setup: async () => {
      await rcon(`summon minecraft:husk ${CX + 10} 65 ${CZ} {PersistenceRequired:1b}`);
    }});
    const gone = async () => /Test failed/.test(await rcon(`execute if entity @e[type=husk,x=${CX},y=65,z=${CZ},distance=..40]`));
    t.job = await job('guard', {x: CX, y: 65, z: CZ, radius: 16}, {timeout: 150000, until: gone});
    t.check('husk killed (defend on, sword + 2 armour)', await gone(), 'entity query');
  } finally { await setDefend(was ?? false); }
});

test('excavate', {timeout: 300000}, async (t) => {
  await t.prep({inv: [['iron_pickaxe', 1]]});
  const b = [CX - 2, 62, CZ - 2, CX + 2, 64, CZ + 2];
  t.job = await job('excavate', {x1: b[0], y1: b[1], z1: b[2], x2: b[3], y2: b[4], z2: b[5]}, {timeout: 300000});
  const air = await countBlocks(...b, 'minecraft:air');
  t.check('room 5x5x3 is all air (75)', air === 75, `air blocks=${air}/75`);
});

test('shaft', {timeout: 420000}, async (t) => {
  await t.prep({inv: [['iron_pickaxe', 1], ['cobblestone', 64]], at: [CX, 65, CZ - 4]});
  const b = {x1: CX - 2, z1: CZ - 2, x2: CX + 1, z2: CZ + 1, top: 64, bottom: 52};
  t.job = await job('shaft', b, {timeout: 420000});
  const bottom = await countBlocks(b.x1, 52, b.z1, b.x2, 52, b.z2, 'minecraft:air');
  const all = await countBlocks(b.x1, 53, b.z1, b.x2, 64, b.z2, 'minecraft:air');
  t.check('bottom layer (y52) dug (>=12 of 16 air; one stair step may remain)', bottom >= 12, `bottom air=${bottom}/16`);
  t.check('layers y53..64 mostly open (>=150 of 192)', all >= 150, `air=${all}/192`);
});

test('level', {timeout: 300000}, async (t) => {
  await t.prep({inv: [['iron_pickaxe', 1], ['cobblestone', 32]], at: [CX, 53, CZ], setup: async () => {
    await box(CX - 2, 52, CZ - 2, CX + 1, 64, CZ + 1, 'minecraft:air'); // an open shaft, floor y 51
  }});
  const b = {x1: CX - 2, z1: CZ - 2, x2: CX + 1, z2: CZ + 1, top: 64, bottom: 52};
  t.job = await job('level', {...b, y: 55, length: 8, branch: 0}, {timeout: 300000});
  const air = await countBlocks(CX - 18, 55, CZ - 18, CX + 18, 56, CZ + 18, 'minecraft:air');
  t.check('tunnel dug outside the shaft at y55-56 (shaft itself = 32 air)', air >= 32 + 8, `air at y55..56 = ${air}`);
});

test('rim', {timeout: 240000}, async (t) => {
  await t.prep({inv: [['cobblestone_wall', 64]]});
  const b = {x1: CX - 2, z1: CZ - 2, x2: CX + 1, z2: CZ + 1, top: 64, bottom: 52};
  t.job = await job('rim', b, {timeout: 240000});
  const n = await countBlocks(CX - 3, 65, CZ - 3, CX + 2, 65, CZ + 2, 'minecraft:cobblestone_wall');
  t.check('wall ring around the shaft with a deliberate entrance gap (14 of 20 cells: the gap is the 2 stair-step neighbourhoods)', n === 14, `walls=${n} (ring=20)`);
});

test('build', async (t) => {
  await t.prep({inv: [['cobblestone', 3]]});
  const o = {x: CX + 3, y: 65, z: CZ + 3};
  t.job = await job('build', {origin: o, blocks: [0, 1, 2].map((x) => ({x, y: 0, z: 0, block: 'cobblestone'}))});
  const n = await countBlocks(o.x, 65, o.z, o.x + 2, 65, o.z, 'minecraft:cobblestone');
  t.check('3 cobblestone placed in a row', n === 3, `cobblestone=${n}/3`);
});

test('shift', {timeout: 240000}, async (t) => {
  const c = [CX + 6, 65, CZ - 2];
  // 35 of 36 slots full: 10 foods (a deposit keeps them), the pickaxe, 24 junk kinds (fit the 27-slot chest with the mined cobblestone)
  const junk = ['dirt', 'gravel', 'sand', 'red_sand', 'clay', 'spruce_planks', 'birch_planks', 'jungle_planks', 'acacia_planks', 'dark_oak_planks', 'mangrove_planks', 'cherry_planks', 'netherrack', 'andesite', 'diorite', 'granite', 'tuff', 'deepslate', 'calcite', 'mud', 'snow_block', 'sandstone', 'terracotta', 'bricks'];
  const food = ['bread', 'apple', 'carrot', 'cooked_beef', 'cooked_porkchop', 'baked_potato', 'cooked_mutton', 'cooked_chicken', 'cooked_cod', 'cooked_salmon'];
  await t.prep({inv: [['iron_pickaxe', 1], ...food.map((j) => [j, 8]), ...junk.map((j) => [j, 64])], setup: async () => { await rcon(`setblock ${P(...c)} minecraft:chest`); }});
  t.job = await job('shift', {block: 'stone', x: c[0], y: c[1], z: c[2]}, {timeout: 240000, until: async () => (await chestCount(...c, 'dirt')) > 0 && (await have('cobblestone')) >= 5});
  const n = await chestCount(...c, 'dirt');
  t.check('full inventory emptied into the chest (junk in chest, food kept) and stone mined (cobblestone in inventory)', n > 0 && (await have('cobblestone')) >= 5 && (await have('bread')) === 8, `chest dirt=${n}, inventory cobblestone=${await have('cobblestone')} bread=${await have('bread')}`);
});

test('say', async (t) => {
  await t.prep();
  const word = `selftest${Date.now() % 100000}`;
  t.job = await job('say', {text: word});
  const logs = await new Promise((res) => execFile('ssh', [...SSH, 'bandit-lab', `docker logs --since 60s ${CONTAINER} 2>&1`], (e, out) => res(out || '')));
  t.check('chat line in the server log', logs.includes(word), `looked for ${word}`);
});

// ---------------------------------------------------------------- runner
async function main() {
  const want = process.argv.slice(2);
  const todo = want.length ? TESTS.filter((x) => want.includes(x.name)) : TESTS;
  if (!todo.length) { console.log('no such test; known:', TESTS.map((x) => x.name).join(' ')); process.exit(2); }
  const s0 = await botState();
  if (!s0?.online) { console.error(`${BOT} is offline`); process.exit(2); }
  const home = await pos();
  await rcon(`forceload add ${CX - 32} ${CZ - 32} ${CX + 32} ${CZ + 32}`);
  await sleep(4000);
  const results = [];
  const t0 = Date.now();
  try {
    for (const tc of todo) {
      const t = {prep, check(desc, ok, detail) { (this.checks ||= []).push({desc, ok: !!ok, detail}); }, checks: [], job: null};
      const started = Date.now();
      let error = null;
      try { await tc.fn(t); } catch (e) { error = e.message; }
      const pass = !error && t.checks.length > 0 && t.checks.every((c) => c.ok);
      results.push({name: tc.name, pass, seconds: Math.round((Date.now() - started) / 1000), job: t.job && {status: t.job.status, text: t.job.text, seconds: Math.round(t.job.ms / 1000), events: t.job.events}, checks: t.checks, error});
      const r = results.at(-1);
      console.log(`${pass ? 'PASS' : 'FAIL'} ${tc.name.padEnd(24)} ${String(r.seconds).padStart(4)}s  job=${r.job?.status}  ${t.checks.map((c) => c.detail).join(' | ')}${error ? ' ERROR ' + error : ''}`);
    }
  } finally {
    await idle().catch(() => {});
    await rcon(`clear ${BOT}`).catch(() => {});
    await rcon(`tp ${BOT} ${home.map((n) => n.toFixed(1)).join(' ')}`).catch(() => {});
    await rcon(`forceload remove ${CX - 32} ${CZ - 32} ${CX + 32} ${CZ + 32}`).catch(() => {});
  }
  fs.writeFileSync(path.join(__dirname, 'last-run.json'), JSON.stringify({at: new Date().toISOString(), seconds: Math.round((Date.now() - t0) / 1000), results}, null, 2));
  console.log(`\n${results.filter((x) => x.pass).length}/${results.length} passed in ${Math.round((Date.now() - t0) / 1000)}s`);
  console.log('\n| test | result | s | job said | evidence |\n|---|---|---|---|---|');
  for (const r of results) console.log(`| ${r.name} | ${r.pass ? 'PASS' : 'FAIL'} | ${r.seconds} | ${r.job?.status}: ${(r.job?.text || '').slice(0, 150)} | ${r.checks.map((c) => c.detail).join('; ').slice(0, 110)}${r.error ? ' ERROR ' + r.error : ''} |`);
  process.exit(results.every((x) => x.pass) ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(2); });
