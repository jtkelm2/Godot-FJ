extends Node

enum TransportType { TCP, WEBSOCKET }

signal message_received(msg: Dictionary)
signal connected
signal disconnected
signal connection_error(err: String)

var _transport_type: TransportType = TransportType.TCP
var _tcp_peer: StreamPeerTCP
var _ws_peer: WebSocketPeer
var _buffer: String = ""
var _is_connected: bool = false
var _connecting: bool = false


func connect_to_server(host: String, port: int, transport: TransportType = TransportType.TCP) -> void:
	disconnect_from_server()
	_transport_type = transport

	match transport:
		TransportType.TCP:
			_connect_tcp(host, port)
		TransportType.WEBSOCKET:
			_connect_websocket(host, port)


func disconnect_from_server() -> void:
	_buffer = ""
	_connecting = false

	if _tcp_peer:
		_tcp_peer.disconnect_from_host()
		_tcp_peer = null

	if _ws_peer:
		_ws_peer.close()
		_ws_peer = null

	if _is_connected:
		_is_connected = false
		disconnected.emit()


func send_message(msg: Dictionary) -> void:
	var json_str := _stringify(msg) + "\n"
	var data := json_str.to_utf8_buffer()

	match _transport_type:
		TransportType.TCP:
			if _tcp_peer and _is_connected:
				_tcp_peer.put_data(data)
		TransportType.WEBSOCKET:
			if _ws_peer and _is_connected:
				_ws_peer.send_text(json_str)


## Variant-typed JSON serializer. `JSON.stringify` emits every numeric value
## as a float (e.g. `0` → `"0.0"`), which breaks the protocol's exact-echo
## rule for response options (§4.4). This walker emits ints as ints and only
## emits the `.0…` form when a value genuinely isn't whole.
static func _stringify(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and abs(f) < 1e16 and f == floor(f):
				return str(int(f))
			return String.num(f)
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(value)
		TYPE_DICTIONARY:
			var parts: PackedStringArray = []
			for k in (value as Dictionary):
				parts.append(JSON.stringify(str(k)) + ":" + _stringify(value[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for v in (value as Array):
				parts.append(_stringify(v))
			return "[" + ",".join(parts) + "]"
		_:
			return JSON.stringify(value)


func _process(_delta: float) -> void:
	match _transport_type:
		TransportType.TCP:
			_poll_tcp()
		TransportType.WEBSOCKET:
			_poll_websocket()


# --- TCP ---

func _connect_tcp(host: String, port: int) -> void:
	_tcp_peer = StreamPeerTCP.new()
	var err := _tcp_peer.connect_to_host(host, port)
	if err != OK:
		connection_error.emit("TCP connect failed: %s" % error_string(err))
		_tcp_peer = null
		return
	_connecting = true


func _poll_tcp() -> void:
	if _tcp_peer == null:
		return

	_tcp_peer.poll()
	var status := _tcp_peer.get_status()

	match status:
		StreamPeerTCP.STATUS_CONNECTING:
			pass
		StreamPeerTCP.STATUS_CONNECTED:
			if _connecting:
				_connecting = false
				_is_connected = true
				_tcp_peer.set_no_delay(true)
				connected.emit()
			_read_tcp()
		StreamPeerTCP.STATUS_ERROR:
			if _connecting:
				_connecting = false
				connection_error.emit("TCP connection failed")
				_tcp_peer = null
			elif _is_connected:
				_is_connected = false
				_tcp_peer = null
				disconnected.emit()
		StreamPeerTCP.STATUS_NONE:
			if _is_connected:
				_is_connected = false
				_tcp_peer = null
				disconnected.emit()


func _read_tcp() -> void:
	var available := _tcp_peer.get_available_bytes()
	if available <= 0:
		return

	var result := _tcp_peer.get_data(available)
	var error_code: int = result[0]
	var data: PackedByteArray = result[1]

	if error_code != OK:
		push_error("TCP read error: %s" % error_string(error_code))
		return

	_buffer += data.get_string_from_utf8()
	_process_buffer()


# --- WebSocket ---

func _connect_websocket(host: String, port: int) -> void:
	_ws_peer = WebSocketPeer.new()
	var url := "ws://%s:%d" % [host, port]
	var err := _ws_peer.connect_to_url(url)
	if err != OK:
		connection_error.emit("WebSocket connect failed: %s" % error_string(err))
		_ws_peer = null
		return
	_connecting = true


func _poll_websocket() -> void:
	if _ws_peer == null:
		return

	_ws_peer.poll()
	var state := _ws_peer.get_ready_state()

	match state:
		WebSocketPeer.STATE_CONNECTING:
			pass
		WebSocketPeer.STATE_OPEN:
			if _connecting:
				_connecting = false
				_is_connected = true
				connected.emit()
			_read_websocket()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if _connecting:
				_connecting = false
				connection_error.emit("WebSocket connection failed (code %d)" % _ws_peer.get_close_code())
				_ws_peer = null
			elif _is_connected:
				_is_connected = false
				_ws_peer = null
				disconnected.emit()


func _read_websocket() -> void:
	while _ws_peer.get_available_packet_count() > 0:
		var packet := _ws_peer.get_packet()
		_buffer += packet.get_string_from_utf8()
	_process_buffer()


# --- Shared ---

func _process_buffer() -> void:
	while true:
		var newline_pos := _buffer.find("\n")
		if newline_pos == -1:
			break

		var line := _buffer.substr(0, newline_pos).strip_edges()
		_buffer = _buffer.substr(newline_pos + 1)

		if line.is_empty():
			continue

		var json := JSON.new()
		var err := json.parse(line)
		if err != OK:
			push_error("JSON parse error: %s (line: %s)" % [json.get_error_message(), line])
			continue

		var msg: Dictionary = json.data
		message_received.emit(msg)
