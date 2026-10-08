'use strict';
// Environment -> validated config. Throws on anything unsafe.
const {NAME_RE} = require('./bots');

function loadConfig(env = process.env) {
  const list = (s) => (s || '').split(',').map((x) => x.trim()).filter(Boolean);
  const names = list(env.BOT_NAMES);
  if (!names.length) throw new Error('BOT_NAMES is required (comma list, e.g. bot1,bot2)');
  const bad = names.filter((n) => !NAME_RE.test(n));
  if (bad.length) throw new Error(`bot names must match ${NAME_RE}: ${bad.join(', ')}`);
  if (new Set(names).size !== names.length) throw new Error('duplicate bot name');
  const allowed = list(env.ALLOWED_TS_LOGINS);
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
  };
}

module.exports = {loadConfig};
