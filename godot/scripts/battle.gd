extends Node
# Route Defense - battle: waves, towers, moves, status, XP, recruiting (ported from the HTML version's battle.js)
# Autoload "BT". The battle state B is a Dictionary like the HTML's object; towers and wild Pokémon are Dictionaries too.
# GDScript notes: a missing key is an error (JS gives undefined), so optional fields are read with .get();
# == on Dictionaries compares contents, so "the same tower / enemy" is checked with is_same().

signal wave_started
signal ask_join
signal finished

var B = null
const RANGE := {2: 66, 3: 106, 1: 94}
static func STAGE(s: float) -> float: return (2 + s) / 2.0 if s >= 0 else 2 / (2 - s)
const OHKO := [12, 32, 90, 329]
const FIXED := {69: "lv", 101: "lv", 82: 40, 49: 20, 162: "half"}
const MAXTIER := 20
const XPMUL := 0.4   # slower leveling: about Lv50 by tier 10
var TZ := 24
var _eid := 0; var _tid := 0

func G(): return C.G
func mod(k: String) -> float: return C.mod(k)
func SP(id: int) -> Dictionary: return C.SP[id]
func mvd(m: int) -> Dictionary: return C.mv(m)
static func has_ref(a: Array, o) -> bool:
	for x in a: if is_same(x, o): return true
	return false
static func hyp(ax: float, ay: float, bx: float, by: float) -> float: return Vector2(ax - bx, ay - by).length()
func rnd() -> float: return randf()
func music(k: String) -> void: if has_node("/root/Snd"): get_node("/root/Snd").play_music(k)
func sfx(k: String) -> void: if has_node("/root/Snd"): get_node("/root/Snd").sfx(k)

static func stable_sort(a: Array, key: Callable) -> Array:   # sorts by key ascending; equal keys keep their order
	var idx := []
	for i in a.size(): idx.append([key.call(a[i]), i])
	idx.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := []
	for q in idx: out.append(a[q[1]])
	return out
# ---------- waves ----------
func lv_range(tier: float) -> Array:   # tier here is the fight's threat (threat_tier); tier 10: Lv40-56, Lv100 near tier 20
	var a := clampi(int(round(2 + (tier - 1) * 4.2)), 2, 95)
	return [a, clampi(a + 3 + int(round(tier * 0.3)), 3, 100)]
# tier traits: each one only for wild Pokémon that really know the move (or have the ability) at their level
const PROTECT_MOVES := [182, 197, 588, 596, 661, 792, 852, 908]
const WX_MOVES := {240: "rain", 241: "sun", 201: "sand", 258: "hail", 883: "hail"}
const TRAITS := [[3, "Ghost types hide, Dig users burrow, Steel / Rock armoured"], [5, "Legendary bosses"], [6, "Healers: self-healing moves restore HP once when low; Regenerator heals slowly"],
	[9, "Protect users raise a shield when hit"], [12, "Sprinters: speed-boosting and priority-move users dash"], [15, "Teleport users jump ahead along the path"]]
func wild_traits(id: int, lv: int, ak: String, tier: float) -> Dictionary:
	var ms := []
	for m in C.moves_at(id, lv):
		var M := mvd(m)
		if not M.is_empty(): ms.append([m, M])
	var o := {}
	if tier >= 6:
		for x in ms:
			if x[1].tg == 7 and x[1].get("hl", 0) > 0: o.heal = {"m": x[0], "hl": x[1].hl / 100.0}; break
		if ak == "regenerator": o.regen = 1
	if tier >= 9:
		for x in ms: if PROTECT_MOVES.has(x[0]): o.prot = x[0]; break
	if tier >= 12:
		for x in ms:
			var M: Dictionary = x[1]; var up := false
			for s in M.sc: if s[0] == 6 and s[1] > 0: up = true
			if (M.tg == 7 and up) or (M.get("pr", 0) > 0 and M.get("p", 0) > 0): o.dashMv = x[0]; break
	if tier >= 15:
		for x in ms: if x[0] == 100: o.tele = 100
	return o
# rarity by catch rate: Common 190+, Uncommon 120-189, Rare 46-119, Very rare 45 or less; each spawns less often than the last
const RARITY := ["Common", "Uncommon", "Rare", "Very rare"]
const RARW := [1.0, 0.6, 0.35, 0.15]
func rar_of(m: Dictionary) -> int: return 0 if m.cr >= 190 else (1 if m.cr >= 120 else (2 if m.cr >= 46 else 3))
func rar_weight(m: Dictionary) -> float:   # the Rescue tree's rare-find nodes help Rare and Very rare ones
	var k := rar_of(m); return RARW[k] * (1 + mod("rare") if k >= 2 else 1.0)
func wave_count(tier: int) -> int: return 40 + (tier - 1)   # 40 waves at tier 1 on every map, +1 per tier (59 at tier 20)
# which wild Pokémon a map and tier can send: the wave builder draws from these, and the route panel lists them
func spawn_info(set_idx: int, tier0: int) -> Dictionary:
	var tier: float = C.threat_tier(set_idx, tier0); var S: Dictionary = C.DB.ts[set_idx]
	var maxB: float = 300 + tier * 30 + C.map_group(set_idx) * 25; var minB: float = min(maxB - 190, 480)   # the floor stops at 480 so top tiers keep the strongest species
	var hasTy := func(m) -> bool:
		for x in m.t: if S.types.has(x): return true
		return false
	var pool := []
	var SPC: Dictionary = C.SPECIAL.get(C.special_of(set_idx), {})
	if SPC.size():   # special maps: their own Pokémon only
		for id in SPC.pool: if C.SP.has(id) and C.SP[id].anim: pool.append(C.SP[id])
		var bs := []
		for id in SPC.boss: if C.SP.has(id) and C.SP[id].anim: bs.append(C.SP[id])
		var rr := {}
		for m in pool + bs: rr[m.id] = rar_of(m)
		return {"tier": tier, "minB": minB, "maxB": maxB, "pool": pool, "heavy": stable_sort(pool, func(m): return -(m.b[0] + m.b[2])).slice(0, 6), "bosses": bs, "legs": [], "rar": rr}
	for m in C.DB.dex.mon:
		if m.anim and not m.get("lg", 0) and hasTy.call(m) and m.bst <= maxB and m.bst >= minB and (tier >= 3 or m.cr > 45): pool.append(m)
	if pool.size() < 8:
		pool = []
		for m in C.DB.dex.mon: if m.anim and not m.get("lg", 0) and hasTy.call(m) and m.bst <= maxB + 60: pool.append(m)
	# stable sorts (ties keep the pool's order, as JavaScript's sort does), so the same seed sends the same waves as the HTML version
	var heavy := stable_sort(pool, func(m): return -(m.b[0] + m.b[2])).slice(0, 6)
	var bosses := stable_sort(pool, func(m): return -m.bst).slice(0, 3)
	var legs := []
	if tier >= 5:
		for m in C.DB.dex.mon:
			if m.anim and m.get("lg", 0) and hasTy.call(m) and m.bst <= 480 + tier * 25 and (m.lg == 1 or tier >= 10): legs.append(m)
	var rar := {}
	for m in pool: rar[m.id] = rar_of(m)
	return {"tier": tier, "minB": minB, "maxB": maxB, "pool": pool, "heavy": heavy, "bosses": bosses, "legs": legs, "rar": rar}
var legend_boss := []   # set by the HUD before start_battle: the Legendary challenge's legendary (or none)
func waves_for(set_idx: int, tier0: int, R, night := false) -> Array:
	var SI := spawn_info(set_idx, tier0); var tier: float = SI.tier; var W := wave_count(tier0)
	var G4: Array = C.MAPGROUP[C.map_group(set_idx)]; var maxB: float = SI.maxB; var minB: float = SI.minB; var pool: Array = SI.pool
	var lr := lv_range(tier); var base: int = min(98, lr[0]); var top: int = min(100, lr[1])
	var pickW := func(target: float) -> Dictionary:
		var w := []; var tot := 0.0
		for m in pool:
			var v := rar_weight(m) / (1 + absf(m.bst - target) / 40.0) * (3.0 if (night and is_night_mon(m.id)) else 1.0) * (2.0 if _season_fav(m) else 1.0); w.append(v); tot += v
		var r: float = R.next() * tot; var k := 0
		r -= w[k]
		while r > 0 and k < w.size() - 1: k += 1; r -= w[k]
		return pool[k]
	var waves := []
	for w in range(1, W + 1):
		var f := w / float(W); var lv := int(round(base + (top - base) * pow(f, 1.3))); var target := minB + (maxB - minB) * f
		var list := []
		if w == W:   # boss wave
			var boss = null
			if tier >= 5:
				var leg: Array = SI.legs
				if leg.size() and R.next() < 0.5 + mod("legend"): boss = leg[int(floor(R.next() * leg.size()))]
			if boss == null: boss = SI.bosses[int(floor(R.next() * min(min(3, pool.size()), SI.bosses.size())))]
			if legend_boss.size(): boss = C.SP[legend_boss[int(floor(R.next() * legend_boss.size()))]]   # Legendary challenge
			var n := int(round((6 + tier) * G4[4]))
			for i in n: list.append({"id": pickW.call(target).id, "lv": lv, "gap": 0.6})
			list.append({"id": boss.id, "lv": min(100, top + (8 if legend_boss.size() else 3)), "gap": 2.5, "boss": 1})
		elif w % 5 == 0:   # heavy wave: few strong ones
			var n := int(round((3 + tier * 0.4 + w * 0.15) * G4[4]))
			var heavy: Array = SI.heavy
			for i in n: list.append({"id": heavy[int(floor(R.next() * heavy.size()))].id, "lv": min(100, lv + 2), "gap": 1.6})
		else:
			var n := int(round((4 + w * (0.6 if tier == 1 else 0.85) + tier * 0.5) * G4[4]))
			var kinds := [pickW.call(target), pickW.call(target), pickW.call(target)]
			kinds = kinds.slice(0, 1 + int(floor(R.next() * 3)))
			var gap := clampf(1.05 - w * 0.025, 0.4, 1.05) / sqrt(G4[4])
			for i in n: list.append({"id": kinds[i % kinds.size()].id, "lv": max(1, lv - (1 if R.next() < 0.3 else 0)), "gap": gap})
		waves.append(list)
	# rival rescue teams (the PMD games' own rivals): on some maps one races through a wave, faster and tougher than the
	# wild ones; knock out all three for a reward, each one that gets through costs 5 lives
	if tier0 >= 2 and W >= 8 and R.next() < 0.3:
		var team: Array = RIVALS[int(floor(R.next() * RIVALS.size()))]
		var cand := []
		for w in range(3, W): if w % 5 != 0: cand.append(w)
		var w: int = cand[int(floor(R.next() * cand.size()))]
		var lv: int = min(100, int(round(base + (top - base) * pow(w / float(W), 1.3))) + 3)
		var at: int = int(waves[w - 1].size() / 2)
		for i in team[1].size():
			if C.SP.has(team[1][i]) and SP(team[1][i]).anim: waves[w - 1].insert(at + i, {"id": team[1][i], "lv": lv, "gap": 0.5, "rival": team[0]})
	return waves
const RIVALS := [["Team Meanies", [94, 23, 308]], ["Team ACT", [65, 6, 248]], ["Team Skull", [435, 41, 109]], ["Team Charm", [428, 282, 308]]]

# ---------- start ----------
# ---- night (the user's choice): Ghost and Dark Pokémon deal 20% more (wild ones, which never attack, get 20% more HP),
# and night Pokémon turn up 3x as often: the species the main games only or mostly let you find at night (PokeAPI
# encounter data: night encounters at least twice their morning / day ones, in the games with time of day: GSC, DPPt,
# HGSS) plus all Ghost and Dark types. Day and night share the map's tiers and stars.
const NIGHT_SPECIES := [43, 44, 48, 49, 60, 92, 96, 97, 120, 163, 164, 167, 168, 183, 194, 198, 200, 202, 215, 228, 332, 354, 355, 356, 361, 364, 402, 419, 422, 423, 479]
func _season_fav(m: Dictionary) -> bool:   # the season's favoured types (C.SEASONS)
	for x in C.SEASONS[C.season()][1]: if m.t.has(x): return true
	return false
const SHINY_RATE := 1.0 / 400.0; const ALPHA_RATE := 1.0 / 200.0
# ---- Empowerment Seed: once per battle. A Pokémon with an animated Mega / Primal form Mega Evolves for the rest of the
# battle (that form's stats, types and ability); any other is Awakened: 30% more damage and attack speed.
func empower(t: Dictionary, mega := 0) -> void:
	if B.get("empowered", false): return
	B.empowered = true
	if mega and C.SP.has(mega):
		t.e.mega_from = t.e.id; t.e.ab_from = t.e.ab
		var ml: Array = C.SP[mega].get("ab", []); t.e.ab = ml[0][0] if ml.size() else t.e.ab
		t.e.id = mega
	else: t.awk = true
	add_fx("eos000/anim01", t.x, t.y, 0); t.anim = "Shoot"; t.at = 0.0
	if has_node("/root/Snd"): get_node("/root/Snd").sfx("evo")
func is_night_mon(id: int) -> bool: return NIGHT_SPECIES.has(id) or SP(id).t.has(7) or SP(id).t.has(16)
func start_battle(set_idx: int, tier: int, seed: int, team: Array, portrait: bool, aspect: float, night := false) -> void:
	C.restore_forms()
	if night:   # Shaymin's Sky Forme needs daylight: at night it fights in its Land Forme
		for e in team: if e.id == 10006: e.mega_from = e.id; e.ab_from = e.ab; e.ab = C.ability_after_evolve(e.id, 492, e.ab); e.id = 492
	var R = MG.Rng.new(seed ^ 0x5bd1e995)
	var M := MG.gen_map(set_idx, portrait, seed, null, aspect, tier)
	var th: float = C.threat_tier(set_idx, tier)
	B = {"M": M, "set": set_idx, "tier": tier, "th": th, "seed": seed, "team": team, "portrait": portrait, "aspect": aspect, "waves": waves_for(set_idx, tier, R, night), "night": night, "legend": legend_boss.size() > 0, "season": C.season(), "snowlook": C.season() == 3 and land_kind(set_idx) == "grass", "wave": 0, "phase": "build",
		"lives": 100, "cash": int(round(220 + th * 60 + mod("startCash"))), "weather": null, "towers": [], "en": [], "proj": [], "fx": [], "fl": [], "q": [], "qt": 0.0, "time": 0.0,
		"speed": 1, "sel": null, "placing": null, "ghost": null, "auto": false, "recruits": [], "asks": [], "declined": {}, "xpLog": {}, "kills": 0, "over": false, "paused": false,
		"q2": [], "traps": [], "decoys": [], "zap": [], "terr": {}, "meter": {}, "bwx": null, "pwx": null, "mwx": null, "mlab": "", "msrc": null, "chain": 0}
	for e in team: G().seen[e.id] = 1
	music(C.DB.ts[set_idx].name)
func start_wave() -> void:
	if B == null or B.phase != "build" or B.wave >= B.waves.size(): return
	B.q = []
	for x in B.waves[B.wave]: B.q.append(x.duplicate())
	B.qt = 0.4; B.wave += 1; B.phase = "wave"
	wave_started.emit()
	if B.wave % 5 == 0 and B.wave != B.waves.size() and C.DB.snd.music.has("_heavy"): music("_heavy")   # heavy waves: Monster House
	if B.wave == B.waves.size():
		var leg := false
		for x in B.waves[B.wave - 1]: if x.get("boss", 0) and SP(x.id).get("lg", 0): leg = true
		music(("_e" if C.DB.ts[B.set].game == "E" else "_") + ("legend" if leg else "boss"))
func spawn(s: Dictionary, d := 0.0) -> Dictionary:
	var nat: int = C.roll_nat(); var iv: Array = C.roll_iv(); var sp := SP(s.id); var st: Array = C.calc_stats(s.id, s.lv, iv, nat)
	var hpm: int = (3 if sp.get("lg", 0) else 4) if s.get("boss", 0) else 1
	var nhp: float = 1.2 if (B.get("night", false) and (sp.t.has(7) or sp.t.has(16))) else 1.0   # night: wild Ghost / Dark are tougher
	var ab: int = C.roll_ability(s.id, 0.05 + mod("hidden")); var ak: String = C.ab_key(ab)
	_eid += 1
	var en := {"eid": _eid, "id": s.id, "lv": s.lv, "st": st, "nat": nat, "iv": iv, "hp": int(st[0] * hpm * nhp), "max": int(st[0] * hpm * nhp), "d": d, "x": 0.0, "y": 0.0, "dir": 2, "boss": bool(s.get("boss", 0)),
		"spd": (30 + sp.b[5] * 0.4), "sts": null, "stt": 0.0, "imm": 0.0, "dots": [], "stg": {3: 0, 5: 0, 6: 0}, "stgt": 0.0, "stop": 0.0, "at": rnd() * 2, "hurt": 0.0,
		"lives": 20 if s.get("boss", 0) else 1 + stages_below(s.id), "ab": ab, "ak": ak, "sbt": 0.0,
		"lane": (rnd() * 2 - 1) * 11, "ph": rnd() * 6.3, "sw": 0.5 + rnd() * 0.6, "pace": 0.88 + rnd() * 0.24,
		"r": s.r if s.has("r") else randi() % B.M.routes.size(),
		"air": (sp.t.has(2) and not GROUND_FLYERS.has(s.id)) or ak == "levitate",     # flyers take the shortcut line
		"hide": B.th >= 3 and sp.t.has(7), "rev": 0.0,                                  # Ghost types are hidden until a seer is near
		"dig": B.th >= 3 and C.moves_at(s.id, s.lv).has(91), "under": false, "digt": 1 + rnd() * 2,   # ones that know Dig burrow
		"armor": B.th >= 3 and (sp.t.has(8) or sp.t.has(5)),
		"bst": {3: 0, 5: 0, 6: 0}, "sh": 0, "shm": 0, "sht": 0.0, "shcd": 0.0, "tt": 4 + rnd() * 3, "dt2": 2 + rnd() * 3, "dash": 0.0, "px": null, "py": null, "dead": 0.0}
	en.merge(wild_traits(s.id, s.lv, ak, B.th), true)
	if s.get("boss", 0):   # boss moves: only ones it really knows
		var ms: Array = C.moves_at(s.id, s.lv)
		en.bwxm = 0
		for m in ms: if WX_MOVES.has(m): en.bwxm = m; break
		en.bwx = WX_MOVES.get(en.bwxm, null)
		en.bup = []
		for m in ms:
			var M := mvd(m)
			if M.is_empty() or M.tg != 7: continue
			for q in M.sc: if (q[0] == 3 or q[0] == 5 or q[0] == 6) and q[1] > 0: en.bup.append(m); break
		en.bt = {"wx": 1.0, "up": 4.0, "call": 8.0}
	if s.get("boss", 0) and C.DB.snd.has("bossTheme") and C.DB.snd.bossTheme.has(s.id): music(C.DB.snd.bossTheme[s.id])   # this boss has its own song in the ROMs
	if s.get("minion", 0): en.lives = 1
	if s.has("rival"):
		en.rival = s.rival; en.hp *= 2; en.max *= 2; en.pace = 1.25; en.lives = 5
		var rv: Dictionary = B.get("rival", {})
		if rv.get("n", "") != s.rival: rv = {"n": s.rival, "left": 0, "got": 0}; B.rival = rv; floater(en, "%s is racing you!" % s.rival, 4); sfx("evo")
		rv.left += 1
	# shiny (1 in 400, when SpriteCollab has its shiny) and Alpha (1 in 200: 1.5x size, 3x HP, perfect IVs); never bosses
	if not s.get("boss", 0) and not s.get("mid", 0):
		if C.has_shiny(s.id) and rnd() < SHINY_RATE: en.shiny = true; en.spk = true
		if rnd() < ALPHA_RATE: en.alpha = true; en.hp *= 3; en.max *= 3; en.iv = [31, 31, 31, 31, 31, 31]
	B.en.append(en); G().seen[s.id] = 1
	return en
# boss transformations: below half HP these bosses take their stronger form (SpriteCollab animates all of them)
const BOSS_FORM := {382: 10077, 383: 10078, 487: 10007, 483: 10245, 484: 10246, 718: 10120, 800: 10157, 888: 10188, 889: 10189, 720: 10086}
func boss_transform(e: Dictionary) -> void:
	var to: int = BOSS_FORM[e.id]
	if not C.SP.has(to): return
	var nm: String = SP(e.id).n
	e.tf = true; e.id = to
	var st: Array = C.calc_stats(to, e.lv, e.iv, e.nat)
	var mul: float = float(e.max) / max(1.0, e.st[0])
	e.st = st; e.max = int(st[0] * mul); e.hp = int(e.max * 0.5); e.spd = 30 + SP(to).b[5] * 0.4
	var al: Array = SP(to).get("ab", [])
	if al.size(): e.ab = al[0][0]; e.ak = C.ab_key(e.ab)
	if to == 10077 or to == 10078:   # Primal Reversion brings its own weather
		e.bwxm = 240 if to == 10077 else 241; e.bwx = WX_MOVES[e.bwxm]; B.bwx = {"k": e.bwx, "e": e}; sync_weather()
	add_fx("eos000/anim01", e.x, e.y, 0); floater(e, "%s became %s!" % [nm, SP(to).n], 4)
	if has_node("/root/Snd"): get_node("/root/Snd").sfx("evo")
func boss_act(e: Dictionary, dt: float) -> void:
	var T: Dictionary = e.bt
	for k in T: T[k] -= dt
	if not e.get("tf", false) and BOSS_FORM.has(e.id) and e.hp < e.max * 0.5: boss_transform(e)
	if e.bwx and B.bwx == null: B.bwx = {"k": e.bwx, "e": e}; floater(e, mvd(e.bwxm).n, 4)   # a boss's weather lasts until it is knocked out
	if e.bup.size() and T.up <= 0:
		var mist := false
		for t in B.towers: if has_m(t, "Mist") and hyp(t.x, t.y, e.x, e.y) <= sk_r(t): mist = true
		if not mist:
			T.up = 9.0
			var m: int = e.bup[randi() % e.bup.size()]; var M := mvd(m); var up := false
			for q in M.sc:
				if (q[0] == 3 or q[0] == 5 or q[0] == 6) and q[1] > 0 and e.bst[q[0]] < 6: e.bst[q[0]] = min(6, e.bst[q[0]] + q[1]); up = true
			if up: floater(e, M.n, 4)
	if T.call <= 0:
		T.call = 15.0
		var pool := []
		for x in B.waves[-1]: if not x.get("boss", 0): pool.append(x)
		if pool.size():
			floater(e, "Called for help!", 4)
			for i in 3:
				var p = pool[randi() % pool.size()]
				var m := spawn({"id": p.id, "lv": max(1, e.lv - 5), "minion": 1, "r": e.r}, max(0, e.d - 20 - i * 14)); m.px = null
# Flying types whose only movement animation is a ground walk (no flight frames in SpriteCollab): they walk the path
const GROUND_FLYERS := [6, 149, 123, 163, 178, 188, 83, 84, 85, 225, 566, 629, 701, 722, 723, 741, 845]
const HOVER_SPEED := 0.65   # flying animations play at 65% speed
func route_of(e: Dictionary) -> Dictionary:
	var r: Dictionary = B.M.routes[min(e.r, B.M.routes.size() - 1)]
	return r.air if e.air else r
const SEE_MOVES := [193, 316, 357]
func sees_why(e: Dictionary):   # why a Pokémon can see hidden Ghost types (null if it can't)
	var k: String = C.ab_key(e.ab)
	if SP(e.id).t.has(13): return "Psychic type"
	if SP(e.id).t.has(7): return "Ghost type"   # Ghosts see Ghosts
	for x in e.mv:
		if SEE_MOVES.has(x) or (C.DB.dex.moves.has(x) and C.DB.dex.moves[x].n == "Defog"): return "knows " + mvd(x).n
	return "ability " + C.DB.dex.abil[e.ab].n if (k == "keen-eye" or k == "frisk") else null
func sees(t: Dictionary) -> bool: return sees_why(t.e) != null
# the tower's longest attack range, with range upgrades and the Flying bonus; used for the range circle and range-based quirks
func max_range(t: Dictionary) -> float:
	var r := 40.0
	for m in t.e.mv: if C.move_use(m) != null: r = max(r, tower_range(t, m))
	return r
func has_t(t: Dictionary, x: int) -> bool: return SP(t.e.id).t.has(x)   # tower type check for the type quirks (TQ in core)
func can_hit(t: Dictionary, m: int, e: Dictionary) -> bool:
	var M := mvd(m)
	if e.under: return m == 89 or m == 222 or m == 90
	if e.hide and not (e.rev > 0): return false
	if e.air:
		if M.t == 4: return false
		if M.c == 2 and not (M.t == 2 or M.t == 5 or SP(t.e.id).t.has(2)) and hyp(e.x, e.y, t.x, t.y) > 40: return false
	return true
func stages_below(id: int) -> int:
	var n := 0; var s = SP(id)
	while s and s.get("f", 0) and C.SP.has(s.f) and SP(s.f).anim and not SP(s.f).get("bb", 0) and n < 3: n += 1; s = SP(s.f)
	return n

# ---------- towers ----------
func can_place(e: Dictionary, x: float, y: float) -> bool:
	var M: Dictionary = B.M
	if x < 6 or y < 6 or x > M.W * TZ - 6 or y > M.H * TZ - 6: return false
	var tv: int = M.t[int(y / TZ)][int(x / TZ)]; var ty: Array = SP(e.id).t
	if tv == 1: return false
	if tv == 2 and not ((M.liq == "water" and ty.has(10)) or (M.liq == "lava" and ty.has(9))): return false
	if MG.dist_to_path(M, x, y) < 30: return false
	for t in B.towers: if hyp(t.x, t.y, x, y) < 22: return false
	return true
func place_tower(e: Dictionary, x: float, y: float):
	var c: int = C.place_cost(e)
	if B.cash < c or B.towers.size() >= 10 or not can_place(e, x, y): return null
	for t in B.towers: if is_same(t.e, e): return null
	B.cash -= c
	_tid += 1
	var t := {"tid": _tid, "e": e, "x": x, "y": y, "pt": B.time, "dir": 0, "anim": "Idle", "at": 0.0, "cd": 0.3, "kills": 0, "buf": {1: 0, 3: 0, 5: 0}, "buft": 0.0, "mode": "first", "paid": c, "up": [0, 0, 0]}
	B.towers.append(t); sfx("place"); return t
const WEATHER := {"rain": ["Rain", "Water moves stronger, Fire moves weaker. Thunder and Hurricane never miss.", Color(60 / 255.0, 90 / 255.0, 200 / 255.0, .13)],
	"sun": ["Harsh sunlight", "Fire moves stronger, Water moves weaker. Nothing freezes.", Color(1, 170 / 255.0, 40 / 255.0, .12)],
	"sand": ["Sandstorm", "Hurts wild Pokémon that aren't Rock, Ground or Steel. Rock types take less from special moves.", Color(200 / 255.0, 160 / 255.0, 90 / 255.0, .18)],
	"hail": ["Hail", "Hurts wild Pokémon that aren't Ice. Blizzard never misses.", Color(220 / 255.0, 235 / 255.0, 1, .16)]}
func weather_cost() -> int: return int(round((120 + B.th * 25) * (1 + mod("weatherCost"))))
func weather_waves() -> int: return 3 + int(floor((mod("weatherDur") + 1e-6) / 0.3))   # 3 waves, +1 for every 3 weather-duration nodes in the Rescue tree
func buy_weather(k: String) -> bool:   # bought during a wave, that wave counts as the first
	var c := weather_cost()
	if B.cash < c: return false
	B.cash -= c
	var first: int = B.wave if B.phase == "wave" else B.wave + 1
	B.pwx = {"k": k, "until": first + weather_waves() - 1}; sync_weather(); sfx("place"); return true
func waves_left() -> int: return B.pwx.until - (B.wave if B.phase == "wave" else B.wave + 1) + 1 if B.pwx else 0
func sync_weather() -> void:   # what's in the sky: a living boss's weather, otherwise yours
	if B.bwx and not (B.bwx.e.hp > 0 and has_ref(B.en, B.bwx.e)): B.bwx = null
	if B.bwx: B.weather = {"k": B.bwx.k, "boss": 1}
	elif B.pwx: B.weather = {"k": B.pwx.k}
	elif B.mwx and B.mwx.until > B.time: B.weather = {"k": B.mwx.k}
	else: B.weather = null
func wk():   # the current weather's key, or null
	return B.weather.k if B.weather else null
# upgrades for a placed Pokémon, paid with battle cash: Range, Attack speed and Power, 5 levels each, +8% per level
const UPG := {"n": ["Range", "Speed", "Power"], "step": 0.08, "max": 5, "cost": [0.8, 1.2, 1.8, 2.6, 3.6]}
func upgrade_cost(t: Dictionary, k: int) -> int: return 0 if t.up[k] >= UPG.max else int(round(C.place_cost(t.e) * UPG.cost[t.up[k]]))
func buy_upgrade(t: Dictionary, k: int) -> bool:
	var c := upgrade_cost(t, k)
	if not c or B.cash < c: return false
	B.cash -= c; t.paid += c; t.up[k] += 1; sfx("lvl"); return true
func up_k(t: Dictionary, k: int) -> float: return 1 + UPG.step * (t.up[k] if t.has("up") else 0)
func sell_tower(t: Dictionary) -> void:
	B.cash += int(floor(t.paid * 0.7))
	B.towers = B.towers.filter(func(x): return not is_same(x, t))
	if B.sel != null and is_same(B.sel, t): B.sel = null
func tower_range(t: Dictionary, m: int) -> float: return RANGE[mvd(m).c] * (1 + min(0.25, t.e.lv / 400.0) + mod("range")) * up_k(t, 0) * (1.15 if has_t(t, 2) else 1.0) * (1.2 if terrain_perk(t) == "rock" else 1.0)   # Flying: Far sight; rocky land: Rock / Ground / Fighting reach further
# ---- terrain (the user's choice): the map's land counts as one terrain from its setting's own type list (the first of
# Grass / Rock-Ground / Ice it lists), plus ponds and lava. Only Pokémon of the matching type get the perk:
#   pond: Water attacks 20% faster   lava: Fire +20% damage   grass land: Grass +20% damage
#   rocky land: Rock / Ground / Fighting +20% range           icy land: Ice attacks 20% faster
const TERRAIN_TXT := {"pond": "Pond: attacks 20% faster", "lava": "Lava: 20% more damage", "grass": "Grassland: 20% more damage",
	"rock": "Rocky ground: 20% more range", "ice": "Icy ground: attacks 20% faster"}
func land_kind(set_idx: int) -> String:
	for x in C.DB.ts[set_idx].get("types", []):
		if x == 11: return "grass"
		if x == 4 or x == 5: return "rock"
		if x == 14: return "ice"
	return ""
func terrain_perk_at(id: int, x: float, y: float) -> String:
	var ty: Array = SP(id).t; var M: Dictionary = B.M
	var tile: int = M.t[clampi(int(y / TZ), 0, M.H - 1)][clampi(int(x / TZ), 0, M.W - 1)]
	if tile == 2: return "pond" if (M.liq == "water" and ty.has(10)) else ("lava" if (M.liq == "lava" and ty.has(9)) else "")
	if not B.has("land"): B.land = land_kind(B.set)
	match B.land:
		"grass": return "grass" if ty.has(11) else ""
		"rock": return "rock" if (ty.has(5) or ty.has(4) or ty.has(1)) else ""
		"ice": return "ice" if ty.has(14) else ""
	return ""
func terrain_perk(t: Dictionary) -> String: return terrain_perk_at(t.e.id, t.x, t.y)
func in_range(t: Dictionary, r: float) -> Array:
	var out := []
	for e in B.en: if e.hp > 0 and e.d > 0 and hyp(e.x, e.y, t.x, t.y) <= r: out.append(e)
	return out
func choose_target(t: Dictionary, list: Array):
	if list.is_empty(): return null
	var best = list[0]
	for b in list:
		if t.mode == "first":
			if b.d > best.d: best = b
		elif t.mode == "last":
			if b.d < best.d: best = b
		elif t.mode == "strong":
			if b.hp > best.hp: best = b
		elif hyp(b.x, b.y, t.x, t.y) < hyp(best.x, best.y, t.x, t.y): best = b
	return best
# enemies this move can hit; empty when there are none
func targets(t: Dictionary, r: float, m: int) -> Array:
	var l := []
	for e in B.en: if e.hp > 0 and e.d > 0 and hyp(e.x, e.y, t.x, t.y) <= r and can_hit(t, m, e): l.append(e)
	return l
# pick the best move against the best target right now
func tower_act(t: Dictionary) -> bool:
	var tf = transform_src(t)
	var st: Array
	if tf:
		var cp: Dictionary = tf.e.duplicate(); cp.lv = t.e.lv; st = C.mon_stats(cp)
	else: st = C.mon_stats(t.e)
	var me := SP((tf if tf else t).e.id)   # Transform: a copy of the strongest teammate
	var best = null
	var hk: String = C.held_key(t.e)
	var moves: Array
	if tf: moves = tf.e.mv.filter(func(x): return C.move_use(x) != null)
	elif hk.begins_with("choice"): moves = t.e.mv.slice(0, 1)
	else: moves = t.e.mv
	for m in moves:
		var use = C.move_use(m)
		if use == null: continue
		var M := mvd(m); var r := tower_range(t, m); var list := targets(t, r, m)
		if list.is_empty(): continue
		var tg = choose_target(t, list)
		var sc := 0.0
		if use == "dmg":
			var p: float = M.p if M.get("p", 0) else (50 if FIXED.has(m) else 60)
			var stab := 1.5 if me.t.has(M.t) else 1.0; var ef: float = C.eff(M.t, SP(tg.id).t)
			sc = p * stab * ef * ((M.a if M.get("a", 0) else 100) / 100.0) * ((M.h[0] + M.h[1]) / 2.0) * (1 + 0.35 * (list.size() - 1) if aoe(M) else 1.0)
			if OHKO.has(m): sc = 0.0 if (tg.boss or tg.lv > t.e.lv) else 60.0
		elif use == "status":
			var free := false
			for e in list: if e.sts == null and e.imm <= 0: free = true; break
			sc = (46.0 if (M.ai == "sleep" or M.ai == "freeze" or M.ai == "trap") else 32.0) * ((M.a if M.get("a", 0) else 100) / 100.0) if free else 0.0
		elif use == "debuff":
			for e in list: if e.stgt <= 0: sc = 28.0; break
		elif use == "buff":
			sc = 55.0 if t.buft <= 0 else 0.0
		if sc > 0 and (best == null or sc > best.sc): best = {"m": m, "sc": sc, "tg": tg, "list": list, "use": use, "r": r}
	if best == null: return false
	fire(t, best, st)
	return true
func aoe(M: Dictionary) -> bool: return M.tg == 9 or M.tg == 11 or M.tg == 14 or M.tg == 12
func fire(t: Dictionary, b: Dictionary, st: Array) -> void:
	var M := mvd(b.m); var fx: Dictionary = C.DB.fx.moves.get(b.m, {})
	if has_node("/root/Snd"): get_node("/root/Snd").move_sfx(b.m)   # the move's own sound
	t.dir = dir_row(b.tg.x - t.x, b.tg.y - t.y); t.anim = "Attack" if M.c == 2 else "Shoot"; t.at = 0.0
	var cd := 5.5 / sqrt(max(5, M.pp)) * (0.8 if M.get("pr", 0) > 0 else 1.0)
	cd /= 1 + st[5] * STAGE(buf_of(t, 5)) / 150.0
	if has_m(t, "Endure") and B.lives < 25: cd /= 1.3
	if B.towers.size() and t.get("tw", 0.0) > B.time: cd /= 1.25
	if t.get("ssw", 0.0) > B.time: cd /= 1.4
	if t.has("acu") and t.acu.k == "s" and t.acu.u > B.time: cd /= 1.3   # move skills
	cd /= up_k(t, 1)   # Attack speed upgrades
	if has_t(t, 6):   # Bug: Swarm
		var n := 0
		for o in B.towers: if not is_same(o, t) and has_t(o, 6): n += 1
		cd /= 1 + 0.05 * n
	var ak: String = C.ab_key(t.e.ab); var hk: String = C.held_key(t.e); var w = wk(); var ty: Array = SP(t.e.id).t
	var tsm := 0.0
	for x in ty: tsm = max(tsm, mod("ts%d" % x))
	cd /= 1 + mod("atkSpeed") + tsm
	var tile: int = B.M.t[int(t.y / TZ)][int(t.x / TZ)]
	if tile == 2 and ((B.M.liq == "water" and ty.has(10)) or (B.M.liq == "lava" and ty.has(9))): cd /= 1 + mod("pondSpeed")
	var tperk := terrain_perk(t)
	if tperk == "pond" or tperk == "ice": cd /= 1.2   # terrain
	if t.get("awk", false): cd /= 1.3   # Awakened
	if (ak == "chlorophyll" and w == "sun") or (ak == "sand-rush" and w == "sand") or (ak == "slush-rush" and w == "hail") or (ak == "swift-swim" and w == "rain"): cd /= 1.5
	if ak == "speed-boost": cd /= 1 + min(0.5, t.get("sbt", 0.0) / 60.0)
	if ak == "swift-swim" and tile == 2: cd /= 1.5
	if hk == "choice-scarf": cd /= 1.5
	if hk == "quick-claw" and rnd() < 0.2: cd *= 0.4
	t.cd = cd
	if fx.has("u"): add_fx(fx.u, t.x, t.y, t.dir, atan2(b.tg.y - t.y, b.tg.x - t.x))
	var hit := func(tg) -> void:
		if b.use == "buff":
			var allies := []
			if M.tg == 13 or M.tg == 3 or M.tg == 5:
				for o in B.towers: if hyp(o.x, o.y, t.x, t.y) < 90: allies.append(o)
			else: allies = [t]
			for o in allies:
				for q in M.sc:
					var k = {2: 1, 4: 3, 6: 5}.get(q[0], null)
					if k != null and q[1] > 0: o.buf[k] = clampi(o.buf[k] + q[1], -6, 6)
				o.buft = 24.0 if C.held_key(o.e) == "light-clay" else 12.0
			return
		var tgs := []
		if aoe(M):
			if M.c == 2 or M.c == 1: tgs = b.list
			else:
				for e in B.en: if e.hp > 0 and hyp(e.x, e.y, tg.x, tg.y) < 46 and can_hit(t, b.m, e): tgs.append(e)
		else: tgs = [tg]
		for e in tgs: apply_move(t, b.m, e, st)
	if b.use == "buff": hit.call(t); return
	if fx.has("p") and M.c != 2:
		B.proj.append({"x": t.x, "y": t.y - 8 * SPR, "tg": b.tg, "fx": fx.p, "sp": 300.0, "at": 0.0, "done": hit, "hfx": fx.get("h", null), "row": 0, "ang": 0.0, "hit": 0})
	else:
		var tg0 = b.tg; var hfx = fx.get("h", null); var dir: int = t.dir
		B.q2.append({"t": 0.12, "fn": func() -> void:
			if tg0.hp > 0 or aoe(M):
				hit.call(tg0)
				if hfx: add_fx(hfx, tg0.x, tg0.y - 8 * ESPR, dir)})
const AB_IMMUNE := {"flash-fire": 9, "water-absorb": 10, "storm-drain": 10, "dry-skin": 10, "volt-absorb": 12, "lightning-rod": 12, "motor-drive": 12, "sap-sipper": 11, "levitate": 4}
func apply_move(t: Dictionary, m: int, e: Dictionary, st: Array) -> void:
	if e.hp <= 0: return
	var M := mvd(m); var use = C.move_use(m); var me := SP(t.e.id); var L: int = t.e.lv; var ak: String = C.ab_key(t.e.ab); var hk: String = C.held_key(t.e); var ek: String = e.ak
	var acc: float = M.a * (1.3 if ak == "compound-eyes" else 1.0) * (0.8 if (ak == "hustle" and M.c == 2) else 1.0) * (1.1 if hk == "wide-lens" else (1.2 if hk == "zoom-lens" else 1.0)) if M.get("a", 0) else 100.0
	if ak == "no-guard" or has_m(t, "Lock-On") or has_m(t, "Mind Reader"): acc = 100
	var w = wk()
	if (w == "rain" and (m == 87 or m == 542)) or (w == "hail" and m == 59): acc = 100   # Thunder / Hurricane in rain, Blizzard in hail never miss
	if acc < 100 and rnd() * 100 > acc: floater(e, "MISS", 1); return
	var secondary: bool = M.get("ac", 0) > 0 or (M.sc.size() and M.get("sch", 0) > 0) or M.get("fl", 0) > 0
	var no_sec: bool = ek == "shield-dust" or (ak == "sheer-force" and secondary)
	var chance := func(p: float) -> bool: return not no_sec and rnd() * 100 < p * (2.0 if ak == "serene-grace" else 1.0) * (1 + mod("effChance"))
	if use == "dmg":
		if AB_IMMUNE.get(ek, -1) == M.t: floater(e, "MISS", 1); return
		var dmg: int
		if OHKO.has(m): dmg = 0 if e.boss else e.hp
		elif FIXED.has(m): dmg = L if FIXED[m] is String and FIXED[m] == "lv" else (max(1, int(floor(e.hp / 2.0))) if FIXED[m] is String and FIXED[m] == "half" else int(FIXED[m]))
		else:
			var phys: bool = M.c == 2
			var A: float = ((max(st[1], st[2]) if has_m(t, "Power Trick") else st[1]) * STAGE(buf_of(t, 1))) if phys else st[3] * STAGE(buf_of(t, 3))
			if phys and (ak == "huge-power" or ak == "pure-power"): A *= 2
			if phys and ak == "hustle": A *= 1.5
			if (phys and hk == "choice-band") or (not phys and hk == "choice-specs"): A *= 1.5
			var D: float = (e.st[2] * STAGE(clampi(e.stg[3] + e.bst[3], -6, 6)) if phys else e.st[4] * STAGE(clampi(e.stg[5] + e.bst[5], -6, 6))) * (e.gsf if e.get("gs", 0.0) > B.time else 1.0)   # Guard Split / Octolock
			var hits: int = M.h[1] if ak == "skill-link" else M.h[0] + randi() % (M.h[1] - M.h[0] + 1)
			var ty: Array = en_types(e)
			if ak == "scrappy" and (M.t == 0 or M.t == 1): ty = ty.filter(func(x): return x != 7)
			var ef: float = C.eff(M.t, ty)
			if ef == 0 or (ek == "wonder-guard" and ef <= 1): floater(e, "MISS", 1); return
			var cs := clampi(M.get("cr", 0) + (2 if t.get("fe", 0.0) > B.time else 0) + (1 if has_t(t, 15) else 0) + (1 if ak == "super-luck" else 0) + (1 if (hk == "scope-lens" or hk == "razor-claw") else 0), 0, 3)
			var sure: bool = t.get("lf", 0) and ek != "battle-armor" and ek != "shell-armor"
			if sure: t.lf = 0   # Laser Focus
			var crit := 1.0
			if sure or (ek != "battle-armor" and ek != "shell-armor" and rnd() < [1 / 24.0, 1 / 8.0, 1 / 2.0, 1.0][cs] + mod("crit") + C.friend_crit(t.e)): crit = 2.25 if ak == "sniper" else 1.5
			var pw: float = M.p if M.get("p", 0) else 60
			if ak == "technician" and pw <= 60: pw *= 1.5
			var stabv: float = (2.0 if ak == "adaptability" else 1.5)
			if C.mods().get("stab", 0.0): stabv += C.mods().stab
			var mlt: float = (stabv if me.t.has(M.t) else 1.0) * ef * crit
			mlt *= 1 + C.mods().get("power", 0.0) + C.mods().get("tp%d" % M.t, 0.0)
			mlt *= up_k(t, 2)   # Power upgrades
			var tpk := terrain_perk(t)
			if tpk == "grass" or tpk == "lava": mlt *= 1.2   # terrain
			if B.get("night", false) and (has_t(t, 7) or has_t(t, 16)): mlt *= 1.2   # night: Ghost / Dark
			if t.get("awk", false): mlt *= 1.3   # Awakened
			if M.t == 12 and t.get("chg", 0): mlt *= 2; t.chg = 0
			if M.t == 12 and e.get("elz", 0.0) > B.time: mlt *= 2   # Charge / Electrify
			if t.get("dt", 0.0) > B.time: mlt *= 2
			if t.get("enc", 0): mlt *= 2; t.enc = 0
			if t.get("hh", 0.0) > B.time: mlt *= 1.25
			if not phys and t.get("th", 0.0) > B.time: mlt *= 1.2   # Double Team / Encore / Helping Hand / Take Heart
			if t.has("acu") and t.acu.k == "d" and t.acu.u > B.time: mlt *= 1.3
			if B.terr.get(M.t, 0.0) > B.time: mlt *= 1.3   # Acupressure / terrains
			if has_m(t, "Ingrain"): mlt *= 1 + min(0.3, 0.05 * floor((B.time - t.get("pt", 0.0)) / 10.0))
			if e.boss: mlt *= 1 + C.mods().get("bossDmg", 0.0) + (0.2 if has_t(t, 1) else 0.0)   # Fighting: Boss hitter
			if has_t(t, 5):   # Rock: Crush
				if not e.has("rk"): e.rk = {}
				if not e.rk.has(t.tid): e.rk[t.tid] = 1; mlt *= 1.3
			for o in B.towers:   # Fairy: Aura
				if not is_same(o, t) and has_t(o, 17) and hyp(o.x, o.y, t.x, t.y) <= 90: mlt *= 1.05; break
			var wp: float = 0.5 + C.mods().get("weatherPower", 0.0)   # weather: Rain / Sun boost one type x1.5 and weaken the other x0.5
			if w == "rain": mlt *= 1 + wp if M.t == 10 else (0.5 if M.t == 9 else 1.0)
			if w == "sun": mlt *= 1 + wp if M.t == 9 else (0.5 if M.t == 10 else 1.0)
			if w == "sun" and ak == "solar-power" and not phys: mlt *= 1.5
			if w == "sand" and not phys and SP(e.id).t.has(5): mlt /= 1.5   # sandstorm raises Rock types' Sp. Def
			if B.lives <= 33 and {"overgrow": 11, "blaze": 9, "torrent": 10, "swarm": 6}.get(ak, -1) == M.t: mlt *= 1.5
			if ak == "sheer-force" and secondary: mlt *= 1.3
			if ak == "tough-claws" and phys: mlt *= 1.3
			if ak == "tinted-lens" and ef < 1: mlt *= 2
			if hk == "life-orb": mlt *= 1.3
			if hk == "expert-belt" and ef > 1: mlt *= 1.2
			if (hk == "muscle-band" and phys) or (hk == "wise-glasses" and not phys): mlt *= 1.1
			if C.TYPE_ITEM.get(hk, -1) == M.t: mlt *= 1.2
			if hk == "metronome":
				t.metro = min(5, t.get("metro", 0) + 1) if t.get("lastM", 0) == m else 0; t.lastM = m; mlt *= 1 + 0.2 * t.metro
			if (ek == "thick-fat" and (M.t == 9 or M.t == 14)) or (ek == "heatproof" and M.t == 9): mlt *= 0.5
			if ek == "dry-skin" and M.t == 9: mlt *= 1.25
			if (ek == "filter" or ek == "solid-rock" or ek == "prism-armor") and ef > 1: mlt *= 0.75
			if (ek == "multiscale" or ek == "shadow-shield") and e.hp >= e.max: mlt *= 0.5
			if e.armor and (M.p if M.get("p", 0) else 60) < 60 and not has_t(t, 8): mlt *= 0.5   # Steel: Pierce
			var dm := 0.0
			for h in hits: dm += ((2 * L / 5.0 + 2) * pw * A / D / 50.0 + 2) * mlt * (0.85 + rnd() * 0.15)
			dmg = max(1, int(floor(dm)))
			if ef > 1: floater(e, "!", 2)
			if e.sts == "freeze" and M.t == 9: e.sts = null; e.stop = 0.0
		if ek == "sturdy" and not e.get("sturdy", 0) and e.hp >= e.max and dmg >= e.hp: dmg = e.hp - 1; e.sturdy = 1
		e.fs = m == 206; B.mlab = M.n; hurt(t, e, dmg); e.fs = false; quirk_hit(t, e, dmg)   # False Swipe: a knockout by it is 3x as likely to ask to join
		var ai: String = M.get("ai", "none")
		if e.hp > 0 and ai != "none" and C.AILMENTS.has(ai) and chance.call(M.get("ac", 0)): inflict(e, ai, t)
		var fl: float = M.get("fl", 0)
		if e.hp > 0 and ((fl and chance.call(fl)) or (not fl and (hk == "kings-rock" or hk == "razor-fang") and rnd() < 0.1)): e.stop = max(e.stop, 0.35)
		if e.hp > 0 and M.sc.size() and M.tg != 7 and chance.call(M.get("sch", 0)): debuff(e, M.sc, t)
	elif use == "status": inflict(e, M.ai, t)
	elif use == "debuff": debuff(e, M.sc, t)
func debuff(e: Dictionary, sc: Array, t) -> void:
	if e.ak == "clear-body" or e.ak == "white-smoke" or e.ak == "full-metal-body": return
	for q in sc: if q[1] < 0 and (q[0] == 3 or q[0] == 5 or q[0] == 6): e.stg[q[0]] = clampi(e.stg[q[0]] + q[1], -6, 0)
	e.stgt = (20.0 if (t != null and C.held_key(t.e) == "light-clay") else 10.0) * (1 + mod("debuffDur"))
const STATUS_BLOCK := {"sleep": ["insomnia", "vital-spirit", "sweet-veil"], "paralysis": ["limber"], "poison": ["immunity", "pastel-veil"], "burn": ["water-veil", "water-bubble"],
	"confusion": ["own-tempo", "oblivious"], "freeze": ["magma-armor"]}
const TYPE_BLOCK := {"burn": [9], "paralysis": [12], "poison": [3, 8], "freeze": [14]}
const STATUS_DUR := {"paralysis": 6, "sleep": 3, "freeze": 3, "burn": 5, "poison": 6, "confusion": 3, "trap": 4, "yawn": 2, "leech-seed": 8}
func inflict(e: Dictionary, ai: String, t = null) -> void:
	if e.sts != null or e.imm > 0: return
	if STATUS_BLOCK.get(ai, []).has(e.ak): return
	for x in TYPE_BLOCK.get(ai, []): if SP(e.id).t.has(x): return
	e.src = t; e.bind = t != null and C.held_key(t.e) == "binding-band"
	var k := 0.5 if e.boss else 1.0
	if ai == "freeze" and wk() == "sun": return   # nothing freezes in sun
	e.sts = ai; e.stt = STATUS_DUR[ai] * k * (1 + mod("statusDur"))
	if ai == "sleep" or ai == "freeze" or ai == "trap": e.stop = max(e.stop, e.stt)
	if t != null and (ai == "sleep" or ai == "freeze" or ai == "trap" or ai == "paralysis" or ai == "confusion"): meter_ctl(t, e.stt)
# on-hit type quirks
func quirk_hit(t: Dictionary, e: Dictionary, dmg: int) -> void:
	if has_t(t, 12) and not B.chain:   # Electric: Chain
		var o = null; var od := 1e9
		for x in B.en:
			if is_same(x, e) or x.hp <= 0 or x.d <= 0 or x.under or (x.hide and not (x.rev > 0)): continue
			var dd := hyp(x.x, x.y, e.x, e.y)
			if dd < 70 and dd < od: od = dd; o = x
		if o:
			B.chain = 1; B.zap.append({"a": Vector2(e.x, e.y), "b": Vector2(o.x, o.y), "t": 0.18})
			var lab: String = B.mlab; B.mlab = "Chain (Electric quirk)"; hurt(t, o, max(1, int(floor(dmg * 0.3)))); B.mlab = lab; B.chain = 0
	if e.hp <= 0: return
	if has_t(t, 9) and rnd() < 0.15: inflict(e, "burn", t)                                  # Fire: Scorch
	if has_t(t, 3): e.pst = min(5, e.get("pst", 0) + 1); e.ptt = 4.0; e.psrc = t            # Poison: Toxic
	if has_t(t, 10): e.wsl = 1.5; meter_ctl(t, 0.15)                                       # Water: Soak
	if has_t(t, 14): e.chill = 2.0; meter_ctl(t, 0.3)                                      # Ice: Chill
	if has_t(t, 4) and rnd() < 0.08: e.stop = max(e.stop, 0.2 if e.boss else 0.4); meter_ctl(t, 0.2 if e.boss else 0.4)   # Ground: Tremor
	if has_t(t, 16) and not e.boss and e.hp > 0 and e.hp < e.max * 0.15:                    # Dark: Finisher
		floater(e, "Finish", 4); var lab: String = B.mlab; B.mlab = "Finisher (Dark quirk)"; hurt(t, e, e.hp); B.mlab = lab
func hurt(t, e: Dictionary, dmg: int) -> void:
	var phase: bool = t != null and has_t(t, 7)   # Ghost: Phase - attacks go through Protect shields
	if not phase and not (e.get("nt", 0.0) > B.time) and e.get("prot", 0) and e.sh <= 0 and e.shcd <= 0 and e.hp - dmg > 0:
		e.sh = int(ceil(e.max * 0.25)); e.shm = e.sh; e.sht = 3.0; e.shcd = 9.0; floater(e, mvd(e.prot).n, 4)
	if not phase and e.sh > 0:
		var a: int = min(e.sh, dmg); e.sh -= a; dmg -= a
		if e.sh <= 0: e.sht = 0.0
		if dmg <= 0: e.hurt = 0.1; return
	meter_dmg(t, min(dmg, max(0, e.hp)), B.mlab if B.mlab != "" else "Other"); e.hp -= dmg
	if e.has("heal") and not e.get("healed", 0) and not (e.get("nt", 0.0) > B.time) and e.hp > 0 and e.hp < e.max * 0.4:
		e.healed = 1; e.hp = min(e.max, e.hp + int(ceil(e.max * e.heal.hl))); floater(e, mvd(e.heal.m).n, 4)
	e.hurt = 0.25; floater(e, str(dmg), 0)
	if e.hp <= 0: ko(t, e)
func ko(t, e: Dictionary) -> void:
	e.hp = 0; e.dead = 0.5; B.kills += 1
	var mt = mtr(t)
	if mt: mt.ko += 1
	if e.has("rival") and B.has("rival"):
		B.rival.got += 1; B.rival.left -= 1
		if B.rival.left <= 0 and B.rival.got >= 3 and not B.rival.get("paid", false):
			B.rival.paid = true; var pay := int(100 + B.th * 40); B.cash += pay; floater(e, "%s beaten! +$%d" % [e.rival, pay], 4)
	B.cash += int(round((2 + floor(e.lv / 6.0) + (50 if e.boss else 0) + (25 if e.get("alpha", false) else 0)) * (2 if (t != null and C.held_key(t.e) == "amulet-coin") else 1) * (1 + mod("koCash"))))
	if t != null:
		var sp := SP(e.id)
		for o in B.towers:
			var L: int = e.lv; var Lp: int = o.e.lv
			var gain: float = floor(sp.x * L / 5.0 * pow((2 * L + 10) / float(L + Lp + 10), 2.5) / 4.0) + 1
			# full XP up to 5 levels above the wild one, none at 15+ above
			var g := int(ceil(gain * (1.0 if is_same(o, t) else 0.33) * (3.0 if e.boss else 1.0) * (1.5 if C.held_key(o.e) == "lucky-egg" else 1.0) * XPMUL * clampf(1 - (o.e.lv - e.lv - 5) / 10.0, 0, 1)))
			var ev: Array = C.give_xp(o.e, g); B.xpLog[o.e.u] = B.xpLog.get(o.e.u, 0) + g
			if ev.size(): floater(o, "Lv %d" % o.e.lv, 3); sfx("lvl")
		t.kills += 1
		# recruiting: knocked-out wild Pokémon sometimes ask to join; you choose whether to take it, like the original;
		# duplicates allowed; a declined species stops asking for the rest of this battle
		var asked := false
		for a in B.asks: if a.id == e.id: asked = true
		if sp.anim and not B.declined.has(e.id) and not asked and not e.has("rival"):
			var p: float = ((0.25 if B.get("legend", false) else 0.04) + mod("bossRecruit") if e.boss else 0.005 * (sp.cr / 255.0) * (1 + B.th * 0.05) * (1 - 0.5 * clampf((B.th - 4) / 5.0, 0, 1))) * (1 + mod("recruit")) * (3.0 if e.get("fs", false) else 1.0) * (2.0 if e.get("lure", 0.0) > B.time else 1.0)
			p *= 3.0 if e.get("alpha", false) else 1.0   # Alpha: likelier to join (a shiny joins as often as any other)
			if rnd() < p: B.asks.append({"id": e.id, "lv": e.lv, "ab": e.ab, "nat": e.nat, "iv": e.iv, "shiny": e.get("shiny", false), "alpha": e.get("alpha", false)}); sfx("join"); ask_join.emit()
	# evolved Pokémon fall back to their earlier stage (they keep coming)
	var s := SP(e.id)
	if not e.boss and s.get("f", 0) and C.SP.has(s.f) and SP(s.f).anim and not SP(s.f).get("bb", 0):
		var c := spawn({"id": s.f, "lv": max(1, e.lv - 3), "r": e.r}, max(1, e.d - 6)); c.lives = max(1, e.lives - 1)
		if c.air != e.air: c.d = MG.nearest_d(route_of(c), e.x, e.y)
func floater(o: Dictionary, txt: String, kind: int) -> void: B.fl.append({"x": o.x + (rnd() * 8 - 4), "y": o.y - 24 * SPR, "txt": txt, "kind": kind, "t": 0.0})
# user effects that flow in from one side of the sheet: turned so that side faces the target (value = which way that side points; PI/2 = down)
var FX_FROM := {"efob023/anim00": PI / 2, "efob023/anim08": PI / 2}   # Absorb, Mega Drain, Giga Drain, Leech Life...: orbs drawn rising from below into the user
func _init() -> void:
	for k in FX_FROM.keys(): FX_FROM["eos" + k.substr(4)] = FX_FROM[k]   # Explorers of Sky has the same effect files, drawn the same way round
func add_fx(ref: String, x: float, y: float, dir: int, ang = null) -> void:
	var a = C.DB.fx.anims.get(ref, null)
	if a: B.fx.append({"a": a, "x": x, "y": y, "row": dir if a.get("r", 1) > 1 else 0, "t": 0.0, "rot": ang - FX_FROM[ref] if (FX_FROM.has(ref) and ang != null) else 0.0})
func dir_row(dx: float, dy: float) -> int:
	var deg := atan2(dy, dx) * 180 / PI
	return ((int(floor((90 - deg) / 45.0 + 0.5)) % 8) + 8) % 8   # JS Math.round (halves go up)

const SPR := 1.5; const FXS := 1.5; const ESPR := SPR * 0.9   # wild Pokémon are drawn 10% smaller than your team; Pokémon and move effects are drawn big

# ---------- update ----------
const SAND_SAFE := ["sand-veil", "sand-rush", "sand-force", "overcoat", "magic-guard"]
const HAIL_SAFE := ["ice-body", "snow-cloak", "overcoat", "magic-guard"]
const DOT_RATE := {"burn": 0.04, "poison": 0.05, "trap": 0.03, "leech-seed": 0.03}
const DOT_LABEL := {"burn": "Burn", "poison": "Poison", "trap": "Trap (bind)", "leech-seed": "Leech Seed"}
const AURA_AB := {"static": "paralysis", "flame-body": "burn", "poison-point": "poison", "effect-spore": "spore"}
func live_tower(t):   # the tower if it is still placed, else null (damage over time from a recalled tower counts for nobody)
	return t if (t != null and has_ref(B.towers, t)) else null
func tick(dt: float) -> void:
	if B == null or B.phase == "win" or B.phase == "lose" or B.paused: return
	dt *= B.speed; B.time += dt
	for e in B.en:   # a shiny's sparkle as it comes onto the map: the glow effect from the ROM and Moonlight's sound
		if e.get("spk", false) and e.d > 6:
			e.spk = false; add_fx("eos000/anim01", e.x, e.y, 0)
			if has_node("/root/Snd"): get_node("/root/Snd").move_sfx(236)
	if B.phase == "wave":
		if B.q.size():
			B.qt -= dt
			while B.q.size() and B.qt <= 0:
				var s: Dictionary = B.q.pop_front(); spawn(s); B.qt += s.gap
		else:
			var alive := false
			for e in B.en: if e.hp > 0: alive = true; break
			if not alive:
				B.cash += int(round((30 + B.wave * 6) * (1 + mod("waveBonus"))))
				if B.pwx and B.wave >= B.pwx.until: B.pwx = null   # your weather ends with its last wave
				if B.wave >= B.waves.size(): finish(true); return
				B.phase = "build"
				music(C.DB.ts[B.set].name)   # before the next wave starts, or it would replace the heavy / boss song
				if B.auto: start_wave()
	sync_weather()
	var vines := []   # Grass: Vines
	for t in B.towers: if has_t(t, 11): vines.append([t.x, t.y, max_range(t)])
	for z in B.zap: z.t -= dt
	B.zap = B.zap.filter(func(z): return z.t > 0)
	var chipK = wk() if (wk() == "sand" or wk() == "hail") else null
	var ens: Array = B.en.duplicate()   # the list can change while enemies are handled (knock-outs, splits)
	for e in ens:
		e.at += dt
		if e.hp <= 0: e.dead -= dt; continue
		if chipK and e.d > 0 and not e.under:   # Sandstorm hurts all but Rock / Ground / Steel, Hail all but Ice (and a few abilities)
			var ty: Array = SP(e.id).t
			var safe: bool = (ty.has(5) or ty.has(4) or ty.has(8) or SAND_SAFE.has(e.ak)) if chipK == "sand" else (ty.has(14) or HAIL_SAFE.has(e.ak))
			if not safe:
				e.wdot = e.get("wdot", 0.0) + e.max * 0.02 * (1 + mod("weatherChip")) * dt * (0.4 if e.boss else 1.0)
				if e.wdot >= 1:
					var d := int(floor(e.wdot)); e.wdot -= d; e.hp -= d
					if e.hp <= 0: ko(null, e); continue
		if e.get("akOff", 0.0) and B.time > e.akOff: e.ak = e.ak0; e.akOff = 0.0
		if e.has("cu") and e.cu.left > 0:
			var d0: float = min(e.cu.left, e.cu.dps * dt); e.cu.left -= d0; e.cud = e.get("cud", 0.0) + d0
			if e.cud >= 1:
				var d := int(floor(e.cud)); e.cud -= d; meter_dmg(live_tower(e.cu.t), min(d, e.hp), "Curse", true); e.hp -= d
				if e.hp <= 0: ko(live_tower(e.cu.t), e); continue
		if e.get("pm", 0.0) and B.time >= e.pm:
			e.pm = 0.0; floater(e, "Perish", 4); B.mlab = "Perish Song"; hurt(live_tower(e.get("pmT")), e, int(ceil(e.max * 0.3)))
			if e.hp <= 0: continue
		e.hurt = max(0, e.hurt - dt); e.imm -= dt; e.chill = e.get("chill", 0.0) - dt; e.wsl = e.get("wsl", 0.0) - dt
		if e.get("pst", 0) > 0:
			e.ptt -= dt
			if e.ptt <= 0: e.pst = 0
			elif e.ak != "magic-guard":
				e.pd = e.get("pd", 0.0) + e.max * 0.01 * e.pst * dt * (0.4 if e.boss else 1.0)
				if e.pd >= 1:
					var d := int(floor(e.pd)); e.pd -= d; meter_dmg(live_tower(e.get("psrc")), min(d, e.hp), "Toxic stacks (Poison quirk)", true); e.hp -= d
					if e.hp <= 0: ko(live_tower(e.get("psrc")), e); continue
		if e.sht > 0:
			e.sht -= dt
			if e.sht <= 0: e.sh = 0
		e.shcd -= dt
		if e.get("regen", 0):
			e.rg = e.get("rg", 0.0) + e.max * 0.01 * dt
			if e.rg >= 1: var h := int(floor(e.rg)); e.rg -= h; e.hp = min(e.max, e.hp + h)
		if e.get("dashMv", 0):
			if e.dash > 0: e.dash -= dt
			elif e.d > 0 and e.stop <= 0 and e.sts == null and not (e.get("nt", 0.0) > B.time):
				e.dt2 -= dt
				if e.dt2 <= 0: e.dash = 0.6; e.dt2 = 4 + rnd() * 2
		if e.get("tele", 0) and e.stop <= 0 and e.sts == null and not (e.get("nt", 0.0) > B.time) and e.d > 0:
			e.tt -= dt
			if e.tt <= 0: e.tt = 7 + rnd() * 3; e.d = min(route_of(e).len - 30, e.d + 70); e.px = null; floater(e, "Teleport", 4)
		if e.boss and e.d > 0 and e.has("bt"): boss_act(e, dt)
		if e.stgt > 0:
			e.stgt -= dt
			if e.stgt <= 0: e.stg = {3: 0, 5: 0, 6: 0}
		if e.sts != null:
			e.stt -= dt
			var dps: float = DOT_RATE.get(e.sts, 0.0) * (1 + mod("dot"))
			if dps and e.ak != "magic-guard":
				e.dot = e.get("dot", 0.0) + e.max * dps * dt * (0.4 if e.boss else 1.0) * (2.0 if (e.get("bind", false) and e.sts == "trap") else 1.0)
				if e.dot >= 1:
					var d := int(floor(e.dot)); e.dot -= d; meter_dmg(live_tower(e.get("src")), min(d, e.hp), DOT_LABEL.get(e.sts, "Status"), true); e.hp -= d
					if e.hp <= 0: ko(live_tower(e.get("src")), e); continue
			if e.stt <= 0:
				if e.sts == "yawn": e.sts = null; inflict(e, "sleep")
				else:
					if e.sts == "sleep": e.imm = 4.0
					e.sts = null
		if e.stop > 0: e.stop -= dt
		else:
			var v: float = e.spd * e.pace * (1 + 0.12 * sin(B.time * e.sw * 1.7 + e.ph)) * STAGE(clampi(e.stg[6] + e.bst[6], -6, 6)) * (3.0 if e.dash > 0 else 1.0)
			if e.ak == "quick-feet" and e.sts != null: v *= 1.5
			if e.ak == "speed-boost": e.sbt += dt; v *= min(2, 1 + e.sbt / 40.0)
			v *= sk_speed(e)   # move skills
			var back: bool = e.get("back", 0.0) > B.time
			if back: v = -absf(v) * 0.6
			if decoy_blocks(e): v = 0
			if e.chill > 0: v *= 0.85
			if e.wsl > 0: v *= 0.9   # Ice / Water quirks
			for q in vines: if hyp(q[0], q[1], e.x, e.y) <= q[2]: v *= 0.9; break   # Grass quirk
			if e.sts == "paralysis": v *= 0.5
			if e.sts == "confusion": v *= (0.6 if sin(B.time * 6) > 0 else -0.3)
			e.d = max(1.0 if back else -1e9, e.d + v * dt)
		if e.dig:
			e.digt -= dt
			if e.digt <= 0: e.under = not e.under; e.digt = 2.5 if e.under else 2.2
		if e.hide:
			e.rev -= dt
			for t in B.towers:
				if sees(t) and hyp(t.x, t.y, e.x, e.y) <= max_range(t) * (1.5 if has_t(t, 13) else 1.0): e.rev = 0.4; break
		var rt := route_of(e); var pa := MG.path_at(B.M, max(0, e.d), rt); var x: float = pa[0]; var y: float = pa[1]; var a: float = pa[2]
		# drift across the path instead of marching on the centre line; ease the turn at corners
		var off: float = e.lane + sin(B.time * e.sw + e.ph) * 5; var nx := -sin(a); var ny := cos(a)
		var tx := x + nx * off; var ty2 := y + ny * off
		if e.px == null: e.x = tx; e.y = ty2
		else: var k: float = min(1, dt * 8); e.x += (tx - e.x) * k; e.y += (ty2 - e.y) * k
		e.px = e.x; e.py = e.y
		e.dir = dir_row(cos(a), sin(a))   # face along the path (the sway doesn't turn them)
		if e.d >= rt.len:
			e.hp = 0; e.dead = 0.0; B.lives -= e.lives
			if B.lives <= 0: B.lives = 0; finish(false); return
	B.en = B.en.filter(func(e): return e.hp > 0 or e.dead > 0)
	for t in B.towers:
		var ak: String = C.ab_key(t.e.ab)
		t.sbt = t.get("sbt", 0.0) + dt if B.phase == "wave" else 0.0
		var aura = AURA_AB.get(ak, null)
		if aura and B.phase == "wave":
			for e in B.en:
				if e.hp > 0 and e.sts == null and not e.under and hyp(e.x, e.y, t.x, t.y) < 38 and rnd() < 0.15 * dt:
					inflict(e, C.pick(["poison", "paralysis", "sleep"]) if aura == "spore" else aura, t)
		t.at += dt; t.cd -= dt
		if t.buft > 0:
			t.buft -= dt
			if t.buft <= 0: t.buf = {1: 0, 3: 0, 5: 0}
		if t.anim != "Idle" and t.at > anim_len(t.e.id, t.anim): t.anim = "Idle"; t.at = 0.0
		if t.cd <= 0 and B.phase == "wave":
			if not tower_act(t): t.cd = 0.15
	skill_tick(dt)
	var q2: Array = B.q2.duplicate()
	for a in q2:
		a.t -= dt
		if a.t <= 0: a.fn.call()
	B.q2 = B.q2.filter(func(a): return a.t > 0)
	for p in B.proj:
		p.at += dt
		var tx: float = p.tg.x; var ty: float = p.tg.y - (8 + (12 if p.tg.air else 0)) * ESPR; var d := hyp(tx, ty, p.x, p.y); var s: float = p.sp * dt
		if d <= s or (p.tg.hp <= 0 and d <= s * 2):
			p.hit = 1; p.done.call(p.tg)
			if p.hfx: add_fx(p.hfx, tx, ty, 0)
		else:
			p.x += (tx - p.x) / d * s; p.y += (ty - p.y) / d * s; p.row = dir_row(tx - p.x, ty - p.y); p.ang = atan2(ty - p.y, tx - p.x)
	B.proj = B.proj.filter(func(p): return not p.hit and p.at < 4)
	for f in B.fx: f.t += dt
	B.fx = B.fx.filter(func(f): return f.t < fx_len(f.a))
	for f in B.fl: f.t += dt
	B.fl = B.fl.filter(func(f): return f.t < 0.9)
func fx_len(a: Dictionary) -> float:
	if a.has("_len"): return a._len
	var s := 0
	for v in a.d: s += v
	a._len = s / 60.0; return a._len
func anim_len(id: int, name: String) -> float:
	var A = C.DB.anim.get(id, {}).get(name, null)
	if A == null: return 0.5
	return fx_len(A)
func finish(won: bool) -> void:
	B.phase = "win" if won else "lose"; B.over = true
	C.restore_forms()
	for tw in B.towers:   # friendship grows with every battle fought together (more for a win, a little for knockouts)
		tw.e.fr = mini(255, int(tw.e.get("fr", 70)) + (6 if won else 2) + mini(4, int(tw.kills / 25)))
		tw.e.lastnight = bool(B.get("night", false))
	var gm: Array = C.MAPGROUP[C.map_group(B.set)]
	var reward := int(round((100 + B.th * 80 + B.lives * 2 if won else floor(B.wave * B.th * 6)) * (1 + (mod("pay") + mod("bossPay") if won else 0.0)) * gm[3]))   # harder maps pay more
	B.reward = reward; G().money += reward; G().stats.maps = G().stats.get("maps", 0) + 1
	# Rescue Points: from clearing maps (a little for getting far on a loss)
	var rpm: float = gm[3]
	var rp := int(round((C.rp_for_clear(B.th) if won else floor(C.rp_for_clear(B.th) * B.wave / float(B.waves.size()) / 2)) * rpm))
	B.rp = rp; G().rp += rp
	B.drop = null; B.hdrop = null; B.stars = 0; B.starRp = 0
	if won:
		# stars: 1 for the win, 2 with 50+ lives left, 3 with all 100. Each new star pays half the tier's Rescue Points, once
		var sk := "%d:%d" % [B.set, B.tier]; var st := 1 + (1 if B.lives >= 50 else 0) + (1 if B.lives >= 100 else 0); var was: int = G().stars.get(sk, 0); B.stars = st
		if st > was: B.starRp = int(round(C.rp_for_clear(B.th) * 0.5 * (st - was) * rpm)); G().stars[sk] = st; G().rp += B.starRp
		G().stats.wins = G().stats.get("wins", 0) + 1
		# this map's next tier, and the first clear of a map opens the next map
		if B.tier >= C.map_tier(B.set) and B.tier < MAXTIER: G().mt[B.set] = B.tier + 1; B.unlocked = true
		if B.tier >= MAXTIER:
			if not G().has("mtDone"): G().mtDone = {}
			G().mtDone[B.set] = 1
		var g: int = C.map_group(B.set); var nx: int = B.set + 1
		if nx < C.NMAPS and C.map_group(nx) == g and not C.map_open(nx): G().mt[nx] = 1; B.mapOpened = C.DB.ts[nx].name
		var spo := C.check_specials()
		if spo != "": B.mapOpened = spo
		if g < 3 and B.tier >= C.group_gate(g + 1):
			var f: int = C.group_start(g + 1)
			if f >= 0 and not C.map_open(f):
				G().mt[f] = 1; B.groupOpened = C.MAPGROUP[g + 1][0]
				if not B.has("mapOpened"): B.mapOpened = C.DB.ts[f].name
		# held items: common ones from tier 1, the strongest (Choice items, Life Orb, Expert Belt) from tier 6
		if rnd() < min(0.85, 0.3 + B.th * 0.03 + mod("drop")):
			var ks := []
			for i in C.DB.dex.held: if B.th >= 6 + mod("rareTier") or not C.HELD_RARE.has(C.DB.dex.held[i].k): ks.append(i)
			var it: int = ks[randi() % ks.size()]; G().held[it] = G().held.get(it, 0) + 1; B.hdrop = it
		if B.th >= 3 and rnd() < 0.15 + B.th * 0.03 + mod("stone"):
			var its: Array = C.DB.dex.items.keys(); var it: int = its[randi() % its.size()]
			G().items[it] = G().items.get(it, 0) + 1; B.drop = it
	C.save(); music(("_e" if C.DB.ts[B.set].game == "E" else "_") + ("win" if won else "lose"))
	finished.emit()

# ---------- move skills: status moves given a tower-defence job (each one picked by the player, Nov 2026).
# They work on their own timer, beside the Pokémon's attacks. Effects use each move's own graphics.
var SKILL = null; var SKID := {}
func MID(n: String) -> int:
	if SKID.has(n): return SKID[n]
	var id := 0
	for k in C.DB.dex.moves: if C.DB.dex.moves[k].n == n: id = k; break
	SKID[n] = id; return id
func has_m(t: Dictionary, n: String) -> bool: return t.e.mv.has(MID(n))
func sk_r(t: Dictionary) -> float: return RANGE[3] * (1 + min(0.25, t.e.lv / 400.0) + mod("range")) * up_k(t, 0) * (1.15 if has_t(t, 2) else 1.0) * (1.2 if (t.has("acu") and t.acu.k == "r" and t.acu.u > B.time) else 1.0)
func visible(e: Dictionary) -> bool: return e.hp > 0 and e.d > 0 and not e.under and not (e.hide and not (e.rev > 0))
func any_visible() -> bool:
	for e in B.en: if visible(e): return true
	return false
func sk_in(t: Dictionary, r := 0.0) -> Array:
	var rr := r if r > 0 else sk_r(t); var out := []
	for e in B.en: if visible(e) and hyp(e.x, e.y, t.x, t.y) <= rr: out.append(e)
	return out
func sk_t(t: Dictionary):
	var l := sk_in(t); return choose_target(t, l) if l.size() else null
func stop_e(e: Dictionary, s: float) -> void: e.stop = max(e.stop, s / 2 if e.boss else s); meter_ctl(B.msrc, s / 2 if e.boss else s)
func slow_e(e: Dictionary, k: String, f: float, d: float) -> void:   # meter: slow seconds weighted by strength
	if not e.has("sl"): e.sl = {}
	e.sl[k] = [f, B.time + d]; meter_ctl(B.msrc, d * (1 - f) * 2)
func sk_speed(e: Dictionary) -> float:
	var v := 1.0
	if e.has("sl"):
		for k in e.sl.keys():
			if e.sl[k][1] > B.time: v *= e.sl[k][0]
			else: e.sl.erase(k)
	if e.has("tr") and e.tr[1] > B.time: v *= e.tr[0]
	return v
func en_types(e: Dictionary) -> Array:
	var o = e.get("tyo", null)
	if o == null or o.u <= B.time: return SP(e.id).t
	if not o.add: return o.t
	var s: Array = SP(e.id).t.duplicate()
	for x in o.t: if not s.has(x): s.append(x)
	return s.slice(0, 3)
func sk_fx(m: int, x: float, y: float, dir := 0) -> void:
	var f = C.DB.fx.moves.get(m, null)
	if f:
		var r = f.get("h", f.get("u", null))
		if r: add_fx(r, x, y - 8 * ESPR, dir)
func sk_use(t: Dictionary, m: int, e = null) -> void:
	var f = C.DB.fx.moves.get(m, null)
	if has_node("/root/Snd"): get_node("/root/Snd").move_sfx(m)
	if f and f.has("u"): add_fx(f.u, t.x, t.y, t.dir)
	if e != null: t.dir = dir_row(e.x - t.x, e.y - t.y); sk_fx(m, e.x, e.y, t.dir)
	t.anim = "Shoot"; t.at = 0.0
func near(t: Dictionary, r := 90.0) -> Array:
	var out := []
	for o in B.towers: if not is_same(o, t) and hyp(o.x, o.y, t.x, t.y) <= r: out.append(o)
	return out
func sk_attack(t: Dictionary, m: int, st: Array, src) -> bool:   # a full attack from a skill (Copycat, Metronome, Nature Power): same hit rules as a normal attack
	var M := mvd(m)
	if M.is_empty(): return false
	var r := tower_range(t, m) if RANGE.has(M.c) else sk_r(t); var list := targets(t, r, m)
	if list.is_empty(): return false
	var tg = choose_target(t, list); var fx: Dictionary = C.DB.fx.moves.get(m, {})
	t.dir = dir_row(tg.x - t.x, tg.y - t.y); t.anim = "Attack" if M.c == 2 else "Shoot"; t.at = 0.0
	if fx.has("u"): add_fx(fx.u, t.x, t.y, t.dir)
	var hit := func(g) -> void:
		var ts := []
		if aoe(M):
			if M.c == 3:
				for e in B.en: if e.hp > 0 and hyp(e.x, e.y, g.x, g.y) < 46 and can_hit(t, m, e): ts.append(e)
			else: ts = list
		else: ts = [g]
		for e in ts: apply_move(t, m, e, st)
	if fx.has("p") and M.c != 2: B.proj.append({"x": t.x, "y": t.y - 8 * SPR, "tg": tg, "fx": fx.p, "sp": 300.0, "at": 0.0, "done": hit, "hfx": fx.get("h", null), "row": 0, "ang": 0.0, "hit": 0})
	else:
		var hfx = fx.get("h", null); var dir: int = t.dir
		B.q2.append({"t": 0.12, "fn": func() -> void:
			if tg.hp > 0 or aoe(M):
				hit.call(tg)
				if hfx: add_fx(hfx, tg.x, tg.y - 8 * ESPR, dir)})
	if src != null: floater(t, src, 4)
	return true
func nature_move() -> String:   # Nature Power, Gen VII rules: the move depends on where the battle is
	var terr: Dictionary = B.terr; var now: float = B.time
	if terr.get(11, 0.0) > now: return "Energy Ball"
	if terr.get(17, 0.0) > now: return "Moonblast"
	if terr.get(12, 0.0) > now: return "Thunderbolt"
	if terr.get(13, 0.0) > now: return "Psychic"
	var S: Dictionary = C.DB.ts[B.set]; var T: Array = S.get("types", []); var nm: String = S.get("name", "").to_lower()
	var rx := func(words: String) -> bool:
		for w in words.split("|"): if nm.contains(w): return true
		return false
	if B.M.liq == "lava": return "Lava Plume"
	if T.has(14): return "Ice Beam"
	if B.M.liq == "water" and T.has(10): return "Hydro Pump"
	if rx.call("cave|cavern|crevice|grotto|ruin|tunnel|depth|crater|chamber|underground"): return "Power Gem"
	if T.has(11) or rx.call("wood|forest|jungle|meadow|field|garden|grass"): return "Energy Ball"
	if T.has(4) or T.has(5) or rx.call("sand|desert|mt |mount|peak|rock|cliff|canyon"): return "Earth Power"
	return "Tri Attack"
func nearest_path(x: float, y: float):
	var b = null
	for r in B.M.routes.size():
		var rt: Dictionary = B.M.routes[r]; var d := 0.0
		while d < rt.len:
			var p := MG.path_at(B.M, d, rt); var k := hyp(p[0], p[1], x, y)
			if b == null or k < b.k: b = {"r": r, "d": d, "x": p[0], "y": p[1], "k": k}
			d += 6
	return b
# skill builders (each returns the action: (t, m) -> used?)
func SLOWA(f: float, d: float, key := "growl") -> Callable:
	return func(t, m) -> bool:
		var l := sk_in(t)
		if l.is_empty(): return false
		for e in l: slow_e(e, key, f, d)
		sk_use(t, m, l[0]); return true
func STOP1(s: float) -> Callable:
	return func(t, m) -> bool:
		var e = sk_t(t)
		if e == null: return false
		stop_e(e, s); sk_use(t, m, e); return true
func TYPEC(ty: int, add: bool) -> Callable:
	return func(t, m) -> bool:
		var e = sk_t(t)
		if e == null: return false
		e.tyo = {"t": [ty], "add": add, "u": B.time + 6}; sk_use(t, m, e); return true
func NOTRICK(t, m) -> bool:
	var l := sk_in(t).filter(func(e): return e.get("prot", 0) or e.has("heal") or e.get("dashMv", 0) or e.get("tele", 0))
	var e = choose_target(t, l) if l.size() else null
	if e == null: return false
	e.nt = B.time + 6; floater(e, "No tricks", 4); sk_use(t, m, e); return true
func TRAP(kind: String) -> Callable:
	return func(t, m) -> bool:
		if not t.get("tp"): t.tp = nearest_path(t.x, t.y)
		if not t.tp: return false
		B.traps = B.traps.filter(func(x): return not is_same(x.t, t) or x.m != m)
		B.traps.append({"t": t, "m": m, "kind": kind, "r": t.tp.r, "d": t.tp.d, "x": t.tp.x, "y": t.tp.y, "hit": {}}); return true
func DECOY(t, m) -> bool:
	var p = nearest_path(t.x, t.y)
	if p == null: return false
	B.decoys = B.decoys.filter(func(x): return not is_same(x.t, t))
	B.decoys.append({"t": t, "m": m, "r": p.r, "d": p.d, "x": p.x, "y": p.y, "u": 0.0}); return true
func TEAMB(key: String, dur: float) -> Callable:
	return func(t, m) -> bool:
		if not any_visible(): return false
		for o in B.towers: o[key] = B.time + dur
		sk_use(t, m); floater(t, mvd(m).n, 4); return true
func NEARB(key: String, dur: float) -> Callable:
	return func(t, m) -> bool:
		var n := near(t)
		if n.is_empty() or not any_visible(): return false
		for o in n: o[key] = B.time + dur
		sk_use(t, m); return true
func SELFB(key: String, dur: float) -> Callable:
	return func(t, m) -> bool:
		if sk_in(t, sk_r(t) * 1.2).is_empty(): return false
		t[key] = B.time + dur; sk_use(t, m); return true
func WXSK(k: String) -> Callable:
	return func(t, m) -> bool:
		if not any_visible() or B.bwx or B.pwx: return false
		B.mwx = {"k": k, "until": B.time + 20}; sync_weather(); sk_use(t, m); floater(t, mvd(m).n, 4); return true
func TERRAIN(ty: int) -> Callable:
	return func(t, m) -> bool:
		if not any_visible(): return false
		B.terr[ty] = B.time + 10; sk_use(t, m); floater(t, mvd(m).n, 4); return true
func boosted(e: Dictionary) -> bool:
	for k in e.bst: if e.bst[k] > 0: return true
	return false
func COPYB(t, m) -> bool:
	var l := sk_in(t).filter(func(e): return e.bst[6] > 0)
	if l.is_empty(): return false
	var e = l[0]; t.buf[5] = max(t.buf[5], e.bst[6]); t.buft = 12.0; sk_use(t, m, e); return true
func COPYCAT(t, m) -> bool:
	var ns := near(t, 1e9)
	if ns.is_empty(): return false
	ns.sort_custom(func(a, b): return hyp(a.x, a.y, t.x, t.y) < hyp(b.x, b.y, t.x, t.y))
	var o = ns[0]
	var ms: Array = o.e.mv.filter(func(x): return C.move_use(x) == "dmg")
	ms.sort_custom(func(a, b): return mvd(b).get("p", 0) < mvd(a).get("p", 0))
	return sk_attack(t, ms[0], C.mon_stats(o.e), mvd(m).n) if ms.size() else false
var _dmg_moves := []
func _sk_quash(t, m) -> bool:
	var e = sk_t(t)
	if e == null: return false
	slow_e(e, "quash", 0.5, 2); sk_use(t, m, e); return true
func _sk_smoke(t, m) -> bool:
	var l := sk_in(t)
	if l.is_empty(): return false
	for e in l: e.stop = max(e.stop, 0.4)
	sk_use(t, m, l[0]); return true
func _sk_fairylock(t, m) -> bool:
	var l := sk_in(t)
	if l.is_empty(): return false
	for e in l: stop_e(e, 1)
	sk_use(t, m, l[0]); return true
func _sk_charm(t, m) -> bool:
	var e = sk_t(t)
	if e == null: return false
	e.back = B.time + (0.75 if e.boss else 1.5); sk_use(t, m, e); return true
func _sk_roar(t, m) -> bool:
	var l := sk_in(t).filter(func(e): return not e.boss)
	var e = choose_target(t, l) if l.size() else null
	if e == null: return false
	e.d = max(1, e.d - 60); e.px = null; sk_use(t, m, e); return true
func _sk_curse(t, m) -> bool:
	var e = sk_t(t)
	if e == null: return false
	e.cu = {"left": e.max * (0.1 if e.boss else 0.25), "dps": e.max * (0.1 if e.boss else 0.25) / 8.0, "t": t}; sk_use(t, m, e); return true
func _sk_electrify(t, m) -> bool:
	var e = sk_t(t)
	if e == null: return false
	e.elz = B.time + 6; sk_use(t, m, e); return true
func _sk_gastro(t, m) -> bool:
	var l := sk_in(t).filter(func(e): return e.ak != null and e.ak != "" and not e.get("akOff", 0.0))
	var e = choose_target(t, l) if l.size() else null
	if e == null: return false
	e.ak0 = e.ak; e.ak = ""; e.akOff = B.time + 8; floater(e, "Ability off", 4); sk_use(t, m, e); return true
func _sk_haze(t, m) -> bool:
	var l := sk_in(t).filter(func(e): return boosted(e))
	if l.is_empty(): return false
	for e in l: e.bst = {3: 0, 5: 0, 6: 0}
	sk_use(t, m, l[0]); return true
func _sk_topsy(t, m) -> bool:
	var l := sk_in(t).filter(func(e): return boosted(e))
	if l.is_empty(): return false
	var e = l[0]
	for k in e.bst: e.bst[k] = -e.bst[k]
	sk_use(t, m, e); return true
func _sk_painsplit(t, m) -> bool:
	var l := sk_in(t).filter(func(e): return not e.boss and e.hp > e.max / 2.0)
	var e = choose_target(t, l) if l.size() else null
	if e == null: return false
	var to := int(ceil((e.hp + e.max / 2.0) / 2.0)); hurt(t, e, e.hp - to); sk_use(t, m, e); return true
func _sk_guardsplit(t, m) -> bool:
	var e = sk_t(t)
	if e == null: return false
	e.gs = B.time + 6; e.gsf = 0.75; sk_use(t, m, e); return true
func _sk_octolock(t, m) -> bool:
	var e = sk_t(t)
	if e == null: return false
	stop_e(e, 1); e.gs = B.time + 6; e.gsf = 0.8; sk_use(t, m, e); return true
func _sk_perish(t, m) -> bool:
	var l := sk_in(t).filter(func(e): return not e.boss and not e.get("pm", 0.0))
	if l.is_empty(): return false
	for e in l:
		e.pm = B.time + 6; e.pmT = t
	sk_use(t, m, l[0]); floater(t, "Perish Song", 4); return true
func _sk_sweetscent(t, m) -> bool:
	var l := sk_in(t)
	if l.is_empty(): return false
	for e in l: e.lure = B.time + 5
	sk_use(t, m, l[0]); return true
func _sk_trickroom(t, m) -> bool:
	var l := sk_in(t)
	if l.size() < 2: return false
	var lo := 1e9; var hi := -1e9
	for e in l:
		lo = min(lo, e.spd); hi = max(hi, e.spd)
	for e in l: e.tr = [clampf((lo + hi - e.spd) / e.spd, 0.4, 1.5), B.time + 6]
	sk_use(t, m, l[0]); return true
func _sk_psychoshift(t, m) -> bool:
	var l := sk_in(t); var a = null; var b = null
	for e in l:
		if e.sts != null and e.sts != "yawn": a = e; break
	if a != null:
		for e in l:
			if not is_same(e, a) and e.sts == null: b = e; break
	if b == null: return false
	inflict(b, a.sts, t); sk_use(t, m, b); return true
func _sk_speedswap(t, m) -> bool:
	var e = sk_t(t)
	if e == null: return false
	slow_e(e, "swap", 0.6, 4); t.ssw = B.time + 4; sk_use(t, m, e); return true
func _sk_laser(t, m) -> bool:
	if t.get("lf", 0): return false
	t.lf = 1; return true
func _sk_charge(t, m) -> bool:
	if t.get("chg", 0): return false
	t.chg = 1; return true
func _sk_acupressure(t, m) -> bool:
	if sk_in(t, sk_r(t) * 1.2).is_empty(): return false
	t.acu = {"k": C.pick(["d", "s", "r"]), "u": B.time + 6}; sk_use(t, m); floater(t, {"d": "Power up", "s": "Speed up", "r": "Range up"}[t.acu.k], 4); return true
func _sk_encore(t, m) -> bool:
	var n := near(t).filter(func(o): return not o.get("enc", 0))
	if n.is_empty() or not any_visible(): return false
	n[0].enc = 1; sk_use(t, m); return true
func _sk_metronome(t, m) -> bool:
	if _dmg_moves.is_empty():
		for x in C.DB.dex.moves:
			if C.move_use(x) == "dmg" and not OHKO.has(x): _dmg_moves.append(x)
	return sk_attack(t, C.pick(_dmg_moves), C.mon_stats(t.e), "Metronome")
func _sk_nature(t, m) -> bool:
	var n := nature_move(); return sk_attack(t, MID(n), C.mon_stats(t.e), n)
func build_skills() -> Dictionary:
	var D := {   # name: [cooldown s, action(t, move) -> used?] ; passive ones have no action (handled where they matter)
		"Growl": [6, SLOWA(0.8, 3)], "Baby-Doll Eyes": [6, SLOWA(0.8, 3)], "Play Nice": [6, SLOWA(0.8, 3)], "Feather Dance": [6, SLOWA(0.8, 3)], "Noble Roar": [6, SLOWA(0.8, 3)],
		"Parting Shot": [6, SLOWA(0.8, 3)], "Eerie Impulse": [6, SLOWA(0.8, 3)], "Confide": [6, SLOWA(0.8, 3)],
		"Sand Attack": [6, STOP1(0.6)], "Mean Look": [12, STOP1(1)], "Block": [12, STOP1(1)], "Attract": [12, STOP1(1.2)],
		"Quash": [10, _sk_quash], "Smokescreen": [8, _sk_smoke], "Fairy Lock": [30, _sk_fairylock], "Charm": [8, _sk_charm], "Roar": [10, _sk_roar], "Curse": [12, _sk_curse],
		"Disable": [8, NOTRICK],
		"Soak": [8, TYPEC(10, false)], "Magic Powder": [8, TYPEC(13, false)], "Trick-or-Treat": [8, TYPEC(7, true)], "Forest’s Curse": [8, TYPEC(11, true)],
		"Electrify": [12, _sk_electrify], "Gastro Acid": [10, _sk_gastro], "Haze": [10, _sk_haze], "Topsy-Turvy": [12, _sk_topsy],
		"Pain Split": [15, _sk_painsplit], "Guard Split": [12, _sk_guardsplit], "Octolock": [14, _sk_octolock], "Perish Song": [30, _sk_perish], "Sweet Scent": [10, _sk_sweetscent],
		"Psych Up": [15, COPYB], "Heart Swap": [15, COPYB], "Trick Room": [30, _sk_trickroom], "Psycho Shift": [10, _sk_psychoshift], "Speed Swap": [12, _sk_speedswap],
		"Focus Energy": [20, SELFB("fe", 10)], "Take Heart": [15, SELFB("th", 8)], "Double Team": [20, SELFB("dt", 5)],
		"Laser Focus": [8, _sk_laser], "Charge": [8, _sk_charge], "Acupressure": [15, _sk_acupressure],
		"Helping Hand": [15, NEARB("hh", 6)], "Encore": [10, _sk_encore], "Tailwind": [30, TEAMB("tw", 6)],
		"Rain Dance": [60, WXSK("rain")], "Sunny Day": [60, WXSK("sun")], "Sandstorm": [60, WXSK("sand")], "Hail": [60, WXSK("hail")], "Snowscape": [60, WXSK("hail")],
		"Electric Terrain": [30, TERRAIN(12)], "Grassy Terrain": [30, TERRAIN(11)], "Misty Terrain": [30, TERRAIN(17)], "Psychic Terrain": [30, TERRAIN(13)],
		"Stealth Rock": [20, TRAP("rock")], "Spikes": [20, TRAP("spikes")], "Toxic Spikes": [20, TRAP("toxic")], "Sticky Web": [20, TRAP("web")],
		"Substitute": [20, DECOY], "Shed Tail": [20, DECOY],
		"Copycat": [6, COPYCAT], "Mimic": [6, COPYCAT],
		"Metronome": [5, _sk_metronome], "Nature Power": [6, _sk_nature],
		# passives (no action)
		"Endure": [0], "Ingrain": [0], "Baton Pass": [0], "Lock-On": [0], "Mind Reader": [0], "Power Trick": [0], "Defog": [0], "Mist": [0], "Transform": [0],
		"Teleport": [0], "Ally Switch": [0], "Sketch": [0], "Splash": [0], "Baneful Bunker": [0], "Burning Bulwark": [0], "Silk Trap": [0],
	}
	D["Whirlwind"] = D["Roar"]; D["Instruct"] = D["Encore"]
	SKILL = {}
	for n in D:
		var id := MID(n)
		if id: SKILL[id] = {"n": n, "cd": D[n][0], "act": D[n][1] if D[n].size() > 1 else null}
	return SKILL
func skills() -> Dictionary: return SKILL if SKILL != null else build_skills()
func _ready() -> void:
	for n in SKDESC: C.SKDESC[n] = SKDESC[n]
const SKDESC := {
	"Growl": "Enemies in range move 20% slower for 3 s",
	"Baby-Doll Eyes": "Enemies in range move 20% slower for 3 s",
	"Play Nice": "Enemies in range move 20% slower for 3 s",
	"Feather Dance": "Enemies in range move 20% slower for 3 s",
	"Noble Roar": "Enemies in range move 20% slower for 3 s",
	"Parting Shot": "Enemies in range move 20% slower for 3 s",
	"Eerie Impulse": "Enemies in range move 20% slower for 3 s",
	"Confide": "Enemies in range move 20% slower for 3 s",
	"Sand Attack": "The target stops for 0.6 s (every 6 s)",
	"Mean Look": "The target stops for 1 s (every 12 s)",
	"Block": "The target stops for 1 s (every 12 s)",
	"Attract": "The target stops for 1.2 s (every 12 s)",
	"Quash": "The target moves 50% slower for 2 s (every 10 s)",
	"Smokescreen": "Enemies in range stop for 0.4 s (every 8 s)",
	"Fairy Lock": "Enemies in range stop for 1 s (every 30 s)",
	"Charm": "The target walks backward for 1.5 s (every 8 s)",
	"Roar": "Pushes the target back along the path (not bosses, every 10 s)",
	"Whirlwind": "Pushes the target back along the path (not bosses, every 10 s)",
	"Curse": "The target loses 25% of its max HP over 8 s (bosses 10%, every 12 s)",
	"Disable": "The target can't shield, heal, dash or teleport for 6 s",
	"Soak": "The target becomes pure Water type for 6 s",
	"Magic Powder": "The target becomes pure Psychic type for 6 s",
	"Trick-or-Treat": "The target also counts as Ghost type for 6 s",
	"Forest’s Curse": "The target also counts as Grass type for 6 s",
	"Electrify": "Electric attacks deal double damage to the target for 6 s (every 12 s)",
	"Gastro Acid": "The target's ability stops working for 8 s",
	"Haze": "Removes the stat boosts of enemies in range (every 10 s)",
	"Topsy-Turvy": "Turns an enemy's stat boosts into drops (every 12 s)",
	"Pain Split": "A non-boss target over half HP loses about a quarter of its max HP (every 15 s)",
	"Guard Split": "The target's defences drop 25% for 6 s (every 12 s)",
	"Octolock": "The target stops for 1 s, then its defences drop 20% for 6 s (every 14 s)",
	"Perish Song": "Non-boss enemies in range lose 30% of their max HP 6 s later (every 30 s)",
	"Sweet Scent": "Enemies in range are 2x as likely to ask to join if knocked out within 5 s",
	"Psych Up": "Copies an enemy's Speed boosts as attack speed (every 15 s)",
	"Heart Swap": "Copies an enemy's Speed boosts as attack speed (every 15 s)",
	"Trick Room": "For 6 s the fastest enemies in range become the slowest (every 30 s)",
	"Psycho Shift": "Copies a status condition onto another enemy in range (every 10 s)",
	"Speed Swap": "The target moves 40% slower and this Pokémon attacks 40% faster for 4 s (every 12 s)",
	"Focus Energy": "Much higher critical-hit chance for 10 s (every 20 s)",
	"Laser Focus": "Every 8 s its next attack is a sure critical hit",
	"Charge": "Every 8 s its next Electric attack deals double damage",
	"Double Team": "For 5 s its attacks hit twice (every 20 s)",
	"Take Heart": "Its special attacks deal +20% for 8 s (every 15 s)",
	"Acupressure": "A random boost for 6 s: +30% damage, attack speed or +20% range (every 15 s)",
	"Helping Hand": "Teammates close by deal +25% damage for 6 s (every 15 s)",
	"Encore": "Every 10 s, the next attack of a teammate close by happens twice",
	"Instruct": "Every 10 s, the next attack of a teammate close by happens twice",
	"Tailwind": "All your Pokémon attack 25% faster for 6 s (every 30 s)",
	"Rain Dance": "Rain for 20 s (every 60 s)",
	"Sunny Day": "Sun for 20 s (every 60 s)",
	"Sandstorm": "A sandstorm for 20 s (every 60 s)",
	"Hail": "Hail for 20 s (every 60 s)",
	"Snowscape": "Hail for 20 s (every 60 s)",
	"Electric Terrain": "Your team's Electric moves deal +30% for 10 s (every 30 s)",
	"Grassy Terrain": "Your team's Grass moves deal +30% for 10 s (every 30 s)",
	"Misty Terrain": "Your team's Fairy moves deal +30% for 10 s (every 30 s)",
	"Psychic Terrain": "Your team's Psychic moves deal +30% for 10 s (every 30 s)",
	"Stealth Rock": "Rocks on the nearest path: each enemy crossing takes Rock damage once (renewed every 20 s)",
	"Spikes": "Spikes on the nearest path: each enemy crossing loses 8% of its max HP once (renewed every 20 s)",
	"Toxic Spikes": "Spikes on the nearest path poison enemies crossing (renewed every 20 s)",
	"Sticky Web": "A web on the nearest path: enemies crossing move 40% slower for 3 s (renewed every 20 s)",
	"Substitute": "A decoy on the path holds enemies up for 2 s (every 20 s)",
	"Shed Tail": "A decoy on the path holds enemies up for 2 s (every 20 s)",
	"Copycat": "Uses the nearest teammate's strongest attack at its power (every 6 s)",
	"Mimic": "Uses the nearest teammate's strongest attack at its power (every 6 s)",
	"Metronome": "Uses a random attack (every 5 s)",
	"Nature Power": "Uses an attack that depends on the map (every 6 s)",
	"Endure": "Attacks 30% faster while you have under 25 lives",
	"Ingrain": "+5% damage for every 10 s it stays placed (up to +30%)",
	"Baton Pass": "Its stat boosts also apply to teammates close by",
	"Lock-On": "Its attacks never miss",
	"Mind Reader": "Its attacks never miss",
	"Power Trick": "Physical attacks use its Attack or Defense, whichever is higher",
	"Defog": "Sees hidden Ghost types",
	"Mist": "Bosses in its range can't raise their stats",
	"Transform": "Fights with the stats and moves of your strongest placed teammate, at its own level",
	"Teleport": "Can be moved to a new spot during battle for free",
	"Ally Switch": "Can swap spots with a placed teammate during battle for free",
	"Sketch": "Out of battle, can be swapped for a move learned by a Pokémon you've seen",
	"Splash": "Enemies right next to it move 10% slower",
	"Baneful Bunker": "Enemies right next to it may get poisoned",
	"Burning Bulwark": "Enemies right next to it may get burned",
	"Silk Trap": "Enemies right next to it move 30% slower for 2 s",
}
# per-tick work: skill timers, traps, decoys, adjacency auras
func skill_tick(dt: float) -> void:
	var S := skills(); var wave: bool = B.phase == "wave"
	for t in B.towers:
		if not t.has("skc"): t.skc = {}
		if not wave: continue
		for m in t.e.mv:
			var s = S.get(m, null)
			if s == null or s.act == null: continue
			t.skc[m] = (1 + rnd() if not t.skc.has(m) else t.skc[m]) - dt
			if t.skc[m] <= 0:
				B.msrc = t; B.mlab = s.n; t.skc[m] = s.cd if s.act.call(t, m) else 0.5; B.msrc = null
		var sp := has_m(t, "Splash"); var silk := has_m(t, "Silk Trap"); var bb := has_m(t, "Baneful Bunker"); var bw := has_m(t, "Burning Bulwark")
		if sp or silk or bb or bw:
			for e in B.en:
				if not (visible(e) and hyp(e.x, e.y, t.x, t.y) < 38): continue
				if sp: slow_e(e, "splash", 0.9, 1)
				if silk: slow_e(e, "silk", 0.7, 2)
				meter_ctl(t, dt * (0.6 if silk else 0.2))
				if bb and e.sts == null and rnd() < 0.5 * dt: inflict(e, "poison", t)
				if bw and e.sts == null and rnd() < 0.5 * dt: inflict(e, "burn", t)
	for tr in B.traps:
		for e in B.en.duplicate():
			if visible(e) and not e.air and e.r == tr.r and absf(e.d - tr.d) < 10 and not tr.hit.has(e.eid):
				tr.hit[e.eid] = 1; B.msrc = tr.t; B.mlab = mvd(tr.m).n
				if tr.kind == "rock": hurt(tr.t, e, max(1, int(floor(e.max * 0.125 * C.eff(5, en_types(e))))))
				elif tr.kind == "spikes": hurt(tr.t, e, max(1, int(floor(e.max * 0.08))))
				elif tr.kind == "toxic": inflict(e, "poison", tr.t)
				elif tr.kind == "web": slow_e(e, "web", 0.6, 3)
				B.msrc = null
	B.traps = B.traps.filter(func(tr): return has_ref(B.towers, tr.t))
	B.decoys = B.decoys.filter(func(dc): return has_ref(B.towers, dc.t) and not (dc.u and dc.u < B.time))
	for k in B.terr.keys(): if B.terr[k] < B.time: B.terr.erase(k)
	if B.mwx and B.mwx.until < B.time: B.mwx = null; sync_weather()
func decoy_blocks(e: Dictionary) -> bool:
	if e.air or e.boss: return false
	for dc in B.decoys:
		if dc.r == e.r and e.d < dc.d and dc.d - e.d < 8:
			if not dc.u: dc.u = B.time + 2
			return true
	return false
func buf_of(t: Dictionary, k: int) -> int:
	var v: int = t.buf[k]
	for o in B.towers:
		if not is_same(o, t) and o.buft > 0 and has_m(o, "Baton Pass") and hyp(o.x, o.y, t.x, t.y) <= 90: v = max(v, o.buf[k])
	return v
func transform_src(t: Dictionary):
	if not has_m(t, "Transform"): return null
	var best = null
	for x in B.towers:
		if is_same(x, t) or has_m(x, "Transform"): continue
		if best == null or x.e.lv > best.e.lv: best = x
	return best

# ---------- damage meter: what each of your Pokémon did this battle (HP actually lost, no overkill, shields don't count) ----------
func mtr(t):
	if t == null or B == null or not t.has("e"): return null
	var M: Dictionary = B.meter
	if not M.has(t.e.u): M[t.e.u] = {"u": t.e.u, "id": t.e.id, "dmg": 0, "ko": 0, "dot": 0, "ctl": 0.0, "br": {}}
	return M[t.e.u]
func meter_dmg(t, amt, label: String, dot := false) -> void:
	var m = mtr(t)
	if m == null or not (amt > 0): return
	m.id = t.e.id; m.dmg += amt; m.br[label] = m.br.get(label, 0) + amt
	if dot: m.dot += amt
func meter_ctl(t, sec: float) -> void:
	var m = mtr(t)
	if m != null and sec > 0: m.ctl += sec
