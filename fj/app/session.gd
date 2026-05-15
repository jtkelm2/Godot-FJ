## Session: the composed Player — Conductor + InputHandler — wired to a
## NexusRouter and a Board scene. Constructed by App at handshake time
## (after `pid_assignment` notify has resolved my_pid).
##
## Session is the composition root for the in-game half of the architecture.

class_name Session extends Node


var _conductor: Conductor
var _input: InputHandler
var _board: Board


func bootstrap(my_pid: NLEnums.PID, nexus: NexusRouter, board: Board) -> void:
	_board = board

	_conductor = Conductor.new()
	_conductor.board = board
	_conductor.info_panels = {my_pid: board.info_panel}
	add_child(_conductor)

	_input = InputHandler.new()
	add_child(_input)

	_wire_nexus(nexus)
	_wire_scene_inputs()

# --- Wiring helpers ---

func _wire_nexus(nexus: NexusRouter) -> void:
	nexus.sl_in.connect(_conductor.push_state)
	nexus.pl_in.connect(_conductor.push_prompt)
	nexus.pl_in.connect(_input.set_pending_prompt)
	nexus.notify_in.connect(func(notify: Prompt.Notify): _board.info_panel.show_notify(notify.text))

	_input.option_accepted.connect(nexus.send_response)
	_input.option_accepted.connect(func(_o: Option): _board.info_panel.clear_prompt())


func _wire_scene_inputs() -> void:
	for view in _board.slots():
		var slot_id := SlotID.make(view.kind, view.side, view.num)
		view.card_clicked.connect(func(_v: SlotView, idx: int): _input.on_card_clicked(slot_id, idx))
		view.slot_clicked.connect(func(_v: SlotView): _input.on_slot_clicked(slot_id))
		view.card_hovered.connect(func(_v: SlotView, idx: int): _board.info_panel.preview_card(view, idx))
		view.card_unhovered.connect(func(_v: SlotView): _board.info_panel.preview_card(null, -1))
	for ws in _board.weapon_slots():
		var ws_id := SlotID.WeaponZone(ws.side, ws.num)
		ws.weapon_slot_clicked.connect(func(_w: WeaponSlotView): _input.on_weapon_slot_clicked(ws_id))

	_board.info_panel.text_option_selected.connect(_input.on_text_option)
	
	_input.option_accepted.connect(func(_opt): _board.clear_all_highlights())
