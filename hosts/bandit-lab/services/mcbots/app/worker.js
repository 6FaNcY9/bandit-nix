#!/usr/bin/env node
'use strict';
// `mcbots-worker bot5`: run bots on this machine under the lab hub.
// Needs HUB_URL, HUB_TOKEN_FILE and MC_HOST (the nix wrapper sets them).
const {loadWorkerConfig} = require('./config');
const {HubClient} = require('./hubclient');

let cfg;
try {
  cfg = loadWorkerConfig(process.env, process.argv.slice(2));
} catch (e) {
  console.error(`mcbots-worker: ${e.message}`);
  process.exit(2);
}
const log = (who, msg) => console.log(`${new Date().toISOString()} [${who}] ${msg}`);
const client = new HubClient({url: cfg.hubUrl, token: cfg.token, names: cfg.names, mcHost: cfg.mcHost, mcPort: cfg.mcPort, loginSeed: cfg.loginSeed, hostLabel: cfg.hostLabel, log});
client.start();

let closing = false;
function shutdown() {
  if (closing) return;
  closing = true;
  client.stop();
  setTimeout(() => process.exit(0), 800);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
