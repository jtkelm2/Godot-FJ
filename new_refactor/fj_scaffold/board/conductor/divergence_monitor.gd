## DivergenceMonitor: validates the SL+DL pairing contract.
##
## `check(state, events)` projects the events onto the previously-stored SL
## snapshot, compares the result against the new authoritative SL, and
## returns a `CheckResult` describing what the Conductor should do:
##
##   initial:   true on the very first SL (no prior baseline). Conductor
##              schedules a full rebuild without playing events.
##   divergent: true when projection ≠ actual. Conductor schedules events
##              first, then a rebuild from `state` to snap the UI to truth.
##   neither:   normal case. Conductor just plays the events.
##
## Wire-agnostic. Pure logic — no Renderer access, no signal emissions.

class_name DivergenceMonitor extends RefCounted


class CheckResult extends RefCounted:
	var initial: bool = false
	var divergent: bool = false
	var diffs: Array[String] = []


var _previous: State = null


## Called per (state, events) pair. Always advances the baseline.
func check(state: State, events: Array[DL]) -> CheckResult:
	var result := CheckResult.new()
	if _previous == null:
		result.initial = true
		_previous = state
		return result

	var projected := _project(_previous, events)
	var diffs := _compare_slots(projected.slots, state.slots)
	result.diffs = diffs
	if not diffs.is_empty():
		push_warning("DivergenceMonitor: %s" % diffs)
		result.divergent = true
	_previous = state
	return result


## Reset state — composer calls when a new game session begins.
func reset() -> void:
	_previous = null


# --- Projection ---

static func _project(prev: State, events: Array[DL]) -> State:
	var p := State.new()
	p.role = prev.role.duplicate()
	p.hp = _clone_hp(prev.hp)
	p.phase = prev.phase
	p.priority = prev.priority
	p.slots = _clone_slots(prev.slots)
	for ev in events:
		_apply(p, ev)
	return p


static func _apply(state: State, ev: DL) -> void:
	match ev.type:
		DL.Type.CARD_MOVED:
			_apply_card_moved(state, ev)
		DL.Type.SLOT_TRANSFERRED:
			_apply_slot_transferred(state, ev)
		DL.Type.HP_CHANGED:
			if state.hp.has(ev.target):
				(state.hp[ev.target] as State.HP).val = ev.new_hp
		DL.Type.PHASE_CHANGED:
			state.phase = ev.phase
		# SLOT_SHUFFLED, PLAYER_DIED, GAME_ENDED: no slot mutation needed for projection.


static func _apply_card_moved(state: State, ev: DL) -> void:
	var card_inst: CardInstance = null
	if ev.orig.type == Loc.Type.SLOT and state.slots.has(ev.orig.slot):
		var contents: State.SlotContents = state.slots[ev.orig.slot]
		match contents.type:
			State.SlotContents.Type.FULL:
				if ev.orig.idx >= 0 and ev.orig.idx < contents.cards.size():
					card_inst = contents.cards[ev.orig.idx]
					contents.cards.remove_at(ev.orig.idx)
			State.SlotContents.Type.COUNT:
				if contents.n > 0:
					contents.n -= 1
	if ev.dest.type == Loc.Type.SLOT and state.slots.has(ev.dest.slot):
		var contents: State.SlotContents = state.slots[ev.dest.slot]
		match contents.type:
			State.SlotContents.Type.FULL:
				if card_inst != null:
					contents.cards.insert(clamp(ev.dest.idx, 0, contents.cards.size()), card_inst)
				# else: source was hidden; projection will diverge and trigger rebuild.
			State.SlotContents.Type.COUNT:
				contents.n += 1


static func _apply_slot_transferred(state: State, ev: DL) -> void:
	if state.slots.has(ev.orig_slot):
		var src: State.SlotContents = state.slots[ev.orig_slot]
		match src.type:
			State.SlotContents.Type.FULL: src.cards.clear()
			State.SlotContents.Type.COUNT: src.n = 0
	if state.slots.has(ev.dest_slot):
		var dst: State.SlotContents = state.slots[ev.dest_slot]
		if dst.type == State.SlotContents.Type.COUNT:
			dst.n += ev.count
		# FULL destination: we don't have CardInstances to synthesize,
		# so projection diverges and triggers rebuild.


# --- Cloning helpers ---

static func _clone_slots(slots: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot in slots:
		var c: State.SlotContents = slots[slot]
		match c.type:
			State.SlotContents.Type.UNKNOWN:
				out[slot] = State.SlotContents.Unknown()
			State.SlotContents.Type.COUNT:
				out[slot] = State.SlotContents.Count(c.n)
			State.SlotContents.Type.FULL:
				var copy: Array[CardInstance] = []
				for ci in c.cards: copy.append(ci)
				out[slot] = State.SlotContents.Full(copy)
	return out


static func _clone_hp(hp: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for pid in hp:
		var h: State.HP = hp[pid]
		out[pid] = State.HP.new(h.val, h.cap, h.floor)
	return out


# --- Comparison ---

static func _compare_slots(expected: Dictionary, actual: Dictionary) -> Array[String]:
	var diffs: Array[String] = []
	for slot in expected:
		if not actual.has(slot):
			diffs.append("slot %s missing in actual" % slot)
		elif not _slot_contents_equal(expected[slot], actual[slot]):
			diffs.append("slot %s mismatch" % slot)
	for slot in actual:
		if not expected.has(slot):
			diffs.append("slot %s missing in expected" % slot)
	return diffs


static func _slot_contents_equal(a: State.SlotContents, b: State.SlotContents) -> bool:
	if a.type != b.type:
		return false
	match a.type:
		State.SlotContents.Type.UNKNOWN:
			return true
		State.SlotContents.Type.COUNT:
			return a.n == b.n
		State.SlotContents.Type.FULL:
			if a.cards.size() != b.cards.size():
				return false
			for i in a.cards.size():
				if a.cards[i].template != b.cards[i].template or a.cards[i].counters != b.cards[i].counters:
					return false
			return true
	return false
