// node --test hosts/bandit-lab/services/memory/ui/views.test.js
const test = require('node:test');
const assert = require('node:assert');
const {searchNotes, highlight, recentActivity, repoName, projectGraph, layout} = require('./views.js');

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
const note = (path, body, extra = {}) => ({path, title: path.replace(/\.md$/, '').split('/').pop(), body, changed: '2026-11-15T10:00:00Z', links: [], ...extra});

test('search needs every word, ranks title hits first, then newest', () => {
  const notes = [
    note('sessions/a.md', 'we fixed the wayvnc tunnel', {changed: '2026-11-15T12:00:00Z'}),
    note('projects/wayvnc.md', 'tunnel notes'),
    note('projects/other.md', 'only wayvnc here'),
  ];
  assert.deepStrictEqual(searchNotes(notes, 'WayVNC tunnel').map((h) => h.n.path), ['projects/wayvnc.md', 'sessions/a.md']);
  assert.deepStrictEqual(searchNotes(notes, '  '), []);
  assert.match(searchNotes(notes, 'fixed')[0].snippet, /^we fixed the wayvnc tunnel$/);
});

test('highlight escapes note text and never splits an entity', () => {
  assert.strictEqual(highlight('a <b>&amp</b>', 'amp', esc), 'a &lt;b&gt;&amp;<mark>amp</mark>&lt;/b&gt;');
  assert.strictEqual(highlight('x.y', '.', esc), 'x<mark>.</mark>y');
  assert.strictEqual(highlight('<i>', '', esc), '&lt;i&gt;');
});

test('recent activity: last two days, newest first, lagebild left out', () => {
  const now = Date.parse('2026-11-15T20:00:00Z');
  const notes = [
    note('old.md', '', {changed: '2026-11-13T19:59:00Z'}),
    note('new.md', '', {changed: '2026-11-15T19:00:00Z'}),
    note('lagebild.md', '', {changed: '2026-11-15T19:55:00Z'}),
    note('mid.md', '', {changed: '2026-11-14T08:00:00Z'}),
  ];
  assert.deepStrictEqual(recentActivity(notes, now).map((n) => n.path), ['new.md', 'mid.md']);
});

test('repo names from the repo: field', () => {
  assert.strictEqual(repoName('github:6FaNcY9/bandit-nix'), 'bandit-nix');
  assert.strictEqual(repoName('bandit-craft (branch feat/highway-bots)'), 'bandit-craft');
  assert.strictEqual(repoName('~/src/mrija-archive, ~/src/x'), 'mrija-archive');
  assert.strictEqual(repoName('"-"'), '');
  assert.strictEqual(repoName('none yet, planned'), '');
  assert.strictEqual(repoName(undefined), '');
});

test('graph: links, shared repo named like a project, shared link target as hub', () => {
  const p = (name, repo, links = []) => ({name, note: {repo, links}});
  const projects = [
    p('bandit-craft', 'github:o/bandit-craft', ['bandit lab']),
    p('highway', 'bandit-craft (branch x)', ['bandit-craft']),
    p('bot-menus', 'bandit-craft'),
    p('lab-net', 'bandit-nix', ['bandit lab', 'archiv/lab-net', 'firma:projects/aiia']),
    p('alone', '-', ['nowhere']),
    p('imported', '-', ['claude-mem src', 'bandit lab']),
  ];
  const resolve = (l) => (projects.some((x) => x.name === l) ? l : l === 'claude-mem src' ? false : null);
  const {nodes, edges} = projectGraph(projects, resolve);
  const has = (a, b) => edges.some((e) => (e[0] === a && e[1] === b) || (e[0] === b && e[1] === a));
  assert.ok(has('highway', 'bandit-craft') && has('bot-menus', 'bandit-craft'));
  assert.strictEqual(edges.filter((e) => e.includes('highway') && e.includes('bandit-craft')).length, 1, 'no double line');
  assert.ok(has('bandit-craft', '#bandit lab') && has('lab-net', '#bandit lab'));
  assert.deepStrictEqual(nodes.filter((n) => n.hub).map((n) => n.hub), ['bandit lab'], 'single-member groups make no hub');
  assert.ok(!edges.some((e) => e.includes('alone')));
  assert.ok(!nodes.some((n) => n.hub === 'claude-mem src'), 'ignored links make no hub');
});

test('layout is finite, repeatable and pulls linked dots together', () => {
  const mk = () => ['a', 'b', 'c', 'd', 'e', 'f'].map((id) => ({id}));
  const edges = [['a', 'b'], ['c', 'd']];
  const one = layout(mk(), edges), two = layout(mk(), edges);
  assert.deepStrictEqual(one, two);
  assert.ok(one.every((n) => Number.isFinite(n.x) && Number.isFinite(n.y)));
  const at = Object.fromEntries(one.map((n) => [n.id, n])), dist = (a, b) => Math.hypot(at[a].x - at[b].x, at[a].y - at[b].y);
  assert.ok(dist('a', 'b') < dist('a', 'e') && dist('c', 'd') < dist('c', 'f'));
});
