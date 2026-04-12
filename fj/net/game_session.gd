extends Node

const CatalogDataScript = preload("res://fj/net/catalog_data.gd")
const SessionLogScript = preload("res://fj/net/session_log.gd")

enum SessionState { DISCONNECTED, AWAITING_CATALOG, AWAITING_ROLE, IN_GAME, GAME_OVER }

## Fires once when both catalog and role_assignment have been received.
signal handshake_complete

## Ongoing game updates (subscribe after handshake).
signal state_updated(view: Dictionary)
signal prompt_arrived(text: String, options: Array)
signal notify_received(text: String)
signal session_ended(result: Variant)

## Authoritative session state - readable directly by GameBoard on _ready().
var state: SessionState = SessionState.DISCONNECTED
var catalog = null  # CatalogData
var my_role: String = ""
var my_side: String = ""
var latest_view: Dictionary = {}
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
	pending_prompt = {}
	log = SessionLogScript.new()
	log.log_event("connected")


func _on_disconnected() -> void:
	if log:
		log.log_event("disconnected", {"previous_state": SessionState.keys()[state]})
		log.save_to_file()
		log = null
	if state == SessionState.IN_GAME or state == SessionState.GAME_OVER:
		session_ended.emit(null)
	state = SessionState.DISCONNECTED


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
	if state != SessionState.IN_GAME:
		push_warning("GameSession: received state in unexpected state %s" % SessionState.keys()[state])
		return

	var view: Dictionary = msg.get("view", {})
	latest_view = view
	state_updated.emit(view)

	var game_result = view.get("game_result")
	if game_result != null:
		state = SessionState.GAME_OVER


func _handle_prompt(msg: Dictionary) -> void:
	if state != SessionState.IN_GAME:
		push_warning("GameSession: received prompt in unexpected state %s" % SessionState.keys()[state])
		return

	var text: String = msg.get("text", "")
	var options: Array = msg.get("options", [])
	pending_prompt = {"text": text, "options": options}
	prompt_arrived.emit(text, options)


func _handle_notify(msg: Dictionary) -> void:
	var kind: String = msg.get("kind", "")
	match kind:
		"role_assignment":
			_handle_role_assignment(msg)
		"info":
			var text: String = msg.get("text", "")
			notify_received.emit(text)
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
	session_ended.emit(null)


# --- Outgoing methods (called by GameBoard layer) ---

func _send(msg: Dictionary) -> void:
	if log:
		log.log_sent(msg)
	NetworkTransport.send_message(msg)


func respond(option: Dictionary) -> void:
	pending_prompt = {}
	_send({"type": "response", "option": option})


func resign() -> void:
	_send({"type": "resign"})


func offer_draw() -> void:
	_send({"type": "draw_offer"})


func accept_draw() -> void:
	_send({"type": "draw_accept"})
