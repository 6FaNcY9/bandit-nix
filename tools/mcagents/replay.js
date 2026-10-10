#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const {createHash} = require('node:crypto');
const {parseArgs} = require('node:util');
const {performance} = require('node:perf_hooks');
const {parseCommand, translate, SAMPLING} = require('./agent');
const {modelRequest, modelReply} = require('./model-protocol');

// Drop credential fields and redact credential-shaped text, including inside prompts.
const SECRET_KEY = /authorization|cookie|token|password|passwd|secret|api[_-]?key|credential|private[_-]?key/i;
function sanitize(value) {
  if (typeof value === 'string') return value
    .replace(/-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?-----END [^-]*PRIVATE KEY-----/g, '[REDACTED]')
    .replace(/\b(?:Bearer|Basic)\s+[A-Za-z0-9+/_=.:-]+/gi, '[REDACTED]')
    .replace(/\b(?:authorization|cookie|set-cookie)\s*:[^\r\n]*/gi, '[REDACTED]')
    .replace(/\b(?:[\w-]*(?:token|password|passwd|secret|api[_-]?key|credential)[\w-]*)["']?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;}]+)/gi, '[REDACTED]')
    .replace(/\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b/g, '[REDACTED]');
  if (Array.isArray(value)) return value.map(sanitize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value)
    .filter(([key]) => !SECRET_KEY.test(key)).map(([key, v]) => [key, sanitize(v)]));
  return value;
}

function readLines(file) {
  return fs.readFileSync(file, 'utf8').split('\n').filter((s) => s.trim()).map((s, i) => {
    try { return JSON.parse(s); } catch { throw new Error(`${file}: invalid JSON at row ${i + 1}`); }
  });
}
function checkRows(rows) {
  const ids = new Set();
  for (const row of rows) {
    if (!row || typeof row.id !== 'string' || !row.id || ids.has(row.id) || typeof row.episode_id !== 'string') throw new Error('Missing or duplicate row id/episode_id');
    ids.add(row.id);
    if (!Array.isArray(row.messages) || !row.messages.length || row.messages.some((m) => !['system', 'user', 'assistant'].includes(m.role) || typeof m.content !== 'string')) throw new Error(`Invalid messages for ${row.id}`);
  }
}
function exportRows(records) {
  const seen = new Set();
  const rows = [];
  let skipped = 0;
  for (const record of records) {
    if (!Array.isArray(record.messages) || !record.messages.length) { skipped++; continue; }
    const r = sanitize(record);
    const messages = r.messages.map(({role, content}) => ({role, content}));
    const key = JSON.stringify(messages);
    if (seen.has(key)) continue;
    seen.add(key);
    const text = messages.map((m) => m.content).join('\n');
    const coords = (label) => {
      const m = text.match(new RegExp(`${label}: x: (-?[\\d.]+), y: (-?[\\d.]+), z: (-?[\\d.]+)`));
      return m ? m.slice(1).map(Number) : null;
    };
    const chest = coords('Base chest');
    const prior = messages.flatMap((m, i) => {
      const command = m.role === 'assistant' && parseCommand(m.content);
      return command ? [{command, outcomes: messages.slice(i + 1).filter((n) => n.role !== 'assistant').map((n) => n.content)}] : [];
    });
    rows.push({id: createHash('sha256').update(key).digest('hex'), episode_id: r.episode_id || r.agent || 'unknown', messages,
      goal: r.goal ?? text.match(/YOUR CURRENT ASSIGNED GOAL: "([^"]*)"/)?.[1] ?? null,
      prior: r.prior ?? prior,
      state: r.state ?? {pos: coords('Position'), supplyChest: chest && {x: chest[0], y: chest[1], z: chest[2]}, places: {}, workers: null},
      expected: r.expected ?? {}});
  }
  checkRows(rows);
  return {rows, skipped};
}

async function run(rows, {endpoint, api, model, seed}) {
  checkRows(rows);
  if (!['ollama', 'openai'].includes(api) || !model || !Number.isSafeInteger(seed)) throw new Error('Require --api ollama|openai, --model and integer --seed');
  const url = new URL(endpoint);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error('Endpoint must be an HTTP URL without credentials/query/fragment');
  const route = api === 'ollama' ? '/api/chat' : '/v1/chat/completions';
  const base = url.pathname.replace(/\/$/, '');
  url.pathname = base.endsWith(route) ? base : base === '/v1' && api === 'openai' ? `${base}/chat/completions` : `${base}${route}`;
  const outputs = [];
  for (const row of rows) {
    const body = modelRequest(api, {model, messages: row.messages, sampling: {...SAMPLING, num_predict: 512, seed}});
    const start = performance.now();
    let result;
    try {
      const response = await fetch(url, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(180000)});
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      const reply = modelReply(api, data);
      result = {reply, tokens: api === 'ollama' ? {prompt: data.prompt_eval_count ?? null, completion: data.eval_count ?? null} : data.usage ?? null,
        truncated: api === 'ollama' ? data.done_reason === 'length' : data.choices[0].finish_reason === 'length'};
    } catch (e) { result = {reply: '', error: sanitize(e.message)}; }
    outputs.push({...row, seed, backend: api, model, sampling: {...SAMPLING, num_predict: 512}, ...result, ms: performance.now() - start});
  }
  return outputs;
}

function evaluate(row) {
  const command = parseCommand(row.reply);
  const translated = command && translate(command, row.state || {});
  const previous = row.prior?.at(-1)?.command;
  return {valid: !!command && !translated.refuse && !row.error && !row.truncated,
    refusal: !command || !!translated.refuse || !!row.error || !!row.truncated,
    repeated: !!command && !!previous && JSON.stringify(command) === JSON.stringify(previous),
    stop: command?.name === 'stop'};
}
const METRICS = ['valid_command_rate', 'refusal_no_command_rate', 'repeat_loop_rate', 'stop_rate', 'median_ms', 'p95_ms'];
function score(rows) {
  const flags = rows.map(evaluate);
  const times = rows.map((r) => r.ms).sort((a, b) => a - b);
  if (times.some((t) => !Number.isFinite(t) || t < 0)) throw new Error('Invalid latency');
  const n = rows.length;
  const rate = (key) => n ? flags.filter((f) => f[key]).length / n : null;
  return {calls: n, valid_command_rate: rate('valid'), refusal_no_command_rate: rate('refusal'), repeat_loop_rate: rate('repeated'), stop_rate: rate('stop'),
    median_ms: n ? (times[Math.floor((n - 1) / 2)] + times[Math.floor(n / 2)]) / 2 : null, p95_ms: n ? times[Math.ceil(n * .95) - 1] : null};
}
function compare(a, b) {
  const key = (r) => JSON.stringify([r.id, r.seed]);
  const map = new Map(b.map((r) => [key(r), r]));
  if (map.size !== b.length || new Set(a.map(key)).size !== a.length || a.length !== b.length) throw new Error('Runs must contain unique matching id/seed pairs');
  const paired = a.map((r) => {
    const other = map.get(key(r));
    if (!other || JSON.stringify([r.episode_id, r.messages, r.goal, r.state, r.prior, r.expected]) !== JSON.stringify([other.episode_id, other.messages, other.goal, other.state, other.prior, other.expected])) throw new Error('Runs must use the same frozen prompts/state/history');
    const x = evaluate(r), y = evaluate(other);
    return {id: r.id, seed: r.seed, valid: Number(y.valid) - Number(x.valid), refusal: Number(y.refusal) - Number(x.refusal), repeated: Number(y.repeated) - Number(x.repeated), stop: Number(y.stop) - Number(x.stop), ms: other.ms - r.ms};
  });
  const x = score(a), y = score(b);
  return {A: x, B: y, difference_B_minus_A: Object.fromEntries(METRICS.map((k) => [k, x[k] === null ? null : y[k] - x[k]])), paired};
}
async function main() {
  const {values, positionals: [command, file, second]} = parseArgs({allowPositionals: true, options: {endpoint: {type: 'string'}, api: {type: 'string'}, model: {type: 'string'}, seed: {type: 'string'}}});
  if (!file || !['export', 'run', 'score', 'compare'].includes(command) || (command === 'compare' && !second)) throw new Error('Usage: replay.js export|run|score FILE; replay.js compare A B');
  const rows = readLines(file);
  if (command === 'export') {
    const out = exportRows(rows);
    console.error(`Skipped ${out.skipped} records without full prompts`);
    for (const row of out.rows) console.log(JSON.stringify(row));
  } else if (command === 'run') {
    for (const row of await run(rows, {...values, seed: values.seed === undefined ? NaN : Number(values.seed)})) console.log(JSON.stringify(row));
  } else console.log(JSON.stringify(command === 'score' ? score(rows) : compare(rows, readLines(second)), null, 2));
}
if (require.main === module) main().catch((e) => { console.error(e.message); process.exitCode = 1; });
module.exports = {sanitize, exportRows, run, score, compare};
