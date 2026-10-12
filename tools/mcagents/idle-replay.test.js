'use strict';
const assert = require('node:assert/strict');
const http = require('node:http');
const {backendBase, sample, score, scoreAll, wilson, samplingFor, runBackend, withVariant} = require('./idle-replay');

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

  const [lo, hi] = wilson(50, 100);
  assert.ok(Math.abs(lo - .4038) < .001 && Math.abs(hi - .5962) < .001, 'Wilson 50/100'); assert.equal(wilson(0, 0), null);
  assert.deepEqual(wilson(10, 10).map((x) => +x.toFixed(3)), [.722, 1]);
  assert.equal(s.agree_good_ci.length, 2); assert.ok(s.score === 0.5);
  const g = samplingFor({});
  assert.equal(g.temperature, 0); assert.equal(g.top_k, 1); assert.equal(g.seed, 11);
  assert.equal(samplingFor({seed: 2}).seed, 2); assert.equal(samplingFor({seed: 2}).temperature, 0.6);
  const all = scoreAll([{...r('v', 'good', '!stop', '!stop', 1), run: 'greedy'}, {...r('v', 'good', '!stop', '!stop', 1), run: 'seed1'}, {...r('v', 'good', '!stop', '!inventory', 1), run: 'seed2'}], ['v'], [1, 2]);
  assert.deepEqual(all.map((x) => x.run), ['greedy', 'sampled']); assert.equal(all[1].agree_good, 0.5);

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
  assert.equal(run.results[0].run, 'greedy');
  assert.equal(run.results.length, 2, 'partial results kept');
  assert.equal(run.alias, 'fake-alias'); assert.match(run.stopped, /health lost/);
  server.close();
  const gone = await runBackend(base, rows, [{name: 'baseline'}]);
  assert.equal(gone.results.length, 0); assert.match(gone.stopped, /not free/);
  // while people play Minecraft (BUSY_FILE exists) a free PC is left alone, before any request
  const busy = require('node:path').join(require('node:os').tmpdir(), `busy-${process.pid}`);
  require('node:fs').writeFileSync(busy, 'fancy8869\n');
  process.env.BUSY_FILE = busy;
  const up = http.createServer((req, res) => { res.statusCode = 200; res.end('{}'); });
  await new Promise((ok) => up.listen(0, '127.0.0.1', ok));
  const played = await runBackend(`http://127.0.0.1:${up.address().port}`, rows, [{name: 'baseline'}]);
  assert.equal(played.results.length, 0); assert.match(played.stopped, /people are playing/);
  require('node:fs').unlinkSync(busy); delete process.env.BUSY_FILE; up.close();
  // a /health that redirects (to Ollama, say) counts as not free, and is never followed (Codex R7-6)
  let followed = false;
  const target = http.createServer((req, res) => { followed = true; res.end('{}'); });
  await new Promise((ok) => target.listen(0, '127.0.0.1', ok));
  const redir = http.createServer((req, res) => { res.statusCode = 302; res.setHeader('Location', `http://127.0.0.1:${target.address().port}/`); res.end(); });
  await new Promise((ok) => redir.listen(0, '127.0.0.1', ok));
  const red = await runBackend(`http://127.0.0.1:${redir.address().port}`, rows, [{name: 'baseline'}]);
  assert.equal(red.results.length, 0); assert.match(red.stopped, /not free/); assert.equal(followed, false);
  redir.close(); target.close();
  console.log('idle-replay tests passed');
})().catch((e) => { console.error(e); process.exitCode = 1; });
