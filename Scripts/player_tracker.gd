class_name PlayerTracker
extends Node

@export var player: Player
@export var timer: GameTimer
@export var interval: float = 5.0

var tomb_combination: String = ""
var records: Array[Dictionary] = []

var _interval_timer: float = 0.0

func notify_respected() -> void:
	_record()

func reset() -> void:
	records.clear()
	_interval_timer = 0.0

func _process(delta: float) -> void:
	if not timer or not timer.is_running():
		return
	_interval_timer += delta
	if _interval_timer >= interval:
		_interval_timer -= interval
		_record()

func _record() -> void:
	if not player or not timer:
		return
	records.append({
		"position": player.global_position,
		"time": timer.elapsed
	})
