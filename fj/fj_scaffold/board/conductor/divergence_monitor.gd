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
##              Conductor is also expected to emit a divergence_detected
##              report (built via `CheckResult.format_report(events)`) for
##              the logger / a remote diagnostic surface.
##   neither:   normal case. Conductor just plays the events.
##
## Wire-agnostic. Pure logic — no Renderer access, no signal emissions.

class_name DivergenceMonitor extends RefCounted


class CheckResult extends RefCounted:
	var initial: bool = false
	var divergent: bool = false
	## One human-readable line per divergent slot. Each line is self-contained:
	## slot identity + the field that mismatched + projected/actual values.
	var diffs: Array[String] = []
	## Captured contents of slots that diverged. Empty when not divergent.
	var divergent_projected: Dictionary[SlotID, State.SlotContents] = {}
	var divergent_actual: Dictionary[SlotID, State.SlotContents] = {}

	## Multi-line dump suitable for the logger. Conductor formats via this.
	func format_report(events: Array[DL]) -> String:
		var lines := PackedStringArray()
		lines.append("events (%d):" % events.size())
		if events.is_empty():
			lines.append("  <none>")
		else:
			for ev in events:
				lines.append("  " + ev.describe())
		lines.append("diffs (%d):" % diffs.size())
		for d in diffs:
			lines.append("  " + d)
		lines.append("projected (divergent slots only):")
		_dump_slots(lines, divergent_projected)
		lines.append("actual (divergent slots only):")
		_dump_slots(lines, divergent_actual)
		return "\n".join(lines)

	static func _dump_slots(lines: PackedStringArray, slots: Dictionary[SlotID, State.SlotContents]) -> void:
		if slots.is_empty():
			lines.append("  <none>")
			return
		for slot in slots:
			lines.append("  %s: %s" % [slot.describe(), slots[slot].describe()])


var _previous: State = null


## Called per (state, events) pair. Always advances the baseline.
func check(state: State, events: Array[DL]) -> CheckResult:
	var result := CheckResult.new()
	if _previous == null:
		result.initial = true
		_previous = state
		return result

	var projected := _project(_previous, events)
	_compare_and_capture(projected.slots, state.slots, result)
	if not result.diffs.is_empty():
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
		DL.Type.POST_MANIPULATE:
			_apply_post_manipulate(state, ev)
		DL.Type.HP_CHANGED:
			if state.hp.has(ev.target):
				state.hp[ev.target].val = ev.new_hp
		DL.Type.PHASE_CHANGED:
			state.phase = ev.phase
		# SLOT_SHUFFLED, PLAYER_DIED, GAME_ENDED: no slot mutation needed
		# for projection. (SLOT_SHUFFLED scrambles a FULL slot's order; if
		# no subsequent card_moved follows in the same batch the next state
		# comparison will positionally diverge — the protocol's expected
		# fallback then is a state rebuild, which is what the Conductor
		# already does on `result.divergent`.)


## Source-side: extract a card. When `ev.card` carries the moved card's
## identity (protocol §3.2.3 — populated whenever either endpoint is
## card-visible), prefer identity-based removal — this stays correct after
## a shuffle, where positional indices are stale. Fall back to positional
## removal only when `ev.card` is absent (both endpoints count-only/hidden).
##
## Dest-side: insert. `ev.card` is server-authoritative; use it directly
## when present, even if extracted differs. When absent, the source's
## extracted instance is the best guess; if neither, source was hidden and
## the projection inevitably underpopulates the dest (next state rebuilds).
static func _apply_card_moved(state: State, ev: DL) -> void:
	var extracted: CardInstance = null
	if ev.orig.type == Loc.Type.SLOT and state.slots.has(ev.orig.slot):
		var contents: State.SlotContents = state.slots[ev.orig.slot]
		match contents.type:
			State.SlotContents.Type.FULL:
				if ev.card != null:
					var i := _find_card_idx(contents.cards, ev.card)
					if i >= 0:
						extracted = contents.cards[i]
						contents.cards.remove_at(i)
					elif ev.orig.idx >= 0 and ev.orig.idx < contents.cards.size():
						contents.cards.remove_at(ev.orig.idx)
				elif ev.orig.idx >= 0 and ev.orig.idx < contents.cards.size():
					extracted = contents.cards[ev.orig.idx]
					contents.cards.remove_at(ev.orig.idx)
			State.SlotContents.Type.COUNT:
				if contents.n > 0:
					contents.n -= 1

	var to_insert: CardInstance = ev.card if ev.card != null else extracted

	if ev.dest.type == Loc.Type.SLOT and state.slots.has(ev.dest.slot):
		var contents: State.SlotContents = state.slots[ev.dest.slot]
		match contents.type:
			State.SlotContents.Type.FULL:
				if to_insert != null:
					contents.cards.insert(clamp(ev.dest.idx, 0, contents.cards.size()), to_insert)
				# else: both endpoints hidden, no card identity available.
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


## PostManipulate (protocol §3.2.3): the manipulator's sidebar empties
## (its 2 cards plus a freshly-drawn opponent's-deck card are repartitioned),
## opponent's deck count is net unchanged (-1 drawn, +1 placed back), and
## opponent's refresh gains 2 cards. No per-card events are emitted for
## these moves; we project the count-level effects only.
static func _apply_post_manipulate(state: State, ev: DL) -> void:
	# Manipulator's sidebar — visible (FULL) only on the manipulator's
	# client; the non-manipulator has it filtered out (hidden).
	var sidebar_key := _find_slot_key(state, SlotID.Sidebar(ev.manipulator))
	if sidebar_key != null:
		var c: State.SlotContents = state.slots[sidebar_key]
		match c.type:
			State.SlotContents.Type.FULL: c.cards.clear()
			State.SlotContents.Type.COUNT: c.n = 0

	# Opponent's refresh — visible (COUNT) only on the non-manipulator's
	# client (own view); hidden on the manipulator's.
	var opp: NLEnums.PID = NLEnums.PID.BLUE if ev.manipulator == NLEnums.PID.RED else NLEnums.PID.RED
	var refresh_key := _find_slot_key(state, SlotID.Refresh(opp))
	if refresh_key != null:
		var c: State.SlotContents = state.slots[refresh_key]
		if c.type == State.SlotContents.Type.COUNT:
			c.n += 2

	# Opponent's deck: -1 (drawn) +1 (placed back) = net 0. No change.


## Linear-search helpers — SlotID and CardInstance instances aren't interned,
## so structural lookup is the right primitive. State.slots' keys all come
## from Catalog (canonical refs); SlotID.Sidebar/.Refresh manufactures fresh
## refs that won't match by identity.
static func _find_slot_key(state: State, target: SlotID) -> SlotID:
	for k in state.slots:
		if k.equals(target):
			return k
	return null


static func _find_card_idx(cards: Array[CardInstance], target: CardInstance) -> int:
	for i in cards.size():
		var c := cards[i]
		if c.template == target.template and c.counters == target.counters:
			return i
	return -1


# --- Cloning helpers ---

static func _clone_slots(slots: Dictionary[SlotID, State.SlotContents]) -> Dictionary[SlotID, State.SlotContents]:
	var out: Dictionary[SlotID, State.SlotContents] = {}
	for slot in slots:
		var c := slots[slot]
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


static func _clone_hp(hp: Dictionary[NLEnums.PID, State.HP]) -> Dictionary[NLEnums.PID, State.HP]:
	var out: Dictionary[NLEnums.PID, State.HP] = {}
	for pid in hp:
		var h := hp[pid]
		out[pid] = State.HP.new(h.val, h.cap, h.floor)
	return out


# --- Comparison ---

## Walks both slot maps and populates `result.diffs` (one verbose line per
## divergent slot) plus `result.divergent_{projected,actual}` (the captured
## contents of those slots). One pass, both halves, keeps slot identity
## attached to its dump.
static func _compare_and_capture(
	projected: Dictionary[SlotID, State.SlotContents],
	actual: Dictionary[SlotID, State.SlotContents],
	result: CheckResult,
) -> void:
	for slot in projected:
		if not actual.has(slot):
			result.diffs.append("slot %s: in projected but missing in actual" % slot.describe())
			result.divergent_projected[slot] = projected[slot]
		else:
			var diff := _content_diff(projected[slot], actual[slot])
			if not diff.is_empty():
				result.diffs.append("slot %s: %s" % [slot.describe(), diff])
				result.divergent_projected[slot] = projected[slot]
				result.divergent_actual[slot] = actual[slot]
	for slot in actual:
		if not projected.has(slot):
			result.diffs.append("slot %s: in actual but missing in projected" % slot.describe())
			result.divergent_actual[slot] = actual[slot]


## Returns a verbose, field-level reason why two SlotContents differ, or
## the empty string if they are equal. The reason names the variant tag,
## the specific field that mismatched, and both values side by side.
static func _content_diff(p: State.SlotContents, a: State.SlotContents) -> String:
	if p.type != a.type:
		return "variant mismatch: projected=%s actual=%s" % [
			State.SlotContents.Type.keys()[p.type],
			State.SlotContents.Type.keys()[a.type],
		]
	match p.type:
		State.SlotContents.Type.UNKNOWN:
			return ""
		State.SlotContents.Type.COUNT:
			if p.n == a.n:
				return ""
			return "COUNT n: projected=%d actual=%d" % [p.n, a.n]
		State.SlotContents.Type.FULL:
			if p.cards.size() != a.cards.size():
				return "FULL size: projected=%d actual=%d" % [p.cards.size(), a.cards.size()]
			for i in p.cards.size():
				var pc := p.cards[i]
				var ac := a.cards[i]
				if pc.template != ac.template:
					return "FULL cards[%d] template: projected=%s actual=%s" % [i, pc.describe(), ac.describe()]
				if pc.counters != ac.counters:
					return "FULL cards[%d] counters: projected=%s actual=%s" % [i, pc.describe(), ac.describe()]
			return ""
	return "<unknown SlotContents.Type=%s>" % p.type
