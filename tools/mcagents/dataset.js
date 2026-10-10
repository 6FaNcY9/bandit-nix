#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {parseArgs} = require('node:util');
const {sanitize, exportRows} = require('./replay');
const {parseCommand, translate} = require('./agent');

const hash = (v) => createHash('sha256').update(JSON.stringify(v)).digest('hex');
const time = (t) => typeof t === 'number' ? t : Date.parse(t);
const normalize = (s) => s.toLowerCase().replace(/-?\d+(?:\.\d+)?/g, '#').replace(/\s+/g, ' ').trim();
const cleanReply = (s) => s.replace(/<think>[\s\S]*?<\/think>/g, '').trim();
const count = (obj, key) => { obj[key] = (obj[key] || 0) + 1; };
const terminal = (text) => text.match(/^(finished|failed|gave up|stopped): (.+?)(?: - | \(|$)/);

function readLines(file) {
  return fs.readFileSync(file, 'utf8').split('\n').flatMap((line, i) => {
    if (!line.trim()) return [];
    try { return [JSON.parse(line)]; } catch { throw new Error(`Invalid JSON at line ${i + 1}`); }
  });
}
function readEvents(file) {
  const text = fs.readFileSync(file, 'utf8');
  let data;
  try { data = JSON.parse(text); } catch { data = readLines(file); }
  return eventRows(data);
}
function eventRows(data) {
  const rows = Array.isArray(data) ? data : data?.events;
  if (!Array.isArray(rows)) throw new Error('Events must be an array, JSONL, or an /api/events dump');
  const seen = new Map();
  return rows.map((r) => ({...(r.event || r), server_session: r.server_session || 'capture'})).filter((e) => {
    if (!e || !Number.isFinite(time(e.t)) || typeof e.bot !== 'string' || typeof e.text !== 'string' || !Number.isSafeInteger(e.id)) throw new Error('Invalid event');
    const key = JSON.stringify([e.server_session, e.id]);
    const signature = hash(e);
    if (seen.has(key) && seen.get(key) !== signature) throw new Error('Conflicting event IDs: annotate server sessions');
    if (seen.has(key)) return false;
    seen.set(key, signature);
    return true;
  });
}

// Compare rolling histories, not the mutable first system/state message.
function freshMessages(previous, current) {
  for (let n = Math.min(previous.length, current.length); n > 0; n--) {
    if (JSON.stringify(previous.slice(-n)) === JSON.stringify(current.slice(0, n))) return current.slice(n);
  }
  // shortcut: no history overlap loses correlation; collect better logs before recovering these turns.
  return previous.length ? [] : current;
}
function jobFor(row, command) {
  if (!command) return {};
  let cmd = command, bot = row.agent;
  if (command.name === 'assign') {
    bot = command.args[0];
    cmd = parseCommand(String(command.args[1] || ''));
    if (!cmd || cmd.name === 'assign') return {refuse: true};
    const docs = row.messages[0].content.match(/Your workers: ([^\n]+)/);
    if (docs && !docs[1].split(',').map((s) => s.trim()).includes(bot)) return {refuse: true};
  }
  const state = exportRows([row]).rows[0].state;
  if (cmd.name === 'baseStatus' && /!baseStatus:/.test(row.messages[0].content)) return {query: 'baseStatus'};
  const translated = translate(cmd, state);
  if (translated.refuse) return {refuse: true};
  if (translated.query && command.name !== 'assign') return {query: translated.query};
  if (!translated.job) return {refuse: command.name === 'assign'};
  const [type, args] = translated.job;
  // Matches bots.js jobLabel without importing the live executor.
  const label = `${type} ${Object.values(args).join(' ')}`.trim();
  return {bot, label};
}

function buildDataset(records, events = [], {cap = 3} = {}) {
  if (!Number.isSafeInteger(cap) || cap < 1) throw new Error('Situation cap must be a positive integer');
  const stats = {input: records.length, dropped: {}, labels: {good: 0, bad: 0, neutral: 0, unknown: 0}, commands: Object.create(null), agents: Object.create(null), sft: 0, splits: {}, episodes: 0, split_groups: 0};
  const rows = [], exact = new Set();
  for (const [i, r] of records.entries()) {
    const drop = (why) => count(stats.dropped, why);
    if (!r || !Array.isArray(r.messages) || !r.messages.length || typeof r.reply !== 'string' || typeof r.agent !== 'string' || !Number.isFinite(time(r.t)) || (r.ms !== undefined && (!Number.isFinite(r.ms) || r.ms < 0)) || r.messages.some((m) => !m || !['system', 'user', 'assistant'].includes(m.role) || typeof m.content !== 'string') || r.messages[0].role !== 'system') { drop('invalid'); continue; }
    if (JSON.stringify(sanitize(r)) !== JSON.stringify(r)) { drop('secrets'); continue; }
    // Human chat must not survive as copied context, including in thinking/replies.
    if (r.messages.some((m) => m.role === 'user' && !/^SYSTEM:|^bot\d+: \(FROM OTHER BOT\)/.test(m.content)) || /\(FROM (?:PLAYER|HUMAN)\)|(?:player|human) chat\s*:|https?:\/\/|\/(?:home|run|var)\//i.test(JSON.stringify(r)) || r.messages.some((m) => /Nearby Human Players:/.test(m.content) && m.content.split('\n').some((line) => /Nearby Human Players:/.test(line) && line.split(':').slice(1).join(':').split(',').some((name) => name.trim() && !/^bot\d+$/.test(name.trim()) && name.trim() !== 'none')))) { drop('privacy'); continue; }
    const rawKey = hash([r.agent, r.t, r.messages, r.reply]);
    if (exact.has(rawKey)) { drop('raw_duplicate'); continue; }
    exact.add(rawKey);
    const reply = cleanReply(r.reply), command = parseCommand(reply);
    const episode = r.episode_id || r.server_session || 'capture';
    if (typeof episode !== 'string' || !episode) throw new Error('Invalid episode/session');
    const job = jobFor(r, command);
    if (!command && /!\w/.test(reply)) job.refuse = true;
    rows.push({...r, reply, command, job, episode, line: i + 1, at: time(r.t), label: job.refuse ? 'bad' : !command ? 'neutral' : 'unknown', reason: job.refuse ? 'refused' : !command ? 'no command' : 'no unambiguous outcome'});
  }
  rows.sort((a, b) => a.at - b.at || a.line - b.line);
  const history = new Map(), signals = [];
  for (const row of rows) {
    const key = JSON.stringify([row.episode, row.agent]);
    const old = history.get(key);
    const current = row.messages.slice(1);
    const fresh = freshMessages(old?.messages || [], current);
    let anchor = null;
    for (const m of fresh) {
      if (m.role === 'assistant') { anchor = old && cleanReply(m.content) === old.row.reply ? old.row : null; continue; }
      if (m.role !== 'user') continue;
      const worker = m.content.match(/^SYSTEM: Worker ([^:]+): ([\s\S]*)$/);
      const text = worker ? worker[2] : m.content.replace(/^SYSTEM: Code output:\s*/, '');
      if (old && !events.length && terminal(text) && (worker || m.content.startsWith('SYSTEM: Code output:'))) signals.push({at: row.at - (row.ms || 0), bot: worker ? worker[1] : row.agent, text, session: row.server_session || 'capture', episode: row.episode});
      if (anchor && /^(?:SYSTEM: )?(?:Refused:|Not sent:|Code output: (?:Action|Assignment to .*|Stop) failed)/i.test(m.content)) {
        anchor.label = 'bad'; anchor.reason = 'refused';
      } else if (anchor?.job.query && /^SYSTEM: (?:STATS|INVENTORY|ENTITIES|Nearby|Saved place names:|BASE STATUS|\*COMMAND DOCS)/.test(m.content)) {
        anchor.label = 'good'; anchor.reason = 'query response';
      }
    }
    history.set(key, {row, messages: current});
  }
  for (const e of eventRows(events)) {
    if (['done', 'fail', 'stop'].includes(e.kind) && terminal(e.text)) signals.push({at: time(e.t), bot: e.bot, text: e.text, session: e.server_session});
  }
  signals.sort((a, b) => a.at - b.at);
  const consumed = new Set();
  for (const s of signals) {
    const [, status, label] = terminal(s.text);
    const candidates = rows.filter((r) => r.at <= s.at && (!s.episode || r.episode === s.episode) && (r.server_session || 'capture') === s.session && r.job.bot === s.bot && r.job.label === label && !consumed.has(r));
    if (candidates.length !== 1) {
      for (const r of candidates) { consumed.add(r); r.reason = 'ambiguous overlapping jobs'; }
      continue;
    }
    const r = candidates[0]; consumed.add(r);
    if (r.label === 'bad') continue;
    r.outcomeAt = s.at;
    r.label = status === 'finished' ? 'good' : status === 'stopped' ? 'unknown' : 'bad';
    r.reason = status;
  }
  // A repeat is bad only after a known failure with unchanged logged system/state.
  const failed = new Map();
  for (const r of rows) {
    const situation = normalize(r.messages.filter((m) => m.role === 'user').at(-1)?.content || '');
    const repeatKey = hash([r.episode, r.agent, r.command, r.messages[0].content]);
    if (r.command && failed.has(repeatKey) && failed.get(repeatKey) <= r.at) { r.label = 'bad'; r.reason = 'repeated failed command'; }
    if (r.label === 'bad' && ['failed', 'gave up', 'repeated failed command'].includes(r.reason)) failed.set(repeatKey, Math.min(failed.get(repeatKey) ?? Infinity, r.outcomeAt ?? r.at));
    count(stats.labels, r.label);
    const name = r.command?.name || '(none)';
    stats.commands[name] ||= {good: 0, bad: 0, neutral: 0, unknown: 0}; count(stats.commands[name], r.label);
    stats.agents[r.agent] ||= {good: 0, bad: 0, neutral: 0, unknown: 0}; count(stats.agents[r.agent], r.label);
    const system = r.messages[0].content;
    const goal = r.goal || system.match(/YOUR CURRENT ASSIGNED GOAL: "([^"]*)"/)?.[1] || system;
    r.cluster = hash([normalize(system), situation]);
    r.situation = hash([goal, r.command?.name, situation.match(/failed|finished|gave up|refused|idle|stopped/)?.[0] || 'other']);
  }
  // Join whole episodes sharing a near prompt before filtering, including dropped duplicates.
  const parent = new Map(rows.map((r) => [r.episode, r.episode]));
  const root = (e) => { while (parent.get(e) !== e) e = parent.get(e); return e; };
  const clusters = new Map();
  for (const r of rows) {
    if (clusters.has(r.cluster)) parent.set(root(r.episode), root(clusters.get(r.cluster)));
    else clusters.set(r.cluster, r.episode);
  }
  const groups = [...new Set(rows.map((r) => root(r.episode)))];
  const split = (episode) => {
    const index = groups.indexOf(root(episode));
    return index < Math.ceil(groups.length * .8) ? 'train' : index < Math.ceil(groups.length * .9) ? 'val' : 'test';
  };
  const splits = {train: [], val: [], test: []}, labels = [], seen = new Set(), caps = new Map();
  for (const r of rows) {
    let filter = null;
    if (r.label !== 'good') filter = 'not_good';
    else if (seen.has(r.cluster)) filter = 'near_duplicate';
    else if ((caps.get(r.situation) || 0) >= cap) filter = 'situation_cap';
    if (!filter) {
      seen.add(r.cluster); caps.set(r.situation, (caps.get(r.situation) || 0) + 1);
      // Keep outcomes as recovery context; historical bad assistant replies are never targets.
      const messages = r.messages.filter((m) => m.role !== 'assistant').map(({role, content}) => ({role, content}));
      messages.push({role: 'assistant', content: r.reply});
      splits[split(r.episode)].push({messages});
    } else count(stats.dropped, filter);
    labels.push({id: hash([r.agent, r.t, r.messages, r.reply]), episode_id: r.episode, source: {line: r.line, agent: r.agent, t: r.t}, command: r.command, label: r.label, reason: r.reason, split: filter ? null : split(r.episode), filter, dedup_key: r.cluster});
  }
  stats.episodes = parent.size; stats.split_groups = groups.length;
  for (const [name, data] of Object.entries(splits)) { stats.splits[name] = data.length; stats.sft += data.length; }
  return {splits, labels, stats};
}

function main() {
  const {values, positionals} = parseArgs({allowPositionals: true, options: {events: {type: 'string'}, out: {type: 'string'}, cap: {type: 'string', default: '3'}}});
  if (positionals.length !== 1 || !values.out) throw new Error('Usage: dataset.js DECISIONS.jsonl --out NEW_DIRECTORY [--events EVENTS.json] [--cap 3]');
  const records = readLines(positionals[0]);
  const result = buildDataset(records, values.events ? readEvents(values.events) : [], {cap: Number(values.cap)});
  // Refuse replacement, including symlinks; artifacts contain private local training data.
  fs.mkdirSync(values.out, {mode: 0o700});
  const write = (name, text) => fs.writeFileSync(path.join(values.out, name), text, {mode: 0o600, flag: 'wx'});
  for (const [name, rows] of Object.entries(result.splits)) write(`${name}.jsonl`, rows.map((r) => JSON.stringify(r) + '\n').join(''));
  write('labels.jsonl', result.labels.map((r) => JSON.stringify(r) + '\n').join(''));
  write('stats.json', JSON.stringify(result.stats, null, 2) + '\n');
  console.log(JSON.stringify(result.stats, null, 2));
}
if (require.main === module) {
  try { main(); } catch { console.error('Dataset build failed: check input schema, episode/event IDs and output path (must be new).'); process.exitCode = 1; }
}
module.exports = {buildDataset, readLines, readEvents};
