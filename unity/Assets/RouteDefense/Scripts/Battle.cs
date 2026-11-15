// Route Defense — battle rules: waves, towers, moves, abilities, items, status, XP, recruiting (port of the HTML battle.js).
using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace RouteDefense
{
    public class SpawnDef { public int id, lv, r = -1; public float gap; public bool boss, minion; }
    public class Weather { public string k; public int until; public bool boss; public Enemy e; }   // until = last wave of your weather; boss weather lasts until its boss is knocked out
    public class Tower
    {
        public Mon e; public float x, y, at, cd = 0.3f, buft, sbt; public int dir, kills, paid, lastM, metro; public string anim = "Idle", mode = "first";
        public int[] buf = new int[7];   // stat stages by stat id (2 atk, 4 spa, 6 spe)
        public int[] up = new int[3];    // upgrade levels: range, attack speed, power
        // move skills: timers and timed boosts (Focus Energy, Take Heart, Double Team, Helping Hand, Tailwind, Speed Swap, Acupressure)
        public Dictionary<int, float> skc = new Dictionary<int, float>(); public float fe, thr, dteam, hh, tw, ssw, acuU, pt; public char acuK; public bool lf, chg, enc;
        public (int r, float d, float x, float y)? tp;   // nearest path spot for its traps
    }
    public class Enemy
    {
        public int id, lv, dir = 2, lives, ab, r, nat; public int[] st, iv; public float hp, max, d, x, y, spd, stt, imm, stgt, stop, at, hurt, sbt, lane, ph, sw, pace, rev, digt, dot, dead;
        public bool boss, air, hide, dig, under, armor, sturdy, bind, placed; public string sts, ak; public int[] stg = new int[7]; public Tower src;
        // tier traits (only from moves / abilities it really has) and boss moves
        public int[] bst = new int[7]; public float sh, shm, sht, shcd, tt, dt2, dash, rg, wdot, healHl; public int healMv, prot, dashMv, bwxm; public bool healed, regen, tele, minion;
        public string bwx; public List<int> bup = new List<int>(); public float btWx = 1, btUp = 4, btCall = 8;
        // type quirks and move skills
        public int pst; public float ptt, pd, wsl, chill, trF = 1, trU, tyoU, elz, akOff, gs, gsf = 1, pm, lure, back, nt, cuLeft, cuDps, cud; public bool fs, tyoAdd; public int[] tyoT; public string ak0;
        public Tower psrc, pmT, cuT; public HashSet<Tower> rk = new HashSet<Tower>(); public Dictionary<string, Vector2> sl = new Dictionary<string, Vector2>();
    }
    public class Proj { public float x, y, sp = 300, at; public Enemy tg; public FxAnim fx; public string hfx; public Action<Enemy> done; public bool hit; public int row; public float ang = float.NaN; }
    public class FxInst { public FxAnim a; public float x, y, t, rot; public int row; }
    public class Floater { public float x, y, t; public string txt; public int kind; }
    public class Ask { public int id, lv, ab, nat; public int[] iv; }

    public partial class Battle
    {
        public static Battle B;
        public static Action<string, int> Toast; public static Action TeamChanged, Finished, AskJoin;
        static readonly Dictionary<int, float> RANGE = new Dictionary<int, float> { { 2, 66 }, { 3, 106 }, { 1, 94 } };
        static float STAGE(int s) => s >= 0 ? (2 + s) / 2f : 2f / (2 - s);
        static readonly HashSet<int> OHKO = new HashSet<int> { 12, 32, 90, 329 };
        static readonly Dictionary<int, string> FIXED = new Dictionary<int, string> { { 69, "lv" }, { 101, "lv" }, { 82, "40" }, { 49, "20" }, { 162, "half" } };
        static float rnd => UnityEngine.Random.value;
        const int TZ = MapGen.TZ;

        public MapData M; public int set, tier, seed, wave, lives = 100, cash, kills, reward, rp, stars, starRp; public float th; public bool portrait, auto, over, paused, unlocked; public string mapOpened, groupOpened; public float aspect = 1.76f;
        public Weather weather, pwx, bwx;   // weather = what's in the sky now; pwx = yours; bwx = a boss's
        public List<Mon> team; public List<List<SpawnDef>> waves; public string phase = "build";
        public List<Tower> towers = new List<Tower>(); public List<Enemy> en = new List<Enemy>(); public List<Proj> proj = new List<Proj>();
        public List<FxInst> fx = new List<FxInst>(); public List<Floater> fl = new List<Floater>(); public List<SpawnDef> q = new List<SpawnDef>();
        public float qt, time; public int speed = 1; public Tower sel; public Enemy selE; public Mon placing;
        public List<Mon> recruits = new List<Mon>(); public List<Ask> asks = new List<Ask>(); public HashSet<int> declined = new HashSet<int>();
        public Dictionary<int, int> xpLog = new Dictionary<int, int>(); public int drop, hdrop;
        readonly List<(float t, Action fn)> q2 = new List<(float, Action)>();

        /* ---------- waves ---------- */
        public const float SPR = 1.5f, FXS = 1.5f;   // Pokémon and move effects are drawn bigger than their sheets so they read on any screen
        public const float ESPR = SPR * 0.9f;   // wild Pokémon are drawn 10% smaller than your team
        public const int MAXTIER = Prog.MAXTIER;
        public static int[] LvRange(float th) { var c = Cfg.C; int a = Mathf.Clamp(Mathf.RoundToInt(2 + (th - 1) * c.lvPerThreat), 2, 95); return new[] { a, Mathf.Clamp(a + Mathf.RoundToInt(c.lvSpread + th * c.lvSpreadPerThreat), 3, 100) }; }   // th = the fight's threat (Prog.Threat)
        /* tier traits: each one only for wild Pokémon that really know the move (or have the ability) at their level */
        static readonly HashSet<int> PROTECT_MOVES = new HashSet<int> { 182, 197, 588, 596, 661, 792, 852, 908 };   // Protect, Detect, King's / Spiky Shield, Baneful Bunker, Obstruct, Silk Trap, Burning Bulwark
        static readonly Dictionary<int, string> WX_MOVES = new Dictionary<int, string> { { 240, "rain" }, { 241, "sun" }, { 201, "sand" }, { 258, "hail" }, { 883, "hail" } };   // Rain Dance, Sunny Day, Sandstorm, Hail, Snowscape
        public static readonly (int tier, string what)[] TRAITS = { (3, "Ghost types hide, Dig users burrow, Steel / Rock armoured"), (5, "Legendary bosses"), (6, "Healers: self-healing moves restore HP once when low; Regenerator heals slowly"),
            (9, "Protect users raise a shield when hit"), (12, "Sprinters: speed-boosting and priority-move users dash"), (15, "Teleport users jump ahead along the path") };
        void WildTraits(Enemy e, int id, int lv, string ak)
        {
            float tier = th;
            var ms = DB.MovesAt(id, lv).Where(m => DB.Mv(m) != null).ToList();
            if (tier >= 6) { int h = ms.FirstOrDefault(m => DB.Mv(m).tg == 7 && DB.Mv(m).hl > 0); if (h != 0) { e.healMv = h; e.healHl = DB.Mv(h).hl / 100f; } if (ak == "regenerator") e.regen = true; }
            if (tier >= 9) e.prot = ms.FirstOrDefault(PROTECT_MOVES.Contains);
            if (tier >= 12) e.dashMv = ms.FirstOrDefault(m => { var M_ = DB.Mv(m); return (M_.tg == 7 && M_.sc.Any(c => c[0] == 6 && c[1] > 0)) || (M_.pr > 0 && M_.p > 0); });
            if (tier >= 15 && ms.Contains(100)) e.tele = true;
        }
        /* weather you can buy (and bosses can set) */
        public static readonly Dictionary<string, string[]> WEATHER = new Dictionary<string, string[]> {
            { "rain", new[] { "Rain", "Water moves stronger, Fire moves weaker. Thunder and Hurricane never miss." } },
            { "sun", new[] { "Harsh sunlight", "Fire moves stronger, Water moves weaker. Nothing freezes." } },
            { "sand", new[] { "Sandstorm", "Hurts wild Pokémon that aren't Rock, Ground or Steel. Rock types take less from special moves." } },
            { "hail", new[] { "Hail", "Hurts wild Pokémon that aren't Ice. Blizzard never misses." } } };
        public int WeatherCost() => Mathf.RoundToInt((120 + th * 25) * (1 + Rescue.Mod("weatherCost")));
        public static int WeatherWaves() => Cfg.C.weatherWaves + (int)Math.Floor((Rescue.Mod("weatherDur") + 1e-6f) / 0.3f);   // 3 waves, +1 for every 3 weather-duration nodes in the Rescue tree
        public bool BuyWeather(string k)   // bought during a wave, that wave counts as the first
        {
            int c = WeatherCost(); if (cash < c) return false; cash -= c;
            int first = phase == "wave" ? wave : wave + 1; pwx = new Weather { k = k, until = first + WeatherWaves() - 1 }; SyncWeather(); Gfx.Sfx("place"); return true;
        }
        public int WavesLeft() => pwx != null ? pwx.until - (phase == "wave" ? wave : wave + 1) + 1 : 0;
        void SyncWeather()   // what's in the sky: a living boss's weather, otherwise yours
        {
            if (bwx != null && !(bwx.e.hp > 0 && en.Contains(bwx.e))) bwx = null;
            weather = bwx != null ? new Weather { k = bwx.k, boss = true } : pwx != null ? new Weather { k = pwx.k } : mwx != null && mwxUntil > time ? new Weather { k = mwx.k } : null;
        }
        string Wk => weather != null ? weather.k : null;
        public static int WaveCount(int tier) => Cfg.C.waveBase + (tier - 1) * Cfg.C.waveStep;   // 40 waves at tier 1 on every map, +1 per tier (59 at tier 20)
        /* rarity by catch rate: Common 190+, Uncommon 120-189, Rare 46-119, Very rare 45 or less; each spawns less often than the last */
        public static readonly string[] RARITY = { "Common", "Uncommon", "Rare", "Very rare" };
        public static int RarOf(Species m) => m.cr >= 190 ? 0 : m.cr >= 120 ? 1 : m.cr >= 46 ? 2 : 3;
        static float RarWeight(Species m) { int k = RarOf(m); return Cfg.C.rarity[k] * (k >= 2 ? 1 + Rescue.Mod("rare") : 1); }   // the Rescue tree's rare-find nodes help Rare and Very rare ones
        /* which wild Pokémon a map and tier can send: the wave builder draws from these, and the route panel lists them */
        public class Spawns { public float tier, minB, maxB; public List<Species> pool, heavy, bosses, legs; public Dictionary<int, int> rar = new Dictionary<int, int>(); }
        public static Spawns SpawnInfo(int setIdx, int tier0)
        {
            float tier = Prog.Threat(setIdx, tier0); var S = DB.TS[setIdx]; int grp = Prog.MapGroup(setIdx);
            float maxB = 300 + tier * 30 + grp * 25, minB = Math.Min(maxB - 190, 480);   // later maps: stronger species; the floor stops at 480 so top tiers keep the strongest species
            Func<Species, bool> hasT = m => m.t.Any(x => S.types.Contains(x));
            var pool = DB.Mons.Where(m => m.anim && m.lg == 0 && hasT(m) && m.bst <= maxB && m.bst >= minB && (tier >= 3 || m.cr > 45)).ToList();
            if (pool.Count < 8) pool = DB.Mons.Where(m => m.anim && m.lg == 0 && hasT(m) && m.bst <= maxB + 60).ToList();
            var rar = pool.ToDictionary(m => m.id, m => RarOf(m));
            return new Spawns { rar = rar, tier = tier, minB = minB, maxB = maxB, pool = pool, heavy = pool.OrderByDescending(m => m.b[0] + m.b[2]).Take(6).ToList(), bosses = pool.OrderByDescending(m => m.bst).Take(3).ToList(),
                legs = tier >= 5 ? DB.Mons.Where(m => m.anim && m.lg > 0 && hasT(m) && m.bst <= 480 + tier * 25 && (m.lg == 1 || tier >= 10)).ToList() : new List<Species>() };
        }
        static List<List<SpawnDef>> WavesFor(int setIdx, int tier0, Rng R)
        {
            var SI = SpawnInfo(setIdx, tier0); float tier = SI.tier; int W = WaveCount(tier0);
            int grp = Prog.MapGroup(setIdx); var G4 = Prog.GROUPS[grp];
            float maxB = SI.maxB, minB = SI.minB; var pool = SI.pool;
            var lr = LvRange(tier); int lvBase = Math.Min(98, lr[0]), top = Math.Min(100, lr[1]);
            Species pickW(float target)
            {
                var w = pool.Select(m => RarWeight(m) / (1 + Math.Abs(m.bst - target) / 40f)).ToList();
                float r = R.Next() * w.Sum(); int k = 0; while ((r -= w[k]) > 0 && k < w.Count - 1) k++;
                return pool[k];
            }
            var waves = new List<List<SpawnDef>>();
            for (int w = 1; w <= W; w++)
            {
                float f = w / (float)W; int lv = Mathf.RoundToInt(lvBase + (top - lvBase) * Mathf.Pow(f, 1.3f)); float target = minB + (maxB - minB) * f;
                var list = new List<SpawnDef>();
                if (w == W)
                {
                    Species boss = null;
                    if (tier >= 5)
                    {
                        var leg = SI.legs;
                        if (leg.Count > 0 && R.Next() < 0.5f + Rescue.Mod("legend")) boss = leg[(int)(R.Next() * leg.Count)];
                    }
                    if (boss == null) boss = SI.bosses[(int)(R.Next() * Math.Min(3, pool.Count))];
                    int n = Mathf.RoundToInt((6 + tier) * G4.count);
                    for (int i = 0; i < n; i++) list.Add(new SpawnDef { id = pickW(target).id, lv = lv, gap = 0.6f });
                    list.Add(new SpawnDef { id = boss.id, lv = Math.Min(100, top + 3), gap = 2.5f, boss = true });
                }
                else if (w % 5 == 0)
                {
                    int n = Mathf.RoundToInt((3 + tier * 0.4f + w * 0.15f) * G4.count);
                    var heavy = SI.heavy;
                    for (int i = 0; i < n; i++) list.Add(new SpawnDef { id = heavy[(int)(R.Next() * heavy.Count)].id, lv = Math.Min(100, lv + 2), gap = 1.6f });
                }
                else
                {
                    int n = Mathf.RoundToInt((4 + w * (tier == 1 ? 0.6f : 0.85f) + tier * 0.5f) * G4.count);
                    var kinds = new List<Species> { pickW(target), pickW(target), pickW(target) }.Take(1 + (int)(R.Next() * 3)).ToList();
                    float gap = Mathf.Clamp(1.05f - w * 0.025f, 0.4f, 1.05f) / Mathf.Sqrt(G4.count);
                    for (int i = 0; i < n; i++) list.Add(new SpawnDef { id = kinds[i % kinds.Count].id, lv = Math.Max(1, lv - (R.Next() < 0.3f ? 1 : 0)), gap = gap });
                }
                waves.Add(list);
            }
            return waves;
        }

        /* ---------- start ---------- */
        public static void Start(int setIdx, int tier, int seed, List<Mon> team, bool portrait, float aspect)
        {
            var R = new Rng((uint)seed ^ 0x5bd1e995u);
            float th = Prog.Threat(setIdx, tier);
            var b = new Battle { set = setIdx, tier = tier, th = th, seed = seed, team = team, portrait = portrait, aspect = aspect, cash = Mathf.RoundToInt(Cfg.C.startCash + th * Cfg.C.startCashPerThreat + Rescue.Mod("startCash")) };
            b.M = MapGen.Gen(setIdx, portrait, seed, null, aspect, tier);
            b.waves = WavesFor(setIdx, tier, R);
            foreach (var e in team) Save.G.See(e.id);
            B = b;
            Gfx.PlayMusic(DB.TS[setIdx].name);
        }
        public void StartWave()
        {
            if (phase != "build" || wave >= waves.Count) return;
            q = waves[wave].Select(x => new SpawnDef { id = x.id, lv = x.lv, gap = x.gap, boss = x.boss }).ToList(); qt = 0.4f; wave++; phase = "wave";
            if (wave % 5 == 0 && wave != waves.Count && DB.Music.ContainsKey("_heavy")) Gfx.PlayMusic("_heavy");   // heavy waves: Monster House
            if (wave == waves.Count) Gfx.PlayMusic((DB.TS[set].game == "E" ? "_e" : "_") + (waves[wave - 1].Any(x => x.boss && DB.SP[x.id].lg > 0) ? "legend" : "boss"));
        }
        Enemy Spawn(SpawnDef s, float d = 0)
        {
            int nat = DB.RollNat(); var iv = DB.RollIV();
            var sp = DB.SP[s.id]; var st = DB.CalcStats(s.id, s.lv, iv, nat); int hpm = s.boss ? (sp.lg > 0 ? 3 : 4) : 1;
            int ab = DB.RollAbility(s.id, 0.05f + Rescue.Mod("hidden")); string ak = DB.AbKey(ab);
            var e = new Enemy
            {
                id = s.id, lv = s.lv, st = st, nat = nat, iv = iv, hp = st[0] * hpm, max = st[0] * hpm, d = d, boss = s.boss, spd = 30 + sp.b[5] * 0.4f, at = rnd * 2,
                lives = s.boss ? 20 : 1 + StagesBelow(s.id), ab = ab, ak = ak,
                lane = (rnd * 2 - 1) * 11, ph = rnd * 6.3f, sw = 0.5f + rnd * 0.6f, pace = 0.88f + rnd * 0.24f,
                r = s.r >= 0 ? s.r : UnityEngine.Random.Range(0, M.routes.Count),
                air = (sp.t.Contains(2) && !DB.GROUND_FLYERS.Contains(s.id)) || ak == "levitate",                                   // flyers take the shortcut line
                hide = th >= 3 && sp.t.Contains(7),                                          // Ghost types are hidden until a seer is near
                dig = th >= 3 && DB.MovesAt(s.id, s.lv).Contains(91), digt = 1 + rnd * 2,   // ones that know Dig burrow
                armor = th >= 3 && (sp.t.Contains(8) || sp.t.Contains(5)),                  // Steel / Rock shrug off weak hits
            };
            e.tt = 4 + rnd * 3; e.dt2 = 2 + rnd * 3;
            WildTraits(e, s.id, s.lv, ak);
            if (s.boss)      // boss moves: only ones it really knows
            {
                var ms = DB.MovesAt(s.id, s.lv);
                e.bwxm = ms.FirstOrDefault(WX_MOVES.ContainsKey); e.bwx = e.bwxm != 0 ? WX_MOVES[e.bwxm] : null;
                e.bup = ms.Where(m => { var M_ = DB.Mv(m); return M_ != null && M_.tg == 7 && M_.sc.Any(c => (c[0] == 3 || c[0] == 5 || c[0] == 6) && c[1] > 0); }).ToList();
            }
            if (s.boss && DB.BossTheme.TryGetValue(s.id, out var theme)) Gfx.PlayMusic(theme);   // this boss has its own song in the ROMs
            if (s.minion) { e.minion = true; e.lives = 1; }
            en.Add(e); Save.G.See(s.id); return e;
        }
        static int StagesBelow(int id) { int n = 0; var s = DB.SP[id]; while (s.f != 0 && DB.SP.TryGetValue(s.f, out var p) && p.anim && !p.bb && n < 3) { n++; s = p; } return n; }
        public Route RouteOf(Enemy e) { var r = M.routes[Math.Min(e.r, M.routes.Count - 1)]; return e.air ? r.air : r; }
        static readonly HashSet<int> SEE_MOVES = new HashSet<int> { 193, 316, 357 };
        public static string SeesWhy(Mon e)   // why a Pokémon can see hidden Ghost types (null if it can't)
        {
            string k = DB.AbKey(e.ab); var ty = DB.SP[e.id].t;
            if (ty.Contains(13)) return "Psychic type";
            if (ty.Contains(7)) return "Ghost type";   // Ghosts see Ghosts
            int m = e.mv.FirstOrDefault(x => SEE_MOVES.Contains(x) || (DB.Mv(x) != null && DB.Mv(x).n == "Defog")); if (m != 0) return "knows " + DB.Mv(m).n;
            return k == "keen-eye" || k == "frisk" ? "ability " + DB.Abil[e.ab].n : null;
        }
        public static bool Sees(Tower t) => SeesWhy(t.e) != null;
        public static float TowerRange(Tower t, int m) => RANGE[DB.Mv(m).c] * (1 + Math.Min(0.25f, t.e.lv / 400f) + Rescue.Mod("range")) * UpK(t, 0) * (HasT(t, 2) ? 1.15f : 1);   // Flying: Far sight
        public static float RangeFor(Mon e) { var ms = e.mv.Where(m => DB.MoveUse(m) != null).ToList(); return ms.Count == 0 ? 40 : ms.Max(m => RANGE[DB.Mv(m).c] * (1 + Math.Min(0.25f, e.lv / 400f) + Rescue.Mod("range"))); }
        public static float MaxRange(Tower t) => Math.Max(40, RangeFor(t.e));
        bool CanHit(Tower t, int m, Enemy e)
        {
            var M_ = DB.Mv(m);
            if (e.under) return m == 89 || m == 222 || m == 90;
            if (e.hide && !(e.rev > 0)) return false;
            if (e.air)
            {
                if (M_.t == 4) return false;
                if (M_.c == 2 && !(M_.t == 2 || M_.t == 5 || DB.SP[t.e.id].t.Contains(2)) && Dist(e.x, e.y, t.x, t.y) > 40) return false;
            }
            return true;
        }
        static float Dist(float ax, float ay, float bx, float by) => Mathf.Sqrt((ax - bx) * (ax - bx) + (ay - by) * (ay - by));

        /* ---------- towers ---------- */
        public bool CanPlace(Mon e, float x, float y)
        {
            if (x < 6 || y < 6 || x > M.W * TZ - 6 || y > M.H * TZ - 6) return false;
            int tv = M.t[(int)(y / TZ), (int)(x / TZ)]; var ty = DB.SP[e.id].t;
            if (tv == 1) return false;
            if (tv == 2 && !((M.liq == "water" && ty.Contains(10)) || (M.liq == "lava" && ty.Contains(9)))) return false;
            if (MapGen.DistToPath(M, x, y) < 30) return false;
            foreach (var t in towers) if (Dist(t.x, t.y, x, y) < 22) return false;
            return true;
        }
        public Tower Place(Mon e, float x, float y)
        {
            int c = DB.PlaceCost(e);
            if (cash < c || towers.Any(t => t.e == e) || towers.Count >= 10 || !CanPlace(e, x, y)) return null;
            cash -= c;
            var tw = new Tower { e = e, x = x, y = y, paid = c, pt = time }; towers.Add(tw); Gfx.Sfx("place"); return tw;
        }
        /* upgrades for a placed Pokémon, paid with battle cash: Range, Attack speed and Power; each level costs a share of its placing cost.
           Recalling it refunds 70% of everything paid, upgrades included. Numbers come from the online settings. */
        public static readonly string[] UPGN = { "Range", "Speed", "Power" };
        public static int UpgradeCost(Tower t, int k) => t.up[k] >= Cfg.C.upgMax ? 0 : Mathf.RoundToInt(DB.PlaceCost(t.e) * Cfg.C.upgCost[t.up[k]]);
        public bool BuyUpgrade(Tower t, int k) { int c = UpgradeCost(t, k); if (c == 0 || cash < c) return false; cash -= c; t.paid += c; t.up[k]++; Gfx.Sfx("lvl"); return true; }
        public static float UpK(Tower t, int k) => 1 + Cfg.C.upgStep * (t.up != null ? t.up[k] : 0);
        public void Sell(Tower t) { cash += (int)(t.paid * 0.7f); towers.Remove(t); if (sel == t) sel = null; }
        List<Enemy> InRange(Tower t, float r) => en.Where(e => e.hp > 0 && e.d > 0 && Dist(e.x, e.y, t.x, t.y) <= r).ToList();
        Enemy ChooseTarget(Tower t, List<Enemy> l)
        {
            if (l.Count == 0) return null;
            switch (t.mode)
            {
                case "first": return l.OrderByDescending(e => e.d).First();
                case "last": return l.OrderBy(e => e.d).First();
                case "strong": return l.OrderByDescending(e => e.hp).First();
                default: return l.OrderBy(e => Dist(e.x, e.y, t.x, t.y)).First();
            }
        }
        class Pick { public int m; public float sc; public Enemy tg; public List<Enemy> list; public string use; }
        static bool Aoe(Move m) => m.tg == 9 || m.tg == 11 || m.tg == 14 || m.tg == 12;
        bool TowerAct(Tower t)
        {
            var tf = TransformSrc(t);   // Transform: a copy of the strongest teammate, at its own level
            var st = tf != null ? DB.CalcStats(tf.e.id, t.e.lv, DB.IvsOf(tf.e), DB.NatOf(tf.e)) : DB.MonStats(t.e); var me = DB.SP[(tf ?? t).e.id];
            string hk = DB.HeldKey(t.e); var moves = tf != null ? tf.e.mv.Where(x => DB.MoveUse(x) != null).ToList() : hk.StartsWith("choice") ? t.e.mv.Take(1).ToList() : t.e.mv;
            Pick best = null;
            foreach (int m in moves)
            {
                string use = DB.MoveUse(m); if (use == null) continue;
                var M_ = DB.Mv(m); float r = TowerRange(t, m); var list = Targets(t, r, m); if (list == null) continue;
                var tg = ChooseTarget(t, list); float sc = 0;
                if (use == "dmg")
                {
                    float p = M_.p > 0 ? M_.p : (FIXED.ContainsKey(m) ? 50 : 60), stab = me.t.Contains(M_.t) ? 1.5f : 1, ef = DB.Eff(M_.t, DB.SP[tg.id].t);
                    sc = p * stab * ef * ((M_.a > 0 ? M_.a : 100) / 100f) * ((M_.h[0] + M_.h[1]) / 2f) * (Aoe(M_) ? 1 + 0.35f * (list.Count - 1) : 1);
                    if (OHKO.Contains(m)) sc = tg.boss || tg.lv > t.e.lv ? 0 : 60;
                }
                else if (use == "status") { bool free = list.Any(e => e.sts == null && e.imm <= 0); sc = free ? (M_.ai == "sleep" || M_.ai == "freeze" || M_.ai == "trap" ? 46 : 32) * ((M_.a > 0 ? M_.a : 100) / 100f) : 0; }
                else if (use == "debuff") sc = list.Any(e => e.stgt <= 0) ? 28 : 0;
                else if (use == "buff") sc = t.buft <= 0 ? 55 : 0;
                if (sc > 0 && (best == null || sc > best.sc)) best = new Pick { m = m, sc = sc, tg = tg, list = list, use = use };
            }
            if (best == null) return false;
            Fire(t, best, st); return true;
        }
        void Fire(Tower t, Pick b, int[] st)
        {
            var M_ = DB.Mv(b.m); DB.FxMoves.TryGetValue(b.m, out var fxm); fxm = fxm ?? new MoveFx();
            t.dir = DirRow(b.tg.x - t.x, b.tg.y - t.y); t.anim = M_.c == 2 ? "Attack" : "Shoot"; t.at = 0;
            float cd = 5.5f / Mathf.Sqrt(Math.Max(5, M_.pp)) * (M_.pr > 0 ? 0.8f : 1);
            cd /= 1 + st[5] * STAGE(BufOf(t, 6)) / 150f;
            cd /= UpK(t, 1);   // Attack speed upgrades
            if (HasT(t, 6)) cd /= 1 + 0.05f * towers.Count(o => o != t && HasT(o, 6));   // Bug: Swarm
            if (HasM(t, "Endure") && lives < 25) cd /= 1.3f; if (t.tw > time) cd /= 1.25f; if (t.ssw > time) cd /= 1.4f; if (t.acuK == 's' && t.acuU > time) cd /= 1.3f;   // move skills
            string ak = DB.AbKey(t.e.ab), hk = DB.HeldKey(t.e), wk = Wk; var ty = DB.SP[t.e.id].t;
            cd /= 1 + Rescue.Mod("atkSpeed") + Math.Max(0, ty.Max(x => Rescue.Mod("ts" + x)));
            int tile = M.t[(int)(t.y / TZ), (int)(t.x / TZ)];
            if (tile == 2 && ((M.liq == "water" && ty.Contains(10)) || (M.liq == "lava" && ty.Contains(9)))) cd /= 1 + Rescue.Mod("pondSpeed");
            if ((ak == "chlorophyll" && wk == "sun") || (ak == "sand-rush" && wk == "sand") || (ak == "slush-rush" && wk == "hail") || (ak == "swift-swim" && wk == "rain")) cd /= 1.5f;
            if (ak == "speed-boost") cd /= 1 + Math.Min(0.5f, t.sbt / 60f);
            if (ak == "swift-swim" && M.t[(int)(t.y / TZ), (int)(t.x / TZ)] == 2) cd /= 1.5f;
            if (hk == "choice-scarf") cd /= 1.5f;
            if (hk == "quick-claw" && rnd < 0.2f) cd *= 0.4f;
            t.cd = cd;
            if (fxm.u != null) AddFx(fxm.u, t.x, t.y, t.dir, Mathf.Atan2(b.tg.y - t.y, b.tg.x - t.x));
            Action<Enemy> hit = tg =>
            {
                if (b.use == "buff")
                {
                    var allies = (M_.tg == 13 || M_.tg == 3 || M_.tg == 5) ? towers.Where(o => Dist(o.x, o.y, t.x, t.y) < 90).ToList() : new List<Tower> { t };
                    foreach (var o in allies) { foreach (var s in M_.sc) if ((s[0] == 2 || s[0] == 4 || s[0] == 6) && s[1] > 0) o.buf[s[0]] = Mathf.Clamp(o.buf[s[0]] + s[1], -6, 6); o.buft = DB.HeldKey(o.e) == "light-clay" ? 24 : 12; }
                    return;
                }
                var targets = Aoe(M_) ? (M_.c == 2 || M_.c == 1 ? b.list : en.Where(e => e.hp > 0 && Dist(e.x, e.y, tg.x, tg.y) < 46 && CanHit(t, b.m, e)).ToList()) : new List<Enemy> { tg };
                foreach (var e in targets) ApplyMove(t, b.m, e, st);
            };
            if (b.use == "buff") { hit(null); return; }
            if (fxm.p != null && M_.c != 2 && DB.FxAnims.TryGetValue(fxm.p, out var pa)) proj.Add(new Proj { x = t.x, y = t.y - 8 * SPR, tg = b.tg, fx = pa, done = hit, hfx = fxm.h });
            else q2.Add((0.12f, () => { if (b.tg.hp > 0 || Aoe(M_)) { hit(b.tg); if (fxm.h != null) AddFx(fxm.h, b.tg.x, b.tg.y - 8 * ESPR, t.dir); } }));
        }
        static readonly Dictionary<string, int> AB_IMMUNE = new Dictionary<string, int> { { "flash-fire", 9 }, { "water-absorb", 10 }, { "storm-drain", 10 }, { "dry-skin", 10 }, { "volt-absorb", 12 }, { "lightning-rod", 12 }, { "motor-drive", 12 }, { "sap-sipper", 11 }, { "levitate", 4 } };
        void ApplyMove(Tower t, int m, Enemy e, int[] st)
        {
            if (e.hp <= 0) return;
            var M_ = DB.Mv(m); string use = DB.MoveUse(m); var me = DB.SP[t.e.id]; int L = t.e.lv; string ak = DB.AbKey(t.e.ab), hk = DB.HeldKey(t.e), ek = e.ak;
            float acc = M_.a > 0 ? M_.a * (ak == "compound-eyes" ? 1.3f : 1) * (ak == "hustle" && M_.c == 2 ? 0.8f : 1) * (hk == "wide-lens" ? 1.1f : hk == "zoom-lens" ? 1.2f : 1) : 100;
            if (ak == "no-guard" || HasM(t, "Lock-On") || HasM(t, "Mind Reader")) acc = 100;
            string wk = Wk;
            if ((wk == "rain" && (m == 87 || m == 542)) || (wk == "hail" && m == 59)) acc = 100;   // Thunder / Hurricane in rain, Blizzard in hail never miss
            if (acc < 100 && rnd * 100 > acc) { Float(e, "MISS", 1); return; }
            bool secondary = M_.ac > 0 || (M_.sc.Count > 0 && M_.sch > 0) || M_.fl > 0;
            bool noSec = ek == "shield-dust" || (ak == "sheer-force" && secondary);
            bool Chance(float p) => !noSec && rnd * 100 < p * (ak == "serene-grace" ? 2 : 1) * (1 + Rescue.Mod("effChance"));
            if (use == "dmg")
            {
                if (AB_IMMUNE.TryGetValue(ek ?? "", out var imt) && imt == M_.t) { Float(e, "MISS", 1); return; }
                float dmg;
                if (OHKO.Contains(m)) dmg = e.boss ? 0 : e.hp;
                else if (FIXED.TryGetValue(m, out var fx)) dmg = fx == "lv" ? L : fx == "half" ? Math.Max(1, Mathf.Floor(e.hp / 2)) : int.Parse(fx);
                else
                {
                    bool phys = M_.c == 2;
                    float A = phys ? (HasM(t, "Power Trick") ? Math.Max(st[1], st[2]) : st[1]) * STAGE(BufOf(t, 2)) : st[3] * STAGE(BufOf(t, 4));
                    if (phys && (ak == "huge-power" || ak == "pure-power")) A *= 2;
                    if (phys && ak == "hustle") A *= 1.5f;
                    if ((phys && hk == "choice-band") || (!phys && hk == "choice-specs")) A *= 1.5f;
                    float D = (phys ? e.st[2] * STAGE(Mathf.Clamp(e.stg[3] + e.bst[3], -6, 6)) : e.st[4] * STAGE(Mathf.Clamp(e.stg[5] + e.bst[5], -6, 6))) * (e.gs > time ? e.gsf : 1);   // Guard Split / Octolock
                    int hits = ak == "skill-link" ? M_.h[1] : M_.h[0] + UnityEngine.Random.Range(0, M_.h[1] - M_.h[0] + 1);
                    var ty = EnTypes(e); if (ak == "scrappy" && (M_.t == 0 || M_.t == 1)) ty = ty.Where(x => x != 7).ToArray();
                    float ef = DB.Eff(M_.t, ty);
                    if (ef == 0 || (ek == "wonder-guard" && ef <= 1)) { Float(e, "MISS", 1); return; }
                    int cs = Mathf.Clamp(M_.cr + (t.fe > time ? 2 : 0) + (HasT(t, 15) ? 1 : 0) + (ak == "super-luck" ? 1 : 0) + (hk == "scope-lens" || hk == "razor-claw" ? 1 : 0), 0, 3);
                    bool sure = t.lf && ek != "battle-armor" && ek != "shell-armor"; if (sure) t.lf = false;   // Laser Focus
                    float crit = sure || ek != "battle-armor" && ek != "shell-armor" && rnd < new[] { 1 / 24f, 1 / 8f, 1 / 2f, 1f }[cs] + Rescue.Mod("crit") ? (ak == "sniper" ? 2.25f : 1.5f) : 1;
                    float pw = M_.p > 0 ? M_.p : 60; if (ak == "technician" && pw <= 60) pw *= 1.5f;
                    float mod = (me.t.Contains(M_.t) ? (ak == "adaptability" ? 2 : 1.5f) + Rescue.Mod("stab") : 1) * ef * crit;
                    mod *= 1 + Rescue.Mod("power") + Rescue.Mod("tp" + M_.t);
                    mod *= UpK(t, 2);   // Power upgrades
                    if (e.boss) mod *= 1 + Rescue.Mod("bossDmg") + (HasT(t, 1) ? 0.2f : 0);   // Fighting: Boss hitter
                    if (HasT(t, 5) && e.rk.Add(t)) mod *= 1.3f;   // Rock: Crush (first hit on each enemy)
                    if (towers.Any(o => o != t && HasT(o, 17) && Dist(o.x, o.y, t.x, t.y) <= 90)) mod *= 1.05f;   // Fairy: Aura
                    if (M_.t == 12 && t.chg) { mod *= 2; t.chg = false; } if (M_.t == 12 && e.elz > time) mod *= 2;   // Charge / Electrify
                    if (t.dteam > time) mod *= 2; if (t.enc) { mod *= 2; t.enc = false; } if (t.hh > time) mod *= 1.25f; if (!phys && t.thr > time) mod *= 1.2f;   // Double Team / Encore / Helping Hand / Take Heart
                    if (t.acuK == 'd' && t.acuU > time) mod *= 1.3f; if (terr.TryGetValue(M_.t, out var tu) && tu > time) mod *= 1.3f;   // Acupressure / terrains
                    if (HasM(t, "Ingrain")) mod *= 1 + Math.Min(0.3f, 0.05f * Mathf.Floor((time - t.pt) / 10));
                    float wp = 0.5f + Rescue.Mod("weatherPower");   // weather: Rain / Sun boost one type and weaken the other x0.5
                    if (wk == "rain") mod *= M_.t == 10 ? 1 + wp : M_.t == 9 ? 0.5f : 1;
                    if (wk == "sun") mod *= M_.t == 9 ? 1 + wp : M_.t == 10 ? 0.5f : 1;
                    if (wk == "sun" && ak == "solar-power" && !phys) mod *= 1.5f;
                    if (wk == "sand" && !phys && DB.SP[e.id].t.Contains(5)) mod /= 1.5f;   // sandstorm raises Rock types' Sp. Def
                    var pinch = new Dictionary<string, int> { { "overgrow", 11 }, { "blaze", 9 }, { "torrent", 10 }, { "swarm", 6 } };
                    if (lives <= 33 && pinch.TryGetValue(ak, out var pt) && pt == M_.t) mod *= 1.5f;
                    if (ak == "sheer-force" && secondary) mod *= 1.3f;
                    if (ak == "tough-claws" && phys) mod *= 1.3f;
                    if (ak == "tinted-lens" && ef < 1) mod *= 2;
                    if (hk == "life-orb") mod *= 1.3f;
                    if (hk == "expert-belt" && ef > 1) mod *= 1.2f;
                    if ((hk == "muscle-band" && phys) || (hk == "wise-glasses" && !phys)) mod *= 1.1f;
                    if (DB.TYPE_ITEM.TryGetValue(hk, out var it) && it == M_.t) mod *= 1.2f;
                    if (hk == "metronome") { t.metro = t.lastM == m ? Math.Min(5, t.metro + 1) : 0; t.lastM = m; mod *= 1 + 0.2f * t.metro; }
                    if ((ek == "thick-fat" && (M_.t == 9 || M_.t == 14)) || (ek == "heatproof" && M_.t == 9)) mod *= 0.5f;
                    if (ek == "dry-skin" && M_.t == 9) mod *= 1.25f;
                    if ((ek == "filter" || ek == "solid-rock" || ek == "prism-armor") && ef > 1) mod *= 0.75f;
                    if ((ek == "multiscale" || ek == "shadow-shield") && e.hp >= e.max) mod *= 0.5f;
                    if (e.armor && (M_.p > 0 ? M_.p : 60) < 60 && !HasT(t, 8)) mod *= 0.5f;   // Steel: Pierce
                    dmg = 0;
                    for (int h = 0; h < hits; h++) dmg += ((2f * L / 5 + 2) * pw * A / D / 50 + 2) * mod * (0.85f + rnd * 0.15f);
                    dmg = Math.Max(1, Mathf.Floor(dmg));
                    if (ef > 1) Float(e, "!", 2);
                    if (e.sts == "freeze" && M_.t == 9) { e.sts = null; e.stop = 0; }
                }
                if (ek == "sturdy" && !e.sturdy && e.hp >= e.max && dmg >= e.hp) { dmg = e.hp - 1; e.sturdy = true; }
                e.fs = m == 206; mlab = M_.n; Hurt(t, e, dmg); e.fs = false; QuirkHit(t, e, dmg);   // False Swipe: a knockout by it is 3x as likely to ask to join
                if (e.hp > 0 && M_.ai != "none" && DB.AILMENTS.Contains(M_.ai) && Chance(M_.ac)) Inflict(e, M_.ai, t);
                if (e.hp > 0 && ((M_.fl > 0 && Chance(M_.fl)) || (M_.fl == 0 && (hk == "kings-rock" || hk == "razor-fang") && rnd < 0.1f))) e.stop = Math.Max(e.stop, 0.35f);
                if (e.hp > 0 && M_.sc.Count > 0 && M_.tg != 7 && Chance(M_.sch)) Debuff(e, M_.sc, t);
            }
            else if (use == "status") Inflict(e, M_.ai, t);
            else if (use == "debuff") Debuff(e, M_.sc, t);
        }
        void Debuff(Enemy e, List<int[]> sc, Tower t)
        {
            if (e.ak == "clear-body" || e.ak == "white-smoke" || e.ak == "full-metal-body") return;
            foreach (var s in sc) if (s[1] < 0 && (s[0] == 3 || s[0] == 5 || s[0] == 6)) e.stg[s[0]] = Mathf.Clamp(e.stg[s[0]] + s[1], -6, 0);
            e.stgt = (t != null && DB.HeldKey(t.e) == "light-clay" ? 20 : 10) * (1 + Rescue.Mod("debuffDur"));
        }
        static readonly Dictionary<string, string[]> STATUS_BLOCK = new Dictionary<string, string[]> {
            { "sleep", new[] { "insomnia", "vital-spirit", "sweet-veil" } }, { "paralysis", new[] { "limber" } }, { "poison", new[] { "immunity", "pastel-veil" } },
            { "burn", new[] { "water-veil", "water-bubble" } }, { "confusion", new[] { "own-tempo", "oblivious" } }, { "freeze", new[] { "magma-armor" } } };
        static readonly Dictionary<string, int[]> TYPE_BLOCK = new Dictionary<string, int[]> { { "burn", new[] { 9 } }, { "paralysis", new[] { 12 } }, { "poison", new[] { 3, 8 } }, { "freeze", new[] { 14 } } };
        static readonly Dictionary<string, float> DUR = new Dictionary<string, float> { { "paralysis", 6 }, { "sleep", 3 }, { "freeze", 3 }, { "burn", 5 }, { "poison", 6 }, { "confusion", 3 }, { "trap", 4 }, { "yawn", 2 }, { "leech-seed", 8 } };
        void Inflict(Enemy e, string ai, Tower t)
        {
            if (e.sts != null || e.imm > 0 || !DUR.ContainsKey(ai)) return;
            if ((STATUS_BLOCK.TryGetValue(ai, out var bl) && bl.Contains(e.ak)) || (TYPE_BLOCK.TryGetValue(ai, out var tb) && tb.Any(x => DB.SP[e.id].t.Contains(x)))) return;
            e.src = t; e.bind = t != null && DB.HeldKey(t.e) == "binding-band";
            if (ai == "freeze" && Wk == "sun") return;   // nothing freezes in sun
            e.sts = ai; e.stt = DUR[ai] * (e.boss ? 0.5f : 1) * (1 + Rescue.Mod("statusDur"));
            if (ai == "sleep" || ai == "freeze" || ai == "trap") e.stop = Math.Max(e.stop, e.stt);
            if (t != null && (ai == "sleep" || ai == "freeze" || ai == "trap" || ai == "paralysis" || ai == "confusion")) MeterCtl(t, e.stt);
        }
        void Hurt(Tower t, Enemy e, float dmg)
        {
            // Protect-type moves raise a shield that soaks up a quarter of its HP
            bool phase_ = t != null && HasT(t, 7);   // Ghost: Phase - attacks go through Protect shields
            if (!phase_ && !(e.nt > time) && e.prot != 0 && e.sh <= 0 && e.shcd <= 0 && e.hp - dmg > 0) { e.shm = e.sh = Mathf.Ceil(e.max * 0.25f); e.sht = 3; e.shcd = 9; Float(e, DB.Mv(e.prot).n, 4); }
            if (!phase_ && e.sh > 0) { float a = Math.Min(e.sh, dmg); e.sh -= a; dmg -= a; if (e.sh <= 0) e.sht = 0; if (dmg <= 0) { e.hurt = 0.1f; return; } }
            MeterDmg(t, Math.Min(dmg, Math.Max(0, e.hp)), mlab); e.hp -= dmg; e.hurt = 0.25f; Float(e, ((int)dmg).ToString(), 0);
            if (e.healMv != 0 && !e.healed && !(e.nt > time) && e.hp > 0 && e.hp < e.max * 0.4f) { e.healed = true; e.hp = Math.Min(e.max, e.hp + Mathf.Ceil(e.max * e.healHl)); Float(e, DB.Mv(e.healMv).n, 4); }
            if (e.hp <= 0) Ko(t, e);
        }
        void BossAct(Enemy e, float dt)
        {
            e.btWx -= dt; e.btUp -= dt; e.btCall -= dt;
            if (e.bwx != null && bwx == null) { bwx = new Weather { k = e.bwx, e = e, boss = true }; Float(e, DB.Mv(e.bwxm).n, 4); }   // a boss's weather lasts until it is knocked out
            if (e.bup.Count > 0 && e.btUp <= 0 && !towers.Any(t => HasM(t, "Mist") && Dist(t.x, t.y, e.x, e.y) <= SkR(t)))
            {
                e.btUp = 9; int m = e.bup[UnityEngine.Random.Range(0, e.bup.Count)]; var M_ = DB.Mv(m); bool up = false;
                foreach (var c in M_.sc) if ((c[0] == 3 || c[0] == 5 || c[0] == 6) && c[1] > 0 && e.bst[c[0]] < 6) { e.bst[c[0]] = Math.Min(6, e.bst[c[0]] + c[1]); up = true; }
                if (up) Float(e, M_.n, 4);
            }
            if (e.btCall <= 0)
            {
                e.btCall = 15; var pool = waves[waves.Count - 1].Where(x => !x.boss).ToList();
                if (pool.Count > 0)
                {
                    Float(e, "Called for help!", 4);
                    for (int i = 0; i < 3; i++) { var p = pool[UnityEngine.Random.Range(0, pool.Count)]; Spawn(new SpawnDef { id = p.id, lv = Math.Max(1, e.lv - 5), minion = true, r = e.r }, Math.Max(0, e.d - 20 - i * 14)); }
                }
            }
        }
        void Ko(Tower t, Enemy e)
        {
            e.hp = 0; e.dead = 0.5f; kills++; { var mr = Mtr(t); if (mr != null) mr.ko++; }
            cash += Mathf.RoundToInt((2 + e.lv / 6 + (e.boss ? 50 : 0)) * (t != null && DB.HeldKey(t.e) == "amulet-coin" ? 2 : 1) * (1 + Rescue.Mod("koCash")));
            var sp = DB.SP[e.id];
            if (t != null)
            {
                foreach (var o in towers)
                {
                    float L = e.lv, Lp = o.e.lv;
                    float gain = Mathf.Floor(sp.x * L / 5 * Mathf.Pow((2 * L + 10) / (L + Lp + 10), 2.5f) / 4) + 1;
                    int g = Mathf.CeilToInt(gain * (o == t ? 1 : 0.33f) * (e.boss ? 3 : 1) * (DB.HeldKey(o.e) == "lucky-egg" ? 1.5f : 1) * Cfg.C.xpMul * Mathf.Clamp01(1 - (o.e.lv - e.lv - Cfg.C.xpFullGap) / (Cfg.C.xpZeroGap - Cfg.C.xpFullGap)));   // full XP up to 5 levels above the wild one, none at 15+ above
                    bool up = Save.GiveXP(o.e, g); xpLog[o.e.u] = (xpLog.TryGetValue(o.e.u, out var x0) ? x0 : 0) + g;
                    if (up) { Float(o.x, o.y, "Lv " + o.e.lv, 3); Gfx.Sfx("lvl"); }
                }
                t.kills++;
                // you choose whether to take it, like the original; a declined species stops asking for the rest of this battle
                if (sp.anim && !declined.Contains(e.id) && !asks.Any(a => a.id == e.id))
                {
                    float p = (e.boss ? 0.04f + Rescue.Mod("bossRecruit") : 0.005f * (sp.cr / 255f) * (1 + th * 0.05f) * (1 - 0.5f * Mathf.Clamp01((th - 4) / 5f))) * (1 + Rescue.Mod("recruit")) * (e.fs ? 3 : 1) * (e.lure > time ? 2 : 1);   // halved from tier 9 up; False Swipe x3; Sweet Scent x2
                    if (rnd < p) { asks.Add(new Ask { id = e.id, lv = e.lv, ab = e.ab, nat = e.nat, iv = e.iv }); Gfx.Sfx("join"); AskJoin?.Invoke(); }
                }
            }
            // evolved Pokémon fall back to their earlier stage
            if (!e.boss && sp.f != 0 && DB.SP.TryGetValue(sp.f, out var pre) && pre.anim && !pre.bb)
            {
                var c = Spawn(new SpawnDef { id = sp.f, lv = Math.Max(1, e.lv - 3), r = e.r }, Math.Max(1, e.d - 6)); c.lives = Math.Max(1, e.lives - 1);
                if (c.air != e.air) c.d = MapGen.NearestD(RouteOf(c), e.x, e.y);
            }
        }
        void Float(Enemy e, string txt, int kind) => Float(e.x, e.y, txt, kind);
        void Float(float x, float y, string txt, int kind) => fl.Add(new Floater { x = x + (rnd * 8 - 4), y = y - 24 * SPR, txt = txt, kind = kind });
        /* user effects that flow in from one side of the sheet: turned so that side faces the target (value = which way that side points; PI/2 = down) */
        static readonly Dictionary<string, float> FX_FROM = new Dictionary<string, float> { { "efob023/anim00", Mathf.PI / 2 }, { "efob023/anim08", Mathf.PI / 2 } }.WithEos();   // Absorb, Mega Drain, Giga Drain, Leech Life...
        void AddFx(string rf, float x, float y, int dir, float ang = float.NaN)
        {
            if (!DB.FxAnims.TryGetValue(rf, out var a)) return;
            fx.Add(new FxInst { a = a, x = x, y = y, row = a.r > 1 ? dir : 0, rot = FX_FROM.TryGetValue(rf, out var fr) && !float.IsNaN(ang) ? ang - fr : 0 });
        }
        public static int DirRow(float dx, float dy) { float deg = Mathf.Atan2(dy, dx) * Mathf.Rad2Deg; return ((Mathf.RoundToInt((90 - deg) / 45) % 8) + 8) % 8; }
        public static float AnimLen(int id, string name) { var a = Gfx.Meta(id, name); return a != null ? a.Total / 60f : 0.5f; }

        /* ---------- update ---------- */
        // per-frame helpers that make no garbage (fewer memory clean-ups = less work for the phone)
        readonly List<Enemy> enBuf = new List<Enemy>();
        static readonly string[] SAND_SAFE = { "sand-veil", "sand-rush", "sand-force", "overcoat", "magic-guard" }, HAIL_SAFE = { "ice-body", "snow-cloak", "overcoat", "magic-guard" };
        bool AnyAlive() { foreach (var e in en) if (e.hp > 0) return true; return false; }
        bool NearQuirk11(Enemy e) { foreach (var t in towers) if (HasT(t, 11) && Dist(t.x, t.y, e.x, e.y) <= MaxRange(t)) return true; return false; }
        // enemies this move can hit; null (no new list) when there are none, which is most checks
        List<Enemy> Targets(Tower t, float r, int m)
        {
            List<Enemy> l = null;
            foreach (var e in en) if (e.hp > 0 && e.d > 0 && Dist(e.x, e.y, t.x, t.y) <= r && CanHit(t, m, e)) (l ??= new List<Enemy>()).Add(e);
            return l;
        }
        public void Tick(float dt)
        {
            if (phase == "win" || phase == "lose" || paused) return;
            dt *= speed; time += dt;
            if (phase == "wave")
            {
                if (q.Count > 0) { qt -= dt; while (q.Count > 0 && qt <= 0) { var s = q[0]; q.RemoveAt(0); Spawn(s); qt += s.gap; } }
                else if (!AnyAlive())
                {
                    cash += Mathf.RoundToInt((30 + wave * 6) * (1 + Rescue.Mod("waveBonus")));
                    if (pwx != null && wave >= pwx.until) pwx = null;   // your weather ends with its last wave
                    if (wave >= waves.Count) { Finish(true); return; }
                    phase = "build"; if (auto) StartWave();
                    Gfx.PlayMusic(DB.TS[set].name);
                }
            }
            SyncWeather();
            string chipK = Wk == "sand" || Wk == "hail" ? Wk : null;
            enBuf.Clear(); enBuf.AddRange(en);   // a reused copy: the list can change while enemies are handled (knock-outs, splits)
            foreach (var e in enBuf)
            {
                e.at += dt;
                if (e.hp <= 0) { e.dead -= dt; continue; }
                if (chipK != null && e.d > 0 && !e.under)   // Sandstorm hurts all but Rock / Ground / Steel, Hail all but Ice (and a few abilities)
                {
                    var ety = DB.SP[e.id].t;
                    bool safe = chipK == "sand" ? Array.IndexOf(ety, 5) >= 0 || Array.IndexOf(ety, 4) >= 0 || Array.IndexOf(ety, 8) >= 0 || Array.IndexOf(SAND_SAFE, e.ak) >= 0
                        : Array.IndexOf(ety, 14) >= 0 || Array.IndexOf(HAIL_SAFE, e.ak) >= 0;
                    if (!safe) { e.wdot += e.max * 0.02f * (1 + Rescue.Mod("weatherChip")) * dt * (e.boss ? 0.4f : 1); if (e.wdot >= 1) { float d = Mathf.Floor(e.wdot); e.wdot -= d; e.hp -= d; if (e.hp <= 0) { Ko(null, e); continue; } } }
                }
                if (e.akOff > 0 && time > e.akOff) { e.ak = e.ak0; e.akOff = 0; }
                if (e.cuLeft > 0) { float d0 = Math.Min(e.cuLeft, e.cuDps * dt); e.cuLeft -= d0; e.cud += d0; if (e.cud >= 1) { float d = Mathf.Floor(e.cud); e.cud -= d; MeterDmg(towers.Contains(e.cuT) ? e.cuT : null, Math.Min(d, e.hp), "Curse", true); e.hp -= d; if (e.hp <= 0) { Ko(towers.Contains(e.cuT) ? e.cuT : null, e); continue; } } }
                if (e.pm > 0 && time >= e.pm) { e.pm = 0; Float(e, "Perish", 4); mlab = "Perish Song"; Hurt(towers.Contains(e.pmT) ? e.pmT : null, e, Mathf.Ceil(e.max * 0.3f)); if (e.hp <= 0) continue; }
                if (e.pst > 0) { e.ptt -= dt; if (e.ptt <= 0) e.pst = 0; else if (e.ak != "magic-guard") { e.pd += e.max * 0.01f * e.pst * dt * (e.boss ? 0.4f : 1); if (e.pd >= 1) { float d = Mathf.Floor(e.pd); e.pd -= d; MeterDmg(towers.Contains(e.psrc) ? e.psrc : null, Math.Min(d, e.hp), "Toxic stacks (Poison quirk)", true); e.hp -= d; if (e.hp <= 0) { Ko(towers.Contains(e.psrc) ? e.psrc : null, e); continue; } } } }
                e.chill -= dt; e.wsl -= dt;
                e.hurt = Math.Max(0, e.hurt - dt); e.imm -= dt;
                if (e.sht > 0) { e.sht -= dt; if (e.sht <= 0) e.sh = 0; } e.shcd -= dt;
                if (e.regen) { e.rg += e.max * 0.01f * dt; if (e.rg >= 1) { float h = Mathf.Floor(e.rg); e.rg -= h; e.hp = Math.Min(e.max, e.hp + h); } }
                if (e.dashMv != 0) { if (e.dash > 0) e.dash -= dt; else if (e.d > 0 && e.stop <= 0 && e.sts == null && !(e.nt > time) && (e.dt2 -= dt) <= 0) { e.dash = 0.6f; e.dt2 = 4 + rnd * 2; } }
                if (e.tele && e.stop <= 0 && e.sts == null && !(e.nt > time) && e.d > 0 && (e.tt -= dt) <= 0) { e.tt = 7 + rnd * 3; e.d = Math.Min(RouteOf(e).len - 30, e.d + 70); e.placed = false; Float(e, "Teleport", 4); }
                if (e.boss && e.d > 0) BossAct(e, dt);
                if (e.stgt > 0) { e.stgt -= dt; if (e.stgt <= 0) e.stg = new int[7]; }
                if (e.sts != null)
                {
                    e.stt -= dt;
                    float dps = (e.sts == "burn" ? 0.04f : e.sts == "poison" ? 0.05f : e.sts == "trap" ? 0.03f : e.sts == "leech-seed" ? 0.03f : 0) * (1 + Rescue.Mod("dot"));
                    if (dps > 0 && e.ak != "magic-guard")
                    {
                        e.dot += e.max * dps * dt * (e.boss ? 0.4f : 1) * (e.bind && e.sts == "trap" ? 2 : 1);
                        if (e.dot >= 1) { float d = Mathf.Floor(e.dot); e.dot -= d; MeterDmg(e.src != null && towers.Contains(e.src) ? e.src : null, Math.Min(d, e.hp), e.sts == "burn" ? "Burn" : e.sts == "poison" ? "Poison" : e.sts == "trap" ? "Trap (bind)" : e.sts == "leech-seed" ? "Leech Seed" : "Status", true); e.hp -= d; if (e.hp <= 0) { Ko(e.src != null && towers.Contains(e.src) ? e.src : null, e); continue; } }
                    }
                    if (e.stt <= 0) { if (e.sts == "yawn") { e.sts = null; Inflict(e, "sleep", e.src); } else { if (e.sts == "sleep") e.imm = 4; e.sts = null; } }
                }
                if (e.stop > 0) e.stop -= dt;
                else
                {
                    float v = e.spd * e.pace * (1 + 0.12f * Mathf.Sin(time * e.sw * 1.7f + e.ph)) * STAGE(Mathf.Clamp(e.stg[6] + e.bst[6], -6, 6)) * (e.dash > 0 ? 3 : 1);
                    if (e.ak == "quick-feet" && e.sts != null) v *= 1.5f;
                    if (e.ak == "speed-boost") { e.sbt += dt; v *= Math.Min(2, 1 + e.sbt / 40); }
                    v *= SkSpeed(e); if (e.back > time) v = -Math.Abs(v) * 0.6f; if (DecoyBlocks(e)) v = 0;   // move skills
                    if (e.chill > 0) v *= 0.85f; if (e.wsl > 0) v *= 0.9f; if (NearQuirk11(e)) v *= 0.9f;   // Ice / Water / Grass quirks
                    if (e.sts == "paralysis") v *= 0.5f;
                    if (e.sts == "confusion") v *= Mathf.Sin(time * 6) > 0 ? 0.6f : -0.3f;
                    e.d = Math.Max(e.back > time ? 1 : -1e9f, e.d + v * dt);
                }
                if (e.dig) { e.digt -= dt; if (e.digt <= 0) { e.under = !e.under; e.digt = e.under ? 2.5f : 2.2f; } }
                if (e.hide) { e.rev -= dt; foreach (var t in towers) if (Sees(t) && Dist(t.x, t.y, e.x, e.y) <= MaxRange(t) * (HasT(t, 13) ? 1.5f : 1)) { e.rev = 0.4f; break; } }
                var rt = RouteOf(e); var p = MapGen.PathAt(rt, Math.Max(0, e.d));
                // drift across the path instead of marching on the centre line; ease round corners; face along the path
                float off = e.lane + Mathf.Sin(time * e.sw + e.ph) * 5, nx = -Mathf.Sin(p.z), ny = Mathf.Cos(p.z);
                float tx = p.x + nx * off, ty = p.y + ny * off;
                if (!e.placed) { e.x = tx; e.y = ty; e.placed = true; } else { float k = Math.Min(1, dt * 8); e.x += (tx - e.x) * k; e.y += (ty - e.y) * k; }
                e.dir = DirRow(Mathf.Cos(p.z), Mathf.Sin(p.z));
                if (e.d >= rt.len) { e.hp = 0; e.dead = 0; lives -= e.lives; if (lives <= 0) { lives = 0; Finish(false); return; } }
            }
            en.RemoveAll(e => e.hp <= 0 && e.dead <= 0);
            foreach (var t in towers)
            {
                string ak = DB.AbKey(t.e.ab);
                t.sbt = phase == "wave" ? t.sbt + dt : 0;
                string aura = ak == "static" ? "paralysis" : ak == "flame-body" ? "burn" : ak == "poison-point" ? "poison" : ak == "effect-spore" ? "spore" : null;
                if (aura != null && phase == "wave")
                    foreach (var e in en) if (e.hp > 0 && e.sts == null && !e.under && Dist(e.x, e.y, t.x, t.y) < 38 && rnd < 0.15f * dt)
                            Inflict(e, aura == "spore" ? new[] { "poison", "paralysis", "sleep" }[UnityEngine.Random.Range(0, 3)] : aura, t);
                t.at += dt; t.cd -= dt;
                if (t.buft > 0) { t.buft -= dt; if (t.buft <= 0) t.buf = new int[7]; }
                if (t.anim != "Idle" && t.at > AnimLen(t.e.id, t.anim)) { t.anim = "Idle"; t.at = 0; }
                if (t.cd <= 0 && phase == "wave") { if (!TowerAct(t)) t.cd = 0.15f; }
            }
            SkillTick(dt);
            for (int i = q2.Count - 1; i >= 0; i--) { var a = q2[i]; a.t -= dt; if (a.t <= 0) { q2.RemoveAt(i); a.fn(); } else q2[i] = a; }
            foreach (var p in proj)
            {
                p.at += dt;
                float tx = p.tg.x, ty = p.tg.y - (8 + (p.tg.air ? 12 : 0)) * ESPR, d = Dist(tx, ty, p.x, p.y), s = p.sp * dt;
                if (d <= s || (p.tg.hp <= 0 && d <= s * 2)) { p.hit = true; p.done(p.tg); if (p.hfx != null) AddFx(p.hfx, tx, ty, 0); }
                else { p.x += (tx - p.x) / d * s; p.y += (ty - p.y) / d * s; p.row = DirRow(tx - p.x, ty - p.y); p.ang = Mathf.Atan2(ty - p.y, tx - p.x); }
            }
            proj.RemoveAll(p => p.hit || p.at >= 4);
            foreach (var f in fx) f.t += dt;
            fx.RemoveAll(f => f.t >= f.a.Total / 60f);
            foreach (var f in fl) f.t += dt;
            fl.RemoveAll(f => f.t >= 0.9f);
        }
        void Finish(bool won)
        {
            phase = won ? "win" : "lose"; over = true;
            int grp = Prog.MapGroup(set); float pay = Prog.GROUPS[grp].pay;   // harder maps pay more
            reward = Mathf.RoundToInt((won ? Cfg.C.winPay + th * Cfg.C.winPayPerThreat + lives * 2 : Mathf.Floor(wave * th * 6)) * (1 + (won ? Rescue.Mod("pay") + Rescue.Mod("bossPay") : 0)) * pay);
            var G = Save.G; G.money += reward; G.maps++;
            // Rescue Points: from clearing maps (a little for getting far on a loss)
            rp = Mathf.RoundToInt((won ? Rescue.RpForClear(th) : Mathf.Floor(Rescue.RpForClear(th) * wave / (float)waves.Count / 2)) * pay); G.rp += rp;
            drop = 0; hdrop = 0; stars = 0; starRp = 0; mapOpened = null; groupOpened = null; unlocked = false;
            if (won)
            {
                G.wins++;
                // stars per map and tier: 1 for the win, 2 with 50+ lives left, 3 with all 100. Each new star pays half the tier's Rescue Points, once
                int sk = set * 100 + tier; stars = 1 + (lives >= 50 ? 1 : 0) + (lives >= 100 ? 1 : 0); int was = G.Count(G.stars, sk);
                if (stars > was) { starRp = Mathf.RoundToInt(Rescue.RpForClear(th) * 0.5f * (stars - was) * pay); G.Add(G.stars, sk, stars - was); G.rp += starRp; }
                // this map's next tier; one win opens the next map of the group; a high tier on any map opens the next group
                if (tier >= Prog.MapTier(set) && tier < MAXTIER) { Prog.SetTier(set, tier + 1); unlocked = true; }
                if (tier >= MAXTIER && !G.mtDone.Contains(set)) G.mtDone.Add(set);
                int nx = set + 1;
                if (nx < DB.TS.Count && Prog.MapGroup(nx) == grp && !Prog.MapOpen(nx)) { Prog.SetTier(nx, 1); mapOpened = DB.TS[nx].name; }
                if (grp < 3 && tier >= Prog.Gate(grp + 1)) { int f = Prog.GroupStart(grp + 1); if (f >= 0 && !Prog.MapOpen(f)) { Prog.SetTier(f, 1); groupOpened = Prog.GROUPS[grp + 1].name; mapOpened = mapOpened ?? DB.TS[f].name; } }
                // held items: common ones from the start, the strongest from threat 6
                if (rnd < Math.Min(0.85f, 0.3f + th * 0.03f + Rescue.Mod("drop")))
                {
                    var ks = DB.Held.Where(kv => th >= 6 + Rescue.Mod("rareTier") || !DB.HELD_RARE.Contains(kv.Value.k)).Select(kv => kv.Key).ToList();
                    hdrop = ks[UnityEngine.Random.Range(0, ks.Count)]; G.Add(G.held, hdrop, 1);
                }
                if (th >= 3 && rnd < 0.15f + th * 0.03f + Rescue.Mod("stone")) { var its = DB.Items.Keys.ToList(); drop = its[UnityEngine.Random.Range(0, its.Count)]; G.Add(G.items, drop, 1); }
            }
            Save.Write(); Gfx.PlayMusic((DB.TS[set].game == "E" ? "_e" : "_") + (won ? "win" : "lose"));
            Finished?.Invoke();
        }
        public void GiveUp() { if (!over) Finish(false); }

        /* accept a join request */
        public Mon Accept(Ask a)
        {
            var e = Save.MakeMon(a.id, a.lv, a.nat, a.iv); e.ab = a.ab; Save.G.box.Add(e); recruits.Add(e);
            if (team.Count < 10) { team.Add(e); TeamChanged?.Invoke(); }
            Save.Write(); return e;
        }
    }
}
