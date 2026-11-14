// Route Defense — textures, sprites and sound. Everything is loaded from Resources (1 world unit = 1 game pixel).
using System.Collections.Generic;
using UnityEngine;

namespace RouteDefense
{
    public static class Gfx
    {
        static readonly Dictionary<string, Texture2D> tex = new Dictionary<string, Texture2D>();
        static readonly Dictionary<string, Sprite> monSpr = new Dictionary<string, Sprite>();
        static readonly Dictionary<string, Sprite> misc = new Dictionary<string, Sprite>();

        public static Texture2D Tex(string path)
        {
            if (tex.TryGetValue(path, out var t)) return t;
            t = Resources.Load<Texture2D>(path);
            if (t == null)   // sprite sheets are kept as their PNG files (.bytes) so the APK stays small; decoded on first use, pixel-perfect
            {
                var raw = Resources.Load<TextAsset>(path);
                if (raw != null) { t = new Texture2D(2, 2, TextureFormat.RGBA32, false); t.LoadImage(raw.bytes, false); Resources.UnloadAsset(raw); }
            }
            if (t != null) { t.filterMode = FilterMode.Point; t.wrapMode = TextureWrapMode.Clamp; }
            tex[path] = t; return t;
        }
        public static Texture2D MonTex(int id) => Tex("Mon/" + id.ToString("0000"));

        /* one frame of a Pokémon animation; the pivot is the sheet's own ground point */
        public static Sprite MonFrame(int id, string anim, int frame, int row)
        {
            if (!DB.Anim.TryGetValue(id, out var A)) return null;
            if (!A.TryGetValue(anim, out var a) && !A.TryGetValue("Idle", out a) && !A.TryGetValue("Walk", out a)) return null;
            int r = a.r > 1 ? row : 0;
            string key = id + ":" + anim + ":" + frame + ":" + r;
            if (monSpr.TryGetValue(key, out var s)) return s;
            var t = MonTex(id); if (t == null) return null;
            float[] gp = a.sh != null ? a.sh[Mathf.Min(r, a.sh.Length - 1)] : new float[] { a.fw / 2f, a.fh / 2f + 4 };
            var rect = new Rect(frame * a.fw, t.height - (a.y + r * a.fh) - a.fh, a.fw, a.fh);
            s = Sprite.Create(t, rect, new Vector2(gp[0] / a.fw, 1f - gp[1] / a.fh), 1f, 0, SpriteMeshType.FullRect);
            monSpr[key] = s; return s;
        }
        /* a menu icon from the shared icon sheet: no need to load each Pokémon's whole sprite sheet (that made the Pokédex freeze) */
        public static Sprite MonIcon(int id)
        {
            string key = "mi:" + id; if (misc.TryGetValue(key, out var s)) return s;
            if (!DB.MIcon.TryGetValue(id, out var n)) return null;
            var t = Tex("Ui/monicons"); if (t == null) return null;
            int c = DB.MIconCell, col = n % DB.MIconCols, row = n / DB.MIconCols;
            s = Sprite.Create(t, new Rect(col * c, t.height - (row + 1) * c, c, c), new Vector2(0.5f, 0.5f), 1f, 0, SpriteMeshType.FullRect); misc[key] = s; return s;
        }
        /* frame index for time t (seconds) — loop or hold the last frame */
        public static int FrameAt(int[] d, int total, float t, bool loop)
        {
            int ft = Mathf.FloorToInt(t * 60);
            ft = loop ? ft % total : Mathf.Min(ft, total - 1);
            int f = 0; while (f < d.Length - 1 && ft >= d[f]) { ft -= d[f]; f++; }
            return f;
        }
        public static AnimMeta Meta(int id, string anim)
        {
            if (!DB.Anim.TryGetValue(id, out var A)) return null;
            if (A.TryGetValue(anim, out var a) || A.TryGetValue("Idle", out a) || A.TryGetValue("Walk", out a)) return a;
            return null;
        }
        public static Sprite FxFrame(FxAnim a, int frame, int row)
        {
            string k = a.f + ":" + frame + ":" + row;
            if (misc.TryGetValue(k, out var s)) return s;
            var t = Tex("Fx/" + a.f); if (t == null) return null;
            int r = a.r > 1 ? row : 0;
            s = Sprite.Create(t, new Rect(frame * a.fw, t.height - (r + 1) * a.fh, a.fw, a.fh), new Vector2(0.5f, 0.5f), 1f, 0, SpriteMeshType.FullRect);
            misc[k] = s; return s;
        }
        /* one frame of a PMD weather screen (sheets are frames left to right, rows top to bottom) */
        public static Sprite WxFrame(string k, Texture2D t, WxMeta w, int f)
        {
            string key = "wx:" + k + ":" + f;
            if (misc.TryGetValue(key, out var s)) return s;
            int col = f % w.per, row = f / w.per;
            s = Sprite.Create(t, new Rect(col * w.fw, t.height - (row + 1) * w.fh, w.fw, w.fh), new Vector2(0.5f, 0.5f), 1f, 0, SpriteMeshType.FullRect);
            misc[key] = s; return s;
        }
        /* main-series bag sprite for an item */
        public static Sprite ItemIcon(int id)
        {
            if (!DB.Icons.TryGetValue(id, out var k)) return null;
            string key = "item:" + k; if (misc.TryGetValue(key, out var s)) return s;
            var t = Tex("Items/" + k); if (t == null) return null;
            s = Sprite.Create(t, new Rect(0, 0, t.width, t.height), new Vector2(0.5f, 0.5f), 1f); misc[key] = s; return s;
        }
        /* PMD damage digits: 0-9 then MISS, 8x8 cells */
        public static Sprite Digit(bool blue, int i, int w = 8)
        {
            string k = (blue ? "db" : "dr") + i + ":" + w;
            if (misc.TryGetValue(k, out var s)) return s;
            var t = Tex(blue ? "Ui/dmg_b" : "Ui/dmg_r"); if (t == null) return null;
            s = Sprite.Create(t, new Rect(i * 8, t.height - 8, w, 8), new Vector2(0.5f, 0.5f), 1f, 0, SpriteMeshType.FullRect);
            misc[k] = s; return s;
        }

        /* simple generated shapes: white pixel, soft ellipse (shadow), circle (range) */
        public static Sprite White => Gen("white", 2, 2, (x, y) => Color.white);
        public static Sprite Shadow => Gen("shadow", 32, 14, (x, y) => { float dx = (x - 15.5f) / 16f, dy = (y - 6.5f) / 7f; return dx * dx + dy * dy <= 1 ? Color.white : Color.clear; });
        public static Sprite Ring => Gen("ring", 256, 256, (x, y) =>
        {
            float d = Mathf.Sqrt((x - 127.5f) * (x - 127.5f) + (y - 127.5f) * (y - 127.5f));
            return d > 128 ? Color.clear : d > 125 ? new Color(1, 1, 1, 0.7f) : new Color(1, 1, 1, 0.16f);
        });
        /* one soft light shaft (pivot at its top), faded at both sides and toward the bottom; and the sun's soft glow */
        public static Sprite Ray
        {
            get
            {
                if (misc.TryGetValue("ray", out var s)) return s;
                var t = new Texture2D(64, 256, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };
                for (int y = 0; y < 256; y++) for (int x = 0; x < 64; x++)
                    {
                        float u = Mathf.Abs(x - 31.5f) / 32f, h = u < 0.3f ? Mathf.Lerp(1, .85f, u / 0.3f) : Mathf.Lerp(.85f, 0, (u - 0.3f) / 0.7f);
                        float d = 1 - y / 255f, v = d < 0.7f ? Mathf.Lerp(1, .7f, d / 0.7f) : Mathf.Lerp(.7f, 0, (d - 0.7f) / 0.3f);   // y = 255 is the top
                        t.SetPixel(x, y, new Color(1, 1, 1, h * v));
                    }
                t.Apply(); s = Sprite.Create(t, new Rect(0, 0, 64, 256), new Vector2(0.5f, 1f), 1f); misc["ray"] = s; return s;
            }
        }
        public static Sprite Glow => Gen("glow", 128, 128, (x, y) => { float d = Mathf.Sqrt((x - 63.5f) * (x - 63.5f) + (y - 63.5f) * (y - 63.5f)) / 64f; return new Color(1, 1, 1, Mathf.Clamp01(1 - d)); });
        /* PMD Red's own markers: yellow ring under your team, dark shadow under wild Pokémon */
        static readonly string[] MKS = { "small", "medium", "large" };
        public static Sprite Marker(bool team, int id)
        {
            int sz = DB.Mk.TryGetValue(id, out var v) ? v : 1; string k = (team ? "team_" : "enemy_") + MKS[Mathf.Clamp(sz, 0, 2)];
            if (misc.TryGetValue(k, out var s)) return s;
            var t = Tex("Ui/" + k); if (t == null) return Shadow;
            s = Sprite.Create(t, new Rect(0, 0, t.width, t.height), new Vector2(0.5f, 0.5f), 1f, 0, SpriteMeshType.FullRect); misc[k] = s; return s;
        }
        /* thin outline circle (knockout ring), a selection ellipse, a gate chevron and a small square spark */
        public static Sprite KoRing => Gen("koring", 64, 64, (x, y) => { float d = Mathf.Sqrt((x - 31.5f) * (x - 31.5f) + (y - 31.5f) * (y - 31.5f)); return d <= 32 && d >= 29 ? Color.white : Color.clear; });
        public static Sprite SelRing => Gen("selring", 128, 52, (x, y) => { float dx = (x - 63.5f) / 64f, dy = (y - 25.5f) / 26f, d = Mathf.Sqrt(dx * dx + dy * dy); return d <= 1 && d >= 0.92f ? Color.white : Color.clear; });
        public static Sprite Chevron => Gen("chevron2", 16, 16, (x, y) => { float u = 11 - x, v = Mathf.Abs(y - 7.5f); return u >= v * 0.67f - 0.5f && u <= v * 0.67f + 3.5f && v <= 6 ? Color.white : Color.clear; });
        public static Sprite Spark => Gen("spark", 3, 3, (x, y) => Color.white);
        /* white silhouettes for hit flashes: the sprite's own alpha, tinted white */
        static Material flashMat;
        public static Material FlashMat { get { if (flashMat == null) { var sh = Shader.Find("GUI/Text Shader"); if (sh != null) flashMat = new Material(sh); } return flashMat; } }
        /* soft dark edges over the battle map, so the floating HUD sits on darker corners */
        public static Sprite Vignette => Gen("vignette", 128, 128, (x, y) => { float dx = (x - 63.5f) / 64f, dy = (y - 63.5f) / 64f, d = Mathf.Sqrt(dx * dx + dy * dy) / 1.414f; return new Color(0, 0, 10 / 255f, .38f * Mathf.Clamp01((d - 0.32f) / 0.5f)); });
        delegate Color Px(int x, int y);
        static Sprite Gen(string k, int w, int h, Px f)
        {
            if (misc.TryGetValue(k, out var s)) return s;
            var t = new Texture2D(w, h, TextureFormat.RGBA32, false) { filterMode = FilterMode.Bilinear, wrapMode = TextureWrapMode.Clamp };
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) t.SetPixel(x, y, f(x, y));
            t.Apply();
            s = Sprite.Create(t, new Rect(0, 0, w, h), new Vector2(0.5f, 0.5f), 1f);
            misc[k] = s; return s;
        }

        /* ---------- sound ---------- */
        static AudioSource music, sfx; static string curMusic = ""; static readonly Dictionary<string, float> last = new Dictionary<string, float>();
        public static string WantMusic = "";
        public static void InitAudio(GameObject host)
        {
            music = host.AddComponent<AudioSource>(); music.loop = true; music.volume = 0.5f;
            sfx = host.AddComponent<AudioSource>(); sfx.volume = 0.6f;
        }
        public static void PlayMusic(string key)
        {
            WantMusic = key;
            if (!DB.Music.TryGetValue(key, out var f) || curMusic == f) return;
            curMusic = f;
            if (Save.G != null && Save.G.mute) { music.Stop(); return; }
            var c = Resources.Load<AudioClip>("Snd/" + f); if (c == null) return;
            music.clip = c; music.loop = !(key.EndsWith("win") || key.EndsWith("lose")); music.Play();   // the victory / defeat jingles play once
        }
        public static void SetMute(bool m) { if (m) music.Stop(); else { curMusic = ""; PlayMusic(WantMusic); } }
        public static void Sfx(string key)
        {
            if (Save.G != null && Save.G.mute) return;
            if (!DB.Sfx.TryGetValue(key, out var f)) return;
            if (last.TryGetValue(key, out var t) && Time.unscaledTime - t < 0.09f) return;
            last[key] = Time.unscaledTime;
            var c = Resources.Load<AudioClip>("Snd/" + f); if (c != null) sfx.PlayOneShot(c);
        }
    }
}
