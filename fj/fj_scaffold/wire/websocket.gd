## WebSocket Transport implementation. Mirrors `TCP` structurally but uses
## `WebSocketPeer` and a `ws://host:port` URL instead of a TCP host/port pair.

class_name WebSocket extends Transport


var _peer: WebSocketPeer
var _buffer: Buffer
var _connected: bool
var _connecting: bool


func _init(host: String, port: int) -> void:
	_buffer = Buffer.new()
	_buffer.recv.connect(recv.emit)

	_connected = false
	_connecting = false

	_peer = WebSocketPeer.new()
	var url := "ws://%s:%d" % [host, port]

	var err := _peer.connect_to_url(url)
	if err != OK:
		# Caller hasn't had a chance to attach `error` listeners yet (we're
		# still inside `_init`). Defer the emit to the next idle frame so
		# subscribers wired right after `.new()` see it.
		error.emit.call_deferred("WebSocket connect failed: %s" % error_string(err))
		_peer = null
		return

	_connecting = true


func send(msg: String) -> void:
	if not _peer:
		push_error("WebSocket peer not initialized")
		return
	_peer.send_text(msg + "\n")


func _process(_delta: float) -> void:
	if not _peer:
		return
	_peer.poll()

	match _peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			pass
		WebSocketPeer.STATE_OPEN:
			if _connecting:
				_connecting = false
				_connected = true
				connected.emit()
			_read_ws()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if _connecting:
				_connecting = false
				var code := _peer.get_close_code()
				_peer = null
				error.emit("WebSocket connection failed (code %d)" % code)
			elif _connected:
				_connected = false
				_peer = null
				disconnected.emit()


func _read_ws() -> void:
	while _peer.get_available_packet_count() > 0:
		var packet := _peer.get_packet()
		_buffer.put(packet.get_string_from_utf8())
