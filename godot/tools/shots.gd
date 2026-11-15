extends Node
# drives the real game through its screens and saves screenshots
var step := 0; var f := 0
func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/s_%s.png" % n); print("SHOT ", n)
func _ready() -> void:
	get_tree().create_timer(160).timeout.connect(func(): print("TIMEOUT"); get_tree().quit())
	DirAccess.remove_absolute("user://save.bin")
	C.G = C.new_save()
	await get_tree().process_frame
	var ui = load("res://main.tscn").instantiate(); get_tree().root.add_child(ui)
	await get_tree().create_timer(2.0).timeout
	await shot("title")
	ui.show_starter(); await get_tree().create_timer(0.6).timeout; await shot("starter")
	for id in [4, 1, 7, 25, 92, 63, 133, 66, 94, 6]: var e = C.make_mon(id, 30); C.G.box.append(e)
	C.G.box[1].lv = 40; C.G.box[5].pend = [94]
	ui.show_hub("routes"); await get_tree().create_timer(0.8).timeout; await shot("hub")
	ui.route_panel(0); await get_tree().create_timer(0.6).timeout; await shot("route")
	K.close_panel(false); ui.show_hub("box"); await get_tree().create_timer(0.5).timeout; await shot("box")
	ui.mon_panel(C.G.box[5]); await get_tree().create_timer(0.5).timeout; await shot("monpanel")
	K.close_panel(false); ui.route = {"set": 30, "tier": 4, "seed": 1234}
	ui.team = []; for e in C.G.box: ui.team.append(e.u)
	ui.begin_battle(); await get_tree().create_timer(1.0).timeout
	var hud = ui.hud
	var B = BT.B
	print("DBG hud size ", hud.size, " scr ", ui.scr.size, " ui ", ui.size, " bar ", hud.bar.position, hud.bar.scale, hud.bar.get_combined_minimum_size(), " map ", hud.map_rect.position, hud.map_rect.size, " vp ", hud.vp.size)
	# place a few, start waves
	for e in B.team.slice(0, 6):
		B.cash = 99999
		var best = null
		for y in range(1, B.M.H):
			for x in range(1, B.M.W):
				var px := x * 24.0 + 12; var py := y * 24.0 + 12
				if BT.can_place(e, px, py) and (best == null or MG.dist_to_path(B.M, px, py) < best[2]): best = [px, py, MG.dist_to_path(B.M, px, py)]
		if best: BT.place_tower(e, best[0], best[1])
	B.auto = true; BT.start_wave(); B.speed = 3; C.G.opts.meter = true; hud.meter_show()
	await get_tree().create_timer(6.0).timeout; B.sel = B.towers[0]; hud.tower_info(); await get_tree().create_timer(0.4).timeout; await shot("battle")
	B.sel = null; hud.tower_info(); BT.buy_weather("rain"); await get_tree().create_timer(3.0).timeout; await shot("battle_rain")
	hud.pause_menu(); await get_tree().create_timer(0.4).timeout; await shot("pause"); K.close_panel()
	B.asks.append({"id": 152, "lv": 20, "ab": 1, "nat": 3, "iv": [1,2,3,4,5,6]}); await get_tree().create_timer(0.6).timeout; await shot("ask"); K.close_panel()
	BT.finish(true); await get_tree().create_timer(1.5).timeout; await shot("result")
	get_tree().quit()
