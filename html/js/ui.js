/* Route Defense - screens: title, starter, hub (routes / box / shop), team, battle HUD, results */
'use strict';
const $ = s => document.querySelector(s);
const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const STARTERS = [1, 4, 7, 152, 155, 158, 252, 255, 258, 387, 390, 393, 495, 498, 501, 650, 653, 656, 722, 725, 728, 810, 813, 816, 906, 909, 912, 25, 133];
let UI = { screen: '', sel: null, portrait: false, hub: 'routes', route: null, team: [] };
/* Android app: it draws behind the camera notch and passes the notch height (device pixels) as #cut=N, so the top bar can stay clear of it */
{ const m = /cut=(\d+)/.exec(location.hash); if (m) document.documentElement.style.setProperty('--cut', (+m[1] / (devicePixelRatio || 1)) + 'px'); }
const isPortrait = () => innerHeight > innerWidth;
const screenAspect = () => Math.max(innerWidth, innerHeight) / Math.max(1, Math.min(innerWidth, innerHeight));
function typeTag(t) { return `<span class="ty" style="background:${TCOL[t]}">${TYPES[t]}</span>`; }

/* small sprite icon: first Idle frame, facing down */
/* a Pokémon's idle animation playing in a small canvas (stops when removed from the page) */
function animIcon(id, size) {
  const A = DB.anim[id], a = A && (A.Idle || A.Walk); if (!a) return icon(id, size);
  const c = el('canvas', 'ic aic'), w = Math.min(a.fw, 64), h = Math.min(a.fh, 64); c.width = w; c.height = h; c.style.width = size + 'px'; c.style.height = size * h / w + 'px';
  const g = c.getContext('2d'), t0 = performance.now();
  const step = now => { if (!c.isConnected && now - t0 > 500) return; g.clearRect(0, 0, w, h); g.imageSmoothingEnabled = false; const gp = a.sh ? a.sh[0] : [a.fw / 2, a.fh / 2 + 4]; drawMon(g, id, A.Idle ? 'Idle' : 'Walk', (now - t0) / 1000, 0, w / 2 + (gp[0] - a.fw / 2), h / 2 + (gp[1] - a.fh / 2), null, true, 1); requestAnimationFrame(step); };
  requestAnimationFrame(step); return c;
}
/* icon cropped to the Pokémon itself (no empty frame around small ones), fitted into a size x size box */
function trimIcon(id, size) {
  const A = DB.anim[id], a = A && (A.Idle || A.Walk), c = el('canvas', 'ic'); if (!a) return icon(id, size);
  c.width = c.height = 1; c.style.width = c.style.height = size + 'px'; c.style.objectFit = 'contain';
  const im = monImg(id), draw = () => {
    const t = document.createElement('canvas'); t.width = a.fw; t.height = a.fh; const tg = t.getContext('2d'); tg.drawImage(im, 0, a.y, a.fw, a.fh, 0, 0, a.fw, a.fh);
    const d = tg.getImageData(0, 0, a.fw, a.fh).data; let x0 = a.fw, y0 = a.fh, x1 = -1, y1 = -1;
    for (let y = 0; y < a.fh; y++) for (let x = 0; x < a.fw; x++) if (d[(y * a.fw + x) * 4 + 3] > 0) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    if (x1 < 0) return; const bw = x1 - x0 + 1, bh = y1 - y0 + 1, m = Math.max(bw, bh);
    c.width = m; c.height = m; const g = c.getContext('2d'); g.imageSmoothingEnabled = false; g.drawImage(t, x0, y0, bw, bh, Math.floor((m - bw) / 2), m - bh, bw, bh);
  };
  if (im.complete && im.naturalWidth) draw(); else im.addEventListener('load', draw, { once: true });
  return c;
}
function icon(id, size) {   // one frame from the shared icon sheet: no need to decode each Pokémon's whole sprite sheet
  size = size || 48; const d = el('div', 'ic mic'), I = DB.micons, n = I.i[id];
  d.style.width = d.style.height = size + 'px';
  if (n == null) return d;
  if (!MICON_URL) { MICON_URL = asset('img/ui/monicons.png'); const st = document.createElement('style'); st.textContent = `.mic{background-image:url(${MICON_URL})}`; document.head.appendChild(st); }
  const k = size / I.c;
  d.style.backgroundSize = `${I.cols * I.c * k}px auto`; d.style.backgroundPosition = `-${(n % I.cols) * I.c * k}px -${Math.floor(n / I.cols) * I.c * k}px`;
  return d;
}
let MICON_URL = null;
function toast(msg, id) {
  const t = el('div', 'toast'); if (id) t.appendChild(icon(id, 28)); t.appendChild(el('span', '', msg));
  $('#toasts').appendChild(t); setTimeout(() => t.classList.add('out'), 2600); setTimeout(() => t.remove(), 3200);
}
function show(name) { UI.screen = name; document.querySelectorAll('.scr').forEach(s => s.classList.toggle('on', s.id === name)); }
let PANEL_CB = null;
/* onClose runs however the box is closed (button or tapping outside); sticky boxes ignore taps outside */
function panel(html, onClose, sticky) {
  const p = $('#modal'); p.innerHTML = ''; PANEL_CB = onClose || null;
  const box = el('div', 'win'); if (typeof html === 'string') box.innerHTML = html; else box.appendChild(html);
  if (!sticky) { const x = el('button', 'wclose alt', 'X'); x.title = 'Close'; x.onclick = ev => { ev.stopPropagation(); sfx('tap'); closePanel(); }; p.appendChild(x); }   // always-visible way out: on the overlay (panels that redraw their contents can't wipe it)
  p.appendChild(box); p.classList.add('on'); p.onclick = e => { if (e.target === p && !sticky) closePanel(); }; return box;
}
function closePanel() { const cb = PANEL_CB; PANEL_CB = null; $('#modal').classList.remove('on'); if (cb) cb(); }

/* ---------- title / starter ---------- */
function showTitle() {
  show('title'); playMusic('_title');
  // the ROM's title-menu artworks, shown whole at a sharp whole-number scale in a framed window; a soft blurred copy fills the screen
  const t = $('#title'), arts = [1, 2, 3].map(i => asset('img/ui/art' + i + '.png'));
  t.innerHTML = `<div class="tblur">${arts.map(u => `<div class="art" style="background-image:url(${u})"></div>`).join('')}</div><div class="vig"></div><canvas class="motes"></canvas>
    <div class="tstack"><div class="logo">ROUTE<br>DEFENSE</div>
    <div class="tframe"><div class="tpic">${arts.map(u => `<div class="art" style="background-image:url(${u})"></div>`).join('')}</div></div>
    <div class="sub">wild Pokémon are coming down the path</div></div>`;
  const b = el('button', 'big', G.box.length ? 'Continue' : 'New Game');
  b.onclick = () => { sfx('tap'); G.box.length ? showHub() : showStarter(); };
  t.querySelector('.tstack').appendChild(b);
  if (G.box.length) t.querySelector('.tstack').appendChild(el('div', 'tinfo2', `${DB.ts.filter((_, i) => mapOpen(i)).length} maps open - best tier ${bestTier()} - ${G.box.length} Pokémon - Pokédex ${Object.keys(G.own).length}`));
  fitTitle(); titleWalkers(t); titleMotes(t); checkUpdate(t);
}
/* online code updates (Android app / bundled file): GitHub holds the newest code; the graphics stay in the app */
const UPD = 'https://raw.githubusercontent.com/Ch4rizard-X/pmd-defense/main/html/';
async function checkUpdate(t) {
  if (!window.__BUNDLE) return;
  const st = t.querySelector('.tstack'), ver = el('div', 'tver', 'v' + window.__CODEV_RUN); st.appendChild(ver);
  try {
    const r = await (await fetch(UPD + 'version.json?t=' + Date.now(), { cache: 'no-store' })).json();
    if (!(r.v > window.__CODEV_RUN) || !t.isConnected) return;
    if (r.data !== window.__DATAH) { ver.textContent = 'v' + window.__CODEV_RUN + ' - v' + r.v + ' is out but needs a new app download'; return; }
    const b = el('button', 'upd', 'Update available (v' + r.v + ')'); st.insertBefore(b, ver);
    b.onclick = async () => {
      b.disabled = true; b.textContent = 'Downloading...';
      try {
        const get = async f => { const x = await fetch(UPD + f + '?t=' + Date.now(), { cache: 'no-store' }); if (!x.ok) throw new Error(f); return x.text(); };
        const js = (await Promise.all(['core', 'map', 'battle', 'ui'].map(n => get('js/' + n + '.js')))).join('\n');
        const page = await get('index.html'), css = page.slice(page.indexOf('>', page.indexOf('<style')) + 1, page.indexOf('</style>'));
        save(); localStorage.setItem('rd_upd', JSON.stringify({ v: r.v, data: r.data, js, css }));
        b.textContent = 'Restarting...'; setTimeout(() => location.reload(), 300);
      } catch (e) { b.disabled = false; b.textContent = 'Update failed - tap to retry'; }
    };
  } catch (e) { /* offline: nothing to show */ }
}
function fitTitle() {   // biggest whole-number scale of the 240x160 picture that leaves room for the logo and button
  const f = document.querySelector('#title .tpic'); if (!f) return;
  const s = Math.max(1, Math.floor(Math.min(innerWidth * 0.82 / 240, (innerHeight - 330 * Math.min(1.6, innerHeight / 720)) / 160)));
  f.style.width = 240 * s + 'px'; f.style.height = 160 * s + 'px';
}
/* floating light motes over the title (simple shapes, no art) */
function titleMotes(t) {
  const cv = t.querySelector('.motes'), g = cv.getContext('2d'), P = [];
  const step = () => {
    if (UI.screen !== 'title' || !cv.isConnected) return;
    if (cv.width !== innerWidth || cv.height !== innerHeight) { cv.width = innerWidth; cv.height = innerHeight; }
    g.clearRect(0, 0, cv.width, cv.height);
    while (P.length < 40) P.push({ x: Math.random() * cv.width, y: cv.height + Math.random() * cv.height, r: 1 + Math.random() * 2.5, v: 10 + Math.random() * 25, ph: Math.random() * 6.3 });
    const now = performance.now() / 1000;
    for (const p of P) { p.y -= p.v / 60; const a = 0.25 + 0.25 * Math.sin(now * 2 + p.ph); g.fillStyle = `rgba(255,240,170,${a})`; g.beginPath(); g.arc(p.x + Math.sin(now + p.ph) * 12, p.y, p.r, 0, 7); g.fill(); if (p.y < -10) { p.y = cv.height + 10; p.x = Math.random() * cv.width; } }
    requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}
function titleWalkers(t) {
  const cv = el('canvas', 'walk'); t.appendChild(cv); const g = cv.getContext('2d');
  const pool = DB.dex.mon.filter(m => m.anim && DB.anim[m.id].Walk && m.g <= 3), walkers = [];
  let last = performance.now();
  const step = now => {
    if (UI.screen !== 'title' || !cv.isConnected) return;
    const dt = Math.min(0.05, (now - last) / 1000); last = now;
    const k = Math.max(2, Math.round(innerHeight / 330)); cv.style.height = 60 * k + 'px'; cv.width = Math.floor(cv.clientWidth / k); cv.height = 60; g.imageSmoothingEnabled = false;
    if (walkers.length < 4 && Math.random() < dt * 0.6) { const m = pool[Math.floor(Math.random() * pool.length)], right = Math.random() < 0.5; walkers.push({ id: m.id, x: right ? -30 : cv.width + 30, v: (right ? 1 : -1) * (14 + m.b[5] * 0.12), t: 0 }); }
    for (const w of walkers) { w.t += dt; w.x += w.v * dt; shadow(g, w.x, 52, false, 1); drawMon(g, w.id, 'Walk', w.t, w.v > 0 ? 2 : 6, w.x, 52, null, true, 1); }
    for (let i = walkers.length - 1; i >= 0; i--) if (walkers[i].x < -60 || walkers[i].x > cv.width + 60) walkers.splice(i, 1);
    requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}
/* the ROM artwork, darkened, behind the menus */
function artBg(elm, i) { elm.classList.add('artbg'); elm.style.backgroundImage = `linear-gradient(#0b1736e0, #0b1736f2), url(${asset('img/ui/art' + i + '.png')})`; }
function showStarter() {
  show('starter'); const s = $('#starter'); artBg(s, 3); s.innerHTML = '<h2>Choose your first partner</h2><div class="grid" id="stg"></div>'; let ci = 0;
  for (const id of STARTERS) {
    if (!SP[id] || !SP[id].anim) continue;
    const c = el('div', 'card'); c.style.setProperty('--i', ci++); c.appendChild(icon(id)); c.appendChild(el('div', 'nm', SP[id].n)); c.appendChild(el('div', '', SP[id].t.map(typeTag).join('')));
    c.onclick = () => {
      const box = panel(`<h3>${SP[id].n}</h3><p>Start your journey with ${SP[id].n}?</p>`);
      const y = el('button', '', 'Yes'); y.onclick = () => { G.box.push(makeMon(id, 5)); UI.team = [G.box[0].u]; G.team = UI.team; save(); closePanel(); sfx('join'); showHub(); };
      const n = el('button', 'alt', 'No'); n.onclick = closePanel; box.append(y, n);
    };
    $('#stg').appendChild(c);
  }
}

/* ---------- hub ---------- */
function showHub(tab) {
  const h = $('#hub'), same = UI.screen === 'hub' && (!tab || tab === UI.hub), keep = same ? h.scrollTop : 0;   // redrawing the same tab: no pop-in, same scroll
  if (tab) UI.hub = tab; show('hub'); playMusic(DB.ts[0].game === 'E' ? '_hub' : '_hub');
  h.innerHTML = ''; h.classList.toggle('noanim', same); requestAnimationFrame(() => { h.scrollTop = keep; }); artBg(h, 1);
  const top = el('div', 'topbar', `<span class="chip"><img src="${asset('img/ui/coin.png')}" alt=""><b>${G.money.toLocaleString()}</b></span><span class="chip"><img src="${asset('img/ui/badge.png')}" alt="">Rescue Points <b>${G.rp || 0}</b></span><span class="chip">Maps <b>${DB.ts.filter((_, i) => mapOpen(i)).length}</b>/${DB.ts.length}</span><span class="chip">Best tier <b>${bestTier()}</b></span><span class="chip">Pokédex <b>${Object.keys(G.own).length}</b>/${DB.dex.mon.filter(m => m.anim).length}</span>`);
  const opt = el('button', 'sm alt', '⚙ Options'); opt.onclick = () => optionsPanel(() => showHub());
  top.appendChild(opt); h.appendChild(top);
  const tabs = el('div', 'tabs');
  for (const [k, n] of [['routes', 'Routes'], ['box', 'Box'], ['rescue', 'Rescue'], ['dex', 'Pokédex'], ['shop', 'Shop'], ['bag', 'Bag']]) { const b = el('button', UI.hub === k ? 'on' : '', n); b.onclick = () => { sfx('tap'); showHub(k); }; tabs.appendChild(b); }
  h.appendChild(tabs);
  const body = el('div', 'body'); h.appendChild(body);
  ({ routes: hubRoutes, box: hubBox, rescue: hubRescue, dex: hubDex, shop: hubShop, bag: hubBag })[UI.hub](body);
}
function hubRoutes(body) {
  body.appendChild(el('p', 'hint', 'Every map is randomly made when you start it. Higher tiers bring stronger, rarer Pokémon - and better ones to recruit.'));
  const g = el('div', 'grid routes');
  DB.ts.forEach((S, i) => {
    const open = mapOpen(i), top = mapCleared(i);
    const c = el('div', 'card route' + (open ? '' : ' locked')); c.style.setProperty('--i', i % 30);
    c.appendChild(routeSwatch(i));
    const MG = MAPGROUP[mapGroup(i)]; c.insertAdjacentHTML('beforeend', `<div class="mgrp" style="color:${MG[1]}">${MG[0]}</div><div class="nm">${S.name}</div>`);
    c.insertAdjacentHTML('beforeend', `<div class="gm">${S.game === 'E' ? 'Explorers of Sky' : 'Rescue Team'}</div><div>${S.types.map(typeTag).join('')}</div>` + (open ? `<div class="rst">${top ? 'Tier ' + (G.mtDone && G.mtDone[i] ? MAXTIER + ' (max)' : top) + ' cleared' : 'New!'}</div>` : `<div class="lk">Clear ${DB.ts[i - 1].name} to open</div>`));
    if (open) c.onclick = () => { sfx('tap'); routePanel(i); };
    g.appendChild(c);
  });
  body.appendChild(g);
}
/* a little strip of the setting's own tiles (ground, a path, a pond) drawn with the same PMD auto-tile rules as the maps */
const SWATCH = {};
function routeSwatch(i) {
  if (!SWATCH[i]) {
    const W = 12, H = 4, t = Array.from({ length: H }, (_, y) => Array.from({ length: W }, (_, x) => (y === 1 || y === 2) && x < 8 ? 1 : (x >= 7 && y >= 1 && x <= 8) ? 1 : 0));
    t[0][10] = t[0][11] = t[1][10] = t[1][11] = 2;
    SWATCH[i] = renderMap({ set: i, W, H, t }, rng(i + 1));
  }
  const c = el('canvas', 'sw'), src = SWATCH[i]; c.width = src.width; c.height = src.height;
  const paint = () => c.getContext('2d').drawImage(src, 0, 0);
  paint(); setTimeout(paint, 300); setTimeout(paint, 1500); return c;
}
function routePanel(i) {
  const S = DB.ts[i];
  UI.route = { set: i, tier: Math.max(1, Math.min(mapTier(i), UI.route && UI.route.set === i ? UI.route.tier : mapTier(i))), seed: (Math.random() * 1e9) | 0 };
  const box = panel('');
  const render = () => {
    const r = UI.route, MG0 = MAPGROUP[mapGroup(i)]; box.innerHTML = `<h3>${S.name} <span class="mgrp" style="color:${MG0[1]}">${MG0[0]}</span></h3><div>${S.types.map(typeTag).join('')}</div>`;
    if (mapGroup(i)) box.insertAdjacentHTML('beforeend', `<div class="hint">${MG0[0]} map: harder by nature - every tier here fights like a higher tier on earlier maps (levels, species and traits), with shorter paths, more entrances and water and ${Math.round((MG0[4] - 1) * 100)}% more per wave. Rewards x${MG0[3]}.</div>`);
    const prev = el('canvas', 'prev'); const pm = genMap(i, false, r.seed, null, screenAspect(), r.tier);
    prev.width = pm.W * TZ; prev.height = pm.H * TZ; const pg = prev.getContext('2d'); pg.lineWidth = 3;
    const paint = () => { pg.drawImage(pm.cv, 0, 0); pg.strokeStyle = 'rgba(120,30,20,.55)'; pg.setLineDash([8, 8]); pg.lineWidth = 3; pg.beginPath(); for (const l of pm.lines) { pg.beginPath(); l.forEach(([x, y], k) => k ? pg.lineTo(x, y) : pg.moveTo(x, y)); pg.stroke(); } };
    paint(); pm.ready.then(paint);
    box.appendChild(prev);
    const MG = MAPGROUP[mapGroup(i)], th = threatTier(i, r.tier), [la, lb] = lvRange(th), lvA = Math.min(98, la), lvB = Math.min(100, lb), stn = starsOf(i, r.tier);
    const row = el('div', 'tier');
    const dn = el('button', 'sm alt', '◀'), up = el('button', 'sm alt', '▶');
    dn.onclick = () => { if (r.tier > 1) { r.tier--; render(); } }; up.onclick = () => { if (r.tier < mapTier(i)) { r.tier++; render(); } };
    row.append(dn, el('span', '', `Tier <b>${r.tier}</b> <span class="stars">${'★'.repeat(stn)}${'☆'.repeat(3 - stn)}</span> - wild Lv ${lvA}-${lvB} - ${waveCount(r.tier)} waves`), up);
    box.appendChild(row);
    const nl = el('button', 'alt', 'New layout'); nl.onclick = () => { r.seed = (Math.random() * 1e9) | 0; render(); };
    const go = el('button', '', 'Choose team ▶'); go.onclick = () => { closePanel(); showTeam(); };
    const bt = el('div', 'rbtns'); bt.append(nl, go); box.appendChild(bt);   // up top, so they're reachable without scrolling past the spawn list
    const tr = TRAITS.filter(x => x[0] <= th); if (tr.length) box.appendChild(el('div', 'hint', '<b>Wild traits here:</b><br>' + tr.map(x => x[1]).join('<br>')));
    { const g = mapGroup(i), nx = i + 1, gs = []; if (nx < DB.ts.length && mapGroup(nx) === g && !mapOpen(nx)) gs.push('Win here to open the next map.');
      if (g < 3 && !mapOpen(groupStart(g + 1))) gs.push(`Clear tier ${groupGate(g + 1)} on any ${MAPGROUP[g][0]} map to open the ${MAPGROUP[g + 1][0]} maps.`);
      if (gs.length) box.appendChild(el('div', 'hint', '<b>' + gs.join('<br>') + '</b>')); }
    box.appendChild(spawnList(i, r.tier));
    box.appendChild(el('div', 'hint', 'Stars: ★ win, ★★ 50+ lives left, ★★★ no lives lost. Each new star gives bonus Rescue Points.'));
    box.appendChild(el('div', 'hint', pm.kind === 'split' ? 'The path splits in two and joins again.' : pm.kind === 'two' ? 'Two entrances: a second path merges in.' : pm.kind === 'three' ? 'Three entrances: two more paths merge in.' : 'One path.'));
  };
  render();
}
/* the wild Pokémon this map and tier can send; ones you haven't seen yet are dark silhouettes */
function spawnList(i, tier) {
  const SI = spawnInfo(i, tier), wrap = el('div', 'spawns');
  const sec = (title, list, note) => {
    if (!list.length) return; wrap.appendChild(el('div', 'hint', `<b>${title}</b>${note ? ' - ' + note : ''}`)); const g = el('div', 'sgrid');
    for (const m of list.slice().sort((a, b) => a.bst - b.bst)) {
      const seen = G.seen[m.id], c = el('div', 'sp' + (seen ? '' : ' unseen')), ic = icon(m.id, 36);
      if (!seen) ic.style.filter = 'brightness(0) opacity(.45)';
      c.appendChild(ic); c.appendChild(el('div', 'snm', seen ? m.n : '???')); c.title = seen ? m.n : 'Not seen yet'; g.appendChild(c);
    }
    wrap.appendChild(g);
  };
  const nSeen = SI.pool.filter(m => G.seen[m.id]).length;
  wrap.appendChild(el('div', 'hint', `<b>Wild Pokémon here</b> - ${nSeen}/${SI.pool.length} seen`));
  RARITY.forEach((n, k) => sec(n, SI.pool.filter(m => SI.rar.get(m.id) === k), ['', '60% as often', '35% as often', '15% as often'][k]));
  sec('Heavy waves (every 5th)', SI.heavy);
  sec('Possible bosses', SI.bosses, SI.legs.length ? 'or a legendary, half the time' : '');
  if (SI.legs.length) sec('Legendary bosses', SI.legs);
  return wrap;
}
const qkLine = id => quirks(id).map(([n, d], i) => `<div class="qk"><span class="ty" style="background:${TCOL[SP[id].t[i]]}">${n}</span> ${d}</div>`).join('');
function monCard(e, onclick, extra) {
  const c = el('div', 'card mon monc'); c.style.setProperty('--i', (UI.ci = (UI.ci || 0) + 1) % 40); c.appendChild(icon(e.id));
  c.appendChild(el('div', 'lvb', 'Lv ' + e.lv)); if (seesWhy(e)) c.appendChild(el('div', 'eyeb', '👁')).title = 'Sees hidden Pokémon: ' + seesWhy(e);
  const ty = SP[e.id].t; c.appendChild(el('div', 'tstripe', '')).style.background = ty.length > 1 ? `linear-gradient(90deg, ${TCOL[ty[0]]} 50%, ${TCOL[ty[1]]} 50%)` : TCOL[ty[0]];
  c.appendChild(el('div', 'nm', SP[e.id].n)); c.appendChild(el('div', 'qkn', quirks(e.id).map(q => q[0]).join(' / '))); c.appendChild(el('div', 'lv', (evoOptions(e).some(o => o.ok) ? '<span class="evo">EVOLVE</span> ' : '') + (e.pend.length ? '<span class="new">NEW MOVE</span>' : '')));
  if (extra) c.appendChild(extra);
  if (onclick) c.onclick = onclick; return c;
}
function hubBox(body) {
  body.appendChild(el('p', 'hint', `${G.box.length} Pokémon. Tap one to see its moves and evolutions.`));
  const g = el('div', 'grid');
  for (const e of G.box.slice().sort((a, b) => b.lv - a.lv)) g.appendChild(monCard(e, () => monPanel(e, () => showHub())));
  body.appendChild(g);
}
function monPanel(e, after) {
  const box = panel('', after || null); const render = () => {
    const s = SP[e.id], st = monStats(e), nx = e.lv < MAXLV ? xpFor(s.gr, e.lv + 1) : e.xp, cur = xpFor(s.gr, e.lv);
    box.innerHTML = '';
    const head = el('div', 'mhead'); head.appendChild(animIcon(e.id, 72));
    const ty = s.t; head.style.background = `linear-gradient(120deg, ${TCOL[ty[0]]}55, ${TCOL[ty[1] != null ? ty[1] : ty[0]]}22 70%, transparent)`;
    head.appendChild(el('div', '', `<h3>${s.n} <small>Lv ${e.lv}</small></h3><div>${s.t.map(typeTag).join('')}</div>
      <div class="xp"><i style="width:${e.lv >= MAXLV ? 100 : Math.floor((e.xp - cur) / (nx - cur) * 100)}%"></i></div>
      <div class="sbars">${st.map((v, i) => { const N = DB.dex.nat[natOf(e) - 1], c = N.up === N.dn ? '' : i === N.up ? 'up' : i === N.dn ? 'dn' : ''; const use = i === 1 || i === 3 || i === 5;
        return `<div class="sb ${c}${use ? '' : ' dead'}"><span>${STATN[i]}${c === 'up' ? ' ▲' : c === 'dn' ? ' ▼' : ''}</span><b>${v}</b><i><u style="width:${Math.min(100, v / (i ? 331 * e.lv / 100 + 5 : 331 * e.lv / 100 + e.lv + 10) * 100)}%"></u></i></div>`; }).join('')}</div>
      ${qkLine(e.id)}<div class="hint">Placing costs $${placeCost(e)} battle cash</div>`));
    box.appendChild(head);
    const A = DB.dex.abil[e.ab];
    if (A) box.appendChild(el('div', 'move', `<b>Ability: ${A.n}</b>${(s.ab.find(x => x[0] === e.ab) || [])[1] ? ' <small>(hidden ability)</small>' : ''}<div class="md">${A.d}</div><div class="md" style="color:${AB_TD[A.k] ? '#9f9' : '#aaa'}">${AB_TD[A.k] ? 'In Route Defense: ' + AB_TD[A.k] : 'No effect in Route Defense'}</div>`));
    const why = seesWhy(e);
    box.appendChild(el('div', 'move', why ? `<b>👁 Sees hidden Pokémon</b><div class="md">Reveals hidden Ghost types in its range (tier 3+): ${why}</div>` : `<b>Can't see hidden Pokémon</b><div class="md">Hidden Ghost types (tier 3+) need a Psychic or Ghost type, Foresight, Odor Sleuth, Miracle Eye, Keen Eye or Frisk nearby</div>`));
    const H = DB.dex.held[e.it], hr = el('div', 'move', H ? `${itemIcon(e.it)}<b>Holding: ${H.n}</b><div class="md">${HELD_TD[H.k]}</div>` : '<b>Holding nothing</b>');
    if (H) { const tb = el('button', 'sm alt', 'Take'); tb.onclick = () => { G.held[e.it] = (G.held[e.it] || 0) + 1; e.it = 0; save(); render(); }; hr.appendChild(tb); }
    const have = Object.keys(G.held).filter(k => G.held[k] > 0);
    if (have.length) { const gb = el('button', 'sm', H ? 'Swap' : 'Give item'); gb.onclick = () => givePanel(e, () => monPanel(e, after)); hr.appendChild(gb); }
    box.appendChild(hr);
    // nature and IVs: change them with Mints and Bottle Caps from the shop (not during a battle)
    const iv = ivsOf(e), nb = el('div', 'move', `<b>Nature: ${natLabel(e.nat)}</b>${e.mint ? `<div class="md">Stats changed by ${DB.dex.tools[Object.keys(DB.dex.tools).find(k => DB.dex.tools[k].nat === e.mint)].n}: ${natLabel(e.mint)}</div>` : ''}
      <div class="md">IVs: ${iv.map((v, i) => `${STATN[i]} <b${v === 31 ? ' class="up"' : ''}>${v}</b>${e.ht[i] ? '*' : ''}`).join(' - ')} (total ${iv.reduce((a, b) => a + b, 0)}/186)</div>${e.ht.some(x => x) ? '<div class="md">* raised by a Bottle Cap</div>' : ''}`);
    const tk = Object.keys(G.tools).filter(k => G.tools[k] > 0);
    if (UI.screen !== 'battle' && tk.length) { const ub = el('button', 'sm', 'Use Mint / Bottle Cap'); ub.onclick = () => toolPanel(e, () => monPanel(e, after)); nb.appendChild(ub); }
    else if (UI.screen === 'battle' && tk.length) nb.appendChild(el('div', 'md', 'Mints and Bottle Caps can only be used outside battle.'));
    box.appendChild(nb);
    box.appendChild(el('h4', '', 'Moves'));
    e.mv.forEach((m, k) => {
      const r = el('div', 'move', `<span class="ty" style="background:${TCOL[mv(m).t]}">${TYPES[mv(m).t]}</span> <b>${mv(m).n}</b><div class="md">${moveDesc(m)}</div>`);
      if (e.pend.length) { const b = el('button', 'sm', 'Replace'); b.onclick = () => { e.mv[k] = e.pend.shift(); save(); render(); }; r.appendChild(b); }
      box.appendChild(r);
    });
    if (e.pend.length) {
      const m = e.pend[0];
      const r = el('div', 'move new', `<b>New: ${mv(m).n}</b> <span class="ty" style="background:${TCOL[mv(m).t]}">${TYPES[mv(m).t]}</span><div class="md">${moveDesc(m)} - tap Replace on a move above, or</div>`);
      const sk = el('button', 'sm alt', "Don't learn"); sk.onclick = () => { e.pend.shift(); save(); render(); }; r.appendChild(sk); box.appendChild(r);
    }
    const rem = learnedBy(e.id, e.lv).filter(m => !e.mv.includes(m) && moveUse(m));
    if (rem.length) { const rb = el('button', 'sm alt', `Move Reminder (${rem.length})`); rb.onclick = () => remindPanel(e, () => monPanel(e, after)); box.appendChild(rb); }
    const ev = evoOptions(e);
    if (ev.length) {
      box.appendChild(el('h4', '', 'Evolution'));
      for (const o of ev) {
        const r = el('div', 'move'); r.appendChild(icon(o.to, 32)); r.appendChild(el('span', '', ` <b>${SP[o.to].n}</b> <small>(${o.item ? itemIcon(o.item) : ''}${o.why})</small> `));
        if (o.ok) { const b = el('button', 'sm', 'Evolve'); b.onclick = () => { evolve(e, o.to, o.item); sfx('evo'); toast(`${s.n} evolved into ${SP[o.to].n}!`, o.to); save(); render(); if (B && B.towers) B.towers.forEach(t => t.e === e && (t.anim = 'Idle')); }; r.appendChild(b); }
        box.appendChild(r);
      }
    }
    const c = el('button', 'alt', 'Close'); c.onclick = () => closePanel(); box.appendChild(c);
    if (UI.screen === 'hub' && G.box.length > 1) {
      const rl = el('button', 'alt sm', 'Release'); rl.style.float = 'right';
      rl.onclick = () => {
        const b2 = panel(`<h3>Release ${s.n}?</h3><p>Lv ${e.lv}. It will leave your box for good${e.it ? ' (its ' + DB.dex.held[e.it].n + ' goes back to your bag)' : ''}.</p>`, () => showHub('box'));
        const y = el('button', '', 'Release'); y.onclick = () => { if (e.it) G.held[e.it] = (G.held[e.it] || 0) + 1; G.box = G.box.filter(x => x !== e); G.team = (G.team || []).filter(u => u !== e.u); save(); closePanel(); };
        const n = el('button', 'alt', 'Keep'); n.onclick = () => monPanel(e, after); b2.append(y, n);
      };
      box.appendChild(rl);
    }
  };
  render();
}
function givePanel(e, back) {
  const box = panel('<h3>Give an item</h3>', back);
  for (const k of Object.keys(G.held).filter(k => G.held[k] > 0)) {
    const H = DB.dex.held[k], r = el('div', 'move', `${itemIcon(k)}<b>${H.n}</b> x${G.held[k]}<div class="md">${HELD_TD[H.k]}</div>`); r.style.cursor = 'pointer';
    r.onclick = () => { if (e.it) G.held[e.it] = (G.held[e.it] || 0) + 1; G.held[k]--; if (!G.held[k]) delete G.held[k]; e.it = +k; save(); closePanel(); };
    box.appendChild(r);
  }
  const c = el('button', 'alt', 'Back'); c.onclick = () => closePanel(); box.appendChild(c);
}
function remindPanel(e, back) {     // relearn any move learned up to this level (free), replacing one
  const box = panel('', back); let pickNew = null;
  const render = () => {
    box.innerHTML = `<h3>Move Reminder</h3><p class="hint">${pickNew == null ? 'Pick a move ' + SP[e.id].n + ' learned before.' : 'Pick a move to forget for ' + mv(pickNew).n + '.'}</p>`;
    const list = pickNew == null ? learnedBy(e.id, e.lv).filter(m => !e.mv.includes(m) && moveUse(m)).sort((a, b) => moveValue(b, e.id) - moveValue(a, e.id)) : e.mv;
    for (const m of list) {
      const r = el('div', 'move', `<span class="ty" style="background:${TCOL[mv(m).t]}">${TYPES[mv(m).t]}</span> <b>${mv(m).n}</b><div class="md">${moveDesc(m)}</div>`);
      r.style.cursor = 'pointer';
      r.onclick = () => { if (pickNew == null) { pickNew = m; if (e.mv.length < 4) { e.mv.push(m); save(); closePanel(); return; } render(); } else { e.mv[e.mv.indexOf(m)] = pickNew; save(); sfx('lvl'); closePanel(); } };
      box.appendChild(r);
    }
    const c = el('button', 'alt', 'Back'); c.onclick = () => closePanel(); box.appendChild(c);
  };
  render();
}
/* where a species turns up: same rules the wave builder uses */
function habitat(id) {
  const m = SP[id], out = [];
  DB.ts.forEach((S, i) => {
    if (!m.t.some(x => S.types.includes(x))) return;
    let T = null;
    const g = mapGroup(i) * 25;   // checks real tiers 1-20; the map's group adds to the tier it fights like
    if (m.lg) { for (let t = 1; t <= MAXTIER; t++) { const h = threatTier(i, t); if (h >= 5 && m.bst <= 480 + h * 25 && (m.lg === 1 || h >= 10)) { T = t; break; } } }
    else for (let t = 1; t <= MAXTIER; t++) { const h = threatTier(i, t); if (m.bst <= 300 + h * 30 + g && m.bst >= Math.min(110 + h * 30 + g, 480) && (h >= 3 || m.cr > 45)) { T = t; break; } }
    if (T) out.push([S.name, T, m.lg ? 'boss' : '']);
  });
  return out.sort((a, b) => a[1] - b[1]);
}
function hubDex(body) {
  const all = DB.dex.mon.filter(m => m.anim);
  UI.gen = UI.gen || 1;
  const seen = all.filter(m => G.seen[m.id]).length, own = all.filter(m => G.own[m.id]).length;
  body.appendChild(el('p', 'hint', `Seen ${seen} - recruited ${own} - of ${all.length}`));
  const gt = el('div', 'tabs');
  for (let g = 1; g <= 9; g++) { const b = el('button', 'sm' + (UI.gen === g ? ' on' : ' alt'), 'Gen ' + g); b.onclick = () => { UI.gen = g; showHub('dex'); }; gt.appendChild(b); }
  body.appendChild(gt);
  const grid = el('div', 'grid dex');
  for (const m of all.filter(m => m.g === UI.gen)) {
    const s = !!G.seen[m.id], c = el('div', 'card' + (G.own[m.id] ? ' picked' : ''));
    const ic = icon(m.id, 40); if (!s) ic.style.filter = 'brightness(0) opacity(.45)';
    c.append(el('div', 'lv', '#' + String(m.id).padStart(4, '0')), ic, el('div', 'nm', s ? m.n : '???'));
    if (G.own[m.id]) c.appendChild(el('div', 'lv', 'recruited'));
    if (s) c.onclick = () => dexPanel(m.id);
    grid.appendChild(c);
  }
  body.appendChild(grid);
}
function dexPanel(id) {
  const m = SP[id], box = panel('');
  const head = el('div', 'mhead'); head.appendChild(icon(id, 64));
  head.appendChild(el('div', '', `<h3>#${id} ${m.n}</h3><div>${m.t.map(typeTag).join('')}</div><div class="stats">HP ${m.b[0]} - Atk ${m.b[1]} - Def ${m.b[2]} - SpA ${m.b[3]} - SpD ${m.b[4]} - Spe ${m.b[5]} (total ${m.bst})</div>`));
  box.appendChild(head);
  box.appendChild(el('div', 'move', '<b>Abilities</b><div class="md">' + m.ab.map(([a, h]) => DB.dex.abil[a] ? DB.dex.abil[a].n + (h ? ' (hidden)' : '') : '').join(', ') + '</div>'));
  const pre = m.f && SP[m.f] ? [m.f] : [], nxt = m.ev.map(v => v.to).filter(t => SP[t]);
  if (pre.length || nxt.length) box.appendChild(el('div', 'move', '<b>Evolution</b><div class="md">' + (pre.length ? 'From ' + SP[pre[0]].n + '. ' : '') + (nxt.length ? 'Evolves into ' + nxt.map(t => SP[t].n).join(', ') : '') + '</div>'));
  const h = habitat(id);
  const extra = nxt.length ? ' Also shows up when its evolved form is knocked out.' : '';
  box.appendChild(el('div', 'move', '<b>Where to find it</b><div class="md">' + (h.length ? h.slice(0, 8).map(([n, t, k]) => `${n} (tier ${t}+${k ? ', as the boss' : ''})`).join(', ') + (h.length > 8 ? `, and ${h.length - 8} more` : '') : 'Not found on any route as a wild Pokémon.') + extra + '</div>'));
  box.appendChild(el('div', 'hint', G.own[id] ? 'You have recruited it.' : 'Knock it out and it may ask to join.'));
  const c = el('button', 'alt', 'Close'); c.onclick = () => closePanel(); box.appendChild(c);
}
/* the Rescue Points tree: 8 branches of paths from a root (like Monkey Knowledge) */
function hubRescue(body) {
  const T = DB.tree; UI.rbr = UI.rbr || T.branches[0].id;
  const own = T.nodes.filter(n => G.tree[n.id]).length;
  body.appendChild(el('p', 'hint', `Rescue Points come from clearing maps (more on higher tiers). ${G.rp || 0} to spend - ${own}/${T.nodes.length} bought.`));
  const tabs = el('div', 'tabs');
  for (const b of T.branches) {
    const have = T.nodes.filter(n => n.br === b.id && G.tree[n.id]).length, all = T.nodes.filter(n => n.br === b.id).length;
    const bt = el('button', 'sm' + (UI.rbr === b.id ? ' on' : ' alt'), `${b.name} ${have}/${all}`); bt.onclick = () => { UI.rbr = b.id; showHub('rescue'); }; tabs.appendChild(bt);
  }
  body.appendChild(tabs);
  const br = T.branches.find(b => b.id === UI.rbr); body.appendChild(el('p', 'hint', br.blurb));
  const ns = T.nodes.filter(n => n.br === br.id), paths = [];
  for (const n of ns) { let p = paths.find(x => x.name === n.path); if (!p) paths.push(p = { name: n.path, nodes: [] }); p.nodes.push(n); }
  for (const p of paths) {
    const row = el('div', 'tpath'); row.appendChild(el('div', 'tpn', p.name === 'root' ? 'Start' : p.name));
    const line = el('div', 'tnodes');
    for (const n of p.nodes) {
      const st = G.tree[n.id] ? 'own' : nodeOpen(n) ? ((G.rp || 0) >= n.cost ? 'buy' : 'poor') : 'lock';
      const c = el('div', 'tnode ' + st, `<b>${n.name}</b><div class="md">${n.desc}</div><div class="tc">${st === 'own' ? 'owned' : n.cost + ' RP'}</div>`);
      if (st === 'buy') c.onclick = () => { if (buyNode(n)) { sfx('lvl'); showHub('rescue'); } };
      line.appendChild(c);
    }
    row.appendChild(line); body.appendChild(row);
  }
  const rc = resetCost();
  if (rc > 0) {
    const r = el('button', 'alt sm', `Reset tree (₽${rc.toLocaleString()})`);
    r.onclick = () => { const b = panel(`<h3>Reset the Rescue tree?</h3><p>All ${treeSpent()} points come back to spend again. Costs ₽${rc.toLocaleString()}.</p>`); const y = el('button', '', 'Reset'); y.onclick = () => { if (resetTree()) { closePanel(); showHub('rescue'); } else toast('Not enough ₽'); }; const n = el('button', 'alt', 'Keep'); n.onclick = closePanel; b.append(y, n); };
    body.appendChild(r);
  }
}
/* use a Mint or Bottle Cap on a Pokémon (outside battle only) */
function toolPanel(e, back) {
  const b = panel('<h3>Use an item</h3>', back), iv = ivsOf(e);
  for (const k of Object.keys(G.tools).filter(k => G.tools[k] > 0)) {
    const T = DB.dex.tools[k];
    if (T.kind === 'mint') {
      const same = natOf(e) === T.nat, r = el('div', 'move', `${itemIcon(k)}<b>${T.n}</b> x ${G.tools[k]}<div class="md">Stats change as if its nature were ${natLabel(T.nat)}</div>`);
      if (same) r.appendChild(el('div', 'md', 'Already has this effect.'));
      else r.onclick = () => { G.tools[k]--; e.mint = T.nat === e.nat ? 0 : T.nat; save(); sfx('lvl'); toast(`${SP[e.id].n}'s stats changed: ${natLabel(T.nat)}`, e.id); closePanel(); };
      b.appendChild(r);
    } else if (T.kind === 'bottle-cap') {
      const r = el('div', 'move', `${itemIcon(k)}<b>${T.n}</b> x ${G.tools[k]}<div class="md">Pick a stat to raise to 31:</div>`);
      STATN.forEach((n, i) => { const sb = el('button', 'sm' + (iv[i] === 31 ? ' alt' : ''), `${n} ${iv[i]}`); if (iv[i] < 31) sb.onclick = () => { G.tools[k]--; e.ht[i] = 1; save(); sfx('lvl'); toast(`${SP[e.id].n}'s ${n} is now as if its IV were 31`, e.id); closePanel(); }; r.appendChild(sb); });
      b.appendChild(r);
    } else {
      const r = el('div', 'move', `${itemIcon(k)}<b>${T.n}</b> x ${G.tools[k]}<div class="md">Raises every stat to IV 31</div>`);
      if (iv.every(v => v === 31)) r.appendChild(el('div', 'md', 'All IVs are already 31.'));
      else r.onclick = () => { G.tools[k]--; e.ht = [1, 1, 1, 1, 1, 1]; save(); sfx('lvl'); toast(`${SP[e.id].n}'s IVs are all 31 now`, e.id); closePanel(); };
      b.appendChild(r);
    }
  }
  const c = el('button', 'alt', 'Back'); c.onclick = closePanel; b.appendChild(c);
}
function hubShop(body) {
  body.appendChild(el('p', 'hint', 'Evolution items. Earn ₽ by clearing routes; higher tiers pay more.'));
  const g = el('div', 'grid');
  const price = shopPrice(2500);
  for (const [id, name] of Object.entries(DB.dex.items)) {
    if (!name) continue;
    const users = DB.dex.mon.filter(m => m.ev.some(v => v.item == id)).map(m => m.n);
    const c = el('div', 'card', `${itemIcon(id)}<div class="nm">${name}</div><div class="hint">${users.slice(0, 4).join(', ')}${users.length > 4 ? '...' : ''}</div><div>₽${price} - have ${G.items[id] || 0}</div>`);
    c.onclick = () => { if (G.money < price) return toast('Not enough ₽'); G.money -= price; G.items[id] = (G.items[id] || 0) + 1; save(); sfx('place'); showHub('shop'); };
    g.appendChild(c);
  }
  body.appendChild(g);
  body.appendChild(el('h4', '', 'Held items'));
  body.appendChild(el('p', 'hint', 'Choice items, Life Orb and Expert Belt are only found on tier 6+ routes.'));
  const g2 = el('div', 'grid');
  for (const [id, H] of Object.entries(DB.dex.held)) {
    let pr = heldPrice(H.k); if (!pr) continue; pr = shopPrice(pr);
    const c = el('div', 'card', `${itemIcon(id)}<div class="nm">${H.n}</div><div class="hint">${HELD_TD[H.k]}</div><div>₽${pr} - have ${G.held[id] || 0}</div>`);
    c.onclick = () => { if (G.money < pr) return toast('Not enough ₽'); G.money -= pr; G.held[id] = (G.held[id] || 0) + 1; save(); sfx('place'); showHub('shop'); };
    g2.appendChild(c);
  }
  body.appendChild(g2);
  body.appendChild(el('h4', '', 'Natures & IVs'));
  body.appendChild(el('p', 'hint', 'Use them from a Pokémon\'s page, outside battle. A Mint changes how its nature affects stats; a Bottle Cap raises one stat as if its IV were 31.'));
  const g3 = el('div', 'grid');
  for (const [id, T] of Object.entries(DB.dex.tools)) {
    const pr = shopPrice(TOOL_PRICE[T.kind]);
    const c = el('div', 'card', `${itemIcon(id)}<div class="nm">${T.n}</div><div class="hint">${T.kind === 'mint' ? natLabel(T.nat).replace(/^\w+ /, '') : T.kind === 'bottle-cap' ? 'One IV to 31' : 'All IVs to 31'}</div><div>₽${pr.toLocaleString()} - have ${G.tools[id] || 0}</div>`);
    c.onclick = () => { if (G.money < pr) return toast('Not enough ₽'); G.money -= pr; G.tools[id] = (G.tools[id] || 0) + 1; save(); sfx('place'); showHub('shop'); };
    g3.appendChild(c);
  }
  body.appendChild(g3);
}
function hubBag(body) {
  const ks = Object.keys(G.items).filter(k => G.items[k] > 0);
  body.appendChild(el('p', 'hint', ks.length || Object.keys(G.held).length ? 'Use items from a Pokémon\'s page in the Box.' : 'Your bag is empty.'));
  for (const k of ks) body.appendChild(el('div', 'move', `${itemIcon(k)}<b>${DB.dex.items[k]}</b> x ${G.items[k]}`));
  const hs = Object.keys(G.held).filter(k => G.held[k] > 0);
  const ts = Object.keys(G.tools || {}).filter(k => G.tools[k] > 0);
  if (ts.length) { body.appendChild(el('h4', '', 'Mints & Bottle Caps (use them from a Pokémon\'s page)')); for (const k of ts) body.appendChild(el('div', 'move', `${itemIcon(k)}<b>${DB.dex.tools[k].n}</b> x ${G.tools[k]}`)); }
  if (hs.length) { body.appendChild(el('h4', '', 'Held items (give them from a Pokémon\'s page)')); for (const k of hs) body.appendChild(el('div', 'move', `${itemIcon(k)}<b>${DB.dex.held[k].n}</b> x ${G.held[k]}<div class="md">${HELD_TD[DB.dex.held[k].k]}</div>`)); }
  const reset = el('button', 'alt sm', 'Delete save'); reset.onclick = () => { const b = panel('<h3>Delete your save?</h3><p>This can\'t be undone.</p>'); const y = el('button', '', 'Delete'); y.onclick = () => { localStorage.removeItem(SAVE_KEY); location.reload(); }; const n = el('button', 'alt', 'Keep'); n.onclick = closePanel; b.append(y, n); };
  body.appendChild(reset);
}

/* ---------- team (max 10) ---------- */
function showTeam() {
  show('team'); const t = $('#team'); artBg(t, 2);
  UI.team = (G.team || []).filter(u => G.box.some(e => e.u === u)).slice(0, 10);
  // built once: a tap only flips that card and the counter (rebuilding everything made the list reload on every pick)
  t.innerHTML = `<div class="bar"><b>${DB.ts[UI.route.set].name} - Tier ${UI.route.tier}</b><span class="tcount"></span></div>`;
  const g = el('div', 'grid'), bar = el('div', 'bar bottom');
  const back = el('button', 'alt', '◀ Back'); back.onclick = () => showHub('routes');
  const go = el('button', '', 'Start ▶'); go.onclick = () => { G.team = UI.team.slice(); save(); beginBattle(); };
  const sync = () => { t.querySelector('.tcount').textContent = `Team ${UI.team.length}/10`; go.disabled = !UI.team.length; };
  for (const e of G.box.slice().sort((a, b) => b.lv - a.lv)) {
    const c = monCard(e, () => {
      const on = UI.team.includes(e.u);
      if (on) UI.team = UI.team.filter(u => u !== e.u); else if (UI.team.length < 10) UI.team.push(e.u); else return;
      c.classList.toggle('picked', !on); sfx('tap'); sync();
    });
    if (UI.team.includes(e.u)) c.classList.add('picked'); g.appendChild(c);
  }
  bar.append(back, go); t.append(g, bar); sync();
}

/* ---------- battle screen ---------- */
let CV, CX, VIEW = { s: 1, ox: 0, oy: 0 };
function beginBattle() {
  UI.zoom = 1; UI.zc = null;
  const team = UI.team.map(u => G.box.find(e => e.u === u)).filter(Boolean);
  UI.portrait = isPortrait();
  startBattle(UI.route.set, UI.route.tier, UI.route.seed, team, UI.portrait, screenAspect());
  show('battle'); buildHud();
  const a = playAspect(); if (Math.abs(a - B.aspect) > 0.01) { B.aspect = a; B.M = genMap(B.set, B.portrait, B.seed, null, a, B.tier); }   // make the map in the shape of the space under the top bar
  layout();
}
function buildHud() {
  const h = $('#hud'); h.innerHTML = '';
  h.innerHTML = `<div class="hb"><span class="st"><i>♥</i><b id="hl"></b></span><span class="st"><i>$</i><b id="hc"></b></span><span class="st"><i>⚑</i><b id="hw"></b></span>
    <button id="bgo" class="sm">GO ▶</button><button id="bsp" class="sm alt">1×</button><button id="bau" class="sm alt">Auto: off</button><button id="bwx" class="sm alt">Weather</button><button id="bmn" class="sm alt">☰</button><div class="wprog"><i id="wpi"></i></div></div><div id="bossbar"><div class="bn"></div><div class="bb"><i class="bt"></i><i class="bf"></i></div></div>`;
  $('#bgo').onclick = () => { sfx('tap'); startWave(); };
  $('#bsp').onclick = () => { B.speed = B.speed === 1 ? 2 : B.speed === 2 ? 3 : 1; $('#bsp').textContent = B.speed + '×'; };
  $('#bau').onclick = () => { B.auto = !B.auto; $('#bau').textContent = 'Auto: ' + (B.auto ? 'on' : 'off'); if (B.auto) startWave(); };
  $('#bmn').onclick = () => pauseMenu();
  $('#bwx').onclick = () => {
    if (B.over) return; B.paused = true;
    const b = panel(`<h3>Weather</h3><p class="hint">Costs $${weatherCost()} battle cash, lasts ${weatherWaves()} waves${B.phase === 'wave' ? ' (this one counts)' : ''}. You have $${B.cash}.${B.bwx ? ' The boss\'s ' + WEATHER[B.bwx.k][0] + ' stays until it is knocked out.' : ''}</p>`, () => { if (B) B.paused = false; });
    for (const [k, [n, d]] of Object.entries(WEATHER)) {
      const r = el('div', 'move', `<b>${n}</b><div class="md">${d}</div>`); r.style.cursor = 'pointer';
      r.onclick = () => { if (buyWeather(k)) closePanel(); else toast('Not enough battle cash'); };
      b.appendChild(r);
    }
    const c = el('button', 'alt', 'Close'); c.onclick = closePanel; b.appendChild(c);
  };
  const tb = $('#teambar'); tb.innerHTML = '';
  for (const e of B.team) {
    const c = el('div', 'tc'); c.dataset.u = e.u; c.appendChild(trimIcon(e.id, 42)); c.style.borderTopColor = TCOL[SP[e.id].t[0]]; if (seesWhy(e)) { c.style.position = 'relative'; c.appendChild(el('div', 'eyeb', '👁')); }
    c.appendChild(el('div', 'tl', `Lv${e.lv}<br>$${placeCost(e)}`));
    c.onclick = () => {
      if (B.towers.some(t => t.e === e)) { B.sel = B.towers.find(t => t.e === e); B.placing = null; towerInfo(); return; }
      B.placing = B.placing === e ? null : e; B.sel = null; towerInfo(); refreshHud();
    };
    tb.appendChild(c);
  }
  refreshHud();
}
const UISIZE = { s: ['Small', 0.85], m: ['Medium', 1], l: ['Large', 1.2], xl: ['Extra large', 1.4] };
function applyUiSize() {   // the menu size option, times a boost on big screens so the HUD grows with the display
  const big = clamp(Math.min(innerWidth / 1280, innerHeight / 720), 1, 2);
  document.documentElement.style.setProperty('--uiz', (UISIZE[G && G.opts.ui] || UISIZE.m)[1] * big);
}
function optionsPanel(after) {
  const b = panel('<h3>Options</h3>', after);
  const render = () => {
    b.innerHTML = '<h3>Options</h3>';
    const s = el('div', 'move', '<b>Sound</b>'); const sb = el('button', 'sm' + (G.opts.mute ? ' alt' : ''), G.opts.mute ? 'Off' : 'On');
    sb.onclick = () => { G.opts.mute = !G.opts.mute; if (G.opts.mute && SND.music) SND.music.pause(); else { SND.cur = ''; playMusic(UI.screen === 'battle' ? DB.ts[B.set].name : '_hub'); } save(); render(); };
    s.appendChild(sb); b.appendChild(s);
    const m = el('div', 'move', '<b>Menu size</b><div class="md">Buttons, text and panels (the map is not affected)</div>');
    for (const [k, [n]] of Object.entries(UISIZE)) { const x = el('button', 'sm' + ((G.opts.ui || 'm') === k ? '' : ' alt'), n); x.onclick = () => { G.opts.ui = k; applyUiSize(); save(); render(); }; m.appendChild(x); }
    b.appendChild(m);
    const c = el('button', 'alt', 'Close'); c.onclick = closePanel; b.appendChild(c);
  };
  render();
}
function pauseMenu() {
  if (!B || B.over || B.paused) return;
  B.paused = true; const b = panel('<h3>Paused</h3>', () => { if (B) B.paused = false; });
  const r = el('button', '', 'Resume'); r.onclick = () => closePanel();
  const q = el('button', 'alt', 'Give up'); q.onclick = () => { closePanel(); finish(false); };
  const o = el('button', 'alt', '⚙ Options'); o.onclick = () => optionsPanel(() => { if (B) B.paused = false; });
  b.append(r, o, q);
}
/* a knocked-out wild Pokémon asks to join: the battle pauses and you decide */
function askJoin() {
  if (!B || !B.asks.length || $('#modal').classList.contains('on') || UI.screen !== 'battle') return;
  const a = B.asks.shift(), s = SP[a.id], A = DB.dex.abil[a.ab], moves = bestMoves(a.id, a.lv);
  B.paused = true;
  const box = panel('', () => { if (!B) return; B.paused = false; if (B.asks.length) setTimeout(askJoin, 50); else if (B.afterAsks) { const f = B.afterAsks; B.afterAsks = null; f(); } }, true);
  const head = el('div', 'mhead'); head.appendChild(icon(a.id, 64));
  head.appendChild(el('div', '', `<h3>${s.n} wants to join your team!</h3><div>Lv ${a.lv} ${s.t.map(typeTag).join('')}</div>
    <div class="hint">${natLabel(a.nat)} nature - IVs ${a.iv.join(' / ')} (total ${a.iv.reduce((x, y) => x + y, 0)}/186)</div>
    <div class="hint">${A ? 'Ability: ' + A.n + (AB_TD[A.k] && !AB_TD[A.k].startsWith('Wild') ? ' - ' + AB_TD[A.k] : '') : ''}</div>
    <div class="mvs">${moves.map(m => `<span class="ty" style="background:${TCOL[mv(m).t]}">${mv(m).n}</span>`).join('')}</div>
    <div class="hint">Box: ${G.box.length} Pokémon${B.team.length < 10 ? ' - it would join this battle too' : ''}</div>`));
  box.appendChild(head);
  const y = el('button', '', 'Accept'), n = el('button', 'alt', 'Decline');
  y.onclick = () => {
    const e = makeMon(a.id, a.lv, a.nat, a.iv); e.ab = a.ab; G.box.push(e); B.recruits.push(e);
    if (B.team.length < 10) { B.team.push(e); buildHud(); }
    toast(`${s.n} joined your team!`, a.id); save(); closePanel();
  };
  n.onclick = () => { B.declined.add(a.id); closePanel(); };
  box.append(y, n);
}
function refreshHud() {
  if (!B) return;
  if (UI.lastLives != null && B.lives < UI.lastLives) { const st = $('#hl').parentNode; st.classList.remove('hit'); void st.offsetWidth; st.classList.add('hit'); }
  UI.lastLives = B.lives;
  $('#hl').textContent = B.lives; $('#hc').textContent = B.cash;
  // wave progress: how much of this wave is left (still to come + still alive)
  const wv = B.waves[Math.max(0, B.wave - 1)] || [], left = B.phase === 'wave' ? B.q.length + B.en.filter(e => e.hp > 0).length : 0;
  $('#wpi').style.width = (B.phase === 'wave' && wv.length ? Math.max(0, 100 - left / wv.length * 100) : B.phase === 'build' && B.wave ? 100 : 0) + '%';
  const boss = B.en.find(e => e.boss && e.hp > 0 && e.d > 0), bb = $('#bossbar');
  bb.classList.toggle('on', !!boss);
  if (boss) { bb.querySelector('.bn').innerHTML = `${SP[boss.id].lg ? '<b class="lg">LEGENDARY</b> ' : ''}${SP[boss.id].n} <small>Lv ${boss.lv}</small>`; const f = boss.hp / boss.max; bb.querySelector('.bf').style.width = f * 100 + '%'; bb.querySelector('.bt').style.width = Math.max(f, (UI.bt = UI.bt && UI.bossRef === boss ? Math.max(f, UI.bt - 0.01) : f)) * 100 + '%'; UI.bossRef = boss; }
  $('#hw').textContent = `${B.wave}/${B.waves.length}`;
  $('#bgo').disabled = B.phase !== 'build';
  const wb = $('#bwx'), wt = B.weather ? WEATHER[B.weather.k][0] + (B.weather.boss ? ' (boss)' : ' - ' + wavesLeft() + (wavesLeft() === 1 ? ' wave' : ' waves')) : 'Weather'; if (wb.textContent !== wt) wb.textContent = wt;
  document.querySelectorAll('#teambar .tc').forEach(c => {
    const e = B.team.find(x => x.u == c.dataset.u), on = B.towers.some(t => t.e === e);
    c.classList.toggle('placed', on); c.classList.toggle('sel', B.placing === e || (B.sel && B.sel.e === e));
    c.classList.toggle('poor', !on && B.cash < placeCost(e));
    const tw = B.towers.find(t => t.e === e), tl = c.querySelector('.tl'), txt = `Lv${e.lv}<br>${on ? tw.kills + ' KO' : '$' + placeCost(e)}`; if (tl.innerHTML !== txt) tl.innerHTML = txt;
    if (c.dataset.id != e.id) { c.dataset.id = e.id; c.replaceChild(trimIcon(e.id, 42), c.firstChild); }
  });
}
function towerInfo() {
  const p = $('#tinfo'); const t = B && B.sel;
  if (B && B.placing && !t) { p.innerHTML = `<b>${SP[B.placing.id].n}</b> - tap the map to place ($${placeCost(B.placing)}). ${quirks(B.placing.id).map(q => q[0] + ': ' + q[1]).join('. ')}. ${SP[B.placing.id].t.includes(10) || SP[B.placing.id].t.includes(9) ? 'Can stand in ' + (SP[B.placing.id].t.includes(10) ? 'water' : 'lava') + '.' : ''}`; p.classList.add('on'); return; }
  if (!t && B && B.selE && B.selE.hp > 0) {
    const x = B.selE, s = SP[x.id], A = DB.dex.abil[x.ab];
    const tags = [x.air && 'Flying: cuts corners, Ground moves miss', x.hide && 'Hidden: needs a Psychic or Ghost type, Foresight, Odor Sleuth, Miracle Eye, Keen Eye or Frisk nearby', x.dig && 'Digs: underground only Earthquake / Magnitude / Fissure hit', x.armor && 'Armoured: moves under 60 power do half', x.boss && 'Boss'].filter(Boolean);
    p.innerHTML = `<b>Wild ${s.n}</b> Lv ${x.lv} ${s.t.map(typeTag).join('')} - HP ${Math.ceil(x.hp)}/${x.max}${A ? ` - ${A.n}${AB_TD[A.k] && AB_TD[A.k].startsWith('Wild') ? ': ' + AB_TD[A.k].slice(6) : ''}` : ''}<div class="hint">${tags.join(' - ') || ''}</div>`;
    p.classList.add('on'); return;
  }
  if (!t) { p.classList.remove('on'); return; }
  const e = t.e, s = SP[e.id];
  const A = DB.dex.abil[e.ab], H = DB.dex.held[e.it];
  const tg = [sees(t) && 'Sees hidden', A && AB_TD[A.k] && !AB_TD[A.k].startsWith('Wild') && A.n, H && H.n].filter(Boolean);
  const x0 = xpFor(s.gr, e.lv), x1 = e.lv < MAXLV ? xpFor(s.gr, e.lv + 1) : e.xp, xf = e.lv >= MAXLV ? 100 : clamp((e.xp - x0) / Math.max(1, x1 - x0), 0, 1) * 100;
  p.innerHTML = `<b>${s.n}</b> Lv ${e.lv} - ${t.kills} KOs ${s.t.map(typeTag).join('')} <span class="hint">${tg.join(' - ')}</span>${qkLine(e.id)}<div class="xprow"><div class="xp"><i style="width:${xf}%"></i></div><span class="hint">${e.lv >= MAXLV ? 'Max level' : (x1 - e.xp).toLocaleString() + ' XP to Lv ' + (e.lv + 1)}</span></div><div class="mvs">${e.mv.map(m => `<span class="ty" style="background:${TCOL[mv(m).t]}" title="${moveDesc(m)}">${mv(m).n}</span>`).join('')}</div>`;
  const modes = el('div', 'modes');
  for (const [k, n] of [['first', 'First'], ['last', 'Last'], ['strong', 'Strong'], ['close', 'Close']]) { const b = el('button', 'sm' + (t.mode === k ? '' : ' alt'), n); b.onclick = () => { t.mode = k; towerInfo(); }; modes.appendChild(b); }
  const more = el('button', 'sm alt', 'Moves / Evolve' + (evoOptions(e).some(o => o.ok) || e.pend.length ? ' ●' : ''));
  more.onclick = () => { B.paused = true; monPanel(e, () => { if (B) B.paused = false; towerInfo(); refreshHud(); }); };
  const ups = el('div', 'ups');
  UPG.n.forEach((n, k) => {
    const lv = t.up[k], c = upgradeCost(t, k), b = el('button', 'sm' + (c && B.cash >= c ? '' : ' alt'), `${n} <span class="pips">${'●'.repeat(lv)}${'○'.repeat(UPG.max - lv)}</span><br><small>${c ? '$' + c + ' (+' + Math.round(UPG.step * 100) + '%)' : 'Max'}</small>`);
    if (c) b.onclick = () => { if (buyUpgrade(t, k)) { towerInfo(); refreshHud(); } else toast('Not enough battle cash'); };
    else b.disabled = true;
    ups.appendChild(b);
  });
  p.appendChild(ups);
  const sell = el('button', 'sm alt', `Recall ($${Math.floor(t.paid * 0.7)})`); sell.onclick = () => { sellTower(t); towerInfo(); refreshHud(); };
  modes.append(more, sell); p.appendChild(modes); p.classList.add('on');
}
/* the top bar covers the map, so the map lives in the space under it: hudInset = the bar's bottom edge in canvas pixels */
function hudInset() { const h = document.querySelector('#hud .hb'), st = $('#stage'); if (!h || !st) return 0; return Math.max(0, h.getBoundingClientRect().bottom - st.getBoundingClientRect().top + 4); }
function teamInset() { const t = $('#teambar'); return t && t.children.length ? t.getBoundingClientRect().height + 10 : 0; }
function playAspect() { fitHud(); const w = innerWidth, h = Math.max(1, innerHeight - hudInset() - teamInset()); return Math.max(w, h) / Math.max(1, Math.min(w, h)); }
/* the top bar is one row: if it is wider than the screen it shrinks to fit */
function fitHud() {
  const h = document.querySelector('#hud .hb'); if (!h) return; h.style.zoom = '';
  const z = parseFloat(getComputedStyle(h).zoom) || 1, w = h.getBoundingClientRect().width, room = innerWidth - 12;
  if (w > room) h.style.zoom = (z * room / w).toFixed(3);
}
function layout() {
  if (!B) return;
  const port = isPortrait(), bat = $('#battle'); bat.classList.toggle('port', port);
  if (port !== B.portrait) {      // turned the phone: same map, flipped to fit
    B.portrait = port; const keepT = B.towers; B.M = genMap(B.set, port, B.seed, null, B.aspect, B.tier);
    for (const t of keepT) { [t.x, t.y] = [t.y, t.x]; }
    for (const e of B.en) { const [x, y] = pathAt(B.M, Math.max(0, e.d)); e.x = x; e.y = y; }
  }
  const area = $('#stage'), r = area.getBoundingClientRect(), dpr = Math.min(2, devicePixelRatio || 1);
  CV.width = Math.floor(r.width * dpr); CV.height = Math.floor(r.height * dpr); CV.style.width = r.width + 'px'; CV.style.height = r.height + 'px';
  fitHud();
  const top = Math.min(CV.height * 0.4, hudInset() * dpr), bot = Math.min(CV.height * 0.3, teamInset() * dpr), ah = CV.height - top - bot, my = top + ah / 2;   // play area: under the top bar, above the team row
  const mw = B.M.W * TZ, mh = B.M.H * TZ, s0 = Math.min(CV.width / mw, ah / mh);   // the whole map fits the play area (it is made in that shape, so the edges left over are thin)
  const z = UI.zoom || 1, s = s0 * z, cx = UI.zc ? UI.zc[0] : mw / 2, cy = UI.zc ? UI.zc[1] : mh / 2;   // pinch zoom: zc is the map point at the play area's centre
  VIEW = { s, s0, ox: CV.width / 2 - cx * s, oy: my - cy * s, dpr, top };
  VIEW.ox = mw * s <= CV.width ? (CV.width - mw * s) / 2 : clamp(VIEW.ox, CV.width - mw * s, 0);
  VIEW.oy = mh * s <= ah ? top : clamp(VIEW.oy, CV.height - bot - mh * s, top);   // the map sits right under the top bar
  { // the team row sits right under the map (where the map ends at normal zoom), and the move info right above the row
    const tb = $('#teambar'), y = (top + Math.min(mh * s0, ah)) / dpr + 4;
    if (tb) { tb.style.top = y + 'px'; tb.style.bottom = 'auto'; }
    const ti = $('#tinfo'); if (ti && tb) ti.style.bottom = (innerHeight - y + 6) + 'px';
  }
  UI.zc = [(CV.width / 2 - VIEW.ox) / s, (my - VIEW.oy) / s];
}
function resetZoom() { UI.zoom = 1; UI.zc = null; if (B) layout(); }
function toMap(ev) { const r = CV.getBoundingClientRect(); return [((ev.clientX - r.left) * VIEW.dpr - VIEW.ox) / VIEW.s, ((ev.clientY - r.top) * VIEW.dpr - VIEW.oy) / VIEW.s]; }
const FINGER = 70;   // on touch, the placement preview sits this many screen pixels above the fingertip
function placeAt(ev) { let [x, y] = toMap(ev); if (ev.pointerType === 'touch') y -= FINGER * VIEW.dpr / VIEW.s; return [x, y]; }
function setGhost(ev) { const [x, y] = placeAt(ev); B.ghost = { x, y, ok: canPlace(B.placing, x, y) && B.cash >= placeCost(B.placing) && B.towers.length < 10 }; }
function setupInput() {
  const P = new Map(); let pinch = null, panned = false, lastTap = 0;
  const pts = () => [...P.values()];
  CV.addEventListener('pointerdown', ev => {
    if (!B) return; CV.setPointerCapture(ev.pointerId); P.set(ev.pointerId, { x: ev.clientX, y: ev.clientY, sx: ev.clientX, sy: ev.clientY });
    if (P.size === 2) {   // two fingers: pinch to zoom (cancels a placement drag)
      const [a, b] = pts(); pinch = { d: Math.hypot(a.x - b.x, a.y - b.y), z: UI.zoom || 1 }; B.ghost = null; return;
    }
    panned = false;
    if (B.placing) setGhost(ev);
  });
  CV.addEventListener('pointermove', ev => {
    if (!B) return; const p = P.get(ev.pointerId);
    if (!p) { if (B.placing && ev.pointerType !== 'touch') setGhost(ev); return; }
    const dx = ev.clientX - p.x, dy = ev.clientY - p.y; p.x = ev.clientX; p.y = ev.clientY;
    if (P.size >= 2 && pinch) {
      const [a, b] = pts(), d = Math.hypot(a.x - b.x, a.y - b.y), r = CV.getBoundingClientRect();
      const mx = ((a.x + b.x) / 2 - r.left) * VIEW.dpr, my = ((a.y + b.y) / 2 - r.top) * VIEW.dpr;
      const fx = (mx - VIEW.ox) / VIEW.s, fy = (my - VIEW.oy) / VIEW.s;   // keep the map point under the fingers in place
      UI.zoom = clamp(pinch.z * d / Math.max(1, pinch.d), 1, 3);
      const s = VIEW.s0 * UI.zoom; const pcy = (VIEW.top || 0) + (CV.height - (VIEW.top || 0)) / 2; UI.zc = [fx + (CV.width / 2 - mx) / s, fy + (pcy - my) / s];
      UI.zc[0] -= dx / 2 * VIEW.dpr / s; UI.zc[1] -= dy / 2 * VIEW.dpr / s; layout(); panned = true; return;
    }
    if (B.placing) { setGhost(ev); return; }
    if ((UI.zoom || 1) > 1 && (panned || Math.hypot(ev.clientX - p.sx, ev.clientY - p.sy) > 8)) {   // one finger drags the zoomed map
      panned = true; UI.zc[0] -= dx * VIEW.dpr / VIEW.s; UI.zc[1] -= dy * VIEW.dpr / VIEW.s; layout();
    }
  });
  const end = ev => {
    if (!B) return; const was = P.size; P.delete(ev.pointerId);
    if (was >= 2) { if (P.size < 2) pinch = null; panned = true; return; }
    if (ev.type === 'pointercancel' || panned) { B.ghost = null; return; }
    if (B.placing) {
      const [x, y] = placeAt(ev);
      if (placeTower(B.placing, x, y)) { B.sel = null; B.placing = null; B.ghost = null; }
      else if (B.cash < placeCost(B.placing)) toast('Not enough battle cash');
      towerInfo(); refreshHud(); return;
    }
    const now = performance.now();
    if (now - lastTap < 300 && (UI.zoom || 1) > 1) { lastTap = 0; resetZoom(); return; }   // double-tap: zoom back out
    lastTap = now;
    const [x, y] = toMap(ev), tr = ev.pointerType === 'touch' ? 30 : 22;
    let best = null, bd = tr;
    for (const t of B.towers) { const d = Math.hypot(t.x - x, t.y - 9 - y); if (d < bd) { bd = d; best = t; } }
    B.sel = best; B.selE = null;
    if (!best) { let be = null, ed = tr - 2; for (const e of B.en) { const d = Math.hypot(e.x - x, e.y - ((e.air ? 12 : 0) + 6) * ESPR - y); if (e.hp > 0 && d < ed) { ed = d; be = e; } } B.selE = be; }
    towerInfo(); refreshHud();
  };
  CV.addEventListener('pointerup', end); CV.addEventListener('pointercancel', end);
  CV.addEventListener('pointerleave', ev => { if (B && ev.pointerType !== 'touch') B.ghost = null; });
}
/* banner across the map when a wave starts (heavy waves and the boss get their own) */
function waveBanner() {
  if (!B || UI.screen !== 'battle') return;
  const w = B.waves[B.wave - 1], boss = w && w.find(x => x.boss), heavy = B.wave % 5 === 0 && !boss;
  const bn = el('div', 'banner' + (boss ? (SP[boss.id].lg ? ' legend' : ' boss') : ''));
  const inner = el('div', '');
  if (boss) { inner.appendChild(icon(boss.id, 56)); inner.appendChild(el('div', '', `${SP[boss.id].lg ? 'Legendary boss!' : 'Boss wave!'}<small>${SP[boss.id].n} Lv ${boss.lv}</small>`)); }
  else inner.appendChild(el('div', '', `Wave ${B.wave}${heavy ? '<small>Heavy wave: tough Pokémon</small>' : ''}`));
  bn.appendChild(inner); $('#battle').appendChild(bn); setTimeout(() => bn.remove(), 1900);
}
function showResult() {
  if (B.asks.length) { B.afterAsks = showResult; askJoin(); return; }   // answer join requests first
  const won = B.phase === 'win', box = panel('', null, true); box.classList.add('res'); if (won) box.classList.add('win');
  box.innerHTML = `<h3>${won ? 'Route cleared!' : 'The wild Pokémon got through...'}</h3>
    <p class="hint" style="text-align:center">${DB.ts[B.set].name} - Tier ${B.tier} - wave ${B.wave}/${B.waves.length} - ${B.kills} KOs</p>
    ${won ? `<div class="rstars">${[0, 1, 2].map(k => `<span class="${k < B.stars ? 'on' : ''}" style="animation-delay:${0.25 + k * 0.3}s">★</span>`).join('')}</div>${B.starRp ? `<p class="hint" style="text-align:center">+${B.starRp} Rescue Points for new stars</p>` : ''}` : ''}
    <div class="rw"><span class="chip"><img src="${asset('img/ui/coin.png')}" alt=""><b class="cnt" data-to="${B.reward}">0</b></span><span class="chip"><img src="${asset('img/ui/badge.png')}" alt="">Rescue Points <b class="cnt" data-to="${B.rp || 0}">0</b></span>
    ${B.unlocked ? `<span class="chip"><b>Tier ${B.tier + 1} unlocked on ${DB.ts[B.set].name}!</b></span>` : ''}${B.groupOpened ? `<span class="chip"><b>${B.groupOpened} maps open!</b></span>` : ''}${B.mapOpened ? `<span class="chip"><b>New map: ${B.mapOpened}!</b></span>` : ''}${B.drop ? `<span class="chip">${itemIcon(B.drop)}${DB.dex.items[B.drop]}</span>` : ''}${B.hdrop ? `<span class="chip">${itemIcon(B.hdrop)}${DB.dex.held[B.hdrop].n}</span>` : ''}</div>`;
  box.querySelectorAll('.cnt').forEach(n => { const to = +n.dataset.to, t0 = performance.now(); const f = now => { const k = Math.min(1, (now - t0) / 900); n.textContent = Math.round(to * (1 - Math.pow(1 - k, 3))).toLocaleString(); if (k < 1) requestAnimationFrame(f); }; requestAnimationFrame(f); });
  if (won) [0, 1, 2].slice(0, B.stars).forEach(k => setTimeout(() => sfx('lvl'), 250 + k * 300));
  if (B.recruits.length) { box.appendChild(el('h4', '', 'Joined your team')); const g = el('div', 'grid'); B.recruits.forEach(e => g.appendChild(monCard(e))); box.appendChild(g); }
  const xs = el('div', 'grid'); for (const e of B.team) { const c = monCard(e); c.appendChild(el('div', 'hint', '+' + (B.xpLog[e.u] || 0) + ' XP')); xs.appendChild(c); }
  box.appendChild(el('h4', '', 'Team')); box.appendChild(xs);
  const again = el('button', '', 'Same route, new layout'); again.onclick = () => { closePanel(); UI.route.seed = (Math.random() * 1e9) | 0; beginBattle(); };
  const hub = el('button', 'alt', 'Back to routes'); hub.onclick = () => { closePanel(); B = null; showHub('routes'); };
  box.append(again, hub);
}

/* ---------- main loop ---------- */
let lastT = 0, hudT = 0;
function frame(ts) {
  const dt = Math.min(0.05, (ts - lastT) / 1000 || 0); lastT = ts;
  if (UI.screen === 'battle' && B) {
    tick(dt);
    if (B.asks && B.asks.length && !$('#modal').classList.contains('on')) askJoin();
    CX.setTransform(1, 0, 0, 1, 0, 0); CX.fillStyle = '#0a1430'; CX.fillRect(0, 0, CV.width, CV.height);
    CX.setTransform(VIEW.s, 0, 0, VIEW.s, VIEW.ox, VIEW.oy); CX.imageSmoothingEnabled = false;
    CX.save(); CX.beginPath(); CX.rect(0, 0, B.M.W * TZ, B.M.H * TZ); CX.clip();   // nothing is drawn outside the map (walkers entering, flyers hovering above the edge)
    drawBattle(CX); CX.restore();
    CX.setTransform(1, 0, 0, 1, 0, 0);   // soft vignette so the floating HUD sits on darker edges
    if (!UI.vg || UI.vg.w !== CV.width || UI.vg.h !== CV.height) { const v = CX.createRadialGradient(CV.width / 2, CV.height / 2, Math.min(CV.width, CV.height) * 0.45, CV.width / 2, CV.height / 2, Math.hypot(CV.width, CV.height) * 0.6); v.addColorStop(0, 'rgba(0,0,0,0)'); v.addColorStop(1, 'rgba(0,0,10,.38)'); UI.vg = { g: v, w: CV.width, h: CV.height }; }
    CX.fillStyle = UI.vg.g; CX.fillRect(0, 0, CV.width, CV.height);
    hudT -= dt; if (hudT <= 0) { hudT = 0.15; refreshHud(); if (B.sel) { const k = B.sel.e.lv + ':' + B.sel.kills + ':' + B.sel.e.id + ':' + B.sel.up.join('') + ':' + [0, 1, 2].map(i => +(B.cash >= upgradeCost(B.sel, i))).join(''); if (UI.tk !== k) { UI.tk = k; towerInfo(); } } else if (B.selE) towerInfo(); }
  }
  requestAnimationFrame(frame);
}
async function boot() {
  if (window.__BUNDLE && document.readyState === 'loading') await new Promise(r => document.addEventListener('DOMContentLoaded', r, { once: true }));
  await loadDB();
  G = load() || newSave(); applyUiSize();
  CV = $('#cv'); CX = CV.getContext('2d'); setupInput();
  addEventListener('resize', () => { applyUiSize(); if (UI.screen === 'battle') layout(); if (UI.screen === 'title') fitTitle(); });
  document.addEventListener('visibilitychange', () => { if (document.hidden) { save(); if (UI.screen === 'battle') pauseMenu(); if (SND.music) SND.music.pause(); } else resumeMusic(); });
  addEventListener('pagehide', () => { save(); if (SND.music) SND.music.pause(); });   // phones: leaving the page or the app stops the music
  addEventListener('beforeunload', save);
  setInterval(save, 15000);
  addEventListener('pointerdown', unlockAudio, { once: false });
  showTitle(); requestAnimationFrame(frame); if (window.__updOK) window.__updOK();   // started fine: keep this code
  setTimeout(() => { for (const S of DB.ts) { const im = img('img/ts/' + S.ts + '.png'); if (im.decode) im.decode().catch(() => {}); } }, 300);   // tilesets ready before any preview
}
boot();
