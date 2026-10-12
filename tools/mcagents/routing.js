'use strict';
// Which model backends a caller may use (owner, 2026-10-11). The lab GPU (Ollama, 11434) and the gaming PC
// "slayer" serve the live agents and the solver; "albert" (ANDY_OFFLINE_NAMES) is reserved for the idle
// replay, the judge and training. The same ANDY_URLS / ANDY_BACKEND_NAMES lists feed both paths; this
// file splits them, and both paths refuse the other's backends.
const fs = require('node:fs');
const OLLAMA_PORT = '11434';

// Offline work only ever talks to a loopback llama-server port, never Ollama.
function backendBase(url) {
  const u = new URL(url);
  if (u.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(u.hostname) || u.port === OLLAMA_PORT || !u.port) throw new Error(`Refusing backend ${url}: only loopback llama-server ports, never Ollama (${OLLAMA_PORT})`);
  return `http://${u.host}`;
}

const list = (v) => String(v ?? '').split(',').map((s) => s.trim()).filter(Boolean);
const offlineNames = (env = process.env) => new Set(list(env.ANDY_OFFLINE_NAMES));

// [{name, url}] of the configured gaming PCs (not Ollama), in ANDY_URLS order.
function pcs(env = process.env) {
  const names = (env.ANDY_BACKEND_NAMES || '').split(',').map((s) => s.trim());
  return list(env.ANDY_URLS || env.ANDY_URL_2).map((url, i) => ({url, name: names[i] || new URL(url).host}));
}

// The backends of the offline path: only the ANDY_OFFLINE_NAMES ones (all PCs if none is named).
function offlineTargets(env = process.env) {
  const off = offlineNames(env);
  return pcs(env).filter((p) => !off.size || off.has(p.name)).map((p) => ({...p, url: backendBase(p.url)}));
}

// Batch work (replay, judge) leaves every PC alone while people play Minecraft: mcagents-players keeps
// BUSY_FILE while anyone but the bots is online (owner 2026-10-12: Minecraft on slayer stuttered under a
// replay pass). The live agents never look at it.
const peoplePlaying = (file = process.env.BUSY_FILE) => !!file && fs.existsSync(file);

module.exports = {OLLAMA_PORT, backendBase, offlineNames, offlineTargets, pcs, peoplePlaying};
