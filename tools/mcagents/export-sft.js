#!/usr/bin/env node
'use strict';
// Daily lab export for the LoRA run on the gaming PC (tools/slayer/train): turns the logged
// model calls (LOG) into OUT/sft.jsonl + OUT/stats.json. Rows are {messages, source, split}:
//  - source "decision": dataset.js rows (good outcomes only, deduplicated, privacy-filtered)
//  - source "solver": solver.js calls whose logged outcome is good (a different prompt, a separate source)
//  - source "demo": demos.js rows, jobs of the deterministic crew that finished (good by construction), at
//    most DEMO_RATIO (default 3) x the decision rows (floor 10 decisions), balanced over the commands
//  - source "judged": decisions with an unknown outcome that the judge (judge.js) graded good, only with
//    JUDGED=1 (at most JUDGED_MAX, default 200); real outcomes always win, so they never hide behind a grade
// A missing or empty log writes an empty export and exits 0. Torn JSON lines are skipped.
// Usage: export-sft.js DECISIONS.jsonl OUT_DIR
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {buildDataset} = require('./dataset');
const {sanitize} = require('./replay');
// A module reference, not destructured: eval-set.js requires this file back (circular), so its
// functions are read at call time, not at load time.
const evalSet = require('./eval-set');

function readRecords(file) {
  let text = '';
  try { text = fs.readFileSync(file, 'utf8'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  let torn = 0;
  const records = text.split('\n').flatMap((line) => {
    if (!line.trim()) return [];
    try { return [JSON.parse(line)]; } catch { torn++; return []; }
  });
  return {records, torn};
}

// Same 80/10/10 idea as dataset.js, by episode so one incident never spans splits.
const splitOf = (episode) => { const n = createHash('sha256').update(String(episode)).digest()[0] / 256; return n < .8 ? 'train' : n < .9 ? 'val' : 'test'; };

function solverRows(records) {
  const good = new Set(records.filter((r) => r?.kind === 'outcome' && r.result === 'good' && typeof r.id === 'string').map((r) => r.id));
  const rows = [];
  for (const r of records) {
    if (r?.kind !== 'solver' || r.error || !good.has(r.id) || typeof r.reply !== 'string' || !r.reply.trim() || !Array.isArray(r.messages) || r.messages[0]?.role !== 'system') continue;
    if (r.messages.some((m) => !m || !['system', 'user'].includes(m.role) || typeof m.content !== 'string')) continue;
    if (JSON.stringify(sanitize(r)) !== JSON.stringify(r) || /https?:\/\/|\/(?:home|run|var)\//i.test(JSON.stringify(r))) continue;
    rows.push({messages: [...r.messages.map(({role, content}) => ({role, content})), {role: 'assistant', content: r.reply.trim()}], source: 'solver', split: splitOf(r.episode_id || r.id)});
  }
  return rows;
}

// Same privacy gate as dataset.js: no secrets, URLs, paths, or human player names in the bot-state text.
const humanNearby = (m) => /Nearby Human Players:/.test(m.content) && m.content.split('\n').some((line) => /Nearby Human Players:/.test(line) && line.split(':').slice(1).join(':').split(',').some((name) => name.trim() && !/^bot\d+$/.test(name.trim()) && !/^none\.?$/i.test(name.trim())));
const safeRow = (r) => JSON.stringify(sanitize(r)) === JSON.stringify(r) && !/https?:\/\/|\/(?:home|run|var)\//i.test(JSON.stringify(r.messages)) && !r.messages.some(humanNearby);

const commandName = (text) => /^\s*!(\w+)/.exec(text)?.[1] || '?';

// Newest first, one row per command in turn, so a job type that finishes all day cannot fill the cap alone.
function balanced(rows, cap) {
  const groups = new Map();
  for (const r of rows) groups.set(r.command, [...(groups.get(r.command) || []), r]);
  const lists = [...groups.values()].map((l) => l.sort((a, b) => String(b.t).localeCompare(String(a.t))));
  const out = [];
  for (let i = 0; out.length < cap && lists.some((l) => i < l.length); i++) for (const l of lists) if (i < l.length && out.length < cap) out.push(l[i]);
  return out;
}

function demoRows(records, cap) {
  const seen = new Set(), ok = [];
  for (const r of records) {
    if (r?.kind !== 'demo' || typeof r.key !== 'string' || seen.has(r.key) || !Array.isArray(r.messages) || r.messages.length !== 3) continue;
    const [sys, user, bot] = r.messages;
    if (sys?.role !== 'system' || user?.role !== 'user' || bot?.role !== 'assistant' || r.messages.some((m) => typeof m.content !== 'string') || !/^!\w/.test(bot.content) || !/^SYSTEM:/.test(user.content)) continue;
    if (!safeRow(r)) continue;
    seen.add(r.key);
    ok.push({...r, command: commandName(bot.content)});
  }
  const picked = balanced(ok, cap);
  return {rows: picked.map((r) => ({messages: r.messages.map(({role, content}) => ({role, content})), source: 'demo', split: splitOf(r.key)})), total: ok.length};
}

// Judged-good decisions with no real outcome, through the normal dataset filters (the grade stands in for the outcome).
function judgedRows(records, judgments, max, taken) {
  const real = new Set(records.filter((r) => r?.kind === 'outcome').map((r) => r.id));
  const last = new Map();
  for (const j of judgments) if (j?.kind === 'judge' && typeof j.ref === 'string') last.set(j.ref, j.verdict); // the newest grade of a decision wins
  const refs = new Set([...last].filter(([ref, v]) => v === 'good' && !real.has(ref)).map(([ref]) => ref));
  const picked = records.filter((r) => r && r.kind === undefined && refs.has(r.id));
  const grades = picked.map((r) => ({kind: 'outcome', id: r.id, result: 'good', reason: 'judged good', ms: 0}));
  const rows = [];
  for (const [split, list] of Object.entries(buildDataset([...picked, ...grades]).splits)) for (const {messages} of list) if (!taken.has(JSON.stringify(messages))) rows.push({messages, source: 'judged', split});
  return rows.slice(0, max);
}

// exclude: context hashes of the frozen eval set (eval-set.js); no training row may share one.
function exportSft(records, {judgments = [], demoRatio = 3, judged = false, judgedMax = 200, exclude = new Set()} = {}) {
  const data = buildDataset(records);
  const free = (r) => !exclude.has(evalSet.ctxKey(r.messages));
  const rows = [];
  for (const [split, list] of Object.entries(data.splits)) for (const {messages} of list) rows.push({messages, source: 'decision', split});
  const decisionAll = rows.length;
  rows.splice(0, rows.length, ...rows.filter(free));
  const decisionRows = rows.length;
  const solver = solverRows(records).filter(free);
  rows.push(...solver);
  const demo = demoRows(records, Math.floor(demoRatio * Math.max(decisionRows, 10)));
  rows.push(...demo.rows);
  const taken = new Set(rows.map((r) => JSON.stringify(r.messages)));
  const judgedList = judged ? judgedRows(records, judgments, judgedMax, taken).filter(free) : [];
  rows.push(...judgedList);
  const sources = {decision: decisionRows, solver: solver.length, demo: demo.rows.length, judged: judgedList.length};
  const stats = {date: new Date().toISOString(), rows: rows.length, decision_rows: decisionRows, solver_rows: solver.length, demo_rows: demo.rows.length, judged_rows: judgedList.length, sources, demo_available: demo.total, judged_enabled: judged, eval_excluded: decisionAll - decisionRows, good: data.stats.labels.good, bad: data.stats.labels.bad, neutral: data.stats.labels.neutral, unknown: data.stats.labels.unknown, input: records.length};
  return {rows, stats};
}

function main() {
  const [file, out] = process.argv.slice(2);
  if (!file || !out) throw new Error('Usage: export-sft.js DECISIONS.jsonl OUT_DIR');
  // agent.js rotates the log at 50 MB to FILE.1: the older half counts too.
  const [older, current] = [readRecords(`${file}.1`), readRecords(file)];
  const records = [...older.records, ...current.records], torn = older.torn + current.torn;
  const judgments = readRecords(process.env.JUDGMENTS || path.join(path.dirname(file), 'judgments.jsonl')).records;
  const {rows, stats} = exportSft(records, {judgments, demoRatio: process.env.DEMO_RATIO === undefined ? 3 : Number(process.env.DEMO_RATIO), judged: process.env.JUDGED === '1', exclude: evalSet.excludedContexts(process.env.EVALS || path.join(path.dirname(file), 'eval')), judgedMax: Number(process.env.JUDGED_MAX) || 200});
  stats.torn_lines = torn;
  fs.mkdirSync(out, {recursive: true});
  // Rename keeps a reader from ever seeing half a file.
  const put = (name, text) => { const tmp = path.join(out, `.${name}.tmp`); fs.writeFileSync(tmp, text, {mode: 0o644}); fs.renameSync(tmp, path.join(out, name)); };
  put('sft.jsonl', rows.map((r) => JSON.stringify(r) + '\n').join(''));
  put('stats.json', JSON.stringify(stats, null, 2) + '\n');
  console.log(JSON.stringify(stats));
}
if (require.main === module) main();
module.exports = {exportSft, readRecords, balanced, demoRows};
