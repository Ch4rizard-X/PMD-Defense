extends Node
# run as a scene so autoloads exist
func _ready():
	get_tree().create_timer(50).timeout.connect(func(): get_tree().quit())
	var out := []
	for cs in [[0, true, 12345, 1.9, 1], [5, false, 777, 1.76, 5], [40, true, 99999, 2.13, 12], [80, true, 31337, 2.4, 20], [60, false, 4242, 1.6, 15]]:
		var M = MG.gen_map(cs[0], cs[1], cs[2], null, cs[3], cs[4])
		var tt := ""
		for row in M.t: for v in row: tt += str(v)
		var ls := []
		for l in M.lines:
			var q := []
			for v in l: q.append([int(round(v.x)), int(round(v.y))])
			ls.append(q)
		var vs := 0
		for row in M.vr: for v in row: vs += v
		out.append([M.W, M.H, M.kind, tt.md5_text(), ls, vs, int(round(M.len))])
	print("RESULT", JSON.stringify(out))
	get_tree().quit()
