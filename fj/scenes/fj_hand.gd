class_name FJHand
extends Hand

@export var hand_owner: G.PColor = G.PColor.Red
var fog_overlay: ColorRect = null


func _ready() -> void:
	super._ready()
	
	_create_fog_overlay()
	
	G.player_switched.connect(_on_player_switched)
	
	_update_visibility()


func _create_fog_overlay() -> void:
	fog_overlay = ColorRect.new()
	fog_overlay.name = "HandFogOverlay"
	fog_overlay.color = Color(0, 0, 0, 0.7)  # Semi-transparent black
	fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_overlay.z_index = 5000  # Above cards
	fog_overlay.visible = false
	
	# Size to cover the entire hand area
	fog_overlay.custom_minimum_size = Vector2(max_hand_spread, 300)
	fog_overlay.size = Vector2(max_hand_spread, 300)
	fog_overlay.position = Vector2(-max_hand_spread / 2, -150)
	
	add_child(fog_overlay)


func _on_player_switched(_new_player: G.PColor) -> void:
	_update_visibility()


func _update_visibility() -> void:
	var viewing_player = G.current_player
	
	# Update fog overlay
	var show_fog = VisibilityManager.should_show_fog_overlay(
		hand_owner,
		VisibilityManager.ZoneType.HAND,
		viewing_player
	)
	if fog_overlay:
		fog_overlay.visible = show_fog
	
	# Update all cards in hand
	for card in _held_cards:
		if card is FJCard:
			var should_show_front = VisibilityManager.should_show_front(
				hand_owner,
				VisibilityManager.ZoneType.HAND,
				viewing_player
			)
			card.show_front = should_show_front
			
			# Disable interaction with opponent's hand
			var can_interact = VisibilityManager.can_interact_with_zone(
				hand_owner,
				VisibilityManager.ZoneType.HAND,
				viewing_player
			)
			card.can_be_interacted_with = can_interact


# Override to update visibility when cards are added
func add_card(card: Card, index: int = -1) -> void:
	super.add_card(card, index)
	_update_visibility()


# Override to update visibility when cards are removed
func remove_card(card: Card) -> bool:
	var result = super.remove_card(card)
	_update_visibility()
	return result
