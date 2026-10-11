'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {buildEval, writeEval, loadEval, excludedContexts, ctxKey} = require('./eval-set');
const {exportSft} = require('./export-sft');
const {table} = require('./compare');

const sys = (n) => ({role: 'system', content: `You are bot1. YOUR CURRENT ASSIGNED GOAL: "g${n}"`});
const recs = [];
let t = 0;
const add = (id, cmd, result, kind) => {
  const messages = [sys(id), {role: 'user', content: `SYSTEM: situation ${id}`}];
  recs.push({id, agent: 'bot1', t: new Date(Date.UTC(2026, 9, 1, 0, 0, t++)).toISOString(), episode_id: `e${id}`, messages, reply: cmd, ...(kind ? {kind} : {})});
  recs.push({kind: 'outcome', id, result, reason: 'x', ms: 1});
};
for (let i = 0; i < 60; i++) add(`g${i}`, i % 3 ? '!stop' : '!inventory', 'good');
for (let i = 0; i < 40; i++) add(`b${i}`, '!stop', 'bad');
add('dup', '!stop', 'good'); recs.push({...recs[0], id: 'dup2'}, {kind: 'outcome', id: 'dup2', result: 'good', ms: 1}); // same situation as g0

const rows = buildEval(recs, 25);
assert.equal(rows.filter((r) => r.label === 'good').length, 25);
assert.equal(rows.filter((r) => r.label === 'bad').length, 25);
assert.equal(new Set(rows.map((r) => r.ctx)).size, rows.length, 'deduped by situation');
const goodCmds = new Set(rows.filter((r) => r.label === 'good').map((r) => r.command));
assert.deepEqual([...goodCmds].sort(), ['inventory', 'stop'], 'stratified: both commands present');
assert.ok(rows.filter((r) => r.label === 'good' && r.command === 'inventory').length >= 12, 'round robin keeps the rare command');
assert.ok(!rows.some((r) => r.id === 'dup2'));

// disjoint from the export
const dir = fs.mkdtempSync(path.join(process.env.TMPDIR || os.tmpdir(), 'eval-'));
const m = writeEval(dir, 'v1', rows);
assert.equal(m.n, 50); assert.equal(m.ids.length, 50);
assert.equal(writeEval(dir, 'v1', []), null, 'a version is never rebuilt');
assert.equal(loadEval(dir, 'v1').length, 50); assert.equal(loadEval(dir, 'v2'), null);
const exclude = excludedContexts(dir);
assert.equal(exclude.size, 50);
const full = exportSft(recs, {exclude: new Set()});
const cut = exportSft(recs, {exclude});
assert.ok(full.rows.length > cut.rows.length);
assert.equal(cut.stats.eval_excluded, full.stats.decision_rows - cut.stats.decision_rows);
for (const r of cut.rows) assert.ok(!exclude.has(ctxKey(r.messages)), 'no training row shares a context with the eval set');
assert.ok(full.rows.some((r) => exclude.has(ctxKey(r.messages))), 'the check is not vacuous');

// compare: latest run per alias, best first, with intervals
const v = (run, ag, db) => ({variant: 'baseline', run, n: 300, agree_good: ag, agree_good_ci: [ag - .05, ag + .05], disagree_bad: db, disagree_bad_ci: [db - .05, db + .05], valid_command_rate: 1, valid_ci: [.98, 1], score: (ag + db) / 2, p95_ms: 900});
const out = table([
  {t: '2026-10-01T00:00:00Z', eval: 'v1', alias: 'andy-old', variants: [v('greedy', .3, .5)]},
  {t: '2026-10-02T00:00:00Z', eval: 'v1', alias: 'andy-old', variants: [v('greedy', .5, .6)]},
  {t: '2026-10-02T00:00:00Z', eval: 'v1', alias: 'andy-lora', stopped: 'deadline', variants: [v('greedy', .6, .7), v('sampled', .5, .6)]},
  {t: '2026-10-03T00:00:00Z', eval: null, alias: 'other', variants: [v('greedy', 1, 1)]},
]);
const lines = out.split('\n');
assert.match(lines[1], /^andy-lora\s+greedy\s+300\*\s+100% \[98-100\]\s+60% \[55-65\]/);
assert.match(lines[2], /^andy-old\s+greedy\s+300\s+100% \[98-100\]\s+50% /, 'latest run per alias');
assert.match(lines[3], /^andy-lora\s+sampled/); assert.ok(!out.includes('other'));
console.log('eval-set tests passed');
