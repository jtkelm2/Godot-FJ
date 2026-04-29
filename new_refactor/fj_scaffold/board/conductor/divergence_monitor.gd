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
	if ev is DL.CardMoved:
		_apply_card_moved(state, ev as DL.CardMoved)
	elif ev is DL.SlotTransferred:
		_apply_slot_transferred(state, ev as DL.SlotTransferred)
	elif ev is DL.HPChanged:
		var hpc := ev as DL.HPChanged
		if state.hp.has(hpc.target):
			(state.hp[hpc.target] as State.HP).val = hpc.new_hp
	elif ev is DL.PhaseChanged:
		state.phase = (ev as DL.PhaseChanged).phase
	# SlotShuffled, PlayerDied, GameEnded: no slot mutation needed for projection.


static func _apply_card_moved(state: State, ev: DL.CardMoved) -> void:
	var card_inst: CardInstance = null
	if ev.orig is Loc.SlotLoc:
		var src := ev.orig as Loc.SlotLoc
		if state.slots.has(src.slot):
			var contents = state.slots[src.slot]
			if contents is State.FullContents:
				var cards := (contents as State.FullContents).cards
				if src.idx >= 0 and src.idx < cards.size():
					card_inst = cards[src.idx]
					cards.remove_at(src.idx)
			elif contents is State.CountContents:
				var cnt := contents as State.CountContents
				if cnt.n > 0:
					cnt.n -= 1
	if ev.dest is Loc.SlotLoc:
		var dst := ev.dest as Loc.SlotLoc
		if state.slots.has(dst.slot):
			var contents = state.slots[dst.slot]
			if contents is State.FullContents:
				var cards := (contents as State.FullContents).cards
				if card_inst != null:
					cards.insert(clamp(dst.idx, 0, cards.size()), card_inst)
				# else: source was hidden; projection will diverge and trigger rebuild.
			elif contents is State.CountContents:
				(contents as State.CountContents).n += 1


static func _apply_slot_transferred(state: State, ev: DL.SlotTransferred) -> void:
	if state.slots.has(ev.orig):
		var src = state.slots[ev.orig]
		if src is State.FullContents:
			(src as State.FullContents).cards.clear()
		elif src is State.CountContents:
			(src as State.CountContents).n = 0
	if state.slots.has(ev.dest):
		var dst = state.slots[ev.dest]
		if dst is State.CountContents:
			(dst as State.CountContents).n += ev.count
		# FullContents destination: we don't have CardInstances to synthesize,
		# so projection diverges and triggers rebuild.


# --- Cloning helpers ---

static func _clone_slots(slots: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot in slots:
		var c = slots[slot]
		if c is State.UnknownContents:
			out[slot] = State.UnknownContents.new()
		elif c is State.CountContents:
			out[slot] = State.CountContents.new((c as State.CountContents).n)
		elif c is State.FullContents:
			var src := (c as State.FullContents).cards
			var copy: Array[CardInstance] = []
			for ci in src: copy.append(ci)
			out[slot] = State.FullContents.new(copy)
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
	if a is State.UnknownContents:
		return b is State.UnknownContents
	if a is State.CountContents and b is State.CountContents:
		return (a as State.CountContents).n == (b as State.CountContents).n
	if a is State.FullContents and b is State.FullContents:
		var ac := (a as State.FullContents).cards
		var bc := (b as State.FullContents).cards
		if ac.size() != bc.size():
			return false
		for i in ac.size():
			if ac[i].template != bc[i].template or ac[i].counters != bc[i].counters:
				return false
		return true
	return false
