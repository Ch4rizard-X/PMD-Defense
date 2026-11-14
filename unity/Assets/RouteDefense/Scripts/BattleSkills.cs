// Route Defense — type quirks, move skills and the damage meter (port of the HTML battle.js additions, Nov 2026).
using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace RouteDefense
{
    public class Trap { public Tower t; public int m, r; public string kind; public float d, x, y; public HashSet<Enemy> hit = new HashSet<Enemy>(); }
    public class Decoy { public Tower t; public int m, r; public float d, x, y, u; }
    public class Zap { public float ax, ay, bx, by, t; }
    public class MeterRow { public int u, id, ko; public float dmg, dot, ctl; public Dictionary<string, float> br = new Dictionary<string, float>(); }

    public partial class Battle
    {
        /* ---------- type quirks: your team only, both types on a dual type ---------- */
        public static readonly Dictionary<int, string[]> TQ = new Dictionary<int, string[]> {
            { 0, new[] { "Thrifty", "Costs 10% less to place" } }, { 1, new[] { "Boss hitter", "+20% damage to bosses" } }, { 2, new[] { "Far sight", "+15% range" } },
            { 3, new[] { "Toxic", "Hits stack poison (up to 5)" } }, { 4, new[] { "Tremor", "Hits may stun briefly" } }, { 5, new[] { "Crush", "First hit on each enemy deals +30%" } },
            { 6, new[] { "Swarm", "+5% attack speed for each other Bug placed" } }, { 7, new[] { "Phase", "Attacks go through Protect shields" } }, { 8, new[] { "Pierce", "Ignores Rock / Steel armour" } },
            { 9, new[] { "Scorch", "Hits may burn" } }, { 10, new[] { "Soak", "Hits slow enemies a little" } }, { 11, new[] { "Vines", "Enemies in its range move 10% slower" } },
            { 12, new[] { "Chain", "Hits jump to one more enemy for 30% damage" } }, { 13, new[] { "Foresight", "Reveals hidden Ghosts from 50% farther" } }, { 14, new[] { "Chill", "Hits slow enemies by 15%" } },
            { 15, new[] { "Fury", "Higher critical-hit chance" } }, { 16, new[] { "Finisher", "Finishes off enemies below 15% HP (not bosses)" } }, { 17, new[] { "Aura", "Teammates close by deal +5% damage" } } };
        public static List<string[]> Quirks(int id) => DB.SP[id].t.Where(TQ.ContainsKey).Select(x => TQ[x]).ToList();
        public static bool HasT(Tower t, int x) => DB.SP[t.e.id].t.Contains(x);
        bool chaining;
        public List<Zap> zap = new List<Zap>();

        void QuirkHit(Tower t, Enemy e, float dmg)
        {
            if (HasT(t, 12) && !chaining)   // Electric: Chain (also when the hit was a knockout)
            {
                var o = en.Where(x => x != e && x.hp > 0 && x.d > 0 && !x.under && !(x.hide && !(x.rev > 0)) && Dist(x.x, x.y, e.x, e.y) < 70).OrderBy(x => Dist(x.x, x.y, e.x, e.y)).FirstOrDefault();
                if (o != null) { chaining = true; zap.Add(new Zap { ax = e.x, ay = e.y, bx = o.x, by = o.y, t = 0.18f }); string L = mlab; mlab = "Chain (Electric quirk)"; Hurt(t, o, Math.Max(1, Mathf.Floor(dmg * 0.3f))); mlab = L; chaining = false; }
            }
            if (e.hp <= 0) return;
            if (HasT(t, 9) && rnd < 0.15f) Inflict(e, "burn", t);                                         // Fire: Scorch
            if (HasT(t, 3)) { e.pst = Math.Min(5, e.pst + 1); e.ptt = 4; e.psrc = t; }                      // Poison: Toxic
            if (HasT(t, 10)) { e.wsl = 1.5f; MeterCtl(t, 0.15f); }                                          // Water: Soak
            if (HasT(t, 14)) { e.chill = 2; MeterCtl(t, 0.3f); }                                            // Ice: Chill
            if (HasT(t, 4) && rnd < 0.08f) { float s = e.boss ? 0.2f : 0.4f; e.stop = Math.Max(e.stop, s); MeterCtl(t, s); }   // Ground: Tremor
            if (HasT(t, 16) && !e.boss && e.hp > 0 && e.hp < e.max * 0.15f) { Float(e, "Finish", 4); string L = mlab; mlab = "Finisher (Dark quirk)"; Hurt(t, e, e.hp); mlab = L; }   // Dark: Finisher
        }

        /* ---------- move skills: status moves with a tower-defence job (each picked by the player); they run on their own timer ---------- */
        static readonly Dictionary<string, int> MIDC = new Dictionary<string, int>();
        public static int MID(string n) { if (MIDC.TryGetValue(n, out var id)) return id; id = DB.Moves.Where(kv => kv.Value.n == n).Select(kv => kv.Key).FirstOrDefault(); MIDC[n] = id; return id; }
        public static bool HasM(Tower t, string n) { int id = MID(n); return id != 0 && t.e.mv.Contains(id); }
        public List<Trap> traps = new List<Trap>(); public List<Decoy> decoys = new List<Decoy>();
        public Dictionary<int, float> terr = new Dictionary<int, float>(); public Weather mwx; public float mwxUntil;
        public Tower msrc; public string mlab; public Tower moving, swapping;

        float SkR(Tower t) => RANGE[3] * (1 + Math.Min(0.25f, t.e.lv / 400f) + Rescue.Mod("range")) * UpK(t, 0) * (HasT(t, 2) ? 1.15f : 1) * (t.acuK == 'r' && t.acuU > time ? 1.2f : 1);
        static bool Visible(Enemy e) => e.hp > 0 && e.d > 0 && !e.under && !(e.hide && !(e.rev > 0));
        List<Enemy> SkIn(Tower t, float r = -1) { float R = r > 0 ? r : SkR(t); return en.Where(e => Visible(e) && Dist(e.x, e.y, t.x, t.y) <= R).ToList(); }
        Enemy SkT(Tower t) { var l = SkIn(t); return l.Count > 0 ? ChooseTarget(t, l) : null; }
        void StopE(Enemy e, float s) { float v = e.boss ? s / 2 : s; e.stop = Math.Max(e.stop, v); MeterCtl(msrc, v); }
        void SlowE(Enemy e, string k, float f, float d) { e.sl[k] = new Vector2(f, time + d); MeterCtl(msrc, d * (1 - f) * 2); }   // meter: slow seconds weighted by strength
        float SkSpeed(Enemy e)
        {
            float v = 1; foreach (var k in e.sl.Keys.ToList()) { var s = e.sl[k]; if (s.y > time) v *= s.x; else e.sl.Remove(k); }
            if (e.trU > time) v *= e.trF; return v;
        }
        public int[] EnTypes(Enemy e) { if (e.tyoT == null || e.tyoU <= time) return DB.SP[e.id].t; return e.tyoAdd ? DB.SP[e.id].t.Concat(e.tyoT).Distinct().Take(3).ToArray() : e.tyoT; }
        void SkFx(int m, float x, float y, int dir) { if (DB.FxMoves.TryGetValue(m, out var f)) { var r = f.h ?? f.u; if (r != null) AddFx(r, x, y - 8 * ESPR, dir); } }
        void SkUse(Tower t, int m, Enemy e = null) { if (DB.FxMoves.TryGetValue(m, out var f) && f.u != null) AddFx(f.u, t.x, t.y, t.dir); if (e != null) { t.dir = DirRow(e.x - t.x, e.y - t.y); SkFx(m, e.x, e.y, t.dir); } t.anim = "Shoot"; t.at = 0; }
        List<Tower> Near(Tower t, float r = 90) => towers.Where(o => o != t && Dist(o.x, o.y, t.x, t.y) <= r).ToList();
        bool AnyVisible => en.Any(Visible);

        bool SkAttack(Tower t, int m, int[] st, string src)   // a full attack from a skill (Copycat, Metronome, Nature Power)
        {
            var M_ = DB.Mv(m); if (M_ == null) return false; float r = RANGE.ContainsKey(M_.c) ? TowerRange(t, m) : SkR(t);
            var list = InRange(t, r).Where(e => CanHit(t, m, e)).ToList(); if (list.Count == 0) return false;
            var tg = ChooseTarget(t, list); DB.FxMoves.TryGetValue(m, out var fxm); fxm = fxm ?? new MoveFx();
            t.dir = DirRow(tg.x - t.x, tg.y - t.y); t.anim = M_.c == 2 ? "Attack" : "Shoot"; t.at = 0;
            if (fxm.u != null) AddFx(fxm.u, t.x, t.y, t.dir);
            Action<Enemy> hit = g => { var ts = Aoe(M_) ? (M_.c == 3 ? en.Where(e => e.hp > 0 && Dist(e.x, e.y, g.x, g.y) < 46 && CanHit(t, m, e)).ToList() : list) : new List<Enemy> { g }; foreach (var e in ts) ApplyMove(t, m, e, st); };
            if (fxm.p != null && M_.c != 2 && DB.FxAnims.TryGetValue(fxm.p, out var pa)) proj.Add(new Proj { x = t.x, y = t.y - 8 * SPR, tg = tg, fx = pa, done = hit, hfx = fxm.h });
            else q2.Add((0.12f, () => { if (tg.hp > 0 || Aoe(M_)) { hit(tg); if (fxm.h != null) AddFx(fxm.h, tg.x, tg.y - 8 * ESPR, t.dir); } }));
            if (src != null) Float(t.x, t.y, src, 4); return true;
        }
        string NatureMove()   // Nature Power, Gen VII rules: the move depends on where the battle is
        {
            float now = time; bool T(int k) => terr.TryGetValue(k, out var u) && u > now;
            if (T(11)) return "Energy Ball"; if (T(17)) return "Moonblast"; if (T(12)) return "Thunderbolt"; if (T(13)) return "Psychic";
            var S = DB.TS[set]; var ty = S.types ?? new int[0]; string nm = S.name ?? "";
            bool Has(string re) => System.Text.RegularExpressions.Regex.IsMatch(nm, re, System.Text.RegularExpressions.RegexOptions.IgnoreCase);
            if (M.liq == "lava") return "Lava Plume";
            if (ty.Contains(14)) return "Ice Beam";
            if (M.liq == "water" && ty.Contains(10)) return "Hydro Pump";
            if (Has("cave|cavern|crevice|grotto|ruin|tunnel|depth|crater|chamber|underground")) return "Power Gem";
            if (ty.Contains(11) || Has("wood|forest|jungle|meadow|field|garden|grass")) return "Energy Ball";
            if (ty.Contains(4) || ty.Contains(5) || Has("sand|desert|mt |mount|peak|rock|cliff|canyon")) return "Earth Power";
            return "Tri Attack";
        }
        (int r, float d, float x, float y)? NearestPath(float x, float y)
        {
            (int r, float d, float x, float y)? b = null; float bk = 1e9f;
            for (int r = 0; r < M.routes.Count; r++) { var rt = M.routes[r]; for (float d = 0; d < rt.len; d += 6) { var p = MapGen.PathAt(rt, d); float k = Dist(p.x, p.y, x, y); if (k < bk) { bk = k; b = (r, d, p.x, p.y); } } }
            return b;
        }

        class Skill { public string n; public float cd; public Func<Tower, int, bool> act; }
        Dictionary<int, Skill> skills;
        Func<Tower, int, bool> SlowA(float f, float d) => (t, m) => { var l = SkIn(t); if (l.Count == 0) return false; foreach (var e in l) SlowE(e, "growl", f, d); SkUse(t, m, l[0]); return true; };
        Func<Tower, int, bool> Stop1(float s) => (t, m) => { var e = SkT(t); if (e == null) return false; StopE(e, s); SkUse(t, m, e); return true; };
        Func<Tower, int, bool> TypeC(int ty, bool add) => (t, m) => { var e = SkT(t); if (e == null) return false; e.tyoT = new[] { ty }; e.tyoAdd = add; e.tyoU = time + 6; SkUse(t, m, e); return true; };
        bool NoTrick(Tower t, int m) { var l = SkIn(t).Where(e => e.prot != 0 || e.healMv != 0 || e.dashMv != 0 || e.tele).ToList(); var e = l.Count > 0 ? ChooseTarget(t, l) : null; if (e == null) return false; e.nt = time + 6; Float(e, "No tricks", 4); SkUse(t, m, e); return true; }
        Func<Tower, int, bool> TrapA(string kind) => (t, m) => { if (t.tp == null) t.tp = NearestPath(t.x, t.y); if (t.tp == null) return false; var p = t.tp.Value; traps.RemoveAll(x => x.t == t && x.m == m); traps.Add(new Trap { t = t, m = m, kind = kind, r = p.r, d = p.d, x = p.x, y = p.y }); return true; };
        bool DecoyA(Tower t, int m) { var p = NearestPath(t.x, t.y); if (p == null) return false; decoys.RemoveAll(x => x.t == t); decoys.Add(new Decoy { t = t, m = m, r = p.Value.r, d = p.Value.d, x = p.Value.x, y = p.Value.y }); return true; }
        Func<Tower, int, bool> TeamB(Action<Tower, float> set, float dur) => (t, m) => { if (!AnyVisible) return false; foreach (var o in towers) set(o, time + dur); SkUse(t, m); Float(t.x, t.y, DB.Mv(m).n, 4); return true; };
        Func<Tower, int, bool> NearB(Action<Tower, float> set, float dur) => (t, m) => { var n = Near(t); if (n.Count == 0 || !AnyVisible) return false; foreach (var o in n) set(o, time + dur); SkUse(t, m); return true; };
        Func<Tower, int, bool> SelfB(Action<Tower, float> set, float dur) => (t, m) => { if (SkIn(t, SkR(t) * 1.2f).Count == 0) return false; set(t, time + dur); SkUse(t, m); return true; };
        Func<Tower, int, bool> WxSk(string k) => (t, m) => { if (!AnyVisible || bwx != null || pwx != null) return false; mwx = new Weather { k = k }; mwxUntil = time + 20; SyncWeather(); SkUse(t, m); Float(t.x, t.y, DB.Mv(m).n, 4); return true; };
        Func<Tower, int, bool> Terrain(int ty) => (t, m) => { if (!AnyVisible) return false; terr[ty] = time + 10; SkUse(t, m); Float(t.x, t.y, DB.Mv(m).n, 4); return true; };
        bool CopyB(Tower t, int m) { var e = SkIn(t).FirstOrDefault(x => x.bst[6] > 0); if (e == null) return false; t.buf[6] = Math.Max(t.buf[6], e.bst[6]); t.buft = 12; SkUse(t, m, e); return true; }
        bool Copycat(Tower t, int m)
        {
            var o = towers.Where(x => x != t).OrderBy(x => Dist(x.x, x.y, t.x, t.y)).FirstOrDefault(); if (o == null) return false;
            var ms = o.e.mv.Where(x => DB.MoveUse(x) == "dmg").OrderByDescending(x => DB.Mv(x).p).ToList(); return ms.Count > 0 && SkAttack(t, ms[0], DB.MonStats(o.e), DB.Mv(m).n);
        }
        static readonly Dictionary<string, string> SKDESC = new Dictionary<string, string>();
        public static string SkillDesc(string n) { BuildDesc(); return SKDESC.TryGetValue(n, out var d) ? d : null; }
        static void BuildDesc()
        {
            if (SKDESC.Count > 0) return; const string slow = "Enemies in range move 20% slower for 3 s";
            foreach (var n in new[] { "Growl", "Baby-Doll Eyes", "Play Nice", "Feather Dance", "Noble Roar", "Parting Shot", "Eerie Impulse", "Confide" }) SKDESC[n] = slow;
            void D(string n, string d) => SKDESC[n] = d;
            D("Sand Attack", "The target stops for 0.6 s (every 6 s)"); D("Mean Look", "The target stops for 1 s (every 12 s)"); D("Block", "The target stops for 1 s (every 12 s)"); D("Attract", "The target stops for 1.2 s (every 12 s)");
            D("Quash", "The target moves 50% slower for 2 s (every 10 s)"); D("Smokescreen", "Enemies in range stop for 0.4 s (every 8 s)"); D("Fairy Lock", "Enemies in range stop for 1 s (every 30 s)");
            D("Charm", "The target walks backward for 1.5 s (every 8 s)"); D("Roar", "Pushes the target back along the path (not bosses, every 10 s)"); D("Whirlwind", "Pushes the target back along the path (not bosses, every 10 s)");
            D("Curse", "The target loses 25% of its max HP over 8 s (bosses 10%, every 12 s)"); D("Disable", "The target can't shield, heal, dash or teleport for 6 s");
            D("Soak", "The target becomes pure Water type for 6 s"); D("Magic Powder", "The target becomes pure Psychic type for 6 s"); D("Trick-or-Treat", "The target also counts as Ghost type for 6 s"); D("Forest’s Curse", "The target also counts as Grass type for 6 s");
            D("Electrify", "Electric attacks deal double damage to the target for 6 s (every 12 s)"); D("Gastro Acid", "The target's ability stops working for 8 s");
            D("Haze", "Removes the stat boosts of enemies in range (every 10 s)"); D("Topsy-Turvy", "Turns an enemy's stat boosts into drops (every 12 s)");
            D("Pain Split", "A non-boss target over half HP loses about a quarter of its max HP (every 15 s)"); D("Guard Split", "The target's defences drop 25% for 6 s (every 12 s)");
            D("Octolock", "The target stops for 1 s, then its defences drop 20% for 6 s (every 14 s)"); D("Perish Song", "Non-boss enemies in range lose 30% of their max HP 6 s later (every 30 s)");
            D("Sweet Scent", "Enemies in range are 2x as likely to ask to join if knocked out within 5 s"); D("Psych Up", "Copies an enemy's Speed boosts as attack speed (every 15 s)"); D("Heart Swap", "Copies an enemy's Speed boosts as attack speed (every 15 s)");
            D("Trick Room", "For 6 s the fastest enemies in range become the slowest (every 30 s)"); D("Psycho Shift", "Copies a status condition onto another enemy in range (every 10 s)");
            D("Speed Swap", "The target moves 40% slower and this Pokémon attacks 40% faster for 4 s (every 12 s)");
            D("Focus Energy", "Much higher critical-hit chance for 10 s (every 20 s)"); D("Laser Focus", "Every 8 s its next attack is a sure critical hit"); D("Charge", "Every 8 s its next Electric attack deals double damage");
            D("Double Team", "For 5 s its attacks hit twice (every 20 s)"); D("Take Heart", "Its special attacks deal +20% for 8 s (every 15 s)"); D("Acupressure", "A random boost for 6 s: +30% damage, attack speed or +20% range (every 15 s)");
            D("Helping Hand", "Teammates close by deal +25% damage for 6 s (every 15 s)"); D("Encore", "Every 10 s, the next attack of a teammate close by happens twice"); D("Instruct", "Every 10 s, the next attack of a teammate close by happens twice");
            D("Tailwind", "All your Pokémon attack 25% faster for 6 s (every 30 s)");
            D("Rain Dance", "Rain for 20 s (every 60 s)"); D("Sunny Day", "Sun for 20 s (every 60 s)"); D("Sandstorm", "A sandstorm for 20 s (every 60 s)"); D("Hail", "Hail for 20 s (every 60 s)"); D("Snowscape", "Hail for 20 s (every 60 s)");
            D("Electric Terrain", "Your team's Electric moves deal +30% for 10 s (every 30 s)"); D("Grassy Terrain", "Your team's Grass moves deal +30% for 10 s (every 30 s)");
            D("Misty Terrain", "Your team's Fairy moves deal +30% for 10 s (every 30 s)"); D("Psychic Terrain", "Your team's Psychic moves deal +30% for 10 s (every 30 s)");
            D("Stealth Rock", "Rocks on the nearest path: each enemy crossing takes Rock damage once (renewed every 20 s)"); D("Spikes", "Spikes on the nearest path: each enemy crossing loses 8% of its max HP once (renewed every 20 s)");
            D("Toxic Spikes", "Spikes on the nearest path poison enemies crossing (renewed every 20 s)"); D("Sticky Web", "A web on the nearest path: enemies crossing move 40% slower for 3 s (renewed every 20 s)");
            D("Substitute", "A decoy on the path holds enemies up for 2 s (every 20 s)"); D("Shed Tail", "A decoy on the path holds enemies up for 2 s (every 20 s)");
            D("Copycat", "Uses the nearest teammate's strongest attack at its power (every 6 s)"); D("Mimic", "Uses the nearest teammate's strongest attack at its power (every 6 s)");
            D("Metronome", "Uses a random attack (every 5 s)"); D("Nature Power", "Uses an attack that depends on the map (every 6 s)");
            D("Endure", "Attacks 30% faster while you have under 25 lives"); D("Ingrain", "+5% damage for every 10 s it stays placed (up to +30%)"); D("Baton Pass", "Its stat boosts also apply to teammates close by");
            D("Lock-On", "Its attacks never miss"); D("Mind Reader", "Its attacks never miss"); D("Power Trick", "Physical attacks use its Attack or Defense, whichever is higher"); D("Defog", "Sees hidden Ghost types");
            D("Mist", "Bosses in its range can't raise their stats"); D("Transform", "Fights with the stats and moves of your strongest placed teammate, at its own level");
            D("Teleport", "Can be moved to a new spot during battle for free"); D("Ally Switch", "Can swap spots with a placed teammate during battle for free");
            D("Sketch", "Out of battle, can be swapped for a move learned by a Pokémon you've seen"); D("Splash", "Enemies right next to it move 10% slower");
            D("Baneful Bunker", "Enemies right next to it may get poisoned"); D("Burning Bulwark", "Enemies right next to it may get burned"); D("Silk Trap", "Enemies right next to it move 30% slower for 2 s");
        }
        public static bool IsSkill(int m) { var M_ = DB.Mv(m); return M_ != null && SkillDesc(M_.n) != null; }

        Dictionary<int, Skill> Skills()
        {
            if (skills != null) return skills;
            var D = new Dictionary<string, (float cd, Func<Tower, int, bool> act)>();
            foreach (var n in new[] { "Growl", "Baby-Doll Eyes", "Play Nice", "Feather Dance", "Noble Roar", "Parting Shot", "Eerie Impulse", "Confide" }) D[n] = (6, SlowA(0.8f, 3));
            D["Sand Attack"] = (6, Stop1(0.6f)); D["Mean Look"] = (12, Stop1(1)); D["Block"] = (12, Stop1(1)); D["Attract"] = (12, Stop1(1.2f));
            D["Quash"] = (10, (t, m) => { var e = SkT(t); if (e == null) return false; SlowE(e, "quash", 0.5f, 2); SkUse(t, m, e); return true; });
            D["Smokescreen"] = (8, (t, m) => { var l = SkIn(t); if (l.Count == 0) return false; foreach (var e in l) e.stop = Math.Max(e.stop, 0.4f); MeterCtl(t, 0.4f * l.Count); SkUse(t, m, l[0]); return true; });
            D["Fairy Lock"] = (30, (t, m) => { var l = SkIn(t); if (l.Count == 0) return false; foreach (var e in l) StopE(e, 1); SkUse(t, m, l[0]); return true; });
            D["Charm"] = (8, (t, m) => { var e = SkT(t); if (e == null) return false; e.back = time + (e.boss ? 0.75f : 1.5f); MeterCtl(t, e.boss ? 0.75f : 1.5f); SkUse(t, m, e); return true; });
            D["Roar"] = D["Whirlwind"] = (10, (t, m) => { var l = SkIn(t).Where(e => !e.boss).ToList(); var e = l.Count > 0 ? ChooseTarget(t, l) : null; if (e == null) return false; e.d = Math.Max(1, e.d - 60); e.placed = false; MeterCtl(t, 1); SkUse(t, m, e); return true; });
            D["Curse"] = (12, (t, m) => { var e = SkT(t); if (e == null) return false; e.cuLeft = e.max * (e.boss ? 0.1f : 0.25f); e.cuDps = e.cuLeft / 8; e.cuT = t; SkUse(t, m, e); return true; });
            D["Disable"] = (8, NoTrick);
            D["Soak"] = (8, TypeC(10, false)); D["Magic Powder"] = (8, TypeC(13, false)); D["Trick-or-Treat"] = (8, TypeC(7, true)); D["Forest’s Curse"] = (8, TypeC(11, true));
            D["Electrify"] = (12, (t, m) => { var e = SkT(t); if (e == null) return false; e.elz = time + 6; SkUse(t, m, e); return true; });
            D["Gastro Acid"] = (10, (t, m) => { var l = SkIn(t).Where(e => !string.IsNullOrEmpty(e.ak) && e.akOff <= 0).ToList(); var e = l.Count > 0 ? ChooseTarget(t, l) : null; if (e == null) return false; e.ak0 = e.ak; e.ak = ""; e.akOff = time + 8; Float(e, "Ability off", 4); SkUse(t, m, e); return true; });
            D["Haze"] = (10, (t, m) => { var l = SkIn(t).Where(e => e.bst.Any(v => v > 0)).ToList(); if (l.Count == 0) return false; foreach (var e in l) e.bst = new int[7]; SkUse(t, m, l[0]); return true; });
            D["Topsy-Turvy"] = (12, (t, m) => { var e = SkIn(t).FirstOrDefault(x => x.bst.Any(v => v > 0)); if (e == null) return false; for (int i = 0; i < 7; i++) e.bst[i] = -e.bst[i]; SkUse(t, m, e); return true; });
            D["Pain Split"] = (15, (t, m) => { var l = SkIn(t).Where(e => !e.boss && e.hp > e.max / 2).ToList(); var e = l.Count > 0 ? ChooseTarget(t, l) : null; if (e == null) return false; float to = Mathf.Ceil((e.hp + e.max / 2) / 2); Hurt(t, e, e.hp - to); SkUse(t, m, e); return true; });
            D["Guard Split"] = (12, (t, m) => { var e = SkT(t); if (e == null) return false; e.gs = time + 6; e.gsf = 0.75f; SkUse(t, m, e); return true; });
            D["Octolock"] = (14, (t, m) => { var e = SkT(t); if (e == null) return false; StopE(e, 1); e.gs = time + 6; e.gsf = 0.8f; SkUse(t, m, e); return true; });
            D["Perish Song"] = (30, (t, m) => { var l = SkIn(t).Where(e => !e.boss && e.pm <= 0).ToList(); if (l.Count == 0) return false; foreach (var e in l) { e.pm = time + 6; e.pmT = t; } SkUse(t, m, l[0]); Float(t.x, t.y, "Perish Song", 4); return true; });
            D["Sweet Scent"] = (10, (t, m) => { var l = SkIn(t); if (l.Count == 0) return false; foreach (var e in l) e.lure = time + 5; SkUse(t, m, l[0]); return true; });
            D["Psych Up"] = D["Heart Swap"] = (15, CopyB);
            D["Trick Room"] = (30, (t, m) => { var l = SkIn(t); if (l.Count < 2) return false; float lo = l.Min(e => e.spd), hi = l.Max(e => e.spd); foreach (var e in l) { e.trF = Mathf.Clamp((lo + hi - e.spd) / e.spd, 0.4f, 1.5f); e.trU = time + 6; } SkUse(t, m, l[0]); return true; });
            D["Psycho Shift"] = (10, (t, m) => { var l = SkIn(t); var a = l.FirstOrDefault(e => e.sts != null && e.sts != "yawn"); var b = a == null ? null : l.FirstOrDefault(e => e != a && e.sts == null); if (b == null) return false; Inflict(b, a.sts, t); SkUse(t, m, b); return true; });
            D["Speed Swap"] = (12, (t, m) => { var e = SkT(t); if (e == null) return false; SlowE(e, "swap", 0.6f, 4); t.ssw = time + 4; SkUse(t, m, e); return true; });
            D["Focus Energy"] = (20, SelfB((t, u) => t.fe = u, 10)); D["Take Heart"] = (15, SelfB((t, u) => t.thr = u, 8)); D["Double Team"] = (20, SelfB((t, u) => t.dteam = u, 5));
            D["Laser Focus"] = (8, (t, m) => { if (t.lf) return false; t.lf = true; return true; }); D["Charge"] = (8, (t, m) => { if (t.chg) return false; t.chg = true; return true; });
            D["Acupressure"] = (15, (t, m) => { if (SkIn(t, SkR(t) * 1.2f).Count == 0) return false; t.acuK = "dsr"[UnityEngine.Random.Range(0, 3)]; t.acuU = time + 6; SkUse(t, m); Float(t.x, t.y, t.acuK == 'd' ? "Power up" : t.acuK == 's' ? "Speed up" : "Range up", 4); return true; });
            D["Helping Hand"] = (15, NearB((t, u) => t.hh = u, 6));
            D["Encore"] = D["Instruct"] = (10, (t, m) => { var n = Near(t).Where(o => !o.enc).ToList(); if (n.Count == 0 || !AnyVisible) return false; n[0].enc = true; SkUse(t, m); return true; });
            D["Tailwind"] = (30, TeamB((t, u) => t.tw = u, 6));
            D["Rain Dance"] = (60, WxSk("rain")); D["Sunny Day"] = (60, WxSk("sun")); D["Sandstorm"] = (60, WxSk("sand")); D["Hail"] = (60, WxSk("hail")); D["Snowscape"] = (60, WxSk("hail"));
            D["Electric Terrain"] = (30, Terrain(12)); D["Grassy Terrain"] = (30, Terrain(11)); D["Misty Terrain"] = (30, Terrain(17)); D["Psychic Terrain"] = (30, Terrain(13));
            D["Stealth Rock"] = (20, TrapA("rock")); D["Spikes"] = (20, TrapA("spikes")); D["Toxic Spikes"] = (20, TrapA("toxic")); D["Sticky Web"] = (20, TrapA("web"));
            D["Substitute"] = D["Shed Tail"] = (20, DecoyA);
            D["Copycat"] = D["Mimic"] = (6, Copycat);
            D["Metronome"] = (5, (t, m) => { var all = DB.Moves.Keys.Where(x => DB.MoveUse(x) == "dmg" && !OHKO.Contains(x)).ToList(); return SkAttack(t, all[UnityEngine.Random.Range(0, all.Count)], DB.MonStats(t.e), "Metronome"); });
            D["Nature Power"] = (6, (t, m) => { string n = NatureMove(); return SkAttack(t, MID(n), DB.MonStats(t.e), n); });
            skills = new Dictionary<int, Skill>();
            foreach (var kv in D) { int id = MID(kv.Key); if (id != 0) skills[id] = new Skill { n = kv.Key, cd = kv.Value.cd, act = kv.Value.act }; }
            return skills;
        }

        /* per-tick work: skill timers, traps, decoys, adjacency auras */
        void SkillTick(float dt)
        {
            var S = Skills(); bool wave = phase == "wave";
            foreach (var t in towers)
            {
                foreach (int m in t.e.mv.ToList())
                {
                    if (!wave || !S.TryGetValue(m, out var s)) continue;
                    float c = (t.skc.TryGetValue(m, out var v) ? v : 1 + rnd) - dt;
                    if (c <= 0) { msrc = t; mlab = s.n; c = s.act(t, m) ? s.cd : 0.5f; msrc = null; }
                    t.skc[m] = c;
                }
                if (!wave) continue;
                bool sp = HasM(t, "Splash"), silk = HasM(t, "Silk Trap"), bb = HasM(t, "Baneful Bunker"), bw = HasM(t, "Burning Bulwark");
                if (sp || silk || bb || bw) foreach (var e in en) if (Visible(e) && Dist(e.x, e.y, t.x, t.y) < 38)
                        {
                            if (sp) e.sl["splash"] = new Vector2(0.9f, time + 1); if (silk) e.sl["silk"] = new Vector2(0.7f, time + 2); MeterCtl(t, dt * (silk ? 0.6f : 0.2f));
                            if (bb && e.sts == null && rnd < 0.5f * dt) Inflict(e, "poison", t); if (bw && e.sts == null && rnd < 0.5f * dt) Inflict(e, "burn", t);
                        }
            }
            foreach (var tr in traps.ToList()) foreach (var e in en.ToList())
                    if (Visible(e) && !e.air && e.r == tr.r && Math.Abs(e.d - tr.d) < 10 && !tr.hit.Contains(e))
                    {
                        tr.hit.Add(e); msrc = tr.t; mlab = DB.Mv(tr.m).n;
                        if (tr.kind == "rock") Hurt(tr.t, e, Math.Max(1, Mathf.Floor(e.max * 0.125f * DB.Eff(5, EnTypes(e)))));
                        else if (tr.kind == "spikes") Hurt(tr.t, e, Math.Max(1, Mathf.Floor(e.max * 0.08f)));
                        else if (tr.kind == "toxic") Inflict(e, "poison", tr.t);
                        else if (tr.kind == "web") SlowE(e, "web", 0.6f, 3);
                        msrc = null;
                    }
            traps.RemoveAll(x => !towers.Contains(x.t)); decoys.RemoveAll(x => !towers.Contains(x.t) || (x.u > 0 && x.u < time));
            foreach (var k in terr.Keys.ToList()) if (terr[k] < time) terr.Remove(k);
            if (mwx != null && mwxUntil < time) { mwx = null; SyncWeather(); }
            foreach (var z in zap) z.t -= dt; zap.RemoveAll(z => z.t <= 0);
        }
        bool DecoyBlocks(Enemy e) { if (e.air || e.boss) return false; foreach (var dc in decoys) if (dc.r == e.r && e.d < dc.d && dc.d - e.d < 8) { if (dc.u <= 0) dc.u = time + 2; return true; } return false; }
        int BufOf(Tower t, int k) { int v = t.buf[k]; foreach (var o in towers) if (o != t && o.buft > 0 && HasM(o, "Baton Pass") && Dist(o.x, o.y, t.x, t.y) <= 90) v = Math.Max(v, o.buf[k]); return v; }
        Tower TransformSrc(Tower t) => HasM(t, "Transform") ? towers.Where(x => x != t && !HasM(x, "Transform")).OrderByDescending(x => x.e.lv).FirstOrDefault() : null;

        /* ---------- damage meter: what each of your Pokémon did this battle (HP actually lost, no overkill, shields don't count) ---------- */
        public Dictionary<int, MeterRow> meter = new Dictionary<int, MeterRow>();
        MeterRow Mtr(Tower t) { if (t == null || t.e == null) return null; if (!meter.TryGetValue(t.e.u, out var r)) meter[t.e.u] = r = new MeterRow { u = t.e.u, id = t.e.id }; return r; }
        void MeterDmg(Tower t, float amt, string label, bool dot = false) { var m = Mtr(t); if (m == null || amt <= 0) return; m.id = t.e.id; m.dmg += amt; label = label ?? "Other"; m.br[label] = (m.br.TryGetValue(label, out var v) ? v : 0) + amt; if (dot) m.dot += amt; }
        void MeterCtl(Tower t, float s) { var m = Mtr(t); if (m != null && s > 0) m.ctl += s; }
    }
}
