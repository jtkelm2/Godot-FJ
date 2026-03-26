class_name Slot
extends Pile

@export var color: G.PColor = G.Red
@export var type: VisibilityManager.SlotType = VisibilityManager.SlotType.ACTION_DISTANT
var hiding: Dictionary[G.PColor, bool]

# Fog overlay for hidden zones
#var fog_overlay: ColorRect = null


func _ready() -> void:
	super._ready()
	_default_hiding()
	# Create fog overlay
	#_create_fog_overlay()
	
	# Connect to player switch signal
	#G.player_switched.connect(_on_player_switched)
	
	# Initial visibility update
	#_update_visibility()

func _default_hiding():
	hiding[G.Blue] = !VisibilityManager.should_show(G.Blue, type, color)
	hiding[G.Red] = !VisibilityManager.should_show(G.Red, type, color)

#func _create_fog_overlay() -> void:
	#fog_overlay = ColorRect.new()
	#fog_overlay.name = "FogOverlay"
	#fog_overlay.color = Color(0, 0, 0, 0.7)  # Semi-transparent black
	#fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	#fog_overlay.z_index = 4000  # Above cards
	#fog_overlay.visible = false
	#
	## Size to match the slot area (adjust based on your card size)
	#fog_overlay.custom_minimum_size = Vector2(85, 146)
	#fog_overlay.size = Vector2(85, 146)
	#
	#add_child(fog_overlay)


#func _on_player_switched(_new_player: G.PColor) -> void:
	#_update_visibility()


#func _update_visibility() -> void:
	#var viewing_player = G.current_player
	#
	#var show_fog = VisibilityManager.should_show_fog_overlay(
		#slot_owner,
		#zone_type,
		#viewing_player
	#)
	#if fog_overlay:
		#fog_overlay.visible = show_fog
	#
	## Update all cards in this slot
	#for card in _held_cards:
		#if card is FJCard:
			#var should_show_front = VisibilityManager.should_show_front(
				#slot_owner,
				#zone_type,
				#viewing_player
			#)
			#card.show_front = should_show_front
			#
			## Optionally disable interaction with opponent's hidden zones
			#var can_interact = VisibilityManager.can_interact_with_zone(
				#slot_owner,
				#zone_type,
				#viewing_player
			#)
			#card.can_be_interacted_with = can_interact and allow_card_movement

func add_card(card : Card, index : int = -1):
	super.add_card(card, index)
	if card is FJCard:
		_add_fj_card(card)

func _add_fj_card(card: FJCard) -> void:
	card.hide_card() if hiding[G.current_player] else card.show_card()
	assert(card.slot == null)
	card.slot = self

func get_cards() -> Array[FJCard]:
	var result:Array[FJCard]
	result.assign(get_top_cards(get_card_count()))
	return result

func remove_card(card: Card) -> bool:
	var result = super.remove_card(card)
	if card is FJCard:
		_remove_fj_card(card)
	return result

func _remove_fj_card(card:FJCard):
	assert(card.slot == self)
	card.slot = null
