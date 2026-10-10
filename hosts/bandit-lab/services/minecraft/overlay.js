// BlueMap webapp script (staged to bluemap/web/mcbots/overlay.js, registered in webapp.conf `scripts`).
// Draws what the bots' block log (mcbots/app/blocklog.js, exported every 15 s as mcbots/changes.json and
// zones.json next to this file) says: built blocks green, removed blocks red, zone outlines and a y label
// every 8 blocks along the shaft. Uses the webapp API as of BlueMap 5.x (window.BlueMap = the webapp's exports,
// window.bluemap.mapViewer.markers = the root scene; see common/webapp/src/js/BlueMap.js in the BlueMap repo).
// If any of that is missing it logs a warning and does nothing.
(function () {
 try {
  const warn = (m) => console.warn('[mcbots overlay] ' + m);
  const BM = window.BlueMap, viewer = window.bluemap && window.bluemap.mapViewer;
  if (!BM || !BM.Three || !BM.CSS2DObject || !viewer || !viewer.markers) return warn('BlueMap webapp API not found, overlay disabled');
  const T = BM.Three, EVERY = 15000, COLOR = {storage: 0xe0a030, shaft: 0x40c0ff, treefarm: 0x40d060, wheat: 0xe8d040, base: 0xffffff, protected: 0xff4060};
  const root = new T.Group(); // a plain group: BlueMap's marker manager only prunes MarkerSets it knows
  root.name = 'mcbots-overlay';
  viewer.markers.add(root);
  let data = {changes: []}, zones = [], windowMs = 3600e3, shown = true, blocks = null, outlines = [];

  const label = (text, x, y, z, color) => {
    const d = document.createElement('div');
    d.textContent = text;
    d.style.cssText = 'font:11px sans-serif;color:' + color + ';text-shadow:0 0 3px #000,0 0 3px #000;pointer-events:none;white-space:nowrap';
    const o = new BM.CSS2DObject(d);
    o.position.set(x, y, z);
    return o;
  };
  const clear = (list) => { for (const o of list.splice(0)) { root.remove(o); o.geometry && o.geometry.dispose(); o.material && o.material.dispose(); } };

  function drawChanges() {
    if (blocks) { root.remove(blocks); blocks.geometry.dispose(); blocks.material.dispose(); blocks = null; }
    const now = Date.now(), list = data.changes.filter((c) => now - c.t <= windowMs);
    info.textContent = list.length + ' changes';
    if (!list.length) return;
    // one instanced mesh per colour via per-instance colour, slightly larger than a block so it shows over the terrain
    blocks = new T.InstancedMesh(new T.BoxGeometry(1.04, 1.04, 1.04), new T.MeshBasicMaterial({transparent: true, opacity: 0.55, depthWrite: false}), list.length);
    blocks.frustumCulled = false;
    const m = new T.Matrix4(), g = new T.Color(0x22dd44), r = new T.Color(0xee3030);
    list.forEach((c, i) => { blocks.setMatrixAt(i, m.makeTranslation(c.x + 0.5, c.y + 0.5, c.z + 0.5)); blocks.setColorAt(i, c.k === 'built' ? g : r); });
    blocks.instanceMatrix.needsUpdate = true;
    if (blocks.instanceColor) blocks.instanceColor.needsUpdate = true;
    root.add(blocks);
  }

  function drawZones() {
    clear(outlines);
    for (const z of zones) {
      const b = z.box, w = b.x2 - b.x1 + 1, h = b.y2 - b.y1 + 1, d = b.z2 - b.z1 + 1;
      const box = new T.LineSegments(new T.EdgesGeometry(new T.BoxGeometry(w, h, d)), new T.LineBasicMaterial({color: COLOR[z.kind] || 0xffffff}));
      box.position.set(b.x1 + w / 2, b.y1 + h / 2, b.z1 + d / 2);
      root.add(box); outlines.push(box);
      const name = label(z.name, b.x1, b.y2 + 1.5, b.z1, '#fff');
      root.add(name); outlines.push(name);
      if (z.kind === 'shaft') {
        for (let y = Math.ceil(b.y1 / 8) * 8; y <= b.y2; y += 8) {
          const l = label('y ' + y, b.x1 - 0.5, y + 0.5, b.z1 - 0.5, '#9fe');
          root.add(l); outlines.push(l);
        }
      }
    }
  }

  async function get(name) {
    const r = await fetch('mcbots/' + name + '?t=' + Date.now(), {cache: 'no-store'}); // BlueMap's server sends max-age=86400
    if (!r.ok) throw new Error(name + ' ' + r.status);
    return r.json();
  }
  async function refresh() {
    try {
      const [c, z] = await Promise.all([get('changes.json'), get('zones.json')]);
      const zs = JSON.stringify(z.zones);
      data = c;
      drawChanges();
      if (zs !== refresh.zs) { refresh.zs = zs; zones = z.zones; drawZones(); }
    } catch (e) { warn('refresh failed: ' + e.message); }
  }

  const ui = document.createElement('div');
  ui.style.cssText = 'position:fixed;left:8px;bottom:8px;z-index:50;background:rgba(0,0,0,.65);color:#fff;font:12px sans-serif;padding:4px 8px;border-radius:4px';
  const sel = document.createElement('select');
  for (const [t, ms] of [['1 h', 3600e3], ['24 h', 86400e3], ['all', 1e15]]) sel.add(new Option(t, ms));
  sel.onchange = () => { windowMs = Number(sel.value); drawChanges(); };
  const cb = document.createElement('input');
  cb.type = 'checkbox'; cb.checked = true;
  cb.onchange = () => { shown = cb.checked; root.visible = shown; };
  const info = document.createElement('span');
  info.style.marginLeft = '6px';
  ui.append(cb, ' built/removed ', sel, info);
  document.body.appendChild(ui);

  // the nether and the end have their own coordinates: draw only on overworld maps
  const onMap = () => { const id = (viewer.map && viewer.map.data && viewer.map.data.id) || ''; root.visible = shown && !/_the_(nether|end)/.test(id); };
  viewer.events && viewer.events.addEventListener('bluemapMapChanged', onMap);
  onMap();
  refresh();
  setInterval(refresh, EVERY);
  console.log('[mcbots overlay] loaded');
 } catch (e) { console.warn('[mcbots overlay] disabled: ' + e); }
})();
