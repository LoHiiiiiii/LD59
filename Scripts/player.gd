class_name Player
extends CharacterBody2D

enum State { NORMAL, JUMPING, LANDING, DANGER_DELAY, DOWNED, JUMP_DISABLED, RESPECT, RESET }

@export var max_speed: float
@export var acceleration: float
@export var deceleration: float
@export var hard_deceleration: float
@export_flags_2d_physics var jumpable_danger_mask: int
@export_flags_2d_physics var jumpable_solve_mask: int
@export_flags_2d_physics var jump_interrupt_mask: int
@export_flags_2d_physics var jump_disable_left_mask: int
@export_flags_2d_physics var jump_disable_right_mask: int
@export_flags_2d_physics var jump_disable_up_mask: int
@export_flags_2d_physics var jump_disable_down_mask: int
@export var jump_duration: float
@export var landing_duration: float
@export var disturbed_landing_duration: float
@export var danger_delay_duration: float
@export var down_duration: float
@export var jump_disabled_duration: float
@export var respect_duration: float
@export var reset_speed: float
@export var _collision_shape: CollisionShape2D
@export var offset_speed: float
@export var min_offset_speed: float
@export var solve_max_dist: float
@export var solve_lateral_max_dist: float
@export var solve_align_threshold: float
@export var max_safe_distance: float
@export var camera: GameCamera
@export var level: Level
@export var jump_sound: AudioStreamPlayer2D
@export var fall_sound: AudioStreamPlayer2D
@export var respect_sound: AudioStreamPlayer2D
@export var danger_sound: AudioStreamPlayer2D

signal resetted

var inputs_locked: bool = false
var _reset_target: Vector2 = Vector2.ZERO
var _speed_modifiers: Dictionary = {}
var _disturbance_count: int = 0
var state: State = State.NORMAL
var state_timer: float = 0.0
var _jump_velocity: Vector2 = Vector2.ZERO
var _last_safe_position: Vector2 = Vector2.ZERO
var _last_direction: Vector2 = Vector2.ZERO
var facing_right: bool = true
var walking: bool = false
var _landing_buffered: bool = false
var _landing_failed: bool = false
var _base_collision_mask: int
var sprite_offset: Vector2 = Vector2.ZERO
var camera_offset: Vector2 = Vector2.ZERO
var _rollboost: bool = false 


func force_reset() -> void:
	velocity = Vector2.ZERO
	collision_mask = 0
	state = State.RESET

func _ready() -> void:
	_base_collision_mask = collision_mask
	_reset_target = global_position
	_last_safe_position = global_position

func _process(delta: float) -> void:
	var t: float = minf(offset_speed * delta, 1.0)
	var min_step: float = min_offset_speed * delta
	sprite_offset = sprite_offset.lerp(Vector2.ZERO, t).move_toward(Vector2.ZERO, min_step)
	camera_offset = camera_offset.lerp(Vector2.ZERO, t).move_toward(Vector2.ZERO, min_step)

	camera.follow_position = global_position + camera_offset

func add_speed_modifier(source: Object, multiplier: float) -> void:
	_speed_modifiers[source] = multiplier

func remove_speed_modifier(source: Object) -> void:
	_speed_modifiers.erase(source)

func add_disturbance() -> void:
	_disturbance_count += 1

func _get_max_speed() -> float:
	var combined: float = 1.0
	for multiplier: float in _speed_modifiers.values():
		combined *= multiplier
	return max_speed * combined

func _jump() -> void:
	var jump_dir: Vector2 = _last_direction
	if jump_dir == Vector2.ZERO:
		jump_dir = Vector2.RIGHT if facing_right else Vector2.LEFT
	if jump_dir.x != 0.0:
		facing_right = jump_dir.x > 0.0
	_disturbance_count = 0
	_landing_buffered = false
	_landing_failed = false
	_last_safe_position = global_position
	_jump_velocity = jump_dir * _get_max_speed()
	velocity = _jump_velocity
	state = State.JUMPING
	state_timer = jump_duration
	var dir_mask := 0
	if _jump_velocity.x < 0.0:
		dir_mask |= jump_disable_left_mask
	if _jump_velocity.x > 0.0:
		dir_mask |= jump_disable_right_mask
	if _jump_velocity.y < 0.0:
		dir_mask |= jump_disable_up_mask
	if _jump_velocity.y > 0.0:
		dir_mask |= jump_disable_down_mask
	collision_mask = _base_collision_mask & ~(jumpable_danger_mask | jumpable_solve_mask | dir_mask)
	jump_sound.play()

func _jump_land() -> void:
	collision_mask = _base_collision_mask
	if _overlaps_layer(jumpable_danger_mask):
		velocity = Vector2.ZERO
		state = State.DANGER_DELAY
		state_timer = danger_delay_duration
		danger_sound.play()
	else:
		if _overlaps_layer(jumpable_solve_mask):
			_try_solve_overlap()
		if _landing_failed:
			state = State.DOWNED
			state_timer = down_duration
			camera.shake(0.6)
			fall_sound.play()
		else:
			state = State.LANDING
			var base_duration: float = disturbed_landing_duration if _disturbance_count > 0 else landing_duration
			state_timer = base_duration / 2.0

func _shape_query(at_transform: Transform2D, mask: int) -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _collision_shape.shape
	params.transform = at_transform
	params.collision_mask = mask
	params.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(params, 1).size() > 0

func _overlaps_layer(mask: int) -> bool:
	return _shape_query(_collision_shape.global_transform, mask)

func _try_solve_overlap() -> void:
	var old_pos: Vector2 = global_position
	var directions: Array[Vector2] = [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
	]
	var base_transform: Transform2D = _collision_shape.global_transform
	var step: float = 0.5
	var dist: float = step
	var solved: bool = false
	var jump_norm: Vector2 = _jump_velocity.normalized() if _jump_velocity.length_squared() > 0.0 else Vector2.ZERO
	directions.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.dot(jump_norm) > b.dot(jump_norm)
	)
	while dist <= solve_max_dist and not solved:
		for dir: Vector2 in directions:
			var alignment: float = absf(dir.dot(jump_norm)) if jump_norm != Vector2.ZERO else 1.0
			var dir_max: float = solve_max_dist if alignment >= solve_align_threshold else solve_lateral_max_dist
			if dist > dir_max:
				continue
			var candidate: Transform2D = base_transform.translated(dir * dist)
			if not _shape_query(candidate, jumpable_solve_mask):
				global_position = candidate.origin
				solved = true
				break
		dist += step
	if not solved:
		global_position = _last_safe_position
	var disp: Vector2 = global_position - old_pos
	sprite_offset -= disp
	camera_offset -= disp

func _on_timer_expired() -> void:
	match state:
		State.JUMPING:
			_jump_land()
		State.LANDING:
			if _landing_buffered:
				state = State.JUMP_DISABLED
				state_timer = jump_disabled_duration
				add_speed_modifier(self, 2)
				_rollboost = true
			else:
				camera.shake(0.6)
				state = State.DOWNED
				state_timer = down_duration
				fall_sound.play()
		State.JUMP_DISABLED:
			state = State.NORMAL
		State.DOWNED:
			state = State.NORMAL
		State.RESPECT:
			if level and level.are_all_tombs_respected():
				velocity = Vector2.ZERO
				collision_mask = 0
				state = State.RESET
			else:
				state = State.NORMAL
		State.DANGER_DELAY:
			var old_pos: Vector2 = global_position
			global_position = _last_safe_position
			camera_offset -= global_position - old_pos
			state = State.DOWNED
			state_timer = down_duration

func _physics_process(delta: float) -> void:
	if _rollboost and state != State.JUMP_DISABLED:
		_rollboost = false
		remove_speed_modifier(self)

	var input: Vector2 = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input != Vector2.ZERO:
		_last_direction = input.normalized()
	else:
		_last_direction = input

	var can_accelerate: bool = false
	walking = false
	var decel_rate: float = deceleration
	var ticks_timer: bool = false

	match state:
		State.NORMAL:
			if global_position.distance_to(_last_safe_position) > max_safe_distance:
				_last_safe_position = global_position
			if not inputs_locked:
				if _last_direction.x != 0.0:
					facing_right = _last_direction.x > 0.0
				can_accelerate = true
				walking = input != Vector2.ZERO
				if Input.is_action_just_pressed("jump"):
					_jump()
				elif Input.is_action_just_pressed("respect"):
					state = State.RESPECT
					state_timer = respect_duration
					respect_sound.play()

		State.JUMP_DISABLED:
			if _last_direction.x != 0.0:
				facing_right = _last_direction.x > 0.0
			can_accelerate = true
			walking = input != Vector2.ZERO
			ticks_timer = true

		State.LANDING:
			can_accelerate = true
			ticks_timer = true
			if Input.is_action_just_pressed("jump"):
				_landing_buffered = true
				state_timer = 0;

		State.DOWNED:
			decel_rate = hard_deceleration
			ticks_timer = true

		State.RESPECT:
			decel_rate = hard_deceleration
			ticks_timer = true

		State.JUMPING:
			ticks_timer = true
			if Input.is_action_just_pressed("jump"):
				_landing_buffered = true
				var effective_landing: float = disturbed_landing_duration if _disturbance_count > 0 else landing_duration
				if state_timer > effective_landing / 2.0:
					_landing_failed = true

		State.DANGER_DELAY:
			ticks_timer = true

		State.RESET:
			pass

	var uses_velocity: bool = state not in [State.JUMPING, State.DANGER_DELAY, State.RESET]
	if uses_velocity:
		var effective_max: float = _get_max_speed()
		var current_speed: float = velocity.length()
		var dot: float = velocity.normalized().dot(input) if current_speed > 0.001 and input != Vector2.ZERO else 0.0
		var over_max: bool = current_speed > effective_max
		if not can_accelerate or input == Vector2.ZERO or dot < 0.0 or over_max:
			velocity = velocity.move_toward(Vector2.ZERO, decel_rate * delta)
		if can_accelerate and input != Vector2.ZERO and not over_max:
			velocity = velocity.move_toward(input * effective_max, acceleration * delta)
		var col: KinematicCollision2D = move_and_collide(velocity * delta)
		if col:
			velocity = velocity.slide(col.get_normal())
		if _overlaps_layer(jumpable_danger_mask):
			velocity = Vector2.ZERO
			state = State.DANGER_DELAY
			state_timer = danger_delay_duration
			danger_sound.play()
	elif state == State.RESET:
		global_position = global_position.move_toward(_reset_target, reset_speed * delta)
		if global_position.distance_to(_reset_target) < 1.0:
			global_position = _reset_target
			collision_mask = _base_collision_mask
			state = State.NORMAL
			resetted.emit()
	elif state == State.JUMPING:
		var col: KinematicCollision2D = move_and_collide(_jump_velocity * delta)
		if col and not _landing_failed:
			if jump_interrupt_mask != 0:
				var ahead: Transform2D = _collision_shape.global_transform.translated(col.get_normal() * -1.0)
				if _shape_query(ahead, jump_interrupt_mask):
					camera.shake(0.4)
					fall_sound.play()
					_landing_failed = true
					_jump_velocity = Vector2.ZERO
					velocity = Vector2.ZERO
					return
			_jump_velocity = _jump_velocity.slide(col.get_normal())

	if ticks_timer:
		state_timer -= delta
		if state_timer <= 0.0:
			_on_timer_expired()
