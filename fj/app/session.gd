## Session: the composed Player — Conductor + InputHandler — wired to a Board
## scene and exposing the NL boundary as its own signals. Constructed by App
## at handshake time (after `pid_assignment` notify has resolved my_pid).
##
## Session is the composition root for the in-game half of the architecture,
## and it is the NL boundary: external producers (WireRouter, replay tools,
## tests) connect to `sl_in` / `pl_in` / `notify_in`; external sinks
## subscribe to `rl_out` / `resign_out` / `draw_offer_out` / `draw_accept_out`.

class_name Session extends Node


# --- Inbound NL signals (App wires these from WireRouter at bootstrap) ---
# Emitted externally via signal-to-signal connects, hence the suppressions.

@warning_ignore("unused_signal") signal sl_in(state: State, events: Array[DL])
@warning_ignore("unused_signal") signal pl_in(prompt: Prompt)
@warning_ignore("unused_signal") signal notify_in(notify: Prompt.Notify)


# --- Outbound NL signals (App wires these into WireRouter at bootstrap) ---

signal rl_out(option: Option)
@warning_ignore("unused_signal") signal resign_out
@warning_ignore("unused_signal") signal draw_offer_out
@warning_ignore("unused_signal") signal draw_accept_out


var _conductor: Conductor
var _input: InputHandler
var _board: Board


func bootstrap(my_pid: NLEnums.PID, board: Board) -> void:
	_board = board

	_conductor = Conductor.new()
	_conductor.board = board
	_conductor.info_panels = {my_pid: board.info_panel}
	_conductor.phase_banner = board.phase_banner
	add_child(_conductor)

	_input = InputHandler.new()
	add_child(_input)

	_wire_nl_signals()
	_wire_scene_inputs()


# --- Wiring helpers ---

func _wire_nl_signals() -> void:
	sl_in.connect(_conductor.push_state)
	pl_in.connect(_conductor.push_prompt)
	pl_in.connect(_input.set_pending_prompt)
	notify_in.connect(func(notify: Prompt.Notify): _board.info_panel.show_notify(notify.text))

	_input.option_accepted.connect(rl_out.emit)
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
