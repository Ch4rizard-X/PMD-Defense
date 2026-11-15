extends Node
func _ready():
	get_tree().create_timer(50).timeout.connect(func(): get_tree().quit())
	var M = MG.gen_map(0, true, 424242, "plain", 2.13, 3)
	M.tex.get_image().save_png("/tmp/gmap.png")
	var M2 = MG.gen_map(30, false, 9, null, 1.9, 8)
	M2.tex.get_image().save_png("/tmp/gmap2.png")
	print("DONE")
	get_tree().quit()
