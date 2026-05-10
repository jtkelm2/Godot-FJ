## Dispatcher: thin NL → Board translator. Owns no animation state; every
## visible mutation goes through the Board's composite API. Holds no card
## factory, no overlay reference, no slot lookups (Board has `find_slot`).
##
## Per-event signals fan delegated work out to whatever subscribers exist;
## Dispatcher itself holds no reference to InfoPanel or any other consumer.
##
## **Action orchestration.** Each animated DL produces an `Action`
## (Seq/Par/Twact/Sync/Lazy tree, see `action/action.gd`); `_orchestrate`
## runs and awaits one such Action between `animation_started` and
## `animation_finished`. A multi-composite work-unit (e.g. `post_manipulate`
## = drain ‖ fill) becomes a `Par.new([drain_action, fill_action])` and
## gates as a single animation, not several stacked ones. Compared to the
## flat-tween model, nested parallelism preserves each Action's internal
## sequencing — e.g. SimpleSlotView's `relayout` Action keeps its
## (apply_visibility → positions → fix_tree_order) order intact even when
## embedded in an outer Par.

class_name Dispatcher extends Node


# --- Animation gating ---

signal animation_started
signal animation_finished


# --- Per-event signals (delegated to subscribers via composer) ---

signal handling(term: NL)
signal hp_changed(target: NLEnums.PID, old: int, new: int)
signal phase_changed(phase: NLEnums.Phase)
signal player_died(target: NLEnums.PID)
signal game_ended(outcome: NLEnums.Outcome, won: Dictionary[NLEnums.PID, bool])
signal state_rebuilt(state: State)
signal prompt_applied(prompt: Prompt)


# --- Composer-set configuration ---

var board: Board = null


# --- Public dispatch ---

## `term as <Subtype>` narrows the NL parameter to a concrete subtype before
## passing to per-subtype handlers — `if term is X` does not flow-narrow the
## static type in GDScript, so the casts are required at the call sites.
func handle(term: NL) -> void:
	handling.emit(term)
	if term is DL:
		await _handle_dl(term as DL)
	elif term is State:
		_full_rebuild(term as State)
		state_rebuilt.emit(term as State)
	elif term is Prompt:
		_apply_prompt(term as Prompt)
		prompt_applied.emit(term as Prompt)


# --- DL handling ---

func _handle_dl(ev: DL) -> void:
	match ev.type:
		DL.Type.CARD_MOVED:       await _on_card_moved(ev)
		DL.Type.SLOT_TRANSFERRED: await _on_slot_transferred(ev)
		DL.Type.SLOT_SHUFFLED:    await _on_slot_shuffled(ev)
		DL.Type.POST_MANIPULATE:  await _on_post_manipulate(ev)
		DL.Type.HP_CHANGED:       hp_changed.emit(ev.target, ev.old_hp, ev.new_hp)
		DL.Type.PHASE_CHANGED:    phase_changed.emit(ev.phase)
		DL.Type.PLAYER_DIED:      player_died.emit(ev.target)
		DL.Type.GAME_ENDED:       game_ended.emit(ev.outcome, ev.won)


func _on_card_moved(ev: DL) -> void:
	var src: SlotView = _slot_view_of_loc(ev.orig)
	var dst: SlotView = _slot_view_of_loc(ev.dest)
	var card_front: Texture2D = ev.card.template.front if ev.card != null else null

	if src == null and dst == null:
		return

	var action: Action
	if src != null and dst != null:
		action = board.move_card(src, ev.orig.idx, dst, ev.dest.idx, card_front)
	elif src == null and dst != null:
		action = board.spawn_card(dst, ev.dest.idx, _anchor_for_one_sided(dst), card_front)
	else:    # src != null, dst == null
		action = board.discard_card(src, ev.orig.idx, _anchor_for_one_sided(src))
	await _orchestrate(action)


func _on_slot_transferred(ev: DL) -> void:
	var src := _find(ev.orig_slot)
	var dst := _find(ev.dest_slot)
	if src == null and dst == null:
		return

	var actions: Array[Action] = []
	if src != null:
		# Drain to dst's location if dst is visible, else to src itself
		# (cards just dissipate in place).
		actions.append(board.drain_slot(src, dst if dst != null else src))
	if dst != null:
		# Fill from src's location if src is visible, else from dst itself.
		actions.append(board.fill_slot_from(src if src != null else dst, dst, ev.count))
	if actions.is_empty():
		return
	await _orchestrate(Action.Par.new(actions))


func _on_slot_shuffled(ev: DL) -> void:
	var slot := _find(ev.slot)
	if slot == null:
		return
	await _orchestrate(board.wiggle_slot(slot))


func _on_post_manipulate(ev: DL) -> void:
	var opp: NLEnums.PID = NLEnums.PID.BLUE if ev.manipulator == NLEnums.PID.RED else NLEnums.PID.RED
	var sidebar := board.find_slot(ev.manipulator, SlotID.Type.SIDEBAR, 0)
	var opp_deck := board.find_slot(opp, SlotID.Type.DECK, 0)
	var opp_refresh := board.find_slot(opp, SlotID.Type.REFRESH, 0)

	var actions: Array[Action] = []
	if sidebar != null and sidebar.count() > 0:
		var anchor: SlotView = opp_deck if opp_deck != null else sidebar
		actions.append(board.drain_slot(sidebar, anchor))
	if opp_refresh != null:
		var anchor: SlotView = opp_deck if opp_deck != null else opp_refresh
		actions.append(board.fill_slot_from(anchor, opp_refresh, 2))
	if actions.is_empty():
		return
	await _orchestrate(Action.Par.new(actions))


# --- State / Prompt synchronous Renderer work ---

func _full_rebuild(state: State) -> void:
	for slot_view in board.slots():
		var slot_id := SlotID.make(slot_view.kind, slot_view.side, slot_view.num)
		var contents: State.SlotContents = _find_contents(state.slots, slot_id)
		if contents == null:
			contents = State.SlotContents.Unknown()
		var descriptors := _descriptors_from(contents, slot_view)
		board.populate_slot(slot_view, descriptors)


func _apply_prompt(prompt: Prompt) -> void:
	board.clear_all_highlights()
	for opt in prompt.options:
		_apply_option_highlight(opt, HighlightLevel.Level.HIGHLIGHT)
	for opt in prompt.context:
		_apply_option_highlight(opt, HighlightLevel.Level.CONTEXT)


func _apply_option_highlight(opt: Option, level: HighlightLevel.Level) -> void:
	match opt.type:
		Option.Type.SLOT:
			var view := _find(opt.slot)
			if view != null:
				board.set_slot_highlight(view, level)
			else:
				var ws := _find_ws(opt.slot)
				if ws != null:
					ws.set_highlight(level)
		Option.Type.LOC:
			if opt.loc.type == Loc.Type.SLOT:
				var view := _find(opt.loc.slot)
				if view != null:
					board.set_card_highlight(view, opt.loc.idx, level)


# --- Orchestration ---

## Run an Action as a single readiness-gated work-unit. One
## animation_started / animation_finished pair fires per call regardless of
## how complex the Action's tree is — a multi-composite work-unit (e.g.
## `_on_post_manipulate`'s drain ‖ fill) gates as one animation.
func _orchestrate(action: Action) -> void:
	animation_started.emit()
	await action.run()
	animation_finished.emit()


# --- Helpers ---

## SlotID → SlotView. SlotIDs live in NL; the renderer only deals in views.
## SlotID's discriminant field is `type`; SlotView's @export is `kind` —
## same value, different field name across the NL/renderer boundary.
func _find(target: SlotID) -> SlotView:
	if target == null:
		return null
	return board.find_slot(target.side, target.type, target.num)


func _find_ws(target: SlotID) -> WeaponSlotView:
	if target == null:
		return null
	return board.find_weapon_slot(target.side, target.num)


func _slot_view_of_loc(loc: Loc) -> SlotView:
	if loc == null or loc.type != Loc.Type.SLOT:
		return null
	return _find(loc.slot)


## When a one-sided card_moved happens (hidden source or hidden dest), we
## use the visible side's own slot as the anchor — cards "appear from" /
## "disappear into" their own slot.
static func _anchor_for_one_sided(visible: SlotView) -> SlotView:
	return visible


## Linear-search lookup against a Dict[SlotID, V] using SlotID.equals.
## Used for state.slots, whose keys come from Catalog vs. our locally
## constructed `SlotID.make(...)` from view exports — different refs.
static func _find_contents(slots: Dictionary, target: SlotID) -> State.SlotContents:
	for k in slots:
		if (k as SlotID).equals(target):
			return slots[k]
	return null


## Build CardDescriptors for a SlotContents, picking the right back via
## `board.back_for(view)`. FULL → faceup descriptors with each card's
## front; COUNT → `n` facedown descriptors; UNKNOWN → empty array.
func _descriptors_from(contents: State.SlotContents, view: SlotView) -> Array[CardDescriptor]:
	var out: Array[CardDescriptor] = []
	var back := board.back_for(view)
	match contents.type:
		State.SlotContents.Type.UNKNOWN:
			pass
		State.SlotContents.Type.COUNT:
			for _i in contents.n:
				out.append(CardDescriptor.face_down(back))
		State.SlotContents.Type.FULL:
			for c in contents.cards:
				out.append(CardDescriptor.face_up(c.template.front, back))
	return out
