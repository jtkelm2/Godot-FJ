extends Control

## Orchestrator. On init: handshake with GameSession (reads catalog +
## my_side), walks scene tree for Slot nodes, resolves each Slot's
## (owner_side, role) to a wire name via the catalog, connects signals.
##
## On every GameSession.changed: rebuild from (latest_view, pending_prompt).
## Full rebuild — every slot's cards are freed and recreated. Single source
## of truth; no caches.
##
## The wire-name ↔ Slot map and weapon-slot alias map are built once and
## never mutated after init.

const SlotWranglerScript = preload("res://fj/ui/slot_wrangler.gd")
const ImageResolverScript = preload("res://fj/net/image_resolver.gd")

@onready var info_panel: Control = $InfoPanel

var _wrangler
var _image_resolver

var _slot_by_wire: Dictionary = {}         # wire_name -> Slot
var _weapon_slot_by_wire: Dictionary = {}  # weapon_slot wire_name -> Slot


func _ready() -> void:
	_image_resolver = ImageResolverScript.new()
	_wrangler = SlotWranglerScript.new()
	_wrangler.initialize(GameSession.catalog, _image_resolver, GameSession.my_side)
	_wrangler.card_created.connect(_on_card_created)

	_bind_slots()

	info_panel.text_option_selected.connect(_on_text_option_selected)
	info_panel.show_notify("You are %s (%s)" % [GameSession.my_role, GameSession.my_side])

	GameSession.changed.connect(_rebuild)
	GameSession.notify_received.connect(info_panel.show_notify)
	_rebuild()


# --- Init: walk scene tree, bind signals, build wire maps ---

func _bind_slots() -> void:
	var catalog = GameSession.catalog
	for slot in _find_slots(self):
		var wire := _wire_for(catalog, slot.owner_side, slot.role)
		if wire.is_empty():
			push_warning("Board: unresolvable slot (owner=%s, role=%s) at %s" % [slot.owner_side, slot.role, slot.get_path()])
			continue
		_slot_by_wire[wire] = slot
		slot.card_clicked.connect(_on_slot_card_clicked.bind(wire))
		slot.slot_clicked.connect(_on_slot_slot_clicked.bind(wire))

	# Convention: a self-owned Slot with role "ws_N_weapon" is also the UI
	# target for weapon_slot option {"name": <self_weapon_slots[ws_N]>}.
	for wire in _slot_by_wire:
		var slot: Slot = _slot_by_wire[wire]
		if slot.owner_side == GameSession.my_side and slot.role.ends_with("_weapon"):
			var ws_role := slot.role.trim_suffix("_weapon")
			var ws_wire: String = catalog.self_weapon_slots.get(ws_role, "")
			if not ws_wire.is_empty():
				_weapon_slot_by_wire[ws_wire] = slot
				slot.slot_clicked.connect(_on_slot_weapon_slot_clicked.bind(ws_wire))


func _find_slots(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		if child is Slot:
			out.append(child)
			# Don't recurse into SlotFields: their internal Slots are private.
			if child is SlotField:
				continue
		_find_slots(child, out)
	return out


func _wire_for(catalog, owner_side: String, role: String) -> String:
	var lookup: Dictionary
	if owner_side == GameSession.my_side:
		lookup = catalog.self_slots
	elif owner_side == "SHARED":
		lookup = catalog.shared_slots
	elif owner_side == "RED" or owner_side == "BLUE":
		lookup = catalog.opponent_slots
	else:
		return ""
	return lookup.get(role, "")


# --- Rebuild ---

func _rebuild() -> void:
	var view: Dictionary = GameSession.latest_view
	var prompt: Dictionary = GameSession.pending_prompt

	# Defensive: stale hover preview gets cleared on every rebuild because
	# mouse_exited does NOT fire when a Control is queue_free'd.
	info_panel.preview_card(null)

	var slots_data: Dictionary = view.get("slots", {}) if not view.is_empty() else {}

	# 1. Rebuild slot contents and clear highlights.
	for wire in _slot_by_wire:
		var slot: Slot = _slot_by_wire[wire]
		_wrangler.apply_to(slot, slots_data.get(wire))
		slot.set_highlight(false)
		for i in slot.count():
			slot.get_card(i).set_highlight(false)

	# 2. Paint prompt highlights and collect text options.
	var text_options: Array = []
	for option in prompt.get("options", []):
		var t := str(option.get("type", ""))
		match t:
			"card":
				var wire := str(option.get("slot", ""))
				var idx := int(option.get("index", -1))
				var slot: Slot = _slot_by_wire.get(wire)
				if slot and idx >= 0 and idx < slot.count():
					slot.get_card(idx).set_highlight(true)
			"slot":
				var wire := str(option.get("name", ""))
				var slot: Slot = _slot_by_wire.get(wire)
				if slot:
					slot.set_highlight(true)
			"weapon_slot":
				var ws_wire := str(option.get("name", ""))
				var slot: Slot = _weapon_slot_by_wire.get(ws_wire)
				if slot:
					slot.set_highlight(true)
			"text":
				text_options.append(option)

	# 3. Info panel.
	if not view.is_empty():
		info_panel.update_view(view, GameSession.my_side)
	info_panel.update_prompt(str(prompt.get("text", "")), text_options)


# --- Click handlers (bound with wire names at init) ---

func _on_slot_card_clicked(_slot: Slot, index: int, wire: String) -> void:
	var option := _find_option({"type": "card", "slot": wire, "index": index})
	if not option.is_empty():
		_respond(option)


func _on_slot_slot_clicked(_slot: Slot, wire: String) -> void:
	var option := _find_option({"type": "slot", "name": wire})
	if not option.is_empty():
		_respond(option)


func _on_slot_weapon_slot_clicked(_slot: Slot, ws_wire: String) -> void:
	var option := _find_option({"type": "weapon_slot", "name": ws_wire})
	if not option.is_empty():
		_respond(option)


func _on_text_option_selected(option: Dictionary) -> void:
	_respond(option)


func _respond(option: Dictionary) -> void:
	if GameSession.log:
		GameSession.log.log_event("player_selected_option", option)
	GameSession.respond(option)
	# pending_prompt is cleared by respond(); rebuild drops highlights.
	_rebuild()


# --- Hover preview wiring ---

func _on_card_created(card: Card, card_name: String) -> void:
	if card_name.is_empty():
		return
	card.mouse_entered.connect(func(): info_panel.preview_card(_image_resolver.get_front_texture(card_name)))
	card.mouse_exited.connect(func(): info_panel.preview_card(null))


# --- Option matching (tolerates int/float drift on JSON round-trip) ---

func _find_option(target: Dictionary) -> Dictionary:
	for opt in GameSession.pending_prompt.get("options", []):
		if _dict_matches(opt, target):
			return opt
	return {}


func _dict_matches(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
		var av = a[k]
		var bv = b[k]
		if (av is int or av is float) and (bv is int or bv is float):
			if float(av) != float(bv):
				return false
		elif av != bv:
			return false
	return true
