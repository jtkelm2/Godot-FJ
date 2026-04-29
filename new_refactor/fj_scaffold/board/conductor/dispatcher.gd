## Dispatcher: translates one NL term at a time into Renderer widget calls.
## Owns its `SlotWrangler` for NL → CardView translation. Animations are
## fire-and-forget; the ReadinessTracker observes `animation_started` /
## `animation_finished` to gate the Scheduler.
##
## Composer-provided configuration (set on Dispatcher fields before the node
## enters the tree, since `_ready` constructs the wrangler from them):
##   - `slot_for: Dict[SlotID, SlotView]`
##   - `weapon_slot_for: Dict[SlotID.WeaponZone, WeaponSlotView]`
##   - `overlay: Control`         — parent for in-flight cards
##   - `card_factory: Callable`   — () -> CardView
##   - `back_for_slot: Callable`  — (slot_id: SlotID) -> Texture2D

class_name Dispatcher extends Node


const FLY_DURATION := 0.25
const SHUFFLE_DURATION := 0.20
const SHUFFLE_AMPLITUDE_PX := 4.0


signal animation_started
signal animation_finished


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

## Single entry point. The Conductor pushes one NL term at a time. Always
## emits `animation_finished` exactly once per call (synchronously or after
## a tween).
func handle(term: NL) -> void:
	if term is DL:
		_handle_dl(term as DL)
	elif term is State:
		_full_rebuild(term as State)
		animation_finished.emit()
	elif term is Prompt:
		_apply_prompt_highlights(term as Prompt)
		animation_finished.emit()
	else:
		animation_finished.emit()


# --- DL handling ---

func _handle_dl(ev: DL) -> void:
	if ev is DL.CardMoved:
		_animate_card_moved(ev as DL.CardMoved)
	elif ev is DL.SlotTransferred:
		_animate_slot_transferred(ev as DL.SlotTransferred)
	elif ev is DL.SlotShuffled:
		_animate_shuffle(ev as DL.SlotShuffled)
	else:
		# HPChanged, PhaseChanged, PlayerDied, GameEnded — Phase 5 routes these
		# to the info panel; for now they're acknowledged instantly.
		animation_finished.emit()


func _animate_card_moved(ev: DL.CardMoved) -> void:
	var src_slot: SlotView = _slot_view_of_loc(ev.orig)
	var dst_slot: SlotView = _slot_view_of_loc(ev.dest)
	if src_slot == null and dst_slot == null:
		animation_finished.emit()
		return

	var src_idx := _idx_of_loc(ev.orig)
	var dst_idx := _idx_of_loc(ev.dest)

	var src_pos := _slot_center_global(src_slot if src_slot else dst_slot)
	var dst_pos := _slot_center_global(dst_slot if dst_slot else src_slot)

	# Use the actual source card when visible; otherwise spawn a facedown
	# stand-in via the wrangler.
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
		animation_finished.emit()
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
	# The count update on dst_slot will arrive in the next state push;
	# Dispatcher doesn't synthesize CardInstances out of thin air.
	animation_finished.emit()


func _animate_shuffle(ev: DL.SlotShuffled) -> void:
	var slot: SlotView = slot_for.get(ev.slot)
	if slot == null:
		animation_finished.emit()
		return
	var origin := slot.position
	animation_started.emit()
	var tween := create_tween()
	tween.tween_property(slot, "position", origin + Vector2(SHUFFLE_AMPLITUDE_PX, 0), SHUFFLE_DURATION * 0.25)
	tween.tween_property(slot, "position", origin + Vector2(-SHUFFLE_AMPLITUDE_PX, 0), SHUFFLE_DURATION * 0.5)
	tween.tween_property(slot, "position", origin, SHUFFLE_DURATION * 0.25)
	await tween.finished
	animation_finished.emit()


# --- State / Prompt ---

## Full rebuild from authoritative state. Iterates `slot_for` and stocks each
## SlotView from the corresponding entry in `state.slots` (UnknownContents
## for slots absent from state).
func _full_rebuild(state: State) -> void:
	for slot_id in slot_for:
		var view: SlotView = slot_for[slot_id]
		var contents: State.SlotContents = state.slots.get(slot_id)
		if contents == null:
			contents = State.UnknownContents.new()
		_wrangler.populate(view, slot_id, contents)


## Decorate prompt options with HIGHLIGHT, context with CONTEXT, everything
## else with LOWLIGHT.
func _apply_prompt_highlights(prompt: Prompt) -> void:
	# Reset everything first.
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
	# TextOption: no spatial decoration; the info panel renders text options
	# (Phase 5).


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
