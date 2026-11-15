extends Node
# Route Defense - menu toolkit (autoload "K"): theme, buttons, cards, popups, toasts, icons.
# NOTE: autoloads (C, MG, BT, Snd, K) start before boot.gd loads a code patch, so changes to them only reach players with a new APK.
# Colours and shapes follow the HTML version's CSS.

const BG := Color("#0b1736"); const DIM := Color("#a9bce8"); const EDGE := Color("#8fb8ff"); const GOLD := Color("#ffd84a")
const WIN_T := Color("#2b56b8"); const WIN_B := Color("#16306f"); const WINB := Color("#dfeaff"); const WIND := Color("#0a1a4a")
const GREEN := Color("#3a8a3a"); const GEDGE := Color("#b9f5a5"); const ALT := Color("#2f55b4"); const ALTE := Color("#cfe0ff")
const TAB_ON := Color("#c58b25"); const TAB_ONE := Color("#ffe39a")
var font: Font
var theme: Theme
var root: Control          # the UI layer (full screen)
var modal: Control = null  # the open popup's overlay
var modal_cb = null
var toasts: VBoxContainer

func _ready() -> void:
	font = load("res://fonts/pmd.ttf")
	theme = Theme.new(); theme.default_font = font; theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_color("font_color", "Button", Color.WHITE)
	theme.set_color("font_hover_color", "Button", Color.WHITE); theme.set_color("font_pressed_color", "Button", Color.WHITE); theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.5))
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	theme.set_constant("separation", "VBoxContainer", 4); theme.set_constant("separation", "HBoxContainer", 4)
	theme.set_constant("h_separation", "HFlowContainer", 6); theme.set_constant("v_separation", "HFlowContainer", 6)

func sb(bg: Color, edge: Color, w := 2, r := 8, pad := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.border_color = edge; s.set_border_width_all(w); s.set_corner_radius_all(r)
	s.content_margin_left = pad; s.content_margin_right = pad; s.content_margin_top = pad; s.content_margin_bottom = pad
	s.anti_aliasing = true
	return s
func win_sb(w := 3, r := 12, pad := 14) -> StyleBoxFlat:
	var s := sb(WIN_T.lerp(WIN_B, 0.5), WINB, w, r, pad); s.shadow_color = Color(0, 0, 0, 0.5); s.shadow_size = 6; return s

# ---------- basic pieces ----------
func lbl(t: String, size := 16, col := Color.WHITE, wrap := true) -> Label:
	var l := Label.new(); l.text = t; l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # a wrapping label needs a width, or it wraps after every letter
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
func rich(t: String, size := 16) -> RichTextLabel:   # text with [b], [color] bits
	var r := RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = true; r.scroll_active = false; r.text = t
	r.add_theme_font_override("normal_font", font); r.add_theme_font_override("bold_font", font); r.add_theme_font_size_override("normal_font_size", size); r.add_theme_font_size_override("bold_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE; r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return r
func btn(t: String, on: Callable, alt := false, small := false) -> Button:
	var b := Button.new(); b.text = t; b.focus_mode = Control.FOCUS_NONE
	var bg := ALT if alt else GREEN; var ed := ALTE if alt else GEDGE
	var p := 4 if small else 8
	var n := sb(bg, ed, 2, 6, p); n.content_margin_left = 9 if small else 14; n.content_margin_right = n.content_margin_left
	var h := n.duplicate(); h.bg_color = bg.lightened(0.12)
	var d := n.duplicate(); d.bg_color = bg.darkened(0.15)
	var x := n.duplicate(); x.bg_color = bg.darkened(0.35); x.border_color = ed.darkened(0.4)
	b.add_theme_stylebox_override("normal", n); b.add_theme_stylebox_override("hover", h); b.add_theme_stylebox_override("pressed", d); b.add_theme_stylebox_override("disabled", x)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", 14 if small else 16)
	b.pressed.connect(func(): Snd.sfx("tap"); on.call())
	return b
func tab_btn(t: String, on: bool, cb: Callable) -> Button:
	var b := btn(t, cb, true)
	if on:
		var s := sb(TAB_ON, TAB_ONE, 2, 8, 8); b.add_theme_stylebox_override("normal", s); b.add_theme_stylebox_override("hover", s); b.add_theme_stylebox_override("pressed", s)
	return b
func vbox(sep := 4) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep); return v
func hbox(sep := 4) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", sep); return h
func flow(sep := 6) -> HFlowContainer:
	var f := HFlowContainer.new(); f.add_theme_constant_override("h_separation", sep); f.add_theme_constant_override("v_separation", sep); return f
func boxp(bg := Color(10 / 255.0, 26 / 255.0, 74 / 255.0, 0.4), edge := Color(1, 1, 1, 0.13), r := 8, pad := 6) -> PanelContainer:   # the HTML's .move box
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", sb(bg, edge, 1, r, pad)); return p
func type_tag(t: int, txt := "") -> PanelContainer:
	var p := PanelContainer.new(); var s := sb(C.TCOL[t], C.TCOL[t].darkened(0.25), 0, 10, 0)
	s.content_margin_left = 7; s.content_margin_right = 7; s.content_margin_top = 1; s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := lbl(txt if txt != "" else C.TYPES[t], 11, Color.WHITE, false); l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5)); l.add_theme_constant_override("shadow_offset_x", 1); l.add_theme_constant_override("shadow_offset_y", 1)
	p.add_child(l); return p
func type_row(types: Array) -> HBoxContainer:
	var h := hbox(2); h.alignment = BoxContainer.ALIGNMENT_CENTER; h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in types: h.add_child(type_tag(t))
	return h
func img(p: String, w := 16, h := 16) -> TextureRect:
	var t := TextureRect.new(); t.texture = C.tex(p); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(w, h); t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; t.mouse_filter = Control.MOUSE_FILTER_IGNORE; return t
func glyph(name: String, h := 16) -> TextureRect:   # the HTML's 👁 ⚙ ☰ (Android's Noto glyphs, as images: the pixel font doesn't have them)
	var t := img("img/ui/%s.png" % name, h, h); t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if t.texture: t.custom_minimum_size = Vector2(h * t.texture.get_width() / float(t.texture.get_height()), h)
	return t
func item_icon(k) -> TextureRect:   # PMD Red's own icon where it has one, else the bag sprite
	var f = C.DB.icons.get(int(k), null)
	return img("img/item/%s.png" % f, 20, 20) if f else img("", 0, 0)

# one frame from the shared icon sheet
func icon(id: int, size := 48) -> TextureRect:
	var t := TextureRect.new(); t.custom_minimum_size = Vector2(size, size); t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var I: Dictionary = C.DB.micons; var n = I.i.get(id, null)
	if n == null: return t
	var a := AtlasTexture.new(); a.atlas = C.tex("img/ui/monicons.png")
	a.region = Rect2((n % I.cols) * I.c, (n / I.cols) * I.c, I.c, I.c); t.texture = a
	return t

# a Pokémon's idle animation playing in a small box
class MonIcon extends Control:
	var id := 0; var t := 0.0; var sc := 1.0
	func _process(dt: float) -> void: t += dt; queue_redraw()
	func _draw() -> void:
		var A = C.DB.anim.get(id, null)
		if A == null: return
		var name := "Idle" if A.has("Idle") else "Walk"; var a = A[name]; var im := C.mon_tex(id)
		if im == null: return
		var tot := 0
		for v in a.d: tot += v
		var ft = int(t * 60) % max(1, tot); var f := 0
		while f < a.n - 1 and ft >= a.d[f]: ft -= a.d[f]; f += 1
		var s: float = min(size.x / a.fw, size.y / a.fh) * sc
		draw_texture_rect_region(im, Rect2((size.x - a.fw * s) / 2, (size.y - a.fh * s) / 2, a.fw * s, a.fh * s), Rect2(f * a.fw, a.y, a.fw, a.fh))
func anim_icon(id: int, size := 72) -> Control:
	var m := MonIcon.new(); m.id = id; m.custom_minimum_size = Vector2(size, size); m.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; m.mouse_filter = Control.MOUSE_FILTER_IGNORE; return m

# a tappable card (the HTML's .card)
func card(w := 104, on = null, picked := false, locked := false) -> PanelContainer:
	var p := PanelContainer.new(); p.custom_minimum_size = Vector2(w, 0); p.set_meta("base_w", w)
	var s := sb(WIN_T.lerp(WIN_B, 0.45), GOLD if picked else WINB, 3 if picked else 2, 10, 6)
	p.add_theme_stylebox_override("panel", s)
	if locked: p.modulate = Color(1, 1, 1, 0.45)
	var v := vbox(3); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; p.add_child(v)
	if on != null and not locked:
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and p.get_global_rect().has_point(ev.global_position) and not p.has_meta("dragged"):
				Snd.sfx("tap"); on.call())
	return p
func card_box(c: PanelContainer) -> VBoxContainer: return c.get_child(0)
func clear(n: Node) -> void:   # remove children now (queue_free alone keeps them until the frame ends, so sizes come out wrong)
	for c in n.get_children(): n.remove_child(c); c.queue_free()

# a grid of cards that fills the row: as many columns as fit (wide cards may shrink to 85%), then the cards stretch
class Grid extends HFlowContainer:
	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_SORT_CHILDREN: _fit()
	func _fit() -> void:
		var W := size.x
		if W <= 0 or get_child_count() == 0: return
		var base := 0.0
		for c in get_children(): if c.has_meta("base_w"): base = c.get_meta("base_w"); break
		if base <= 0: return
		var gap := 6.0; var minw := base * 0.85 if base >= 140 else base
		var cols: int = max(1, int((W + gap) / (minw + gap))); var cw = floor((W - gap * (cols - 1)) / cols)
		for c in get_children():
			if c.has_meta("base_w") and absf(c.custom_minimum_size.x - cw) > 0.5: c.custom_minimum_size.x = cw
func grid() -> Grid:
	var g := Grid.new(); g.add_theme_constant_override("h_separation", 6); g.add_theme_constant_override("v_separation", 6); g.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return g

# ---------- popup window (the HTML's panel): onClose runs however it closes; sticky ones ignore taps outside ----------
func panel(on_close = null, sticky := false) -> VBoxContainer:
	close_panel(false)
	modal_cb = on_close
	var ov := Control.new(); ov.set_anchors_preset(Control.PRESET_FULL_RECT); ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT); ov.add_child(dim)
	dim.gui_input.connect(func(ev):
		if not sticky and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: close_panel())
	var mc := MarginContainer.new(); mc.set_anchors_preset(Control.PRESET_FULL_RECT); mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ["margin_left", "margin_right"]: mc.add_theme_constant_override(k, 8)
	for k in ["margin_top", "margin_bottom"]: mc.add_theme_constant_override(k, 26)
	ov.add_child(mc)
	var cc := CenterContainer.new(); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE; mc.add_child(cc)
	var pc := PanelContainer.new(); pc.add_theme_stylebox_override("panel", win_sb()); cc.add_child(pc)
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; pc.add_child(sc)
	var v := vbox(6); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(v)
	var fit := func():   # as wide as the screen allows (up to 640), as tall as its contents (up to the screen)
		var vs := root.size
		var w: float = min(640, vs.x - 16) - 28
		v.custom_minimum_size.x = w
		sc.custom_minimum_size = Vector2(w, min(v.get_combined_minimum_size().y, vs.y - 52 - 28))
	v.resized.connect(fit); root.resized.connect(fit); fit.call.call_deferred()
	ov.set_meta("fit", fit)
	if not sticky:   # always-visible way out
		var x := btn("X", func(): close_panel(), true); x.set_anchors_preset(Control.PRESET_TOP_RIGHT); x.position = Vector2(-48, 4); x.size = Vector2(40, 40)
		x.anchor_left = 1; x.anchor_right = 1; x.offset_left = -48; x.offset_right = -6; x.offset_top = 4; x.offset_bottom = 44
		ov.add_child(x)
	root.add_child(ov); modal = ov
	return v
func panel_title(v: VBoxContainer, t: String) -> void:
	var l := lbl(t, 22, GOLD); l.add_theme_color_override("font_shadow_color", WIND); l.add_theme_constant_override("shadow_offset_x", 2); l.add_theme_constant_override("shadow_offset_y", 2); v.add_child(l)
	var line := ColorRect.new(); line.color = Color(1, 1, 1, 0.16); line.custom_minimum_size = Vector2(0, 2); v.add_child(line)
func close_panel(run_cb := true) -> void:
	if modal: modal.queue_free(); modal = null
	var cb = modal_cb; modal_cb = null
	if run_cb and cb != null: cb.call()

func toast(msg: String, id := 0) -> void:
	if toasts == null: return
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", sb(WIN_T.lerp(WIN_B, 0.5), GOLD, 2, 8, 6)); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := hbox(8); p.add_child(h)
	if id: h.add_child(icon(id, 28))
	h.add_child(lbl(msg, 15, Color.WHITE, false)); toasts.add_child(p)
	var tw := p.create_tween(); tw.tween_interval(2.6); tw.tween_property(p, "modulate:a", 0.0, 0.5); tw.tween_callback(p.queue_free)

