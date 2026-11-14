// Route Defense — random maps from the PMD Red / Explorers of Sky tilesets (same generator and seeds as the HTML version).
using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace RouteDefense
{
    public class Route { public List<Vector2> line; public List<float> seg = new List<float>(); public float len; public Route air; }
    public class MapData
    {
        public int set, seed, W, H; public int[,] t; public string kind, liq;
        public List<List<Vector2>> lines = new List<List<Vector2>>(); public List<Route> routes = new List<Route>();
        public int[,] vr; public Texture2D tex; public Sprite sprite;
    }

    public class Rng
    {
        uint a;
        public Rng(uint seed) { a = seed; }
        public float Next()
        {
            unchecked
            {
                a += 0x6D2B79F5u;
                uint t = (a ^ (a >> 15)) * (1u | a);
                t = (t + ((t ^ (t >> 7)) * (61u | t))) ^ t;
                return (float)((t ^ (t >> 14)) / 4294967296.0);
            }
        }
    }

    public static class MapGen
    {
        public const int TZ = 24;
        static readonly int[][] NB = { new[] { 0, 1 }, new[] { 1, 1 }, new[] { 1, 0 }, new[] { 1, -1 }, new[] { 0, -1 }, new[] { -1, -1 }, new[] { -1, 0 }, new[] { -1, 1 } }; // S SE E NE N NW W SW
        static readonly int[][] D4 = { new[] { 1, 0 }, new[] { -1, 0 }, new[] { 0, 1 }, new[] { 0, -1 } };
        static string K(int[] c) => c[0] + "," + c[1];

        /* path through a grid of 5x5-tile cells, left edge to right edge, never touching itself */
        static List<int[]> CellPath(int cw, int ch, Rng R, float minF = 0.55f, float maxF = 0.85f)
        {
            int N = 28, minL = Math.Max(cw + 1, (int)(N * minF)), maxL = Math.Max(cw + 3, (int)(N * maxF));   // path length as on a 7x4 map, whatever the screen shape
            List<int[]> best = null;
            for (int tries = 0; tries < 4000; tries++)
            {
                var p = new List<int[]> { new[] { 0, (int)(R.Next() * ch) } }; var seen = new HashSet<string> { K(p[0]) };
                while (true)
                {
                    var cur = p[p.Count - 1]; int x = cur[0], y = cur[1];
                    if (x == cw - 1 && p.Count >= minL) break;
                    var opts = D4.Select(d => new[] { x + d[0], y + d[1] })
                        .Where(c => c[0] >= 0 && c[1] >= 0 && c[0] < cw && c[1] < ch && !seen.Contains(K(c)) && (c[0] < cw - 1 || p.Count + 1 >= minL - 1)).ToList();
                    if (opts.Count == 0) break;
                    var w = opts.Select(c => (c[1] != y ? 1.6f : 1f) * (c[0] > x ? 1.1f : c[0] < x ? 0.8f : 1f)).ToList();
                    float r = R.Next() * w.Sum(); int k = 0; while ((r -= w[k]) > 0) k++;
                    p.Add(opts[k]); seen.Add(K(opts[k]));
                    if (p.Count > maxL) break;
                }
                int ex = p[p.Count - 1][0];
                if (ex == cw - 1 && p.Count >= minL && p.Count <= maxL) { if (best == null || p.Count > best.Count) best = p; if (R.Next() < 0.35f) break; }
            }
            return best;
        }
        static List<int[]> CellRoute(int cw, int ch, Rng R, int[] start, Func<int[], bool> goal, HashSet<string> used, int minLen, int maxLen)
        {
            for (int tries = 0; tries < 600; tries++)
            {
                var p = new List<int[]> { start }; var seen = new HashSet<string> { K(start) };
                while (p.Count <= maxLen)
                {
                    var cur = p[p.Count - 1];
                    var nb = D4.Select(d => new[] { cur[0] + d[0], cur[1] + d[1] }).Where(c => c[0] >= 0 && c[1] >= 0 && c[0] < cw && c[1] < ch && !seen.Contains(K(c))).ToList();
                    var fin = nb.Where(c => goal(c) && p.Count >= minLen).ToList();
                    if (fin.Count > 0) { p.Add(fin[0]); return p; }
                    var free = nb.Where(c => !used.Contains(K(c))).ToList();
                    if (free.Count == 0) break;
                    var c2 = free[(int)(R.Next() * free.Count)]; p.Add(c2); seen.Add(K(c2));
                }
            }
            return null;
        }

        /* aspect = long side / short side of the screen: the map is made in that shape so it fills it */
        public static int MapCols(float aspect) => Mathf.Clamp(Mathf.RoundToInt((aspect * 21 - 2) / 5f), 5, 10);
        public static float ScreenAspect() => Mathf.Max(Screen.width, Screen.height) / (float)Mathf.Max(1, Mathf.Min(Screen.width, Screen.height));
        public static MapData Gen(int setIdx, bool portrait, int seed, string kind = null, float aspect = 1.76f, int tier = 1)
        {
            int grp = Prog.MapGroup(setIdx); float md = grp / 3f;                                   // later maps are harder by nature
            float hard = Mathf.Clamp01((tier - 4) / 16f) * 0.6f + md * 0.4f;                        // tier gives up to 60%, the map's group the other 40%
            float effTier = tier * 0.75f + grp * 4, lenK = 1 - 0.3f * md;                           // third entrances: late tiers on later maps; paths up to 30% shorter
            var R = new Rng((uint)seed); var S = DB.TS[setIdx];
            int cw = MapCols(aspect); const int CS = 5, H = 21, ch = 4, ox = 1, oy = 0; int W = cw * CS + 2;
            var t = new int[H, W];
            // layout kind: one path, a split that rejoins, a second entrance, or a third entrance; plain paths fade out as fights get harder
            if (kind == null)
            {
                float pPlain = 0.45f * (1 - hard), pThree = effTier >= 13 ? 0.4f * Mathf.Clamp01((effTier - 12) / 15f) : 0, rest = (1 - pPlain - pThree) / 2, r = R.Next();
                kind = r < pPlain ? "plain" : r < pPlain + rest ? "split" : r < pPlain + 2 * rest ? "two" : "three";
            }
            var cp = kind == "plain" ? CellPath(cw, ch, R, 0.55f * lenK, 0.85f * lenK) : CellPath(cw, ch, R, 0.42f * lenK, 0.62f * lenK);
            var used = new HashSet<string>(cp.Select(K));
            Func<int[], int[]> ctr = c => new[] { ox + c[0] * CS + 2, oy + c[1] * CS + 3 };
            void carve(int ax, int ay, int bx, int by)
            {
                int x0 = Math.Min(ax, bx), x1 = Math.Max(ax, bx), y0 = Math.Min(ay, by), y1 = Math.Max(ay, by);
                for (int y = y0 - 1; y <= y1; y++) for (int x = x0 - 1; x <= x1; x++) if (y >= 0 && y < H && x >= 0 && x < W) t[y, x] = 1;
            }
            void carveCells(List<int[]> cells) { var q = cells.Select(ctr).ToList(); for (int i = 1; i < q.Count; i++) carve(q[i - 1][0], q[i - 1][1], q[i][0], q[i][1]); }
            var pts = cp.Select(ctr).ToList(); var first = pts[0]; var last = pts[pts.Count - 1];
            carve(0, first[1], first[0], first[1]); carveCells(cp); carve(last[0], last[1], W, last[1]);
            Func<IEnumerable<int[]>, List<Vector2>> px = cells => cells.Select(ctr).Select(c => new Vector2(c[0] * TZ, c[1] * TZ)).ToList();
            var mainLine = new List<Vector2> { new Vector2(-TZ * 1.5f, first[1] * TZ) }; mainLine.AddRange(px(cp)); mainLine.Add(new Vector2(W * TZ + TZ * 1.5f, last[1] * TZ));
            var M = new MapData { set = setIdx, seed = seed, liq = S.liq };
            M.lines.Add(mainLine);
            if (kind == "split")
            {
                bool ok = false;
                for (int tr = 0; tr < 40 && !ok; tr++)
                {
                    int i = (int)(R.Next() * (cp.Count - 4));
                    var br = CellRoute(cw, ch, R, cp[i], c => { int j = cp.FindIndex(d => K(d) == K(c)); return j > i + 2; }, used, 3, 9);
                    if (br == null) continue;
                    int jj = cp.FindIndex(d => K(d) == K(br[br.Count - 1]));
                    carveCells(br); foreach (var c in br.Skip(1).Take(br.Count - 2)) used.Add(K(c));
                    var l = new List<Vector2> { mainLine[0] }; l.AddRange(px(cp.Take(i))); l.AddRange(px(br)); l.AddRange(px(cp.Skip(jj + 1))); l.Add(mainLine[mainLine.Count - 1]);
                    M.lines.Add(l); ok = true;
                }
                if (!ok) kind = "plain";
            }
            else if (kind == "two" || kind == "three")
            {
                // extra entrances from the top or bottom edge that merge into the main path (a third one comes from the other edge)
                var sides = new List<bool> { R.Next() < 0.5f }; if (kind == "three") sides.Add(!sides[0]);
                int made = 0;
                foreach (bool top in sides)
                {
                bool ok = false;
                for (int tr = 0; tr < 40 && !ok; tr++)
                {
                    int sy = top ? 0 : ch - 1, sx = 1 + (int)(R.Next() * (cw - 2)); var st = new[] { sx, sy };
                    if (used.Contains(K(st))) continue;
                    var br = CellRoute(cw, ch, R, st, c => { int j = cp.FindIndex(d => K(d) == K(c)); return j >= 3 && j < cp.Count - 2; }, used, 2, 10);
                    if (br == null) continue;
                    int jj = cp.FindIndex(d => K(d) == K(br[br.Count - 1]));
                    var e = ctr(st); carve(e[0], e[1], e[0], top ? 0 : H); carveCells(br);
                    foreach (var c in br.Take(br.Count - 1)) used.Add(K(c));
                    var l = new List<Vector2> { new Vector2(e[0] * TZ, top ? -TZ * 1.5f : H * TZ + TZ * 1.5f) }; l.AddRange(px(br)); l.AddRange(px(cp.Skip(jj + 1))); l.Add(mainLine[mainLine.Count - 1]);
                    M.lines.Add(l); ok = true; made++;
                }
                }
                kind = made == 0 ? "plain" : made == 1 ? "two" : "three";
            }
            // ponds (water, or lava in volcanic settings), kept off the path
            bool nearPath(int x, int y, int d) { for (int j = -d; j <= d; j++) for (int i = -d; i <= d; i++) { int a = x + i, b = y + j; if (a >= 0 && b >= 0 && a < W && b < H && t[b, a] == 1) return true; } return false; }
            int np = 1 + (int)(R.Next() * 3) + Mathf.RoundToInt(hard * 5);   // more ponds / lava pools on harder fights: fewer good spots
            for (int k = 0; k < np; k++)
                for (int tr = 0; tr < 60; tr++)
                {
                    int sx = 1 + (int)(R.Next() * (W - 3)), sy = 1 + (int)(R.Next() * (H - 3));
                    if (nearPath(sx, sy, 2) || nearPath(sx + 1, sy + 1, 2)) continue;
                    var blob = new List<int[]> { new[] { sx, sy }, new[] { sx + 1, sy }, new[] { sx, sy + 1 }, new[] { sx + 1, sy + 1 } }; int size = 6 + (int)(R.Next() * 10) + Mathf.RoundToInt(hard * 14 * R.Next());
                    for (int g = 0; g < 200 && blob.Count < size; g++)
                    {
                        var bc = blob[(int)(R.Next() * blob.Count)]; var d = NB[new[] { 0, 2, 4, 6 }[(int)(R.Next() * 4)]];
                        int a = bc[0] + d[0], b = bc[1] + d[1];
                        if (a < 1 || b < 1 || a >= W - 1 || b >= H - 1 || nearPath(a, b, 1) || blob.Any(c => c[0] == a && c[1] == b)) continue;
                        blob.Add(new[] { a, b });
                    }
                    foreach (var c in blob) t[c[1], c[0]] = 2;
                    break;
                }
            for (int pass = 0; pass < 3; pass++)        // PMD's liquid tiles need 2x2 bodies to look right
                for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) if (t[y, x] == 2)
                        {
                            bool ok = false;
                            foreach (var o in new[] { new[] { 0, 0 }, new[] { -1, 0 }, new[] { 0, -1 }, new[] { -1, -1 } })
                            {
                                bool all = true;
                                foreach (var q in new[] { new[] { 0, 0 }, new[] { 1, 0 }, new[] { 0, 1 }, new[] { 1, 1 } })
                                { int a = x + o[0] + q[0], b = y + o[1] + q[1]; if (!(a >= 0 && b >= 0 && a < W && b < H && t[b, a] == 2)) { all = false; break; } }
                                if (all) ok = true;
                            }
                            if (!ok) t[y, x] = 0;
                        }
            M.kind = kind; M.W = W; M.H = H; M.t = t;
            if (portrait)
            {
                var tt = new int[W, H]; for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) tt[x, y] = t[y, x];
                M.t = tt; M.W = H; M.H = W; M.lines = M.lines.Select(l => l.Select(v => new Vector2(v.y, v.x)).ToList()).ToList();
            }
            foreach (var l in M.lines) { var r = MkRoute(l); r.air = MkRoute(AirLine(l)); M.routes.Add(r); }
            M.vr = new int[M.H, M.W]; for (int y = 0; y < M.H; y++) for (int x = 0; x < M.W; x++) M.vr[y, x] = (int)(R.Next() * 3);
            Render(M);
            return M;
        }
        static Route MkRoute(List<Vector2> line) { var r = new Route { line = line }; for (int i = 1; i < line.Count; i++) { float l = Vector2.Distance(line[i], line[i - 1]); r.seg.Add(l); r.len += l; } return r; }
        static List<Vector2> AirLine(List<Vector2> line) { var o = new List<Vector2> { line[0] }; for (int i = 2; i < line.Count - 1; i += 2) o.Add(line[i]); o.Add(line[line.Count - 1]); return o; }
        public static int TileAt(MapData M, int x, int y) => M.t[Mathf.Clamp(y, 0, M.H - 1), Mathf.Clamp(x, 0, M.W - 1)];

        static readonly Dictionary<string, Color32[]> tsPix = new Dictionary<string, Color32[]>();
        /* a little strip of the setting's own tiles (ground, a path, a pond) drawn with the same PMD auto-tile rules as the maps */
        static readonly Dictionary<int, Texture2D> swatch = new Dictionary<int, Texture2D>();
        public static Texture2D Swatch(int i)
        {
            if (swatch.TryGetValue(i, out var tx)) return tx;
            const int W = 12, H = 4; var t = new int[H, W];
            for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) t[y, x] = ((y == 1 || y == 2) && x < 8) || (x >= 7 && y >= 1 && x <= 8) ? 1 : 0;
            t[0, 10] = t[0, 11] = t[1, 10] = t[1, 11] = 2;
            var M = new MapData { set = i, W = W, H = H, t = t, vr = new int[H, W] }; var R = new Rng((uint)(i + 1));
            for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) M.vr[y, x] = (int)(R.Next() * 3);
            Render(M); swatch[i] = M.tex; return M.tex;
        }
        /* paint the map with PMD's own auto-tile rules into one texture */
        static void Render(MapData M)
        {
            var S = DB.TS[M.set]; var src = Gfx.Tex("Ts/" + S.ts); int C = S.cols > 0 ? S.cols : 10;
            if (!tsPix.TryGetValue(S.ts, out var sp)) { sp = src.GetPixels32(); tsPix[S.ts] = sp; }
            int sw = src.width, shh = src.height, mw = M.W * TZ, mh = M.H * TZ;
            var dst = new Color32[mw * mh];
            for (int y = 0; y < M.H; y++) for (int x = 0; x < M.W; x++)
                {
                    int v = M.t[y, x], mask = 0;
                    for (int i = 0; i < 8; i++) { int n = TileAt(M, x + NB[i][0], y + NB[i][1]); if (v == 0 ? n == 0 : v == 1 ? n != 0 : n == v) mask |= 1 << i; }
                    int key = mask + (v == 1 ? 512 : v == 2 ? 256 : 0), ri = M.vr[y, x] + key * 3;
                    if (ri >= S.rules.Length) continue;
                    int b = S.rules[ri]; if (b < 0) continue;
                    int bx = (b % C) * TZ, by = (b / C) * TZ;
                    for (int j = 0; j < TZ; j++)
                    {
                        int sy = shh - 1 - (by + j), dy = mh - 1 - (y * TZ + j);
                        if (sy < 0) continue;
                        Array.Copy(sp, sy * sw + bx, dst, dy * mw + x * TZ, TZ);
                    }
                }
            M.tex = new Texture2D(mw, mh, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Clamp };
            M.tex.SetPixels32(dst); M.tex.Apply();
            M.sprite = Sprite.Create(M.tex, new Rect(0, 0, mw, mh), new Vector2(0, 1), 1f);   // pivot top-left: game (0,0) = world (0,0)
        }

        /* position + facing along a route at distance d (game pixels, y down) */
        public static Vector3 PathAt(Route r, float d)
        {
            int i = 0;
            while (i < r.seg.Count - 1 && d > r.seg[i]) { d -= r.seg[i]; i++; }
            var a = r.line[i]; var b = r.line[i + 1]; float f = r.seg[i] > 0 ? Mathf.Clamp01(d / r.seg[i]) : 0;
            return new Vector3(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, Mathf.Atan2(b.y - a.y, b.x - a.x));
        }
        public static float NearestD(Route r, float x, float y) { float best = 0, bd = 1e9f; for (float d = 0; d <= r.len; d += 6) { var p = PathAt(r, d); float k = Mathf.Sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)); if (k < bd) { bd = k; best = d; } } return best; }
        public static float DistToPath(MapData M, float x, float y)
        {
            float best = 1e9f;
            foreach (var line in M.lines) for (int i = 1; i < line.Count; i++)
                {
                    var a = line[i - 1]; var b = line[i]; float dx = b.x - a.x, dy = b.y - a.y, l = dx * dx + dy * dy;
                    float f = l > 0 ? Mathf.Clamp01(((x - a.x) * dx + (y - a.y) * dy) / l) : 0;
                    best = Mathf.Min(best, Mathf.Sqrt(Mathf.Pow(x - a.x - dx * f, 2) + Mathf.Pow(y - a.y - dy * f, 2)));
                }
            return best;
        }
    }
}
