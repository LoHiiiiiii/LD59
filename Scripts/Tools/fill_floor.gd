@tool
extends EditorScript

func _run() -> void:
	var root: Node = get_scene()
	if not root:
		printerr("No scene open")
		return
	var layer := root.find_child("Template Floor Layer") as TileMapLayer
	if not layer:
		printerr("Template Floor Layer not found")
		return
	var tiles: int = 600 / layer.tile_set.tile_size.x
	layer.clear()
	for x: int in tiles:
		for y: int in tiles:
			layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
