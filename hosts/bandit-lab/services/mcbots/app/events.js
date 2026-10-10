'use strict';
// Bounded event log for the dashboard ("what happened?"): a ring buffer of the
// last MAX events with increasing ids, so a client asks for "everything after
// id N" and the buffer can never grow. Remote workers send theirs to the hub,
// which re-validates them with clean() before adding.
const MAX = 200;
const KINDS = new Set(['connect', 'disconnect', 'job', 'done', 'fail', 'stop', 'death', 'respawn', 'deposit', 'claim', 'hub', 'info', 'alert']);

class EventLog {
  constructor({max = MAX, now = Date.now, onAdd = null} = {}) {
    this.max = max;
    this.now = now;
    this.items = [];
    this.lastId = 0;
    this.onAdd = onAdd;
  }

  add(bot, kind, text) {
    const e = {id: ++this.lastId, t: this.now(), bot: String(bot).slice(0, 16), kind: KINDS.has(kind) ? kind : 'info', text: String(text).slice(0, 200)};
    this.items.push(e);
    if (this.items.length > this.max) this.items.splice(0, this.items.length - this.max);
    try { this.onAdd?.(e); } catch {}
    return e;
  }

  // Events with id > since, oldest first.
  since(since = 0) {
    return this.items.filter((e) => e.id > since);
  }
}

// A worker's event, as the hub accepts it: {bot, kind, text}, nothing else.
const clean = (e, names) => {
  if (!e || typeof e !== 'object' || !names.has(e.bot) || typeof e.text !== 'string') return null;
  return {bot: e.bot, kind: KINDS.has(e.kind) ? e.kind : 'info', text: e.text};
};

module.exports = {EventLog, clean, MAX, KINDS};
