'use strict';
// Server administration for the owner's dashboard: a minimal RCON client (Source RCON, as Minecraft
// implements it) and the validated admin actions built on it. Human path only: agentauth's allowlist
// never lists /api/admin/*. RCON is reached over the internal `minecraft` Docker network, never published.
const net = require('node:net');

const NAME_RE = /^[A-Za-z0-9_]{1,16}$/;
const T_AUTH = 3, T_CMD = 2, T_PROBE = 100;

// [len][id][type][body]\0\0 - len counts everything after itself.
function encode(id, type, body) {
  const b = Buffer.from(body, 'utf8');
  const out = Buffer.alloc(14 + b.length);
  out.writeInt32LE(10 + b.length, 0);
  out.writeInt32LE(id, 4);
  out.writeInt32LE(type, 8);
  b.copy(out, 12);
  return out;
}

// Whole packets from the front of buf, and the rest.
function decode(buf) {
  const packets = [];
  let o = 0;
  while (buf.length - o >= 4) {
    const len = buf.readInt32LE(o);
    if (len < 10 || len > 8192) throw new Error('bad RCON packet length');
    if (buf.length - o < 4 + len) break;
    packets.push({id: buf.readInt32LE(o + 4), type: buf.readInt32LE(o + 8), body: buf.toString('utf8', o + 12, o + 4 + len - 2)});
    o += 4 + len;
  }
  return {packets, rest: buf.subarray(o)};
}

// One connection: authenticate, run the commands in order, return the replies. A reply can span several
// packets, so each command is followed by an unknown-type probe: the server answers it after the reply.
function rcon({host, port, password, timeoutMs = 5000}, commands) {
  return new Promise((resolve, reject) => {
    const sock = net.connect({host, port});
    let buf = Buffer.alloc(0), step = -1, text = '', id = 1;
    const replies = [];
    const done = (err) => {
      clearTimeout(timer);
      sock.destroy();
      err ? reject(err) : resolve(replies);
    };
    const timer = setTimeout(() => done(new Error('RCON timed out')), timeoutMs);
    const next = () => {
      step++;
      if (step >= commands.length) return done();
      text = '';
      id += 2;
      sock.write(Buffer.concat([encode(id, T_CMD, commands[step]), encode(id + 1, T_PROBE, '')]));
    };
    sock.on('connect', () => sock.write(encode(1, T_AUTH, password)));
    sock.on('error', (e) => done(new Error(`RCON: ${e.code || e.message}`)));
    sock.on('close', () => done(new Error('RCON closed the connection')));
    sock.on('data', (d) => {
      try {
        const r = decode(Buffer.concat([buf, d]));
        buf = r.rest;
        for (const p of r.packets) {
          if (step === -1) {
            if (p.id === -1) return done(new Error('RCON refused the password'));
            if (p.type === T_CMD) next();
          } else if (p.id === id) text += p.body;
          else if (p.id === id + 1) {
            replies.push(text);
            next();
          }
        }
      } catch (e) {
        done(e);
      }
    });
  });
}

// RCON calls one after another: the server takes few connections, and a chain keeps replies apart.
function queued(opts) {
  let tail = Promise.resolve();
  return (commands) => {
    const run = tail.then(() => rcon(opts, commands));
    tail = run.catch(() => {});
    return run;
  };
}

const clean = (s) => String(s).replace(/§./g, '').replace(/\x1b\[[0-9;]*m/g, '').trim();
const noControl = (s) => !/[\x00-\x1f\x7f]/.test(s);
function name(n) {
  if (typeof n !== 'string' || !NAME_RE.test(n)) throw new Error('name must be 1-16 letters, digits or underscores');
  return n;
}
function text(s, max, what) {
  if (typeof s !== 'string' || !s.trim() || s.length > max || !noControl(s)) throw new Error(`${what} must be 1-${max} characters on one line`);
  return s.trim();
}

// The command for an admin action, or throws. `minecraft:` prefixes keep a plugin's own /ban or /op out of it.
function build(action, b = {}) {
  const reason = () => (b.reason === undefined || b.reason === '' ? '' : ` ${text(b.reason, 100, 'reason')}`);
  switch (action) {
    case 'kick': return `minecraft:kick ${name(b.name)}${reason()}`;
    case 'ban': return `minecraft:ban ${name(b.name)}${reason()}`;
    case 'unban': return `minecraft:pardon ${name(b.name)}`;
    case 'whitelist-add': return `minecraft:whitelist add ${name(b.name)}`;
    case 'whitelist-remove': return `minecraft:whitelist remove ${name(b.name)}`;
    case 'op': return `minecraft:op ${name(b.name)}`;
    case 'deop': return `minecraft:deop ${name(b.name)}`;
    case 'time': if (b.value !== 'day' && b.value !== 'night') throw new Error('value must be day or night'); return `minecraft:time set ${b.value}`;
    case 'weather-clear': return 'minecraft:weather clear';
    case 'save': return 'minecraft:save-all flush';
    case 'command': return text(b.cmd, 200, 'command').replace(/^\/+/, '');
    default: throw new Error('unknown action');
  }
}

const QUERIES = {plugins: 'plugins', whitelist: 'minecraft:whitelist list', bans: 'minecraft:banlist players', imageframe: 'imageframe list'};
const afterColon = (t) => (t.includes(':') ? t.slice(t.indexOf(':') + 1) : '').split(',').map((s) => s.trim()).filter((s) => NAME_RE.test(s));
const parse = {
  players: (t) => afterColon(clean(t)),
  whitelist: (t) => afterColon(clean(t)),
  bans: (t) => [...clean(t).matchAll(/^(\S+) was banned/gm)].map((m) => m[1]),
  tps: (t) => {
    const c = clean(t), m = /TPS from last[^:]*:\s*([^\n]+)/i.exec(c), mem = /Memory Usage:\s*([\d,.]+)\s*\/\s*([\d,.]+)\s*mb/i.exec(c);
    return {tps: m ? m[1].match(/\d+(?:\.\d+)?/g)?.map(Number) || [] : [], memUsedMb: mem ? Number(mem[1].replace(/,/g, '')) : null, memTotalMb: mem ? Number(mem[2].replace(/,/g, '')) : null, raw: c.slice(0, 600)};
  },
};

const SCHEDULE = [[0, 60], [30000, 30], [50000, 10]]; // [ms after the request, seconds left]

class Admin {
  // call(commands[]) -> Promise<replies[]>; botNames: names to mark as bots; events: the dashboard's EventLog.
  constructor({call, events, botNames = [], setTimer = setTimeout, clearTimer = clearTimeout}) {
    this.call = call;
    this.events = events;
    this.botNames = new Set(botNames);
    this.setTimer = setTimer;
    this.clearTimer = clearTimer;
    this.console = []; // {id, t, cmd, reply}, newest last
    this.nextId = 0;
    this.timers = null;
    this.restartAt = 0;
  }

  isBot(n) { return this.botNames.has(n) || /^bot\d{1,3}$/.test(n); }

  record(cmd, reply) {
    this.console.push({id: ++this.nextId, t: Date.now(), cmd, reply: clean(reply).slice(0, 4000)});
    if (this.console.length > 100) this.console.shift();
  }

  async run(cmd) {
    const [reply] = await this.call([cmd]);
    this.record(cmd, reply);
    return clean(reply);
  }

  async status() {
    const [list, tps, mspt] = await this.call(['minecraft:list', 'tps', 'mspt']);
    return {players: parse.players(list).map((n) => ({name: n, bot: this.isBot(n)})), listText: clean(list), ...parse.tps(tps), mspt: clean(mspt).slice(0, 400), restartAt: this.restartAt || null};
  }

  async query(what) {
    if (!QUERIES[what]) throw new Error('what must be one of ' + Object.keys(QUERIES).join(', '));
    const t = clean((await this.call([QUERIES[what]]))[0]);
    return {what, names: what === 'whitelist' ? parse.whitelist(t) : what === 'bans' ? parse.bans(t) : undefined, text: t.slice(0, 4000)};
  }

  consoleSince(since = 0) { return {lastId: this.nextId, entries: this.console.filter((e) => e.id > since)}; }

  async act(action, b = {}) {
    if (action === 'restart') return this.restart();
    if (action === 'restart-cancel') return this.cancelRestart();
    const cmd = build(action, b);
    const reply = await this.run(cmd);
    this.events.add('admin', 'info', `admin: ${action}${b.name ? ' ' + b.name : ''}${action === 'command' ? ' ' + cmd.slice(0, 80) : ''}${b.reason ? ' (' + String(b.reason).slice(0, 40) + ')' : ''}`);
    return {ok: true, reply};
  }

  // Warn 60/30/10 s ahead, save, stop. docker-minecraft has Restart=always, so `stop` is a restart.
  restart() {
    if (this.timers) throw new Error('a restart is already counting down');
    this.restartAt = Date.now() + 60000;
    const say = (s) => this.call([`minecraft:say Server restarting in ${s} seconds`]).catch(() => {});
    this.timers = SCHEDULE.map(([ms, s]) => this.setTimer(() => say(s), ms));
    this.timers.push(this.setTimer(async () => {
      this.timers = null;
      this.restartAt = 0;
      try {
        await this.call(['minecraft:save-all flush']);
        await this.call(['minecraft:stop']).catch(() => {}); // the connection may drop with the server
        this.events.add('admin', 'info', 'admin: server stopped for restart');
      } catch (e) {
        this.events.add('admin', 'fail', `admin: restart failed (${e.message})`);
      }
    }, 60000));
    this.events.add('admin', 'info', 'admin: restart in 60 s (warnings at 60/30/10)');
    return {ok: true, restartAt: this.restartAt};
  }

  cancelRestart() {
    if (!this.timers) throw new Error('no restart is counting down');
    for (const t of this.timers) this.clearTimer(t);
    this.timers = null;
    this.restartAt = 0;
    this.call(['minecraft:say Restart cancelled']).catch(() => {});
    this.events.add('admin', 'info', 'admin: restart cancelled');
    return {ok: true};
  }
}

module.exports = {encode, decode, rcon, queued, Admin, build, parse, clean, NAME_RE};
