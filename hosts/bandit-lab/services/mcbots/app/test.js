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
// Block claims: a second bot cannot take a block the first one holds.
const {WorldModel} = require('./world');
const claims = new WorldModel();
assert.ok(claims.claim('bot1', 'o:1,2,3'));
assert.ok(!claims.claim('bot2', 'o:1,2,3'));
assert.ok(claims.claimedByOther('bot2', 'o:1,2,3'));
claims.release('bot1', 'o:1,2,3');
assert.ok(claims.claim('bot2', 'o:1,2,3'));
// Login passwords are stable per seed and name, and differ between bots.
const pw = (n) => new BotRunner(n, {host: 'x', port: 1, log: () => {}, world: null, loginSeed: 'seed'}).password;
assert.strictEqual(pw('bot1'), pw('bot1'));
assert.notStrictEqual(pw('bot1'), pw('bot2'));
assert.strictEqual(pw('bot1').length, 32);
const {normalize} = require('./itemfix');
assert.deepStrictEqual(normalize({enchantments: [{id: 1, level: 5}]}, {enchantments: {1: {name: 'efficiency'}}}), [{name: 'efficiency', lvl: 5}]);
assert.deepStrictEqual(normalize([{name: 'x', lvl: 1}], {}), [{name: 'x', lvl: 1}]);
assert.deepStrictEqual(VALIDATE.craft({item: 'stone_pickaxe', count: '2'}), {item: 'stone_pickaxe', count: 2});
assert.throws(() => VALIDATE.craft({item: 'Stone Pickaxe'}));
assert.deepStrictEqual(VALIDATE.shift({block: 'logs', x: 1, y: 2, z: 3}), {block: 'logs', x: 1, y: 2, z: 3});
require('./crafting');
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
  const child = spawn(process.execPath, [require('node:path').join(__dirname, 'server.js')], {
    env: {PATH: process.env.PATH, NODE_PATH: process.env.NODE_PATH || '', BOT_NAMES: 'bot1,bot2', DASHBOARD_PORT: String(port), DASHBOARD_HOST: '127.0.0.1', ALLOWED_TS_LOGINS: 'a@github', MC_HOST: '127.0.0.1', MC_PORT: '1', BOT_PASSWORD_SEED: 'test'},
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
      assert.ok(Array.isArray(b.positions) && Array.isArray(b.queue));
    }
    assert.strictEqual((await fetch(base, {method: 'POST', headers: {'tailscale-user-login': 'a@github'}})).status, 404);
  } finally {
    child.kill('SIGKILL');
  }
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
  await new Promise((res) => setTimeout(res, 20));
  assert.deepStrictEqual(said, ['slow', 'next']);
  console.log('ok');
})();
