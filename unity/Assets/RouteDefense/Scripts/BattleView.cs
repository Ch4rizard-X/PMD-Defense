// Route Defense — draws a battle: the map, Pokémon, shadows, HP bars, move effects, damage numbers and range rings.
// Game coordinates are pixels with y down (same as the HTML version); world = (x, -y).
using System.Collections.Generic;
using UnityEngine;

namespace RouteDefense
{
    public class BattleView : MonoBehaviour
    {
        class V { public GameObject go; public SpriteRenderer sr, sh, hb, hf, st, sb, bub, fl, ko, trail, sel; public SpriteRenderer[] sparks; public float hpd = -1; public bool used; }
        readonly Dictionary<object, V> views = new Dictionary<object, V>();
        SpriteRenderer map, ring, ghostRing, ghost, ghostShadow;
        readonly List<SpriteRenderer> gatePool = new List<SpriteRenderer>(); int gateUsed;
        readonly List<SpriteRenderer> digitPool = new List<SpriteRenderer>(); int digitUsed;
        readonly List<TextMesh[]> textPool = new List<TextMesh[]>(); int textUsed; Font font;
        readonly List<SpriteRenderer> wxTiles = new List<SpriteRenderer>(); SpriteRenderer tint, glow; readonly List<SpriteRenderer> rays = new List<SpriteRenderer>(); Material addMat;
        public Camera cam; MapData shownMap;
        public Rect viewport = new Rect(0, 0, 1, 1);
        public Vector2? ghostPos; public bool ghostOk;
        static readonly Dictionary<string, Color> STS = new Dictionary<string, Color> {
            { "paralysis", new Color(1, 1, 0) }, { "sleep", new Color(.67f, .67f, 1) }, { "freeze", new Color(.53f, 1, 1) }, { "burn", new Color(1, .4f, 0) },
            { "poison", new Color(.8f, .27f, 1) }, { "confusion", new Color(1, .53f, .8f) }, { "trap", new Color(.67f, .53f, .27f) }, { "yawn", new Color(.8f, .8f, .8f) }, { "leech-seed", new Color(.4f, .8f, .2f) } };

        void Awake()
        {
            cam = new GameObject("BattleCamera").AddComponent<Camera>(); cam.transform.SetParent(transform);
            cam.orthographic = true; cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = Color.black; cam.nearClipPlane = -100; cam.farClipPlane = 100;
            // a full-screen camera behind it that only clears to black, so no old frames show outside the map
            var bg = new GameObject("BackgroundCamera").AddComponent<Camera>(); bg.transform.SetParent(transform);
            bg.clearFlags = CameraClearFlags.SolidColor; bg.backgroundColor = Color.black; bg.cullingMask = 0; bg.depth = -10; bg.orthographic = true;
            cam.depth = 0;
            map = Make("map", Gfx.White, -32000);
            ring = Make("ring", Gfx.Ring, 31000); ghostRing = Make("ghostRing", Gfx.Ring, 31000);
            ghostShadow = Make("ghostShadow", Gfx.Shadow, -20000); ghostShadow.color = new Color(0, 0, 0, .28f);
            ghost = Make("ghost", null, 31500);
            tint = Make("weatherTint", Gfx.White, 29000); glow = Make("sunGlow", Gfx.Glow, 29100);
            for (int i = 0; i < 7; i++) rays.Add(Make("sunRay", Gfx.Ray, 29200));
            font = Resources.Load<Font>("Fonts/pmd");
            // the font builds its letter sheet on demand: when it rebuilds, words already on screen must be laid out again or they show as solid bars
            Font.textureRebuilt += f => { if (f != font) return; foreach (var pr in textPool) foreach (var tm in pr) { var t0 = tm.text; tm.text = ""; tm.text = t0; } };
            var shd = Shader.Find("Legacy Shaders/Particles/Additive"); if (shd != null) addMat = new Material(shd);
        }
        SpriteRenderer Make(string n, Sprite s, int order)
        {
            var g = new GameObject(n); g.transform.SetParent(transform); var r = g.AddComponent<SpriteRenderer>(); r.sprite = s; r.sortingOrder = order; return r;
        }
        static Vector3 W(float x, float y) => new Vector3(x, -y, 0);

        /* fit the whole map inside the stage area of the screen */
        public float zoom = 1; public Vector2 zc = new Vector2(-1, -1);   // pinch zoom: zc is the map point at the screen's centre (-1 = middle of the map)
        public void ResetZoom() { zoom = 1; zc = new Vector2(-1, -1); }
        public void Refit() { if (Battle.B != null) Fit(Battle.B.M); }
        void Fit(MapData M)
        {
            // shrink the camera to exactly the map's shape inside the stage, so nothing shows past the map's edges
            // fill the screen (the map is made in the screen's shape, so little is cut); buttons float on top
            float mw = M.W * MapGen.TZ, mh = M.H * MapGen.TZ;
            float sw = Screen.width * viewport.width, sh = Mathf.Max(1, Screen.height * viewport.height);
            float k = Mathf.Max(sw / mw, sh / mh) * Mathf.Max(1, zoom);
            cam.rect = viewport;
            cam.orthographicSize = sh / k / 2f;
            float hw = sw / k / 2f, hh = sh / k / 2f; if (zc.x < 0) zc = new Vector2(mw / 2f, mh / 2f);
            zc = new Vector2(hw * 2 >= mw ? mw / 2f : Mathf.Clamp(zc.x, hw, mw - hw), hh * 2 >= mh ? mh / 2f : Mathf.Clamp(zc.y, hh, mh - hh));   // never show past the map's edges
            cam.transform.position = new Vector3(zc.x, -zc.y, -10);
        }
        /* screen pixel -> game pixel */
        public Vector2 ScreenToGame(Vector2 screen)
        {
            var w = cam.ScreenToWorldPoint(new Vector3(screen.x, screen.y, 0));
            return new Vector2(w.x, -w.y);
        }

        void LateUpdate()
        {
            var B = Battle.B; bool on = B != null && UI.InBattle;
            cam.enabled = true; if (!on) { foreach (var v in views.Values) Destroy(v.go); views.Clear(); HideDigits(0); map.enabled = false; ring.enabled = ghostRing.enabled = ghost.enabled = ghostShadow.enabled = false; HideTexts(0); foreach (var gp2 in gatePool) gp2.enabled = false; tint.enabled = false; glow.enabled = false; foreach (var ry in rays) ry.enabled = false; foreach (var wt in wxTiles) wt.enabled = false; return; }
            if (shownMap != B.M) { shownMap = B.M; map.sprite = B.M.sprite; }
            map.enabled = true; map.transform.position = Vector3.zero;
            Fit(B.M);
            foreach (var v in views.Values) v.used = false;

            foreach (var t in B.towers)
            {
                var v = Get(t);
                var meta = Gfx.Meta(t.e.id, t.anim); int f = meta == null ? 0 : Gfx.FrameAt(meta.d, meta.Total, t.at, t.anim == "Idle");
                v.sr.sprite = Gfx.MonFrame(t.e.id, t.anim, f, t.dir); v.sr.color = Color.white;
                v.go.transform.position = W(t.x, t.y); v.sr.sortingOrder = (int)t.y * 2;
                v.sh.sprite = Gfx.Marker(true, t.e.id); v.sh.color = Color.white; v.sh.transform.localPosition = Vector3.zero; v.sh.transform.localScale = Vector3.one * Battle.SPR; v.sr.transform.localScale = Vector3.one * Battle.SPR;
                v.fl.enabled = false; v.ko.enabled = false; foreach (var sp in v.sparks) sp.enabled = false; v.trail.enabled = false;
                v.sel.enabled = B.sel == t; if (B.sel == t) { float pl = 0.5f + 0.5f * Mathf.Sin(B.time * 6); v.sel.transform.localScale = new Vector3(30 * Battle.SPR / 128f, 12 * Battle.SPR / 52f, 1); v.sel.color = new Color(1, .85f, .29f, 0.5f + 0.5f * pl); }
                v.hb.enabled = v.hf.enabled = false; v.st.enabled = t.buft > 0; if (t.buft > 0) { v.st.color = new Color(1, .53f, .27f); v.st.transform.localPosition = new Vector3(0, 30 * Battle.SPR, 0); }
            }
            foreach (var e in B.en)
            {
                var v = Get(e);
                if (e.d <= 0) { v.go.SetActive(false); continue; }
                v.go.SetActive(true);
                float al = e.hp <= 0 ? Mathf.Clamp01(e.dead / 0.5f) : 1;
                bool hidden = e.hp > 0 && (e.under || (e.hide && !(e.rev > 0)));
                if (e.hide && !(e.rev > 0)) al *= 0.28f; if (e.under) al *= 0.12f;
                float lift = (e.air ? 12 + Mathf.Sin(B.time * 3 + e.ph) * 2.5f : 0) * Battle.ESPR;
                var A = DB.Anim[e.id]; string walk = e.air && A.ContainsKey("Hover") ? "Hover" : "Walk";
                string an = e.hp <= 0 || e.hurt > 0 ? "Hurt" : e.stop > 0 && e.sts != null ? "Idle" : walk;
                var meta = Gfx.Meta(e.id, an); int f = meta == null ? 0 : Gfx.FrameAt(meta.d, meta.Total, e.at, true);
                v.sr.sprite = Gfx.MonFrame(e.id, an, f, e.dir); v.sr.color = new Color(1, 1, 1, al);
                v.go.transform.position = W(e.x, e.y); v.sr.transform.localPosition = new Vector3(0, lift, 0); v.sr.transform.localScale = Vector3.one * Battle.ESPR; v.sr.sortingOrder = (int)e.y * 2 + 1;
                v.sh.sprite = Gfx.Marker(false, e.id); v.sh.color = new Color(1, 1, 1, al); v.sh.transform.localScale = Vector3.one * Battle.ESPR * (e.boss ? 1.3f : 1); v.sel.enabled = false;
                // white hit flash
                bool fla = e.hurt > 0.12f && e.hp > 0 && Gfx.FlashMat != null; v.fl.enabled = fla;
                if (fla) { v.fl.sprite = v.sr.sprite; v.fl.sharedMaterial = Gfx.FlashMat; v.fl.color = new Color(1, 1, 1, Mathf.Clamp((e.hurt - 0.12f) * 5, 0, 0.85f)); v.fl.transform.localPosition = v.sr.transform.localPosition; v.fl.transform.localScale = v.sr.transform.localScale; v.fl.sortingOrder = v.sr.sortingOrder; }
                // knockout: a quick ring and sparks
                float kk = 1 - Mathf.Clamp01(e.dead / 0.5f); bool kob = e.hp <= 0 && kk < 1; v.ko.enabled = kob; foreach (var sp in v.sparks) sp.enabled = kob;
                if (kob)
                {
                    float R = (e.boss ? 26 : 14) * (0.4f + kk), ka = (1 - kk) * 0.8f; var c0 = new Vector3(0, 10 * Battle.ESPR, 0);
                    v.ko.transform.localPosition = c0; v.ko.transform.localScale = Vector3.one * (R * 2 / 64f); v.ko.color = new Color(1, 1, 1, ka);
                    for (int i = 0; i < 8; i++) { float sa = i * Mathf.PI / 4 + 0.4f; v.sparks[i].transform.localPosition = c0 + new Vector3(Mathf.Cos(sa), -Mathf.Sin(sa), 0) * R * 1.25f; v.sparks[i].color = new Color(1, .9f, .5f, ka); }
                }
                bool bar = e.hp > 0 && !hidden && (e.hp < e.max || e.boss || e.sh > 0 || B.selE == e);   // bars only once hurt (cleaner map); bosses always
                v.hb.enabled = v.hf.enabled = v.trail.enabled = bar; v.st.enabled = bar && e.sts != null;
                if (bar)
                {
                    float w = e.boss ? 30 : 18, fr = Mathf.Clamp01(e.hp / e.max);
                    v.hpd = v.hpd < 0 ? fr : Mathf.Max(fr, v.hpd - 0.02f);   // recent damage trails behind
                    v.trail.transform.localPosition = new Vector3(-w / 2 + w * v.hpd / 2, -8, 0); v.trail.transform.localScale = new Vector3(Mathf.Max(0.01f, w * v.hpd / 2f), 1, 1);
                    v.hb.transform.localPosition = new Vector3(0, -8, 0); v.hb.transform.localScale = new Vector3((w + 2) / 2f, 2, 1);
                    v.hf.transform.localPosition = new Vector3(-w / 2 + w * fr / 2, -8, 0); v.hf.transform.localScale = new Vector3(Mathf.Max(0.01f, w * fr / 2f), 1, 1);
                    v.hf.color = fr > .5f ? new Color(.2f, .8f, .2f) : fr > .2f ? new Color(1, .8f, .2f) : new Color(1, .2f, .2f);
                    if (e.sts != null) { v.st.color = STS.TryGetValue(e.sts, out var c) ? c : Color.white; v.st.transform.localPosition = new Vector3(w / 2 + 4, -8, 0); }
                }
                bool shield = e.hp > 0 && e.sh > 0 && !hidden;     // Protect-type shield: a green bubble and a thin bar over the HP bar
                v.bub.enabled = v.sb.enabled = shield;
                if (shield)
                {
                    float bw = e.boss ? 30 : 18, br = (e.boss ? 22 : 15) * Battle.SPR, sf = e.sh / Mathf.Max(1, e.shm);
                    v.bub.transform.localPosition = new Vector3(0, 10 * Battle.SPR + lift, 0); v.bub.transform.localScale = Vector3.one * (br * 2 / 256f); v.bub.color = new Color(.63f, 1, .63f, .9f);
                    v.sb.transform.localPosition = new Vector3(-bw / 2 + bw * sf / 2, -6, 0); v.sb.transform.localScale = new Vector3(Mathf.Max(.01f, bw * sf / 2f), .5f, 1);
                }
            }
            foreach (var p in B.proj)
            {
                var v = Get(p, false); int f = Gfx.FrameAt(p.fx.d, p.fx.Total, p.at, true);
                bool turn = PROJ_FRONT.TryGetValue(p.fx.f.Replace("_anim", "/anim"), out var front) && !float.IsNaN(p.ang);
                v.sr.sprite = Gfx.FxFrame(p.fx, f, turn ? 0 : p.row); v.go.transform.position = W(p.x, p.y); v.sr.transform.localScale = Vector3.one * Battle.FXS; v.sr.sortingOrder = 30000;
                v.sr.transform.localRotation = Quaternion.Euler(0, 0, turn ? -(p.ang - front) * Mathf.Rad2Deg : 0);   // game y points down, so turns flip sign
            }
            foreach (var x in B.fx)
            {
                var v = Get(x, false); int f = Gfx.FrameAt(x.a.d, x.a.Total, x.t, true);
                v.sr.sprite = Gfx.FxFrame(x.a, f, x.rot != 0 ? 0 : x.row); v.go.transform.position = W(x.x, x.y); v.sr.transform.localScale = Vector3.one * Battle.FXS; v.sr.sortingOrder = 30001;
                v.sr.transform.localRotation = Quaternion.Euler(0, 0, -x.rot * Mathf.Rad2Deg);
            }
            var dead = new List<object>(); foreach (var kv in views) if (!kv.Value.used) dead.Add(kv.Key);
            foreach (var k in dead) { Destroy(views[k].go); views.Remove(k); }

            // damage numbers (PMD's own digits)
            digitUsed = 0;
            foreach (var fl in B.fl)
            {
                float y = fl.y - fl.t * 22;
                if (fl.txt == "MISS") { var d = Digit(); d.sprite = Gfx.Digit(false, 12, 32); d.transform.position = W(fl.x, y); continue; }
                string s = fl.txt.StartsWith("Lv ") ? fl.txt.Substring(3) : fl.txt; bool blue = fl.kind == 3;
                if (s.Length == 0 || !char.IsDigit(s[0])) { if (s != "!") Text(fl.txt, fl.x, y, fl.kind); continue; }
                float x0 = fl.x - s.Length * 7 / 2f + 3.5f;
                for (int i = 0; i < s.Length; i++) { if (!char.IsDigit(s[i])) continue; var d = Digit(); d.sprite = Gfx.Digit(blue, s[i] - '0'); d.transform.position = W(x0 + i * 7, y); }
            }
            HideDigits(digitUsed); HideTexts(textUsed);
            DrawWeather(B); DrawGates(B);

            // range ring for the selected tower, and the placement ghost
            ring.enabled = B.sel != null;
            if (B.sel != null) { float r = Battle.MaxRange(B.sel); ring.transform.position = W(B.sel.x, B.sel.y); ring.transform.localScale = Vector3.one * (r * 2 / 256f); ring.color = Color.white; }
            bool gh = B.placing != null && ghostPos.HasValue;
            ghostRing.enabled = ghost.enabled = ghostShadow.enabled = gh;
            if (gh)
            {
                var gp = ghostPos.Value; float r = Battle.RangeFor(B.placing);
                ghostRing.transform.position = W(gp.x, gp.y); ghostRing.transform.localScale = Vector3.one * (r * 2 / 256f); ghostRing.color = ghostOk ? Color.white : new Color(1, .25f, .25f);
                var meta = Gfx.Meta(B.placing.id, "Idle"); int f = meta == null ? 0 : Gfx.FrameAt(meta.d, meta.Total, B.time, true);
                ghost.sprite = Gfx.MonFrame(B.placing.id, "Idle", f, 0); ghost.transform.position = W(gp.x, gp.y); ghost.transform.localScale = Vector3.one * Battle.SPR; ghost.color = new Color(1, 1, 1, ghostOk ? .8f : .4f);
                ghostShadow.sprite = Gfx.Marker(true, B.placing.id); ghostShadow.color = Color.white; ghostShadow.transform.position = W(gp.x, gp.y); ghostShadow.transform.localScale = Vector3.one * Battle.SPR;
            }
        }
        /* where wild Pokémon come in (green) and where they escape (red, pulsing): a soft glow and two sliding chevrons */
        void DrawGates(Battle B)
        {
            gateUsed = 0; float mw = B.M.W * MapGen.TZ, mh = B.M.H * MapGen.TZ, p = 0.5f + 0.5f * Mathf.Sin(B.time * 4); var seen = new HashSet<Vector2>();
            void gate(Vector2 pt, Vector2 dir, Color col)
            {
                var c = new Vector2(Mathf.Clamp(pt.x, 10, mw - 10), Mathf.Clamp(pt.y, 10, mh - 10)); if (!seen.Add(c)) return;
                var gl = GateSpr(Gfx.Glow, -19500); gl.transform.position = W(c.x, c.y); gl.transform.localScale = Vector3.one * (60 / 128f); gl.transform.localRotation = Quaternion.identity; gl.color = new Color(col.r, col.g, col.b, 0.45f + 0.25f * p);
                float a = Mathf.Atan2(dir.y, dir.x);
                for (int i = 0; i < 2; i++)
                {
                    float o = ((B.time * 18 + i * 9) % 18) - 9; var ch = GateSpr(Gfx.Chevron, -19400);
                    ch.transform.position = W(c.x + Mathf.Cos(a) * o, c.y + Mathf.Sin(a) * o); ch.transform.localRotation = Quaternion.Euler(0, 0, -a * Mathf.Rad2Deg); ch.transform.localScale = Vector3.one; ch.color = new Color(col.r, col.g, col.b, .85f);
                }
            }
            foreach (var r in B.M.routes)
            {
                var l = r.line; gate(l[0], l[1] - l[0], new Color(90 / 255f, 230 / 255f, 120 / 255f)); gate(l[l.Count - 1], l[l.Count - 1] - l[l.Count - 2], new Color(1, 70 / 255f, 70 / 255f));
            }
            for (int i = gateUsed; i < gatePool.Count; i++) gatePool[i].enabled = false;
        }
        SpriteRenderer GateSpr(Sprite s, int order)
        {
            if (gateUsed >= gatePool.Count) gatePool.Add(Make("gate", s, order));
            var g = gatePool[gateUsed++]; g.enabled = true; g.sprite = s; g.sortingOrder = order; return g;
        }
        /* the ROM draws every projectile in one orientation; these have a clear front, so they're turned to face where they fly.
           value = which way the front points in the sheet (radians; 0 = right, PI/2 = down) */
        static readonly Dictionary<string, float> PROJ_FRONT = new Dictionary<string, float> {
            { "efob013/anim48", Mathf.PI / 2 }, { "efob136/anim16", Mathf.PI / 2 }, { "efob136/anim24", Mathf.PI / 2 }, { "efob062/anim00", Mathf.PI / 2 },
            { "efob052/anim00", Mathf.PI / 2 }, { "efob118/anim00", Mathf.PI / 2 }, { "efob013/anim32", Mathf.PI / 2 }, { "efob013/anim08", 0 },
            { "efob069/anim00", Mathf.PI / 2 }, { "efob127/anim00", Mathf.PI / 2 }, { "efob013/anim16", -Mathf.PI / 2 } };   // Megahorn and Icicle Spear lead with their point; Mud Shot's stack is aligned with its flight
        V Get(object o, bool unit = true)
        {
            if (!views.TryGetValue(o, out var v))
            {
                v = new V { go = new GameObject("u") }; v.go.transform.SetParent(transform);
                v.sr = new GameObject("spr").AddComponent<SpriteRenderer>(); v.sr.transform.SetParent(v.go.transform, false);
                if (unit)
                {
                    v.sh = new GameObject("shadow").AddComponent<SpriteRenderer>(); v.sh.transform.SetParent(v.go.transform, false); v.sh.sprite = Gfx.Shadow; v.sh.color = new Color(0, 0, 0, .28f); v.sh.sortingOrder = -20000;
                    v.hb = Bar(v.go, Color.black, 30010); v.hf = Bar(v.go, Color.green, 30011); v.st = Bar(v.go, Color.white, 30012); v.st.transform.localScale = new Vector3(2, 2, 1);
                    v.sb = Bar(v.go, new Color(.6f, 1, .6f), 30013); v.sb.enabled = false;
                    v.bub = new GameObject("shield").AddComponent<SpriteRenderer>(); v.bub.transform.SetParent(v.go.transform, false); v.bub.sprite = Gfx.Ring; v.bub.sortingOrder = 30005; v.bub.enabled = false;
                    v.trail = Bar(v.go, new Color(1, 1, 1, .55f), 30010); v.trail.sortingOrder = 30010; v.hf.sortingOrder = 30011;
                    v.fl = new GameObject("flash").AddComponent<SpriteRenderer>(); v.fl.transform.SetParent(v.go.transform, false); v.fl.enabled = false;
                    v.ko = new GameObject("ko").AddComponent<SpriteRenderer>(); v.ko.transform.SetParent(v.go.transform, false); v.ko.sprite = Gfx.KoRing; v.ko.sortingOrder = 30020; v.ko.enabled = false;
                    v.sparks = new SpriteRenderer[8]; for (int i = 0; i < 8; i++) { var sp = new GameObject("spark").AddComponent<SpriteRenderer>(); sp.transform.SetParent(v.go.transform, false); sp.sprite = Gfx.Spark; sp.sortingOrder = 30021; sp.enabled = false; v.sparks[i] = sp; }
                    v.sel = new GameObject("sel").AddComponent<SpriteRenderer>(); v.sel.transform.SetParent(v.go.transform, false); v.sel.sprite = Gfx.SelRing; v.sel.sortingOrder = -19990; v.sel.enabled = false;
                }
                views[o] = v;
            }
            v.used = true; return v;
        }
        static SpriteRenderer Bar(GameObject parent, Color c, int order)
        {
            var r = new GameObject("bar").AddComponent<SpriteRenderer>(); r.transform.SetParent(parent.transform, false); r.sprite = Gfx.White; r.color = c; r.sortingOrder = order; return r;
        }
        SpriteRenderer Digit()
        {
            if (digitUsed >= digitPool.Count) digitPool.Add(Make("digit", null, 31800));
            var d = digitPool[digitUsed++]; d.enabled = true; return d;
        }
        void HideDigits(int from) { for (int i = from; i < digitPool.Count; i++) digitPool[i].enabled = false; }
        /* words over a Pokémon (move names like Recover or Detect), in the PMD font with a dark edge */
        void Text(string txt, float x, float y, int kind)
        {
            if (font == null) return;
            if (textUsed >= textPool.Count)
            {
                var pair = new TextMesh[2];
                for (int i = 0; i < 2; i++)
                {
                    var g = new GameObject("text"); g.transform.SetParent(transform); var tm = g.AddComponent<TextMesh>();
                    tm.font = font; tm.fontSize = 44; tm.characterSize = 2.5f; tm.anchor = TextAnchor.MiddleCenter; tm.alignment = TextAlignment.Center;
                    var mr = g.GetComponent<MeshRenderer>(); mr.sharedMaterial = font.material; mr.sortingOrder = 31900 + i; pair[i] = tm;
                }
                textPool.Add(pair);
            }
            var p = textPool[textUsed++];
            font.RequestCharactersInTexture(txt, 44);
            p[0].text = p[1].text = txt; p[0].color = Color.black; p[1].color = kind == 2 ? new Color(1, .88f, .25f) : kind == 4 ? new Color(1, .63f, .75f) : new Color(.53f, 1, 1);
            p[0].transform.position = W(x + 1, y + 5); p[1].transform.position = W(x, y + 4);
            p[0].gameObject.SetActive(true); p[1].gameObject.SetActive(true);
        }
        void HideTexts(int from) { for (int i = from; i < textPool.Count; i++) { textPool[i][0].gameObject.SetActive(false); textPool[i][1].gameObject.SetActive(false); } }
        /* weather over the map: PMD Red's own rain / sandstorm / hail screens, tiled; sunlight is a warm tint (the ROM has no sun screen) */
        void DrawWeather(Battle B)
        {
            var wk = B.weather != null ? B.weather.k : null; float mw = B.M.W * MapGen.TZ, mh = B.M.H * MapGen.TZ;
            tint.enabled = wk != null && wk != "sand";
            if (tint.enabled)
            {
                tint.color = wk == "rain" ? new Color(15 / 255f, 25 / 255f, 60 / 255f, .22f) : wk == "hail" ? new Color(30 / 255f, 45 / 255f, 75 / 255f, .16f) : new Color(1, 170 / 255f, 40 / 255f, .12f);
                tint.transform.position = W(mw / 2, mh / 2); tint.transform.localScale = new Vector3(mw / 2f, mh / 2f, 1);
            }
            int used = 0;
            if (wk != null && DB.Wx.TryGetValue(wk, out var w))
            {
                var tex = Gfx.Tex("Wx/" + wk);
                if (tex != null)
                {
                    int f = Mathf.FloorToInt(B.time * 1000 / w.ms) % w.n; var spr = Gfx.WxFrame(wk, tex, w, f); bool add = w.blend == "lighter" && addMat != null;
                    for (float y = 0; y < mh; y += w.fh) for (float x = 0; x < mw; x += w.fw)
                        {
                            if (used >= wxTiles.Count) wxTiles.Add(Make("weather", null, 29500));
                            var t = wxTiles[used++]; t.enabled = true; t.sprite = spr; t.transform.position = W(x + w.fw / 2f, y + w.fh / 2f);
                            if (add) { t.sharedMaterial = addMat; t.color = Color.white; } else t.color = new Color(1, 1, 1, .4f);
                        }
                }
            }
            for (int i = used; i < wxTiles.Count; i++) wxTiles[i].enabled = false;
            SunRays(B, wk == "sun");
        }
        /* sunlight: soft diagonal shafts of warm light that drift and shimmer across the map (drawn, not from the ROM: PMD Red has no sunlight screen) */
        void SunRays(Battle B, bool on)
        {
            glow.enabled = on; foreach (var ry in rays) ry.enabled = on; if (!on) return;
            float mw = B.M.W * MapGen.TZ, mh = B.M.H * MapGen.TZ, ang = 0.42f, len = mh / Mathf.Cos(ang) * 1.15f, T = B.time; int n = rays.Count;
            float gr = Mathf.Max(mw, mh) * 0.7f; glow.transform.position = W(0, 0); glow.transform.localScale = Vector3.one * (gr * 2 / 128f); glow.color = new Color(1, .86f, .55f, .22f);   // the sun sits off the top-left corner
            for (int i = 0; i < n; i++)
            {
                float bs = (i + 0.5f) / n, x = (-0.25f + bs * 1.15f) * mw + Mathf.Sin(T * 0.11f + i * 1.7f) * mw * 0.03f;   // slow drift
                float w = mw * (0.035f + 0.05f * ((i * 0.618f) % 1)) * (1 + 0.15f * Mathf.Sin(T * 0.3f + i));
                float a = 0.3f + 0.18f * (0.5f + 0.5f * Mathf.Sin(T * 0.6f + i * 2.3f));   // shimmer
                var ry = rays[i]; ry.transform.position = W(x, -mh * 0.05f); ry.transform.localScale = new Vector3(w / 64f, len / 256f, 1);
                ry.transform.localRotation = Quaternion.Euler(0, 0, ang * Mathf.Rad2Deg); ry.color = new Color(1, .97f, .85f, a * 0.8f);
            }
        }
    }
}
