#!/usr/bin/env node
// stdio <-> HTTPS bridge to the shared memory (svc:memory on bandit-lab).
// Termux cannot resolve tailnet names, so this dials the service's tailnet
// address and only names the host for TLS.
// shortcut: forwards requests and their replies only (no server-initiated
// messages); enough for tool calls. Drop it once Termux resolves *.ts.net.
const https = require('https');
const HOST = 'memory.tail7facc9.ts.net', ADDR = process.env.MEMORY_ADDR || '100.103.202.198';
let session, initLine, queue = Promise.resolve();

const post = (line, quiet = false) => new Promise((resolve) => {
  // Only initialize opens a session: Claude first sends a discovery probe the server rejects.
  const init = /"method"\s*:\s*"initialize"/.test(line);
  if (init) initLine = line;
  const headers = {'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', Host: HOST};
  if (session && !init) headers["mcp-session-id"] = session;
  const fail = (msg) => {
    let id = null;
    try { id = JSON.parse(line).id ?? null; } catch {}
    if (id !== null) process.stdout.write(JSON.stringify({jsonrpc: '2.0', id, error: {code: -32000, message: msg}}) + '\n');
    resolve();
  };
  const req = https.request({host: ADDR, servername: HOST, path: '/mcp', method: 'POST', headers}, (res) => {
    if (init && res.headers["mcp-session-id"]) session = res.headers["mcp-session-id"];
    let body = '';
    res.setEncoding('utf8').on('data', (c) => (body += c)).on('end', () => {
      // Server restarted and forgot our session: log in again with the saved initialize, then retry once.
      if (res.statusCode === 404 && !init && !quiet && initLine && body.includes('Session not found')) {
        session = undefined;
        return post(initLine, true)
          .then(() => post('{"jsonrpc":"2.0","method":"notifications/initialized"}', true))
          .then(() => post(line, true)).then(resolve);
      }
      if (quiet && init) return resolve();  // replayed initialize: its reply must not reach Claude
      if (res.statusCode >= 400) return fail(`memory server: HTTP ${res.statusCode} ${body.slice(0, 200)}`);
      const sse = String(res.headers['content-type']).includes('text/event-stream');
      const msgs = sse ? body.split(/\r?\n/).filter((l) => l.startsWith('data:')).map((l) => l.slice(5).trim()) : [body.trim()];
      for (const m of msgs) if (m) process.stdout.write(m + '\n');
      resolve();
    });
  });
  req.on('error', (e) => fail(`memory server unreachable (Tailscale on?): ${e.message}`));
  req.end(line);
});

require('readline').createInterface({input: process.stdin}).on('line', (line) => {
  if (line.trim()) queue = queue.then(() => post(line));
});
