class_name BoxAnimator
extends Node

signal opened
signal closed

@export var box: Control
@export var duration: float = 0.3

var _t: float = 0.0
var _opening: bool = false
var _animating: bool = false

func _ready() -> void:
	_apply(0)

func open() -> void:
	if not _animating and _opening:
		return
	_opening = true
	_animating = true
	_t = 0.0
	box.visible = true
	_apply(0.0)

func close() -> void:
	if not _animating and not _opening:
		return
	_opening = false
	_animating = true
	_t = 0.0
	_apply(1.0)

func _process(delta: float) -> void:
	if not _animating:
		return
	_t = minf(_t + delta / duration, 1.0)
	var p: float = ease(_t, -2.0)
	_apply(p if _opening else 1.0 - p)
	if _t >= 1.0:
		_animating = false
		if _opening:
			opened.emit()
		else:
			box.visible = false
			closed.emit()

func _apply(scale: float) -> void:
	box.pivot_offset = box.size * 0.5
	box.scale = Vector2(scale, scale)
