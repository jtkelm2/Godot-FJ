extends RefCounted

## Pure projection of `state.events` onto the previous game state. The
## previous state has two parts:
##   * `slots`   — Dict[wire, Array|int] from `view.slots`.
##   * `weapons` — Dict[ws_wire, {card, sharpness, kills}] derived from
##                 `view.weapons`. The caller normalizes the protocol's array
##                 form into a wire-keyed dict before constructing.
##
## `apply(event)` mutates whichever projection the event targets. A
## `card_moved` whose source/dest is one of the catalog's `self_weapon_interior_slots`
## mutates the weapons projection (writing the holster's `card` field or
## adjusting the killstack's `kills` count); otherwise it mutates `slots`.
## `slot_transferred` is similar.
##
## `diff_against(new_slots, new_weapons)` compares both projections to the
## authoritative new state and returns a list of human-readable diffs.

var _slots: Dictionary    # working copy of view.slots
var _weapons: Dictionary  # ws_wire -> {card, sharpness, kills}
var _catalog                # CatalogData (for interior-slot routing)


func _init(prev_slots: Dictionary, prev_weapons: Dictionary, catalog) -> void:
	_slots = prev_slots.duplicate(true)
	_weapons = prev_weapons.duplicate(true)
	_catalog = catalog


## Mutate the projection to reflect one event. Unknown event types are
## silently ignored (they don't touch slots or weapons).
func apply(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"card_moved":
			_apply_card_moved(event)
		"slot_transferred":
			_apply_slot_transferred(event)


## Compare the projection against the authoritative new state. `new_weapons`
## is in the same wire-keyed dict shape `_init` took.
func diff_against(new_slots: Dictionary, new_weapons: Dictionary) -> Array:
	var diffs: Array = []

	for wire in _slots:
		if not _values_match(_slots[wire], new_slots.get(wire)):
			diffs.append("slot %s: expected=%s actual=%s" % [wire, _slots[wire], new_slots.get(wire)])
	for wire in new_slots:
		if not _slots.has(wire):
			diffs.append("slot %s: missing in expected; actual=%s" % [wire, new_slots[wire]])

	for ws_wire in _weapons:
		var expected_w: Dictionary = _weapons[ws_wire]
		var actual_w = new_weapons.get(ws_wire)
		if actual_w == null:
			diffs.append("weapon %s: missing in actual; expected=%s" % [ws_wire, expected_w])
			continue
		if not _weapons_match(expected_w, actual_w):
			diffs.append("weapon %s: expected=%s actual=%s" % [ws_wire, expected_w, actual_w])
	for ws_wire in new_weapons:
		if not _weapons.has(ws_wire):
			diffs.append("weapon %s: missing in expected; actual=%s" % [ws_wire, new_weapons[ws_wire]])

	return diffs


# --- Mutation handlers ---

func _apply_card_moved(event: Dictionary) -> void:
	var src = event.get("source")
	var dst = event.get("dest")
	var src_idx: int = int(event.get("source_index", 0))
	var dst_idx: int = int(event.get("dest_index", 0))
	var moved_name = _take_from(src, src_idx)
	_place_into(dst, dst_idx, moved_name)


func _apply_slot_transferred(event: Dictionary) -> void:
	var src = event.get("source")
	var dst = event.get("dest")
	var count: int = int(event.get("count", 0))
	# Source: drained.
	if _is_weapon_interior(src):
		# A weapon-interior batch transfer is unusual; treat as zeroing the
		# killstack count (or clearing the holster card). Best-effort.
		_clear_weapon_interior(src)
	elif src != null and _slots.has(src):
		var sv = _slots[src]
		if sv is Array:
			_slots[src] = []
		else:
			_slots[src] = 0
	# Destination: receives `count` cards.
	if _is_weapon_interior(dst):
		# Anonymous transfer into a killstack: bump kills.
		var route: Dictionary = _weapon_route_for(dst)
		if route.get("kind", "") == "killstack":
			var w := _ensure_weapon_entry(route["ws_wire"])
			w["kills"] = int(w.get("kills", 0)) + count
	elif dst != null:
		if not _slots.has(dst):
			_slots[dst] = count
		else:
			var dv = _slots[dst]
			if dv is Array:
				for i in count:
					dv.append(null)
			else:
				_slots[dst] = int(dv) + count


# --- Source/dest helpers (route to slots OR weapons by wire kind) ---

func _take_from(wire, idx: int):
	if wire == null:
		return null
	if _is_weapon_interior(wire):
		var route: Dictionary = _weapon_route_for(wire)
		var w := _ensure_weapon_entry(route["ws_wire"])
		match route["kind"]:
			"holster":
				var name = w.get("card")
				w["card"] = null
				return name
			"killstack":
				w["kills"] = max(0, int(w.get("kills", 0)) - 1)
				return null  # facedown; identity unknown
		return null
	# Regular slot
	if not _slots.has(wire):
		return null
	var sv = _slots[wire]
	if sv is Array:
		if idx >= 0 and idx < sv.size():
			var name = sv[idx]
			sv.remove_at(idx)
			return name
	elif sv is int or sv is float:
		_slots[wire] = max(0, int(sv) - 1)
	return null


func _place_into(wire, idx: int, name) -> void:
	if wire == null:
		return
	if _is_weapon_interior(wire):
		var route: Dictionary = _weapon_route_for(wire)
		var w := _ensure_weapon_entry(route["ws_wire"])
		match route["kind"]:
			"holster":
				w["card"] = name  # may be null for facedown moves
			"killstack":
				w["kills"] = int(w.get("kills", 0)) + 1
		return
	# Regular slot
	if not _slots.has(wire):
		_slots[wire] = 1
		return
	var dv = _slots[wire]
	if dv is Array:
		dv.insert(clamp(idx, 0, dv.size()), name)
	elif dv is int or dv is float:
		_slots[wire] = int(dv) + 1


# --- Catalog routing ---

func _is_weapon_interior(wire) -> bool:
	if wire == null or _catalog == null:
		return false
	return _catalog.self_weapon_interior_slots.has(wire)


func _weapon_route_for(wire: String) -> Dictionary:
	return _catalog.self_weapon_interior_slots.get(wire, {})


func _ensure_weapon_entry(ws_wire: String) -> Dictionary:
	if not _weapons.has(ws_wire):
		_weapons[ws_wire] = {"card": null, "sharpness": 0, "kills": 0}
	return _weapons[ws_wire]


func _clear_weapon_interior(wire: String) -> void:
	var route: Dictionary = _weapon_route_for(wire)
	var w := _ensure_weapon_entry(route["ws_wire"])
	match route.get("kind", ""):
		"holster":
			w["card"] = null
		"killstack":
			w["kills"] = 0


# --- Diff comparators ---

func _values_match(a, b) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if a[i] != null and b[i] != null and a[i] != b[i]:
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return int(a) == int(b)
	return a == b


func _weapons_match(a: Dictionary, b: Dictionary) -> bool:
	# Authoritative server data may omit fields; treat missing as default.
	if a.get("card") != b.get("card"):
		return false
	if int(a.get("kills", 0)) != int(b.get("kills", 0)):
		return false
	if int(a.get("sharpness", 0)) != int(b.get("sharpness", 0)):
		return false
	return true
