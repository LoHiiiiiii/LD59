class_name GhostPlayer
extends Node2D

@export var sprite: Sprite2D
@export var label: Label
@export var detection_area: Area2D
@export var spawn_duration: float = 0.5
@export var flip_threshold: float = 0.5

var ghost_name: String = ""
var color: Color = Color(1.0, 1.0, 1.0, 0.6)

signal tomb_entered(tomb: Tomb)

var _positions: Array = []
var _elapsed: float = 0.0
var _running: bool = false
var _anim_elapsed: float = 0.0
var _at_end: bool = false
var _shrink_elapsed: float = 0.0
var _detected_tombs: Array = []
var _start_position: Vector2

func setup(p_name: String, p_positions: Array, p_color: Color) -> void:
	ghost_name = p_name
	color = p_color
	_positions = p_positions
	if sprite:
		sprite.modulate = p_color
	if label:
		label.text = p_name
	_start_position = global_position

func activate() -> void:
	_running = true
	_elapsed = 0.0
	_anim_elapsed = 0.0
	_at_end = false
	_shrink_elapsed = 0.0
	_detected_tombs.clear()
	scale = Vector2.ONE * 0.01
	if sprite:
		sprite.scale = Vector2.ONE
	visible = true

func deactivate() -> void:
	_running = false
	visible = false

func _physics_process(delta: float) -> void:
	if not _running or _positions.is_empty():
		return

	_anim_elapsed += delta
	if _anim_elapsed < spawn_duration:
		var t := _anim_elapsed / spawn_duration
		scale = Vector2(t, t)
	else:
		scale = Vector2.ONE

	_elapsed += delta
	var prev_x := global_position.x
	global_position = _get_position_at(_elapsed)
	var dx := global_position.x - prev_x
	if absf(dx) >= flip_threshold:
		sprite.flip_h = dx < 0.0

	if not _at_end:
		var last_time := float((_positions[-1] as Dictionary)["time"])
		if _elapsed >= last_time:
			_at_end = true

	if detection_area:
		for area: Area2D in detection_area.get_overlapping_areas():
			if area is Tomb and not _detected_tombs.has(area):
				_detected_tombs.append(area)
				tomb_entered.emit(area as Tomb)

	if _at_end and sprite:
		_shrink_elapsed += delta
		var t := 1.0 - clampf(_shrink_elapsed / spawn_duration, 0.0, 1.0)
		sprite.scale = Vector2(t, t)


func _get_position_at(t: float) -> Vector2:
	if _positions.size() == 0:
		return _start_position

	if _positions.size() == 1:
		var p := _positions[0] as Dictionary
		return Vector2(float(p["x"]), float(p["y"]))

	var last := _positions.size() - 1
	for i: int in last:
		var a := _positions[i] as Dictionary
		var b := _positions[i + 1] as Dictionary
		var ta := float(a["time"])
		var tb := float(b["time"])
		if t >= ta and t <= tb:
			var f := (t - ta) / maxf(tb - ta, 0.001)
			return Vector2(float(a["x"]), float(a["y"])).lerp(
				Vector2(float(b["x"]), float(b["y"])), f
			)

	if t > _positions[last]["time"]:
		return Vector2(_positions[last]["x"], _positions[last]["y"])

	var start = _positions[0]
	return _start_position.lerp(
		Vector2(float(start["x"]), float(start["y"])), t / float(start["time"])
	)
