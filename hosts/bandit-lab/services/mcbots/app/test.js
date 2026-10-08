'use strict';
// Minimal self-check: config validation + job argument validation.
const assert = require('node:assert');
const {loadConfig} = require('./config');
const {VALIDATE} = require('./bots');
assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1, bot22'}).names, ['bot1', 'bot22']);
for (const bad of ['bot', 'bot100', 'Bot1', 'steve', 'bot1,x']) assert.throws(() => loadConfig({BOT_NAMES: bad}), bad);
assert.throws(() => loadConfig({BOT_NAMES: 'bot1', DASHBOARD_HOST: '0.0.0.0'}));
assert.ok(loadConfig({BOT_NAMES: 'bot1', DASHBOARD_HOST: '0.0.0.0', ALLOWED_TS_LOGINS: 'a@github'}).allowed.length);
assert.deepStrictEqual(VALIDATE.goto({x: '1', y: 64, z: -3}), {x: 1, y: 64, z: -3});
assert.throws(() => VALIDATE.goto({x: 'a', y: 1, z: 1}));
assert.throws(() => VALIDATE.say({text: '/op me'}));
assert.throws(() => VALIDATE.mine({block: 'Iron Ore'}));
assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1', PROTECTED_AREAS: '10,5,-10,-5; 1,2,3,4'}).protectedAreas, [[-10, -5, 10, 5], [1, 2, 3, 4]]);
assert.throws(() => loadConfig({BOT_NAMES: 'bot1', PROTECTED_AREAS: '1,2,3'}));

// ---- shared world / combat logic ----
const W = require('./world');
const {weaponScore} = require('./combat');
assert.ok(W.isHostile({type: 'hostile', name: 'zombie'}));
assert.ok(W.isHostile({type: 'mob', category: 'Hostile mobs', name: 'phantom'}));
assert.ok(!W.isHostile({type: 'player', name: 'x'}) && !W.isHostile({type: 'animal', name: 'wolf'}) && !W.isHostile(null));
assert.ok(W.shouldFight({type: 'hostile', name: 'creeper'}));
for (const n of ['enderman', 'zombified_piglin', 'warden']) assert.ok(!W.shouldFight({type: 'hostile', name: n}), n);
assert.strictEqual(W.normDim('minecraft:the_nether'), 'the_nether');
assert.strictEqual(W.deadlineMs(0), 90000);
assert.strictEqual(W.deadlineMs(100), 190000);
assert.strictEqual(W.deadlineMs(1e6), 600000);
assert.ok(weaponScore('iron_sword') > weaponScore('diamond_axe') && weaponScore('diamond_sword') > weaponScore('iron_sword') && weaponScore('stick') === 0);
const bm = {players: [
  {uuid: 'u1', name: 'steve', foreign: false, position: {x: 1.5, y: 64, z: -3}},
  {uuid: 'u2', name: 'alex', foreign: true, position: {x: 0, y: 0, z: 0}},
  {uuid: 'u3', name: 'bad name!', foreign: false, position: {x: 0, y: 0, z: 0}},
  {uuid: 'u4', name: 'nopos', foreign: false},
]};
assert.deepStrictEqual(W.parsePlayers(bm, 'overworld'), [{name: 'steve', uuid: 'u1', x: 1.5, y: 64, z: -3, dim: 'overworld'}]);
assert.deepStrictEqual(W.parsePlayers(null, 'overworld'), []);
let clock = 1000;
const wm = new W.WorldModel({now: () => clock});
wm.setPlayers(W.parsePlayers(bm, 'the_nether'));
assert.strictEqual(wm.player('steve').dim, 'the_nether');
const mob = (id, x) => ({id, name: 'zombie', position: {x, y: 64, z: 0}});
wm.noteMob('bot1', mob(1, 10), 'overworld');
assert.strictEqual(wm.hostilesNear(12, 0, 'overworld', 8).length, 1);
assert.strictEqual(wm.hostilesNear(12, 0, 'the_nether', 8).length, 0);
assert.strictEqual(wm.hostilesNear(100, 0, 'overworld', 8).length, 0);
wm.forgetMob(1);
assert.strictEqual(wm.mobs.size, 0);
wm.noteMob('bot1', mob(2, 10), 'overworld');
clock += W.MOB_TTL_MS + 1; // mobs expire; players (10 s) too
assert.strictEqual(wm.snapshot().mobs.length, 0);
assert.strictEqual(wm.player('steve'), undefined);
for (let i = 0; i < W.MAX_MOBS + 50; i++) { clock++; wm.noteMob('bot1', mob(i, i), 'overworld'); }
assert.strictEqual(wm.mobs.size, W.MAX_MOBS);
assert.ok(wm.mobs.has(`overworld:${W.MAX_MOBS + 49}`) && !wm.mobs.has('overworld:0')); // oldest evicted
for (let i = 0; i < W.MAX_BLOCKS + 20; i++) { clock++; wm.noteBlock('bot1', 'chest', {x: i, y: 1, z: 1}, 'overworld'); }
assert.strictEqual(wm.blocks.size, W.MAX_BLOCKS);
assert.strictEqual(loadConfig({BOT_NAMES: 'bot1', BLUEMAP_URL: 'http://minecraft:8100/'}).bluemapUrl, 'http://minecraft:8100');
assert.throws(() => loadConfig({BOT_NAMES: 'bot1', BLUEMAP_URL: 'file:///etc'}));
assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1', SUPPLY_CHEST: '-100,71,12'}).supplyChest, {x: -100, y: 71, z: 12});
assert.throws(() => loadConfig({BOT_NAMES: 'bot1', SUPPLY_CHEST: '1,2'}));
assert.deepStrictEqual(VALIDATE.rearm({x: 1, y: 2, z: 3}), {x: 1, y: 2, z: 3});
// Constructing a runner must not throw (it does not connect until start()).
const {BotRunner} = require('./bots');
const runner = new BotRunner('bot1', {host: 'x', port: 1, log: () => {}, world: null, protectedAreas: [], supplyChest: {x: 1, y: 2, z: 3}});
assert.deepStrictEqual(runner.supplyChest, {x: 1, y: 2, z: 3});

// ---- new jobs: strict validation ----
assert.deepStrictEqual(VALIDATE.craft({item: 'oak_planks', count: '4'}), {item: 'oak_planks', count: 4});
assert.deepStrictEqual(VALIDATE.smelt({item: 'raw_iron'}), {item: 'raw_iron', count: 1});
assert.deepStrictEqual(VALIDATE.place({block: 'torch', x: 1, y: 64, z: 2}), {block: 'torch', x: 1, y: 64, z: 2});
assert.deepStrictEqual(VALIDATE['dig-down']({}), {distance: 5});
for (const bad of [{item: 'Oak Planks'}, {item: ''}, {item: 'a'.repeat(49)}, {item: 'stick', count: 0}, {item: 'stick', count: 65}]) assert.throws(() => VALIDATE.craft(bad), JSON.stringify(bad));
assert.throws(() => VALIDATE.place({block: 'stone', x: 1, y: 999, z: 1}));
assert.throws(() => VALIDATE.place({block: 'stone;x', x: 1, y: 1, z: 1}));
assert.throws(() => VALIDATE['dig-down']({distance: 100}));
for (const t of ['collect-drops', 'sleep', 'surface']) assert.deepStrictEqual(VALIDATE[t]({junk: 1}), {});

// ---- Mindcraft skills load without a server; every skill sees our Movements ----
const mindcraft = require('./mindcraft');
const pf = require('mineflayer-pathfinder');
(async () => {
  const lib = await mindcraft.load('26.1');
  for (const fn of ['goToPosition', 'collectBlock', 'craftRecipe', 'smeltItem', 'placeBlock', 'pickupNearbyItems', 'goToBed', 'digDown', 'goToSurface']) {
    assert.strictEqual(typeof lib.skills[fn], 'function', fn);
  }
  assert.ok(lib.mc.getItemCraftingRecipes('crafting_table').length > 0);
  // pf.Movements is what skills.js instantiates: constraints must apply to it.
  const mcData = require('minecraft-data')('26.1');
  const fakeBot = {registry: mcData, entity: null, world: {}, version: '26.1'};
  mindcraft.attach(Object.assign(fakeBot, {loadPlugin() {}, once() {}}), [[0, 0, 10, 10]]);
  const mv = new pf.Movements(fakeBot);
  assert.strictEqual(mv.allowSprinting, false);
  assert.strictEqual(mv.allowParkour, false);
  assert.strictEqual(mv.getMoveDiagonal(), undefined);
  assert.strictEqual(mv.exclusionAreasBreak[0]({position: {x: 5, z: 5}}), 100);
  assert.strictEqual(mv.exclusionAreasPlace[0]({position: {x: 50, z: 5}}), 0);
  assert.ok(mindcraft.inArea([[0, 0, 10, 10]], 10, 0) && !mindcraft.inArea([[0, 0, 10, 10]], 11, 0));
  console.log('ok');
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
