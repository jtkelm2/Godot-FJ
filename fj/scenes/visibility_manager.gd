class_name VisibilityManager
extends Node

enum SlotType {
	HAND,              # Player's hand
	MANIPULATION,      # Manipulation field slots
	ACTION_HIDDEN,     # Hidden action slots
	ACTION_DISTANT,    # Distant action slots
	EQUIPMENT,         # Equipment slots
	WEAPON,            # Weapon slot
	KILL,              # Kill pile
	DECK,              # Draw deck
	REFRESH,           # Refresh pile
	DISCARD            # Discard pile
}

static func should_show(color:G.PColor, type:SlotType, slot_color:G.PColor) -> bool:
	match type:
		SlotType.ACTION_DISTANT: return true
		_: return color == slot_color

## Determines if a card in a specific zone owned by a player should show its front face
## to the current viewing player
#static func should_show_front(
	#card_owner: G.PColor,
	#zone_type: ZoneType,
	#viewing_player: G.PColor
#) -> bool:
	#var is_own_card = card_owner == viewing_player
	#
	#match zone_type:
		#ZoneType.HAND:
			## Only owner can see their hand
			#return is_own_card
			#
		#ZoneType.MANIPULATION:
			## Only owner can see their manipulation field
			#return is_own_card
			#
		#ZoneType.ACTION_HIDDEN:
			## Only owner can see their hidden action slots
			#return is_own_card
			#
		#ZoneType.ACTION_DISTANT:
			## Both players can see distant action slots (always face up per rulebook)
			#return true
			#
		#ZoneType.EQUIPMENT, ZoneType.WEAPON, ZoneType.KILL:
			## Equipment, weapons, and kill piles are visible to both players
			#return true
			#
		#ZoneType.DECK, ZoneType.REFRESH, ZoneType.DISCARD:
			## Piles are always face down
			#return false
	#
	#return false


## Determines if a zone should have a fog overlay (visual indicator of hidden area)
#static func should_show_fog_overlay(
	#zone_owner: G.PColor,
	#zone_type: ZoneType,
	#viewing_player: G.PColor
#) -> bool:
	#var is_own_zone = zone_owner == viewing_player
	#
	## No fog on your own zones
	#if is_own_zone:
		#return false
	#
	## Show fog on opponent's hidden zones
	#match zone_type:
		#ZoneType.HAND:
			#return true
		#ZoneType.MANIPULATION:
			#return true
		#ZoneType.ACTION_HIDDEN:
			#return true
	#
	#return false


## Determines if a zone should allow mouse interaction for the current player
#static func can_interact_with_zone(
	#zone_owner: G.PColor,
	#zone_type: ZoneType,
	#current_player: G.PColor
#) -> bool:
	#var is_own_zone = zone_owner == current_player
	#
	## Players can only interact with their own zones during their turn
	## (consent mechanics will be handled separately in action resolution)
	#return is_own_zone
