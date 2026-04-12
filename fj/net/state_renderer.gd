extends Node

const SlotViewScript = preload("res://fj/net/slot_view.gd")

## Maps semantic roles to scene node paths under CardManager.
## Always an Array so the single-vs-multi distinction disappears.
const RED_ROLE_MAP := {
	"hand": ["RHand"],
	"deck": ["RDeck"],
	"refresh": ["RedRefresh"],
	"discard": ["RedDiscardSlot"],
	"equipment": ["RedEquipmentSlot1", "RedEquipmentSlot2"],
	"sidebar": ["RedSidebar1", "RedSidebar2", "RedSidebar3", "RedSidebar4"],
	"action_field_top_distant": ["RedDistantSlot1"],
	"action_field_top_hidden": ["RedHiddenSlot1"],
	"action_field_bottom_hidden": ["RedHiddenSlot2"],
	"action_field_bottom_distant": ["RedDistantSlot2"],
	"ws_0_weapon": ["RedWeaponSlot"],
	"ws_0_killstack": ["RedKillSlot"],
}

const BLUE_ROLE_MAP := {
	"hand": ["BHand"],
	"deck": ["BDeck"],
	"refresh": ["BlueRefresh"],
	"discard": ["BlueDiscardSlot"],
	"equipment": ["BlueEquipmentSlot1", "BlueEquipmentSlot2"],
	"sidebar": ["BlueSidebar1", "BlueSidebar2", "BlueSidebar3", "BlueSidebar4"],
	"action_field_top_distant": ["BlueDistantSlot1"],
	"action_field_top_hidden": ["BlueHiddenSlot1"],
	"action_field_bottom_hidden": ["BlueHiddenSlot2"],
	"action_field_bottom_distant": ["BlueDistantSlot2"],
	"ws_0_weapon": ["BlueWeaponSlot"],
	"ws_0_killstack": ["BlueKillSlot"],
}

const SHARED_ROLE_MAP := {
	"guard_deck": ["GuardDeck"]
}

var card_manager: CardManager
var card_factory: FjCardFactory
var catalog  # CatalogData
var image_resolver  # ImageResolver

## wire_name -> SlotView
var slot_views: Dictionary = {}

## CardContainer -> SlotView (reverse lookup for click routing)
var container_to_view: Dictionary = {}

var self_back: Texture2D
var opponent_back: Texture2D
var neutral_back: Texture2D


func initialize(p_catalog: RefCounted, p_card_manager: CardManager, p_card_factory: FjCardFactory) -> void:
	catalog = p_catalog
	card_manager = p_card_manager
	card_factory = p_card_factory
	image_resolver = card_factory.image_resolver

	G.my_side = catalog.my_color

	var self_map: Dictionary
	var opp_map: Dictionary
	if catalog.my_color == "RED":
		self_map = RED_ROLE_MAP
		opp_map = BLUE_ROLE_MAP
	else:
		self_map = BLUE_ROLE_MAP
		opp_map = RED_ROLE_MAP

	self_back = image_resolver.get_back_texture(catalog.my_color)
	var opp_color := "BLUE" if catalog.my_color == "RED" else "RED"
	opponent_back = image_resolver.get_back_texture(opp_color)
	neutral_back = image_resolver.get_back_texture("SHARED")

	_build_slot_views(catalog.self_slots, self_map, self_back, "self")
	_build_slot_views(catalog.opponent_slots, opp_map, opponent_back, "opponent")
	_build_slot_views(catalog.shared_slots, SHARED_ROLE_MAP, neutral_back, "shared")


func _build_slot_views(slots_by_role: Dictionary, role_map: Dictionary, back_texture: Texture2D, slot_owner: String) -> void:
	for role in slots_by_role:
		var wire_name: String = slots_by_role[role]
		if not role_map.has(role):
			push_warning("StateRenderer: no node mapping for role '%s' (wire: %s, owner: %s)" % [role, wire_name, slot_owner])
			continue

		var node_names: Array = role_map[role]
		var containers: Array = []
		for node_name in node_names:
			var container := _get_container(node_name)
			if container:
				_tag_container(container, wire_name, role)
				containers.append(container)

		if containers.is_empty():
			continue

		var view = SlotViewScript.new()
		view.wire_name = wire_name
		view.role = role
		view.owner = slot_owner
		view.containers = containers
		view.back_texture = back_texture
		view.card_factory = card_factory

		slot_views[wire_name] = view
		for c in containers:
			container_to_view[c] = view


func _get_container(node_name: String) -> CardContainer:
	var node := card_manager.get_node_or_null(node_name)
	if node == null:
		push_error("StateRenderer: node '%s' not found under CardManager" % node_name)
		return null
	return node as CardContainer


func _tag_container(container: CardContainer, wire_name: String, role: String) -> void:
	if container is Slot:
		(container as Slot).wire_name = wire_name
		(container as Slot).semantic_role = role
	elif container is FJHand:
		(container as FJHand).wire_name = wire_name
		(container as FJHand).semantic_role = role


## Get the SlotView for a given wire name (or null).
func get_slot_view(wire_name: String):
	return slot_views.get(wire_name)


## Reverse lookup: get the SlotView that owns a given physical container.
func get_view_for_container(container):
	return container_to_view.get(container)


## Update the entire visual board from a server state snapshot.
func render_state(view: Dictionary) -> void:
	var slots_data: Dictionary = view.get("slots", {})

	for wire_name in slot_views:
		var slot_view = slot_views[wire_name]
		if slots_data.has(wire_name):
			var value = slots_data[wire_name]
			if value is Array:
				slot_view.set_visible_cards(value)
			elif value is int or value is float:
				slot_view.set_facedown_count(int(value))
		else:
			# Fog-of-war hidden: absent from state, clear the visual.
			slot_view.clear()
