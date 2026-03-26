class_name FJCard
extends Card

@export var color:G.PColor:
	set = _set_color

var slot:Slot = null

func _set_color(_color:G.PColor):
	color = _color
	if color == G.PColor.Blue:
		$BackFace/TextureRect.texture = G.blue_back_texture

func hide_card():
	$FrontFace/HidingFace.visible = true

func show_card():
	$FrontFace/HidingFace.visible = false

func get_texture() -> Texture2D:
	return $FrontFace/TextureRect.texture if !$FrontFace/HidingFace.visible else $FrontFace/HidingFace.texture

func _gui_input(event):
	if slot and event is InputEventMouseButton and event.pressed:
		Signals.slot_clicked.emit(slot)
