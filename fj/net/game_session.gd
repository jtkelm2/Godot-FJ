extends Node

const CatalogDataScript = preload("res://fj/net/catalog_data.gd")

enum SessionState { DISCONNECTED, AWAITING_CATALOG, IN_GAME, GAME_OVER }

signal catalog_ready(catalog: RefCounted)
signal state_updated(view: Dictionary)
signal prompt_arrived(text: String, options: Array)
signal notify_received(text: String)
signal session_ended(result: Variant)

var state: SessionState = SessionState.DISCONNECTED
var catalog = null  # CatalogData


func _ready() -> void:
	NetworkTransport.message_received.connect(_on_message_received)
	NetworkTransport.connected.connect(_on_connected)
	NetworkTransport.disconnected.connect(_on_disconnected)


func _on_connected() -> void:
	state = SessionState.AWAITING_CATALOG
	catalog = null


func _on_disconnected() -> void:
	if state == SessionState.IN_GAME:
		session_ended.emit(null)
	state = SessionState.DISCONNECTED
	catalog = null


func _on_message_received(msg: Dictionary) -> void:
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
	state = SessionState.IN_GAME
	catalog_ready.emit(catalog)


func _handle_state(msg: Dictionary) -> void:
	if state != SessionState.IN_GAME:
		push_warning("GameSession: received state before catalog")
		return

	var view: Dictionary = msg.get("view", {})
	state_updated.emit(view)

	# Check for game result in this state
	var game_result = view.get("game_result")
	if game_result != null:
		state = SessionState.GAME_OVER


func _handle_prompt(msg: Dictionary) -> void:
	if state != SessionState.IN_GAME:
		push_warning("GameSession: received prompt before catalog")
		return

	var text: String = msg.get("text", "")
	var options: Array = msg.get("options", [])
	prompt_arrived.emit(text, options)


func _handle_notify(msg: Dictionary) -> void:
	var text: String = msg.get("text", "")
	notify_received.emit(text)


func _handle_close() -> void:
	state = SessionState.GAME_OVER
	session_ended.emit(null)


# --- Outgoing methods (called by GameBoard layer) ---

func respond(option: Dictionary) -> void:
	NetworkTransport.send_message({"type": "response", "option": option})


func resign() -> void:
	NetworkTransport.send_message({"type": "resign"})


func offer_draw() -> void:
	NetworkTransport.send_message({"type": "draw_offer"})


func accept_draw() -> void:
	NetworkTransport.send_message({"type": "draw_accept"})
