extends Node
func place_all(team: Array) -> void:
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
		if best and BT.B.cash >= C.place_cost(e): BT.place_tower(e, best[0], best[1])
func _ready():
	get_tree().create_timer(170).timeout.connect(func(): print("TIMEOUT"); get_tree().quit())
	C.G = C.new_save()
	var team := []
	for id in [4, 1, 7, 25, 92, 63]: var e = C.make_mon(id, 18); C.G.box.append(e); team.append(e)
	# waves must match the HTML version for the same seed
	BT.start_battle(0, 1, 777, team, true, 2.0)
	var wv := []
	for w in BT.B.waves: wv.append(w.map(func(s): return [s.id, s.lv]))
	print("WAVES", JSON.stringify(wv.slice(0, 6)), "|", BT.B.waves.size(), "|", JSON.stringify(wv[-1]))
	for run in [[0, 1, 777, 18], [20, 3, 4242, 30], [50, 6, 999, 45]]:
		C.G = C.new_save(); team = []
		for id in [4, 1, 7, 25, 92, 63, 133, 66]: var e = C.make_mon(id, run[3]); C.G.box.append(e); team.append(e)
		BT.start_battle(run[0], run[1], run[2], team, true, 2.0)
		place_all(team); BT.B.auto = true; BT.B.speed = 1; BT.start_wave()
		var steps := 0; var t0 := Time.get_ticks_msec()
		while BT.B.phase != "win" and BT.B.phase != "lose" and steps < 200000:
			BT.tick(1.0 / 20); steps += 1
			if steps % 40 == 0:
				place_all(team)
				for t in BT.B.towers:
					for k in [2, 1, 0]: BT.buy_upgrade(t, k)
			if BT.B.phase == "build": BT.start_wave()
		var met := []
		for u in BT.B.meter: var m = BT.B.meter[u]; met.append([C.SP[m.id].n, m.dmg, m.ko, int(m.ctl)])
		print("RUN set=%d tier=%d -> %s wave %d/%d lives %d kills %d towers %d asks %d  %.1fs real, %d steps" % [run[0], run[1], BT.B.phase, BT.B.wave, BT.B.waves.size(), BT.B.lives, BT.B.kills, BT.B.towers.size(), BT.B.asks.size(), (Time.get_ticks_msec() - t0) / 1000.0, steps])
		print("METER ", JSON.stringify(met))
	get_tree().quit()
