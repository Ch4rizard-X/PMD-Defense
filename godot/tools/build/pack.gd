extends SceneTree
# Windows game data: the Android build's files (graphics, sound, data, scenes) + the current scripts as text
const A := "/tmp/apkr/assets"
const SKIP := ["dexopt", "_cl_", "assets.sparsepck", "tools"]
# sound made since the APK (re-rendered at the right speed / new): rdgodot's imported copies replace the APK's
const NEW_SND := ["e11", "e96", "e98", "m128"]
func is_new_snd(r: String) -> bool:
	for k in NEW_SND: if r.begins_with(".godot/imported/%s.mp3-" % k): return true
	var f := r.get_file()   # move sounds: wXXXX.mp3 (Explorers of Sky sound ids)
	return r.begins_with(".godot/imported/") and f.length() > 9 and f[0] == "w" and f.substr(5, 5) == ".mp3-"
# data rebuilt since the APK: forms / regional forms / moves (dex), sprites (anim), shinies, music list, special maps
const DATA_NEW := ["data/snd.bin", "data/dex.bin", "data/anim.bin", "data/shiny.bin", "data/tsx.bin"]
var pk := PCKPacker.new(); var n := 0
func add_dir(rel: String) -> void:
	var d := DirAccess.open(A + "/" + rel); d.include_hidden = true
	for f in d.get_files():
		var r := (rel + "/" + f).trim_prefix("/")
		if r in SKIP: continue
		if r.begins_with("scripts/") and (r.ends_with(".gdc") or r.ends_with(".gd.remap")): continue   # replaced by the current text scripts
		if r in ["boot.gdc", "boot.gd.remap"] or r in DATA_NEW or is_new_snd(r): continue
		pk.add_file("res://" + r, A + "/" + r); n += 1
	for s in d.get_directories():
		var r := (rel + "/" + s).trim_prefix("/")
		if r in SKIP: continue
		add_dir(r)
func _init() -> void:
	pk.pck_start("/tmp/win/RouteDefense.pck")
	add_dir("")
	for f in DirAccess.get_files_at("/home/claude/rdgodot/scripts"):
		if f.ends_with(".gd"): pk.add_file("res://scripts/" + f, "/home/claude/rdgodot/scripts/" + f); n += 1
	pk.add_file("res://boot.gd", "/tmp/winsrc/boot.gd"); n += 1
	# extra assets made since the APK: Red's Monster House + the music list that names it
	for d in DATA_NEW: pk.add_file("res://" + d, "/tmp/winsrc/" + d.get_file()); n += 1
	# every imported file the APK doesn't have (shiny / form sprites, new tilesets, songs, move sounds) + re-rendered songs
	const RG := "/home/claude/rdgodot/"
	for f in DirAccess.get_files_at(RG + ".godot/imported"):
		if f.ends_with(".md5"): continue
		var r := ".godot/imported/" + f
		if is_new_snd(r) or not FileAccess.file_exists(A + "/" + r): pk.add_file("res://" + r, RG + r); n += 1
	for dir in ["img/mon", "img/ts", "snd"]:
		for f in DirAccess.get_files_at(RG + dir):
			var r: String = dir + "/" + f
			if f.ends_with(".import") and (not FileAccess.file_exists(A + "/" + r) or is_new_snd(".godot/imported/" + f.trim_suffix(".import") + "-")): pk.add_file("res://" + r, RG + r); n += 1
	pk.flush(); print("packed ", n, " files"); quit()
