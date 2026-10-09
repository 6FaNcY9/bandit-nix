'use strict';
// node tools/mcbots-mcp/server.test.js — the MCP server over real stdio against a fake dashboard API.
const assert = require('node:assert');
const http = require('node:http');
const {spawn} = require('node:child_process');
const path = require('node:path');

const posted = [];
const fake = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    res.setHeader('Content-Type', 'application/json');
    if (req.method === 'GET' && req.url === '/api/state') {
      return res.end(JSON.stringify({bots: [{name: 'bot1', online: true, pos: [1, 64, 2], health: 20, food: 20, activity: 'idle', job: null, queue: [], inventory: ['cobblestone x9']}], supplyChest: {x: 5, y: 64, z: 5}, places: [], world: {players: []}}));
    }
    if (req.method === 'POST' && req.url === '/api/job') {
      assert.ok(req.headers.origin, 'POSTs carry an Origin');
      const job = JSON.parse(body);
      if (job.type === 'mine' && job.args.block === 'Bad Block') {
        res.statusCode = 400;
        return res.end(JSON.stringify({error: 'bot1: block must be a block name like iron_ore'}));
      }
      posted.push(job);
      return res.end(JSON.stringify({ok: true}));
    }
    res.statusCode = 404;
    res.end('{}');
  });
});

fake.listen(0, '127.0.0.1', async () => {
  const api = `http://127.0.0.1:${fake.address().port}`;
  const child = spawn(process.execPath, [path.join(__dirname, 'server.js')], {env: {...process.env, MCBOTS_API: api}});
  const waiting = new Map();
  let buf = '';
  child.stdout.on('data', (d) => {
    buf += d;
    for (let i; (i = buf.indexOf('\n')) >= 0;) {
      const msg = JSON.parse(buf.slice(0, i));
      buf = buf.slice(i + 1);
      waiting.get(msg.id)?.(msg);
    }
  });
  let n = 0;
  const rpc = (method, params) => new Promise((resolve) => {
    const id = ++n;
    waiting.set(id, resolve);
    child.stdin.write(JSON.stringify({jsonrpc: '2.0', id, method, params}) + '\n');
  });
  const call = async (name, args) => (await rpc('tools/call', {name, arguments: args})).result;
  try {
    const init = await rpc('initialize', {protocolVersion: '2025-06-18', capabilities: {}, clientInfo: {name: 't', version: '1'}});
    assert.strictEqual(init.result.serverInfo.name, 'mcbots');
    assert.ok(init.result.capabilities.tools);
    child.stdin.write(JSON.stringify({jsonrpc: '2.0', method: 'notifications/initialized'}) + '\n'); // no reply expected

    const names = (await rpc('tools/list', {})).result.tools.map((t) => t.name);
    for (const t of ['mc_state', 'mc_mine', 'mc_build', 'mc_stop']) assert.ok(names.includes(t), t);
    assert.ok(!names.some((t) => /say|chat/.test(t)), 'no chat tool');

    const st = JSON.parse((await call('mc_state', {})).content[0].text);
    assert.deepStrictEqual(st.bots[0].inventory, ['cobblestone x9']);
    assert.deepStrictEqual(st.supplyChest, {x: 5, y: 64, z: 5});

    await call('mc_mine', {bot: 'bot1', block: 'iron_ore', count: 8});
    assert.deepStrictEqual(posted.at(-1), {bots: ['bot1'], type: 'mine', args: {block: 'iron_ore', count: 8}, replace: false});

    await call('mc_build', {bot: 'bot1', blueprint: 'test-pad-3x3', x: -121, y: 77, z: 9});
    assert.strictEqual(posted.at(-1).type, 'build');
    assert.deepStrictEqual(posted.at(-1).args.origin, {x: -121, y: 77, z: 9});
    assert.strictEqual(posted.at(-1).args.blocks.length, 9);

    await call('mc_stop', {bot: 'all'});
    assert.deepStrictEqual(posted.at(-1), {bots: 'all', type: 'stop', args: {}, replace: true});

    const bad = await call('mc_mine', {bot: 'bot1', block: 'Bad Block', count: 1});
    assert.ok(bad.isError && /block name/.test(bad.content[0].text), 'API refusals come back as tool errors');
    assert.ok((await call('mc_mine', {bot: 'bot1'})).isError, 'missing arguments are refused');
    assert.ok((await call('mc_build', {bot: 'bot1', blueprint: '../../etc/passwd', x: 0, y: 64, z: 0})).isError, 'no path escape');
    assert.strictEqual((await rpc('nope/method', {})).error.code, -32601);
    console.log('ok');
  } finally {
    child.kill();
    fake.close();
  }
});
