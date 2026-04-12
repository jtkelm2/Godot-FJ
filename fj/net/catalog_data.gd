extends RefCounted

## Card template metadata keyed by card name.
var card_templates: Dictionary = {}

## Flat slot catalog: wire_name -> { "owner": "self"/"opponent"/"shared", "role": String }
var slots: Dictionary = {}

## Flat weapon slot catalog: wire_name -> { "owner": "self"/"opponent"/"shared", "role": String }
var weapon_slots: Dictionary = {}

## Convenience: role -> wire_name, grouped by owner
var self_slots: Dictionary = {}      # role -> wire_name
var opponent_slots: Dictionary = {}  # role -> wire_name
var shared_slots: Dictionary = {}    # role -> wire_name
var self_weapon_slots: Dictionary = {}
var opponent_weapon_slots: Dictionary = {}

## Set externally from the role_assignment notify, not inferred from catalog.
var my_color: String = ""


## Parse a catalog message dict and populate this instance.
func parse_from(msg: Dictionary) -> void:
	if msg.has("cards"):
		card_templates = msg["cards"]

	# Slots: flat dict keyed by wire_name, value has "owner" and "role"
	if msg.has("slots"):
		slots = msg["slots"]
		for wire_name in slots:
			var info: Dictionary = slots[wire_name]
			var owner_str: String = info.get("owner", "")
			var role: String = info.get("role", "")
			match owner_str:
				"self":
					self_slots[role] = wire_name
				"opponent":
					opponent_slots[role] = wire_name
				"shared":
					shared_slots[role] = wire_name

	# Weapon slots: same flat format
	if msg.has("weapon_slots"):
		weapon_slots = msg["weapon_slots"]
		for wire_name in weapon_slots:
			var info: Dictionary = weapon_slots[wire_name]
			var owner_str: String = info.get("owner", "")
			var role: String = info.get("role", "")
			match owner_str:
				"self":
					self_weapon_slots[role] = wire_name
				"opponent":
					opponent_weapon_slots[role] = wire_name



## Look up which owner and role a wire name belongs to.
func lookup_wire(wire_name: String) -> Dictionary:
	return slots.get(wire_name, {})


## Look up a weapon slot's owner and role.
func lookup_weapon_wire(wire_name: String) -> Dictionary:
	return weapon_slots.get(wire_name, {})
