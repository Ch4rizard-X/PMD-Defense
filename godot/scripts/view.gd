extends Node2D
# Route Defense - battle drawing (ported from the HTML version's drawBattle and friends).
# Draws in map pixels (24 per tile); the parent decides where the map sits on screen and how big.
# Two child layers: Flash (white hit silhouettes, needs a shader) and Sky (weather, needs additive blending).

const TZ := 24
var SPR: float = BT.SPR; var FXS: float = BT.FXS; var ESPR: float = BT.ESPR
const MKS := ["small", "medium", "large"]
const STS_COL := {"paralysis": Color("#ff0"), "sleep": Color("#aaf"), "freeze": Color("#8ff"), "burn": Color("#f60"), "poison": Color("#c4f"), "confusion": Color("#f8c"), "trap": Color("#a84"), "yawn": Color("#ccc"), "leech-seed": Color("#6c3")}
# the ROM draws every projectile in one orientation; these have a clear front, so they're turned to face where they fly
# value = which way the front points in the sheet (radians; 0 = right, PI/2 = down)
var PROJ_FRONT := {"efob013/anim48": PI / 2, "efob136/anim16": PI / 2, "efob136/anim24": PI / 2, "efob062/anim00": PI / 2,
	"efob052/anim00": PI / 2, "efob118/anim00": PI / 2, "efob013/anim32": PI / 2, "efob013/anim08": 0.0,
	"efob069/anim00": PI / 2, "efob127/anim00": PI / 2, "efob013/anim16": -PI / 2}   # Megahorn and Icicle Spear lead with their point
var flash: Node2D; var sky: Node2D; var glitch: Node2D; var dark: Node2D; var lights: Node2D
var font: Font

func _ready() -> void:
	for k in PROJ_FRONT.keys(): PROJ_FRONT["eos" + k.substr(4)] = PROJ_FRONT[k]
	font = load("res://fonts/pmd.ttf") if ResourceLoader.exists("res://fonts/pmd.ttf") else ThemeDB.fallback_font
	flash = Node2D.new(); flash.name = "Flash"
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec4 c = texture(TEXTURE, UV); COLOR = vec4(1.0, 1.0, 1.0, c.a * COLOR.a); }"
	var mat := ShaderMaterial.new(); mat.shader = sh; flash.material = mat
	flash.draw.connect(_draw_flash); add_child(flash)
	# ---- night lights (the user's choice): the night is a darkness layer (multiplied over the map and sprites) with holes
	# of light around your team and around Pokémon that glow in their games; on top, glows: those light sources' coloured
	# halos, an aura on wild Ghost / Dark types at night, and shinies (gold) and Alphas (red) at any time
	dark = Node2D.new(); dark.name = "Dark"
	var dsh := Shader.new()
	dsh.code = """shader_type canvas_item;
render_mode blend_mul;
uniform vec4 L[48];
uniform int n = 0;
uniform vec3 tint = vec3(0.3, 0.36, 0.66);
varying vec2 wp;
void vertex(){ wp = VERTEX; }
void fragment(){
	float l = 0.0;
	for (int i = 0; i < 48; i++) {
		if (i >= n) break;
		float d = distance(wp, L[i].xy);
		l = max(l, (1.0 - smoothstep(L[i].z * 0.35, L[i].z, d)) * L[i].w);
	}
	COLOR = vec4(mix(tint, vec3(1.0), l), 1.0);
}"""
	var dm := ShaderMaterial.new(); dm.shader = dsh; dark.material = dm
	dark.draw.connect(func():
		if BT.B and BT.B.get("night", false): dark.draw_rect(Rect2(0, 0, BT.B.M.W * TZ, BT.B.M.H * TZ), Color.WHITE))
	add_child(dark)
	lights = Node2D.new(); lights.name = "Lights"
	var lm := CanvasItemMaterial.new(); lm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD; lights.material = lm
	var gt := GradientTexture2D.new(); gt.fill = GradientTexture2D.FILL_RADIAL; gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5); gt.width = 64; gt.height = 64
	var gr := Gradient.new(); gr.set_color(0, Color(1, 1, 1, 1)); gr.set_color(1, Color(1, 1, 1, 0)); gt.gradient = gr; _glow_tex = gt
	lights.draw.connect(_draw_lights); add_child(lights)
	sky = Node2D.new(); sky.name = "Sky"; sky.draw.connect(_draw_sky); add_child(sky)
	# Ultra Wormhole (the user's choice): the map glitches - bands of it jump sideways in bursts, red / blue edges drift
	# apart and back, and its colours slowly cycle. Drawn behind everything else, on the map only.
	glitch = Node2D.new(); glitch.name = "Glitch"; glitch.show_behind_parent = true; glitch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var gs := Shader.new()
	gs.code = """shader_type canvas_item;
float h(float x){ return fract(sin(x * 12.9898) * 43758.5453); }
void fragment(){
	vec2 uv = UV;
	float tick = floor(TIME * 8.0);
	float burst = step(0.75, h(floor(TIME * 3.0) + 0.37));                 // short bursts a few times a few seconds
	float band = floor(uv.y * 36.0);
	float r = h(band * 7.31 + tick * 1.7);
	uv.x += burst * step(0.7, r) * (r - 0.85) * 0.3;                     // slice jitter
	float sp = (0.0015 + 0.0025 * (0.5 + 0.5 * sin(TIME * 1.7))) * (1.0 + burst * 2.0);   // colour split
	vec4 c = texture(TEXTURE, uv);
	vec3 col = vec3(texture(TEXTURE, uv + vec2(sp, 0.0)).r, c.g, texture(TEXTURE, uv - vec2(sp, 0.0)).b);
	float a = TIME * 0.35;                                                  // colour cycling (hue turn)
	vec3 k = vec3(0.57735);
	col = col * cos(a) + cross(k, col) * sin(a) + k * dot(k, col) * (1.0 - cos(a));
	COLOR = vec4(col, c.a);
}"""
	var gm := ShaderMaterial.new(); gm.shader = gs; glitch.material = gm
	glitch.draw.connect(func():
		if BT.B and C.special_of(BT.B.set) == "wormhole": glitch.draw_texture(BT.B.M.tex, Vector2.ZERO))
	add_child(glitch)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_dt: float) -> void:
	if BT.B:
		queue_redraw(); flash.queue_redraw(); sky.queue_redraw(); glitch.queue_redraw(); lights.queue_redraw()
		if BT.B.get("night", false): _set_night_lights(); dark.queue_redraw()

# Pokémon that glow in their own games (their Pokédex entries: Chinchou / Lanturn's lights, Volbeat's tail, Ampharos'
# tail, Finneon / Lumineon's patterns, Litwick's line's flames, Morelull / Shiinotic's spores) plus every Fire type
const GLOWERS := {170: Color(1, 0.95, 0.5), 171: Color(1, 0.95, 0.5), 313: Color(0.85, 1, 0.45), 181: Color(1, 0.75, 0.35),
	456: Color(0.5, 0.85, 1), 457: Color(0.6, 0.8, 1), 607: Color(0.75, 0.55, 1), 608: Color(0.75, 0.55, 1), 609: Color(0.75, 0.55, 1),
	755: Color(0.6, 1, 0.75), 756: Color(0.6, 1, 0.75)}
const FIRE_GLOW := Color(1, 0.6, 0.25)
var _glow_tex: Texture2D
func _glow_col(id: int):
	if GLOWERS.has(id): return GLOWERS[id]
	if GLOWERS.has(int(C.SP.get(id, {}).get("base", 0))): return GLOWERS[int(C.SP[id].base)]
	return FIRE_GLOW if C.SP.get(id, {}).get("t", []).has(9) else null
func _set_night_lights() -> void:   # light holes in the darkness: x, y, radius, strength
	var B = BT.B; var L := []
	for t in B.towers:
		L.append(Vector4(t.x, t.y, 34 * SPR, 0.75))
		if _glow_col(t.e.id) != null: L.append(Vector4(t.x, t.y, 56 * SPR, 0.95))
	for e in B.en:
		if e.hp > 0 and not e.get("under", false) and _glow_col(e.id) != null: L.append(Vector4(e.x, e.y - _lift(e), 36 * ESPR, 0.85))
	L = L.slice(0, 48)
	dark.material.set_shader_parameter("n", L.size())
	while L.size() < 48: L.append(Vector4.ZERO)
	dark.material.set_shader_parameter("L", L)
func _halo(x: float, y: float, r: float, c: Color) -> void:
	draw_texture_rect_to(lights, x, y, r, c)
func draw_texture_rect_to(ci: CanvasItem, x: float, y: float, r: float, c: Color) -> void:
	ci.draw_texture_rect(_glow_tex, Rect2(x - r, y - r, r * 2, r * 2), false, c)
func _draw_lights() -> void:
	var B = BT.B
	if B == null: return
	var night: bool = B.get("night", false); var p := 0.5 + 0.5 * sin(B.time * 3)
	if night:
		for t in B.towers:
			var gc = _glow_col(t.e.id)
			if gc != null: _halo(t.x, t.y - 8 * SPR, 30 * SPR, Color(gc.r, gc.g, gc.b, 0.22 + 0.08 * p))
	for e in B.en:
		if e.hp <= 0 or e.get("under", false) or (e.get("hide", false) and e.get("rev", 0.0) <= 0): continue
		var y: float = e.y - _lift(e) - 8 * ESPR
		if night:
			var gc = _glow_col(e.id)
			if gc != null: _halo(e.x, y, 24 * ESPR, Color(gc.r, gc.g, gc.b, 0.22 + 0.08 * p))
			var sp: Dictionary = C.SP.get(e.id, {})
			if sp.get("t", []).has(7) or sp.get("t", []).has(16):   # Ghost / Dark aura at night
				var q := 0.5 + 0.5 * sin(B.time * 4 + e.ph)
				_halo(e.x, y, 22 * ESPR, Color(0.55, 0.2, 0.85, 0.22 + 0.16 * q) if sp.t.has(7) else Color(0.8, 0.15, 0.25, 0.2 + 0.16 * q))
		if e.get("shiny", false): _halo(e.x, y, 20 * ESPR, Color(1, 0.9, 0.45, 0.16 + 0.1 * (0.5 + 0.5 * sin(B.time * 5 + e.ph))))
		if e.get("alpha", false): _halo(e.x, y, 30 * ESPR, Color(1, 0.2, 0.15, 0.22 + 0.1 * p))
# ---------- pieces ----------
func anim_frame(a: Dictionary, t: float, loop := true) -> int:
	var tot := BT.fx_len(a) * 60.0; var ft := int(floor(t * 60))
	ft = (min(ft, int(tot) - 1) if not loop else ft % max(1, int(tot)))
	var f := 0
	while f < a.n - 1 and ft >= a.d[f]: ft -= a.d[f]; f += 1
	return f
func mon_anim(id: int, name: String):
	var A = C.anim_of(id)
	if A == null: return null
	return A.get(name, A.get("Idle", A.get("Walk", null)))
func draw_mon(ci: CanvasItem, id: int, name: String, t: float, row: int, x: float, y: float, alpha := 1.0, loop := true, sc := -1.0) -> void:
	if sc < 0: sc = SPR
	var a = mon_anim(id, name)
	if a == null: return
	var im := C.mon_tex(id)
	if im == null: return
	var f := anim_frame(a, t, loop); var r: int = row if a.r > 1 else 0
	var gp: Array = a.sh[min(r, a.sh.size() - 1)] if a.has("sh") else [a.fw / 2.0, a.fh / 2.0 + 4]   # the sheet's own ground point lands on (x, y)
	ci.draw_texture_rect_region(im, Rect2(round(x - gp[0] * sc), round(y - gp[1] * sc), a.fw * sc, a.fh * sc), Rect2(f * a.fw, a.y + r * a.fh, a.fw, a.fh), Color(1, 1, 1, alpha))
func draw_fx_anim(ci: CanvasItem, a, t: float, row: int, x: float, y: float, rot := 0.0, alpha := 1.0) -> void:
	if a == null: return
	var im := C.tex("img/fx/%s.png" % a.f)
	if im == null: return
	var ft: int = int(floor(t * 60)) % max(1, int(BT.fx_len(a) * 60)); var f := 0
	while f < a.n - 1 and ft >= a.d[f]: ft -= a.d[f]; f += 1
	var ax: float = (a.ox if a.has("ox") else a.fw / 2.0) * FXS; var ay: float = (a.oy if a.has("oy") else a.fh / 2.0) * FXS   # Explorers of Sky sheets carry their anchor point; Red's are centred
	if rot != 0.0:
		ci.draw_set_transform(Vector2(round(x), round(y)), rot, Vector2.ONE)
		ci.draw_texture_rect_region(im, Rect2(-ax, -ay, a.fw * FXS, a.fh * FXS), Rect2(f * a.fw, 0, a.fw, a.fh), Color(1, 1, 1, alpha))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE); return
	var rr: int = row if a.get("r", 1) > 1 else 0
	ci.draw_texture_rect_region(im, Rect2(round(x - ax), round(y - ay), a.fw * FXS, a.fh * FXS), Rect2(f * a.fw, rr * a.fh, a.fw, a.fh), Color(1, 1, 1, alpha))
func draw_digits(txt: String, x: float, y: float, kind: int, sc := 1.0, alpha := 1.0) -> void:
	var im := C.tex("img/dmg_b.png" if kind == 3 else "img/dmg_r.png")
	var col := Color(1, 1, 1, alpha)
	if txt == "MISS" and im: draw_texture_rect_region(im, Rect2(round(x - 16 * sc), round(y), 32 * sc, 8 * sc), Rect2(12 * 8, 0, 32, 8), col); return
	if txt.is_valid_int() and im:
		var w := txt.length() * 7 * sc
		for i in txt.length(): draw_texture_rect_region(im, Rect2(round(x - w / 2 + i * 7 * sc), round(y), 8 * sc, 8 * sc), Rect2(int(txt[i]) * 8, 0, 8, 8), col)
		return
	var fs := 11
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(x - tw / 2 + 1, y + 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, alpha))
	var c := Color("#ffe040") if kind == 2 else (Color("#ffa0c0") if kind == 4 else Color("#8ff")); c.a = alpha
	draw_string(font, Vector2(x - tw / 2, y + 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
func marker(team: bool, id: int, x: float, y: float, sc: float, alpha := 1.0) -> void:   # PMD Red's own markers: yellow ring under your team, dark shadow under wild Pokémon
	var sz: int = C.DB.mk.get(id, 1); var im := C.tex("img/ui/%s%s.png" % ["team_" if team else "enemy_", MKS[sz]])
	if im == null:
		draw_set_transform(Vector2(x, y), 0, Vector2(1, 0.42))
		draw_circle(Vector2.ZERO, (12 if sz == 2 else 8) * sc, Color(0, 0, 0, .28 * alpha))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE); return
	var w := im.get_width() * sc; var h := im.get_height() * sc
	draw_texture_rect(im, Rect2(round(x - w / 2), round(y - h / 2), w, h), false, Color(1, 1, 1, alpha))
func ring(x: float, y: float, r: float, ok: bool) -> void:   # range ring for the selected / ghost tower
	# soft fill toward the edge (the HTML's radial gradient, as a few bands)
	for i in 6:
		var k := (i + 1) / 6.0
		var c := Color(160 / 255.0, 210 / 255.0, 1, 0.22 / 6) if ok else Color(1, 40 / 255.0, 40 / 255.0, 0.3 / 6)
		if i >= 2: draw_circle(Vector2(x, y), r * (0.2 + 0.8 * k), c)
	# dashed, slowly turning outline
	var n := int(max(16, r * 2 * PI / 11)); var off := fmod(BT.B.time * 14 / r, TAU / n * 2)
	var col := Color(1, 1, 1, .75) if ok else Color(1, 80 / 255.0, 80 / 255.0, .8)
	for i in n:
		if i % 2: continue
		var a0 := i * TAU / n + off
		draw_arc(Vector2(x, y), r, a0, a0 + TAU / n * 6 / 11.0 * 2, 6, col, 1.5)
func draw_gates(M: Dictionary) -> void:   # where wild Pokémon come in (green) and where they escape (red, pulsing)
	var W: float = M.W * TZ; var H: float = M.H * TZ; var p := 0.5 + 0.5 * sin(BT.B.time * 4); var seen := {}
	var gate := func(pt: Vector2, dv: Vector2, col: Color) -> void:
		var x := clampf(pt.x, 10, W - 10); var y := clampf(pt.y, 10, H - 10); var k := "%d,%d" % [x, y]
		if seen.has(k): return
		seen[k] = 1
		for i in 8:   # glow: radial falloff
			var rr := 30.0 * (1 - i / 8.0); var c := col; c.a = (0.45 + 0.25 * p) * (i + 1) / 8.0 * 0.25
			draw_circle(Vector2(x, y), rr, c)
		draw_set_transform(Vector2(x, y), atan2(dv.y, dv.x), Vector2.ONE)
		var c2 := col; c2.a = 0.85
		for i in 2:
			var o := fmod(BT.B.time * 18 + i * 9, 18.0) - 9
			draw_colored_polygon(PackedVector2Array([Vector2(o - 4, -6), Vector2(o + 4, 0), Vector2(o - 4, 6), Vector2(o - 1, 0)]), c2)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for r in M.routes:
		var l: Array = r.line
		gate.call(l[0], l[1] - l[0], Color(90 / 255.0, 230 / 255.0, 120 / 255.0))
		gate.call(l[-1], l[-1] - l[-2], Color(1, 70 / 255.0, 70 / 255.0))
func ko_burst(x: float, y: float, k: float, big: bool) -> void:   # knockout: a quick ring and sparks
	var R := (26.0 if big else 14.0) * (0.4 + k); var a := 1 - k
	if a <= 0: return
	draw_arc(Vector2(x, y), R, 0, TAU, 24, Color(1, 1, 1, a * 0.8), 2 * (1 - k) + 0.5)
	for i in 8:
		var an := i * PI / 4 + 0.4
		draw_rect(Rect2(x + cos(an) * R * 1.25 - 1.5, y + sin(an) * R * 1.25 - 1.5, 3, 3), Color(1, 230 / 255.0, 128 / 255.0, a * 0.8))
func draw_skills() -> void:   # traps and decoys, drawn with each move's own effect graphics
	for tr in BT.B.traps:
		var f = C.DB.fx.moves.get(tr.m, null)
		if f: draw_fx_anim(self, C.DB.fx.anims.get(f.get("h", f.get("u", "")), null), fmod(BT.B.time, 1.2), 0, tr.x, tr.y, 0.0, 0.85)
	for dc in BT.B.decoys:
		var f = C.DB.fx.moves.get(dc.m, null)
		if f: draw_fx_anim(self, C.DB.fx.anims.get(f.get("u", f.get("h", "")), null), fmod(BT.B.time, 1.0), 0, dc.x, dc.y - 6)

# ---------- the battle ----------
func _draw() -> void:
	var B = BT.B
	if B == null: return
	var M: Dictionary = B.M
	if C.special_of(B.set) != "wormhole": draw_texture(M.tex, Vector2.ZERO)   # the wormhole's map is drawn glitched by the Glitch child
	if B.get("snowlook", false):   # winter: a light dusting of snow on the land and path (water / lava stay clear)
		if _snow == null or _snow_for != M: _snow = _make_snow(M); _snow_for = M
		draw_texture_rect(_snow, Rect2(0, 0, M.W * TZ, M.H * TZ), false)
	draw_gates(M)
	if B.sel: ring(B.sel.x, B.sel.y, BT.max_range(B.sel), true)
	if B.ghost and B.placing:
		var r := 40.0
		for m in B.placing.mv: if C.move_use(m) != null: r = max(r, BT.RANGE[C.mv(m).c] * (1 + min(0.25, B.placing.lv / 400.0)))
		ring(B.ghost.x, B.ghost.y, r, B.ghost.ok)
	draw_skills()   # traps and decoys under the Pokémon
	var ents := []
	for t in B.towers: ents.append([t.y, 0, t])
	for e in B.en: ents.append([e.y, 1, e])
	ents.sort_custom(func(a, b): return a[0] < b[0])
	for it in ents:
		if it[1] == 0: _draw_tower(it[2])
		else: _draw_enemy(it[2])
	if B.ghost and B.placing:
		marker(true, B.placing.id, B.ghost.x, B.ghost.y, SPR)
		draw_mon(self, C.sid(B.placing), "Idle", B.time, 0, B.ghost.x, B.ghost.y, 0.8 if B.ghost.ok else 0.4)
	for z in B.zap:   # Electric: Chain - a short zigzag between the two enemies
		var pts := PackedVector2Array([Vector2(z.a.x, z.a.y - 8 * ESPR)])
		for i in range(1, 5):
			var k := i / 5.0
			pts.append(Vector2(z.a.x + (z.b.x - z.a.x) * k + (randf() - 0.5) * 10, z.a.y + (z.b.y - z.a.y) * k - 8 * ESPR + (randf() - 0.5) * 10))
		pts.append(Vector2(z.b.x, z.b.y - 8 * ESPR))
		draw_polyline(pts, Color(1, 240 / 255.0, 120 / 255.0, min(1, z.t / 0.1)), 2)
	for p in B.proj:
		var a = C.DB.fx.anims.get(p.fx, null)
		draw_fx_anim(self, a, p.at, p.row, p.x, p.y, p.ang - PROJ_FRONT[p.fx] if PROJ_FRONT.has(p.fx) else 0.0)
	for f in B.fx: draw_fx_anim(self, f.a, f.t, f.row, f.x, f.y, f.rot)
	for f in B.fl:
		var pop: float = 1 + max(0, 0.12 - f.t) * 5; var a: float = 1 - (f.t - 0.65) / 0.25 if f.t > 0.65 else 1.0
		draw_digits(f.txt, f.x, f.y - f.t * 22, f.kind, 1.35 * pop, clampf(a, 0, 1))
func _draw_tower(t: Dictionary) -> void:
	var B = BT.B
	if B.sel != null and is_same(B.sel, t):
		var p := 0.5 + 0.5 * sin(B.time * 6)
		draw_set_transform(Vector2(t.x, t.y), 0, Vector2(1, 6.0 / 15.0))
		draw_arc(Vector2.ZERO, 15 * SPR, 0, TAU, 32, Color(1, 216 / 255.0, 74 / 255.0, 0.5 + 0.5 * p), 2 * 15.0 / 6.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	marker(true, t.e.id, t.x, t.y, SPR)
	draw_mon(self, C.sid(t.e), t.anim, t.at, t.dir, t.x, t.y, 1.0, t.anim == "Idle")
	if t.buft > 0: draw_rect(Rect2(t.x - 2, t.y - 30 * SPR, 4, 4), Color("#f84"))
func _lift(e: Dictionary) -> float: return (12 + sin(BT.B.time * 3 + e.ph) * 2.5 if e.air else 0.0) * ESPR
func _enemy_anim(e: Dictionary) -> Array:
	var A = C.anim_of(C.sid(e))
	if A == null: A = {}
	var walk := "Hover" if (e.air and A.has("Hover")) else "Walk"   # flyers use their Hover animation when the sheet has one
	var an := "Hurt" if (e.hp <= 0 or e.hurt > 0) else ("Idle" if (e.stop > 0 and e.sts != null) else walk)
	var at: float = e.at * BT.HOVER_SPEED if an == "Hover" else e.at   # flight loops are short: played a bit slower so flapping isn't frantic
	return [an, at]
func _draw_enemy(e: Dictionary) -> void:
	var B = BT.B
	if e.d <= 0: return
	var al := clampf(e.dead / 0.5, 0, 1) if e.hp <= 0 else 1.0
	if e.hide and not (e.rev > 0): al *= 0.28
	if e.under: al *= 0.12
	var lift := _lift(e)
	marker(false, e.id, e.x, e.y, ESPR * (1.3 if e.boss else 1.0), al)
	var aa := _enemy_anim(e)
	draw_mon(self, C.sid(e), aa[0], aa[1], e.dir, e.x, e.y - lift, al, true, ESPR * (1.5 if e.get("alpha", false) else 1.0))
	if e.hp <= 0: ko_burst(e.x, e.y - 10 * ESPR, 1 - clampf(e.dead / 0.5, 0, 1), e.boss)
	if e.hp > 0 and (e.under or (e.hide and not (e.rev > 0))): return
	if e.hp > 0 and e.sh > 0:
		draw_circle(Vector2(e.x, e.y - 10 * ESPR - lift), (22 if e.boss else 15) * ESPR, Color(120 / 255.0, 220 / 255.0, 120 / 255.0, .18))
		draw_arc(Vector2(e.x, e.y - 10 * ESPR - lift), (22 if e.boss else 15) * ESPR, 0, TAU, 32, Color(160 / 255.0, 1, 160 / 255.0, .75), 1.5)
	if e.hp > 0 and (e.hp < e.max or e.boss or e.sh > 0 or (B.get("selE") != null and is_same(B.selE, e))):   # bars only once hurt (cleaner map); bosses always
		var w := 30.0 if e.boss else 18.0; var f: float = e.hp / float(e.max)
		e.hpd = f if not e.has("hpd") else max(f, e.hpd - 0.02)
		draw_rect(Rect2(e.x - w / 2 - 1, e.y + 5, w + 2, 5), Color(0, 0, 0, .75))
		draw_rect(Rect2(e.x - w / 2, e.y + 6, w * e.hpd, 3), Color(1, 1, 1, .55))   # recent damage trails behind
		draw_rect(Rect2(e.x - w / 2, e.y + 6, w * f, 3), Color("#46d846") if f > 0.5 else (Color("#ffcc33") if f > 0.2 else Color("#ff4040")))
		draw_rect(Rect2(e.x - w / 2, e.y + 6, w * f, 1), Color(1, 1, 1, .35))
		if e.sh > 0: draw_rect(Rect2(e.x - w / 2, e.y + 4, w * e.sh / float(e.shm), 1), Color("#9f9"))
		if e.sts != null: draw_rect(Rect2(e.x + w / 2 + 2, e.y + 6, 4, 4), STS_COL.get(e.sts, Color.WHITE))

# white hit flashes (shader layer): the enemy's current frame as a white silhouette
func _draw_flash() -> void:
	var B = BT.B
	if B == null: return
	for e in B.en:
		if e.hurt > 0.12 and e.hp > 0 and e.d > 0:
			var aa := _enemy_anim(e)
			draw_mon(flash, C.sid(e), aa[0], aa[1], e.dir, e.x, e.y - _lift(e), clampf((e.hurt - 0.12) * 5, 0, 0.85), true, ESPR * (1.5 if e.get("alpha", false) else 1.0))

# ---------- weather: PMD Red's own weather screens (rain, sandstorm, hail) tiled over the map; sun has none in the ROM ----------
var _sky_mat_add: CanvasItemMaterial
func _draw_sky() -> void:
	var B = BT.B
	if B == null or (B.weather == null and not B.get("snowlook", false)): return
	var M: Dictionary = B.M; var k: String = B.weather.k if B.weather != null else "hail"; var w = C.DB.wx.get(k, null)   # no weather: winter's falling snow (just the look)
	var W: float = M.W * TZ; var H: float = M.H * TZ
	if _sky_mat_add == null: _sky_mat_add = CanvasItemMaterial.new(); _sky_mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	if k == "sun":
		sky.material = _sky_mat_add
		sky.draw_rect(Rect2(0, 0, W, H), Color(1, 170 / 255.0, 40 / 255.0, .06))
		_sun_rays(W, H); return
	var im := C.tex("img/wx/%s.png" % k)
	if w == null or im == null: sky.material = null; sky.draw_rect(Rect2(0, 0, W, H), BT.WEATHER[k][2]); return
	var f := int(floor(B.time * 1000 / w.ms)) % int(w.n); var sx: int = (f % int(w.per)) * w.fw; var sy: int = (f / int(w.per)) * w.fh
	var add: bool = w.get("blend", "") == "lighter"
	sky.material = _sky_mat_add if add else null
	if not add and (k == "rain" or k == "hail"): sky.draw_rect(Rect2(0, 0, W, H), Color(15 / 255.0, 25 / 255.0, 60 / 255.0, .22) if k == "rain" else Color(30 / 255.0, 45 / 255.0, 75 / 255.0, .16))   # overcast, so the falling streaks stand out
	var y := 0.0
	while y < H:
		var x := 0.0
		while x < W:
			sky.draw_texture_rect_region(im, Rect2(x, y, w.fw, w.fh), Rect2(sx, sy, w.fw, w.fh), Color(1, 1, 1, 1.0 if add else 0.4))
			x += w.fw
		y += w.fh
# sunlight: soft diagonal shafts of warm light that drift and shimmer across the map (drawn, not from the ROM: PMD Red has no sunlight screen)
var _ray: ImageTexture
func _ray_tex() -> ImageTexture:
	if _ray: return _ray
	var im := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	for yy in 256:
		var v := 1.0 - 0.3 * clampf(yy / 179.0, 0, 1) if yy < 179 else 0.7 * (1 - (yy - 179) / 77.0)
		for xx in 64:
			var u := absf(xx - 31.5) / 32.0
			var h := 1.0 - u / 0.3 * 0.15 if u < 0.3 else 0.85 * (1 - (u - 0.3) / 0.7)
			im.set_pixel(xx, yy, Color(1, 0.96, 0.84, clampf(h * v, 0, 1)))
	_ray = ImageTexture.create_from_image(im); return _ray
func _sun_rays(W: float, H: float) -> void:
	var tex := _ray_tex(); var ang := 0.42; var lenr := H / cos(ang) * 1.15; var T: float = BT.B.time; var n := 7
	for i in 6:   # the sun sits off the top-left corner, where the rays come from
		sky.draw_circle(Vector2.ZERO, max(W, H) * 0.7 * (1 - i / 6.0), Color(1, 220 / 255.0, 140 / 255.0, .22 / 6))
	for i in n:
		var base := (i + 0.5) / n; var x := (-0.25 + base * 1.15) * W + sin(T * 0.11 + i * 1.7) * W * 0.03   # slow drift
		var w := W * (0.035 + 0.05 * fmod(i * 0.618, 1.0)) * (1 + 0.15 * sin(T * 0.3 + i))
		var al := 0.3 + 0.18 * (0.5 + 0.5 * sin(T * 0.6 + i * 2.3))   # shimmer
		sky.draw_set_transform(Vector2(x, -H * 0.05), -ang, Vector2.ONE)
		sky.draw_texture_rect(tex, Rect2(-w / 2, 0, w, lenr), false, Color(1, 1, 1, al * 0.6))
		sky.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
# ---- winter snow on the tiles: made once per map on a 3-pixel grid (pixel-art sized), drawn over the map tiles
var _snow: ImageTexture = null; var _snow_for = null
func _make_snow(M: Dictionary) -> ImageTexture:
	const G3 := 3
	var w: int = int(M.W * TZ / G3); var h: int = int(M.H * TZ / G3)
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new(); rng.seed = int(M.seed) ^ 0x5A0B
	for y in h:
		for x in w:
			var tv: int = M.t[mini(int(y * G3 / TZ), M.H - 1)][mini(int(x * G3 / TZ), M.W - 1)]
			if tv == 2: continue
			var a := 0.16 if tv == 0 else 0.08                         # frost wash: land a little more than the path
			var r := rng.randf()
			if r < (0.10 if tv == 0 else 0.04): a = 0.75                # snow specks
			elif r < (0.16 if tv == 0 else 0.06): a = 0.4
			im.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(im)
	return tex