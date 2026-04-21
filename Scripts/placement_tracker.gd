class_name PlacementTracker
extends Node

@export var label: Label
@export var player: Player
@export var timer: GameTimer

var _active_tombs: Array[Tomb] = []
var _ghost_entries: Array = []
var _active: bool = false

func setup(tombs: Array[Tomb]) -> void:
	_active_tombs = tombs
	_ghost_entries.clear()
	_active = true

func register_ghost(ghost: GhostPlayer) -> void:
	var entry: Dictionary = {"ghost": ghost, "count": 0, "respected_tombs": []}
	_ghost_entries.append(entry)
	ghost.tomb_entered.connect(func(tomb: Tomb) -> void:
		_on_ghost_enters_tomb(tomb, entry)
	)

func stop() -> void:
	_active = false
	if label:
		label.visible = false
	_active_tombs.clear()
	_ghost_entries.clear()

func _on_ghost_enters_tomb(tomb: Tomb, entry: Dictionary) -> void:
	if not _active_tombs.has(tomb):
		return
	var respected: Array = entry["respected_tombs"]
	if respected.has(tomb):
		return
	respected.append(tomb)
	entry["count"] = entry["count"] + 1

func _process(_delta: float) -> void:
	if not _active or not label or not timer:
		return
	label.visible = timer.is_displaying() and not _ghost_entries.is_empty()
	if not label.visible:
		return
	var player_count := 0
	for tomb: Tomb in _active_tombs:
		if tomb.is_respected:
			player_count += 1
	if player_count == _active_tombs.size():
		return
	label.text = "#" + str(_get_player_placement(player_count))

func _get_player_placement(player_count: int) -> int:
	if not player:
		return 1
	var player_unrespected := _active_tombs.filter(
		func(t: Tomb) -> bool: return not t.is_respected)
	var player_dist := _nearest_dist(player.global_position, player_unrespected)
	var ahead := 0
	for entry: Variant in _ghost_entries:
		var e := entry as Dictionary
		var ghost: GhostPlayer = e["ghost"]
		var respected: Array = e["respected_tombs"]
		var ghost_unrespected := _active_tombs.filter(
			func(t: Tomb) -> bool: return not respected.has(t))
		var ghost_dist := _nearest_dist(ghost.global_position, ghost_unrespected)
		if _ranks_higher(e["count"], ghost_dist, player_count, player_dist):
			ahead += 1
	return ahead + 1

func _ranks_higher(count_a: int, dist_a: float, count_b: int, dist_b: float) -> bool:
	if count_a != count_b:
		return count_a > count_b
	return dist_a < dist_b

func _nearest_dist(from: Vector2, tombs: Array) -> float:
	if tombs.is_empty():
		return 0.0
	var min_dist := INF
	for t: Variant in tombs:
		min_dist = minf(min_dist, from.distance_to((t as Tomb).global_position))
	return min_dist
