## SlotView: abstract base for a container of ordered CardViews.
##
## `_cards` (in concrete subclasses) is the authoritative list — server-driven,
## mutated only via `insert_state` / `remove_state` / `clear_state`. Subclasses
## arrange children visually, but the indexing contract above always speaks in
## protocol order (`_cards[0]` is the top of the pile, per protocol §3.2.1).
##
## **API split — three concerns kept apart:**
## 1. Inspection (sync, pure): `count`, `get_card`, `card_position`.
## 2. State mutation (sync, impure, no animation): `insert_state`, `remove_state`,
##    `clear_state`. These do NOT lay out — positions are unchanged.
## 3. Animation (async, pure — no `_cards` mutation): `relayout()`,
##    `wiggle(amp, dur)`. Both return an `Action` (see `action/action.gd`),
##    composable into Seq/Par trees. Returning `Action` (instead of taking
##    a `Tween` argument) preserves each method's INTERNAL sequencing when
##    embedded in a parallel block — Godot's flat tween model collapses
##    nested sequences inside `set_parallel(true)`, which silently re-times
##    callbacks like `_fix_tree_order`.
## A sync helper `layout()` snaps positions instantly — used by Board's sync
## `populate_slot` (full rebuild) where animated layout would be jarring.
##
## **Renderer-internal naming**: identity-free. The widget doesn't know which
## NL `SlotID` it represents — the composition root maintains the
## `Dict[SlotID, SlotView]` mapping externally. The `@export` fields below
## are scene-init metadata only; the widget's runtime logic doesn't read them.
##
## Signal choreography: when a child CardView fires `clicked`, the SlotView
## emits `card_clicked(self, index)` followed by `slot_clicked(self)`. Empty-
## area clicks emit only `slot_clicked(self)`.

@abstract
class_name SlotView extends Control


signal slot_clicked(slot: SlotView)
signal card_clicked(slot: SlotView, index: int)
signal card_hovered(slot: SlotView, index: int)
signal card_unhovered(slot: SlotView)


## Scene-level identity exports. The SlotView itself doesn't use these for
## any logic — they're metadata the composer reads at scene-init time to
## resolve which Catalog-vended SlotID this widget represents.
##
## `side` is the absolute PID owner (RED/BLUE), ignored by GuardDeck. `kind`
## is the typed slot identity. `num` is the weapon-slot index for ws-interior
## kinds; ignored otherwise.
@export var side: NLEnums.PID = NLEnums.PID.RED
@export var kind: SlotID.Type = SlotID.Type.HAND
@export var num: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_slot_gui_input)


# --- (1) Inspection ---

@abstract func count() -> int
@abstract func get_card(index: int) -> CardView

## Local position (relative to this Control) the i-th card SHOULD occupy
## after layout. Used by Board's animation composites to compute glide
## targets without flying to the slot's center first.
@abstract func card_position(index: int) -> Vector2

## Convenience: where the next-inserted card would land. Default impl is
## `card_position(count())`; subclasses may override if their layout is
## non-trivially count-dependent.
func next_insert_position() -> Vector2:
	return card_position(count())


# --- (2) State mutation (no layout, no animation) ---

## Splice `card` into `_cards` at `index`, reparent into the SlotView, and
## attach signal routing. Caller is responsible for laying out (via `layout`
## or `relayout`) before the user sees the result.
@abstract func insert_state(index: int, card: CardView) -> void

## Splice the card out of `_cards`, detach signal routing, reparent away.
## Returns the card. Caller is responsible for re-laying-out.
@abstract func remove_state(index: int) -> CardView

## Empty `_cards` and `queue_free` every child card. No layout needed
## afterwards (nothing left to lay out).
@abstract func clear_state() -> void

## Sync layout snap: set every card's local position to `card_position(idx)`
## immediately, fix tree order. Use after a `populate_slot`-style full
## rebuild where instant snap-to-truth is correct.
@abstract func layout() -> void


# --- (3) Animation (returns Action) ---

@abstract func _relayout() -> Action # nonlazy action factory

## Animate every child to its natural `card_position(idx)`. Lazy wrapper over _relayout.
func relayout() -> Action:
	return Action.Lazy.new(_relayout)


## Three-step horizontal shake.
@abstract func wiggle(_amplitude_px: float, _duration_s: float) -> Action


# --- Highlights — (2)+(3) bundled, self-contained ---

## Visual prompt decoration. Default no-op; subclasses override. The "(3)"
## animation is a self-running looped tween scoped inside the subclass —
## not gated by the conductor's readiness signals.
@abstract func set_highlight(_level: HighlightLevel.Level) -> void


## Cascade LOWLIGHT to self and every child card. Used by the Dispatcher
## before applying a fresh prompt's highlights.
func reset_highlights() -> void:
	set_highlight(HighlightLevel.Level.LOWLIGHT)
	for i in count():
		get_card(i).set_highlight(HighlightLevel.Level.LOWLIGHT)


# --- Signal choreography (subclass calls these when a card is added/removed) ---

func _attach_card(card: CardView) -> void:
	card.clicked.connect(_on_child_card_clicked.bind(card))
	card.mouse_entered.connect(_on_child_card_hovered.bind(card))
	card.mouse_exited.connect(_on_child_card_unhovered)


## Mirror of `_attach_card`. Must be called from `remove_state()` before the
## card is detached from the slot — otherwise the card retains a connection
## back to this slot's handlers, and a subsequent `_attach_card` on a
## different slot would result in the click firing on both slots.
##
## Not needed for `clear_state()`: `queue_free()` auto-disconnects on free.
func _detach_card(card: CardView) -> void:
	card.clicked.disconnect(_on_child_card_clicked.bind(card))
	card.mouse_entered.disconnect(_on_child_card_hovered.bind(card))
	card.mouse_exited.disconnect(_on_child_card_unhovered)


func _on_child_card_clicked(card: CardView) -> void:
	var idx := _index_of(card)
	if idx < 0:
		return
	# Card-specific signal first; slot_clicked follows for any slot-level
	# listener that would otherwise miss the gesture.
	card_clicked.emit(self, idx)
	slot_clicked.emit(self)


func _on_child_card_hovered(card: CardView) -> void:
	var idx := _index_of(card)
	if idx >= 0:
		card_hovered.emit(self, idx)


func _on_child_card_unhovered() -> void:
	card_unhovered.emit(self)


func _on_slot_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(self)
			accept_event()


func _index_of(card: CardView) -> int:
	for i in count():
		if get_card(i) == card:
			return i
	return -1
