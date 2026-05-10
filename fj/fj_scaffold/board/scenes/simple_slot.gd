## SimpleSlotView: lays cards out in a single pile with a configurable
## per-card offset.
##
##   offset = (0, 0)        — perfect stack (deck, discard).
##   offset = small Vector2 — fan / pile effect.
##   offset = larger        — hand spread.
##
## Tree-order convention: `_cards[0]` (protocol's top-of-pile) is the LAST
## sibling in the scene tree. Godot routes mouse input to the last sibling
## first AND draws it last, so card[0] is the visual top AND receives input
## first. Backdrop nodes (Art, SlotHighlight) sit earlier in the tree; the
## SlotHighlight uses `z_index=1000` (set in the .tscn) to render above cards
## regardless of tree position.
##
## API: see `slot_view.gd`. `*_state` methods mutate without animating;
## `layout()` snaps positions; `relayout()` returns an Action that
## animates positions.

class_name SimpleSlotView extends SlotView


@export var offset: Vector2 = Vector2(0, -4)

## Cap on how many cards are visually rendered. `count()` still reports the
## full logical count (driven by NL traffic), so prompt indices remain valid
## for the hidden remainder. 0 = no cap.
@export var max_display: int = 0


const HIGHLIGHT_TWEEN_DURATION := 0.5
const HIGHLIGHT_INITIAL_SCALE := Vector2(1.05, 1.05)
const RELAYOUT_DURATION := 0.18


@onready var _highlight: Panel = $SlotHighlight
@onready var _overflow_badge: Label = $OverflowBadge
@onready var _context_arrow: Node2D = $ContextArrow


var _cards: Array[CardView] = []
var _highlight_tween: Tween = null


# --- (1) Inspection ---

func count() -> int:
	return _cards.size()


func get_card(index: int) -> CardView:
	assert(0 <= index and index < _cards.size(), "SimpleSlotView: get_card(%d) beyond bounds" % index)
	return _cards[index]


func card_position(index: int) -> Vector2:
	return offset * index


# --- (2) State mutation (no layout) ---

func insert_state(index: int, card: CardView) -> void:
	_cards.insert(index, card)
	add_child(card)
	_attach_card(card)


func remove_state(index: int) -> CardView:
	assert(0 <= index and index < _cards.size(), "SimpleSlotView: remove_state(%d) on slot with %d cards" % [index, count()])
	var card := _cards[index]
	_detach_card(card)
	_cards.remove_at(index)
	remove_child(card)
	return card


func clear_state() -> void:
	for card in _cards:
		remove_child(card)
		card.queue_free()
	_cards.clear()


func layout() -> void:
	_apply_visibility()
	for i in _cards.size():
		_cards[i].position = card_position(i)
	_fix_tree_order()
	_update_overflow_badge()


# --- (3) Animation (returns Action) ---

## Sync fix_tree_order, then sync apply_visibility, then a Par of per-card
## position Twacts (only for cards that will be visible after
## apply_visibility), then sync update_overflow_badge. The Action's nested
## structure preserves the (tree-fix → visibility → positions → badge)
## ordering even when this Action is embedded in an outer Par.
func _relayout() -> Action:
	var n := _cards.size()
	var visible_n := n if max_display <= 0 else mini(n, max_display)

	var moves: Array[Action] = []
	for i in visible_n:
		var card := _cards[i]
		var target := card_position(i)
		var slot = self
		moves.append(Action.Twact.new(func() -> Tween:
			var t := slot.create_tween()
			t.tween_property(card, "position", target, RELAYOUT_DURATION) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			return t))

	return Action.Seq.new([
		Action.Sync.new(_fix_tree_order),
		Action.Sync.new(_apply_visibility),
		Action.Par.new(moves),
		Action.Sync.new(_update_overflow_badge),
	])


## Three-step horizontal shake. Each step is its own Twact; the Seq strings
## them in order. `origin` is captured at construction time — if the slot
## moves between construction and fire, the shake terminates at the
## captured origin rather than the slot's then-current position.
func wiggle(amplitude_px: float, duration_s: float) -> Action:
	var origin := position
	var slot := self
	return Action.Seq.new([
		Action.Twact.new(func() -> Tween:
			var t := create_tween()
			t.tween_property(slot, "position", origin + Vector2(amplitude_px, 0), duration_s * 0.25)
			return t),
		Action.Twact.new(func() -> Tween:
			var t := create_tween()
			t.tween_property(slot, "position", origin + Vector2(-amplitude_px, 0), duration_s * 0.5)
			return t),
		Action.Twact.new(func() -> Tween:
			var t := create_tween()
			t.tween_property(slot, "position", origin, duration_s * 0.25)
			return t),
	])


# --- Highlights ---

func set_highlight(level: HighlightLevel.Level) -> void:
	_set_pulse_outline(level == HighlightLevel.Level.HIGHLIGHT)
	_set_context_arrow(level == HighlightLevel.Level.CONTEXT)


# --- Internals ---

func _set_pulse_outline(on: bool) -> void:
	if _highlight_tween and _highlight_tween.is_valid():
		_highlight_tween.kill()
	if on:
		_highlight.visible = true
		_highlight.pivot_offset = _highlight.size * 0.5
		_highlight.scale = HIGHLIGHT_INITIAL_SCALE
		_highlight_tween = create_tween().set_loops()
		_highlight_tween.tween_property(_highlight, "scale", Vector2.ONE, HIGHLIGHT_TWEEN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_highlight_tween.tween_property(_highlight, "scale", HIGHLIGHT_INITIAL_SCALE, HIGHLIGHT_TWEEN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_highlight.visible = false


func _set_context_arrow(on: bool) -> void:
	_context_arrow.visible = on


## Toggle each card's `visible` based on `max_display`. Called by both
## `layout()` (sync) and `relayout(tween)` (async, via tween_callback at
## the start of the tween) so newly visible cards have a defined position
## before any motion starts.
func _apply_visibility() -> void:
	var n := _cards.size()
	var visible_n := n if max_display <= 0 else mini(n, max_display)
	for i in n:
		_cards[i].visible = i < visible_n


## Reorder children so `_cards[0]` ends up as the last sibling. Godot routes
## mouse input by tree-sibling order (last child gets input first).
## Iterating high-to-low and moving each to the end produces final tree
## order [card[n-1], ..., card[0]] — card[0] last.
func _fix_tree_order() -> void:
	for i in range(_cards.size() - 1, -1, -1):
		move_child(_cards[i], -1)


func _update_overflow_badge() -> void:
	var n := _cards.size()
	if max_display > 0 and n > max_display:
		_overflow_badge.text = "+%d" % (n - max_display)
		_overflow_badge.visible = true
	else:
		_overflow_badge.visible = false
