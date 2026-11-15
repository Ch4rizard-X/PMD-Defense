extends Node
func _ready():
	for p in ["res://scripts/hud.gd", "res://scripts/view.gd", "res://scripts/ui.gd", "res://scripts/kit.gd", "res://scripts/battle.gd", "res://scripts/mapgen.gd", "res://scripts/core.gd", "res://scripts/snd.gd", "res://boot.gd"]:
		var s = load(p)
	get_tree().quit()
