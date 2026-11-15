/* Route Defense - battle: waves, towers, moves, status, XP, recruiting */
'use strict';
let B = null;
const RANGE = { 2: 66, 3: 106, 1: 94 };
const STAGE = s => s >= 0 ? (2 + s) / 2 : 2 / (2 - s);
const OHKO = new Set([12, 32, 90, 329]);
const FIXED = { 69: 'lv', 101: 'lv', 82: 40, 49: 20, 162: 'half' };
const MAXTIER = 20, XPMUL = 0.4;   // slower leveling: about Lv50 by tier 10
const SETREQ = i => Math.min(MAXTIER, 1 + Math.floor(i * MAXTIER / DB.ts.length));   // settings spread evenly over the 20 tiers (about 5 open per tier)          // tier needed to open each setting

/* ---------- waves ---------- */
function lvRange(tier) { const a = clamp(Math.round(2 + (tier - 1) * 4.2), 2, 95); return [a, clamp(a + 3 + Math.round(tier * 0.3), 3, 100)]; }   // tier here is the fight's threat (threatTier)   // tier 10: Lv40-56, Lv100 near tier 20
/* tier traits: each one only for wild Pokémon that really know the move (or have the ability) at their level */
const PROTECT_MOVES = new Set([182, 197, 588, 596, 661, 792, 852, 908]);           // Protect, Detect, King's / Spiky Shield, Baneful Bunker, Obstruct, Silk Trap, Burning Bulwark
const WX_MOVES = { 240: 'rain', 241: 'sun', 201: 'sand', 258: 'hail', 883: 'hail' }; // Rain Dance, Sunny Day, Sandstorm, Hail, Snowscape
const TRAITS = [[3, 'Ghost types hide, Dig users burrow, Steel / Rock armoured'], [5, 'Legendary bosses'], [6, 'Healers: self-healing moves restore HP once when low; Regenerator heals slowly'],
  [9, 'Protect users raise a shield when hit'], [12, 'Sprinters: speed-boosting and priority-move users dash'], [15, 'Teleport users jump ahead along the path']];
function wildTraits(id, lv, ak, tier) {
  const ms = movesAt(id, lv).map(m => [m, mv(m)]).filter(x => x[1]), o = {};
  if (tier >= 6) { const h = ms.find(([m, M]) => M.tg === 7 && M.hl > 0); if (h) o.heal = { m: h[0], hl: h[1].hl / 100 }; if (ak === 'regenerator') o.regen = 1; }
  if (tier >= 9) { const p = ms.find(([m]) => PROTECT_MOVES.has(m)); if (p) o.prot = p[0]; }
  if (tier >= 12) { const q = ms.find(([m, M]) => (M.tg === 7 && M.sc.some(([st, c]) => st === 6 && c > 0)) || (M.pr > 0 && M.p > 0)); if (q) o.dashMv = q[0]; }
  if (tier >= 15 && ms.some(([m]) => m === 100)) o.tele = 100;
  return o;
}
/* rarity by catch rate: Common 190+, Uncommon 120-189, Rare 46-119, Very rare 45 or less; each spawns less often than the last */
const RARITY = ['Common', 'Uncommon', 'Rare', 'Very rare'], RARW = [1, 0.6, 0.35, 0.15];
function rarOf(m) { return m.cr >= 190 ? 0 : m.cr >= 120 ? 1 : m.cr >= 46 ? 2 : 3; }
function rarWeight(m) { const k = rarOf(m); return RARW[k] * (k >= 2 ? 1 + mod('rare') : 1); }   // the Rescue tree's rare-find nodes help Rare and Very rare ones
function waveCount(tier) { return 40 + (tier - 1); }   // 40 waves at tier 1 on every map, +1 per tier (59 at tier 20)
/* which wild Pokémon a map and tier can send: the wave builder draws from these, and the route panel lists them */
function spawnInfo(setIdx, tier0) {
  const tier = threatTier(setIdx, tier0), S = DB.ts[setIdx], maxB = 300 + tier * 30 + mapGroup(setIdx) * 25, minB = Math.min(maxB - 190, 480);   // later maps: stronger species; the floor stops at 480 so top tiers keep the strongest species
  const hasT = m => m.t.some(x => S.types.includes(x));
  let pool = DB.dex.mon.filter(m => m.anim && !m.lg && hasT(m) && m.bst <= maxB && m.bst >= minB && (tier >= 3 || m.cr > 45));
  if (pool.length < 8) pool = DB.dex.mon.filter(m => m.anim && !m.lg && hasT(m) && m.bst <= maxB + 60);
  const heavy = pool.slice().sort((a, b) => b.b[0] + b.b[2] - a.b[0] - a.b[2]).slice(0, 6), bosses = pool.slice().sort((a, b) => b.bst - a.bst).slice(0, 3);
  const legs = tier >= 5 ? DB.dex.mon.filter(m => m.anim && m.lg && hasT(m) && m.bst <= 480 + tier * 25 && (m.lg === 1 || tier >= 10)) : [];
  const rar = new Map(pool.map(m => [m.id, rarOf(m)]));
  return { tier, minB, maxB, pool, heavy, bosses, legs, rar };
}
function wavesFor(setIdx, tier0, R) {
  const SI = spawnInfo(setIdx, tier0), tier = SI.tier, W = waveCount(tier0);
  const G4 = MAPGROUP[mapGroup(setIdx)], maxB = SI.maxB, minB = SI.minB, pool = SI.pool;
  const [b0, t0] = lvRange(tier), base = Math.min(98, b0), top = Math.min(100, t0);
  const pickW = (target) => {
    const w = pool.map(m => rarWeight(m) / (1 + Math.abs(m.bst - target) / 40));
    let r = R() * w.reduce((a, b) => a + b, 0), k = 0; while ((r -= w[k]) > 0 && k < w.length - 1) k++;
    return pool[k];
  };
  const waves = [];
  for (let w = 1; w <= W; w++) {
    const f = w / W, lv = Math.round(base + (top - base) * Math.pow(f, 1.3)), target = minB + (maxB - minB) * f;
    const list = [];
    if (w === W) {         // boss wave
      let boss = null;
      if (tier >= 5) {
        const leg = SI.legs;
        if (leg.length && R() < 0.5 + mod('legend')) boss = leg[Math.floor(R() * leg.length)];
      }
      if (!boss) boss = SI.bosses[Math.floor(R() * Math.min(3, pool.length))];
      const n = Math.round((6 + tier) * G4[4]);
      for (let i = 0; i < n; i++) list.push({ id: pickW(target).id, lv, gap: 0.6 });
      list.push({ id: boss.id, lv: Math.min(100, top + 3), gap: 2.5, boss: 1 });
    } else if (w % 5 === 0) {   // heavy wave: few strong ones
      const n = Math.round((3 + tier * 0.4 + w * 0.15) * G4[4]);
      const heavy = SI.heavy;
      for (let i = 0; i < n; i++) list.push({ id: heavy[Math.floor(R() * heavy.length)].id, lv: Math.min(100, lv + 2), gap: 1.6 });
    } else {
      const n = Math.round((4 + w * (tier === 1 ? 0.6 : 0.85) + tier * 0.5) * G4[4]), kinds = [pickW(target), pickW(target), pickW(target)].slice(0, 1 + Math.floor(R() * 3));
      const gap = clamp(1.05 - w * 0.025, 0.4, 1.05) / Math.sqrt(G4[4]);
      for (let i = 0; i < n; i++) list.push({ id: kinds[i % kinds.length].id, lv: Math.max(1, lv - (R() < 0.3 ? 1 : 0)), gap });
    }
    waves.push(list);
  }
  return waves;
}

/* heavy waves (every 5th): the bulkiest third of the map's Pokémon (at least 6), and each heavy wave draws from the
   next 3 of them in strength order (weakest first), so every heavy wave brings new species, stronger as the map goes on; they also grow with the map.
   Built after the normal wave builder, with their own random numbers, so the other waves stay exactly the same.
   The Godot version (ui.gd rework_heavy) does the same with the same numbers. */
function heavyPool(SI) {
  return SI.pool.slice().sort((a, b) => b.b[0] + b.b[2] - a.b[0] - a.b[2]).slice(0, Math.max(6, Math.ceil(SI.pool.length / 3)));
}
function reworkHeavy(waves, setIdx, tier0, seed) {
  const SI = spawnInfo(setIdx, tier0), tier = SI.tier, H = heavyPool(SI), W = waves.length, G4 = MAPGROUP[mapGroup(setIdx)];
  const [b0, t0] = lvRange(tier), base = Math.min(98, b0), top = Math.min(100, t0), R = rng(seed ^ 0x4ea7);
  const byB = H.slice().sort((a, b) => a.bst - b.bst), K = Math.floor((W - 1) / 5);   // weakest to strongest; K heavy waves
  for (let w = 5; w < W; w += 5) {
    const f = w / W, lv = Math.round(base + (top - base) * Math.pow(f, 1.3)), k = w / 5 - 1;
    const st = K > 1 ? Math.max(0, Math.round(k * (byB.length - 3) / (K - 1))) : 0, picks = byB.slice(st, st + 3);   // a window of 3 that walks from the weakest to the strongest
    const n = Math.round((3 + tier * 0.4 + w * 0.3) * G4[4]), list = [];
    for (let i = 0; i < n; i++) list.push({ id: picks[Math.floor(R() * picks.length)].id, lv: Math.min(100, lv + 2), gap: 1.6 });
    waves[w - 1] = list;
  }
  return waves;
}
/* ---------- start ---------- */
function startBattle(setIdx, tier, seed, team, portrait, aspect) {
  const R = rng(seed ^ 0x5bd1e995);
  const M = genMap(setIdx, portrait, seed, null, aspect, tier);
  B = { M, set: setIdx, tier, th: threatTier(setIdx, tier), seed, team, portrait, aspect, waves: reworkHeavy(wavesFor(setIdx, tier, R), setIdx, tier, seed), wave: 0, phase: 'build',
    lives: 100, cash: Math.round(220 + threatTier(setIdx, tier) * 60 + mod('startCash')), weather: null, towers: [], en: [], proj: [], fx: [], fl: [], q: [], qt: 0, time: 0,
    speed: 1, sel: null, placing: null, ghost: null, auto: false, recruits: [], asks: [], declined: new Set(), xpLog: {}, kills: 0, over: false };
  for (const e of team) { G.seen[e.id] = 1; }
  // decode every sprite sheet this map will need now, off the main thread, so new arrivals don't stall a frame
  const ids = new Set(team.map(e => e.id));
  for (const w of B.waves) for (const s of w) { let id = s.id; while (id && SP[id] && !ids.has(id)) { ids.add(id); id = SP[id].f; } }
  for (const e of team) for (const v of SP[e.id].ev) ids.add(v.to);
  for (const id of ids) { const im = monImg(id); if (im.decode) im.decode().catch(() => {}); }
  playMusic(DB.ts[setIdx].name);
}
function startWave() {
  if (!B || B.phase !== 'build' || B.wave >= B.waves.length) return;
  B.q = B.waves[B.wave].map(x => Object.assign({}, x)); B.qt = 0.4; B.wave++; B.phase = 'wave';
  if (typeof waveBanner === 'function') waveBanner();
  if (B.wave % 5 === 0 && B.wave !== B.waves.length && DB.snd.music._heavy) playMusic('_heavy');   // heavy waves: Monster House
  if (B.wave === B.waves.length) playMusic((DB.ts[B.set].game === 'E' ? '_e' : '_') + (B.waves[B.wave - 1].some(x => x.boss && SP[x.id].lg) ? 'legend' : 'boss'));
}
function spawn(s, d) {
  const nat = rollNat(), iv = rollIV(), sp = SP[s.id], st = calcStats(s.id, s.lv, iv, nat), hpm = s.boss ? (sp.lg ? 3 : 4) : 1;
  const ab = rollAbility(s.id, 0.05 + mod('hidden')), ak = abKey(ab);
  const en = { id: s.id, lv: s.lv, st, nat, iv, hp: st[0] * hpm, max: st[0] * hpm, d: d || 0, x: 0, y: 0, dir: 2, boss: !!s.boss,
    spd: (30 + sp.b[5] * 0.4), sts: null, stt: 0, imm: 0, dots: [], stg: { 3: 0, 5: 0, 6: 0 }, stgt: 0, stop: 0, at: rnd() * 2, hurt: 0,
    lives: s.boss ? 20 : 1 + stagesBelow(s.id), ab, ak, sbt: 0,
    lane: (rnd() * 2 - 1) * 11, ph: rnd() * 6.3, sw: 0.5 + rnd() * 0.6, pace: 0.88 + rnd() * 0.24,
    r: s.r != null ? s.r : Math.floor(rnd() * B.M.routes.length),
    air: (sp.t.includes(2) && !GROUND_FLYERS.has(s.id)) || ak === 'levitate',     // flyers take the shortcut line
    hide: B.th >= 3 && sp.t.includes(7), rev: 0,                                 // Ghost types are hidden until a seer is near
    dig: B.th >= 3 && movesAt(s.id, s.lv).includes(91), under: false, digt: 1 + rnd() * 2,   // ones that know Dig burrow
    armor: B.th >= 3 && (sp.t.includes(8) || sp.t.includes(5)),
    bst: { 3: 0, 5: 0, 6: 0 }, sh: 0, shm: 0, sht: 0, shcd: 0, tt: 4 + rnd() * 3, dt2: 2 + rnd() * 3, dash: 0 };
  Object.assign(en, wildTraits(s.id, s.lv, ak, B.th));
  if (s.boss) {      // boss moves: only ones it really knows
    const ms = movesAt(s.id, s.lv);
    en.bwxm = ms.find(m => WX_MOVES[m]) || 0; en.bwx = WX_MOVES[en.bwxm] || null;
    en.bup = ms.filter(m => { const M = mv(m); return M && M.tg === 7 && M.sc.some(([st, c]) => (st === 3 || st === 5 || st === 6) && c > 0); });
    en.bt = { wx: 1, up: 4, call: 8 };
  }
  if (s.boss && DB.snd.bossTheme && DB.snd.bossTheme[s.id]) playMusic(DB.snd.bossTheme[s.id]);   // this boss has its own song in the ROMs
  if (s.minion) en.lives = 1;                                 // Steel / Rock shrug off weak hits
  B.en.push(en); G.seen[s.id] = 1;
  return en;
}
function bossAct(e, dt) {
  const T = e.bt; for (const k in T) T[k] -= dt;
  if (e.bwx && !B.bwx) { B.bwx = { k: e.bwx, e }; floater(e, mv(e.bwxm).n, 4); }   // a boss's weather lasts until it is knocked out
  if (e.bup.length && T.up <= 0 && !B.towers.some(t => hasM(t, 'Mist') && Math.hypot(t.x - e.x, t.y - e.y) <= skR(t))) { T.up = 9; const m = e.bup[Math.floor(rnd() * e.bup.length)], M = mv(m); let up = 0;
    for (const [st, c] of M.sc) if ((st === 3 || st === 5 || st === 6) && c > 0 && e.bst[st] < 6) { e.bst[st] = Math.min(6, e.bst[st] + c); up = 1; }
    if (up) floater(e, M.n, 4); }
  if (T.call <= 0) { T.call = 15; const pool = B.waves[B.waves.length - 1].filter(x => !x.boss); if (pool.length) { floater(e, 'Called for help!', 4);
    for (let i = 0; i < 3; i++) { const p = pool[Math.floor(rnd() * pool.length)]; const m = spawn({ id: p.id, lv: Math.max(1, e.lv - 5), minion: 1, r: e.r }, Math.max(0, e.d - 20 - i * 14)); m.px = null; } } }
}
// Flying types whose only movement animation is a ground walk (no flight frames in SpriteCollab): they walk the path
const GROUND_FLYERS = new Set([6, 149, 123, 163, 178, 188, 83, 84, 85, 225, 566, 629, 701, 722, 723, 741, 845]);
const HOVER_SPEED = 0.65;   // flying animations play at 65% speed
function routeOf(e) { const r = B.M.routes[Math.min(e.r, B.M.routes.length - 1)]; return e.air ? r.air : r; }
const SEE_MOVES = new Set([193, 316, 357]);
function seesWhy(e) {   // why a Pokémon can see hidden Ghost types (null if it can't)
  const k = abKey(e.ab); if (SP[e.id].t.includes(13)) return 'Psychic type';
  if (SP[e.id].t.includes(7)) return 'Ghost type';   // Ghosts see Ghosts
  const m = e.mv.find(x => SEE_MOVES.has(x) || (DB.dex.moves[x] && DB.dex.moves[x].n === 'Defog')); if (m) return 'knows ' + mv(m).n;
  return k === 'keen-eye' || k === 'frisk' ? 'ability ' + DB.dex.abil[e.ab].n : null;
}
function sees(t) { return !!seesWhy(t.e); }
function maxRange(t) { return Math.max(40, ...t.e.mv.filter(moveUse).map(m => towerRange(t, m))); }
const hasT = (t, x) => SP[t.e.id].t.includes(x);   // tower type check for the type quirks (TQ in core.js)
function canHit(t, m, e) {
  const M = mv(m);
  if (e.under) return m === 89 || m === 222 || m === 90;
  if (e.hide && !(e.rev > 0)) return false;
  if (e.air) {
    if (M.t === 4) return false;
    if (M.c === 2 && !(M.t === 2 || M.t === 5 || SP[t.e.id].t.includes(2)) && Math.hypot(e.x - t.x, e.y - t.y) > 40) return false;
  }
  return true;
}
function stagesBelow(id) { let n = 0, s = SP[id]; while (s && s.f && SP[s.f] && SP[s.f].anim && !SP[s.f].bb && n < 3) { n++; s = SP[s.f]; } return n; }

/* ---------- towers ---------- */
function canPlace(e, x, y) {
  const M = B.M;
  if (x < 6 || y < 6 || x > M.W * TZ - 6 || y > M.H * TZ - 6) return false;
  const tv = M.t[Math.floor(y / TZ)][Math.floor(x / TZ)], ty = SP[e.id].t;
  if (tv === 1) return false;
  if (tv === 2 && !((M.liq === 'water' && ty.includes(10)) || (M.liq === 'lava' && ty.includes(9)))) return false;
  if (distToPath(M, x, y) < 30) return false;
  for (const t of B.towers) if (Math.hypot(t.x - x, t.y - y) < 22) return false;
  return true;
}
function placeTower(e, x, y) {
  const c = placeCost(e);
  if (B.cash < c || B.towers.some(t => t.e === e) || B.towers.length >= 10 || !canPlace(e, x, y)) return false;
  B.cash -= c;
  const t = { e, x, y, pt: B.time, dir: 0, anim: 'Idle', at: 0, cd: 0.3, kills: 0, buf: { 1: 0, 3: 0, 5: 0 }, buft: 0, mode: 'first', paid: c, up: [0, 0, 0] };
  B.towers.push(t); sfx('place'); return t;
}
const WEATHER = { rain: ['Rain', 'Water moves stronger, Fire moves weaker. Thunder and Hurricane never miss.', 'rgba(60,90,200,.13)'],
  sun: ['Harsh sunlight', 'Fire moves stronger, Water moves weaker. Nothing freezes.', 'rgba(255,170,40,.12)'],
  sand: ['Sandstorm', 'Hurts wild Pokémon that aren\'t Rock, Ground or Steel. Rock types take less from special moves.', 'rgba(200,160,90,.18)'],
  hail: ['Hail', 'Hurts wild Pokémon that aren\'t Ice. Blizzard never misses.', 'rgba(220,235,255,.16)'] };
function weatherCost() { return Math.round((120 + B.th * 25) * (1 + mod('weatherCost'))); }
function weatherWaves() { return 3 + Math.floor((mod('weatherDur') + 1e-6) / 0.3); }   // 3 waves, +1 for every 3 weather-duration nodes in the Rescue tree (6 in all = +2)
function buyWeather(k) {   // bought during a wave, that wave counts as the first
  const c = weatherCost(); if (B.cash < c) return false; B.cash -= c;
  const first = B.phase === 'wave' ? B.wave : B.wave + 1; B.pwx = { k, until: first + weatherWaves() - 1 }; syncWeather(); sfx('place'); return true;
}
function wavesLeft() { return B.pwx ? B.pwx.until - (B.phase === 'wave' ? B.wave : B.wave + 1) + 1 : 0; }
function syncWeather() {   // what's in the sky: a living boss's weather, otherwise yours
  if (B.bwx && !(B.bwx.e.hp > 0 && B.en.includes(B.bwx.e))) B.bwx = null;
  B.weather = B.bwx ? { k: B.bwx.k, boss: 1 } : B.pwx ? { k: B.pwx.k } : B.mwx && B.mwx.until > B.time ? { k: B.mwx.k } : null;
}
/* upgrades for a placed Pokémon, paid with battle cash: Range, Attack speed and Power, 5 levels each, +8% per level.
   Each level costs a share of its placing cost; recalling it refunds 70% of everything paid, upgrades included */
const UPG = { n: ['Range', 'Speed', 'Power'], step: 0.08, max: 5, cost: [0.8, 1.2, 1.8, 2.6, 3.6] };
function upgradeCost(t, k) { return t.up[k] >= UPG.max ? 0 : Math.round(placeCost(t.e) * UPG.cost[t.up[k]]); }
function buyUpgrade(t, k) { const c = upgradeCost(t, k); if (!c || B.cash < c) return false; B.cash -= c; t.paid += c; t.up[k]++; sfx('lvl'); return true; }
const upK = (t, k) => 1 + UPG.step * ((t.up && t.up[k]) || 0);
function sellTower(t) { B.cash += Math.floor(t.paid * 0.7); B.towers = B.towers.filter(x => x !== t); if (B.sel === t) B.sel = null; }
function towerRange(t, m) { return RANGE[mv(m).c] * (1 + Math.min(0.25, t.e.lv / 400) + mod('range')) * upK(t, 0) * (hasT(t, 2) ? 1.15 : 1); }   // Flying: Far sight
function inRange(t, r) { return B.en.filter(e => e.hp > 0 && e.d > 0 && Math.hypot(e.x - t.x, e.y - t.y) <= r); }
function chooseTarget(t, list) {
  if (!list.length) return null;
  if (t.mode === 'first') return list.reduce((a, b) => b.d > a.d ? b : a);
  if (t.mode === 'last') return list.reduce((a, b) => b.d < a.d ? b : a);
  if (t.mode === 'strong') return list.reduce((a, b) => b.hp > a.hp ? b : a);
  return list.reduce((a, b) => Math.hypot(b.x - t.x, b.y - t.y) < Math.hypot(a.x - t.x, a.y - t.y) ? b : a);
}
/* pick the best move against the best target right now */
function towerAct(t) {
  const tf = transformSrc(t), st = tf ? monStats(Object.assign({}, tf.e, { lv: t.e.lv })) : monStats(t.e), me = SP[(tf || t).e.id];   // Transform: a copy of the strongest teammate
  let best = null;
  const hk = heldKey(t.e), moves = tf ? tf.e.mv.filter(x => moveUse(x)) : hk.startsWith('choice') ? t.e.mv.slice(0, 1) : t.e.mv;
  for (const m of moves) {
    const use = moveUse(m); if (!use) continue;
    const M = mv(m), r = towerRange(t, m), list = inRange(t, r).filter(e => canHit(t, m, e)); if (!list.length) continue;
    const tg = chooseTarget(t, list);
    let sc = 0;
    if (use === 'dmg') {
      const p = M.p || (FIXED[m] ? 50 : 60), stab = me.t.includes(M.t) ? 1.5 : 1, ef = eff(M.t, SP[tg.id].t);
      sc = p * stab * ef * ((M.a || 100) / 100) * ((M.h[0] + M.h[1]) / 2) * (aoe(M) ? 1 + 0.35 * (list.length - 1) : 1);
      if (OHKO.has(m)) sc = tg.boss || tg.lv > t.e.lv ? 0 : 60;
    } else if (use === 'status') {
      const free = list.filter(e => !e.sts && e.imm <= 0);
      sc = free.length ? (M.ai === 'sleep' || M.ai === 'freeze' || M.ai === 'trap' ? 46 : 32) * ((M.a || 100) / 100) : 0;
    } else if (use === 'debuff') {
      sc = list.some(e => e.stgt <= 0) ? 28 : 0;
    } else if (use === 'buff') {
      sc = t.buft <= 0 ? 55 : 0;
    }
    if (sc > 0 && (!best || sc > best.sc)) best = { m, sc, tg, list, use, r };
  }
  if (!best) return false;
  fire(t, best, st);
  return true;
}
function aoe(M) { return M.tg === 9 || M.tg === 11 || M.tg === 14 || M.tg === 12; }
function fire(t, b, st) {
  const M = mv(b.m), fx = DB.fx.moves[b.m] || {};
  t.dir = dirRow(b.tg.x - t.x, b.tg.y - t.y); t.anim = M.c === 2 ? 'Attack' : 'Shoot'; t.at = 0;
  let cd = 5.5 / Math.sqrt(Math.max(5, M.pp)) * (M.pr > 0 ? 0.8 : 1);
  cd /= 1 + st[5] * STAGE(bufOf(t, 5)) / 150;
  if (hasM(t, 'Endure') && B.lives < 25) cd /= 1.3; if (B.towers.length && t.tw > B.time) cd /= 1.25; if (t.ssw > B.time) cd /= 1.4; if (t.acu && t.acu.k === 's' && t.acu.u > B.time) cd /= 1.3;   // move skills
  cd /= upK(t, 1);   // Attack speed upgrades
  if (hasT(t, 6)) cd /= 1 + 0.05 * B.towers.filter(o => o !== t && hasT(o, 6)).length;   // Bug: Swarm
  const ak = abKey(t.e.ab), hk = heldKey(t.e), wk = B.weather && B.weather.k, ty = SP[t.e.id].t;
  cd /= 1 + mod('atkSpeed') + Math.max(0, ...ty.map(x => mod('ts' + x)));
  const tile = B.M.t[Math.floor(t.y / TZ)][Math.floor(t.x / TZ)];
  if (tile === 2 && ((B.M.liq === 'water' && ty.includes(10)) || (B.M.liq === 'lava' && ty.includes(9)))) cd /= 1 + mod('pondSpeed');
  if ((ak === 'chlorophyll' && wk === 'sun') || (ak === 'sand-rush' && wk === 'sand') || (ak === 'slush-rush' && wk === 'hail') || (ak === 'swift-swim' && wk === 'rain')) cd /= 1.5;
  if (ak === 'speed-boost') cd /= 1 + Math.min(0.5, (t.sbt || 0) / 60);
  if (ak === 'swift-swim' && B.M.t[Math.floor(t.y / TZ)][Math.floor(t.x / TZ)] === 2) cd /= 1.5;
  if (hk === 'choice-scarf') cd /= 1.5;
  if (hk === 'quick-claw' && rnd() < 0.2) cd *= 0.4;
  t.cd = cd;
  if (fx.u) addFx(fx.u, t.x, t.y, t.dir, Math.atan2(b.tg.y - t.y, b.tg.x - t.x));
  const hit = (tg) => {
    if (b.use === 'buff') {
      const allies = (M.tg === 13 || M.tg === 3 || M.tg === 5) ? B.towers.filter(o => Math.hypot(o.x - t.x, o.y - t.y) < 90) : [t];
      for (const o of allies) { for (const [s, c] of M.sc) { const k = { 2: 1, 4: 3, 6: 5 }[s]; if (k != null && c > 0) o.buf[k] = clamp(o.buf[k] + c, -6, 6); } o.buft = heldKey(o.e) === 'light-clay' ? 24 : 12; }
      return;
    }
    const targets = aoe(M) ? (M.c === 2 || M.c === 1 ? b.list : B.en.filter(e => e.hp > 0 && Math.hypot(e.x - tg.x, e.y - tg.y) < 46 && canHit(t, b.m, e))) : [tg];
    for (const e of targets) applyMove(t, b.m, e, st);
  };
  if (b.use === 'buff') { hit(t); return; }
  if (fx.p && M.c !== 2) {
    B.proj.push({ x: t.x, y: t.y - 8 * SPR, tg: b.tg, fx: fx.p, sp: 300, at: 0, done: hit, hfx: fx.h });
  } else {
    B.q2 = B.q2 || [];
    B.q2.push({ t: 0.12, fn: () => { if (b.tg.hp > 0 || aoe(M)) { hit(b.tg); if (fx.h) addFx(fx.h, b.tg.x, b.tg.y - 8 * ESPR, t.dir); } } });
  }
}
const AB_IMMUNE = { 'flash-fire': 9, 'water-absorb': 10, 'storm-drain': 10, 'dry-skin': 10, 'volt-absorb': 12, 'lightning-rod': 12, 'motor-drive': 12, 'sap-sipper': 11, levitate: 4 };
function applyMove(t, m, e, st) {
  if (e.hp <= 0) return;
  const M = mv(m), use = moveUse(m), me = SP[t.e.id], L = t.e.lv, ak = abKey(t.e.ab), hk = heldKey(t.e), ek = e.ak;
  let acc = M.a ? M.a * (ak === 'compound-eyes' ? 1.3 : 1) * (ak === 'hustle' && M.c === 2 ? 0.8 : 1) * (hk === 'wide-lens' ? 1.1 : hk === 'zoom-lens' ? 1.2 : 1) : 100;
  if (ak === 'no-guard' || hasM(t, 'Lock-On') || hasM(t, 'Mind Reader')) acc = 100;
  const wk = B.weather && B.weather.k;
  if ((wk === 'rain' && (m === 87 || m === 542)) || (wk === 'hail' && m === 59)) acc = 100;   // Thunder / Hurricane in rain, Blizzard in hail never miss
  if (acc < 100 && rnd() * 100 > acc) { floater(e, 'MISS', 1); return; }
  const secondary = M.ac > 0 || (M.sc.length && M.sch > 0) || M.fl > 0;
  const noSec = ek === 'shield-dust' || (ak === 'sheer-force' && secondary);
  const chance = p => !noSec && rnd() * 100 < p * (ak === 'serene-grace' ? 2 : 1) * (1 + mod('effChance'));
  if (use === 'dmg') {
    if (AB_IMMUNE[ek] === M.t) { floater(e, 'MISS', 1); return; }
    let dmg;
    if (OHKO.has(m)) dmg = e.boss ? 0 : e.hp;
    else if (FIXED[m]) dmg = FIXED[m] === 'lv' ? L : FIXED[m] === 'half' ? Math.max(1, Math.floor(e.hp / 2)) : FIXED[m];
    else {
      const phys = M.c === 2;
      let A = phys ? (hasM(t, 'Power Trick') ? Math.max(st[1], st[2]) : st[1]) * STAGE(bufOf(t, 1)) : st[3] * STAGE(bufOf(t, 3));
      if (phys && (ak === 'huge-power' || ak === 'pure-power')) A *= 2;
      if (phys && ak === 'hustle') A *= 1.5;
      if (phys && hk === 'choice-band' || !phys && hk === 'choice-specs') A *= 1.5;
      const D = (phys ? e.st[2] * STAGE(clamp(e.stg[3] + e.bst[3], -6, 6)) : e.st[4] * STAGE(clamp(e.stg[5] + e.bst[5], -6, 6))) * (e.gs > B.time ? e.gsf : 1);   // Guard Split / Octolock
      const hits = ak === 'skill-link' ? M.h[1] : M.h[0] + Math.floor(rnd() * (M.h[1] - M.h[0] + 1));
      let ty = enTypes(e); if (ak === 'scrappy' && (M.t === 0 || M.t === 1)) ty = ty.filter(x => x !== 7);
      const ef = eff(M.t, ty);
      if (ef === 0 || (ek === 'wonder-guard' && ef <= 1)) { floater(e, 'MISS', 1); return; }
      const cs = clamp(M.cr + (t.fe > B.time ? 2 : 0) + (hasT(t, 15) ? 1 : 0) + (ak === 'super-luck' ? 1 : 0) + (hk === 'scope-lens' || hk === 'razor-claw' ? 1 : 0), 0, 3);
      const sure = t.lf && ek !== 'battle-armor' && ek !== 'shell-armor'; if (sure) t.lf = 0;   // Laser Focus
      const crit = sure || ek !== 'battle-armor' && ek !== 'shell-armor' && rnd() < [1 / 24, 1 / 8, 1 / 2, 1][cs] + mod('crit') ? (ak === 'sniper' ? 2.25 : 1.5) : 1;
      let pw = M.p || 60; if (ak === 'technician' && pw <= 60) pw *= 1.5;
      let mlt = (me.t.includes(M.t) ? (ak === 'adaptability' ? 2 : 1.5) + mods().stab || (ak === 'adaptability' ? 2 : 1.5) : 1) * ef * crit;
      mlt *= 1 + (mods().power || 0) + (mods()['tp' + M.t] || 0);
      mlt *= upK(t, 2);   // Power upgrades
      if (M.t === 12 && t.chg) { mlt *= 2; t.chg = 0; } if (M.t === 12 && e.elz > B.time) mlt *= 2;   // Charge / Electrify
      if (t.dt > B.time) mlt *= 2; if (t.enc) { mlt *= 2; t.enc = 0; } if (t.hh > B.time) mlt *= 1.25; if (!phys && t.th > B.time) mlt *= 1.2;   // Double Team / Encore / Helping Hand / Take Heart
      if (t.acu && t.acu.k === 'd' && t.acu.u > B.time) mlt *= 1.3; if (B.terr && B.terr[M.t] > B.time) mlt *= 1.3;   // Acupressure / terrains
      if (hasM(t, 'Ingrain')) mlt *= 1 + Math.min(0.3, 0.05 * Math.floor((B.time - (t.pt || 0)) / 10));
      if (e.boss) mlt *= 1 + (mods().bossDmg || 0) + (hasT(t, 1) ? 0.2 : 0);   // Fighting: Boss hitter
      if (hasT(t, 5)) { const rk = e.rk || (e.rk = new Set()); if (!rk.has(t)) { rk.add(t); mlt *= 1.3; } }   // Rock: Crush
      if (B.towers.some(o => o !== t && hasT(o, 17) && Math.hypot(o.x - t.x, o.y - t.y) <= 90)) mlt *= 1.05;   // Fairy: Aura
      const wp = 0.5 + (mods().weatherPower || 0);   // weather: Rain / Sun boost one type x1.5 and weaken the other x0.5
      if (wk === 'rain') mlt *= M.t === 10 ? 1 + wp : M.t === 9 ? 0.5 : 1;
      if (wk === 'sun') mlt *= M.t === 9 ? 1 + wp : M.t === 10 ? 0.5 : 1;
      if (wk === 'sun' && ak === 'solar-power' && !phys) mlt *= 1.5;
      if (wk === 'sand' && !phys && SP[e.id].t.includes(5)) mlt /= 1.5;   // sandstorm raises Rock types' Sp. Def
      if (B.lives <= 33 && ({ overgrow: 11, blaze: 9, torrent: 10, swarm: 6 })[ak] === M.t) mlt *= 1.5;
      if (ak === 'sheer-force' && secondary) mlt *= 1.3;
      if (ak === 'tough-claws' && phys) mlt *= 1.3;
      if (ak === 'tinted-lens' && ef < 1) mlt *= 2;
      if (hk === 'life-orb') mlt *= 1.3;
      if (hk === 'expert-belt' && ef > 1) mlt *= 1.2;
      if (hk === 'muscle-band' && phys || hk === 'wise-glasses' && !phys) mlt *= 1.1;
      if (TYPE_ITEM[hk] === M.t) mlt *= 1.2;
      if (hk === 'metronome') { t.metro = t.lastM === m ? Math.min(5, (t.metro || 0) + 1) : 0; t.lastM = m; mlt *= 1 + 0.2 * t.metro; }
      if ((ek === 'thick-fat' && (M.t === 9 || M.t === 14)) || (ek === 'heatproof' && M.t === 9)) mlt *= 0.5;
      if (ek === 'dry-skin' && M.t === 9) mlt *= 1.25;
      if ((ek === 'filter' || ek === 'solid-rock' || ek === 'prism-armor') && ef > 1) mlt *= 0.75;
      if ((ek === 'multiscale' || ek === 'shadow-shield') && e.hp >= e.max) mlt *= 0.5;
      if (e.armor && (M.p || 60) < 60 && !hasT(t, 8)) mlt *= 0.5;   // Steel: Pierce
      dmg = 0;
      for (let h = 0; h < hits; h++) dmg += ((2 * L / 5 + 2) * pw * A / D / 50 + 2) * mlt * (0.85 + rnd() * 0.15);
      dmg = Math.max(1, Math.floor(dmg));
      if (ef > 1) floater(e, '!', 2);
      if (e.sts === 'freeze' && M.t === 9) { e.sts = null; e.stop = 0; }
    }
    if (ek === 'sturdy' && !e.sturdy && e.hp >= e.max && dmg >= e.hp) { dmg = e.hp - 1; e.sturdy = 1; }
    e.fs = m === 206; B.mlab = M.n; hurt(t, e, dmg); e.fs = false; quirkHit(t, e, dmg);   // False Swipe: a knockout by it is 3x as likely to ask to join
    if (e.hp > 0 && M.ai !== 'none' && AILMENTS.includes(M.ai) && chance(M.ac || 0)) inflict(e, M.ai, t);
    if (e.hp > 0 && (M.fl && chance(M.fl) || (!M.fl && (hk === 'kings-rock' || hk === 'razor-fang') && rnd() < 0.1))) e.stop = Math.max(e.stop, 0.35);
    if (e.hp > 0 && M.sc.length && M.tg !== 7 && chance(M.sch || 0)) debuff(e, M.sc, t);
  } else if (use === 'status') {
    inflict(e, M.ai, t);
  } else if (use === 'debuff') {
    debuff(e, M.sc, t);
  }
}
function debuff(e, sc, t) {
  if (e.ak === 'clear-body' || e.ak === 'white-smoke' || e.ak === 'full-metal-body') return;
  for (const [s, c] of sc) if (c < 0 && (s === 3 || s === 5 || s === 6)) e.stg[s] = clamp(e.stg[s] + c, -6, 0);
  e.stgt = (t && heldKey(t.e) === 'light-clay' ? 20 : 10) * (1 + mod('debuffDur'));
}
const STATUS_BLOCK = { sleep: ['insomnia', 'vital-spirit', 'sweet-veil'], paralysis: ['limber'], poison: ['immunity', 'pastel-veil'], burn: ['water-veil', 'water-bubble'],
  confusion: ['own-tempo', 'oblivious'], freeze: ['magma-armor'] };
const TYPE_BLOCK = { burn: [9], paralysis: [12], poison: [3, 8], freeze: [14] };
function inflict(e, ai, t) {
  if (e.sts || e.imm > 0) return;
  if ((STATUS_BLOCK[ai] || []).includes(e.ak) || (TYPE_BLOCK[ai] || []).some(x => SP[e.id].t.includes(x))) return;
  e.src = t || null; e.bind = !!(t && heldKey(t.e) === 'binding-band');
  const k = e.boss ? 0.5 : 1;
  const D = { paralysis: 6, sleep: 3, freeze: 3, burn: 5, poison: 6, confusion: 3, trap: 4, yawn: 2, 'leech-seed': 8 };
  if (ai === 'freeze' && B.weather && B.weather.k === 'sun') return;   // nothing freezes in sun
  e.sts = ai; e.stt = D[ai] * k * (1 + mod('statusDur'));
  if (ai === 'sleep' || ai === 'freeze' || ai === 'trap') e.stop = Math.max(e.stop, e.stt);
  if (t && (ai === 'sleep' || ai === 'freeze' || ai === 'trap' || ai === 'paralysis' || ai === 'confusion')) meterCtl(t, e.stt);
}
/* on-hit type quirks */
function quirkHit(t, e, dmg) {
  if (hasT(t, 12) && !B.chain) {                                                            // Electric: Chain
    const o = B.en.filter(x => x !== e && x.hp > 0 && x.d > 0 && !x.under && !(x.hide && !(x.rev > 0)) && Math.hypot(x.x - e.x, x.y - e.y) < 70)
      .sort((a, b) => Math.hypot(a.x - e.x, a.y - e.y) - Math.hypot(b.x - e.x, b.y - e.y))[0];
    if (o) { B.chain = 1; B.zap = (B.zap || []).concat([{ a: [e.x, e.y], b: [o.x, o.y], t: 0.18 }]); const L = B.mlab; B.mlab = 'Chain (Electric quirk)'; hurt(t, o, Math.max(1, Math.floor(dmg * 0.3))); B.mlab = L; B.chain = 0; }
  }
  if (e.hp <= 0) return;
  if (hasT(t, 9) && rnd() < 0.15) inflict(e, 'burn', t);                                    // Fire: Scorch
  if (hasT(t, 3)) { e.pst = Math.min(5, (e.pst || 0) + 1); e.ptt = 4; e.psrc = t; }          // Poison: Toxic
  if (hasT(t, 10)) { e.wsl = 1.5; meterCtl(t, 0.15); }                                                             // Water: Soak
  if (hasT(t, 14)) { e.chill = 2; meterCtl(t, 0.3); }                                                             // Ice: Chill
  if (hasT(t, 4) && rnd() < 0.08) { e.stop = Math.max(e.stop, e.boss ? 0.2 : 0.4); meterCtl(t, e.boss ? 0.2 : 0.4); }            // Ground: Tremor
  if (hasT(t, 16) && !e.boss && e.hp > 0 && e.hp < e.max * 0.15) { floater(e, 'Finish', 4); const L = B.mlab; B.mlab = 'Finisher (Dark quirk)'; hurt(t, e, e.hp); B.mlab = L; }   // Dark: Finisher
}
function hurt(t, e, dmg) {
  const phase = t && hasT(t, 7);   // Ghost: Phase - attacks go through Protect shields
  if (!phase && !(e.nt > B.time) && e.prot && e.sh <= 0 && e.shcd <= 0 && e.hp - dmg > 0) { e.shm = e.sh = Math.ceil(e.max * 0.25); e.sht = 3; e.shcd = 9; floater(e, mv(e.prot).n, 4); }
  if (!phase && e.sh > 0) { const a = Math.min(e.sh, dmg); e.sh -= a; dmg -= a; if (e.sh <= 0) e.sht = 0; if (dmg <= 0) { e.hurt = 0.1; return; } }
  meterDmg(t, Math.min(dmg, Math.max(0, e.hp)), B.mlab || 'Other'); e.hp -= dmg;
  if (e.heal && !e.healed && !(e.nt > B.time) && e.hp > 0 && e.hp < e.max * 0.4) { e.healed = 1; e.hp = Math.min(e.max, e.hp + Math.ceil(e.max * e.heal.hl)); floater(e, mv(e.heal.m).n, 4); } e.hurt = 0.25; floater(e, String(dmg), 0);
  if (e.hp <= 0) ko(t, e);
}
function ko(t, e) {
  e.hp = 0; e.dead = 0.5; B.kills++; { const m = mtr(t); if (m) m.ko++; }
  B.cash += Math.round((2 + Math.floor(e.lv / 6) + (e.boss ? 50 : 0)) * (t && heldKey(t.e) === 'amulet-coin' ? 2 : 1) * (1 + mod('koCash')));
  if (t) {
    const sp = SP[e.id];
    const gain = (L, Lp) => Math.floor(sp.x * L / 5 * Math.pow((2 * L + 10) / (L + Lp + 10), 2.5) / 4) + 1;
    for (const o of B.towers) {
      const g = Math.ceil(gain(e.lv, o.e.lv) * (o === t ? 1 : 0.33) * (e.boss ? 3 : 1) * (heldKey(o.e) === 'lucky-egg' ? 1.5 : 1) * XPMUL * clamp(1 - (o.e.lv - e.lv - 5) / 10, 0, 1));   // full XP up to 5 levels above the wild one, none at 15+ above
      const before = o.e.lv; const ev = giveXP(o.e, g); B.xpLog[o.e.u] = (B.xpLog[o.e.u] || 0) + g;
      if (ev.length) { floater(o, 'Lv ' + o.e.lv, 3); sfx('lvl'); }
    }
    t.kills++;
    // recruiting: knocked-out wild Pokémon sometimes ask to join (only species you don't have yet)
    // you choose whether to take it, like the original; duplicates allowed; a declined species stops asking for the rest of this battle
    if (sp.anim && !B.declined.has(e.id) && !B.asks.some(a => a.id === e.id)) {
      const p = (e.boss ? 0.04 + mod('bossRecruit') : 0.005 * (sp.cr / 255) * (1 + B.th * 0.05) * (1 - 0.5 * clamp((B.th - 4) / 5, 0, 1)))   /* halved from tier 9 up */ * (1 + mod('recruit')) * (e.fs ? 3 : 1) * (e.lure > B.time ? 2 : 1);
      if (rnd() < p) { B.asks.push({ id: e.id, lv: e.lv, ab: e.ab, nat: e.nat, iv: e.iv }); sfx('join'); if (typeof askJoin === 'function') askJoin(); }
    }
  }
  // evolved Pokémon fall back to their earlier stage (they keep coming)
  const s = SP[e.id];
  if (!e.boss && s.f && SP[s.f] && SP[s.f].anim && !SP[s.f].bb) {
    const c = spawn({ id: s.f, lv: Math.max(1, e.lv - 3), r: e.r }, Math.max(1, e.d - 6)); c.lives = Math.max(1, e.lives - 1);
    if (c.air !== e.air) c.d = nearestD(routeOf(c), e.x, e.y);
  }
}
function floater(o, txt, kind) { B.fl.push({ x: o.x + (rnd() * 8 - 4), y: o.y - 24 * SPR, txt, kind, t: 0 }); }
/* user effects that flow in from one side of the sheet: turned so that side faces the target (value = which way that side points; PI/2 = down) */
const FX_FROM = { 'efob023/anim00': Math.PI / 2, 'efob023/anim08': Math.PI / 2 };   // Absorb, Mega Drain, Giga Drain, Leech Life...: orbs drawn rising from below into the user
for (const k of Object.keys(FX_FROM)) FX_FROM['eos' + k.slice(4)] = FX_FROM[k];   // Explorers of Sky has the same effect files (same numbers), drawn the same way round
function addFx(ref, x, y, dir, ang) { const a = DB.fx.anims[ref]; if (a) B.fx.push({ a, x, y, row: a.r > 1 ? dir : 0, t: 0, rot: FX_FROM[ref] != null && ang != null ? ang - FX_FROM[ref] : 0 }); }
function dirRow(dx, dy) { const deg = Math.atan2(dy, dx) * 180 / Math.PI; return ((Math.round((90 - deg) / 45) % 8) + 8) % 8; }

/* ---------- update ---------- */
function tick(dt) {
  if (!B || B.phase === 'win' || B.phase === 'lose' || B.paused) return;
  dt *= B.speed; B.time += dt;
  if (B.phase === 'wave') {
    if (B.q.length) { B.qt -= dt; while (B.q.length && B.qt <= 0) { const s = B.q.shift(); spawn(s); B.qt += s.gap; } }
    else if (!B.en.some(e => e.hp > 0)) {
      B.cash += Math.round((30 + B.wave * 6) * (1 + mod('waveBonus')));
      if (B.pwx && B.wave >= B.pwx.until) B.pwx = null;   // your weather ends with its last wave
      if (B.wave >= B.waves.length) return finish(true);
      B.phase = 'build';
      playMusic(DB.ts[B.set].name);   // before the next wave starts, or it would replace the heavy / boss song
      if (B.auto) startWave();
    }
  }
  syncWeather();
  const vines = B.towers.filter(t => hasT(t, 11)).map(t => [t.x, t.y, maxRange(t)]);   // Grass: Vines
  if (B.zap) { for (const z of B.zap) z.t -= dt; B.zap = B.zap.filter(z => z.t > 0); }
  const chipK = B.weather && (B.weather.k === 'sand' || B.weather.k === 'hail') ? B.weather.k : null;
  for (const e of B.en) {
    e.at += dt;
    if (e.hp <= 0) { e.dead -= dt; continue; }
    if (chipK && e.d > 0 && !e.under) {   // Sandstorm hurts all but Rock / Ground / Steel, Hail all but Ice (and a few abilities)
      const ty = SP[e.id].t, safe = chipK === 'sand' ? ty.some(x => x === 5 || x === 4 || x === 8) || ['sand-veil', 'sand-rush', 'sand-force', 'overcoat', 'magic-guard'].includes(e.ak)
        : ty.includes(14) || ['ice-body', 'snow-cloak', 'overcoat', 'magic-guard'].includes(e.ak);
      if (!safe) { e.wdot = (e.wdot || 0) + e.max * 0.02 * (1 + mod('weatherChip')) * dt * (e.boss ? 0.4 : 1); if (e.wdot >= 1) { const d = Math.floor(e.wdot); e.wdot -= d; e.hp -= d; if (e.hp <= 0) { ko(null, e); continue; } } }
    }
    if (e.akOff && B.time > e.akOff) { e.ak = e.ak0; e.akOff = 0; }
    if (e.cu && e.cu.left > 0) { const d0 = Math.min(e.cu.left, e.cu.dps * dt); e.cu.left -= d0; e.cud = (e.cud || 0) + d0; if (e.cud >= 1) { const d = Math.floor(e.cud); e.cud -= d; meterDmg(B.towers.includes(e.cu.t) ? e.cu.t : null, Math.min(d, e.hp), 'Curse', true); e.hp -= d; if (e.hp <= 0) { ko(B.towers.includes(e.cu.t) ? e.cu.t : null, e); continue; } } }
    if (e.pm && B.time >= e.pm) { e.pm = 0; floater(e, 'Perish', 4); B.mlab = 'Perish Song'; hurt(B.towers.includes(e.pmT) ? e.pmT : null, e, Math.ceil(e.max * 0.3)); if (e.hp <= 0) continue; }
    e.hurt = Math.max(0, e.hurt - dt); e.imm -= dt; e.chill = (e.chill || 0) - dt; e.wsl = (e.wsl || 0) - dt;
    if (e.pst > 0) { e.ptt -= dt; if (e.ptt <= 0) e.pst = 0; else if (e.ak !== 'magic-guard') { e.pd = (e.pd || 0) + e.max * 0.01 * e.pst * dt * (e.boss ? 0.4 : 1); if (e.pd >= 1) { const d = Math.floor(e.pd); e.pd -= d; meterDmg(B.towers.includes(e.psrc) ? e.psrc : null, Math.min(d, e.hp), 'Toxic stacks (Poison quirk)', true); e.hp -= d; if (e.hp <= 0) { ko(B.towers.includes(e.psrc) ? e.psrc : null, e); continue; } } } }
    if (e.sht > 0) { e.sht -= dt; if (e.sht <= 0) e.sh = 0; } e.shcd -= dt;
    if (e.regen) { e.rg = (e.rg || 0) + e.max * 0.01 * dt; if (e.rg >= 1) { const h = Math.floor(e.rg); e.rg -= h; e.hp = Math.min(e.max, e.hp + h); } }
    if (e.dashMv) { if (e.dash > 0) e.dash -= dt; else if (e.d > 0 && !e.stop && !e.sts && !(e.nt > B.time) && (e.dt2 -= dt) <= 0) { e.dash = 0.6; e.dt2 = 4 + rnd() * 2; } }
    if (e.tele && !e.stop && !e.sts && !(e.nt > B.time) && e.d > 0 && (e.tt -= dt) <= 0) { e.tt = 7 + rnd() * 3; e.d = Math.min(routeOf(e).len - 30, e.d + 70); e.px = null; floater(e, 'Teleport', 4); }
    if (e.boss && e.d > 0 && e.bt) bossAct(e, dt);
    if (e.stgt > 0) { e.stgt -= dt; if (e.stgt <= 0) e.stg = { 3: 0, 5: 0, 6: 0 }; }
    if (e.sts) {
      e.stt -= dt;
      const dps = { burn: 0.04, poison: 0.05, trap: 0.03, 'leech-seed': 0.03 }[e.sts] * (1 + mod('dot'));
      if (dps && e.ak !== 'magic-guard') { e.dot = (e.dot || 0) + e.max * dps * dt * (e.boss ? 0.4 : 1) * (e.bind && e.sts === 'trap' ? 2 : 1); if (e.dot >= 1) { const d = Math.floor(e.dot); e.dot -= d; meterDmg(B.towers.includes(e.src) ? e.src : null, Math.min(d, e.hp), { burn: 'Burn', poison: 'Poison', trap: 'Trap (bind)', 'leech-seed': 'Leech Seed' }[e.sts] || 'Status', true); e.hp -= d; if (e.hp <= 0) { ko(e.src && B.towers.includes(e.src) ? e.src : null, e); continue; } } }
      if (e.stt <= 0) { if (e.sts === 'yawn') { e.sts = null; inflict(e, 'sleep'); } else { if (e.sts === 'sleep') e.imm = 4; e.sts = null; } }
    }
    if (e.stop > 0) { e.stop -= dt; } else {
      let v = e.spd * e.pace * (1 + 0.12 * Math.sin(B.time * e.sw * 1.7 + e.ph)) * STAGE(clamp(e.stg[6] + e.bst[6], -6, 6)) * (e.dash > 0 ? 3 : 1);
      if (e.ak === 'quick-feet' && e.sts) v *= 1.5;
      if (e.ak === 'speed-boost') { e.sbt += dt; v *= Math.min(2, 1 + e.sbt / 40); }
      v *= skSpeed(e); if (e.back > B.time) v = -Math.abs(v) * 0.6; if (decoyBlocks(e)) v = 0;   // move skills
      if (e.chill > 0) v *= 0.85; if (e.wsl > 0) v *= 0.9; if (vines.some(([x, y, r]) => Math.hypot(x - e.x, y - e.y) <= r)) v *= 0.9;   // Ice / Water / Grass quirks
      if (e.sts === 'paralysis') v *= 0.5; if (e.sts === 'confusion') v *= (Math.sin(B.time * 6) > 0 ? 0.6 : -0.3);
      e.d = Math.max(e.back > B.time ? 1 : -1e9, e.d + v * dt);
    }
    if (e.dig) { e.digt -= dt; if (e.digt <= 0) { e.under = !e.under; e.digt = e.under ? 2.5 : 2.2; } }
    if (e.hide) { e.rev -= dt; for (const t of B.towers) if (sees(t) && Math.hypot(t.x - e.x, t.y - e.y) <= maxRange(t) * (hasT(t, 13) ? 1.5 : 1)) { e.rev = 0.4; break; } }
    const rt = routeOf(e), [x, y, a] = pathAt(B.M, Math.max(0, e.d), rt);
    // drift across the path instead of marching on the centre line; ease the turn at corners
    const off = e.lane + Math.sin(B.time * e.sw + e.ph) * 5, nx = -Math.sin(a), ny = Math.cos(a);
    const tx = x + nx * off, ty = y + ny * off;
    if (e.px == null) { e.x = tx; e.y = ty; } else { const k = Math.min(1, dt * 8); e.x += (tx - e.x) * k; e.y += (ty - e.y) * k; }
    const mvx = e.x - (e.px ?? e.x), mvy = e.y - (e.py ?? e.y); e.px = e.x; e.py = e.y;
    e.dir = dirRow(Math.cos(a), Math.sin(a));   // face along the path (the sway doesn't turn them)
    if (e.d >= rt.len) { e.hp = 0; e.dead = 0; B.lives -= e.lives; if (B.lives <= 0) { B.lives = 0; return finish(false); } }
  }
  B.en = B.en.filter(e => e.hp > 0 || e.dead > 0);
  for (const t of B.towers) {
    const ak = abKey(t.e.ab);
    if (B.phase === 'wave') t.sbt = (t.sbt || 0) + dt; else t.sbt = 0;
    const aura = { static: 'paralysis', 'flame-body': 'burn', 'poison-point': 'poison', 'effect-spore': 'spore' }[ak];
    if (aura && B.phase === 'wave') for (const e of B.en) if (e.hp > 0 && !e.sts && !e.under && Math.hypot(e.x - t.x, e.y - t.y) < 38 && rnd() < 0.15 * dt)
      inflict(e, aura === 'spore' ? pick(['poison', 'paralysis', 'sleep']) : aura, t);
    t.at += dt; t.cd -= dt; if (t.buft > 0) { t.buft -= dt; if (t.buft <= 0) t.buf = { 1: 0, 3: 0, 5: 0 }; }
    if (t.anim !== 'Idle' && t.at > animLen(t.e.id, t.anim)) { t.anim = 'Idle'; t.at = 0; }
    if (t.cd <= 0 && B.phase === 'wave') { if (!towerAct(t)) t.cd = 0.15; }
  }
  skillTick(dt);
  if (B.q2) { for (const a of B.q2) { a.t -= dt; if (a.t <= 0) a.fn(); } B.q2 = B.q2.filter(a => a.t > 0); }
  for (const p of B.proj) {
    p.at += dt;
    const tx = p.tg.x, ty = p.tg.y - (8 + (p.tg.air ? 12 : 0)) * ESPR, d = Math.hypot(tx - p.x, ty - p.y), s = p.sp * dt;
    if (d <= s || p.tg.hp <= 0 && d <= s * 2) { p.hit = 1; if (p.tg.hp > 0 || true) { p.done(p.tg); if (p.hfx) addFx(p.hfx, tx, ty, 0); } }
    else { p.x += (tx - p.x) / d * s; p.y += (ty - p.y) / d * s; p.row = dirRow(tx - p.x, ty - p.y); p.ang = Math.atan2(ty - p.y, tx - p.x); }
  }
  B.proj = B.proj.filter(p => !p.hit && p.at < 4);
  for (const f of B.fx) f.t += dt;
  B.fx = B.fx.filter(f => f.t < f.a.d.reduce((s, v) => s + v, 0) / 60);
  for (const f of B.fl) f.t += dt;
  B.fl = B.fl.filter(f => f.t < 0.9);
}
function animLen(id, name) { const a = DB.anim[id] && DB.anim[id][name]; return a ? a.d.reduce((s, v) => s + v, 0) / 60 : 0.5; }
function finish(won) {
  B.phase = won ? 'win' : 'lose'; B.over = true;
  const reward = Math.round((won ? 100 + B.th * 80 + B.lives * 2 : Math.floor(B.wave * B.th * 6)) * (1 + (won ? mod('pay') + mod('bossPay') : 0)) * MAPGROUP[mapGroup(B.set)][3]);   // harder maps pay more
  B.reward = reward; G.money += reward; G.stats.maps++;
  // Rescue Points: from clearing maps (a little for getting far on a loss)
  const rpm = MAPGROUP[mapGroup(B.set)][3], rp = Math.round((won ? rpForClear(B.th) : Math.floor(rpForClear(B.th) * B.wave / B.waves.length / 2)) * rpm);
  B.rp = rp; G.rp = (G.rp || 0) + rp;
  B.drop = null; B.hdrop = null; B.stars = 0; B.starRp = 0;
  if (won) {
    // stars: 1 for the win, 2 with 50+ lives left, 3 with all 100. Each new star pays half the tier's Rescue Points, once
    G.stars = G.stars || {}; const sk = B.set + ':' + B.tier, st = 1 + (B.lives >= 50) + (B.lives >= 100), was = G.stars[sk] || 0; B.stars = st;
    if (st > was) { B.starRp = Math.round(rpForClear(B.th) * 0.5 * (st - was) * rpm); G.stars[sk] = st; G.rp += B.starRp; }
    G.stats.wins++;
    // this map's next tier, and the first clear of a map opens the next map
    if (B.tier >= mapTier(B.set) && B.tier < MAXTIER) { G.mt[B.set] = B.tier + 1; B.unlocked = true; }
    if (B.tier >= MAXTIER) { G.mtDone = G.mtDone || {}; G.mtDone[B.set] = 1; }
    const g = mapGroup(B.set), nx = B.set + 1;
    if (nx < DB.ts.length && mapGroup(nx) === g && !mapOpen(nx)) { G.mt[nx] = 1; B.mapOpened = DB.ts[nx].name; }
    if (g < 3 && B.tier >= groupGate(g + 1)) { const f = groupStart(g + 1); if (f >= 0 && !mapOpen(f)) { G.mt[f] = 1; B.groupOpened = MAPGROUP[g + 1][0]; B.mapOpened = B.mapOpened || DB.ts[f].name; } }
    // held items: common ones from tier 1, the strongest (Choice items, Life Orb, Expert Belt) from tier 6
    if (rnd() < Math.min(0.85, 0.3 + B.th * 0.03 + mod('drop'))) {
      const ks = Object.keys(DB.dex.held).filter(i => B.th >= 6 + mod('rareTier') || !HELD_RARE.has(DB.dex.held[i].k));
      const it = +ks[Math.floor(rnd() * ks.length)]; G.held[it] = (G.held[it] || 0) + 1; B.hdrop = it;
    }
    if (B.th >= 3 && rnd() < 0.15 + B.th * 0.03 + mod('stone')) {
      const its = Object.keys(DB.dex.items).map(Number); const it = its[Math.floor(rnd() * its.length)];
      G.items[it] = (G.items[it] || 0) + 1; B.drop = it;
    }
  }
  save(); playMusic((DB.ts[B.set].game === 'E' ? '_e' : '_') + (won ? 'win' : 'lose'));
  showResult();
}

/* ---------- drawing ---------- */
const SPR = 1.5, FXS = 1.5, ESPR = SPR * 0.9;   // wild Pokémon are drawn 10% smaller than your team   // Pokémon and move effects are drawn bigger than their sheets so they read on any screen
function drawMon(g, id, name, t, row, x, y, alpha, loop, sc) {
  sc = sc || SPR;
  const A = DB.anim[id]; if (!A) return;
  const a = A[name] || A.Idle || A.Walk; if (!a) return;
  const im = monImg(id); if (!im.complete || !im.naturalWidth) return;
  const tot = a.d.reduce((s, v) => s + v, 0); let ft = Math.floor(t * 60);
  ft = loop === false ? Math.min(ft, tot - 1) : ft % tot;
  let f = 0; while (f < a.n - 1 && ft >= a.d[f]) { ft -= a.d[f]; f++; }
  const r = a.r > 1 ? row : 0;
  if (alpha != null) g.globalAlpha = alpha;
  const gp = a.sh ? a.sh[Math.min(r, a.sh.length - 1)] : [a.fw / 2, a.fh / 2 + 4];   // the sheet's own ground point lands on (x, y)
  g.drawImage(im, f * a.fw, a.y + r * a.fh, a.fw, a.fh, Math.round(x - gp[0] * sc), Math.round(y - gp[1] * sc), a.fw * sc, a.fh * sc);
  g.globalAlpha = 1;
}
/* the ROM draws every projectile in one orientation; these have a clear front, so they're turned to face where they fly.
   value = which way the front points in the sheet (radians; 0 = right, PI/2 = down) */
const PROJ_FRONT = { 'efob013/anim48': Math.PI / 2, 'efob136/anim16': Math.PI / 2, 'efob136/anim24': Math.PI / 2, 'efob062/anim00': Math.PI / 2,
  'efob052/anim00': Math.PI / 2, 'efob118/anim00': Math.PI / 2, 'efob013/anim32': Math.PI / 2, 'efob013/anim08': 0,
  'efob069/anim00': Math.PI / 2, 'efob127/anim00': Math.PI / 2, 'efob013/anim16': -Math.PI / 2 };   // Megahorn and Icicle Spear lead with their point; Mud Shot's stack is aligned with its flight
for (const k of Object.keys(PROJ_FRONT)) PROJ_FRONT['eos' + k.slice(4)] = PROJ_FRONT[k];
function drawFxAnim(g, a, t, row, x, y, rot) {
  const im = img('img/fx/' + a.f + '.png'); if (!im.complete || !im.naturalWidth) return;
  let ft = Math.floor(t * 60), f = 0; const tot = a.d.reduce((s, v) => s + v, 0); ft %= tot;
  while (f < a.n - 1 && ft >= a.d[f]) { ft -= a.d[f]; f++; }
  const ax = (a.ox != null ? a.ox : a.fw / 2) * FXS, ay = (a.oy != null ? a.oy : a.fh / 2) * FXS;   // Explorers of Sky sheets carry their anchor point; Red's are centred
  if (rot) { g.save(); g.translate(Math.round(x), Math.round(y)); g.rotate(rot); g.drawImage(im, f * a.fw, 0, a.fw, a.fh, -ax, -ay, a.fw * FXS, a.fh * FXS); g.restore(); return; }
  g.drawImage(im, f * a.fw, (a.r > 1 ? row : 0) * a.fh, a.fw, a.fh, Math.round(x - ax), Math.round(y - ay), a.fw * FXS, a.fh * FXS);
}
function drawDigits(g, txt, x, y, kind, sc) {
  sc = sc || 1;
  const im = img(kind === 3 ? 'img/dmg_b.png' : 'img/dmg_r.png');
  if (txt === 'MISS') { if (im.complete) g.drawImage(im, 12 * 8, 0, 32, 8, Math.round(x - 16 * sc), Math.round(y), 32 * sc, 8 * sc); return; }
  if (/^\d+$/.test(txt) && im.complete) { const w = txt.length * 7 * sc; for (let i = 0; i < txt.length; i++) g.drawImage(im, (+txt[i]) * 8, 0, 8, 8, Math.round(x - w / 2 + i * 7 * sc), Math.round(y), 8 * sc, 8 * sc); return; }
  g.font = '11px pmd, monospace'; g.textAlign = 'center'; g.fillStyle = '#000'; g.fillText(txt, x + 1, y + 9); g.fillStyle = kind === 2 ? '#ffe040' : kind === 4 ? '#ffa0c0' : '#8ff'; g.fillText(txt, x, y + 8);
}
function drawBattle(g) {
  const M = B.M;
  g.drawImage(M.cv, 0, 0);
  // range ring for the selected / ghost tower
  const ring = (x, y, r, ok) => {
    g.beginPath(); g.arc(x, y, r, 0, 7); const gr = g.createRadialGradient(x, y, r * 0.2, x, y, r);
    gr.addColorStop(0, ok ? 'rgba(255,255,255,0)' : 'rgba(255,40,40,.05)'); gr.addColorStop(1, ok ? 'rgba(160,210,255,.22)' : 'rgba(255,40,40,.3)'); g.fillStyle = gr; g.fill();
    g.save(); g.setLineDash([6, 5]); g.lineDashOffset = -B.time * 14; g.lineWidth = 1.5; g.strokeStyle = ok ? 'rgba(255,255,255,.75)' : 'rgba(255,80,80,.8)'; g.stroke(); g.restore();
  };
  drawGates(g, M);
  if (B.sel) { const r = Math.max(...B.sel.e.mv.filter(moveUse).map(m => towerRange(B.sel, m)), 40); ring(B.sel.x, B.sel.y, r, true); }
  if (B.ghost && B.placing) { const r = Math.max(...B.placing.mv.filter(moveUse).map(m => RANGE[mv(m).c] * (1 + Math.min(0.25, B.placing.lv / 400))), 40); ring(B.ghost.x, B.ghost.y, r, B.ghost.ok); }
  drawSkills(g);   // traps and decoys under the Pokémon
  const ents = [];
  for (const t of B.towers) ents.push({ y: t.y, f: () => { if (B.sel === t) { const p = 0.5 + 0.5 * Math.sin(B.time * 6); g.beginPath(); g.ellipse(t.x, t.y, 15 * SPR, 6 * SPR, 0, 0, 7); g.strokeStyle = `rgba(255,216,74,${0.5 + 0.5 * p})`; g.lineWidth = 2; g.stroke(); g.lineWidth = 1; } marker(g, true, t.e.id, t.x, t.y, SPR); drawMon(g, t.e.id, t.anim, t.at, t.dir, t.x, t.y, null, t.anim === 'Idle'); if (t.buft > 0) { g.fillStyle = '#f84'; g.fillRect(t.x - 2, t.y - 30 * SPR, 4, 4); } } });
  for (const e of B.en) ents.push({ y: e.y, f: () => {
    if (e.d <= 0) return;
    let al = e.hp <= 0 ? clamp(e.dead / 0.5, 0, 1) : 1;
    if (e.hide && !(e.rev > 0)) al *= 0.28; if (e.under) al *= 0.12;
    const lift = (e.air ? 12 + Math.sin(B.time * 3 + e.ph) * 2.5 : 0) * ESPR;
    g.globalAlpha = al; marker(g, false, e.id, e.x, e.y, ESPR * (e.boss ? 1.3 : 1)); g.globalAlpha = 1;
    const A = DB.anim[e.id], walk = e.air && A && A.Hover ? 'Hover' : 'Walk';   // flyers use their Hover animation when the sheet has one (FlapAround turns in a full circle, so it isn't used)
    const an = e.hp <= 0 || e.hurt > 0 ? 'Hurt' : e.stop > 0 && e.sts ? 'Idle' : walk;
    const at = an === 'Hover' ? e.at * HOVER_SPEED : e.at;   // flight loops are short: played a bit slower so flapping isn't frantic
    drawMon(g, e.id, an, at, e.dir, e.x, e.y - lift, al, undefined, ESPR);
    if (e.hurt > 0.12 && e.hp > 0) flashMon(g, e.id, an, at, e.dir, e.x, e.y - lift, ESPR, (e.hurt - 0.12) * 5);   // white hit flash
    if (e.hp <= 0) koBurst(g, e.x, e.y - 10 * ESPR, 1 - clamp(e.dead / 0.5, 0, 1), e.boss);
    if (e.hp > 0 && (e.under || (e.hide && !(e.rev > 0)))) return;
    if (e.hp > 0 && e.sh > 0) { g.beginPath(); g.arc(e.x, e.y - 10 * ESPR - lift, (e.boss ? 22 : 15) * ESPR, 0, 7); g.fillStyle = 'rgba(120,220,120,.18)'; g.fill(); g.strokeStyle = 'rgba(160,255,160,.75)'; g.lineWidth = 1.5; g.stroke(); g.lineWidth = 1; }
    if (e.hp > 0 && (e.hp < e.max || e.boss || e.sh > 0 || B.selE === e)) {   // bars only once hurt (cleaner map); bosses always
      const w = e.boss ? 30 : 18, f = e.hp / e.max; e.hpd = e.hpd == null ? f : Math.max(f, e.hpd - 0.02);
      g.fillStyle = 'rgba(0,0,0,.75)'; g.fillRect(e.x - w / 2 - 1, e.y + 5, w + 2, 5);
      g.fillStyle = 'rgba(255,255,255,.55)'; g.fillRect(e.x - w / 2, e.y + 6, w * e.hpd, 3);   // recent damage trails behind
      g.fillStyle = f > 0.5 ? '#46d846' : f > 0.2 ? '#ffcc33' : '#ff4040'; g.fillRect(e.x - w / 2, e.y + 6, w * f, 3);
      g.fillStyle = 'rgba(255,255,255,.35)'; g.fillRect(e.x - w / 2, e.y + 6, w * f, 1);
      if (e.sh > 0) { g.fillStyle = '#9f9'; g.fillRect(e.x - w / 2, e.y + 4, w * e.sh / e.shm, 1); }
      if (e.sts) { g.fillStyle = { paralysis: '#ff0', sleep: '#aaf', freeze: '#8ff', burn: '#f60', poison: '#c4f', confusion: '#f8c', trap: '#a84', yawn: '#ccc', 'leech-seed': '#6c3' }[e.sts]; g.fillRect(e.x + w / 2 + 2, e.y + 6, 4, 4); }
    }
  } });
  ents.sort((a, b) => a.y - b.y); for (const e of ents) e.f();
  if (B.ghost && B.placing) { marker(g, true, B.placing.id, B.ghost.x, B.ghost.y, SPR); drawMon(g, B.placing.id, 'Idle', B.time, 0, B.ghost.x, B.ghost.y, B.ghost.ok ? 0.8 : 0.4); }
  if (B.zap) for (const z of B.zap) {   // Electric: Chain - a short zigzag between the two enemies
    const [ax, ay] = z.a, [bx, by] = z.b, n = 5; g.save(); g.strokeStyle = 'rgba(255,240,120,' + Math.min(1, z.t / 0.1) + ')'; g.lineWidth = 2; g.beginPath(); g.moveTo(ax, ay - 8 * ESPR);
    for (let i = 1; i < n; i++) { const k = i / n; g.lineTo(ax + (bx - ax) * k + (rnd() - 0.5) * 10, ay + (by - ay) * k - 8 * ESPR + (rnd() - 0.5) * 10); }
    g.lineTo(bx, by - 8 * ESPR); g.stroke(); g.restore();
  }
  for (const p of B.proj) drawFxAnim(g, DB.fx.anims[p.fx], p.at, p.row || 0, p.x, p.y, PROJ_FRONT[p.fx] != null && p.ang != null ? p.ang - PROJ_FRONT[p.fx] : 0);
  for (const f of B.fx) drawFxAnim(g, f.a, f.t, f.row, f.x, f.y, f.rot);
  for (const f of B.fl) { const pop = 1 + Math.max(0, 0.12 - f.t) * 5, a = f.t > 0.65 ? 1 - (f.t - 0.65) / 0.25 : 1; g.globalAlpha = clamp(a, 0, 1); drawDigits(g, f.txt, f.x, f.y - f.t * 22, f.kind, 1.35 * pop); g.globalAlpha = 1; }
  if (B.weather) drawWeather(g, M);
}
/* PMD Red's own weather screens (rain, sandstorm, hail) tiled over the map; sun has none in the ROM, so it's a warm tint */
function drawWeather(g, M) {
  const k = B.weather.k, w = DB.wx[k], im = w && img('img/wx/' + k + '.png');
  if (k === 'sun') { g.fillStyle = WEATHER[k][2]; g.fillRect(0, 0, M.W * TZ, M.H * TZ); sunRays(g, M); return; }
  if (!w || !im.complete || !im.naturalWidth) { g.fillStyle = WEATHER[k][2]; g.fillRect(0, 0, M.W * TZ, M.H * TZ); return; }
  const f = Math.floor(B.time * 1000 / w.ms) % w.n, sx = (f % w.per) * w.fw, sy = Math.floor(f / w.per) * w.fh;
  if (k === 'rain' || k === 'hail') { g.fillStyle = k === 'rain' ? 'rgba(15,25,60,.22)' : 'rgba(30,45,75,.16)'; g.fillRect(0, 0, M.W * TZ, M.H * TZ); }   // overcast, so the falling streaks stand out
  g.save();
  if (w.blend === 'lighter') g.globalCompositeOperation = 'lighter'; else g.globalAlpha = 0.4;
  for (let y = 0; y < M.H * TZ; y += w.fh) for (let x = 0; x < M.W * TZ; x += w.fw) g.drawImage(im, sx, sy, w.fw, w.fh, x, y, w.fw, w.fh);
  g.restore();
}
/* sunlight: soft diagonal shafts of warm light that drift and shimmer across the map (drawn, not from the ROM: PMD Red has no sunlight screen) */
let RAY = null;
function rayTex() {   // one soft shaft, faded at both sides and toward the bottom; stretched and turned for every ray
  if (RAY) return RAY; RAY = document.createElement('canvas'); RAY.width = 64; RAY.height = 256; const c = RAY.getContext('2d');
  const h = c.createLinearGradient(0, 0, 64, 0); h.addColorStop(0, 'rgba(255,236,170,0)'); h.addColorStop(0.35, 'rgba(255,244,200,.85)'); h.addColorStop(0.5, 'rgba(255,250,225,1)'); h.addColorStop(0.65, 'rgba(255,244,200,.85)'); h.addColorStop(1, 'rgba(255,236,170,0)');
  c.fillStyle = h; c.fillRect(0, 0, 64, 256); c.globalCompositeOperation = 'destination-in';
  const v = c.createLinearGradient(0, 0, 0, 256); v.addColorStop(0, 'rgba(0,0,0,1)'); v.addColorStop(0.7, 'rgba(0,0,0,.7)'); v.addColorStop(1, 'rgba(0,0,0,0)');
  c.fillStyle = v; c.fillRect(0, 0, 64, 256); return RAY;
}
function sunRays(g, M) {
  const W = M.W * TZ, H = M.H * TZ, tex = rayTex(), ang = 0.42, len = H / Math.cos(ang) * 1.15, T = B.time, n = 7;
  g.save(); g.globalCompositeOperation = 'screen';
  const glow = g.createRadialGradient(0, 0, 0, 0, 0, Math.max(W, H) * 0.7); glow.addColorStop(0, 'rgba(255,220,140,.22)'); glow.addColorStop(1, 'rgba(255,220,140,0)');
  g.fillStyle = glow; g.fillRect(0, 0, W, H);   // the sun sits off the top-left corner, where the rays come from
  for (let i = 0; i < n; i++) {
    const base = (i + 0.5) / n, x = (-0.25 + base * 1.15) * W + Math.sin(T * 0.11 + i * 1.7) * W * 0.03;   // slow drift
    const w = W * (0.035 + 0.05 * ((i * 0.618) % 1)) * (1 + 0.15 * Math.sin(T * 0.3 + i));
    g.globalAlpha = 0.3 + 0.18 * (0.5 + 0.5 * Math.sin(T * 0.6 + i * 2.3));   // shimmer
    g.save(); g.translate(x, -H * 0.05); g.rotate(-ang); g.drawImage(tex, -w / 2, 0, w, len); g.restore();
  }
  g.restore();
}
/* a white silhouette of the current frame, for hit flashes */
const FLASH = document.createElement('canvas'), FG = FLASH.getContext('2d');
function flashMon(g, id, name, t, row, x, y, sc, a) {
  const A = DB.anim[id]; if (!A) return; const an = A[name] || A.Idle || A.Walk; if (!an) return;
  FLASH.width = Math.ceil(an.fw * sc) + 2; FLASH.height = Math.ceil(an.fh * sc) + 2; FG.imageSmoothingEnabled = false;
  const gp = an.sh ? an.sh[Math.min(an.r > 1 ? row : 0, an.sh.length - 1)] : [an.fw / 2, an.fh / 2 + 4];
  FG.clearRect(0, 0, FLASH.width, FLASH.height); drawMon(FG, id, name, t, row, gp[0] * sc, gp[1] * sc, null, true, sc);
  FG.globalCompositeOperation = 'source-atop'; FG.fillStyle = '#fff'; FG.fillRect(0, 0, FLASH.width, FLASH.height); FG.globalCompositeOperation = 'source-over';
  g.globalAlpha = clamp(a, 0, 0.85); g.drawImage(FLASH, Math.round(x - gp[0] * sc), Math.round(y - gp[1] * sc)); g.globalAlpha = 1;
}
/* knockout: a quick ring and sparks */
function koBurst(g, x, y, k, big) {
  const R = (big ? 26 : 14) * (0.4 + k), a = 1 - k; if (a <= 0) return;
  g.save(); g.globalAlpha = a * 0.8; g.strokeStyle = '#fff'; g.lineWidth = 2 * (1 - k) + 0.5; g.beginPath(); g.arc(x, y, R, 0, 7); g.stroke();
  g.fillStyle = '#ffe680'; for (let i = 0; i < 8; i++) { const an = i * Math.PI / 4 + 0.4; g.fillRect(x + Math.cos(an) * R * 1.25 - 1.5, y + Math.sin(an) * R * 1.25 - 1.5, 3, 3); }
  g.restore();
}
/* where wild Pokémon come in (green) and where they escape (red, pulsing) */
function drawGates(g, M) {
  const W = M.W * TZ, H = M.H * TZ, p = 0.5 + 0.5 * Math.sin(B.time * 4), seen = new Set();
  const gate = (pt, nx, ny, col) => {
    const x = clamp(pt[0], 10, W - 10), y = clamp(pt[1], 10, H - 10), k = x + ',' + y; if (seen.has(k)) return; seen.add(k);
    const gr = g.createRadialGradient(x, y, 2, x, y, 30); gr.addColorStop(0, col.replace('A', 0.45 + 0.25 * p)); gr.addColorStop(1, col.replace('A', 0)); g.fillStyle = gr; g.beginPath(); g.arc(x, y, 30, 0, 7); g.fill();
    g.save(); g.translate(x, y); g.rotate(Math.atan2(ny, nx)); g.fillStyle = col.replace('A', 0.85);
    for (let i = 0; i < 2; i++) { const o = ((B.time * 18 + i * 9) % 18) - 9; g.beginPath(); g.moveTo(o - 4, -6); g.lineTo(o + 4, 0); g.lineTo(o - 4, 6); g.lineTo(o - 1, 0); g.closePath(); g.fill(); }
    g.restore();
  };
  for (const r of M.routes) { const l = r.line, a = l[0], b = l[1], z = l[l.length - 1], y2 = l[l.length - 2]; gate(a, b[0] - a[0], b[1] - a[1], 'rgba(90,230,120,A)'); gate(z, z[0] - y2[0], z[1] - y2[1], 'rgba(255,70,70,A)'); }
}
const MKS = ['small', 'medium', 'large'];
function marker(g, team, id, x, y, sc) {   // PMD Red's own markers: yellow ring under your team, dark shadow under wild Pokémon
  const sz = DB.mk[id] != null ? DB.mk[id] : 1, im = img('img/ui/' + (team ? 'team_' : 'enemy_') + MKS[sz] + '.png');
  if (!im.complete || !im.naturalWidth) return shadow(g, x, y, sz === 2, sc);
  const w = im.naturalWidth * sc, h = im.naturalHeight * sc; g.drawImage(im, Math.round(x - w / 2), Math.round(y - h / 2), w, h);
}
function shadow(g, x, y, big, sc) {
  sc = sc || SPR; g.fillStyle = 'rgba(0,0,0,.28)'; g.beginPath(); g.ellipse(x, y, (big ? 12 : 8) * sc, (big ? 5 : 3.5) * sc, 0, 0, 7); g.fill(); }

/* ---------- move skills: status moves given a tower-defence job (each one picked by the player, Nov 2026).
   They work on their own timer, beside the Pokémon's attacks. Effects use each move's own graphics. ---------- */
let SKILL = null, SKID = {};
const MID = n => SKID[n] || (SKID[n] = +(Object.keys(DB.dex.moves).find(k => DB.dex.moves[k].n === n) || 0));
const hasM = (t, n) => t.e.mv.includes(MID(n));
function skR(t) { return RANGE[3] * (1 + Math.min(0.25, t.e.lv / 400) + mod('range')) * upK(t, 0) * (hasT(t, 2) ? 1.15 : 1) * (t.acu && t.acu.k === 'r' && t.acu.u > B.time ? 1.2 : 1); }
const visible = e => e.hp > 0 && e.d > 0 && !e.under && !(e.hide && !(e.rev > 0));
const skIn = (t, r) => B.en.filter(e => visible(e) && Math.hypot(e.x - t.x, e.y - t.y) <= (r || skR(t)));
const skT = t => { const l = skIn(t); return l.length ? chooseTarget(t, l) : null; };
const stopE = (e, s) => { e.stop = Math.max(e.stop, e.boss ? s / 2 : s); meterCtl(B.msrc, e.boss ? s / 2 : s); };
const slowE = (e, k, f, d) => { (e.sl || (e.sl = {}))[k] = [f, B.time + d]; meterCtl(B.msrc, d * (1 - f) * 2); };   // meter: slow seconds weighted by strength
function skSpeed(e) { let v = 1; if (e.sl) for (const k in e.sl) { const [f, u] = e.sl[k]; if (u > B.time) v *= f; else delete e.sl[k]; } if (e.tr && e.tr[1] > B.time) v *= e.tr[0]; return v; }
function enTypes(e) { const o = e.tyo; if (!o || o.u <= B.time) return SP[e.id].t; return o.add ? [...new Set(SP[e.id].t.concat(o.t))].slice(0, 3) : o.t; }
function skFx(m, x, y, dir) { const f = DB.fx.moves[m]; if (f) { const r = f.h || f.u; if (r) addFx(r, x, y - 8 * ESPR, dir || 0); } }
function skUse(t, m, e) { const f = DB.fx.moves[m]; if (f && f.u) addFx(f.u, t.x, t.y, t.dir); if (e) { t.dir = dirRow(e.x - t.x, e.y - t.y); skFx(m, e.x, e.y, t.dir); } t.anim = 'Shoot'; t.at = 0; }
const near = (t, r) => B.towers.filter(o => o !== t && Math.hypot(o.x - t.x, o.y - t.y) <= (r || 90));
function skAttack(t, m, st, src) {   // a full attack from a skill (Copycat, Metronome, Nature Power): same hit rules as a normal attack
  const M = mv(m); if (!M) return false; const r = RANGE[M.c] ? towerRange(t, m) : skR(t), list = inRange(t, r).filter(e => canHit(t, m, e)); if (!list.length) return false;
  const tg = chooseTarget(t, list), fx = DB.fx.moves[m] || {}; t.dir = dirRow(tg.x - t.x, tg.y - t.y); t.anim = M.c === 2 ? 'Attack' : 'Shoot'; t.at = 0;
  if (fx.u) addFx(fx.u, t.x, t.y, t.dir);
  const hit = g => { const ts = aoe(M) ? (M.c === 3 ? B.en.filter(e => e.hp > 0 && Math.hypot(e.x - g.x, e.y - g.y) < 46 && canHit(t, m, e)) : list) : [g]; for (const e of ts) applyMove(t, m, e, st); };
  if (fx.p && M.c !== 2) B.proj.push({ x: t.x, y: t.y - 8 * SPR, tg, fx: fx.p, sp: 300, at: 0, done: hit, hfx: fx.h });
  else { B.q2 = B.q2 || []; B.q2.push({ t: 0.12, fn: () => { if (tg.hp > 0 || aoe(M)) { hit(tg); if (fx.h) addFx(fx.h, tg.x, tg.y - 8 * ESPR, t.dir); } } }); }
  if (src) floater(t, src, 4); return true;
}
function natureMove() {   // Nature Power, Gen VII rules: the move depends on where the battle is
  const terr = B.terr || {}, now = B.time;
  if (terr[11] > now) return 'Energy Ball'; if (terr[17] > now) return 'Moonblast'; if (terr[12] > now) return 'Thunderbolt'; if (terr[13] > now) return 'Psychic';
  const S = DB.ts[B.set], T = S.types || [], nm = S.name || '';
  if (B.M.liq === 'lava') return 'Lava Plume';
  if (T.includes(14)) return 'Ice Beam';
  if (B.M.liq === 'water' && T.includes(10)) return 'Hydro Pump';
  if (/cave|cavern|crevice|grotto|ruin|tunnel|depth|crater|chamber|underground/i.test(nm)) return 'Power Gem';
  if (T.includes(11) || /wood|forest|jungle|meadow|field|garden|grass/i.test(nm)) return 'Energy Ball';
  if (T.includes(4) || T.includes(5) || /sand|desert|mt |mount|peak|rock|cliff|canyon/i.test(nm)) return 'Earth Power';
  return 'Tri Attack';
}
function nearestPath(x, y) { let b = null; B.M.routes.forEach((rt, r) => { for (let d = 0; d < rt.len; d += 6) { const [px, py] = pathAt(B.M, d, rt); const k = Math.hypot(px - x, py - y); if (!b || k < b.k) b = { r, d, x: px, y: py, k }; } }); return b; }
const SLOWA = (f, d, key) => (t, m) => { const l = skIn(t); if (!l.length) return false; for (const e of l) slowE(e, key || 'growl', f, d); skUse(t, m, l[0]); return true; };
const STOP1 = s => (t, m) => { const e = skT(t); if (!e) return false; stopE(e, s); skUse(t, m, e); return true; };
const TYPEC = (ty, add) => (t, m) => { const e = skT(t); if (!e) return false; e.tyo = { t: [ty], add, u: B.time + 6 }; skUse(t, m, e); return true; };
const NOTRICK = (t, m) => { const l = skIn(t).filter(e => e.prot || e.heal || e.dashMv || e.tele); const e = l.length ? chooseTarget(t, l) : null; if (!e) return false; e.nt = B.time + 6; floater(e, 'No tricks', 4); skUse(t, m, e); return true; };
const TRAP = kind => (t, m) => { if (!t.tp) t.tp = nearestPath(t.x, t.y); if (!t.tp) return false; B.traps = (B.traps || []).filter(x => x.t !== t || x.m !== m); B.traps.push({ t, m, kind, r: t.tp.r, d: t.tp.d, x: t.tp.x, y: t.tp.y, hit: new Set() }); return true; };
const DECOY = (t, m) => { const p = nearestPath(t.x, t.y); if (!p) return false; B.decoys = (B.decoys || []).filter(x => x.t !== t); B.decoys.push({ t, m, r: p.r, d: p.d, x: p.x, y: p.y, u: 0 }); return true; };
const TEAMB = (key, dur) => (t, m) => { if (!B.en.some(visible)) return false; for (const o of B.towers) o[key] = B.time + dur; skUse(t, m); floater(t, mv(m).n, 4); return true; };
const NEARB = (key, dur) => (t, m) => { const n = near(t); if (!n.length || !B.en.some(visible)) return false; for (const o of n) o[key] = B.time + dur; skUse(t, m); return true; };
const SELFB = (key, dur) => (t, m) => { if (!skIn(t, skR(t) * 1.2).length) return false; t[key] = B.time + dur; skUse(t, m); return true; };
const WXSK = k => (t, m) => { if (!B.en.some(visible) || B.bwx || B.pwx) return false; B.mwx = { k, until: B.time + 20 }; syncWeather(); skUse(t, m); floater(t, mv(m).n, 4); return true; };
const TERRAIN = ty => (t, m) => { if (!B.en.some(visible)) return false; (B.terr || (B.terr = {}))[ty] = B.time + 10; skUse(t, m); floater(t, mv(m).n, 4); return true; };
const COPYB = (t, m) => { const l = skIn(t).filter(e => e.bst && e.bst[6] > 0); if (!l.length) return false; const e = l[0]; t.buf[5] = Math.max(t.buf[5], e.bst[6]); t.buft = 12; skUse(t, m, e); return true; };
const COPYCAT = (t, m) => { const o = near(t, 1e9).sort((a, b) => Math.hypot(a.x - t.x, a.y - t.y) - Math.hypot(b.x - t.x, b.y - t.y))[0]; if (!o) return false;
  const ms = o.e.mv.filter(x => moveUse(x) === 'dmg').sort((a, b) => (mv(b).p || 0) - (mv(a).p || 0)); return ms.length ? skAttack(t, ms[0], monStats(o.e), mv(m).n) : false; };
function buildSkills() {
  const D = {   // name: [cooldown s, action(t, move) -> used?] ; passive ones have no action (handled where they matter)
    'Growl': [6, SLOWA(0.8, 3)], 'Baby-Doll Eyes': [6, SLOWA(0.8, 3)], 'Play Nice': [6, SLOWA(0.8, 3)], 'Feather Dance': [6, SLOWA(0.8, 3)], 'Noble Roar': [6, SLOWA(0.8, 3)],
    'Parting Shot': [6, SLOWA(0.8, 3)], 'Eerie Impulse': [6, SLOWA(0.8, 3)], 'Confide': [6, SLOWA(0.8, 3)],
    'Sand Attack': [6, STOP1(0.6)], 'Mean Look': [12, STOP1(1)], 'Block': [12, STOP1(1)], 'Attract': [12, STOP1(1.2)],
    'Quash': [10, (t, m) => { const e = skT(t); if (!e) return false; slowE(e, 'quash', 0.5, 2); skUse(t, m, e); return true; }],
    'Smokescreen': [8, (t, m) => { const l = skIn(t); if (!l.length) return false; for (const e of l) e.stop = Math.max(e.stop, 0.4); skUse(t, m, l[0]); return true; }],
    'Fairy Lock': [30, (t, m) => { const l = skIn(t); if (!l.length) return false; for (const e of l) stopE(e, 1); skUse(t, m, l[0]); return true; }],
    'Charm': [8, (t, m) => { const e = skT(t); if (!e) return false; e.back = B.time + (e.boss ? 0.75 : 1.5); skUse(t, m, e); return true; }],
    'Roar': [10, (t, m) => { const l = skIn(t).filter(e => !e.boss); const e = l.length ? chooseTarget(t, l) : null; if (!e) return false; e.d = Math.max(1, e.d - 60); e.px = null; skUse(t, m, e); return true; }],
    'Curse': [12, (t, m) => { const e = skT(t); if (!e) return false; e.cu = { left: e.max * (e.boss ? 0.1 : 0.25), dps: e.max * (e.boss ? 0.1 : 0.25) / 8, t }; skUse(t, m, e); return true; }],
    'Disable': [8, NOTRICK],
    'Soak': [8, TYPEC(10, false)], 'Magic Powder': [8, TYPEC(13, false)], 'Trick-or-Treat': [8, TYPEC(7, true)], 'Forest’s Curse': [8, TYPEC(11, true)],
    'Electrify': [12, (t, m) => { const e = skT(t); if (!e) return false; e.elz = B.time + 6; skUse(t, m, e); return true; }],
    'Gastro Acid': [10, (t, m) => { const l = skIn(t).filter(e => e.ak && !e.akOff); const e = l.length ? chooseTarget(t, l) : null; if (!e) return false; e.ak0 = e.ak; e.ak = null; e.akOff = B.time + 8; floater(e, 'Ability off', 4); skUse(t, m, e); return true; }],
    'Haze': [10, (t, m) => { const l = skIn(t).filter(e => e.bst && Object.values(e.bst).some(v => v > 0)); if (!l.length) return false; for (const e of l) e.bst = { 3: 0, 5: 0, 6: 0 }; skUse(t, m, l[0]); return true; }],
    'Topsy-Turvy': [12, (t, m) => { const l = skIn(t).filter(e => e.bst && Object.values(e.bst).some(v => v > 0)); if (!l.length) return false; const e = l[0]; for (const k in e.bst) e.bst[k] = -e.bst[k]; skUse(t, m, e); return true; }],
    'Pain Split': [15, (t, m) => { const l = skIn(t).filter(e => !e.boss && e.hp > e.max / 2); const e = l.length ? chooseTarget(t, l) : null; if (!e) return false; const to = Math.ceil((e.hp + e.max / 2) / 2); hurt(t, e, e.hp - to); skUse(t, m, e); return true; }],
    'Guard Split': [12, (t, m) => { const e = skT(t); if (!e) return false; e.gs = B.time + 6; e.gsf = 0.75; skUse(t, m, e); return true; }],
    'Octolock': [14, (t, m) => { const e = skT(t); if (!e) return false; stopE(e, 1); e.gs = B.time + 6; e.gsf = 0.8; skUse(t, m, e); return true; }],
    'Perish Song': [30, (t, m) => { const l = skIn(t).filter(e => !e.boss && !e.pm); if (!l.length) return false; for (const e of l) { e.pm = B.time + 6; e.pmT = t; } skUse(t, m, l[0]); floater(t, 'Perish Song', 4); return true; }],
    'Sweet Scent': [10, (t, m) => { const l = skIn(t); if (!l.length) return false; for (const e of l) e.lure = B.time + 5; skUse(t, m, l[0]); return true; }],
    'Psych Up': [15, COPYB], 'Heart Swap': [15, COPYB],
    'Trick Room': [30, (t, m) => { const l = skIn(t); if (l.length < 2) return false; const s = l.map(e => e.spd), lo = Math.min(...s), hi = Math.max(...s); for (const e of l) e.tr = [clamp((lo + hi - e.spd) / e.spd, 0.4, 1.5), B.time + 6]; skUse(t, m, l[0]); return true; }],
    'Psycho Shift': [10, (t, m) => { const l = skIn(t), a = l.find(e => e.sts && e.sts !== 'yawn'), b = a && l.find(e => e !== a && !e.sts); if (!b) return false; inflict(b, a.sts, t); skUse(t, m, b); return true; }],
    'Speed Swap': [12, (t, m) => { const e = skT(t); if (!e) return false; slowE(e, 'swap', 0.6, 4); t.ssw = B.time + 4; skUse(t, m, e); return true; }],
    'Focus Energy': [20, SELFB('fe', 10)], 'Take Heart': [15, SELFB('th', 8)], 'Double Team': [20, SELFB('dt', 5)],
    'Laser Focus': [8, (t, m) => { if (t.lf) return false; t.lf = 1; return true; }], 'Charge': [8, (t, m) => { if (t.chg) return false; t.chg = 1; return true; }],
    'Acupressure': [15, (t, m) => { if (!skIn(t, skR(t) * 1.2).length) return false; t.acu = { k: pick(['d', 's', 'r']), u: B.time + 6 }; skUse(t, m); floater(t, { d: 'Power up', s: 'Speed up', r: 'Range up' }[t.acu.k], 4); return true; }],
    'Helping Hand': [15, NEARB('hh', 6)], 'Encore': [10, (t, m) => { const n = near(t).filter(o => !o.enc); if (!n.length || !B.en.some(visible)) return false; n[0].enc = 1; skUse(t, m); return true; }],
    'Tailwind': [30, TEAMB('tw', 6)],
    'Rain Dance': [60, WXSK('rain')], 'Sunny Day': [60, WXSK('sun')], 'Sandstorm': [60, WXSK('sand')], 'Hail': [60, WXSK('hail')], 'Snowscape': [60, WXSK('hail')],
    'Electric Terrain': [30, TERRAIN(12)], 'Grassy Terrain': [30, TERRAIN(11)], 'Misty Terrain': [30, TERRAIN(17)], 'Psychic Terrain': [30, TERRAIN(13)],
    'Stealth Rock': [20, TRAP('rock')], 'Spikes': [20, TRAP('spikes')], 'Toxic Spikes': [20, TRAP('toxic')], 'Sticky Web': [20, TRAP('web')],
    'Substitute': [20, DECOY], 'Shed Tail': [20, DECOY],
    'Copycat': [6, COPYCAT], 'Mimic': [6, COPYCAT],
    'Metronome': [5, (t, m) => { const all = Object.keys(DB.dex.moves).map(Number).filter(x => moveUse(x) === 'dmg' && !OHKO.has(x)); return skAttack(t, pick(all), monStats(t.e), 'Metronome'); }],
    'Nature Power': [6, (t, m) => { const n = natureMove(); return skAttack(t, MID(n), monStats(t.e), n); }],
    // passives (no action)
    'Endure': [0], 'Ingrain': [0], 'Baton Pass': [0], 'Lock-On': [0], 'Mind Reader': [0], 'Power Trick': [0], 'Defog': [0], 'Mist': [0], 'Transform': [0],
    'Teleport': [0], 'Ally Switch': [0], 'Sketch': [0], 'Splash': [0], 'Baneful Bunker': [0], 'Burning Bulwark': [0], 'Silk Trap': [0],
  };
  D['Whirlwind'] = D['Roar']; D['Instruct'] = D['Encore'];
  SKILL = {}; for (const n in D) { const id = MID(n); if (id) SKILL[id] = { n, cd: D[n][0], act: D[n][1] }; }
  return SKILL;
}
const skills = () => SKILL || buildSkills();
const SKDESC = {
  'Growl': 'Enemies in range move 20% slower for 3 s', 'Baby-Doll Eyes': 'Enemies in range move 20% slower for 3 s', 'Play Nice': 'Enemies in range move 20% slower for 3 s', 'Feather Dance': 'Enemies in range move 20% slower for 3 s',
  'Noble Roar': 'Enemies in range move 20% slower for 3 s', 'Parting Shot': 'Enemies in range move 20% slower for 3 s', 'Eerie Impulse': 'Enemies in range move 20% slower for 3 s', 'Confide': 'Enemies in range move 20% slower for 3 s',
  'Sand Attack': 'The target stops for 0.6 s (every 6 s)', 'Mean Look': 'The target stops for 1 s (every 12 s)', 'Block': 'The target stops for 1 s (every 12 s)', 'Attract': 'The target stops for 1.2 s (every 12 s)',
  'Quash': 'The target moves 50% slower for 2 s (every 10 s)', 'Smokescreen': 'Enemies in range stop for 0.4 s (every 8 s)', 'Fairy Lock': 'Enemies in range stop for 1 s (every 30 s)',
  'Charm': 'The target walks backward for 1.5 s (every 8 s)', 'Roar': 'Pushes the target back along the path (not bosses, every 10 s)', 'Whirlwind': 'Pushes the target back along the path (not bosses, every 10 s)',
  'Curse': 'The target loses 25% of its max HP over 8 s (bosses 10%, every 12 s)', 'Disable': 'The target can\'t shield, heal, dash or teleport for 6 s',
  'Soak': 'The target becomes pure Water type for 6 s', 'Magic Powder': 'The target becomes pure Psychic type for 6 s', 'Trick-or-Treat': 'The target also counts as Ghost type for 6 s', 'Forest’s Curse': 'The target also counts as Grass type for 6 s',
  'Electrify': 'Electric attacks deal double damage to the target for 6 s (every 12 s)', 'Gastro Acid': 'The target\'s ability stops working for 8 s',
  'Haze': 'Removes the stat boosts of enemies in range (every 10 s)', 'Topsy-Turvy': 'Turns an enemy\'s stat boosts into drops (every 12 s)',
  'Pain Split': 'A non-boss target over half HP loses about a quarter of its max HP (every 15 s)', 'Guard Split': 'The target\'s defences drop 25% for 6 s (every 12 s)',
  'Octolock': 'The target stops for 1 s, then its defences drop 20% for 6 s (every 14 s)', 'Perish Song': 'Non-boss enemies in range lose 30% of their max HP 6 s later (every 30 s)',
  'Sweet Scent': 'Enemies in range are 2x as likely to ask to join if knocked out within 5 s', 'Psych Up': 'Copies an enemy\'s Speed boosts as attack speed (every 15 s)', 'Heart Swap': 'Copies an enemy\'s Speed boosts as attack speed (every 15 s)',
  'Trick Room': 'For 6 s the fastest enemies in range become the slowest (every 30 s)', 'Psycho Shift': 'Copies a status condition onto another enemy in range (every 10 s)',
  'Speed Swap': 'The target moves 40% slower and this Pokémon attacks 40% faster for 4 s (every 12 s)',
  'Focus Energy': 'Much higher critical-hit chance for 10 s (every 20 s)', 'Laser Focus': 'Every 8 s its next attack is a sure critical hit', 'Charge': 'Every 8 s its next Electric attack deals double damage',
  'Double Team': 'For 5 s its attacks hit twice (every 20 s)', 'Take Heart': 'Its special attacks deal +20% for 8 s (every 15 s)', 'Acupressure': 'A random boost for 6 s: +30% damage, attack speed or +20% range (every 15 s)',
  'Helping Hand': 'Teammates close by deal +25% damage for 6 s (every 15 s)', 'Encore': 'Every 10 s, the next attack of a teammate close by happens twice', 'Instruct': 'Every 10 s, the next attack of a teammate close by happens twice',
  'Tailwind': 'All your Pokémon attack 25% faster for 6 s (every 30 s)',
  'Rain Dance': 'Rain for 20 s (every 60 s)', 'Sunny Day': 'Sun for 20 s (every 60 s)', 'Sandstorm': 'A sandstorm for 20 s (every 60 s)', 'Hail': 'Hail for 20 s (every 60 s)', 'Snowscape': 'Hail for 20 s (every 60 s)',
  'Electric Terrain': 'Your team\'s Electric moves deal +30% for 10 s (every 30 s)', 'Grassy Terrain': 'Your team\'s Grass moves deal +30% for 10 s (every 30 s)',
  'Misty Terrain': 'Your team\'s Fairy moves deal +30% for 10 s (every 30 s)', 'Psychic Terrain': 'Your team\'s Psychic moves deal +30% for 10 s (every 30 s)',
  'Stealth Rock': 'Rocks on the nearest path: each enemy crossing takes Rock damage once (renewed every 20 s)', 'Spikes': 'Spikes on the nearest path: each enemy crossing loses 8% of its max HP once (renewed every 20 s)',
  'Toxic Spikes': 'Spikes on the nearest path poison enemies crossing (renewed every 20 s)', 'Sticky Web': 'A web on the nearest path: enemies crossing move 40% slower for 3 s (renewed every 20 s)',
  'Substitute': 'A decoy on the path holds enemies up for 2 s (every 20 s)', 'Shed Tail': 'A decoy on the path holds enemies up for 2 s (every 20 s)',
  'Copycat': 'Uses the nearest teammate\'s strongest attack at its power (every 6 s)', 'Mimic': 'Uses the nearest teammate\'s strongest attack at its power (every 6 s)',
  'Metronome': 'Uses a random attack (every 5 s)', 'Nature Power': 'Uses an attack that depends on the map (every 6 s)',
  'Endure': 'Attacks 30% faster while you have under 25 lives', 'Ingrain': '+5% damage for every 10 s it stays placed (up to +30%)', 'Baton Pass': 'Its stat boosts also apply to teammates close by',
  'Lock-On': 'Its attacks never miss', 'Mind Reader': 'Its attacks never miss', 'Power Trick': 'Physical attacks use its Attack or Defense, whichever is higher', 'Defog': 'Sees hidden Ghost types',
  'Mist': 'Bosses in its range can\'t raise their stats', 'Transform': 'Fights with the stats and moves of your strongest placed teammate, at its own level',
  'Teleport': 'Can be moved to a new spot during battle for free', 'Ally Switch': 'Can swap spots with a placed teammate during battle for free',
  'Sketch': 'Out of battle, can be swapped for a move learned by a Pokémon you\'ve seen', 'Splash': 'Enemies right next to it move 10% slower',
  'Baneful Bunker': 'Enemies right next to it may get poisoned', 'Burning Bulwark': 'Enemies right next to it may get burned', 'Silk Trap': 'Enemies right next to it move 30% slower for 2 s',
};
/* per-tick work: skill timers, traps, decoys, adjacency auras */
function skillTick(dt) {
  const S = skills(), wave = B.phase === 'wave';
  for (const t of B.towers) {
    t.skc = t.skc || {};
    for (const m of t.e.mv) { const s = S[m]; if (!s || !s.act) continue; if (!wave) continue; t.skc[m] = (t.skc[m] == null ? 1 + rnd() : t.skc[m]) - dt; if (t.skc[m] <= 0) { B.msrc = t; B.mlab = s.n; t.skc[m] = s.act(t, m) ? s.cd : 0.5; B.msrc = null; } }
    if (!wave) continue;
    const adj = [hasM(t, 'Splash') && 'sp', hasM(t, 'Silk Trap') && 'silk', hasM(t, 'Baneful Bunker') && 'bb', hasM(t, 'Burning Bulwark') && 'bw'].filter(Boolean);
    if (adj.length) for (const e of B.en) if (visible(e) && Math.hypot(e.x - t.x, e.y - t.y) < 38) {
      if (adj.includes('sp')) slowE(e, 'splash', 0.9, 1); if (adj.includes('silk')) slowE(e, 'silk', 0.7, 2); meterCtl(t, dt * (adj.includes('silk') ? 0.6 : 0.2));
      if (adj.includes('bb') && !e.sts && rnd() < 0.5 * dt) inflict(e, 'poison', t); if (adj.includes('bw') && !e.sts && rnd() < 0.5 * dt) inflict(e, 'burn', t);
    }
  }
  if (B.traps) for (const tr of B.traps) for (const e of B.en) if (visible(e) && !e.air && e.r === tr.r && Math.abs(e.d - tr.d) < 10 && !tr.hit.has(e)) {
    tr.hit.add(e); B.msrc = tr.t; B.mlab = mv(tr.m).n;
    if (tr.kind === 'rock') hurt(tr.t, e, Math.max(1, Math.floor(e.max * 0.125 * eff(5, enTypes(e)))));
    else if (tr.kind === 'spikes') hurt(tr.t, e, Math.max(1, Math.floor(e.max * 0.08)));
    else if (tr.kind === 'toxic') inflict(e, 'poison', tr.t);
    else if (tr.kind === 'web') slowE(e, 'web', 0.6, 3);
    B.msrc = null;
  }
  if (B.traps) B.traps = B.traps.filter(tr => B.towers.includes(tr.t));
  if (B.decoys) B.decoys = B.decoys.filter(dc => B.towers.includes(dc.t) && !(dc.u && dc.u < B.time));
  B.terr && Object.keys(B.terr).forEach(k => { if (B.terr[k] < B.time) delete B.terr[k]; });
  if (B.mwx && B.mwx.until < B.time) { B.mwx = null; syncWeather(); }
}
function decoyBlocks(e) { if (!B.decoys || e.air || e.boss) return false; for (const dc of B.decoys) if (dc.r === e.r && e.d < dc.d && dc.d - e.d < 8) { if (!dc.u) dc.u = B.time + 2; return true; } return false; }
function drawSkills(g) {   // traps and decoys, drawn with each move's own effect graphics
  for (const tr of B.traps || []) { const f = DB.fx.moves[tr.m], a = f && DB.fx.anims[f.h || f.u]; if (a) { g.save(); g.globalAlpha = 0.85; drawFxAnim(g, a, B.time % 1.2, 0, tr.x, tr.y, 0); g.restore(); } }
  for (const dc of B.decoys || []) { const f = DB.fx.moves[dc.m], a = f && DB.fx.anims[f.u || f.h]; if (a) drawFxAnim(g, a, B.time % 1, 0, dc.x, dc.y - 6, 0); }
}
function bufOf(t, k) { let v = t.buf[k]; for (const o of B.towers) if (o !== t && o.buft > 0 && hasM(o, 'Baton Pass') && Math.hypot(o.x - t.x, o.y - t.y) <= 90) v = Math.max(v, o.buf[k]); return v; }
function transformSrc(t) { if (!hasM(t, 'Transform')) return null; const o = B.towers.filter(x => x !== t && !hasM(x, 'Transform')).sort((a, b) => b.e.lv - a.e.lv)[0]; return o || null; }

/* ---------- damage meter: what each of your Pokémon did this battle (HP actually lost, no overkill, shields don't count) ---------- */
function mtr(t) { if (!t || !t.e || !B) return null; const M = B.meter || (B.meter = {}); return M[t.e.u] || (M[t.e.u] = { u: t.e.u, id: t.e.id, dmg: 0, ko: 0, dot: 0, ctl: 0, br: {} }); }
function meterDmg(t, amt, label, dot) { const m = mtr(t); if (!m || !(amt > 0)) return; m.id = t.e.id; m.dmg += amt; m.br[label] = (m.br[label] || 0) + amt; if (dot) m.dot += amt; }
function meterCtl(t, sec) { const m = mtr(t); if (m && sec > 0) m.ctl += sec; }
