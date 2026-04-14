class_name Card
extends Control

## A card face. Contract:
##   - front_texture / back_texture: setters, exposed in editor.
##   - is_faceup: true shows front, false shows back.
##   - flip(): toggle face.
##   - set_highlight(bool): purely visual prompt tint.
##   - clicked: emitted on left-mouse-down, always (filtering is the Board's job).

signal clicked

const HIGHLIGHT_PULSE_DURATION := 1.1
const HIGHLIGHT_PEAK_ALPHA := 0.35

const _SCENE: PackedScene = preload("res://fj/ui/card.tscn")


## Instantiate a Card with the given front/back textures and face-up state.
## Returns the new Card (not yet parented — caller adds it to a scene tree).
static func create(front: Texture2D, back: Texture2D, faceup: bool) -> Card:
	var c: Card = _SCENE.instantiate()
	c.set_front(front)
	c.set_back(back)
	c.set_face(faceup)
	return c

@export var front_texture: Texture2D: set = set_front
@export var back_texture: Texture2D: set = set_back
@export var is_faceup: bool = true: set = set_face

@onready var _front: TextureRect = $Front
@onready var _back: TextureRect = $Back
@onready var _tint: ColorRect = $HighlightTint

var _pulse_tween: Tween = null


func _ready() -> void:
	_apply_textures()
	_apply_face()


func set_front(tex: Texture2D) -> void:
	front_texture = tex
	if is_inside_tree():
		_front.texture = tex


func set_back(tex: Texture2D) -> void:
	back_texture = tex
	if is_inside_tree():
		_back.texture = tex


func set_face(faceup: bool) -> void:
	is_faceup = faceup
	if is_inside_tree():
		_apply_face()


func flip() -> void:
	set_face(not is_faceup)


func set_highlight(on: bool) -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if on:
		_tint.visible = true
		_tint.color.a = 0.0
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(_tint, "color:a", HIGHLIGHT_PEAK_ALPHA, HIGHLIGHT_PULSE_DURATION * 0.5).set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(_tint, "color:a", 0.0, HIGHLIGHT_PULSE_DURATION * 0.5).set_trans(Tween.TRANS_SINE)
	else:
		_tint.visible = false
		_tint.color.a = 0.0


func _apply_textures() -> void:
	_front.texture = front_texture
	_back.texture = back_texture


func _apply_face() -> void:
	_front.visible = is_faceup
	_back.visible = not is_faceup


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()
