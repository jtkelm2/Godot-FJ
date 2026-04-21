extends RefCounted

## Pure projection of `state.events` onto the previous game state. The
## previous state is `view.slots` — Dict[wire, Array|int], where each array
## entry is a card object {"name": <string>, "counters": <int>} per §3.2.1.
## Weapon interior slots (holsters, killstacks) are regular entries in
## `slots` per the wire protocol, so there's no separate weapons branch here.
##
## `apply(event)` mutates the projection for the event's type.
## `diff_against(new_slots)` returns a list of human-readable mismatches.

var _slots: Dictionary  # working copy of view.slots


func _init(prev_slots: Dictionary) -> void:
	_slots = prev_slots.duplicate(true)


## Mutate the projection to reflect one event. Unknown event types are
## silently ignored.
func apply(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"card_moved":
			_apply_card_moved(event)
		"slot_transferred":
			_apply_slot_transferred(event)


## Compare the projection against the authoritative new slots dict and
## return a list of human-readable diffs.
func diff_against(new_slots: Dictionary) -> Array:
	var diffs: Array = []
	for wire in _slots:
		if not _values_match(_slots[wire], new_slots.get(wire)):
			diffs.append("slot %s: expected=%s actual=%s" % [wire, _slots[wire], new_slots.get(wire)])
	for wire in new_slots:
		if not _slots.has(wire):
			diffs.append("slot %s: missing in expected; actual=%s" % [wire, new_slots[wire]])
	return diffs


# --- Mutation handlers ---

func _apply_card_moved(event: Dictionary) -> void:
	var src = event.get("source")
	var dst = event.get("dest")
	var src_idx: int = int(event.get("source_index", 0))
	var dst_idx: int = int(event.get("dest_index", 0))
	var moved_card = _take_from(src, src_idx)
	_place_into(dst, dst_idx, moved_card)


func _apply_slot_transferred(event: Dictionary) -> void:
	var src = event.get("source")
	var dst = event.get("dest")
	var count: int = int(event.get("count", 0))
	if src != null and _slots.has(src):
		var sv = _slots[src]
		if sv is Array:
			_slots[src] = []
		else:
			_slots[src] = 0
	if dst != null:
		if not _slots.has(dst):
			_slots[dst] = count
		else:
			var dv = _slots[dst]
			if dv is Array:
				for i in count:
					dv.append(null)
			else:
				_slots[dst] = int(dv) + count


# --- Slot read/write helpers ---

func _take_from(wire, idx: int):
	if wire == null or not _slots.has(wire):
		return null
	var sv = _slots[wire]
	if sv is Array:
		if idx >= 0 and idx < sv.size():
			var card = sv[idx]
			sv.remove_at(idx)
			return card
	elif sv is int or sv is float:
		_slots[wire] = max(0, int(sv) - 1)
	return null


func _place_into(wire, idx: int, card) -> void:
	if wire == null:
		return
	if not _slots.has(wire):
		_slots[wire] = 1
		return
	var dv = _slots[wire]
	if dv is Array:
		dv.insert(clamp(idx, 0, dv.size()), card)
	elif dv is int or dv is float:
		_slots[wire] = int(dv) + 1


# --- Diff comparator ---

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
