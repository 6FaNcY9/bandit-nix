// Logic of the page's Suche, Heute and Karte views (services/memory), kept apart from the DOM so node --test can check it.
// Notes are {path, title, slug, type, body, changed, links, repo} as index.html parses them.
(function (root) {
  const words = (query) => String(query).toLowerCase().split(/\s+/).filter(Boolean);
  const reEsc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  // Every word must be in the title, path or text; title/path hits first, then the newest.
  function searchNotes(notes, query, limit = 30) {
    const ws = words(query);
    if (!ws.length) return [];
    const hits = [];
    for (const n of notes) {
      const head = (n.title + ' ' + n.path).toLowerCase(), body = n.body.toLowerCase();
      if (!ws.every((w) => head.includes(w) || body.includes(w))) continue;
      const first = ws.map((w) => body.indexOf(w)).filter((i) => i >= 0).sort((a, b) => a - b)[0];
      hits.push({n, score: ws.filter((w) => head.includes(w)).length, snippet: first === undefined ? '' : snippetAt(n.body, first)});
    }
    return hits.sort((a, b) => b.score - a.score || b.n.changed.localeCompare(a.n.changed)).slice(0, limit);
  }
  function snippetAt(text, i) {
    const s = Math.max(0, i - 60), e = Math.min(text.length, i + 120);
    return (s ? '…' : '') + text.slice(s, e).replace(/\s+/g, ' ').trim() + (e < text.length ? '…' : '');
  }
  // Escapes the text and marks the query words; matches are cut out before escaping, so marks never split an entity.
  function highlight(text, query, esc) {
    const ws = words(query);
    if (!ws.length) return esc(text);
    return String(text).split(new RegExp('(' + ws.map(reEsc).join('|') + ')', 'gi'))
      .map((part, i) => (i % 2 ? '<mark>' + esc(part) + '</mark>' : esc(part))).join('');
  }

  // Heute: notes changed in the last `days` days, newest first (the generated lagebild left out).
  function recentActivity(notes, now, days = 2, limit = 12) {
    const since = now - days * 864e5;
    return notes.filter((n) => n.path !== 'lagebild.md' && Date.parse(n.changed) >= since)
      .sort((a, b) => Date.parse(b.changed) - Date.parse(a.changed)).slice(0, limit);
  }

  // "github:owner/bandit-nix", "~/src/mrija-archive, …", "bandit-craft (branch x)" -> the repo's own name; "-"/"none" -> ''.
  function repoName(repo) {
    const first = String(repo || '').trim().replace(/^["']|["']$/g, '').split(/[\s,;]/)[0];
    const name = first.split(/[/:]/).pop();
    return !name || name === '-' || /^none$/i.test(name) ? '' : name;
  }

  // Karte: one dot per project. Lines join a project to another it links to; projects sharing a repo or a link target
  // join that project (when the repo is named like one) or a grey hub dot.
  // resolve(link): a project name; null for any other target (shared ones become hubs); false to ignore the link.
  function projectGraph(projects, resolve) {
    const names = new Set(projects.map((p) => p.name)), edges = [], seen = new Set(), groups = {};
    const edge = (a, b) => {
      const k = [a, b].sort().join('\n');
      if (a !== b && !seen.has(k)) { seen.add(k); edges.push([a, b]); }
    };
    for (const p of projects) {
      const repo = repoName(p.note && p.note.repo);
      if (repo) (groups[repo] ||= new Set()).add(p.name);
      for (const link of (p.note && p.note.links) || []) {
        if (/^archiv\/|^[a-z]+:/.test(link)) continue; // own archive and other stores' notes say nothing about belonging
        const target = resolve(link);
        if (target && names.has(target)) edge(p.name, target);
        else if (target === null) (groups[link] ||= new Set()).add(p.name);
      }
    }
    const nodes = projects.map((p) => ({id: p.name, p}));
    for (const [hub, members] of Object.entries(groups)) {
      if (names.has(hub)) { for (const m of members) edge(m, hub); continue; }
      if (members.size < 2) continue;
      nodes.push({id: '#' + hub, hub});
      for (const m of members) edge(m, '#' + hub);
    }
    return {nodes, edges};
  }

  // Small force layout from a fixed start, so the same notes always give the same map:
  // dots push each other away, lines pull their ends together, a weak pull keeps everything near the middle.
  // aspect = screen width / height: a tall phone screen pulls harder sideways, so the map comes out tall too.
  // Defaults tuned on the real 20 projects (2026-11-15): no label overlaps on a laptop screen.
  function layout(nodes, edges, {iters = 400, push = 400000, len = 260, pull = 0.01, wide = 2.5, aspect = 1} = {}) {
    const at = new Map(nodes.map((n, i) => {
      const a = 2 * Math.PI * i / nodes.length;
      Object.assign(n, {x: 400 * Math.cos(a), y: 400 * Math.sin(a)});
      return [n.id, n];
    }));
    for (let it = 0; it < iters; it++) {
      for (const n of nodes) { n.dx = -pull * n.x / Math.sqrt(aspect); n.dy = -pull * n.y * Math.sqrt(aspect); }
      for (let i = 0; i < nodes.length; i++) for (let j = i + 1; j < nodes.length; j++) {
        // wide > 1 counts side-by-side dots as closer: labels sit under the dots and are wider than tall
        const a = nodes[i], b = nodes[j], dx = a.x - b.x, dy = a.y - b.y, d = Math.max(Math.hypot(dx / wide, dy), 10), f = push / (d * d * d);
        a.dx += dx * f; a.dy += dy * f; b.dx -= dx * f; b.dy -= dy * f;
      }
      for (const [s, t] of edges) {
        const a = at.get(s), b = at.get(t), dx = b.x - a.x, dy = b.y - a.y, d = Math.hypot(dx, dy) || 1, f = 0.06 * (d - len) / d;
        a.dx += dx * f; a.dy += dy * f; b.dx -= dx * f; b.dy -= dy * f;
      }
      const cap = 1 + 40 * (1 - it / iters); // steps shrink, so the dots settle
      for (const n of nodes) {
        const m = Math.hypot(n.dx, n.dy) || 1, k = Math.min(m, cap) / m;
        n.x += n.dx * k; n.y += n.dy * k;
      }
    }
    for (const n of nodes) { delete n.dx; delete n.dy; }
    return nodes;
  }

  const api = {searchNotes, highlight, recentActivity, repoName, projectGraph, layout};
  if (typeof module !== 'undefined') module.exports = api;
  else Object.assign(root, api);
})(typeof window !== 'undefined' ? window : globalThis);
