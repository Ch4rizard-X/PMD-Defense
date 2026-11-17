extends Control
# Route Defense - the battle screen (ported from the HTML version's ui.js battle parts):
# the map (drawn by view.gd into its own viewport), the one-row top bar, the boss bar, the team row over the map,
# the info panel, the damage meter, weather / pause / join / results windows, and touch input (place, pinch, pan).
var ui                                   # ui.gd
var vp: SubViewport; var view: Node2D; var map_rect: TextureRect
var bar: PanelContainer; var barrow: HBoxContainer; var wprog: ColorRect; var wprog_bg: ColorRect
var hl: Label; var hc: Label; var hw: Label
var bgo: Button; var bsp: Button; var bau: Button; var bwx: Button; var bmt: Button
var bossbar: VBoxContainer; var boss_name: RichTextLabel; var boss_fill: ColorRect; var boss_trail: ColorRect; var boss_bg: ColorRect
var teamsv: ScrollContainer; var teamrow: HBoxContainer; var tcards := {}
var tinfo: PanelContainer; var tinfo_v: VBoxContainer
var meter: PanelContainer; var meter_v: VBoxContainer; var met_tab := "dmg"; var met_open = null
var zoom := 1.0; var zc = null
var hud_space := 54.0
var B: Dictionary:
	get: return BT.B
var G: Dictionary:
	get: return C.G
const FINGER := 70.0   # on touch, the placement preview sits this many screen pixels above the fingertip

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); mouse_filter = Control.MOUSE_FILTER_IGNORE
func start(set_idx: int, tier: int, seed: int, team: Array) -> void:
	zoom = 1.0; zc = null
	var vs := get_viewport_rect().size; var portrait := vs.y > vs.x
	var bgc := ColorRect.new(); bgc.color = Color("#0a1430"); bgc.set_anchors_preset(Control.PRESET_FULL_RECT); bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bgc)
	BT.legend_boss = C.legends_of(set_idx) if ui.route.get("legend", false) else []
	BT.start_battle(set_idx, tier, seed, team, portrait, play_aspect(), bool(ui.route.get("night", false))); ui._xp_seen = {}; ui.shorten_waves(tier); ui.rework_heavy(set_idx, tier, seed)
	BT.wave_started.connect(wave_banner); BT.wave_started.connect(func(): _wave_music.call_deferred()); BT.ask_join.connect(func(): ask_join.call_deferred()); BT.finished.connect(func(): show_result.call_deferred())
	vp = SubViewport.new(); vp.transparent_bg = false; vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(vp)
	view = load("res://scripts/view.gd").new(); vp.add_child(view)
	map_rect = TextureRect.new()
	# night: the map's darkness and lights are drawn by view.gd (the old blue tint is now its shadow colour)
	map_rect.texture = vp.get_texture(); map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(map_rect)
	var input := Control.new(); input.set_anchors_preset(Control.PRESET_FULL_RECT); input.mouse_filter = Control.MOUSE_FILTER_STOP; input.gui_input.connect(_on_input); add_child(input)
	build_hud()
	resized.connect(layout)
	ui.apply_fps()
	(func(): layout(); _fix_aspect(); layout()).call_deferred()   # measure the top bar first, then shape the map to the space under it
func _fix_aspect() -> void:   # make the map in the shape of the space under the top bar (the team row floats over the map)
	var a := play_aspect()
	if absf(a - B.aspect) > 0.01: B.aspect = a; B.M = MG.gen_map(B.set, B.portrait, B.seed, null, a, B.tier)
# PC (Windows) screens are big: the top bar floats over the map instead of taking a strip above it
func _bar_over() -> bool: return OS.has_feature("pc")
func play_aspect() -> float:
	var vs := get_viewport_rect().size; var h: float = max(1, vs.y - (0.0 if _bar_over() else hud_space))
	return max(vs.x, h) / max(1, min(vs.x, h))

# ---------- the top bar ----------
func build_hud() -> void:
	bar = PanelContainer.new(); var st := K.sb(Color(10 / 255.0, 26 / 255.0, 74 / 255.0, 0.85), Color(1, 1, 1, 0.25), 2, 10, 4); st.content_margin_bottom = 7
	bar.add_theme_stylebox_override("panel", st); bar.position = Vector2(6, 6); add_child(bar)
	var bv := K.vbox(2); bar.add_child(bv)
	barrow = K.hbox(6); bv.add_child(barrow)
	hl = _stat("♥", Color("#ff6b6b")); hc = _stat("$", K.GOLD); hw = _stat("Wave", Color.WHITE)
	bgo = K.btn("GO ▶", func(): BT.start_wave(), false, true); barrow.add_child(bgo)
	bsp = K.btn("1x", func(): B.speed = 2 if B.speed == 1 else (3 if B.speed == 2 else 1); bsp.text = "%dx" % B.speed, true, true); barrow.add_child(bsp)
	bau = K.btn("Auto: off", func():
		B.auto = not B.auto; bau.text = "Auto: " + ("on" if B.auto else "off")
		if B.auto: BT.start_wave(), true, true); barrow.add_child(bau)
	bwx = K.btn("Weather", weather_panel, true, true); barrow.add_child(bwx)
	bmt = K.btn("Meter", func(): G.opts.meter = not G.opts.get("meter", false); C.save(); meter_show(), true, true); barrow.add_child(bmt)
	var bmn := K.btn("", pause_menu, true, true); bmn.icon = K.glyph("menu", 16).texture; bmn.expand_icon = false; bmn.add_theme_constant_override("icon_max_width", 18); barrow.add_child(bmn)
	var wp := Control.new(); wp.custom_minimum_size = Vector2(0, 3); bv.add_child(wp)
	wprog_bg = ColorRect.new(); wprog_bg.color = Color(1, 1, 1, 0.15); wprog_bg.set_anchors_preset(Control.PRESET_FULL_RECT); wp.add_child(wprog_bg)
	wprog = ColorRect.new(); wprog.color = K.GOLD; wprog.position = Vector2.ZERO; wprog.size = Vector2(0, 3); wp.add_child(wprog)
	for c in barrow.get_children(): c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# boss bar
	bossbar = K.vbox(2); bossbar.visible = false; bossbar.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(bossbar)
	boss_name = K.rich("", 16); boss_name.custom_minimum_size = Vector2(260, 0); bossbar.add_child(boss_name)
	boss_name.add_theme_constant_override("outline_size", 6); boss_name.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.12))   # dark outline: readable on any tileset
	var bb := Control.new(); bb.custom_minimum_size = Vector2(260, 12); bossbar.add_child(bb)
	var frame := ColorRect.new(); frame.color = Color(0.02, 0.04, 0.12); frame.set_anchors_preset(Control.PRESET_FULL_RECT); frame.offset_left = -2; frame.offset_top = -2; frame.offset_right = 2; frame.offset_bottom = 2; bb.add_child(frame)   # dark frame around the bar
	boss_bg = ColorRect.new(); boss_bg.color = Color(0, 0, 0, 0.7); boss_bg.set_anchors_preset(Control.PRESET_FULL_RECT); bb.add_child(boss_bg)
	boss_trail = ColorRect.new(); boss_trail.color = Color(1, 1, 1, 0.5); bb.add_child(boss_trail)
	boss_fill = ColorRect.new(); boss_fill.color = Color("#ff4040"); bb.add_child(boss_fill)
	# team row (floats over the bottom of the map; scrolls sideways when it's long)
	teamsv = ScrollContainer.new(); teamsv.set_meta("own_drag", true); teamsv.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; teamsv.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var tst := K.sb(Color(11 / 255.0, 31 / 255.0, 92 / 255.0, 0.8), Color(223 / 255.0, 234 / 255.0, 1, 0.53), 2, 12, 4)
	var tpc := PanelContainer.new(); tpc.add_theme_stylebox_override("panel", tst); tpc.name = "TeamPanel"; add_child(tpc)
	tpc.add_child(teamsv); teamrow = K.hbox(4); teamsv.add_child(teamrow)
	tpc.mouse_filter = Control.MOUSE_FILTER_STOP; tpc.gui_input.connect(func(ev): _row_input(ev, null))
	teamsv.mouse_filter = Control.MOUSE_FILTER_PASS; teamrow.mouse_filter = Control.MOUSE_FILTER_PASS
	# info panel
	tinfo = PanelContainer.new(); tinfo.add_theme_stylebox_override("panel", K.win_sb(2, 10, 8)); tinfo.visible = false; add_child(tinfo)
	tinfo_v = K.vbox(4); tinfo.add_child(tinfo_v)
	build_team()
	meter_show()
func _stat(icon: String, col: Color) -> Label:
	var h := K.hbox(3); h.add_child(K.lbl(icon, 16, col, false)); var v := K.lbl("", 16, Color.WHITE, false); h.add_child(v); barrow.add_child(h); return v
func build_team() -> void:
	K.clear(teamrow)
	tcards = {}
	for e in B.team:
		var c := PanelContainer.new(); c.custom_minimum_size = Vector2(64, 0); c.mouse_filter = Control.MOUSE_FILTER_STOP
		var v := K.vbox(0); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.add_child(v)
		var stripe := ColorRect.new(); stripe.color = C.TCOL[C.SP[e.id].t[0]]; stripe.custom_minimum_size = Vector2(0, 3); stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(stripe)
		var top := Control.new(); top.custom_minimum_size = Vector2(56, 42); top.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(top)
		var ic := K.icon(e.id, 42); ic.position = Vector2(7, 0); top.add_child(ic)
		ui._badges(top, e)
		if BT.sees_why(e) != null: top.add_child(ui.eye_badge(true))
		var tl := K.lbl("", 11, Color.WHITE, false); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(tl)
		c.gui_input.connect(func(ev): _row_input(ev, e))
		teamrow.add_child(c); tcards[e.u] = {"c": c, "tl": tl, "ic": ic, "id": e.id, "e": e}
	refresh_hud(); layout.call_deferred()
# heavy waves (every 5th): every wild Pokémon has double HP. Midboss waves (every 10th): the midboss (the wave's one
# entry marked "mid", 3 levels above the rest) gets double HP, the boss HP bar, boss resistances and rewards, costs 10
# lives if it gets through (the final boss: 20). The whole midboss wave plays the boss song (_wave_music).
# battle.gd can't be patched, so new arrivals are powered up here the frame they appear.
var _hv_seen := 0
# early tiers were too easy (the user's call): wild Pokémon, bosses included, get 30% more HP up to threat tier 3
# (Beginner tiers 1-5, Intermediate tier 1), fading to none at threat tier 6 (Beginner tier 11, Intermediate tier 7)
static func early_hp_at(th: float) -> float: return 1.0 + 0.3 * clampf((6.0 - th) / 3.0, 0.0, 1.0)
func early_hp() -> float: return early_hp_at(B.th)
func _heavy_hook() -> void:
	if B.phase != "wave": return
	var heavy: bool = B.wave % 5 == 0 and B.wave != B.waves.size()
	var mid = null
	if heavy:
		for x in B.waves[B.wave - 1]: if x.get("mid", 0): mid = x
	var em := early_hp()
	for e in B.en:
		if e.eid > _hv_seen:
			_hv_seen = max(_hv_seen, e.eid)
			if em > 1.0: e.hp = int(e.hp * em); e.max = int(e.max * em)
			if B.th >= 2.9 and not e.hide and C.SP[e.id].t.has(7): e.hide = true   # Ghosts hide from Beginner tier 5 (app builds before v26 used 3)
			if heavy:
				e.hp *= 2; e.max *= 2
				if mid != null and e.id == mid.id and e.lv == mid.lv and not e.get("mid", false):
					e.mid = true; e.boss = true; e.lives = 10
# the level-up sound plays one at a time: while it's still playing, new ones (fast upgrades, several level-ups at once)
# are skipped. snd.gd can't be patched, so its 'last played' time for that sound is kept current while it plays.
var _lvl_path := ""
func _hold_lvl_sfx() -> void:
	if _lvl_path == "":
		var f = C.DB.snd.sfx.get("lvl", null)
		if f == null: return
		_lvl_path = "res://snd/%s.mp3" % f
	for p in Snd.fx:
		if p.playing and p.stream != null and p.stream.resource_path == _lvl_path:
			Snd.last["lvl"] = Time.get_ticks_msec(); return
# team row: swipe anywhere on it to scroll (with a little glide); a tap that didn't move picks the card
var _rdrag = null; var _rvel := 0.0
func _mv_is(t, m) -> bool: return _mv_open.size() == 2 and is_same(_mv_open[0], t) and _mv_open[1] == m
var _mv_open := []   # [tower, move id] whose description is shown in the info panel
func _row_input(ev: InputEvent, e) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _rdrag = {"x": ev.global_position.x, "s": teamsv.scroll_horizontal, "moved": false, "lx": ev.global_position.x, "t": Time.get_ticks_msec()}; _rvel = 0.0
		elif _rdrag != null:
			var tap: bool = not _rdrag.moved; _rdrag = null
			if tap and e != null: Snd.sfx("tap"); _team_tap(e)
	elif ev is InputEventMouseMotion and _rdrag != null:
		var dx: float = ev.global_position.x - _rdrag.x
		if not _rdrag.moved and absf(dx) < 10: return
		_rdrag.moved = true
		teamsv.scroll_horizontal = int(_rdrag.s - dx)
		var now := Time.get_ticks_msec(); var dt: float = max(1, now - _rdrag.t) / 1000.0
		_rvel = lerpf(_rvel, -(ev.global_position.x - _rdrag.lx) / dt, 0.5); _rdrag.lx = ev.global_position.x; _rdrag.t = now
func _row_glide(dt: float) -> void:
	if _rdrag != null or absf(_rvel) < 20: _rvel = 0.0 if _rdrag == null else _rvel; return
	teamsv.scroll_horizontal = int(teamsv.scroll_horizontal + _rvel * dt); _rvel *= pow(0.02, dt)
func _team_tap(e: Dictionary) -> void:
	for t in B.towers:
		if is_same(t.e, e): B.sel = t; B.placing = null; tower_info(); return
	B.placing = null if (B.placing != null and is_same(B.placing, e)) else e; B.sel = null; tower_info(); refresh_hud()

var _last_lives := -1; var _boss_ref = null; var _bt := 1.0
func refresh_hud() -> void:
	if B == null: return
	hl.text = str(B.lives); hc.text = str(B.cash); hw.text = "%d/%d" % [B.wave, B.waves.size()]
	if _last_lives >= 0 and B.lives < _last_lives:
		var tw := hl.create_tween(); hl.modulate = Color(1, 0.3, 0.3); tw.tween_property(hl, "modulate", Color.WHITE, 0.4)
	_last_lives = B.lives
	# wave progress: how much of this wave is left (still to come + still alive)
	var wv: Array = B.waves[max(0, B.wave - 1)] if B.waves.size() else []; var left := 0
	if B.phase == "wave":
		left = B.q.size()
		for e in B.en: if e.hp > 0: left += 1
	var f = (max(0, 1.0 - left / float(wv.size())) if (B.phase == "wave" and wv.size()) else (1.0 if (B.phase == "build" and B.wave) else 0.0))
	wprog.size = Vector2(wprog_bg.size.x * f, 3)
	var boss = null
	for e in B.en: if e.boss and e.hp > 0 and e.d > 0: boss = e; break
	bossbar.visible = boss != null
	if boss:
		var lg: bool = C.SP[boss.id].get("lg", 0)
		boss_name.text = "[center]%s%s [font_size=12]Lv %d[/font_size][/center]" % ["[color=#ffd84a]LEGENDARY[/color] " if lg else ("[color=#ff9a3c]MIDBOSS[/color] " if boss.get("mid", false) else ""), C.SP[boss.id].n, boss.lv]
		var fr: float = boss.hp / float(boss.max)
		_bt = max(fr, _bt - 0.01) if (_boss_ref != null and is_same(_boss_ref, boss)) else fr; _boss_ref = boss
		boss_fill.size = Vector2(260 * fr, 12); boss_trail.size = Vector2(260 * _bt, 12)
	bgo.disabled = B.phase != "build"
	var wt := "Weather"
	if B.weather: wt = BT.WEATHER[B.weather.k][0] + (" (boss)" if B.weather.has("boss") else " - %d %s" % [BT.waves_left(), "wave" if BT.waves_left() == 1 else "waves"])
	if bwx.text != wt: bwx.text = wt
	for u in tcards:
		var T: Dictionary = tcards[u]; var e: Dictionary = T.e; var tw = null
		for t in B.towers: if is_same(t.e, e): tw = t
		var sel: bool = (B.placing != null and is_same(B.placing, e)) or (B.sel != null and is_same(B.sel.e, e))
		var poor: bool = tw == null and B.cash < C.place_cost(e)
		var key := "%s%s%s" % [tw != null, sel, poor]
		if T.get("k", "") != key:
			T.k = key
			var st := K.sb(Color(20 / 255.0, 48 / 255.0, 120 / 255.0, 0.95) if tw == null else Color(30 / 255.0, 80 / 255.0, 40 / 255.0, 0.95), K.GOLD if sel else Color(1, 1, 1, 0.3), 2 if not sel else 3, 8, 3)
			T.c.add_theme_stylebox_override("panel", st); T.c.modulate = Color(1, 1, 1, 0.55) if poor else Color.WHITE
		var txt := "Lv%d\n%s" % [e.lv, ("%d KO" % tw.kills) if tw != null else "$%d" % C.place_cost(e)]
		if T.tl.text != txt: T.tl.text = txt
		if T.id != e.id: T.id = e.id; var ni := K.icon(e.id, 42); ni.position = Vector2(7, 0); T.ic.replace_by(ni); T.ic.queue_free(); T.ic = ni   # evolved

# ---------- layout: the map fills the space under the top bar; the team row floats over its bottom edge ----------
func layout() -> void:
	if B == null or bar == null or not is_inside_tree(): return   # (a resize can arrive while the screen is being taken down)
	var vs := size if size.x > 0 else get_viewport_rect().size
	# the top bar is one row: if it's wider than the screen it shrinks to fit
	bar.scale = Vector2.ONE; bar.reset_size()
	var need := bar.get_combined_minimum_size().x
	var k: float = min(1.0, (vs.x - 12) / max(1, need)); bar.scale = Vector2(k, k)
	bar.position = Vector2((vs.x - need * k) / 2, 6)
	hud_space = bar.position.y + bar.get_combined_minimum_size().y * k + 4
	bossbar.position = Vector2((vs.x - 260) / 2, hud_space + 2)
	var M: Dictionary = B.M; var mw: float = M.W * 24; var mh: float = M.H * 24
	var top := 0.0 if _bar_over() else hud_space; var ah: float = vs.y - top   # on PC the top bar sits over the map
	var s0: float = min(vs.x / mw, ah / mh); var s := s0 * zoom
	if zc == null: zc = Vector2(mw / 2, mh / 2)
	var ox: float = vs.x / 2 - zc.x * s; var oy: float = top + ah / 2 - zc.y * s
	ox = (vs.x - mw * s) / 2 if mw * s <= vs.x else clampf(ox, vs.x - mw * s, 0)
	oy = top if mh * s <= ah else clampf(oy, vs.y - mh * s, top)   # the map sits right under the top bar
	zc = Vector2((vs.x / 2 - ox) / s, (top + ah / 2 - oy) / s)
	map_rect.position = Vector2(ox, oy); map_rect.size = Vector2(mw * s, mh * s)
	# Lower resolution: draw at the art's own resolution (one pixel per art pixel); otherwise at screen resolution
	var screen_k: float = get_viewport().get_final_transform().get_scale().x
	var q := 1.0 if G.opts.get("lowres", true) else clampf(s0 * screen_k, 1, 4)
	var want := Vector2i(int(mw * q), int(mh * q))
	if vp.size != want: vp.size = want
	view.scale = Vector2(q, q)
	# team row and info panel
	var tp: PanelContainer = get_node("TeamPanel")
	var rowmin := teamrow.get_combined_minimum_size()
	teamsv.custom_minimum_size = Vector2(min(rowmin.x, vs.x - 12 - 8), rowmin.y)   # exactly the cards' width (scrolls when it's wider than the screen)
	tp.size = Vector2.ZERO; var th := tp.get_combined_minimum_size().y
	tp.reset_size(); th = tp.size.y
	var map_end: float = min(oy + mh * s0 * (1.0 if zoom == 1.0 else 0.0) + (mh * s if zoom != 1.0 else 0.0), vs.y) if zoom == 1.0 else vs.y
	map_end = min(oy + mh * s, vs.y) if zoom == 1.0 else vs.y
	tp.position = Vector2((vs.x - tp.size.x) / 2, map_end - th - 6)
	tinfo.custom_minimum_size.x = min(520, vs.x - 16); _team_top = tp.position.y
	_place_tinfo(); _settle_tinfo()   # and again two frames later: wrapped rows only know their height once their width is set
	if meter: _meter_place()
var _team_top := 0.0
var _settle_n := 0
func _open_tinfo() -> void:
	if not tinfo.visible: tinfo.modulate.a = 0.0   # only on first opening: hidden until it has its final size (refreshes while open stay visible)
	tinfo.visible = true
	layout()
func _settle_tinfo() -> void:
	_settle_n += 1; var my := _settle_n
	await get_tree().process_frame; await get_tree().process_frame
	if my != _settle_n or not is_instance_valid(tinfo): return
	_place_tinfo(); tinfo.modulate.a = 1.0
func _sort_now(n: Node) -> void:
	if n is Container: n.notification(Container.NOTIFICATION_SORT_CHILDREN)
	elif n is Label: n.notification(Control.NOTIFICATION_RESIZED); n.update_minimum_size()
	for c in n.get_children(): _sort_now(c)
func _place_tinfo() -> void:
	if not is_instance_valid(tinfo): return
	var inner: float = tinfo.custom_minimum_size.x - 16
	for c in tinfo_v.get_children():   # wrapping text gets its real width up front, so it never measures one letter per line
		if c is Label and c.autowrap_mode != TextServer.AUTOWRAP_OFF: c.custom_minimum_size.x = inner; c.size.x = inner
		elif c is FlowContainer or c is HBoxContainer: c.size.x = inner   # wrap rows measure their height at their current width
	tinfo_v.size.x = inner
	for i in 3:   # lay the panel out now instead of next frame, so its first height is already the real one
		tinfo.size = Vector2(tinfo.custom_minimum_size.x, 0); tinfo.reset_size(); _sort_now(tinfo)
	tinfo.size = Vector2(tinfo.custom_minimum_size.x, 0); tinfo.reset_size()
	var vs := size if size.x > 0 else get_viewport_rect().size
	tinfo.position = Vector2((vs.x - tinfo.size.x) / 2, _team_top - tinfo.size.y - 6)
func _process(dt: float) -> void:
	if B == null: return
	_row_glide(dt); _hold_lvl_sfx(); _heavy_hook()
	BT.tick(min(0.05, dt))
	if B.asks.size() and K.modal == null: ask_join()
	_hud_t -= dt
	if _hud_t <= 0:
		_hud_t = 0.15; refresh_hud()
		if B.sel:
			var key := "%d:%d:%d:%s:%s" % [B.sel.e.lv, B.sel.kills, B.sel.e.id, str(B.sel.up), str([B.cash >= BT.upgrade_cost(B.sel, 0), B.cash >= BT.upgrade_cost(B.sel, 1), B.cash >= BT.upgrade_cost(B.sel, 2)])]
			if _tk != key: _tk = key; tower_info()
		elif B.get("selE") != null: tower_info()
		_need_w = bar.get_combined_minimum_size().x
		if absf(_need_w - _last_w) > 2: _last_w = _need_w; layout()
	_meter_t -= dt
	if _meter_t <= 0 and meter and meter.visible and not _meter_hold: _meter_t = 0.5; meter_draw(meter_v, met_tab, false)
var _hud_t := 0.0; var _tk := ""; var _need_w := 0.0; var _last_w := 0.0; var _meter_t := 0.0

# ---------- info panel: the selected Pokémon (or wild one, or the one being placed) ----------
func tower_info() -> void:
	K.clear(tinfo_v)
	var t = B.sel
	if B.placing != null and t == null:
		var e: Dictionary = B.placing; var ty: Array = C.SP[e.id].t; var qs := []
		for q in C.quirks(e.id): qs.append(q[0] + ": " + q[1])
		var txt := "%s - tap the map to place ($%d). %s." % [C.SP[e.id].n, C.place_cost(e), ". ".join(qs)]
		if ty.has(10) or ty.has(9): txt += " Can stand in %s." % ("water" if ty.has(10) else "lava")
		if not B.has("land"): B.land = BT.land_kind(B.set)
		var lp := {"grass": ty.has(11), "rock": ty.has(5) or ty.has(4) or ty.has(1), "ice": ty.has(14)}
		if lp.get(B.land, false): txt += " " + BT.TERRAIN_TXT[B.land] + " anywhere on this map's land."
		if (ty.has(10) and B.M.liq == "water") or (ty.has(9) and B.M.liq == "lava"): txt += " " + BT.TERRAIN_TXT["pond" if ty.has(10) else "lava"] + " in the %s." % ("water" if ty.has(10) else "lava")
		tinfo_v.add_child(K.lbl(txt, 14)); _open_tinfo(); return
	if t == null and B.get("selE") != null and B.selE.hp > 0:
		var x: Dictionary = B.selE; var s: Dictionary = C.SP[x.id]; var A = C.DB.dex.abil.get(x.ab, null)
		var tags := []
		if x.air: tags.append("Flying: cuts corners, Ground moves miss")
		if x.hide: tags.append("Hidden: needs a Psychic or Ghost type, Foresight, Odor Sleuth, Miracle Eye, Keen Eye or Frisk nearby")
		if x.dig: tags.append("Digs: underground only Earthquake / Magnitude / Fissure hit")
		if x.armor: tags.append("Armoured: moves under 60 power do half")
		if x.boss: tags.append("Boss")
		if x.get("shiny", false): tags.append("Shiny")
		if x.get("alpha", false): tags.append("Alpha: 3x HP, perfect IVs, 3x likelier to join")
		if x.has("rival"): tags.append("%s (rival rescue team): 2x HP, faster, costs 5 lives if it gets through" % x.rival)
		var h := K.hbox(4); tinfo_v.add_child(h)
		h.add_child(K.lbl("Wild %s Lv %d" % [s.n, x.lv], 16, Color.WHITE, false))
		for ty in s.t: h.add_child(K.type_tag(ty))
		var ab := ""
		if A: ab = " - " + A.n + ((": " + C.AB_TD[A.k].substr(6)) if (C.AB_TD.has(A.k) and C.AB_TD[A.k].begins_with("Wild")) else "")
		tinfo_v.add_child(K.lbl("HP %d/%d%s" % [ceil(x.hp), x.max, ab], 13))
		if tags.size(): tinfo_v.add_child(K.lbl(" - ".join(tags), 12, K.DIM))
		_open_tinfo(); return
	if t == null: tinfo.visible = false; return
	var e: Dictionary = t.e; var s: Dictionary = C.SP[e.id]; var A = C.DB.dex.abil.get(e.ab, null); var H = C.DB.dex.held.get(e.it, null)
	var tg := []
	if BT.sees(t): tg.append("Sees hidden")
	if A and C.AB_TD.has(A.k) and not C.AB_TD[A.k].begins_with("Wild"): tg.append(A.n)
	if H: tg.append(H.n)
	var h := K.hbox(4); tinfo_v.add_child(h)
	h.add_child(K.lbl("%s Lv %d - %d KOs" % [s.n, e.lv, t.kills], 16, Color.WHITE, false))
	for ty in s.t: h.add_child(K.type_tag(ty))
	if tg.size(): tinfo_v.add_child(K.lbl(" - ".join(tg), 12, K.DIM))
	tinfo_v.add_child(ui.qk_line(e.id))
	var tpk: String = BT.terrain_perk(t)
	if tpk != "": tinfo_v.add_child(K.lbl(BT.TERRAIN_TXT[tpk], 12, Color("#7ee08a")))   # terrain perk it stands on
	var x0: int = C.xp_for(s.gr, e.lv); var x1: int = C.xp_for(s.gr, e.lv + 1) if e.lv < C.MAXLV else e.xp
	var xr := K.hbox(6); tinfo_v.add_child(xr)
	var xp := ProgressBar.new(); xp.show_percentage = false; xp.custom_minimum_size = Vector2(120, 6); xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER; xp.max_value = 100
	xp.value = 100 if e.lv >= C.MAXLV else clampf((e.xp - x0) / float(max(1, x1 - x0)), 0, 1) * 100; xr.add_child(xp)
	xr.add_child(K.lbl("Max level" if e.lv >= C.MAXLV else "%s XP to Lv %d" % [ui._num(x1 - e.xp), e.lv + 1], 12, K.DIM, false))
	var mvs := K.flow(3); tinfo_v.add_child(mvs)
	for m in e.mv:   # tap a move to read what it does (tap again to hide)
		var chip := K.type_tag(C.mv(m).t, C.mv(m).n); chip.mouse_filter = Control.MOUSE_FILTER_STOP
		if _mv_is(t, m): chip.get_theme_stylebox("panel").border_color = Color.WHITE; chip.get_theme_stylebox("panel").set_border_width_all(2)
		chip.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				Snd.sfx("tap"); _mv_open = [] if _mv_is(t, m) else [t, m]; tower_info())
		mvs.add_child(chip)
	if _mv_open.size() and is_same(_mv_open[0], t) and e.mv.has(_mv_open[1]):
		var md := K.lbl("%s: %s" % [C.mv(_mv_open[1]).n, C.move_desc(_mv_open[1])], 12, K.DIM); tinfo_v.add_child(md)
	var ups := K.flow(4); tinfo_v.add_child(ups)
	for k in 3:
		var lv: int = t.up[k]; var c: int = BT.upgrade_cost(t, k)
		var b := K.btn("", func():
			if BT.buy_upgrade(t, k): tower_info(); refresh_hud()
			else: K.toast("Not enough battle cash"), not (c and B.cash >= c), true)
		b.disabled = c == 0; ups.add_child(b)
		# level dots are drawn, not text: the font has no ● / ○, and the fallback fonts drew them at different sizes
		var col: Color = b.get_theme_color("font_disabled_color" if b.disabled else "font_color")
		var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(cc)
		var bv := K.vbox(1); bv.mouse_filter = Control.MOUSE_FILTER_IGNORE; cc.add_child(bv)
		var top := K.hbox(4); top.alignment = BoxContainer.ALIGNMENT_CENTER; top.mouse_filter = Control.MOUSE_FILTER_IGNORE; bv.add_child(top)
		var nl := K.lbl(BT.UPG.n[k], 16, col, false); top.add_child(nl)
		var dots := UpDots.new(); dots.n = lv; dots.of = BT.UPG.max; dots.col = col; top.add_child(dots)
		var cl := K.lbl(("$%d (+%d%%)" % [c, int(round(BT.UPG.step * 100))]) if c else "Max", 16, col, false); cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; bv.add_child(cl)
		b.custom_minimum_size = bv.get_combined_minimum_size() + Vector2(12, 10)
	# Empowerment Seed: once per battle (a Mega / Primal where SpriteCollab animates one, otherwise Awakening)
	if not B.get("empowered", false):
		var emp := K.flow(4); tinfo_v.add_child(emp)
		var mg: Array = ui.megas_ready(t.e)   # Mega Evolution needs its own Mega Stone held (Rayquaza: none)
		for mid in mg: emp.add_child(K.btn("Empower: %s" % C.SP[mid].n, func(): BT.empower(t, mid); tower_info(), false, true))
		if mg.is_empty(): emp.add_child(K.btn("Empower (Awaken)", func(): BT.empower(t); tower_info(), false, true))
		var cm: Array = C.megas_of(t.e.id)
		if mg.is_empty() and cm.size(): tinfo_v.add_child(K.lbl("Holding %s would let it Mega Evolve instead" % ui.STONE_NAME.get(ui.stone_for(cm[0]), "its Mega Stone"), 12, K.DIM))
	elif t.get("awk", false): tinfo_v.add_child(K.lbl("Awakened: 30% more damage and attack speed", 12, Color("#ffd84a")))
	elif t.e.has("mega_from") and C.SP[t.e.id].get("form", "") == "mega": tinfo_v.add_child(K.lbl("Empowered for this battle", 12, Color("#ffd84a")))
	var modes := K.flow(4); tinfo_v.add_child(modes)
	for kn in [["first", "First"], ["last", "Last"], ["strong", "Strong"], ["close", "Close"]]:
		modes.add_child(K.btn(kn[1], func(): t.mode = kn[0]; tower_info(), t.mode != kn[0], true))
	if BT.has_m(t, "Teleport"): modes.add_child(K.btn("Move (free)", func(): B.moving = t; B.swapping = null; K.toast("Tap where it should go"), false, true))
	if BT.has_m(t, "Ally Switch") and B.towers.size() > 1: modes.add_child(K.btn("Swap (free)", func(): B.swapping = t; B.moving = null; K.toast("Tap a teammate to swap with"), false, true))
	var dot := false
	for o in C.evo_options(e): if o.ok: dot = true
	if e.pend.size(): dot = true
	modes.add_child(K.btn("Moves / Evolve" + (" ●" if dot else ""), func():
		B.paused = true; ui.mon_panel(e, func():
			if BT.B: B.paused = false; tower_info(); refresh_hud()), true, true))
	modes.add_child(K.btn("Recall ($%d)" % int(floor(t.paid * 0.7)), func(): BT.sell_tower(t); tower_info(); refresh_hud(), true, true))
	_open_tinfo()

# ---------- windows ----------
func weather_panel() -> void:
	if B.over: return
	B.paused = true
	var b := K.panel(func(): if BT.B: B.paused = false)
	K.panel_title(b, "Weather")
	b.add_child(K.lbl("Costs $%d battle cash, lasts %d waves%s. You have $%d.%s" % [BT.weather_cost(), BT.weather_waves(), " (this one counts)" if B.phase == "wave" else "", B.cash, (" The boss's %s stays until it is knocked out." % BT.WEATHER[B.bwx.k][0]) if B.bwx else ""], 13, K.DIM))
	for k in BT.WEATHER:
		var c := K.card(0, func():
			if BT.buy_weather(k): K.close_panel()
			else: K.toast("Not enough battle cash"))
		var cb := K.card_box(c); cb.alignment = BoxContainer.ALIGNMENT_BEGIN; cb.add_child(K.lbl(BT.WEATHER[k][0])); cb.add_child(K.lbl(BT.WEATHER[k][1], 12, K.DIM)); b.add_child(c)
	b.add_child(K.btn("Close", func(): K.close_panel(), true))
func pause_menu() -> void:
	if B == null or B.over or B.paused: return
	B.paused = true
	var b := K.panel(func(): if BT.B: B.paused = false)
	K.panel_title(b, "Paused")
	var h := K.flow(6); b.add_child(h)
	h.add_child(K.btn("Resume", func(): K.close_panel()))
	h.add_child(ui._glyph_btn(K.btn("Options", func(): ui.options_panel(func(): if BT.B: B.paused = false), true), "gear"))
	h.add_child(K.btn("Give up", func(): K.close_panel(false); BT.finish(false), true))
func ask_join() -> void:   # a knocked-out wild Pokémon asks to join: the battle pauses and you decide
	if B == null or B.asks.is_empty() or K.modal != null or ui.screen != "battle": return
	if not BT.has_method("evo_half"):   # app builds before evolved heavies: half their asks are dropped here instead
		while B.asks.size() and B.get("evo_only", {}).has(B.asks[0].id) and not B.asks[0].get("evok", false):
			if randf() < 0.5: B.asks.pop_front()
			else: B.asks[0].evok = true
		if B.asks.is_empty(): return
	var a: Dictionary = B.asks.pop_front(); var s: Dictionary = C.SP[a.id]; var A = C.DB.dex.abil.get(a.ab, null); var moves: Array = C.best_moves(a.id, a.lv)
	B.paused = true
	var box := K.panel(func():
		if BT.B == null: return
		B.paused = false
		if B.asks.size(): ask_join.call_deferred()
		elif B.get("afterAsks"): var f: Callable = B.afterAsks; B.afterAsks = null; f.call(), true)
	var head := K.hbox(10); box.add_child(head); head.add_child(K.icon(a.id, 64))
	var hv := K.vbox(3); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(hv)
	hv.add_child(K.lbl("%s wants to join your team!" % s.n, 20, K.GOLD))
	var row := K.hbox(4); hv.add_child(row)
	var owned := 0
	for x in G.box: if x.id == a.id: owned += 1
	if owned:   # already have this species: a Poké Ball marker, like the main games' caught icon
		var op := PanelContainer.new(); op.add_theme_stylebox_override("panel", K.sb(Color(0.85, 0.2, 0.2, 0.85), Color(1, 0.8, 0.8), 1, 8, 2)); var oh := K.hbox(3); op.add_child(oh)
		oh.add_child(K.img("img/ui/pokeball.png", 14, 14)); oh.add_child(K.lbl("Owned" + (" x%d" % owned if owned > 1 else ""), 12, Color.WHITE, false)); row.add_child(op)
	row.add_child(K.lbl("Lv %d" % a.lv, 16, Color.WHITE, false))
	for ty in s.t: row.add_child(K.type_tag(ty))
	var tot := 0
	for v in a.iv: tot += v
	hv.add_child(K.lbl("%s nature - IVs %s (total %d/186)" % [C.nat_label(a.nat), " / ".join(a.iv.map(func(v): return str(v))), tot], 12, K.DIM))
	if A: hv.add_child(K.lbl("Ability: " + A.n + ((" - " + C.AB_TD[A.k]) if (C.AB_TD.has(A.k) and not C.AB_TD[A.k].begins_with("Wild")) else ""), 12, K.DIM))
	var mv := K.flow(3); hv.add_child(mv)
	for m in moves: mv.add_child(K.type_tag(C.mv(m).t, C.mv(m).n))
	hv.add_child(K.lbl("Box: %d Pokémon%s" % [G.box.size(), " - it would join this battle too" if B.team.size() < 10 else ""], 12, K.DIM))
	var h := K.hbox(6); box.add_child(h)
	h.add_child(K.btn("Accept", func():
		var e: Dictionary = C.make_mon(a.id, a.lv, a.nat, a.iv); e.ab = a.ab
		if a.get("shiny", false): e.shiny = true
		if a.get("alpha", false): e.alpha = true
		G.box.append(e); B.recruits.append(e)
		if B.team.size() < 10: B.team.append(e); build_team()
		K.toast("%s joined your team!" % s.n, a.id); C.save(); K.close_panel()))
	h.add_child(K.btn("Decline", func(): B.declined[a.id] = 1; K.close_panel(), true))
# heavy waves play Monster House, the last wave the boss song. Re-applied after the battle code finishes the frame:
# with Auto on, the old battle code (it can't be patched) started the next wave and then set the route song over it.
func _wave_music() -> void:
	if B == null or B.phase != "wave": return
	var last: bool = B.wave == B.waves.size()
	if B.wave % 10 == 0 and not last: Snd.play_music(("_e" if C.DB.ts[B.set].game == "E" else "_") + "boss")   # midboss wave: the boss song all wave
	elif B.wave % 5 == 0 and not last and C.DB.snd.music.has("_heavy"):   # heavy wave: Monster House, Explorers of Sky's or Red's at random
		var mh := ["_heavy"]
		if C.DB.snd.music.has("_heavy2") and ResourceLoader.exists("res://snd/%s.mp3" % C.DB.snd.music._heavy2): mh.append("_heavy2")
		Snd.play_music(mh[randi() % mh.size()])
	elif last:
		var leg := false; var bid = null
		for x in B.waves[B.wave - 1]:
			if x.get("boss", 0): bid = x.id; if C.SP[x.id].get("lg", 0): leg = true
		var k: String = ("_e" if C.DB.ts[B.set].game == "E" else "_") + ("legend" if leg else "boss")
		var own = C.DB.snd.get("bossTheme", {}).get(bid, null)
		if own != null and B.en.any(func(e): return e.boss and e.hp > 0): k = own   # the boss is out and has its own song
		Snd.play_music(k)
func wave_banner() -> void:   # banner across the map when a wave starts (heavy waves and the boss get their own)
	if B == null: return
	var w: Array = B.waves[B.wave - 1]; var boss = null
	for x in w: if x.get("boss", 0): boss = x
	var heavy: bool = B.wave % 5 == 0 and boss == null
	var p := PanelContainer.new(); var col := Color("#7a1010") if (boss and not C.SP[boss.id].get("lg", 0)) else (Color("#6a4a00") if boss else Color(10 / 255.0, 26 / 255.0, 74 / 255.0))
	p.add_theme_stylebox_override("panel", K.sb(Color(col, 0.85), K.GOLD if boss else K.WINB, 2, 10, 10)); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := K.hbox(10); p.add_child(h)
	if boss:
		h.add_child(K.icon(boss.id, 56)); var v := K.vbox(0); h.add_child(v)
		v.add_child(K.lbl("Legendary boss!" if C.SP[boss.id].get("lg", 0) else "Boss wave!", 24, K.GOLD, false)); v.add_child(K.lbl("%s Lv %d" % [C.SP[boss.id].n, boss.lv], 15, Color.WHITE, false))
	else:
		var v := K.vbox(0); h.add_child(v); v.add_child(K.lbl("Wave %d" % B.wave, 26, Color.WHITE, false))
		if heavy: v.add_child(K.lbl("Heavy wave: tough Pokémon", 14, K.DIM, false))
	add_child(p); p.reset_size(); p.position = Vector2((size.x - p.size.x) / 2, size.y * 0.32)
	p.modulate.a = 0; var tw := p.create_tween(); tw.tween_property(p, "modulate:a", 1.0, 0.2); tw.tween_interval(1.4); tw.tween_property(p, "modulate:a", 0.0, 0.3); tw.tween_callback(p.queue_free)
func show_result() -> void:
	if B.asks.size(): B.afterAsks = show_result; ask_join(); return   # answer join requests first
	var won: bool = B.phase == "win"; var box := K.panel(null, true)
	K.panel_title(box, "Route cleared!" if won else "The wild Pokémon got through...")
	var sub := K.lbl("%s - Tier %d - wave %d/%d - %d KOs" % [C.DB.ts[B.set].name, B.tier, B.wave, B.waves.size(), B.kills], 13, K.DIM); sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(sub)
	if won:
		var sr := K.hbox(6); sr.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_child(sr)
		for k in 3:
			var st := K.lbl("★", 40, K.GOLD if k < B.stars else Color(1, 1, 1, 0.2), false); sr.add_child(st)
			if k < B.stars: st.scale = Vector2.ZERO; st.pivot_offset = Vector2(14, 20); var tw := st.create_tween(); tw.tween_interval(0.25 + k * 0.3); tw.tween_property(st, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK); tw.tween_callback(func(): Snd.sfx("lvl"))
		if B.starRp: var sl := K.lbl("+%d Rescue Points for new stars" % B.starRp, 13, K.DIM); sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; box.add_child(sl)
	var rw := K.flow(6); rw.alignment = FlowContainer.ALIGNMENT_CENTER; box.add_child(rw)
	var c1: PanelContainer = ui._chip("img/ui/coin.png", "", "0"); rw.add_child(c1); _count_up(c1, B.reward)
	var c2: PanelContainer = ui._chip("img/ui/badge.png", "Rescue Points ", "0"); rw.add_child(c2); _count_up(c2, B.rp)
	if B.get("unlocked", false): rw.add_child(ui._chip("", "", "Tier %d unlocked on %s!" % [B.tier + 1, C.DB.ts[B.set].name]))
	if B.has("groupOpened"): rw.add_child(ui._chip("", "", "%s maps open!" % B.groupOpened))
	if B.has("mapOpened"): rw.add_child(ui._chip("", "", "New map: %s!" % B.mapOpened))
	if B.drop: rw.add_child(_item_chip(B.drop, C.DB.dex.items[B.drop]))
	if B.hdrop: rw.add_child(_item_chip(B.hdrop, C.DB.dex.held[B.hdrop].n))
	if B.phase == "win" and not B.has("tmdrop"): B.tmdrop = ui.tm_drop(B.th, B.team); C.save()
	if B.phase == "win" and not B.has("mdrop"): B.mdrop = ui.stone_drop(B.th); C.save()
	if B.get("mdrop", 0): rw.add_child(_item_chip(B.mdrop, C.DB.dex.held[B.mdrop].n))
	if B.get("tmdrop", 0):
		var tc: PanelContainer = ui._chip("", "", "TM %s" % C.mv(B.tmdrop).n); tc.get_child(0).add_child(ui.tm_icon(B.tmdrop)); tc.get_child(0).move_child(tc.get_child(0).get_child(-1), 0); rw.add_child(tc)
	if B.recruits.size():
		box.add_child(K.lbl("Joined your team", 18, K.GOLD)); var g := K.grid(); box.add_child(g)
		for e in B.recruits: g.add_child(ui.mon_card(e))
	box.add_child(K.lbl("Team", 18, K.GOLD)); var xs := K.grid(); box.add_child(xs)
	for e in B.team: var c: PanelContainer = ui.mon_card(e); K.card_box(c).add_child(ui._center(K.lbl("+%d XP" % B.xpLog.get(e.u, 0), 12, K.DIM))); xs.add_child(c)
	if B.meter.size():
		B.mtime = B.time; box.add_child(K.lbl("Damage meter", 18, K.GOLD)); var mb := K.vbox(2); box.add_child(mb); met_open = null; meter_draw(mb, "dmg", true)
	var h := K.flow(6); box.add_child(h)
	h.add_child(K.btn("Same route, new layout", func(): K.close_panel(false); ui.route.seed = randi() % 1000000000; ui.begin_battle()))
	h.add_child(K.btn("Back to routes", func(): K.close_panel(false); BT.B = null; ui.show_hub("routes"), true))
	if meter: meter.visible = false
	if grip: grip.visible = false
func _item_chip(id, name: String) -> PanelContainer:
	var c: PanelContainer = ui._chip("", "", name); c.get_child(0).add_child(ui.item_icon(id)); c.get_child(0).move_child(c.get_child(0).get_child(-1), 0); return c
func _count_up(chip: PanelContainer, to: int) -> void:
	var l: Label = chip.get_child(0).get_child(-1); var tw := chip.create_tween()
	tw.tween_method(func(k: float): l.text = ui._num(round(to * (1 - pow(1 - k, 3)))), 0.0, 1.0, 0.9)

# ---------- damage meter (Details!-style): Damage / Knockouts / Effects, tap a row for its move breakdown ----------
var _meter_hold := false; var _mdrag = null
func meter_show() -> void:
	if meter == null:
		meter = PanelContainer.new(); meter.add_theme_stylebox_override("panel", K.sb(Color(10 / 255.0, 26 / 255.0, 74 / 255.0, 0.82), Color(1, 1, 1, 0.25), 1, 8, 4))
		meter.custom_minimum_size = Vector2(150, 0); add_child(meter)
		meter_v = K.vbox(2); meter.add_child(meter_v)
		meter.gui_input.connect(_meter_input)
		grip = MeterGrip.new(); add_child(grip); grip.gui_input.connect(_grip_input)
	meter.visible = G.opts.get("meter", false) and not B.over; grip.visible = meter.visible
	_meter_place(); meter_draw(meter_v, met_tab, false)
func _meter_place() -> void:
	var P = G.opts.get("meterPos", null); var vs := size; meter.reset_size()
	var k: float = clampf(float(G.opts.get("meterScale", 1.0)), 0.7, 3.0); meter.scale = Vector2(k, k); var ms: Vector2 = meter.size * k
	if P == null: meter.position = Vector2(vs.x - ms.x - 6, hud_space + 4)
	else: meter.position = Vector2(clampf(P[0] * vs.x, 0, max(0, vs.x - ms.x)), clampf(P[1] * vs.y, 0, max(0, vs.y - min(ms.y, 60))))
	if grip: grip.position = meter.position + ms - grip.size; grip.visible = meter.visible   # inside the corner, so it never goes off-screen
# resize: drag the grip at the meter's bottom-right corner; the whole meter (text and icons) scales, and the size is saved
var grip: Control; var _gdrag = null
func _grip_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _gdrag = {"s": ev.global_position, "k": meter.scale.x, "w": meter.size.x * meter.scale.x}; _meter_hold = true
		else:
			if _gdrag: C.save()
			_gdrag = null; _meter_hold = false
		accept_event()
	elif ev is InputEventMouseMotion and _gdrag:
		var d: Vector2 = ev.global_position - _gdrag.s
		G.opts.meterScale = clampf(_gdrag.k * (_gdrag.w + (d.x + d.y) / 2.0) / _gdrag.w, 0.7, 3.0); _meter_place(); accept_event()
class MeterGrip extends Control:   # three diagonal lines, like a window's resize corner
	func _init() -> void: custom_minimum_size = Vector2(22, 22); size = custom_minimum_size; mouse_filter = Control.MOUSE_FILTER_STOP; mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	func _draw() -> void:
		for i in 3:
			var o := 6.0 + i * 5.0
			draw_line(Vector2(size.x - 3, size.y - 3 - o), Vector2(size.x - 3 - o, size.y - 3), Color(1, 0.85, 0.3, 0.95), 2.0, true)
func _meter_input(ev: InputEvent) -> void:   # drag the meter anywhere (a short tap still works on its tabs and rows)
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed: _mdrag = {"s": ev.global_position, "o": meter.position, "moved": false}; _meter_hold = true
		else:
			if _mdrag and _mdrag.moved: C.save()
			_mdrag = null; _meter_hold = false
	elif ev is InputEventMouseMotion and _mdrag:
		var d: Vector2 = ev.global_position - _mdrag.s
		if not _mdrag.moved and d.length() < 8: return
		_mdrag.moved = true; var p: Vector2 = _mdrag.o + d
		G.opts.meterPos = [p.x / size.x, p.y / size.y]; _meter_place(); accept_event()
func meter_draw(box: VBoxContainer, tab: String, full: bool) -> void:
	K.clear(box)
	var rows := []
	for u in B.meter:
		var m: Dictionary = B.meter[u]
		for e in G.box: if e.u == m.u: rows.append({"m": m, "e": e})
	var tot := {"dmg": 0, "ko": 0, "dot": 0, "ctl": 0.0}
	for r in rows: tot.dmg += r.m.dmg; tot.ko += r.m.ko; tot.dot += r.m.dot; tot.ctl += r.m.ctl
	var val := func(r) -> float: return float(r.m.dmg) if tab == "dmg" else (float(r.m.ko) if tab == "ko" else (r.m.ctl / tot.ctl if tot.ctl else 0.0) + (r.m.dot / float(tot.dot) if tot.dot else 0.0))
	rows.sort_custom(func(a, b): return val.call(a) > val.call(b))
	var tabs := K.hbox(2); box.add_child(tabs)
	for kn in ([["dmg", "Damage"], ["ko", "Knockouts"], ["fx", "Effects"]] if full else [["dmg", "Dmg"], ["ko", "KO"], ["fx", "Fx"]]):
		tabs.add_child(K.btn(kn[1], func(): met_tab = kn[0]; met_open = null; meter_draw(box, kn[0], full), kn[0] != tab, true))
	if rows.is_empty(): box.add_child(K.lbl("Nothing yet - place a Pokémon and start a wave.", 12, K.DIM)); return
	var mx: float = max(1e-9, val.call(rows[0])); var secs: float = max(1, B.get("mtime", B.time))
	var kf := func(v) -> String: return ("%.0fk" % (v / 1000.0) if v >= 100000 else "%.1fk" % (v / 1000.0)) if (not full and v >= 10000) else ui._num(v)
	for i in rows.size():
		var r = rows[i]; var m: Dictionary = r.m
		var pct := int(round(m.dmg / float(max(1, tot.dmg)) * 100)) if tab == "dmg" else (int(round(m.ko / float(max(1, tot.ko)) * 100)) if tab == "ko" else 0)
		var txt := ""
		if not full and tab == "dmg": txt = "%s %d%%" % [kf.call(m.dmg), pct]
		elif not full and tab == "fx": txt = "%ds%s" % [round(m.ctl), (" " + kf.call(m.dot)) if m.dot else ""]
		elif tab == "dmg": txt = "%s  %d/s  %d%%" % [ui._num(m.dmg), round(m.dmg / secs), pct]
		elif tab == "ko": txt = "%d  %d%%" % [m.ko, pct]
		else: txt = "%d s control%s" % [round(m.ctl), (" - %s over time" % ui._num(m.dot)) if m.dot else ""]
		var ic: int = (36 if full else 28) if _bar_over() else (28 if full else 20)   # the Pokémon's own sprite (box icons were barely visible); bigger on PC
		var row := Control.new(); row.custom_minimum_size = Vector2(0, max(ic, 26 if full else 18)); row.mouse_filter = Control.MOUSE_FILTER_STOP; box.add_child(row)
		var barc := ColorRect.new(); barc.color = Color(C.TCOL[C.SP[r.e.id].t[0]], 0.55); barc.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(barc)
		var fr: float = max(0.02, val.call(r) / mx)
		row.resized.connect(func(): barc.size = Vector2(row.size.x * fr, row.size.y))
		var h := K.hbox(4); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(h)
		var mi = K.anim_icon(C.sid(r.e), ic); mi.sc = 1.5; mi.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(mi)   # sprite frames have empty space around the Pokémon: zoom in
		var nm := K.lbl(("%d. " % (i + 1) if full else "") + C.SP[r.e.id].n + ("  MVP" if (full and i == 0 and tab == "dmg") else ""), 14 if full else 11, Color.WHITE, false); nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL; nm.clip_text = true; h.add_child(nm)
		h.add_child(K.lbl(txt, 14 if full else 11, Color.WHITE, false))
		row.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not (_mdrag and _mdrag.moved):
				met_open = null if met_open == m.u else m.u; meter_draw(box, tab, full))
		if met_open == m.u:
			var bd := K.vbox(1); box.add_child(bd)
			var br: Array = m.br.keys(); br.sort_custom(func(a, b): return m.br[a] > m.br[b])
			for k in br: bd.add_child(_kv(k, "%s (%d%%)" % [ui._num(m.br[k]), round(m.br[k] / float(max(1, m.dmg)) * 100)], full))
			bd.add_child(_kv("Control", "%d s" % round(m.ctl), full)); bd.add_child(_kv("Knockouts", str(m.ko), full))
	box.add_child(K.lbl(("Team: %s damage" % ui._num(tot.dmg)) if tab == "dmg" else (("Team: %d knockouts" % tot.ko) if tab == "ko" else "Control = seconds enemies spent stopped or slowed (stronger slows count more)"), 11 if not full else 13, K.DIM))
	if box == meter_v: (func(): if is_instance_valid(meter): meter.reset_size(); _meter_place()).call_deferred()
func _kv(k: String, v: String, full: bool) -> HBoxContainer:
	var h := K.hbox(4); var a := K.lbl(k, 12 if full else 10, K.DIM, false); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(a); h.add_child(K.lbl(v, 12 if full else 10, Color.WHITE, false)); return h

# ---------- touch / mouse on the map ----------
var _P := {}; var _pinch = null; var _panned := false; var _last_tap := 0
func to_map(p: Vector2) -> Vector2:
	var r := map_rect.get_rect(); var M: Dictionary = B.M
	return Vector2((p.x - r.position.x) / r.size.x * M.W * 24, (p.y - r.position.y) / r.size.y * M.H * 24)
func place_at(p: Vector2, touch: bool) -> Vector2:
	var m := to_map(p)
	if touch: m.y -= FINGER / (map_rect.size.x / (B.M.W * 24.0))
	return m
func set_ghost(p: Vector2, touch: bool) -> void:
	var m := place_at(p, touch)
	B.ghost = {"x": m.x, "y": m.y, "ok": BT.can_place(B.placing, m.x, m.y) and B.cash >= C.place_cost(B.placing) and B.towers.size() < 10}
func _on_input(ev: InputEvent) -> void:
	if B == null or B.paused: return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_P[ev.index] = {"p": ev.position, "s": ev.position}
			if _P.size() == 2:   # two fingers: pinch to zoom (cancels a placement drag)
				var ps := _P.values(); _pinch = {"d": ps[0].p.distance_to(ps[1].p), "z": zoom}; B.ghost = null; return
			_panned = false
			if B.placing != null: set_ghost(ev.position, true)
		else:
			var was := _P.size(); _P.erase(ev.index)
			if was >= 2:
				if _P.size() < 2: _pinch = null
				_panned = true; return
			if ev.canceled or _panned: B.ghost = null; return
			_tap(ev.position, true)
	elif ev is InputEventScreenDrag:
		if not _P.has(ev.index): return
		var p = _P[ev.index]; var d: Vector2 = ev.position - p.p; p.p = ev.position
		if _P.size() >= 2 and _pinch:
			var ps := _P.values(); var dist: float = ps[0].p.distance_to(ps[1].p); var mid: Vector2 = (ps[0].p + ps[1].p) / 2
			var f := to_map(mid)   # keep the map point under the fingers in place
			zoom = clampf(_pinch.z * dist / max(1, _pinch.d), 1, 3); layout()
			var f2 := to_map(mid); zc += (f - f2); zc -= d / 2 / (map_rect.size.x / (B.M.W * 24.0)); layout(); _panned = true; return
		if B.placing != null: set_ghost(ev.position, true); return
		if zoom > 1 and (_panned or ev.position.distance_to(p.s) > 8):   # one finger drags the zoomed map
			_panned = true; zc -= d / (map_rect.size.x / (B.M.W * 24.0)); layout()
	elif ev is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed:
				var f := to_map(ev.position); zoom = clampf(zoom * (1.15 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.15), 1, 3); layout(); zc += f - to_map(ev.position); layout()
			return
		if ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed: _tap(ev.position, false)
	elif ev is InputEventMouseMotion and not DisplayServer.is_touchscreen_available():
		if B.placing != null: set_ghost(ev.position, false)
func _tap(pos: Vector2, touch: bool) -> void:
	if B.get("moving") != null:   # Teleport: free move to a new spot
		var t = B.moving; var m := place_at(pos, touch); var ox: float = t.x; var oy: float = t.y; t.x = -999.0; t.y = -999.0; B.moving = null
		if BT.can_place(t.e, m.x, m.y): t.x = m.x; t.y = m.y; t.tp = null; Snd.sfx("place")
		else: t.x = ox; t.y = oy; K.toast("It can't go there")
		tower_info(); return
	if B.placing != null:
		var m := place_at(pos, touch)
		if BT.place_tower(B.placing, m.x, m.y) != null: B.sel = null; B.placing = null; B.ghost = null
		elif B.cash < C.place_cost(B.placing): K.toast("Not enough battle cash")
		tower_info(); refresh_hud(); return
	var now := Time.get_ticks_msec()
	if now - _last_tap < 300 and zoom > 1: _last_tap = 0; zoom = 1.0; zc = null; layout(); return   # double-tap: zoom back out
	_last_tap = now
	var m := to_map(pos); var tr := 30.0 if touch else 22.0; var best = null; var bd := tr
	for t in B.towers:
		var d := Vector2(t.x - m.x, t.y - 9 - m.y).length()
		if d < bd: bd = d; best = t
	if B.get("swapping") != null:   # Ally Switch
		var a = B.swapping; B.swapping = null
		if best != null and not is_same(best, a):
			var ax: float = a.x; var ay: float = a.y; a.x = best.x; a.y = best.y; best.x = ax; best.y = ay; a.tp = null; best.tp = null; Snd.sfx("place")
		tower_info(); return
	B.sel = best; B.selE = null
	if best == null:
		var be = null; var ed := tr - 2
		for e in B.en:
			var d := Vector2(e.x - m.x, e.y - ((12 if e.air else 0) + 6) * BT.ESPR - m.y).length()
			if e.hp > 0 and d < ed: ed = d; be = e
		B.selE = be
	tower_info(); refresh_hud()

class UpDots extends Control:   # upgrade level: n filled circles out of `of`, all the same size
	var n := 0; var of := 5; var col := Color.WHITE
	const R := 3.6; const GAP := 2.4
	func _get_minimum_size() -> Vector2: return Vector2(of * (R * 2 + GAP) - GAP, R * 2 + 2)
	func _draw() -> void:
		var cy := size.y / 2
		for i in of:
			var c := Vector2(R + i * (R * 2 + GAP), cy)
			if i < n: draw_circle(c, R, col)
			else: draw_arc(c, R - 0.75, 0, TAU, 20, col, 1.5, true)
