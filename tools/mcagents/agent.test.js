'use strict';
// node tools/mcagents/agent.test.js — the Mindcraft command translator.
const assert = require('node:assert');
const {parseCommand, translate, commandDocs, inventoryText, repeatHint} = require('./agent');

assert.deepStrictEqual(parseCommand('Sure! !collectBlocks("oak_log", 10)'), {name: 'collectBlocks', args: ['oak_log', 10]});
assert.deepStrictEqual(parseCommand("Bye! !endConversation('john')"), {name: 'endConversation', args: ['john']});
assert.deepStrictEqual(parseCommand('<think>maybe !stop</think>Let me look. !inventory'), {name: 'inventory', args: []}, 'thinking is ignored');
assert.strictEqual(parseCommand('hello there'), null);

const ctx = {pos: [1, 64, 2], supplyChest: {x: 5, y: 64, z: 5}, places: {base: {x: 9, y: 70, z: 9}}};
const tr = (s) => translate(parseCommand(s), ctx);
assert.deepStrictEqual(tr('!collectBlocks("oak_log", 10)'), {job: ['chop', {count: 10}]});
assert.deepStrictEqual(tr('!collectBlocks("cobblestone", 8)'), {job: ['mine', {block: 'stone', count: 8}]});
assert.deepStrictEqual(tr('!collectBlocks("iron_ore", 5)'), {job: ['mine', {block: 'iron_ore', count: 5}]});
assert.deepStrictEqual(tr('!putInChest("raw_iron", 5)'), {job: ['deposit', {x: 5, y: 64, z: 5, only: 'raw_iron'}]});
assert.deepStrictEqual(tr('!takeFromChest("coal", 3)'), {job: ['withdraw', {x: 5, y: 64, z: 5, item: 'coal', count: 3}]});
assert.deepStrictEqual(tr('!goToRememberedPlace("base")'), {job: ['goto', {x: 9, y: 70, z: 9}]});
assert.deepStrictEqual(tr('!craftRecipe("stick", 4)'), {job: ['craft', {item: 'stick', count: 4}]});
assert.deepStrictEqual(tr('!stop'), {job: ['stop', {}]});
assert.ok(tr('!newAction("build a house")').refuse, 'code writing is refused');
assert.ok(tr('!attackPlayer("steve")').refuse, 'unknown commands are refused');
assert.ok(translate(parseCommand('!putInChest("dirt", 1)'), {pos: null, supplyChest: null}).refuse);
assert.strictEqual(tr('!inventory').query, 'inventory');
assert.strictEqual(tr('!buildBlueprint("test-pad-3x3", 1, 64, 2)').local, 'buildBlueprint');
assert.ok(commandDocs(['test-pad-3x3']).includes('!collectBlocks: Collect the nearest blocks'));
assert.ok(!commandDocs().includes('!newAction'), 'code writing is not offered');
assert.strictEqual(inventoryText({inventory: ['cobblestone x12', 'oak_log x3']}), 'INVENTORY\n- cobblestone: 12\n- oak_log: 3\n');
assert.match(repeatHint('!buildBlueprint("test-pad-3x3", -95, 66, -15)'), /failed twice.*Do not repeat it/);
console.log('ok');
