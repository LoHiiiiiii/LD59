class_name GameTimer
extends Node

signal countdown_finished
signal time_up

@export var time_label: Label
@export var countdown_label: Label
@export var start_time: float = 120.0
@export var step_duration: float = 0.8
@export var go_duration: float = 1.0
@export var go_sound: AudioStreamPlayer
@export var beep_sound: AudioStreamPlayer

enum _State { IDLE, COUNTDOWN, GO, RUNNING, STOPPED }

const _STEPS: Array[String] = ["3", "2", "1"]

var elapsed: float = 0.0

var _state: _State = _State.IDLE
var _step: int = 0
var _step_timer: float = 0.0
var _go_timer: float = 0.0

func begin_showing() -> void:
	_state = _State.COUNTDOWN
	_step = 0
	_step_timer = 0.0
	elapsed = 0.0
	if time_label:
		time_label.visible = false
	if countdown_label:
		countdown_label.text = _STEPS[0]
		countdown_label.visible = true
		beep_sound.play()

func begin_game() -> void:
	_state = _State.GO
	_go_timer = 0.0
	elapsed = 0.0
	go_sound.play()
	if countdown_label:
		countdown_label.text = "GO"
		countdown_label.visible = true
	if time_label:
		time_label.visible = false

func is_running() -> bool:
	return _state == _State.RUNNING or _state == _State.GO

func is_displaying() -> bool:
	return _state == _State.RUNNING or _state == _State.STOPPED

func stop() -> void:
	_state = _State.STOPPED

func hide_all() -> void:
	_state = _State.IDLE
	if time_label:
		time_label.visible = false
	if countdown_label:
		countdown_label.visible = false

func _process(delta: float) -> void:
	match _state:
		_State.COUNTDOWN:
			_step_timer += delta
			if _step_timer >= step_duration:
				_step_timer -= step_duration
				_step += 1
				if _step >= _STEPS.size():
					if countdown_label:
						countdown_label.visible = false
					countdown_finished.emit()
				else:
					if countdown_label:
						countdown_label.text = _STEPS[_step]
						beep_sound.play()
		_State.GO:
			elapsed += delta
			_go_timer += delta
			if _go_timer >= go_duration:
				_state = _State.RUNNING
				if countdown_label:
					countdown_label.visible = false
				if time_label:
					time_label.visible = true

		_State.RUNNING:
			elapsed += delta
			var remaining: float = maxf(start_time - elapsed, 0.0)
			if time_label:
				_update_time_label(remaining)
			if remaining <= 0.0:
				_state = _State.STOPPED
				time_up.emit()

func _update_time_label(remaining: float) -> void:
	var m: int = int(remaining / 60.0)
	var s: int = int(remaining) % 60
	var cs: int = int(remaining * 100.0) % 100
	time_label.text = "%02d:%02d.%02d" % [m, s, cs]
