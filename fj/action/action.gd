@abstract class_name Action extends RefCounted

## A composable, deferred unit of work. `fire()` starts the work non-blocking
## and the Action emits exactly one terminal signal — `finished` on natural
## completion or `cancelled` if `cancel()` is called before completion.
## `run()` awaits either, so `await action.run()` always resolves.
##
## Composition: Seq/Par/Lazy forward a child's terminal signal as their own —
## a `cancelled` child propagates up the tree rather than being treated as
## advancement. To stop a composite mid-flight, call `cancel()` on it; the
## current/unfinished children are cancelled in turn.

signal finished
signal cancelled
signal _delayed_finish


var _terminated: bool = false


@abstract func fire() -> void


## Stops in-flight work and emits `cancelled` exactly once. No-op if the
## action has already terminated (finished or cancelled). Subclasses override
## `_on_cancel` to stop their specific work; the base handles the flag and
## signal so subclass overrides don't need to.
func cancel() -> void:
	if _terminated: return
	_terminated = true
	_on_cancel()
	cancelled.emit()


## Subclass hook: stop any in-flight work. Default no-op — Sync has nothing
## async to stop, and composites override this to cascade to children.
func _on_cancel() -> void:
	pass


## Subclass helper: emit `finished` exactly once. No-op if already terminated.
## Subclasses MUST emit completion via this rather than `finished.emit()`
## directly, so a cancel that races with natural completion can't double-emit.
func _emit_finished() -> void:
	if _terminated: return
	_terminated = true
	finished.emit()


## Blocking variant; awaits either `finished` or `cancelled`. Always resolves
## at least one frame after fire() — the terminal signal is forwarded via
## CONNECT_DEFERRED so callers can rely on a yield point.
func run() -> void:
	finished.connect(_delayed_finish.emit, ConnectFlags.CONNECT_DEFERRED | ConnectFlags.CONNECT_ONE_SHOT)
	cancelled.connect(_delayed_finish.emit, ConnectFlags.CONNECT_DEFERRED | ConnectFlags.CONNECT_ONE_SHOT)
	fire()
	await _delayed_finish


## Trivial Action that does nothing and finishes immediately. Useful as the
## return value of a no-op codepath or as a placeholder in a Seq/Par.
static func noop() -> Action:
	return Seq.new([])


class Seq extends Action:
	var _children: Array[Action]
	var _current_idx: int = -1

	func _init(children: Array[Action]) -> void:
		_children = children

	func _fire_child(idx: int) -> void:
		if _terminated: return
		if idx >= _children.size():
			_emit_finished()
			return
		_current_idx = idx
		var child := _children[idx]
		child.finished.connect(_fire_child.bind(idx + 1), ConnectFlags.CONNECT_ONE_SHOT)
		child.cancelled.connect(_on_child_cancelled, ConnectFlags.CONNECT_ONE_SHOT)
		child.fire()

	func _on_child_cancelled() -> void:
		if _terminated: return
		_terminated = true
		cancelled.emit()

	func fire() -> void:
		_fire_child(0)

	func _on_cancel() -> void:
		if _current_idx >= 0 and _current_idx < _children.size():
			_children[_current_idx].cancel()


class Par extends Action:
	var _children: Array[Action]
	var _completed: int = 0

	func _init(children: Array[Action]) -> void:
		_children = children

	func _on_child_finished() -> void:
		if _terminated: return
		_completed += 1
		if _completed == _children.size():
			_emit_finished()

	func _on_child_cancelled() -> void:
		if _terminated: return
		_terminated = true
		for child in _children:
			if not child._terminated:
				child.cancel()
		cancelled.emit()

	func fire() -> void:
		if _children.is_empty():
			_emit_finished()
			return
		for child in _children:
			child.finished.connect(_on_child_finished, ConnectFlags.CONNECT_ONE_SHOT)
			child.cancelled.connect(_on_child_cancelled, ConnectFlags.CONNECT_ONE_SHOT)
			child.fire()

	func _on_cancel() -> void:
		for child in _children:
			if not child._terminated:
				child.cancel()


class Twact extends Action:
	var tweenFactory: Callable
	var _tween: Tween

	func _init(_tweenFactory: Callable) -> void:
		tweenFactory = _tweenFactory

	func fire() -> void:
		if _terminated: return
		_tween = tweenFactory.call() as Tween
		_tween.finished.connect(_emit_finished, ConnectFlags.CONNECT_ONE_SHOT)

	func _on_cancel() -> void:
		if _tween != null and _tween.is_valid():
			_tween.kill()


## Synchronous, instantaneous Action: invokes a no-arg callable, then
## immediately emits `finished`. Useful for sync mutations interleaved
## with async Twacts inside a Seq (reparent calls, state mutations,
## visibility flips). Inside Seq.fire() / Par.fire() the synchronous emit
## is fine — the parent's signal connection is set BEFORE child.fire() is
## called, and Action.run() always defers the top-level finish for at
## least one frame.
class Sync extends Action:
	var _f: Callable

	func _init(f: Callable) -> void:
		_f = f

	func fire() -> void:
		if _terminated: return
		_f.call()
		_emit_finished()


## Time-based delay. Completes after `duration` seconds via SceneTreeTimer.
## `cancel()` sets `_terminated`; the late timeout fires `_emit_finished`
## which the guard makes a no-op. SceneTreeTimer can't be killed, but the
## Callable it holds keeps this Action alive until it fires regardless, so
## a cancelled Wait is GC'd shortly after its duration elapses.
class Wait extends Action:
	var _duration: float

	func _init(duration: float) -> void:
		_duration = duration

	func fire() -> void:
		if _terminated: return
		var tree := Engine.get_main_loop() as SceneTree
		tree.create_timer(_duration).timeout.connect(_emit_finished, ConnectFlags.CONNECT_ONE_SHOT)


## Signal-based wait. Completes when `signal_` next emits. `cancel()`
## disconnects the listener (no leaked connections). Connection is set in
## `fire()`, not `_init()` — emissions that happen before the OnSignal is
## fired are not retroactively counted.
class OnSignal extends Action:
	var _signal: Signal
	var _callable: Callable

	func _init(signal_: Signal) -> void:
		_signal = signal_

	func fire() -> void:
		if _terminated: return
		_callable = _emit_finished
		_signal.connect(_callable, ConnectFlags.CONNECT_ONE_SHOT)

	func _on_cancel() -> void:
		if _callable.is_valid() and _signal.is_connected(_callable):
			_signal.disconnect(_callable)


## Defers Action construction until fire() time. Wraps a callable that
## returns an Action; when this Lazy fires, the callable is invoked, its
## returned Action's terminal signal is forwarded to ours, and the inner
## Action fires. Use when the inner Action's shape depends on state mutated
## by an earlier sibling in a Seq (e.g., `Lazy.new(slot.relayout)` after a
## `Sync` that removed a card from `slot`).
##
## **`_inner` MUST be a member field, not a local.** Signal connections do
## NOT retain the signal's owner — without a strong reference, the inner
## Action (and everything it holds: nested Pars/Seqs/Twacts) gets
## garbage-collected the moment `fire()` returns, even though tweens it
## scheduled are still running. Twact's `tween.finished → twact.finished.emit`
## connection then points at a freed Twact and silently no-ops when the
## tween eventually fires.
class Lazy extends Action:
	var _f: Callable    # () -> Action
	var _inner: Action

	func _init(f: Callable) -> void:
		_f = f

	func fire() -> void:
		if _terminated: return
		_inner = _f.call()
		_inner.finished.connect(_emit_finished, ConnectFlags.CONNECT_ONE_SHOT)
		_inner.cancelled.connect(_on_inner_cancelled, ConnectFlags.CONNECT_ONE_SHOT)
		_inner.fire()

	func _on_inner_cancelled() -> void:
		if _terminated: return
		_terminated = true
		cancelled.emit()

	func _on_cancel() -> void:
		if _inner != null:
			_inner.cancel()
