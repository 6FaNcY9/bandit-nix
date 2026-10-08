'use strict';
// Minimal self-check: config validation + job argument validation.
const assert = require('node:assert');
const {loadConfig} = require('./config');
const {VALIDATE} = require('./bots');
assert.deepStrictEqual(loadConfig({BOT_NAMES: 'bot1, bot22'}).names, ['bot1', 'bot22']);
for (const bad of ['bot', 'bot100', 'Bot1', 'steve', 'bot1,x']) assert.throws(() => loadConfig({BOT_NAMES: bad}), bad);
assert.throws(() => loadConfig({BOT_NAMES: 'bot1', DASHBOARD_HOST: '0.0.0.0'}));
assert.ok(loadConfig({BOT_NAMES: 'bot1', DASHBOARD_HOST: '0.0.0.0', ALLOWED_TS_LOGINS: 'a@github'}).allowed.length);
assert.deepStrictEqual(VALIDATE.goto({x: '1', y: 64, z: -3}), {x: 1, y: 64, z: -3});
assert.throws(() => VALIDATE.goto({x: 'a', y: 1, z: 1}));
assert.throws(() => VALIDATE.say({text: '/op me'}));
assert.throws(() => VALIDATE.mine({block: 'Iron Ore'}));
console.log('ok');
