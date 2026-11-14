// node --test hosts/bandit-lab/services/memory/ui/stores.test.js
const test = require('node:test');
const assert = require('node:assert');
const {storeLinks, wikiLinks, switcherHtml} = require('./stores.js');

test('a cross-store link opens that store\'s note', () => {
  assert.equal(storeLinks('see [[firma:projects/aiia]]'),
    'see <a href="https://memory-firma.tail7facc9.ts.net/notes/projects/aiia.md">firma:projects/aiia</a>');
  assert.match(storeLinks('[[vino:a/b.md]]'), /href="https:\/\/memory\.tail7facc9\.ts\.net\/notes\/a\/b\.md"/);
});

test('plain wiki links and unknown stores are left alone', () => {
  assert.equal(storeLinks('[[projects/aiia]] [[other:x]]'), '[[projects/aiia]] [[other:x]]');
});

test('the switcher marks the current store', () => {
  const h = switcherHtml('memory-albert.tail7facc9.ts.net');
  assert.equal((h.match(/<a /g) || []).length, 3);
  assert.match(h, /aria-current="page">albert/);
  assert.ok(!switcherHtml('example.org').includes('aria-current'));
});

test('a store link nested in a wiki link cannot smuggle attributes', () => {
  const out = wikiLinks(storeLinks('[[x [[firma:a onmouseover=alert(1) b]] y]]'));
  assert.ok(!out.includes('<button'));
  assert.equal(wikiLinks('[[projects/aiia]]'), '<button class="link" data-open="projects/aiia">projects/aiia</button>');
});
