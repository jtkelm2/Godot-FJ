extends Control

## Orchestrator. On init: handshake with GameSession (reads catalog +
## my_side), walks scene tree for Slot nodes, resolves each Slot's
## (owner_side, role) to a wire name via the catalog, connects signals.
##
## On every GameSession.changed:
##   1. If `latest_events` is non-empty AND we have a previous view, animate
##      each event in sequence, mutating an `expected_slots` mirror.
##   2. Assert the mirror matches the new view's slots (events should fully
##      describe the transition).
##   3. Run a full rebuild from view to reconcile (safety net).
##
## Cards in flight are reparented to a `BoardOverlay` Control so they render
## above all slots.

const SlotWranglerScript = preload("res://fj/ui/slot_wrangler.gd")
const ImageResolverScript = preload("res://fj/assets/image_resolver.gd")

const EVENT_ANIM_DURATION := 0.25
const EVENT_ANIM_INTERVAL := 0.05

@onready var info_panel: Control = $InfoPanel
@onready var game_area: Control = $GameArea

var _wrangler
var _image_resolver
var _overlay: Control

var _slot_by_wire: Dictionary = {}         # wire_name -> Slot
var _weapon_slot_by_wire: Dictionary = {}  # weapon_slot wire_name -> Slot

## Snapshot of the slots dict from the most recent view we fully applied.
## Used as the starting point for the expected-slots model when animating
## the next round of events.
var _last_applied_slots: Dictionary = {}
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

	info_panel.set_side(GameSession.my_side)
	_position_game_area_for_side(GameSession.my_side)
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


## Slide GameArea inward to leave room for the InfoPanel on the player's side.
## RED player → panel on left, GameArea offset_left = panel width + margin.
## BLUE player → panel on right, GameArea offset_right = -(panel width + margin).
func _position_game_area_for_side(side: String) -> void:
	const PANEL_W := 448.0
	const MARGIN := 16.0
	if side == "RED":
		game_area.offset_left = PANEL_W + MARGIN
		game_area.offset_right = -MARGIN
	else:  # BLUE or anything else → panel on right
		game_area.offset_left = MARGIN
		game_area.offset_right = -(PANEL_W + MARGIN)


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
	# Re-entrance guard: while animating a previous batch, swallow new changed
	# signals. The next full-rebuild at the end of _change_pass will pick up
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
		await _animate_events(events, view)

	_full_rebuild()
	_last_applied_slots = (view.get("slots", {}) as Dictionary).duplicate(true)
	_animating = false


## Apply each event in order: tween it visually AND mutate a working copy of
## the slots state. After all events, assert the working copy matches the
## authoritative `new_view.slots`.
func _animate_events(events: Array, new_view: Dictionary) -> void:
	var expected: Dictionary = _last_applied_slots.duplicate(true)
	for event in events:
		var t := str(event.get("type", ""))
		match t:
			"card_moved":
				_apply_card_moved_to_state(event, expected)
				await _anim_card_moved(event)
			"slot_transferred":
				_apply_slot_transferred_to_state(event, expected)
				await _anim_slot_transferred(event)
			"hp_changed":
				await _anim_hp_changed(event)
			"slot_shuffled":
				await _anim_slot_shuffled(event)
			"phase_changed", "player_died", "game_ended":
				pass  # handled in _full_rebuild via view; nothing to animate
			_:
				push_warning("Board: unknown event type '%s'" % t)
		await get_tree().create_timer(EVENT_ANIM_INTERVAL).timeout

	# Sanity check: events should describe the full transition. If they
	# don't, the upcoming full-rebuild will still correct the UI, but the
	# divergence is worth recording so server bugs surface early.
	var diffs := _diff_slots(expected, new_view.get("slots", {}))
	if not diffs.is_empty():
		push_warning("Board: events diverged from view. Diffs:\n  %s" % "\n  ".join(diffs))
		if GameSession.log:
			GameSession.log.log_event("events_diverged", {"diffs": diffs})


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

	var slots_data: Dictionary = view.get("slots", {}) if not view.is_empty() else {}

	# 1. Rebuild slot contents and clear highlights. Own weapon/killstack
	# sub-slots are populated from view.weapons (step 1.5), not from slots.
	for wire in _slot_by_wire:
		var slot: Slot = _slot_by_wire[wire]
		if _is_own_weapon_subslot(slot):
			continue
		_wrangler.apply_to(slot, slots_data.get(wire))
		slot.set_highlight(false)
		for i in slot.count():
			slot.get_card(i).set_highlight(false)

	# 1.5. Own weapon/killstack contents come via view.weapons (§3.2.2).
	for w in view.get("weapons", []):
		_populate_own_weapon_entry(w)

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


# --- Event animations ---

func _anim_card_moved(event: Dictionary) -> void:
	var src_wire = event.get("source")
	var dst_wire = event.get("dest")
	var src_idx: int = int(event.get("source_index", 0))
	var src_slot: Slot = _slot_by_wire.get(src_wire) if src_wire != null else null
	var dst_slot: Slot = _slot_by_wire.get(dst_wire) if dst_wire != null else null
	if src_slot == null and dst_slot == null:
		return  # both ends invisible/off-screen — nothing to animate

	var src_pos := _slot_center_global(src_slot) if src_slot else _slot_center_global(dst_slot)
	var dst_pos := _slot_center_global(dst_slot) if dst_slot else _slot_center_global(src_slot)

	# Grab the actual card at (source_slot, source_index) if possible so the
	# animation uses its real front texture. For count-only or missing sources,
	# spawn a facedown temp card as a stand-in.
	var flying: Card = null
	if src_slot != null and src_idx >= 0 and src_idx < src_slot.count():
		flying = src_slot.remove(src_idx)  # detaches from slot, keeps node alive
	if flying == null:
		var owner_for_back: String = (src_slot.owner_side if src_slot else dst_slot.owner_side)
		flying = Card.create(null, _image_resolver.get_back_for(owner_for_back), false)

	_overlay.add_child(flying)
	flying.position = src_pos - flying.size * 0.5

	var tween := create_tween()
	tween.tween_property(flying, "position", dst_pos - flying.size * 0.5, EVENT_ANIM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	# The full-rebuild at the end of _change_pass rebuilds the destination
	# slot's contents from the authoritative view, so we can safely drop the
	# flying card here.
	flying.queue_free()


func _anim_slot_transferred(event: Dictionary) -> void:
	# Treat as a single batch gesture — render one fly-over to represent the move.
	await _anim_card_moved({
		"source": event.get("source"),
		"dest": event.get("dest"),
	})


func _anim_hp_changed(event: Dictionary) -> void:
	# Brief flash on the InfoPanel; the actual number is set by _full_rebuild.
	var old_hp: int = int(event.get("old", 0))
	var new_hp: int = int(event.get("new", 0))
	var delta := new_hp - old_hp
	if delta == 0:
		return
	var color := Color.LIGHT_GREEN if delta > 0 else Color(1.0, 0.5, 0.5)
	info_panel.show_notify(("+%d HP" if delta > 0 else "%d HP") % delta)
	# Inline tween of the panel tint as a quick pulse.
	if info_panel is ColorRect:
		var orig := (info_panel as ColorRect).color
		var tween := create_tween()
		tween.tween_property(info_panel, "color", color, EVENT_ANIM_DURATION * 0.3)
		tween.tween_property(info_panel, "color", orig, EVENT_ANIM_DURATION * 0.7)
		await tween.finished
	else:
		await get_tree().create_timer(EVENT_ANIM_DURATION).timeout


func _anim_slot_shuffled(event: Dictionary) -> void:
	var wire = event.get("slot")
	var slot: Slot = _slot_by_wire.get(wire) if wire != null else null
	if slot == null:
		return
	# Quick wiggle.
	var orig := slot.position
	var tween := create_tween()
	tween.tween_property(slot, "position", orig + Vector2(4, 0), EVENT_ANIM_DURATION * 0.25)
	tween.tween_property(slot, "position", orig + Vector2(-4, 0), EVENT_ANIM_DURATION * 0.5)
	tween.tween_property(slot, "position", orig, EVENT_ANIM_DURATION * 0.25)
	await tween.finished


# --- Expected-state mutation (mirrors the events on a copy of the view) ---

func _apply_card_moved_to_state(event: Dictionary, slots: Dictionary) -> void:
	var src = event.get("source")
	var dst = event.get("dest")
	var src_idx: int = int(event.get("source_index", 0))
	var dst_idx: int = int(event.get("dest_index", 0))
	var moved_name = null

	if src != null and slots.has(src):
		var sv = slots[src]
		if sv is Array:
			if src_idx >= 0 and src_idx < sv.size():
				moved_name = sv[src_idx]
				sv.remove_at(src_idx)
		elif sv is int or sv is float:
			slots[src] = max(0, int(sv) - 1)

	if dst != null:
		if not slots.has(dst):
			# Server may push a new slot in this event; default to a count-1 cell.
			slots[dst] = 1
		else:
			var dv = slots[dst]
			if dv is Array:
				dv.insert(clamp(dst_idx, 0, dv.size()), moved_name)
			elif dv is int or dv is float:
				slots[dst] = int(dv) + 1


func _apply_slot_transferred_to_state(event: Dictionary, slots: Dictionary) -> void:
	var src = event.get("source")
	var dst = event.get("dest")
	var count: int = int(event.get("count", 0))
	if src != null and slots.has(src):
		var sv = slots[src]
		if sv is Array:
			slots[src] = []
		else:
			slots[src] = 0
	if dst != null:
		if not slots.has(dst):
			slots[dst] = count
		else:
			var dv = slots[dst]
			if dv is Array:
				# We don't have card names — represent transferred as nulls.
				for i in count: dv.append(null)
			else:
				slots[dst] = int(dv) + count


func _diff_slots(expected: Dictionary, actual: Dictionary) -> Array:
	var diffs: Array = []
	for wire in expected:
		# Own weapon/killstack slots come via view.weapons, not view.slots —
		# the authoritative `actual` won't list them, so skip.
		if _is_own_weapon_wire(wire):
			continue
		var ev = expected[wire]
		var av = actual.get(wire)
		if not _values_match(ev, av):
			diffs.append("%s: expected=%s actual=%s" % [wire, ev, av])
	for wire in actual:
		if _is_own_weapon_wire(wire):
			continue
		if not expected.has(wire):
			diffs.append("%s: missing in expected; actual=%s" % [wire, actual[wire]])
	return diffs


# --- Weapon subslot helpers (own side only; opp weapons are hidden) ---

func _is_own_weapon_subslot(slot: Slot) -> bool:
	return slot.owner_side == GameSession.my_side \
		and (slot.role.ends_with("_weapon") or slot.role.ends_with("_killstack"))


func _is_own_weapon_wire(wire: String) -> bool:
	var info = GameSession.catalog.slots.get(wire, null) if GameSession.catalog else null
	if info == null:
		return false
	var role := str(info.get("role", ""))
	var own := str(info.get("owner", ""))
	return own == "self" and (role.ends_with("_weapon") or role.ends_with("_killstack"))


## Fill the UI slots backing one weapon-slot entry from view.weapons.
## `w` is {"name": "red_ws_0", "card": <name>|null, "sharpness": int, "kills": int}.
func _populate_own_weapon_entry(w: Dictionary) -> void:
	var catalog = GameSession.catalog
	if catalog == null:
		return
	var ws_wire := str(w.get("name", ""))
	var ws_info = catalog.weapon_slots.get(ws_wire, null)
	if ws_info == null:
		return
	var ws_role := str(ws_info.get("role", ""))  # e.g. "ws_0"
	if ws_role.is_empty():
		return

	var weapon_wire: String = catalog.self_slots.get(ws_role + "_weapon", "")
	var killstack_wire: String = catalog.self_slots.get(ws_role + "_killstack", "")

	var weapon_slot: Slot = _slot_by_wire.get(weapon_wire)
	if weapon_slot:
		var card_name = w.get("card")
		var data: Array = [str(card_name)] if card_name != null else []
		_wrangler.apply_to(weapon_slot, data)
		weapon_slot.set_highlight(false)
		for i in weapon_slot.count():
			weapon_slot.get_card(i).set_highlight(false)

	var killstack_slot: Slot = _slot_by_wire.get(killstack_wire)
	if killstack_slot:
		_wrangler.apply_to(killstack_slot, int(w.get("kills", 0)))
		killstack_slot.set_highlight(false)


func _values_match(a, b) -> bool:
	if a is Array and b is Array:
		# Tolerate null entries from slot_transferred.
		if a.size() != b.size():
			return false
		for i in a.size():
			if a[i] != null and b[i] != null and a[i] != b[i]:
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return int(a) == int(b)
	return a == b


func _slot_center_global(slot: Slot) -> Vector2:
	if slot == null:
		return Vector2.ZERO
	return slot.global_position + slot.size * 0.5


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
	# pending_prompt is cleared by respond(); re-trigger the change pipeline
	# so the highlights drop and any pending events drain.
	_on_changed()


# --- Hover preview wiring ---

func _on_slot_card_hovered(slot: Slot, index: int) -> void:
	info_panel.preview_card(slot, index)


func _on_slot_card_unhovered(_slot: Slot) -> void:
	info_panel.preview_card(null, -1)


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
