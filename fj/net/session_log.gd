extends RefCounted

var entries: Array[Dictionary] = []
var _start_time: int


func _init() -> void:
	_start_time = Time.get_ticks_msec()


func log_received(msg: Dictionary) -> void:
	entries.append({
		"dir": "recv",
		"time": _elapsed(),
		"msg": msg,
	})


func log_sent(msg: Dictionary) -> void:
	entries.append({
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
	entries.append(entry)


func save_to_file(path: String = "") -> String:
	if path.is_empty():
		var datetime := Time.get_datetime_string_from_system().replace(":", "-")
		path = "user://session_%s.log" % datetime

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SessionLog: failed to open %s for writing" % path)
		return ""

	for entry in entries:
		file.store_line(JSON.stringify(entry))
	file.close()

	var abs_path := ProjectSettings.globalize_path(path)
	print("SessionLog: saved %d entries to %s" % [entries.size(), abs_path])
	return abs_path


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _start_time) / 1000.0
