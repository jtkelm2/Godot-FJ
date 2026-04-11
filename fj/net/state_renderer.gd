extends Node

## Maps semantic roles to scene node paths under CardManager.
## "self" roles map to Red* nodes, "opponent" to Blue* nodes.
## If we're actually BLUE, we swap during initialization.
const RED_ROLE_MAP := {
	"hand": "RHand",
	"deck": "RDeck",
	"refresh": "RedRefresh",
	"discard": "RedDiscardSlot",
	"equipment": ["RedEquipmentSlot1", "RedEquipmentSlot2"],
	"sidebar": [],  # sidebar may use manipulation slots or a new node
	"action_field_top_distant": "RedDistantSlot1",
	"action_field_top_hidden": "RedHiddenSlot1",
	"action_field_bottom_hidden": "RedHiddenSlot2",
	"action_field_bottom_distant": "RedDistantSlot2",
	"ws_0_weapon": "RedWeaponSlot",
	"ws_0_killstack": "RedKillSlot",
}

const BLUE_ROLE_MAP := {
	"hand": "BHand",
	"deck": "BDeck",
	"refresh": "BlueRefresh",
	"discard": "BlueDiscardSlot",
	"equipment": ["BlueEquipmentSlot1", "BlueEquipmentSlot2"],
	"sidebar": [],
	"action_field_top_distant": "BlueDistantSlot1",
	"action_field_top_hidden": "BlueHiddenSlot1",
	"action_field_bottom_hidden": "BlueHiddenSlot2",
	"action_field_bottom_distant": "BlueDistantSlot2",
	"ws_0_weapon": "BlueWeaponSlot",
	"ws_0_killstack": "BlueKillSlot",
}

var card_manager: CardManager
var card_factory: FjCardFactory
var catalog  # CatalogData
var image_resolver  # ImageResolver

## wire_name -> CardContainer (single slot or hand)
var wire_to_container: Dictionary = {}

## wire_name -> Array[CardContainer] (for equipment which spans 2 slots)
var wire_to_multi_container: Dictionary = {}

## Back textures for self and opponent cards
var self_back: Texture2D
var opponent_back: Texture2D


func initialize(p_catalog: RefCounted, p_card_manager: CardManager, p_card_factory: FjCardFactory) -> void:
	catalog = p_catalog
	card_manager = p_card_manager
	card_factory = p_card_factory
	image_resolver = card_factory.image_resolver

	G.my_side = catalog.my_color

	# Determine which physical side maps to self vs opponent.
	# Self always uses Red physical nodes if we're RED, Blue if we're BLUE.
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

	# Map self slots
	_build_mapping(catalog.self_slots, self_map, self_back, "self")

	# Map opponent slots
	_build_mapping(catalog.opponent_slots, opp_map, opponent_back, "opponent")

	# Map shared slots (e.g., guard_deck) -- no scene nodes for these currently
	for role in catalog.shared_slots:
		var wire_name: String = catalog.shared_slots[role]
		push_warning("StateRenderer: shared slot '%s' (%s) has no scene node mapping" % [role, wire_name])


func _build_mapping(slots: Dictionary, role_map: Dictionary, _back: Texture2D, owner: String) -> void:
	for role in slots:
		var wire_name: String = slots[role]
		if not role_map.has(role):
			push_warning("StateRenderer: no node mapping for role '%s' (wire: %s, owner: %s)" % [role, wire_name, owner])
			continue

		var node_ref = role_map[role]

		if node_ref is Array:
			# Multi-slot (equipment)
			var containers: Array[CardContainer] = []
			for node_name in node_ref:
				var container := _get_container(node_name)
				if container:
					_tag_container(container, wire_name, role)
					containers.append(container)
			if not containers.is_empty():
				wire_to_multi_container[wire_name] = containers
		elif node_ref is String:
			var container := _get_container(node_ref)
			if container:
				_tag_container(container, wire_name, role)
				wire_to_container[wire_name] = container


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


## Update the entire visual board from a server state snapshot.
func render_state(view: Dictionary) -> void:
	var slots_data: Dictionary = view.get("slots", {})

	for wire_name in slots_data:
		var value = slots_data[wire_name]

		if wire_to_container.has(wire_name):
			var container: CardContainer = wire_to_container[wire_name]
			_reconcile_container(container, value, wire_name)
		elif wire_to_multi_container.has(wire_name):
			var containers: Array = wire_to_multi_container[wire_name]
			_reconcile_multi_container(containers, value, wire_name)
		# else: unmapped wire name (e.g. shared slots), skip silently


func _reconcile_container(container: CardContainer, value: Variant, wire_name: String) -> void:
	if value is Array:
		_reconcile_visible_cards(container, value, wire_name)
	elif value is int or value is float:
		_reconcile_facedown_count(container, int(value), wire_name)


func _reconcile_multi_container(containers: Array, value: Variant, wire_name: String) -> void:
	if value is Array:
		# Distribute cards across multiple slots (e.g. equipment across 2 slots)
		var card_names: Array = value
		for i in containers.size():
			if i < card_names.size():
				_reconcile_visible_cards(containers[i], [card_names[i]], wire_name)
			else:
				_reconcile_visible_cards(containers[i], [], wire_name)
	elif value is int or value is float:
		# Distribute count across slots (show all in first slot)
		var count := int(value)
		_reconcile_facedown_count(containers[0], count, wire_name)
		for i in range(1, containers.size()):
			_reconcile_facedown_count(containers[i], 0, wire_name)


func _reconcile_visible_cards(container: CardContainer, card_names: Array, wire_name: String) -> void:
	var current_cards: Array = container._held_cards.duplicate()
	var target_size := card_names.size()
	var current_size := current_cards.size()

	# Determine back texture from wire name ownership
	var back_texture := _back_for_wire(wire_name)

	# Compare by index: keep cards that match, replace mismatches
	var cards_to_keep := mini(current_size, target_size)
	var i := 0

	while i < cards_to_keep:
		var existing: Card = current_cards[i]
		var target_name: String = card_names[i]
		if existing.card_name != target_name:
			# Mismatch at this index -- remove old, insert new
			container.remove_card(existing)
			_tween_remove(existing)
			var new_card := card_factory.create_network_card(target_name, back_texture, container)
			if new_card:
				new_card.show_front = true
		else:
			# Card matches, ensure it's face-up
			existing.show_front = true
		i += 1

	# Remove excess cards
	while i < current_size:
		var excess: Card = current_cards[i]
		container.remove_card(excess)
		_tween_remove(excess)
		i += 1

	# Add missing cards
	var j := cards_to_keep
	while j < target_size:
		var new_name: String = card_names[j]
		var new_card := card_factory.create_network_card(new_name, back_texture, container)
		if new_card:
			new_card.show_front = true
		j += 1


func _reconcile_facedown_count(container: CardContainer, count: int, wire_name: String) -> void:
	var current_count := container.get_card_count()
	var back_texture := _back_for_wire(wire_name)

	if current_count < count:
		for i in range(count - current_count):
			var card := card_factory.create_facedown_card(back_texture, container)
			if card:
				card.show_front = false
	elif current_count > count:
		var cards_to_remove: Array = container._held_cards.duplicate()
		for i in range(current_count - count):
			var card: Card = cards_to_remove[cards_to_remove.size() - 1 - i]
			container.remove_card(card)
			card.queue_free()


func _back_for_wire(wire_name: String) -> Texture2D:
	var info: Dictionary = catalog.lookup_wire(wire_name)
	if info.get("owner", "") == "self":
		return self_back
	return opponent_back


func _tween_remove(card: Card) -> void:
	var tween := card.create_tween()
	tween.tween_property(card, "modulate:a", 0.0, 0.2)
	tween.tween_callback(card.queue_free)
