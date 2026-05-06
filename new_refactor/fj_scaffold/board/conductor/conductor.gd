## Conductor: the bridge from NL to Renderer animation primitives.
##
## Composes Scheduler + Dispatcher + ReadinessTracker + DivergenceMonitor.
## (Dispatcher owns its own SlotWrangler internally — composer doesn't see
## it.) The Conductor takes the Renderer's widget arrays as input and builds
## its internal lookup dicts itself; it knows nothing of Catalog.
##
## Public surface:
##
##   Inbound (composer wires NexusRouter signals to these):
##     push_state(state, events)   — paired SL+DL.
##     push_prompt(prompt)         — PL.
##     push_diffs(events)          — bare DL batch.
##
##   Outbound delegated-event signals (composer wires these to InfoPanel,
##   replay logger, AI observer, …):
##     hp_changed / phase_changed / player_died / game_ended /
##     state_rebuilt / prompt_applied
##
##   Animation-gating hooks (any subscriber that animates in response to a
##   per-event signal claims the queue via these):
##     mark_busy() / mark_free()
##
##   Configuration (composer sets BEFORE add_child(conductor)):
##     slot_views                  — Array[SlotView] from board.find_slot_views()
##     weapon_slot_views           — Array[WeaponSlotView] from board.find_weapon_slot_views()
##     overlay                     — Control parent for in-flight cards
##     card_factory                — Callable() -> CardView

class_name Conductor extends Node


# --- Configuration ---

var slot_views: Array[SlotView] = []
var weapon_slot_views: Array[WeaponSlotView] = []
var overlay: Control = null
var card_factory: Callable


# --- Re-emitted Dispatcher signals ---

signal hp_changed(target: NLEnums.PID, old: int, new: int)
signal phase_changed(phase: NLEnums.Phase)
signal player_died(target: NLEnums.PID)
signal game_ended(outcome: NLEnums.Outcome, won: Dictionary)
signal state_rebuilt(state: State)
signal prompt_applied(prompt: Prompt)


# --- Internal sub-components ---

var _scheduler: Scheduler
var _dispatcher: Dispatcher
var _readiness: ReadinessTracker
var _monitor: DivergenceMonitor


func _ready() -> void:
	_readiness = ReadinessTracker.new()
	_scheduler = Scheduler.new()
	_monitor = DivergenceMonitor.new()

	_dispatcher = Dispatcher.new()
	_dispatcher.slot_views = slot_views
	_dispatcher.weapon_slot_views = weapon_slot_views
	_dispatcher.overlay = overlay
	_dispatcher.card_factory = card_factory
	add_child(_dispatcher)

	# Scheduler ↔ Dispatcher dispatch.
	_scheduler.next_term.connect(_on_next_term)

	# Dispatcher's own animations gate the ReadinessTracker.
	_dispatcher.animation_started.connect(_readiness.mark_busy)
	_dispatcher.animation_finished.connect(_readiness.mark_free)

	# Re-emit Dispatcher's per-event signals as Conductor's own.
	_dispatcher.hp_changed.connect(hp_changed.emit)
	_dispatcher.phase_changed.connect(phase_changed.emit)
	_dispatcher.player_died.connect(player_died.emit)
	_dispatcher.game_ended.connect(game_ended.emit)
	_dispatcher.state_rebuilt.connect(state_rebuilt.emit)
	_dispatcher.prompt_applied.connect(prompt_applied.emit)

	# Scheduler advances when readiness drains.
	_readiness.became_free.connect(_scheduler.notify_idle)


# --- Public push API ---

func push_state(state: State, events: Array[DL]) -> void:
	var result := _monitor.check(state, events)
	if result.initial:
		_scheduler.push(state)
		return
	for ev in events:
		_scheduler.push(ev)
	if result.divergent:
		_scheduler.push(state)


func push_diffs(events: Array[DL]) -> void:
	for ev in events:
		_scheduler.push(ev)


func push_prompt(prompt: Prompt) -> void:
	_scheduler.push(prompt)


# --- Animation-gating hooks (any animated subscriber claims via these) ---

func mark_busy() -> void:
	_readiness.mark_busy()


func mark_free() -> void:
	_readiness.mark_free()


# --- Lifecycle ---

func reset() -> void:
	_monitor.reset()


# --- Internal: term dispatch wrapper ---

## Wraps the Dispatcher's handle so we can advance the Scheduler immediately
## when no animation runs. If an animation is in flight by the time `handle`
## returns synchronously, the ReadinessTracker's eventual `became_free`
## signal will advance the Scheduler instead.
func _on_next_term(term: NL) -> void:
	_dispatcher.handle(term)
	if _readiness.is_free():
		_scheduler.notify_idle()
