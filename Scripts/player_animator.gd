class_name PlayerAnimator
extends AnimationPlayer

@export var player: Player
@export var player_sprite: Node2D
@export var player_shadow: Node2D
@export var jump_start_duration: float
@export var jump_fall_duration: float
@export var jump_height: float
@export var jump_start_height: float
@export var roll_sound: AudioStreamPlayer2D

var _current_anim: StringName = &""
var _was_jumping: bool = false
var _jump_timer: float = 0.0
var _effective_rise: float = 0.0
var _effective_fall: float = 0.0
var _effective_height: float = 0.0


func _process(delta: float) -> void:
	var is_jumping: bool = player.state == Player.State.JUMPING

	if is_jumping and not _was_jumping:
		_begin_jump()
	_was_jumping = is_jumping

	if is_jumping:
		_jump_timer += delta
	var arc_y: float = -_calc_arc(_jump_timer) if is_jumping else 0.0
	player_sprite.position = player.sprite_offset + Vector2(0.0, arc_y)
	player_shadow.position = player.sprite_offset

	player_sprite.flip_h = not player.facing_right

	var target: StringName = _resolve_anim()
	if target != _current_anim:
		_current_anim = target
		play(target)
		seek(0.0, true)

func roll() -> void:
	roll_sound.play()

func _begin_jump() -> void:
	_jump_timer = 0.0
	var total: float = jump_start_duration + jump_fall_duration
	if player.jump_duration >= total:
		_effective_rise = jump_start_duration
		_effective_fall = jump_fall_duration
		_effective_height = jump_height
	else:
		var scale: float = player.jump_duration / total
		_effective_rise = jump_start_duration * scale
		_effective_fall = jump_fall_duration * scale
		_effective_height = jump_height * scale

func _calc_arc(t: float) -> float:
	if t <= _effective_rise:
		var p: float = ease(t / _effective_rise, 0.5)
		return lerpf(jump_start_height, _effective_height, p)
	var fall_start: float = player.jump_duration - _effective_fall
	if t < fall_start:
		return _effective_height
	var fall_t: float = clampf((t - fall_start) / _effective_fall, 0.0, 1.0)
	return _effective_height * (1.0 - ease(fall_t, 2.0))

func _resolve_anim() -> StringName:
	match player.state:
		Player.State.JUMPING:
			return &"downed" if player._landing_failed else (&"jump_disabled" if player._landing_buffered else &"jump")
		Player.State.LANDING:
			return &"jump_disabled" if player._landing_buffered else &"landing"
		Player.State.DOWNED:
			return &"downed"
		Player.State.DANGER_DELAY:
			return &"danger"
		Player.State.JUMP_DISABLED:
			return &"jump_disabled"
		Player.State.RESPECT:
			return &"respect"
		Player.State.RESET:
			return &"reset"
	return &"walk" if player.walking else &"idle"
