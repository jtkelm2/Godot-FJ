## NexusRouter: pure bidirectional NL fanout. Wire-agnostic — knows nothing
## about WireRouter, local engines, replays, or any other source / sink. The
## composition root (`App`) wires it up by connecting whatever produces NL to
## the inbound `push_*` methods, and whatever consumes outbound NL to the
## `*_out` signals.
##
## Inbound side (NL into the player):
##   external producer  ──push_state(state, events)──►  sl_in  ──►  consumers
##   external producer  ──push_prompt(prompt)──────►  pl_in  ──►  consumers
##   external producer  ──push_notify(notify)──────►  notify_in  ──►  consumers
##
## Outbound side (NL out of the player):
##   consumer  ──send_response(option)─────►  rl_out  ──►  external sink
##   consumer  ──send_resign()─────────────►  resign_out  ──►  external sink
##   consumer  ──send_draw_offer()─────────►  draw_offer_out  ──►  external sink
##   consumer  ──send_draw_accept()────────►  draw_accept_out  ──►  external sink
##
## SL carries its paired DL batch in the same signal so DivergenceMonitor
## sees them atomically; that's the only deviation from a pure 1-term-per-call
## API and it's required by the architecture's SL+DL pairing contract.

class_name NexusRouter extends Node


# --- Inbound signals (consumed by GameBoard, Conductor, DivergenceMonitor, …) ---

signal sl_in(state: State, events: Array[DL])
signal pl_in(prompt: Prompt)
signal notify_in(notify: Prompt.Notify)


# --- Outbound signals (consumed by WireRouter, local engine, replay log, …) ---

signal rl_out(option: Option)
signal resign_out
signal draw_offer_out
signal draw_accept_out


# --- Inbound push methods ---

func push_state(state: State, events: Array[DL]) -> void:
	sl_in.emit(state, events)


func push_prompt(prompt: Prompt) -> void:
	pl_in.emit(prompt)


func push_notify(notify: Prompt.Notify) -> void:
	notify_in.emit(notify)


# --- Outbound send methods ---

func send_response(option: Option) -> void:
	rl_out.emit(option)


func send_resign() -> void:
	resign_out.emit()


func send_draw_offer() -> void:
	draw_offer_out.emit()


func send_draw_accept() -> void:
	draw_accept_out.emit()
