extends Node
func _ready():
	C.G = C.new_save(); var out := []
	for id in range(1, 1026, 7): if C.SP.has(id): out.append([id, C.best_moves(id, 40)])
	print("BM", JSON.stringify(out)); get_tree().quit()
