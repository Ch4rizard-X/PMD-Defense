/* Route Defense — random maps from PMD Red tilesets */
'use strict';
const TZ = 24;
function rng(seed) { let a = seed >>> 0; return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const NB = [[0, 1], [1, 1], [1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1]];   // S SE E NE N NW W SW (PMD bit order)

/* path through a grid of 5x5-tile cells, left edge to right edge, never touching itself */
function cellPath(cw, ch, R, minF, maxF) {
  const N = 28, minL = Math.max(cw + 1, Math.floor(N * (minF || 0.55))), maxL = Math.max(cw + 3, Math.floor(N * (maxF || 0.85)));   // path length as on a 7x4 map, whatever the screen shape
  let best = null;
  for (let tries = 0; tries < 4000; tries++) {
    const p = [[0, Math.floor(R() * ch)]], seen = new Set([p[0] + '']);
    while (true) {
      const [x, y] = p[p.length - 1];
      if (x === cw - 1 && p.length >= minL) break;
      const opts = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => [x + dx, y + dy])
        .filter(([a, b]) => a >= 0 && b >= 0 && a < cw && b < ch && !seen.has(a + ',' + b) && (a < cw - 1 || p.length + 1 >= minL - 1));
      if (!opts.length) break;
      // a little bias toward vertical moves keeps paths winding
      const w = opts.map(([a, b]) => (b !== y ? 1.6 : 1) * (a > x ? 1.1 : a < x ? 0.8 : 1));
      let r = R() * w.reduce((s, v) => s + v, 0), k = 0; while ((r -= w[k]) > 0) k++;
      p.push(opts[k]); seen.add(opts[k] + '');
      if (p.length > maxL) break;
    }
    const [ex] = p[p.length - 1];
    if (ex === cw - 1 && p.length >= minL && p.length <= maxL) { if (!best || p.length > best.length) best = p; if (R() < 0.35) break; }
  }
  return best;
}

/* random walk through free cells from a to b (or to any cell satisfying goal), avoiding used cells */
function cellRoute(cw, ch, R, start, goal, used, minLen, maxLen) {
  for (let tries = 0; tries < 600; tries++) {
    const p = [start], seen = new Set([start + '']);
    while (p.length <= maxLen) {
      const [x, y] = p[p.length - 1];
      const nb = [[1, 0], [-1, 0], [0, 1], [0, -1]].map(([dx, dy]) => [x + dx, y + dy]).filter(([a, b]) => a >= 0 && b >= 0 && a < cw && b < ch && !seen.has(a + ',' + b));
      const fin = nb.filter(c => goal(c) && p.length >= minLen);
      if (fin.length) { p.push(fin[0]); return p; }
      const free = nb.filter(c => !used.has(c + ''));
      if (!free.length) break;
      const c = free[Math.floor(R() * free.length)]; p.push(c); seen.add(c + '');
    }
  }
  return null;
}
/* aspect = long side / short side of the screen: the map is made in that shape so it fills it */
function mapCols(aspect) { return clamp(Math.round(((aspect || 1.76) * 21 - 2) / 5), 5, 10); }
function genMap(setIdx, portrait, seed, kind, aspect, tier) {
  const grp = mapGroup(setIdx), md = grp / 3;                       // later maps are harder by nature
  const hard = clamp(((tier || 1) - 4) / 16, 0, 1) * 0.6 + md * 0.4;   // tier gives up to 60%, the map's group the other 40%: Expert at tier 20 = full
  const effTier = (tier || 1) * 0.75 + grp * 4, lenK = 1 - 0.3 * md;   // third entrances: late tiers on later maps; paths up to 30% shorter
  const R = rng(seed), S = DB.ts[setIdx];
  const CS = 5, ch = 4, cw = mapCols(aspect), W = cw * CS + 2, H = 21, ox = 1, oy = 0;
  const t = Array.from({ length: H }, () => new Array(W).fill(0));
  // layout kind: one path, a path that splits in two and rejoins, or a second entrance that merges in
  // layout kind: one path, a split that rejoins, a second entrance, or (tier 15+) a third entrance; plain paths fade out with tier
  if (!kind) {
    const pPlain = 0.45 * (1 - hard), pThree = effTier >= 13 ? 0.4 * clamp((effTier - 12) / 15, 0, 1) : 0, rest = (1 - pPlain - pThree) / 2, r = R();
    kind = r < pPlain ? 'plain' : r < pPlain + rest ? 'split' : r < pPlain + 2 * rest ? 'two' : 'three';
  }
  const cp = kind === 'plain' ? cellPath(cw, ch, R, 0.55 * lenK, 0.85 * lenK) : cellPath(cw, ch, R, 0.42 * lenK, 0.62 * lenK);
  const used = new Set(cp.map(c => c + ''));
  const ctr = ([x, y]) => [ox + x * CS + 2, oy + y * CS + 3];          // corner point shared by the 2x2 path block
  const carve = (ax, ay, bx, by) => {                                  // 2-wide corridor between two centre points
    const x0 = Math.min(ax, bx), x1 = Math.max(ax, bx), y0 = Math.min(ay, by), y1 = Math.max(ay, by);
    for (let y = y0 - 1; y <= y1; y++) for (let x = x0 - 1; x <= x1; x++) if (y >= 0 && y < H && x >= 0 && x < W) t[y][x] = 1;
  };
  const carveCells = cells => { const q = cells.map(ctr); for (let i = 1; i < q.length; i++) carve(q[i - 1][0], q[i - 1][1], q[i][0], q[i][1]); };
  const pts = cp.map(ctr), first = pts[0], last = pts[pts.length - 1];
  carve(0, first[1], first[0], first[1]); carveCells(cp); carve(last[0], last[1], W, last[1]);
  const px = cells => cells.map(ctr).map(([x, y]) => [x * TZ, y * TZ]);
  const mainLine = [[-TZ * 1.5, first[1] * TZ]].concat(px(cp)).concat([[W * TZ + TZ * 1.5, last[1] * TZ]]);
  const lines = [mainLine];
  if (kind === 'split') {
    let ok = false;
    for (let tr = 0; tr < 40 && !ok; tr++) {
      const i = Math.floor(R() * (cp.length - 4)), key = c => c + '';
      const br = cellRoute(cw, ch, R, cp[i], c => { const j = cp.findIndex(d => d + '' === c + ''); return j > i + 2; }, used, 3, 9);
      if (!br) continue;
      const j = cp.findIndex(d => d + '' === br[br.length - 1] + '');
      carveCells(br); br.slice(1, -1).forEach(c => used.add(key(c)));
      lines.push([mainLine[0]].concat(px(cp.slice(0, i))).concat(px(br)).concat(px(cp.slice(j + 1))).concat([mainLine[mainLine.length - 1]]));
      ok = true;
    }
    if (!ok) kind = 'plain';
  } else if (kind === 'two' || kind === 'three') {
    // extra entrances from the top or bottom edge that merge into the main path (a third one comes from the other edge)
    const sides = kind === 'three' ? [R() < 0.5] : [R() < 0.5];
    if (kind === 'three') sides.push(!sides[0]);
    let made = 0;
    for (const top of sides) {
      let ok = false;
      for (let tr = 0; tr < 40 && !ok; tr++) {
        const sy = top ? 0 : ch - 1, sx = 1 + Math.floor(R() * (cw - 2)), st = [sx, sy];
        if (used.has(st + '')) continue;
        const br = cellRoute(cw, ch, R, st, c => { const j = cp.findIndex(d => d + '' === c + ''); return j >= 3 && j < cp.length - 2; }, used, 2, 10);
        if (!br) continue;
        const j = cp.findIndex(d => d + '' === br[br.length - 1] + '');
        const [ex, ey] = ctr(st); carve(ex, ey, ex, top ? 0 : H); carveCells(br);
        br.slice(0, -1).forEach(c => used.add(c + ''));
        const edge = [ex * TZ, top ? -TZ * 1.5 : H * TZ + TZ * 1.5];
        lines.push([edge].concat(px(br)).concat(px(cp.slice(j + 1))).concat([mainLine[mainLine.length - 1]]));
        ok = true; made++;
      }
    }
    kind = made === 0 ? 'plain' : made === 1 ? 'two' : 'three';
  }
  // ponds (water, or lava in volcanic settings), kept off the path
  const nearPath = (x, y, d) => { for (let j = -d; j <= d; j++) for (let i = -d; i <= d; i++) { const a = x + i, b = y + j; if (a >= 0 && b >= 0 && a < W && b < H && t[b][a] === 1) return true; } return false; };
  const np = 1 + Math.floor(R() * 3) + Math.round(hard * 5);   // more ponds / lava pools at higher tiers: fewer good spots
  for (let k = 0; k < np; k++) {
    for (let tr = 0; tr < 60; tr++) {
      const sx = 1 + Math.floor(R() * (W - 3)), sy = 1 + Math.floor(R() * (H - 3));
      if (nearPath(sx, sy, 2) || nearPath(sx + 1, sy + 1, 2)) continue;
      const blob = [[sx, sy], [sx + 1, sy], [sx, sy + 1], [sx + 1, sy + 1]], size = 6 + Math.floor(R() * 10) + Math.round(hard * 14 * R());
      for (let g = 0; g < 200 && blob.length < size; g++) {
        const [bx, by] = blob[Math.floor(R() * blob.length)], [dx, dy] = NB[[0, 2, 4, 6][Math.floor(R() * 4)]];
        const a = bx + dx, b = by + dy;
        if (a < 1 || b < 1 || a >= W - 1 || b >= H - 1 || nearPath(a, b, 1) || blob.some(([u, v]) => u === a && v === b)) continue;
        blob.push([a, b]);
      }
      for (const [a, b] of blob) t[b][a] = 2;
      break;
    }
  }
  for (let pass = 0; pass < 3; pass++)        // PMD's liquid tiles need 2x2 bodies to look right
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (t[y][x] === 2) {
      let ok = false;
      for (const [i, j] of [[0, 0], [-1, 0], [0, -1], [-1, -1]]) {
        if ([[0, 0], [1, 0], [0, 1], [1, 1]].every(([u, v]) => { const a = x + i + u, b = y + j + v; return a >= 0 && b >= 0 && a < W && b < H && t[b][a] === 2; })) ok = true;
      }
      if (!ok) t[y][x] = 0;
    }
  let M = { set: setIdx, seed, W, H, t, lines, kind, liq: S.liq };
  if (portrait) M = transpose(M);
  M.routes = M.lines.map(l => mkRoute(l));
  for (const r of M.routes) r.air = mkRoute(airLine(r.line));      // flyers cut the corners
  M.line = M.lines[0]; M.len = M.routes[0].len; M.seg = M.routes[0].seg;
  M.cv = renderMap(M, R);
  return M;
}
function mkRoute(line) { const seg = []; let len = 0; for (let i = 1; i < line.length; i++) { const l = Math.hypot(line[i][0] - line[i - 1][0], line[i][1] - line[i - 1][1]); seg.push(l); len += l; } return { line, seg, len }; }
function airLine(line) { const out = [line[0]]; for (let i = 2; i < line.length - 1; i += 2) out.push(line[i]); out.push(line[line.length - 1]); return out; }
function transpose(M) {
  const t = Array.from({ length: M.W }, (_, y) => Array.from({ length: M.H }, (_, x) => M.t[x][y]));
  return Object.assign({}, M, { W: M.H, H: M.W, t, lines: M.lines.map(l => l.map(([x, y]) => [y, x])) });
}
function tileAt(M, x, y) { const a = clamp(x, 0, M.W - 1), b = clamp(y, 0, M.H - 1); return M.t[b][a]; }
function renderMap(M, R) {
  const S = DB.ts[M.set], cv = document.createElement('canvas');
  cv.width = M.W * TZ; cv.height = M.H * TZ;
  const g = cv.getContext('2d'), im = img('img/ts/' + S.ts + '.png'), C = S.cols || 10;
  const draw = () => {
    for (let y = 0; y < M.H; y++) for (let x = 0; x < M.W; x++) {
      const v = M.t[y][x]; let mask = 0;
      for (let i = 0; i < 8; i++) {
        const n = tileAt(M, x + NB[i][0], y + NB[i][1]);
        if (v === 0 ? n === 0 : v === 1 ? n !== 0 : n === v) mask |= 1 << i;
      }
      const key = mask + (v === 1 ? 512 : v === 2 ? 256 : 0);
      const b = S.rules[(M.vr ? M.vr[y][x] : 0) + key * 3];
      if (b == null || b < 0) continue;
      g.drawImage(im, (b % C) * TZ, Math.floor(b / C) * TZ, TZ, TZ, x * TZ, y * TZ, TZ, TZ);
    }
  };
  M.vr = Array.from({ length: M.H }, () => Array.from({ length: M.W }, () => Math.floor(R() * 3)));
  M.ready = im.complete && im.naturalWidth ? (draw(), Promise.resolve()) : new Promise(r => im.addEventListener('load', () => { draw(); r(); }, { once: true }));
  return cv;
}
/* position + facing along a route at distance d */
function pathAt(M, d, route) {
  const r = route || M.routes[0];
  let i = 0;
  while (i < r.seg.length - 1 && d > r.seg[i]) { d -= r.seg[i]; i++; }
  const [ax, ay] = r.line[i], [bx, by] = r.line[i + 1], f = r.seg[i] ? clamp(d / r.seg[i], 0, 1) : 0;
  return [ax + (bx - ax) * f, ay + (by - ay) * f, Math.atan2(by - ay, bx - ax)];
}
function nearestD(r, x, y) { let best = 0, bd = 1e9; for (let d = 0; d <= r.len; d += 6) { const [px, py] = pathAt(null, d, r); const k = Math.hypot(px - x, py - y); if (k < bd) { bd = k; best = d; } } return best; }
function distToPath(M, x, y) {
  let best = 1e9;
  for (const line of M.lines) for (let i = 1; i < line.length; i++) {
    const [ax, ay] = line[i - 1], [bx, by] = line[i], dx = bx - ax, dy = by - ay, l = dx * dx + dy * dy;
    const f = l ? clamp(((x - ax) * dx + (y - ay) * dy) / l, 0, 1) : 0;
    best = Math.min(best, Math.hypot(x - ax - dx * f, y - ay - dy * f));
  }
  return best;
}
