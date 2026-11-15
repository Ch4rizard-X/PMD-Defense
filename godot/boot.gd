extends Node
# Route Defense - boot: loads a downloaded code patch (user://patch.pck) before the game starts.
# This script is never patched itself, so keep it tiny. A patch that fails to start is skipped next time.
const BUILT_V := 1                       # the code version inside this APK (raised with every APK build)
const PATCH := "user://patch.pck"        # newest downloaded code (scripts only; graphics stay in the APK)
const INFO := "user://patch.txt"         # its version number
const TRY := "user://patch_try.txt"      # set while a patch is starting; the game clears it once it runs fine

func _ready() -> void:
	var pv := _read_int(INFO)
	if pv > BUILT_V and FileAccess.file_exists(PATCH):
		if _read_int(TRY) == pv:
			# this patch was tried and the game never got going: drop it and run the built-in code
			DirAccess.remove_absolute(PATCH); DirAccess.remove_absolute(INFO); DirAccess.remove_absolute(TRY)
			pv = BUILT_V
		else:
			_write(TRY, str(pv))
			if not ProjectSettings.load_resource_pack(PATCH, true):
				DirAccess.remove_absolute(TRY); pv = BUILT_V
	else:
		pv = BUILT_V
	Engine.set_meta("code_v", pv); Engine.set_meta("built_v", BUILT_V)
	get_tree().call_deferred("change_scene_to_file", "res://main.tscn")

func _read_int(p: String) -> int:
	if not FileAccess.file_exists(p): return 0
	return FileAccess.get_file_as_string(p).strip_edges().to_int()
func _write(p: String, s: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f: f.store_string(s)
