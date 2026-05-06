## Transport: abstract bytes-over-socket. Frames inbound bytes on `\n` via the
## inner `Buffer` helper; emits one `recv(line)` per complete line. Outbound
## is `send(line)` — implementations append the framing newline themselves.
##
## Concrete implementations: `TCP`, `WebSocket`. Each takes `(host, port)` in
## its `_init` constructor and starts connecting immediately. The composition
## root then connects `recv` / `connected` / `disconnected` / `error` signals
## to consumers.

@abstract
class_name Transport extends Node


## Selector for which concrete Transport to instantiate. App's
## `connect_to(host, port, type)` matches on this; ConnectionScreen lists
## the values in its dropdown.
enum Type { TCP, WEBSOCKET }


@warning_ignore_start("unused_signal")
signal error(msg: String)
signal connected
signal disconnected
signal recv(msg: String)
@warning_ignore_restore("unused_signal")


@abstract func send(msg: String) -> void


## Line-buffer helper. Implementations feed raw byte strings via `put`;
## the buffer splits on `\n` and emits `recv(line)` per complete line.
class Buffer:
	signal recv(msg: String)

	var _buffer: String = ""

	func put(string: String) -> void:
		_buffer += string
		_process_buffer()

	func _process_buffer() -> void:
		while true:
			var newline_pos := _buffer.find("\n")
			if newline_pos == -1:
				break
			var msg := _buffer.substr(0, newline_pos).strip_edges()
			_buffer = _buffer.substr(newline_pos + 1)
			recv.emit(msg)
