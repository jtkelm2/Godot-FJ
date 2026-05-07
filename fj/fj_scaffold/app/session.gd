## Session: the composed Player — Conductor + InputHandler — wired to a
## NexusRouter and a Board scene. Constructed by App at handshake time
## (after `pid_assignment` notify has resolved my_pid).
##
## Session is the composition root for the in-game half of the architecture.

class_name Session extends Node


const CARD_VIEW_SCENE_PATH := "res://fj/fj_scaffold/board/scenes/card_view.tscn"


var _conductor: Conductor
var _input: InputHandler
var _board: Board

## Public: the composer (App) can configure sink/silencing before bootstrap
## or anytime afterward.
var logger: Logg = Logg.new()


func bootstrap(my_pid: NLEnums.PID, nexus: NexusRouter, board: Board) -> void:
	_board = board

	board.info_panel.set_my_pid(my_pid)

	var card_scene: PackedScene = load(CARD_VIEW_SCENE_PATH)

	_conductor = Conductor.new()
	_conductor.slot_views = board.slot_views
	_conductor.weapon_slot_views = board.weapon_slot_views
	_conductor.overlay = board.overlay
	_conductor.card_factory = func() -> CardView:
		return card_scene.instantiate() as CardView
	add_child(_conductor)

	_input = InputHandler.new()
	add_child(_input)

	_wire_nexus(nexus)
	_wire_dispatcher_to_info_panel()
	_wire_info_panel_animation_gating()
	_wire_scene_inputs()
	if my_pid == NLEnums.PID.BLUE: _wire_logger()


# --- Wiring helpers ---

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
	_board.info_panel.animation_started.connect(_conductor.mark_busy)
	_board.info_panel.animation_finished.connect(_conductor.mark_free)


func _wire_scene_inputs() -> void:
	for view in _board.slot_views:
		var slot_id := SlotID.make(view.kind, view.side, view.num)
		view.card_clicked.connect(func(_v: SlotView, idx: int): _input.on_card_clicked(slot_id, idx))
		view.slot_clicked.connect(func(_v: SlotView): _input.on_slot_clicked(slot_id))
		view.card_hovered.connect(func(_v: SlotView, idx: int): _board.info_panel.preview_card(view, idx))
		view.card_unhovered.connect(func(_v: SlotView): _board.info_panel.preview_card(null, -1))
	for ws in _board.weapon_slot_views:
		var ws_id := SlotID.WeaponZone(ws.side, ws.num)
		ws.weapon_slot_clicked.connect(func(_w: WeaponSlotView): _input.on_weapon_slot_clicked(ws_id))

	_board.info_panel.text_option_selected.connect(_input.on_text_option)


func _wire_logger() -> void:
	_conductor.handling.connect(_log_handling)
	_conductor.divergence_detected.connect(_log_divergence)


func _log_handling(term: NL) -> void:
	logger.write("conductor.handling", Logg.describe_nl(term))


## Multi-line; we prefix the report with a newline so the first divergence
## line lands below the bracketed stream tag instead of next to it. Each
## subsequent line carries no tag — they're part of the same dump.
func _log_divergence(report: String) -> void:
	logger.write("conductor.divergence", "\n" + report)
