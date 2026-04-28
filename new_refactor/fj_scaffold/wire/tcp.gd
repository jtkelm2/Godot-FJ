## TCP Transport implementation.

class_name TCP extends Transport


var _peer: StreamPeerTCP
var _buffer: Buffer
var _connected: bool
var _connecting: bool


func _init(host: String, port: int) -> void:
	_buffer = Buffer.new()
	_buffer.recv.connect(recv.emit)

	_connected = false
	_connecting = false

	_peer = StreamPeerTCP.new()

	var err := _peer.connect_to_host(host, port)
	if err != OK:
		error.emit("TCP connect failed: %s" % error_string(err))
		_peer = null
		return

	_connecting = true


func send(msg: String) -> void:
	if not _peer:
		push_error("TCP peer not initialized")
		return
	var data := (msg + "\n").to_utf8_buffer()
	_peer.put_data(data)


func _process(_delta: float) -> void:
	if not _peer:
		return
	_peer.poll()

	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			pass
		StreamPeerTCP.STATUS_CONNECTED:
			if _connecting:
				_connecting = false
				_connected = true
				_peer.set_no_delay(true)
				connected.emit()
			_read_tcp()
		StreamPeerTCP.STATUS_ERROR:
			if _connecting:
				_connecting = false
				_peer = null
				error.emit("TCP connection failed")
			elif _connected:
				_connected = false
				_peer = null
				disconnected.emit()
		StreamPeerTCP.STATUS_NONE:
			if _connected:
				_connected = false
				_peer = null
				disconnected.emit()


func _read_tcp() -> void:
	var available := _peer.get_available_bytes()
	if available <= 0:
		return

	var result := _peer.get_data(available)
	var error_code: int = result[0]
	var data: PackedByteArray = result[1]

	if error_code != OK:
		push_error("TCP read error: %s" % error_string(error_code))
		return

	_buffer.put(data.get_string_from_utf8())
