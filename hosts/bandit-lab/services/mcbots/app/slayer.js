'use strict';
// The owner's gaming PC ("slayer") runs llama-server (llama.cpp) for the agents when no game is
// running. This polls it through the lab tunnel (SLAYER_URL) and keeps the last answer for
// GET /api/slayer. Everything it reads is untrusted text from another machine: parsed
// defensively, clamped, never trusted for anything but display.
const {execFile} = require('node:child_process');

const DAY = 86400000;
const STATES = new Set(['serving', 'paused-game', 'offline']);
const STATUS_MAX = 4096;
const STATUS_STALE = 180000; // a status file older than this (3 missed writes) is ignored

// llama-server --metrics, Prometheus text: "llamacpp:name value" (labels tolerated). Missing or
// unparsable values are null. predicted_tokens_seconds is llama.cpp's average since it started.
function parseMetrics(text) {
  const out = {promptPerSec: null, predictedPerSec: null, processing: null, decodeTotal: null};
  const keys = {'llamacpp:prompt_tokens_seconds': 'promptPerSec', 'llamacpp:predicted_tokens_seconds': 'predictedPerSec', 'llamacpp:requests_processing': 'processing', 'llamacpp:n_decode_total': 'decodeTotal'};
  for (const line of String(text).slice(0, 65536).split('\n')) {
    const m = /^(llamacpp:\w+)(?:\{[^}]*\})?\s+(\S+)/.exec(line);
    const k = m && keys[m[1]];
    const v = m && Number(m[2]);
    if (k && Number.isFinite(v) && v >= 0) out[k] = v;
  }
  return out;
}

// The PC's status.json (or the command's stdout): {state, gpu:{util, vramUsedMB, vramTotalMB, tempC}}.
// Returns {state, gpu} or {error}; unknown keys are dropped, numbers must be finite and sane.
function parseStatus(text) {
  if (typeof text !== 'string' || Buffer.byteLength(text) > STATUS_MAX) return {error: 'status too long'};
  let j;
  try {
    j = JSON.parse(text.replace(/^\uFEFF/, '')); // PowerShell's Out-File writes a BOM
  } catch {
    return {error: 'status is not JSON'};
  }
  if (!j || typeof j !== 'object' || Array.isArray(j)) return {error: 'status is not an object'};
  if (j.state !== undefined && !STATES.has(j.state)) return {error: 'bad state'};
  let gpu = null;
  if (j.gpu !== undefined && j.gpu !== null) {
    const max = {util: 100, vramUsedMB: 1e6, vramTotalMB: 1e6, tempC: 150};
    gpu = {};
    for (const [k, hi] of Object.entries(max)) {
      const v = j.gpu[k];
      if (typeof v !== 'number' || !Number.isFinite(v) || v < 0 || v > hi) return {error: `bad gpu.${k}`};
      gpu[k] = Math.round(v);
    }
  }
  return {state: j.state || null, gpu};
}

// Decisions of the last 24 h per backend (missing field = the lab's own model).
// ponytail: the decisions log keeps 200 entries, so a busy day counts only the newest 200.
function countBackends(items, now = Date.now()) {
  const n = {lab: 0, slayer: 0};
  for (const e of items) if (now - e.t < DAY && (e.backend === undefined || Object.hasOwn(n, e.backend))) n[e.backend || 'lab']++;
  return n;
}

class Slayer {
  // url '' = off. cmd = fixed argv for the optional status command (no shell), or [].
  constructor({url, cmd = [], decisions, fetchFn = fetch, run = execFile, now = Date.now}) {
    Object.assign(this, {url, cmd, decisions, fetchFn, run, now});
    this.last = {online: false, busy: false, tokensPerSec: null, promptPerSec: null, t: 0};
    this.status = null; // {t, state, gpu}
    this.timers = [];
  }

  start() {
    if (!this.url) return;
    this.timers.push(setInterval(() => this.poll().catch(() => {}), 10000));
    if (this.cmd.length) this.timers.push(setInterval(() => this.pollStatusCmd().catch(() => {}), 60000));
    this.poll().catch(() => {});
    if (this.cmd.length) this.pollStatusCmd().catch(() => {});
  }

  stop() {
    for (const t of this.timers) clearInterval(t);
  }

  async get(path) {
    const r = await this.fetchFn(this.url + path, {signal: AbortSignal.timeout(2000)});
    return {ok: r.ok, text: (await r.text()).slice(0, 65536)};
  }

  async poll() {
    const last = {online: false, busy: false, tokensPerSec: null, promptPerSec: null, t: this.now()};
    try {
      last.online = (await this.get('/health')).ok;
    } catch {} // tunnel down or PC off
    if (last.online) {
      const [slots, metrics, st] = await Promise.all([this.get('/slots'), this.get('/metrics'), this.get('/status.json')].map((p) => p.catch(() => null)));
      let busy = false;
      try {
        busy = slots?.ok && JSON.parse(slots.text).some((s) => s && s.is_processing === true);
      } catch {} // /slots can be disabled or malformed
      const m = metrics?.ok ? parseMetrics(metrics.text) : null;
      last.busy = !!busy || (m?.processing ?? 0) > 0;
      last.tokensPerSec = m?.predictedPerSec ?? null;
      last.promptPerSec = m?.promptPerSec ?? null;
      const s = st?.ok ? parseStatus(st.text) : null;
      if (s && !s.error) this.status = {...s, t: last.t};
    }
    this.last = last;
  }

  pollStatusCmd() {
    return new Promise((resolve) => {
      this.run(this.cmd[0], this.cmd.slice(1), {timeout: 5000, maxBuffer: STATUS_MAX, windowsHide: true}, (err, stdout) => {
        const s = err ? null : parseStatus(String(stdout));
        if (s && !s.error) this.status = {...s, t: this.now()};
        resolve();
      });
    });
  }

  view() {
    const now = this.now();
    const fresh = this.status && now - this.status.t < STATUS_STALE ? this.status : null;
    const {online} = this.last;
    const d = countBackends(this.decisions.items, now);
    return {
      enabled: !!this.url,
      online,
      busy: online && this.last.busy,
      tokensPerSec: online ? this.last.tokensPerSec : null,
      promptPerSec: online ? this.last.promptPerSec : null,
      requestsToday: d.slayer,
      decisions: d,
      gpu: fresh?.gpu || null,
      state: online ? 'serving' : fresh?.state === 'paused-game' ? 'paused-game' : 'offline',
      t: this.last.t,
    };
  }
}

// SLAYER_STATUS_CMD is a JSON array (the fixed argv), e.g. ["ssh","slayer","type","C:\\bandit-ai\\status.json"].
function parseCmd(s) {
  if (!s) return [];
  let a;
  try {
    a = JSON.parse(s);
  } catch {}
  if (!Array.isArray(a) || !a.length || a.length > 16 || a.some((x) => typeof x !== 'string' || !x || x.length > 200)) throw new Error('SLAYER_STATUS_CMD must be a JSON array of 1..16 non-empty strings');
  return a;
}

module.exports = {Slayer, parseMetrics, parseStatus, countBackends, parseCmd};
