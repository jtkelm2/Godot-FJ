class_name FJCard
extends Card

## The prompt option dict to echo back when this card is clicked during a prompt.
var prompt_option: Dictionary = {}

## Whether this card is highlighted as a valid prompt choice.
var _highlighted: bool = false


func hide_card() -> void:
	$FrontFace/HidingFace.visible = true


func show_card() -> void:
	$FrontFace/HidingFace.visible = false


func get_texture() -> Texture2D:
	if $FrontFace/HidingFace.visible:
		return $FrontFace/HidingFace.texture
	return $FrontFace/TextureRect.texture


func set_highlighted(enabled: bool) -> void:
	_highlighted = enabled
	if enabled:
		modulate = Color(1.2, 1.2, 0.6, 1.0)
	else:
		modulate = Color.WHITE
		prompt_option = {}


## Override: click-only, no dragging. Emit card_clicked signal.
func _handle_mouse_pressed() -> void:
	if _highlighted:
		Signals.card_clicked.emit(self)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _highlighted:
			Signals.card_clicked.emit(self)
