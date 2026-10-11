#!/usr/bin/env node
'use strict';
// Frozen evaluation set for model comparisons (owner, 2026-10-11): idle-replay used to sample the newest 100
// labelled decisions at random, so two runs of the same model differed by 4 points. This builds ONCE a fixed
// set of outcome-labelled agent and solver decisions, stratified over the command types and deduplicated by
// situation (the context), and records its context hashes in a manifest. export-sft.js drops every row whose
// context is in a manifest, so training and evaluation stay disjoint. A version is never rebuilt: a new one
// only with EVAL_VERSION=v2 (older manifests keep excluding too).
// Usage: eval-set.js DECISIONS.jsonl EVAL_DIR   (reads DECISIONS.jsonl.1 as well; EVAL_VERSION, EVAL_PER_LABEL)
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {parseCommand} = require('./agent');
const {buildDataset} = require('./dataset');
const {sanitize} = require('./replay');

const sha = (text) => createHash('sha256').update(text).digest('hex');
// The situation: every turn except the assistant ones (the same view dataset.js trains on), without the reply.
const ctxKey = (messages) => sha(JSON.stringify(messages.filter((m) => m.role !== 'assistant').map(({role, content}) => ({role, content}))));
const MIN_PER_LABEL = 20; // a frozen set smaller than this would be worse than none

// One entry per command in turn, so a command that is logged all day cannot fill the set alone.
function roundRobin(rows, cap) {
  const groups = new Map();
  for (const r of rows) groups.set(r.command, [...(groups.get(r.command) || []), r]);
  const lists = [...groups.values()], out = [];
  for (let i = 0; out.length < cap && lists.some((l) => i < l.length); i++) for (const l of lists) if (i < l.length && out.length < cap) out.push(l[i]);
  return out;
}

// records: the decision log. -> rows [{id, label, source, command, ctx, messages, reply}]
function buildEval(records, perLabel = 150) {
  const outcome = new Map();
  for (const r of records) if (r?.kind === 'outcome' && typeof r.id === 'string' && ['good', 'bad'].includes(r.result) && !outcome.has(r.id)) outcome.set(r.id, r.result);
  // Agent decisions pass dataset.js's validity and privacy filters; solver calls get solverRows' checks.
  const valid = new Set(buildDataset(records).labels.filter((l) => l.label_source === 'outcome' && l.decision_id).map((l) => l.decision_id));
  const seen = new Set(), pool = {good: [], bad: []};
  for (const r of [...records].reverse()) { // newest first
    const label = outcome.get(r?.id);
    if (!label || typeof r.reply !== 'string' || !r.reply.trim() || !Array.isArray(r.messages) || r.messages[0]?.role !== 'system') continue;
    const source = r.kind === 'solver' ? 'solver' : r.kind === undefined ? 'decision' : null;
    if (!source || (source === 'decision' ? !valid.has(r.id) : r.error || JSON.stringify(sanitize(r)) !== JSON.stringify(r) || /https?:\/\/|\/(?:home|run|var)\//i.test(JSON.stringify(r)))) continue;
    const ctx = ctxKey(r.messages), command = parseCommand(r.reply)?.name ?? null;
    if (seen.has(ctx) || (label === 'good' && !command)) continue;
    seen.add(ctx);
    pool[label].push({id: r.id, label, source, command: command ?? '?', ctx, messages: r.messages, reply: r.reply});
  }
  return [...roundRobin(pool.good, perLabel), ...roundRobin(pool.bad, perLabel)];
}

const files = (dir, version) => ({set: path.join(dir, `eval-${version}.jsonl`), manifest: path.join(dir, `eval-${version}.manifest.json`)});

// Writes eval-VERSION.jsonl + manifest once. -> manifest, or null when it exists already.
function writeEval(dir, version, rows) {
  const f = files(dir, version);
  if (fs.existsSync(f.set)) return null;
  fs.mkdirSync(dir, {recursive: true});
  const text = rows.map((r) => JSON.stringify(r) + '\n').join('');
  const manifest = {version, date: new Date().toISOString(), n: rows.length, good: rows.filter((r) => r.label === 'good').length, bad: rows.filter((r) => r.label === 'bad').length,
    commands: rows.reduce((m, r) => ({...m, [r.command]: (m[r.command] ?? 0) + 1}), {}), sha256: sha(text), ids: rows.map((r) => r.id), ctx: rows.map((r) => r.ctx)};
  const put = (file, body) => { fs.writeFileSync(`${file}.tmp`, body, {mode: 0o644}); fs.renameSync(`${file}.tmp`, file); };
  put(f.manifest, JSON.stringify(manifest, null, 1) + '\n');
  put(f.set, text); // last: its existence is the "frozen" marker
  return manifest;
}

function loadEval(dir, version) {
  try { return fs.readFileSync(files(dir, version).set, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)); } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
}

// Context hashes of every eval version in DIR (what training must not see).
function excludedContexts(dir) {
  let names = [];
  try { names = fs.readdirSync(dir).filter((n) => /^eval-.+\.manifest\.json$/.test(n)); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  return new Set(names.flatMap((n) => JSON.parse(fs.readFileSync(path.join(dir, n), 'utf8')).ctx ?? []));
}

function main() {
  const [log, dir] = process.argv.slice(2);
  if (!log || !dir) throw new Error('Usage: eval-set.js DECISIONS.jsonl EVAL_DIR');
  const version = process.env.EVAL_VERSION || 'v1';
  if (!/^[\w.-]+$/.test(version)) throw new Error('Bad EVAL_VERSION');
  if (fs.existsSync(files(dir, version).set)) return console.log(`eval ${version}: frozen already, kept`);
  const {readRecords} = require('./export-sft'); // lazy: export-sft requires this file
  const records = [...readRecords(`${log}.1`).records, ...readRecords(log).records];
  const rows = buildEval(records, Number(process.env.EVAL_PER_LABEL) || 150);
  const per = (l) => rows.filter((r) => r.label === l).length;
  if (per('good') < MIN_PER_LABEL || per('bad') < MIN_PER_LABEL) return console.log(`eval ${version}: not enough labelled decisions yet (good ${per('good')}, bad ${per('bad')}, need ${MIN_PER_LABEL} each), not built`);
  const m = writeEval(dir, version, rows);
  console.log(`eval ${version}: built ${m.n} rows (good ${m.good}, bad ${m.bad}), sha256 ${m.sha256}`);
}
if (require.main === module) main();
module.exports = {ctxKey, buildEval, writeEval, loadEval, excludedContexts, roundRobin};
