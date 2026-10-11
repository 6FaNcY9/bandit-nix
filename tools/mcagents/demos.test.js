'use strict';
const assert = require('node:assert/strict');
const http = require('node:http');
const {translate, parseCommand, Agent, demoContext, backends, noteIdle, knownCommand} = require('./agent');
const {DemoRecorder, labelJob, inverse, commandFor, sameJob} = require('./demos');
const {exportSft, balanced} = require('./export-sft');
const {parseVerdict, condense, candidates, runJudge} = require('./judge');
const {offlineTargets, backendBase} = require('./routing');

const chest = {x: -271, y: 66, z: -214};
const places = [{name: 'Tree farm', x: -255, y: 65, z: -231}];
const ctx = {places, pos: [-250, 65, -230], chest};
const deps = {translate, parseCommand};

// ---- inverse translation: translate(parse(inverse(job))) == job for every supported type ----
const jobs = [
  ['mine', {block: 'stone', count: 32}], ['mine', {block: 'iron_ore', count: 5}], ['mine', {block: 'coal_ore', count: 16}],
  ['chop', {count: 12}], ['deposit', {...chest, only: 'logs'}], ['withdraw', {item: 'coal', count: 4, ...chest}],
  ['craft', {item: 'torch', count: 8}], ['smelt', {item: 'raw_iron', count: 29}],
  ['shaft', {x1: -291, z1: -222, x2: -276, z2: -207}], ['treefarm', {x1: -262, z1: -238, x2: -248, z2: -224}],
  ['seal', {x1: -295, z1: -226, x2: -272, z2: -203, y1: 50, y2: 90}], ['homebed', {}],
  ['shift', {block: 'logs', ...chest}], ['goto', {x: -255, y: 65, z: -231}], ['tidy', {x: -250, y: 65, z: -230, radius: 16}],
];
for (const job of jobs) {
  const text = commandFor(job, {...ctx, chest}, deps);
  assert.ok(text, `command for ${job[0]}`);
  assert.ok(knownCommand(parseCommand(text).name), text);
  const t = translate(parseCommand(text), {pos: job[0] === 'tidy' ? [job[1].x, job[1].y, job[1].z] : ctx.pos, supplyChest: ['deposit', 'withdraw', 'shift'].includes(job[0]) ? {x: job[1].x, y: job[1].y, z: job[1].z} : chest, places: Object.fromEntries(places.map((p) => [p.name, p]))});
  assert.ok(sameJob(t.job, job), `round trip ${job[0]}: ${text}`);
}
assert.equal(inverse(jobs[0], ctx), '!collectBlocks("cobblestone", 32)');
assert.equal(inverse(['chop', {count: 3}], ctx), '!collectBlocks("logs", 3)');
assert.equal(inverse(['homebed', {}], ctx), '!setHomeBed');
// no command / not expressible -> null
for (const j of [['rearm', {...chest}], ['wheatfarm', {x1: 1, z1: 1, x2: 5, z2: 5}], ['stock', chest], ['deposit', {...chest, only: ''}], ['goto', {x: 1, y: 2, z: 3}], ['tidy', {x: 0, y: 65, z: 0, radius: 16}], ['craft', {item: 'torch', count: 99}], ['smelt', {item: 'coal_ore', count: 3}]]) {
  assert.equal(commandFor(j, ctx, deps), null, j[0]);
}
// ---- labels as the dashboard writes them -> jobs ----
assert.deepEqual(labelJob('mine', ' stone 32'), ['mine', {block: 'stone', count: 32}]);
assert.deepEqual(labelJob('shaft', ' -291 -222 -276 -207 66 -54'), ['shaft', {x1: -291, z1: -222, x2: -276, z2: -207}]);
assert.deepEqual(labelJob('withdraw', ' logs 4 -271 66 -214'), ['withdraw', {x: -271, y: 66, z: -214, item: 'logs', count: 4}]);
assert.deepEqual(labelJob('deposit', ' -271 66 -214 logs'), ['deposit', {...chest, only: 'logs'}]);
assert.equal(labelJob('wheatfarm', ' 1 2 3 4'), null);
assert.equal(labelJob('mine', ' stone'), null);

// ---- recorder ----
const bot = (name, extra = {}) => ({name, online: true, dead: false, health: 20, food: 18, pos: [-250, 65, -230], inventory: ['oak_log x20', 'stone_pickaxe x1'], job: null, queue: [], ...extra});
const mkState = (bots, extra = {}) => ({bots, supplyChest: chest, places, world: {players: [{name: 'Steve'}], stock: {items: {coal: 3, logs: 40}, age: 5}}, plan: {roster: ['bot3', 'bot4'], current: {id: 'stock-basics', label: 'stock the base chest', kind: 'keeper'}}, ...extra});
let id = 0;
const ev = (bot, kind, text) => ({id: ++id, t: Date.now(), bot, kind, text});
(async () => {
  const lines = [], scans = [];
  const rec = new DemoRecorder({
    fetchScan: async (b) => { scans.push(b); return 'coal_ore 2 3 4'; },
    makeContext: demoContext, verify: (job, c) => commandFor(job, c, deps), logCall: (l) => lines.push(JSON.parse(l)),
    agents: new Set(['bot1']), isSolverJob: (b) => b === 'bot4',
  });
  const busy = mkState([bot('bot1'), bot('bot3', {job: {label: 'mine stone 32', type: 'mine'}}), bot('bot4')]);
  await rec.feed([ev('bot3', 'job', 'started: mine stone 32'), ev('bot4', 'job', 'started: chop 12'), ev('bot1', 'job', 'started: chop 3'), ev('bot3', 'job', 'started: wheatfarm 1 2 3 4')], busy, 1000);
  assert.deepEqual(scans.sort(), ['bot3', 'bot4']);
  assert.equal(lines.length, 0, 'nothing before a result');
  const idle = mkState([bot('bot1'), bot('bot3'), bot('bot4')]);
  await rec.feed([ev('bot3', 'done', 'finished: mine stone 32 (14 s)'), ev('bot4', 'done', 'finished: chop 12 (30 s)'), ev('bot1', 'done', 'finished: chop 3 (3 s)')], idle, 5000);
  assert.equal(lines.length, 2, 'LLM agents are not demonstrators');
  const [a, b] = lines;
  assert.equal(a.kind, 'demo'); assert.equal(a.bot, 'bot3'); assert.equal(a.source, 'keeper'); assert.equal(b.source, 'solver');
  assert.equal(a.messages[2].content, '!collectBlocks("cobblestone", 32)');
  assert.match(a.messages[0].content, /You are an AI Minecraft bot named bot3/);
  assert.match(a.messages[0].content, /YOUR CURRENT ASSIGNED GOAL: "stock the base chest"/);
  assert.match(a.messages[0].content, /Current Action: Idle/, 'the prompt does not show the job it asks for');
  assert.match(a.messages[0].content, /Around you.*coal_ore 2 3 4/);
  assert.match(a.messages[0].content, /Nearby Human Players: None\./, 'no human names in a demo');
  assert.match(a.messages[1].content, /^SYSTEM: Check-in: you are idle.*Base chest \(lowest first\): coal 3, logs 40/);
  assert.equal(a.messages.length, 3);
  // wheatfarm has no command; failed and stopped jobs write nothing; a start and result in one batch has no usable state
  await rec.feed([ev('bot3', 'done', 'finished: wheatfarm 1 2 3 4 (3 s)'), ev('bot3', 'job', 'started: craft torch 8'), ev('bot3', 'fail', 'failed: craft torch 8 - no coal')], idle, 6000);
  await rec.feed([ev('bot4', 'job', 'started: chop 5')], idle, 7000);
  await rec.feed([ev('bot4', 'stop', 'stopped: chop 5')], idle, 8000);
  await rec.feed([ev('bot4', 'job', 'started: craft torch 4'), ev('bot4', 'done', 'finished: craft torch 4 (1 s)')], idle, 9000);
  assert.equal(lines.length, 2);
  // dedupe: the same job in the same coarse state is written once
  await rec.feed([ev('bot3', 'job', 'started: mine stone 32')], idle, 10000);
  await rec.feed([ev('bot3', 'done', 'finished: mine stone 32 (14 s)')], idle, 20000);
  assert.equal(lines.length, 2); assert.equal(rec.stats.duplicate, 1);
  // a different inventory is a different state; the scan is reused inside 30 s and fetched again after
  const other = mkState([bot('bot3', {inventory: ['oak_log x20', 'stone_pickaxe x1', 'coal x40']})]);
  const before = scans.length;
  await rec.feed([ev('bot3', 'job', 'started: mine stone 32')], other, 21000);
  await rec.feed([ev('bot3', 'done', 'finished: mine stone 32 (9 s)')], other, 22000);
  assert.equal(lines.length, 3); assert.equal(scans.length, before, 'scan reused within 30 s');
  await rec.feed([ev('bot3', 'job', 'started: chop 12')], idle, 60000);
  assert.equal(scans.length, before + 1);
  // a death forgets the pending jobs
  await rec.feed([ev('bot3', 'death', 'died at 1 2 3')], idle, 61000);
  await rec.feed([ev('bot3', 'done', 'finished: chop 12 (5 s)')], idle, 62000);
  assert.equal(lines.length, 3);

  // ---- export: demos as source "demo", capped, per-source stats ----
  const decision = (i) => ({t: new Date(1e12 + i * 1000).toISOString(), id: `d${i}`, agent: 'bot2', episode_id: `e${i}`, messages: [{role: 'system', content: `YOUR CURRENT ASSIGNED GOAL: "g${i}"\nSTATS\nx`}, {role: 'user', content: `SYSTEM: Idle ${i}`}], reply: '!goToCoordinates(1, 64, 2)'});
  const demoRow = (i, cmd = `!collectBlocks("cobblestone", ${i})`) => ({kind: 'demo', t: new Date(1e12 + i * 1000).toISOString(), id: `demo-${i}`, source: 'plan', bot: 'bot3', job: 'x', key: `k${i}`, messages: [{role: 'system', content: `sys ${i}`}, {role: 'user', content: 'SYSTEM: Check-in: you are idle.'}, {role: 'assistant', content: cmd}]});
  const recs = [decision(1), {kind: 'outcome', id: 'd1', result: 'good', reason: 'finished', ms: 5}, ...Array.from({length: 40}, (_, i) => demoRow(i)), demoRow(0), {...demoRow(99), key: 'k0'}, {...demoRow(98), messages: [{role: 'system', content: 'https://x.test'}, ...demoRow(98).messages.slice(1)]}, {...demoRow(97, 'hello'), key: 'k97'}];
  let r = exportSft(recs);
  assert.equal(r.stats.decision_rows, 1); assert.equal(r.stats.demo_rows, 30, 'cap = 3 x max(decisions, 10)');
  assert.deepEqual(r.stats.sources, {decision: 1, solver: 0, demo: 30, judged: 0});
  assert.ok(r.rows.filter((x) => x.source === 'demo').every((x) => x.messages.length === 3 && ['train', 'val', 'test'].includes(x.split)));
  assert.equal(exportSft(recs, {demoRatio: 0}).stats.demo_rows, 0);
  assert.equal(exportSft(recs, {demoRatio: 100}).stats.demo_rows, 40, 'duplicates, URLs and non-commands are not exported');
  const mixed = balanced([...Array.from({length: 10}, (_, i) => ({command: '!a', t: i})), {command: '!b', t: 0}, {command: '!c', t: 1}], 6);
  assert.deepEqual(mixed.map((x) => x.command).sort(), ['!a', '!a', '!a', '!a', '!b', '!c'], 'one command cannot fill the cap');

  // judged rows: off by default; only unknown outcomes; a real outcome beats a grade
  const jr = [decision(5), decision(6), decision(7), {kind: 'outcome', id: 'd7', result: 'bad', reason: 'failed', ms: 1}];
  const grades = [{kind: 'judge', ref: 'd5', verdict: 'good'}, {kind: 'judge', ref: 'd6', verdict: 'bad'}, {kind: 'judge', ref: 'd7', verdict: 'good'}];
  assert.equal(exportSft(jr, {judgments: grades}).stats.judged_rows, 0);
  r = exportSft(jr, {judgments: grades, judged: true});
  assert.equal(r.stats.judged_rows, 1); assert.equal(r.stats.sources.decision, 0);
  assert.equal(r.rows[0].source, 'judged'); assert.match(r.rows[0].messages[1].content, /Idle 5/);

  // ---- judge ----
  assert.deepEqual(parseVerdict('good | fits the inventory'), {verdict: 'good', reason: 'fits the inventory'});
  assert.deepEqual(parseVerdict('<think>x</think>\n**Bad**: repeats the failure'), {verdict: 'bad', reason: 'repeats the failure'});
  assert.deepEqual(parseVerdict('Verdict: good'), {verdict: 'good', reason: ''});
  assert.equal(parseVerdict('I think this is good'), null); assert.equal(parseVerdict(''), null); assert.equal(parseVerdict('goodness'), null);
  const cond = condense([{role: 'system', content: 'head\n*COMMAND DOCS\n!a: x\n*\ntail'}, {role: 'user', content: 'SYSTEM: Idle'}], '!stop');
  assert.ok(!cond.includes('!a: x') && cond.includes('REPLY TO GRADE: !stop') && cond.includes('tail'));
  const unknown = [decision(1), decision(2), {...decision(3), reply: 'just talk'}, {...decision(4), reply: '!notACommand(1)'}, {...decision(5), messages: decision(2).messages}];
  assert.deepEqual(candidates(unknown, new Set(), 10).map((c) => c.id), ['d5', 'd1'], 'newest first, valid commands only, no repeated situation');
  assert.deepEqual(candidates(unknown, new Set(['d5']), 10).map((c) => c.id), ['d2', 'd1'], 'judged ones are skipped');
  assert.equal(candidates(unknown, new Set(), 1).length, 1);

  // the judge stops when the PC goes away (health) and never follows a redirect
  let served = 0;
  const server = http.createServer((req, res) => {
    if (req.url === '/health') { res.statusCode = served >= 1 ? 503 : 200; return res.end('{}'); }
    req.resume(); req.on('end', () => { served++; res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({model: 'alias', choices: [{message: {content: 'good | ok'}}]})); });
  });
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const run = await runJudge(`http://127.0.0.1:${server.address().port}`, candidates(unknown, new Set(), 5).map((c) => ({...c})), '!stop');
  assert.deepEqual(run.grades, [{ref: 'd5', verdict: 'good', reason: 'ok'}]); assert.match(run.stopped, /health lost/); assert.equal(run.alias, 'alias');
  server.close();

  // ---- routing split ----
  const env = {ANDY_URLS: 'http://127.0.0.1:18081,http://127.0.0.1:18082', ANDY_BACKEND_NAMES: 'slayer,albert', ANDY_OFFLINE_NAMES: 'albert', OLLAMA_URL: 'http://127.0.0.1:11434', ANDY_PREFER: 'lab'};
  const saved = {...process.env};
  Object.assign(process.env, env);
  assert.deepEqual(backends().map((x) => [x.name, x.url]), [['lab', 'http://127.0.0.1:11434'], ['slayer', 'http://127.0.0.1:18081']], 'live: lab + slayer, never albert');
  assert.deepEqual(offlineTargets(env), [{name: 'albert', url: 'http://127.0.0.1:18082'}], 'offline: albert only');
  assert.ok(!offlineTargets(env).some((t) => t.url.includes(':11434') || t.name === 'slayer'));
  assert.deepEqual(offlineTargets({...env, ANDY_OFFLINE_NAMES: ''}).map((t) => t.name), ['slayer', 'albert'], 'no offline names: all PCs (old behaviour)');
  assert.throws(() => offlineTargets({...env, ANDY_URLS: 'http://127.0.0.1:11434', ANDY_BACKEND_NAMES: 'lab', ANDY_OFFLINE_NAMES: 'lab'}), /Refusing/);
  assert.throws(() => backendBase('http://127.0.0.1:11434'), /Refusing/);
  process.env.ANDY_OFFLINE_NAMES = 'albert,slayer';
  assert.deepEqual(backends().map((x) => x.name), ['lab'], 'a live path with only offline PCs falls back to the lab alone');
  for (const k of Object.keys(env)) if (!(k in saved)) delete process.env[k]; else process.env[k] = saved[k];

  // ---- idle wake ----
  const ag = new Agent('bot1', 'g', null);
  assert.equal(noteIdle(ag, bot('bot1', {job: {label: 'x'}}), 1), false);
  ag.wake = false;
  assert.equal(noteIdle(ag, bot('bot1'), 2), true, 'job just ended: ask now');
  assert.ok(ag.wake && ag.wakeAt === 2);
  ag.wake = false;
  assert.equal(noteIdle(ag, bot('bot1'), 3), false, 'staying idle is the check-in\'s job');
  assert.equal(noteIdle(ag, bot('bot1', {queue: [1]}), 4), false);
  assert.equal(noteIdle(ag, bot('bot1', {dead: true}), 5), false);
  console.log('demos, export, judge, routing tests passed');
})().catch((e) => { console.error(e); process.exitCode = 1; });

{ // the judge may use slayer too (JUDGE_NAMES), never Ollama, and splits the work into disjoint slices
  const J = require('./judge');
  const env = {ANDY_URLS: 'http://127.0.0.1:18081,http://127.0.0.1:18082', ANDY_BACKEND_NAMES: 'slayer,albert', ANDY_OFFLINE_NAMES: 'albert', JUDGE_NAMES: 'albert,slayer'};
  assert.deepStrictEqual(J.judgeTargets(env).map((x) => x.name), ['slayer', 'albert']);
  assert.deepStrictEqual(J.judgeTargets({...env, JUDGE_NAMES: ''}).map((x) => x.name), ['albert']);
  assert.throws(() => J.judgeTargets({ANDY_URLS: 'http://127.0.0.1:11434', ANDY_BACKEND_NAMES: 'lab', JUDGE_NAMES: 'lab'}), /never Ollama/);
  assert.deepStrictEqual(J.slices([1, 2, 3, 4, 5], 2), [[1, 3, 5], [2, 4]]);
  console.log('ok judge targets');
}
