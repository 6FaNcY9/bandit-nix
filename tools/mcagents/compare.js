#!/usr/bin/env node
'use strict';
// Which model is better? Reads the idle replay's summary.jsonl and prints, per model alias, its latest run on
// the frozen eval set (rates with 95% Wilson intervals). Usage: compare.js [SUMMARY.jsonl] [--eval v1] [--variant baseline]
const fs = require('node:fs');

const pct = (x, ci) => x === null || x === undefined ? '-' : `${(x * 100).toFixed(0)}%` + (ci ? ` [${(ci[0] * 100).toFixed(0)}-${(ci[1] * 100).toFixed(0)}]` : '');

// lines: parsed summary objects. -> text table, best combined score first.
function table(summaries, {evalName = 'v1', variant = 'baseline'} = {}) {
  const latest = new Map();
  for (const s of summaries) if (s.eval === evalName && s.alias && (!latest.has(s.alias) || s.t > latest.get(s.alias).t)) latest.set(s.alias, s);
  const rows = [];
  for (const [alias, s] of latest) for (const v of s.variants.filter((x) => x.variant === variant)) rows.push([alias, v.run ?? 'greedy', v.n + (s.stopped ? '*' : ''), pct(v.valid_command_rate, v.valid_ci), pct(v.agree_good, v.agree_good_ci), pct(v.disagree_bad, v.disagree_bad_ci), pct(v.score), `${Math.round(v.p95_ms ?? 0)}ms`, s.t.slice(0, 10), v.score ?? -1]);
  if (!rows.length) return `no runs on eval ${evalName} yet`;
  rows.sort((a, b) => (a[1] === 'greedy' ? 0 : 1) - (b[1] === 'greedy' ? 0 : 1) || b[9] - a[9]);
  const head = ['model', 'run', 'n', 'valid', 'agree-good', 'disagree-bad', 'score', 'p95', 'date'];
  const cells = [head, ...rows.map((r) => r.slice(0, 9))];
  const w = head.map((_, i) => Math.max(...cells.map((r) => String(r[i]).length)));
  return cells.map((r) => r.map((c, i) => String(c).padEnd(w[i])).join('  ').trimEnd()).join('\n') + `\n(eval ${evalName}, variant ${variant}; 95% Wilson intervals; * = stopped early; score = mean of agree-good and disagree-bad)`;
}

function main() {
  const args = process.argv.slice(2), opt = (k, d) => { const i = args.indexOf(k); return i < 0 ? d : args.splice(i, 2)[1]; };
  const evalName = opt('--eval', 'v1'), variant = opt('--variant', 'baseline');
  const file = args[0] || '/var/lib/mcagents/replays/summary.jsonl';
  const summaries = fs.readFileSync(file, 'utf8').split('\n').flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
  console.log(table(summaries, {evalName, variant}));
}
if (require.main === module) main();
module.exports = {table};
