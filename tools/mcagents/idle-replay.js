#!/usr/bin/env node
'use strict';
// Gives idle gaming PCs useful work: replays logged decisions against each PC's llama-server
// (only while its /health answers, i.e. nobody is gaming) and records how the model does.
// Only the offline backends (ANDY_OFFLINE_NAMES, albert): never Ollama (11434) or anything but loopback.
const fs = require('node:fs');
const path = require('node:path');
const {performance} = require('node:perf_hooks');
const {parseCommand, SAMPLING} = require('./agent');
const {modelRequest, modelReply} = require('./model-protocol');
const {backendBase, offlineTargets, peoplePlaying} = require('./routing');
const {loadEval} = require('./eval-set');

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
    if (['solver', 'demo', 'demo-bad', 'judge'].includes(r.kind)) continue; // not Mindcraft decisions
    (r.kind === 'outcome' ? outcomes : decisions).push(r);
  }
  return {decisions, outcomes};
}
function withVariant(messages, variant) {
  if (!variant.system_append) return messages;
  return messages.map((m, i) => i === 0 && m.role === 'system' ? {...m, content: m.content + variant.system_append} : m);
}
const same = (a, b) => !!a && !!b && JSON.stringify(a) === JSON.stringify(b);

// 95% Wilson score interval of k successes in n; null when n is 0.
function wilson(k, n, z = 1.96) {
  if (!n) return null;
  const p = k / n, d = 1 + z * z / n, c = p + z * z / (2 * n), m = z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n));
  return [(c - m) / d, (c + m) / d];
}

// Two ways of asking: greedy (temperature 0, the comparable number) and sampled with a fixed seed (as the
// live agents ask). llama-server honours "seed"; N sampled runs = N seeds.
const SEEDS = [1, 2, 3];
const samplingFor = ({seed}) => seed === undefined
  ? {...SAMPLING, temperature: 0, top_k: 1, top_p: 1, min_p: 0, num_predict: 512, seed: 11}
  : {...SAMPLING, num_predict: 512, seed};

// results: [{variant, run, label, logged, reply, ms, error}] -> one summary per variant and run.
function score(results, variant, run = 'greedy') {
  const rs = results.filter((r) => r.variant === variant && (r.run ?? 'greedy') === run);
  const ok = rs.filter((r) => !r.error);
  const times = ok.map((r) => r.ms).sort((a, b) => a - b);
  const cmds = ok.map((r) => ({...r, command: parseCommand(r.reply)}));
  const of = (label) => cmds.filter((r) => r.label === label);
  const frac = (a, b) => b.length ? a.length / b.length : null;
  const good = of('good'), bad = of('bad');
  const valid = cmds.filter((r) => r.command), agree = good.filter((r) => same(r.command, parseCommand(r.logged))), differ = bad.filter((r) => !same(r.command, parseCommand(r.logged)));
  const agree_good = frac(agree, good), disagree_bad = frac(differ, bad);
  return {variant, run, n: rs.length, errors: rs.length - ok.length, ok_n: ok.length,
    valid_command_rate: frac(valid, cmds), valid_ci: wilson(valid.length, cmds.length),
    agree_good, agree_good_ci: wilson(agree.length, good.length), good_n: good.length,
    disagree_bad, disagree_bad_ci: wilson(differ.length, bad.length), bad_n: bad.length,
    score: agree_good === null || disagree_bad === null ? null : (agree_good + disagree_bad) / 2, // mean of the two label rates
    mean_ms: times.length ? times.reduce((a, b) => a + b, 0) / times.length : null,
    p95_ms: times.length ? times[Math.ceil(times.length * .95) - 1] : null};
}

// Per variant: the greedy score, plus "sampled" = the mean of the seeded runs (CIs use one run's n).
function scoreAll(results, variants, seeds = SEEDS) {
  const out = [];
  for (const v of variants) {
    out.push(score(results, v, 'greedy'));
    const runs = seeds.map((s) => score(results, v, `seed${s}`)).filter((r) => r.n);
    if (!runs.length) continue;
    const mean = (k) => runs.some((r) => r[k] === null) ? null : runs.reduce((a, r) => a + r[k], 0) / runs.length;
    const one = runs[0], ci = (k, den) => mean(k) === null ? null : wilson(mean(k) * den, den);
    out.push({...one, run: 'sampled', seeds: runs.length, errors: runs.reduce((a, r) => a + r.errors, 0),
      valid_command_rate: mean('valid_command_rate'), valid_ci: ci('valid_command_rate', one.ok_n),
      agree_good: mean('agree_good'), agree_good_ci: ci('agree_good', one.good_n),
      disagree_bad: mean('disagree_bad'), disagree_bad_ci: ci('disagree_bad', one.bad_n),
      score: mean('score'), mean_ms: mean('mean_ms'), p95_ms: mean('p95_ms')});
  }
  return out;
}

// Replay rows x variants x runs (greedy, then each seed; seeds only for the first variant, the baseline) against
// one server. Stops at the first sign the PC is gone (health not 200, any request error) or at the deadline,
// and keeps what it has.
async function runBackend(base, rows, variants, {timeoutMs = 60000, healthMs = 3000, seeds = [], deadline = Infinity} = {}) {
  base = backendBase(base);
  const healthy = () => !peoplePlaying() && fetch(`${base}/health`, {redirect: 'error', signal: AbortSignal.timeout(healthMs)}).then((r) => r.status === 200, () => false);
  const out = {alias: null, results: [], stopped: null};
  if (!await healthy()) { out.stopped = peoplePlaying() ? 'not free (people are playing)' : 'not free (health)'; return out; }
  const plan = variants.flatMap((variant, i) => [{variant, run: 'greedy'}, ...(i === 0 ? seeds.map((seed) => ({variant, run: `seed${seed}`, seed})) : [])]);
  for (const {variant, run, seed} of plan) for (const row of rows) {
    if (Date.now() > deadline) { out.stopped = 'deadline'; return out; }
    if (out.results.length && !await healthy()) { out.stopped = 'health lost'; return out; }
    const body = modelRequest('openai', {model: 'andy', messages: withVariant(row.messages, variant), sampling: samplingFor({seed})});
    const t0 = performance.now();
    try {
      const res = await fetch(`${base}/v1/chat/completions`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(timeoutMs)});
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      out.alias ??= data.model ?? null;
      out.results.push({id: row.id, variant: variant.name, run, label: row.label, logged: row.reply, reply: modelReply('openai', data), ms: performance.now() - t0});
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
  const targets = offlineTargets(env); // ANDY_OFFLINE_NAMES only (albert); never the live backends or Ollama
  const dir = env.REPLAYS || '/var/lib/mcagents/replays';
  const n = Number(env.BATCH || 100);
  const variants = JSON.parse(fs.readFileSync(env.VARIANTS || path.join(__dirname, 'variants.json'), 'utf8'));
  const {decisions, outcomes} = readLog(env.LOG || '/var/lib/mcagents/decisions.jsonl');
  // The frozen eval set when present (comparable runs); else the old newest-labelled sample.
  const version = env.EVAL_VERSION || 'v1';
  const frozen = loadEval(env.EVALS || '/var/lib/mcagents/eval', version);
  const rows = frozen ? frozen.map(({id, messages, reply, label}) => ({id, messages, reply, label})) : sample(decisions, outcomes, n);
  const seeds = (env.SEEDS ?? SEEDS.join(',')).split(',').filter(Boolean).map(Number);
  const deadline = Date.now() + Number(env.DEADLINE_MS || 45 * 60000); // stay inside the unit's timeout
  fs.mkdirSync(dir, {recursive: true});
  const lines = [];
  for (const {name, url} of targets) {
    const run = await runBackend(url, rows, variants, {seeds, deadline});
    if (!run.results.length) { console.log(`${name}: ${run.stopped}`); continue; }
    const t = new Date().toISOString().replace(/\.\d+Z$/, 'Z').replace(/:/g, '');
    const summary = {t: new Date().toISOString(), backend: name, alias: run.alias, eval: frozen ? version : null, eval_n: rows.length, stopped: run.stopped, variants: scoreAll(run.results, variants.map((v) => v.name), seeds)};
    fs.writeFileSync(path.join(dir, `${t}-${name}.json`), JSON.stringify({...summary, results: run.results}, null, 1));
    fs.appendFileSync(path.join(dir, 'summary.jsonl'), JSON.stringify(summary) + '\n');
    const pct = (x) => x === null ? '-' : `${Math.round(x * 100)}%`;
    lines.push(`${name} (${run.alias}) ${run.stopped ? 'stopped early: ' + run.stopped : 'done'}: ` + summary.variants.map((s) => `${s.variant}/${s.run} n=${s.n} valid ${pct(s.valid_command_rate)} agree-good ${pct(s.agree_good)} disagree-bad ${pct(s.disagree_bad)} score ${pct(s.score)} p95 ${Math.round(s.p95_ms ?? 0)}ms`).join('; '));
  }
  console.log(lines.join('\n') || 'no PC was free');
  if (lines.length) await notify(lines.join('\n'));
}
if (require.main === module) main().catch((e) => { console.error(e.message); process.exitCode = 1; });
module.exports = {backendBase, sample, score, scoreAll, wilson, samplingFor, runBackend, withVariant};
