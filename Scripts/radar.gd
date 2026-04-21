class_name Radar
extends Node2D

@export var player: Player
@export var player_sprite: CanvasItem
@export var speed_modifier: float
@export var minimum_duration: float
@export var retract_duration: float
@export var slerp_speed: float
@export var line_length: float
@export var start_dot_spacing: float
@export var dot_spacing: float
@export var dot_size: float
@export var dot_move_speed: float
@export var min_dot_distance: float
@export var angle_threshold: float
@export var indicator_size: float
@export var indicator_min_distance: float
@export var visible_duration: float
@export var cooldown_duration: float
@export var dot_color: Color
@export var color_cold: Color
@export var color_medium: Color
@export var color_hot: Color
@export var dist_cold: float
@export var dist_medium: float
@export var dist_hot: float
@export var radar_sound: AudioStreamPlayer2D
@export var detect_sound: AudioStreamPlayer2D

const _PHASE_HIDDEN: int = 0
const _PHASE_VISIBLE: int = 1
const _PHASE_COOLDOWN: int = 2

const _TEMP_COLD: int = 0
const _TEMP_MEDIUM: int = 1
const _TEMP_HOT: int = 2

var on: bool = false
var _emitting: bool = false
var _scan_timer: float = 0.0
var _line_progress: float = 0.0
var _radar_dir: Vector2 = Vector2.ZERO
var _draw_dir: Vector2 = Vector2.ZERO
var _ind_phase: Array[int] = []
var _ind_timer: Array[float] = []
var _ind_dir: Array[Vector2] = []
var _ind_dist: Array[float] = []
var _ind_temp: Array[int] = []

func _set_radar_shader(value: bool) -> void:
	if player_sprite and player_sprite.material:
		player_sprite.material.set_shader_parameter(&"radar_on", value)

func _turn_off() -> void:
	if _emitting:
		player.remove_speed_modifier(self)
	_emitting = false
	_scan_timer = 0.0
	radar_sound.stop()
	_set_radar_shader(false)

func _sync_indicator_state() -> void:
	var count: int = player.level.collectable_positions.size()
	if _ind_phase.size() == count:
		return
	_ind_phase.resize(count)
	_ind_timer.resize(count)
	_ind_dir.resize(count)
	_ind_dist.resize(count)
	_ind_temp.resize(count)
	for i: int in count:
		_ind_phase[i] = _PHASE_HIDDEN
		_ind_timer[i] = 0.0
		_ind_dir[i] = Vector2.ZERO
		_ind_dist[i] = 0.0
		_ind_temp[i] = _TEMP_COLD

func _process(delta: float) -> void:
	var active_state: bool = player.state == Player.State.NORMAL or player.state == Player.State.JUMPING

	if _emitting and not active_state:
		_turn_off()

	var radar: Vector2 = Vector2(
		Input.get_axis("radar_left", "radar_right"),
		Input.get_axis("radar_up", "radar_down")
	)

	if radar != Vector2.ZERO:
		_radar_dir = radar.normalized()

	if active_state and not _emitting and radar != Vector2.ZERO:
		on = true
		radar_sound.play()
		_emitting = true
		_scan_timer = 0.0
		_draw_dir = _radar_dir
		player.add_disturbance()
		player.add_speed_modifier(self, speed_modifier)
		_set_radar_shader(true)

	if _emitting:
		if radar == Vector2.ZERO:
			_turn_off()
		else:
			var angle_diff: float = _draw_dir.angle_to(_radar_dir)
			_draw_dir = _draw_dir.rotated(clampf(angle_diff, -slerp_speed * delta, slerp_speed * delta))
			_scan_timer += delta

			if player.level and _line_progress >= 1.0:
				_sync_indicator_state()
				var threshold_rad: float = deg_to_rad(angle_threshold)
				for i: int in player.level.collectable_positions.size():
					var to: Vector2 = player.level.collectable_positions[i] - global_position
					var dist: float = to.length()
					if _ind_phase[i] == _PHASE_HIDDEN and dist > 0.0:
						if absf(_draw_dir.angle_to(to.normalized())) <= threshold_rad:
							_ind_phase[i] = _PHASE_VISIBLE
							_ind_timer[i] = 0.0
							_ind_dir[i] = to.normalized()
							_ind_dist[i] = dist
							_ind_temp[i] = player.level.get_collectable_temperature(i, global_position)
							detect_sound.play()

	if on:
		var rate: float = (1.0 / minimum_duration) if minimum_duration > 0.0 else 1.0
		if _emitting:
			_line_progress = minf(_line_progress + rate * delta, 1.0)
		else:
			var retract_rate: float = (1.0 / retract_duration) if retract_duration > 0.0 else 1.0
			_line_progress = maxf(_line_progress - retract_rate * delta, 0.0)
			if _line_progress <= 0.0:
				on = false
				_draw_dir = Vector2.ZERO

	if player.level:
		for i: int in _ind_phase.size():
			match _ind_phase[i]:
				_PHASE_VISIBLE:
					_ind_timer[i] += delta
					if _ind_timer[i] >= visible_duration:
						_ind_phase[i] = _PHASE_COOLDOWN
						_ind_timer[i] = 0.0
				_PHASE_COOLDOWN:
					_ind_timer[i] += delta
					if _ind_timer[i] >= cooldown_duration:
						_ind_phase[i] = _PHASE_HIDDEN
						_ind_timer[i] = 0.0

	queue_redraw()

func _draw() -> void:
	if on and _draw_dir != Vector2.ZERO:
		var current_length: float = lerpf(0.0, line_length, _line_progress)
		var current_spacing: float = lerpf(start_dot_spacing, dot_spacing, _line_progress)
		var phase: float = fmod(_scan_timer * dot_move_speed, current_spacing) if current_spacing > 0.0 else 0.0
		var t: float = min_dot_distance + phase
		if current_spacing > 0.0:
			while t <= current_length:
				draw_rect(Rect2(_draw_dir * t - Vector2.ONE * dot_size * 0.5, Vector2.ONE * dot_size), dot_color)
				t += current_spacing

	if not player.level:
		return

	for i: int in _ind_phase.size():
		if _ind_phase[i] != _PHASE_VISIBLE:
			continue
		var fade: float = 1.0 - (_ind_timer[i] / visible_duration)
		var size: float = indicator_size * fade
		var display_dist: float = _temp_dist(_ind_temp[i])
		var color: Color = _temp_color(_ind_temp[i])
		var half: float = size * 0.5
		draw_rect(Rect2(_ind_dir[i] * display_dist - Vector2.ONE * half, Vector2.ONE * size), color)

func _temp_dist(temp: int) -> float:
	match temp:
		_TEMP_HOT: return dist_hot
		_TEMP_MEDIUM: return dist_medium
		_: return dist_cold

func _temp_color(temp: int) -> Color:
	match temp:
		_TEMP_HOT: return color_hot
		_TEMP_MEDIUM: return color_medium
		_: return color_cold
