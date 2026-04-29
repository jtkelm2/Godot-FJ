## ReadinessTracker: a busy/free counter the Scheduler consults to decide
## whether the StepHandler can accept the next NL term.
##
## Composition: anything that initiates a non-instant operation (animation,
## divergence reconciliation, …) calls `mark_busy()`; the matching completion
## calls `mark_free()`. When the count returns to zero, `became_free` fires.
##
## Tracker is wire-agnostic. It doesn't know what's being tracked — just
## counts.

class_name ReadinessTracker extends RefCounted


signal became_free


var _busy_count: int = 0


func is_free() -> bool:
	return _busy_count == 0


func mark_busy() -> void:
	_busy_count += 1


func mark_free() -> void:
	_busy_count -= 1
	if _busy_count <= 0:
		_busy_count = 0
		became_free.emit()
