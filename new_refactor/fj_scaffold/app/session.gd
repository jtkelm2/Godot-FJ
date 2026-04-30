## Session: the composed Player — Conductor + InputHandler — wired to a
## NexusRouter and a Board scene. Constructed by App at handshake time
## (after Catalog is built and `pid_assignment` notify has resolved my_pid).
##
## Session is the composition root for the in-game half of the architecture.
## It does the wiring that neither Conductor nor Board nor NexusRouter does
## itself — every connection you'll see below is one of:
##
##   - NL flow upward    (NexusRouter signals → Conductor / InputHandler push methods)
##   - NL flow downward  (InputHandler.option_accepted → NexusRouter.send_response)
##   - Renderer events   (Dispatcher per-event signals → InfoPanel methods)
##   - Animation gating  (InfoPanel animation_started/finished → Conductor mark_busy/free)
##   - Scene input       (SlotView/WeaponSlotView click signals → InputHandler, with SlotID bound)
##
## Every component remains independent (no inter-component imports). Session
## is the only thing that knows about all of them.

class_name Session extends Node


const CARD_VIEW_SCENE_PATH := "res://new_refactor/fj_scaffold/board/scenes/card_view.tscn"


var _conductor: Conductor
var _input: InputHandler
var _board: Board
var _catalog: Catalog
var _my_pid: NLEnums.PID
var _slot_for: Dictionary = {}
var _weapon_slot_for: Dictionary = {}


func bootstrap(catalog: Catalog, my_pid: NLEnums.PID, nexus: NexusRouter, board: Board) -> void:
	_catalog = catalog
	_my_pid = my_pid
	_board = board

	board.info_panel.set_my_pid(my_pid)

	_build_slot_dicts()

	var card_scene: PackedScene = load(CARD_VIEW_SCENE_PATH)

	_conductor = Conductor.new()
	_conductor.slot_for = _slot_for
	_conductor.weapon_slot_for = _weapon_slot_for
	_conductor.overlay = board.overlay
	_conductor.card_factory = func() -> CardView:
		return card_scene.instantiate() as CardView
	_conductor.back_for_slot = func(slot_id: SlotID) -> Texture2D:
		if slot_id is SlotID.GuardDeck:
			return _catalog.neutral_back()
		return _catalog.back_for_pid(_side_of(slot_id))
	add_child(_conductor)

	_input = InputHandler.new()
	add_child(_input)

	_wire_nexus(nexus)
	_wire_dispatcher_to_info_panel()
	_wire_info_panel_animation_gating()
	_wire_scene_inputs()


# --- Wiring helpers ---

func _build_slot_dicts() -> void:
	for view in _board.find_slot_views():
		var slot_id := _catalog.slot_id_for(view.side, view.kind, view.num)
		if slot_id != null:
			_slot_for[slot_id] = view
	for ws in _board.find_weapon_slot_views():
		var ws_id := _catalog.weapon_slot_id_for(ws.side, ws.num)
		if ws_id != null:
			_weapon_slot_for[ws_id] = ws


func _wire_nexus(nexus: NexusRouter) -> void:
	nexus.sl_in.connect(_conductor.push_state)
	nexus.pl_in.connect(_conductor.push_prompt)
	nexus.pl_in.connect(_input.set_pending_prompt)
	nexus.notify_in.connect(func(notify: Prompt.Notify): _board.info_panel.show_notify(notify.text))

	_input.option_accepted.connect(nexus.send_response)
	_input.option_accepted.connect(func(_o: Option): _board.info_panel.clear_prompt())


func _wire_dispatcher_to_info_panel() -> void:
	_conductor.hp_changed.connect(_board.info_panel.flash_hp)
	_conductor.phase_changed.connect(_board.info_panel.set_phase)
	_conductor.player_died.connect(_board.info_panel.mark_player_died)
	_conductor.game_ended.connect(_board.info_panel.set_game_result)
	_conductor.state_rebuilt.connect(_board.info_panel.bind_state)
	_conductor.prompt_applied.connect(_board.info_panel.bind_prompt)


func _wire_info_panel_animation_gating() -> void:
	# InfoPanel's HP-flash (and any future animated info-panel feedback) must
	# gate the Scheduler so subsequent NL terms wait. The composition feeds
	# its animation signals into the same ReadinessTracker the Dispatcher
	# uses.
	_board.info_panel.animation_started.connect(_conductor.mark_busy)
	_board.info_panel.animation_finished.connect(_conductor.mark_free)


func _wire_scene_inputs() -> void:
	for slot_id: SlotID in _slot_for:
		var view: SlotView = _slot_for[slot_id]
		view.card_clicked.connect(func(_v: SlotView, idx: int): _input.on_card_clicked(slot_id, idx))
		view.slot_clicked.connect(func(_v: SlotView): _input.on_slot_clicked(slot_id))
		view.card_hovered.connect(func(_v: SlotView, idx: int): _board.info_panel.preview_card(view, idx))
		view.card_unhovered.connect(func(_v: SlotView): _board.info_panel.preview_card(null, -1))
	for ws_id: SlotID in _weapon_slot_for:
		var ws: WeaponSlotView = _weapon_slot_for[ws_id]
		ws.weapon_slot_clicked.connect(func(_w: WeaponSlotView): _input.on_weapon_slot_clicked(ws_id))

	_board.info_panel.text_option_selected.connect(_input.on_text_option)


## SlotID side accessor — every constructor except GuardDeck carries `side`.
## Caller filters GuardDeck before invoking.
static func _side_of(slot_id: SlotID) -> NLEnums.PID:
	if "side" in slot_id:
		return slot_id.side
	return NLEnums.PID.RED
