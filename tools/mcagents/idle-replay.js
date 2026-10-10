#!/usr/bin/env node
'use strict';
// Gives idle gaming PCs useful work: replays logged decisions against each PC's llama-server
// (only while its /health answers, i.e. nobody is gaming) and records how the model does.
// Never talks to Ollama (11434, the lab GPU) or to anything but loopback.
const fs = require('node:fs');
const path = require('node:path');
const {performance} = require('node:perf_hooks');
const {parseCommand, SAMPLING} = require('./agent');
const {modelRequest, modelReply} = require('./model-protocol');

const OLLAMA_PORT = '11434';
function backendBase(url) {
  const u = new URL(url);
  if (u.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(u.hostname) || u.port === OLLAMA_PORT || !u.port) throw new Error(`Refusing backend ${url}: only loopback llama-server ports, never Ollama (${OLLAMA_PORT})`);
  return `http://${u.host}`;
}

// Labeled decisions first (newest first), then the newest unlabeled ones, up to n.
function sample(decisions, outcomes, n) {
  const label = new Map(outcomes.map((o) => [o.id, o.result]));
  const seen = new Set();
  const rows = decisions.filter((d) => d.id && Array.isArray(d.messages) && d.messages.length && typeof d.reply === 'string' && !seen.has(d.id) && seen.add(d.id))
    .map((d) => ({id: d.id, messages: d.messages, reply: d.reply, label: label.get(d.id) ?? null}))
    .reverse();
  const good = (r) => r.label === 'good' || r.label === 'bad';
  return [...rows.filter(good), ...rows.filter((r) => !good(r))].slice(0, n);
}
function readLog(file) {
  const decisions = [], outcomes = [];
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    let r; try { r = JSON.parse(line); } catch { continue; }
    if (r.kind === 'solver') continue; // problem-solver prompts are not Mindcraft decisions
    (r.kind === 'outcome' ? outcomes : decisions).push(r);
  }
  return {decisions, outcomes};
}
function withVariant(messages, variant) {
  if (!variant.system_append) return messages;
  return messages.map((m, i) => i === 0 && m.role === 'system' ? {...m, content: m.content + variant.system_append} : m);
}
const same = (a, b) => !!a && !!b && JSON.stringify(a) === JSON.stringify(b);

// results: [{variant, label, logged, reply, ms, error}] -> one summary per variant.
function score(results, variant) {
  const rs = results.filter((r) => r.variant === variant);
  const ok = rs.filter((r) => !r.error);
  const times = ok.map((r) => r.ms).sort((a, b) => a - b);
  const cmds = ok.map((r) => ({...r, command: parseCommand(r.reply)}));
  const of = (label) => cmds.filter((r) => r.label === label);
  const frac = (a, b) => b.length ? a.length / b.length : null;
  const good = of('good'), bad = of('bad');
  return {variant, n: rs.length, errors: rs.length - ok.length,
    valid_command_rate: frac(cmds.filter((r) => r.command), cmds),
    agree_good: frac(good.filter((r) => same(r.command, parseCommand(r.logged))), good), good_n: good.length,
    disagree_bad: frac(bad.filter((r) => !same(r.command, parseCommand(r.logged))), bad), bad_n: bad.length,
    mean_ms: times.length ? times.reduce((a, b) => a + b, 0) / times.length : null,
    p95_ms: times.length ? times[Math.ceil(times.length * .95) - 1] : null};
}

// Replay rows x variants against one server. Stops at the first sign the PC is gone
// (health not 200, any request error) and keeps what it has.
async function runBackend(base, rows, variants, {timeoutMs = 60000, healthMs = 3000} = {}) {
  base = backendBase(base);
  const healthy = () => fetch(`${base}/health`, {signal: AbortSignal.timeout(healthMs)}).then((r) => r.status === 200, () => false);
  const out = {alias: null, results: [], stopped: null};
  if (!await healthy()) { out.stopped = 'not free (health)'; return out; }
  for (const variant of variants) for (const row of rows) {
    if (out.results.length && !await healthy()) { out.stopped = 'health lost'; return out; }
    const body = modelRequest('openai', {model: 'andy', messages: withVariant(row.messages, variant), sampling: {...SAMPLING, num_predict: 512, seed: 11}});
    const t0 = performance.now();
    try {
      const res = await fetch(`${base}/v1/chat/completions`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(timeoutMs)});
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      out.alias ??= data.model ?? null;
      out.results.push({id: row.id, variant: variant.name, label: row.label, logged: row.reply, reply: modelReply('openai', data), ms: performance.now() - t0});
    } catch (e) { out.stopped = `request failed: ${e.message}`; return out; }
  }
  return out;
}

async function notify(text) {
  const dir = process.env.CREDENTIALS_DIRECTORY, url = process.env.NTFY_URL;
  if (!dir || !url) return;
  try {
    const token = fs.readFileSync(path.join(dir, 'ntfy'), 'utf8').match(/^NTFY_TOKEN=(.+)$/m)?.[1];
    if (token) await fetch(url, {method: 'POST', headers: {Authorization: `Bearer ${token}`, Title: 'mcagents idle replay'}, body: text, signal: AbortSignal.timeout(10000)});
  } catch { /* notification is best effort */ }
}

async function main() {
  const env = process.env;
  const names = (env.ANDY_BACKEND_NAMES || '').split(',').filter(Boolean), urls = (env.ANDY_URLS || '').split(',').filter(Boolean);
  const dir = env.REPLAYS || '/var/lib/mcagents/replays';
  const n = Number(env.BATCH || 100);
  const variants = JSON.parse(fs.readFileSync(env.VARIANTS || path.join(__dirname, 'variants.json'), 'utf8'));
  const {decisions, outcomes} = readLog(env.LOG || '/var/lib/mcagents/decisions.jsonl');
  const rows = sample(decisions, outcomes, n);
  fs.mkdirSync(dir, {recursive: true});
  const lines = [];
  for (const [i, name] of names.entries()) {
    const run = await runBackend(urls[i], rows, variants);
    if (!run.results.length) { console.log(`${name}: ${run.stopped}`); continue; }
    const t = new Date().toISOString().replace(/\.\d+Z$/, 'Z').replace(/:/g, '');
    const summary = {t: new Date().toISOString(), backend: name, alias: run.alias, stopped: run.stopped, variants: variants.map((v) => score(run.results, v.name))};
    fs.writeFileSync(path.join(dir, `${t}-${name}.json`), JSON.stringify({...summary, results: run.results}, null, 1));
    fs.appendFileSync(path.join(dir, 'summary.jsonl'), JSON.stringify(summary) + '\n');
    const pct = (x) => x === null ? '-' : `${Math.round(x * 100)}%`;
    lines.push(`${name} (${run.alias}) ${run.stopped ? 'stopped early: ' + run.stopped : 'done'}: ` + summary.variants.map((s) => `${s.variant} n=${s.n} valid ${pct(s.valid_command_rate)} agree-good ${pct(s.agree_good)} disagree-bad ${pct(s.disagree_bad)} p95 ${Math.round(s.p95_ms ?? 0)}ms`).join('; '));
  }
  console.log(lines.join('\n') || 'no PC was free');
  if (lines.length) await notify(lines.join('\n'));
}
if (require.main === module) main().catch((e) => { console.error(e.message); process.exitCode = 1; });
module.exports = {backendBase, sample, score, runBackend, withVariant};
