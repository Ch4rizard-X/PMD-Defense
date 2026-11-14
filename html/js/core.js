/* Route Defense - core: data, assets, Pokémon maths, save */
'use strict';
const DB = {};
const SP = {};          // species id -> data
const TYPES = ['Normal','Fighting','Flying','Poison','Ground','Rock','Bug','Ghost','Steel','Fire','Water','Grass','Electric','Psychic','Ice','Dragon','Dark','Fairy'];
const TCOL = ['#a8a878','#c03028','#a890f0','#a040a0','#e0c068','#b8a038','#a8b820','#705898','#b8b8d0','#f08030','#6890f0','#78c850','#f8d030','#f85888','#98d8d8','#7038f8','#705848','#ee99ac'];
const rnd = Math.random;
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const pick = a => a[Math.floor(rnd() * a.length)];

async function loadDB() {
  for (const k of ['dex', 'anim', 'ts', 'fx', 'snd', 'tree', 'icons', 'wx', 'mk', 'micons']) {
    DB[k] = window.__BUNDLE ? (window.__DB || (window.__DB = JSON.parse(document.getElementById('__D').textContent)))[k] : await (await fetch('data/' + k + '.json')).json();
  }
  for (const m of DB.dex.mon) { m.anim = DB.anim[m.id] ? 1 : 0; m.bst = m.b.reduce((a, b) => a + b, 0); SP[m.id] = m; }
}
let AIDX = null; const ACACHE = {};
function asset(p) {             // in the single-file build each asset is a base64 text block; turn it into a blob URL on first use
  if (!window.__BUNDLE) return p;
  if (ACACHE[p]) return ACACHE[p];
  if (!AIDX) { AIDX = {}; for (const e of document.querySelectorAll('script[data-a]')) AIDX[e.dataset.a] = e; }
  const e = AIDX[p]; if (!e) return p;
  // data: URLs rather than blob: URLs - some file viewers block blob: images
  const u = 'data:' + e.dataset.m + ';base64,' + e.textContent.trim(); e.textContent = ''; return ACACHE[p] = u;
}
const IMG = {};
function img(p) { let i = IMG[p]; if (!i) { i = new Image(); i.src = asset(p); IMG[p] = i; } return i; }
function itemIcon(id) { const k = DB.icons[id]; return k ? `<img class="iic" src="${asset('img/item/' + k + '.png')}" alt="">` : ''; }   // PMD Red's own icon where it has one, else the bag sprite
function monImg(id) { return img('img/mon/' + String(id).padStart(4, '0') + '.webp'); }

/* ---------- sound ---------- */
const SND = { music: null, cur: '', vol: 0.5, sfxVol: 0.6, last: {}, tok: 0, done: false, blocked: false };
/* one music player for the whole game, reused for every song: a second song can never play over the first
   (phones start songs slowly; making a new player per song let old ones keep going) */
function playMusic(key) {
  if (typeof UI !== 'undefined') UI.want = key;
  const f = DB.snd.music[key]; if (!f || SND.cur === f) return;
  if (!SND.music) { SND.music = new Audio(); SND.music.preload = 'auto'; SND.music.addEventListener('ended', () => { SND.done = true; }); }
  const a = SND.music, tok = ++SND.tok; a.pause(); SND.cur = f; SND.done = false; SND.blocked = false;
  a.src = asset('snd/' + f + '.mp3'); a.loop = !/(win|lose)$/.test(key);   // the victory / defeat jingles play once
  a.volume = SND.vol; if (G && G.opts && G.opts.mute) return;
  a.play().catch(() => { if (tok === SND.tok) SND.blocked = true; });   // blocked until the first tap (browsers' autoplay rule); an older song's failure is ignored
}
function resumeMusic() { const a = SND.music; if (a && SND.cur && a.paused && !SND.done && !(G && G.opts && G.opts.mute)) { const tok = SND.tok; a.play().then(() => { if (tok === SND.tok) SND.blocked = false; }).catch(() => {}); } }
/* sound effects are decoded once into Web Audio buffers (making a new <audio> per hit stalls phones) */
const SFXBUF = {}; let ACTX = null;
function unlockAudio() {
  if (ACTX) { if (ACTX.state === 'suspended') ACTX.resume(); if (SND.blocked) resumeMusic(); else if (!SND.cur && UI.want) playMusic(UI.want); return; }
  try { ACTX = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return; }
  for (const [k, f] of Object.entries(DB.snd.sfx))
    fetch(asset('snd/' + f + '.mp3')).then(r => r.arrayBuffer()).then(b => ACTX.decodeAudioData(b)).then(buf => { SFXBUF[k] = buf; }).catch(() => {});
  if (SND.blocked) resumeMusic(); else if (!SND.cur && UI.want) playMusic(UI.want);
}
function sfx(key) {
  if (!ACTX || (G && G.opts && G.opts.mute)) return;
  const buf = SFXBUF[key]; if (!buf) return;
  const now = performance.now(); if (now - (SND.last[key] || 0) < 90) return; SND.last[key] = now;
  const s = ACTX.createBufferSource(), g = ACTX.createGain(); g.gain.value = SND.sfxVol; s.buffer = buf; s.connect(g).connect(ACTX.destination); s.start();
}

/* ---------- Pokémon maths (main-series formulas, IVs 15, no EVs) ---------- */
/* main-series stat formula: IVs 0-31, nature x1.1 / x0.9 on one stat each (no EVs) */
function calcStats(id, lv, iv, nat) {
  const b = SP[id].b, N = nat && DB.dex.nat[nat - 1];
  return b.map((v, i) => {
    const I = iv ? iv[i] : 15;
    if (i === 0) return Math.floor((2 * v + I) * lv / 100) + lv + 10;
    const s = Math.floor((2 * v + I) * lv / 100) + 5;
    return N && N.up !== N.dn ? Math.floor(s * (i === N.up ? 1.1 : i === N.dn ? 0.9 : 1)) : s;
  });
}
const rollIV = () => Array.from({ length: 6 }, () => Math.floor(Math.random() * 32));
const rollNat = () => 1 + Math.floor(Math.random() * 25);
function ivsOf(e) { return e.iv.map((v, i) => e.ht && e.ht[i] ? 31 : v); }      // Bottle Caps raise a stat as if its IV were 31 (like Hyper Training)
function natOf(e) { return e.mint || e.nat; }                                     // a Mint changes how the nature affects stats; the nature itself stays
function monStats(e) { return calcStats(e.id, e.lv, ivsOf(e), natOf(e)); }
const STATN = ['HP', 'Atk', 'Def', 'SpA', 'SpD', 'Spe'];
function natLabel(n) { const N = DB.dex.nat[n - 1]; return N.up === N.dn ? N.n + ' (neutral)' : `${N.n} (+${STATN[N.up]} -${STATN[N.dn]})`; }
const TOOL_PRICE = { mint: 2000, 'bottle-cap': 5000, 'gold-bottle-cap': 25000 };
function xpFor(gr, lv) { const t = DB.dex.xp[gr]; return lv >= 100 ? t[100] : t[lv]; }
const MAXLV = 100;
function movesAt(id, lv) {   // the last four moves learned by this level (what a wild one knows)
  const out = [];
  for (const [l, m] of SP[id].ls) if (l <= lv && DB.dex.moves[m] && !out.includes(m)) { out.push(m); if (out.length > 4) out.shift(); }
  return out;
}
function newMovesAt(id, lv) { return SP[id].ls.filter(([l, m]) => l === lv && DB.dex.moves[m]).map(x => x[1]); }
function mv(id) { return DB.dex.moves[id]; }
const AILMENTS = ['paralysis', 'sleep', 'freeze', 'burn', 'poison', 'confusion', 'trap', 'yawn', 'leech-seed'];
function moveUse(id) {           // how a tower can use a move: 'dmg' | 'status' | 'debuff' | 'buff' | null
  const m = mv(id); if (!m) return null;
  if (m.c !== 1) return 'dmg';
  if (AILMENTS.includes(m.ai) && m.tg !== 7) return 'status';
  if (m.tg !== 7 && m.sc.some(s => s[1] < 0 && (s[0] === 3 || s[0] === 5 || s[0] === 6))) return 'debuff';
  if (m.sc.some(s => s[1] > 0 && (s[0] === 2 || s[0] === 4 || s[0] === 6))) return 'buff';
  return null;
}
function moveDesc(id) {
  const m = mv(id), u = moveUse(id);
  const k = m.c === 2 ? 'Physical' : m.c === 3 ? 'Special' : 'Status';
  let s = `${TYPES[m.t]} - ${k}`;
  if (m.c !== 1) s += ` - Pow ${m.p || '-'}`;
  if (m.a) s += ` - Acc ${m.a}`;
  s += ` - PP ${m.pp}`;
  const sk = typeof SKDESC !== 'undefined' && SKDESC[m.n]; if (sk) s += ' - ' + sk; else if (!u) s += ' - (no use in battle)';
  if (id === 206) s += ' - Knockouts with it are 3x as likely to ask to join';
  return s;
}
function moveValue(id, sp) {      // rough worth of a move for a tower, used to pick starting moves
  const m = mv(id), u = moveUse(id); if (!u) return 0;
  const b = SP[sp].b, side = m.c === 2 ? b[1] / Math.max(b[1], b[3]) : m.c === 3 ? b[3] / Math.max(b[1], b[3]) : 1;
  if (u === 'dmg') return (m.p || 55) * side * (m.c === 3 ? 1.15 : 1) * (SP[sp].t.includes(m.t) ? 1.5 : 1) * ((m.a || 100) / 100) * ((m.h[0] + m.h[1]) / 2) * (m.tg === 9 || m.tg === 11 ? 1.3 : 1);
  if (u === 'status') return m.ai === 'sleep' || m.ai === 'freeze' || m.ai === 'trap' ? 50 : 35;
  return u === 'buff' ? 30 : 20;
}
function learnedBy(id, lv) { const s = new Set(); for (const [l, m] of SP[id].ls) if (l <= lv && DB.dex.moves[m]) s.add(m); return [...s]; }
function bestMoves(id, lv) {
  const all = learnedBy(id, lv).sort((a, b) => moveValue(b, id) - moveValue(a, id));
  const out = []; const types = new Set();
  for (const m of all) { if (out.length >= 4) break; const k = mv(m).t; if (moveUse(m) === 'dmg' && types.has(k) && all.length > 6 && out.filter(x => mv(x).t === k).length >= 2) continue; out.push(m); types.add(k); }
  return out.length ? out : movesAt(id, lv);
}
function eff(t, defTypes) { let f = 1; for (const d of defTypes) f *= DB.dex.chart[t][d]; return f; }
function evoOptions(e) {          // evolutions this box Pokémon can take right now
  const s = SP[e.id], out = [];
  for (const v of s.ev) {
    const t = SP[v.to]; if (!t || !t.anim) continue;
    let ok = false, why = '';
    if (v.tr === 1) { const need = v.lv || (v.happy ? 22 : v.move ? 32 : 30); ok = e.lv >= need; why = 'Lv ' + need; }
    else if (v.tr === 2) { ok = e.lv >= 36; why = 'Lv 36'; }
    else if (v.tr === 3) { const it = v.item; ok = (G.items[it] || 0) > 0; why = DB.dex.items[it] || 'item'; }
    else { ok = e.lv >= 30; why = 'Lv 30'; }
    out.push({ to: v.to, ok, why, item: v.tr === 3 ? v.item : 0 });
  }
  return out;
}
/* ---------- abilities: real ones from the data; these have a tower-defense meaning (the rest show "no effect here") ---------- */
const AB_TD = {
  overgrow: 'Grass moves x1.5 when your lives are at 1/3 or less', blaze: 'Fire moves x1.5 when your lives are at 1/3 or less',
  torrent: 'Water moves x1.5 when your lives are at 1/3 or less', swarm: 'Bug moves x1.5 when your lives are at 1/3 or less',
  'compound-eyes': 'Accuracy x1.3', hustle: 'Physical moves x1.5, accuracy x0.8', 'huge-power': 'Physical moves x2', 'pure-power': 'Physical moves x2',
  adaptability: 'Same-type bonus is x2 instead of x1.5', technician: 'Moves with 60 power or less x1.5', 'skill-link': 'Multi-hit moves always hit the most times',
  'serene-grace': 'Added effects happen twice as often', sniper: 'Critical hits do x2.25', 'super-luck': 'Critical hits more likely',
  'sheer-force': 'Moves with added effects x1.3, but the effects are lost', 'tinted-lens': '"Not very effective" hits do double',
  'tough-claws': 'Physical moves x1.3', 'no-guard': 'Moves never miss', 'keen-eye': 'Can see hidden Pokémon', frisk: 'Can see hidden Pokémon',
  scrappy: 'Normal and Fighting moves hit Ghost types', 'speed-boost': 'Attacks faster the longer a wave goes on',
  static: 'Wild Pokémon walking close by may be paralyzed', 'flame-body': 'Wild Pokémon walking close by may be burned',
  'poison-point': 'Wild Pokémon walking close by may be poisoned', 'effect-spore': 'Wild Pokémon walking close by may be poisoned, paralyzed or put to sleep',
  'swift-swim': 'Attacks x1.5 faster in rain or when standing in water', chlorophyll: 'Attacks x1.5 faster in sun', 'sand-rush': 'Attacks x1.5 faster in a sandstorm',
  'slush-rush': 'Attacks x1.5 faster in hail', 'solar-power': 'Special moves x1.5 in sun', levitate: 'Wild: flies over the path; immune to Ground moves',
  'flash-fire': 'Wild: immune to Fire moves', 'water-absorb': 'Wild: immune to Water moves', 'storm-drain': 'Wild: immune to Water moves', 'dry-skin': 'Wild: immune to Water moves, takes x1.25 from Fire',
  'volt-absorb': 'Wild: immune to Electric moves', 'lightning-rod': 'Wild: immune to Electric moves', 'motor-drive': 'Wild: immune to Electric moves',
  'sap-sipper': 'Wild: immune to Grass moves', 'wonder-guard': 'Wild: only super-effective hits do damage', sturdy: 'Wild: survives one knockout hit at full HP',
  'thick-fat': 'Wild: takes half from Fire and Ice', heatproof: 'Wild: takes half from Fire', filter: 'Wild: super-effective hits x0.75', 'solid-rock': 'Wild: super-effective hits x0.75',
  'prism-armor': 'Wild: super-effective hits x0.75', multiscale: 'Wild: takes half damage at full HP', 'shadow-shield': 'Wild: takes half damage at full HP',
  'magic-guard': 'Wild: no damage from burn, poison or traps', insomnia: 'Wild: can\'t fall asleep', 'vital-spirit': 'Wild: can\'t fall asleep',
  limber: 'Wild: can\'t be paralyzed', immunity: 'Wild: can\'t be poisoned', 'water-veil': 'Wild: can\'t be burned', 'own-tempo': 'Wild: can\'t be confused',
  oblivious: 'Wild: can\'t be confused', 'magma-armor': 'Wild: can\'t be frozen', 'shield-dust': 'Wild: added effects don\'t happen to it',
  'clear-body': 'Wild: stats can\'t be lowered', 'white-smoke': 'Wild: stats can\'t be lowered', 'full-metal-body': 'Wild: stats can\'t be lowered',
  'battle-armor': 'Wild: can\'t take critical hits', 'shell-armor': 'Wild: can\'t take critical hits', 'quick-feet': 'Wild: x1.5 speed while it has a status',
};
function abKey(a) { return a && DB.dex.abil[a] ? DB.dex.abil[a].k : ''; }
function rollAbility(id, hidChance) {
  const l = SP[id].ab || [], nor = l.filter(x => !x[1]), hid = l.filter(x => x[1]);
  if (hid.length && rnd() < hidChance) return hid[0][0];
  return nor.length ? nor[Math.floor(rnd() * nor.length)][0] : (l[0] || [0])[0];
}
function abilityAfterEvolve(from, to, a) {
  const fl = SP[from].ab || [], tl = SP[to].ab || [], i = fl.findIndex(x => x[0] === a);
  if (i >= 0 && tl[i] && tl[i][1] === fl[i][1]) return tl[i][0];
  return (tl.find(x => x[1] === (i >= 0 ? fl[i][1] : 0)) || tl[0] || [a])[0];
}
/* ---------- held items (real items; what each does in Route Defense) ---------- */
const TYPE_ITEM = { charcoal: 9, 'mystic-water': 10, 'miracle-seed': 11, magnet: 12, 'never-melt-ice': 14, 'black-belt': 1, 'poison-barb': 3, 'soft-sand': 4, 'sharp-beak': 2,
  'twisted-spoon': 13, 'silver-powder': 6, 'hard-stone': 5, 'spell-tag': 7, 'dragon-fang': 15, 'black-glasses': 16, 'metal-coat': 8, 'silk-scarf': 0, 'fairy-feather': 17 };
const HELD_TD = { 'choice-band': 'Physical moves x1.5, but only its first move is used', 'choice-specs': 'Special moves x1.5, but only its first move is used',
  'choice-scarf': 'Attacks x1.5 faster, but only its first move is used', 'life-orb': 'All damage x1.3', 'expert-belt': 'Super-effective hits x1.2',
  'scope-lens': 'Critical hits more likely', 'razor-claw': 'Critical hits more likely', 'wide-lens': 'Accuracy x1.1', 'zoom-lens': 'Accuracy x1.2',
  'quick-claw': 'Sometimes attacks again right away', 'kings-rock': '10% chance to make the target flinch', 'razor-fang': '10% chance to make the target flinch',
  'muscle-band': 'Physical moves x1.1', 'wise-glasses': 'Special moves x1.1', 'light-clay': 'Its stat boosts and drops last twice as long',
  'binding-band': 'Trapping moves do double damage over time', 'lucky-egg': 'Earns x1.5 XP', 'amulet-coin': 'Knockouts by it earn double ₽',
  metronome: 'Using the same move again and again: up to x2 damage' };
for (const [k, t] of Object.entries(TYPE_ITEM)) HELD_TD[k] = `${TYPES[t]} moves x1.2`;
const HELD_RARE = new Set(['choice-band', 'choice-specs', 'choice-scarf', 'life-orb', 'expert-belt']);
function heldKey(e) { return e && e.it && DB.dex.held[e.it] ? DB.dex.held[e.it].k : ''; }
function heldPrice(k) { return HELD_RARE.has(k) ? 0 : k === 'lucky-egg' || k === 'amulet-coin' ? 8000 : 3000; }
/* ---------- type quirks (your team only; a dual type gets both) ---------- */
const TQ = {
  0: ['Thrifty', 'Costs 10% less to place'], 1: ['Boss hitter', '+20% damage to bosses'], 2: ['Far sight', '+15% range'],
  3: ['Toxic', 'Hits stack poison (up to 5)'], 4: ['Tremor', 'Hits may stun briefly'], 5: ['Crush', 'First hit on each enemy deals +30%'],
  6: ['Swarm', '+5% attack speed for each other Bug placed'], 7: ['Phase', 'Attacks go through Protect shields'], 8: ['Pierce', 'Ignores Rock / Steel armour'],
  9: ['Scorch', 'Hits may burn'], 10: ['Soak', 'Hits slow enemies a little'], 11: ['Vines', 'Enemies in its range move 10% slower'],
  12: ['Chain', 'Hits jump to one more enemy for 30% damage'], 13: ['Foresight', 'Reveals hidden Ghosts from 50% farther'], 14: ['Chill', 'Hits slow enemies by 15%'],
  15: ['Fury', 'Higher critical-hit chance'], 16: ['Finisher', 'Finishes off enemies below 15% HP (not bosses)'], 17: ['Aura', 'Teammates close by deal +5% damage'],
};
const quirks = id => SP[id].t.map(x => TQ[x]).filter(Boolean);
function placeCost(e) { return Math.round((40 + SP[e.id].bst * 0.25 + e.lv * 2.5) * (1 + mod('placeCost')) * (SP[e.id].t.includes(0) ? 0.9 : 1)); }
/* ---------- Rescue Points tree: owned nodes add up into small permanent bonuses ---------- */
let MODS = null;
function mods() {
  if (MODS) return MODS; MODS = {};
  for (const n of DB.tree.nodes) if (G && G.tree && G.tree[n.id]) for (const [k, v] of Object.entries(n.eff)) MODS[k] = (MODS[k] || 0) + v;
  return MODS;
}
function mod(k) { return mods()[k] || 0; }
function nodeOpen(n) { return !G.tree[n.id] && n.req.every(r => G.tree[r]); }
function buyNode(n) { if (!nodeOpen(n) || G.rp < n.cost) return false; G.rp -= n.cost; G.tree[n.id] = 1; MODS = null; save(); return true; }
function treeSpent() { return DB.tree.nodes.filter(n => G.tree[n.id]).reduce((s, n) => s + n.cost, 0); }
function resetCost() { return treeSpent() * 100; }
function resetTree() { const c = resetCost(); if (G.money < c) return false; G.money -= c; G.rp += treeSpent(); G.tree = {}; MODS = null; save(); return true; }
function rpForClear(tier) { return 1 + Math.floor(tier * 0.6); }
function shopPrice(p) { return Math.round(p * (1 + mod('shop'))); }

/* ---------- save ---------- */
let G = null;
const SAVE_KEY = 'routedef_v1';
function newSave() { return { v: 2, mt: { 0: 1 }, box: [], uid: 1, money: 0, rp: 0, tree: {}, stars: {}, items: {}, tools: {}, held: {}, tier: 1, seen: {}, own: {}, opts: { mute: false }, stats: { maps: 0, wins: 0 } }; }
function save() { try { localStorage.setItem(SAVE_KEY, JSON.stringify(G)); } catch (e) {} }
function load() { try { const s = localStorage.getItem(SAVE_KEY); if (s) { const g = JSON.parse(s); if (!g.v || g.v < 2) return null;   // per-map tiers: saves from before start over
      g.mt = g.mt || { 0: 1 }; g.held = g.held || {}; g.rp = g.rp || 0; g.tree = g.tree || {}; g.stars = g.stars || {}; g.tools = g.tools || {}; for (const e of g.box) { if (e.ab == null) e.ab = rollAbility(e.id, 0.05); if (e.it == null) e.it = 0; if (!e.nat) e.nat = rollNat(); if (!e.iv) e.iv = rollIV(); if (!e.ht) e.ht = [0, 0, 0, 0, 0, 0]; if (e.mint == null) e.mint = 0; } return g; } } catch (e) {} return null; }
function makeMon(id, lv, nat, iv) {
  const e = { u: G.uid++, id, lv, xp: xpFor(SP[id].gr, lv), mv: bestMoves(id, lv), pend: [], ab: rollAbility(id, 0.05), it: 0, nat: nat || rollNat(), iv: iv ? iv.slice() : rollIV(), ht: [0, 0, 0, 0, 0, 0], mint: 0 };
  G.own[id] = 1; G.seen[id] = 1; return e;
}
function giveXP(e, amt) {       // returns list of events
  const ev = [];
  if (e.lv >= MAXLV) return ev;
  e.xp += amt;
  while (e.lv < MAXLV && e.xp >= xpFor(SP[e.id].gr, e.lv + 1)) {
    e.lv++; ev.push('lv');
    for (const m of newMovesAt(e.id, e.lv)) {
      if (e.mv.includes(m) || e.pend.includes(m)) continue;
      if (e.mv.length < 4) e.mv.push(m); else e.pend.push(m);
    }
  }
  return ev;
}
function evolve(e, to, item) {
  if (item) { G.items[item]--; if (!G.items[item]) delete G.items[item]; }
  e.ab = abilityAfterEvolve(e.id, to, e.ab); e.id = to; G.own[to] = 1; G.seen[to] = 1;
  for (const m of newMovesAt(to, 1).concat(newMovesAt(to, e.lv))) {
    if (e.mv.includes(m) || e.pend.includes(m)) continue;
    if (e.mv.length < 4) e.mv.push(m); else e.pend.push(m);
  }
}
/* ---------- per-map tiers: each map climbs from tier 1; clearing a map (any tier) opens the next one ---------- */
function mapTier(i) { return (G.mt && G.mt[i]) || 0; }              // highest tier you can pick on map i (0 = map not open)
function mapOpen(i) { return mapTier(i) > 0; }
function mapCleared(i) { return Math.max(0, mapTier(i) - 1); }       // highest tier cleared on map i (20 when done)
function bestTier() { let b = 0; for (const k in G.mt) b = Math.max(b, (G.mtDone && G.mtDone[k]) ? MAXTIER : G.mt[k] - 1); return b; }
function starsOf(i, t) { return (G.stars || {})[i + ':' + t] || 0; }
/* map difficulty, like Bloons TD 6: the 96 maps in opening order, in 4 groups */
const MAPGROUP = [['Beginner', '#5fd068', 0, 1, 1, 0], ['Intermediate', '#ffd84a', 4, 1.1, 1.05, 5], ['Advanced', '#ff9a3c', 13, 1.2, 1.1, 10], ['Expert', '#ff5a5a', 27, 1.35, 1.15, 15]];   // name, colour, tiers added to every fight, reward multiplier, wild Pokémon per wave, tier to clear on any map of the group before to open this group
function mapGroup(i) { return Math.min(3, Math.floor(i * 4 / DB.ts.length)); }
/* how hard a fight is, on the old one-group tier scale: one long climb over all 4 groups, so each group's tier 1 matches the gate before it
   (Beginner 5 = Intermediate 1, Intermediate 10 = Advanced 1, Advanced 15 = Expert 1) and wild Lv 100 only arrives at Expert tier 20 */
function threatTier(i, t) { return 1 + (t + MAPGROUP[mapGroup(i)][2] - 1) * 2.05 / 4.2; }
function groupStart(g) { for (let i = 0; i < DB.ts.length; i++) if (mapGroup(i) === g) return i; return -1; }   // first map of a group
function groupGate(g) { return MAPGROUP[g][5]; }   // within a group one clear opens the next map; the next group opens from a high tier on any map of this one
