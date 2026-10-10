'use strict';
// node tools/mcagents/agent.test.js — the Mindcraft command translator.
const assert = require('node:assert');
process.env.LOG ||= require('node:path').join(require('node:os').tmpdir(), `mcagents-test-${process.pid}.jsonl`); // decide() logs every model call
const {decide, Agent, parseCommand, translate, commandDocs, inventoryText, repeatHint, isRoutine, Budget, promptReason, assignJob, workersText} = require('./agent');

assert.deepStrictEqual(parseCommand('Sure! !collectBlocks("oak_log", 10)'), {name: 'collectBlocks', args: ['oak_log', 10]});
assert.deepStrictEqual(parseCommand("Bye! !endConversation('john')"), {name: 'endConversation', args: ['john']});
assert.deepStrictEqual(parseCommand('<think>maybe !stop</think>Let me look. !inventory'), {name: 'inventory', args: []}, 'thinking is ignored');
assert.strictEqual(parseCommand('hello there'), null);

const ctx = {pos: [1, 64, 2], supplyChest: {x: 5, y: 64, z: 5}, places: {base: {x: 9, y: 70, z: 9}}};
const tr = (s) => translate(parseCommand(s), ctx);
assert.deepStrictEqual(tr('!collectBlocks("oak_log", 10)'), {job: ['chop', {count: 10}]});
assert.deepStrictEqual(tr('!collectBlocks("cobblestone", 8)'), {job: ['mine', {block: 'stone', count: 8}]});
assert.deepStrictEqual(tr('!collectBlocks("iron_ore", 5)'), {job: ['mine', {block: 'iron_ore', count: 5}]});
assert.deepStrictEqual(tr('!putInChest("raw_iron", 5)'), {job: ['deposit', {x: 5, y: 64, z: 5, only: 'raw_iron'}]});
assert.deepStrictEqual(tr('!takeFromChest("coal", 3)'), {job: ['withdraw', {x: 5, y: 64, z: 5, item: 'coal', count: 3}]});
assert.deepStrictEqual(tr('!goToRememberedPlace("base")'), {job: ['goto', {x: 9, y: 70, z: 9}]});
assert.deepStrictEqual(tr('!craftRecipe("stick", 4)'), {job: ['craft', {item: 'stick', count: 4}]});
assert.deepStrictEqual(tr('!stop'), {job: ['stop', {}]});
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
    let takes = 0; // queries only: every model call after the first takes budget
    const {calls} = await run({replies: ['!stats'], budget: {take: () => (takes++, true)}});
    assert.strictEqual(calls.model, 5);
    assert.strictEqual(takes, calls.model - 1, 'one budget token per extra model call');
  } finally {
    globalThis.fetch = realFetch;
  }
  console.log('ok decide');
})();
