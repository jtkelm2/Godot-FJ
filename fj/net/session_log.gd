extends RefCounted

## Session event log, written incrementally. The file is opened on
## construction, every entry is appended and flushed immediately, and the
## handle is closed when save_to_file() is called (at session end) or when
## this RefCounted is freed.
##
## Flushing after every line means a crash loses at most the in-flight
## event, not the whole session.

var _start_time: int
var _file: FileAccess
var _path: String


func _init() -> void:
	_start_time = Time.get_ticks_msec()
	var datetime := Time.get_datetime_string_from_system().replace(":", "-")
	_path = "user://session_%s.log" % datetime
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("SessionLog: failed to open %s: %s" % [_path, error_string(FileAccess.get_open_error())])


func log_received(msg: Dictionary) -> void:
	_write({
		"dir": "recv",
		"time": _elapsed(),
		"msg": msg,
	})


func log_sent(msg: Dictionary) -> void:
	_write({
		"dir": "sent",
		"time": _elapsed(),
		"msg": msg,
	})


func log_event(event: String, detail: Variant = null) -> void:
	var entry := {
		"dir": "client",
		"time": _elapsed(),
		"event": event,
	}
	if detail != null:
		entry["detail"] = detail
	_write(entry)


## Close the log file and return its absolute path. Called at session end.
## Argument kept for backward compatibility; the path was fixed at _init.
func save_to_file(_ignored: String = "") -> String:
	if _file:
		_file.flush()
		_file.close()
		_file = null
	var abs_path := ProjectSettings.globalize_path(_path)
	print("SessionLog: closed %s" % abs_path)
	return abs_path


func _write(entry: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(entry))
	_file.flush()


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _start_time) / 1000.0
