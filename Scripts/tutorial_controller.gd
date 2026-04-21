class_name TutorialController
extends Node

@export var label: Label
@export var player: Player
@export var level: Level
@export var box_animator: BoxAnimator
@export var texts: Array[String] = []
@export var brief_label: Label
@export var brief_box_animator: BoxAnimator
@export var text_speed: float = 20.0
@export var trigger_delay: float = 0.5

var active: bool = false

var _brief: bool = false
var _index: int = 0
var _revealing: bool = false
var _visible_chars: float = 0.0
var _trigger_timer: float = 0.0

func start() -> void:
	_brief = false
	_close_then_open(brief_box_animator, brief_label)

func start_brief() -> void:
	_brief = true
	_close_then_open(box_animator, label)

func _close_then_open(closing_animator: BoxAnimator, closing_label: Label) -> void:
	if closing_label:
		closing_label.visible_characters = 0
	if closing_animator and (closing_animator._opening or closing_animator._animating):
		if not closing_animator.closed.is_connected(_open_current_animator):
			closing_animator.closed.connect(_open_current_animator, CONNECT_ONE_SHOT)
		closing_animator.close()
	else:
		_open_current_animator()

func _open_current_animator() -> void:
	var animator := _current_animator()
	if not animator:
		_on_box_opened()
		return
	if not animator._animating and animator._opening:
		_on_box_opened()
		return
	if not animator.opened.is_connected(_on_box_opened):
		animator.opened.connect(_on_box_opened, CONNECT_ONE_SHOT)
	animator.open()

func _on_box_opened() -> void:
	active = true
	_revealing = true
	_update_label()

func stop() -> void:
	_index = 1
	_revealing = false
	var lbl := _current_label()
	if lbl:
		lbl.visible_characters = 0
	var animator := _current_animator()
	if animator:
		animator.close()

var _saved_index: int = -1

func enter_name_mode() -> void:
	if not active:
		return
	_saved_index = _index
	_index = 0
	_brief = false
	_close_then_open(brief_box_animator, brief_label)

func exit_name_mode() -> void:
	if _saved_index < 0:
		return
	_index = _saved_index
	_saved_index = -1
	_update_label()

func is_brief() -> bool:
	return _brief

func notify_respected() -> void:
	if _revealing or not active or _trigger_timer > 0:
		return
	if _index == 3:
		_try_advance()

func _process(delta: float) -> void:
	if not active:
		return

	if _revealing:
		var animator := _current_animator()
		if animator and animator._animating:
			return
		_visible_chars += text_speed * delta
		var lbl := _current_label()
		if lbl:
			lbl.visible_characters = int(_visible_chars)
			if lbl.visible_characters >= lbl.get_total_character_count():
				lbl.visible_characters = -1
				_revealing = false
				_trigger_timer = trigger_delay
		return

	if _brief:
		return

	if _trigger_timer > 0.0:
		_trigger_timer -= delta
		return

	_check_trigger()

func _check_trigger() -> void:
	match _index:
		0:
			if level and level._phase != Level.Phase.NAME:
				_try_advance()
		2:
			var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			if move != Vector2.ZERO:
				_try_advance()
		1:
			var radar := Input.get_vector("radar_left", "radar_right", "radar_up", "radar_down")
			if radar != Vector2.ZERO:
				_try_advance()
		4:
			if player and player.state == Player.State.JUMPING:
				_try_advance()
		5:
			if player and player.state == Player.State.JUMP_DISABLED:
				_try_advance()

func _try_advance() -> void:
	if _revealing or _index >= texts.size() - 1:
		return
	_index += 1
	_update_label()

func _update_label() -> void:
	var lbl := _current_label()
	if not lbl:
		return
	if not _brief and _index >= 0 and _index < texts.size():
		lbl.text = texts[_index]
	if _brief:
		lbl.visible_characters = -1
		_revealing = false
	else:
		lbl.visible_characters = 0
		_visible_chars = 0.0
		_revealing = true

func _current_label() -> Label:
	return brief_label if _brief else label

func _current_animator() -> BoxAnimator:
	return brief_box_animator if _brief else box_animator

