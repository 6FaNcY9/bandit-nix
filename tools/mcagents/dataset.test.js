#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {buildDataset, readEvents} = require('./dataset');
const {EventLog} = require('../../hosts/bandit-lab/services/mcbots/app/events');

const system = 'YOUR CURRENT ASSIGNED GOAL: "Build a base"\nSTATS\nPosition: x: 1, y: 64, z: 2\nBase chest: x: 5, y: 64, z: 5\nYour workers: bot2, bot3';
const user = (content) => ({role: 'user', content});
const assistant = (content) => ({role: 'assistant', content});
const row = (t, reply, extra = {}) => ({t, agent: 'bot1', messages: [{role: 'system', content: system}, user('SYSTEM: Idle')], reply, ...extra});
const event = (id, t, bot, text, kind = 'done') => ({id, t, bot, text, kind});
const label = (data, i = 0) => data.labels[i].label;
const goto = '!goToCoordinates(1, 64, 2)';

let out = buildDataset([row(100, goto), row(110, 'Hello'), row(120, '!newAction("evil")')], [event(1, 105, 'bot1', 'finished: goto 1 64 2 (1 s)')]);
assert.deepEqual(out.stats.labels, {good: 1, bad: 1, neutral: 1, unknown: 0});
assert.deepEqual(out.splits.train[0].messages.at(-1), assistant(goto));
assert.deepEqual(out.stats.commands.goToCoordinates, {good: 1, bad: 0, neutral: 0, unknown: 0});
assert.equal(out.stats.agents.bot1.good, 1);
assert.ok(!JSON.stringify(out.splits).includes('thinking'));
assert.equal(label(buildDataset([row(100, goto)], [event(1, 90, 'bot1', 'finished: goto 1 64 2')])), 'unknown', 'pre-dispatch events are stale');
assert.equal(label(buildDataset([row(100, goto)], [event(1, 110, 'bot2', 'finished: goto 1 64 2')])), 'unknown', 'wrong bot');
assert.equal(label(buildDataset([row(100, goto)], [event(1, 110, 'bot1', 'finished: goto 2 64 2')])), 'unknown', 'wrong job arguments');
assert.equal(label(buildDataset([row(100, goto)], [event(1, 110, 'bot1', 'stopped: goto 1 64 2', 'stop')])), 'unknown');
for (const status of ['failed', 'gave up']) assert.equal(label(buildDataset([row(100, goto)], [event(1, 110, 'bot1', `${status}: goto 1 64 2 - no path`, 'fail')])), 'bad');
out = buildDataset([row(100, goto), row(105, goto)], [event(1, 110, 'bot1', 'finished: goto 1 64 2')]);
assert.equal(out.stats.labels.unknown, 2, 'overlapping identical jobs are ambiguous');
assert.equal(out.stats.sft, 0);
const assign = '!assign("bot2", "!collectBlocks(\\\"cobblestone\\\", 32)")';
assert.equal(label(buildDataset([row(100, assign)], [event(1, 110, 'bot2', 'finished: mine stone 32 (2 s)')])), 'good', 'assigned worker, inner command');
assert.equal(label(buildDataset([row(100, '!assign("bot9", "!collectBlocks(\\\"stone\\\", 32)")')])), 'bad', 'worker allowlist');
assert.equal(label(buildDataset([row(100, '!assign("bot2", "!inventory")')])), 'bad', 'workers cannot receive queries');

const history = [user('SYSTEM: Idle'), assistant(goto), user('SYSTEM: Code output:\nfinished: goto 1 64 2 (1 s)')];
out = buildDataset([row(100, goto), row(200, 'Done', {messages: [{role: 'system', content: system}, ...history]}), row(300, goto, {messages: [{role: 'system', content: system}, ...history, assistant('Done'), user('SYSTEM: Idle')]})]);
assert.equal(label(out), 'good', 'subsequent direct result');
assert.equal(label(out, 2), 'unknown', 'copied history cannot label a later dispatch');
assert.ok(out.splits.train[0].messages.slice(0, -1).every((m) => m.role !== 'assistant'));
out = buildDataset([row(100, assign), row(200, 'Done', {messages: [{role: 'system', content: system}, user('SYSTEM: Idle'), assistant(assign), user('SYSTEM: Worker bot2: finished: mine stone 32 (2 s)')]})]);
assert.equal(label(out), 'good', 'worker result in prompt');
out = buildDataset([row(100, goto), row(200, 'Done', {messages: [{role: 'system', content: system}, user('SYSTEM: Idle'), assistant(goto), user('SYSTEM: Refused: do something different')]})]);
assert.equal(label(out), 'bad', 'explicit executor refusal');
out = buildDataset([row(100, '!inventory'), row(200, 'Done', {messages: [{role: 'system', content: system}, user('SYSTEM: Idle'), assistant('!inventory'), user('SYSTEM: INVENTORY\ncoal: 3')]})]);
assert.equal(label(out), 'good', 'query has immediate response');
out = buildDataset([row(100, goto), row(120, goto)], [event(1, 110, 'bot1', 'failed: goto 1 64 2 - no path', 'fail')]);
assert.equal(label(out, 1), 'bad', 'repeat after failure');
out = buildDataset([row(100, goto), row(105, goto)], [event(1, 110, 'bot1', 'failed: goto 1 64 2 - no path', 'fail')]);
assert.equal(label(out, 1), 'unknown', 'do not use a future failure for repeat detection');
out = buildDataset([row(100, goto), row(120, goto, {messages: [{role: 'system', content: system + '\nINVENTORY coal: 3'}, user('SYSTEM: Idle')]})], [event(1, 110, 'bot1', 'failed: goto 1 64 2 - no path', 'fail')]);
assert.equal(label(out, 1), 'unknown', 'material state change permits retry');

for (const extra of [{password: 'hidden'}, {thinking: 'Bearer abcdef'}, {reply: 'api_key="hidden"'}, {messages: [{role: 'system', content: system}, user('SYSTEM: sk-abcdefghijkl')]}]) {
  const data = buildDataset([row(100, goto, extra)]);
  assert.equal(data.stats.dropped.secrets, 1);
  assert.equal(data.labels.length, 0, 'secret rows dropped, not redacted into training');
}
for (const content of ['Steve: private chat', 'SYSTEM: (FROM PLAYER) hi', 'SYSTEM: https://private.test/']) assert.equal(buildDataset([row(100, goto, {messages: [{role: 'system', content: system}, user(content)]})]).stats.dropped.privacy, 1);
assert.equal(buildDataset([row(100, goto), row(100, goto)]).stats.dropped.raw_duplicate, 1);
assert.equal(buildDataset([{}]).stats.dropped.invalid, 1);
const hostile = buildDataset([row(100, '!__proto__', {agent: '__proto__'})]);
assert.equal(hostile.stats.commands.__proto__.bad, 1);
assert.equal(hostile.stats.agents.__proto__.bad, 1);
assert.equal(Object.prototype.bad, undefined, 'untrusted names cannot pollute prototypes');
assert.throws(() => buildDataset([], [], {cap: 0}));

const unique = 'abcdefghij'.split('').map((letter, i) => row(i * 100 + 100, `!goToCoordinates(${i}, 64, 2)`, {episode_id: letter, messages: [{role: 'system', content: system.replace('Build a base', `Task ${letter}`)}, user('SYSTEM: Idle')]}));
const successes = unique.map((r, i) => event(i + 1, r.t + 10, 'bot1', `finished: goto ${i} 64 2`));
out = buildDataset(unique, successes);
assert.deepEqual(out.stats.splits, {train: 8, val: 1, test: 1});
assert.deepEqual(buildDataset(unique.slice().reverse(), successes).splits, out.splits, 'deterministic chronological splits');
const near = row(1200, '!goToCoordinates(30, 64, 2)', {episode_id: 'near', messages: unique[0].messages});
out = buildDataset([...unique, near], [...successes, event(11, 1210, 'bot1', 'finished: goto 30 64 2')]);
assert.equal(out.stats.dropped.near_duplicate, 1);
assert.equal(out.stats.split_groups, 10, 'near prompt connects whole episodes');
// A duplicate in the last episode moves its other distinct prompt into the same split.
const bridge = row(1150, '!goToCoordinates(31, 64, 2)', {episode_id: 'j', messages: unique[0].messages});
out = buildDataset([...unique, bridge], [...successes, event(12, 1160, 'bot1', 'finished: goto 31 64 2')]);
assert.equal(out.labels.find((r) => r.episode_id === 'a').split, out.labels.find((r) => r.episode_id === 'j' && r.split).split);
const byEpisode = new Map();
for (const r of out.labels.filter((r) => r.split)) { if (byEpisode.has(r.episode_id)) assert.equal(byEpisode.get(r.episode_id), r.split); byEpisode.set(r.episode_id, r.split); }
const diverse = 'abcde'.split('').map((letter, i) => row(i * 100 + 100, `!goToCoordinates(${i}, 64, 2)`, {messages: [{role: 'system', content: system}, user(`SYSTEM: Idle ${letter}`)]}));
out = buildDataset(diverse, successes.slice(0, 5), {cap: 2});
assert.equal(out.stats.sft, 2);
assert.equal(out.stats.dropped.situation_cap, 3);
assert.equal(buildDataset([row(100, '!startShift("logs")')]).stats.labels.unknown, 1, 'no invented routine finish');

// Logged outcome records (agent.js) label decisions by id and beat event joins; events stay the fallback.
const outcome = (id, result, reason, ms = 5000) => ({kind: 'outcome', t: 105, id, agent: 'bot1', result, reason, ms});
const logged = [row(100, goto, {id: 'a1'}), row(200, '!inventory', {id: 'a2'}), row(300, 'Hello', {id: 'a3'}), row(400, goto, {id: 'a4'}), row(500, goto, {id: 'a5'}), row(600, goto)];
out = buildDataset([...logged, outcome('a1', 'good', 'finished'), outcome('a2', 'bad', 'refused'), outcome('a4', 'neutral', 'no result in 15 min'), outcome('a5', 'bad', 'failed: no path'), outcome('a1', 'bad', 'second one ignored'), outcome('zz', 'good', 'orphan'), {kind: 'outcome', id: 'a3', result: 'great'}],
  [event(1, 450, 'bot1', 'failed: goto 1 64 2 - no path', 'fail'), event(2, 650, 'bot1', 'finished: goto 1 64 2 (1 s)')]);
assert.deepEqual(out.labels.map((l) => [l.label, l.reason, l.label_source]),
  [['good', 'finished', 'outcome'], ['bad', 'refused', 'outcome'], ['neutral', 'no command', 'inferred'], ['neutral', 'no result in 15 min', 'outcome'], ['bad', 'failed: no path', 'outcome'], ['good', 'finished', 'inferred']]);
assert.deepEqual(out.labels.map((l) => l.decision_id), ['a1', 'a2', 'a3', 'a4', 'a5', null]);
assert.deepEqual(out.stats.outcomes, {records: 5, labelled: 4});
assert.equal(out.stats.dropped.invalid_outcome, 1, 'bad result value');
assert.equal(out.stats.input, 13, 'outcome lines are not decisions and are never invalid rows');
assert.equal(out.stats.dropped.invalid, undefined);
// a logged good beats a later event failure; a logged outcome is not overridden by the repeat rule
out = buildDataset([row(100, goto, {id: 'b1'}), row(120, goto, {id: 'b2'}), outcome('b1', 'bad', 'failed: no path', 10), outcome('b2', 'good', 'finished')]);
assert.deepEqual(out.labels.map((l) => l.label), ['bad', 'good'], 'repeat rule leaves logged outcomes alone');
out = buildDataset([row(100, goto, {id: 'c1'}), row(120, goto, {id: 'c2'}), outcome('c1', 'bad', 'failed: no path', 10)]);
assert.equal(out.labels[1].reason, 'repeated failed command', 'a logged failure still feeds the repeat rule for unlabeled repeats');
out = buildDataset([row(100, goto, {id: 'd1'}), outcome('d1', 'good', 'Bearer abcdef123456')]);
assert.ok(!JSON.stringify(out.labels).includes('abcdef123456'), 'outcome reasons are sanitized');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dataset-test-'));
try {
  const log = new EventLog({now: () => 110});
  log.add('bot1', 'done', 'finished: goto 1 64 2');
  const input = path.join(dir, 'decisions.jsonl'), events = path.join(dir, 'events.json'), output = path.join(dir, 'out');
  fs.writeFileSync(input, JSON.stringify(row(100, goto)) + '\n');
  fs.writeFileSync(events, JSON.stringify({events: log.since(0), lastId: log.lastId}));
  assert.equal(readEvents(events).length, 1, 'real EventLog fixture dump');
  const cli = (...args) => spawnSync(process.execPath, [path.join(__dirname, 'dataset.js'), ...args], {encoding: 'utf8'});
  let result = cli(input, '--events', events, '--out', output);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).sft, 1);
  assert.equal(JSON.parse(fs.readFileSync(path.join(output, 'train.jsonl'))).messages.at(-1).content, goto);
  assert.equal(fs.statSync(output).mode & 0o777, 0o700);
  assert.equal(fs.statSync(path.join(output, 'labels.jsonl')).mode & 0o777, 0o600);
  assert.equal(cli(input, '--out', output).status, 1, 'never overwrite');
  assert.equal(cli(input, '--out', path.join(dir, 'badcap'), '--cap', 'NaN').status, 1);
  fs.writeFileSync(input, '{bad json');
  assert.equal(cli(input, '--out', path.join(dir, 'badjson')).status, 1);
  fs.writeFileSync(events, [JSON.stringify({server_session: 'one', event: log.items[0]}), JSON.stringify({server_session: 'one', event: log.items[0]})].join('\n'));
  assert.equal(readEvents(events).length, 1, 'overlapping event dumps deduped');
  fs.writeFileSync(events, JSON.stringify([log.items[0], {...log.items[0], text: 'changed'}]));
  assert.throws(() => readEvents(events), /Conflicting event IDs/);
  assert.throws(() => buildDataset([], [{id: 1, t: 'bad', bot: 'bot1', text: 'finished: goto 1 64 2'}]));
} finally { fs.rmSync(dir, {recursive: true, force: true}); }
console.log('dataset tests passed');
