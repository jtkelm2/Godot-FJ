extends RefCounted

## Card template metadata keyed by card name.
var card_templates: Dictionary = {}

## Slot mappings: semantic_role -> wire_name
var self_slots: Dictionary = {}
var opponent_slots: Dictionary = {}
var shared_slots: Dictionary = {}

## Weapon slot mappings: semantic_role -> wire_name
var self_weapon_slots: Dictionary = {}
var opponent_weapon_slots: Dictionary = {}

## Reverse lookup: wire_name -> { "owner": "self"/"opponent"/"shared", "role": semantic_role }
var wire_to_semantic: Dictionary = {}

## Derived from wire names (e.g., "RED" if self slots contain "red_*")
var my_color: String = ""


## Parse a catalog message dict and populate this instance.
func parse_from(msg: Dictionary) -> void:
	# Parse card templates
	if msg.has("cards"):
		card_templates = msg["cards"]

	# Parse slot mappings
	if msg.has("slots"):
		var slots: Dictionary = msg["slots"]
		if slots.has("self"):
			self_slots = slots["self"]
		if slots.has("opponent"):
			opponent_slots = slots["opponent"]
		if slots.has("shared"):
			shared_slots = slots["shared"]

	# Parse weapon slot mappings
	if msg.has("weapon_slots"):
		var ws: Dictionary = msg["weapon_slots"]
		if ws.has("self"):
			self_weapon_slots = ws["self"]
		if ws.has("opponent"):
			opponent_weapon_slots = ws["opponent"]

	# Build reverse lookup
	for role in self_slots:
		var wire_name: String = self_slots[role]
		wire_to_semantic[wire_name] = {"owner": "self", "role": role}

	for role in opponent_slots:
		var wire_name: String = opponent_slots[role]
		wire_to_semantic[wire_name] = {"owner": "opponent", "role": role}

	for role in shared_slots:
		var wire_name: String = shared_slots[role]
		wire_to_semantic[wire_name] = {"owner": "shared", "role": role}

	# Derive color from self slot wire names
	my_color = _infer_color(self_slots)


static func _infer_color(slots: Dictionary) -> String:
	for role in slots:
		var wire_name: String = slots[role]
		if wire_name.begins_with("red_"):
			return "RED"
		elif wire_name.begins_with("blue_"):
			return "BLUE"
	return ""


## Get the wire name for a semantic role on our side.
func get_self_wire(role: String) -> String:
	return self_slots.get(role, "")


## Get the wire name for a semantic role on the opponent's side.
func get_opponent_wire(role: String) -> String:
	return opponent_slots.get(role, "")


## Get the wire name for a shared semantic role.
func get_shared_wire(role: String) -> String:
	return shared_slots.get(role, "")


## Look up which owner and role a wire name belongs to.
func lookup_wire(wire_name: String) -> Dictionary:
	return wire_to_semantic.get(wire_name, {})
