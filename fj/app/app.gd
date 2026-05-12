## App: the single autoload. Owns the lifetime of Transport, WireRouter,
## NexusRouter, and (when in-game) Session. Orchestrates connection
## lifecycle and scene transitions.
##
## ConnectionScreen is the main scene. When the user connects, App constructs
## a Transport, wires `transport ↔ WireCodec ↔ WireRouter` and
## `WireRouter ↔ NexusRouter`. As soon as both `handshake_complete(catalog)`
## and `pid_assigned(pid)` arrive, App swaps to Board.tscn and bootstraps a
## Session. On disconnect, App tears down Session, resets WireRouter, and
## returns to ConnectionScreen.
##
## ConnectionScreen and any other scene-side code should talk only to App;
## App is the sole reachable global.

extends Node


const CONNECTION_SCREEN_PATH := "res://fj/app/connection_screen.tscn"
const BOARD_SCENE_PATH := "res://fj/board/scenes/board.tscn"


# --- Public lifecycle signals (ConnectionScreen subscribes to these) ---

signal connected
signal disconnected
signal connection_error(err: String)
signal session_started(my_pid: NLEnums.PID)


# --- Internal state ---

var _transport: Transport = null
var _wire_router: WireRouter
var _nexus_router: NexusRouter

var _session: Session = null
var _board: Board = null

var _handshake_done: bool = false
var _my_pid: NLEnums.PID
var _have_my_pid: bool = false

var logger: Logg = Logg.new()


func _ready() -> void:
	_wire_router = WireRouter.new()
	_nexus_router = NexusRouter.new()

	_wire_router.state_received.connect(_nexus_router.push_state)
	_wire_router.prompt_received.connect(_nexus_router.push_prompt)
	_wire_router.notify_received.connect(_nexus_router.push_notify)

	_nexus_router.rl_out.connect(_wire_router.send_response)
	_nexus_router.resign_out.connect(_wire_router.send_resign)
	_nexus_router.draw_offer_out.connect(_wire_router.send_draw_offer)
	_nexus_router.draw_accept_out.connect(_wire_router.send_draw_accept)

	_wire_router.handshake_complete.connect(_on_handshake_complete)
	_wire_router.pid_assigned.connect(_on_pid_assigned)
	_wire_router.session_closed.connect(_on_session_closed)

	add_child(_wire_router)
	add_child(_nexus_router)


# --- Public connect / disconnect API ---

func connect_to(host: String, port: int, transport_type: Transport.Type) -> void:
	disconnect_from_server()

	match transport_type:
		Transport.Type.TCP:
			_transport = TCP.new(host, port)
		Transport.Type.WEBSOCKET:
			_transport = WebSocket.new(host, port)

	# Wire all signals before the Transport enters the tree (and so before
	# `_process` polling can fire). TCP / WebSocket also defer any
	# synchronous-error `error.emit` from their `_init` to the next idle
	# frame, so listeners attached here will see those too.
	_transport.recv.connect(_on_transport_recv)
	_wire_router.wl_out.connect(_on_wire_router_wl_out)
	_transport.connected.connect(_on_transport_connected)
	_transport.disconnected.connect(_on_transport_disconnected)
	_transport.error.connect(_on_transport_error)

	add_child(_transport)


func disconnect_from_server() -> void:
	_teardown_session()
	if _transport:
		# Disconnect the codec wires before the Transport goes away — defensive,
		# in case _transport receives one final packet during free.
		if _transport.recv.is_connected(_on_transport_recv):
			_transport.recv.disconnect(_on_transport_recv)
		if _wire_router.wl_out.is_connected(_on_wire_router_wl_out):
			_wire_router.wl_out.disconnect(_on_wire_router_wl_out)
		if _transport.connected.is_connected(_on_transport_connected):
			_transport.connected.disconnect(_on_transport_connected)
		if _transport.disconnected.is_connected(_on_transport_disconnected):
			_transport.disconnected.disconnect(_on_transport_disconnected)
		if _transport.error.is_connected(_on_transport_error):
			_transport.error.disconnect(_on_transport_error)
		_transport.queue_free()
		_transport = null
	_wire_router.reset()
	_handshake_done = false
	_have_my_pid = false


# --- Codec pipeline ---

func _on_transport_recv(line: String) -> void:
	var parsed: Variant = WireCodec.decode(line)
	var color_prefix:String
	if _have_my_pid:
		if _my_pid == NLEnums.PID.RED: color_prefix = "(RED) "
		else: color_prefix = "(BLUE) "
	else: color_prefix = "(???) "
	if not _have_my_pid or (_have_my_pid and _my_pid == NLEnums.PID.BLUE): logger.write("transport.recv", color_prefix + line)
	if parsed is Dictionary:
		_wire_router.wl_in(parsed)


func _on_wire_router_wl_out(msg: Dictionary) -> void:
	if _transport:
		_transport.send(WireCodec.encode(msg))


# --- Transport lifecycle ---

func _on_transport_connected() -> void:
	connected.emit()


func _on_transport_disconnected() -> void:
	disconnected.emit()
	_teardown_session()
	_wire_router.reset()
	_handshake_done = false
	_have_my_pid = false
	_swap_to_connection_screen()


func _on_transport_error(err: String) -> void:
	connection_error.emit(err)


# --- Handshake choreography ---

func _on_handshake_complete() -> void:
	_handshake_done = true
	_try_bootstrap_session()


func _on_pid_assigned(pid: NLEnums.PID) -> void:
	_my_pid = pid
	_have_my_pid = true
	_try_bootstrap_session()


func _on_session_closed() -> void:
	# Server signaled end-of-session. Tear down and return to ConnectionScreen.
	_teardown_session()
	_wire_router.reset()
	_handshake_done = false
	_have_my_pid = false
	_swap_to_connection_screen()


func _try_bootstrap_session() -> void:
	if not _handshake_done or not _have_my_pid or _session != null:
		return
	_swap_to_board()
	_session = Session.new()
	add_child(_session)
	_session.bootstrap(_my_pid, _nexus_router, _board)
	session_started.emit(_my_pid)


# --- Scene transitions ---

func _swap_to_board() -> void:
	var board_scene: PackedScene = load(BOARD_SCENE_PATH)
	_board = board_scene.instantiate() as Board
	_replace_current_scene(_board)


func _swap_to_connection_screen() -> void:
	var screen_scene: PackedScene = load(CONNECTION_SCREEN_PATH)
	var screen := screen_scene.instantiate()
	_replace_current_scene(screen)


func _replace_current_scene(new_scene: Node) -> void:
	var tree := get_tree()
	var prev := tree.current_scene
	tree.root.add_child(new_scene)
	tree.current_scene = new_scene
	if prev and prev != new_scene:
		prev.queue_free()


# --- Internal teardown ---

func _teardown_session() -> void:
	if _session:
		_session.queue_free()
		_session = null
	# `_board` is freed by `_replace_current_scene` when ConnectionScreen
	# takes its place; we just drop the reference here.
	_board = null
