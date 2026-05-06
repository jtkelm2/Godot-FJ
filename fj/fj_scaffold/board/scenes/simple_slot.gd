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

class_name SimpleSlotView extends SlotView


@export var offset: Vector2 = Vector2(0, -4)

## Cap on how many cards are visually rendered. `count()` still reports the
## full logical count (driven by NL traffic), so prompt indices remain valid
## for the hidden remainder. 0 = no cap.
@export var max_display: int = 0


const HIGHLIGHT_TWEEN_DURATION := 0.5
const HIGHLIGHT_INITIAL_SCALE := Vector2(1.05, 1.05)


@onready var _highlight: Panel = $SlotHighlight
@onready var _overflow_badge: Label = $OverflowBadge
@onready var _context_arrow: Node2D = $ContextArrow


var _cards: Array[CardView] = []
var _highlight_tween: Tween = null


func count() -> int:
	return _cards.size()


func get_card(index: int) -> CardView:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index]


func insert(index: int, card: CardView) -> void:
	_cards.insert(index, card)
	add_child(card)
	_attach_card(card)
	_relayout()


func remove(index: int) -> CardView:
	if index < 0 or index >= _cards.size():
		return null
	var card := _cards[index]
	_detach_card(card)
	_cards.remove_at(index)
	remove_child(card)
	_relayout()
	return card


func clear() -> void:
	for card in _cards:
		remove_child(card)
		card.queue_free()
	_cards.clear()


func set_highlight(level: HighlightLevel.Level) -> void:
	_set_pulse_outline(level == HighlightLevel.Level.HIGHLIGHT)
	_set_context_arrow(level == HighlightLevel.Level.CONTEXT)


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


func _relayout() -> void:
	var n := _cards.size()
	var visible_n := n if max_display <= 0 else mini(n, max_display)
	for i in n:
		var card := _cards[i]
		if i < visible_n:
			card.visible = true
			card.position = offset * i
		else:
			card.visible = false

	# Reorder the tree so card[0] ends up as the last sibling. Godot routes
	# mouse input by tree-sibling order (last child gets input first).
	# Iterating high-to-low and moving each to the end produces final tree
	# order [card[n-1], ..., card[0]] — card[0] last.
	for i in range(n - 1, -1, -1):
		move_child(_cards[i], -1)

	if max_display > 0 and n > max_display:
		_overflow_badge.text = "+%d" % (n - max_display)
		_overflow_badge.visible = true
	else:
		_overflow_badge.visible = false
