@abstract class_name Action extends RefCounted

signal finished # emits as soon as completed, which may be synchronous; await should be used on run()
signal _delayed_finish

@abstract func fire() -> void # non-blocking
func run() -> void: # blocking, for at least one frame
	finished.connect(_delayed_finish.emit, ConnectFlags.CONNECT_DEFERRED | ConnectFlags.CONNECT_ONE_SHOT)
	fire()
	await _delayed_finish


## Trivial Action that does nothing and finishes immediately. Useful as the
## return value of a no-op codepath or as a placeholder in a Seq/Par.
static func noop() -> Action:
	return Seq.new([])


class Seq extends Action:
	var _children:Array[Action]
	
	func _init(children:Array[Action]):
		_children = children
	
	func _fire_child(idx:int):
		if idx >= _children.size():
			finished.emit()
			return
		var child = _children[idx]
		child.finished.connect(_fire_child.bind(idx+1), ConnectFlags.CONNECT_ONE_SHOT)
		child.fire()
	
	func fire(): _fire_child(0)

class Par extends Action:
	var _children:Array[Action]
	var _completed:int
	
	func _init(children:Array[Action]):
		_children = children
		_completed = 0
	
	func _increment_completed() -> void:
		_completed = _completed + 1
		if _completed == _children.size(): finished.emit()
	
	func fire():
		if _children.is_empty(): finished.emit()
		for child in _children:
			child.finished.connect(_increment_completed, ConnectFlags.CONNECT_ONE_SHOT)
			child.fire()

class Twact extends Action:
	var tweenFactory:Callable

	func _init(_tweenFactory:Callable):
		tweenFactory = _tweenFactory

	func fire():
		(tweenFactory.call() as Tween).finished.connect(finished.emit, ConnectFlags.CONNECT_ONE_SHOT)


## Synchronous, instantaneous Action: invokes a no-arg callable, then
## immediately emits `finished`. Useful for sync mutations interleaved
## with async Twacts inside a Seq (reparent calls, state mutations,
## visibility flips). Inside Seq.fire() / Par.fire() the synchronous emit
## is fine — the parent's signal connection is set BEFORE child.fire() is
## called, and Action.run() always defers the top-level finish for at
## least one frame.
class Sync extends Action:
	var _f: Callable

	func _init(f: Callable):
		_f = f

	func fire():
		_f.call()
		finished.emit()


## Defers Action construction until fire() time. Wraps a callable that
## returns an Action; when this Lazy fires, the callable is invoked, its
## returned Action's `finished` is forwarded to ours, and the inner Action
## fires. Use when the inner Action's shape depends on state mutated by an
## earlier sibling in a Seq (e.g., `Lazy.new(slot.relayout)` after a
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

	func _init(f: Callable):
		_f = f

	func fire():
		_inner = _f.call()
		_inner.finished.connect(finished.emit, ConnectFlags.CONNECT_ONE_SHOT)
		_inner.fire()
