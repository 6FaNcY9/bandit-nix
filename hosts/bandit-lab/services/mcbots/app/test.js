'use strict';
// Minimal self-check: config validation + job argument validation.
const assert = require('node:assert');
const {loadConfig} = require('./config');
const {VALIDATE} = require('./bots');
assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1, bot22'}).names, ['bot1', 'bot22']);
for (const bad of ['bot', 'bot100', 'Bot1', 'steve', 'bot1,x']) assert.throws(() => loadConfig({BOT_NAMES: bad}), bad);
{ // agent bearer (H5): config pairs token and bots; the policy limits endpoints, bots, jobs and chests
  const tok = 'a'.repeat(40);
  assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1', TRUSTED_PROXIES: '10.250.77.1, 172.22.0.1'}).trustedProxies, ['10.250.77.1', '172.22.0.1']);
  assert.throws(() => loadConfig({BOT_NAMES: 'bot1', TRUSTED_PROXIES: 'evil.example'}), /IP addresses/);
  assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1,bot2', AGENT_TOKEN: tok, AGENT_BOTS: 'bot1'}).agentBots, ['bot1']);
  assert.throws(() => loadConfig({BOT_NAMES: 'bot1', AGENT_TOKEN: tok}), /set together/);
  assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1', AGENT_TOKEN: tok, AGENT_BOTS: 'bot1,bot16'}).agentBots, ['bot1', 'bot16'], 'worker bots too');
  assert.throws(() => loadConfig({BOT_NAMES: 'bot1', AGENT_TOKEN: tok, AGENT_BOTS: 'steve'}), /must be bot names/);
  assert.throws(() => loadConfig({BOT_NAMES: 'bot1', AGENT_TOKEN: 'short', AGENT_BOTS: 'bot1'}), /32..128/);
  assert.throws(() => loadConfig({BOT_NAMES: 'bot1', AGENT_TOKEN: tok, AGENT_BOTS: 'bot1', WORKER_TOKEN: tok, WORKER_PORT: '8096'}), /differ/);
  const A = require('./agentauth');
  const h = A.hash(tok);
  assert.strictEqual(A.bearerMatches(undefined, h), null, 'no bearer: human path');
  assert.strictEqual(A.bearerMatches(`Bearer ${tok}`, h), true);
  for (const bad of [`Bearer ${'b'.repeat(40)}`, `bearer ${tok}`, tok, `Bearer ${tok} x`, '']) assert.strictEqual(A.bearerMatches(bad, h), false, bad);
  assert.strictEqual(A.bearerMatches(`Bearer ${tok}`, null), false, 'no agent token configured: every bearer fails');
  assert.ok(A.agentEndpoint('GET', '/api/state') && A.agentEndpoint('GET', '/api/events') && A.agentEndpoint('POST', '/api/job') && A.agentEndpoint('POST', '/api/decision'));
  assert.ok(A.agentEndpoint('POST', '/api/agentstatus') && !A.agentEndpoint('GET', '/api/agents') && !A.agentEndpoint('POST', '/api/agents'), 'only the agent posts its status');
  const sp = {agentBots: ['bot1']};
  assert.deepStrictEqual(A.agentStatus({agent: 'bot1', goal: 'g'.repeat(600), workers: ['bot2'], role: 'lead'}, sp), {agent: 'bot1', goal: 'g'.repeat(500), workers: ['bot2'], role: 'lead'});
  for (const bad of [{agent: 'bot9', goal: '', workers: []}, {agent: 'bot1', goal: 1, workers: []}, {agent: 'bot1', goal: '', workers: 'bot2'}, {agent: 'bot1', goal: '', workers: ['a b']}, {agent: 'bot1', goal: '', workers: Array(13).fill('w')}]) assert.ok(A.agentStatus(bad, sp).error, JSON.stringify(bad));
  assert.ok(!A.agentEndpoint('GET', '/api/decisions'), 'reading decisions is for humans');
  for (const [m, u] of [['POST', '/api/settings'], ['POST', '/api/keeper'], ['POST', '/api/places'], ['GET', '/api/debug'], ['GET', '/'], ['GET', '/api/view']]) assert.ok(!A.agentEndpoint(m, u), u);
  const pol = {agentBots: ['bot1', 'bot2'], supplyChest: {x: 1, y: 2, z: 3}};
  const no = (body) => A.agentJobRefusal(body, pol);
  assert.strictEqual(no({bots: ['bot1'], type: 'mine', args: {block: 'stone', count: 3}}), null);
  assert.strictEqual(no({bots: ['bot2'], type: 'stop', args: {}}), null);
  assert.strictEqual(no({bots: ['bot1'], type: 'deposit', args: {x: 1, y: 2, z: 3}}), null);
  assert.match(no({bots: 'all', type: 'stop'}), /name their bots/);
  assert.match(no({bots: ['bot1', 'bot10'], type: 'stop'}), /bot10 is not an agent bot/);
  assert.match(no({bots: ['bot1'], type: 'say', args: {text: 'hi'}}), /not allowed/);
  assert.match(no({bots: ['bot1'], type: 'rearm', args: {}}), /not allowed/);
  for (const type of ['withdraw', 'deposit', 'stock', 'shift']) assert.match(no({bots: ['bot1'], type, args: {x: 9, y: 2, z: 3}}), /supply chest/, type);
}
assert.throws(() => loadConfig({BOT_NAMES: 'bot1', DASHBOARD_HOST: '0.0.0.0'}));
assert.ok(loadConfig({BOT_NAMES: 'bot1', DASHBOARD_HOST: '0.0.0.0', ALLOWED_TS_LOGINS: 'a@github'}).allowed.length);
assert.deepStrictEqual(VALIDATE.goto({x: '1', y: 64, z: -3}), {x: 1, y: 64, z: -3});
assert.throws(() => VALIDATE.goto({x: 'a', y: 1, z: 1}));
assert.throws(() => VALIDATE.say({text: '/op me'}));
assert.throws(() => VALIDATE.mine({block: 'Iron Ore'}));
assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1', PROTECTED_AREAS: '10,5,-10,-5; 1,2,3,4'}).protectedAreas, [[-10, -5, 10, 5], [1, 2, 3, 4]]);
assert.throws(() => loadConfig({BOT_NAMES: 'bot1', PROTECTED_AREAS: '1,2,3'}));

// ---- build job: blueprint validation, order, next block (fake world) ----
{
  const B = require('./build');
  const cube = (n, block = 'cobblestone') => Array.from({length: n}, (_, i) => ({x: i % 3, y: Math.floor(i / 9), z: Math.floor(i / 3) % 3, block}));
  const bp = {origin: {x: 100, y: 64, z: 100}, blocks: cube(18).reverse()};
  const plan = B.validate(bp);
  assert.deepStrictEqual(plan.blocks.slice(0, 2).map((b) => [b.x, b.y, b.z]), [[100, 64, 100], [101, 64, 100]], 'bottom layer first, then z, then x');
  assert.ok(plan.blocks.every((b, i, a) => !i || a[i - 1].y <= b.y));
  assert.deepStrictEqual(B.materials(plan), {cobblestone: 18});
  assert.deepStrictEqual(B.shortfall({cobblestone: 18, stone: 2}, {cobblestone: 20}), {stone: 2}, 'counts of what is missing');
  assert.deepStrictEqual(B.shortfall({cobblestone: 18, stone: 2}, {cobblestone: 5, stone: 2}), {cobblestone: 13});
  assert.deepStrictEqual(B.shortfall({cobblestone: 9}, {cobblestone: 9}), {}, 'nothing missing');
  assert.deepStrictEqual(B.formatShortfall({stone: 2, cobblestone: 13}), ['2 stone', '13 cobblestone']);
  assert.deepStrictEqual(B.countHave([{name: 'cobblestone', count: 40}, {name: 'dirt', count: 3}, {name: 'cobblestone', count: 24}]), {cobblestone: 64, dirt: 3}, 'stacks add up');
  {
    // withdraw only what is missing: 9 needed, 5 carried -> take 4; afterwards nothing is missing
    const need = {cobblestone: 9};
    const before = B.shortfall(need, B.countHave([{name: 'cobblestone', count: 5}]));
    assert.deepStrictEqual(before, {cobblestone: 4});
    assert.deepStrictEqual(B.shortfall(need, B.countHave([{name: 'cobblestone', count: 5 + before.cobblestone}])), {});
  }
  {
    // B4: what to gather, in which order
    const rich = {furnace: true, wood: true, hasFuel: () => true};
    assert.deepStrictEqual(B.gatherPlan({cobblestone: 9}, rich), {jobs: [['mine', {block: 'stone', count: 9}]], unknown: [], total: 9});
    assert.deepStrictEqual(B.gatherPlan({dirt: 4}).jobs, [['mine', {block: 'dirt', count: 4}]]);
    assert.deepStrictEqual(B.gatherPlan({stone: 9}, rich).jobs, [['mine', {block: 'stone', count: 9}], ['smelt', {item: 'cobblestone', count: 9}]], 'furnace and fuel at hand');
    assert.deepStrictEqual(B.gatherPlan({stone: 9}, {furnace: false, wood: true, hasFuel: () => false}).jobs,
      [['mine', {block: 'stone', count: 17}], ['mine', {block: 'coal_ore', count: 2}], ['smelt', {item: 'cobblestone', count: 9}]], '8 more stone for the furnace, coal for fuel');
    assert.deepStrictEqual(B.gatherPlan({stone: 3}, {furnace: false, wood: false, hasFuel: () => true}).jobs.map((j) => j[0]), ['mine', 'chop', 'smelt'], 'a table needs a log');
    assert.deepStrictEqual(B.gatherPlan({stone: 3}, {furnace: true, wood: false, hasFuel: () => true}).jobs.map((j) => j[0]), ['mine', 'smelt'], 'a furnace in reach needs no table');
    assert.deepStrictEqual(B.gatherPlan({stone: 70}, rich).jobs.filter((j) => j[0] === 'smelt').map((j) => j[1].count), [64, 6], 'one furnace load at most');
    assert.deepStrictEqual(B.gatherPlan({cobblestone: 5, stone: 4}, rich).jobs, [['mine', {block: 'stone', count: 9}], ['smelt', {item: 'cobblestone', count: 4}]], 'both mine stone: one job');
    assert.deepStrictEqual(B.gatherPlan({cobblestone: 5, oak_planks: 2, glass: 1}, rich).unknown, ['2 oak_planks', '1 glass'], 'cannot gather yet');
  }
  for (const [bad, re] of [
    [{...bp, blocks: [{x: 0, y: 0, z: 0, block: 'chest'}]}, /cannot be built/],
    [{...bp, blocks: [{x: 0, y: 0, z: 0, block: 'sand'}]}, /cannot be built/],
    [{...bp, blocks: [{x: 0, y: 0, z: 0, block: 'oak_door'}]}, /cannot be built/],
    [{...bp, blocks: [{x: 0, y: 0, z: 0, block: 'Stone'}]}, /cannot be built/],
    [{...bp, blocks: [{x: 0, y: 0, z: 0, block: 'stone'}, {x: 0, y: 0, z: 0, block: 'dirt'}]}, /two blocks/],
    [{...bp, blocks: [{x: 0, y: 0, z: 0, block: 'stone'}, {x: 0, y: 3, z: 0, block: 'stone'}]}, /larger than/],
    [{...bp, blocks: [{x: 0, y: 0, z: 0, block: 'stone'}, {x: 5, y: 0, z: 0, block: 'stone'}]}, /larger than/],
    [{...bp, blocks: Array.from({length: 76}, () => ({x: 0, y: 0, z: 0, block: 'stone'}))}, /at most 75/],
    [{...bp, blocks: []}, /no blocks/],
    [{...bp, origin: {x: 1.5, y: 64, z: 0}}, /whole number/],
  ]) assert.throws(() => B.validate(bad), re);
  assert.ok(B.validate({...bp, blocks: [{x: 0, y: 0, z: 0, block: 'sandstone'}]}), 'sandstone is not a gravity block');
  assert.throws(() => B.validate(bp, [[90, 90, 110, 110]]), /protected area/);
  assert.ok(B.validate(bp, [[0, 0, 10, 10]]));
  // VALIDATE.build keeps the blueprint relative so a resumed job validates the same way.
  assert.deepStrictEqual(VALIDATE.build({origin: {x: '1', y: 64, z: 2}, blocks: [{x: 0, y: '0', z: 0, block: 'dirt'}]}),
    {origin: {x: 1, y: 64, z: 2}, blocks: [{x: 0, y: 0, z: 0, block: 'dirt'}], remove: false});
  // Fake world: ground (stone) at y 63, air above; placing fills the map.
  const world = new Map();
  const nameAt = (x, y, z) => world.get(`${x},${y},${z}`) ?? (y <= 63 ? 'stone' : 'air');
  let s = B.step(plan, nameAt);
  assert.deepStrictEqual([s.next.x, s.next.y, s.next.z, s.face], [100, 64, 100, [0, -1, 0]], 'first block goes on the ground');
  assert.ok(B.step(plan, nameAt, new Set(['100,64,100'])).next.x === 101, 'a claimed block is skipped');
  let n = 0;
  while (!(s = B.step(plan, nameAt)).done) {
    assert.ok(s.next && ++n <= 18, 'every block gets placed, in order');
    world.set(`${s.next.x},${s.next.y},${s.next.z}`, s.next.block);
  }
  assert.strictEqual(n, 18);
  assert.deepStrictEqual(B.materials(plan, nameAt), {});
  // A floating second layer waits until the first exists (no neighbour yet).
  const floating = B.validate({origin: {x: 0, y: 70, z: 0}, blocks: [{x: 0, y: 1, z: 0, block: 'dirt'}]});
  assert.ok(B.step(floating, nameAt).wait === 1);
  world.set('100,65,100', 'dirt'); // wrong block where the blueprint wants cobblestone
  assert.match(B.step(plan, nameAt).stuck, /dirt is in the way/);
  world.set('100,65,100', 'wildflowers'); // a plant is broken first, not refused
  assert.deepStrictEqual(B.step(plan, nameAt, new Set(), (n) => n === 'wildflowers').clear, true);
  assert.match(B.step(plan, nameAt).stuck, /wildflowers is in the way/);
  world.set('100,65,100', 'cobblestone');
  // Remove: only blocks the build placed, top layer first; a block that was there before stays.
  const rm = B.validate({...bp, remove: true});
  const placedKeys = new Set(rm.blocks.map((q) => `${q.x},${q.y},${q.z}`).filter((k) => k !== '100,64,100'));
  assert.strictEqual(B.removeStep(rm, nameAt, new Set(), placedKeys).next.y, 65);
  assert.ok(B.removeStep(rm, nameAt).done, 'no record: nothing is removed');
  for (let k = 0; !(s = B.removeStep(rm, nameAt, new Set(), placedKeys)).done; k++) {
    assert.ok(k < 18);
    world.delete(`${s.next.x},${s.next.y},${s.next.z}`);
  }
  assert.deepStrictEqual([...world.keys()], ['100,64,100'], 'the pre-existing block stays');
  // Plants are an explicit list: a player's torch or redstone wire is never cleared.
  for (const n of ['wildflowers', 'short_grass', 'poppy']) assert.ok(B.PLANTS.has(n), n);
  for (const n of ['torch', 'redstone_wire', 'rail', 'lever', 'tripwire']) assert.ok(!B.PLANTS.has(n), n);
}

// ---- shared world / combat logic ----
const W = require('./world');
const {weaponScore, wantsToEat, deathCause} = require('./combat');
{
  // Deep miners with coal but no wood cannot make torches (bot2 at y -55, 2026-10-10).
  const {needsWood} = require('./bots');
  assert.equal(needsWood([{name: 'coal', count: 8}]), true);
  assert.equal(needsWood([]), true);
  assert.equal(needsWood([{name: 'oak_log', count: 1}, {name: 'oak_planks', count: 7}]), true);
  assert.equal(needsWood([{name: 'oak_log', count: 2}]), false);
  assert.equal(needsWood([{name: 'birch_planks', count: 8}]), false);
  assert.equal(needsWood([{name: 'oak_log', count: 1}, {name: 'spruce_log', count: 1}]), false);
}
// Hurt bots eat at food 15-17 so they regenerate (bot1 sat at 6.7 health with food 17, 2026-10-10).
assert.equal(wantsToEat(17, 6.7, 15), true);
assert.equal(wantsToEat(17, 20, 15), false);
assert.equal(wantsToEat(14, 20, 15), true);
assert.equal(wantsToEat(19, 10, 15), false);
// Death causes: only the bot's own death messages; chat and other players are ignored.
assert.equal(deathCause('bot1', 'bot1 was slain by Zombie'), 'was slain by Zombie');
assert.equal(deathCause('bot1', 'bot1 fell from a high place'), 'fell from a high place');
assert.equal(deathCause('bot1', 'bot1 hit the ground too hard'), 'hit the ground too hard');
assert.equal(deathCause('bot1', 'bot1 tried to swim in lava'), 'tried to swim in lava');
assert.equal(deathCause('bot1', 'bot1 experienced kinetic energy'), 'experienced kinetic energy');
for (const m of ['bot1 drowned', 'bot1 burned to death', 'bot1 went up in flames', 'bot1 blew up', 'bot1 was blown up by Creeper', 'bot1 suffocated in a wall', 'bot1 starved to death', 'bot1 froze to death', 'bot1 was killed by magic', 'bot1 withered away', 'bot1 was pricked to death', 'bot1 was shot by Skeleton']) assert.ok(deathCause('bot1', m), m);
assert.equal(deathCause('bot1', 'bot2 was slain by Zombie'), null);
assert.equal(deathCause('bot1', '<bot1> fell from a high place'), null);
assert.equal(deathCause('bot1', 'bot1 joined the game'), null);
assert.equal(deathCause('bot1', 'bot10 fell from a high place'), null);
{
  // A fight during a dig ends the dig before the weapon goes into the hand (wrong-tool digs, 2026-10-10).
  const {Combat} = require('./combat');
  const calls = [];
  const bot = {targetDigBlock: {name: 'stone'}, stopDigging: () => calls.push('stop'), currentWindow: null,
    heldItem: {name: 'stone_pickaxe', type: 2}, inventory: {items: () => [{name: 'stone_sword', type: 1}]},
    equip: async () => calls.push('equip')};
  const c = new Combat({bot, inventoryBusy: 0});
  c.stop();
  c.fight({isValid: false}).then(() => {
    assert.deepStrictEqual(calls, ['stop', 'equip'], 'dig stopped first, then the weapon');
    assert.ok(Date.now() - c.lastFight < 1000);
  });
}
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
// Block claims: a second bot cannot take a block the first one holds.
const {WorldModel} = require('./world');
const claims = new WorldModel();
assert.ok(claims.claim('bot1', 'o:1,2,3'));
assert.ok(!claims.claim('bot2', 'o:1,2,3'));
assert.ok(claims.claimedByOther('bot2', 'o:1,2,3'));
claims.release('bot1', 'o:1,2,3');
assert.ok(claims.claim('bot2', 'o:1,2,3'));
assert.deepStrictEqual(claims.claimStats('bot1'), {granted: 1, refused: 0, timedOut: 0});
assert.deepStrictEqual(claims.claimStats('bot2'), {granted: 1, refused: 1, timedOut: 0});
assert.deepStrictEqual(claims.claimStats('nobody'), {granted: 0, refused: 0, timedOut: 0});
// Protected boxes are inclusive; a block outside every box may be dug.
const boxes = [[-80, -144, 80, 80], [112, 368, 272, 592]];
assert.ok(W.insideAreas(boxes, 0, 0) && W.insideAreas(boxes, 80, 80) && W.insideAreas(boxes, 200, 400));
assert.ok(!W.insideAreas(boxes, 81, 0) && !W.insideAreas(boxes, -36, -197) && !W.insideAreas([], 0, 0));
// Login passwords are stable per seed and name, and differ between bots.
const pw = (n) => new BotRunner(n, {host: 'x', port: 1, log: () => {}, world: null, loginSeed: 'seed'}).password;
assert.strictEqual(pw('bot1'), pw('bot1'));
assert.notStrictEqual(pw('bot1'), pw('bot2'));
assert.strictEqual(pw('bot1').length, 32);
const {normalize} = require('./itemfix');
assert.deepStrictEqual(normalize({enchantments: [{id: 1, level: 5}]}, {enchantments: {1: {name: 'efficiency'}}}), [{name: 'efficiency', lvl: 5}]);
assert.deepStrictEqual(normalize([{name: 'x', lvl: 1}], {}), [{name: 'x', lvl: 1}]);
{ // digfix.js: ore blocks get the pickaxe speed bonus (vanilla times)
  const {fix} = require('./digfix');
  assert.strictEqual(fix('26.1'), false); // already applied by bots.js
  const reg = require('prismarine-registry')('26.1');
  const Block = require('prismarine-block')(reg);
  const ms = (block, tool) => Block.fromStateId(reg.blocksByName[block].defaultState, 0).digTime(reg.itemsByName[tool]?.id ?? null, false, false, false, [], []);
  assert.strictEqual(ms('iron_ore', 'iron_pickaxe'), 750);
  assert.strictEqual(ms('deepslate_diamond_ore', 'iron_pickaxe'), 1150);
  assert.strictEqual(ms('stone', 'iron_pickaxe'), 400);
  assert.strictEqual(ms('iron_ore', 'wooden_pickaxe'), 7500); // cannot harvest: no drop, slow
  assert.ok(ms('iron_ore', 'wooden_axe') > ms('iron_ore', 'wooden_pickaxe')); // an axe is no ore tool
  assert.strictEqual(ms('diamond_ore', 'stone_pickaxe'), 3750); // tier rules unchanged
}
assert.deepStrictEqual(VALIDATE.craft({item: 'stone_pickaxe', count: '2'}), {item: 'stone_pickaxe', count: 2});
assert.throws(() => VALIDATE.craft({item: 'Stone Pickaxe'}));
assert.deepStrictEqual(VALIDATE.shift({block: 'logs', x: 1, y: 2, z: 3}), {block: 'logs', x: 1, y: 2, z: 3});
require('./crafting');
// hub.js cleanPng: a worker's view frame must be a real, small PNG.
{
  const {cleanPng} = require('./hub');
  const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(20)]);
  assert.ok(cleanPng(png.toString('base64')));
  assert.strictEqual(cleanPng(Buffer.from('<html>evil').toString('base64')), null, 'not a PNG');
  assert.strictEqual(cleanPng('x'.repeat(230000)), null, 'too big');
  assert.strictEqual(cleanPng({}), null);
}
// alerts.js: chest gone/back once each, night/morning on change, mobs at most every 2 minutes.
{
  const {Alerts, MOB_EVERY_MS} = require('./alerts');
  const {EventLog} = require('./events');
  let t = 0;
  const ev = new EventLog({now: () => t});
  const al = new Alerts({events: ev, now: () => t});
  const chest = {x: 1, y: 2, z: 3};
  al.check({chestBlock: 'chest', timeOfDay: 6000, hostiles: []}, chest);
  assert.strictEqual(ev.items.length, 0, 'all well');
  al.check({chestBlock: 'air', timeOfDay: 6000, hostiles: []}, chest);
  al.check({chestBlock: 'air', timeOfDay: 6000, hostiles: []}, chest);
  assert.deepStrictEqual(ev.items.map((e) => [e.kind, e.text]), [['alert', 'the supply chest at 1 2 3 is gone (air there now)']]);
  al.check({chestBlock: null, timeOfDay: 14000, hostiles: [{type: 'creeper'}, {type: 'creeper'}, {type: 'zombie'}]}, chest);
  assert.match(ev.items.at(-2).text, /night falls/);
  assert.match(ev.items.at(-1).text, /creeper x2, zombie x1/);
  t += 1000;
  al.check({chestBlock: 'chest', timeOfDay: 14000, hostiles: [{type: 'creeper'}]}, chest);
  assert.match(ev.items.at(-1).text, /is back/, 'no second mob alert within 2 minutes');
  t += MOB_EVERY_MS;
  al.check({chestBlock: 'chest', timeOfDay: 23500, hostiles: [{type: 'creeper'}]}, chest);
  assert.deepStrictEqual(ev.items.slice(-2).map((e) => e.text.split(':')[0]), ['morning', 'hostile mobs near the base']);
}
// pathcache.js: one Block per position inside the window, a fresh one after it.
{
  const {cacheGetBlock, WINDOW_MS} = require('./pathcache');
  let calls = 0;
  let t = 1000;
  const mv = cacheGetBlock({getBlock: (pos, dx, dy, dz) => ({n: ++calls, y: pos ? pos.y + dy : null})}, () => t);
  const a = mv.getBlock({x: 1, y: 2, z: 3}, 0, 1, 0);
  assert.strictEqual(mv.getBlock({x: 1, y: 3, z: 3}, 0, 0, 0), a, 'same absolute position, same block');
  assert.notStrictEqual(mv.getBlock({x: 1, y: 2, z: 3}, 0, 0, 0), a);
  t += WINDOW_MS + 1;
  assert.notStrictEqual(mv.getBlock({x: 1, y: 2, z: 3}, 0, 1, 0), a, 'expired');
  assert.strictEqual(calls, 3);
  assert.strictEqual(mv.getBlock(null, 0, 0, 0).n, 4, 'no position: not cached');
  let ver = 0; // a block update inside the window: the next ask is fresh (air -> water must not be cached)
  const mv2 = cacheGetBlock({getBlock: () => ({n: ++calls})}, () => t, () => ver);
  const b = mv2.getBlock({x: 1, y: 2, z: 3}, 0, 0, 0);
  assert.strictEqual(mv2.getBlock({x: 1, y: 2, z: 3}, 0, 0, 0), b);
  ver++;
  assert.notStrictEqual(mv2.getBlock({x: 1, y: 2, z: 3}, 0, 0, 0), b, 'block update empties the cache');
}
// Paper refuses a position whose box touches a block face exactly, so every
// horizontal collision must end a hair short (physicsfix.js).
{
  const AABB = require('prismarine-physics/lib/aabb');
  const {GAP} = require('./physicsfix');
  const wall = new AABB(-5, 58, -5, -4, 59, -4);
  const player = (x) => new AABB(x - 0.3, 58, -5, x + 0.3, 59.8, -4.4);
  const stop = wall.computeOffsetX(player(-3.5), -1); // would end flush at x=-3.7
  assert.ok(Math.abs(stop - -0.2) < 2 * GAP && stop > -0.2, `gap kept, got ${stop}`);
  assert.strictEqual(wall.computeOffsetX(player(-3.7), -1), 0); // already flush: stay
  assert.strictEqual(wall.computeOffsetX(player(-3.7 + GAP / 2), -1), 0); // inside the margin: stay
  assert.strictEqual(wall.computeOffsetX(player(-3.5), -0.1), -0.1); // free move untouched
  assert.strictEqual(wall.computeOffsetX(player(-3.5), 0.5), 0.5); // moving away untouched
  const zwall = new AABB(-5, 58, -5, -4, 59, -4);
  const zp = (z) => new AABB(-4.8, 58, z - 0.3, -4.2, 59.8, z + 0.3);
  assert.ok(zwall.computeOffsetZ(zp(-3.5), -1) > -0.2 && zwall.computeOffsetZ(zp(-3.5), -1) < -0.2 + 2 * GAP);
}
// ---- debug trace + /api/debug ----
{
  const {BotTrace} = require('./debug');
  let now = 1000000;
  const tr = new BotTrace(() => now);
  tr.sample({x: 1, y: 64, z: 2});
  now += 10000; tr.sample({x: 2.123456, y: 64, z: 3});
  tr.correction(); now += 1000; tr.correction();
  now += 25000; // the first sample is 36 s old, the corrections 26 s / 25 s
  tr.setError('boom');
  let s = tr.snapshot();
  assert.deepStrictEqual(s.positions, [{agoS: 26, x: 2.12, y: 64, z: 3}]); // 30 s window, 2 decimals
  assert.deepStrictEqual(s.corrections, {total: 2, last30s: 2, lastAgoS: 25});
  assert.deepStrictEqual(s.lastError, {message: 'boom', agoS: 0});
  now += 6000; // corrections age out of the window, the total stays
  s = tr.snapshot();
  assert.deepStrictEqual(s.corrections, {total: 2, last30s: 0, lastAgoS: 31});
  assert.strictEqual(tr.recentCorrections(), 0);
  tr.setError('');
  assert.strictEqual(tr.snapshot().lastError, null);

  // offline runner: nothing live, still a full shape
  const off = new BotRunner('bot1', {host: 'x', port: 1, log: () => {}, world: null});
  off.lastError = 'kicked: test';
  let d = off.debug();
  assert.strictEqual(d.online, false);
  assert.strictEqual(d.pos, null);
  assert.strictEqual(d.physics, null);
  assert.strictEqual(d.pathfinder, null);
  assert.strictEqual(d.job, null);
  assert.strictEqual(d.lastError.message, 'kicked: test');
  assert.strictEqual(off.lastError, 'kicked: test'); // accessor keeps working for the old callers
  assert.strictEqual(off.snapshot().pullbacks, 0);

  // online runner with a stub bot: job step, pathfinder, physics, controls
  class GoalNear {}
  const on = new BotRunner('bot2', {host: 'x', port: 1, log: () => {}, world: null});
  on.online = true;
  on.bot = {
    entity: {position: {x: 1.234, y: 60, z: -3.5}, velocity: {x: 0, y: -0.0784, z: 0}, onGround: true, isCollidedHorizontally: true},
    game: {dimension: 'minecraft:overworld'},
    controlState: {forward: true, jump: false, back: false},
    pathfinder: {isMoving: () => true, isMining: () => false, isBuilding: () => false, goal: new GoalNear()},
  };
  on.current = {id: 3, type: 'goto', args: {x: 1, y: 2, z: 3}, status: 'running', progress: '12 blocks', startedAt: Date.now() - 2500};
  on.queue = [{id: 4, type: 'say', args: {text: 'hi'}}];
  on.trace.sample(on.bot.entity.position);
  on.trace.correction();
  d = on.debug();
  assert.deepStrictEqual(d.pos, [1.23, 60, -3.5]);
  assert.strictEqual(d.dimension, 'overworld');
  assert.deepStrictEqual(d.physics, {onGround: true, collidedHorizontally: true, velocity: [0, -0.078, 0], controls: ['forward']});
  assert.deepStrictEqual(d.pathfinder, {moving: true, mining: false, building: false, goal: 'GoalNear'});
  assert.strictEqual(d.job.type, 'goto');
  assert.strictEqual(d.job.progress, '12 blocks');
  assert.ok(d.job.runningS >= 2.4 && d.job.runningS < 4, String(d.job.runningS));
  assert.deepStrictEqual(d.queue, ['say hi']);
  assert.strictEqual(d.corrections.last30s, 1);
  assert.strictEqual(d.positions.length, 1);
  assert.doesNotThrow(() => JSON.stringify(d));
}

// GET /api/debug end to end: start the real server, hit it with and without a tailscale login.
(async () => {
  const {spawn} = require('node:child_process');
  const net = require('node:net');
  const port = await new Promise((res) => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); });
  // fake BlueMap: one tile, records every path asked for
  const asked = [];
  const bm = require('node:http').createServer((q, s) => { asked.push(q.url); if (q.url === '/maps/world/tiles/1/x-1/z0.png') { s.writeHead(200); s.end('PNGDATA'); } else { s.writeHead(404); s.end(); } });
  await new Promise((res) => bm.listen(0, '127.0.0.1', res));
  const child = spawn(process.execPath, [require('node:path').join(__dirname, 'server.js')], {
    env: {PATH: process.env.PATH, NODE_PATH: process.env.NODE_PATH || '', BOT_NAMES: 'bot1,bot2', WORKER_PORT: String(port + 1 < 65535 ? port + 1 : port - 1), WORKER_TOKEN: 'c0ffee11'.repeat(5), DASHBOARD_PORT: String(port), DASHBOARD_HOST: '127.0.0.1', ALLOWED_TS_LOGINS: 'a@github', MC_HOST: '127.0.0.1', MC_PORT: '1', BOT_PASSWORD_SEED: 'test', BLUEMAP_URL: `http://127.0.0.1:${bm.address().port}`},
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  try {
    await new Promise((res, rej) => {
      const to = setTimeout(() => rej(new Error('server did not start')), 8000);
      child.stdout.on('data', (b) => { if (String(b).includes('listening')) { clearTimeout(to); res(); } });
      child.on('exit', (c) => rej(new Error(`server exited early (${c})`)));
    });
    const base = `http://127.0.0.1:${port}/api/debug`;
    assert.strictEqual((await fetch(base)).status, 403, 'no login -> 403');
    assert.strictEqual((await fetch(base, {headers: {'tailscale-user-login': 'evil@github'}})).status, 403);
    const r = await fetch(base, {headers: {'tailscale-user-login': 'a@github'}});
    assert.strictEqual(r.status, 200);
    assert.ok(/json/.test(r.headers.get('content-type')));
    const j = await r.json();
    assert.strictEqual(j.windowS, 30);
    assert.ok(!Number.isNaN(Date.parse(j.generatedAt)));
    assert.deepStrictEqual(j.bots.map((b) => b.name), ['bot1', 'bot2']);
    for (const b of j.bots) {
      assert.strictEqual(b.online, false);
      assert.deepStrictEqual(Object.keys(b.corrections).sort(), ['last30s', 'lastAgoS', 'total']);
      assert.deepStrictEqual(b.claims, {granted: 0, refused: 0, timedOut: 0});
      assert.ok(Array.isArray(b.positions) && Array.isArray(b.queue));
    }
    assert.strictEqual((await fetch(base, {method: 'POST', headers: {'tailscale-user-login': 'a@github'}})).status, 404);
    // the hub inside the real server: a worker joins, "all" reaches it, and an absent worker never blocks a Stop
    const wport = port + 1 < 65535 ? port + 1 : port - 1;
    const WebSocket = require('ws');
    const post = (body) => fetch(`http://127.0.0.1:${port}/api/job`, {method: 'POST', headers: {'content-type': 'application/json', origin: `http://127.0.0.1:${port}`, 'tailscale-user-login': 'a@github'}, body: JSON.stringify(body)});
    const state = async () => (await (await fetch(`http://127.0.0.1:${port}/api/state`, {headers: {'tailscale-user-login': 'a@github'}})).json()).bots;
    const wsOpen = (headers) => new Promise((res, rej) => { const ws = new WebSocket(`ws://127.0.0.1:${wport}/worker`, {headers}); ws.on('open', () => res(ws)); ws.on('unexpected-response', (_q, r) => rej(new Error(`HTTP ${r.statusCode}`))); ws.on('error', () => {}); });
    await assert.rejects(wsOpen({}), /401/);
    const wk = await wsOpen({Authorization: `Bearer ${'c0ffee11'.repeat(5)}`});
    const got = [];
    wk.on('message', (d) => got.push(JSON.parse(String(d))));
    wk.send(JSON.stringify({t: 'hello', v: 1, host: 'laptop', bots: ['bot5']}));
    wk.send(JSON.stringify({t: 'status', bots: [{name: 'bot5', online: true, pos: [1, 2, 3]}]}));
    const poll = async (f, what) => { for (let i = 0; i < 100; i++) { const v = await f(); if (v) return v; await new Promise((r) => setTimeout(r, 50)); } throw new Error(`timed out: ${what}`); };
    const b5 = await poll(async () => (await state()).find((b) => b.name === 'bot5' && b.online), 'bot5 listed online');
    assert.deepStrictEqual([b5.host, b5.remote, b5.connected], ['laptop', true, true]);
    assert.strictEqual((await post({bots: 'all', type: 'stop'})).status, 200);
    await poll(() => got.find((m) => m.t === 'job' && m.type === 'stop'), 'stop reached the worker');
    assert.strictEqual((await post({bots: ['bot5'], type: 'goto', args: {x: 1, y: 2, z: 3}})).status, 200);
    // events: the worker's own (only for its bots, kinds and sizes cleaned) and the hub's "worker connected"
    wk.send(JSON.stringify({t: 'status', bots: [], events: [{bot: 'bot5', kind: 'done', text: 'finished: goto 1 2 3'}, {bot: 'bot1', kind: 'done', text: 'not my bot'}, {bot: 'bot5', kind: 'weird', text: 'x'.repeat(500)}, 7]}));
    const ev = await poll(async () => { const j = await (await fetch(`http://127.0.0.1:${port}/api/events?since=0`, {headers: {'tailscale-user-login': 'a@github'}})).json(); return j.events.length >= 3 && j; }, 'events arrived');
    assert.deepStrictEqual(ev.events.map((e) => [e.bot, e.kind]), [['bot5', 'hub'], ['bot5', 'done'], ['bot5', 'info']]);
    assert.strictEqual(ev.events[2].text.length, 200);
    assert.strictEqual(ev.lastId, ev.events.at(-1).id);
    const after = await (await fetch(`http://127.0.0.1:${port}/api/events?since=${ev.lastId}`, {headers: {'tailscale-user-login': 'a@github'}})).json();
    assert.deepStrictEqual(after.events, []);
    // the page may only run its own two inline blocks
    const csp = (await fetch(`http://127.0.0.1:${port}/`, {headers: {'tailscale-user-login': 'a@github'}})).headers.get('content-security-policy');
    assert.match(csp, /default-src 'none'; script-src 'sha256-[\w+/=]{44}'; style-src 'sha256-[\w+/=]{44}'; connect-src 'self'/);
    // a supply marker replaces the configured supply chest for everyone
    const placesPost = (body, origin = `http://127.0.0.1:${port}`) => fetch(`http://127.0.0.1:${port}/api/places`, {method: 'POST', headers: {'content-type': 'application/json', origin, 'tailscale-user-login': 'a@github'}, body: JSON.stringify(body)});
    assert.strictEqual((await placesPost({action: 'set', place: {name: 'Main', kind: 'supply', x: 5, y: 64, z: 6}}, 'http://evil.example')).status, 403, 'cross-origin refused');
    const pr = await placesPost({action: 'set', place: {name: 'Main', kind: 'supply', x: 5, y: 64, z: 6}});
    assert.deepStrictEqual([pr.status, (await pr.json()).supplyChest], [200, {x: 5, y: 64, z: 6}]);
    const full = await (await fetch(`http://127.0.0.1:${port}/api/state`, {headers: {'tailscale-user-login': 'a@github'}})).json();
    assert.deepStrictEqual([full.supplyChest, full.places.length], [{x: 5, y: 64, z: 6}, 1]);
    assert.strictEqual((await placesPost({action: 'set', place: {name: 'Bad', kind: 'nope', x: 0, y: 0, z: 0}})).status, 400);

    // map tiles: proxied from BlueMap; anything else never reaches it
    const tileUrl = (pth) => fetch(`http://127.0.0.1:${port}${pth}`, {headers: {'tailscale-user-login': 'a@github'}});
    const tl = await tileUrl('/api/tile/world/1/x-1/z0.png');
    assert.deepStrictEqual([tl.status, tl.headers.get('content-type'), await tl.text()], [200, 'image/png', 'PNGDATA']);
    assert.strictEqual((await tileUrl('/api/tile/world/1/x9/z9.png')).status, 404, 'missing tile');
    for (const bad of ['/api/tile/evil/1/x0/z0.png', '/api/tile/world/7/x0/z0.png', '/api/tile/world/1/x0/z0.png%2F..%2F..%2Fsettings.json']) assert.strictEqual((await tileUrl(bad)).status, 404, bad);
    assert.ok(asked.filter((u) => u.includes('/tiles/')).every((u) => /^\/maps\/world\/tiles\/1\/x-?\d+\/z-?\d+\.png$/.test(u)), asked.join());
    bm.close();
    wk.close();
    const gone = await poll(async () => (await state()).find((b) => b.name === 'bot5' && !b.connected), 'bot5 offline');
    assert.deepStrictEqual([gone.online, gone.host, gone.lastSeen > 0], [false, 'laptop', true]);
    assert.strictEqual((await post({bots: 'all', type: 'stop'})).status, 200, 'an absent worker does not break Stop for all');
    const named = await post({bots: ['bot5'], type: 'stop'});
    assert.strictEqual(named.status, 400);
    assert.match((await named.json()).error, /bot5.*offline/);
    assert.strictEqual((await fetch(`http://127.0.0.1:${wport}/api/state`)).status, 404, 'the worker port serves no dashboard');
  } finally {
    child.kill('SIGKILL');
  }
})();
// ---- hub: reservations, remote workers, worker client ----
{
  const {WorldModel} = require('./world');
  const w = new WorldModel();
  assert.ok(w.claim('bot1', 'overworld:1,2,3') && w.claim('bot1', 'overworld:1,2,4') && !w.claim('bot2', 'overworld:1,2,3'));
  w.releaseAll('bot1');
  assert.strictEqual(w.claims.size, 0);
  assert.strictEqual(w.unreachable, false);
  assert.ok(w.claim('bot2', 'overworld:1,2,3'));

  const {loadWorkerConfig, loadConfig: lc} = require('./config');
  const env = {HUB_URL: 'wss://bandit-lab.example.ts.net:8446/worker', HUB_TOKEN: 'x'.repeat(40), MC_HOST: '100.1.1.1', BOT_PASSWORD_SEED: 's'};
  const wc = loadWorkerConfig(env, ['bot5', 'bot6']);
  assert.deepStrictEqual([wc.names, wc.mcHost, wc.mcPort], [['bot5', 'bot6'], '100.1.1.1', 25565]);
  for (const bad of [[], ['bot5', 'bot5'], ['bot1000'], ['--help'], ['Bot5']]) assert.throws(() => loadWorkerConfig(env, bad), JSON.stringify(bad));
  assert.throws(() => loadWorkerConfig({...env, HUB_URL: 'http://x/worker'}, ['bot5']));
  assert.throws(() => loadWorkerConfig({...env, HUB_URL: 'ws://evil.example/worker'}, ['bot5']));
  assert.doesNotThrow(() => loadWorkerConfig({...env, HUB_URL: 'ws://127.0.0.1:9/worker'}, ['bot5']));
  assert.throws(() => loadWorkerConfig({...env, HUB_TOKEN: ''}, ['bot5']));
  const tok = 'a1b2c3d4'.repeat(8);
  assert.strictEqual(lc({BOT_NAMES: 'bot1', WORKER_PORT: '8096', WORKER_TOKEN: tok}).workerPort, 8096);
  assert.throws(() => lc({BOT_NAMES: 'bot1', WORKER_PORT: '8096'}), 'port without token');
  assert.throws(() => lc({BOT_NAMES: 'bot1', WORKER_TOKEN: tok}), 'token without port');
  assert.throws(() => lc({BOT_NAMES: 'bot1', WORKER_PORT: '8095', WORKER_TOKEN: tok}), 'same port as the dashboard');
  assert.throws(() => lc({BOT_NAMES: 'bot1', WORKER_PORT: '8096', WORKER_TOKEN: 'short'}));
  assert.strictEqual(lc({BOT_NAMES: 'bot1'}).workerToken, '');
}

(async () => {
  const WebSocket = require('ws');
  const net = require('node:net');
  const {WorldModel} = require('./world');
  const {Hub, createWorkerServer, RemoteRunner} = require('./hub');
  const {RemoteWorld, HubClient} = require('./hubclient');
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const until = async (f, what, ms = 10000) => {
    for (let t = 0; t < ms; t += 20) {
      const v = await f();
      if (v) return v;
      await sleep(20);
    }
    throw new Error(`timed out: ${what}`);
  };
  const port = await new Promise((res) => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); });
  const token = 'f00dcafe'.repeat(6);
  const world = new WorldModel();
  const labBot = {name: 'bot1', start() {}, shutdown() {}, snapshot: () => ({name: 'bot1', online: true}), debug: () => ({}), enqueue() {}};
  const runners = new Map([['bot1', labBot]]);
  const hubSettings = new (require('./settings').Settings)('');
  const hub = new Hub({world, runners, token, log: () => {}, protectedAreas: [[1, 2, 3, 4]], supplyChest: {x: 1, y: 2, z: 3}, settings: hubSettings});
  const server = createWorkerServer(hub);
  await new Promise((res) => server.listen(port, '127.0.0.1', res));
  const url = `ws://127.0.0.1:${port}/worker`;

  // a worker as a raw websocket, to look at the wire
  const open = (headers) => new Promise((res, rej) => {
    const ws = new WebSocket(url, {headers});
    const msgs = [];
    ws.on('message', (d) => msgs.push(JSON.parse(String(d))));
    ws.on('open', () => res({ws, msgs, send: (m) => ws.send(JSON.stringify(m)), closed: new Promise((r) => ws.on('close', (c) => r(c)))}));
    ws.on('unexpected-response', (_q, r) => rej(new Error(`HTTP ${r.statusCode}`)));
    ws.on('error', () => {});
  });
  const rejects = async (p, re) => { try { await p; } catch (e) { return assert.match(e.message, re); } assert.fail('should have been refused'); };

  try {
    // admission: token required, nothing but /worker is served
    await rejects(open({}), /401/);
    await rejects(open({Authorization: 'Bearer wrong' + token}), /401/);
    await rejects(open({Authorization: `Basic ${token}`}), /401/);
    await rejects(new Promise((res, rej) => { const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`, {headers: {Authorization: `Bearer ${token}`}}); ws.on('open', res); ws.on('unexpected-response', (_q, r) => rej(new Error(`HTTP ${r.statusCode}`))); ws.on('error', () => {}); }), /404/);
    const plain = await fetch(`http://127.0.0.1:${port}/api/state`);
    assert.strictEqual(plain.status, 404, 'no dashboard routes on the worker port');
    const auth = {Authorization: `Bearer ${token}`};
    const W1 = 'a1'.repeat(16), W2 = 'b2'.repeat(16); // two workers' ids (hubclient derives them from the login seed)

    // a worker may not take over the lab's bots, nor send anything before hello
    let a = await open(auth);
    a.send({t: 'hello', v: 1, host: 'laptop', bots: ['bot1']});
    await until(() => a.msgs.find((m) => m.t === 'error'), 'lab bot refused');
    assert.match(a.msgs.find((m) => m.t === 'error').message, /bot1 run in the lab/);
    await a.closed;
    a = await open(auth);
    a.send({t: 'status', bots: []});
    assert.strictEqual((await a.closed), 1008);
    a = await open(auth);
    a.send({t: 'hello', v: 99, host: 'laptop', bots: ['bot5']});
    await a.closed;
    assert.ok(!runners.has('bot5'));

    // a proper worker
    a = await open(auth);
    a.send({t: 'hello', v: 1, host: 'laptop', wid: W1, bots: ['bot5']});
    const welcome = await until(() => a.msgs.find((m) => m.t === 'welcome'), 'welcome');
    assert.deepStrictEqual([welcome.protectedAreas, welcome.supplyChest], [[[1, 2, 3, 4]], {x: 1, y: 2, z: 3}]);
    const r5 = runners.get('bot5');
    assert.ok(r5 instanceof RemoteRunner);
    assert.strictEqual(r5.snapshot().online, false, 'not online until the bot reports in');
    a.send({t: 'status', bots: [
      {name: 'bot5', online: true, health: 18, food: 'lots', pos: [1, 64, 3], dimension: 'overworld', job: {label: 'mine stone 3', progress: '1/3'}, queue: ['say hi'], inventory: Array(500).fill('x'.repeat(500)), lastError: 'e'.repeat(5000), pullbacks: 3, debug: {pos: [1, 64, 3], corrections: {total: 7, last30s: 2, lastAgoS: 1.5}, claims: {granted: 4, refused: -1, timedOut: 'x', evil: 9}, positions: [{agoS: 1, x: 1, y: 64, z: 3}], job: {id: 1, type: 'mine', args: {block: 'stone', evil: {a: 1}}, status: 'running', progress: '1/3', runningS: 2}}},
      {name: 'bot1', online: true, health: 1}, // not this worker's bot: ignored
      {name: 'bot9', online: true}, // not announced: ignored
    ]});
    await until(() => r5.snapshot().online, 'bot5 online');
    const s5 = r5.snapshot();
    assert.strictEqual(s5.host, 'laptop');
    assert.strictEqual(s5.remote, true);
    assert.deepStrictEqual([s5.health, s5.food, s5.pos, s5.pullbacks], [18, null, [1, 64, 3], 3]);
    assert.strictEqual(s5.inventory.length, 80);
    assert.ok(s5.inventory.every((x) => x.length <= 60) && s5.lastError.length === 300);
    assert.ok(s5.lastSeen > 0);
    assert.ok(!runners.has('bot9') && runners.get('bot1') === labBot);
    const d5 = r5.debug();
    assert.deepStrictEqual(d5.corrections, {total: 7, last30s: 2, lastAgoS: 1.5});
    assert.deepStrictEqual(d5.claims, {granted: 4, refused: 0, timedOut: 0}, 'claim counters are sanitised to non-negative ints, unknown keys dropped');
    assert.strictEqual(d5.job.args.evil, '[object Object]'.slice(0, 200));
    assert.doesNotThrow(() => JSON.stringify([s5, d5]));
    assert.deepStrictEqual(r5.kept, [], 'no kept jobs reported yet');
    // kept jobs: only the long job types, re-validated; bad entries and over-long lists are dropped
    a.send({t: 'status', bots: [{name: 'bot5', online: true, kept: [
      {type: 'say', args: {text: 'hi'}}, {type: 'mine', args: {block: 'stone', count: 'many'}}, 'junk', null,
      {type: 'shift', args: {block: 'logs', x: 1, y: 64, z: 1, evil: 1}}, {type: 'mine', args: {block: 'stone', count: 3}},
      ...Array(40).fill({type: 'chop', args: {count: 2}}),
    ]}]});
    await until(() => r5.kept.length, 'kept jobs reported');
    assert.deepStrictEqual(r5.kept.slice(0, 2).map((j) => j.type), ['shift', 'mine']);
    assert.ok(!('evil' in r5.kept[0].args) && r5.kept.length <= 20);

    // jobs from the dashboard go to the worker, validated on the hub first
    r5.enqueue('goto', {x: '1', y: 2, z: 3}, {replace: true});
    r5.enqueue('stop');
    const jobs = await until(() => a.msgs.filter((m) => m.t === 'job').length === 2 && a.msgs.filter((m) => m.t === 'job'), 'jobs forwarded');
    assert.deepStrictEqual(jobs[0], {t: 'job', bot: 'bot5', type: 'goto', args: {x: 1, y: 2, z: 3}, replace: true});
    assert.deepStrictEqual([jobs[1].type, jobs[1].replace], ['stop', false]);
    assert.throws(() => r5.enqueue('say', {text: '/op me'}));
    assert.throws(() => r5.enqueue('format-disk', {}));
    assert.strictEqual(a.msgs.filter((m) => m.t === 'job').length, 2, 'rejected jobs never reach the worker');

    // reservations: the hub is the only authority
    assert.ok(world.claim('bot1', 'overworld:5,60,5')); // a lab bot holds this block
    const ask = async (key, by = 'bot5') => {
      const id = Math.floor(Math.random() * 1e6);
      a.send({t: 'claim', id, key, by});
      return (await until(() => a.msgs.find((m) => m.t === 'claim_result' && m.id === id), 'claim_result')).ok;
    };
    assert.strictEqual(await ask('overworld:5,60,5'), false, 'a block a lab bot holds is refused');
    assert.strictEqual(await ask('overworld:6,60,5'), true);
    assert.ok(world.claimedByOther('bot1', 'overworld:6,60,5'), 'lab bots see the worker claim');
    assert.strictEqual(await ask('overworld:7,60,5', 'bot1'), false, 'a worker cannot claim for a lab bot');
    assert.strictEqual(await ask('not a key'), false);
    for (let i = 0; i < 12; i++) await ask(`overworld:${10 + i},60,5`);
    assert.ok([...world.claims.values()].filter((c) => c.by === 'bot5').length <= 8, 'claims per bot are capped');
    a.send({t: 'release', key: 'overworld:6,60,5', by: 'bot5'});
    await until(() => !world.claims.has('overworld:6,60,5'), 'release');

    // observations and the picture sent back
    a.send({t: 'observe', mobs: [{id: 77, type: 'zombie', x: 1, y: 2, z: 3, dim: 'overworld', by: 'bot5'}, {id: 'x', type: 'zombie'}], blocks: [{type: 'chest', x: 4, y: 5, z: 6, dim: 'overworld', by: 'bot5'}], gone: []});
    await until(() => world.mobs.has('overworld:77') && world.blocks.size === 1, 'observations');
    assert.strictEqual(world.mobs.size, 1);
    hub.broadcastWorld();
    const wm = await until(() => a.msgs.find((m) => m.t === 'world'), 'world broadcast');
    assert.ok(wm.mobs.some((m) => m.id === 77) && wm.claims.some((c) => c.by === 'bot1'));

    // the worker goes away: bot5 stays listed as offline with its last-seen, claims are freed
    const seen = r5.snapshot().lastSeen;
    assert.ok(await ask('overworld:30,60,5'));
    a.ws.close();
    await until(() => !r5.snapshot().connected, 'offline');
    const off = r5.snapshot();
    assert.deepStrictEqual([off.online, off.host, off.lastSeen, off.job, off.queue], [false, 'laptop', seen, null, []]);
    assert.ok(![...world.claims.values()].some((c) => c.by === 'bot5'), 'claims of a gone worker are released');
    assert.throws(() => r5.enqueue('goto', {x: 1, y: 2, z: 3}), /offline/);

    // a reconnect replaces a stale connection (same worker: same wid, whatever its host label says)
    const old = await open(auth);
    old.send({t: 'hello', v: 1, host: 'laptop', wid: W1, bots: ['bot5']});
    await until(() => old.msgs.find((m) => m.t === 'welcome'), 'welcome 1');
    const fresh = await open(auth);
    fresh.send({t: 'hello', v: 1, host: 'laptop2', wid: W1, bots: ['bot5']});
    await until(() => fresh.msgs.find((m) => m.t === 'welcome'), 'welcome 2');
    assert.strictEqual(await old.closed, 4001);
    assert.strictEqual(r5.snapshot().connected, true, 'the new connection stays owner');
    assert.strictEqual(r5.snapshot().host, 'laptop2');
    fresh.ws.close();
    await until(() => !r5.snapshot().connected, 'offline again');

    // a replaced connection must not keep acting for the bot it lost
    {
      const o = await open(auth);
      o.send({t: 'hello', v: 1, host: 'a', wid: W1, bots: ['bot8']});
      await until(() => o.msgs.find((m) => m.t === 'welcome'), 'welcome old');
      const n = await open(auth);
      n.send({t: 'hello', v: 1, host: 'b', wid: W1, bots: ['bot8']});
      await until(() => n.msgs.find((m) => m.t === 'welcome'), 'welcome new');
      o.send({t: 'claim', id: 1, key: 'overworld:70,60,5', by: 'bot8'});
      o.send({t: 'ping'});
      await sleep(300);
      assert.ok(!world.claims.has('overworld:70,60,5'), 'a replaced connection cannot claim');
      n.ws.close();
      await until(() => !runners.get('bot8').snapshot().connected, 'bot8 offline');
    }

    // bot names belong to the worker that first announced them (R2-6)
    {
      const hello = async (wid, host, bots) => {
        const c = await open(auth);
        c.send({t: 'hello', v: 1, host, ...(wid ? {wid} : {}), bots});
        return c;
      };
      const welcomed = (c, what) => until(() => c.msgs.find((m) => m.t === 'welcome'), what);
      const lab = await hello(W1, 'bandit-lab-worker', ['bot16', 'bot17']);
      await welcomed(lab, 'lab worker');
      // another credential holder can neither announce nor replace them, nor the laptop's bot5
      for (const names of [['bot16'], ['bot16', 'bot21'], ['bot5'], ['bot17', 'bot5']]) {
        const evil = await hello(W2, 'bandit-lab-worker', names);
        assert.strictEqual(await evil.closed, 4003, names.join());
        assert.match(evil.msgs.find((m) => m.t === 'error').message, /taken by another worker/);
        assert.ok(runners.get('bot16').snapshot().connected, 'the owner stays connected');
        assert.ok(runners.get('bot16').conn.bots.has('bot16'));
      }
      assert.ok(!runners.has('bot21'), 'a refused hello binds and creates nothing');
      // the same worker (same id, whatever its label) takes its names back and replaces the stale socket
      const again = await hello(W1, 'renamed-host', ['bot16', 'bot17']);
      await welcomed(again, 'owner again');
      assert.strictEqual(await lab.closed, 4001);
      // a free name goes to whoever asks first; a worker without id is told apart by its host label
      const other = await hello(W2, 'laptop', ['bot21']);
      await welcomed(other, 'second worker, free name');
      const old1 = await hello(null, 'oldhost', ['bot22']);
      await welcomed(old1, 'worker without id');
      const old2 = await hello(null, 'elsewhere', ['bot22']);
      assert.strictEqual(await old2.closed, 4003);
      const old3 = await hello(W1, 'oldhost', ['bot22']);
      assert.strictEqual(await old3.closed, 4003, 'an id does not match a name bound by label');
      const old4 = await hello(null, 'oldhost', ['bot22']);
      await welcomed(old4, 'same label reconnects');
      assert.strictEqual(await old1.closed, 4001);
      for (const c of [again, other, old4]) c.ws.close();
      await until(() => !runners.get('bot16').snapshot().connected && !runners.get('bot22').snapshot().connected, 'all offline');
    }

    // a worker restarted alone: the hub queues its bots' KEEP jobs again once they are online and idle
    {
      const hello = async () => {
        const c = await open(auth);
        c.send({t: 'hello', v: 1, host: 'laptop', wid: W2, bots: ['bot20']});
        await until(() => c.msgs.find((m) => m.t === 'welcome'), 'welcome bot20');
        return c;
      };
      const keep = [{type: 'mine', args: {block: 'stone', count: 5}}];
      const status = (c, extra) => c.send({t: 'status', bots: [{name: 'bot20', ...extra}]});
      const jobs = (c) => c.msgs.filter((m) => m.t === 'job');
      let c = await hello();
      status(c, {online: true, job: {type: 'mine', label: 'mine stone 5'}, kept: keep});
      const r20 = runners.get('bot20');
      await until(() => r20.kept.length === 1, 'kept reported');
      c.ws.close(); // the worker is restarted
      await until(() => !r20.snapshot().connected, 'worker gone');
      c = await hello();
      status(c, {online: false, kept: []}); // the new process: not logged in yet, nothing queued
      await sleep(150);
      assert.strictEqual(r20.kept.length, 1, 'the old list is kept while the bot logs in');
      assert.strictEqual(jobs(c).length, 0);
      status(c, {online: true, kept: []});
      await until(() => jobs(c).length === 1, 'job queued again');
      assert.deepStrictEqual([jobs(c)[0].type, jobs(c)[0].args], ['mine', {block: 'stone', count: 5}]);
      assert.strictEqual(r20.kept.length, 1, 'saved until the worker reports it');
      status(c, {online: true, kept: []}); // not queued twice
      await sleep(150);
      assert.strictEqual(jobs(c).length, 1);
      // a plain reconnect (the worker never stopped) keeps the worker's own queue: nothing is sent
      status(c, {online: true, job: {type: 'mine', label: 'mine stone 5'}, kept: keep});
      await until(() => r20.kept.length === 1 && r20.snap.job, 'job running');
      c.ws.close();
      await until(() => !r20.snapshot().connected, 'blip');
      c = await hello();
      status(c, {online: true, job: {type: 'mine', label: 'mine stone 5'}, kept: keep});
      await sleep(150);
      assert.strictEqual(jobs(c).length, 0);
      // a stop forgets them; a bot that stays away past the window starts empty
      c.ws.close();
      await until(() => !r20.snapshot().connected, 'blip 2');
      c = await hello();
      const realNow = hub.now;
      hub.now = () => Date.now() + 6 * 60000;
      status(c, {online: true, kept: []});
      await until(() => r20.kept.length === 0, 'window over: adopt the worker list');
      assert.strictEqual(jobs(c).length, 0);
      hub.now = realNow;
      c.ws.close();
      await until(() => !r20.snapshot().connected, 'bot20 offline');
    }

    // a flooding worker is cut off
    {
      const f = await open(auth);
      f.send({t: 'hello', v: 1, host: 'flood', bots: ['bot9']});
      await until(() => f.msgs.find((m) => m.t === 'welcome'), 'welcome flood');
      for (let i = 0; i < 1000; i++) f.send({t: 'ping'});
      assert.strictEqual(await f.closed, 1008, 'message flood closes the connection');
    }

    // connections are capped (each costs memory before it has said hello)
    {
      const socks = [];
      let refused = false;
      for (let i = 0; i < 40 && !refused; i++) {
        try { socks.push(await open(auth)); } catch (e) { refused = /503/.test(e.message); if (!refused) throw e; }
      }
      assert.ok(refused, 'too many connections are refused with 503');
      for (const x of socks) x.ws.terminate();
      await until(() => hub.conns.size === 0, 'sockets closed');
    }

    // a worker with the wrong token keeps retrying with back-off and never gets a runner
    const badLogs = [];
    const bad = new HubClient({url, token: 'bad'.repeat(20), names: ['bot7'], hostLabel: 'lap', log: (w, m) => badLogs.push(m), makeRunner: () => assert.fail('no runner without a welcome')});
    bad.start();
    await until(() => badLogs.filter((l) => /refused.*401/.test(l)).length >= 2, 'refused twice (retrying)', 8000);
    assert.ok(bad.backoff >= 2000, `back-off grows: ${bad.backoff}`);
    bad.stop();
    assert.ok(!runners.has('bot7'));

    // guessing: after 20 wrong tokens in a minute the next wrong one is 429, but the real token still gets in
    for (let i = 0; i < 25; i++) await open({Authorization: `Bearer ${'x'.repeat(30 + i)}`}).catch(() => {});
    await rejects(open({Authorization: `Bearer ${'y'.repeat(40)}`}), /429/);
    (await open(auth)).ws.close(); // the real client below also connects while the window is full

    // the real client against the real hub (stub bots instead of a Minecraft login)
    const got = [];
    hubSettings.set('bot6', {defend: false, eatBelow: 10}); // chosen before the worker ever connected
    const stub = {name: 'bot6', started: false, current: null, queue: [], start() { this.started = true; }, shutdown() {}, snapshot: () => ({name: 'bot6', online: true, pos: [9, 9, 9], job: null, queue: [], inventory: [], pullbacks: 0}), debug: () => ({pos: [9, 9, 9]}), enqueue: (type, args, opts) => got.push([type, args, opts])};
    const logs = [];
    const client = new HubClient({url, token, names: ['bot6'], hostLabel: 'lap', log: (w, m) => logs.push(`${w}: ${m}`), makeRunner: () => stub});
    assert.strictEqual(client.world.unreachable, true, 'no reservations before the hub answered');
    assert.strictEqual(await client.world.claim('bot6', 'overworld:1,1,1'), false);
    client.start();
    const r6 = await until(() => runners.get('bot6')?.snapshot().online && runners.get('bot6'), 'worker bot online');
    assert.ok(stub.started);
    assert.strictEqual(client.world.unreachable, false);
    assert.strictEqual(r6.snapshot().host, 'lap');
    // settings: the stored ones arrive with the welcome, a change is forwarded, a bad frame is refused on the worker too
    assert.deepStrictEqual([stub.getSettings().defend, stub.getSettings().eatBelow, stub.getSettings().torches], [false, 10, true]);
    r6.pushSettings(hubSettings.set('bot6', {torches: false}));
    await until(() => stub.getSettings().torches === false, 'settings forwarded to the worker');
    assert.strictEqual(stub.getSettings().defend, false, 'earlier settings stay');
    client.handle({t: 'settings', bot: 'bot6', settings: {eatBelow: 99}});
    client.handle({t: 'settings', bot: 'bot7', settings: {eatBelow: 3}});
    client.handle({t: 'settings', bot: 'bot6', settings: {evil: 1, fightRange: 4}});
    assert.deepStrictEqual([stub.getSettings().eatBelow, stub.getSettings().fightRange, client.settings.get('bot7').eatBelow], [10, 4, 15], 'refused values and foreign bots change nothing, unknown keys are dropped');
    assert.ok(logs.some((l) => /bot6: settings from hub rejected/.test(l)));
    // kept jobs: the worker reports its own list, the hub keeps it; Stop empties it at once
    stub.current = {type: 'shift', args: {block: 'logs', x: 1, y: 64, z: 1}};
    stub.queue = [{type: 'mine', args: {block: 'stone', count: 5}, collected: 2}, {type: 'say', args: {text: 'x'}}, {type: 'chop', args: {count: 4}, cancelled: true}];
    await until(() => r6.kept.length === 2, 'kept jobs reached the hub');
    assert.deepStrictEqual(r6.kept, [{type: 'shift', args: {block: 'logs', x: 1, y: 64, z: 1}}, {type: 'mine', args: {block: 'stone', count: 3}}]);
    r6.enqueue('stop');
    assert.deepStrictEqual(r6.kept, []);
    stub.current = null;
    stub.queue = [];
    await until(() => got.length === 1, 'stop reached the stub bot');
    got.length = 0;
    r6.enqueue('mine', {block: 'stone', count: 2});
    await until(() => got.length === 1, 'job reached the stub bot');
    assert.deepStrictEqual(got[0], ['mine', {block: 'stone', count: 2}, {replace: false}]);
    assert.strictEqual(await client.world.claim('bot6', 'overworld:40,60,5'), true);
    assert.ok(world.claimedByOther('bot1', 'overworld:40,60,5'));
    assert.ok(world.claim('bot1', 'overworld:41,60,5'));
    hub.broadcastWorld();
    await until(() => client.world.claimedByOther('bot6', 'overworld:41,60,5'), 'lab claim mirrored to the worker');
    assert.strictEqual(await client.world.claim('bot6', 'overworld:41,60,5'), false, 'worker cannot take a lab bot block');
    assert.deepStrictEqual(client.world.claimStats('bot6'), {granted: 1, refused: 1, timedOut: 0}, 'worker counts hub answers and mirror refusals');
    {
      const mute = new RemoteWorld();
      mute.attach(() => {}); // a hub that never answers
      assert.strictEqual(await mute.claim('bot6', 'overworld:1,1,1'), false);
      assert.strictEqual(mute.claimStats('bot6').timedOut, 1);
    }
    // what a worker's bot saw in the supply chest reaches the hub's picture (cleaned: bad names and counts dropped)
    client.world.noteStock('bot6', {coal: 3, oak_log: 20, 'Bad Name': 5, stone: -1, dirt: 1.5});
    client.world.flush();
    await until(() => world.stock?.items.coal === 3, 'stock reached the hub');
    assert.deepStrictEqual(world.stock.items, {coal: 3, oak_log: 20});
    assert.strictEqual(world.stock.by, 'bot6');
    client.world.release('bot6', 'overworld:40,60,5');
    await until(() => !world.claims.has('overworld:40,60,5'), 'worker release reached the hub');
    // hub link drops: reservations are refused until it is back
    for (const c of hub.conns) c.ws.terminate();
    await until(() => client.world.unreachable, 'client noticed the drop');
    assert.strictEqual(await client.world.claim('bot6', 'overworld:42,60,5'), false);
    hubSettings.set('bot6', {fightRange: 5}); // changed while the worker is away (nothing to forward to)
    r6.pushSettings(hubSettings.get('bot6'));
    await until(() => !client.world.unreachable && runners.get('bot6').snapshot().connected, 'client reconnected', 6000);
    assert.strictEqual(stub.started, true);
    await until(() => stub.getSettings().fightRange === 5, 'reconnect brings the settings changed meanwhile');
    assert.strictEqual(stub.getSettings().torches, false, 'and keeps the rest');
    client.stop();
    await until(() => !runners.get('bot6').snapshot().connected, 'stopped worker is offline');
    assert.strictEqual(runners.get('bot6').snapshot().online, false);
  } finally {
    hub.close();
    server.close();
    for (const c of hub.conns) c.ws.terminate();
  }
})();

// ---- per-worker hub credentials (Codex R2-6): a lab worker runs its own names only ----
(async () => {
  const WebSocket = require('ws');
  const net = require('node:net');
  const {execSync} = require('node:child_process');
  const {WorldModel} = require('./world');
  const {Hub, createWorkerServer, workerToken} = require('./hub');
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const until = async (f, what, ms = 5000) => {
    for (let t = 0; t < ms; t += 20) {
      const v = await f();
      if (v) return v;
      await sleep(20);
    }
    throw new Error(`timed out: ${what}`);
  };
  const shared = 'f00dcafe'.repeat(6);
  assert.strictEqual(workerToken(shared, 'bandit-lab-worker'), execSync(`printf 'mcbots-worker:%s:%s' bandit-lab-worker ${shared} | sha256sum | cut -c1-64`, {encoding: 'utf8'}).trim(), 'the sh derivation in default.nix matches');
  assert.deepStrictEqual(require('./config').loadConfig({BOT_NAMES: 'bot1', HUB_WORKERS: 'w-one=bot16,bot17; w-two=bot2'}).hubWorkers, {'w-one': ['bot16', 'bot17'], 'w-two': ['bot2']});
  assert.throws(() => require('./config').loadConfig({BOT_NAMES: 'bot1', HUB_WORKERS: 'w-one=steve'}), /HUB_WORKERS/);
  const port = await new Promise((res) => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); });
  const fresh = () => new Map([['bot1', {name: 'bot1', start() {}, shutdown() {}, snapshot: () => ({name: 'bot1', online: true}), debug: () => ({}), enqueue() {}}]]);
  let runners = fresh();
  const workers = {'w-one': ['bot16', 'bot17', 'bot18'], 'w-two': ['bot2', 'bot3', 'bot4']};
  const make = () => new Hub({world: new WorldModel(), runners: (runners = fresh()), token: shared, workers, log: () => {}});
  let hub = make();
  const server = createWorkerServer(hub);
  server.removeAllListeners('upgrade');
  server.on('upgrade', (req, socket, head) => hub.upgrade(req, socket, head));
  await new Promise((res) => server.listen(port, '127.0.0.1', res));
  const open = (token) => new Promise((res, rej) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/worker`, {headers: {Authorization: `Bearer ${token}`}});
    const msgs = [];
    ws.on('message', (d) => msgs.push(JSON.parse(String(d))));
    ws.on('open', () => res({ws, msgs, send: (m) => ws.send(JSON.stringify(m)), closed: new Promise((r) => ws.on('close', (c) => r(c)))}));
    ws.on('unexpected-response', (_q, r) => rej(new Error(`HTTP ${r.statusCode}`)));
    ws.on('error', () => {});
  });
  const hello = async (token, bots, extra = {}) => {
    const c = await open(token);
    c.send({t: 'hello', v: 1, host: 'h', wid: 'a1'.repeat(16), bots, ...extra});
    return c;
  };
  const welcomed = (c) => until(() => c.msgs.find((m) => m.t === 'welcome'), 'welcome');
  try {
    const one = workerToken(shared, 'w-one'), two = workerToken(shared, 'w-two');
    // each credential runs its own names; the same wid and host label (as both lab containers have) change nothing
    const a = await hello(one, ['bot16', 'bot17']);
    await welcomed(a);
    const b = await hello(two, ['bot2']);
    await welcomed(b);
    for (const [token, names] of [[two, ['bot16']], [two, ['bot17', 'bot2']], [one, ['bot2']], [one, ['bot5']], [shared, ['bot16']], [shared, ['bot2', 'bot5']]]) {
      const evil = await hello(token, names);
      assert.strictEqual(await evil.closed, 4003, `${token.slice(0, 4)} ${names}`);
      assert.match(evil.msgs.find((m) => m.t === 'error').message, /may not be run with this worker credential|belong to a lab worker/);
    }
    assert.ok(runners.get('bot16').snapshot().connected && runners.get('bot2').snapshot().connected, 'the owners stay connected');
    assert.ok(!runners.has('bot5'), 'a refused hello creates nothing');
    // the owner reconnects and replaces its stale socket; the shared (laptop) credential still runs other names
    const again = await hello(one, ['bot16', 'bot17', 'bot18']);
    await welcomed(again);
    assert.strictEqual(await a.closed, 4001);
    const laptop = await hello(shared, ['bot5'], {wid: 'c3'.repeat(16)});
    await welcomed(laptop);
    for (const c of [again, b, laptop]) c.ws.close();
    // after a hub restart nothing is first-come: the sets are the server's
    hub.close();
    for (const c of hub.conns) c.ws.terminate();
    hub = make();
    const evil = await hello(two, ['bot16']);
    assert.strictEqual(await evil.closed, 4003, 'worker 2 cannot claim bot16 first after a restart');
    const owner = await hello(one, ['bot16']);
    await welcomed(owner);
    owner.ws.close();
    await assert.rejects(open('x'.repeat(40)), /401/);
  } finally {
    hub.close();
    server.close();
    for (const c of hub.conns) c.ws.terminate();
  }
})();

// ---- claims expire out of the per-bot count; offline workers are forgotten after an hour ----
{
  const {WorldModel, CLAIM_TTL_MS} = require('./world');
  let t = 1000;
  const w = new WorldModel({now: () => t});
  for (let i = 0; i < 8; i++) w.claim('bot5', `overworld:${i},1,1`);
  assert.strictEqual(w.held('bot5'), 8);
  t += CLAIM_TTL_MS + 1;
  assert.strictEqual(w.held('bot5'), 0); // expired claims no longer count
  assert.strictEqual(w.claims.size, 8);
  w.prune();
  assert.strictEqual(w.claims.size, 0); // and are pruned
  assert.ok(w.claim('bot6', 'overworld:0,1,1'));

  const {Hub, RemoteRunner, FORGET_MS} = require('./hub');
  const runners = new Map([['bot1', new BotRunner('bot1', {host: 'x', port: 1, log: () => {}, world: w})]]);
  const {EventLog} = require('./events');
  const events = new EventLog();
  let now = 5000;
  const hub = new Hub({world: w, runners, token: 'k'.repeat(40), now: () => now, events});
  const away = new RemoteRunner('bot5', () => now); away.lastSeen = now; away.conn = null;
  const here = new RemoteRunner('bot6', () => now); here.lastSeen = now - 2 * FORGET_MS; here.conn = {ws: {}};
  runners.set('bot5', away); runners.set('bot6', here);
  now += FORGET_MS - 1000;
  hub.heartbeat();
  assert.ok(runners.has('bot5'));
  now += 2000;
  hub.heartbeat();
  assert.deepStrictEqual([...runners.keys()], ['bot1', 'bot6']); // bot5 gone; a connected one stays however old; lab bots stay
  assert.match(events.items.at(-1).text, /removed from the list/);
  hub.close();
}
{ // a deposit event names what went in, biggest first, and stays short
  const {depositList} = require('./bots');
  assert.strictEqual(depositList({coal: 12, cobblestone: 64}), '64 cobblestone, 12 coal');
  assert.strictEqual(depositList({a: 1, b: 2, c: 3, d: 4, e: 5, f: 6}), '6 f, 5 e, 4 d, 3 c, 2 more kinds');
  // the agent's state carries the supply chest as last seen
  const sw = new W.WorldModel({now: () => 5000});
  assert.strictEqual(sw.snapshot().stock, null);
  sw.noteStock('bot3', {cobblestone: 64});
  assert.deepStrictEqual(sw.snapshot().stock, {items: {cobblestone: 64}, by: 'bot3', age: 0});
}
// ---- event log, activity line, queue removal ----
{
  const {EventLog, clean, MAX} = require('./events');
  let t = 0;
  const log = new EventLog({now: () => ++t});
  for (let i = 0; i < MAX + 30; i++) log.add('bot1', 'job', `n${i}`);
  assert.strictEqual(log.items.length, MAX); // ring buffer: never more than MAX
  assert.strictEqual(log.items[0].text, 'n30');
  assert.strictEqual(log.lastId, MAX + 30);
  assert.deepStrictEqual(log.since(MAX + 28).map((e) => e.text), [`n${MAX + 28}`, `n${MAX + 29}`]);
  assert.strictEqual(log.add('bot1', 'nonsense', 'x'.repeat(999)).kind, 'info');
  assert.strictEqual(log.items.at(-1).text.length, 200);
  assert.strictEqual(clean({bot: 'bot9', kind: 'done', text: 'x'}, new Set(['bot5'])), null);
  assert.strictEqual(clean({bot: 'bot5', kind: 'done', text: 5}, new Set(['bot5'])), null);
  assert.deepStrictEqual(clean({bot: 'bot5', kind: 'x', text: 'y', extra: 1}, new Set(['bot5'])), {bot: 'bot5', kind: 'info', text: 'y'});

  const seen = [];
  const r = new BotRunner('bot3', {host: 'x', port: 1, log: () => {}, world: null, supplyChest: {x: 1, y: 2, z: 3}, onEvent: (b, k, x) => seen.push([b, k, x])});
  assert.strictEqual(r.activity(), 'connecting...');
  r.lastSeen = 1;
  assert.strictEqual(r.activity(), 'offline');
  r.online = true;
  r.bot = {inventory: {items: () => [], emptySlotCount: () => 36}, heldItem: {name: 'stone_pickaxe', durabilityUsed: 50}, registry: {itemsByName: {stone_pickaxe: {maxDurability: 131}}}, entity: null};
  assert.strictEqual(r.activity(), 'idle - no job');
  assert.deepStrictEqual(r.tool(), {name: 'stone_pickaxe', max: 131, left: 81});
  r.queue = [{id: 7, type: 'goto', args: {x: 1, y: 2, z: 3}}, {id: 8, type: 'chop', args: {count: 4}}];
  assert.strictEqual(r.activity(), 'starting the next job');
  r.enqueue('remove', {id: 7});
  assert.deepStrictEqual(r.snapshot().queueIds, [8]); // a running job is not removed, queued ones are
  r.queue = [];
  r.current = {id: 9, type: 'mine', args: {block: 'stone', count: 8}, progress: '2/8', startedAt: Date.now() - 5000, t: {doing: 'mining stone 2/8 near 1 2 3', done: 2, total: 8}};
  let sn = r.snapshot();
  assert.deepStrictEqual([sn.activity, sn.job.done, sn.job.total, sn.job.type], ['mining stone 2/8 near 1 2 3', 2, 8, 'mine']);
  r.dead = true;
  assert.strictEqual(r.activity(), 'dead - respawning');
  r.dead = false;
  r.emit('death', 'died');
  r.onEvent = () => { throw new Error('a broken listener must not kill the bot'); };
  assert.doesNotThrow(() => r.emit('death', 'again'));
  assert.deepStrictEqual(seen, [['bot3', 'death', 'died']]);
  // several refusals in a row are one event
  r.onEvent = (b, k, x) => seen.push([b, k, x]);
  seen.length = 0;
  for (let i = 0; i < 5; i++) r.conflict();
  assert.strictEqual(seen.length, 1);
  assert.match(seen[0][2], /^1 block skipped/);
  // the hub passes the new fields through and refuses wrong types
  const {cleanSnapshot} = require('./hub');
  const cs = cleanSnapshot({...sn, tool: {name: 5, max: -1, left: 'x'}, queueIds: [1, 'a', -3], activity: 'x'.repeat(999)});
  assert.deepStrictEqual([cs.tool, cs.queueIds, cs.activity.length, cs.job.done, cs.job.total], [{name: '', max: 0, left: null}, [1, 0, 0], 200, 2, 8]);
  assert.deepStrictEqual(cleanSnapshot(null).queueIds, []);
  const {RemoteRunner} = require('./hub');
  const sent = [];
  const rr = new RemoteRunner('bot5');
  rr.conn = {ws: {send: (m) => sent.push(JSON.parse(m))}};
  rr.enqueue('remove', {id: '12'});
  assert.deepStrictEqual(sent[0], {t: 'job', bot: 'bot5', type: 'remove', args: {id: 12}, replace: false});
}
// ---- keeper: standing orders ----
{
  const {Keeper, parseQuotas, IDLE_MS, COOLDOWN_MS, STOCK_MAX_AGE_MS} = require('./keeper');
  assert.deepStrictEqual(parseQuotas('logs:64, cobblestone:128'), [['logs', 64], ['cobblestone', 128]]);
  assert.deepStrictEqual(parseQuotas(''), []);
  for (const bad of ['logs', 'logs:0', 'Logs:5', 'logs:5000', 'logs:1,logs:2', 'a:b']) assert.throws(() => parseQuotas(bad), bad);
  assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1', KEEPER_QUOTAS: 'coal:32', KEEPER_SITE: '1,2,3'}).keeperSite, {x: 1, y: 2, z: 3});
  assert.throws(() => loadConfig({BOT_NAMES: 'bot1', KEEPER_SITE: '1,2'}));

  let now = 1e6;
  const chest = {x: 1, y: 2, z: 3};
  const world = new WorldModel({now: () => now});
  const fake = (name) => ({name, sent: [], idle: true, online: true, snapshot() { return {online: this.online, dead: false, job: this.idle ? null : {label: 'x'}, queue: []}; }, enqueue(type, args) { this.sent.push([type, args]); this.idle = false; }});
  const bots = [fake('bot1'), fake('bot2'), fake('bot3')];
  const runners = new Map(bots.map((b) => [b.name, b]));
  const {EventLog} = require('./events');
  const events = new EventLog();
  const k = new Keeper({runners, world, chest, quotas: [['logs', 64], ['cobblestone', 128], ['torch', 16], ['diamond', 5]], events, now: () => now});
  assert.throws(() => new Keeper({runners, world, chest: null, quotas: [], now: () => now}).setEnabled(true), /no supply chest/);
  k.tick();
  assert.strictEqual(bots.every((b) => !b.sent.length), true, 'off by default: nothing is assigned');
  assert.strictEqual(k.state().enabled, false);
  k.setEnabled(true);
  k.tick(); // idle bots are only taken after IDLE_MS
  assert.strictEqual(bots.every((b) => !b.sent.length), true);
  now += IDLE_MS;
  k.tick(); // no numbers yet: the first idle bot is sent to count the chest
  assert.deepStrictEqual(bots[0].sent, [['stock', chest]]);
  assert.strictEqual(k.state().counting, 'bot1');
  k.tick();
  assert.strictEqual(bots[1].sent.length, 0, 'only one bot counts');
  // bot1 reports and goes idle again
  world.noteStock('bot1', {oak_log: 20, birch_log: 4, cobblestone: 200, coal: 0});
  bots[0].idle = true;
  now += 6000;
  k.tick();
  const st = k.state();
  assert.deepStrictEqual(st.quotas.map((q) => [q.item, q.have, q.want]), [['logs', 24, 64], ['cobblestone', 200, 128], ['torch', 0, 16], ['diamond', 0, 5]]);
  // logs are short: a chop of the missing 40 and a deposit of logs only, on an idle bot (not the one that just finished)
  const logBot = bots.find((b) => b.sent.some((x) => x[0] === 'chop'));
  assert.ok(logBot && logBot !== bots[0]);
  assert.deepStrictEqual(logBot.sent, [['chop', {count: 40}], ['deposit', {...chest, only: 'logs'}]]);
  assert.strictEqual(k.state().quotas[0].bot, logBot.name);
  assert.match(k.state().quotas[2].note, /needs 4 coal/); // torches wait for coal
  assert.match(k.state().quotas[3].note, /no way to make/);
  assert.strictEqual(k.state().quotas[1].bot, null, 'cobblestone is above its target: no job');
  // cobblestone falls short: a second chain, on another bot
  world.noteStock('bot1', {oak_log: 24, cobblestone: 20, coal: 8});
  k.tick();
  const stoneBot = bots.find((b) => b.sent.some((x) => x[0] === 'mine'));
  assert.ok(stoneBot && stoneBot !== logBot);
  assert.deepStrictEqual(stoneBot.sent, [['mine', {block: 'stone', count: 64}], ['deposit', {...chest, only: 'cobblestone'}]]);
  // the third bot is never used: at most two at once
  now += IDLE_MS; k.tick();
  assert.strictEqual(bots.filter((b) => b.sent.length).length, 3, 'bot1 counted, two worked');
  assert.match(k.state().quotas[2].note, /waiting for a free bot|needs 4 coal/);
  // the log bot finishes but the chest did not get more logs: cooldown, no retry loop
  k.tick();
  logBot.idle = true;
  now += 5000;
  world.noteStock(logBot.name, {oak_log: 24, cobblestone: 20, coal: 8});
  k.tick();
  assert.match(events.items.map((e) => e.text).join('\n'), new RegExp(`${logBot.name} is done with logs, but the chest did not get more \\(24 -> 24\\)`));
  const sentBefore = bots.map((b) => b.sent.length);
  now += IDLE_MS; k.tick(); k.tick();
  assert.ok(bots.every((b) => !b.sent.slice(sentBefore[bots.indexOf(b)]).some((x) => x[0] === 'chop')), 'logs on cooldown: no new chop');
  assert.match(k.state().quotas[0].note, /retrying in \d+ min/);
  for (const b of bots) b.idle = true; // everyone is done (the torch chain started when coal appeared)
  world.noteStock('bot1', {oak_log: 24, cobblestone: 20, coal: 8});
  now += 1000; k.tick(); // chains end, their items cool down
  now += COOLDOWN_MS + 1;
  world.noteStock('bot1', {oak_log: 24, cobblestone: 20, coal: 8});
  k.tick(); now += IDLE_MS; k.tick();
  assert.ok(bots.some((b, i) => b.sent.slice(sentBefore[i]).some((x) => x[0] === 'chop')), 'after the cooldown logs are tried again');
  // old numbers: nothing is planned from them, a bot counts again
  now += STOCK_MAX_AGE_MS + 1;
  const n0 = bots.reduce((n, b) => n + b.sent.length, 0);
  for (const b of bots) b.idle = true;
  k.work.clear(); k.counting = null; k.idleSince.clear();
  k.tick(); now += IDLE_MS; k.tick();
  assert.ok(bots.some((b) => b.sent.at(-1)?.[0] === 'stock') && bots.reduce((n, b) => n + b.sent.length, 0) === n0 + 1);
  // off again: nothing more is assigned
  k.setEnabled(false);
  const n1 = bots.reduce((n, b) => n + b.sent.length, 0);
  k.tick();
  assert.strictEqual(bots.reduce((n, b) => n + b.sent.length, 0), n1);
  // a busy bot and an offline bot are never taken
  k.setEnabled(true);
  for (const b of bots) { b.idle = false; }
  bots[1].idle = true; bots[1].online = false;
  k.idleSince.clear(); now += IDLE_MS; k.tick(); now += IDLE_MS; k.tick();
  assert.strictEqual(bots.reduce((n, b) => n + b.sent.length, 0), n1);
  // torches: 4 coal and a log in the chest allow a chain that takes both, crafts and puts the torches back
  const {PLANS} = require('./keeper');
  assert.deepStrictEqual(PLANS.torch(16, chest, {coal: 4, birch_log: 1}).map((j) => j[0]), ['withdraw', 'withdraw', 'craft', 'deposit']);
  assert.match(PLANS.torch(16, chest, {coal: 3, oak_log: 1}).blocked, /4 coal/);
  assert.match(PLANS.torch(16, chest, {coal: 4}).blocked, /log/);
  // chain arguments pass the real validators (the bots would refuse them otherwise)
  const {VALIDATE: V} = require('./bots');
  for (const [type, args] of [...PLANS.logs(40, chest), ...PLANS.cobblestone(64, chest), ...PLANS.coal(8, chest), ...PLANS.torch(16, chest, {coal: 9, oak_log: 3}), ['stock', chest], ['goto', chest]]) assert.doesNotThrow(() => V[type](args), type);
  assert.throws(() => V.deposit({...chest, only: 'Bad Name'}));
  assert.deepStrictEqual(V.deposit(chest), chest); // plain deposits are unchanged
}
// ---- a death or disconnect keeps the job; the user's stop does not ----
(async () => {
  const mk = () => new BotRunner('bot1', {host: 'x', port: 1, log: () => {}, world: null, onEvent: () => {}});
  const r = mk();
  const job = {id: 5, type: 'mine', args: {block: 'stone', count: 40}, collected: 12, status: 'running', t: {area: {x: 1, y: 2, z: 3}}, startPos: {x: 9, y: 9, z: 9}};
  r.resumeLater(job, 'died');
  assert.strictEqual(r.queue.length, 1);
  const back = r.queue[0];
  assert.deepStrictEqual([back.id, back.type, back.collected, back.status, back.cancelled, back.resume, back.interruptions], [5, 'mine', 12, 'queued', false, {x: 1, y: 2, z: 3}, 1]);
  assert.strictEqual(job.interrupted, true);
  r.queue = [];
  r.resumeLater({...job, t: undefined}, 'disconnected'); // no dig yet: back to where the job started
  assert.deepStrictEqual(r.queue[0].resume, {x: 9, y: 9, z: 9});
  r.queue = [];
  r.resumeLater({id: 6, type: 'craft', args: {item: 'torch', count: 4}}, 'died'); // crafting is not resumed
  r.resumeLater({id: 7, type: 'rearm', args: {x: 1, y: 2, z: 3}}, 'died');
  r.resumeLater(null, 'died');
  assert.strictEqual(r.queue.length, 0);
  let j = job;
  for (let i = 0; i < 3; i++) { r.resumeLater(j, 'died'); j = r.queue.shift(); }
  assert.strictEqual(j.interruptions, 3);
  r.resumeLater(j, 'died'); // the fourth time it is given up
  assert.strictEqual(r.queue.length, 0);
  // nothing runs while dead or (for a resumed job) offline
  const q = mk();
  let ran = 0;
  const {JOBS} = require('./bots');
  const goto = JOBS.goto;
  JOBS.goto = () => { ran++; };
  q.online = true; q.dead = true;
  q.queue = [{id: 1, type: 'goto', args: {x: 1, y: 2, z: 3}, status: 'queued'}];
  q.pump();
  assert.strictEqual(ran, 0);
  q.dead = false; q.online = false;
  q.queue[0].resume = true;
  q.pump();
  assert.strictEqual(ran, 0);
  q.online = true;
  q.pump();
  await new Promise((res) => setTimeout(res, 50));
  assert.strictEqual(ran, 1);
  JOBS.goto = goto;
})();
// A job that had nothing to do says so in its finished event; the agent reads it.
(async () => {
  const {JOBS} = require('./bots');
  const seen = [];
  const q = new BotRunner('bot1', {host: 'x', port: 1, log: () => {}, world: null, onEvent: (b, k, t) => seen.push(`${k}: ${t}`)});
  q.online = true;
  const goto = JOBS.goto;
  JOBS.goto = (r, job) => { job.noop = job.args.x === 1; };
  q.enqueue('goto', {x: 1, y: 2, z: 3});
  for (let i = 0; i < 100 && !seen.some((e) => e.startsWith('done')); i++) await new Promise((res) => setTimeout(res, 20));
  q.enqueue('goto', {x: 2, y: 2, z: 3});
  for (let i = 0; i < 100 && seen.filter((e) => e.startsWith('done')).length < 2; i++) await new Promise((res) => setTimeout(res, 20));
  JOBS.goto = goto;
  const done = seen.filter((e) => e.startsWith('done'));
  assert.match(done[0], /^done: finished: goto 1 2 3 - already complete \(\d+ s\)$/);
  assert.match(done[1], /^done: finished: goto 2 2 3 \(\d+ s\)$/, 'a job that worked has no such note');
})();
// A job queued after "stop" must survive the stopped job winding down.
(async () => {
  const {JOBS} = require('./bots');
  const q = new BotRunner('bot1', {host: 'x', port: 1, log: () => {}, world: null});
  q.online = true;
  let release;
  const said = [];
  JOBS.say = (r, job) => (said.push(job.args.text), job.args.text === 'slow' ? new Promise((res) => (release = res)) : null);
  q.enqueue('say', {text: 'slow'});
  q.enqueue('stop');
  q.enqueue('say', {text: 'next'});
  release();
  for (let i = 0; i < 150 && said.length < 2; i++) await new Promise((res) => setTimeout(res, 20));
  assert.deepStrictEqual(said, ['slow', 'next']);

  // in-game view: stone floor at y=60, a gold block straight ahead (-z), sky above
  const {render, cast} = require('./view');
  const world = (x, y, z) => (y <= 60 ? 'stone' : x === 0 && z === -5 && y === 61 ? 'gold_block' : 'air');
  assert.strictEqual(cast(world, 0.5, 61.5, 0.5, 0, 0, -1).name, 'gold_block', 'yaw 0 looks to -z');
  assert.strictEqual(cast(world, 0.5, 61.5, 0.5, 0, -1, 0).name, 'stone');
  assert.strictEqual(cast((x, y, z) => (z < -3 ? null : 'air'), 0.5, 61.5, 0.5, 0, 0, -1), null, 'unloaded chunk');
  const img = render({blockAt: world, eye: {x: 0.5, y: 61.6, z: 0.5}, yaw: 0, pitch: 0, w: 16, h: 9});
  assert.deepStrictEqual([...img.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10], 'PNG signature');
  const raw = require('node:zlib').inflateSync(img.subarray(41, img.length - 12)); // IHDR is 25 bytes after the signature
  const px = (x, y) => [...raw.subarray(y * 49 + 1 + x * 3, y * 49 + 4 + x * 3)];
  assert.deepStrictEqual(px(8, 0), [135, 175, 235], 'sky at the top');
  assert.ok(px(8, 8)[0] < 135 && px(8, 8)[2] < 200, 'floor at the bottom: ' + px(8, 8));
  // a frame never runs past its deadline: past deadline = all sky; a slow world stops early
  const skyOnly = require('node:zlib').inflateSync((() => { const i = render({blockAt: world, eye: {x: 0.5, y: 61.6, z: 0.5}, yaw: 0, pitch: 0, w: 16, h: 9, deadline: 0}); return i.subarray(41, i.length - 12); })());
  assert.deepStrictEqual([...skyOnly.subarray(8 * 49 + 1 + 24, 8 * 49 + 4 + 24)], [135, 175, 235], 'past the deadline the floor is not cast');
  const slow = (x, y, z) => { const end = Date.now() + 1; while (Date.now() < end); return world(x, y, z); };
  let t0 = Date.now();
  render({blockAt: slow, eye: {x: 0.5, y: 61.6, z: 0.5}, yaw: 0, pitch: 0, w: 256, h: 144, deadline: t0 + 50});
  assert.ok(Date.now() - t0 < 400, `a slow frame stops near its deadline (${Date.now() - t0} ms)`);
  // botView reads block state ids (no Block object per step); unloaded columns stay unloaded
  const {botView} = require('./view');
  const vbot = {entity: {position: {x: 0.5, y: 61, z: 0.5, distanceTo: () => 0}, yaw: 0, pitch: -1.2, eyeHeight: 1.62}, entities: {},
    registry: {blocksByStateId: {0: {name: 'air'}, 1: {name: 'stone'}}},
    world: {getColumnAt: (p) => (p.z < -20 ? null : {}), getBlockStateId: (p) => (p.y <= 60 ? 1 : 0)}};
  const vraw = require('node:zlib').inflateSync((() => { const i = botView(vbot, {w: 16, h: 9}); return i.subarray(41, i.length - 12); })());
  assert.ok(vraw[8 * 49 + 1 + 24] < 135, 'looking down at stone');

  // settings: validated, merged over defaults, kept across a restart in STATE_DIR
  const {Settings, DEFAULTS} = require('./settings');
  const dir = require('node:fs').mkdtempSync(require('node:path').join(require('node:os').tmpdir(), 'mcbots-'));
  const st = new Settings(dir);
  assert.deepStrictEqual(st.get('bot1'), DEFAULTS);
  assert.deepStrictEqual(st.set('bot1', {fightRange: 12, defend: false, junk: 1}), {...DEFAULTS, fightRange: 12, defend: false});
  assert.throws(() => st.set('bot1', {fightRange: 99}), /fightRange/);
  assert.throws(() => st.set('bot1', {defend: 'yes'}), /defend/);
  assert.deepStrictEqual(new Settings(dir).get('bot1'), {...DEFAULTS, fightRange: 12, defend: false}, 'survives a restart');
  assert.deepStrictEqual(new Settings('').get('bot1'), DEFAULTS, 'no STATE_DIR: memory only');

  // safe digging: fluids next to the target, or a drop under the bot's feet
  const {unsafeDig} = require('./bots');
  const {Vec3} = require('vec3');
  const fake = (blocks, feet) => ({entity: {position: new Vec3(feet[0] + 0.5, feet[1], feet[2] + 0.5)}, blockAt: (p) => ({name: blocks[`${p.x},${p.y},${p.z}`] || 'stone', boundingBox: (blocks[`${p.x},${p.y},${p.z}`] || 'stone') === 'stone' ? 'block' : 'empty'})});
  assert.strictEqual(unsafeDig(fake({}, [0, 10, 0]), new Vec3(3, 10, 0)), null, 'plain stone is fine');
  assert.match(unsafeDig(fake({'4,10,0': 'water'}, [0, 10, 0]), new Vec3(3, 10, 0)), /water next to it/);
  assert.match(unsafeDig(fake({'3,11,0': 'lava'}, [0, 10, 0]), new Vec3(3, 10, 0)), /lava/);
  assert.strictEqual(unsafeDig(fake({'0,8,0': 'air', '0,7,0': 'air'}, [0, 10, 0]), new Vec3(0, 9, 0)), null, 'a drop of 3 is fine');
  assert.match(unsafeDig(fake({'0,8,0': 'air', '0,7,0': 'air', '0,6,0': 'air', '0,5,0': 'air'}, [0, 10, 0]), new Vec3(0, 9, 0)), /drop/);
  assert.match(unsafeDig(fake({'0,8,0': 'air', '0,7,0': 'lava'}, [0, 10, 0]), new Vec3(0, 9, 0)), /lava below/);

  // places: validated, replaced by name, kept across a restart; first supply wins
  const {Places} = require('./places');
  const pdir = require('node:fs').mkdtempSync(require('node:path').join(require('node:os').tmpdir(), 'mcbots-p-'));
  const pl = new Places(pdir);
  pl.set({name: 'Forest', kind: 'site', x: -258, y: 65, z: -210});
  pl.set({name: 'Main chest', kind: 'supply', x: '-260', y: '65', z: '-213'});
  assert.deepStrictEqual(pl.first('supply'), {name: 'Main chest', kind: 'supply', dim: 'overworld', x: -260, y: 65, z: -213});
  pl.set({name: 'Forest', kind: 'site', x: -250, y: 66, z: -200});
  assert.strictEqual(pl.list.length, 2, 'same name replaces');
  assert.throws(() => pl.set({name: 'x', kind: 'castle', x: 0, y: 0, z: 0}), /kind/);
  assert.throws(() => pl.set({name: '<script>', kind: 'site', x: 0, y: 0, z: 0}), /name/);
  assert.throws(() => pl.set({name: 'deep', kind: 'site', x: 0, y: 999, z: 0}), /y must/);
  assert.deepStrictEqual(new Places(pdir).list.map((p) => [p.name, p.x]), [['Forest', -250], ['Main chest', -260]], 'survives a restart');
  pl.remove('Forest');
  assert.throws(() => pl.remove('Forest'), /no place/);

  // MC-2: sealing never changes a neighbour inside a protected area, and honours a stop
  {
    const {sealFluids, Cancelled} = require('./bots');
    const {Vec3} = require('vec3');
    const make = (blocks, areas, onPlace) => {
      const placed = [];
      const bot = {
        blockAt: (p) => { const name = blocks[`${p.x},${p.y},${p.z}`]; return name ? {name, position: new Vec3(p.x, p.y, p.z)} : null; },
        inventory: {items: () => [{name: 'cobblestone'}]},
        equip: async () => {},
        placeBlock: async (target, face) => { const at = target.position.plus(face); placed.push(`${at.x},${at.y},${at.z}`); blocks[`${at.x},${at.y},${at.z}`] = 'cobblestone'; onPlace?.(); },
      };
      return {r: {bot, protectedAreas: areas, emit() {}}, placed};
    };
    const T = new Vec3(10, 64, 0);
    // ore outside the boundary, water inside it: no sealing, nothing placed, target stays unmined (false)
    let w = make({'10,64,0': 'diamond_ore', '11,64,0': 'water'}, [[11, -5, 20, 5]]);
    assert.strictEqual(await sealFluids(w.r, {cancelled: false}, T), false);
    assert.deepStrictEqual(w.placed, []);
    // one forbidden neighbour among several: still nothing placed, not even on the allowed one
    w = make({'10,64,0': 'diamond_ore', '10,65,0': 'water', '11,64,0': 'lava'}, [[11, -5, 20, 5]]);
    assert.strictEqual(await sealFluids(w.r, {cancelled: false}, T), false);
    assert.deepStrictEqual(w.placed, []);
    // an unprotected neighbour is sealed
    w = make({'10,64,0': 'diamond_ore', '11,64,0': 'water'}, [[100, 100, 110, 110]]);
    assert.strictEqual(await sealFluids(w.r, {cancelled: false}, T), true);
    assert.deepStrictEqual(w.placed, ['11,64,0']);
    // a stop during sealing: the first placement happens, the second never does
    const job = {cancelled: false};
    w = make({'10,64,0': 'diamond_ore', '11,64,0': 'water', '10,65,0': 'water'}, [], () => { job.cancelled = true; });
    await assert.rejects(sealFluids(w.r, job, T), Cancelled);
    assert.strictEqual(w.placed.length, 1, 'no placement after the stop');
  }

  // guard job arguments
  const gq = new BotRunner('bot2', {host: 'x', port: 1, log: () => {}, world: null});
  gq.online = true;
  JOBS.guard = () => new Promise(() => {}); // never ends; we only check the queued args
  gq.enqueue('guard', {x: '1', y: '64', z: '-3'});
  assert.deepStrictEqual(gq.current?.args || gq.queue[0]?.args, {x: 1, y: 64, z: -3, radius: 16});
  assert.throws(() => gq.enqueue('guard', {player: 'Steve', radius: 99}), /radius/);
  assert.throws(() => gq.enqueue('guard', {player: 'bad name!'}), /player/);
  console.log('ok');
})();

// MC-1: Stop is decided by the server: standing orders off, saved jobs dropped (also those waiting
// for an offline bot), persistence before the answer, a worker that is away reported, not claimed.
(async () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const net = require('node:net');
  const {spawn} = require('node:child_process');
  const WebSocket = require('ws');
  const freePort = () => new Promise((res) => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => res(p)); }); });
  const TOKEN = 'c0ffee11'.repeat(5);
  const H = {'tailscale-user-login': 'a@github'};
  const launch = async (dir) => {
    const port = await freePort();
    const wport = await freePort();
    const child = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
      env: {PATH: process.env.PATH, NODE_PATH: process.env.NODE_PATH || '', BOT_NAMES: 'bot1,bot2', STATE_DIR: dir, SUPPLY_CHEST: '1,64,1', KEEPER_QUOTAS: 'logs:64', WORKER_PORT: String(wport), WORKER_TOKEN: TOKEN, DASHBOARD_PORT: String(port), DASHBOARD_HOST: '127.0.0.1', ALLOWED_TS_LOGINS: 'a@github', MC_HOST: '127.0.0.1', MC_PORT: '1', BOT_PASSWORD_SEED: 'test'},
      stdio: ['ignore', 'pipe', 'inherit'],
    });
    await new Promise((res, rej) => {
      const to = setTimeout(() => rej(new Error('server did not start')), 8000);
      child.stdout.on('data', (b) => { if (String(b).includes('listening')) { clearTimeout(to); res(); } });
      child.on('exit', (c) => rej(new Error(`server exited early (${c})`)));
    });
    const call = (pth, body) => fetch(`http://127.0.0.1:${port}${pth}`, {method: 'POST', headers: {'content-type': 'application/json', origin: `http://127.0.0.1:${port}`, ...H}, body: JSON.stringify(body)});
    const get = async (pth) => (await fetch(`http://127.0.0.1:${port}${pth}`, {headers: H})).json();
    const stop = () => new Promise((res) => { child.once('exit', res); child.kill('SIGINT'); });
    return {port, wport, call, get, stop};
  };
  const saved = (dir) => JSON.parse(fs.readFileSync(path.join(dir, 'jobs.json'), 'utf8'));
  const jobs = {bot1: [{type: 'shift', args: {block: 'logs', x: 1, y: 64, z: 1}}], bot2: [{type: 'guard', args: {x: 5, y: 64, z: 5, radius: 16}}]};
  const dirA = fs.mkdtempSync(path.join(os.tmpdir(), 'mcbots-stopA-'));
  fs.writeFileSync(path.join(dirA, 'jobs.json'), JSON.stringify(jobs));

  // A: keeper on, saved jobs waiting for offline bots, a worker that joined and left
  let a = await launch(dirA);
  try {
    assert.strictEqual((await (await a.call('/api/keeper', {enabled: true})).json()).enabled, true);
    const wk = await new Promise((res, rej) => { const ws = new WebSocket(`ws://127.0.0.1:${a.wport}/worker`, {headers: {Authorization: `Bearer ${TOKEN}`}}); ws.on('open', () => res(ws)); ws.on('error', rej); });
    wk.send(JSON.stringify({t: 'hello', v: 1, host: 'laptop', bots: ['bot5']}));
    for (let i = 0; i < 100 && !(await a.get('/api/state')).bots.some((b) => b.name === 'bot5'); i++) await new Promise((r) => setTimeout(r, 50));
    wk.close();
    for (let i = 0; i < 100 && (await a.get('/api/state')).bots.find((b) => b.name === 'bot5')?.connected; i++) await new Promise((r) => setTimeout(r, 50));
    assert.deepStrictEqual(saved(dirA), jobs, 'pending jobs are kept while their bots are away');
    const res = await a.call('/api/job', {bots: 'all', type: 'stop'});
    const body = await res.json();
    assert.strictEqual(res.status, 200);
    assert.strictEqual(body.keeperOff, true);
    assert.deepStrictEqual(body.unreached, ['bot5'], 'the absent worker is reported, not claimed as stopped');
    assert.deepStrictEqual(saved(dirA), {}, 'persisted before the answer: nothing can come back');
    assert.strictEqual((await a.get('/api/state')).keeper.enabled, false);
  } finally {
    await a.stop();
  }
  // stop followed by a process restart: nothing resumes, standing orders stay off
  a = await launch(dirA);
  try {
    await new Promise((r) => setTimeout(r, 2500)); // longer than the 2 s resume/save tick
    assert.deepStrictEqual((await a.get('/api/events?since=0')).events.filter((e) => /resumed/.test(e.text)), []);
    assert.strictEqual((await a.get('/api/state')).keeper.enabled, false);
    assert.deepStrictEqual(saved(dirA), {});
  } finally {
    await a.stop();
  }

  // B: per-bot stop drops only that bot's saved jobs; a failed state write is reported, not hidden
  const dirB = fs.mkdtempSync(path.join(os.tmpdir(), 'mcbots-stopB-'));
  fs.writeFileSync(path.join(dirB, 'jobs.json'), JSON.stringify(jobs));
  const b = await launch(dirB);
  try {
    const one = await b.call('/api/job', {bots: ['bot1'], type: 'stop'});
    assert.strictEqual(one.status, 200);
    assert.deepStrictEqual(saved(dirB), {bot2: jobs.bot2}, "only bot1's saved job is gone");
    fs.rmSync(path.join(dirB, 'jobs.json'));
    fs.mkdirSync(path.join(dirB, 'jobs.json')); // writes now fail
    const bad = await b.call('/api/job', {bots: ['bot2'], type: 'stop'});
    assert.strictEqual(bad.status, 500);
    assert.match((await bad.json()).error, /stopped, but the stopped state could not be saved/);
  } finally {
    await b.stop();
  }

  // C: worker bots - settings are forwarded and kept, kept jobs come back once the worker is connected again
  const dirC = fs.mkdtempSync(path.join(os.tmpdir(), 'mcbots-workerC-'));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const until = async (f, what, ms = 6000) => {
    for (let t = 0; t < ms; t += 50) {
      const v = await f();
      if (v) return v;
      await sleep(50);
    }
    throw new Error(`timed out: ${what}`);
  };
  const worker = (s, status) => new Promise((res, rej) => {
    const ws = new WebSocket(`ws://127.0.0.1:${s.wport}/worker`, {headers: {Authorization: `Bearer ${TOKEN}`}});
    const msgs = [];
    ws.on('message', (d) => msgs.push(JSON.parse(String(d))));
    ws.on('open', () => {
      ws.send(JSON.stringify({t: 'hello', v: 1, host: 'laptop', bots: ['bot5']}));
      if (status) ws.send(JSON.stringify({t: 'status', bots: [{name: 'bot5', online: true, ...status}]}));
      res({ws, msgs});
    });
    ws.on('error', rej);
  });
  const shift = {type: 'shift', args: {block: 'logs', x: 1, y: 64, z: 1}};
  let c = await launch(dirC);
  try {
    let w = await worker(c, {kept: [shift]});
    const welcome = await until(() => w.msgs.find((m) => m.t === 'welcome'), 'welcome');
    assert.strictEqual(welcome.settings.bot5.defend, true, 'defaults travel with the welcome');
    await until(async () => (await c.get('/api/state')).bots.find((b) => b.name === 'bot5')?.online, 'bot5 online');
    assert.strictEqual((await c.get('/api/state')).bots.find((b) => b.name === 'bot5').settings.eatBelow, 15, 'the dashboard shows remote settings like local ones');
    assert.strictEqual((await c.call('/api/settings', {bot: 'bot5', settings: {defend: false, eatBelow: 10}})).status, 200);
    const frame = await until(() => w.msgs.find((m) => m.t === 'settings'), 'settings frame');
    assert.deepStrictEqual([frame.bot, frame.settings.defend, frame.settings.eatBelow], ['bot5', false, 10]);
    for (const bad of [{eatBelow: 99}, {defend: 'yes'}]) {
      assert.strictEqual((await c.call('/api/settings', {bot: 'bot5', settings: bad})).status, 400);
    }
    assert.strictEqual((await c.call('/api/settings', {bot: 'bot99', settings: {defend: false}})).status, 400);
    assert.strictEqual(w.msgs.filter((m) => m.t === 'settings').length, 1, 'refused settings never reach the worker');
    await until(() => { try { return saved(dirC).bot5; } catch { return null; } }, 'worker job saved', 5000);
    assert.deepStrictEqual(saved(dirC).bot5, [shift]);
    w.ws.close();
    await until(async () => !(await c.get('/api/state')).bots.find((b) => b.name === 'bot5').connected, 'worker gone');
    assert.strictEqual((await c.call('/api/settings', {bot: 'bot5', settings: {torches: false}})).status, 200, 'accepted while the worker is away');
    await sleep(2200);
    assert.deepStrictEqual(saved(dirC).bot5, [shift], 'its job stays in the file while the worker is away');
  } finally {
    await c.stop();
  }
  // hub restart: the worker connects, the idle bot gets its settings and its shift back
  c = await launch(dirC);
  try {
    const w = await worker(c, {job: null, queue: []});
    const welcome = await until(() => w.msgs.find((m) => m.t === 'welcome'), 'welcome after restart');
    assert.deepStrictEqual([welcome.settings.bot5.defend, welcome.settings.bot5.eatBelow, welcome.settings.bot5.torches], [false, 10, false], 'settings survive a hub restart');
    const job = await until(() => w.msgs.find((m) => m.t === 'job'), 'shift resumed', 5000);
    assert.deepStrictEqual([job.bot, job.type, job.args], ['bot5', 'shift', shift.args]);
    assert.ok((await c.get('/api/events?since=0')).events.some((e) => e.bot === 'bot5' && /resumed after restart: shift/.test(e.text)));
    w.ws.close();
  } finally {
    await c.stop();
  }
  // a worker that kept playing through the hub restart is not given the job twice
  fs.writeFileSync(path.join(dirC, 'jobs.json'), JSON.stringify({bot5: [shift]}));
  c = await launch(dirC);
  try {
    const w = await worker(c, {job: {label: 'shift logs', type: 'shift'}, queue: [], kept: [shift]});
    await until(async () => (await c.get('/api/state')).bots.find((b) => b.name === 'bot5')?.online, 'busy bot online');
    await sleep(2500);
    assert.deepStrictEqual(w.msgs.filter((m) => m.t === 'job'), []);
    assert.deepStrictEqual(saved(dirC).bot5, [shift], 'its reported job stays saved');
    // Stop all reaches it and empties the file at once (the worker's old report is not trusted)
    assert.strictEqual((await c.call('/api/job', {bots: 'all', type: 'stop'})).status, 200);
    assert.deepStrictEqual(saved(dirC), {});
    await until(() => w.msgs.find((m) => m.t === 'job' && m.type === 'stop'), 'stop forwarded');
    w.ws.close();
  } finally {
    await c.stop();
  }
  console.log('ok');
})();

// B3: build() takes what it lacks from the supply chest, only that, never when removing.
(async () => {
  const B = require('./build');
  const {Vec3} = require('vec3');
  const bpArgs = (remove = false) => ({origin: {x: 0, y: 64, z: 0}, blocks: Array.from({length: 9}, (_, i) => ({x: i % 3, y: 0, z: Math.floor(i / 3), block: 'cobblestone'})), remove});
  // r.bot: ground below y 64, air above; the carried inventory is a mutable list.
  const fake = (carried, supplyChest = {x: 5, y: 64, z: 5}) => {
    const items = carried.map(([name, count]) => ({name, count}));
    const mv = {exclusionAreasBreak: [], exclusionAreasPlace: [], scafoldingBlocks: []};
    const bot = {game: {dimension: 'minecraft:overworld'}, pathfinder: {movements: mv}, registry: {itemsByName: {cobblestone: {id: 1}}},
      blockAt: (p) => ({name: p.y < 64 ? 'stone' : 'air', position: p}), inventory: {items: () => items}};
    return {r: {bot, protectedAreas: [], supplyChest, name: 'bot6'}, items};
  };
  const run = (r, withdraw, args, passedAfter = null) => {
    let guards = 0;
    const guard = () => { if (passedAfter !== null && guards++ >= passedAfter) throw new Error('passed-check'); };
    const build = B.makeBuild({goNear: async () => {}, guard, sleep: async () => {}, goals: {}, digAt: async () => {}, withdraw});
    return build(r, {args, t: {}});
  };
  const calls = [];
  const give = (f) => async (r, job, item, count) => { calls.push([item, count]); f(item, count); };
  // 5 carried, 4 missing: exactly 4 are taken, then the build goes on (the first guard of the place loop ends the test)
  let f = fake([['cobblestone', 5]]);
  await assert.rejects(run(f.r, give((item, n) => f.items[0].count += n), bpArgs(), 3), /passed-check/);
  assert.deepStrictEqual(calls, [['cobblestone', 4]], 'only the missing count is taken');
  // nothing carried, chest has no cobblestone: the item error is absorbed, the recount names the shortage
  calls.length = 0;
  f = fake([]);
  await assert.rejects(run(f.r, async (r, j, item, n) => { calls.push([item, n]); throw new Error(`no ${item} in the chest`); }, bpArgs()), /missing material: 9 cobblestone \(not in the supply chest either\)/);
  assert.deepStrictEqual(calls, [['cobblestone', 9]]);
  // the chest holds only 3 of 9: still short by 6
  f = fake([]);
  await assert.rejects(run(f.r, give((item, n) => f.items.push({name: item, count: 3})), bpArgs()), /missing material: 6 cobblestone \(not in the supply chest either\)/);
  // another error (no chest there) is not hidden
  f = fake([]);
  await assert.rejects(run(f.r, async () => { throw new Error('no chest at 5 64 5 (found air)'); }, bpArgs()), /no chest at 5 64 5/);
  // no supply chest configured: the plain message, no withdraw attempt
  calls.length = 0;
  f = fake([], null);
  await assert.rejects(run(f.r, give(() => {}), bpArgs()), (e) => e.message === 'missing material: 9 cobblestone');
  assert.deepStrictEqual(calls, []);
  // remove mode never withdraws (the blocks are in the world, nothing to carry)
  f = fake([]);
  f.r.bot.blockAt = (p) => ({name: p.y === 64 && p.x < 3 && p.z < 3 ? 'cobblestone' : p.y < 64 ? 'stone' : 'air', position: p});
  await assert.rejects(run(f.r, give(() => {}), bpArgs(true), 1), /passed-check|no record/); // no record of placing it (MC-3): refused even earlier
  assert.deepStrictEqual(calls, [], 'no withdraw in remove mode');
  // a stop between items ends the build before the next withdraw
  calls.length = 0;
  f = fake([]);
  const two = {origin: {x: 0, y: 64, z: 0}, blocks: [{x: 0, y: 0, z: 0, block: 'cobblestone'}, {x: 1, y: 0, z: 0, block: 'dirt'}]};
  f.r.bot.registry.itemsByName.dirt = {id: 2};
  await assert.rejects(run(f.r, async (r, j, item, n) => { calls.push([item, n]); f.items.push({name: item, count: n}); }, two, 1), /passed-check/);
  assert.strictEqual(calls.length, 1, 'a stop during the withdrawals prevents the next one');
  // B4: what the chest lacks is gathered, once, in order; a stop ends it; the cap holds
  {
    const runs = [];
    const gather = (f, after) => async (r, j, type, args) => {
      runs.push([type, args.block || args.item, args.count]);
      if (type === 'mine') f.items.push({name: 'cobblestone', count: args.count});
      if (after) after(type, args);
    };
    // chest has 3, 6 are mined; the chest is asked first
    calls.length = 0;
    f = fake([]);
    await assert.rejects(B.makeBuild({goNear: async () => {}, guard: () => { if (runs.length) throw new Error('passed-check'); }, sleep: async () => {}, goals: {}, digAt: async () => {},
      withdraw: async (r, j, item, n) => { calls.push([item, n]); f.items.push({name: item, count: 3}); }, runJob: gather(f)})(f.r, {args: bpArgs(), t: {}}), /passed-check/);
    assert.deepStrictEqual(calls, [['cobblestone', 9]]);
    assert.deepStrictEqual(runs, [['mine', 'stone', 6]], 'only the rest is gathered');
    // no chest at all: gathers the whole 9
    runs.length = 0;
    f = fake([], null);
    await assert.rejects(B.makeBuild({goNear: async () => {}, guard: () => { if (runs.length) throw new Error('passed-check'); }, sleep: async () => {}, goals: {}, digAt: async () => {}, runJob: gather(f)})(f.r, {args: bpArgs(), t: {}}), /passed-check/);
    assert.deepStrictEqual(runs, [['mine', 'stone', 9]]);
    // something nobody can gather: refused before any job runs
    runs.length = 0;
    f = fake([]);
    const planks = {origin: {x: 0, y: 64, z: 0}, blocks: [{x: 0, y: 0, z: 0, block: 'oak_planks'}, {x: 1, y: 0, z: 0, block: 'cobblestone'}]};
    await assert.rejects(B.makeBuild({goNear: async () => {}, guard: () => {}, sleep: async () => {}, goals: {}, digAt: async () => {}, withdraw: async () => { throw new Error('no oak_planks in the chest'); }, runJob: gather(f)})(f.r, {args: planks, t: {}}), /cannot gather 1 oak_planks yet/);
    assert.deepStrictEqual(runs, []);
    // a stop between two gather jobs ends it
    runs.length = 0;
    f = fake([], null);
    let ctxCalls = 0;
    await assert.rejects(B.makeBuild({goNear: async () => {}, guard: () => { if (runs.length >= 1) throw new Error('stopped'); }, sleep: async () => {}, goals: {}, digAt: async () => {},
      runJob: gather(f), gatherContext: () => { ctxCalls++; return {furnace: false, wood: true, hasFuel: () => true}; }})(f.r, {args: {...planks, blocks: [{x: 0, y: 0, z: 0, block: 'stone'}]}, t: {}}), /stopped/);
    assert.strictEqual(runs.length, 1, 'the smelt after the mine never started');
    assert.strictEqual(ctxCalls, 1);
    // drops lost: a second round, then the 2x cap ends it (9 blocks: 9 + 9 gathered, a third round would pass 18)
    runs.length = 0;
    f = fake([], null);
    await assert.rejects(B.makeBuild({goNear: async () => {}, guard: () => {}, sleep: async () => {}, goals: {}, digAt: async () => {}, runJob: async (r, j, type, args) => { runs.push([type, args.count]); }})(f.r, {args: bpArgs(), t: {}}),
      /missing material: 9 cobblestone \(gathered 18, the limit is 18\)/);
    assert.deepStrictEqual(runs, [['mine', 9], ['mine', 9]]);
  }
  // build orchestration with a fake bot (MC-3): Stop, provenance, failed digs, no-progress deadline
  {
    const B = require('./build');
    const fakeRun = ({preset = [], equipStops = false, digOk = true, claimOk = true} = {}) => {
      const blocks = new Map(preset.map((k) => [k, 'cobblestone']));
      const name = (v) => blocks.get(`${v.x},${v.y},${v.z}`) ?? (v.y <= 63 ? 'stone' : 'air');
      const job = {t: {}, cancelled: false};
      const log = {placed: 0, expects: []};
      const mv = {exclusionAreasBreak: [], exclusionAreasPlace: [], scafoldingBlocks: [1, 2]};
      const bot = {game: {dimension: 'overworld'}, pathfinder: {movements: mv}, world: {},
        registry: {itemsByName: {cobblestone: {id: 1}}},
        inventory: {items: () => [{name: 'cobblestone', count: 64, type: 1}]},
        blockAt: (v) => ({name: name(v), position: v}),
        equip: async () => { if (equipStops) job.cancelled = true; },
        placeBlock: async (against, face) => { log.placed++; const t = against.position.plus(face); blocks.set(`${t.x},${t.y},${t.z}`, 'cobblestone'); }};
      const r = {bot, protectedAreas: [], name: 'b', world: claimOk ? null : {claim: async () => false, release() {}}, conflict() {}};
      const guard = (j) => { if (j.cancelled) throw new Error('stopped'); };
      const build = B.makeBuild({goNear: async () => {}, guard, sleep: async () => new Promise((res) => setTimeout(res, 5)), goals: {GoalPlaceBlock: class {}}, withdraw: async () => {},
        digAt: async (rr, jj, p, expect) => { log.expects.push(expect); if (!digOk) return false; blocks.delete(`${p.x},${p.y},${p.z}`); return true; }, waitMs: 50});
      return {build, r, job, blocks, log, mv};
    };
    const pad = (o, extra = {}) => ({origin: o, blocks: [0, 1, 2].map((x) => ({x, y: 0, z: 0, block: 'cobblestone'})), ...extra});
    let f = fakeRun({equipStops: true}); // a Stop during the equip places nothing; pathfinder settings come back
    f.job.args = pad({x: 500, y: 64, z: 500});
    await assert.rejects(f.build(f.r, f.job), /stopped/);
    assert.strictEqual(f.log.placed, 0, 'nothing placed after Stop');
    assert.deepStrictEqual([f.mv.exclusionAreasBreak.length, f.mv.exclusionAreasPlace.length, f.mv.scafoldingBlocks], [0, 0, [1, 2]], 'settings restored');
    f = fakeRun({preset: ['600,64,600']}); // build next to a pre-existing block, then remove: only ours come out
    f.job.args = pad({x: 600, y: 64, z: 600});
    await f.build(f.r, f.job);
    assert.strictEqual(f.log.placed, 2);
    assert.ok(!f.job.noop, 'a build that placed blocks is not "already complete"');
    const again = {t: {}, cancelled: false, args: pad({x: 600, y: 64, z: 600})};
    await f.build(f.r, again);
    assert.strictEqual(again.noop, true, 'a second build of the finished blueprint had nothing to do');
    assert.strictEqual(f.log.placed, 2);
    f.job.args = pad({x: 600, y: 64, z: 600}, {remove: true});
    await f.build(f.r, f.job);
    assert.deepStrictEqual([...f.blocks.keys()], ['600,64,600'], 'the pre-existing block stays');
    assert.ok(f.log.expects.length && f.log.expects.every((e) => e && e('cobblestone') && !e('torch')), 'removal digs only the recorded block type');
    f = fakeRun(); // remove without a record is refused
    f.job.args = pad({x: 700, y: 64, z: 700}, {remove: true});
    await assert.rejects(f.build(f.r, f.job), /no record/);
    const g = fakeRun({digOk: false}); // a dig that never works ends with an error
    g.job.args = pad({x: 800, y: 64, z: 800});
    await g.build(g.r, g.job);
    g.job.args = pad({x: 800, y: 64, z: 800}, {remove: true});
    await assert.rejects(g.build(g.r, g.job), /could not dig|no progress/);
    const h = fakeRun({claimOk: false}); // claims refused past the deadline: fail, not wait forever
    h.job.args = pad({x: 900, y: 64, z: 900});
    const t0 = Date.now();
    await assert.rejects(h.build(h.r, h.job), /no progress/);
    assert.ok(Date.now() - t0 < 2000);
  }
  { // openChest: a Stop between two covers digs no more and opens nothing; a single chest has no partner
    const {openChest, Cancelled} = require('./bots');
    const {Vec3} = require('vec3');
    const run = (types) => {
      const blocks = new Map([['0,64,0', ['chest', types[0]]], ['1,64,0', ['chest', types[1]]], ['0,65,0', ['cobblestone']], ['1,65,0', ['cobblestone']]]);
      const job = {t: {}, cancelled: false};
      const log = {digs: 0, opened: 0};
      const bot = {
        blockAt: (p) => {
          const b = blocks.get(`${p.x},${p.y},${p.z}`);
          return b ? {name: b[0], position: p, boundingBox: 'block', getProperties: () => (b[1] ? {facing: 'north', type: b[1]} : {})} : null;
        },
        entity: {position: new Vec3(0, 64, 3), onGround: true}, game: {dimension: 'overworld'}, entities: {}, inventory: {items: () => [{type: 1, name: 'stone_pickaxe'}]},
        pathfinder: {goto: async () => {}, stop() {}, setGoal() {}}, tool: {equipForBlock: async () => {}},
        dig: async (blk) => { log.digs++; blocks.delete(`${blk.position.x},${blk.position.y},${blk.position.z}`); job.cancelled = true; },
        openContainer: async () => { log.opened++; }, stopDigging() {},
      };
      const r = {bot, world: {hostilesNear: () => []}, emit() {}, protectedAreas: []};
      return {go: () => openChest(r, job, bot.blockAt(new Vec3(0, 64, 0))), log};
    };
    let x = run(['left', 'right']);
    await assert.rejects(x.go(), Cancelled);
    assert.deepStrictEqual(x.log, {digs: 1, opened: 0}, 'Stop after the first cover');
    x = run(['single', 'single']);
    await assert.rejects(x.go(), Cancelled); // its own cover is dug (and the Stop then holds) ...
    assert.strictEqual(x.log.digs, 1, '... but never the single neighbour\'s');
  }
  { // guardDigs: the pathfinder's own digs stop for a stopped job, a protected area, a changed block or a fluid
    const {guardDigs} = require('./bots');
    const {Vec3} = require('vec3');
    const world = new Map([['0,60,0', 'stone'], ['5,60,5', 'stone'], ['6,60,5', 'water'], ['20,60,20', 'stone']]);
    let dug = 0;
    const bot = {dig: async () => { dug++; }, equip: async () => {}, placeBlock: async () => {}, entity: {position: new Vec3(0, 62, 3)},
      blockAt: (p) => (world.get(`${p.x},${p.y},${p.z}`) ? {name: world.get(`${p.x},${p.y},${p.z}`), position: p, getProperties: () => ({})} : null)};
    const runner = {current: {cancelled: false}, protectedAreas: [[15, 15, 25, 25]]};
    guardDigs(runner, bot);
    const blk = (x, y, z, name = 'stone') => ({name, position: new Vec3(x, y, z)});
    await bot.dig(blk(0, 60, 0));
    assert.strictEqual(dug, 1, 'a plain dig passes');
    await assert.rejects(bot.dig(blk(5, 60, 5)), /water next to it/);
    await assert.rejects(bot.dig(blk(20, 60, 20)), /protected/);
    await assert.rejects(bot.dig(blk(0, 60, 0, 'dirt')), /changed/);
    runner.current.cancelled = true;
    await assert.rejects(bot.dig(blk(0, 60, 0)), /stopped/);
    assert.strictEqual(dug, 1);
  }
  { // the pathfinder's equip-then-dig / equip-then-place survives neither a Stop, a path reset nor a new job (Codex R2-2, R3-2)
    const {guardDigs, BotRunner} = require('./bots');
    const EventEmitter = require('node:events');
    const {Vec3} = require('vec3');
    const world = new Map();
    const rig = ({areas = []} = {}) => {
      world.clear();
      world.set('0,60,0', {name: 'stone', stateId: 1});
      let release = () => {}, digs = 0, places = 0, mining = false, building = false;
      const bot = Object.assign(new EventEmitter(), {
        equip: () => new Promise((res) => { release = res; }),
        dig: async () => { digs++; },
        placeBlock: async () => { places++; },
        entity: {position: new Vec3(0, 64, 3)},
        pathfinder: {stop() {}, setGoal() {}, isMining: () => mining, isBuilding: () => building},
        blockAt: (p) => { const b = world.get(`${p.x},${p.y},${p.z}`); return b ? {...b, position: p, getProperties: () => ({})} : null; },
      });
      const runner = Object.assign(Object.create(BotRunner.prototype), {bot, current: {cancelled: false}, protectedAreas: areas});
      guardDigs(runner, bot);
      // the pathfinder's executor: equip, then dig (its catch swallows an equip error, then digs anyway)
      const pfDig = () => { mining = true; return bot.equip({}, 'hand').catch(() => {}).then(() => bot.dig({name: 'stone', stateId: 1, position: new Vec3(0, 60, 0)}, true)).catch(() => {}); };
      const pfPlace = () => { building = true; return bot.equip({}, 'hand').then(() => bot.placeBlock({position: new Vec3(0, 60, 0)}, new Vec3(0, 1, 0))).catch(() => {}); };
      return {bot, runner, pfDig, pfPlace, release: () => release(), digs: () => digs, places: () => places};
    };
    const flush = () => new Promise((res) => setImmediate(res));
    let x = rig(), p = x.pfDig();
    x.release(); await p;
    assert.strictEqual(x.digs(), 1, 'untouched: the dig goes ahead');
    for (const [how, act] of [
      ['Stop, pump clears the job', (q) => { q.runner.cancel(); q.runner.current = null; }],
      ['Stop, then a new job', (q) => { q.runner.cancel(); q.runner.current = {cancelled: false}; }],
      ['path reset', (q) => q.bot.emit('path_reset', 'x')],
      ['goal replaced', (q) => q.bot.emit('goal_updated', null)],
      ['block state swapped', () => world.set('0,60,0', {name: 'stone', stateId: 2})],
      ['water arrives', () => world.set('1,60,0', {name: 'water', stateId: 3})],
      ['block turned to another', () => world.set('0,60,0', {name: 'chest', stateId: 4})],
    ]) {
      x = rig();
      p = x.pfDig();
      act(x);
      x.release(); await p; await flush();
      assert.strictEqual(x.digs(), 0, `dig after: ${how}`);
    }
    x = rig({areas: [[-1, -1, 1, 1]]});
    p = x.pfDig(); x.release(); await p;
    assert.strictEqual(x.digs(), 0, 'protected target');
    // scaffolding placement
    x = rig(); p = x.pfPlace(); x.release(); await p;
    assert.strictEqual(x.places(), 1, 'untouched: the scaffold goes ahead');
    for (const [how, act] of [
      ['Stop', (q) => { q.runner.cancel(); q.runner.current = null; }],
      ['Stop, then a new job', (q) => { q.runner.cancel(); q.runner.current = {cancelled: false}; }],
      ['path reset', (q) => q.bot.emit('path_reset', 'x')],
    ]) {
      x = rig(); p = x.pfPlace(); act(x); x.release(); await p; await flush();
      assert.strictEqual(x.places(), 0, `scaffold after: ${how}`);
    }
    x = rig({areas: [[-1, -1, 1, 1]]});
    await assert.rejects(x.bot.placeBlock({position: new Vec3(0, 60, 0)}, new Vec3(0, 1, 0)), /protected/);
    x = rig(); x.runner.current.cancelled = true;
    await assert.rejects(x.bot.placeBlock({position: new Vec3(0, 60, 0)}, new Vec3(0, 1, 0)), /stopped/);
    // a job's own equip does not care about path resets, only about a Stop
    x = rig(); p = x.bot.equip({}, 'hand'); x.bot.emit('path_reset', 'x'); x.release();
    await p;
    x = rig(); p = x.bot.equip({}, 'hand'); x.runner.cancel(); x.release();
    await assert.rejects(p, /Equip aborted/);
  }
  { // placeNear (crafting table / furnace): a Stop during the equip places nothing (Codex R3-2)
    const {placeNear} = require('./crafting');
    const {Cancelled} = require('./bots');
    const {Vec3} = require('vec3');
    let placed = 0, stopped = false, release;
    const bot = {
      inventory: {items: () => [{name: 'crafting_table'}]},
      entity: {position: new Vec3(0.5, 64, 0.5)},
      blockAt: (p) => (p.y === 63 ? {boundingBox: 'block', position: p, name: 'stone'} : {boundingBox: 'empty', position: p, name: 'air'}),
      equip: () => new Promise((res) => { release = res; }),
      placeBlock: async () => { placed++; },
    };
    const p = placeNear(bot, 'crafting_table', [], () => { if (stopped) throw new Cancelled('stopped'); });
    stopped = true;
    release();
    await assert.rejects(p, Cancelled);
    assert.strictEqual(placed, 0);
  }
  { // excavate's walking may dig natural ground only: placed walls stay, also for the ascent (Codex R3-1)
    const {safeMovements, guardDigs, BotRunner, NATURAL} = require('./bots');
    const {Movements} = require('mineflayer-pathfinder');
    const EventEmitter = require('node:events');
    const {Vec3} = require('vec3');
    const md = require('minecraft-data')('26.1');
    let walking = true, dug = 0;
    const world = {60: 'cobblestone', 61: 'dirt'};
    const bot = Object.assign(new EventEmitter(), {registry: md, version: '26.1', inventory: {items: () => []}, entity: {position: new Vec3(0, 64, 0)}, entities: {}, pathfinder: {isMining: () => walking}, dig: async () => { dug++; }, equip: async () => {}, placeBlock: async () => {},
      blockAt: (p) => ({name: world[p.y], position: p, getProperties: () => ({})})});
    const runner = Object.assign(Object.create(BotRunner.prototype), {bot, current: {cancelled: false}, protectedAreas: []});
    const mv = safeMovements(bot, [], runner);
    mv.getBlock = () => ({liquid: false, canFall: false});
    const blk = (n) => ({type: md.blocksByName[n].id, name: n, position: new Vec3(0, 60, 0)});
    for (const n of ['cobblestone', 'oak_planks', 'torch']) assert.ok(mv.safeToBreak(blk(n)), `${n}: free outside an excavation`);
    guardDigs(runner, bot);
    const dig = (y) => bot.dig({name: world[y], position: new Vec3(0, y, 0)}, true);
    await dig(60);
    assert.strictEqual(dug, 1, 'outside an excavation a walk digs what it needs');
    runner.digOnly = NATURAL;
    assert.ok(mv.safeToBreak(blk('dirt')) && mv.safeToBreak(blk('stone')));
    for (const n of ['cobblestone', 'oak_planks', 'torch']) assert.ok(!mv.safeToBreak(blk(n)), `${n}: never planned as a dig during an excavation`);
    await assert.rejects(dig(60), /not part of the job/);
    await dig(61);
    assert.strictEqual(dug, 2, 'natural ground is still dug');
    walking = false; // the job's own dig (digAt: a chest cover) is not a walk
    await dig(60);
    assert.strictEqual(dug, 3);
  }
  { // openChest: the partner is the one block facing + left/right point to (R2-5)
    const {openChest, partnerOf} = require('./bots');
    const {Vec3} = require('vec3');
    // left half -> offset of its partner (clockwise of facing); the right half's is the opposite
    const STEP = {north: [1, 0], south: [-1, 0], east: [0, 1], west: [0, -1]};
    const world = (chests) => { // chests: [[x, z, name, facing, type]]; a cobblestone cover over each
      const blocks = new Map();
      for (const [x, z, name, facing, type] of chests) {
        blocks.set(`${x},64,${z}`, [name, type ? {facing, type} : {}]);
        blocks.set(`${x},65,${z}`, ['cobblestone', {}]);
      }
      const dug = [];
      const job = {t: {}, cancelled: false};
      const bot = {
        blockAt: (p) => {
          const b = blocks.get(`${p.x},${p.y},${p.z}`);
          return b ? {name: b[0], position: p, boundingBox: 'block', getProperties: () => b[1]} : null;
        },
        entity: {position: new Vec3(0, 64, 5), onGround: true}, game: {dimension: 'overworld'}, entities: {}, inventory: {items: () => [{type: 1, name: 'stone_pickaxe'}]},
        pathfinder: {goto: async () => {}, stop() {}, setGoal() {}}, tool: {equipForBlock: async () => {}},
        dig: async (blk) => { dug.push(`${blk.position.x},${blk.position.z}`); blocks.delete(`${blk.position.x},${blk.position.y},${blk.position.z}`); },
        openContainer: async () => 'box', stopDigging() {},
      };
      const r = {bot, world: {hostilesNear: () => []}, emit() {}, protectedAreas: []};
      return {bot, open: (x, z) => openChest(r, job, bot.blockAt(new Vec3(x, 64, z))), dug};
    };
    for (const [facing, [dx, dz]] of Object.entries(STEP)) {
      for (const half of ['left', 'right']) {
        const s = half === 'left' ? 1 : -1;
        const other = half === 'left' ? 'right' : 'left';
        // the opened half at 10,10; its partner where facing + side say; an unrelated chest of the
        // other half's type, same facing, on the wrong axis (and one opposite the partner)
        const px = 10 + s * dx, pz = 10 + s * dz;
        const wrong = [[10 + dz, 10 + dx, 'chest', facing, other], [10 - s * dx, 10 - s * dz, 'chest', facing, other]];
        const w = world([[10, 10, 'chest', facing, half], [px, pz, 'chest', facing, other], ...wrong]);
        assert.strictEqual(partnerOf(w.bot, w.bot.blockAt(new Vec3(10, 64, 10))).position.x, px, `${facing} ${half}`);
        assert.strictEqual(await w.open(10, 10), 'box');
        assert.deepStrictEqual(w.dug.sort(), [`10,10`, `${px},${pz}`].sort(), `${facing} ${half}: only the pair's covers`);
      }
      // two adjacent double chests: each half pairs with its own partner, never the neighbouring pair's
      const along = (k) => [10 + k * dx, 10 + k * dz];
      const pair = (k, l) => [[...along(k), 'chest', facing, l ? 'left' : 'right'], [...along(k + 1), 'chest', facing, l ? 'right' : 'left']];
      // left at k, right at k+1 (left's partner lies +step); pair 2 starts at k+2
      const two = [...pair(0, true), ...pair(2, true)];
      for (const [k, want] of [[0, [0, 1]], [1, [0, 1]], [2, [2, 3]], [3, [2, 3]]]) {
        const w = world(two);
        await w.open(...along(k));
        assert.deepStrictEqual(w.dug.sort(), want.map((i) => along(i).join(',')).sort(), `${facing} adjacent pairs, opening block ${k}`);
      }
    }
    // missing/unloaded partner, two singles, a different type of chest, a barrel, unknown facing
    let w = world([[0, 0, 'chest', 'north', 'left']]);
    await w.open(0, 0);
    assert.deepStrictEqual(w.dug, ['0,0'], 'unloaded partner: only its own cover');
    w = world([[0, 0, 'chest', 'north', 'single'], [1, 0, 'chest', 'north', 'single']]);
    await w.open(0, 0);
    assert.deepStrictEqual(w.dug, ['0,0'], 'two singles');
    w = world([[0, 0, 'chest', 'north', 'left'], [1, 0, 'trapped_chest', 'north', 'right']]);
    await w.open(0, 0);
    assert.deepStrictEqual(w.dug, ['0,0'], 'a trapped chest is no partner of a chest');
    w = world([[0, 0, 'chest', 'north', 'left'], [1, 0, 'chest', 'south', 'right']]);
    await w.open(0, 0);
    assert.deepStrictEqual(w.dug, ['0,0'], 'facing must match');
    w = world([[0, 0, 'barrel'], [1, 0, 'barrel']]);
    assert.strictEqual(partnerOf(w.bot, w.bot.blockAt(new Vec3(0, 64, 0))), null);
  }
  { // rearm: the optional spare pickaxe / logs / planks never end the equipment step (R2-4)
    const {JOBS, Cancelled} = require('./bots');
    const {Vec3} = require('vec3');
    const SLOT = {head: 5, torso: 6, legs: 7, feet: 8, 'off-hand': 45};
    const it = (name, count = 1) => ({name, count, type: name.length * 7 + name.charCodeAt(0), metadata: null});
    const PLANKS = {oak_planks: 900, birch_planks: 901};
    // a shared chest so two bots can race for the same stack; cap = most stacks the bot can carry
    const chestOf = (items) => ({items: items.map((i) => ({...i})), opened: 0, closed: 0});
    const botOf = (chest, {inv = [], cap = 36, craft, failAt = {}} = {}) => {
      const slots = [];
      const equipped = [];
      const bot = {
        findBlocks: () => [new Vec3(0, 64, 0)],
        blockAt: (p) => (p.y === 64 ? {name: 'chest', position: p, boundingBox: 'block', getProperties: () => ({})} : null),
        entity: {position: new Vec3(0, 64, 3), onGround: true}, game: {dimension: 'overworld'}, entities: {},
        registry: {blocksByName: {chest: {id: 1}}, itemsByName: {...Object.fromEntries(Object.entries(PLANKS).map(([k, v]) => [k, {id: v}]))}, foodsByName: {bread: {}}},
        pathfinder: {goto: async () => {}, stop() {}, setGoal() {}},
        inventory: {items: () => inv, slots},
        getEquipmentDestSlot: (s) => SLOT[s],
        openContainer: async () => {
          chest.opened++;
          return {
            containerItems: () => chest.items,
            close: () => chest.closed++,
            withdraw: async (type, _m, n) => {
              if (failAt.withdraw) throw new Error(failAt.withdraw);
              const src = chest.items.find((i) => i.type === type);
              if (!src || src.count < n) throw new Error('Server rejected transaction');
              if (!inv.some((i) => i.type === type) && inv.length >= cap) throw new Error('Inventory is full');
              src.count -= n;
              if (!src.count) chest.items.splice(chest.items.indexOf(src), 1);
              const mine = inv.find((i) => i.type === type);
              if (mine) mine.count += n; else inv.push({...src, count: n});
            },
          };
        },
        recipesFor: (id) => [{id}],
        craft: craft || (async (recipe, n) => {
          const logI = inv.findIndex((i) => /_log$/.test(i.name));
          inv[logI].count -= n; if (!inv[logI].count) inv.splice(logI, 1);
          inv.push({name: 'oak_planks', type: recipe.id, count: 4 * n});
        }),
        equip: async (item, dest) => { equipped.push(`${item.name}>${dest}`); },
      };
      return {bot, inv, equipped};
    };
    const run = (b, job = {t: {}, cancelled: false}) => {
      const infos = [];
      const r = {bot: b.bot, world: {hostilesNear: () => []}, emit: (k, m) => infos.push(m), protectedAreas: [], supplyChest: null};
      return {go: () => JOBS.rearm(r, Object.assign(job, {args: {x: 0, y: 64, z: 0}})), job, infos};
    };
    // 1. full inventory with a pickaxe and carried armour: the spare pickaxe cannot be taken, the armour is worn
    let chest = chestOf([it('iron_pickaxe'), it('bread', 20)]);
    let b = botOf(chest, {inv: [it('stone_pickaxe'), it('iron_helmet'), it('iron_chestplate')], cap: 3});
    let x = run(b);
    await x.go();
    assert.deepStrictEqual(b.equipped, ['iron_helmet>head', 'iron_chestplate>torso']);
    assert.strictEqual(chest.closed, chest.opened, 'window closed');
    assert.ok(x.infos.some((m) => /could not take iron_pickaxe/.test(m)), 'reported');
    assert.strictEqual(b.inv.filter((i) => i.name === 'iron_pickaxe').length, 0);
    // 2. the last spare is taken between containerItems() and withdraw(): rearm still equips and feeds
    chest = chestOf([it('diamond_sword'), it('iron_pickaxe'), it('bread', 20)]);
    b = botOf(chest, {inv: [it('stone_pickaxe'), it('iron_boots')]});
    const left = b.bot.openContainer;
    b.bot.openContainer = async (...a) => {
      const box = await left(...a);
      const w = box.withdraw;
      box.withdraw = async (type, m, n) => {
        if (chest.items.find((i) => i.type === type)?.name === 'iron_pickaxe') chest.items.splice(chest.items.findIndex((i) => i.type === type), 1); // another bot was faster
        return w(type, m, n);
      };
      return box;
    };
    x = run(b);
    await x.go();
    assert.deepStrictEqual(b.equipped.sort(), ['diamond_sword>hand', 'iron_boots>feet']);
    assert.strictEqual(b.inv.find((i) => i.name === 'bread')?.count, 20, 'food still taken');
    assert.strictEqual(chest.closed, 1);
    // 3. the log stack changed (a taller one than offered): not an error either
    chest = chestOf([it('oak_log', 1)]);
    b = botOf(chest, {inv: [it('stone_sword')]});
    b.bot.openContainer = ((f) => async () => { const box = await f(); const w = box.withdraw; box.withdraw = async () => { chest.items.length = 0; return w(1, null, 2); }; return box; })(b.bot.openContainer);
    await run(b).go();
    assert.deepStrictEqual(b.equipped, ['stone_sword>hand']);
    // 4. full output inventory: the planks craft fails; reported, the rest done, no throw
    chest = chestOf([it('oak_log', 2)]);
    b = botOf(chest, {inv: [it('iron_sword')], craft: async () => { throw new Error('Inventory full'); }});
    x = run(b);
    await x.go();
    assert.ok(/no planks/.test(x.job.progress), x.job.progress);
    assert.ok(x.infos.some((m) => /no planks \(oak_log: Inventory full\)/.test(m)));
    assert.deepStrictEqual(b.equipped, ['iron_sword>hand']);
    // 4b. a craft that returns but makes nothing is reported too
    b = botOf(chestOf([it('oak_log', 1)]), {craft: async () => {}});
    x = run(b);
    await x.go();
    assert.ok(/no planks/.test(x.job.progress) && x.infos.some((m) => /nothing crafted/.test(m)));
    // 5. 0 / 1 / 2 logs become planks, a woodcutter's 3+ stay logs
    for (const [logs, planks] of [[0, 0], [1, 4], [2, 8], [3, 0], [20, 0]]) {
      b = botOf(chestOf([]), {inv: logs ? [it('oak_log', logs)] : []});
      x = run(b);
      await x.go();
      const n = (re) => b.inv.filter((i) => re.test(i.name)).reduce((s, i) => s + i.count, 0);
      assert.strictEqual(n(/_planks$/), planks, `${logs} logs`);
      assert.strictEqual(n(/_log$/), planks ? 0 : logs, `${logs} logs left`);
      assert.ok(!/no planks/.test(x.job.progress), `${logs} logs: ${x.job.progress}`);
    }
    // 5b. logs from the chest: never more than 2 in total, then converted
    chest = chestOf([it('oak_log', 64)]);
    b = botOf(chest, {inv: [it('oak_log', 1)]});
    await run(b).go();
    assert.strictEqual(chest.items[0].count, 63);
    assert.strictEqual(b.inv.find((i) => /_planks/.test(i.name))?.count, 8);
    // 6. a Stop during a failed withdrawal ends the job and closes the window
    chest = chestOf([it('iron_helmet')]);
    b = botOf(chest);
    const job = {t: {}, cancelled: false};
    b.bot.openContainer = ((f) => async () => { const box = await f(); box.withdraw = async () => { job.cancelled = true; throw new Error('aborted'); }; return box; })(b.bot.openContainer);
    await assert.rejects(run(b, job).go(), Cancelled);
    assert.strictEqual(chest.closed, chest.opened);
    // 7. two bots re-arm from the same chest with one spare pickaxe: one gets it, nobody throws or duplicates
    chest = chestOf([it('iron_pickaxe'), it('bread', 40)]);
    const A = botOf(chest, {inv: [it('stone_pickaxe')]}), B = botOf(chest, {inv: [it('stone_pickaxe')]});
    await Promise.all([run(A).go(), run(B).go()]);
    const picks = [A, B].map((q) => q.inv.filter((i) => i.name === 'iron_pickaxe').reduce((s, i) => s + i.count, 0));
    assert.strictEqual(picks[0] + picks[1], 1, 'one spare, one owner');
    assert.strictEqual(chest.closed, chest.opened);
    // 8. a Stop inside the first armour equip (or the craft) starts no further equip or craft (Codex R2-3)
    for (const at of ['equip', 'craft']) {
      chest = chestOf([]);
      const carried = ['iron_helmet', 'iron_chestplate', 'iron_leggings', 'iron_boots', 'totem_of_undying', 'diamond_sword'].map((n) => it(n));
      b = botOf(chest, {inv: [...carried, ...(at === 'craft' ? [it('oak_log', 2)] : [])]});
      const j = {t: {}, cancelled: false};
      let calls = 0;
      const stop = async () => { calls++; j.cancelled = true; };
      if (at === 'equip') b.bot.equip = stop;
      else { b.bot.craft = stop; b.bot.equip = async () => { calls++; }; }
      await assert.rejects(run(b, j).go(), Cancelled, at);
      assert.strictEqual(calls, 1, `${at}: nothing is started after the Stop`);
      assert.strictEqual(chest.closed, chest.opened);
    }
  }
  { // excavate: digs natural ground top-down, leaves placed blocks and protected areas alone
    const {JOBS, VALIDATE} = require('./bots');
    assert.deepStrictEqual(VALIDATE.excavate({x1: 5, y1: 60, z1: 5, x2: 3, y2: 58, z2: 4}), {x1: 3, y1: 58, z1: 4, x2: 5, y2: 60, z2: 5});
    assert.throws(() => VALIDATE.excavate({x1: 0, y1: 60, z1: 0, x2: 9, y2: 60, z2: 0}), /at most 9/);
    assert.throws(() => VALIDATE.excavate({x1: 0, y1: 60, z1: 0, x2: 0, y2: 65, z2: 0}), /5 high/);
    const {Vec3} = require('vec3');
    const blocks = new Map([['0,60,0', 'stone'], ['1,60,0', 'cobblestone'], ['0,59,0', 'dirt'], ['1,59,0', 'chest'], ['0,58,0', 'iron_ore']]);
    const order = [];
    const bot = {
      blockAt: (p) => (blocks.get(`${p.x},${p.y},${p.z}`) ? {name: blocks.get(`${p.x},${p.y},${p.z}`), type: 1, position: p, boundingBox: 'block', getProperties: () => ({})} : null),
      entity: {position: new Vec3(0, 61, 2), onGround: true}, game: {dimension: 'overworld'}, entities: {}, food: 20,
      registry: {blocks: {}, foodsByName: {}},
      inventory: {items: () => [{type: 2, name: 'stone_pickaxe'}], emptySlotCount: () => 30, slots: []}, getEquipmentDestSlot: () => 5,
      pathfinder: {goto: async () => {}, stop() {}, setGoal() {}}, tool: {equipForBlock: async () => {}},
      dig: async (b) => { order.push(`${b.name}@${b.position.y}`); blocks.delete(`${b.position.x},${b.position.y},${b.position.z}`); },
      stopDigging() {},
    };
    const job = {t: {}, cancelled: false, type: 'excavate', args: {x1: 0, y1: 58, z1: 0, x2: 1, y2: 60, z2: 0}};
    const r = {bot, world: {hostilesNear: () => [], claim: async () => true, release() {}}, emit() {}, protectedAreas: [], supplyChest: null, combat: null};
    await JOBS.excavate(r, job);
    assert.ok(!job.noop, 'a dig that removed blocks is not "already complete"');
    assert.deepStrictEqual(order, ['stone@60', 'dirt@59', 'iron_ore@58'], 'top-down, natural ground only');
    const again = {...job, t: {}};
    await JOBS.excavate(r, again);
    assert.strictEqual(again.noop, true, 'a second dig of the same room had nothing to do');
    assert.deepStrictEqual([...blocks.values()].sort(), ['chest', 'cobblestone'], 'placed blocks stay');
    await assert.rejects(JOBS.excavate({...r, protectedAreas: [[-5, -5, 5, 5]]}, {...job, t: {}}), /protected/);
  }
  { // shaft: 1-high excavate layers top-down, one stair step per layer spiralling along the walls
    const {JOBS, VALIDATE, stairRing} = require('./bots');
    const {Vec3} = require('vec3');
    assert.deepStrictEqual(VALIDATE.shaft({x1: 15, z1: 0, x2: 0, z2: 15}), {x1: 0, z1: 0, x2: 15, z2: 15, top: 80, bottom: -59});
    assert.strictEqual(VALIDATE.shaft({x1: 0, z1: 0, x2: 3, z2: 3, top: 60, bottom: -64}).bottom, -59, 'never into bedrock');
    assert.throws(() => VALIDATE.shaft({x1: 0, z1: 0, x2: 16, z2: 3}), /16 x 16/);
    const ring = stairRing(0, 0, 15, 15);
    assert.strictEqual(ring.length, 60);
    for (let i = 0; i < ring.length; i++) { const a = ring[i], b = ring[(i + 1) % ring.length]; assert.strictEqual(Math.abs(a.x - b.x) + Math.abs(a.z - b.z), 1, 'each step is next to the one below'); }
    const blocks = new Map();
    for (let y = 58; y <= 60; y++) for (let x = 0; x <= 2; x++) for (let z = 0; z <= 2; z++) blocks.set(`${x},${y},${z}`, 'stone');
    const bot = {
      blockAt: (p) => (blocks.get(`${p.x},${p.y},${p.z}`) ? {name: 'stone', type: 1, position: p, boundingBox: 'block', getProperties: () => ({})} : null),
      entity: {position: new Vec3(0, 61, 4), onGround: true}, game: {dimension: 'overworld'}, entities: {}, food: 20,
      registry: {blocks: {}, foodsByName: {}},
      inventory: {items: () => [{type: 2, name: 'stone_pickaxe'}], emptySlotCount: () => 30, slots: []}, getEquipmentDestSlot: () => 5,
      pathfinder: {goto: async () => {}, stop() {}, setGoal() {}}, tool: {equipForBlock: async () => {}},
      dig: async (b) => { blocks.delete(`${b.position.x},${b.position.y},${b.position.z}`); },
      stopDigging() {},
    };
    const job = {t: {}, cancelled: false, type: 'shaft', args: VALIDATE.shaft({x1: 0, z1: 0, x2: 2, z2: 2, top: 60, bottom: 58})};
    const dug = [];
    const dig0 = bot.dig;
    bot.dig = async (b) => { dug.push(`${b.position.x},${b.position.z}`); return dig0(b); };
    await JOBS.shaft({name: 'bot18', bot, world: {hostilesNear: () => [], claim: async () => true, release() {}}, emit() {}, protectedAreas: [], supplyChest: null, combat: null}, job);
    assert.strictEqual(dug[0], '0,1', 'bot18 starts at the first corner (its step 0,0 stays)');
    assert.deepStrictEqual([...blocks.keys()].sort(), ['0,60,0', '1,59,0', '2,58,0'], 'one step left per layer, each one further along');
    assert.deepStrictEqual([job.t.done, job.t.total], [3, 3]);
    for (let y = 58; y <= 60; y++) for (let x = 0; x <= 2; x++) for (let z = 0; z <= 2; z++) blocks.set(`${x},${y},${z}`, 'stone');
    dug.length = 0;
    await JOBS.shaft({name: 'bot17', bot, world: {hostilesNear: () => [], claim: async () => true, release() {}}, emit() {}, protectedAreas: [], supplyChest: null, combat: null}, {...job, t: {}});
    assert.strictEqual(dug[0], '2,2', 'bot17 starts at the opposite corner');
  }
  { // digAt rechecks the block after every walk and equip: a Stop or a swapped block means no dig
    const {digAt, Cancelled} = require('./bots');
    const {Vec3} = require('vec3');
    const pos = new Vec3(5, 64, 5);
    const run = ({onEquip = () => {}, onWalk = () => {}, expect} = {}) => {
      const blocks = new Map([['5,64,5', 'blue_orchid']]);
      const job = {t: {}, cancelled: false};
      let digs = 0;
      const bot = {
        blockAt: (p) => (blocks.get(`${p.x},${p.y},${p.z}`) ? {name: blocks.get(`${p.x},${p.y},${p.z}`), position: p, getProperties: () => ({})} : null),
        entity: {position: new Vec3(3, 64, 3), onGround: true}, game: {dimension: 'overworld'}, entities: {}, inventory: {items: () => []},
        pathfinder: {goto: async () => onWalk(blocks, job), stop() {}, setGoal() {}},
        tool: {equipForBlock: async () => onEquip(blocks, job)},
        dig: async () => { digs++; blocks.delete('5,64,5'); },
        stopDigging() {},
      };
      const r = {bot, world: {hostilesNear: () => []}, emit() {}};
      return {go: () => digAt(r, job, pos, expect), digs: () => digs};
    };
    let x = run({onEquip: (_, job) => (job.cancelled = true)});
    await assert.rejects(x.go(), Cancelled);
    assert.strictEqual(x.digs(), 0);
    const plant = (n) => n === 'blue_orchid';
    for (const at of ['onEquip', 'onWalk']) {
      x = run({expect: plant, [at]: (blocks) => blocks.set('5,64,5', 'torch')});
      assert.strictEqual(await x.go(), false, at);
      assert.strictEqual(x.digs(), 0, at);
    }
    x = run({onWalk: (blocks) => blocks.set('5,64,5', 'chest')}); // default expect: the block seen first
    assert.strictEqual(await x.go(), false);
    assert.strictEqual(x.digs(), 0);
    x = run({expect: plant});
    assert.strictEqual(await x.go(), true);
    assert.strictEqual(x.digs(), 1);
  }
  { // hunt and bed (R5): validation, the pure picks, then both jobs against a fake bot
    const {JOBS, VALIDATE, Cancelled} = require('./bots');
    const H = require('./hunt');
    const {Vec3} = require('vec3');
    const A = require('./agentauth');
    assert.deepStrictEqual(VALIDATE.hunt({animal: 'sheep', count: 3, x: 1, y: 64, z: 2}), {animal: 'sheep', count: 3, x: 1, y: 64, z: 2, radius: 24});
    for (const bad of [{animal: 'wolf'}, {animal: 'constructor'}, {animal: 'cow', count: 99}, {animal: 'cow', radius: 2}]) assert.throws(() => VALIDATE.hunt({x: 1, y: 64, z: 2, ...bad}), bad.animal);
    assert.deepStrictEqual(VALIDATE.bed({x: 1, y: 60, z: 2, facing: 'north'}), {x: 1, y: 60, z: 2, facing: 'north'});
    for (const facing of ['up', 'constructor', undefined]) assert.throws(() => VALIDATE.bed({x: 1, y: 60, z: 2, facing}), /facing/);
    const pol = {agentBots: ['bot1'], supplyChest: {x: 1, y: 2, z: 3}};
    for (const type of ['hunt', 'bed']) assert.strictEqual(A.agentJobRefusal({bots: ['bot1'], type, args: {}}, pol), null, type);

    // huntTarget: nearest sheep in range; never named, baby, handled, protected, other kinds or players
    const sheep = (id, x, z, extra = {}) => ({id, name: 'sheep', position: new Vec3(x, 64, z), ...extra});
    const base = {animal: 'sheep', x: 0, y: 64, z: 0, radius: 20, areas: [[100, 100, 120, 120]], done: new Set([9]), me: new Vec3(0, 64, 0)};
    const list = [sheep(1, 10, 0), sheep(2, 3, 0, {metadata: [0, 0, {text: 'Dolly'}]}), sheep(3, 4, 0, {metadata: Object.assign([], {16: true})}), sheep(4, 5, 0, {isValid: false}),
      sheep(5, 6, 0, {type: 'player'}), sheep(9, 2, 0), sheep(6, 105, 105), sheep(7, 30, 0), {id: 8, name: 'cow', position: new Vec3(1, 64, 0)}, sheep(10, 0, 0, {metadata: [0, 0, null]})];
    assert.strictEqual(H.huntTarget(list, base).id, 10, 'a null name is no name');
    assert.strictEqual(H.huntTarget(list.filter((e) => e.id !== 10), base).id, 1, 'nearest unnamed adult sheep in range');
    assert.strictEqual(H.huntTarget(list, {...base, x: 105, z: 105, radius: 30}), undefined, 'protected (and the rest out of range)');
    assert.strictEqual(H.huntTarget(list, {...base, areas: [[5, -5, 12, 5]], me: new Vec3(10, 64, 0)})?.id, 10, 'the one at 10,0 is inside the area, so the next nearest');

    // bed cells and checks
    const world = (cells) => (x, y, z) => cells[`${x},${y},${z}`] || null;
    const ground = {name: 'stone', boundingBox: 'block'}, air = {name: 'air', boundingBox: 'empty'};
    const flat = (extra = {}) => world({'5,59,5': ground, '5,59,6': ground, '5,60,5': air, '5,60,6': air, ...extra});
    const cells = H.bedCells({x: 5, y: 60, z: 5}, 'south');
    assert.deepStrictEqual([cells.head, cells.back(2)], [{x: 5, y: 60, z: 6}, {x: 5, y: 60, z: 3}]);
    assert.deepStrictEqual(H.bedCheck(flat(), cells, []), {});
    assert.match(H.bedCheck(flat(), cells, [[0, 0, 9, 9]]).problem, /protected/);
    assert.match(H.bedCheck(flat({'5,60,6': {name: 'chest', boundingBox: 'block'}}), cells, []).problem, /chest is in the way/);
    assert.match(H.bedCheck(flat({'5,59,6': air}), cells, []).problem, /nothing solid under 5 60 6/);
    assert.match(H.bedCheck(flat({'5,60,5': {name: 'water', boundingBox: 'empty'}}), cells, []).problem, /water is in the way/);
    assert.match(H.bedCheck(flat({'5,60,6': null}), cells, []).problem, /not loaded/);
    assert.deepStrictEqual(H.bedCheck(flat({'5,60,5': {name: 'red_bed'}, '5,60,6': {name: 'red_bed'}}), cells, []), {present: true});
    assert.ok(H.standable(flat({'5,59,3': ground, '5,60,3': air, '5,61,3': air}), cells.back(2)) === true && !H.standable(flat(), cells.back(2)));
    const woolOf = (o) => Object.entries(o).map(([k, count]) => ({name: `${k}_wool`, count}));
    assert.strictEqual(H.woolColour(woolOf({white: 2, red: 1})), null, 'no colour has 3');
    assert.strictEqual(H.woolColour([...woolOf({white: 2}), {name: 'white_wool', count: 1}, ...woolOf({black: 5})]), 'black', 'the most of a colour with 3+');
    assert.strictEqual(H.woolColour([{name: 'oak_planks', count: 9}]), null);

    // a fake bot: sheep that die after 3 hits (or give wool when sheared), drops, a bed that appears when placed
    const fake = ({sheeps = [], inv = [], blocks = {}, areas = [], night = false, onAttack = () => {}} = {}) => {
      const entities = {}, hits = {}, events = [], infos = [], listeners = new Set();
      for (const s of sheeps) entities[s.id] = {name: 'sheep', height: 1.3, ...s};
      const cell = new Map(Object.entries(blocks));
      const it = (name, count = 1) => ({name, count, type: name.length});
      const bot = {
        entities, inventory: {items: () => inv}, heldItem: null, game: {dimension: 'overworld'}, time: {timeOfDay: night ? 14000 : 1000}, isSleeping: false,
        entity: {position: new Vec3(0, 64, 0), onGround: true},
        pathfinder: {goto: async () => {}, setGoal() {}, stop() {}, isMoving: () => true},
        equip: async (item) => { bot.heldItem = item; events.push(`equip ${item.name}`); },
        lookAt: async () => {},
        attack: (e) => { hits[e.id] = (hits[e.id] || 0) + 1; onAttack(e, hits[e.id]); if (hits[e.id] >= 3) { delete entities[e.id]; entities[100 + e.id] = {name: 'item', position: e.position}; inv.push(it('mutton')); } },
        activateEntity: async (e) => { events.push(`shear ${e.id}`); inv.push(it('white_wool', 2)); },
        blockAt: (p) => { const c = cell.get(`${p.x},${p.y},${p.z}`); return c ? {position: p, ...c} : null; },
        placeBlock: async (ref, face) => { events.push(`place ${ref.position.x},${ref.position.y + 1},${ref.position.z}`); cell.set(`${ref.position.x},${ref.position.y + 1},${ref.position.z}`, {name: 'red_bed'}); cell.set(`${ref.position.x},${ref.position.y + 1},${ref.position.z + 1}`, {name: 'red_bed'}); },
        activateBlock: async (b) => { events.push(`click ${b.name}`); for (const l of listeners) l('Respawn point set'); },
        sleep: async () => { events.push('sleep'); bot.isSleeping = true; for (const l of listeners) l('Respawn point set'); },
        wake: async () => { events.push('wake'); bot.isSleeping = false; },
        on: (n, f) => n === 'messagestr' && listeners.add(f), off: (n, f) => listeners.delete(f),
      };
      return {bot, events, infos, hits, entities, cell, it, r: {bot, world: {hostilesNear: () => []}, combat: {busy: false, epoch: 0}, emit: (k, t) => infos.push(t), protectedAreas: areas}};
    };
    const hunt = (extra = {}) => ({t: {}, cancelled: false, type: 'hunt', args: {animal: 'sheep', count: 2, x: 0, y: 64, z: 0, radius: 20}, ...extra});

    // kills the 2 nearest sheep with the sword, leaves the third and the named one alone
    let f = fake({sheeps: [{id: 1, position: new Vec3(4, 64, 0)}, {id: 2, position: new Vec3(6, 64, 1)}, {id: 3, position: new Vec3(8, 64, 0)}, {id: 4, position: new Vec3(2, 64, 0), metadata: [0, 0, {text: 'Bob'}]}], inv: [{name: 'iron_sword', count: 1, type: 99}]});
    f.bot.entity.position = new Vec3(3.5, 64, 0); // everything within 3 blocks: no walking needed
    let job = hunt();
    await JOBS.hunt(f.r, job);
    assert.strictEqual(job.collected, 2);
    assert.ok(f.entities[3] && f.entities[4] && !f.entities[1] && !f.entities[2], 'two killed, the far and the named one alive');
    assert.ok(f.events.includes('equip iron_sword') && f.infos.some((m) => /hunted 2 sheep/.test(m)), f.infos.join('|'));
    // a sword sweep kills the sheep next to the target: it counts, and nothing is attacked twice
    f = fake({sheeps: [{id: 1, position: new Vec3(2, 64, 0)}, {id: 2, position: new Vec3(2, 64, 1)}, {id: 3, position: new Vec3(3, 64, 0)}], onAttack: (e, n) => { if (e.id === 1 && n === 3) delete f.entities[2]; }});
    job = hunt({args: {animal: 'sheep', count: 3, x: 0, y: 64, z: 0, radius: 20}});
    await JOBS.hunt(f.r, job);
    assert.ok(job.collected === 3 && f.hits[2] === undefined && f.hits[3] === 3, `sweep: ${job.collected}`);
    // not enough sheep: the job fails with the count it reached; protected sheep do not count
    f = fake({sheeps: [{id: 1, position: new Vec3(2, 64, 0)}, {id: 2, position: new Vec3(3, 64, 0)}], areas: [[2.5, -5, 10, 5]]});
    await assert.rejects(JOBS.hunt(f.r, hunt()), /1 of 2 sheep hunted: no more within 20 blocks/);
    assert.strictEqual(f.hits[2], undefined, 'nothing attacked inside the protected area');
    // shears: the sheep lives and the wool counts; a sheep that gives no wool is left and does not count
    f = fake({sheeps: [{id: 1, position: new Vec3(2, 64, 0)}, {id: 2, position: new Vec3(2, 64, 1)}], inv: [{name: 'shears', count: 1, type: 7}]});
    job = hunt({args: {animal: 'sheep', count: 2, x: 0, y: 64, z: 0, radius: 20}});
    await JOBS.hunt(f.r, job);
    assert.deepStrictEqual(f.events.filter((e) => e.startsWith('shear')), ['shear 1', 'shear 2']);
    assert.ok(f.entities[1] && f.entities[2] && !f.hits[1], 'sheared, not hit');
    f.bot.inventory.items().length = 1; // only the shears are left: nothing more to gain from a sheared sheep
    f.bot.activateEntity = async () => {};
    job = hunt({args: {animal: 'sheep', count: 1, x: 0, y: 64, z: 0, radius: 20}});
    await assert.rejects(JOBS.hunt(f.r, job), /0 of 1 sheep hunted/);
    // a Stop in the middle of the fight ends the job
    f = fake({sheeps: [{id: 1, position: new Vec3(2, 64, 0)}], onAttack: () => (job.cancelled = true)});
    job = hunt();
    await assert.rejects(JOBS.hunt(f.r, job), Cancelled);
    assert.strictEqual(f.hits[1], 1, 'no second blow after the Stop');

    // bed: protected and blocked cells are refused, a bed lying there is only clicked, a new one is placed then clicked
    const floor = (z) => ({[`5,59,${z}`]: {name: 'stone', boundingBox: 'block'}, [`5,60,${z}`]: {name: 'air', boundingBox: 'empty'}, [`5,61,${z}`]: {name: 'air', boundingBox: 'empty'}});
    const field = () => ({...floor(3), ...floor(4), ...floor(5), ...floor(6)});
    const bedJob = (extra = {}) => ({t: {}, cancelled: false, type: 'bed', args: {x: 5, y: 60, z: 5, facing: 'south'}, ...extra});
    f = fake({blocks: field(), areas: [[0, 0, 9, 9]]});
    await assert.rejects(JOBS.bed(f.r, bedJob()), /protected/);
    f = fake({blocks: {...field(), '5,60,6': {name: 'chest', boundingBox: 'block'}}});
    await assert.rejects(JOBS.bed(f.r, bedJob()), /chest is in the way/);
    f = fake({blocks: field(), inv: woolOf({white: 2, red: 1}).map((w) => ({...w, type: 1}))});
    await assert.rejects(JOBS.bed(f.r, bedJob()), /need 3 wool of one colour/);
    f = fake({blocks: field(), inv: [{name: 'white_wool', count: 3, type: 1}]});
    await assert.rejects(JOBS.bed(f.r, bedJob()), /need 3 more planks and have no logs/);
    f = fake({blocks: field(), inv: [{name: 'red_bed', count: 1, type: 5}]});
    await JOBS.bed(f.r, bedJob());
    assert.deepStrictEqual(f.events, ['equip red_bed', 'place 5,60,5', 'click red_bed'], 'placed on the stone under the foot, then clicked');
    assert.ok(f.infos.some((m) => /^spawn set at 5 60 5$/.test(m)), f.infos.join('|'));
    f = fake({blocks: {...field(), '5,60,5': {name: 'red_bed'}, '5,60,6': {name: 'red_bed'}}}); // the bed is already there: click only
    await JOBS.bed(f.r, bedJob());
    assert.deepStrictEqual(f.events, ['click red_bed']);
    f = fake({blocks: {...field(), '5,60,5': {name: 'red_bed'}, '5,60,6': {name: 'red_bed'}}, night: true}); // at night it sleeps a moment and wakes
    await JOBS.bed(f.r, bedJob());
    assert.deepStrictEqual(f.events, ['sleep', 'wake']);
    f = fake({blocks: {...field(), '5,60,5': {name: 'red_bed'}, '5,60,6': {name: 'red_bed'}}, night: true}); // monsters near: sleep refuses, the click is made anyway
    f.bot.sleep = async () => { throw new Error('there are monsters nearby'); };
    await JOBS.bed(f.r, bedJob());
    assert.deepStrictEqual(f.events, ['click red_bed']);
    assert.ok(f.infos.some((m) => /could not sleep \(there are monsters nearby\)/.test(m)));
    f = fake({blocks: field(), inv: [{name: 'red_bed', count: 1, type: 5}]}); // a Stop during the equip places nothing
    const stopped = bedJob();
    f.bot.equip = async () => { stopped.cancelled = true; };
    await assert.rejects(JOBS.bed(f.r, stopped), Cancelled);
    assert.deepStrictEqual(f.events, []);
    f = fake({blocks: field(), inv: [{name: 'red_bed', count: 1, type: 5}]}); // the server never shows the bed
    f.bot.placeBlock = async () => {};
    await assert.rejects(JOBS.bed(f.r, bedJob()), /did not take/);
  }
  console.log('ok');
})();
