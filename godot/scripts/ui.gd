extends Control
# Route Defense - screens: title, starter, hub (routes / box / rescue / dex / shop / bag), team, results.
# Ported from the HTML version's ui.js. The battle screen is in hud.gd.

const STARTERS := [1, 4, 7, 152, 155, 158, 252, 255, 258, 387, 390, 393, 495, 498, 501, 650, 653, 656, 722, 725, 728, 810, 813, 816, 906, 909, 912, 25, 133]
const UPD := "https://raw.githubusercontent.com/Ch4rizard-X/PMD-Defense/main/godot/"
var screen := ""; var hub := "routes"; var route = null; var team: Array = []; var gen := 1; var rbr = null
var scr: Control            # the current screen
var hud = null              # the battle screen (hud.gd) while in battle
var G: Dictionary:
	get: return C.G

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT); theme = K.theme
	K.root = self
	if C.G == null: C.G = C.new_save()
	K.toasts = VBoxContainer.new(); K.toasts.set_anchors_preset(Control.PRESET_CENTER_TOP); K.toasts.anchor_left = 0.5; K.toasts.anchor_right = 0.5
	K.toasts.offset_top = 60; K.toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH; K.toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE; K.toasts.z_index = 50
	apply_ui_size()
	show_title()
	add_child(K.toasts)
	# this code version started fine: a downloaded patch is now trusted (boot.gd drops a patch that never gets this far)
	get_tree().create_timer(4.0).timeout.connect(func(): DirAccess.remove_absolute("user://patch_try.txt"))
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST: C.save()
	if what == NOTIFICATION_APPLICATION_PAUSED: C.save()

# the menu size option (Small / Medium / Large / Extra large)
const UISIZE := {"s": ["Small", 0.85], "m": ["Medium", 1.0], "l": ["Large", 1.2], "xl": ["Extra large", 1.4]}
func apply_ui_size() -> void:
	_prune_panel_fits()
	get_window().content_scale_factor = UISIZE.get(G.opts.get("ui", "m"), UISIZE.m)[1]

func show_screen(name: String) -> Control:
	K.close_panel(false)
	if scr: scr.queue_free()
	if hud and name != "battle": hud.queue_free(); hud = null
	screen = name
	scr = Control.new(); scr.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(scr); move_child(scr, 0)
	return scr
func art_bg(c: Control, i: int) -> void:   # the ROM artwork, darkened, behind the menus
	var t := K.img("img/ui/art%d.png" % i, 0, 0); t.set_anchors_preset(Control.PRESET_FULL_RECT); t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; c.add_child(t)   # soft, like the HTML's background
	var d := ColorRect.new(); d.color = Color(11 / 255.0, 23 / 255.0, 54 / 255.0, 0.92); d.set_anchors_preset(Control.PRESET_FULL_RECT); d.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(d)
func scroll_body(c: Control, pad := 10) -> VBoxContainer:
	var sc := ScrollContainer.new(); sc.set_anchors_preset(Control.PRESET_FULL_RECT); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; c.add_child(sc)
	var m := MarginContainer.new(); m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: m.add_theme_constant_override(k, pad)
	sc.add_child(m)
	var v := K.vbox(8); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; m.add_child(v)
	return v

# ---------- title ----------
var _title_t := 0.0
func show_title() -> void:
	var s := show_screen("title"); Snd.play_music("_title")
	# the ROM's title-menu artworks, shown whole at a sharp whole-number scale in a framed window; a soft blurred copy fills the screen
	var bgi := K.img("img/ui/art1.png", 0, 0); bgi.set_anchors_preset(Control.PRESET_FULL_RECT); bgi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED; bgi.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; bgi.modulate = Color(0.45, 0.5, 0.7); s.add_child(bgi)
	var vig := ColorRect.new(); vig.color = Color(0.02, 0.05, 0.15, 0.45); vig.set_anchors_preset(Control.PRESET_FULL_RECT); vig.mouse_filter = Control.MOUSE_FILTER_IGNORE; s.add_child(vig)
	var walk := TitleWalkers.new(); walk.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); walk.anchor_top = 1; walk.offset_top = -130; walk.mouse_filter = Control.MOUSE_FILTER_IGNORE; s.add_child(walk)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE; s.add_child(cc)
	var st := K.vbox(10); st.alignment = BoxContainer.ALIGNMENT_CENTER; cc.add_child(st)
	var logo := K.lbl("ROUTE\nDEFENSE", 40, K.GOLD, false); logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_shadow_color", K.WIND); logo.add_theme_constant_override("shadow_offset_x", 3); logo.add_theme_constant_override("shadow_offset_y", 3); logo.add_theme_constant_override("line_spacing", -4)
	st.add_child(logo)
	var frame := PanelContainer.new(); frame.add_theme_stylebox_override("panel", K.sb(Color(0, 0, 0, 0.3), K.WINB, 3, 6, 3)); frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pic := TitleArt.new(); frame.add_child(pic); st.add_child(frame)
	var sub := K.lbl("wild Pokémon are coming down the path", 14, K.DIM, false); sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; st.add_child(sub)
	var b := K.btn("Continue" if G.box.size() else "New Game", func(): (show_hub() if G.box.size() else show_starter())); b.add_theme_font_size_override("font_size", 24); b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	st.add_child(b)
	if G.box.size():
		var nopen := 0
		for i in C.DB.ts.size(): if C.map_open(i): nopen += 1
		var info := K.lbl("%d maps open - best tier %d - %d Pokémon - Pokédex %d" % [nopen, C.best_tier(), G.box.size(), G.own.size()], 13, K.DIM); info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; info.custom_minimum_size.x = 300; st.add_child(info)
	check_update(st)
	pic.fit.call_deferred()

class TitleArt extends Control:   # the ROM's three title artworks, cross-fading, at the biggest whole-number scale that fits
	var t := 0.0; var arts := []
	func _ready() -> void:
		for i in [1, 2, 3]: arts.append(C.tex("img/ui/art%d.png" % i))
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_viewport().size_changed.connect(fit)
	func fit() -> void:
		var vs := get_viewport_rect().size
		var s: int = max(1, int(floor(min(vs.x * 0.82 / 240.0, (vs.y - 330) / 160.0))))
		custom_minimum_size = Vector2(240 * s, 160 * s)
	func _process(dt: float) -> void: t += dt; queue_redraw()
	func _draw() -> void:
		if arts.is_empty() or arts[0] == null: return
		var per := 6.0; var i := int(t / per) % 3; var f := clampf((fmod(t, per) - (per - 1)) / 1.0, 0, 1)
		draw_texture_rect(arts[i], Rect2(Vector2.ZERO, size), false)
		if f > 0: draw_texture_rect(arts[(i + 1) % 3], Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, f))
class TitleWalkers extends Control:   # Pokémon walking across the bottom of the title screen
	var walkers := []; var pool := []
	func _ready() -> void:
		for m in C.DB.dex.mon: if m.anim and C.DB.anim[m.id].has("Walk") and m.get("g", 9) <= 3: pool.append(m)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	func _process(dt: float) -> void:
		var k: float = max(2, round(get_viewport_rect().size.y / 330.0)); var w := size.x / k
		if walkers.size() < 4 and randf() < dt * 0.6 and pool.size():
			var m = pool[randi() % pool.size()]; var right := randf() < 0.5
			walkers.append({"id": m.id, "x": -30.0 if right else w + 30, "v": (1 if right else -1) * (14 + m.b[5] * 0.12), "t": 0.0})
		for a in walkers: a.t += dt; a.x += a.v * dt
		walkers = walkers.filter(func(a): return a.x > -60 and a.x < w + 60)
		queue_redraw()
	func _draw() -> void:
		var k: float = max(2, round(get_viewport_rect().size.y / 330.0))
		draw_set_transform(Vector2(0, size.y - 60 * k), 0, Vector2(k, k))
		for a in walkers:
			draw_set_transform(Vector2(a.x * k, size.y - 8 * k), 0, Vector2(k, k * 0.42)); draw_circle(Vector2.ZERO, 8, Color(0, 0, 0, .28))
			draw_set_transform(Vector2(0, size.y - 60 * k), 0, Vector2(k, k))
			var A = C.DB.anim[a.id].Walk; var im := C.mon_tex(a.id)
			if im == null: continue
			var tot := 0
			for v in A.d: tot += v
			var ft = int(a.t * 60) % max(1, tot); var f := 0
			while f < A.n - 1 and ft >= A.d[f]: ft -= A.d[f]; f += 1
			var row := 2 if a.v > 0 else 6; var r: int = row if A.r > 1 else 0
			var gp: Array = A.sh[min(r, A.sh.size() - 1)] if A.has("sh") else [A.fw / 2.0, A.fh / 2.0 + 4]
			draw_texture_rect_region(im, Rect2(round(a.x - gp[0]), round(52 - gp[1]), A.fw, A.fh), Rect2(f * A.fw, A.y + r * A.fh, A.fw, A.fh))

# ---------- online code updates: GitHub holds the newest scripts (a small patch); the graphics stay in the app ----------
func check_update(st: VBoxContainer) -> void:
	var run_v: int = Engine.get_meta("code_v", 1)
	var ver := K.lbl("v%d" % run_v, 12, K.DIM, false); ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; st.add_child(ver)
	var chk := K.btn("Check for updates", func(): pass, true, true); chk.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; st.add_child(chk)
	var state := {"upd": null}
	var run := func(manual: bool) -> void:
		if manual: chk.disabled = true; chk.text = "Checking..."
		var req := HTTPRequest.new(); add_child(req); req.timeout = 10
		req.request_completed.connect(func(res, code, _h, body):
			req.queue_free()
			if not is_instance_valid(st): return
			chk.disabled = false; chk.text = "Check for updates"
			if res != HTTPRequest.RESULT_SUCCESS or code != 200:
				if manual: K.toast("Couldn't check for updates (offline?)")
				return
			var r = JSON.parse_string(body.get_string_from_utf8())
			if typeof(r) != TYPE_DICTIONARY: return
			if int(r.get("v", 0)) <= run_v:
				if manual: K.toast("You have the newest version (v%d)" % run_v)
				return
			if r.has("base") and int(r.base) > int(Engine.get_meta("built_v", 1)):
				ver.text = "v%d - v%d is out but needs a new app download" % [run_v, int(r.v)]; return
			if state.upd != null and is_instance_valid(state.upd): state.upd.text = "Update available (v%d)" % int(r.v); return
			var b := K.btn("Update available (v%d)" % int(r.v), func(): pass, true)
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			st.add_child(b); st.move_child(b, ver.get_index()); state.upd = b
			b.pressed.connect(func(): _download_patch(r, b)))
		req.request(UPD + "version.json?t=%d" % Time.get_unix_time_from_system())
	chk.pressed.connect(func(): run.call(true))
	run.call(false)   # also checks by itself when the title screen opens
func _download_patch(r: Dictionary, b: Button) -> void:
	b.disabled = true; b.text = "Downloading..."
	var req := HTTPRequest.new(); add_child(req); req.timeout = 60; req.download_file = "user://patch_new.pck"
	req.request_completed.connect(func(res, code, _h, _body):
		req.queue_free()
		var ok = res == HTTPRequest.RESULT_SUCCESS and code == 200
		if ok and r.has("sha256"):   # a damaged download never replaces the code
			var hc := HashingContext.new(); hc.start(HashingContext.HASH_SHA256)
			var f := FileAccess.open("user://patch_new.pck", FileAccess.READ)
			while f and not f.eof_reached(): hc.update(f.get_buffer(1 << 16))
			if f: f.close()
			ok = hc.finish().hex_encode() == String(r.sha256).to_lower()
		if not ok:
			DirAccess.remove_absolute("user://patch_new.pck"); b.disabled = false; b.text = "Update failed - tap to retry"; return
		C.save()
		DirAccess.rename_absolute("user://patch_new.pck", "user://patch.pck")
		var fi := FileAccess.open("user://patch.txt", FileAccess.WRITE); fi.store_string(str(int(r.v))); fi.close()
		DirAccess.remove_absolute("user://patch_try.txt")
		# the new code loads when the game starts again (boot.gd loads it before anything else)
		if OS.has_feature("pc"):
			b.text = "Restarting..."; await get_tree().create_timer(0.3).timeout; OS.set_restart_on_exit(true); get_tree().quit()
		else:
			b.text = "Updated - close and reopen the game"; b.disabled = false
			for cn in b.pressed.get_connections(): b.pressed.disconnect(cn.callable)
			b.pressed.connect(func(): C.save(); get_tree().quit()))
	req.request(UPD + String(r.get("pck", "patch.pck")) + "?t=%d" % Time.get_unix_time_from_system())

# ---------- starter ----------
func show_starter() -> void:
	var s := show_screen("starter"); art_bg(s, 3)
	var v := scroll_body(s); v.add_child(K.lbl("Choose your first partner", 22, K.GOLD))
	var g := K.grid(); v.add_child(g)
	for id in STARTERS:
		if not C.SP.has(id) or not C.SP[id].anim: continue
		var c := K.card(104, func(): _confirm_starter(id)); var cb := K.card_box(c)
		cb.add_child(K.icon(id)); cb.add_child(_center(K.lbl(C.SP[id].n, 15))); cb.add_child(K.type_row(C.SP[id].t)); g.add_child(c)
func _confirm_starter(id: int) -> void:
	var box := K.panel(); K.panel_title(box, C.SP[id].n); box.add_child(K.lbl("Start your journey with %s?" % C.SP[id].n))
	var h := K.hbox(); box.add_child(h)
	h.add_child(K.btn("Yes", func():
		G.box.append(C.make_mon(id, 5)); team = [G.box[0].u]; G.team = team.duplicate(); C.save(); K.close_panel(false); Snd.sfx("join"); show_hub()))
	h.add_child(K.btn("No", func(): K.close_panel(), true))
func _center(l: Label) -> Label: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; return l

# ---------- hub ----------
var _hub_scroll := 0
func show_hub(tab := "") -> void:
	var same := screen == "hub" and (tab == "" or tab == hub)
	if tab != "": hub = tab
	var s := show_screen("hub"); Snd.play_music("_hub"); art_bg(s, 1)
	var sc := ScrollContainer.new(); sc.set_anchors_preset(Control.PRESET_FULL_RECT); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; s.add_child(sc)
	var m := MarginContainer.new(); m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: m.add_theme_constant_override(k, 10)
	sc.add_child(m)
	var v := K.vbox(8); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; m.add_child(v)
	var top := K.flow(8); v.add_child(top)
	var nopen := 0
	for i in C.DB.ts.size(): if C.map_open(i): nopen += 1
	top.add_child(_chip("img/ui/coin.png", "", _num(G.money)))
	top.add_child(_chip("img/ui/badge.png", "Rescue Points ", str(G.rp)))
	top.add_child(_chip("", "Maps ", "%d/%d" % [nopen, C.DB.ts.size()]))
	top.add_child(_chip("", "Best tier ", str(C.best_tier())))
	top.add_child(_chip("", "Pokédex ", "%d/%d" % [G.own.size(), _anim_count()]))
	var ob := K.btn("Options", func(): options_panel(func(): show_hub()), true, true); ob.icon = K.glyph("gear", 16).texture; ob.expand_icon = false; top.add_child(_glyph_btn(ob, "gear"))
	var tabs := K.flow(4); v.add_child(tabs)
	for kn in [["routes", "Routes"], ["box", "Box"], ["dex", "Pokédex"], ["rescue", "Rescue"], ["shop", "Shop"], ["bag", "Bag"]]:
		tabs.add_child(K.tab_btn(kn[1], hub == kn[0], func(): show_hub(kn[0])))
	var body := K.vbox(8); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_child(body)
	match hub:
		"routes": hub_routes(body)
		"box": hub_box(body)
		"rescue": hub_rescue(body)
		"dex": hub_dex(body)
		"shop": hub_shop(body)
		"bag": hub_bag(body)
	if same: (func(): sc.scroll_vertical = _hub_scroll).call_deferred()
	sc.get_v_scroll_bar().value_changed.connect(func(x): _hub_scroll = int(x))
func _glyph_btn(b: Button, g: String) -> Button:   # "⚙ Options": the Noto gear in front of the text
	b.icon = K.glyph(g, 16).texture; b.expand_icon = false; b.add_theme_constant_override("icon_max_width", 18); return b
func _anim_count() -> int:
	var n := 0
	for m in C.DB.dex.mon: if m.anim: n += 1
	return n
func _num(n) -> String:   # 12345 -> 12,345
	var s := str(int(n)); var out := ""
	while s.length() > 3: out = "," + s.substr(s.length() - 3) + out; s = s.substr(0, s.length() - 3)
	return s + out
func _chip(icon_path: String, t: String, b: String) -> PanelContainer:
	var p := PanelContainer.new(); var st := K.sb(Color(10 / 255.0, 26 / 255.0, 74 / 255.0, 0.8), Color(1, 1, 1, 0.2), 2, 20, 4); st.content_margin_left = 10; st.content_margin_right = 10
	p.add_theme_stylebox_override("panel", st)
	var h := K.hbox(6); p.add_child(h)
	if icon_path != "": h.add_child(K.img(icon_path, 16, 16))
	if t != "": h.add_child(K.lbl(t, 16, Color.WHITE, false))
	h.add_child(K.lbl(b, 16, K.GOLD, false)); return p

func hub_routes(body: VBoxContainer) -> void:
	body.add_child(K.lbl("Every map is randomly made when you start it. Each map has its own tiers. One win opens the next map of its group; a high tier on any map opens the next group. Later groups are harder by nature, and pay more.", 13, K.DIM))
	var last_g := -1; var g = null
	for i in C.DB.ts.size():
		var gi: int = C.map_group(i)
		if gi != last_g:
			last_g = gi; var MGr: Array = C.MAPGROUP[gi]
			body.add_child(K.lbl(MGr[0], 20, Color(MGr[1]))); g = K.grid(); body.add_child(g)
		var S: Dictionary = C.DB.ts[i]; var open: bool = C.map_open(i); var topt: int = C.map_cleared(i)
		var c := K.card(150, func(): route_panel(i), false, not open); var cb := K.card_box(c)
		cb.add_child(_swatch(i))
		cb.add_child(_center(K.lbl(S.name, 15))); cb.add_child(_center(K.lbl("Explorers of Sky" if S.game == "E" else "Rescue Team", 12, K.DIM))); cb.add_child(_types_flow(S.types))
		if open: cb.add_child(_center(K.lbl(("Tier %s cleared" % ("%d (max)" % C.MAXTIER if G.get("mtDone", {}).get(i, 0) else str(topt))) if topt else "New", 13, Color("#9f9"))))
		else: cb.add_child(_center(K.lbl("Win the map before to open" if (i > 0 and C.map_group(i - 1) == gi) else "Clear tier %d on any %s map" % [C.group_gate(gi), C.MAPGROUP[max(0, gi - 1)][0]], 12, Color("#ff9a9a"))))
		g.add_child(c)
func _types_flow(types: Array) -> HFlowContainer:
	var f := K.flow(2); f.alignment = FlowContainer.ALIGNMENT_CENTER; f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in types: f.add_child(K.type_tag(t))
	return f
# a little strip of the setting's own tiles (ground, a path, a pond) drawn with the same PMD auto-tile rules as the maps
var SWATCH := {}
func _swatch(i: int) -> TextureRect:
	if not SWATCH.has(i):
		var W := 12; var H := 4; var t := []
		for y in H:
			var row := PackedInt32Array(); row.resize(W)
			for x in W: row[x] = 1 if (((y == 1 or y == 2) and x < 8) or (x >= 7 and y >= 1 and x <= 8)) else 0
			t.append(row)
		t[0][10] = 2; t[0][11] = 2; t[1][10] = 2; t[1][11] = 2
		var R := MG.Rng.new(i + 1); var vr := []
		for y in H:
			var row := PackedInt32Array(); row.resize(W)
			for x in W: row[x] = int(floor(R.next() * 3))
			vr.append(row)
		SWATCH[i] = MG.render_map({"set": i, "W": W, "H": H, "t": t, "vr": vr})
	var tr := TextureRect.new(); tr.texture = SWATCH[i]; tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; tr.mouse_filter = Control.MOUSE_FILTER_IGNORE; tr.custom_minimum_size = Vector2(0, 40); tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.resized.connect(func(): tr.custom_minimum_size.y = tr.size.x / 3.0)
	return tr

func route_panel(i: int) -> void:
	var S: Dictionary = C.DB.ts[i]
	var keep: int = route.tier if (route != null and route.set == i) else C.map_tier(i)
	route = {"set": i, "tier": max(1, min(C.map_tier(i), keep)), "seed": randi() % 1000000000}
	var box := K.panel()
	var render := func(self_ref: Callable) -> void:
		K.clear(box)
		var r = route; var gi: int = C.map_group(i); var MG0: Array = C.MAPGROUP[gi]
		K.panel_title(box, "%s  (%s)" % [S.name, MG0[0]]); box.add_child(_types_flow(S.types))
		if gi: box.add_child(K.lbl("%s map: harder by nature - every tier here fights like a higher tier on earlier maps (levels, species and traits), with shorter paths, more entrances and water and %d%% more per wave. Rewards x%s." % [MG0[0], int(round((MG0[4] - 1) * 100)), str(MG0[3])], 13, K.DIM))
		var vs := get_viewport_rect().size
		var pm := MG.gen_map(i, false, r.seed, null, max(vs.x, vs.y) / min(vs.x, vs.y), r.tier)
		var prev := RoutePreview.new(); prev.M = pm; prev.custom_minimum_size = Vector2(0, 80); prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_child(prev)
		var th: float = C.threat_tier(i, r.tier); var lr: Array = BT.lv_range(th); var stn: int = C.stars_of(i, r.tier)
		var row := K.hbox(6); row.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_child(row)
		row.add_child(K.btn("◀", func():
			if r.tier > 1: r.tier -= 1; self_ref.call(self_ref), true, true))
		row.add_child(K.lbl("Tier %d  %s%s  -  wild Lv %d-%d  -  %d waves" % [r.tier, "★".repeat(stn), "☆".repeat(3 - stn), min(98, lr[0]), min(100, lr[1]), BT.wave_count(r.tier)], 15, Color.WHITE, false))
		row.add_child(K.btn("▶", func():
			if r.tier < C.map_tier(i): r.tier += 1; self_ref.call(self_ref), true, true))
		var bt := K.hbox(6); bt.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_child(bt)
		bt.add_child(K.btn("New layout", func(): r.seed = randi() % 1000000000; self_ref.call(self_ref), true))
		bt.add_child(K.btn("Choose team ▶", func(): K.close_panel(false); show_team()))
		var tr := []
		for x in BT.TRAITS: if x[0] <= th: tr.append(x[1])
		if tr.size(): box.add_child(K.rich("[b]Wild traits here:[/b]\n" + "\n".join(tr), 13))
		var gs := []; var nx := i + 1
		if nx < C.DB.ts.size() and C.map_group(nx) == gi and not C.map_open(nx): gs.append("Win here to open the next map.")
		if gi < 3 and not C.map_open(C.group_start(gi + 1)): gs.append("Clear tier %d on any %s map to open the %s maps." % [C.group_gate(gi + 1), C.MAPGROUP[gi][0], C.MAPGROUP[gi + 1][0]])
		if gs.size(): box.add_child(K.rich("[b]" + "\n".join(gs) + "[/b]", 13))
		box.add_child(spawn_list(i, r.tier))
		box.add_child(K.lbl("Stars: ★ win, ★★ 50+ lives left, ★★★ no lives lost. Each new star gives bonus Rescue Points.", 13, K.DIM))
		box.add_child(K.lbl({"split": "The path splits in two and joins again.", "two": "Two entrances: a second path merges in.", "three": "Three entrances: two more paths merge in."}.get(pm.kind, "One path."), 13, K.DIM))
	render.call(render)
class RoutePreview extends Control:   # the map preview with the paths dashed over it
	var M: Dictionary
	func _ready() -> void: texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; resized.connect(func(): custom_minimum_size.y = size.x * M.H / float(M.W))
	func _draw() -> void:
		var s = size.x / (M.W * 24.0)
		draw_texture_rect(M.tex, Rect2(0, 0, M.W * 24 * s, M.H * 24 * s), false)
		for l in M.lines:
			for k in range(1, l.size()):
				draw_dashed_line(l[k - 1] * s, l[k] * s, Color(120 / 255.0, 30 / 255.0, 20 / 255.0, .55), 3 * s, 8 * s)
# the wild Pokémon this map and tier can send; ones you haven't seen yet are dark silhouettes
func spawn_list(i: int, tier: int) -> VBoxContainer:
	var SI: Dictionary = BT.spawn_info(i, tier); var wrap := K.vbox(4)
	var sec := func(title: String, list: Array, note: String) -> void:
		if list.is_empty(): return
		wrap.add_child(K.rich("[b]%s[/b]%s" % [title, (" - " + note) if note != "" else ""], 13))
		var g := K.flow(4); wrap.add_child(g)
		var l2 := list.duplicate(); l2.sort_custom(func(a, b): return a.bst < b.bst)
		for m in l2:
			var seen: bool = G.seen.has(m.id); var c := K.vbox(0); c.custom_minimum_size = Vector2(56, 0)
			var ic := K.icon(m.id, 36)
			if not seen: ic.modulate = Color(0, 0, 0, 0.45)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			c.add_child(ic); var nl := K.lbl(m.n if seen else "???", 10, Color.WHITE); nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; c.add_child(nl); g.add_child(c)
	var nseen := 0
	for m in SI.pool: if G.seen.has(m.id): nseen += 1
	wrap.add_child(K.rich("[b]Wild Pokémon here[/b] - %d/%d seen" % [nseen, SI.pool.size()], 13))
	var notes := ["", "60% as often", "35% as often", "15% as often"]
	for k in 4:
		var l := []
		for m in SI.pool: if SI.rar[m.id] == k: l.append(m)
		sec.call(BT.RARITY[k], l, notes[k])
	sec.call("Heavy waves (every 5th)", heavy_pool(SI), "later heavy waves bring the stronger ones")
	sec.call("Possible bosses", SI.bosses, "or a legendary, half the time" if SI.legs.size() else "")
	if SI.legs.size(): sec.call("Legendary bosses", SI.legs, "")
	return wrap

# ---------- Pokémon cards and pages ----------
func qk_line(id: int) -> VBoxContainer:
	var v := K.vbox(2); var ty: Array = C.SP[id].t; var qs := C.quirks(id)
	for k in qs.size():
		var h := K.hbox(4); h.add_child(K.type_tag(ty[k], qs[k][0])); var d := K.lbl(qs[k][1], 12, K.DIM); d.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(d); v.add_child(h)
	return v
func mon_card(e: Dictionary, on = null, picked := false) -> PanelContainer:
	var c := K.card(104, on, picked); var cb := K.card_box(c)
	var top := Control.new(); top.custom_minimum_size = Vector2(0, 48); top.mouse_filter = Control.MOUSE_FILTER_IGNORE; cb.add_child(top)
	var ic := K.icon(e.id); ic.set_anchors_preset(Control.PRESET_CENTER_TOP); ic.anchor_left = 0.5; ic.anchor_right = 0.5; ic.offset_left = -24; ic.offset_right = 24; ic.offset_bottom = 48; top.add_child(ic)
	var lst := K.sb(K.WIND, Color(1, 1, 1, 0.27), 1, 8, 1); lst.content_margin_left = 5; lst.content_margin_right = 5
	var lv := PanelContainer.new(); lv.add_theme_stylebox_override("panel", lst); lv.add_child(K.lbl("Lv %d" % e.lv, 11, Color.WHITE, false))
	# sized by its text, growing leftward from the card's top-right corner (a fixed width let the text spill out)
	lv.set_anchors_preset(Control.PRESET_TOP_RIGHT); lv.anchor_left = 1; lv.anchor_right = 1; lv.offset_left = 0; lv.offset_right = 0; lv.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE; top.add_child(lv)
	if BT.sees_why(e) != null: top.add_child(eye_badge(false))
	var ty: Array = C.SP[e.id].t
	var stripe := HBoxContainer.new(); stripe.add_theme_constant_override("separation", 0); stripe.custom_minimum_size = Vector2(0, 3); stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in ty:
		var cr := ColorRect.new(); cr.color = C.TCOL[t]; cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cr.mouse_filter = Control.MOUSE_FILTER_IGNORE; stripe.add_child(cr)
	cb.add_child(stripe)
	cb.add_child(_center(K.lbl(C.SP[e.id].n, 15)))
	var qn := []
	for q in C.quirks(e.id): qn.append(q[0])
	cb.add_child(_center(K.lbl(" / ".join(qn), 11, K.DIM)))
	var tags := []
	for o in C.evo_options(e): if o.ok: tags.append("[color=#7f7]EVOLVE[/color]"); break
	if e.pend.size(): tags.append("[color=#7cf]NEW MOVE[/color]")
	if tags.size(): var rt := K.rich("[center]" + " ".join(tags) + "[/center]", 11); cb.add_child(rt)
	return c
func eye_badge(small: bool) -> PanelContainer:   # the HTML's eye badge in a card's top-left corner: this Pokémon sees hidden Pokémon
	var p := PanelContainer.new(); var s := K.sb(Color(0x4a / 255.0, 0x1a / 255.0, 0x6a / 255.0, 0.8), Color("#d8b0ff"), 1, 7, 1); s.content_margin_left = 3; s.content_margin_right = 3
	p.add_theme_stylebox_override("panel", s); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(K.glyph("eye", 9 if small else 11)); p.position = Vector2(1, 1) if small else Vector2(4, 3)
	return p
func hub_box(body: VBoxContainer) -> void:
	body.add_child(K.lbl("%d Pokémon. Tap one to see its moves and evolutions." % G.box.size(), 13, K.DIM))
	var g := K.grid(); body.add_child(g)
	var l: Array = G.box.duplicate(); l.sort_custom(func(a, b): return a.lv > b.lv)
	for e in l: g.add_child(mon_card(e, func(): mon_panel(e, func(): show_hub())))
func move_row(m: int) -> PanelContainer:
	var p := K.boxp(); var v := K.vbox(2); p.add_child(v); var M := C.mv(m)
	var h := K.hbox(4); h.add_child(K.type_tag(M.t)); h.add_child(K.lbl(M.n, 16, Color.WHITE, false)); v.add_child(h)
	v.add_child(K.lbl(C.move_desc(m), 12, K.DIM)); return p
func mon_panel(e: Dictionary, after = null) -> void:
	var box := K.panel(after)
	var render := func(self_ref: Callable) -> void:
		K.clear(box)
		var s: Dictionary = C.SP[e.id]; var st: Array = C.mon_stats(e)
		var nx: int = C.xp_for(s.gr, e.lv + 1) if e.lv < C.MAXLV else e.xp; var cur: int = C.xp_for(s.gr, e.lv)
		var head := K.hbox(10); box.add_child(head)
		head.add_child(K.anim_icon(e.id, 72))
		var hv := K.vbox(3); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(hv)
		hv.add_child(K.rich("[color=#ffd84a][font_size=22]%s[/font_size][/color] [font_size=14]Lv %d[/font_size]" % [s.n, e.lv], 16)); hv.add_child(_types_flow_left(s.t))
		var xp := ProgressBar.new(); xp.show_percentage = false; xp.custom_minimum_size = Vector2(0, 6); xp.max_value = 100
		xp.value = 100 if e.lv >= C.MAXLV else floor((e.xp - cur) / float(max(1, nx - cur)) * 100); hv.add_child(xp)
		var N = C.DB.dex.nat[C.nat_of(e) - 1]
		for i in 6:
			var c := "up" if (N.up != N.dn and i == N.up) else ("dn" if (N.up != N.dn and i == N.dn) else "")
			var use := i == 1 or i == 3 or i == 5
			var row := K.hbox(4); hv.add_child(row)
			var nl := K.lbl(C.STATN[i] + (" ▲" if c == "up" else (" ▼" if c == "dn" else "")), 12, Color("#ff9a9a") if c == "up" else (Color("#9ab8ff") if c == "dn" else (Color.WHITE if use else K.DIM)), false); nl.custom_minimum_size.x = 56; row.add_child(nl)
			var vl := K.lbl(str(st[i]), 12, Color.WHITE if use else K.DIM, false); vl.custom_minimum_size.x = 34; row.add_child(vl)
			var bar := ProgressBar.new(); bar.show_percentage = false; bar.custom_minimum_size = Vector2(0, 5); bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.max_value = 100; bar.value = min(100, st[i] / ((331 * e.lv / 100.0 + 5) if i else (331 * e.lv / 100.0 + e.lv + 10)) * 100); row.add_child(bar)
		hv.add_child(qk_line(e.id)); hv.add_child(K.lbl("Placing costs $%d battle cash" % C.place_cost(e), 13, K.DIM))
		var A = C.DB.dex.abil.get(e.ab, null)
		if A:
			var hid := false
			for x in s.ab: if x[0] == e.ab and x[1]: hid = true
			var p := K.boxp(); var pv := K.vbox(2); p.add_child(pv); box.add_child(p)
			pv.add_child(K.lbl("Ability: %s%s" % [A.n, " (hidden ability)" if hid else ""]))
			pv.add_child(K.lbl(A.get("d", ""), 12, K.DIM))
			pv.add_child(K.lbl(("In Route Defense: " + C.AB_TD[A.k]) if C.AB_TD.has(A.k) else "No effect in Route Defense", 12, Color("#9f9") if C.AB_TD.has(A.k) else Color("#aaa")))
		var why = BT.sees_why(e)
		var sp := K.boxp(); var spv := K.vbox(2); sp.add_child(spv); box.add_child(sp)
		if why != null:
			var eh := K.hbox(4); eh.add_child(K.glyph("eye", 14)); eh.add_child(K.lbl("Sees hidden Pokémon")); spv.add_child(eh)
			spv.add_child(K.lbl("Reveals hidden Ghost types in its range (tier 3+): " + why, 12, K.DIM))
		else:
			spv.add_child(K.lbl("Can't see hidden Pokémon")); spv.add_child(K.lbl("Hidden Ghost types (tier 3+) need a Psychic or Ghost type, Foresight, Odor Sleuth, Miracle Eye, Keen Eye or Frisk nearby", 12, K.DIM))
		var H = C.DB.dex.held.get(e.it, null)
		var hp := K.boxp(); var hv2 := K.vbox(2); hp.add_child(hv2); box.add_child(hp)
		var hh := K.hbox(4); hv2.add_child(hh)
		if H: hh.add_child(K.item_icon(e.it)); hh.add_child(K.lbl("Holding: " + H.n, 16, Color.WHITE, false))
		else: hh.add_child(K.lbl("Holding nothing"))
		if H:
			hv2.add_child(K.lbl(C.HELD_TD.get(H.k, ""), 12, K.DIM))
			hh.add_child(K.btn("Take", func(): G.held[e.it] = G.held.get(e.it, 0) + 1; e.it = 0; C.save(); self_ref.call(self_ref), true, true))
		var have := false
		for k in G.held: if G.held[k] > 0: have = true
		if have: hh.add_child(K.btn("Swap" if H else "Give item", func(): give_panel(e, func(): mon_panel(e, after)), false, true))
		# nature and IVs: change them with Mints and Bottle Caps from the shop (not during a battle)
		var iv: Array = C.ivs_of(e); var np := K.boxp(); var nv := K.vbox(2); np.add_child(nv); box.add_child(np)
		nv.add_child(K.lbl("Nature: " + C.nat_label(e.nat)))
		if e.mint:
			for k in C.DB.dex.tools: if C.DB.dex.tools[k].get("nat", 0) == e.mint: nv.add_child(K.lbl("Stats changed by %s: %s" % [C.DB.dex.tools[k].n, C.nat_label(e.mint)], 12, K.DIM))
		var ivs := []; var tot := 0
		for i in 6: ivs.append("%s %d%s" % [C.STATN[i], iv[i], "*" if e.ht[i] else ""]); tot += iv[i]
		nv.add_child(K.lbl("IVs: " + " - ".join(ivs) + " (total %d/186)" % tot, 12, K.DIM))
		if e.ht.has(1): nv.add_child(K.lbl("* raised by a Bottle Cap", 12, K.DIM))
		var tk := false
		for k in G.tools: if G.tools[k] > 0: tk = true
		if screen != "battle" and tk: nv.add_child(K.btn("Use Mint / Bottle Cap", func(): tool_panel(e, func(): mon_panel(e, after)), false, true))
		elif screen == "battle" and tk: nv.add_child(K.lbl("Mints and Bottle Caps can only be used outside battle.", 12, K.DIM))
		box.add_child(K.lbl("Moves", 18, K.GOLD))
		for k in e.mv.size():
			var r := move_row(e.mv[k]); box.add_child(r)
			if e.pend.size(): r.get_child(0).get_child(0).add_child(K.btn("Replace", func(): e.mv[k] = e.pend.pop_front(); C.save(); self_ref.call(self_ref), false, true))
		if e.pend.size():
			var m: int = e.pend[0]; var r := move_row(m); r.add_theme_stylebox_override("panel", K.sb(Color(10 / 255.0, 26 / 255.0, 74 / 255.0, 0.4), Color("#7cf"), 1, 8, 6)); box.add_child(r)
			r.get_child(0).add_child(K.lbl("New move - tap Replace on a move above, or", 12, K.DIM))
			r.get_child(0).add_child(K.btn("Don't learn", func(): e.pend.pop_front(); C.save(); self_ref.call(self_ref), true, true))
		var rem := []
		for m in C.learned_by(e.id, e.lv): if not e.mv.has(m) and (C.move_use(m) != null or BT.skills().has(m)): rem.append(m)
		var bts := K.flow(4); box.add_child(bts)
		var ski: int = e.mv.find(BT.MID("Sketch"))
		if ski >= 0 and screen != "battle": bts.add_child(K.btn("Sketch a move", func(): sketch_panel(e, ski, func(): mon_panel(e, after)), false, true))
		if rem.size(): bts.add_child(K.btn("Move Reminder (%d)" % rem.size(), func(): remind_panel(e, func(): mon_panel(e, after)), true, true))
		var ev: Array = C.evo_options(e)
		if ev.size():
			box.add_child(K.lbl("Evolution", 18, K.GOLD))
			for o in ev:
				var p := K.boxp(); var h := K.hbox(6); p.add_child(h); box.add_child(p)
				h.add_child(K.icon(o.to, 32)); h.add_child(K.lbl(C.SP[o.to].n, 16, Color.WHITE, false))
				if o.item: h.add_child(K.item_icon(o.item))
				h.add_child(K.lbl("(%s)" % o.why, 12, K.DIM, false))
				if o.ok: h.add_child(K.btn("Evolve", func(): _evolve(e, o, s.n); self_ref.call(self_ref), false, true))
		var cl := K.hbox(6); box.add_child(cl)
		cl.add_child(K.btn("Close", func(): K.close_panel(), true))
		if screen == "hub" and G.box.size() > 1:
			var sp2 := Control.new(); sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cl.add_child(sp2)
			cl.add_child(K.btn("Release", func(): _release(e, after), true, true))
	render.call(render)
func _evolve(e: Dictionary, o: Dictionary, from_n: String) -> void:
	C.evolve(e, o.to, o.item); Snd.sfx("evo"); K.toast("%s evolved into %s!" % [from_n, C.SP[o.to].n], o.to); C.save()
	if BT.B:
		for t in BT.B.towers:
			if is_same(t.e, e): t.anim = "Idle"
func apply_fps() -> void: Engine.max_fps = 60 if G.opts.get("fps60", true) else 30
func _types_flow_left(types: Array) -> HFlowContainer:
	var f := K.flow(2)
	for t in types: f.add_child(K.type_tag(t))
	return f
func _release(e: Dictionary, after) -> void:
	var b := K.panel(func(): show_hub("box")); K.panel_title(b, "Release %s?" % C.SP[e.id].n)
	b.add_child(K.lbl("Lv %d. It will leave your box for good%s." % [e.lv, (" (its %s goes back to your bag)" % C.DB.dex.held[e.it].n) if e.it else ""]))
	var h := K.hbox(); b.add_child(h)
	h.add_child(K.btn("Release", func():
		if e.it: G.held[e.it] = G.held.get(e.it, 0) + 1
		G.box = G.box.filter(func(x): return not is_same(x, e)); G.team = G.get("team", []).filter(func(u): return u != e.u); C.save(); K.close_panel()))
	h.add_child(K.btn("Keep", func(): mon_panel(e, after), true))
func give_panel(e: Dictionary, back: Callable) -> void:
	var box := K.panel(back); K.panel_title(box, "Give an item")
	for k in G.held.keys():
		if G.held[k] <= 0: continue
		var H: Dictionary = C.DB.dex.held[k]; var p := K.card(0, func():
			if e.it: G.held[e.it] = G.held.get(e.it, 0) + 1
			G.held[k] -= 1
			if not G.held[k]: G.held.erase(k)
			e.it = k; C.save(); K.close_panel())
		var cb := K.card_box(p); cb.alignment = BoxContainer.ALIGNMENT_BEGIN
		var h := K.hbox(4); h.add_child(K.item_icon(k)); h.add_child(K.lbl("%s x%d" % [H.n, G.held[k]], 16, Color.WHITE, false)); cb.add_child(h); cb.add_child(K.lbl(C.HELD_TD.get(H.k, ""), 12, K.DIM)); box.add_child(p)
	box.add_child(K.btn("Back", func(): K.close_panel(), true))
func remind_panel(e: Dictionary, back: Callable) -> void:   # relearn any move learned up to this level (free), replacing one
	var box := K.panel(back); var st := {"pick": null}
	var render := func(self_ref: Callable) -> void:
		K.clear(box)
		K.panel_title(box, "Move Reminder")
		box.add_child(K.lbl(("Pick a move %s learned before." % C.SP[e.id].n) if st.pick == null else ("Pick a move to forget for %s." % C.mv(st.pick).n), 13, K.DIM))
		var list := []
		if st.pick == null:
			for m in C.learned_by(e.id, e.lv): if not e.mv.has(m) and (C.move_use(m) != null or BT.skills().has(m)): list.append(m)
			list.sort_custom(func(a, b): return C.move_value(a, e.id) > C.move_value(b, e.id))
		else: list = e.mv
		for m in list:
			var p := K.card(0, func():
				if st.pick == null:
					st.pick = m
					if e.mv.size() < 4: e.mv.append(m); C.save(); K.close_panel(); return
					self_ref.call(self_ref)
				else:
					e.mv[e.mv.find(m)] = st.pick; C.save(); Snd.sfx("lvl"); K.close_panel())
			var cb := K.card_box(p); cb.alignment = BoxContainer.ALIGNMENT_BEGIN
			var h := K.hbox(4); h.add_child(K.type_tag(C.mv(m).t)); h.add_child(K.lbl(C.mv(m).n, 16, Color.WHITE, false)); cb.add_child(h); cb.add_child(K.lbl(C.move_desc(m), 12, K.DIM)); box.add_child(p)
		box.add_child(K.btn("Back", func(): K.close_panel(), true))
	render.call(render)
func tool_panel(e: Dictionary, back: Callable) -> void:   # use a Mint or Bottle Cap on a Pokémon (outside battle only)
	var b := K.panel(back); K.panel_title(b, "Use an item"); var iv: Array = C.ivs_of(e)
	for k in G.tools.keys():
		if G.tools[k] <= 0: continue
		var T: Dictionary = C.DB.dex.tools[k]
		var p := K.boxp(); var v := K.vbox(3); p.add_child(v); b.add_child(p)
		var h := K.hbox(4); h.add_child(K.item_icon(k)); h.add_child(K.lbl("%s x %d" % [T.n, G.tools[k]], 16, Color.WHITE, false)); v.add_child(h)
		if T.kind == "mint":
			v.add_child(K.lbl("Stats change as if its nature were " + C.nat_label(T.nat), 12, K.DIM))
			if C.nat_of(e) == T.nat: v.add_child(K.lbl("Already has this effect.", 12, K.DIM))
			else: v.add_child(K.btn("Use", func(): G.tools[k] -= 1; e.mint = 0 if T.nat == e.nat else T.nat; C.save(); Snd.sfx("lvl"); K.toast("%s's stats changed: %s" % [C.SP[e.id].n, C.nat_label(T.nat)], e.id); K.close_panel(), false, true))
		elif T.kind == "bottle-cap":
			v.add_child(K.lbl("Pick a stat to raise to 31:", 12, K.DIM)); var f := K.flow(4); v.add_child(f)
			for i in 6:
				var sbn := K.btn("%s %d" % [C.STATN[i], iv[i]], func():
					if iv[i] < 31: G.tools[k] -= 1; e.ht[i] = 1; C.save(); Snd.sfx("lvl"); K.toast("%s's %s is now as if its IV were 31" % [C.SP[e.id].n, C.STATN[i]], e.id); K.close_panel(), iv[i] == 31, true)
				f.add_child(sbn)
		else:
			v.add_child(K.lbl("Raises every stat to IV 31", 12, K.DIM))
			if iv.min() == 31: v.add_child(K.lbl("All IVs are already 31.", 12, K.DIM))
			else: v.add_child(K.btn("Use", func(): G.tools[k] -= 1; e.ht = [1, 1, 1, 1, 1, 1]; C.save(); Snd.sfx("lvl"); K.toast("%s's IVs are all 31 now" % C.SP[e.id].n, e.id); K.close_panel(), false, true))
	b.add_child(K.btn("Back", func(): K.close_panel(), true))
func sketch_panel(e: Dictionary, slot: int, back: Callable) -> void:   # Sketch: swap it for any move a Pokémon you've seen learns by level
	var box := K.panel(back); var ids := {}
	for id in G.seen:
		if not C.SP.has(id): continue
		for x in C.SP[id].ls:
			var m: int = x[1] if x is Array else x
			if (C.move_use(m) != null or BT.skills().has(m)) and not e.mv.has(m): ids[m] = 1
	var list: Array = ids.keys(); list.sort_custom(func(a, b): return C.mv(a).n < C.mv(b).n)
	K.panel_title(box, "Sketch"); box.add_child(K.lbl("%s can copy one of %d moves from the Pokémon you've seen. Sketch is replaced by it." % [C.SP[e.id].n, list.size()], 13, K.DIM))
	var f := LineEdit.new(); f.placeholder_text = "Search moves"; box.add_child(f)
	var wrap := K.vbox(4); box.add_child(wrap)
	var draw := func(q: String) -> void:
		K.clear(wrap)
		var n := 0
		for m in list:
			if n >= 80: break
			if q != "" and not C.mv(m).n.to_lower().contains(q.to_lower()): continue
			n += 1
			var p := K.card(0, func(): e.mv[slot] = m; C.save(); K.toast("%s sketched %s!" % [C.SP[e.id].n, C.mv(m).n]); back.call())
			var cb := K.card_box(p); cb.alignment = BoxContainer.ALIGNMENT_BEGIN
			var h := K.hbox(4); h.add_child(K.type_tag(C.mv(m).t)); h.add_child(K.lbl(C.mv(m).n, 16, Color.WHITE, false)); cb.add_child(h); cb.add_child(K.lbl(C.move_desc(m), 12, K.DIM)); wrap.add_child(p)
	f.text_changed.connect(draw); draw.call("")

# ---------- Pokédex ----------
func habitat(id: int) -> Array:   # where a species turns up: same rules the wave builder uses
	var m: Dictionary = C.SP[id]; var out := []
	for i in C.DB.ts.size():
		var S: Dictionary = C.DB.ts[i]; var hit := false
		for x in m.t: if S.types.has(x): hit = true
		if not hit: continue
		var T = null; var g: int = C.map_group(i) * 25
		for t in range(1, C.MAXTIER + 1):
			var h: float = C.threat_tier(i, t)
			if m.get("lg", 0):
				if h >= 5 and m.bst <= 480 + h * 25 and (m.lg == 1 or h >= 10): T = t; break
			elif m.bst <= 300 + h * 30 + g and m.bst >= min(110 + h * 30 + g, 480) and (h >= 3 or m.cr > 45): T = t; break
		if T != null: out.append([S.name, T, "boss" if m.get("lg", 0) else ""])
	out.sort_custom(func(a, b): return a[1] < b[1])
	return out
func hub_dex(body: VBoxContainer) -> void:
	var all := []
	for m in C.DB.dex.mon: if m.anim: all.append(m)
	var seen := 0; var own := 0
	for m in all:
		if G.seen.has(m.id): seen += 1
		if G.own.has(m.id): own += 1
	body.add_child(K.lbl("Seen %d - recruited %d - of %d" % [seen, own, all.size()], 13, K.DIM))
	var gt := K.flow(4); body.add_child(gt)
	for g in range(1, 10): gt.add_child(K.btn("Gen %d" % g, func(): gen = g; show_hub("dex"), gen != g, true))
	var grid := K.grid(); body.add_child(grid)
	for m in all:
		if m.get("g", 0) != gen: continue
		var s: bool = G.seen.has(m.id)
		var c := K.card(80, (func(): dex_panel(m.id)) if s else null, G.own.has(m.id)); var cb := K.card_box(c)
		cb.add_child(_center(K.lbl("#%04d" % m.id, 11, K.DIM)))
		var ic := K.icon(m.id, 40); ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if not s: ic.modulate = Color(0, 0, 0, 0.45)
		cb.add_child(ic); cb.add_child(_center(K.lbl(m.n if s else "???", 13)))
		if G.own.has(m.id): cb.add_child(_center(K.lbl("recruited", 11, K.DIM)))
		grid.add_child(c)
func dex_panel(id: int) -> void:
	var m: Dictionary = C.SP[id]; var box := K.panel()
	var head := K.hbox(10); box.add_child(head); head.add_child(K.icon(id, 64))
	var hv := K.vbox(3); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(hv)
	hv.add_child(K.lbl("#%d %s" % [id, m.n], 22, K.GOLD)); hv.add_child(_types_flow_left(m.t))
	hv.add_child(K.lbl("HP %d - Atk %d - Def %d - SpA %d - SpD %d - Spe %d (total %d)" % [m.b[0], m.b[1], m.b[2], m.b[3], m.b[4], m.b[5], m.bst], 12, K.DIM))
	var abs_ := []
	for x in m.get("ab", []): if C.DB.dex.abil.has(x[0]): abs_.append(C.DB.dex.abil[x[0]].n + (" (hidden)" if x[1] else ""))
	box.add_child(_info_box("Abilities", ", ".join(abs_)))
	var pre = m.f if (m.get("f", 0) and C.SP.has(m.f)) else 0; var nxt := []
	for v in m.ev: if C.SP.has(v.to): nxt.append(C.SP[v.to].n)
	if pre or nxt.size(): box.add_child(_info_box("Evolution", (("From %s. " % C.SP[pre].n) if pre else "") + (("Evolves into " + ", ".join(nxt)) if nxt.size() else "")))
	var h := habitat(id); var hs := []
	for x in h.slice(0, 8): hs.append("%s (tier %d+%s)" % [x[0], x[1], ", as the boss" if x[2] != "" else ""])
	var txt: String = (", ".join(hs) + ((", and %d more" % (h.size() - 8)) if h.size() > 8 else "")) if h.size() else "Not found on any route as a wild Pokémon."
	if nxt.size(): txt += " Also shows up when its evolved form is knocked out."
	box.add_child(_info_box("Where to find it", txt))
	box.add_child(K.lbl("You have recruited it." if G.own.has(id) else "Knock it out and it may ask to join.", 13, K.DIM))
	box.add_child(K.btn("Close", func(): K.close_panel(), true))
func _info_box(title: String, txt: String) -> PanelContainer:
	var p := K.boxp(); var v := K.vbox(2); p.add_child(v); v.add_child(K.lbl(title)); v.add_child(K.lbl(txt, 12, K.DIM)); return p

# ---------- Rescue Points tree: 8 branches of paths from a root (like Monkey Knowledge) ----------
func hub_rescue(body: VBoxContainer) -> void:
	var T: Dictionary = C.DB.tree
	if rbr == null: rbr = T.branches[0].id
	var own := 0
	for n in T.nodes: if G.tree.has(n.id): own += 1
	body.add_child(K.lbl("Rescue Points come from clearing maps (more on higher tiers). %d to spend - %d/%d bought." % [G.rp, own, T.nodes.size()], 13, K.DIM))
	var tabs := K.flow(4); body.add_child(tabs)
	for b in T.branches:
		var have := 0; var all := 0
		for n in T.nodes:
			if n.br == b.id:
				all += 1
				if G.tree.has(n.id): have += 1
		tabs.add_child(K.btn("%s %d/%d" % [b.name, have, all], func(): rbr = b.id; show_hub("rescue"), rbr != b.id, true))
	var br = null
	for b in T.branches: if b.id == rbr: br = b
	body.add_child(K.lbl(br.blurb, 13, K.DIM))
	var paths := []; var pidx := {}
	for n in T.nodes:
		if n.br != br.id: continue
		if not pidx.has(n.path): pidx[n.path] = paths.size(); paths.append({"name": n.path, "nodes": []})
		paths[pidx[n.path]].nodes.append(n)
	for p in paths:
		body.add_child(K.lbl("Start" if p.name == "root" else p.name, 15, K.GOLD))
		var line := K.flow(6); body.add_child(line)
		for n in p.nodes:
			var st := "own" if G.tree.has(n.id) else (("buy" if G.rp >= n.cost else "poor") if C.node_open(n) else "lock")
			var c := K.card(150, (func():
				if C.buy_node(n): Snd.sfx("lvl"); show_hub("rescue")) if st == "buy" else null, st == "own", st == "lock")
			var cb := K.card_box(c); cb.add_child(_center(K.lbl(n.name, 14))); cb.add_child(_center(K.lbl(n.desc, 11, K.DIM)))
			cb.add_child(_center(K.lbl("owned" if st == "own" else "%d RP" % n.cost, 13, Color("#9f9") if st == "own" else (K.GOLD if st == "buy" else K.DIM))))
			line.add_child(c)
	var rc: int = C.reset_cost()
	if rc > 0:
		body.add_child(K.btn("Reset tree (₽%s)" % _num(rc), func():
			var b := K.panel(); K.panel_title(b, "Reset the Rescue tree?"); b.add_child(K.lbl("All %d points come back to spend again. Costs ₽%s." % [C.tree_spent(), _num(rc)]))
			var h := K.hbox(); b.add_child(h)
			h.add_child(K.btn("Reset", func():
				if C.reset_tree(): K.close_panel(false); show_hub("rescue")
				else: K.toast("Not enough ₽")))
			h.add_child(K.btn("Keep", func(): K.close_panel(), true)), true, true))

# ---------- shop and bag ----------
func _buy(price: int, store: String, id) -> void:
	if G.money < price: K.toast("Not enough ₽"); return
	G.money -= price; G[store][id] = G[store].get(id, 0) + 1; C.save(); Snd.sfx("place"); show_hub("shop")
func hub_shop(body: VBoxContainer) -> void:
	body.add_child(K.lbl("Evolution items. Earn ₽ by clearing routes; higher tiers pay more.", 13, K.DIM))
	var g := K.grid(); body.add_child(g); var price: int = C.shop_price(2500)
	for id in C.DB.dex.items:
		var name = C.DB.dex.items[id]
		if not name: continue
		var users := []
		for m in C.DB.dex.mon:
			for v in m.ev: if v.get("item", 0) == id: users.append(m.n); break
		var c := K.card(150, func(): _buy(price, "items", id)); var cb := K.card_box(c)
		cb.add_child(K.item_icon(id)); cb.add_child(_center(K.lbl(name, 15)))
		cb.add_child(_center(K.lbl(", ".join(users.slice(0, 4)) + ("..." if users.size() > 4 else ""), 12, K.DIM))); cb.add_child(_center(K.lbl("₽%d - have %d" % [price, G.items.get(id, 0)], 13)))
		g.add_child(c)
	body.add_child(K.lbl("Held items", 18, K.GOLD)); body.add_child(K.lbl("Choice items, Life Orb and Expert Belt are only found on tier 6+ routes.", 13, K.DIM))
	var g2 := K.grid(); body.add_child(g2)
	for id in C.DB.dex.held:
		var H: Dictionary = C.DB.dex.held[id]; var pr: int = C.held_price(H.k)
		if not pr: continue
		pr = C.shop_price(pr)
		var c := K.card(150, func(): _buy(pr, "held", id)); var cb := K.card_box(c)
		cb.add_child(K.item_icon(id)); cb.add_child(_center(K.lbl(H.n, 15))); cb.add_child(_center(K.lbl(C.HELD_TD.get(H.k, ""), 12, K.DIM))); cb.add_child(_center(K.lbl("₽%s - have %d" % [_num(pr), G.held.get(id, 0)], 13)))
		g2.add_child(c)
	body.add_child(K.lbl("Natures & IVs", 18, K.GOLD)); body.add_child(K.lbl("Use them from a Pokémon's page, outside battle. A Mint changes how its nature affects stats; a Bottle Cap raises one stat as if its IV were 31.", 13, K.DIM))
	var g3 := K.grid(); body.add_child(g3)
	for id in C.DB.dex.tools:
		var T: Dictionary = C.DB.dex.tools[id]; var pr: int = C.shop_price(C.TOOL_PRICE[T.kind])
		var desc: String = (C.nat_label(T.nat).split(" ", true, 1)[1] if C.nat_label(T.nat).contains(" ") else C.nat_label(T.nat)) if T.kind == "mint" else ("One IV to 31" if T.kind == "bottle-cap" else "All IVs to 31")
		var c := K.card(150, func(): _buy(pr, "tools", id)); var cb := K.card_box(c)
		cb.add_child(K.item_icon(id)); cb.add_child(_center(K.lbl(T.n, 15))); cb.add_child(_center(K.lbl(desc, 12, K.DIM))); cb.add_child(_center(K.lbl("₽%s - have %d" % [_num(pr), G.tools.get(id, 0)], 13)))
		g3.add_child(c)
func hub_bag(body: VBoxContainer) -> void:
	var ks := []; var hs := []; var tsk := []
	for k in G.items: if G.items[k] > 0: ks.append(k)
	for k in G.held: if G.held[k] > 0: hs.append(k)
	for k in G.tools: if G.tools[k] > 0: tsk.append(k)
	body.add_child(K.lbl("Use items from a Pokémon's page in the Box." if (ks.size() or hs.size()) else "Your bag is empty.", 13, K.DIM))
	var row := func(k, name: String, n: int, desc := "") -> void:
		var p := K.boxp(); var v := K.vbox(2); p.add_child(v); var h := K.hbox(4); h.add_child(K.item_icon(k)); h.add_child(K.lbl("%s x %d" % [name, n], 16, Color.WHITE, false)); v.add_child(h)
		if desc != "": v.add_child(K.lbl(desc, 12, K.DIM))
		body.add_child(p)
	for k in ks: row.call(k, C.DB.dex.items[k], G.items[k])
	if tsk.size():
		body.add_child(K.lbl("Mints & Bottle Caps (use them from a Pokémon's page)", 16, K.GOLD))
		for k in tsk: row.call(k, C.DB.dex.tools[k].n, G.tools[k])
	if hs.size():
		body.add_child(K.lbl("Held items (give them from a Pokémon's page)", 16, K.GOLD))
		for k in hs: row.call(k, C.DB.dex.held[k].n, G.held[k], C.HELD_TD.get(C.DB.dex.held[k].k, ""))
	body.add_child(K.btn("Delete save", func():
		var b := K.panel(); K.panel_title(b, "Delete your save?"); b.add_child(K.lbl("This can't be undone."))
		var h := K.hbox(); b.add_child(h)
		h.add_child(K.btn("Delete", func(): DirAccess.remove_absolute(C.SAVE_PATH); C.G = C.new_save(); K.close_panel(false); show_title()))
		h.add_child(K.btn("Keep", func(): K.close_panel(), true)), true, true))

# ---------- options ----------
func options_panel(after: Callable) -> void:
	var b := K.panel(after); K.panel_title(b, "Options")
	var opt_row := func(title: String, hint: String, label: String, on: bool, cb: Callable) -> void:
		var p := K.boxp(); var v := K.vbox(3); p.add_child(v); b.add_child(p)
		var h := K.hbox(6); h.add_child(K.lbl(title, 16, Color.WHITE, false)); h.add_child(K.btn(label, cb, not on, true)); v.add_child(h)
		if hint != "": v.add_child(K.lbl(hint, 12, K.DIM))
	opt_row.call("60 fps", "Smooth motion; 30 fps is a bit cooler but choppier", "On" if G.opts.get("fps60", true) else "Off (30 fps)", G.opts.get("fps60", true), func():
		G.opts.fps60 = not G.opts.get("fps60", true); C.save(); get_node("/root/Main").apply_fps(); options_panel(after))
	opt_row.call("Lower resolution", "Draws fewer pixels so the phone stays much cooler", "On" if G.opts.get("lowres", true) else "Off", G.opts.get("lowres", true), func():
		G.opts.lowres = not G.opts.get("lowres", true); C.save()
		if hud: hud.layout()
		options_panel(after))
	opt_row.call("Sound", "", "Off" if G.opts.get("mute", false) else "On", not G.opts.get("mute", false), func():
		G.opts.mute = not G.opts.get("mute", false); Snd.set_mute(G.opts.mute); C.save(); options_panel(after))
	var p := K.boxp(); var v := K.vbox(3); p.add_child(v); b.add_child(p)
	v.add_child(K.lbl("Menu size")); v.add_child(K.lbl("Buttons, text and panels (the map is not affected)", 12, K.DIM))
	var f := K.flow(4); v.add_child(f)
	for k in ["s", "m", "l", "xl"]:
		f.add_child(K.btn(UISIZE[k][0], func(): G.opts.ui = k; C.save(); apply_ui_size(); options_panel(after), G.opts.get("ui", "m") != k, true))
	var cv := K.boxp(); var cvv := K.vbox(2); cv.add_child(cvv); b.add_child(cv)
	cvv.add_child(K.lbl("Code version %d" % Engine.get_meta("code_v", 1), 13, K.DIM))
	b.add_child(K.btn("Close", func(): K.close_panel(), true))

# ---------- team (max 10) ----------
func show_team() -> void:
	var s := show_screen("team"); art_bg(s, 2)
	team = []
	for u in G.get("team", []):
		for e in G.box: if e.u == u and team.size() < 10: team.append(u)
	var v := K.vbox(0); v.set_anchors_preset(Control.PRESET_FULL_RECT); s.add_child(v)
	var bar := K.hbox(10); var mc := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top"]: mc.add_theme_constant_override(k, 10)
	mc.add_child(bar); v.add_child(mc)
	bar.add_child(K.lbl("%s - Tier %d" % [C.DB.ts[route.set].name, route.tier], 18, K.GOLD, false))
	var cnt := K.lbl("", 18, Color.WHITE, false); bar.add_child(cnt)
	var body := Control.new(); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; v.add_child(body)
	var inner := scroll_body(body)
	var g := K.grid(); inner.add_child(g)
	var bottom := K.hbox(8); bottom.alignment = BoxContainer.ALIGNMENT_END; var mb := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_bottom", "margin_top"]: mb.add_theme_constant_override(k, 10)
	mb.add_child(bottom); v.add_child(mb)
	bottom.add_child(K.btn("◀ Back", func(): show_hub("routes"), true))
	var go := K.btn("Start ▶", func(): G.team = team.duplicate(); C.save(); begin_battle()); bottom.add_child(go)
	var sync := func(): cnt.text = "Team %d/10" % team.size(); go.disabled = team.is_empty()
	var l: Array = G.box.duplicate(); l.sort_custom(func(a, b): return a.lv > b.lv)
	# built once: a tap only flips that card and the counter
	for e in l:
		var holder := {}
		var c := mon_card(e, func():
			var on := team.has(e.u)
			if on: team.erase(e.u)
			elif team.size() < 10: team.append(e.u)
			else: return
			var st: StyleBoxFlat = holder.c.get_theme_stylebox("panel").duplicate(); st.border_color = K.GOLD if not on else K.WINB; st.set_border_width_all(3 if not on else 2); holder.c.add_theme_stylebox_override("panel", st)
			sync.call(), team.has(e.u))
		holder.c = c; g.add_child(c)
	sync.call()

# ---------- battle ----------
func begin_battle() -> void:
	var s := show_screen("battle")
	hud = load("res://scripts/hud.gd").new(); hud.ui = self; s.add_child(hud)
	var tm := []
	for u in team:
		for e in G.box: if e.u == u: tm.append(e)
	hud.start(route.set, route.tier, route.seed, tm)

# ---- swipe-to-scroll for every list (lives here, not in kit.gd: autoload scripts start before a code patch loads, so they can't be patched)
# (buttons and cards inside a list used to swallow the swipe) ----
# A press inside a ScrollContainer that then moves more than 10 px becomes a scroll: the button under the
# finger gets a "let go outside" so it doesn't fire, and the list follows the finger with a short glide after.
var _sw = null; var _sw_fake := false; var _gl_sc: ScrollContainer = null; var _gl_v := Vector2.ZERO
func _scroll_under(c: Node) -> ScrollContainer:
	while c != null:
		if c is ScrollContainer and not c.has_meta("own_drag"): return c
		c = c.get_parent()
	return null
# the list under a finger, found from where it touched (on a phone there's no mouse "hover" before a touch)
func _scroll_at(p: Vector2) -> ScrollContainer:
	var root: Node = K.modal if is_instance_valid(K.modal) else get_tree().root   # with a popup open, only its lists
	var best: ScrollContainer = null; var st: Array = [root]
	while st.size():
		var n: Node = st.pop_back()
		if n is CanvasItem and not n.visible: continue
		if n is ScrollContainer and not n.has_meta("own_drag") and n.get_global_rect().has_point(p): best = n   # later in the tree = drawn on top / nested deeper
		var ch := n.get_children(); ch.reverse(); st.append_array(ch)
	return best
func _input(ev: InputEvent) -> void:
	if _sw_fake: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_gl_sc = null
			var sc := _scroll_at(ev.position)
			_sw = null if sc == null else {"sc": sc, "p": ev.position, "h": sc.scroll_horizontal, "v": sc.scroll_vertical, "on": false, "lp": ev.position, "t": Time.get_ticks_msec(), "vel": Vector2.ZERO}
		elif _sw != null:
			if _sw.on:
				get_viewport().set_input_as_handled()
				if is_instance_valid(_sw.sc): _gl_sc = _sw.sc; _gl_v = _sw.vel
			_sw = null
	elif ev is InputEventMouseMotion and _sw != null:
		if not is_instance_valid(_sw.sc): _sw = null; return
		var sc: ScrollContainer = _sw.sc
		var d: Vector2 = ev.position - _sw.p
		var hz := sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED; var vt := sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
		if not _sw.on:
			if (absf(d.y) < 10 or not vt) and (absf(d.x) < 10 or not hz): return
			_sw.on = true
			var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = Vector2(-9999, -9999); up.global_position = up.position
			_sw_fake = true; get_viewport().push_input(up); _sw_fake = false   # the button under the finger lets go without firing
		get_viewport().set_input_as_handled()
		if vt: sc.scroll_vertical = int(_sw.v - d.y)
		if hz: sc.scroll_horizontal = int(_sw.h - d.x)
		var now := Time.get_ticks_msec(); var dt: float = max(1, now - _sw.t) / 1000.0
		var step: Vector2 = ev.position - _sw.lp
		_sw.vel = _sw.vel.lerp(-step / dt, 0.5); _sw.lp = ev.position; _sw.t = now
func _glide(dt: float) -> void:
	if _gl_sc == null: return
	if not is_instance_valid(_gl_sc) or _gl_v.length() < 20: _gl_sc = null; return
	if _gl_sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: _gl_sc.scroll_vertical = int(_gl_sc.scroll_vertical + _gl_v.y * dt)
	if _gl_sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: _gl_sc.scroll_horizontal = int(_gl_sc.scroll_horizontal + _gl_v.x * dt)
	_gl_v *= pow(0.03, dt)
func _process(dt: float) -> void: _glide(dt); _prune_panel_fits()
# every popup (K.panel) hooks a size handler onto the menu layer and never removes it; once the popup is gone that handler
# points at freed nodes, and a resize (changing the UI size, resizing the window on PC) ran all of them: errors, or a crash.
# kit.gd can't be patched, so the dead ones are dropped here: only the open popup's own handler is kept.
func _prune_panel_fits() -> void:
	if K.root == null or not is_instance_valid(K.root): return
	var cons: Array = K.root.get_signal_connection_list("resized")
	if cons.size() <= 1: return
	var keep = K.modal.get_meta("fit") if is_instance_valid(K.modal) and K.modal.has_meta("fit") else null
	for c in cons:
		var cb: Callable = c.callable
		if cb.is_custom() and (keep == null or cb != keep): K.root.resized.disconnect(cb)
# ---- heavy waves (every 5th): the bulkiest third of the map's Pokémon (at least 6), and each heavy wave draws from the
# next 3 of them in strength order (weakest first), so every heavy wave brings new species, stronger as the map goes on; they also grow with the map.
# Built after the battle code's own waves (with their own random numbers, so the other waves stay exactly the same).
# The HTML version (battle.js reworkHeavy) does the same with the same numbers.
func heavy_pool(SI: Dictionary) -> Array:
	var bulk: Array = BT.stable_sort(SI.pool, func(m): return -(m.b[0] + m.b[2]))
	return bulk.slice(0, max(6, ceili(SI.pool.size() / 3.0)))
func rework_heavy(set_idx: int, tier0: int, seed: int) -> void:
	var B: Dictionary = BT.B; var W: int = B.waves.size()
	var SI: Dictionary = BT.spawn_info(set_idx, tier0); var tier: float = SI.tier; var H := heavy_pool(SI)
	var G4: Array = C.MAPGROUP[C.map_group(set_idx)]
	var lr: Array = BT.lv_range(tier); var base: int = min(98, lr[0]); var top: int = min(100, lr[1])
	var R = MG.Rng.new(seed ^ 0x4ea7)
	var byB: Array = BT.stable_sort(H, func(m): return m.bst); var K := int(floor((W - 1) / 5.0))   # weakest to strongest; K heavy waves
	for w in range(5, W, 5):
		var f := w / float(W); var lv := int(floor(base + (top - base) * pow(f, 1.3) + 0.5)); var k := w / 5 - 1
		var st: int = max(0, int(floor(k * (byB.size() - 3) / float(K - 1) + 0.5))) if K > 1 else 0
		var picks: Array = byB.slice(st, st + 3)   # a window of 3 that walks from the weakest to the strongest
		var n := int(floor((3 + tier * 0.4 + w * 0.3) * G4[4] + 0.5))
		var list := []
		for i in n: list.append({"id": picks[int(floor(R.next() * picks.size()))].id, "lv": min(100, lv + 2), "gap": 1.6})
		B.waves[w - 1] = list
