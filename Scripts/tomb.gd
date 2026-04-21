class_name Tomb
extends Area2D

signal respected

@export var sprite: CanvasItem
@export var respect_sound: AudioStreamPlayer2D

var is_respected: bool = false

func _physics_process(_delta: float) -> void:
	if is_respected:
		return
	for body: Node2D in get_overlapping_bodies():
		if not body is Player:
			continue
		if (body as Player).state != Player.State.RESPECT:
			continue
		respect()
		break

func set_enabled(value: bool) -> void:
	visible = value
	monitoring = value
	monitorable = value
	process_mode = PROCESS_MODE_INHERIT if value else PROCESS_MODE_DISABLED

func pre_respect() -> void:
	is_respected = true
	if sprite and sprite.material:
		sprite.material.set_shader_parameter(&"radar_on", false)

func reset() -> void:
	is_respected = false
	if sprite and sprite.material:
		sprite.material.set_shader_parameter(&"radar_on", true)

func respect() -> void:
	if is_respected:
		return
	is_respected = true
	respect_sound.play()
	if sprite and sprite.material:
		sprite.material.set_shader_parameter(&"radar_on", false)
	respected.emit()
