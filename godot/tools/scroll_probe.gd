extends Node
var opened := 0
func mb(p: Vector2, down: bool) -> void:   # a finger, like on the phone (no mouse hover before it)
	var e := InputEventScreenTouch.new(); e.index = 0; e.pressed = down; e.position = get_viewport().get_final_transform() * p; Input.parse_input_event(e)
func mm(p: Vector2, r: Vector2) -> void:
	var e := InputEventScreenDrag.new(); e.index = 0; e.position = get_viewport().get_final_transform() * p; e.relative = r * 2.7; Input.parse_input_event(e)
func find_sc(n: Node) -> ScrollContainer:
	if n is ScrollContainer and n.is_visible_in_tree() and n.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED: return n
	for c in n.get_children():
		var r := find_sc(c)
		if r: return r
	return null
func _ready() -> void:
	get_tree().create_timer(60).timeout.connect(func(): print("TIMEOUT"); get_tree().quit())
	DirAccess.remove_absolute("user://save.bin"); C.G = C.new_save()
	Input.emulate_touch_from_mouse = true; print("touchscreen mode: ", DisplayServer.is_touchscreen_available())
	await get_tree().process_frame
	var ui = load("res://main.tscn").instantiate(); get_tree().root.add_child(ui)
	await get_tree().create_timer(1.5).timeout
	ui.show_hub("routes"); await get_tree().create_timer(0.8).timeout
	var sc := find_sc(ui); print("scroll at start ", sc.scroll_vertical)
	var p := Vector2(110, 600)
	mb(p, true); for i in 3: await get_tree().process_frame
	for i in 12: p.y -= 15; mm(p, Vector2(0, -15)); await get_tree().process_frame
	mb(p, false); await get_tree().process_frame
	print("after swipe ", sc.scroll_vertical, "  panel opened: ", K.modal != null)
	await get_tree().create_timer(0.8).timeout; print("after glide ", sc.scroll_vertical)
	sc.scroll_vertical = 0; await get_tree().create_timer(0.2).timeout
	var card: Control = null
	var st := [sc]
	while st.size():
		var n = st.pop_front()
		if n is PanelContainer and n.mouse_filter == Control.MOUSE_FILTER_STOP and n.is_visible_in_tree() and n.size.y > 100: card = n; break
		for c in n.get_children(): st.append(c)
	var q := card.get_global_rect().get_center(); print("tapping card at ", q); mb(q, true); for i in 2: await get_tree().process_frame
	mb(q, false); for i in 3: await get_tree().process_frame
	print("tap opens panel: ", K.modal != null)
	get_tree().quit()
