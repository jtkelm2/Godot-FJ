## Conductor: the bridge from NL to Renderer animation primitives.
##
## Composes Scheduler + Dispatcher + ReadinessTracker + DivergenceMonitor.
## The Dispatcher is the only thing that talks to the Board and to
## InfoPanels; the Conductor passes both references through at construction
## time and re-emits per-event signals upward for external observers
## (loggers, tests).
##
## Public surface:
##
##   Inbound (composer wires Session's NL signals to these):
##     push_state(state, events)   — paired SL+DL.
##     push_prompt(prompt)         — PL.
##     push_diffs(events)          — bare DL batch.
##
##   Outbound delegated-event signals (composer wires these to InfoPanel,
##   replay logger, AI observer, …):
##     hp_changed / phase_changed / player_died / game_ended /
##     state_rebuilt / prompt_applied / divergence_detected / handling
##
##   Animation-gating hooks (any subscriber that animates in response to a
##   per-event signal claims the queue via these):
##     mark_busy() / mark_free()
##
##   Configuration (composer sets BEFORE add_child(conductor)):
##     board                       — Board scene root (owns the Renderer's
##                                   animation surface; passed straight to
##                                   the Dispatcher).
##     info_panels                 — Dictionary[PID, InfoPanel] passed straight
##                                   to the Dispatcher; Dispatcher fans state /
##                                   event updates out to every configured
##                                   panel.
##     phase_banner                 — Single PhaseBanner overlaying the play
##                                   area. Optional. Dispatcher orchestrates a
##                                   gated banner animation on PhaseChanged
##                                   when present.
##     role_screen                  — Single RoleScreen overlaying the full
##                                   game window.

class_name Conductor extends Node

# --- Configuration ---

var board: Board = null
var info_panels: Dictionary[NLEnums.PID, InfoPanel] = {}
var phase_banner: PhaseBanner = null
var role_screen: RoleScreen = null
var card_presenter: CardPresenter = null

# --- Internal sub-components ---

var _scheduler: Scheduler
var _dispatcher: Dispatcher
var _readiness: ReadinessTracker
var _monitor: DivergenceMonitor


func _ready() -> void:
	assert(board != null, "Conductor: composer must set `board` before add_child")

	_readiness = ReadinessTracker.new()
	_scheduler = Scheduler.new()
	_monitor = DivergenceMonitor.new()

	_dispatcher = Dispatcher.new()
	_dispatcher.board = board
	_dispatcher.info_panels = info_panels
	_dispatcher.phase_banner = phase_banner
	_dispatcher.role_screen = role_screen
	_dispatcher.card_presenter = card_presenter
	add_child(_dispatcher)

	# Scheduler ↔ Dispatcher dispatch.
	_scheduler.next_term.connect(_on_next_term)

	# Dispatcher's own animations gate the ReadinessTracker.
	_dispatcher.animation_started.connect(_readiness.mark_busy)
	_dispatcher.animation_finished.connect(_readiness.mark_free)

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
		App.logger.write("conductor.divergence", "\n" + result.format_report(events))
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
