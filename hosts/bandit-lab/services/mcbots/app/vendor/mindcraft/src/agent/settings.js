// Stand-in for upstream src/agent/settings.js (our own file): mcdata.js reads
// these only in initBot(), which we never call (see init() in mcdata.js).
export default {minecraft_version: null, host: null, port: null, auth: 'offline'};
