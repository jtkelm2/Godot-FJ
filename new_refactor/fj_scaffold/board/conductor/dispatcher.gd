## Dispatcher: translates one NL term at a time into Renderer widget calls.
## Owns its `SlotWrangler`, builds its internal slot-lookup dictionaries,
## and loads its own card backs. Knows nothing of Catalog or any wire-side
## component.
##
## SlotID-keyed lookups go through private linear-search helpers
## (`_find_view` / `_find_view_ws` / `_find_contents`) using
## `SlotID.equals` — SlotIDs aren't interned, so reference-equality dict
## lookup wouldn't find them.
##
## Composer-set configuration (set on Dispatcher fields before the node
## enters the tree):
##   slot_views                  — Array[SlotView]
##   weapon_slot_views           — Array[WeaponSlotView]
##   overlay                     — Control
##   card_factory                — Callable() -> CardView
##
## Per-event signals fan delegated work out to whatever subscribers exist;
## Dispatcher itself holds no reference to InfoPanel or any other consumer.

class_name Dispatcher extends Node


const FLY_DURATION := 0.25
const SHUFFLE_DURATION := 0.20
const SHUFFLE_AMPLITUDE_PX := 4.0

const _CARD_BACK_DIR := "res://fj/assets/images/cards/"


# --- Animation gating for Dispatcher's own tweens ---

signal animation_started
signal animation_finished


# --- Per-event signals (delegated to subscribers via composer) ---

signal hp_changed(target: NLEnums.PID, old: int, new: int)
signal phase_changed(phase: NLEnums.Phase)
signal player_died(target: NLEnums.PID)
signal game_ended(outcome: NLEnums.Outcome, won: Dictionary)
signal state_rebuilt(state: State)
signal prompt_applied(prompt: Prompt)


# --- Composer-set configuration ---

var slot_views: Array[SlotView] = []
var weapon_slot_views: Array[WeaponSlotView] = []
var overlay: Control = null
var card_factory: Callable


# --- Internal ---

var _wrangler: SlotWrangler
var _slot_for: Dictionary = {}            ## Dict[SlotID, SlotView]
var _weapon_slot_for: Dictionary = {}     ## Dict[SlotID, WeaponSlotView]
var _back_by_pid: Dictionary = {}         ## Dict[NLEnums.PID, Texture2D]
var _neutral_back: Texture2D = null


func _ready() -> void:
	_load_back_textures()
	_build_lookup_dicts()
	_wrangler = SlotWrangler.new()
	_wrangler.card_factory = card_factory
	_wrangler.back_for_slot = _back_for_slot


# --- Public dispatch ---

func handle(term: NL) -> void:
	if term is DL:
		_handle_dl(term as DL)
	elif term is State:
		_full_rebuild(term as State)
		state_rebuilt.emit(term as State)
	elif term is Prompt:
		_apply_prompt(term as Prompt)
		prompt_applied.emit(term as Prompt)


# --- DL handling ---

func _handle_dl(ev: DL) -> void:
	match ev.type:
		DL.Type.CARD_MOVED:       _animate_card_moved(ev)
		DL.Type.SLOT_TRANSFERRED: _animate_slot_transferred(ev)
		DL.Type.SLOT_SHUFFLED:    _animate_shuffle(ev)
		DL.Type.HP_CHANGED:       hp_changed.emit(ev.target, ev.old_hp, ev.new_hp)
		DL.Type.PHASE_CHANGED:    phase_changed.emit(ev.phase)
		DL.Type.PLAYER_DIED:      player_died.emit(ev.target)
		DL.Type.GAME_ENDED:       game_ended.emit(ev.outcome, ev.won)


func _animate_card_moved(ev: DL) -> void:
	var src_slot: SlotView = _slot_view_of_loc(ev.orig)
	var dst_slot: SlotView = _slot_view_of_loc(ev.dest)
	if src_slot == null and dst_slot == null:
		return

	var src_idx := _idx_of_loc(ev.orig)
	var dst_idx := _idx_of_loc(ev.dest)

	var src_pos := _slot_center_global(src_slot if src_slot else dst_slot)
	var dst_pos := _slot_center_global(dst_slot if dst_slot else src_slot)

	var flying: CardView = null
	if src_slot != null and src_idx >= 0 and src_idx < src_slot.count():
		flying = src_slot.remove(src_idx)
	if flying == null:
		var anchor_id: SlotID = _slot_id_of_loc(ev.orig if ev.orig.type == Loc.Type.SLOT else ev.dest)
		flying = _wrangler.create_card(null, _back_for_slot(anchor_id), false)

	overlay.add_child(flying)
	flying.position = src_pos - flying.size * 0.5

	animation_started.emit()
	var tween := create_tween()
	tween.tween_property(flying, "position", dst_pos - flying.size * 0.5, FLY_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	overlay.remove_child(flying)
	if dst_slot != null:
		dst_slot.insert(maxi(dst_idx, 0), flying)
	else:
		flying.queue_free()
	animation_finished.emit()


func _animate_slot_transferred(ev: DL) -> void:
	var src_slot: SlotView = _find_view(ev.orig_slot)
	var dst_slot: SlotView = _find_view(ev.dest_slot)
	if src_slot == null or dst_slot == null:
		return

	src_slot.clear()
	var flying := _wrangler.create_card(null, _back_for_slot(ev.orig_slot), false)
	overlay.add_child(flying)
	flying.position = _slot_center_global(src_slot) - flying.size * 0.5

	animation_started.emit()
	var tween := create_tween()
	tween.tween_property(flying, "position", _slot_center_global(dst_slot) - flying.size * 0.5, FLY_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	overlay.remove_child(flying)
	flying.queue_free()
	animation_finished.emit()


func _animate_shuffle(ev: DL) -> void:
	var slot: SlotView = _find_view(ev.slot)
	if slot == null:
		return
	var origin := slot.position
	animation_started.emit()
	var tween := create_tween()
	tween.tween_property(slot, "position", origin + Vector2(SHUFFLE_AMPLITUDE_PX, 0), SHUFFLE_DURATION * 0.25)
	tween.tween_property(slot, "position", origin + Vector2(-SHUFFLE_AMPLITUDE_PX, 0), SHUFFLE_DURATION * 0.5)
	tween.tween_property(slot, "position", origin, SHUFFLE_DURATION * 0.25)
	await tween.finished
	animation_finished.emit()


# --- State / Prompt synchronous Renderer work ---

func _full_rebuild(state: State) -> void:
	for slot_id in _slot_for:
		var view: SlotView = _slot_for[slot_id]
		var contents: State.SlotContents = _find_contents(state.slots, slot_id)
		if contents == null:
			contents = State.SlotContents.Unknown()
		_wrangler.populate(view, slot_id, contents)


func _apply_prompt(prompt: Prompt) -> void:
	for slot_id in _slot_for:
		(_slot_for[slot_id] as SlotView).set_highlight(HighlightLevel.Level.LOWLIGHT)
	for ws_id in _weapon_slot_for:
		(_weapon_slot_for[ws_id] as WeaponSlotView).set_highlight(HighlightLevel.Level.LOWLIGHT)

	for opt in prompt.options:
		_apply_option_highlight(opt, HighlightLevel.Level.HIGHLIGHT)
	for opt in prompt.context:
		_apply_option_highlight(opt, HighlightLevel.Level.CONTEXT)


func _apply_option_highlight(opt: Option, level: HighlightLevel.Level) -> void:
	match opt.type:
		Option.Type.SLOT:
			var view: SlotView = _find_view(opt.slot)
			if view != null:
				view.set_highlight(level)
			else:
				var ws: WeaponSlotView = _find_view_ws(opt.slot)
				if ws != null:
					ws.set_highlight(level)
		Option.Type.LOC:
			if opt.loc.type == Loc.Type.SLOT:
				var view: SlotView = _find_view(opt.loc.slot)
				if view != null:
					var card := view.get_card(opt.loc.idx)
					if card != null:
						card.set_highlight(level)


# --- Lookup-dict + back-texture construction (run once in _ready) ---

func _build_lookup_dicts() -> void:
	for view in slot_views:
		var sid := SlotID.make(view.kind, view.side, view.num)
		_slot_for[sid] = view
	for ws in weapon_slot_views:
		var sid := SlotID.WeaponZone(ws.side, ws.num)
		_weapon_slot_for[sid] = ws


func _load_back_textures() -> void:
	_back_by_pid[NLEnums.PID.RED] = load(_CARD_BACK_DIR + "back_red.png") as Texture2D
	_back_by_pid[NLEnums.PID.BLUE] = load(_CARD_BACK_DIR + "back_blue.png") as Texture2D
	_neutral_back = load(_CARD_BACK_DIR + "back1.png") as Texture2D


func _back_for_slot(slot_id: SlotID) -> Texture2D:
	if slot_id.type == SlotID.Type.GUARD_DECK:
		return _neutral_back
	return _back_by_pid.get(slot_id.side)


# --- SlotID-keyed lookup helpers (linear search via SlotID.equals) ---

func _find_view(target: SlotID) -> SlotView:
	for sid in _slot_for:
		if (sid as SlotID).equals(target):
			return _slot_for[sid]
	return null


func _find_view_ws(target: SlotID) -> WeaponSlotView:
	for sid in _weapon_slot_for:
		if (sid as SlotID).equals(target):
			return _weapon_slot_for[sid]
	return null


## Linear-search lookup against a Dict[SlotID, V] using SlotID.equals.
## Used for state.slots, whose keys come from a different construction site
## than ours (Deserializer's vs. Dispatcher._ready's).
static func _find_contents(slots: Dictionary, target: SlotID) -> State.SlotContents:
	for k in slots:
		if (k as SlotID).equals(target):
			return slots[k]
	return null


# --- Helpers ---

func _slot_view_of_loc(loc: Loc) -> SlotView:
	if loc.type == Loc.Type.SLOT:
		return _find_view(loc.slot)
	return null


func _idx_of_loc(loc: Loc) -> int:
	if loc.type == Loc.Type.SLOT:
		return loc.idx
	return -1


func _slot_id_of_loc(loc: Loc) -> SlotID:
	if loc.type == Loc.Type.SLOT:
		return loc.slot
	return null


static func _slot_center_global(slot: SlotView) -> Vector2:
	if slot == null:
		return Vector2.ZERO
	return slot.global_position + slot.size * 0.5
