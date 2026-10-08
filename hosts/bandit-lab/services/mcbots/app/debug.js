'use strict';
// Per-bot debug trace for the dashboard panel and GET /api/debug: the last
// 30 s of positions, how often the server pulled the bot back ("forcedMove"),
// and when the last error happened. Paste /api/debug into a bug report.
const WINDOW_MS = 30000;
const SAMPLE_MS = 500;
const round = (n, d = 2) => (Number.isFinite(n) ? Math.round(n * 10 ** d) / 10 ** d : null);

class BotTrace {
  constructor(now = Date.now) {
    this.now = now;
    this.positions = []; // {t, x, y, z}
    this.corrections = []; // timestamps inside the window
    this.total = 0;
    this.lastCorrection = 0;
    this.error = null; // {message, t}
  }

  prune(t) {
    while (this.positions.length && t - this.positions[0].t > WINDOW_MS) this.positions.shift();
    while (this.corrections.length && t - this.corrections[0] > WINDOW_MS) this.corrections.shift();
  }

  sample(pos) {
    const t = this.now();
    if (pos) this.positions.push({t, x: pos.x, y: pos.y, z: pos.z});
    this.prune(t);
  }

  correction() {
    const t = this.now();
    this.total++;
    this.lastCorrection = t;
    this.corrections.push(t);
    this.prune(t);
  }

  setError(message) {
    this.error = message ? {message: String(message), t: this.now()} : null;
  }

  recentCorrections() {
    this.prune(this.now());
    return this.corrections.length;
  }

  snapshot() {
    const t = this.now();
    this.prune(t);
    const ago = (x) => round((t - x) / 1000, 1);
    return {
      positions: this.positions.map((p) => ({agoS: ago(p.t), x: round(p.x), y: round(p.y), z: round(p.z)})),
      corrections: {total: this.total, last30s: this.corrections.length, lastAgoS: this.lastCorrection ? ago(this.lastCorrection) : null},
      lastError: this.error && {message: this.error.message, agoS: ago(this.error.t)},
    };
  }
}

module.exports = {BotTrace, WINDOW_MS, SAMPLE_MS, round};
