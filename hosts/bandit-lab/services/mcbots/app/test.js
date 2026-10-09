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
  const hub = new Hub({world, runners, token, log: () => {}, protectedAreas: [[1, 2, 3, 4]], supplyChest: {x: 1, y: 2, z: 3}});
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
    a.send({t: 'hello', v: 1, host: 'laptop', bots: ['bot5']});
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

    // a reconnect replaces a stale connection
    const old = await open(auth);
    old.send({t: 'hello', v: 1, host: 'laptop', bots: ['bot5']});
    await until(() => old.msgs.find((m) => m.t === 'welcome'), 'welcome 1');
    const fresh = await open(auth);
    fresh.send({t: 'hello', v: 1, host: 'laptop2', bots: ['bot5']});
    await until(() => fresh.msgs.find((m) => m.t === 'welcome'), 'welcome 2');
    assert.strictEqual(await old.closed, 4001);
    assert.strictEqual(r5.snapshot().connected, true, 'the new connection stays owner');
    assert.strictEqual(r5.snapshot().host, 'laptop2');
    fresh.ws.close();
    await until(() => !r5.snapshot().connected, 'offline again');

    // a replaced connection must not keep acting for the bot it lost
    {
      const o = await open(auth);
      o.send({t: 'hello', v: 1, host: 'a', bots: ['bot8']});
      await until(() => o.msgs.find((m) => m.t === 'welcome'), 'welcome old');
      const n = await open(auth);
      n.send({t: 'hello', v: 1, host: 'b', bots: ['bot8']});
      await until(() => n.msgs.find((m) => m.t === 'welcome'), 'welcome new');
      o.send({t: 'claim', id: 1, key: 'overworld:70,60,5', by: 'bot8'});
      o.send({t: 'ping'});
      await sleep(300);
      assert.ok(!world.claims.has('overworld:70,60,5'), 'a replaced connection cannot claim');
      n.ws.close();
      await until(() => !runners.get('bot8').snapshot().connected, 'bot8 offline');
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
    const stub = {name: 'bot6', started: false, start() { this.started = true; }, shutdown() {}, snapshot: () => ({name: 'bot6', online: true, pos: [9, 9, 9], job: null, queue: [], inventory: [], pullbacks: 0}), debug: () => ({pos: [9, 9, 9]}), enqueue: (type, args, opts) => got.push([type, args, opts])};
    const logs = [];
    const client = new HubClient({url, token, names: ['bot6'], hostLabel: 'lap', log: (w, m) => logs.push(`${w}: ${m}`), makeRunner: () => stub});
    assert.strictEqual(client.world.unreachable, true, 'no reservations before the hub answered');
    assert.strictEqual(await client.world.claim('bot6', 'overworld:1,1,1'), false);
    client.start();
    const r6 = await until(() => runners.get('bot6')?.snapshot().online && runners.get('bot6'), 'worker bot online');
    assert.ok(stub.started);
    assert.strictEqual(client.world.unreachable, false);
    assert.strictEqual(r6.snapshot().host, 'lap');
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
    await until(() => !client.world.unreachable && runners.get('bot6').snapshot().connected, 'client reconnected', 6000);
    assert.strictEqual(stub.started, true);
    client.stop();
    await until(() => !runners.get('bot6').snapshot().connected, 'stopped worker is offline');
    assert.strictEqual(runners.get('bot6').snapshot().online, false);
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
