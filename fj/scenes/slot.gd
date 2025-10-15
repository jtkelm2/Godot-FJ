class_name Slot
extends Pile

@export var visibleToRed:bool=true
@export var visibleToBlue:bool=true

func visibleTo(color:G.PColor) -> bool:
	match color:
		G.PColor.Blue: return visibleToBlue
		G.PColor.Red: return visibleToRed
		_: return false
