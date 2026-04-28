## WireRouter: WL ↔ NL bidirectional translator.
##
## Wire-agnostic of its surroundings — knows nothing about Transport,
## WireCodec, or NexusRouter. Composition wires them together externally:
##
##   transport.recv     ──►  WireCodec.decode  ──►  wire_router.wl_in
##   wire_router.wl_out ──►  WireCodec.encode  ──►  transport.send
##   wire_router.state_received  ──►  nexus_router.push_state
##   nexus_router.rl_out         ──►  wire_router.send_response
##
## Internal: a single Catalog, built on the first WCL message. State machine
## is just AWAITING_CATALOG → ACTIVE → CLOSED. Use `reset()` to return to
## AWAITING_CATALOG (e.g., on transport reconnect).

class_name WireRouter extends Node


enum SessionState { AWAITING_CATALOG, ACTIVE, CLOSED }


# --- Outbound NL signals ---

signal handshake_complete
signal pid_assigned(pid: NLEnums.PID)
signal state_received(state: State, events: Array[DL])
signal prompt_received(prompt: Prompt)
signal notify_received(notify: Prompt.Notify)
signal session_closed


# --- Outbound WL signal ---

signal wl_out(msg: Dictionary)


var _state: SessionState = SessionState.AWAITING_CATALOG
var _catalog: Catalog = null


# --- Inbound WL ---

func wl_in(msg: Dictionary) -> void:
	var msg_type := str(msg.get("type", ""))
	match msg_type:
		"catalog":  _handle_catalog(msg)
		"state":    _handle_state(msg)
		"prompt":   _handle_prompt(msg)
		"notify":   _handle_notify(msg)
		"close":    _handle_close()
		_:
			push_warning("WireRouter: unknown wire message type '%s'" % msg_type)


# --- Inbound NL (outbound across the boundary) ---

func send_response(option: Option) -> void:
	if _state != SessionState.ACTIVE:
		push_warning("WireRouter.send_response: not active (state=%s)" % SessionState.keys()[_state])
		return
	wl_out.emit(Serializer.serialize_response(option, _catalog))


func send_resign() -> void:
	if _state == SessionState.CLOSED: return
	wl_out.emit(Serializer.serialize_resign())


func send_draw_offer() -> void:
	if _state == SessionState.CLOSED: return
	wl_out.emit(Serializer.serialize_draw_offer())


func send_draw_accept() -> void:
	if _state == SessionState.CLOSED: return
	wl_out.emit(Serializer.serialize_draw_accept())


# --- Lifecycle ---

## Returns to AWAITING_CATALOG and clears the catalog. Call from the
## composer when the transport reconnects.
func reset() -> void:
	_state = SessionState.AWAITING_CATALOG
	_catalog = null


# --- Internal handlers ---

func _handle_catalog(msg: Dictionary) -> void:
	if _state != SessionState.AWAITING_CATALOG:
		push_warning("WireRouter: catalog received in unexpected state %s" % SessionState.keys()[_state])
		return
	_catalog = Catalog.new(msg)
	_state = SessionState.ACTIVE
	handshake_complete.emit()


func _handle_state(msg: Dictionary) -> void:
	if _state != SessionState.ACTIVE:
		push_warning("WireRouter: state received in unexpected state %s" % SessionState.keys()[_state])
		return
	var view: Dictionary = msg.get("view", {})
	var events_raw: Array = msg.get("events", [])
	var wire_state := Deserializer.parse_state(view, _catalog)
	var nl_state := Deserializer.lift_state(wire_state, _catalog)
	var events := Deserializer.parse_dl_batch(events_raw, _catalog)
	state_received.emit(nl_state, events)


func _handle_prompt(msg: Dictionary) -> void:
	if _state != SessionState.ACTIVE:
		push_warning("WireRouter: prompt received in unexpected state %s" % SessionState.keys()[_state])
		return
	prompt_received.emit(Deserializer.parse_prompt(msg, _catalog))


func _handle_notify(msg: Dictionary) -> void:
	# pid_assignment is special: it carries the receiving client's absolute PID
	# (§3.4.2) and gets a dedicated typed signal. All other notify kinds pass
	# through as generic Prompt.Notify values.
	if str(msg.get("kind", "")) == "pid_assignment":
		pid_assigned.emit(Deserializer.parse_pid(str(msg.get("pid", ""))))
		return
	notify_received.emit(Deserializer.parse_notify(msg))


func _handle_close() -> void:
	_state = SessionState.CLOSED
	session_closed.emit()
