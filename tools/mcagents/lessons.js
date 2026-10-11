'use strict';
// Fix memory (the "bots learn by themselves" project, step B1): for a kind of problem (failed job type + error
// class), which fix was tried next and whether the bot's next job result was a success. It learns from job
// results, not from the model's word, and costs no model call. The solver and the agents see the record the
// next time the same problem comes up ("rearm worked 3 of 4 times").
const fs = require('node:fs');
const path = require('node:path');

const MAX_PROBLEMS = 500;
const MAX_FIXES = 6;

// "failed: mine iron_ore 5 - could not reach 1 2 3: No path" -> {type, reason} | null
function parseResult(text) {
  const m = /^(finished|failed|gave up): (\w+)(.*?)(?: - (.*))?$/.exec(String(text || ''));
  return m ? {ok: m[1] === 'finished', type: m[2], rest: m[3].trim(), reason: m[4] || ''} : null;
}
const errorClass = (t) => String(t || '').toLowerCase().replace(/-?\d+(\.\d+)?/g, '#').replace(/[^a-z# ]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 48);
const problemKey = (type, reason) => `${type}|${errorClass(reason)}`;
// A fix as the model would name it again: the job type and its first word argument ("withdraw torch", "rearm").
const fixLabel = (type, rest = '') => [type, String(rest).split(/\s+/).find((w) => /^[a-z_]{2,40}$/.test(w))].filter(Boolean).join(' ');

class Lessons {
  constructor(file, {now = () => Date.now()} = {}) {
    Object.assign(this, {file, now, data: {}});
    try {
      if (file) this.data = JSON.parse(fs.readFileSync(file, 'utf8')) || {};
    } catch {} // no file yet, or a broken one: start empty
  }

  record(problem, fix, ok) {
    if (!problem || !fix) return;
    const p = (this.data[problem] ||= {});
    const f = (p[fix] ||= {tries: 0, wins: 0, t: 0});
    f.tries++;
    if (ok) f.wins++;
    f.t = this.now();
    const fixes = Object.entries(p).sort((a, b) => b[1].t - a[1].t);
    for (const [k] of fixes.slice(MAX_FIXES)) delete p[k];
    const problems = Object.entries(this.data).sort((a, b) => latest(b[1]) - latest(a[1]));
    for (const [k] of problems.slice(MAX_PROBLEMS)) delete this.data[k];
    this.save();
  }

  // "rearm worked 3 of 4 times; retry 0 of 2" (best first), or '' when this problem is new.
  hint(problem, n = 3) {
    const fixes = Object.entries(this.data[problem] || {}).sort((a, b) => b[1].wins / b[1].tries - a[1].wins / a[1].tries || b[1].tries - a[1].tries).slice(0, n);
    return fixes.map(([k, f], i) => `${k} worked ${f.wins} of ${f.tries}${i ? '' : ' times'}`).join('; ');
  }

  save() {
    if (!this.file) return;
    try {
      const tmp = path.join(path.dirname(this.file), `.${path.basename(this.file)}.tmp`);
      fs.writeFileSync(tmp, JSON.stringify(this.data));
      fs.renameSync(tmp, this.file);
    } catch (e) {
      console.error(`[lessons] ${e.message}`);
    }
  }
}
const latest = (p) => Math.max(0, ...Object.values(p).map((f) => f.t));

// Follows one bot's job results: after a failure, the next result (whatever job the bot or its helper chose)
// is recorded as a fix for that failure. Returns the hint to show for a fresh failure, or ''.
class Follow {
  constructor(lessons) { Object.assign(this, {lessons, open: new Map()}); }

  result(bot, text) {
    const r = parseResult(text);
    if (!r) return '';
    const was = this.open.get(bot);
    if (was) this.lessons.record(was, fixLabel(r.type, r.rest), r.ok);
    if (r.ok) {
      this.open.delete(bot);
      return '';
    }
    const key = problemKey(r.type, r.reason);
    this.open.set(bot, key);
    return this.lessons.hint(key);
  }
}

module.exports = {Lessons, Follow, parseResult, problemKey, fixLabel, errorClass};

if (require.main === module) { // self-check: node lessons.js
  const assert = require('node:assert');
  let t = 0;
  const l = new Lessons(null, {now: () => ++t});
  const f = new Follow(l);
  assert.strictEqual(f.result('bot3', 'failed: mine iron_ore 5 - needs a tool that can harvest iron_ore: stone_pickaxe'), '');
  f.result('bot3', 'finished: craft stone_pickaxe 1 (3 s)');
  assert.strictEqual(f.result('bot3', 'failed: mine iron_ore 9 - needs a tool that can harvest iron_ore: stone_pickaxe'), 'craft stone_pickaxe worked 1 of 1 times');
  f.result('bot3', 'failed: rearm -271 66 -214 - could not reach -271 66 -214: No path to the goal!'); // a failed fix
  assert.strictEqual(l.hint(problemKey('mine', 'needs a tool that can harvest iron_ore: stone_pickaxe')), 'craft stone_pickaxe worked 1 of 1 times; rearm worked 0 of 1');
  assert.strictEqual(problemKey('goto', 'could not reach 1 -2 3'), problemKey('goto', 'could not reach 40 5 -6'), 'coordinates do not split a problem');
  assert.strictEqual(fixLabel('deposit', '-271 66 -214 coal'), 'deposit coal');
  assert.strictEqual(parseResult('stopped: mine'), null);
  console.log('lessons ok');
}
