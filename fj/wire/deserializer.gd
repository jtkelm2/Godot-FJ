## Deserializer: WL Variant dicts → typed NL/WL values.
##
## Per `WireLang = DL | WireState | Prompt | Response | WireCatalog`, the
## sublanguages DL, Prompt, Notify, and Response are produced as NL directly
## (no separate Wire-prefixed type). Only `state` is materialized into the
## WL `WireState` (with `WireSlotInfo` carrying `WireCardInfo` cards), because
## CardTemplate resolution is heavy and stays lazy at this layer.
##
## All factory methods are static and take a Catalog. They tolerate (warn +
## return null) on unknown tags per protocol §1.2; malformed shapes get
## push_error.
##
## **Untyped Dictionary at the wire boundary.** All `Dictionary` parameters in
## this file carry JSON-shaped payloads — the dicts are produced by
## `JSON.parse_string` and arrive as runtime-untyped Dictionary. Typing them
## as `Dictionary[String, Variant]` would force a runtime entry-by-entry
## coercion at every call without buying real protection (we already access
## fields via `.get(key, default)`). Internal dicts we construct here ARE
## typed strictly.

@abstract
class_name Deserializer extends RefCounted


# --- Top-level wire messages ---

## `state` payload → WireState. `view` is the inner wire dict.
## Card content is left in WL form (`WireSlotInfo` carrying `WireCardInfo`).
## Use `lift_state` to resolve those into NL `SlotContents` / `CardInstance`.
static func parse_state(view: Dictionary, catalog: Catalog) -> WireState:
	var s := WireState.new()
	_parse_players(view.get("players", {}), s)
	s.phase = parse_phase(view.get("current_phase"))
	s.priority = parse_pid(str(view.get("priority", "")))
	s.slots = _parse_wire_slot_table(view.get("slots", {}), catalog)
	return s


## WL → NL: resolves WireCardInfo (name string) into CardInstance (with a
## CardTemplate ref looked up from Catalog), and WireSlotInfo variants into
## the corresponding SlotContents variants. Cheap because Catalog has all
## CardTemplates eagerly loaded — this is just a dict-traversal + lookups.
static func lift_state(ws: WireState, catalog: Catalog) -> State:
	var s := State.new()
	s.role = ws.role
	s.hp = ws.hp
	s.phase = ws.phase
	s.priority = ws.priority
	s.slots = {}
	for slot: SlotID in ws.slots:
		s.slots[slot] = _lift_slot_info(ws.slots[slot], catalog)
	return s


static func _lift_slot_info(wsi: WireSlotInfo, catalog: Catalog) -> State.SlotContents:
	match wsi.type:
		WireSlotInfo.Type.UNKNOWN:
			return State.SlotContents.Unknown()
		WireSlotInfo.Type.COUNT:
			return State.SlotContents.Count(wsi.n)
		WireSlotInfo.Type.FULL:
			var cards: Array[CardInstance] = []
			for wci in wsi.cards:
				cards.append(CardInstance.new(catalog.card_for(wci.name), wci.counters))
			return State.SlotContents.Full(cards)
	push_error("Deserializer.lift_state: unknown WireSlotInfo type: %s" % wsi.type)
	return State.SlotContents.Unknown()


## `events` array → DL list. Skips unparseable / unknown events with a warning.
static func parse_dl_batch(events: Array, state: State, catalog: Catalog) -> Array[DL]:
	var out: Array[DL] = []
	for e in events:
		if e is Dictionary:
			var d := parse_dl(e, state, catalog)
			if d != null:
				out.append(d)
	return out


## `event` dict → DL. Returns null for unknown event types.
##
## `dict.get(key)` returns null for absent keys; the protocol now omits keys
## entirely instead of sending JSON null (§3.2.3 / §3.4), so absent and
## explicit-null are treated identically. Each branch documents which fields
## are optional.
static func parse_dl(e: Dictionary, state: State, catalog: Catalog) -> DL:
	match str(e.get("type", "")):
		"card_moved":
			# `source` / `source_index` are omitted when the card had no
			# prior slot. `card` is omitted when both endpoints are
			# count-only or hidden.
			return DL.CardMoved(
				_parse_loc(e.get("source"), e.get("source_index"), catalog),
				_parse_loc(e.get("dest"), e.get("dest_index"), catalog),
				_parse_cardstate(e.get("dest"), state, catalog),
				_parse_card(e.get("card"), catalog),
			)
		"slot_transferred":
			return DL.SlotTransferred(
				catalog.slot_for(str(e.get("source", ""))),
				catalog.slot_for(str(e.get("dest", ""))),
				_parse_cardstate(e.get("dest"), state, catalog),
				int(e.get("count", 0)),
			)
		"hp_changed":
			return DL.HPChanged(
				parse_pid(str(e.get("target", ""))),
				int(e.get("old", 0)),
				int(e.get("new", 0)),
			)
		"slot_shuffled":
			return DL.SlotShuffled(catalog.slot_for(str(e.get("slot", ""))))
		"post_manipulate":
			# `forced` is present only on the manipulator's view AND only
			# when they forced; -1 sentinel means "absent." Check explicitly
			# against null (not just `e.has`) — `int(null)` is 0, which
			# collides with valid force-index 0.
			var forced_v: Variant = e.get("forced")
			var forced: int = int(forced_v) if forced_v != null else -1
			var effect_v: Variant = e.get("effect")
			var effect: bool = effect_v != null
			return DL.PostManipulate(parse_pid(str(e.get("manipulator", ""))), forced, effect)
		"role_assigned":
			var alignment = NLEnums.Alignment.GOOD if str(e.role) == "GOOD" else NLEnums.Alignment.EVIL
			var card = _parse_card(e.card, catalog)
			var name = card.template.display_name
			var role = State.Role.new(alignment, name)
			var pid = parse_pid(e.player)
			return DL.RoleAssigned(pid, card, role)
		"player_died":
			return DL.PlayerDied(parse_pid(str(e.get("target", ""))))
		"phase_changed":
			# `phase` is omitted between phases (no new phase yet).
			return DL.PhaseChanged(parse_phase(e.get("phase")))
		"game_ended":
			return DL.GameEnded(
				parse_outcome(str(e.get("outcome", ""))),
				_parse_won(e.get("winners", [])),
			)
		_:
			push_warning("Deserializer.parse_dl: unknown event type: %s" % e)
			return null


## Optional `card` payload on `card_moved` → CardInstance, or null if absent.
## Shape: `{"name": <string>, "counters": <int>}` (same as a slot entry).
static func _parse_card(v: Variant, catalog: Catalog) -> CardInstance:
	if v == null:
		return null
	if not (v is Dictionary):
		push_warning("Deserializer._parse_card: expected dict, got %s" % v)
		return null
	var d := v as Dictionary
	var card_name := str(d.get("name", ""))
	if not catalog.has_card(card_name):
		push_warning("Deserializer._parse_card: unknown card name '%s'" % card_name)
		return null
	return CardInstance.new(catalog.card_for(card_name), int(d.get("counters", 0)))


## `prompt` payload → Prompt.
## `must_select` is omitted on the wire when == 1 (§3.3).
static func parse_prompt(d: Dictionary, catalog: Catalog) -> Prompt:
	var p := Prompt.new()
	p.text = str(d.get("text", ""))
	p.options = _parse_option_array(d.get("options", []), catalog)
	p.context = _parse_option_array(d.get("context", []), catalog)
	p.must_select = int(d.get("must_select", 1))
	return p


## `notify` payload → Prompt.Notify.
static func parse_notify(d: Dictionary) -> Prompt.Notify:
	return Prompt.Notify.new(str(d.get("kind", "")), str(d.get("text", "")))


## Single option dict → typed Option. Returns null for unknown option types
## (which receivers MUST tolerate per protocol §3.3.1 / §1.2).
static func parse_option(d: Dictionary, catalog: Catalog) -> Option:
	match str(d.get("type", "")):
		"text":
			return Option.Text(str(d.get("text", "")))
		"card":
			var slot_wire := str(d.get("slot", ""))
			var idx := int(d.get("index", -1))
			return Option.Loc(Loc.Slot(catalog.slot_for(slot_wire), idx))
		"slot":
			return Option.Slot(catalog.slot_for(str(d.get("name", ""))))
		"weapon_slot":
			return Option.Slot(catalog.weapon_slot_for(str(d.get("name", ""))))
		"revealed_card":
			return Option.RevealedCard(catalog.card_for(d.name))
		_:
			push_warning("Deserializer.parse_option: unknown option type: %s" % d)
			return null


# --- Primitive parsers ---

static func parse_pid(s: String) -> NLEnums.PID:
	match s.to_upper():
		"RED":  return NLEnums.PID.RED
		"BLUE": return NLEnums.PID.BLUE
		_:
			push_error("Deserializer.parse_pid: unknown PID '%s'" % s)
			return NLEnums.PID.RED


static func parse_phase(v: Variant) -> NLEnums.Phase:
	if v == null:
		return NLEnums.Phase.NONE
	match str(v).to_upper():
		"SETUP":        return NLEnums.Phase.SETUP
		"REFRESH":      return NLEnums.Phase.REFRESH
		"MANIPULATION": return NLEnums.Phase.MANIPULATION
		"ACTION":       return NLEnums.Phase.ACTION
		_:
			push_warning("Deserializer.parse_phase: unknown phase '%s'; treating as NONE" % v)
			return NLEnums.Phase.NONE


static func parse_alignment(s: String) -> NLEnums.Alignment:
	match s.to_upper():
		"GOOD": return NLEnums.Alignment.GOOD
		"EVIL": return NLEnums.Alignment.EVIL
		_:
			push_warning("Deserializer.parse_alignment: unknown alignment '%s'; defaulting to GOOD" % s)
			return NLEnums.Alignment.GOOD


static func parse_outcome(s: String) -> NLEnums.Outcome:
	match s.to_upper():
		"MUTUAL_GOOD_WIN":          return NLEnums.Outcome.MUTUAL_GOOD_WIN
		"GOOD_KILLED_EVIL":         return NLEnums.Outcome.GOOD_KILLED_EVIL
		"EVIL_KILLED_GOOD":         return NLEnums.Outcome.EVIL_KILLED_GOOD
		"GOOD_KILLED_GOOD":         return NLEnums.Outcome.GOOD_KILLED_GOOD
		"EXHAUSTION":               return NLEnums.Outcome.EXHAUSTION
		"GOOD_GOOD_MUTUAL_DEATH":   return NLEnums.Outcome.GOOD_GOOD_MUTUAL_DEATH
		"GOOD_EVIL_MUTUAL_DEATH":   return NLEnums.Outcome.GOOD_EVIL_MUTUAL_DEATH
		"GOOD_THWARTED":            return NLEnums.Outcome.GOOD_THWARTED
		"EVIL_THWARTED":            return NLEnums.Outcome.EVIL_THWARTED
		_:
			push_warning("Deserializer.parse_outcome: unknown outcome '%s'; defaulting to EXHAUSTION" % s)
			return NLEnums.Outcome.EXHAUSTION


# --- Internal helpers ---

## (slot_wire, idx) → Loc. Both nullable per protocol §3.2.3 (CardMoved.source).
static func _parse_loc(slot_wire_v: Variant, idx_v: Variant, catalog: Catalog) -> Loc:
	if slot_wire_v == null:
		return Loc.Unknown()
	var slot := catalog.slot_for(str(slot_wire_v))
	var idx := -1 if idx_v == null else int(idx_v)
	return Loc.Slot(slot, idx)

static func _parse_cardstate(slot_wire_v: Variant, state: State, catalog: Catalog) -> DL.CardState:
	var slot := catalog.slot_for(str(slot_wire_v))
	match state.slots[slot].type:
		State.SlotContents.Type.UNKNOWN:
			return DL.CardState.DISCARD
		State.SlotContents.Type.COUNT:
			return DL.CardState.FACEDOWN
		State.SlotContents.Type.FULL:
			return DL.CardState.FACEUP
		_:
			push_error("Unknown slot type for %s" % slot)
			return DL.CardState.DISCARD

static func _parse_option_array(a: Array, catalog: Catalog) -> Array[Option]:
	var r: Array[Option] = []
	for entry in a:
		if entry is Dictionary:
			var o := parse_option(entry, catalog)
			if o != null:
				r.append(o)
	return r


## view.players (Dict[PID-string, {role, alignment, hp}]) → state.role and
## state.hp dicts. Both PIDs are always present in view.players per protocol
## §3.2; hidden fields are null. We materialize a Role/HP entry only when the
## relevant fields are non-null on the wire.
static func _parse_players(players: Dictionary, into: WireState) -> void:
	for pid_str in players:
		var pid := parse_pid(str(pid_str))
		var block: Dictionary = players[pid_str]
		var role_v = block.get("role")
		var align_v = block.get("alignment")
		if role_v != null and not str(role_v).is_empty():
			var alignment := parse_alignment(str(align_v)) if align_v != null else NLEnums.Alignment.GOOD
			into.role[pid] = State.Role.new(alignment, str(role_v))
		var hp_v = block.get("hp")
		if hp_v != null:
			# cap/floor not on the wire (TBD via local game-rule constants).
			into.hp[pid] = State.HP.new(int(hp_v), 0, 0)


## view.slots → Dict[SlotID, WireSlotInfo]. Slots absent from the view dict
## are treated as fog-of-war hidden and represented as WireSlotInfo.Unknown.
static func _parse_wire_slot_table(raw: Dictionary, catalog: Catalog) -> Dictionary[SlotID, WireSlotInfo]:
	var out: Dictionary[SlotID, WireSlotInfo] = {}
	# Visible slots (present in view).
	for wire_name in raw:
		var key := str(wire_name)
		if not catalog.has_slot(key):
			push_warning("Deserializer: view references unknown slot '%s'" % key)
			continue
		out[catalog.slot_for(key)] = _parse_wire_slot_info(raw[wire_name])
	# Hidden slots (in catalog but absent from view).
	for slot in catalog.all_slots():
		if not out.has(slot):
			out[slot] = WireSlotInfo.Unknown()
	return out


## `as Array` / `as Dictionary` here narrow Variant from JSON. The casts
## cannot be dropped — `if v is Array:` does not flow-narrow the static type
## of `v` to Array in GDScript; the iterator and `.get(...)` access need a
## casted local.
static func _parse_wire_slot_info(v: Variant) -> WireSlotInfo:
	if v is Array:
		var cards: Array[WireCardInfo] = []
		for entry: Variant in (v as Array):
			if entry is Dictionary:
				var d := entry as Dictionary
				cards.append(WireCardInfo.new(
					str(d.get("name", "")),
					int(d.get("counters", 0)),
				))
		return WireSlotInfo.Full(cards)
	if v is int or v is float:
		return WireSlotInfo.Count(int(v))
	push_warning("Deserializer: unknown slot value shape: %s" % v)
	return WireSlotInfo.Unknown()


## winners array (e.g., ["RED"]) → Dict[PID, bool].
static func _parse_won(winners: Array) -> Dictionary[NLEnums.PID, bool]:
	var out: Dictionary[NLEnums.PID, bool] = {
		NLEnums.PID.RED: false,
		NLEnums.PID.BLUE: false,
	}
	for w in winners:
		out[parse_pid(str(w))] = true
	return out
