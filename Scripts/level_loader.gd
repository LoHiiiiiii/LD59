class_name LevelLoader
extends RefCounted

static func apply(template_layers: Array[TileMapLayer], target_layers: Array[TileMapLayer], rotation: int, flip_x: bool) -> void:
	var center: Vector2 = _get_center(template_layers[0])
	for i: int in range(mini(template_layers.size(), target_layers.size())):
		var src: TileMapLayer = template_layers[i]
		var dst: TileMapLayer = target_layers[i]
		dst.clear()
		for cell: Vector2i in src.get_used_cells():
			dst.set_cell(
				_transform_cell(cell, rotation, flip_x, center),
				src.get_cell_source_id(cell),
				src.get_cell_atlas_coords(cell),
				src.get_cell_alternative_tile(cell)
			)

static func transform_position(world_pos: Vector2, reference_layer: TileMapLayer, rotation: int, flip_x: bool) -> Vector2:
	var tile_size: Vector2 = Vector2(reference_layer.tile_set.tile_size)
	var cell: Vector2 = (world_pos - reference_layer.global_position) / tile_size
	var transformed: Vector2 = _transform_point(cell, rotation, flip_x, _get_center(reference_layer))
	return reference_layer.global_position + transformed * tile_size

static func _get_center(layer: TileMapLayer) -> Vector2:
	var rect: Rect2i = layer.get_used_rect()
	return Vector2(rect.position) + Vector2(rect.size) * 0.5 - Vector2(0.5, 0.5)

static func _transform_cell(cell: Vector2i, rotation: int, flip_x: bool, center: Vector2) -> Vector2i:
	return Vector2i(_transform_point(Vector2(cell), rotation, flip_x, center).round())

static func _transform_point(p: Vector2, rotation: int, flip_x: bool, center: Vector2) -> Vector2:
	p -= center
	if flip_x:
		p.x = -p.x
	match rotation:
		1: p = Vector2(-p.y, p.x)
		2: p = Vector2(-p.x, -p.y)
		3: p = Vector2(p.y, -p.x)
	return p + center
