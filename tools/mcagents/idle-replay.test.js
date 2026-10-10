'use strict';
const assert = require('node:assert/strict');
const http = require('node:http');
const {backendBase, sample, score, runBackend, withVariant} = require('./idle-replay');

(async () => {
  for (const bad of ['http://127.0.0.1:11434', 'http://localhost:11434/v1', 'http://10.0.0.5:18081', 'https://127.0.0.1:18081', 'http://127.0.0.1']) assert.throws(() => backendBase(bad), /Refusing/, bad);
  assert.equal(backendBase('http://127.0.0.1:18081/x'), 'http://127.0.0.1:18081');

  const d = (id, reply = '!stop') => ({id, messages: [{role: 'system', content: 'S'}, {role: 'user', content: id}], reply});
  const picked = sample([d('a'), d('b'), d('c'), d('d'), d('a')], [{id: 'a', result: 'good'}, {id: 'c', result: 'bad'}, {id: 'b', result: 'neutral'}], 3);
  assert.deepEqual(picked.map((r) => r.id), ['c', 'a', 'd'], 'labeled good/bad first, newest first, deduped');
  assert.equal(withVariant(picked[0].messages, {name: 'v', system_append: '+X'})[0].content, 'S+X');

  const r = (variant, label, logged, reply, ms, error) => ({variant, label, logged, reply, ms, error});
  const s = score([r('v', 'good', '!stop', '!stop', 100), r('v', 'good', '!stop', '!inventory', 300), r('v', 'bad', '!stop', '!stop', 200), r('v', 'bad', '!stop', 'hello', 400), r('v', null, '', '', 0, 'x'), r('w', 'good', '!stop', '!stop', 1)], 'v');
  assert.equal(s.n, 5); assert.equal(s.errors, 1);
  assert.equal(s.valid_command_rate, 0.75); assert.equal(s.agree_good, 0.5); assert.equal(s.disagree_bad, 0.5);
  assert.equal(s.mean_ms, 250); assert.equal(s.p95_ms, 400);

  // fake server: healthy, answers 2 requests, then dies like llama-server killed by the watcher
  let served = 0;
  const server = http.createServer((req, res) => {
    if (req.url === '/health') { res.statusCode = served >= 2 ? 503 : 200; return res.end('{}'); }
    req.resume(); req.on('end', () => { served++; res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({model: 'fake-alias', choices: [{message: {content: '!stop'}, finish_reason: 'stop'}]})); });
  });
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
  const base = `http://127.0.0.1:${server.address().port}`;
  const rows = ['a', 'b', 'c'].map((id) => ({...d(id), label: null}));
  const run = await runBackend(base, rows, [{name: 'baseline'}]);
  assert.equal(run.results.length, 2, 'partial results kept');
  assert.equal(run.alias, 'fake-alias'); assert.match(run.stopped, /health lost/);
  server.close();
  const gone = await runBackend(base, rows, [{name: 'baseline'}]);
  assert.equal(gone.results.length, 0); assert.match(gone.stopped, /not free/);
  console.log('idle-replay tests passed');
})().catch((e) => { console.error(e); process.exitCode = 1; });
