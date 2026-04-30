## Dispatcher: translates one NL term at a time into Renderer widget calls.
## Owns its `SlotWrangler` for NL → CardView translation. Per-event signals
## fan delegated work out to whatever subscribers exist (zero, one, or many);
## Dispatcher itself doesn't import or know about InfoPanel or any other
## consumer.
##
## Composer-set configuration (set on Dispatcher fields before the node
## enters the tree):
##   slot_for, weapon_slot_for, overlay, card_factory, back_for_slot.
##
## Animation-gating model:
##   - Dispatcher's OWN animations (CardMoved fly, SlotTransferred fly,
##     SlotShuffled jiggle) emit `animation_started` / `animation_finished`
##     around their tweens — same as before.
##   - Per-event signals (hp_changed, phase_changed, player_died,
##     game_ended, state_rebuilt, prompt_applied) are pure announcements.
##     If a subscriber animates in response, it emits its own
##     animation_started/finished pair, which the composer wires to the
##     same ReadinessTracker via Conductor.mark_busy / mark_free.

class_name Dispatcher extends Node


const FLY_DURATION := 0.25
const SHUFFLE_DURATION := 0.20
const SHUFFLE_AMPLITUDE_PX := 4.0


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

var slot_for: Dictionary
var weapon_slot_for: Dictionary
var overlay: Control = null
var card_factory: Callable
var back_for_slot: Callable


# --- Internal ---

var _wrangler: SlotWrangler


func _ready() -> void:
	_wrangler = SlotWrangler.new()
	_wrangler.card_factory = card_factory
	_wrangler.back_for_slot = back_for_slot


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
		flying = _wrangler.create_card(null, _wrangler.back_for_slot.call(anchor_id), false)

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
	var src_slot: SlotView = slot_for.get(ev.orig)
	var dst_slot: SlotView = slot_for.get(ev.dest)
	if src_slot == null or dst_slot == null:
		return

	src_slot.clear()
	var flying := _wrangler.create_card(null, _wrangler.back_for_slot.call(ev.orig), false)
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
	var slot: SlotView = slot_for.get(ev.slot)
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
	for slot_id in slot_for:
		var view: SlotView = slot_for[slot_id]
		var contents: State.SlotContents = state.slots.get(slot_id)
		if contents == null:
			contents = State.UnknownContents.new()
		_wrangler.populate(view, slot_id, contents)


func _apply_prompt(prompt: Prompt) -> void:
	for slot_id in slot_for:
		(slot_for[slot_id] as SlotView).set_highlight(HighlightLevel.Level.LOWLIGHT)
	for ws_id in weapon_slot_for:
		(weapon_slot_for[ws_id] as WeaponSlotView).set_highlight(HighlightLevel.Level.LOWLIGHT)

	for opt in prompt.options:
		_apply_option_highlight(opt, HighlightLevel.Level.HIGHLIGHT)
	for opt in prompt.context:
		_apply_option_highlight(opt, HighlightLevel.Level.CONTEXT)


func _apply_option_highlight(opt: Option, level: HighlightLevel.Level) -> void:
	if opt is Option.SlotOption:
		var s := (opt as Option.SlotOption).slot
		if slot_for.has(s):
			(slot_for[s] as SlotView).set_highlight(level)
		elif weapon_slot_for.has(s):
			(weapon_slot_for[s] as WeaponSlotView).set_highlight(level)
	elif opt is Option.LocOption:
		var loc := (opt as Option.LocOption).loc
		if loc is Loc.SlotLoc:
			var sl := loc as Loc.SlotLoc
			var view: SlotView = slot_for.get(sl.slot)
			if view != null:
				var card := view.get_card(sl.idx)
				if card != null:
					card.set_highlight(level)


# --- Helpers ---

func _slot_view_of_loc(loc: Loc) -> SlotView:
	if loc is Loc.SlotLoc:
		return slot_for.get((loc as Loc.SlotLoc).slot)
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
