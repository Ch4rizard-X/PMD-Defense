extends SceneTree
# Route Defense: turns data/*.json into data/*.bin (Godot's own format) once, at build time.
# JSON has only decimal numbers and text keys; the game needs whole numbers and number keys (species 25, move 33),
# so whole-number values become ints and keys that are numbers become int keys.

func fix(v):
	if v is float:
		return int(v) if v == floor(v) and absf(v) < 1e15 else v
	if v is Array:
		var a := []
		for x in v: a.append(fix(x))
		return a
	if v is Dictionary:
		var d := {}
		for k in v:
			var kk = int(k) if (k is String and k.is_valid_int()) else k
			d[kk] = fix(v[k])
		return d
	return v

func _init():
	for f in ["dex", "anim", "ts", "fx", "snd", "tree", "icons", "wx", "mk", "micons"]:
		var txt := FileAccess.get_file_as_string("res://data/%s.json" % f)
		var j = JSON.parse_string(txt)
		if j == null:
			push_error("bad json " + f); continue
		var out := FileAccess.open("res://data/%s.bin" % f, FileAccess.WRITE)
		out.store_var(fix(j))
		out.close()
		print("converted ", f)
	quit()
