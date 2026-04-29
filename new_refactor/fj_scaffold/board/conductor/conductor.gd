## Conductor: the bridge from NL to Renderer animation primitives.
##
## Composes Scheduler + Dispatcher + ReadinessTracker + DivergenceMonitor.
## (Dispatcher owns its own SlotWrangler internally — composer doesn't see it.)
## Each is a self-contained component; Conductor wires them together
## internally and exposes a small public surface to the composer:
##
##   Inbound (composer wires NexusRouter signals to these):
##     push_state(state, events)   — paired SL+DL.
##     push_prompt(prompt)         — PL.
##     push_diffs(events)          — bare DL batch (currently never sent
##                                   by the wire; here for future protocol).
##
##   Configuration (composer sets BEFORE add_child(conductor) so that
##   `_ready` can forward fields to the Dispatcher in turn):
##     slot_for, weapon_slot_for   — Dict[SlotID, …View] from the Renderer.
##     overlay                     — Control parent for in-flight cards.
##     card_factory                — Callable() -> CardView.
##     back_for_slot               — Callable(SlotID) -> Texture2D.

class_name Conductor extends Node


# --- Configuration (composer sets) ---

var slot_for: Dictionary
var weapon_slot_for: Dictionary
var overlay: Control = null
var card_factory: Callable
var back_for_slot: Callable


# --- Internal sub-components ---

var _scheduler: Scheduler
var _dispatcher: Dispatcher
var _readiness: ReadinessTracker
var _monitor: DivergenceMonitor


func _ready() -> void:
	_readiness = ReadinessTracker.new()
	_scheduler = Scheduler.new()
	_monitor = DivergenceMonitor.new()

	# Configure the Dispatcher BEFORE adding it to the tree so that its own
	# `_ready` (which builds its SlotWrangler) sees populated fields.
	_dispatcher = Dispatcher.new()
	_dispatcher.slot_for = slot_for
	_dispatcher.weapon_slot_for = weapon_slot_for
	_dispatcher.overlay = overlay
	_dispatcher.card_factory = card_factory
	_dispatcher.back_for_slot = back_for_slot
	add_child(_dispatcher)

	# Internal wiring.
	_scheduler.next_term.connect(_dispatcher.handle)
	_dispatcher.animation_started.connect(_readiness.mark_busy)
	_dispatcher.animation_finished.connect(_readiness.mark_free)
	_readiness.became_free.connect(_scheduler.notify_idle)


# --- Public push API ---

func push_state(state: State, events: Array[DL]) -> void:
	var result := _monitor.check(state, events)
	if result.initial:
		# First state — single rebuild, no events to play.
		_scheduler.push(state)
		return
	# Normal / divergent: play events, then (if divergent) a rebuild snaps
	# the UI back to the authoritative state.
	for ev in events:
		_scheduler.push(ev)
	if result.divergent:
		_scheduler.push(state)


func push_diffs(events: Array[DL]) -> void:
	for ev in events:
		_scheduler.push(ev)


func push_prompt(prompt: Prompt) -> void:
	_scheduler.push(prompt)


## Called externally on session reset (transport reconnect).
func reset() -> void:
	_monitor.reset()
