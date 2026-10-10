'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const {spawn} = require('node:child_process');
const {sanitize, exportRows, run, score, compare} = require('./replay');
const {SAMPLING} = require('./agent');

async function cli(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [path.join(__dirname, 'replay.js'), ...args]);
    let stdout = '', stderr = '';
    child.stdout.on('data', (s) => { stdout += s; });
    child.stderr.on('data', (s) => { stderr += s; });
    child.on('error', reject);
    child.on('close', (code) => resolve({code, stdout, stderr}));
  });
}
async function main() {
  const fixture = path.join(__dirname, 'fixtures/decisions.jsonl');
  const records = fs.readFileSync(fixture, 'utf8').trim().split('\n').map(JSON.parse);
  const {rows, skipped} = exportRows(records);
  assert.equal(rows.length, 2);
  assert.equal(skipped, 1, 'dashboard decision bodies lack prompts');
  assert.deepEqual(exportRows(records).rows, rows, 'stable ids and deduplication');
  const serialized = JSON.stringify(rows);
  for (const secret of ['fake-dashboard-token', 'sk-fake12345678', 'fixture-secret', 'discard-me', 'Authorization']) assert.ok(!serialized.includes(secret), secret);
  assert.equal(rows[0].goal, 'Gather logs');
  assert.deepEqual(rows[0].state.pos, [1, 64, 2]);
  assert.deepEqual(rows[0].state.supplyChest, {x: 5, y: 64, z: 5});
  assert.deepEqual(rows[0].prior[0].command, {name: 'stop', args: []});
  assert.deepEqual(rows[0].expected, {}, 'human constraints are not invented');
  assert.deepEqual(sanitize({apiToken: 'hidden', password: 'hidden', nested: {Authorization: 'hidden', safe: 'yes'}}), {nested: {safe: 'yes'}});
  for (const text of ['Bearer abcDEF123', 'Basic YWJjOmRlZg==', 'sk-abcdefghijk', 'ghp_abcdefghijk', 'eyJabc.def.ghi', 'password="hidden value"', 'Cookie: session=hidden', 'https://example.test/?access_token=hidden']) assert.ok(!sanitize(text).includes('hidden') && sanitize(text).includes('[REDACTED]'));
  assert.equal(sanitize('-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----'), '[REDACTED]');
  const requests = [];
  const server = http.createServer(async (req, res) => {
    let text = '';
    for await (const chunk of req) text += chunk;
    const body = JSON.parse(text);
    requests.push({url: req.url, body});
    if (body.model === 'http-error') { res.writeHead(503); res.end('unavailable'); return; }
    if (body.model === 'bad-json') { res.end('{'); return; }
    res.setHeader('Content-Type', 'application/json');
    const reply = body.messages[0].content.startsWith('YOUR') ? '<think>!inventory</think>!stop' : '\t';
    res.end(JSON.stringify(req.url === '/api/chat'
      ? {message: {content: reply}, prompt_eval_count: 12, eval_count: 3, done_reason: body.model === 'truncated' ? 'length' : 'stop'}
      : {choices: [{message: {content: reply}, finish_reason: body.model === 'truncated' ? 'length' : 'stop'}], usage: {prompt_tokens: 12, completion_tokens: 3, total_tokens: 15}}));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const endpoint = `http://127.0.0.1:${server.address().port}`;
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mcagents-replay-'));
  try {
    const a = await run(rows, {endpoint, api: 'ollama', model: 'fake', seed: 11});
    const b = await run(rows, {endpoint: `${endpoint}/v1`, api: 'openai', model: 'fake', seed: 11});
    assert.equal(requests.length, 4);
    assert.deepEqual(requests.map((r) => r.url), ['/api/chat', '/api/chat', '/v1/chat/completions', '/v1/chat/completions']);
    assert.deepEqual(requests[0].body.options, {...SAMPLING, num_predict: 512, seed: 11});
    assert.equal(requests[0].body.think, false);
    assert.equal(requests[0].body.stream, false);
    for (const [key, value] of Object.entries(SAMPLING)) if (key !== 'num_ctx') assert.equal(requests[2].body[key], value);
    assert.equal(requests[2].body.max_tokens, 512);
    assert.equal(requests[2].body.seed, 11);
    assert.deepEqual(requests[2].body.chat_template_kwargs, {enable_thinking: false});
    assert.deepEqual(requests[0].body.messages, requests[2].body.messages);
    assert.equal(a[0].reply, '<think>!inventory</think>!stop', 'raw reply is retained');
    assert.deepEqual(a[0].tokens, {prompt: 12, completion: 3});
    assert.equal(b[0].tokens.total_tokens, 15);
    assert.ok(a.every((r) => Number.isFinite(r.ms) && r.ms >= 0));
    const samples = [
      {...rows[0], reply: '<think>!inventory</think>!stop', ms: 10},
      {...rows[1], reply: '!inventory', ms: 20},
      {...rows[0], reply: '!newAction("evil")', ms: 30},
      {...rows[0], reply: '\t', ms: 40},
      {...rows[0], reply: '!stop', error: 'timeout', ms: 50},
    ];
    assert.deepEqual(score(samples), {calls: 5, valid_command_rate: .4, refusal_no_command_rate: .6, repeat_loop_rate: .6, stop_rate: .4, median_ms: 30, p95_ms: 50});
    assert.equal(score([{reply: '!putInChest("coal", 2)', ms: 1, state: {}}]).valid_command_rate, 0, 'missing precondition is refused');
    assert.equal(score([{reply: '!digRoom(1, 2, 3, 50, 1, 1)', ms: 1}]).valid_command_rate, 0);
    assert.equal(score([]).median_ms, null);
    assert.equal(score([{reply: '!stop', ms: 10}, {reply: '!stop', ms: 20}]).median_ms, 15);
    const other = b.map((r) => ({...r, reply: '!newAction("evil")', ms: 5})).reverse();
    const comparison = compare(a.map((r) => ({...r, ms: 10})), other);
    assert.equal(comparison.difference_B_minus_A.valid_command_rate, -.5);
    assert.equal(comparison.paired[0].valid, -1);
    assert.equal(comparison.paired[0].ms, -5);
    assert.throws(() => compare(a, b.slice(1)), /matching/);
    assert.throws(() => compare(a, b.map((r) => ({...r, seed: 22}))), /same frozen/);
    assert.throws(() => compare(a, b.map((r) => ({...r, messages: []}))), /same frozen/);
    assert.throws(() => compare(a, [b[0], b[0]]), /unique/);
    for (const api of ['ollama', 'openai']) {
      const failure = await run(rows, {endpoint, api, model: 'http-error', seed: 11});
      assert.equal(failure.length, rows.length);
      assert.equal(failure[0].error, 'HTTP 503');
      assert.equal(score(failure).valid_command_rate, 0);
      const truncated = await run(rows, {endpoint, api, model: 'truncated', seed: 11});
      assert.equal(score(truncated).valid_command_rate, 0);
    }
    assert.ok((await run(rows, {endpoint, api: 'ollama', model: 'bad-json', seed: 11}))[0].error);
    await assert.rejects(run(rows, {endpoint, api: 'wrong', model: 'fake', seed: 11}), /Require/);
    const exported = await cli(['export', fixture]);
    assert.equal(exported.code, 0, exported.stderr);
    assert.deepEqual(exported.stdout.trim().split('\n').map(JSON.parse), rows);
    assert.match(exported.stderr, /Skipped 1/);
    const replay = path.join(dir, 'replay.jsonl');
    fs.writeFileSync(replay, exported.stdout);
    const ran = await cli(['run', replay, '--endpoint', endpoint, '--api', 'openai', '--model', 'fake', '--seed', '11']);
    assert.equal(ran.code, 0, ran.stderr);
    const output = path.join(dir, 'run.jsonl');
    fs.writeFileSync(output, ran.stdout);
    const scored = await cli(['score', output]);
    assert.equal(scored.code, 0, scored.stderr);
    assert.equal(JSON.parse(scored.stdout).valid_command_rate, .5);
    const compared = await cli(['compare', output, output]);
    assert.equal(compared.code, 0, compared.stderr);
    assert.equal(JSON.parse(compared.stdout).difference_B_minus_A.median_ms, 0);
    assert.equal((await cli(['run', replay, '--endpoint', endpoint, '--api', 'ollama', '--model', 'fake'])).code, 1);
    fs.writeFileSync(replay, 'broken-json\n');
    assert.equal((await cli(['export', replay])).code, 1);
    assert.ok(requests.every((r) => ['/api/chat', '/v1/chat/completions'].includes(r.url)), 'no dashboard/job calls');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(dir, {recursive: true, force: true});
  }
  console.log('replay tests passed');
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
