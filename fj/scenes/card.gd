class_name FJCard
extends Card

@export var color:G.PColor:
	set = _set_color
	
func _set_color(_color:G.PColor):
	color = _color
	if color == G.PColor.Blue:
		$BackFace/TextureRect.texture = G.blue_back_texture
