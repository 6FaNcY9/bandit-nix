'use strict';
// node tools/mcagents/agent.test.js — the Mindcraft command translator.
const assert = require('node:assert');
process.env.LOG ||= require('node:path').join(require('node:os').tmpdir(), `mcagents-test-${process.pid}.jsonl`); // decide() logs every model call
const {decide, Agent, workersOf, idleWorkers, noteWorker, trackError, parseCommand, translate, commandDocs, inventoryText, repeatHint, isRoutine, Budget, promptReason, assignJob, workersText, assigner, onEvent, baseStatusText, baseLine, noteSent, noteFinished} = require('./agent');

assert.deepStrictEqual(parseCommand('Sure! !collectBlocks("oak_log", 10)'), {name: 'collectBlocks', args: ['oak_log', 10]});
assert.deepStrictEqual(parseCommand("Bye! !endConversation('john')"), {name: 'endConversation', args: ['john']});
assert.deepStrictEqual(parseCommand('<think>maybe !stop</think>Let me look. !inventory'), {name: 'inventory', args: []}, 'thinking is ignored');
assert.strictEqual(parseCommand('hello there'), null);

const ctx = {pos: [1, 64, 2], supplyChest: {x: 5, y: 64, z: 5}, places: {base: {x: 9, y: 70, z: 9}}};
const tr = (s) => translate(parseCommand(s), ctx);
assert.deepStrictEqual(tr('!collectBlocks("oak_log", 10)'), {job: ['chop', {count: 10}]});
assert.deepStrictEqual(tr('!collectBlocks("cobblestone", 8)'), {job: ['mine', {block: 'stone', count: 8}]});
assert.deepStrictEqual(tr('!collectBlocks("iron_ore", 5)'), {job: ['mine', {block: 'iron_ore', count: 5}]});
assert.deepStrictEqual(tr('!collectBlocks("coal", 5)'), {job: ['mine', {block: 'coal_ore', count: 5}]}, 'an ore by its item name');
assert.deepStrictEqual(tr('!startShift("raw_iron")'), {job: ['shift', {block: 'iron_ore', x: 5, y: 64, z: 5}]});
assert.deepStrictEqual(tr('!startShift("lapis_lazuli")'), {job: ['shift', {block: 'lapis_lazuli', x: 5, y: 64, z: 5}]}, 'unknown names pass through to the validator');
assert.deepStrictEqual(tr('!putInChest("raw_iron", 5)'), {job: ['deposit', {x: 5, y: 64, z: 5, only: 'raw_iron'}]});
assert.deepStrictEqual(tr('!takeFromChest("coal", 3)'), {job: ['withdraw', {x: 5, y: 64, z: 5, item: 'coal', count: 3}]});
assert.deepStrictEqual(tr('!goToRememberedPlace("base")'), {job: ['goto', {x: 9, y: 70, z: 9}]});
assert.deepStrictEqual(tr('!craftRecipe("stick", 4)'), {job: ['craft', {item: 'stick', count: 4}]});
assert.deepStrictEqual(tr('!stop'), {job: ['stop', {}]});
assert.deepStrictEqual(tr('!digRoom(-272, 58, -219, 7, 7, 4)'), {job: ['excavate', {x1: -272, y1: 58, z1: -219, x2: -266, y2: 61, z2: -213}]});
assert.ok(tr('!digRoom(0, 60, 0, 12, 3, 3)').refuse, 'too wide');
assert.deepStrictEqual(tr('!placeBlockAt("chest", -270, 58, -213)'), {job: ['place', {item: 'chest', x: -270, y: 58, z: -213}]});
assert.match(tr('!smeltItem("coal_ore", 5)').refuse, /gives coal/);
assert.match(tr('!smeltItem("deepslate_iron_ore", 2)').refuse, /Smelt raw_iron instead/);
assert.deepStrictEqual(tr('!smeltItem("raw_iron", 3)'), {job: ['smelt', {item: 'raw_iron', count: 3}]});
assert.ok(tr('!newAction("build a house")').refuse, 'code writing is refused');
assert.ok(tr('!attackPlayer("steve")').refuse, 'unknown commands are refused');
assert.ok(translate(parseCommand('!putInChest("dirt", 1)'), {pos: null, supplyChest: null}).refuse);
assert.strictEqual(tr('!inventory').query, 'inventory');
assert.strictEqual(tr('!buildBlueprint("test-pad-3x3", 1, 64, 2)').local, 'buildBlueprint');
assert.ok(commandDocs(['test-pad-3x3']).includes('!collectBlocks: Collect the nearest blocks'));
assert.ok(!commandDocs().includes('!newAction'), 'code writing is not offered');
assert.strictEqual(inventoryText({inventory: ['cobblestone x12', 'oak_log x3']}), 'INVENTORY\n- cobblestone: 12\n- oak_log: 3\n');
assert.match(repeatHint('!buildBlueprint("test-pad-3x3", -95, 66, -15)'), /failed twice.*Do not repeat it/);
// H1: routines as commands.
assert.deepStrictEqual(tr('!startShift("oak_log")'), {job: ['shift', {block: 'logs', x: 5, y: 64, z: 5}]});
assert.deepStrictEqual(tr('!startShift("cobblestone")'), {job: ['shift', {block: 'stone', x: 5, y: 64, z: 5}]});
assert.deepStrictEqual(tr('!startShift("iron_ore")'), {job: ['shift', {block: 'iron_ore', x: 5, y: 64, z: 5}]});
assert.ok(translate(parseCommand('!startShift("logs")'), {pos: null, supplyChest: null}).refuse, 'a shift needs the base chest');
assert.ok(tr('!startShift()').refuse);
assert.deepStrictEqual(tr('!guardHere(20)'), {job: ['guard', {x: 1, y: 64, z: 2, radius: 20}]});
assert.deepStrictEqual(tr('!guardHere(500)').job[1].radius, 48);
assert.deepStrictEqual(tr('!guardHere(1)').job[1].radius, 4);
assert.deepStrictEqual(tr('!guardHere').job[1].radius, 16);
assert.strictEqual(tr('!afkHere').local, 'afkHere');
assert.ok(isRoutine({type: 'shift'}) && isRoutine({type: 'guard'}) && isRoutine({type: 'follow'}));
assert.ok(!isRoutine({type: 'mine'}) && !isRoutine(null));
for (const c of ['startShift', 'guardHere', 'afkHere']) assert.ok(commandDocs().includes(`!${c}:`), c);
// H2: event-driven prompting and the global cap.
const B = new Budget(3);
assert.ok(B.take(1000) && B.take(1001) && B.take(1002));
assert.ok(!B.take(1003), 'cap of 3 per minute');
assert.ok(B.take(61001), 'the window slides');
const ag = (o = {}) => ({inbox: [], goal: 'work', afk: false, wake: false, lastDecisionAt: 0, ...o});
const bot = (o = {}) => ({online: true, dead: false, job: null, queue: [], ...o});
const T = 10 * 60000;
assert.strictEqual(promptReason(ag({wake: true}), bot(), T, T), 'event', 'a job result wakes an idle bot');
assert.strictEqual(promptReason(ag({lastDecisionAt: 1000}), bot(), 1500, T), null, 'idle, nothing happened: no prompt');
assert.strictEqual(promptReason(ag({lastDecisionAt: 1000}), bot({job: {type: 'shift'}}), 1500, T), null, 'a routine is not re-prompted');
assert.strictEqual(promptReason(ag({lastDecisionAt: 1000}), bot({job: {type: 'shift'}}), 1000 + T, T), 'checkin', 'check-in during a routine');
assert.strictEqual(promptReason(ag({wake: true}), bot({job: {type: 'mine'}}), T, T), null, 'a plain job is never interrupted');
assert.strictEqual(promptReason(ag({wake: true}), bot({queue: [{}]}), T, T), null, 'a queued job (rearm) is not idle');
assert.strictEqual(promptReason(ag({wake: true, inbox: ['hi']}), bot({job: {type: 'mine'}}), T, T), 'message', 'a message prompts even while working');
assert.strictEqual(promptReason(ag({wake: true, afk: true}), bot(), T, T), null, 'afk stays silent');
assert.strictEqual(promptReason(ag({afk: true, inbox: ['hi']}), bot(), T, T), 'message', 'a message ends afk');
assert.strictEqual(promptReason(ag({wake: true, goal: ''}), bot(), T, T), null, 'no goal, no self-prompt');
assert.strictEqual(promptReason(ag({wake: true}), bot({dead: true}), T, T), null);
assert.strictEqual(promptReason(ag({wake: true}), bot({online: false}), T, T), null);
// H4: foreman. The nested command survives quotes and escapes.
for (const t of ['!assign("bot12", "!collectBlocks(\\"iron_ore\\", 32)")', '!assign("bot12", "!collectBlocks("iron_ore", 32)")', "ok !assign('bot12', '!collectBlocks(\\'iron_ore\\', 32)')"]) {
  assert.deepStrictEqual(parseCommand(t).args[0], 'bot12', t);
  assert.ok(/^!collectBlocks\(.iron_ore., 32\)$/.test(parseCommand(t).args[1]), t);
}
assert.deepStrictEqual(parseCommand('!assign("bot12", "!stop")').args, ['bot12', '!stop']);
assert.strictEqual(tr('!assign("bot12", "!stop")').local, 'assign');
const st = {supplyChest: {x: 5, y: 64, z: 5}, bots: [{name: 'bot12', online: true, pos: [3, 64, 3], job: null}, {name: 'bot13', online: true, job: {type: 'shift', label: 'shift logs'}}, {name: 'bot14', online: false}]};
const W = new Set(['bot12', 'bot13', 'bot14']);
const asg = (t, w = W) => assignJob(parseCommand(t), w, st);
assert.deepStrictEqual(asg('!assign("bot12", "!collectBlocks(\\"iron_ore\\", 32)")'), {worker: 'bot12', job: ['mine', {block: 'iron_ore', count: 32}], replace: false});
assert.deepStrictEqual(asg('!assign("bot13", "!collectBlocks(\\"cobblestone\\", 8)")'), {worker: 'bot13', job: ['mine', {block: 'stone', count: 8}], replace: true}, 'a routine is replaced');
assert.ok(asg('!assign("bot1", "!stop")').refuse, 'not a worker');
assert.ok(asg('!assign("bot12", "!stop")', new Set(['bot13'])).refuse, 'bot12 is not listed');
assert.ok(asg('!assign("bot14", "!stop")').refuse, 'offline');
assert.ok(asg('!assign("bot12", "!inventory")').refuse, 'queries cannot be assigned');
assert.ok(asg('!assign("bot12", "!assign(\\"bot13\\", \\"!stop\\")")').refuse, 'no chains');
assert.ok(asg('!assign("bot12", "!newAction(\\"x\\")")').refuse, 'no code');
assert.ok(asg('!assign("bot12", "!buildBlueprint(\\"test-pad-3x3\\", 1, 2, 3)")').refuse, 'blueprints stay with the brain');
assert.ok(asg('!assign("bot12", "hello")').refuse);
assert.ok(asg('!assign("bot12")').refuse);
assert.deepStrictEqual(asg('!assign("bot12", "!putInChest(\\"cobblestone\\", 5)")').job, ['deposit', {x: 5, y: 64, z: 5, only: 'cobblestone'}]);
assert.strictEqual(workersText(W, st), 'YOUR WORKERS (use !assign)\n- bot12: idle\n- bot13: shift logs\n');
assert.ok(commandDocs([], ['bot12']).includes('!assign:') && !commandDocs().includes('!assign'), 'assign is offered only with workers');
console.log('ok');

assert.deepStrictEqual(idleWorkers(new Set(['bot2', 'bot16', 'bot17', 'bot18']), {bots: [
  {name: 'bot2', online: true, job: {type: 'shift'}, queue: []}, {name: 'bot16', online: true, job: null, queue: []},
  {name: 'bot17', online: false, job: null, queue: []}, {name: 'bot18', online: true, dead: true, job: null, queue: []}, {name: 'bot1', online: true, job: null, queue: []}]}), ['bot16']);
assert.ok(!new Agent('bot1', 'g', null).system({bots: [], places: [], world: {}}, {name: 'bot1', pos: [0, 0, 0], inventory: []}).includes("Sure, I'll stop"), 'no example answer to copy');
{ // a foreman with idle workers is asked even while its own job runs
  const a = {inbox: [], goal: 'lead', wake: true, lastDecisionAt: 0};
  const busyBot = {online: true, job: {type: 'rearm'}, queue: []};
  assert.strictEqual(promptReason(a, busyBot, 1000, 600000, 0), null);
  assert.strictEqual(promptReason(a, busyBot, 1000, 600000, 2), 'workers');
}
{ // a worker failing twice for the same reason rests (does not wake the foreman) for 5 minutes
  const st = {bots: [{name: 'bot9', online: true, job: null, queue: []}]};
  const ws = new Set(['bot9']);
  noteWorker('bot9', 'failed: shift stone -260 63 -213 - no pickaxe and could not make one: could not reach -278 63 -211', 1000);
  assert.deepStrictEqual(idleWorkers(ws, st, 2000), ['bot9']);
  noteWorker('bot9', 'failed: shift coal_ore -260 63 -213 - no pickaxe and could not make one: could not reach -279 63 -210', 3000);
  assert.deepStrictEqual(idleWorkers(ws, st, 4000), [], 'resting');
  assert.deepStrictEqual(idleWorkers(ws, st, 3000 + 300001), ['bot9'], 'after 5 minutes again');
  noteWorker('bot9', 'finished: shift stone (10 s)', 5000);
  assert.deepStrictEqual(idleWorkers(ws, st, 6000), ['bot9'], 'a success clears it');
}
{ // a foreman's command docs list only its few commands; workers and lone agents keep the full set
  const docs = commandDocs([], ['bot2']);
  const listed = [...docs.matchAll(/^!(\w+):/gm)].map((m) => m[1]).sort();
  assert.deepStrictEqual(listed, ['assign', 'baseStatus', 'buildBlueprint', 'digRoom', 'goToCoordinates', 'inventory', 'placeBlockAt', 'startConversation', 'stats', 'stop', 'viewChest']);
  assert.ok([...commandDocs().matchAll(/^!(\w+):/gm)].length > 20 && commandDocs().includes('!collectBlocks:'), 'no workers: the full set');
  assert.deepStrictEqual(tr('!collectBlocks("stone", 3)'), {job: ['mine', {block: 'stone', count: 3}]}, 'translate() is unchanged for workers');
}
{ // the foreman's base summary: chest counts from the last stock/deposit and which parts are done
  const fm = new Agent('bot1', 'lead', null);
  fm.workers = new Set(['bot2']);
  const state = {bots: [{name: 'bot1', online: true, pos: [0, 64, 0], inventory: []}, {name: 'bot2', online: true, job: null, queue: []}], world: {stock: {items: {coal: 12, cobblestone: 64}, by: 'bot3', age: 30}}, places: []};
  assert.strictEqual(baseLine(fm, state), 'BASE: chest (lowest first) coal 12, cobblestone 64 (counted 30 s ago). Already done: nothing built or dug yet.\n');
  assert.match(baseLine(fm, {...state, world: {}}), /chest not counted yet/);
  noteSent(fm, ['build', {origin: {x: -272, y: 65, z: -219}, blocks: new Array(22).fill({})}], 'base-hall');
  noteSent(fm, ['excavate', {x1: -272, y1: 58, z1: -219, x2: -266, y2: 61, z2: -213}]);
  noteFinished(fm, 'finished: build at -272 65 -219 22 blocks false - already complete (0 s)');
  assert.deepStrictEqual([...fm.done], ['built base-hall at -272 65 -219']);
  noteFinished(fm, 'finished: build at 1 2 3 5 blocks false (4 s)');
  assert.strictEqual(fm.done.size, 1, 'a build we did not send is not recorded');
  noteSent(fm, ['build', {origin: {x: 0, y: 70, z: 0}, blocks: new Array(5).fill({})}], 'wall-a');
  noteSent(fm, ['build', {origin: {x: 0, y: 70, z: 0}, blocks: new Array(5).fill({})}], 'wall-b');
  noteFinished(fm, 'failed: build at 0 70 0 5 blocks false - could not reach 1 2 3'); // wall-a failed
  noteFinished(fm, 'finished: build at 0 70 0 5 blocks false (9 s)'); // wall-b, same origin and size
  assert.deepStrictEqual([...fm.done], ['built base-hall at -272 65 -219', 'built wall-b at 0 70 0']);
  fm.done.delete('built wall-b at 0 70 0');
  noteFinished(fm, 'finished: excavate -272 58 -219 -266 61 -213 (50 s)');
  assert.match(baseLine(fm, state), /Already done: built base-hall at -272 65 -219; dug room -272 58 -219 7x7x4\./);
  const prompt = fm.system(state, state.bots[0]);
  assert.ok(prompt.includes('BASE: chest (lowest first) coal 12, cobblestone 64') && prompt.includes('YOUR WORKERS') && !prompt.includes('!collectBlocks:') && !prompt.includes('!startShift:'));
  assert.ok(!new Agent('bot9', 'g', null).system(state, state.bots[0]).includes('BASE:'), 'only a foreman has the base line');
  // worker lines carry the last result and a stuck note
  noteWorker('bot2', 'failed: shift stone 1 2 3 - no pickaxe: could not reach 1 2 3', 1);
  noteWorker('bot2', 'failed: shift stone 1 2 3 - no pickaxe: could not reach 4 5 6');
  fm.last.set('bot2', 'failed: shift stone 1 2 3 - no pickaxe: could not reach 4 5 6');
  assert.match(baseStatusText(fm, state), /^BASE STATUS\nYOUR WORKERS \(use !assign\)\n- bot2: idle \(last: failed: shift stone.*\) STUCK.*\nBASE: chest \(lowest first\) coal 12, cobblestone/);
  assert.match(assignJob(parseCommand('!assign("bot2", "!startShift(\\"logs\\")")'), new Set(['bot2']), {...state, supplyChest: {x: 1, y: 2, z: 3}}).refuse, /bot2 is resting after two identical failures \(no pickaxe: could not reach #.*\)\. Give the work to another worker/, 'a stuck worker gets no order');
  noteWorker('bot2', 'finished: shift stone (3 s)');
  assert.ok(assignJob(parseCommand('!assign("bot2", "!startShift(\\"logs\\")")'), new Set(['bot2']), {...state, supplyChest: {x: 1, y: 2, z: 3}}).job, 'after a success it can be assigned again');
}
{ // events: a worker's deposit reaches its foreman as one short line, without waking it
  const fm = new Agent('bot1', 'lead', null);
  fm.workers = new Set(['bot3']);
  fm.wake = false;
  const agents = new Map([['bot1', fm]]);
  onEvent(agents, {bot: 'bot3', kind: 'deposit', text: 'deposited 64 cobblestone at the supply chest'});
  assert.strictEqual(fm.history.length, 0, 'bot3 was never assigned by this foreman');
  assigner.set('bot3', 'bot1');
  onEvent(agents, {bot: 'bot3', kind: 'deposit', text: 'deposited 64 cobblestone, 12 coal at the supply chest'});
  onEvent(agents, {bot: 'bot3', kind: 'deposit', text: 'deposited 5 oak_log at 1 2 3'});
  assert.deepStrictEqual(fm.history, [{role: 'system', content: 'bot3 put 64 cobblestone, 12 coal into the base chest'}], 'one line; a chest that is not the base chest is not news');
  assert.strictEqual(fm.wake, false);
  for (let i = 1; i <= 5; i++) onEvent(agents, {bot: 'bot3', kind: 'deposit', text: `deposited ${i} coal at the supply chest`});
  assert.deepStrictEqual(fm.history.map((m) => m.content), ['bot3 put 3 coal into the base chest', 'bot3 put 4 coal into the base chest', 'bot3 put 5 coal into the base chest'], 'the history keeps the last three');
  onEvent(agents, {bot: 'bot3', kind: 'done', text: 'finished: build at 1 2 3 5 blocks false - already complete (0 s)'});
  assert.strictEqual(fm.last.get('bot3'), 'finished: build at 1 2 3 5 blocks false - already complete (0 s)');
  assert.ok(fm.wake && fm.history.at(-1).content.startsWith('Worker bot3: finished: build'));
  assigner.delete('bot3');
  fm.wake = false;
  onEvent(agents, {bot: 'bot10', kind: 'alert', text: 'night falls'});
  assert.ok(fm.wake && fm.history.at(-1).content === 'ALERT: night falls', 'an alert goes to every foreman');
}
{ // each agent its own crew; agents are never workers
  const ag = new Map([['bot1', 1], ['bot2', 1]]);
  const env = {WORKERS: 'bot3,bot4', WORKERS_bot2: 'bot3, bot1'};
  assert.deepStrictEqual([...workersOf(env, 'bot1', ag)], ['bot3', 'bot4']);
  assert.deepStrictEqual([...workersOf(env, 'bot2', ag)], ['bot3']);
  assert.deepStrictEqual([...workersOf({}, 'bot1', ag)], []);
}
// decide() against a fake dashboard and model (global fetch): MC-4 regressions.
(async () => {
  const realFetch = globalThis.fetch;
  const run = async ({replies, jobOk = true, budget = {take: () => true}}) => {
    const calls = {model: 0, jobs: []};
    globalThis.fetch = async (url, opt = {}) => {
      const body = opt.body ? JSON.parse(opt.body) : null;
      if (url.includes('/api/chat')) assert.ok(!opt.headers?.Origin && !opt.headers?.Authorization, 'Ollama gets neither Origin nor a bearer');
      const reply = (code, obj) => ({ok: code < 400, status: code, json: async () => obj});
      if (url.endsWith('/api/chat')) return reply(200, {message: {content: replies[Math.min(calls.model++, replies.length - 1)]}});
      if (url.endsWith('/api/decision')) return reply(200, {ok: true});
      if (url.endsWith('/api/job')) {
        calls.jobs.push(body.type);
        return jobOk ? reply(200, {}) : reply(500, {error: 'dashboard down'});
      }
      return reply(404, {});
    };
    const agent = new Agent('bot1', 'mine coal', null);
    Object.assign(agent, {wake: false});
    const state = {bots: [{name: 'bot1', online: true, pos: [0, 64, 0], inventory: [], queue: [], job: {type: 'shift', label: 'shift coal_ore'}}], places: []};
    await decide(agent, new Map([['bot1', agent]]), async () => state, budget);
    return {agent, calls};
  };
  try {
    for (const cmd of ['!afkHere', '!endGoal']) {
      let {agent, calls} = await run({replies: [cmd], jobOk: false}); // Stop failed: stay awake, keep the goal
      assert.deepStrictEqual(calls.jobs, ['stop'], cmd);
      assert.ok(!agent.afk && agent.goal === 'mine coal' && agent.wake, `${cmd}: a failed Stop must not silence the agent`);
      assert.match(agent.history.at(-1).content, /Stop failed/);
      ({agent} = await run({replies: [cmd]})); // acknowledged Stop: now quiet
      assert.ok(cmd === '!afkHere' ? agent.afk : agent.goal === '', cmd);
    }
    { // the same command after two failures is refused without a job
      const agent = new Agent('bot1', 'mine coal', null);
      Object.assign(agent, {lastCommand: '!collectBlocks("coal_ore", 5)', failures: 2, lastFailure: 'no pickaxe'});
      const jobs = [];
      globalThis.fetch = async (url, opt = {}) => ({ok: true, status: 200, json: async () => (url.endsWith('/api/chat') ? {message: {content: '!collectBlocks("coal_ore", 5)'}} : (jobs.push(url), {}))});
      const state = {bots: [{name: 'bot1', online: true, pos: [0, 64, 0], inventory: [], queue: [], job: null}], places: []};
      await decide(agent, new Map([['bot1', agent]]), async () => state, {take: () => true});
      assert.ok(!jobs.some((u) => u.endsWith('/api/job')), 'no job for a twice-failed command');
      assert.match(agent.history.at(-1).content, /Refused: .*no pickaxe/);
    }
    { // a new order replaces a running routine instead of queueing behind it forever
      const agent = new Agent('bot1', 'mine coal', null);
      let sent;
      globalThis.fetch = async (url, opt = {}) => ({ok: true, status: 200, json: async () => (url.endsWith('/api/chat') ? {message: {content: '!collectBlocks("coal_ore", 5)'}} : (url.endsWith('/api/job') && (sent = JSON.parse(opt.body)), {}))});
      const state = {bots: [{name: 'bot1', online: true, pos: [0, 64, 0], inventory: [], queue: [], job: {type: 'shift', label: 'shift stone'}}], places: []};
      await decide(agent, new Map([['bot1', agent]]), async () => state, {take: () => true});
      assert.strictEqual(sent.replace, true);
      state.bots[0].job = {type: 'mine', label: 'mine'};
      await decide(agent, new Map([['bot1', agent]]), async () => state, {take: () => true});
      assert.strictEqual(sent.replace, false, 'a plain job finishes first');
    }
    { // same job type failing with the same reason twice: a different command of that type is refused too
      const a = {};
      trackError(a, 'failed: build at -272 65 -219 22 blocks false - could not reach -260 63 -213: No path to the goal!');
      trackError(a, 'failed: build at -272 65 -219 10 blocks false - could not reach -260 63 -213: No path to the goal!');
      assert.strictEqual(a.errStreak, 2);
      trackError(a, 'failed: build at -272 65 -219 7 blocks false - could not reach -261 64 -213: No path to the goal!');
      assert.strictEqual(a.errStreak, 3, 'numbers do not make a new reason');
      trackError(a, 'finished: goto -260 63 -213 (3 s)');
      assert.strictEqual(a.errStreak, 0, 'a success clears it');
      const agent = new Agent('bot1', 'build', null);
      Object.assign(agent, {errStreak: 2, lastErrType: 'build', lastFailure: 'could not reach the chest'});
      const jobs = [];
      globalThis.fetch = async (url, opt = {}) => ({ok: true, status: 200, json: async () => (url.endsWith('/api/chat') ? {message: {content: '!buildBlueprint("test-pad-3x3", 1, 64, 1)'}} : (jobs.push(url), {}))});
      const state = {bots: [{name: 'bot1', online: true, pos: [0, 64, 0], inventory: [], queue: [], job: null}], places: []};
      await decide(agent, new Map([['bot1', agent]]), async () => state, {take: () => true});
      assert.ok(!jobs.some((u) => u.endsWith('/api/job')));
      assert.match(agent.history.at(-1).content, /build jobs failed 2 times/);
    }
    { // a foreman never gathers itself
      const agent = new Agent('bot1', 'lead', null);
      agent.workers = new Set(['bot2']);
      const jobs = [];
      globalThis.fetch = async (url, opt = {}) => ({ok: true, status: 200, json: async () => (url.endsWith('/api/chat') ? {message: {content: '!collectBlocks("stone", 32)'}} : (jobs.push(url), {}))});
      const state = {bots: [{name: 'bot1', online: true, pos: [0, 64, 0], inventory: [], queue: [], job: null}], places: []};
      await decide(agent, new Map([['bot1', agent]]), async () => state, {take: () => true});
      assert.ok(!jobs.some((u) => u.endsWith('/api/job')));
      assert.match(agent.history.at(-1).content, /you lead.*!assign\("worker", "!collectBlocks\(\\"stone\\", 32\)"\)/);
    }
    { // a foreman gets a one-line refusal for a command it does not have, and !baseStatus answers from known facts
      const fm = new Agent('bot1', 'lead', null);
      fm.workers = new Set(['bot2']);
      const jobs = [];
      let reply;
      globalThis.fetch = async (url, opt = {}) => ({ok: true, status: 200, json: async () => (url.endsWith('/api/chat') ? {message: {content: reply}} : (jobs.push(url), {}))});
      const state = {bots: [{name: 'bot1', online: true, pos: [0, 64, 0], inventory: [], queue: [], job: null}, {name: 'bot2', online: true, job: {type: 'shift', label: 'shift logs'}, queue: []}], world: {stock: {items: {coal: 2}, by: 'bot2', age: 200}}, places: []};
      const once = async (r) => { reply = r; fm.history = []; await decide(fm, new Map([['bot1', fm]]), async () => state, {take: () => true}); return fm.history.filter((m) => m.role === 'system').map((m) => m.content); };
      for (const r of ['!entities', '!goal("x")', '!rememberHere("a")', '!afkHere', '!craftRecipe("stick", 1)', '!help']) {
        const [first] = await once(r);
        assert.match(first, /^Refused: !\w+ is not one of your commands\. Yours: !assign.*!startConversation\.$/, r);
        assert.ok(!first.includes('\n'), 'one line');
      }
      assert.match((await once('!startShift("stone")'))[0], /you lead.*!assign\("worker", "!startShift\(\\"stone\\"\)"\)/);
      assert.ok(!jobs.some((u) => u.endsWith('/api/job')), 'nothing was sent for a refused command');
      const [status] = await once('!baseStatus');
      assert.match(status, /^BASE STATUS\nYOUR WORKERS \(use !assign\)\n- bot2: shift logs\nBASE: chest \(lowest first\) coal 2 \(counted 3 min ago\)\./);
      await once('!stats'); // listed commands still work
      assert.match(fm.history[1].content, /^STATS/);
      await once('!goToCoordinates(1, 64, 2)');
      assert.ok(jobs.some((u) => u.endsWith('/api/job')), 'a listed command is sent');
      const lone = new Agent('bot1', 'solo', null); // no workers: !entities and !baseStatus behave as before
      reply = '!entities';
      await decide(lone, new Map([['bot1', lone]]), async () => state, {take: () => true});
      assert.match(lone.history[1].content, /^NEARBY_ENTITIES/);
      reply = '!baseStatus';
      lone.history = [];
      await decide(lone, new Map([['bot1', lone]]), async () => state, {take: () => true});
      assert.match(lone.history[1].content, /not available here/);
    }
    { // a part that already finished is not built again (the model copies its last command)
      const fm = new Agent('bot1', 'lead', null);
      fm.workers = new Set(['bot2']);
      const bp = JSON.parse(require('node:fs').readFileSync(require('node:path').join(__dirname, '../../hosts/bandit-lab/services/mcbots/blueprints/test-pad-3x3.json'), 'utf8'));
      const jobs = [];
      globalThis.fetch = async (url, opt = {}) => ({ok: true, status: 200, json: async () => (url.endsWith('/api/chat') ? {message: {content: '!buildBlueprint("test-pad-3x3", 1, 64, 1)'}} : (jobs.push(url), {}))});
      const state = {bots: [{name: 'bot1', online: true, pos: [0, 64, 0], inventory: [], queue: [], job: null}], places: []};
      const go = () => decide(fm, new Map([['bot1', fm]]), async () => state, {take: () => true});
      await go();
      assert.strictEqual(jobs.filter((u) => u.endsWith('/api/job')).length, 1, 'the first build goes out');
      assert.strictEqual(fm.sent.size, 1);
      onEvent(new Map([['bot1', fm]]), {bot: 'bot1', kind: 'done', text: `finished: build at 1 64 1 ${bp.blocks.length} blocks false (12 s)`});
      assert.deepStrictEqual([...fm.done], ['built test-pad-3x3 at 1 64 1']);
      const sent = jobs.length;
      await go();
      assert.strictEqual(jobs.length, sent, 'no second build job');
      assert.match(fm.history.at(-1).content, /^Refused: already done \(built test-pad-3x3 at 1 64 1\)/);
    }
    let takes = 0; // queries only: every model call takes budget
    const {calls} = await run({replies: ['!stats'], budget: {take: () => (takes++, true)}});
    assert.strictEqual(calls.model, 5);
    assert.strictEqual(takes, calls.model, 'one budget token per model call, the first included');
  } finally {
    globalThis.fetch = realFetch;
  }
  console.log('ok decide');
})();
