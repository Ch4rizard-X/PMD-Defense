// Route Defense — game data (from the user's ROMs, SpriteCollab and PokeAPI) and the Pokémon maths.
using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace RouteDefense
{
    public class Evo { public int to, tr, lv, item; public bool happy, move; }
    public class Species
    {
        public int id, cr, g, gr, x, f, lg, bst; public bool bb, anim;
        public string n; public int[] t, b; public List<Evo> ev = new List<Evo>();
        public List<int[]> ls = new List<int[]>();      // [level, move]
        public List<int[]> ab = new List<int[]>();      // [ability, hidden]
    }
    public class Move
    {
        public int id, t, p, pp, a, c, tg, pr, ac, dr, hl, cr, fl, cat, sch; public string n, ai;
        public int[] h; public List<int[]> sc = new List<int[]>();
    }
    public class AnimMeta { public int fw, fh, n, r, hit, y; public int[] d; public float[][] sh; public int Total; }
    public class FxAnim { public string f; public int fw, fh, n, r; public int[] d; public int Total; public float ox = -1, oy = -1; }   // ox/oy: anchor point inside the frame (Explorers of Sky sheets); -1 = centre
    public class MoveFx { public string u, p, h; }
    public class Setting { public string name, game, ts, liq; public int cols; public int[] types; public int[] rules; }
    public class Named { public string k, n, d; }
    public class RescueNode { public string id, br, path, name, desc; public int cost; public string[] req; public Dictionary<string, float> eff = new Dictionary<string, float>(); }
    public class Branch { public string id, name, blurb; }
    public class WxMeta { public int n, fw, fh, per, ms; public string blend; }
    public class Nature { public int id, up, dn; public string k, n; }
    public class Tool { public int id, nat; public string k, n, kind; }

    public static class DB
    {
        public static readonly string[] TYPES = { "Normal", "Fighting", "Flying", "Poison", "Ground", "Rock", "Bug", "Ghost", "Steel", "Fire", "Water", "Grass", "Electric", "Psychic", "Ice", "Dragon", "Dark", "Fairy" };
        public static readonly string[] TCOL = { "#a8a878", "#c03028", "#a890f0", "#a040a0", "#e0c068", "#b8a038", "#a8b820", "#705898", "#b8b8d0", "#f08030", "#6890f0", "#78c850", "#f8d030", "#f85888", "#98d8d8", "#7038f8", "#705848", "#ee99ac" };
        public static Dictionary<int, Species> SP = new Dictionary<int, Species>();
        public static List<Species> Mons = new List<Species>();
        public static Dictionary<int, Move> Moves = new Dictionary<int, Move>();
        public static float[,] Chart = new float[18, 18];
        public static Dictionary<int, int[]> XP = new Dictionary<int, int[]>();
        public static Dictionary<int, string> Items = new Dictionary<int, string>();
        public static Dictionary<int, Named> Abil = new Dictionary<int, Named>();
        public static Dictionary<int, Named> Held = new Dictionary<int, Named>();
        public static Dictionary<int, Dictionary<string, AnimMeta>> Anim = new Dictionary<int, Dictionary<string, AnimMeta>>();
        public static Dictionary<string, FxAnim> FxAnims = new Dictionary<string, FxAnim>();
        public static Dictionary<int, MoveFx> FxMoves = new Dictionary<int, MoveFx>();
        public static List<Setting> TS = new List<Setting>();
        public static Dictionary<string, string> Music = new Dictionary<string, string>(), Sfx = new Dictionary<string, string>();
        public static Dictionary<int, string> BossTheme = new Dictionary<int, string>();   // bosses with their own song in the ROMs
        public static List<RescueNode> Tree = new List<RescueNode>(); public static List<Branch> Branches = new List<Branch>();
        public static Dictionary<int, string> Icons = new Dictionary<int, string>();
        public static Dictionary<string, WxMeta> Wx = new Dictionary<string, WxMeta>();
        public static List<Nature> Nat = new List<Nature>(); public static Dictionary<int, Tool> Tools = new Dictionary<int, Tool>();
        public static Dictionary<int, int> Mk = new Dictionary<int, int>();
        public static Dictionary<int, int> MIcon = new Dictionary<int, int>(); public static int MIconCols = 32, MIconCell = 40;   // one shared icon sheet (cell index per species)   // marker size per species (SpriteCollab ShadowSize: 0 small, 1 medium, 2 large)

        static object Load(string name) => Json.Parse(Resources.Load<TextAsset>("Data/" + name).text);

        public static void LoadAll()
        {
            var anim = Json.O(Load("anim"));
            foreach (var kv in anim)
            {
                var m = new Dictionary<string, AnimMeta>();
                foreach (var a in Json.O(kv.Value))
                {
                    var o = Json.O(a.Value);
                    var am = new AnimMeta { fw = Json.GI(o, "fw"), fh = Json.GI(o, "fh"), n = Json.GI(o, "n"), r = Json.GI(o, "r"), hit = Json.GI(o, "hit"), y = Json.GI(o, "y"), d = Json.IA(Json.Get(o, "d")) };
                    var sh = Json.A(Json.Get(o, "sh"));
                    if (sh != null) am.sh = sh.Select(p => Json.FA(p)).ToArray();
                    am.Total = Math.Max(1, am.d.Sum());
                    m[a.Key] = am;
                }
                Anim[int.Parse(kv.Key)] = m;
            }
            var dex = Json.O(Load("dex"));
            foreach (var mo in Json.A(dex["mon"]))
            {
                var o = Json.O(mo);
                var s = new Species
                {
                    id = Json.GI(o, "id"), n = Json.S(o["n"]), t = Json.IA(o["t"]), b = Json.IA(o["b"]), cr = Json.GI(o, "cr"), g = Json.GI(o, "g"),
                    gr = Json.GI(o, "gr"), x = Json.GI(o, "x"), f = Json.GI(o, "f"), lg = Json.GI(o, "lg"), bb = Json.GI(o, "bb") == 1
                };
                foreach (var e in Json.A(o["ev"])) { var eo = Json.O(e); s.ev.Add(new Evo { to = Json.GI(eo, "to"), tr = Json.GI(eo, "tr"), lv = Json.GI(eo, "lv"), item = Json.GI(eo, "item"), happy = eo.ContainsKey("happy"), move = eo.ContainsKey("move") }); }
                foreach (var l in Json.A(o["ls"])) s.ls.Add(Json.IA(l));
                foreach (var l in Json.A(Json.Get(o, "ab")) ?? new List<object>()) s.ab.Add(Json.IA(l));
                s.bst = s.b.Sum(); s.anim = Anim.ContainsKey(s.id);
                SP[s.id] = s; Mons.Add(s);
            }
            foreach (var kv in Json.O(dex["moves"]))
            {
                var o = Json.O(kv.Value);
                var m = new Move
                {
                    id = int.Parse(kv.Key), n = Json.S(o["n"]), t = Json.GI(o, "t"), p = Json.GI(o, "p"), pp = Json.GI(o, "pp"), a = Json.GI(o, "a"), c = Json.GI(o, "c"),
                    tg = Json.GI(o, "tg"), pr = Json.GI(o, "pr"), ai = Json.S(o["ai"]), ac = Json.GI(o, "ac"), h = Json.IA(o["h"]), dr = Json.GI(o, "dr"), hl = Json.GI(o, "hl"),
                    cr = Json.GI(o, "cr"), fl = Json.GI(o, "fl"), cat = Json.GI(o, "cat"), sch = Json.GI(o, "sch")
                };
                foreach (var x in Json.A(Json.Get(o, "sc")) ?? new List<object>()) m.sc.Add(Json.IA(x));
                Moves[m.id] = m;
            }
            var ch = Json.A(dex["chart"]);
            for (int i = 0; i < 18; i++) { var r = Json.FA(ch[i]); for (int j = 0; j < 18; j++) Chart[i, j] = r[j]; }
            foreach (var kv in Json.O(dex["xp"])) XP[int.Parse(kv.Key)] = Json.IA(kv.Value);
            foreach (var kv in Json.O(dex["items"])) Items[int.Parse(kv.Key)] = Json.S(kv.Value);
            foreach (var kv in Json.O(dex["abil"])) { var o = Json.O(kv.Value); Abil[int.Parse(kv.Key)] = new Named { k = Json.S(o["k"]), n = Json.S(o["n"]), d = Json.S(o["d"]) }; }
            foreach (var kv in Json.O(dex["held"])) { var o = Json.O(kv.Value); Held[int.Parse(kv.Key)] = new Named { k = Json.S(o["k"]), n = Json.S(o["n"]), d = Json.S(o["d"]) }; }
            foreach (var x in Json.A(dex["nat"])) { var o = Json.O(x); Nat.Add(new Nature { id = Json.GI(o, "id"), k = Json.S(o["k"]), n = Json.S(o["n"]), up = Json.GI(o, "up"), dn = Json.GI(o, "dn") }); }
            foreach (var kv in Json.O(dex["tools"])) { var o = Json.O(kv.Value); Tools[int.Parse(kv.Key)] = new Tool { id = int.Parse(kv.Key), k = Json.S(o["k"]), n = Json.S(o["n"]), kind = Json.S(o["kind"]), nat = Json.GI(o, "nat") }; }
            foreach (var t in Json.A(Load("ts")))
            {
                var o = Json.O(t);
                TS.Add(new Setting { name = Json.S(o["name"]), game = Json.S(o["game"]), ts = Json.S(o["ts"]), cols = Json.GI(o, "cols"), types = Json.IA(o["types"]), liq = Json.S(o["liq"]), rules = Json.IA(o["rules"]) });
            }
            var fx = Json.O(Load("fx"));
            foreach (var kv in Json.O(fx["anims"])) { var o = Json.O(kv.Value); var a = new FxAnim { f = Json.S(o["f"]), fw = Json.GI(o, "fw"), fh = Json.GI(o, "fh"), n = Json.GI(o, "n"), r = Json.GI(o, "r"), d = Json.IA(o["d"]), ox = o.ContainsKey("ox") ? Json.GI(o, "ox") : -1, oy = o.ContainsKey("oy") ? Json.GI(o, "oy") : -1 }; a.Total = Math.Max(1, a.d.Sum()); FxAnims[kv.Key] = a; }
            foreach (var kv in Json.O(fx["moves"])) { var o = Json.O(kv.Value); FxMoves[int.Parse(kv.Key)] = new MoveFx { u = Json.Get(o, "u") as string, p = Json.Get(o, "p") as string, h = Json.Get(o, "h") as string }; }
            var snd = Json.O(Load("snd"));
            foreach (var kv in Json.O(snd["music"])) Music[kv.Key] = Json.S(kv.Value);
            var bt = Json.Get(snd, "bossTheme"); if (bt != null) foreach (var kv in Json.O(bt)) BossTheme[int.Parse(kv.Key)] = Json.S(kv.Value);
            foreach (var kv in Json.O(snd["sfx"])) Sfx[kv.Key] = Json.S(kv.Value);
            var tree = Json.O(Load("tree"));
            foreach (var b in Json.A(tree["branches"])) { var o = Json.O(b); Branches.Add(new Branch { id = Json.S(o["id"]), name = Json.S(o["name"]), blurb = Json.S(o["blurb"]) }); }
            foreach (var nd in Json.A(tree["nodes"]))
            {
                var o = Json.O(nd);
                var n = new RescueNode { id = Json.S(o["id"]), br = Json.S(o["br"]), path = Json.S(o["path"]), name = Json.S(o["name"]), desc = Json.S(o["desc"]), cost = Json.GI(o, "cost"), req = Json.A(o["req"]).Select(x => Json.S(x)).ToArray() };
                foreach (var kv in Json.O(o["eff"])) n.eff[kv.Key] = Json.F(kv.Value);
                Tree.Add(n);
            }
            foreach (var kv in Json.O(Load("icons"))) Icons[int.Parse(kv.Key)] = Json.S(kv.Value);
            foreach (var kv in Json.O(Load("mk"))) Mk[int.Parse(kv.Key)] = Json.I(kv.Value);
            var mi = Json.O(Load("micons")); MIconCols = Json.GI(mi, "cols"); MIconCell = Json.GI(mi, "c"); foreach (var kv in Json.O(mi["i"])) MIcon[int.Parse(kv.Key)] = Json.I(kv.Value);
            foreach (var kv in Json.O(Load("wx"))) { var o = Json.O(kv.Value); Wx[kv.Key] = new WxMeta { n = Json.GI(o, "n"), fw = Json.GI(o, "fw"), fh = Json.GI(o, "fh"), per = Json.GI(o, "per"), ms = Json.GI(o, "ms"), blend = Json.S(o["blend"]) }; }
        }

        /* ---------- Pokémon maths: main-series stat formula, IVs 0-31, nature x1.1 / x0.9 on one stat each (no EVs) ---------- */
        public static int[] CalcStats(int id, int lv, int[] iv = null, int nat = 0)
        {
            var b = SP[id].b; var r = new int[6]; var N = nat > 0 && nat <= Nat.Count ? Nat[nat - 1] : null;
            for (int i = 0; i < 6; i++)
            {
                int I = iv != null ? iv[i] : 15;
                if (i == 0) { r[i] = (2 * b[i] + I) * lv / 100 + lv + 10; continue; }
                int st = (2 * b[i] + I) * lv / 100 + 5;
                r[i] = N != null && N.up != N.dn ? (int)Math.Floor(st * (i == N.up ? 1.1 : i == N.dn ? 0.9 : 1)) : st;
            }
            return r;
        }
        public static int[] RollIV() { var a = new int[6]; for (int i = 0; i < 6; i++) a[i] = UnityEngine.Random.Range(0, 32); return a; }
        public static int RollNat() => UnityEngine.Random.Range(1, 26);
        public static int[] IvsOf(Mon e) { var a = new int[6]; for (int i = 0; i < 6; i++) a[i] = e.ht != null && e.ht.Length == 6 && e.ht[i] != 0 ? 31 : e.iv[i]; return a; }   // Bottle Caps raise a stat as if its IV were 31 (like Hyper Training)
        public static int NatOf(Mon e) => e.mint != 0 ? e.mint : e.nat;                 // a Mint changes how the nature affects stats; the nature itself stays
        public static int[] MonStats(Mon e) => CalcStats(e.id, e.lv, IvsOf(e), NatOf(e));
        public static readonly string[] STATN = { "HP", "Atk", "Def", "SpA", "SpD", "Spe" };
        public static string NatLabel(int n) { var N = Nat[n - 1]; return N.up == N.dn ? N.n + " (neutral)" : N.n + " (+" + STATN[N.up] + " -" + STATN[N.dn] + ")"; }
        public static readonly Dictionary<string, int> TOOL_PRICE = new Dictionary<string, int> { { "mint", 2000 }, { "bottle-cap", 5000 }, { "gold-bottle-cap", 25000 } };
        // Flying types whose only movement animation is a ground walk (no flight frames in SpriteCollab): they walk the path
        public static readonly HashSet<int> GROUND_FLYERS = new HashSet<int> { 6, 149, 123, 163, 178, 188, 83, 84, 85, 225, 566, 629, 701, 722, 723, 741, 845 };
        public static int XpFor(int gr, int lv) { var t = XP[gr]; return t[Math.Min(100, lv)]; }
        public const int MAXLV = 100;
        public static Move Mv(int id) => Moves.TryGetValue(id, out var m) ? m : null;
        public static readonly string[] AILMENTS = { "paralysis", "sleep", "freeze", "burn", "poison", "confusion", "trap", "yawn", "leech-seed" };

        public static List<int> MovesAt(int id, int lv)
        {
            var o = new List<int>();
            foreach (var l in SP[id].ls) if (l[0] <= lv && Moves.ContainsKey(l[1]) && !o.Contains(l[1])) { o.Add(l[1]); if (o.Count > 4) o.RemoveAt(0); }
            return o;
        }
        public static List<int> NewMovesAt(int id, int lv) => SP[id].ls.Where(l => l[0] == lv && Moves.ContainsKey(l[1])).Select(l => l[1]).ToList();
        public static List<int> LearnedBy(int id, int lv) { var s = new List<int>(); foreach (var l in SP[id].ls) if (l[0] <= lv && Moves.ContainsKey(l[1]) && !s.Contains(l[1])) s.Add(l[1]); return s; }

        /* how a tower can use a move: "dmg" | "status" | "debuff" | "buff" | null */
        public static string MoveUse(int id)
        {
            var m = Mv(id); if (m == null) return null;
            if (m.c != 1) return "dmg";
            if (AILMENTS.Contains(m.ai) && m.tg != 7) return "status";
            if (m.tg != 7 && m.sc.Any(s => s[1] < 0 && (s[0] == 3 || s[0] == 5 || s[0] == 6))) return "debuff";
            if (m.sc.Any(s => s[1] > 0 && (s[0] == 2 || s[0] == 4 || s[0] == 6))) return "buff";
            return null;
        }
        public static string MoveDesc(int id)
        {
            var m = Mv(id); var u = MoveUse(id);
            string k = m.c == 2 ? "Physical" : m.c == 3 ? "Special" : "Status";
            string s = TYPES[m.t] + " - " + k;
            if (m.c != 1) s += " - Pow " + (m.p > 0 ? m.p.ToString() : "-");
            if (m.a > 0) s += " - Acc " + m.a;
            s += " - PP " + m.pp;
            string sk = Battle.SkillDesc(m.n); if (sk != null) s += " - " + sk; else if (u == null) s += " - (no use in battle)";
            if (id == 206) s += " - Knockouts with it are 3x as likely to ask to join";
            return s;
        }
        public static float MoveValue(int id, int sp)
        {
            var m = Mv(id); var u = MoveUse(id); if (u == null) return 0;
            var b = SP[sp].b; float mx = Math.Max(b[1], b[3]);
            float side = m.c == 2 ? b[1] / mx : m.c == 3 ? b[3] / mx : 1;
            if (u == "dmg") return (m.p > 0 ? m.p : 55) * side * (m.c == 3 ? 1.15f : 1) * (SP[sp].t.Contains(m.t) ? 1.5f : 1) * ((m.a > 0 ? m.a : 100) / 100f) * ((m.h[0] + m.h[1]) / 2f) * (m.tg == 9 || m.tg == 11 ? 1.3f : 1);
            if (u == "status") return m.ai == "sleep" || m.ai == "freeze" || m.ai == "trap" ? 50 : 35;
            return u == "buff" ? 30 : 20;
        }
        public static List<int> BestMoves(int id, int lv)
        {
            var all = LearnedBy(id, lv).OrderByDescending(m => MoveValue(m, id)).ToList();
            var o = new List<int>();
            foreach (var m in all)
            {
                if (o.Count >= 4) break;
                int k = Mv(m).t;
                if (MoveUse(m) == "dmg" && all.Count > 6 && o.Count(x => Mv(x).t == k) >= 2) continue;
                o.Add(m);
            }
            return o.Count > 0 ? o : MovesAt(id, lv);
        }
        public static float Eff(int t, int[] def) { float f = 1; foreach (var d in def) f *= Chart[t, d]; return f; }

        /* ---------- abilities: real ones; these have a tower-defense meaning ---------- */
        public static readonly Dictionary<string, string> AB_TD = new Dictionary<string, string>
        {
            {"overgrow","Grass moves x1.5 when your lives are at 1/3 or less"},{"blaze","Fire moves x1.5 when your lives are at 1/3 or less"},
            {"torrent","Water moves x1.5 when your lives are at 1/3 or less"},{"swarm","Bug moves x1.5 when your lives are at 1/3 or less"},
            {"compound-eyes","Accuracy x1.3"},{"hustle","Physical moves x1.5, accuracy x0.8"},{"huge-power","Physical moves x2"},{"pure-power","Physical moves x2"},
            {"adaptability","Same-type bonus is x2 instead of x1.5"},{"technician","Moves with 60 power or less x1.5"},{"skill-link","Multi-hit moves always hit the most times"},
            {"serene-grace","Added effects happen twice as often"},{"sniper","Critical hits do x2.25"},{"super-luck","Critical hits more likely"},
            {"sheer-force","Moves with added effects x1.3, but the effects are lost"},{"tinted-lens","\"Not very effective\" hits do double"},
            {"tough-claws","Physical moves x1.3"},{"no-guard","Moves never miss"},{"keen-eye","Can see hidden Pokémon"},{"frisk","Can see hidden Pokémon"},
            {"scrappy","Normal and Fighting moves hit Ghost types"},{"speed-boost","Attacks faster the longer a wave goes on"},
            {"static","Wild Pokémon walking close by may be paralyzed"},{"flame-body","Wild Pokémon walking close by may be burned"},
            {"poison-point","Wild Pokémon walking close by may be poisoned"},{"effect-spore","Wild Pokémon walking close by may be poisoned, paralyzed or put to sleep"},
            {"swift-swim","Attacks x1.5 faster when standing in water"},{"levitate","Wild: flies over the path; immune to Ground moves"},
            {"flash-fire","Wild: immune to Fire moves"},{"water-absorb","Wild: immune to Water moves"},{"storm-drain","Wild: immune to Water moves"},{"dry-skin","Wild: immune to Water moves, takes x1.25 from Fire"},
            {"volt-absorb","Wild: immune to Electric moves"},{"lightning-rod","Wild: immune to Electric moves"},{"motor-drive","Wild: immune to Electric moves"},
            {"sap-sipper","Wild: immune to Grass moves"},{"wonder-guard","Wild: only super-effective hits do damage"},{"sturdy","Wild: survives one knockout hit at full HP"},
            {"thick-fat","Wild: takes half from Fire and Ice"},{"heatproof","Wild: takes half from Fire"},{"filter","Wild: super-effective hits x0.75"},{"solid-rock","Wild: super-effective hits x0.75"},
            {"prism-armor","Wild: super-effective hits x0.75"},{"multiscale","Wild: takes half damage at full HP"},{"shadow-shield","Wild: takes half damage at full HP"},
            {"magic-guard","Wild: no damage from burn, poison or traps"},{"insomnia","Wild: can't fall asleep"},{"vital-spirit","Wild: can't fall asleep"},
            {"limber","Wild: can't be paralyzed"},{"immunity","Wild: can't be poisoned"},{"water-veil","Wild: can't be burned"},{"own-tempo","Wild: can't be confused"},
            {"oblivious","Wild: can't be confused"},{"magma-armor","Wild: can't be frozen"},{"shield-dust","Wild: added effects don't happen to it"},
            {"clear-body","Wild: stats can't be lowered"},{"white-smoke","Wild: stats can't be lowered"},{"full-metal-body","Wild: stats can't be lowered"},
            {"battle-armor","Wild: can't take critical hits"},{"shell-armor","Wild: can't take critical hits"},{"quick-feet","Wild: x1.5 speed while it has a status"},
            {"chlorophyll","Attacks x1.5 faster in sun"},{"sand-rush","Attacks x1.5 faster in a sandstorm"},{"slush-rush","Attacks x1.5 faster in hail"},{"solar-power","Special moves x1.5 in sun"},
        };
        public static string AbKey(int a) => a != 0 && Abil.TryGetValue(a, out var n) ? n.k : "";
        public static int RollAbility(int id, float hid)
        {
            var l = SP[id].ab; var nor = l.Where(x => x[1] == 0).ToList(); var hi = l.Where(x => x[1] == 1).ToList();
            if (hi.Count > 0 && UnityEngine.Random.value < hid) return hi[0][0];
            return nor.Count > 0 ? nor[UnityEngine.Random.Range(0, nor.Count)][0] : (l.Count > 0 ? l[0][0] : 0);
        }
        public static int AbilityAfterEvolve(int from, int to, int a)
        {
            var fl = SP[from].ab; var tl = SP[to].ab; int i = fl.FindIndex(x => x[0] == a);
            if (i >= 0 && i < tl.Count && tl[i][1] == fl[i][1]) return tl[i][0];
            int want = i >= 0 ? fl[i][1] : 0; var m = tl.FirstOrDefault(x => x[1] == want) ?? (tl.Count > 0 ? tl[0] : null);
            return m != null ? m[0] : a;
        }

        /* ---------- held items: real items; what each does here ---------- */
        public static readonly Dictionary<string, int> TYPE_ITEM = new Dictionary<string, int> {
            {"charcoal",9},{"mystic-water",10},{"miracle-seed",11},{"magnet",12},{"never-melt-ice",14},{"black-belt",1},{"poison-barb",3},{"soft-sand",4},{"sharp-beak",2},
            {"twisted-spoon",13},{"silver-powder",6},{"hard-stone",5},{"spell-tag",7},{"dragon-fang",15},{"black-glasses",16},{"metal-coat",8},{"silk-scarf",0},{"fairy-feather",17} };
        public static readonly Dictionary<string, string> HELD_TD = new Dictionary<string, string> {
            {"choice-band","Physical moves x1.5, but only its first move is used"},{"choice-specs","Special moves x1.5, but only its first move is used"},
            {"choice-scarf","Attacks x1.5 faster, but only its first move is used"},{"life-orb","All damage x1.3"},{"expert-belt","Super-effective hits x1.2"},
            {"scope-lens","Critical hits more likely"},{"razor-claw","Critical hits more likely"},{"wide-lens","Accuracy x1.1"},{"zoom-lens","Accuracy x1.2"},
            {"quick-claw","Sometimes attacks again right away"},{"kings-rock","10% chance to make the target flinch"},{"razor-fang","10% chance to make the target flinch"},
            {"muscle-band","Physical moves x1.1"},{"wise-glasses","Special moves x1.1"},{"light-clay","Its stat boosts and drops last twice as long"},
            {"binding-band","Trapping moves do double damage over time"},{"lucky-egg","Earns x1.5 XP"},{"amulet-coin","Knockouts by it earn double ₽"},
            {"metronome","Using the same move again and again: up to x2 damage"} };
        public static readonly HashSet<string> HELD_RARE = new HashSet<string> { "choice-band", "choice-specs", "choice-scarf", "life-orb", "expert-belt" };
        static DB() { foreach (var kv in TYPE_ITEM) HELD_TD[kv.Key] = TYPES[kv.Value] + " moves x1.2"; }
        public static string HeldKey(Mon e) => e != null && e.it != 0 && Held.TryGetValue(e.it, out var h) ? h.k : "";
        public static int HeldPrice(string k) => HELD_RARE.Contains(k) ? 0 : k == "lucky-egg" || k == "amulet-coin" ? 8000 : 3000;

        public class EvoOpt { public int to, item; public bool ok; public string why; }
        public static List<EvoOpt> EvoOptions(Mon e)
        {
            var o = new List<EvoOpt>();
            foreach (var v in SP[e.id].ev)
            {
                if (!SP.TryGetValue(v.to, out var t) || !t.anim) continue;
                bool ok; string why;
                if (v.tr == 1) { int need = v.lv > 0 ? v.lv : v.happy ? 22 : v.move ? 32 : 30; ok = e.lv >= need; why = "Lv " + need; }
                else if (v.tr == 2) { ok = e.lv >= 36; why = "Lv 36"; }
                else if (v.tr == 3) { ok = Save.G.Count(Save.G.items, v.item) > 0; why = Items.TryGetValue(v.item, out var nm) ? nm : "item"; }
                else { ok = e.lv >= 30; why = "Lv 30"; }
                o.Add(new EvoOpt { to = v.to, ok = ok, why = why, item = v.tr == 3 ? v.item : 0 });
            }
            return o;
        }
        public static int PlaceCost(Mon e) => Mathf.RoundToInt((40 + SP[e.id].bst * 0.25f + e.lv * 2.5f) * (1 + Rescue.Mod("placeCost")) * (SP[e.id].t.Contains(0) ? 0.9f : 1));   // Normal: Thrifty
    }

    /* ---------- save ---------- */
    [Serializable] public class Mon { public int u, id, lv, xp, ab, it, nat, mint; public int[] iv, ht; public List<int> mv = new List<int>(), pend = new List<int>(); }
    [Serializable] public class Pair { public int k, v; }
    [Serializable]
    public class SaveData
    {
        public int v = 2, uid = 1, money, maps, wins, rp; public bool mute; public string ui = "m";   // menu size option
        public bool smooth = true, lowres = true, meter; public float mx = -1, my = -1;   // 60 fps; lower resolution (cooler phone); damage meter on, and where it was dragged (share of the screen)
        public int gfx;   // graphics options version (0 in old saves and new ones): older saves get the new defaults once
        public List<string> tree = new List<string>();
        public List<Pair> mt = new List<Pair> { new Pair { k = 0, v = 1 } };   // per-map tiers: map -> highest tier you can pick (missing = map not open)
        public List<int> mtDone = new List<int>();                             // maps with tier 20 cleared
        public List<Pair> stars = new List<Pair>();                            // key = map * 100 + tier
        public List<Pair> tools = new List<Pair>();                            // Mints and Bottle Caps
        public List<Mon> box = new List<Mon>(); public List<int> team = new List<int>(), seen = new List<int>(), own = new List<int>();
        public List<Pair> items = new List<Pair>(), held = new List<Pair>();
        public int Count(List<Pair> l, int k) { var p = l.Find(x => x.k == k); return p != null ? p.v : 0; }
        public void Add(List<Pair> l, int k, int d) { var p = l.Find(x => x.k == k); if (p == null) { p = new Pair { k = k }; l.Add(p); } p.v += d; if (p.v <= 0) l.Remove(p); }
        public bool Seen(int id) => seen.Contains(id); public bool Own(int id) => own.Contains(id);
        public void See(int id) { if (!seen.Contains(id)) seen.Add(id); }
        public void Got(int id) { See(id); if (!own.Contains(id)) own.Add(id); }
    }
    public static class Save
    {
        public static SaveData G;
        const string KEY = "routedef_v1";
        public static void Write() { if (G != null) { PlayerPrefs.SetString(KEY, JsonUtility.ToJson(G)); PlayerPrefs.Save(); } }
        public static void Load()
        {
            var s = PlayerPrefs.GetString(KEY, ""); G = string.IsNullOrEmpty(s) ? new SaveData() : JsonUtility.FromJson<SaveData>(s);
            if (G.v < 2) G = new SaveData();   // per-map tiers: saves from before start over (same as the HTML version)
            if (G.gfx < 1) { G.smooth = true; G.lowres = true; G.gfx = 1; }   // the old Battery saver became two options: 60 fps and Lower resolution, both on
            if (G.tree == null) G.tree = new List<string>(); if (G.stars == null) G.stars = new List<Pair>(); if (G.tools == null) G.tools = new List<Pair>();
            if (G.mt == null || G.mt.Count == 0) G.mt = new List<Pair> { new Pair { k = 0, v = 1 } }; if (G.mtDone == null) G.mtDone = new List<int>();
            foreach (var e in G.box) { if (e.nat == 0) e.nat = DB.RollNat(); if (e.iv == null || e.iv.Length != 6) e.iv = DB.RollIV(); if (e.ht == null || e.ht.Length != 6) e.ht = new int[6]; }
            Rescue.Dirty();
        }
        public static void Delete() { PlayerPrefs.DeleteKey(KEY); G = new SaveData(); Rescue.Dirty(); }

        public static Mon MakeMon(int id, int lv, int nat = 0, int[] iv = null)
        {
            var e = new Mon { u = G.uid++, id = id, lv = lv, xp = DB.XpFor(DB.SP[id].gr, lv), mv = DB.BestMoves(id, lv), ab = DB.RollAbility(id, 0.05f),
                nat = nat != 0 ? nat : DB.RollNat(), iv = iv != null ? (int[])iv.Clone() : DB.RollIV(), ht = new int[6] };
            G.Got(id); return e;
        }
        /* returns true when it levelled up */
        public static bool GiveXP(Mon e, int amt)
        {
            bool up = false; if (e.lv >= DB.MAXLV) return false;
            e.xp += amt;
            while (e.lv < DB.MAXLV && e.xp >= DB.XpFor(DB.SP[e.id].gr, e.lv + 1))
            {
                e.lv++; up = true;
                foreach (var m in DB.NewMovesAt(e.id, e.lv)) { if (e.mv.Contains(m) || e.pend.Contains(m)) continue; if (e.mv.Count < 4) e.mv.Add(m); else e.pend.Add(m); }
            }
            return up;
        }
        public static void Evolve(Mon e, int to, int item)
        {
            if (item != 0) G.Add(G.items, item, -1);
            e.ab = DB.AbilityAfterEvolve(e.id, to, e.ab); e.id = to; G.Got(to);
            foreach (var m in DB.NewMovesAt(to, 1).Concat(DB.NewMovesAt(to, e.lv))) { if (e.mv.Contains(m) || e.pend.Contains(m)) continue; if (e.mv.Count < 4) e.mv.Add(m); else e.pend.Add(m); }
        }
    }

    /* ---------- per-map tiers and map difficulty (like Bloons TD 6): the maps in opening order, in 4 groups ---------- */
    public static class Prog
    {
        public const int MAXTIER = 20;
        // name, colour, tiers added to every fight, reward multiplier, wild Pokémon per wave, tier to clear on any map of the group before to open this group
        static readonly string[] GNAME = { "Beginner", "Intermediate", "Advanced", "Expert" }, GCOL = { "#5fd068", "#ffd84a", "#ff9a3c", "#ff5a5a" };
        public static (string name, string col, int add, float pay, float count, int gate)[] GROUPS   // numbers come from the online settings (Cfg)
        {
            get { var c = Cfg.C; var g = new (string, string, int, float, float, int)[4]; for (int i = 0; i < 4; i++) g[i] = (GNAME[i], GCOL[i], c.groupAdd[i], c.groupPay[i], c.groupCount[i], c.groupGate[i]); return g; }
        }
        public static int MapGroup(int i) => Math.Min(3, i * 4 / Math.Max(1, DB.TS.Count));
        /* how hard a fight is, on the one-group tier scale: one long climb over all 4 groups, so each group's tier 1 matches the gate before it
           (Beginner 5 = Intermediate 1, Intermediate 10 = Advanced 1, Advanced 15 = Expert 1) and wild Lv 100 only arrives at Expert tier 20 */
        public static float Threat(int i, int t) => 1 + (t + Cfg.C.groupAdd[MapGroup(i)] - 1) * Cfg.C.threatStep;
        public static int GroupStart(int g) { for (int i = 0; i < DB.TS.Count; i++) if (MapGroup(i) == g) return i; return -1; }
        public static int Gate(int g) => Cfg.C.groupGate[g];
        public static int MapTier(int i) => Save.G.Count(Save.G.mt, i);          // highest tier you can pick on map i (0 = not open)
        public static bool MapOpen(int i) => MapTier(i) > 0;
        public static int BestTier() { int b = 0; foreach (var p in Save.G.mt) b = Math.Max(b, Save.G.mtDone.Contains(p.k) ? MAXTIER : p.v - 1); return b; }
        public static int Stars(int i, int t) => Save.G.Count(Save.G.stars, i * 100 + t);
        public static void SetTier(int i, int t) { var p = Save.G.mt.Find(x => x.k == i); if (p == null) Save.G.mt.Add(new Pair { k = i, v = t }); else p.v = t; }
        public static int OpenCount() => Save.G.mt.Count(p => p.v > 0);
        public static readonly Color[] COLS = { new Color32(0x5f, 0xd0, 0x68, 255), new Color32(0xff, 0xd8, 0x4a, 255), new Color32(0xff, 0x9a, 0x3c, 255), new Color32(0xff, 0x5a, 0x5a, 255) };
    }

    /* ---------- Rescue Points tree: owned nodes add up into small permanent bonuses ---------- */
    public static class Rescue
    {
        static Dictionary<string, float> mods;
        public static void Dirty() { mods = null; }
        public static Dictionary<string, float> Mods()
        {
            if (mods != null) return mods; mods = new Dictionary<string, float>();
            if (Save.G == null) return mods;
            foreach (var n in DB.Tree) if (Save.G.tree.Contains(n.id)) foreach (var kv in n.eff) mods[kv.Key] = (mods.TryGetValue(kv.Key, out var v) ? v : 0) + kv.Value;
            return mods;
        }
        public static float Mod(string k) => Mods().TryGetValue(k, out var v) ? v : 0;
        public static bool Owned(RescueNode n) => Save.G.tree.Contains(n.id);
        public static bool Open(RescueNode n) => !Owned(n) && n.req.All(r => Save.G.tree.Contains(r));
        public static bool Buy(RescueNode n) { if (!Open(n) || Save.G.rp < n.cost) return false; Save.G.rp -= n.cost; Save.G.tree.Add(n.id); Dirty(); Save.Write(); return true; }
        public static int Spent() => DB.Tree.Where(Owned).Sum(n => n.cost);
        public static int ResetCost() => Spent() * 100;
        public static bool Reset() { int c = ResetCost(); if (Save.G.money < c) return false; Save.G.money -= c; Save.G.rp += Spent(); Save.G.tree.Clear(); Dirty(); Save.Write(); return true; }
        public static int RpForClear(float tier) => 1 + (int)Math.Floor(tier * 0.6f);
        public static int ShopPrice(int p) => Mathf.RoundToInt(p * (1 + Mod("shop")));
    }
}
