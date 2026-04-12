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


## Override so cards never drag; PromptHandler does its own hit-testing.
func _handle_mouse_pressed() -> void:
	pass
