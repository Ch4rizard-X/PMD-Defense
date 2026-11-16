extends Node
# Route Defense - core: data, assets, Pokémon maths, save (ported from the HTML version's core.js)
# Autoload "C". Data comes from data/*.bin (made by tools/convert_data.gd): whole numbers are ints, number keys are int keys.

var DB := {}
var SP := {}          # species id -> data
const TYPES := ["Normal","Fighting","Flying","Poison","Ground","Rock","Bug","Ghost","Steel","Fire","Water","Grass","Electric","Psychic","Ice","Dragon","Dark","Fairy"]
const TCOL_HEX := ["#a8a878","#c03028","#a890f0","#a040a0","#e0c068","#b8a038","#a8b820","#705898","#b8b8d0","#f08030","#6890f0","#78c850","#f8d030","#f85888","#98d8d8","#7038f8","#705848","#ee99ac"]
var TCOL: Array[Color] = []

func rnd() -> float: return randf()
func clampf2(v: float, a: float, b: float) -> float: return a if v < a else (b if v > b else v)
func pick(a: Array): return a[randi() % a.size()]

func _ready() -> void:
	randomize()
	for h in TCOL_HEX: TCOL.append(Color(h))
	load_db()
	G = load_save()

func load_db() -> void:
	for k in ["dex", "anim", "ts", "fx", "snd", "tree", "icons", "wx", "mk", "micons", "shiny", "tsx"]:
		var f := FileAccess.open("res://data/%s.bin" % k, FileAccess.READ)
		DB[k] = f.get_var() if f else {}
	# special maps (Ultra Wormhole, Paradox Portal) go after the normal ones: NMAPS counts only the normal maps
	NMAPS = DB.ts.size()
	if DB.tsx is Array: DB.ts += DB.tsx
	# DB.dex.mon: every species + the regional forms (wild Pokémon, Pokédex); DB.dex.forms: battle forms (Megas, Primals,
	# boss forms, fusions, Rotom / Deoxys / Shaymin forms): in C.SP for battles, but never wild or in the Pokédex
	for m in DB.dex.mon + DB.dex.get("forms", []):
		m["anim"] = 1 if DB.anim.has(m.id) else 0
		var s := 0
		for b in m.b: s += b
		m["bst"] = s
		SP[m.id] = m
	# Arceus / Silvally type forms (SpriteCollab sprites 0493/0773 subgroups 1-17): the same Pokémon with another type
	var SCT := ["Bug", "Dark", "Dragon", "Electric", "Fighting", "Fire", "Flying", "Ghost", "Grass", "Ground", "Ice", "Poison", "Psychic", "Rock", "Steel", "Water", "Fairy"]
	for b in [493, 773]:
		if not SP.has(b): continue
		for k in range(1, 18):
			var vid: int = VARIANT + int(b) * 100 + k
			if not DB.anim.has(vid): continue
			var m: Dictionary = SP[b].duplicate(true); m.id = vid; m.t = [TYPES.find(SCT[k - 1])]; m.n = "%s (%s)" % [SP[b].n, SCT[k - 1]]
			m.base = b; m.form = "form"; m.anim = 1; SP[vid] = m

# ---------- assets ----------
var _tex := {}
func tex(p: String) -> Texture2D:
	if _tex.has(p): return _tex[p]
	var t: Texture2D = load("res://" + p) if ResourceLoader.exists("res://" + p) else null
	_tex[p] = t
	return t
# sprite ids: a species' own id, or id + SHINY for its shiny (SpriteCollab's shiny sheets, img/mon/NNNN_s.webp, each
# with its own animation layout in data/shiny.bin). Species data (C.SP) always uses the plain id.
const SHINY := 100000
const VARIANT := 200000   # sprite-only variants: VARIANT + species * 100 + SpriteCollab subgroup (Deerling seasons, Arceus types...)
func sid(e) -> int:
	var id := int(e.id)
	if e.get("shiny", false): return id + SHINY
	if (id == 585 or id == 586) and season() > 0: return VARIANT + id * 100 + season()   # Deerling / Sawsbuck wear the season
	if e.get("vform", 0): return VARIANT + id * 100 + int(e.vform)                     # a chosen look (Arceus / Silvally type)
	return id
func has_shiny(id: int) -> bool: return DB.get("shiny", {}).has(id)
func anim_of(s: int):
	if s >= VARIANT: return DB.anim.get(s, DB.anim.get((s - VARIANT) / 100, null))
	if s >= SHINY: return DB.get("shiny", {}).get(s - SHINY, DB.anim.get(s - SHINY, null))
	return DB.anim.get(s, null)
func mon_tex(id: int) -> Texture2D:
	if id >= VARIANT: return tex("img/mon/%d.webp" % id) if DB.anim.has(id) else tex("img/mon/%04d.webp" % ((id - VARIANT) / 100))
	if id >= SHINY and has_shiny(id - SHINY): return tex("img/mon/%04d_s.webp" % (id - SHINY))
	return tex("img/mon/%04d.webp" % (id % SHINY))

# ---------- Pokémon maths (main-series formulas: IVs 0-31, nature x1.1 / x0.9 on one stat each, no EVs) ----------
func calc_stats(id: int, lv: int, iv, nat: int) -> Array:
	var b: Array = SP[id].b
	var N = DB.dex.nat[nat - 1] if nat > 0 else null
	var out := []
	for i in 6:
		var I: int = iv[i] if iv != null else 15
		if i == 0:
			out.append(int(floor((2 * b[i] + I) * lv / 100.0)) + lv + 10)
		else:
			var s := int(floor((2 * b[i] + I) * lv / 100.0)) + 5
			if N != null and N.up != N.dn:
				s = int(floor(s * (1.1 if i == N.up else (0.9 if i == N.dn else 1.0))))
			out.append(s)
	return out
func roll_iv() -> Array:
	var a := []
	for i in 6: a.append(randi() % 32)
	return a
func roll_nat() -> int: return 1 + randi() % 25
func ivs_of(e: Dictionary) -> Array:   # Bottle Caps raise a stat as if its IV were 31 (like Hyper Training)
	var a := []
	for i in 6: a.append(31 if (e.has("ht") and e.ht[i]) else e.iv[i])
	return a
func nat_of(e: Dictionary) -> int: return e.mint if e.get("mint", 0) else e.nat   # a Mint changes how the nature affects stats; the nature itself stays
func mon_stats(e: Dictionary) -> Array: return calc_stats(e.id, e.lv, ivs_of(e), nat_of(e))
const STATN := ["HP", "Atk", "Def", "SpA", "SpD", "Spe"]
func nat_label(n: int) -> String:
	var N = DB.dex.nat[n - 1]
	return N.n + " (neutral)" if N.up == N.dn else "%s (+%s -%s)" % [N.n, STATN[N.up], STATN[N.dn]]
const TOOL_PRICE := {"mint": 2000, "bottle-cap": 5000, "gold-bottle-cap": 25000}
func xp_for(gr: int, lv: int) -> int:
	var t = DB.dex.xp[gr]
	return t[100] if lv >= 100 else t[lv]
const MAXLV := 100
func moves_at(id: int, lv: int) -> Array:   # the last four moves learned by this level (what a wild one knows)
	var out := []
	for x in SP[id].ls:
		var l: int = x[0]; var m: int = x[1]
		if l <= lv and DB.dex.moves.has(m) and not out.has(m):
			out.append(m)
			if out.size() > 4: out.pop_front()
	return out
func new_moves_at(id: int, lv: int) -> Array:
	var out := []
	for x in SP[id].ls:
		if x[0] == lv and DB.dex.moves.has(x[1]): out.append(x[1])
	return out
func mv(id: int) -> Dictionary: return DB.dex.moves.get(id, {})
const AILMENTS := ["paralysis", "sleep", "freeze", "burn", "poison", "confusion", "trap", "yawn", "leech-seed"]
func move_use(id: int):   # how a tower can use a move: "dmg" | "status" | "debuff" | "buff" | null
	var m := mv(id)
	if m.is_empty(): return null
	if m.c != 1: return "dmg"
	if AILMENTS.has(m.get("ai", "")) and m.tg != 7: return "status"
	if m.tg != 7:
		for s in m.sc:
			if s[1] < 0 and (s[0] == 3 or s[0] == 5 or s[0] == 6): return "debuff"
	for s in m.sc:
		if s[1] > 0 and (s[0] == 2 or s[0] == 4 or s[0] == 6): return "buff"
	return null
var SKDESC := {}   # filled by the battle skills
func move_desc(id: int) -> String:
	var m := mv(id); var u = move_use(id)
	var k := "Physical" if m.c == 2 else ("Special" if m.c == 3 else "Status")
	var s := "%s - %s" % [TYPES[m.t], k]
	if m.c != 1: s += " - Pow %s" % (str(m.p) if m.get("p", 0) else "-")
	if m.get("a", 0): s += " - Acc %d" % m.a
	s += " - PP %d" % m.pp
	var sk = SKDESC.get(m.n, "")
	if sk != "": s += " - " + sk
	elif u == null: s += " - (no use in battle)"
	if id == 206: s += " - Knockouts with it are 3x as likely to ask to join"
	return s
func move_value(id: int, sp: int) -> float:   # rough worth of a move for a tower, used to pick starting moves
	var m := mv(id); var u = move_use(id)
	if u == null: return 0.0
	var b: Array = SP[sp].b
	var side := 1.0
	if m.c == 2: side = b[1] / float(max(b[1], b[3]))
	elif m.c == 3: side = b[3] / float(max(b[1], b[3]))
	if u == "dmg":
		var p: float = m.p if m.get("p", 0) else 55
		return p * side * (1.15 if m.c == 3 else 1.0) * (1.5 if SP[sp].t.has(m.t) else 1.0) * ((m.a if m.get("a", 0) else 100) / 100.0) * ((m.h[0] + m.h[1]) / 2.0) * (1.3 if (m.tg == 9 or m.tg == 11) else 1.0)
	if u == "status": return 50.0 if (m.ai == "sleep" or m.ai == "freeze" or m.ai == "trap") else 35.0
	return 30.0 if u == "buff" else 20.0
func learned_by(id: int, lv: int) -> Array:
	var s := []
	for x in SP[id].ls:
		if x[0] <= lv and DB.dex.moves.has(x[1]) and not s.has(x[1]): s.append(x[1])
	return s
func best_moves(id: int, lv: int) -> Array:
	var all0 := learned_by(id, lv); var idx := []
	for i in all0.size(): idx.append([-move_value(all0[i], id), i])
	idx.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))   # stable, like JavaScript's sort
	var all := []
	for q in idx: all.append(all0[q[1]])
	var out := []; var types := {}
	for m in all:
		if out.size() >= 4: break
		var k: int = mv(m).t
		if move_use(m) == "dmg" and types.has(k) and all.size() > 6:
			var same := 0
			for x in out: if mv(x).t == k: same += 1
			if same >= 2: continue
		out.append(m); types[k] = 1
	return out if out.size() else moves_at(id, lv)
func eff(t: int, def_types: Array) -> float:
	var f := 1.0
	for d in def_types: f *= DB.dex.chart[t][d]
	return f
func evo_options(e: Dictionary) -> Array:   # evolutions this box Pokémon can take right now
	var s = SP[e.id]; var out := []
	for v in s.ev:
		var t = SP.get(v.to)
		if t == null or not t.anim: continue
		var ok := false; var why := ""
		var tr: int = v.get("tr", 0)
		if tr == 1:
			if v.get("happy", 0) > 1:   # friendship evolution: PokeAPI's own friendship (160 / 220), time of day, known-move type
				var fr: int = e.get("fr", 70); var tod: String = v.get("tod", ""); var mt: int = v.get("mtype", -1)
				var known := mt < 0
				for m in e.mv: if mt >= 0 and DB.dex.moves.has(m) and DB.dex.moves[m].t == mt: known = true
				var tok: bool = tod == "" or (tod == "night") == bool(e.get("lastnight", false))
				ok = fr >= v.happy and tok and known
				why = "Friendship %d/%d%s%s" % [fr, v.happy, (", after a %s battle" % tod) if tod != "" else "", (", knowing a %s move" % TYPES[mt]) if mt >= 0 else ""]
			else:
				var need: int = v.get("lv", 0) if v.get("lv", 0) else (32 if v.get("move", 0) else 30)
				ok = e.lv >= need; why = "Lv %d" % need
		elif tr == 2: ok = e.lv >= 36; why = "Lv 36"
		elif tr == 3:
			var it = v.item; ok = G.items.get(it, 0) > 0; why = DB.dex.items.get(it, "item")
		else: ok = e.lv >= 30; why = "Lv 30"
		out.append({"to": v.to, "ok": ok, "why": why, "item": v.item if tr == 3 else 0})
	return out

# ---------- abilities: real ones from the data; these have a tower-defense meaning ----------
const AB_TD := {
	"overgrow": "Grass moves x1.5 when your lives are at 1/3 or less", "blaze": "Fire moves x1.5 when your lives are at 1/3 or less",
	"torrent": "Water moves x1.5 when your lives are at 1/3 or less", "swarm": "Bug moves x1.5 when your lives are at 1/3 or less",
	"compound-eyes": "Accuracy x1.3", "hustle": "Physical moves x1.5, accuracy x0.8", "huge-power": "Physical moves x2", "pure-power": "Physical moves x2",
	"adaptability": "Same-type bonus is x2 instead of x1.5", "technician": "Moves with 60 power or less x1.5", "skill-link": "Multi-hit moves always hit the most times",
	"serene-grace": "Added effects happen twice as often", "sniper": "Critical hits do x2.25", "super-luck": "Critical hits more likely",
	"sheer-force": "Moves with added effects x1.3, but the effects are lost", "tinted-lens": "\"Not very effective\" hits do double",
	"tough-claws": "Physical moves x1.3", "no-guard": "Moves never miss", "keen-eye": "Can see hidden Pokémon", "frisk": "Can see hidden Pokémon",
	"scrappy": "Normal and Fighting moves hit Ghost types", "speed-boost": "Attacks faster the longer a wave goes on",
	"static": "Wild Pokémon walking close by may be paralyzed", "flame-body": "Wild Pokémon walking close by may be burned",
	"poison-point": "Wild Pokémon walking close by may be poisoned", "effect-spore": "Wild Pokémon walking close by may be poisoned, paralyzed or put to sleep",
	"swift-swim": "Attacks x1.5 faster in rain or when standing in water", "chlorophyll": "Attacks x1.5 faster in sun", "sand-rush": "Attacks x1.5 faster in a sandstorm",
	"slush-rush": "Attacks x1.5 faster in hail", "solar-power": "Special moves x1.5 in sun", "levitate": "Wild: flies over the path; immune to Ground moves",
	"flash-fire": "Wild: immune to Fire moves", "water-absorb": "Wild: immune to Water moves", "storm-drain": "Wild: immune to Water moves", "dry-skin": "Wild: immune to Water moves, takes x1.25 from Fire",
	"volt-absorb": "Wild: immune to Electric moves", "lightning-rod": "Wild: immune to Electric moves", "motor-drive": "Wild: immune to Electric moves",
	"sap-sipper": "Wild: immune to Grass moves", "wonder-guard": "Wild: only super-effective hits do damage", "sturdy": "Wild: survives one knockout hit at full HP",
	"thick-fat": "Wild: takes half from Fire and Ice", "heatproof": "Wild: takes half from Fire", "filter": "Wild: super-effective hits x0.75", "solid-rock": "Wild: super-effective hits x0.75",
	"prism-armor": "Wild: super-effective hits x0.75", "multiscale": "Wild: takes half damage at full HP", "shadow-shield": "Wild: takes half damage at full HP",
	"magic-guard": "Wild: no damage from burn, poison or traps", "insomnia": "Wild: can't fall asleep", "vital-spirit": "Wild: can't fall asleep",
	"limber": "Wild: can't be paralyzed", "immunity": "Wild: can't be poisoned", "water-veil": "Wild: can't be burned", "own-tempo": "Wild: can't be confused",
	"oblivious": "Wild: can't be confused", "magma-armor": "Wild: can't be frozen", "shield-dust": "Wild: added effects don't happen to it",
	"clear-body": "Wild: stats can't be lowered", "white-smoke": "Wild: stats can't be lowered", "full-metal-body": "Wild: stats can't be lowered",
	"battle-armor": "Wild: can't take critical hits", "shell-armor": "Wild: can't take critical hits", "quick-feet": "Wild: x1.5 speed while it has a status",
}
func ab_key(a) -> String: return DB.dex.abil[a].k if (a and DB.dex.abil.has(a)) else ""
func roll_ability(id: int, hid_chance: float) -> int:
	var l: Array = SP[id].get("ab", [])
	var nor := []; var hid := []
	for x in l:
		if x[1]: hid.append(x)
		else: nor.append(x)
	if hid.size() and randf() < hid_chance: return hid[0][0]
	if nor.size(): return nor[randi() % nor.size()][0]
	return l[0][0] if l.size() else 0
func ability_after_evolve(from: int, to: int, a: int) -> int:
	var fl: Array = SP[from].get("ab", []); var tl: Array = SP[to].get("ab", [])
	var i := -1
	for j in fl.size(): if fl[j][0] == a: i = j; break
	if i >= 0 and i < tl.size() and tl[i][1] == fl[i][1]: return tl[i][0]
	var want = fl[i][1] if i >= 0 else 0
	for x in tl: if x[1] == want: return x[0]
	return tl[0][0] if tl.size() else a

# ---------- held items (real items; what each does in Route Defense) ----------
const TYPE_ITEM := {"charcoal": 9, "mystic-water": 10, "miracle-seed": 11, "magnet": 12, "never-melt-ice": 14, "black-belt": 1, "poison-barb": 3, "soft-sand": 4, "sharp-beak": 2,
	"twisted-spoon": 13, "silver-powder": 6, "hard-stone": 5, "spell-tag": 7, "dragon-fang": 15, "black-glasses": 16, "metal-coat": 8, "silk-scarf": 0, "fairy-feather": 17}
var HELD_TD := {"choice-band": "Physical moves x1.5, but only its first move is used", "choice-specs": "Special moves x1.5, but only its first move is used",
	"choice-scarf": "Attacks x1.5 faster, but only its first move is used", "life-orb": "All damage x1.3", "expert-belt": "Super-effective hits x1.2",
	"scope-lens": "Critical hits more likely", "razor-claw": "Critical hits more likely", "wide-lens": "Accuracy x1.1", "zoom-lens": "Accuracy x1.2",
	"quick-claw": "Sometimes attacks again right away", "kings-rock": "10% chance to make the target flinch", "razor-fang": "10% chance to make the target flinch",
	"muscle-band": "Physical moves x1.1", "wise-glasses": "Special moves x1.1", "light-clay": "Its stat boosts and drops last twice as long",
	"binding-band": "Trapping moves do double damage over time", "lucky-egg": "Earns x1.5 XP", "amulet-coin": "Knockouts by it earn double ₽",
	"metronome": "Using the same move again and again: up to x2 damage"}
const HELD_RARE := ["choice-band", "choice-specs", "choice-scarf", "life-orb", "expert-belt"]
func _init() -> void:
	for k in TYPE_ITEM: HELD_TD[k] = "%s moves x1.2" % TYPES[TYPE_ITEM[k]]
func held_key(e) -> String: return DB.dex.held[e.it].k if (e and e.get("it", 0) and DB.dex.held.has(e.it)) else ""
func held_price(k: String) -> int: return 0 if HELD_RARE.has(k) else (8000 if (k == "lucky-egg" or k == "amulet-coin") else 3000)

# ---------- type quirks (your team only; a dual type gets both) ----------
const TQ := {
	0: ["Thrifty", "Costs 10% less to place"], 1: ["Boss hitter", "+20% damage to bosses"], 2: ["Far sight", "+15% range"],
	3: ["Toxic", "Hits stack poison (up to 5)"], 4: ["Tremor", "Hits may stun briefly"], 5: ["Crush", "First hit on each enemy deals +30%"],
	6: ["Swarm", "+5% attack speed for each other Bug placed"], 7: ["Phase", "Attacks go through Protect shields"], 8: ["Pierce", "Ignores Rock / Steel armour"],
	9: ["Scorch", "Hits may burn"], 10: ["Soak", "Hits slow enemies a little"], 11: ["Vines", "Enemies in its range move 10% slower"],
	12: ["Chain", "Hits jump to one more enemy for 30% damage"], 13: ["Foresight", "Reveals hidden Ghosts from 50% farther"], 14: ["Chill", "Hits slow enemies by 15%"],
	15: ["Fury", "Higher critical-hit chance"], 16: ["Finisher", "Finishes off enemies below 15% HP (not bosses)"], 17: ["Aura", "Teammates close by deal +5% damage"],
}
func quirks(id: int) -> Array:
	var out := []
	for x in SP[id].t: if TQ.has(x): out.append(TQ[x])
	return out
func place_cost(e: Dictionary) -> int:
	return int(round((40 + SP[e.id].bst * 0.25 + e.lv * 2.5) * (1 + mod("placeCost")) * (0.9 if SP[e.id].t.has(0) else 1.0)))

# ---------- Rescue Points tree: owned nodes add up into small permanent bonuses ----------
var MODS = null
func mods() -> Dictionary:
	if MODS != null: return MODS
	MODS = {}
	for n in DB.tree.nodes:
		if G and G.tree.has(n.id):
			for k in n.eff: MODS[k] = MODS.get(k, 0.0) + n.eff[k]
	return MODS
func mod(k: String) -> float: return mods().get(k, 0.0)
func node_open(n: Dictionary) -> bool:
	if G.tree.has(n.id): return false
	for r in n.req: if not G.tree.has(r): return false
	return true
func buy_node(n: Dictionary) -> bool:
	if not node_open(n) or G.rp < n.cost: return false
	G.rp -= n.cost; G.tree[n.id] = 1; MODS = null; save(); return true
func tree_spent() -> int:
	var s := 0
	for n in DB.tree.nodes: if G.tree.has(n.id): s += n.cost
	return s
func reset_cost() -> int: return tree_spent() * 100
func reset_tree() -> bool:
	var c := reset_cost()
	if G.money < c: return false
	G.money -= c; G.rp += tree_spent(); G.tree = {}; MODS = null; save(); return true
func rp_for_clear(tier: int) -> int: return 1 + int(floor(tier * 0.6))
func shop_price(p: float) -> int: return int(round(p * (1 + mod("shop"))))

# ---------- save (Godot's own format: keeps whole numbers and number keys) ----------
var G = null
const SAVE_PATH := "user://save.bin"
func new_save() -> Dictionary:
	return {"v": 2, "mt": {0: 1}, "box": [], "uid": 1, "money": 0, "rp": 0, "tree": {}, "stars": {}, "items": {}, "tools": {}, "held": {}, "tier": 1, "seen": {}, "own": {},
		"opts": {"mute": false, "fps60": true, "lowres": true, "gfx": 1, "ui": "m"}, "stats": {"maps": 0, "wins": 0}}
func save() -> void:
	if G == null: return
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return
	f.store_var(G); f.close()
	DirAccess.rename_absolute(tmp, SAVE_PATH)   # write then swap: a crash mid-save never leaves a broken save
func load_save():
	if not FileAccess.file_exists(SAVE_PATH): return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return null
	var g = f.get_var()
	if typeof(g) != TYPE_DICTIONARY or g.get("v", 0) < 2: return null
	for k in ["mt", "held", "tree", "stars", "tools", "items", "seen", "own", "opts", "stats"]:
		if not g.has(k): g[k] = {} if k != "mt" else {0: 1}
	if not g.has("rp"): g.rp = 0
	for e in g.box:
		if e.has("mega_from"): e.id = e.mega_from; e.ab = e.get("ab_from", e.get("ab", 0)); e.erase("mega_from"); e.erase("ab_from")   # a battle that never finished
		if not e.has("ab"): e.ab = roll_ability(e.id, 0.05)
		if not e.has("it"): e.it = 0
		if not e.get("nat", 0): e.nat = roll_nat()
		if not e.has("iv"): e.iv = roll_iv()
		if not e.has("ht"): e.ht = [0, 0, 0, 0, 0, 0]
		if not e.has("mint"): e.mint = 0
	return g
func make_mon(id: int, lv: int, nat := 0, iv = null) -> Dictionary:
	var e := {"u": G.uid, "id": id, "lv": lv, "xp": xp_for(SP[id].gr, lv), "mv": best_moves(id, lv), "pend": [], "ab": roll_ability(id, 0.05), "it": 0,
		"nat": nat if nat else roll_nat(), "iv": iv.duplicate() if iv != null else roll_iv(), "ht": [0, 0, 0, 0, 0, 0], "mint": 0, "fr": 70}
	G.uid += 1
	G.own[id] = 1; G.seen[id] = 1
	return e
func give_xp(e: Dictionary, amt: float) -> Array:   # returns list of events
	var ev := []
	if e.lv >= MAXLV: return ev
	e.xp += amt
	while e.lv < MAXLV and e.xp >= xp_for(SP[e.id].gr, e.lv + 1):
		e.lv += 1; ev.append("lv")
		for m in new_moves_at(e.id, e.lv):
			if e.mv.has(m) or e.pend.has(m): continue
			if e.mv.size() < 4: e.mv.append(m)
			else: e.pend.append(m)
	return ev
func evolve(e: Dictionary, to: int, item: int) -> void:
	if item:
		G.items[item] -= 1
		if not G.items[item]: G.items.erase(item)
	e.ab = ability_after_evolve(e.id, to, e.ab); e.id = to; G.own[to] = 1; G.seen[to] = 1
	for m in new_moves_at(to, 1) + new_moves_at(to, e.lv):
		if e.mv.has(m) or e.pend.has(m): continue
		if e.mv.size() < 4: e.mv.append(m)
		else: e.pend.append(m)

# ---------- per-map tiers: each map climbs from tier 1; clearing a map (any tier) opens the next one ----------
# friendship (the user's choice): 70 to start (a newly caught Pokémon in the main games), up to 255; it grows with every
# battle a Pokémon fights in (more for a win, a little for its knockouts). From 160 it lands more critical hits
# (+5%, up to +10% at 255); friendship evolutions use the main games' own thresholds.
func friend_crit(e: Dictionary) -> float:
	var fr: int = e.get("fr", 70)
	return 0.0 if fr < 160 else 0.05 + 0.05 * (fr - 160) / 95.0
# ---- forms you choose for a team member (Moves / Evolve screen): Rotom's appliances, Deoxys, Shaymin's Sky Forme,
# Arceus' Plates and Silvally's Memories (a type each). Kyurem fuses with a Reshiram (White) or Zekrom (Black) you own.
func form_family(id: int) -> Array:
	var b: int = int(SP.get(id, {}).get("base", id))
	var fam := {479: [10008, 10009, 10010, 10011, 10012], 386: [10001, 10002, 10003], 492: [10006]}
	var out := [b]
	if fam.has(b): out += fam[b]
	elif b == 493 or b == 773:
		for k in range(1, 18): if SP.has(VARIANT + b * 100 + k): out.append(VARIANT + b * 100 + k)
	return out.filter(func(x): return SP.has(x)) if out.size() > 1 else []
func set_form(e: Dictionary, to: int) -> void:
	e.ab = ability_after_evolve(e.id, to, e.ab); e.id = to; G.seen[to] = 1
const FUSE := {643: 10023, 644: 10022}   # Reshiram -> White Kyurem, Zekrom -> Black Kyurem
func fuse(e: Dictionary, partner: Dictionary) -> void:
	e.fused = partner; G.box.erase(partner); set_form(e, FUSE[partner.id])
func unfuse(e: Dictionary) -> void:
	if not e.has("fused"): return
	G.box.append(e.fused); e.erase("fused"); set_form(e, 646)
# ---- Empowerment (Mega Evolution for one battle): the Mega / Primal forms SpriteCollab animates
func megas_of(id: int) -> Array:
	var out := []
	for m in DB.dex.get("forms", []): if int(m.get("base", 0)) == id and m.get("form", "") == "mega" and m.anim: out.append(m.id)
	return out
func restore_forms() -> void:   # after a battle: Megas and night-time Land Shaymin go back to what they were
	if G == null: return
	for e in G.box:
		if e.has("mega_from"): e.id = e.mega_from; e.ab = e.get("ab_from", e.ab); e.erase("mega_from"); e.erase("ab_from")
const MAXTIER := 20
func map_tier(i: int) -> int: return G.mt.get(i, 0)              # highest tier you can pick on map i (0 = map not open)
func map_open(i: int) -> bool: return map_tier(i) > 0
func map_cleared(i: int) -> int: return max(0, map_tier(i) - 1)   # highest tier cleared on map i (20 when done)
func best_tier() -> int:
	var b := 0
	for k in G.mt: b = max(b, MAXTIER if G.get("mtDone", {}).get(k, 0) else G.mt[k] - 1)
	return b
func stars_of(i: int, t: int) -> int: return G.stars.get("%d:%d" % [i, t], 0)
# map difficulty, like Bloons TD 6: the 96 maps in opening order, in 4 groups
# name, colour, tiers added to every fight, reward multiplier, wild Pokémon per wave, tier to clear on any map of the group before to open this group
const MAPGROUP := [["Beginner", "#5fd068", 0, 1.0, 1.0, 0], ["Intermediate", "#ffd84a", 4, 1.1, 1.05, 5], ["Advanced", "#ff9a3c", 13, 1.2, 1.1, 10], ["Expert", "#ff5a5a", 27, 1.35, 1.15, 15]]
# ---- seasons (the user's choice): the game's own calendar, not the real one: the season moves on every 5 map wins.
# Each favours two fitting types in the waves (2x as often; winter: Ice), and winter puts falling snow over grass maps
# (PMD Red's hail screen, just the look: no weather effect).
const SEASONS := [["Spring", [11, 17]], ["Summer", [6, 9]], ["Autumn", [7, 4]], ["Winter", [14]]]
const SEASON_WINS := 5
func season() -> int: return int(G.stats.get("wins", 0) / SEASON_WINS) % 4 if G != null else 0
func season_left() -> int: return SEASON_WINS - int(G.stats.get("wins", 0)) % SEASON_WINS if G != null else SEASON_WINS
var NMAPS := 0
func map_group(i: int) -> int: return min(3, int(floor(i * 4.0 / NMAPS)))
# ---- special maps (Expert difficulty): the Ultra Wormhole (Ultra Beasts, Necrozma / Guzzlord; Explorers of Sky's Spacial
# Rift) opens with the Advanced maps, the Paradox Portal (paradox Pokémon, Koraidon; Deep Spacial Rift) with the Expert maps
const SPECIAL := {"wormhole": {"group": 2, "pool": [793, 794, 795, 796, 797, 798, 803, 804, 805, 806], "boss": [800, 799],
		"note": "A rift to Ultra Space: Ultra Beasts pour through, and Necrozma or Guzzlord waits at the end."},
	"paradox": {"group": 3, "pool": [984, 985, 987, 988, 989, 991, 992, 994, 995, 1005, 1006, 1009, 1010], "boss": [1007],
		"note": "A portal to Area Zero: paradox Pokémon from the past and the future, and Koraidon at the end."}}
func special_of(i: int) -> String: return str(DB.ts[i].get("special", "")) if i >= 0 and i < DB.ts.size() else ""
func check_specials() -> String:   # opens special maps whose gate is met; returns the name of one just opened
	var got := ""
	for i in range(NMAPS, DB.ts.size()):
		var sp: Dictionary = SPECIAL.get(special_of(i), {})
		if sp.size() and not map_open(i) and map_open(group_start(sp.group)): G.mt[i] = 1; got = DB.ts[i].name
	return got
# ---- legendary maps: the dungeons where the PMD games have you meet a legendary. After clearing tier 5 on one, its
# Legendary challenge sends that legendary as the boss every time (stronger, and likelier to join)
const LEGEND_HOME := {"Mt Thunder": [145], "Mt Thunder Peak": [145], "Mt Blaze": [146], "Mt Freeze": [144], "Magma Cavern": [383],
	"Sky Tower": [384], "Silver Trench": [249], "Meteor Cave": [386], "Fiery Field": [244], "Lightning Field": [243],
	"Northwind Field": [245], "Mt Faraway": [250], "Western Cave": [150], "Wish Cave": [385], "Buried Relic": [377, 378, 379],
	"Temporal Tower": [483], "Giant Volcano": [485], "Dark Crater": [491]}
func legends_of(i: int) -> Array:
	if i >= NMAPS: return []
	var nm: String = DB.ts[i].name
	var b := nm.get_slice(" 1", 0).get_slice(" 2", 0).get_slice(" 3", 0).get_slice(" 4", 0).get_slice(" 5", 0).get_slice(" 6", 0).get_slice(" 7", 0).get_slice(" 8", 0).get_slice(" 9", 0)
	return LEGEND_HOME.get(b, LEGEND_HOME.get(nm, [])).filter(func(x): return SP.has(x) and SP[x].anim)
# how hard a fight is, on the old one-group tier scale (one long climb over all 4 groups)
func threat_tier(i: int, t: float) -> float: return 1 + (t + MAPGROUP[map_group(i)][2] - 1) * 2.05 / 4.2
func group_start(g: int) -> int:
	for i in NMAPS: if map_group(i) == g: return i
	return -1
func group_gate(g: int) -> int: return MAPGROUP[g][5]
