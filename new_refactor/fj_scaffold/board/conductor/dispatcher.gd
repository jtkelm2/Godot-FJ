## Dispatcher: translates one NL term at a time into Renderer widget calls.
## Owns its `SlotWrangler`, builds its internal slot-lookup dictionaries,
## and loads its own card backs. Knows nothing of Catalog or any wire-side
## component.
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
var _slot_for: Dictionary = {}            ## Dict[Array[3], SlotView] keyed by SlotID.key()
var _weapon_slot_for: Dictionary = {}     ## Dict[Array[3], WeaponSlotView] keyed by SlotID.key()
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
	if ev is DL.CardMoved:
		_animate_card_moved(ev as DL.CardMoved)
	elif ev is DL.SlotTransferred:
		_animate_slot_transferred(ev as DL.SlotTransferred)
	elif ev is DL.SlotShuffled:
		_animate_shuffle(ev as DL.SlotShuffled)
	elif ev is DL.HPChanged:
		var hpc := ev as DL.HPChanged
		hp_changed.emit(hpc.target, hpc.old_hp, hpc.new_hp)
	elif ev is DL.PhaseChanged:
		phase_changed.emit((ev as DL.PhaseChanged).phase)
	elif ev is DL.PlayerDied:
		player_died.emit((ev as DL.PlayerDied).target)
	elif ev is DL.GameEnded:
		var ge := ev as DL.GameEnded
		game_ended.emit(ge.outcome, ge.won)


func _animate_card_moved(ev: DL.CardMoved) -> void:
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
		var anchor_id: SlotID = _slot_id_of_loc(ev.orig if ev.orig is Loc.SlotLoc else ev.dest)
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


func _animate_slot_transferred(ev: DL.SlotTransferred) -> void:
	var src_slot: SlotView = _slot_for.get(ev.orig.key())
	var dst_slot: SlotView = _slot_for.get(ev.dest.key())
	if src_slot == null or dst_slot == null:
		return

	src_slot.clear()
	var flying := _wrangler.create_card(null, _back_for_slot(ev.orig), false)
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


func _animate_shuffle(ev: DL.SlotShuffled) -> void:
	var slot: SlotView = _slot_for.get(ev.slot.key())
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
	for slot_key in _slot_for:
		var view: SlotView = _slot_for[slot_key]
		var slot_id := SlotID.make(slot_key[0], slot_key[1], slot_key[2])
		var contents: State.SlotContents = _find_contents(state.slots, slot_key)
		if contents == null:
			contents = State.UnknownContents.new()
		_wrangler.populate(view, slot_id, contents)


func _apply_prompt(prompt: Prompt) -> void:
	for slot_key in _slot_for:
		(_slot_for[slot_key] as SlotView).set_highlight(HighlightLevel.Level.LOWLIGHT)
	for ws_key in _weapon_slot_for:
		(_weapon_slot_for[ws_key] as WeaponSlotView).set_highlight(HighlightLevel.Level.LOWLIGHT)

	for opt in prompt.options:
		_apply_option_highlight(opt, HighlightLevel.Level.HIGHLIGHT)
	for opt in prompt.context:
		_apply_option_highlight(opt, HighlightLevel.Level.CONTEXT)


func _apply_option_highlight(opt: Option, level: HighlightLevel.Level) -> void:
	if opt is Option.SlotOption:
		var s := (opt as Option.SlotOption).slot
		var k := s.key()
		if _slot_for.has(k):
			(_slot_for[k] as SlotView).set_highlight(level)
		elif _weapon_slot_for.has(k):
			(_weapon_slot_for[k] as WeaponSlotView).set_highlight(level)
	elif opt is Option.LocOption:
		var loc := (opt as Option.LocOption).loc
		if loc is Loc.SlotLoc:
			var sl := loc as Loc.SlotLoc
			var view: SlotView = _slot_for.get(sl.slot.key())
			if view != null:
				var card := view.get_card(sl.idx)
				if card != null:
					card.set_highlight(level)


# --- Lookup-dict + back-texture construction (run once in _ready) ---

func _build_lookup_dicts() -> void:
	for view in slot_views:
		_slot_for[_view_key(view)] = view
	for ws in weapon_slot_views:
		_weapon_slot_for[_view_key_weapon(ws)] = ws


func _load_back_textures() -> void:
	_back_by_pid[NLEnums.PID.RED] = load(_CARD_BACK_DIR + "back_red.png") as Texture2D
	_back_by_pid[NLEnums.PID.BLUE] = load(_CARD_BACK_DIR + "back_blue.png") as Texture2D
	_neutral_back = load(_CARD_BACK_DIR + "back1.png") as Texture2D


func _back_for_slot(slot_id: SlotID) -> Texture2D:
	if slot_id is SlotID.GuardDeck:
		return _neutral_back
	# All non-GuardDeck SlotIDs carry `side`.
	return _back_by_pid.get(slot_id.side)


# --- Helpers ---

static func _view_key(view: SlotView) -> Array:
	return [int(view.kind), int(view.side), view.num]


static func _view_key_weapon(ws: WeaponSlotView) -> Array:
	return [int(NLEnums.SlotKind.WS), int(ws.side), ws.num]


## state.slots is keyed by SlotID instances (whose `key()` matches our keys).
## We look up by structural key rather than instance.
static func _find_contents(slots: Dictionary, slot_key: Array) -> State.SlotContents:
	for k in slots:
		if (k as SlotID).key() == slot_key:
			return slots[k]
	return null


func _slot_view_of_loc(loc: Loc) -> SlotView:
	if loc is Loc.SlotLoc:
		return _slot_for.get((loc as Loc.SlotLoc).slot.key())
	return null


func _idx_of_loc(loc: Loc) -> int:
	if loc is Loc.SlotLoc:
		return (loc as Loc.SlotLoc).idx
	return -1


func _slot_id_of_loc(loc: Loc) -> SlotID:
	if loc is Loc.SlotLoc:
		return (loc as Loc.SlotLoc).slot
	return null


static func _slot_center_global(slot: SlotView) -> Vector2:
	if slot == null:
		return Vector2.ZERO
	return slot.global_position + slot.size * 0.5
