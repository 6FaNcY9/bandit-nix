'use strict';
// Environment -> validated config. Throws on anything unsafe.
const {NAME_RE} = require('./bots');
const {parseQuotas} = require('./keeper');

// Laptop runs have no BOT_PASSWORD_SEED: keep a random one in
// $XDG_STATE_HOME/mcbots/seed so a bot name keeps its VeloAuth password.
function localSeed(env) {
  const fs = require('node:fs');
  const path = require('node:path');
  const dir = path.join(env.XDG_STATE_HOME || path.join(env.HOME || '/nonexistent', '.local/state'), 'mcbots');
  try {
    return fs.readFileSync(path.join(dir, 'seed'), 'utf8').trim();
  } catch {}
  try {
    const seed = require('node:crypto').randomBytes(32).toString('hex');
    fs.mkdirSync(dir, {recursive: true, mode: 0o700});
    fs.writeFileSync(path.join(dir, 'seed'), seed, {mode: 0o600, flag: 'wx'});
    return seed;
  } catch {
    return null;
  }
}

function loadConfig(env = process.env) {
  const list = (s) => (s || '').split(',').map((x) => x.trim()).filter(Boolean);
  const names = list(env.BOT_NAMES);
  if (!names.length) throw new Error('BOT_NAMES is required (comma list, e.g. bot1,bot2)');
  const bad = names.filter((n) => !NAME_RE.test(n));
  if (bad.length) throw new Error(`bot names must match ${NAME_RE}: ${bad.join(', ')}`);
  if (new Set(names).size !== names.length) throw new Error('duplicate bot name');
  const allowed = list(env.ALLOWED_TS_LOGINS);
  // "x1,z1,x2,z2;..." boxes where bots never dig or place (player bases).
  const protectedAreas = (env.PROTECTED_AREAS || '').split(';').map((b) => b.trim()).filter(Boolean).map((b) => {
    const n = b.split(',').map(Number);
    if (n.length !== 4 || n.some((v) => !Number.isInteger(v))) throw new Error(`bad PROTECTED_AREAS box: ${b}`);
    return [Math.min(n[0], n[2]), Math.min(n[1], n[3]), Math.max(n[0], n[2]), Math.max(n[1], n[3])];
  });
  // Optional BlueMap webserver base URL for global player positions.
  const bluemapUrl = (env.BLUEMAP_URL || '').trim();
  if (bluemapUrl && !/^https?:\/\/[^\s/]+(:\d+)?(\/\S*)?$/.test(bluemapUrl)) throw new Error(`bad BLUEMAP_URL: ${bluemapUrl}`);
  // "x,y,z" of a chest bots re-equip from after dying (optional).
  let supplyChest = null;
  if (env.SUPPLY_CHEST) {
    const n = env.SUPPLY_CHEST.split(',').map(Number);
    if (n.length !== 3 || n.some((v) => !Number.isInteger(v))) throw new Error('SUPPLY_CHEST must be x,y,z');
    supplyChest = {x: n[0], y: n[1], z: n[2]};
  }
  // Standing orders (keeper.js): "logs:64,cobblestone:128,..." wanted in the supply
  // chest, and an optional "x,y,z" the bots walk to before they chop or mine.
  const keeperQuotas = parseQuotas(env.KEEPER_QUOTAS);
  let keeperSite = null;
  if (env.KEEPER_SITE) {
    const n = env.KEEPER_SITE.split(',').map(Number);
    if (n.length !== 3 || n.some((v) => !Number.isInteger(v))) throw new Error('KEEPER_SITE must be x,y,z');
    keeperSite = {x: n[0], y: n[1], z: n[2]};
  }
  const loginSeed = env.BOT_PASSWORD_SEED || localSeed(env);
  // Optional hub for remote workers (laptop bots): a second listener that only
  // accepts the WebSocket on /worker, guarded by a bearer token.
  const workerToken = readToken(env.WORKER_TOKEN, env.WORKER_TOKEN_FILE);
  const workerPort = env.WORKER_PORT ? Number(env.WORKER_PORT) : 0;
  if (!!workerToken !== !!workerPort) throw new Error('WORKER_PORT and WORKER_TOKEN (or WORKER_TOKEN_FILE) must be set together');
  if (workerPort && (!Number.isInteger(workerPort) || workerPort === Number(env.DASHBOARD_PORT || 8095))) throw new Error('WORKER_PORT must be a port other than the dashboard port');
  if (workerToken && !/^[\w-]{32,128}$/.test(workerToken)) throw new Error('worker token must be 32..128 characters of [A-Za-z0-9_-]');
  const host = env.DASHBOARD_HOST || '127.0.0.1';
  if (!allowed.length && host !== '127.0.0.1') {
    throw new Error('DASHBOARD_HOST other than 127.0.0.1 requires ALLOWED_TS_LOGINS');
  }
  return {
    names,
    mcHost: env.MC_HOST || 'localhost',
    mcPort: Number(env.MC_PORT || 25565),
    host,
    port: Number(env.DASHBOARD_PORT || 8095),
    allowed,
    protectedAreas,
    supplyChest,
    keeperQuotas,
    keeperSite,
    loginSeed,
    bluemapUrl: bluemapUrl.replace(/\/+$/, ''),
    workerToken,
    workerPort,
    workerHost: env.WORKER_HOST || '127.0.0.1',
    hostLabel: (env.HOST_LABEL || require('node:os').hostname()).slice(0, 40),
  };
}

function readToken(inline, file) {
  if (inline && inline.trim()) return inline.trim();
  if (!file) return '';
  try {
    return require('node:fs').readFileSync(file, 'utf8').trim();
  } catch (e) {
    throw new Error(`cannot read worker token file ${file}: ${e.code || e.message}`);
  }
}

// `mcbots-worker bot5 [bot6 ...]`: bots on this machine, driven by the hub.
function loadWorkerConfig(env = process.env, argv = []) {
  const flags = argv.filter((a) => a.startsWith('-'));
  const names = argv.filter((a) => !a.startsWith('-'));
  if (flags.length || !names.length) throw new Error('usage: mcbots-worker bot5 [bot6 ...]');
  const bad = names.filter((n) => !NAME_RE.test(n));
  if (bad.length) throw new Error(`bot names must match ${NAME_RE}: ${bad.join(', ')}`);
  if (new Set(names).size !== names.length) throw new Error('duplicate bot name');
  const hubUrl = (env.HUB_URL || '').trim();
  if (!/^wss:\/\/[\w.-]+(:\d+)?\/worker$/.test(hubUrl) && !/^ws:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/worker$/.test(hubUrl)) {
    throw new Error('HUB_URL must be wss://<host>[:port]/worker (plain ws:// only to localhost)');
  }
  const token = readToken(env.HUB_TOKEN, env.HUB_TOKEN_FILE);
  if (!token) throw new Error('no hub token: set HUB_TOKEN_FILE (sops secret mcbots-worker-token) or HUB_TOKEN');
  const mcPort = Number(env.MC_PORT || 25565);
  if (!env.MC_HOST) throw new Error('MC_HOST is required (the Velocity address bots join)');
  return {names, hubUrl, token, mcHost: env.MC_HOST, mcPort, loginSeed: env.BOT_PASSWORD_SEED || localSeed(env), hostLabel: (env.HOST_LABEL || require('node:os').hostname()).replace(/[^\w.-]/g, '-').slice(0, 40) || 'worker'};
}

module.exports = {loadConfig, loadWorkerConfig};
