extends SceneTree
func _init():
	var C = load("res://scripts/core.gd").new()
	C._init(); C.load_db(); C.G = C.new_save()
	var out := []
	for id in [1, 25, 150, 445, 887]:
		out.append([id, C.calc_stats(id, 50, null, 0), C.best_moves(id, 30), C.place_cost({"id": id, "lv": 20})])
	out.append(C.move_desc(33)); out.append(C.move_desc(206)); out.append(C.threat_tier(50, 7)); out.append(C.eff(9, [11, 10]))
	print(JSON.stringify(out))
	quit()
