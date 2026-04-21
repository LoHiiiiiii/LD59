class_name GameCamera
extends Node2D

@export var shaker: Node2D
@export var max_offset: float
@export var decay: float
@export var noise_speed: float

var follow_position: Vector2 = Vector2.ZERO
var _trauma: float = 0.0
var _noise_time: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()

func shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)

func _process(delta: float) -> void:
	_trauma = maxf(_trauma - decay * delta, 0.0)
	var s: float = _trauma * _trauma
	_noise_time += noise_speed * delta
	if shaker:
		shaker.position = Vector2(
			_noise.get_noise_1d(_noise_time) * max_offset * s,
			_noise.get_noise_1d(_noise_time + 1000.0) * max_offset * s
		)
	global_position = follow_position
