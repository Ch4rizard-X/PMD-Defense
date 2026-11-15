// Route Defense - all screens, built in code with UI Toolkit: title, starter, hub (routes / box / Pokédex / shop / bag),
// team select, battle HUD, pop-ups (route, Pokémon, items, move reminder, join request, pause, results) and toasts.
using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.UIElements;

namespace RouteDefense
{
    public static class UI
    {
        public static float LastInput;   // time of the last touch / drag / scroll
        public static VisualElement Root; static VisualElement screen, modal, toasts; static Action modalClose; static bool modalSticky;
        public static bool InBattle; public static BattleView View;
        static string hubTab = "routes"; static int dexGen = 1;
        static int routeSet, routeTier, routeSeed; static List<int> team = new List<int>();
        static readonly int[] STARTERS = { 1, 4, 7, 152, 155, 158, 252, 255, 258, 387, 390, 393, 495, 498, 501, 650, 653, 656, 722, 725, 728, 810, 813, 816, 906, 909, 912, 25, 133 };

        static readonly Color BG = Hex("#0b1736"), WIN = Hex("#1a3580"), EDGE = Hex("#8fb8ff"), ACC = Hex("#ffd84a"), DIM = Hex("#a9bce8"), GREEN = Hex("#2f7a2f"), GEDGE = Hex("#b9f5a5"), ALT = Hex("#22408a");
        public static Color Hex(string h) { ColorUtility.TryParseHtmlString(h, out var c); return c; }

        /* ---------- setup ---------- */
        public static void Init(GameObject host)
        {
            var go = new GameObject("UI"); go.SetActive(false); go.transform.SetParent(host.transform);
            var ps = ScriptableObject.CreateInstance<PanelSettings>();
            // size by screen density, like a web page: 1x on a PC monitor, ~2.5x on a phone
            ps.scaleMode = PanelScaleMode.ConstantPixelSize; ps.scale = UiScale(); Settings = ps;
            ps.themeStyleSheet = Resources.Load<ThemeStyleSheet>("Ui/RDTheme");
            var doc = go.AddComponent<UIDocument>(); doc.panelSettings = ps; go.SetActive(true);
            Root = doc.rootVisualElement;
            // any touch, drag or scroll counts as activity: Game.Update draws at full speed for a moment after it
            Root.RegisterCallback<PointerDownEvent>(_ => LastInput = Time.unscaledTime, TrickleDown.TrickleDown);
            Root.RegisterCallback<PointerMoveEvent>(_ => LastInput = Time.unscaledTime, TrickleDown.TrickleDown);
            Root.RegisterCallback<PointerUpEvent>(_ => LastInput = Time.unscaledTime, TrickleDown.TrickleDown);
            Root.RegisterCallback<WheelEvent>(_ => LastInput = Time.unscaledTime, TrickleDown.TrickleDown);
            var font = Resources.Load<Font>("Fonts/pmd");
            if (font != null) Root.style.unityFontDefinition = FontDefinition.FromFont(font);
            Root.style.color = Color.white; Root.style.fontSize = 16; Root.style.flexGrow = 1;
            screen = new VisualElement(); Full(screen); Root.Add(screen);
            modal = new VisualElement(); Full(modal); modal.style.backgroundColor = new Color(0, 0, 0, .6f); modal.style.alignItems = Align.Center; modal.style.justifyContent = Justify.Center;
            modal.style.display = DisplayStyle.None; Root.Add(modal);
            modal.RegisterCallback<PointerDownEvent>(e => { if (e.target == modal && !modalSticky) ClosePanel(); });
            toasts = new VisualElement(); toasts.style.position = Position.Absolute; toasts.style.top = 52; toasts.style.left = 0; toasts.style.right = 0; toasts.style.alignItems = Align.Center; toasts.pickingMode = PickingMode.Ignore;
            Root.Add(toasts);
            Battle.Toast = (m, id) => Toast(m, id); Battle.Finished = ShowResult; Battle.AskJoin = AskJoin; Battle.TeamChanged = BuildTeamBar;
        }
        public static PanelSettings Settings;
        public static readonly (string k, string n, float s)[] UISIZE = { ("s", "Small", 0.85f), ("m", "Medium", 1f), ("l", "Large", 1.2f), ("xl", "Extra large", 1.4f) };
        public static float UiScale()   // denser or taller screens get bigger menus, times the menu size option
        {
            float dpi = Screen.dpi > 0 ? Screen.dpi : 96, opt = 1; foreach (var u in UISIZE) if (Save.G != null && u.k == Save.G.ui) opt = u.s;
            // sized from the screen's real resolution, then shrunk by the render scale (Battery saver draws fewer pixels) so menus keep their size
            float r = Game.RenderScale(), nativeH = Screen.height / r;
            return Mathf.Clamp(Mathf.Max(dpi / 150f, nativeH / 720f), 1f, 3f) * opt * r;
        }
        static void Full(VisualElement e) { e.style.position = Position.Absolute; e.style.left = 0; e.style.top = 0; e.style.right = 0; e.style.bottom = 0; }

        /* ---------- small builders ---------- */
        static T Add<T>(VisualElement p, T e) where T : VisualElement { p.Add(e); return e; }
        static Label L(string t, int size = 16, Color? c = null) { var l = new Label(t); l.style.fontSize = size; l.style.color = c ?? Color.white; l.style.whiteSpace = WhiteSpace.Normal; l.style.marginTop = l.style.marginBottom = 2; return l; }
        static void Edge(VisualElement e, Color c, float w, float r)
        {
            e.style.borderTopWidth = e.style.borderBottomWidth = e.style.borderLeftWidth = e.style.borderRightWidth = w;
            e.style.borderTopColor = e.style.borderBottomColor = e.style.borderLeftColor = e.style.borderRightColor = c;
            e.style.borderTopLeftRadius = e.style.borderTopRightRadius = e.style.borderBottomLeftRadius = e.style.borderBottomRightRadius = r;
        }
        static void Pad(VisualElement e, float p) { e.style.paddingTop = e.style.paddingBottom = e.style.paddingLeft = e.style.paddingRight = p; }
        static Button Btn(string t, Action a, bool alt = false, bool small = false)
        {
            var b = new Button(() => { Gfx.Sfx("tap"); a(); }) { text = t };
            b.style.backgroundColor = alt ? ALT : GREEN; Edge(b, alt ? EDGE : GEDGE, 2, 6); b.style.color = Color.white;
            b.style.fontSize = small ? 14 : 16; Pad(b, small ? 4 : 8); b.style.paddingLeft = b.style.paddingRight = small ? 9 : 14;
            b.style.marginTop = b.style.marginBottom = b.style.marginLeft = b.style.marginRight = 4; return b;
        }
        static VisualElement Row(bool wrap = false) { var r = new VisualElement(); r.style.flexDirection = FlexDirection.Row; r.style.alignItems = Align.Center; if (wrap) r.style.flexWrap = Wrap.Wrap; return r; }
        static VisualElement Card(float w = 104)
        {
            var c = new VisualElement(); c.style.width = w; c.style.minHeight = 64; c.style.backgroundColor = WIN; Edge(c, EDGE, 2, 8); Pad(c, 6);
            c.style.alignItems = Align.Center; c.style.marginRight = c.style.marginBottom = 8; c.userData = w; return c;   // userData: the card's base width, for Grid's fitting
        }
        static VisualElement Grid()
        {
            var g = Row(true); g.style.alignItems = Align.FlexStart; g.style.alignSelf = Align.Stretch;
            // fill the whole row: as many columns as fit (a wide card may shrink to 85% to fit one more), then the cards stretch so no strip is left empty
            g.RegisterCallback<GeometryChangedEvent>(_ => FitGrid(g)); return g;
        }
        static void FitGrid(VisualElement g)
        {
            float W = g.layout.width; if (float.IsNaN(W) || W <= 0) return;
            float baseW = 0; foreach (var c in g.Children()) if (c.userData is float f) { baseW = f; break; }
            if (baseW <= 0) return;
            const float M = 8;   // a card's right margin
            // wide cards (maps) may shrink to 85% to fit one more column; narrow ones (Pokémon) never shrink, or long names break mid-word
            float minW = baseW >= 140 ? baseW * 0.85f : baseW;
            int cols = Mathf.Max(1, Mathf.FloorToInt((W + 0.5f) / (minW + M)));
            float cw = Mathf.Floor(W / cols - M);
            foreach (var c in g.Children()) if (c.userData is float) c.style.width = cw;
        }
        static Label TypeTag(int t)
        {
            var l = new Label(DB.TYPES[t]); l.style.fontSize = 11; l.style.backgroundColor = Hex(DB.TCOL[t]); l.style.color = Color.white; Pad(l, 1); l.style.paddingLeft = l.style.paddingRight = 5;
            l.style.marginRight = 2; l.style.borderTopLeftRadius = l.style.borderTopRightRadius = l.style.borderBottomLeftRadius = l.style.borderBottomRightRadius = 4; return l;
        }
        static VisualElement Types(int[] ts) { var r = Row(true); foreach (var t in ts) r.Add(TypeTag(t)); return r; }
        static Image Icon(int id, float size, bool silhouette = false)
        {
            var img = new Image { sprite = Gfx.MonIcon(id) ?? Gfx.MonFrame(id, "Idle", 0, 0), scaleMode = ScaleMode.ScaleToFit }; img.style.width = size; img.style.height = size;
            if (silhouette) img.tintColor = new Color(0, 0, 0, .45f); return img;
        }
        static Image ItemImg(int id, float size = 32)
        {
            var img = new Image { sprite = Gfx.ItemIcon(id), scaleMode = ScaleMode.ScaleToFit }; img.style.width = size; img.style.height = size; img.style.flexShrink = 0;
            if (img.sprite == null) img.style.display = DisplayStyle.None; return img;
        }
        /* names are always shown whole: the text shrinks just enough for the longest word to fit the card (two-word names may use two lines) */
        static Label OneLine(Label l, float w)
        {
            int longest = l.text.Split(' ').Max(x => x.Length); float fs = l.style.fontSize.value.value;
            l.style.fontSize = Mathf.Min(fs, w / Mathf.Max(1, longest * 0.62f)); l.style.unityTextAlign = TextAnchor.MiddleCenter; l.style.whiteSpace = WhiteSpace.Normal; return l;
        }
        static string Stars(int n) => new string('★', n) + new string('☆', 3 - n);
        static VisualElement Click(VisualElement e, Action a) { e.RegisterCallback<ClickEvent>(_ => { Gfx.Sfx("tap"); a(); }); return e; }
        static ScrollView Scroll()
        {
            var s = new ScrollView(ScrollViewMode.Vertical); s.style.flexGrow = 1; s.touchScrollBehavior = ScrollView.TouchScrollBehavior.Clamped;
            s.horizontalScrollerVisibility = ScrollerVisibility.Hidden;
            // a thin rounded scrollbar in the game's colours instead of Unity's grey one with arrow buttons
            var v = s.verticalScroller; v.lowButton.style.display = DisplayStyle.None; v.highButton.style.display = DisplayStyle.None;
            v.style.width = 8; v.style.minWidth = 8; v.style.marginLeft = 6; v.style.backgroundColor = Color.clear; Edge(v, Color.clear, 0, 4);
            var sl = v.slider; sl.style.marginTop = sl.style.marginBottom = sl.style.marginLeft = sl.style.marginRight = 0; sl.style.width = 8; sl.style.minWidth = 8;
            foreach (var n in new[] { "unity-tracker", "unity-dragger", "unity-dragger-border" })
            {
                var e = sl.Q(n); if (e == null) continue;
                e.style.left = 0; e.style.right = StyleKeyword.Auto; e.style.width = 8; e.style.marginLeft = e.style.marginRight = 0;
                e.style.backgroundColor = n == "unity-tracker" ? new Color(0, 0, 0, .28f) : n == "unity-dragger" ? new Color(EDGE.r, EDGE.g, EDGE.b, .75f) : Color.clear;
                Edge(e, Color.clear, 0, 4);
            }
            return s;
        }

        static Action<float> screenTick;   // per-frame animation of the current screen (title motes, walkers...)
        static VisualElement Show(int art = 0)
        {
            InBattle = false; screenTick = null; screen.Clear(); screen.style.backgroundColor = BG; Pad(screen, 12); screen.style.flexDirection = FlexDirection.Column;
            // the ROM artwork, darkened, behind the menus
            if (art > 0) { screen.style.backgroundImage = new StyleBackground(Gfx.Tex("Ui/art" + art)); screen.style.unityBackgroundImageTintColor = new Color(.13f, .17f, .3f); screen.style.backgroundSize = new BackgroundSize(BackgroundSizeType.Cover); }
            else screen.style.backgroundImage = StyleKeyword.None;
            screen.style.alignItems = Align.Stretch; screen.style.justifyContent = Justify.FlexStart; return screen;   // reset what other screens changed
        }
        public static VisualElement Panel(Action onClose = null, bool sticky = false)
        {
            modal.Clear(); modalClose = onClose; modalSticky = sticky;
            var w = new VisualElement(); w.style.backgroundColor = WIN; Edge(w, EDGE, 3, 10); Pad(w, 14); w.style.maxWidth = 640; w.style.width = new Length(94, LengthUnit.Percent); w.style.maxHeight = new Length(92, LengthUnit.Percent);
            var sv = Scroll(); w.Add(sv); modal.Add(w); modal.style.display = DisplayStyle.Flex;
            if (!sticky) { var x = Btn("X", ClosePanel, true, true); x.style.position = Position.Absolute; x.style.top = 8; x.style.right = 8; x.style.fontSize = 18; modal.Add(x); }   // always-visible way out
            return sv.contentContainer;
        }
        public static bool ModalOpen => modal.style.display == DisplayStyle.Flex;
        public static void ClosePanel() { var cb = modalClose; modalClose = null; modal.style.display = DisplayStyle.None; modal.Clear(); cb?.Invoke(); }
        public static void Toast(string msg, int id = 0)
        {
            var t = Row(); t.style.backgroundColor = WIN; Edge(t, ACC, 2, 8); Pad(t, 6); t.style.marginBottom = 6; t.pickingMode = PickingMode.Ignore;
            if (id != 0) t.Add(Icon(id, 28)); t.Add(L(msg)); toasts.Add(t);
            t.schedule.Execute(() => t.RemoveFromHierarchy()).StartingIn(3000);
        }

        /* ---------- title / starter ---------- */
        public static void ShowTitle()
        {
            var s = Show(); Pad(s, 0); s.style.alignItems = Align.Center; s.style.justifyContent = Justify.Center; Gfx.PlayMusic("_title");
            // the ROM's title-menu artworks, shown whole at a sharp whole-number scale in a framed window; a darkened copy fills the screen
            var arts = new[] { Gfx.Tex("Ui/art1"), Gfx.Tex("Ui/art2"), Gfx.Tex("Ui/art3") };
            var bg = new VisualElement(); Full(bg); bg.pickingMode = PickingMode.Ignore; s.Add(bg);
            var bgI = arts.Select(t => { var im = new Image { image = t, scaleMode = ScaleMode.ScaleAndCrop }; Full(im); im.tintColor = new Color(.42f, .47f, .62f); im.pickingMode = PickingMode.Ignore; bg.Add(im); return im; }).ToArray();
            var shade = new VisualElement(); Full(shade); shade.style.backgroundColor = new Color(.04f, .09f, .21f, .45f); shade.pickingMode = PickingMode.Ignore; s.Add(shade);
            var motes = new VisualElement(); Full(motes); motes.pickingMode = PickingMode.Ignore; s.Add(motes);
            var walk = new VisualElement(); walk.style.position = Position.Absolute; walk.style.left = 0; walk.style.right = 0; walk.style.bottom = 0; walk.pickingMode = PickingMode.Ignore; walk.style.overflow = Overflow.Hidden; s.Add(walk);
            var stack = new VisualElement(); stack.style.alignItems = Align.Center; s.Add(stack);
            var logo = L("ROUTE\nDEFENSE", 54, ACC); logo.style.unityTextAlign = TextAnchor.MiddleCenter; logo.style.unityTextOutlineColor = Hex("#0a1a4a"); logo.style.unityTextOutlineWidth = 2; stack.Add(logo);
            var frame = Add(stack, new VisualElement()); frame.style.backgroundColor = Hex("#c6d8f6"); Edge(frame, Hex("#0a1a4a"), 3, 14); Pad(frame, 6); frame.style.marginTop = frame.style.marginBottom = 8;
            var pic = Add(frame, new VisualElement()); pic.style.overflow = Overflow.Hidden; Edge(pic, Hex("#0a1a4a"), 2, 9); pic.style.backgroundColor = Color.black;
            var picI = arts.Select(t => { var im = new Image { image = t, scaleMode = ScaleMode.StretchToFill }; Full(im); pic.Add(im); return im; }).ToArray();
            stack.Add(L("wild Pokémon are coming down the path", 16, DIM));
            stack.Add(Btn(Save.G.box.Count > 0 ? "Continue" : "New Game", () => { if (Save.G.box.Count > 0) ShowHub(); else ShowStarter(); }));
            if (Save.G.box.Count > 0) stack.Add(L(Prog.OpenCount() + " maps open - best tier " + Prog.BestTier() + " - " + Save.G.box.Count + " Pokémon - Pokédex " + Save.G.own.Count, 13, DIM));
            // floating light motes (simple shapes, no art)
            var P = new List<(VisualElement e, float x, float y, float r, float v, float ph)>();
            for (int k = 0; k < 40; k++) { var m = new VisualElement(); m.pickingMode = PickingMode.Ignore; m.style.position = Position.Absolute; motes.Add(m); P.Add((m, UnityEngine.Random.value, 1 + UnityEngine.Random.value, 1 + UnityEngine.Random.value * 2.5f, 10 + UnityEngine.Random.value * 25, UnityEngine.Random.value * 6.3f)); }
            // Pokémon from the first three generations wander along the bottom
            var pool = DB.Mons.Where(m => m.anim && m.g <= 3 && DB.Anim[m.id].ContainsKey("Walk")).ToList();
            var W = new List<(VisualElement e, Image sh, Image im, int id, float x, float v)>(); float T = 0;
            screenTick = dt =>
            {
                T += dt; float pw = Root.layout.width, ph = Root.layout.height; if (pw <= 0) return;
                int k = Mathf.Max(1, Mathf.FloorToInt(Mathf.Min(pw * 0.82f / 240, (ph - 330 * Mathf.Min(1.6f, ph / 720)) / 160)));   // biggest whole-number scale that leaves room for the logo and button
                pic.style.width = 240 * k; pic.style.height = 160 * k;
                float cyc = T / 6f; int ai = Mathf.FloorToInt(cyc) % 3; float fr = cyc - Mathf.Floor(cyc);   // the three artworks take turns, with a soft crossfade
                for (int a = 0; a < 3; a++) { float o = a == ai ? 1 : a == (ai + 1) % 3 && fr > 0.9f ? (fr - 0.9f) / 0.1f : 0; picI[a].style.opacity = o; bgI[a].style.opacity = o; picI[a].style.scale = new Scale(Vector3.one * (a == ai ? 1.06f - 0.06f * Mathf.Clamp01(fr / 0.4f) : 1.06f)); }
                logo.style.translate = new Translate(0, -2.5f + 2.5f * Mathf.Sin(T * 2.2f));
                for (int n = 0; n < P.Count; n++)
                {
                    var p = P[n]; float y = p.y - p.v * dt / Mathf.Max(1, ph); if (y < -0.02f) { y = 1.02f; p.x = UnityEngine.Random.value; } P[n] = (p.e, p.x, y, p.r, p.v, p.ph);
                    float a2 = 0.25f + 0.25f * Mathf.Sin(T * 2 + p.ph); p.e.style.left = p.x * pw + Mathf.Sin(T + p.ph) * 12; p.e.style.top = y * ph; p.e.style.width = p.e.style.height = p.r * 2;
                    p.e.style.borderTopLeftRadius = p.e.style.borderTopRightRadius = p.e.style.borderBottomLeftRadius = p.e.style.borderBottomRightRadius = p.r; p.e.style.backgroundColor = new Color(1, .94f, .67f, a2);
                }
                int wk = Mathf.Max(2, Mathf.RoundToInt(ph / 330)); walk.style.height = 60 * wk; float vw = pw / wk;
                if (W.Count < 4 && UnityEngine.Random.value < dt * 0.6f && pool.Count > 0)
                {
                    var m = pool[UnityEngine.Random.Range(0, pool.Count)]; bool right = UnityEngine.Random.value < 0.5f;
                    var e = new VisualElement(); e.style.position = Position.Absolute; e.pickingMode = PickingMode.Ignore; walk.Add(e);
                    var sh = new Image { sprite = Gfx.Shadow, scaleMode = ScaleMode.StretchToFill }; sh.tintColor = new Color(0, 0, 0, .28f); sh.style.position = Position.Absolute; e.Add(sh);
                    var im = new Image { scaleMode = ScaleMode.StretchToFill }; im.style.position = Position.Absolute; e.Add(im);
                    W.Add((e, sh, im, m.id, right ? -30 : vw + 30, (right ? 1 : -1) * (14 + m.b[5] * 0.12f)));
                }
                for (int n = W.Count - 1; n >= 0; n--)
                {
                    var w = W[n]; float x = w.x + w.v * dt; W[n] = (w.e, w.sh, w.im, w.id, x, w.v);
                    if (x < -60 || x > vw + 60) { w.e.RemoveFromHierarchy(); W.RemoveAt(n); continue; }
                    var a = Gfx.Meta(w.id, "Walk"); if (a == null) continue; int f = Gfx.FrameAt(a.d, a.Total, T, true), row = w.v > 0 ? 2 : 6;
                    float[] gp = a.sh != null ? a.sh[Mathf.Min(a.r > 1 ? row : 0, a.sh.Length - 1)] : new float[] { a.fw / 2f, a.fh / 2f + 4 };
                    w.im.sprite = Gfx.MonFrame(w.id, "Walk", f, row); w.im.style.width = a.fw * wk; w.im.style.height = a.fh * wk; w.im.style.left = (x - gp[0]) * wk; w.im.style.top = (52 - gp[1]) * wk;
                    w.sh.style.width = 16 * wk; w.sh.style.height = 7 * wk; w.sh.style.left = (x - 8) * wk; w.sh.style.top = (52 - 3.5f) * wk;
                }
            };
        }
        static void ShowStarter()
        {
            var s = Show(3); s.Add(L("Choose your first partner", 22)); var sv = Scroll(); s.Add(sv); var g = Add(sv, Grid());
            foreach (int id in STARTERS)
            {
                if (!DB.SP.TryGetValue(id, out var sp) || !sp.anim) continue;
                var c = Card(); c.Add(Icon(id, 56)); c.Add(OneLine(L(sp.n, 15), 88)); c.Add(Types(sp.t));
                g.Add(Click(c, () =>
                {
                    var p = Panel(); p.Add(L(sp.n, 20)); p.Add(L("Start your journey with " + sp.n + "?"));
                    var r = Add(p, Row());
                    r.Add(Btn("Yes", () => { var e = Save.MakeMon(id, 5); Save.G.box.Add(e); Save.G.team = new List<int> { e.u }; Save.Write(); ClosePanel(); Gfx.Sfx("join"); ShowHub(); }));
                    r.Add(Btn("No", ClosePanel, true));
                }));
            }
        }

        /* ---------- hub ---------- */
        public static void ShowHub(string tab = null)
        {
            if (tab != null) hubTab = tab; var s = Show(1); Gfx.PlayMusic("_hub"); var G = Save.G;
            var top = Add(s, Row(true));
            top.Add(UiImg("coin", 20)); top.Add(L(" " + G.money.ToString("N0"), 16, ACC)); top.Add(Gap()); top.Add(UiImg("badge", 20)); top.Add(L(" Rescue Points " + G.rp)); top.Add(Gap());
            top.Add(L("Maps " + Prog.OpenCount() + "/" + DB.TS.Count)); top.Add(Gap()); top.Add(L("Best tier " + Prog.BestTier())); top.Add(Gap());
            top.Add(L("Pokédex " + G.own.Count + "/" + DB.Mons.Count(m => m.anim))); top.Add(Gap());
            top.Add(Btn("Options", () => OptionsPanel(() => ShowHub()), true, true));
            var tabs = Add(s, Row(true));
            foreach (var (k, n) in new[] { ("routes", "Routes"), ("box", "Box"), ("dex", "Pokédex"), ("rescue", "Rescue"), ("shop", "Shop"), ("bag", "Bag") })
            {
                var b = Btn(n, () => ShowHub(k), hubTab != k, true); if (hubTab == k) { b.style.backgroundColor = Hex("#b07c1c"); Edge(b, Hex("#ffe39a"), 2, 6); }
                tabs.Add(b);
            }
            var sv = Scroll(); s.Add(sv); var body = sv.contentContainer;
            switch (hubTab) { case "routes": HubRoutes(body); break; case "box": HubBox(body); break; case "dex": HubDex(body); break; case "shop": HubShop(body); break; case "rescue": HubRescue(body); break; default: HubBag(body); break; }
        }
        static Image UiImg(string k, float size) { var t = Gfx.Tex("Ui/" + k); var im = new Image { image = t, scaleMode = ScaleMode.ScaleToFit }; im.style.width = im.style.height = size; im.style.flexShrink = 0; return im; }
        static void OptionsPanel(Action after)
        {
            var p = Panel(after); var G = Save.G; p.Add(L("Options", 20));
            var fb = Box(); var fr = Add(fb, Row(true)); fr.Add(L("60 fps  ")); fr.Add(Btn(G.smooth ? "On" : "Off (30 fps)", () => { G.smooth = !G.smooth; Application.targetFrameRate = G.smooth ? 60 : 30; Save.Write(); OptionsPanel(after); }, !G.smooth, true)); fb.Add(L("Smooth motion; 30 fps is a bit cooler but choppier", 12, DIM)); p.Add(fb);
            var rb = Box(); var rr = Add(rb, Row(true)); rr.Add(L("Lower resolution  ")); rr.Add(Btn(G.lowres ? "On" : "Off", () => { G.lowres = !G.lowres; Game.ApplyResolution(); Save.Write(); OptionsPanel(after); }, !G.lowres, true)); rb.Add(L("Draws fewer pixels so the phone stays much cooler; text a little softer", 12, DIM)); p.Add(rb);
            var sb = Box(); var sr = Add(sb, Row(true)); sr.Add(L("Sound  ")); sr.Add(Btn(G.mute ? "Off" : "On", () => { G.mute = !G.mute; Gfx.SetMute(G.mute); Save.Write(); OptionsPanel(after); }, G.mute, true)); p.Add(sb);
            var mb = Box(); mb.Add(L("Menu size")); mb.Add(L("Buttons, text and panels (the map is not affected)", 12, DIM)); var mr = Add(mb, Row(true));
            foreach (var u in UISIZE) { var uk = u.k; mr.Add(Btn(u.n, () => { G.ui = uk; if (Settings != null) Settings.scale = UiScale(); Save.Write(); OptionsPanel(after); }, G.ui != uk, true)); }
            p.Add(mb);
            var cb = Box(); cb.Add(L("Balance settings: " + Cfg.Status, 13, DIM)); cb.Add(L("Balance numbers update by themselves when online; new features come with a new build", 12, DIM)); p.Add(cb);
            p.Add(Btn("Close", ClosePanel, true));
        }
        static VisualElement Gap(float w = 14) { var v = new VisualElement(); v.style.width = w; return v; }
        static void HubRoutes(VisualElement body)
        {
            body.Add(L("Every map is randomly made when you start it. Each map has its own tiers. One win opens the next map of its group; a high tier on any map opens the next group. Later groups are harder by nature, and pay more.", 13, DIM));
            for (int gi = 0; gi < 4; gi++)
            {
                var GR = Prog.GROUPS[gi]; var gh = L(GR.name + (gi > 0 ? "  -  opens at tier " + GR.gate + " on any " + Prog.GROUPS[gi - 1].name + " map" : ""), 17, Prog.COLS[gi]); gh.style.marginTop = 8; body.Add(gh);
                var g = Add(body, Grid());
                for (int i = 0; i < DB.TS.Count; i++)
                {
                    if (Prog.MapGroup(i) != gi) continue;
                    int idx = i; var S = DB.TS[i]; bool open = Prog.MapOpen(i);
                    var c = Card(150); Edge(c, Prog.COLS[gi], 2, 8);
                    var sw = new Image { image = MapGen.Swatch(i), scaleMode = ScaleMode.StretchToFill }; sw.style.alignSelf = Align.Stretch; sw.style.height = 136 / 3f; sw.RegisterCallback<GeometryChangedEvent>(_ => { if (sw.layout.width > 0) sw.style.height = sw.layout.width / 3f; }); Edge(sw, new Color(0, 0, 0, .5f), 1, 4); c.Add(sw);
                    c.Add(L(S.name, 15)); c.Add(L(S.game == "E" ? "Explorers of Sky" : "Rescue Team", 12, DIM)); c.Add(Types(S.types));
                    if (!open) { c.Add(L(i > 0 && Prog.MapGroup(i - 1) == gi ? "Win the map before to open" : "Opens at tier " + GR.gate + " on any " + Prog.GROUPS[Math.Max(0, gi - 1)].name + " map", 12, Hex("#ffb0b0"))); c.style.opacity = .45f; }
                    else { int ct = Save.G.mtDone.Contains(i) ? Prog.MAXTIER : Prog.MapTier(i) - 1; c.Add(L(ct > 0 ? "Tier " + ct + " cleared" : "New", 12, ct > 0 ? ACC : Hex("#99ff99"))); Click(c, () => RoutePanel(idx)); }
                    g.Add(c);
                }
            }
        }
        static void RoutePanel(int i, bool keep = false)
        {
            var S = DB.TS[i];
            if (!keep) { routeSet = i; routeTier = Math.Max(1, Prog.MapTier(i)); routeSeed = UnityEngine.Random.Range(0, 1000000000); }
            int gi = Prog.MapGroup(i); var GR = Prog.GROUPS[gi];
            var p = Panel(); var hr0 = Add(p, Row(true)); hr0.Add(L(S.name + "  ", 20)); hr0.Add(L(GR.name, 15, Prog.COLS[gi])); p.Add(Types(S.types));
            if (gi > 0) p.Add(L($"{GR.name} map: harder by nature - every tier here fights like a higher tier on earlier maps (levels, species and traits), with shorter paths, more entrances and water and {Mathf.RoundToInt((GR.count - 1) * 100)}% more per wave. Rewards x{GR.pay}.", 13, DIM));
            var pm = MapGen.Gen(i, false, routeSeed, null, PlayAspect(), routeTier);
            var prev = new Image { image = pm.tex, scaleMode = ScaleMode.ScaleToFit }; prev.style.width = new Length(100, LengthUnit.Percent); prev.style.height = 260; Edge(prev, EDGE, 2, 6);
            var over = new VisualElement(); Full(over); over.pickingMode = PickingMode.Ignore; prev.Add(over);   // path line drawn on a layer above the map
            over.generateVisualContent += ctx =>
            {
                var r = over.contentRect; float sc = Mathf.Min(r.width / pm.tex.width, r.height / pm.tex.height), ox = (r.width - pm.tex.width * sc) / 2, oy = (r.height - pm.tex.height * sc) / 2;
                var pt = ctx.painter2D; pt.strokeColor = new Color(.47f, .12f, .08f, .6f); pt.lineWidth = 3;
                foreach (var l in pm.lines) { pt.BeginPath(); for (int k = 0; k < l.Count; k++) { var v = new Vector2(ox + l[k].x * sc, oy + l[k].y * sc); if (k == 0) pt.MoveTo(v); else pt.LineTo(v); } pt.Stroke(); }
            };
            prev.RegisterCallback<GeometryChangedEvent>(_ => over.MarkDirtyRepaint());
            p.Add(prev);
            float th = Prog.Threat(i, routeTier); var lr = Battle.LvRange(th); int lvA = Math.Min(98, lr[0]), lvB = Math.Min(100, lr[1]), stn = Prog.Stars(i, routeTier);
            var tr = Add(p, Row());   // both arrows stay on this row; the text between them wraps instead
            var dn = Add(tr, Btn("◀", () => { if (routeTier > 1) { routeTier--; RoutePanel(i, true); } }, true, true)); dn.style.flexShrink = 0;
            var tt = Add(tr, L($"Tier {routeTier}  {Stars(stn)}  - wild Lv {lvA}-{lvB} - {Battle.WaveCount(routeTier)} waves", 16)); tt.style.flexGrow = 1; tt.style.flexShrink = 1; tt.style.unityTextAlign = TextAnchor.MiddleCenter;
            var up = Add(tr, Btn("▶", () => { if (routeTier < Prog.MapTier(i)) { routeTier++; RoutePanel(i, true); } }, true, true)); up.style.flexShrink = 0;
            var br = Add(p, Row(true));   // up top, so they're reachable without scrolling past the spawn list
            var nlb = Add(br, Btn("New layout", () => { routeSeed = UnityEngine.Random.Range(0, 1000000000); RoutePanel(i, true); }, true)); nlb.style.flexGrow = 1;
            var gob = Add(br, Btn("Choose team ▶", () => { ClosePanel(); ShowTeam(); })); gob.style.flexGrow = 1;
            var trs = Battle.TRAITS.Where(x => x.tier <= th).Select(x => x.what).ToList(); if (trs.Count > 0) p.Add(L("Wild traits here: " + string.Join(" · ", trs), 13, DIM));
            var gates = new List<string>();
            if (i + 1 < DB.TS.Count && Prog.MapGroup(i + 1) == gi && !Prog.MapOpen(i + 1)) gates.Add("Win here to open the next map.");
            if (gi < 3 && !Prog.MapOpen(Prog.GroupStart(gi + 1))) gates.Add($"Clear tier {Prog.Gate(gi + 1)} on any {GR.name} map to open the {Prog.GROUPS[gi + 1].name} maps.");
            if (gates.Count > 0) p.Add(L(string.Join("\n", gates), 14, ACC));
            SpawnList(p, i, routeTier);
            p.Add(L("Stars: ★ win · ★★ 50+ lives left · ★★★ no lives lost. Each new star gives bonus Rescue Points.", 13, DIM));
            p.Add(L(pm.kind == "split" ? "The path splits in two and joins again." : pm.kind == "two" ? "Two entrances: a second path merges in." : pm.kind == "three" ? "Three entrances: paths from the top and bottom merge in." : "One path.", 13, DIM));
        }
        /* the wild Pokémon this map and tier can send; ones you haven't seen yet are dark silhouettes */
        static void SpawnList(VisualElement p, int i, int tier)
        {
            var SI = Battle.SpawnInfo(i, tier);
            void sec(string title, List<Species> list, string note)
            {
                if (list.Count == 0) return; p.Add(L(title + (note.Length > 0 ? " - " + note : ""), 13, ACC)); var g = Add(p, Grid()); g.style.justifyContent = Justify.Center;
                foreach (var m in list.OrderBy(x => x.bst))
                {
                    bool seen = Save.G.Seen(m.id); var c = new VisualElement(); c.style.width = 66; c.style.alignItems = Align.Center; c.style.backgroundColor = new Color(0, 0, 0, .2f); Edge(c, new Color(1, 1, 1, .11f), 1, 6); Pad(c, 2); c.style.marginRight = c.style.marginBottom = 4;
                    c.Add(Icon(m.id, 32, !seen)); c.Add(OneLine(L(seen ? m.n : "???", 10, seen ? Hex("#cfdcff") : Hex("#8090b8")), 60)); g.Add(c);
                }
            }
            p.Add(L("Wild Pokémon here - " + SI.pool.Count(m => Save.G.Seen(m.id)) + "/" + SI.pool.Count + " seen", 15));
            var rnote = new[] { "", "60% as often", "35% as often", "15% as often" };
            for (int k = 0; k < 4; k++) { int kk = k; sec(Battle.RARITY[k], SI.pool.Where(m => SI.rar[m.id] == kk).ToList(), rnote[k]); }
            sec("Heavy waves (every 5th)", SI.heavy, "");
            sec("Possible bosses", SI.bosses, SI.legs.Count > 0 ? "or a legendary, half the time" : "");
            sec("Legendary bosses", SI.legs, "");
        }
        static VisualElement MonCard(Mon e, Action onClick = null)
        {
            var c = Card(); c.Add(Icon(e.id, 56)); c.Add(OneLine(L(DB.SP[e.id].n, 15), 88));
            string extra = (DB.EvoOptions(e).Any(o => o.ok) ? "  EVOLVE" : "") + (e.pend.Count > 0 ? "  NEW MOVE" : "");
            c.Add(L("Lv " + e.lv + extra, 13, extra.Length > 0 ? ACC : DIM));
            var qk = L(string.Join(" / ", Battle.Quirks(e.id).Select(q => q[0])), 10, Hex("#ffe39a")); qk.style.unityTextAlign = TextAnchor.MiddleCenter; c.Add(qk);   // type quirks
            if (Battle.SeesWhy(e) != null) c.Add(SeesTag());
            if (onClick != null) Click(c, onClick); return c;
        }
        /* small badge for Pokémon that can see hidden Ghost types */
        static Label SeesTag() { var l = new Label("sees hidden"); l.style.fontSize = 10; l.style.color = Hex("#1a2a55"); l.style.backgroundColor = ACC; Pad(l, 1); l.style.paddingLeft = l.style.paddingRight = 4; l.style.borderTopLeftRadius = l.style.borderTopRightRadius = l.style.borderBottomLeftRadius = l.style.borderBottomRightRadius = 4; return l; }
        static void HubBox(VisualElement body)
        {
            body.Add(L(Save.G.box.Count + " Pokémon. Tap one to see its moves and evolutions.", 13, DIM));
            var g = Add(body, Grid());
            foreach (var e in Save.G.box.OrderByDescending(x => x.lv)) g.Add(MonCard(e, () => MonPanel(e, () => ShowHub())));
        }
        static VisualElement MoveRow(int m)
        {
            var mv = DB.Mv(m); var r = new VisualElement(); r.style.backgroundColor = new Color(0, 0, 0, .2f); Edge(r, new Color(1, 1, 1, .13f), 1, 6); Pad(r, 6); r.style.marginTop = r.style.marginBottom = 3;
            var h = Add(r, Row()); h.Add(TypeTag(mv.t)); h.Add(L(" " + mv.n)); r.Add(L(DB.MoveDesc(m), 12, DIM)); return r;
        }
        public static void MonPanel(Mon e, Action after)
        {
            var p = Panel(after); var s = DB.SP[e.id]; var st = DB.MonStats(e);
            int nx = e.lv < DB.MAXLV ? DB.XpFor(s.gr, e.lv + 1) : e.xp, cur = DB.XpFor(s.gr, e.lv);
            var head = Add(p, Row()); head.Add(Icon(e.id, 64)); var hc = Add(head, new VisualElement()); hc.style.flexShrink = 1;
            hc.Add(L(s.n + "  Lv " + e.lv, 20)); hc.Add(Types(s.t));
            var xb = Add(hc, new VisualElement()); xb.style.height = 6; xb.style.width = 200; xb.style.backgroundColor = new Color(0, 0, 0, .4f);
            var xf = Add(xb, new VisualElement()); xf.style.height = 6; xf.style.backgroundColor = Hex("#55ccff"); xf.style.width = new Length(e.lv >= DB.MAXLV ? 100 : Mathf.Clamp01((e.xp - cur) / (float)Mathf.Max(1, nx - cur)) * 100, LengthUnit.Percent);
            hc.Add(L($"HP {st[0]} - Atk {st[1]} - Def {st[2]} - SpA {st[3]} - SpD {st[4]} - Spe {st[5]}", 13, DIM));
            foreach (var q in Battle.Quirks(e.id)) { var qr = Add(hc, Row(true)); var tg = TypeTag(s.t[Array.FindIndex(s.t, x => Battle.TQ.TryGetValue(x, out var v2) && v2 == q)]); tg.text = q[0]; qr.Add(tg); qr.Add(L(" " + q[1], 13)); }
            hc.Add(L("Placing costs $" + DB.PlaceCost(e) + " battle cash", 13, DIM));
            var iv = DB.IvsOf(e); var nb = Box(); nb.Add(L("Nature: " + DB.NatLabel(e.nat)));
            if (e.mint != 0) { var mt = DB.Tools.Values.FirstOrDefault(x => x.nat == e.mint); nb.Add(L("Stats changed by " + (mt != null ? mt.n : "a Mint") + ": " + DB.NatLabel(e.mint), 12, Hex("#99ff99"))); }
            nb.Add(L("IVs " + string.Join(" / ", iv) + "  (total " + iv.Sum() + "/186)", 12, DIM));
            var sw = Battle.SeesWhy(e); nb.Add(L(sw != null ? "Sees hidden Pokémon: reveals hidden Ghost types in its range (" + sw + ")" : "Can't see hidden Pokémon: hidden Ghost types need a Psychic or Ghost type, Foresight, Odor Sleuth, Miracle Eye, Keen Eye or Frisk nearby", 12, sw != null ? Hex("#99ff99") : Hex("#aaaaaa")));
            if (!InBattle && Save.G.tools.Count > 0) nb.Add(Btn("Use a Mint or Bottle Cap", () => ToolPanel(e, () => MonPanel(e, after)), false, true));
            p.Add(nb);
            if (DB.Abil.TryGetValue(e.ab, out var A))
            {
                var r = Box(); r.Add(L("Ability: " + A.n + (s.ab.Any(x => x[0] == e.ab && x[1] == 1) ? " (hidden ability)" : ""))); r.Add(L(A.d, 12, DIM));
                r.Add(L(DB.AB_TD.TryGetValue(A.k, out var td) ? "In Route Defense: " + td : "No effect in Route Defense", 12, DB.AB_TD.ContainsKey(A.k) ? Hex("#99ff99") : Hex("#aaaaaa"))); p.Add(r);
            }
            var hr = Box(); var hrow = Add(hr, Row(true));
            if (e.it != 0 && DB.Held.TryGetValue(e.it, out var H))
            {
                hrow.Add(ItemImg(e.it, 28)); hrow.Add(L("Holding: " + H.n)); hrow.Add(Btn("Take", () => { Save.G.Add(Save.G.held, e.it, 1); e.it = 0; Save.Write(); MonPanel(e, after); }, true, true)); hr.Add(L(DB.HELD_TD.TryGetValue(H.k, out var hd) ? hd : "", 12, DIM));
            }
            else hrow.Add(L("Holding nothing"));
            if (Save.G.held.Count > 0) hrow.Add(Btn(e.it != 0 ? "Swap" : "Give item", () => GivePanel(e, () => MonPanel(e, after)), false, true));
            p.Add(hr);
            p.Add(L("Moves", 17));
            for (int k = 0; k < e.mv.Count; k++)
            {
                int idx = k; var r = MoveRow(e.mv[k]);
                if (e.pend.Count > 0) r.Add(Btn("Replace", () => { e.mv[idx] = e.pend[0]; e.pend.RemoveAt(0); Save.Write(); MonPanel(e, after); }, false, true));
                p.Add(r);
            }
            if (e.pend.Count > 0)
            {
                var r = MoveRow(e.pend[0]); r.Insert(0, L("New move - tap Replace on a move above, or:", 13, Hex("#77ccff")));
                r.Add(Btn("Don't learn", () => { e.pend.RemoveAt(0); Save.Write(); MonPanel(e, after); }, true, true)); p.Add(r);
            }
            int skI = e.mv.IndexOf(Battle.MID("Sketch")); if (skI >= 0 && !InBattle) p.Add(Btn("Sketch a move", () => SketchPanel(e, skI, () => MonPanel(e, after)), false, true));
            var rem = DB.LearnedBy(e.id, e.lv).Where(m => !e.mv.Contains(m) && (DB.MoveUse(m) != null || Battle.IsSkill(m))).ToList();
            if (rem.Count > 0) p.Add(Btn("Move Reminder (" + rem.Count + ")", () => RemindPanel(e, () => MonPanel(e, after)), true, true));
            var ev = DB.EvoOptions(e);
            if (ev.Count > 0)
            {
                p.Add(L("Evolution", 17));
                foreach (var o in ev)
                {
                    var r = Row(true); r.Add(Icon(o.to, 32)); if (o.item != 0) r.Add(ItemImg(o.item, 24)); r.Add(L(" " + DB.SP[o.to].n + " (" + o.why + ") "));
                    if (o.ok) r.Add(Btn("Evolve", () => { string from = s.n; Save.Evolve(e, o.to, o.item); Gfx.Sfx("evo"); Toast(from + " evolved into " + DB.SP[o.to].n + "!", o.to); Save.Write(); MonPanel(e, after); }, false, true));
                    p.Add(r);
                }
            }
            var br = Add(p, Row(true));
            br.Add(Btn("Close", ClosePanel, true));
            if (!InBattle && Save.G.box.Count > 1)
                br.Add(Btn("Release", () =>
                {
                    var q = Panel(() => ShowHub("box")); q.Add(L("Release " + s.n + "?", 20));
                    q.Add(L("Lv " + e.lv + ". It will leave your box for good" + (e.it != 0 ? " (its " + DB.Held[e.it].n + " goes back to your bag)" : "") + "."));
                    var rr = Add(q, Row());
                    rr.Add(Btn("Release", () => { if (e.it != 0) Save.G.Add(Save.G.held, e.it, 1); Save.G.box.Remove(e); Save.G.team.Remove(e.u); Save.Write(); ClosePanel(); }));
                    rr.Add(Btn("Keep", () => MonPanel(e, after), true));
                }, true, true));
        }
        /* Sketch: swap it for any move a Pokémon you've seen learns by level */
        static void SketchPanel(Mon e, int slot, Action back)
        {
            var p = Panel(back); var ids = new HashSet<int>();
            foreach (int id in Save.G.seen) if (DB.SP.TryGetValue(id, out var sp)) foreach (var l in sp.ls) if ((DB.MoveUse(l[1]) != null || Battle.IsSkill(l[1])) && !e.mv.Contains(l[1])) ids.Add(l[1]);
            var list = ids.Where(DB.Moves.ContainsKey).OrderBy(m => DB.Mv(m).n).ToList();
            p.Add(L("Sketch", 20)); p.Add(L(DB.SP[e.id].n + " can copy one of " + list.Count + " moves from the Pokémon you've seen. Sketch is replaced by it.", 13, DIM));
            var f = new TextField(); f.style.marginTop = f.style.marginBottom = 4; p.Add(f); var wrap = Add(p, new VisualElement());
            void Draw() { wrap.Clear(); string q = (f.value ?? "").ToLower(); foreach (int m in list.Where(x => DB.Mv(x).n.ToLower().Contains(q)).Take(80)) { int mm = m; wrap.Add(Click(MoveRow(m), () => { e.mv[slot] = mm; Save.Write(); Toast(DB.SP[e.id].n + " sketched " + DB.Mv(mm).n + "!"); back(); })); } }
            f.RegisterValueChangedCallback(_ => Draw()); Draw();
        }
        /* Mints change how the nature affects stats; Bottle Caps raise IVs to 31 (like Hyper Training). Only outside battle. */
        static void ToolPanel(Mon e, Action back)
        {
            var p = Panel(back); p.Add(L("Mints & Bottle Caps", 20)); var iv = DB.IvsOf(e);
            foreach (var pr in Save.G.tools.ToList())
            {
                var T = DB.Tools[pr.k]; var r = Box(); var hr2 = Add(r, Row()); hr2.Add(ItemImg(pr.k, 28)); hr2.Add(L(" " + T.n + " x" + pr.v));
                if (T.kind == "mint")
                {
                    bool same = DB.NatOf(e) == T.nat; r.Add(L("Stats change as if its nature were " + DB.NatLabel(T.nat), 12, DIM));
                    if (same) r.Add(L("Already works like this", 12, Hex("#aaaaaa")));
                    else Click(r, () => { Save.G.Add(Save.G.tools, pr.k, -1); e.mint = T.nat == e.nat ? 0 : T.nat; Save.Write(); Gfx.Sfx("lvl"); Toast(DB.SP[e.id].n + "'s stats changed: " + DB.NatLabel(T.nat), e.id); ClosePanel(); });
                }
                else if (T.kind == "bottle-cap")
                {
                    r.Add(L("Pick a stat to raise to 31:", 12, DIM)); var sr = Add(r, Row(true));
                    for (int k = 0; k < 6; k++) { int ki = k; var b = Btn(DB.STATN[k] + " " + iv[k], () => { if (iv[ki] >= 31) return; Save.G.Add(Save.G.tools, pr.k, -1); e.ht[ki] = 1; Save.Write(); Gfx.Sfx("lvl"); Toast(DB.SP[e.id].n + "'s " + DB.STATN[ki] + " IV is 31 now", e.id); ClosePanel(); }, iv[k] >= 31, true); sr.Add(b); }
                }
                else
                {
                    r.Add(L("Raises every stat to IV 31", 12, DIM));
                    if (iv.All(v => v >= 31)) r.Add(L("Already all 31", 12, Hex("#aaaaaa")));
                    else Click(r, () => { Save.G.Add(Save.G.tools, pr.k, -1); e.ht = new[] { 1, 1, 1, 1, 1, 1 }; Save.Write(); Gfx.Sfx("lvl"); Toast(DB.SP[e.id].n + "'s IVs are all 31 now", e.id); ClosePanel(); });
                }
                p.Add(r);
            }
            p.Add(Btn("Back", ClosePanel, true));
        }
        static VisualElement Box() { var r = new VisualElement(); r.style.backgroundColor = new Color(0, 0, 0, .2f); Edge(r, new Color(1, 1, 1, .13f), 1, 6); Pad(r, 6); r.style.marginTop = r.style.marginBottom = 4; return r; }
        static void GivePanel(Mon e, Action back)
        {
            var p = Panel(back); p.Add(L("Give an item", 20));
            foreach (var pr in Save.G.held.ToList())
            {
                var H = DB.Held[pr.k]; var r = Box(); var hr2 = Add(r, Row()); hr2.Add(ItemImg(pr.k, 28)); hr2.Add(L(" " + H.n + " x" + pr.v)); r.Add(L(DB.HELD_TD.TryGetValue(H.k, out var d) ? d : "", 12, DIM));
                p.Add(Click(r, () => { if (e.it != 0) Save.G.Add(Save.G.held, e.it, 1); Save.G.Add(Save.G.held, pr.k, -1); e.it = pr.k; Save.Write(); ClosePanel(); }));
            }
            p.Add(Btn("Back", ClosePanel, true));
        }
        static void RemindPanel(Mon e, Action back, int pickNew = 0)
        {
            var p = Panel(back); p.Add(L("Move Reminder", 20));
            p.Add(L(pickNew == 0 ? "Pick a move " + DB.SP[e.id].n + " learned before." : "Pick a move to forget for " + DB.Mv(pickNew).n + ".", 13, DIM));
            var list = pickNew == 0 ? DB.LearnedBy(e.id, e.lv).Where(m => !e.mv.Contains(m) && DB.MoveUse(m) != null).OrderByDescending(m => DB.MoveValue(m, e.id)).ToList() : e.mv.ToList();
            foreach (int m in list)
                p.Add(Click(MoveRow(m), () =>
                {
                    if (pickNew == 0) { if (e.mv.Count < 4) { e.mv.Add(m); Save.Write(); ClosePanel(); } else RemindPanel(e, back, m); }
                    else { e.mv[e.mv.IndexOf(m)] = pickNew; Save.Write(); Gfx.Sfx("lvl"); ClosePanel(); }
                }));
            p.Add(Btn("Back", ClosePanel, true));
        }
        /* where a species turns up: same rules the wave builder uses */
        static List<(string, int, bool)> Habitat(int id)
        {
            var m = DB.SP[id]; var o = new List<(string, int, bool)>();
            for (int i = 0; i < DB.TS.Count; i++)
            {
                var S = DB.TS[i]; if (!m.t.Any(x => S.types.Contains(x))) continue; int T = 0;
                int g = Prog.MapGroup(i) * 25;   // real tiers 1-20; the map's group adds to the tier it fights like
                if (m.lg > 0) { for (int t = 1; t <= Prog.MAXTIER; t++) { float h = Prog.Threat(i, t); if (h >= 5 && m.bst <= 480 + h * 25 && (m.lg == 1 || h >= 10)) { T = t; break; } } }
                else for (int t = 1; t <= Prog.MAXTIER; t++) { float h = Prog.Threat(i, t); if (m.bst <= 300 + h * 30 + g && m.bst >= Math.Min(110 + h * 30 + g, 480) && (h >= 3 || m.cr > 45)) { T = t; break; } }
                if (T > 0) o.Add((S.name, T, m.lg > 0));
            }
            return o.OrderBy(x => x.Item2).ToList();
        }
        static void HubDex(VisualElement body)
        {
            var all = DB.Mons.Where(m => m.anim).ToList(); var G = Save.G;
            body.Add(L($"Seen {all.Count(m => G.Seen(m.id))} - recruited {all.Count(m => G.Own(m.id))} - of {all.Count}", 13, DIM));
            var gt = Add(body, Row(true));
            for (int g = 1; g <= 9; g++) { int gg = g; var b = Btn("Gen " + g, () => { dexGen = gg; ShowHub("dex"); }, dexGen != g, true); if (dexGen == g) b.style.backgroundColor = Hex("#b07c1c"); gt.Add(b); }
            var grid = Add(body, Grid());
            foreach (var m in all.Where(m => m.g == dexGen))
            {
                bool s = G.Seen(m.id); var c = Card(100); if (G.Own(m.id)) Edge(c, ACC, 2, 8);
                c.Add(L("#" + m.id.ToString("0000"), 12, DIM)); c.Add(Icon(m.id, 56, !s)); c.Add(OneLine(L(s ? m.n : "???", 13), 84));
                if (G.Own(m.id)) c.Add(L("recruited", 11, DIM));
                if (s) Click(c, () => DexPanel(m.id));
                grid.Add(c);
            }
        }
        static void DexPanel(int id)
        {
            var m = DB.SP[id]; var p = Panel();
            var head = Add(p, Row()); head.Add(Icon(id, 64)); var hc = Add(head, new VisualElement()); hc.style.flexShrink = 1;
            hc.Add(L("#" + id + " " + m.n, 20)); hc.Add(Types(m.t));
            hc.Add(L($"HP {m.b[0]} - Atk {m.b[1]} - Def {m.b[2]} - SpA {m.b[3]} - SpD {m.b[4]} - Spe {m.b[5]} (total {m.bst})", 13, DIM));
            var ab = Box(); ab.Add(L("Abilities")); ab.Add(L(string.Join(", ", m.ab.Where(a => DB.Abil.ContainsKey(a[0])).Select(a => DB.Abil[a[0]].n + (a[1] == 1 ? " (hidden)" : ""))), 12, DIM)); p.Add(ab);
            var nxt = m.ev.Where(v => DB.SP.ContainsKey(v.to)).Select(v => DB.SP[v.to].n).ToList();
            if (m.f != 0 || nxt.Count > 0) { var eb = Box(); eb.Add(L("Evolution")); eb.Add(L((m.f != 0 && DB.SP.ContainsKey(m.f) ? "From " + DB.SP[m.f].n + ". " : "") + (nxt.Count > 0 ? "Evolves into " + string.Join(", ", nxt) : ""), 12, DIM)); p.Add(eb); }
            var h = Habitat(id); var wb = Box(); wb.Add(L("Where to find it"));
            wb.Add(L((h.Count > 0 ? string.Join(", ", h.Take(8).Select(x => $"{x.Item1} (tier {x.Item2}+{(x.Item3 ? ", as the boss" : "")})")) + (h.Count > 8 ? $", and {h.Count - 8} more" : "") : "Not found on any route as a wild Pokémon.")
                + (nxt.Count > 0 ? " Also shows up when its evolved form is knocked out." : ""), 12, DIM));
            p.Add(wb); p.Add(L(Save.G.Own(id) ? "You have recruited it." : "Knock it out and it may ask to join.", 13, DIM));
            p.Add(Btn("Close", ClosePanel, true));
        }
        /* the Rescue Points tree: 8 branches of paths from a root (like Monkey Knowledge) */
        static string rescueBr;
        static void HubRescue(VisualElement body)
        {
            var G = Save.G; if (rescueBr == null) rescueBr = DB.Branches[0].id;
            body.Add(L($"Rescue Points come from clearing maps (more on higher tiers). {G.rp} to spend - {DB.Tree.Count(Rescue.Owned)}/{DB.Tree.Count} bought.", 13, DIM));
            var tabs = Add(body, Row(true));
            foreach (var b in DB.Branches)
            {
                int have = DB.Tree.Count(n => n.br == b.id && Rescue.Owned(n)), all = DB.Tree.Count(n => n.br == b.id); string id = b.id;
                var bt = Btn(b.name + " " + have + "/" + all, () => { rescueBr = id; ShowHub("rescue"); }, rescueBr != b.id, true);
                if (rescueBr == b.id) { bt.style.backgroundColor = Hex("#b07c1c"); Edge(bt, Hex("#ffe39a"), 2, 6); }
                tabs.Add(bt);
            }
            var br = DB.Branches.Find(b => b.id == rescueBr); body.Add(L(br.blurb, 13, DIM));
            foreach (var path in DB.Tree.Where(n => n.br == br.id).GroupBy(n => n.path))
            {
                var row = Add(body, Row()); row.style.alignItems = Align.Stretch; row.style.marginBottom = 4;
                var pn = L(path.Key == "root" ? "Start" : path.Key, 13, ACC); pn.style.width = 96; pn.style.flexShrink = 0; row.Add(pn);
                var line = Add(row, Row(true)); line.style.flexShrink = 1; line.style.alignItems = Align.Stretch;
                foreach (var n in path)
                {
                    string st = Rescue.Owned(n) ? "own" : Rescue.Open(n) ? (G.rp >= n.cost ? "buy" : "poor") : "lock";
                    var c = new VisualElement(); c.style.width = 128; c.style.backgroundColor = st == "own" ? Hex("#2f6a2f") : st == "buy" ? Hex("#2a4aa0") : Hex("#1a2a55");
                    Edge(c, st == "own" ? GEDGE : st == "buy" ? ACC : new Color(1, 1, 1, .2f), 2, 6); Pad(c, 5); c.style.marginRight = c.style.marginBottom = 4; c.style.opacity = st == "lock" ? .45f : 1;
                    c.Add(L(n.name, 13)); c.Add(L(n.desc, 11, DIM)); c.Add(L(st == "own" ? "owned" : n.cost + " RP", 12, st == "poor" ? Hex("#ff9999") : ACC));
                    if (st == "buy") { var nn = n; Click(c, () => { if (Rescue.Buy(nn)) { Gfx.Sfx("lvl"); ShowHub("rescue"); } }); }
                    line.Add(c);
                }
            }
            int rc = Rescue.ResetCost();
            if (rc > 0)
                body.Add(Btn("Reset tree (₽" + rc.ToString("N0") + ")", () =>
                {
                    var q = Panel(); q.Add(L("Reset the Rescue tree?", 20)); q.Add(L($"All {Rescue.Spent()} points come back to spend again. Costs ₽{rc:N0}."));
                    var r = Add(q, Row()); r.Add(Btn("Reset", () => { if (Rescue.Reset()) { ClosePanel(); ShowHub("rescue"); } else Toast("Not enough ₽"); })); r.Add(Btn("Keep", ClosePanel, true));
                }, true, true));
        }
        static void HubShop(VisualElement body)
        {
            int price = Rescue.ShopPrice(2500);
            body.Add(L("Evolution items. Earn ₽ by clearing routes; higher tiers pay more.", 13, DIM));
            var g = Add(body, Grid());
            foreach (var kv in DB.Items)
            {
                if (string.IsNullOrEmpty(kv.Value)) continue; int id = kv.Key;
                var users = DB.Mons.Where(m => m.ev.Any(v => v.item == id)).Select(m => m.n).ToList();
                var c = Card(150); c.Add(ItemImg(id)); c.Add(L(kv.Value, 15)); c.Add(L(string.Join(", ", users.Take(4)) + (users.Count > 4 ? "..." : ""), 12, DIM)); c.Add(L("₽" + price + " - have " + Save.G.Count(Save.G.items, id), 13));
                g.Add(Click(c, () => { if (Save.G.money < price) { Toast("Not enough ₽"); return; } Save.G.money -= price; Save.G.Add(Save.G.items, id, 1); Save.Write(); Gfx.Sfx("place"); ShowHub("shop"); }));
            }
            body.Add(L("Mints & Bottle Caps", 17)); body.Add(L("Use them from a Pokémon's page, outside battle.", 13, DIM));
            var g3 = Add(body, Grid());
            foreach (var T in DB.Tools.Values)
            {
                int pr = Rescue.ShopPrice(DB.TOOL_PRICE.TryGetValue(T.kind, out var tp) ? tp : 2000); int id = T.id;
                var c = Card(150); c.Add(ItemImg(id)); c.Add(L(T.n, 15)); c.Add(L(T.kind == "mint" ? DB.NatLabel(T.nat).Substring(DB.NatLabel(T.nat).IndexOf(' ') + 1) : T.kind == "bottle-cap" ? "One IV to 31" : "All IVs to 31", 12, DIM));
                c.Add(L("₽" + pr.ToString("N0") + " - have " + Save.G.Count(Save.G.tools, id), 13));
                g3.Add(Click(c, () => { if (Save.G.money < pr) { Toast("Not enough ₽"); return; } Save.G.money -= pr; Save.G.Add(Save.G.tools, id, 1); Save.Write(); Gfx.Sfx("place"); ShowHub("shop"); }));
            }
            body.Add(L("Held items", 17)); body.Add(L("Choice items, Life Orb and Expert Belt are only found on harder routes.", 13, DIM));
            var g2 = Add(body, Grid());
            foreach (var kv in DB.Held)
            {
                int pr = DB.HeldPrice(kv.Value.k); if (pr == 0) continue; pr = Rescue.ShopPrice(pr); int id = kv.Key;
                var c = Card(150); c.Add(ItemImg(id)); c.Add(L(kv.Value.n, 15)); c.Add(L(DB.HELD_TD.TryGetValue(kv.Value.k, out var d) ? d : "", 12, DIM)); c.Add(L("₽" + pr + " - have " + Save.G.Count(Save.G.held, id), 13));
                g2.Add(Click(c, () => { if (Save.G.money < pr) { Toast("Not enough ₽"); return; } Save.G.money -= pr; Save.G.Add(Save.G.held, id, 1); Save.Write(); Gfx.Sfx("place"); ShowHub("shop"); }));
            }
        }
        static void HubBag(VisualElement body)
        {
            var G = Save.G;
            body.Add(L(G.items.Count > 0 || G.held.Count > 0 || G.tools.Count > 0 ? "Use items from a Pokémon's page in the Box." : "Your bag is empty.", 13, DIM));
            foreach (var p in G.items) { var r = Box(); var rr = Add(r, Row()); rr.Add(ItemImg(p.k)); rr.Add(L(" " + (DB.Items.TryGetValue(p.k, out var n) ? n : "?") + " x " + p.v)); body.Add(r); }
            if (G.held.Count > 0) { body.Add(L("Held items (give them from a Pokémon's page)", 17)); foreach (var p in G.held) { var H = DB.Held[p.k]; var r = Box(); var rr = Add(r, Row()); rr.Add(ItemImg(p.k)); rr.Add(L(" " + H.n + " x " + p.v)); r.Add(L(DB.HELD_TD.TryGetValue(H.k, out var d) ? d : "", 12, DIM)); body.Add(r); } }
            if (G.tools.Count > 0) { body.Add(L("Mints & Bottle Caps (use them from a Pokémon's page)", 17)); foreach (var p in G.tools) { var r = Box(); var rr = Add(r, Row()); rr.Add(ItemImg(p.k)); rr.Add(L(" " + DB.Tools[p.k].n + " x " + p.v)); body.Add(r); } }
            body.Add(Btn("Delete save", () =>
            {
                var q = Panel(); q.Add(L("Delete your save?", 20)); q.Add(L("This can't be undone."));
                var r = Add(q, Row()); r.Add(Btn("Delete", () => { Save.Delete(); ClosePanel(); ShowTitle(); })); r.Add(Btn("Keep", ClosePanel, true));
            }, true, true));
        }

        /* ---------- team (max 10) ---------- */
        static void ShowTeam()
        {
            var G = Save.G; team = G.team.Where(u => G.box.Any(e => e.u == u)).Take(10).ToList();
            var s = Show();
            var top = Add(s, Row(true)); top.Add(L(DB.TS[routeSet].name + " - Tier " + routeTier, 16, ACC)); top.Add(Gap()); var cnt = L("Team " + team.Count + "/10"); top.Add(cnt);
            var sv = Scroll(); s.Add(sv); var g = Add(sv.contentContainer, Grid());
            foreach (var e in G.box.OrderByDescending(x => x.lv))
            {
                var c = MonCard(e); if (team.Contains(e.u)) Edge(c, ACC, 3, 8);
                Click(c, () => { if (team.Contains(e.u)) team.Remove(e.u); else if (team.Count < 10) team.Add(e.u); Edge(c, team.Contains(e.u) ? ACC : EDGE, team.Contains(e.u) ? 3 : 2, 8); cnt.text = "Team " + team.Count + "/10"; });
                g.Add(c);
            }
            var bar = Add(s, Row()); bar.style.justifyContent = Justify.FlexEnd;
            bar.Add(Btn("◀ Back", () => ShowHub("routes"), true));
            bar.Add(Btn("Start ▶", () => { if (team.Count == 0) return; G.team = team.ToList(); Save.Write(); BeginBattle(); }));
        }

        /* ---------- battle screen ---------- */
        static VisualElement bottomBox, meterBox; static ScrollView teamSV; static Button bmt; static string meterTab = "dmg"; static int meterOpen; static bool meterHold; static float meterT;
        static VisualElement stage, hud, info, teamBar, wprog, bossBar, bossFill, bossTrail; static Label hl, hc, hw, bossName; static Button bgo, bsp, bau, bwx; static float hudT, bossT; static string infoKey = ""; static int lastLives = -1, bannerWave; static Enemy bossRef;
        static bool Portrait => Screen.height > Screen.width;
        static void BeginBattle()
        {
            var tm = team.Select(u => Save.G.box.Find(e => e.u == u)).Where(e => e != null).ToList();
            Battle.Start(routeSet, routeTier, routeSeed, tm, Portrait, PlayAspect()); View.ResetZoom();
            BuildBattle();
        }
        /* the map fills the screen; the buttons, team bar and info float over it */
        static void BuildBattle()
        {
            InBattle = true; screen.Clear(); screen.style.backgroundColor = Color.clear; Pad(screen, 0);
            screen.style.flexDirection = FlexDirection.Column; screen.style.alignItems = Align.Stretch; screen.style.justifyContent = Justify.FlexStart;
            stage = Add(screen, new VisualElement()); Full(stage);
            var vg = new Image { sprite = Gfx.Vignette, scaleMode = ScaleMode.StretchToFill }; Full(vg); vg.pickingMode = PickingMode.Ignore; stage.Add(vg);   // soft dark edges so the HUD sits on darker corners
            hud = Add(screen, Row(false)); hud.style.position = Position.Absolute; hud.style.transformOrigin = new TransformOrigin(new Length(0), new Length(0), 0); hud.style.left = 6; hud.style.top = 6; hud.style.flexWrap = Wrap.NoWrap;   // no width cap: BattleLayout shrinks the whole bar to fit instead
            hud.style.backgroundColor = new Color(.03f, .07f, .19f, .78f); Edge(hud, new Color(.56f, .72f, 1f, .5f), 1, 8); Pad(hud, 3); hud.style.paddingLeft = 8;
            hl = Add(hud, L("")); hudL = hudC = hudW = -1; hud.Add(Gap(10)); hc = Add(hud, L("", 16, ACC)); hud.Add(Gap(10)); hw = Add(hud, L("")); hud.Add(Gap(6));
            bgo = Add(hud, Btn("GO ▶", () => Battle.B.StartWave(), false, true));
            bsp = Add(hud, Btn(Battle.B.speed + "x", () => { var B = Battle.B; B.speed = B.speed == 1 ? 2 : B.speed == 2 ? 3 : 1; bsp.text = B.speed + "x"; }, true, true));
            bau = Add(hud, Btn("Auto: " + (Battle.B.auto ? "on" : "off"), () => { var B = Battle.B; B.auto = !B.auto; bau.text = "Auto: " + (B.auto ? "on" : "off"); if (B.auto) B.StartWave(); }, true, true));
            bwx = Add(hud, Btn("Weather", WeatherPanel, true, true));
            bmt = Add(hud, Btn("Meter", () => { Save.G.meter = !Save.G.meter; Save.Write(); MeterShow(); }, !Save.G.meter, true));
            hud.Add(Btn("Menu", PauseMenu, true, true));
            // wave progress: how much of this wave is done (a thin line under the one-row bar)
            var wp = Add(hud, new VisualElement()); wp.style.height = 3; wp.style.position = Position.Absolute; wp.style.left = 8; wp.style.right = 8; wp.style.bottom = 1; wp.style.backgroundColor = new Color(0, 0, 0, .35f); hud.style.paddingBottom = 7;
            wprog = Add(wp, new VisualElement()); wprog.style.height = 3; wprog.style.backgroundColor = ACC;
            foreach (var c in hud.Children()) c.style.flexShrink = 0;   // every item keeps its natural size (nothing squeezed or cut)
            // boss bar across the top
            bossBar = Add(screen, new VisualElement()); bossBar.style.position = Position.Absolute; bossBar.style.top = 52; bossBar.style.left = new Length(25, LengthUnit.Percent); bossBar.style.width = new Length(50, LengthUnit.Percent);
            bossBar.style.alignItems = Align.Center; bossBar.pickingMode = PickingMode.Ignore; bossBar.style.display = DisplayStyle.None;
            bossName = Add(bossBar, L("", 15)); bossName.style.unityTextOutlineColor = Color.black; bossName.style.unityTextOutlineWidth = 1;
            var bb = Add(bossBar, new VisualElement()); bb.style.height = 10; bb.style.width = new Length(100, LengthUnit.Percent); bb.style.backgroundColor = new Color(0, 0, 0, .7f); Edge(bb, Hex("#ffd84a"), 2, 4); bb.style.overflow = Overflow.Hidden;
            bossTrail = Add(bb, new VisualElement()); bossTrail.style.position = Position.Absolute; bossTrail.style.left = 0; bossTrail.style.top = 0; bossTrail.style.bottom = 0; bossTrail.style.backgroundColor = new Color(1, 1, 1, .55f);
            bossFill = Add(bb, new VisualElement()); bossFill.style.position = Position.Absolute; bossFill.style.left = 0; bossFill.style.top = 0; bossFill.style.bottom = 0; bossFill.style.backgroundColor = Hex("#e8403a");
            lastLives = Battle.B.lives;
            // bottom: info box above a centred row of the team
            var bottom = Add(screen, new VisualElement()); bottom.style.position = Position.Absolute; bottom.style.left = 0; bottom.style.right = 0; bottom.style.bottom = 4;
            bottom.style.alignItems = Align.Center; bottom.pickingMode = PickingMode.Ignore;
            info = Add(bottom, new VisualElement()); info.style.backgroundColor = new Color(.1f, .21f, .5f, .92f); Edge(info, EDGE, 2, 8); Pad(info, 6); info.style.marginBottom = 4;
            info.style.maxWidth = new Length(96, LengthUnit.Percent); info.style.display = DisplayStyle.None;
            teamSV = new ScrollView(ScrollViewMode.Horizontal); teamSV.horizontalScrollerVisibility = ScrollerVisibility.Hidden; teamSV.verticalScrollerVisibility = ScrollerVisibility.Hidden; teamSV.touchScrollBehavior = ScrollView.TouchScrollBehavior.Clamped; bottom.Add(teamSV);   // swipe sideways when the team is wider than the screen
            teamSV.style.maxWidth = new Length(98, LengthUnit.Percent); teamSV.style.backgroundColor = new Color(.03f, .07f, .19f, .7f); Edge(teamSV, new Color(.56f, .72f, 1f, .4f), 1, 8); Pad(teamSV, 3);
            teamBar = teamSV.contentContainer; teamBar.style.flexDirection = FlexDirection.Row;
            bottomBox = bottom; meterBox = null; MeterShow();
            bannerWave = 0; ptrs.Clear(); pinch = false;
            stage.RegisterCallback<PointerDownEvent>(e => { stage.CapturePointer(e.pointerId); ptrs[e.pointerId] = e.position; if (ptrs.Count == 1) { downAt = e.position; panned = false; } Pointer(e.position, 1, e.pointerId, e.pointerType == "touch"); });
            stage.RegisterCallback<PointerMoveEvent>(e => Pointer(e.position, 0, e.pointerId, e.pointerType == "touch"));
            stage.RegisterCallback<PointerUpEvent>(e => { stage.ReleasePointer(e.pointerId); Pointer(e.position, 2, e.pointerId, e.pointerType == "touch"); });
            stage.RegisterCallback<PointerCancelEvent>(e => { ptrs.Remove(e.pointerId); pinch = ptrs.Count >= 2; View.ghostPos = null; });
            stage.RegisterCallback<PointerLeaveEvent>(e => { if (e.pointerType != "touch") View.ghostPos = null; });
            BuildTeamBar(); RefreshHud(); TowerInfo();
        }
        static void WeatherPanel()
        {
            var B = Battle.B; if (B == null || B.over) return; B.paused = true;
            var p = Panel(() => { if (Battle.B != null) Battle.B.paused = false; });
            p.Add(L("Weather", 20)); p.Add(L($"Costs ${B.WeatherCost()} battle cash, lasts {Battle.WeatherWaves()} waves (bought during a wave, that wave counts). A boss's weather covers yours until it's knocked out. You have ${B.cash}.", 13, DIM));
            foreach (var kv in Battle.WEATHER)
            {
                string k = kv.Key; var r = Box(); r.Add(L(kv.Value[0])); r.Add(L(kv.Value[1], 12, DIM));
                p.Add(Click(r, () => { if (B.BuyWeather(k)) ClosePanel(); else Toast("Not enough battle cash"); }));
            }
            p.Add(Btn("Close", ClosePanel, true));
        }
        static void BuildTeamBar()
        {
            if (teamBar == null || Battle.B == null) return; teamBar.Clear();
            foreach (var e in Battle.B.team)
            {
                var c = new VisualElement(); c.userData = e; c.style.width = 56; c.style.alignItems = Align.Center; c.style.backgroundColor = WIN; Edge(c, EDGE, 2, 6); c.style.borderTopWidth = 4; Pad(c, 2); c.style.marginLeft = c.style.marginRight = 2; c.style.marginTop = c.style.marginBottom = 2;
                c.Add(Icon(e.id, 30)); if (Battle.SeesWhy(e) != null) { var st = SeesTag(); st.text = "sees"; c.Add(st); } var tl = L("", 11); tl.name = "tl"; tl.style.unityTextAlign = TextAnchor.MiddleCenter; c.Add(tl);
                Click(c, () =>
                {
                    var B = Battle.B; var tw = B.towers.Find(t => t.e == e);
                    if (tw != null) { B.sel = tw; B.selE = null; B.placing = null; }
                    else { B.placing = B.placing == e ? null : e; B.sel = null; B.selE = null; }
                    TowerInfo(); RefreshHud();
                });
                teamBar.Add(c);
            }
        }
        static int hudL = -1, hudC = -1, hudW = -1;
        static void RefreshHud()
        {
            var B = Battle.B; if (B == null || hl == null) return;
            if (lastLives >= 0 && B.lives < lastLives) { hl.style.color = Hex("#ff5050"); hl.schedule.Execute(() => hl.style.color = Color.white).StartingIn(450); }   // lives lost: a red flash
            lastLives = B.lives;
            // texts only change when the numbers do (no new strings every frame)
            if (B.lives != hudL) { hudL = B.lives; hl.text = "♥ " + B.lives; }
            if (B.cash != hudC) { hudC = B.cash; hc.text = "$ " + B.cash; }
            if (B.wave != hudW) { hudW = B.wave; hw.text = "Wave " + B.wave + "/" + B.waves.Count; }
            var wv = B.waves[Math.Max(0, B.wave - 1)]; int left = B.phase == "wave" ? B.q.Count + B.en.Count(x => x.hp > 0) : 0;
            wprog.style.width = new Length(B.phase == "wave" && wv.Count > 0 ? Mathf.Max(0, 100 - left * 100f / wv.Count) : B.phase == "build" && B.wave > 0 ? 100 : 0, LengthUnit.Percent);
            var boss = B.en.FirstOrDefault(x => x.boss && x.hp > 0 && x.d > 0); bossBar.style.display = boss != null ? DisplayStyle.Flex : DisplayStyle.None;
            // its height on screen is set only in BattleLayout (right under the shrunk top bar); setting it here too made it jump
            if (boss != null)
            {
                float f = boss.hp / boss.max; if (bossRef != boss) { bossRef = boss; bossT = f; } else bossT = Mathf.Max(f, bossT - 0.01f);
                bossName.text = (DB.SP[boss.id].lg > 0 ? "LEGENDARY  " : "") + DB.SP[boss.id].n + "  Lv " + boss.lv; bossName.style.color = DB.SP[boss.id].lg > 0 ? ACC : Color.white;
                bossFill.style.width = new Length(f * 100, LengthUnit.Percent); bossTrail.style.width = new Length(bossT * 100, LengthUnit.Percent);
            }
            if (B.phase == "wave" && B.wave != bannerWave) { bannerWave = B.wave; WaveBanner(); }
            bgo.SetEnabled(B.phase == "build");
            bwx.text = B.weather != null ? (Battle.WEATHER[B.weather.k][0] + (B.weather.boss ? " (boss)" : " - " + B.WavesLeft() + " wave" + (B.WavesLeft() == 1 ? "" : "s"))) : "Weather";
            foreach (var c in teamBar.Children())
            {
                var e = (Mon)c.userData; bool on = B.towers.Any(t => t.e == e);
                c.style.opacity = on ? .55f : 1; Edge(c, B.placing == e || (B.sel != null && B.sel.e == e) ? ACC : EDGE, 2, 6); c.style.borderTopWidth = 4; c.style.borderTopColor = Hex(DB.TCOL[DB.SP[e.id].t[0]]);   // its type's colour on top
                var tw = B.towers.Find(t => t.e == e); var tl = c.Q<Label>("tl"); tl.text = "Lv" + e.lv + "\n" + (on ? tw.kills + " KO" : "$" + DB.PlaceCost(e)); tl.style.color = !on && B.cash < DB.PlaceCost(e) ? Hex("#ff9999") : Color.white;
            }
        }
        /* banner across the map when a wave starts (heavy waves and the boss get their own) */
        static void WaveBanner()
        {
            var B = Battle.B; if (B == null || !InBattle) return;
            var w = B.waves[B.wave - 1]; var boss = w.FirstOrDefault(x => x.boss); bool heavy = B.wave % 5 == 0 && boss == null, leg = boss != null && DB.SP[boss.id].lg > 0;
            var bn = Add(screen, Row()); bn.style.position = Position.Absolute; bn.style.top = new Length(38, LengthUnit.Percent); bn.style.left = 0; bn.style.right = 0; bn.style.justifyContent = Justify.Center; bn.pickingMode = PickingMode.Ignore;
            bn.style.backgroundColor = boss == null ? new Color(.1f, .21f, .5f, .85f) : leg ? new Color(.42f, .23f, .66f, .9f) : new Color(.54f, .08f, .08f, .9f); Pad(bn, 8);
            if (boss != null) bn.Add(Icon(boss.id, 56));
            var col = Add(bn, new VisualElement()); col.style.marginLeft = 10;
            col.Add(L(boss != null ? (leg ? "Legendary boss!" : "Boss wave!") : "Wave " + B.wave, 30)); if (boss != null) col.Add(L(DB.SP[boss.id].n + " Lv " + boss.lv, 15, DIM)); else if (heavy) col.Add(L("Heavy wave: tough Pokémon", 15, DIM));
            bn.style.translate = new Translate(new Length(-100, LengthUnit.Percent), 0); bn.style.opacity = 0;
            float t0 = Time.unscaledTime;
            bn.schedule.Execute(() =>   // slide in, hold, slide out
            {
                float k = (Time.unscaledTime - t0) / 1.9f; if (k >= 1) { bn.RemoveFromHierarchy(); return; }
                float x = k < 0.15f ? -100 + 100 * k / 0.15f : k < 0.8f ? 0 : 100 * (k - 0.8f) / 0.2f; bn.style.translate = new Translate(new Length(x, LengthUnit.Percent), 0); bn.style.opacity = k < 0.15f ? k / 0.15f : k > 0.8f ? 1 - (k - 0.8f) / 0.2f : 1;
            }).Every(16).Until(() => bn.panel == null);
        }
        static void TowerInfo()
        {
            var B = Battle.B; if (info == null || B == null) return; info.Clear();
            if (B.placing != null && B.sel == null)
            {
                var sp = DB.SP[B.placing.id];
                info.Add(L(sp.n + " - tap the map to place ($" + DB.PlaceCost(B.placing) + "). " + string.Join(". ", Battle.Quirks(sp.id).Select(q => q[0] + ": " + q[1])) + "." + (sp.t.Contains(10) ? " Can stand in water." : sp.t.Contains(9) ? " Can stand in lava." : ""), 14));
                info.style.display = DisplayStyle.Flex; return;
            }
            if (B.sel == null && B.selE != null && B.selE.hp > 0)
            {
                var x = B.selE; var s = DB.SP[x.id]; DB.Abil.TryGetValue(x.ab, out var A);
                var r = Add(info, Row(true)); r.Add(L("Wild " + s.n + " Lv " + x.lv + "  ", 14)); r.Add(Types(s.t)); r.Add(L("  HP " + Mathf.CeilToInt(x.hp) + "/" + (int)x.max + (A != null ? " - " + A.n : ""), 14));
                var tags = new List<string>();
                if (x.air) tags.Add("Flying: cuts corners, Ground moves miss");
                if (x.hide) tags.Add("Hidden: needs a Psychic or Ghost type, Foresight, Odor Sleuth, Miracle Eye, Keen Eye or Frisk nearby");
                if (x.dig) tags.Add("Digs: underground only Earthquake / Magnitude / Fissure hit");
                if (x.armor) tags.Add("Armoured: moves under 60 power do half");
                if (x.healMv != 0) tags.Add("Heals with " + DB.Mv(x.healMv).n + (x.healed ? " (used)" : ""));
                if (x.regen) tags.Add("Regenerator");
                if (x.prot != 0) tags.Add("Shields with " + DB.Mv(x.prot).n);
                if (x.dashMv != 0) tags.Add("Dashes (" + DB.Mv(x.dashMv).n + ")");
                if (x.tele) tags.Add("Teleports ahead");
                if (x.boss) tags.Add("Boss" + (x.bwx != null ? " - " + DB.Mv(x.bwxm).n : "") + (x.bup.Count > 0 ? " - " + string.Join(", ", x.bup.Select(m => DB.Mv(m).n)) : "") + " - calls for help");
                if (tags.Count > 0) info.Add(L(string.Join(" - ", tags), 12, DIM));
                info.style.display = DisplayStyle.Flex; return;
            }
            var t = B.sel; if (t == null) { info.style.display = DisplayStyle.None; return; }
            var e = t.e; var sp2 = DB.SP[e.id]; DB.Abil.TryGetValue(e.ab, out var A2); DB.Held.TryGetValue(e.it, out var H);
            var h = Add(info, Row(true)); h.Add(L(sp2.n + " Lv " + e.lv + " - " + t.kills + " KOs  ", 14)); h.Add(Types(sp2.t));
            var tg = new List<string>(); var why = Battle.SeesWhy(e); if (why != null) tg.Add("Sees hidden (" + why + ")"); if (A2 != null && DB.AB_TD.TryGetValue(A2.k, out var td) && !td.StartsWith("Wild")) tg.Add(A2.n); if (H != null) tg.Add(H.n);
            if (tg.Count > 0) h.Add(L("  " + string.Join(" - ", tg), 12, DIM));
            foreach (var q in Battle.Quirks(e.id)) info.Add(L(q[0] + ": " + q[1], 12, Hex("#ffe39a")));
            int x0 = DB.XpFor(sp2.gr, e.lv), x1 = e.lv < DB.MAXLV ? DB.XpFor(sp2.gr, e.lv + 1) : e.xp; var xr = Add(info, Row());
            var xb = Add(xr, new VisualElement()); xb.style.height = 6; xb.style.width = 140; xb.style.backgroundColor = new Color(0, 0, 0, .4f); xb.style.marginRight = 8;
            var xf = Add(xb, new VisualElement()); xf.style.height = 6; xf.style.backgroundColor = Hex("#55ccff"); xf.style.width = new Length(e.lv >= DB.MAXLV ? 100 : Mathf.Clamp01((e.xp - x0) / (float)Mathf.Max(1, x1 - x0)) * 100, LengthUnit.Percent);
            xr.Add(L(e.lv >= DB.MAXLV ? "Max level" : (x1 - e.xp).ToString("N0") + " XP to Lv " + (e.lv + 1), 12, DIM));
            var mr = Add(info, Row(true)); foreach (int m in e.mv) { var tt = TypeTag(DB.Mv(m).t); tt.text = DB.Mv(m).n; mr.Add(tt); }
            var ups = Add(info, Row(true));   // upgrades: Range / Speed / Power, a pip per level
            for (int k = 0; k < 3; k++)
            {
                int kk = k, lv = t.up[k], c = Battle.UpgradeCost(t, k); string pips = lv + "/" + Cfg.C.upgMax;   // plain digits: the pixel font has no dot symbols
                var ub = Btn(Battle.UPGN[k] + " " + pips + "\n" + (c > 0 ? "$" + c + " (+" + Mathf.RoundToInt(Cfg.C.upgStep * 100) + "%)" : "Max"), () => { if (B.BuyUpgrade(t, kk)) { TowerInfo(); RefreshHud(); } else Toast("Not enough battle cash"); }, c == 0 || B.cash < c, true);
                ub.SetEnabled(c > 0); ub.style.flexGrow = 1; ups.Add(ub);
            }
            var modes = Add(info, Row(true));
            foreach (var (k, n) in new[] { ("first", "First"), ("last", "Last"), ("strong", "Strong"), ("close", "Close") }) modes.Add(Btn(n, () => { t.mode = k; TowerInfo(); }, t.mode != k, true));
            modes.Add(Btn("Moves / Evolve" + (DB.EvoOptions(e).Any(o => o.ok) || e.pend.Count > 0 ? " ●" : ""), () => { B.paused = true; MonPanel(e, () => { if (Battle.B != null) Battle.B.paused = false; TowerInfo(); RefreshHud(); }); }, true, true));
            modes.Add(Btn("Recall ($" + (int)(t.paid * 0.7f) + ")", () => { B.Sell(t); TowerInfo(); RefreshHud(); }, true, true));
            if (Battle.HasM(t, "Teleport")) modes.Add(Btn("Move (free)", () => { B.moving = t; B.swapping = null; Toast("Tap where it should go"); }, false, true));
            if (Battle.HasM(t, "Ally Switch") && B.towers.Count > 1) modes.Add(Btn("Swap (free)", () => { B.swapping = t; B.moving = null; Toast("Tap a teammate to swap with"); }, false, true));
            info.style.display = DisplayStyle.Flex;
        }
        /* map input (panel coordinates): kind 0 move, 1 down, 2 up. Two fingers pinch to zoom, one finger drags a zoomed map,
           double-tap zooms back out; on touch the placement preview sits above the fingertip so it isn't hidden */
        static readonly Dictionary<int, Vector2> ptrs = new Dictionary<int, Vector2>(); static bool pinch, panned; static float pinchD, pinchZ, lastTap; static Vector2 downAt;
        const float FINGER = 70;
        static Vector2 ToGame(Vector2 panelPos) { float sc = Screen.width / Mathf.Max(1, Root.layout.width); return View.ScreenToGame(new Vector2(panelPos.x * sc, Screen.height - panelPos.y * sc)); }
        static void Pointer(Vector2 panelPos, int kind, int id, bool touch)
        {
            var B = Battle.B; if (B == null || B.over) return;
            Vector2 prev = ptrs.TryGetValue(id, out var pv) ? pv : panelPos;
            if (kind == 0 && ptrs.ContainsKey(id)) ptrs[id] = panelPos;
            if (kind == 1 && ptrs.Count == 2) { var pp = ptrs.Values.ToList(); pinch = true; pinchD = Vector2.Distance(pp[0], pp[1]); pinchZ = View.zoom; View.ghostPos = null; return; }
            if (kind == 2) { int was = ptrs.Count; ptrs.Remove(id); if (was >= 2) { if (ptrs.Count < 2) pinch = false; panned = true; return; } }
            if (pinch && ptrs.Count >= 2 && kind == 0)
            {
                var pp = ptrs.Values.ToList(); var mid = (pp[0] + pp[1]) / 2; var before = ToGame(mid);
                View.zoom = Mathf.Clamp(pinchZ * Vector2.Distance(pp[0], pp[1]) / Mathf.Max(1, pinchD), 1, 3); View.Refit();
                var after = ToGame(mid); View.zc = View.zc + (before - after); View.Refit(); panned = true; return;   // keep the map point under the fingers in place
            }
            Vector2 placeAt = touch ? panelPos - new Vector2(0, FINGER) : panelPos;
            var gp = ToGame(placeAt);
            if (B.moving != null && kind == 2 && !panned)   // Teleport: free move to a new spot
            {
                var t = B.moving; B.moving = null; float ox = t.x, oy = t.y; t.x = t.y = -999;
                if (B.CanPlace(t.e, gp.x, gp.y)) { t.x = gp.x; t.y = gp.y; t.tp = null; Gfx.Sfx("place"); } else { t.x = ox; t.y = oy; Toast("It can't go there"); }
                TowerInfo(); return;
            }
            if (B.placing != null)
            {
                if (kind == 2 && panned) { View.ghostPos = null; return; }
                bool ok = B.CanPlace(B.placing, gp.x, gp.y) && B.cash >= DB.PlaceCost(B.placing) && B.towers.Count < 10;
                if (kind != 0 || !touch || ptrs.ContainsKey(id)) { View.ghostPos = gp; View.ghostOk = ok; }
                if (kind == 2)
                {
                    if (B.Place(B.placing, gp.x, gp.y) != null) { B.sel = null; B.placing = null; View.ghostPos = null; }
                    else if (B.cash < DB.PlaceCost(B.placing)) Toast("Not enough battle cash");
                    TowerInfo(); RefreshHud();
                }
                return;
            }
            if (kind == 0 && ptrs.ContainsKey(id) && View.zoom > 1 && (panned || Vector2.Distance(panelPos, downAt) > 8))   // one finger drags the zoomed map
            { panned = true; View.zc = View.zc - (ToGame(panelPos) - ToGame(prev)); View.Refit(); return; }
            if (kind != 2 || panned) return;
            if (Time.unscaledTime - lastTap < 0.3f && View.zoom > 1) { lastTap = 0; View.ResetZoom(); return; }   // double-tap: zoom back out
            lastTap = Time.unscaledTime;
            var g = ToGame(panelPos); float tr = touch ? 30 : 22;
            Tower best = null; float bd = tr;
            foreach (var t in B.towers) { float d = Vector2.Distance(new Vector2(t.x, t.y - 9), g); if (d < bd) { bd = d; best = t; } }
            if (B.swapping != null) { var a = B.swapping; B.swapping = null; if (best != null && best != a) { (a.x, a.y, best.x, best.y) = (best.x, best.y, a.x, a.y); a.tp = best.tp = null; Gfx.Sfx("place"); } TowerInfo(); return; }   // Ally Switch
            B.sel = best; B.selE = null;
            if (best == null) { float ed = tr - 2; foreach (var e in B.en) { float d = Vector2.Distance(new Vector2(e.x, e.y - ((e.air ? 12 : 0) + 6) * Battle.ESPR), g); if (e.hp > 0 && d < ed) { ed = d; B.selE = e; } } }
            TowerInfo(); RefreshHud();
        }
        static void PauseMenu()
        {
            var B = Battle.B; if (B == null || B.over || B.paused) return;
            B.paused = true; var p = Panel(() => { if (Battle.B != null) Battle.B.paused = false; }); p.Add(L("Paused", 20));
            var r = Add(p, Row()); r.Add(Btn("Resume", ClosePanel)); r.Add(Btn("Options", () => OptionsPanel(() => { if (Battle.B != null) Battle.B.paused = false; }), true)); r.Add(Btn("Give up", () => { ClosePanel(); Battle.B.GiveUp(); }, true));
        }
        public static void OnPause() { if (InBattle) PauseMenu(); }
        /* a knocked-out wild Pokémon asks to join: the battle pauses and you decide */
        public static void AskJoin()
        {
            var B = Battle.B; if (B == null || B.asks.Count == 0 || ModalOpen || !InBattle) return;
            var a = B.asks[0]; B.asks.RemoveAt(0); var s = DB.SP[a.id]; DB.Abil.TryGetValue(a.ab, out var A); var moves = DB.BestMoves(a.id, a.lv);
            B.paused = true;
            var p = Panel(() =>
            {
                if (Battle.B == null) return; Battle.B.paused = false;
                if (Battle.B.asks.Count > 0) AskJoin(); else if (Battle.B.over) ShowResult();
            }, true);
            var head = Add(p, Row()); head.Add(Icon(a.id, 64)); var hc2 = Add(head, new VisualElement()); hc2.style.flexShrink = 1;
            hc2.Add(L(s.n + " wants to join your team!", 20)); var rr = Add(hc2, Row(true));
            int owned = Save.G.box.Count(x => x.id == a.id);   // already have this species: a Poké Ball marker, like the main games' caught icon
            if (owned > 0) { var ot = Add(rr, Row()); ot.style.backgroundColor = new Color(0, 0, 0, .4f); Edge(ot, Color.clear, 0, 9); ot.style.paddingRight = 6; ot.style.marginRight = 6; if (Gfx.Tex("Ui/pokeball") != null) ot.Add(UiImg("pokeball", 20)); ot.Add(L("Owned" + (owned > 1 ? " x" + owned : ""), 12, Hex("#ffe39a"))); }
            rr.Add(L("Lv " + a.lv + "  ")); rr.Add(Types(s.t));
            if (a.nat != 0 && a.iv != null) hc2.Add(L(DB.NatLabel(a.nat) + " nature - IVs " + string.Join(" / ", a.iv) + " (total " + a.iv.Sum() + "/186)", 13, DIM));
            if (A != null) hc2.Add(L("Ability: " + A.n + (DB.AB_TD.TryGetValue(A.k, out var td) && !td.StartsWith("Wild") ? " - " + td : ""), 13, DIM));
            var mr = Add(hc2, Row(true)); foreach (int m in moves) { var tt = TypeTag(DB.Mv(m).t); tt.text = DB.Mv(m).n; mr.Add(tt); }
            hc2.Add(L("Box: " + Save.G.box.Count + " Pokémon" + (B.team.Count < 10 ? " - it would join this battle too" : ""), 13, DIM));
            var br = Add(p, Row());
            br.Add(Btn("Accept", () => { B.Accept(a); Toast(s.n + " joined your team!", a.id); ClosePanel(); }));
            br.Add(Btn("Decline", () => { B.declined.Add(a.id); ClosePanel(); }, true));
        }
        static void ShowResult()
        {
            var B = Battle.B; if (B == null) return;
            if (B.asks.Count > 0) { if (!ModalOpen) AskJoin(); return; }   // answer join requests first
            bool won = B.phase == "win"; var p = Panel(null, true);
            p.Add(L(won ? "Route cleared!" : "The wild Pokémon got through...", 20));
            p.Add(L($"{DB.TS[B.set].name} - Tier {B.tier} - wave {B.wave}/{B.waves.Count} - {B.kills} KOs"));
            if (won)
            {
                var sr = Add(p, Row(true)); sr.style.justifyContent = Justify.Center;
                for (int k = 0; k < 3; k++) { var st = L("★", 34, k < B.stars ? ACC : new Color(1, 1, 1, .2f)); st.style.opacity = 0; sr.Add(st); int kk = k; st.schedule.Execute(() => { st.style.opacity = 1; if (kk < B.stars) Gfx.Sfx("lvl"); }).StartingIn(250 + k * 300); }
                if (B.starRp > 0) p.Add(L("+" + B.starRp + " Rescue Points for new stars", 13, DIM));
            }
            var rw = Add(p, Row(true)); rw.Add(UiImg("coin", 20)); var cm = L(" 0", 18, ACC); rw.Add(cm); rw.Add(Gap()); rw.Add(UiImg("badge", 20)); var cr = L(" Rescue Points 0", 16); rw.Add(cr);
            { float t0 = Time.unscaledTime; int toM = B.reward, toR = B.rp; cm.schedule.Execute(() => { float k = Mathf.Min(1, (Time.unscaledTime - t0) / 0.9f), e2 = 1 - Mathf.Pow(1 - k, 3); cm.text = " " + Mathf.RoundToInt(toM * e2).ToString("N0"); cr.text = " Rescue Points " + Mathf.RoundToInt(toR * e2); }).Every(16).Until(() => cm.panel == null || Time.unscaledTime - t0 > 1); }   // counters roll up
            var dr = Add(p, Row(true)); if (B.drop != 0) dr.Add(ItemImg(B.drop)); if (B.hdrop != 0) dr.Add(ItemImg(B.hdrop));
            if (B.unlocked || B.mapOpened != null || B.groupOpened != null) p.Add(L((B.unlocked ? "Tier " + (B.tier + 1) + " unlocked on " + DB.TS[B.set].name + "!  " : "") + (B.groupOpened != null ? B.groupOpened + " maps open!  " : "") + (B.mapOpened != null ? "New map: " + B.mapOpened + "!" : ""), 15, ACC));
            if (B.drop != 0 || B.hdrop != 0) p.Add(L(((B.drop != 0 ? "Found a " + DB.Items[B.drop] + "!  " : "") + (B.hdrop != 0 ? "Found a " + DB.Held[B.hdrop].n + "!" : "")).Trim()));
            if (B.recruits.Count > 0) { p.Add(L("Joined your team", 17)); var g = Add(p, Grid()); foreach (var e in B.recruits) g.Add(MonCard(e)); }
            p.Add(L("Team", 17)); var g2 = Add(p, Grid());
            foreach (var e in B.team) { var c = MonCard(e); c.Add(L("+" + (B.xpLog.TryGetValue(e.u, out var x) ? x : 0) + " XP", 12, DIM)); g2.Add(c); }
            if (B.meter.Count > 0) { p.Add(L("Damage meter", 17)); var mb = Add(p, new VisualElement()); mb.style.backgroundColor = new Color(0, 0, 0, .2f); Pad(mb, 6); Edge(mb, Color.clear, 0, 8); meterOpen = 0; MeterDraw(mb, "dmg", true); }
            var r = Add(p, Row(true));
            r.Add(Btn("Same route, new layout", () => { ClosePanel(); routeSeed = UnityEngine.Random.Range(0, 1000000000); BeginBattle(); }));
            r.Add(Btn("Back to routes", () => { ClosePanel(); Battle.B = null; ShowHub("routes"); }, true));
        }

        /* ---------- damage meter (Details!-style): Dmg / KO / Fx tabs, tap a row for its move breakdown, drag it anywhere ---------- */
        static void MeterShow()
        {
            if (screen == null || !InBattle) return;
            if (meterBox == null)
            {
                meterBox = Add(screen, new VisualElement()); meterBox.style.position = Position.Absolute; meterBox.style.width = 168; meterBox.style.backgroundColor = new Color(.03f, .07f, .19f, .72f);
                Edge(meterBox, new Color(.87f, .92f, 1f, .5f), 1, 7); Pad(meterBox, 3); meterBox.style.right = 6; meterBox.style.top = 60;
                Vector2 start = default, origin = default; int pid = -1; bool moved = false;
                meterBox.RegisterCallback<PointerDownEvent>(e => { pid = e.pointerId; start = e.position; origin = new Vector2(meterBox.layout.x, meterBox.layout.y); moved = false; meterHold = true; }, TrickleDown.TrickleDown);
                meterBox.RegisterCallback<PointerMoveEvent>(e =>
                {
                    if (e.pointerId != pid) return; var d = (Vector2)e.position - start;
                    if (!moved && d.magnitude < 8) return; if (!moved) { moved = true; meterBox.CapturePointer(pid); }
                    float W = Root.layout.width, H = Root.layout.height, x = Mathf.Clamp(origin.x + d.x, 0, Mathf.Max(0, W - meterBox.layout.width)), y = Mathf.Clamp(origin.y + d.y, 0, Mathf.Max(0, H - 40));
                    meterBox.style.right = StyleKeyword.Auto; meterBox.style.left = x; meterBox.style.top = y; Save.G.mx = x / W; Save.G.my = y / H;
                }, TrickleDown.TrickleDown);
                meterBox.RegisterCallback<PointerUpEvent>(e => { if (e.pointerId != pid) return; if (moved) { meterBox.ReleasePointer(pid); Save.Write(); e.StopImmediatePropagation(); } pid = -1; meterBox.schedule.Execute(() => meterHold = false).StartingIn(60); }, TrickleDown.TrickleDown);
            }
            meterBox.style.display = Save.G.meter ? DisplayStyle.Flex : DisplayStyle.None;
            if (Save.G.mx >= 0 && Root.layout.width > 0) { meterBox.style.right = StyleKeyword.Auto; meterBox.style.left = Save.G.mx * Root.layout.width; meterBox.style.top = Save.G.my * Root.layout.height; }
            if (bmt != null) bmt.style.backgroundColor = Save.G.meter ? GREEN : ALT;
            if (Save.G.meter) MeterDraw(meterBox, meterTab, false);
        }
        static string K(float v) => v >= 10000 ? (v / 1000f).ToString(v >= 100000 ? "0" : "0.0") + "k" : ((int)v).ToString("N0");
        static void MeterDraw(VisualElement box, string tab, bool full)
        {
            var B = Battle.B; if (B == null) return; box.Clear();
            var tabs = Add(box, Row());
            foreach (var (k, n) in full ? new[] { ("dmg", "Damage"), ("ko", "Knockouts"), ("fx", "Effects") } : new[] { ("dmg", "Dmg"), ("ko", "KO"), ("fx", "Fx") })
            { var b = Btn(n, () => { meterTab = k; meterOpen = 0; MeterDraw(box, k, full); }, k != tab, true); if (!full) { b.style.fontSize = 10; Pad(b, 0); b.style.paddingLeft = b.style.paddingRight = 4; b.style.marginTop = b.style.marginBottom = 1; } tabs.Add(b); }
            var rows = B.meter.Values.Select(m => (m, e: Save.G.box.Find(x => x.u == m.u))).Where(r => r.e != null).ToList();
            float tD = rows.Sum(r => r.m.dmg), tK = rows.Sum(r => r.m.ko), tC = rows.Sum(r => r.m.ctl), tO = rows.Sum(r => r.m.dot);
            Func<MeterRow, float> val = r => tab == "dmg" ? r.dmg : tab == "ko" ? r.ko : (tC > 0 ? r.ctl / tC : 0) + (tO > 0 ? r.dot / tO : 0);
            rows = rows.OrderByDescending(r => val(r.m)).ToList(); float max = rows.Count > 0 ? Mathf.Max(0.0001f, val(rows[0].m)) : 1, secs = Mathf.Max(1, B.time);
            if (rows.Count == 0) { box.Add(L("Nothing yet - place a Pokémon and start a wave.", full ? 13 : 10, DIM)); return; }
            int fs = full ? 14 : 10, isz = full ? 22 : 14, i = 0;
            foreach (var (m, e) in rows)
            {
                i++; var row = Add(box, Row()); row.style.marginTop = row.style.marginBottom = 1; row.style.backgroundColor = new Color(0, 0, 0, .3f); Edge(row, Color.clear, 0, 3); row.style.overflow = Overflow.Hidden; row.style.paddingLeft = row.style.paddingRight = 3;
                var bar = Add(row, new VisualElement()); bar.style.position = Position.Absolute; bar.style.left = 0; bar.style.top = 0; bar.style.bottom = 0; bar.style.width = new Length(Mathf.Max(2, val(m) / max * 100), LengthUnit.Percent);
                var c = Hex(DB.TCOL[DB.SP[e.id].t[0]]); c.a = .45f; bar.style.backgroundColor = c; bar.pickingMode = PickingMode.Ignore;
                row.Add(Icon(e.id, isz)); var nm = Add(row, L((full ? i + ". " : "") + DB.SP[e.id].n + (full && i == 1 && tab == "dmg" ? "  MVP" : ""), fs, full && i == 1 && tab == "dmg" ? ACC : Color.white)); nm.style.flexGrow = 1; nm.style.whiteSpace = WhiteSpace.NoWrap; nm.style.overflow = Overflow.Hidden;
                int pct = Mathf.RoundToInt(tab == "dmg" ? m.dmg / Mathf.Max(1, tD) * 100 : m.ko / Mathf.Max(1, tK) * 100);
                string txt = tab == "dmg" ? (full ? ((int)m.dmg).ToString("N0") + "  " + Mathf.RoundToInt(m.dmg / secs) + "/s  " : K(m.dmg) + " ") + pct + "%" : tab == "ko" ? m.ko + "  " + pct + "%" : Mathf.RoundToInt(m.ctl) + "s" + (m.dot > 0 ? "  " + K(m.dot) : "");
                var v = Add(row, L(txt, fs)); v.style.whiteSpace = WhiteSpace.NoWrap;
                int u = m.u; Click(row, () => { meterOpen = meterOpen == u ? 0 : u; MeterDraw(box, tab, full); });
                if (meterOpen == u)
                {
                    var bd = Add(box, new VisualElement()); bd.style.paddingLeft = full ? 30 : 18;
                    foreach (var kv in m.br.OrderByDescending(x => x.Value)) { var r2 = Add(bd, Row()); var a = Add(r2, L(kv.Key, fs - 2, DIM)); a.style.flexGrow = 1; r2.Add(L(((int)kv.Value).ToString("N0") + " (" + Mathf.RoundToInt(kv.Value / Mathf.Max(1, m.dmg) * 100) + "%)", fs - 2, DIM)); }
                    var r3 = Add(bd, Row()); var a3 = Add(r3, L("Control", fs - 2, DIM)); a3.style.flexGrow = 1; r3.Add(L(Mathf.RoundToInt(m.ctl) + " s", fs - 2, DIM));
                    var r4 = Add(bd, Row()); var a4 = Add(r4, L("Knockouts", fs - 2, DIM)); a4.style.flexGrow = 1; r4.Add(L(m.ko.ToString(), fs - 2, DIM));
                }
            }
            if (full) box.Add(L(tab == "dmg" ? "Team: " + ((int)tD).ToString("N0") + " damage" : tab == "ko" ? "Team: " + (int)tK + " knockouts" : "Control = seconds enemies spent stopped or slowed (stronger slows count more)", 12, DIM));
        }
        /* map under the one-row top bar, the team row right under the map, the bar shrinking to fit */
        // the map is made in the shape of the space it gets: the screen below the top bar (the team row floats over the map)
        // (bar height measured in the last battle; the first battle uses a typical size)
        static float hudSpace = 54;
        static float PlayAspect()
        {
            float w = Root != null ? Root.layout.width : 0, h = Root != null ? Root.layout.height : 0;
            if (float.IsNaN(w) || w <= 0 || float.IsNaN(h) || h <= 0) return MapGen.ScreenAspect();
            h = Mathf.Max(1, h - hudSpace); return Mathf.Max(w, h) / Mathf.Min(w, h);
        }
        static void BattleLayout()
        {
            if (hud == null || hud.layout.width <= 0 || Root.layout.width <= 0) return;
            // the bar's natural width = its items side by side (the bar itself can be squeezed by the screen edge, so it isn't measured)
            float need = hud.resolvedStyle.paddingLeft + hud.resolvedStyle.paddingRight + hud.resolvedStyle.borderLeftWidth + hud.resolvedStyle.borderRightWidth;
            foreach (var c in hud.Children()) if (c.resolvedStyle.position != Position.Absolute) need += c.layout.width + c.resolvedStyle.marginLeft + c.resolvedStyle.marginRight;
            float W = Root.layout.width, k = need > W - 12 ? (W - 12) / need : 1;
            hud.style.width = need;   // full natural width; the scale below makes it fit the screen
            hud.style.scale = new Scale(new Vector3(k, k, 1));
            float top = hud.layout.y + hud.layout.height * k + 4, teamH = teamSV != null ? teamSV.layout.height + 10 : 0;
            if (top > 10) hudSpace = top;
            stage.style.top = top; stage.style.bottom = 0; stage.style.height = StyleKeyword.Auto;   // the map takes everything under the bar
            if (bossBar != null) bossBar.style.top = top + 2;
            // the team row floats over the bottom edge of the map (the camera shows exactly the map, top-aligned in the stage)
            var mr = View.MapRectPanel(W, Root.layout.height);
            if (bottomBox != null && mr.height > 0)
            {
                float infoH = info != null && info.style.display == DisplayStyle.Flex ? info.layout.height + 4 : 0;
                bottomBox.style.bottom = StyleKeyword.Auto; bottomBox.style.top = Mathf.Min(mr.yMax, Root.layout.height) - teamH - infoH;
            }
        }
        /* ---------- per frame ---------- */
        static bool lastPortrait; static Vector2Int lastSize;
        public static void Tick(float dt)
        {
            var size = new Vector2Int(Screen.width, Screen.height);
            if (size != lastSize) { lastSize = size; if (Settings != null) Settings.scale = UiScale(); }
            screenTick?.Invoke(dt);
            var B = Battle.B; if (!InBattle || B == null) return;
            // keep the battle camera inside the stage area
            if (stage != null && stage.panel != null && Root.layout.width > 0)
            {
                float sc = Screen.width / Root.layout.width; var wb = stage.worldBound;
                View.viewport = new Rect(wb.x * sc / Screen.width, (Screen.height - wb.yMax * sc) / Screen.height, wb.width * sc / Screen.width, wb.height * sc / Screen.height);
            }
            // turned the phone: same map, flipped to fit
            if (Portrait != lastPortrait)
            {
                lastPortrait = Portrait;
                if (Portrait != B.portrait)
                {
                    B.portrait = Portrait; B.M = MapGen.Gen(B.set, B.portrait, B.seed, null, B.aspect, B.tier); View.ResetZoom();
                    foreach (var t in B.towers) { var x = t.x; t.x = t.y; t.y = x; }
                    foreach (var e in B.en) { e.placed = false; }
                }
                BuildBattle();
            }
            if (B.asks.Count > 0 && !ModalOpen) AskJoin();
            BattleLayout();
            meterT -= dt; if (meterT <= 0 && Save.G.meter && meterBox != null && !meterHold) { meterT = 0.5f; MeterDraw(meterBox, meterTab, false); }
            hudT -= dt;
            if (hudT <= 0)
            {
                hudT = 0.15f; RefreshHud();
                string k = B.sel != null ? B.sel.e.lv + ":" + B.sel.kills + ":" + B.sel.e.id + ":" + string.Join("", B.sel.up) + ":" + (B.cash >= Battle.UpgradeCost(B.sel, 0) ? 1 : 0) + (B.cash >= Battle.UpgradeCost(B.sel, 1) ? 1 : 0) + (B.cash >= Battle.UpgradeCost(B.sel, 2) ? 1 : 0) : B.selE != null ? "e" + B.selE.GetHashCode() + ":" + (int)B.selE.hp : B.placing != null ? "p" : "";
                if (k != infoKey) { infoKey = k; TowerInfo(); }
            }
        }
    }
}
