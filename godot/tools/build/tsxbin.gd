extends SceneTree
func fix(v):
	if v is float and v == floor(v): return int(v)
	if v is Array: return v.map(func(x): return fix(x))
	if v is Dictionary:
		var o := {}
		for k in v: o[k] = fix(v[k])
		return o
	return v
func _init() -> void:
	var X = fix(JSON.parse_string(FileAccess.get_file_as_string("/tmp/winsrc/tsx.json")))
	var f := FileAccess.open("/tmp/winsrc/tsx.bin", FileAccess.WRITE); f.store_var(X); f.close()
	var snd = FileAccess.open("/tmp/winsrc/snd.bin", FileAccess.READ).get_var()
	snd.music["Ultra Wormhole"] = "e39"; snd.music["Paradox Portal"] = "e41"
	var g := FileAccess.open("/tmp/winsrc/snd.bin", FileAccess.WRITE); g.store_var(snd); g.close()
	print("tsx ", X.size(), " music ", snd.music["Ultra Wormhole"], " ", snd.music.get("Tiny Woods")); quit()
