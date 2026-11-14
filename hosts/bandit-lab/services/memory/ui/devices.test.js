// node --test hosts/bandit-lab/services/memory/ui/devices.test.js
const test = require('node:test');
const assert = require('node:assert');
const {devicesHtml} = require('./devices.js');

const list = [
  {host: 'albert', kind: 'pc', online: true, state: 'idle', job: 'ollama', last_seen: '2026-11-13T12:00:00Z'},
  {host: 'pong', kind: 'phone', online: false, state: null, job: null, last_seen: null},
];

test('one row per device with German state and the job', () => {
  const h = devicesHtml(list);
  assert.equal((h.match(/<tr class="dev/g) || []).length, 2);
  assert.match(h, /albert[\s\S]*frei[\s\S]*ollama/);
});

test('offline devices say offline and never seen', () => {
  const h = devicesHtml(list);
  assert.match(h, /pong[\s\S]*offline[\s\S]*nie/);
});

test('host names are escaped', () => {
  const h = devicesHtml([{host: '<img src=x onerror=alert(1)>', kind: 'pc', online: true, state: 'heavy'}]);
  assert.ok(!h.includes('<img'));
  assert.match(h, /&lt;img/);
});

test('an error or empty answer is said plainly', () => {
  assert.match(devicesHtml(null), /nicht erreichbar/);
  assert.match(devicesHtml([]), /Keine Geräte/);
});
