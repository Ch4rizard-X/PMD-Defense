extends Node2D
var view; var frames := 0; var team := []
func _ready():
	get_tree().create_timer(100).timeout.connect(func(): get_tree().quit())
	C.G = C.new_save()
	for id in [4, 1, 7, 25, 92, 63, 133, 66]: var e = C.make_mon(id, 30); C.G.box.append(e); team.append(e)
	var vs := get_viewport_rect().size
	BT.start_battle(50, 6, 999, team, true, (vs.y - 50) / vs.x)
	view = load("res://scripts/view.gd").new(); add_child(view)
	var M = BT.B.M; var s: float = min(vs.x / (M.W * 24.0), (vs.y - 50) / (M.H * 24.0))
	view.scale = Vector2(s, s); view.position = Vector2((vs.x - M.W * 24 * s) / 2, 50)
	BT.B.auto = true; BT.start_wave()
func place():
	var M = BT.B.M
	for e in team:
		var placed := false
		for t in BT.B.towers: if is_same(t.e, e): placed = true
		if placed or BT.B.cash < C.place_cost(e): continue
		var best = null
		for y in range(1, M.H):
			for x in range(1, M.W):
				var px := x * 24.0 + 12; var py := y * 24.0 + 12
				if BT.can_place(e, px, py):
					var d: float = MG.dist_to_path(M, px, py)
					if best == null or d < best[2]: best = [px, py, d]
		if best: BT.place_tower(e, best[0], best[1])
func _process(_d):
	frames += 1
	for i in 6: BT.tick(1.0 / 60)
	if frames % 20 == 0: place()
	if BT.B.wave == 30 and BT.B.weather == null: BT.B.cash += 5000; BT.buy_weather("rain")
	if BT.B.towers.size() and BT.B.sel == null: BT.B.sel = BT.B.towers[0]
	if frames in [420, 900, 1500]:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/gv_%d.png" % frames)
		print("SHOT ", frames, " wave ", BT.B.wave, " towers ", BT.B.towers.size(), " en ", BT.B.en.size(), " phase ", BT.B.phase)
	if frames > 1510: get_tree().quit()
