## Scheduler: NL-term queue with readiness gating.
##
## Inbound: `push(term)` accepts NL terms (DL events, State, Prompt) in
## arrival order. The Conductor calls this to enqueue.
##
## Outbound: `next_term(term)` fires when a term is ready to be processed.
## The Conductor wires this to `Dispatcher.handle`. After Dispatcher signals
## `animation_finished` (via the ReadinessTracker), the Conductor calls
## `notify_idle()` and the Scheduler emits the next term.
##
## Wire-agnostic. Knows nothing about Dispatcher / ReadinessTracker / NL
## variants — it just queues opaque terms and gates emission.

class_name Scheduler extends RefCounted


signal next_term(term: NL)


var _queue: Array[NL] = []
var _idle: bool = true


func push(term: NL) -> void:
	_queue.append(term)
	_try_emit()


## Called externally when the StepHandler finishes processing one term.
func notify_idle() -> void:
	_idle = true
	_try_emit()


func _try_emit() -> void:
	if not _idle or _queue.is_empty():
		return
	_idle = false
	# Defer to break re-entrance: a Dispatcher that finishes synchronously
	# would otherwise call notify_idle within next_term, recursively unrolling
	# the queue on the same stack frame.
	_emit_next.call_deferred(_queue.pop_front())


func _emit_next(term: NL) -> void:
	next_term.emit(term)
