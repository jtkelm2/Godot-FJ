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

## Routes a self-side regular slot wire (e.g. "red_ws_0_weapon") back to its
## owning weapon slot. Each entry is keyed by the interior slot's wire and
## carries the parent weapon slot's wire plus which interior position it is:
##   { "ws_wire": "red_ws_0", "kind": "holster" | "killstack" }
## Built once during parse_from. Empty for opponent-owned weapons (they're
## hidden information per protocol §3.2).
var self_weapon_interior_slots: Dictionary = {}

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

	# Build the interior-slot routing table for self-side weapons. For each
	# self weapon slot ws_N, find the regular slots ws_N_weapon (holster) and
	# ws_N_killstack and record their parent ws wire + which interior they are.
	for ws_role in self_weapon_slots:
		var ws_wire: String = self_weapon_slots[ws_role]
		var holster_wire: String = self_slots.get(ws_role + "_weapon", "")
		var killstack_wire: String = self_slots.get(ws_role + "_killstack", "")
		if not holster_wire.is_empty():
			self_weapon_interior_slots[holster_wire] = {"ws_wire": ws_wire, "kind": "holster"}
		if not killstack_wire.is_empty():
			self_weapon_interior_slots[killstack_wire] = {"ws_wire": ws_wire, "kind": "killstack"}



## Look up which owner and role a wire name belongs to.
func lookup_wire(wire_name: String) -> Dictionary:
	return slots.get(wire_name, {})


## Look up a weapon slot's owner and role.
func lookup_weapon_wire(wire_name: String) -> Dictionary:
	return weapon_slots.get(wire_name, {})
