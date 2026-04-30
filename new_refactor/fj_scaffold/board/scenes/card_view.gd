## CardView: a single card widget — front face + back face + highlight tint.
## Renderer-internal. Knows nothing of NL: callers pass Texture2D references
## directly (the Conductor pulls them from CardTemplate / Catalog).
##
## Public surface:
##   set_front(texture)           — swap the front face texture.
##   set_back(texture)            — swap the back face texture.
##   set_face(faceup: bool)       — show front (true) or back (false).
##   flip()                       — toggle face.
##   set_highlight(level)         — visual prompt decoration (HighlightLevel.Level).
##   clicked: signal              — left mouse down on the card.

class_name CardView extends Control


signal clicked


const HIGHLIGHT_PULSE_DURATION := 1.1
const HIGHLIGHT_PEAK_ALPHA := 0.35


@export var front_texture: Texture2D: set = set_front
@export var back_texture: Texture2D: set = set_back
@export var is_faceup: bool = true: set = set_face


@onready var _front: TextureRect = $Front
@onready var _back: TextureRect = $Back
@onready var _tint: ColorRect = $HighlightTint
@onready var _context_arrow: Node2D = $ContextArrow


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


func set_highlight(level: HighlightLevel.Level) -> void:
	_set_pulse_tint(level == HighlightLevel.Level.HIGHLIGHT)
	_set_context_arrow(level == HighlightLevel.Level.CONTEXT)


func _set_pulse_tint(on: bool) -> void:
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


func _set_context_arrow(on: bool) -> void:
	_context_arrow.visible = on


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
