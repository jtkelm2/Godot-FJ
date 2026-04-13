class_name Card
extends Control

## A card face. Contract:
##   - front_texture / back_texture: setters, exposed in editor.
##   - is_faceup: true shows front, false shows back.
##   - flip(): toggle face.
##   - set_highlight(bool): purely visual prompt tint.
##   - clicked: emitted on left-mouse-down, always (filtering is the Board's job).

signal clicked

@export var front_texture: Texture2D: set = set_front
@export var back_texture: Texture2D: set = set_back
@export var is_faceup: bool = true: set = set_face

@onready var _front: TextureRect = $Front
@onready var _back: TextureRect = $Back


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
	modulate = Color(1.35, 1.35, 0.55) if on else Color.WHITE


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
