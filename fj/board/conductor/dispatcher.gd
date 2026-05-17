## Dispatcher: thin NL → Board / InfoPanel translator. Owns no animation
## state; every visible mutation goes through the Board's composite API or
## the InfoPanel public surface. Holds no card factory, no overlay
## reference, no slot lookups (Board has `find_slot`).
##
## InfoPanels are configured by the composer as a `Dictionary[PID, panel]`;
## Dispatcher fans state/prompt/event updates out to every configured panel
## directly, so subscribers no longer need to wire `hp_changed`/`phase_changed`
## etc. themselves. The per-event signals are still emitted for external
## observers (loggers, tests, replay tools).
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

# --- Composer-set configuration ---

var board: Board = null

## InfoPanels keyed by the PID whose perspective each panel renders. Set by
## the composer before `add_child`; Dispatcher fans events out to every
## panel here and, for events that target a specific PID (HP_CHANGED,
## PLAYER_DIED), raises an error if that PID has no configured panel.
var info_panels: Dictionary[NLEnums.PID, InfoPanel] = {}

## Single PhaseBanner. Set by the composer before `add_child`.
var phase_banner: PhaseBanner = null

## Single RoleScreen for dramatic role reveals on the local player's
## perspective. Set by the composer before `add_child`. Plays the first
## time a non-empty role appears in State.role[App._my_pid] and again
## whenever the role's name changes; identical-name State pushes (e.g.
## divergence rebuilds) are filtered by `_shown_role_name`.
var role_screen: RoleScreen = null

func _ready() -> void:
	for pid in info_panels:
		var panel: InfoPanel = info_panels[pid]
		panel.set_my_pid(pid)
		panel.animation_started.connect(animation_started.emit)
		panel.animation_finished.connect(animation_finished.emit)


# --- Public dispatch ---

## `term as <Subtype>` narrows the NL parameter to a concrete subtype before
## passing to per-subtype handlers — `if term is X` does not flow-narrow the
## static type in GDScript, so the casts are required at the call sites.
func handle(term: NL) -> void:
	if App._my_pid == NLEnums.PID.BLUE: App.logger.write("conductor.handling", Logg.describe_nl(term))
	if term is DL:
		await _handle_dl(term as DL)
	elif term is State:
		var s := term as State
		_full_rebuild(s)
		for panel in info_panels.values():
			panel.bind_state(s)
	elif term is Prompt:
		var p := term as Prompt
		_apply_prompt(p)
		for panel:InfoPanel in info_panels.values(): # TODO: Prompt messages should include the player in review mode
			panel.bind_prompt(p)


# --- DL handling ---

func _handle_dl(ev: DL) -> void:
	match ev.type:
		DL.Type.CARD_MOVED:       await _on_card_moved(ev)
		DL.Type.SLOT_TRANSFERRED: await _on_slot_transferred(ev)
		DL.Type.SLOT_SHUFFLED:    await _on_slot_shuffled(ev)
		DL.Type.POST_MANIPULATE:  await _on_post_manipulate(ev)
		DL.Type.HP_CHANGED:       await _on_hp_changed(ev)
		DL.Type.PHASE_CHANGED:    await _on_phase_changed(ev)
		DL.Type.ROLE_ASSIGNED:    await _on_show_role(ev.card, ev.role)
		DL.Type.PLAYER_DIED:      _on_player_died(ev) # TODO: mournful animation overlay
		DL.Type.GAME_ENDED:       _on_game_ended(ev) # TODO: animation overlay depending on outcome


func _on_card_moved(ev: DL) -> void:
	var src: SlotView = _slot_view_of_loc(ev.orig)
	var dst: SlotView = _slot_view_of_loc(ev.dest)
	var card_front: Texture2D = ev.card.template.front if ev.card != null and ev.card_endstate == DL.CardState.FACEUP else null

	if src == null and dst == null:
		return

	var action: Action
	if src != null and dst != null:
		var move = board.move_card(src, ev.orig.idx, dst, ev.dest.idx, card_front)
		if ev.card_endstate == DL.CardState.DISCARD:
			var discard = Action.Lazy.new(board.discard_card.bind(dst, ev.dest.idx, _anchor_for_one_sided(dst)))
			action = Action.Seq.new([move, discard])
		else: action = move
	elif src == null and dst != null:
		action = board.spawn_card(dst, ev.dest.idx, _anchor_for_one_sided(dst), card_front)
	else:    # src != null, dst == null
		action = board.discard_card(src, ev.orig.idx, _anchor_for_one_sided(src))
	await _orchestrate(action)


func _on_slot_transferred(ev: DL) -> void:
	var src: SlotView = _slot_view_of_loc(ev.orig)
	var dst: SlotView = _slot_view_of_loc(ev.dest)
	await _orchestrate(board.slot_transfer_all(src,dst))


func _on_slot_shuffled(ev: DL) -> void:
	var slot := _find(ev.slot)
	if slot == null:
		return
	await _orchestrate(board.wiggle_slot(slot))


func _on_hp_changed(ev: DL) -> void:
	_require_panel(ev.target, "HP_CHANGED")
	await info_panels[ev.target].flash_hp(ev.old_hp, ev.new_hp)


func _on_phase_changed(ev: DL) -> void:
	for panel in info_panels.values():
		panel.set_phase(ev.phase)
	if phase_banner != null:
		await _orchestrate(phase_banner.play_for_phase(ev.phase))

func _on_show_role(card:CardInstance, role:State.Role):
	role_screen.role_name = role.role_name
	role_screen.role_front = card.template.front
	role_screen.role_back = board.back_for_pid(App._my_pid)
	await _orchestrate(role_screen.play())

func _on_player_died(ev: DL) -> void:
	_require_panel(ev.target, "PLAYER_DIED")
	for panel in info_panels.values():
		panel.mark_player_died(ev.target)


func _on_game_ended(ev: DL) -> void:
	for panel in info_panels.values():
		panel.set_game_result(ev.outcome, ev.won)


func _require_panel(pid: NLEnums.PID, ctx: String) -> void:
	if not info_panels.has(pid):
		push_error("Dispatcher: %s targets PID %s but no info_panel is configured for that PID" \
			% [ctx, NLEnums.PID.keys()[pid]])


func _on_post_manipulate(ev: DL) -> void:
	var opp: NLEnums.PID = NLEnums.PID.BLUE if ev.manipulator == NLEnums.PID.RED else NLEnums.PID.RED
	var sidebar := board.find_slot(ev.manipulator, SlotID.Type.SIDEBAR, 0)
	var opp_deck := board.find_slot(opp, SlotID.Type.DECK, 0)
	var opp_refresh := board.find_slot(opp, SlotID.Type.REFRESH, 0)
	var and_discard := ev.into_hidden_zone

	var actions: Array[Action] = [
		board.slot_transfer_all(sidebar, opp_deck),
		board.slot_transfer(opp_deck, opp_refresh, 2, and_discard)
	]
	await _orchestrate(Action.Seq.new(actions))


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
	var back := board.back_for_slot(view)
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
