#!/usr/bin/env node
'use strict';
// Daily lab export for the LoRA run on the gaming PC (tools/slayer/train): turns the logged
// model calls (LOG) into OUT/sft.jsonl + OUT/stats.json. Rows are {messages, source, split}:
//  - source "decision": dataset.js rows (good outcomes only, deduplicated, privacy-filtered)
//  - source "solver": solver.js calls whose logged outcome is good (a different prompt, a separate source)
// A missing or empty log writes an empty export and exits 0. Torn JSON lines are skipped.
// Usage: export-sft.js DECISIONS.jsonl OUT_DIR
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {buildDataset} = require('./dataset');
const {sanitize} = require('./replay');

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

function exportSft(records) {
  const data = buildDataset(records);
  const rows = [];
  for (const [split, list] of Object.entries(data.splits)) for (const {messages} of list) rows.push({messages, source: 'decision', split});
  const solver = solverRows(records);
  rows.push(...solver);
  const stats = {date: new Date().toISOString(), rows: rows.length, decision_rows: rows.length - solver.length, solver_rows: solver.length, good: data.stats.labels.good, bad: data.stats.labels.bad, neutral: data.stats.labels.neutral, unknown: data.stats.labels.unknown, input: records.length};
  return {rows, stats};
}

function main() {
  const [file, out] = process.argv.slice(2);
  if (!file || !out) throw new Error('Usage: export-sft.js DECISIONS.jsonl OUT_DIR');
  const {records, torn} = readRecords(file);
  const {rows, stats} = exportSft(records);
  stats.torn_lines = torn;
  fs.mkdirSync(out, {recursive: true});
  // Rename keeps a reader from ever seeing half a file.
  const put = (name, text) => { const tmp = path.join(out, `.${name}.tmp`); fs.writeFileSync(tmp, text, {mode: 0o644}); fs.renameSync(tmp, path.join(out, name)); };
  put('sft.jsonl', rows.map((r) => JSON.stringify(r) + '\n').join(''));
  put('stats.json', JSON.stringify(stats, null, 2) + '\n');
  console.log(JSON.stringify(stats));
}
if (require.main === module) main();
module.exports = {exportSft, readRecords};
