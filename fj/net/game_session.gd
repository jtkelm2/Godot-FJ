extends Node

## Protocol state machine and single source of truth for the board's view of
## the game. Speaks to NetworkTransport on the wire side; exposes a tiny API
## to the UI side:
##
##   - `latest_view`, `pending_prompt`, `catalog`, `my_side`, `my_role` — state.
##   - `changed`           — something the UI needs to re-render has changed.
##   - `notify_received`   — a pulse-style side-channel message for toasts.
##   - `handshake_complete` — fires once when ready to load the board scene.
##   - `respond(option)`   — send a response to the outstanding prompt.

const CatalogDataScript = preload("res://fj/net/catalog_data.gd")
const SessionLogScript = preload("res://fj/net/session_log.gd")

enum SessionState { DISCONNECTED, AWAITING_CATALOG, AWAITING_ROLE, IN_GAME, GAME_OVER }

signal handshake_complete
signal changed
signal notify_received(text: String)

var state: SessionState = SessionState.DISCONNECTED
var catalog = null  # CatalogData
var my_role: String = ""
var my_side: String = ""
var latest_view: Dictionary = {}
## Events that arrived with the most recent state push (cleared by Board after
## it consumes them). Advisory: the view is authoritative, but events let the
## UI animate transitions.
var latest_events: Array = []
var pending_prompt: Dictionary = {}
var log = null  # SessionLog


func _ready() -> void:
	NetworkTransport.message_received.connect(_on_message_received)
	NetworkTransport.connected.connect(_on_connected)
	NetworkTransport.disconnected.connect(_on_disconnected)


func _on_connected() -> void:
	state = SessionState.AWAITING_CATALOG
	catalog = null
	my_role = ""
	my_side = ""
	latest_view = {}
	latest_events = []
	pending_prompt = {}
	log = SessionLogScript.new()
	log.log_event("connected")


func _on_disconnected() -> void:
	if log:
		log.log_event("disconnected", {"previous_state": SessionState.keys()[state]})
		log.save_to_file()
		log = null
	var was_in_game := state == SessionState.IN_GAME or state == SessionState.GAME_OVER
	state = SessionState.DISCONNECTED
	if was_in_game:
		changed.emit()


func _on_message_received(msg: Dictionary) -> void:
	if log:
		log.log_received(msg)

	var msg_type: String = msg.get("type", "")

	match msg_type:
		"catalog":
			_handle_catalog(msg)
		"state":
			_handle_state(msg)
		"prompt":
			_handle_prompt(msg)
		"notify":
			_handle_notify(msg)
		"close":
			_handle_close()
		_:
			push_warning("GameSession: unknown message type '%s'" % msg_type)


func _handle_catalog(msg: Dictionary) -> void:
	if state != SessionState.AWAITING_CATALOG:
		push_warning("GameSession: received catalog in unexpected state %s" % SessionState.keys()[state])
		return
	catalog = CatalogDataScript.new()
	catalog.parse_from(msg)
	state = SessionState.AWAITING_ROLE


func _handle_state(msg: Dictionary) -> void:
	if state != SessionState.IN_GAME and state != SessionState.GAME_OVER:
		push_warning("GameSession: received state in unexpected state %s" % SessionState.keys()[state])
		return
	latest_view = msg.get("view", {})
	latest_events = msg.get("events", [])
	if latest_view.get("game_result") != null:
		state = SessionState.GAME_OVER
	changed.emit()


func _handle_prompt(msg: Dictionary) -> void:
	if state != SessionState.IN_GAME:
		push_warning("GameSession: received prompt in unexpected state %s" % SessionState.keys()[state])
		return
	pending_prompt = {
		"text": msg.get("text", ""),
		"options": msg.get("options", []),
		"context": msg.get("context", []),
	}
	changed.emit()


func _handle_notify(msg: Dictionary) -> void:
	var kind: String = msg.get("kind", "")
	match kind:
		"role_assignment":
			_handle_role_assignment(msg)
		_:
			var text: String = msg.get("text", "")
			if not text.is_empty():
				notify_received.emit(text)


func _handle_role_assignment(msg: Dictionary) -> void:
	my_role = msg.get("role", "")
	my_side = msg.get("side", "")
	if catalog:
		catalog.my_color = my_side
	if state == SessionState.AWAITING_ROLE:
		state = SessionState.IN_GAME
		handshake_complete.emit()
	else:
		push_warning("GameSession: role_assignment arrived in unexpected state %s" % SessionState.keys()[state])


func _handle_close() -> void:
	if log:
		log.log_event("session_closed")
		log.save_to_file()
	state = SessionState.GAME_OVER
	changed.emit()


# --- Outgoing ---

func _send(msg: Dictionary) -> void:
	if log:
		log.log_sent(msg)
	NetworkTransport.send_message(msg)


func respond(option: Dictionary) -> void:
	# Clear first so any re-entrant signal/handler sees an empty prompt.
	pending_prompt = {}
	_send({"type": "response", "option": option})


func resign() -> void:
	_send({"type": "resign"})


func offer_draw() -> void:
	_send({"type": "draw_offer"})


func accept_draw() -> void:
	_send({"type": "draw_accept"})
