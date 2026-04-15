extends Control

## Orchestrator. On init: handshake with GameSession (reads catalog +
## my_side), walks scene tree for Slot and WeaponSlot nodes, resolves each
## Slot's (owner_side, role) to a wire name via the catalog, connects
## signals.
##
## On every GameSession.changed:
##   1. If `latest_events` is non-empty AND we have a previous view, animate
##      each event in sequence (EventAnimator) while projecting it onto a
##      mirror of the previous (slots, weapons) state (EventProjector).
##   2. Assert the mirror matches the new (view.slots, view.weapons); log
##      divergence.
##   3. Run a full rebuild from the authoritative view (safety net).
##
## Cards in flight are reparented to a `BoardOverlay` Control so they render
## above all slots.
##
## Slots and WeaponSlots are first-class peers — no slot-side code special-
## cases weapons, no weapon-side code is jury-rigged out of slot helpers.
## Weapon-related work (data ingestion, click routing, highlights) goes
## through WeaponSlot's API or `Wrangler.apply_to_weapon_slot`.

const SlotWranglerScript = preload("res://fj/ui/slot_wrangler.gd")
const ImageResolverScript = preload("res://fj/assets/image_resolver.gd")
const EventAnimatorScript = preload("res://fj/ui/event_animator.gd")
const EventProjectorScript = preload("res://fj/net/event_projector.gd")

const EVENT_INTERVAL := 0.05

@onready var info_panel: Control = $HBoxContainer/InfoPanel
@onready var game_area: Control = $HBoxContainer/GameArea
@onready var _outer_row: HBoxContainer = $HBoxContainer

var _wrangler
var _image_resolver
var _animator
var _overlay: Control

var _slot_by_wire: Dictionary = {}                  # wire_name -> Slot
var _weapon_slots_by_ws_wire: Dictionary = {}       # ws wire_name -> WeaponSlot
var _weapon_slots_by_interior_wire: Dictionary = {} # holster/killstack wire -> WeaponSlot

## Snapshots from the most recent view we fully applied — starting points
## for the projector's mirror in the next change pass.
var _last_applied_slots: Dictionary = {}
var _last_applied_weapons: Dictionary = {}  # ws_wire -> entry dict
var _animating: bool = false


func _ready() -> void:
	_image_resolver = ImageResolverScript.new(GameSession.my_side)
	_wrangler = SlotWranglerScript.new()
	_wrangler.initialize(GameSession.catalog, _image_resolver)

	_overlay = Control.new()
	_overlay.name = "BoardOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.z_index = 2000
	add_child(_overlay)

	_bind_slots()
	_bind_weapon_slots()

	_animator = EventAnimatorScript.new()
	_animator.initialize(get_tree(), _slot_by_wire, _overlay, info_panel, _image_resolver)

	info_panel.set_side(GameSession.my_side)
	_place_info_panel_for_side(GameSession.my_side)
	info_panel.text_option_selected.connect(_on_text_option_selected)
	info_panel.show_notify("You are %s (%s)" % [GameSession.my_role, GameSession.my_side])

	GameSession.changed.connect(_on_changed)
	GameSession.notify_received.connect(info_panel.show_notify)
	_on_changed()


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
		slot.card_hovered.connect(_on_slot_card_hovered)
		slot.card_unhovered.connect(_on_slot_card_unhovered)


func _bind_weapon_slots() -> void:
	for ws in _find_weapon_slots(self):
		if not ws.ws_wire.is_empty():
			_weapon_slots_by_ws_wire[ws.ws_wire] = ws
			ws.weapon_slot_clicked.connect(_on_weapon_slot_clicked.bind(ws.ws_wire))
		# Per-card events from the holster/killstack route through here too,
		# so {type: card} prompts targeting an interior wire work transparently.
		for interior_wire in ws.interior_wires():
			_weapon_slots_by_interior_wire[interior_wire] = ws
		ws.card_clicked.connect(_on_weapon_card_clicked)
		ws.card_hovered.connect(_on_weapon_card_hovered)
		ws.card_unhovered.connect(_on_weapon_card_unhovered)


## Walk the tree for Slot nodes, treating SlotField AND WeaponSlot as
## opaque composites — their interior Slots are private to them.
func _find_slots(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		if child is WeaponSlot:
			continue  # interior slots are owned by the WeaponSlot
		if child is Slot:
			out.append(child)
			if child is SlotField:
				continue  # interior slots are owned by the SlotField
		_find_slots(child, out)
	return out


func _find_weapon_slots(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		if child is WeaponSlot:
			out.append(child)
		_find_weapon_slots(child, out)
	return out


## Order the outer row so the InfoPanel sits on the local player's side:
## RED → left (index 0), BLUE → right (last).
func _place_info_panel_for_side(side: String) -> void:
	if side == "RED":
		_outer_row.move_child(info_panel, 0)
	else:
		_outer_row.move_child(info_panel, _outer_row.get_child_count() - 1)


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


# --- Change pipeline: animate events, then full-rebuild ---

func _on_changed() -> void:
	# Re-entrance guard: while animating a previous batch, swallow new
	# changed signals. The full-rebuild at the end of _change_pass picks up
	# whatever the latest view is at that moment.
	if _animating:
		return
	_animating = true
	_change_pass()


func _change_pass() -> void:
	var view: Dictionary = GameSession.latest_view
	var events: Array = GameSession.latest_events.duplicate()
	GameSession.latest_events = []  # consume

	if not _last_applied_slots.is_empty() and not events.is_empty():
		await _run_events(events, view)

	_full_rebuild()
	_last_applied_slots = (view.get("slots", {}) as Dictionary).duplicate(true)
	_last_applied_weapons = _weapons_array_to_dict(view.get("weapons", []))
	_animating = false


## Walk events: project each onto the (slots, weapons) mirror AND play its
## animation. Assert the mirror matches the authoritative new view at the
## end; log the diff if it doesn't.
func _run_events(events: Array, new_view: Dictionary) -> void:
	var projector = EventProjectorScript.new(_last_applied_slots, _last_applied_weapons, GameSession.catalog)
	for event in events:
		projector.apply(event)
		await _animator.play(event)
		await get_tree().create_timer(EVENT_INTERVAL).timeout

	var new_weapons := _weapons_array_to_dict(new_view.get("weapons", []))
	var diffs := projector.diff_against(new_view.get("slots", {}), new_weapons)
	if not diffs.is_empty():
		push_warning("Board: events diverged from view. Diffs:\n  %s" % "\n  ".join(diffs))
		if GameSession.log:
			GameSession.log.log_event("events_diverged", {"diffs": diffs})


## Convert protocol's `view.weapons` array into a wire-keyed dict for the
## projector and snapshots:
##   [{"name": "red_ws_0", "card": ..., ...}]
##   →  {"red_ws_0": {"card": ..., ...}}
func _weapons_array_to_dict(weapons: Array) -> Dictionary:
	var out: Dictionary = {}
	for entry in weapons:
		var ws_wire := str(entry.get("name", ""))
		if not ws_wire.is_empty():
			out[ws_wire] = entry
	return out


# --- Full rebuild (safety-net reconciliation against authoritative view) ---

func _full_rebuild() -> void:
	var view: Dictionary = GameSession.latest_view
	var prompt: Dictionary = GameSession.pending_prompt

	if GameSession.log:
		GameSession.log.log_event("full_rebuild", {
			"slot_count": view.get("slots", {}).size(),
			"has_prompt": not prompt.is_empty(),
		})

	# Defensive: stale hover preview gets cleared on every rebuild because
	# mouse_exited does NOT fire when a Control is queue_free'd.
	info_panel.preview_card(null, -1)

	_rebuild_slot_contents(view)
	_rebuild_weapon_slots(view)
	var text_options := _apply_prompt_highlights(prompt)
	_update_info_panel(view, prompt, text_options)


## Populate each registered Slot from the authoritative view.slots. Weapon
## interior slots are NOT here — they're handled by _rebuild_weapon_slots.
func _rebuild_slot_contents(view: Dictionary) -> void:
	var slots_data: Dictionary = view.get("slots", {}) if not view.is_empty() else {}
	for wire in _slot_by_wire:
		var slot: Slot = _slot_by_wire[wire]
		_wrangler.apply_to(slot, slots_data.get(wire))
		slot.set_highlight(false)
		for i in slot.count():
			slot.get_card(i).set_highlight(false)


## Populate each registered WeaponSlot from view.weapons.
func _rebuild_weapon_slots(view: Dictionary) -> void:
	var weapons_by_wire := _weapons_array_to_dict(view.get("weapons", []))
	for ws_wire in _weapon_slots_by_ws_wire:
		var ws: WeaponSlot = _weapon_slots_by_ws_wire[ws_wire]
		var entry: Dictionary = weapons_by_wire.get(ws_wire, {"card": null, "sharpness": 0, "kills": 0})
		_wrangler.apply_to_weapon_slot(ws, entry)
		ws.clear_highlights()


## Decorate selectable prompt options. Returns the `text` options collected
## for the info panel (which renders them as buttons).
func _apply_prompt_highlights(prompt: Dictionary) -> Array:
	var text_options: Array = []
	for option in prompt.get("options", []):
		var t := str(option.get("type", ""))
		match t:
			"card":
				_highlight_card_option(option)
			"slot":
				var slot: Slot = _slot_by_wire.get(str(option.get("name", "")))
				if slot:
					slot.set_highlight(true)
			"weapon_slot":
				var ws: WeaponSlot = _weapon_slots_by_ws_wire.get(str(option.get("name", "")))
				if ws:
					ws.set_highlight(true)
			"text":
				text_options.append(option)
	return text_options


## A `card` option may target a regular slot or an interior weapon slot;
## route to whichever owns that wire.
func _highlight_card_option(option: Dictionary) -> void:
	var wire := str(option.get("slot", ""))
	var idx := int(option.get("index", -1))
	var slot: Slot = _slot_by_wire.get(wire)
	if slot and idx >= 0 and idx < slot.count():
		slot.get_card(idx).set_highlight(true)
		return
	var ws: WeaponSlot = _weapon_slots_by_interior_wire.get(wire)
	if ws:
		ws.set_card_highlight(wire, idx, true)


func _update_info_panel(view: Dictionary, prompt: Dictionary, text_options: Array) -> void:
	if not view.is_empty():
		info_panel.update_view(view, GameSession.my_side)
	info_panel.update_prompt(str(prompt.get("text", "")), text_options)


# --- Click handlers (bound with wire names at init) ---

func _on_slot_card_clicked(_slot: Slot, index: int, wire: String) -> void:
	_respond_matching({"type": "card", "slot": wire, "index": index})


func _on_slot_slot_clicked(_slot: Slot, wire: String) -> void:
	_respond_matching({"type": "slot", "name": wire})


func _on_weapon_slot_clicked(_ws: WeaponSlot, ws_wire: String) -> void:
	_respond_matching({"type": "weapon_slot", "name": ws_wire})


## A card click came from a WeaponSlot's holster or killstack. Route it
## through the same `card`-option matcher as regular slots.
func _on_weapon_card_clicked(interior_wire: String, index: int) -> void:
	_respond_matching({"type": "card", "slot": interior_wire, "index": index})


func _on_text_option_selected(option: Dictionary) -> void:
	_respond(option)


## Find an option in the pending prompt that structurally matches `target`
## and send it as a response. Godot 4's `Dictionary ==` is reference equality
## (not content), so we walk and content-compare. NetworkTransport's
## int-preserving stringifier guarantees the echoed response is byte-identical
## to what the server sent.
func _respond_matching(target: Dictionary) -> void:
	for opt in GameSession.pending_prompt.get("options", []):
		if _dict_content_equal(opt, target):
			_respond(opt)
			return


func _dict_content_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or a[k] != b[k]:
			return false
	return true


func _respond(option: Dictionary) -> void:
	if GameSession.log:
		GameSession.log.log_event("player_selected_option", option)
	GameSession.respond(option)
	# pending_prompt is cleared by respond(); re-trigger the pipeline so
	# highlights drop and any queued events drain.
	_on_changed()


# --- Hover preview wiring ---

func _on_slot_card_hovered(slot: Slot, index: int) -> void:
	info_panel.preview_card(slot, index)


func _on_slot_card_unhovered(_slot: Slot) -> void:
	info_panel.preview_card(null, -1)


## A WeaponSlot's interior card was hovered. Resolve the interior Slot to
## drive the same preview machinery as regular hover.
func _on_weapon_card_hovered(interior_wire: String, index: int) -> void:
	var ws: WeaponSlot = _weapon_slots_by_interior_wire.get(interior_wire)
	if ws == null:
		return
	var interior: Slot = ws.holster if interior_wire == ws.holster_wire else ws.killstack
	if interior:
		info_panel.preview_card(interior, index)


func _on_weapon_card_unhovered() -> void:
	info_panel.preview_card(null, -1)
