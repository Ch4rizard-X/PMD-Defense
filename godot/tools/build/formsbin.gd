extends SceneTree
# merge the forms (forms.json) into the game's dex.bin / anim.bin (JSON numbers -> ints where whole, like convert_data.gd)
func fix(v):
	if v is float and v == floor(v): return int(v)
	if v is Array: return v.map(func(x): return fix(x))
	if v is Dictionary:
		var o := {}
		for k in v: o[k] = fix(v[k])
		return o
	return v
func _init() -> void:
	var F = fix(JSON.parse_string(FileAccess.get_file_as_string("/tmp/forms/forms.json")))
	var dex = FileAccess.open("/tmp/apkr/assets/data/dex.bin", FileAccess.READ).get_var()
	var anim = FileAccess.open("/tmp/apkr/assets/data/anim.bin", FileAccess.READ).get_var()
	var forms := []; var nreg := 0
	for e in F.mon:
		if e.f == null: e.erase("f")
		if e.form == "regional": dex.mon.append(e); nreg += 1
		else: forms.append(e)
	dex["forms"] = forms
	for k in F.moves: dex.moves[int(k)] = F.moves[k]
	for k in F.abil: dex.abil[int(k)] = F.abil[k]
	for k in F.anim: anim[int(k)] = F.anim[k]
	# friendship evolutions: PokeAPI's own minimum friendship (160 / 220), time of day and known-move type
	var hp = fix(JSON.parse_string(FileAccess.get_file_as_string("/tmp/happy_patch.json"))); var nh := 0
	for m in dex.mon:
		var pf = hp.get(str(m.id), null)
		if pf == null: continue
		for v in m.ev:
			var q = pf.get(str(v.to), null)
			if q != null: v.happy = q.happy; v.tod = q.tod; v.mtype = q.mtype; nh += 1
	print("friendship evolutions marked ", nh)
	var o := FileAccess.open("/tmp/winsrc/dex.bin", FileAccess.WRITE); o.store_var(dex); o.close()
	o = FileAccess.open("/tmp/winsrc/anim.bin", FileAccess.WRITE); o.store_var(anim); o.close()
	print("dex mon ", dex.mon.size(), " (regional ", nreg, ")  battle forms ", forms.size(), "  moves ", dex.moves.size(), "  anim ", anim.size()); quit()
