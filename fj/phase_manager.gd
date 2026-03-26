extends Node

# "Setup"
# "Refresh"
# "Manipulation"
# "Action"
# "Hierophant_Red"
# "Hierophant_Blue"

# In setup, nothing is clickable, nothing is draggable
# In manipulation, the hand and manipulation slots are draggable, and equipment slots are clickable (forcing)
# In action, equipment and weapon slots are clickable (discard), action slots are clickable (resolve), deck is clickable (resolve if nothing else is available)
# In Hierophant, hand cards are draggable to either half of the action field, or clickable
#
#
#
#


@export var card_manager:CardManager
var resolutions_remaining:Dictionary[G.PColor,int]
var current_phase:String
var processing:bool = false

func _ready():
	change_phase("Action")

func change_phase(new_phase:String):
	current_phase = new_phase
	Signals.phase_changed.emit(new_phase)
