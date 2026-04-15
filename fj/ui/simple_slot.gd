class_name SimpleSlot
extends Slot

## A slot that lays out its cards in a single pile with a configurable
## per-card offset. Offset = (0, 0) → cards stack perfectly on top; a small
## Vector2 → fan/pile effect; a larger Vector2 → hand spread.
##
## Render/input order: cards are reordered in the tree so card[0] (protocol's
## top-of-pile) is the LAST child. Godot routes mouse input to the last
## sibling first, and the last sibling is also drawn last, so card[0] is
## visually on top AND receives hover/click first. Any backdrop children
## (Art TextureRect, SlotHighlight) sit earlier in the tree — the Art naturally
## ends up behind cards; the `SlotHighlight` uses z_index=1000 (set in the
## .tscn) to render above cards regardless of tree position.

@export var offset: Vector2 = Vector2(0, -4)

## Cap on how many cards are visually rendered in this slot. count() still
## reports the full logical count (driven by the protocol), so prompt indices
## remain valid for hidden cards too. 0 = no cap (default).
@export var max_display: int = 0

const HIGHLIGHT_TWEEN_DURATION := 0.5
const HIGHLIGHT_INITIAL_SCALE := Vector2(1.05, 1.05)
const _CONTEXT_ARROW_SCENE: PackedScene = preload("res://fj/ui/context_arrow.tscn")

@onready var _highlight: Panel = $SlotHighlight
@onready var _overflow_badge: Label = $OverflowBadge

var _cards: Array[Card] = []
var _highlight_tween: Tween = null
var _context_arrow: Node2D = null


func count() -> int:
	return _cards.size()


func get_card(index: int) -> Card:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index]


func insert(index: int, card: Card) -> void:
	_cards.insert(index, card)
	add_child(card)
	_attach_card(card)
	_relayout()


func remove(index: int) -> Card:
	if index < 0 or index >= _cards.size():
		return null
	var card := _cards[index]
	_cards.remove_at(index)
	remove_child(card)
	_relayout()
	return card


func clear() -> void:
	for card in _cards:
		remove_child(card)
		card.queue_free()
	_cards.clear()


func set_highlight(level: int) -> void:
	_set_pulse_outline(level == Highlight.Level.HIGHLIGHT)
	_set_context_arrow(level == Highlight.Level.CONTEXT)


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
	if on and _context_arrow == null:
		_context_arrow = _CONTEXT_ARROW_SCENE.instantiate()
		add_child(_context_arrow)
		_context_arrow.position = Vector2(size.x * 0.5, size.y)
	elif not on and _context_arrow != null:
		_context_arrow.queue_free()
		_context_arrow = null


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

	# Godot routes mouse input by tree-sibling order (last child gets input
	# first), not by z_index. To make the visually-topmost card also be the
	# click/hover target, reorder the tree so card[0] ends up as the last
	# sibling. Iterating high-to-low and moving each to the end produces
	# final tree order [card[n-1], ..., card[0]] — card[0] last.
	for i in range(n - 1, -1, -1):
		move_child(_cards[i], -1)

	if max_display > 0 and n > max_display:
		_overflow_badge.text = "+%d" % (n - max_display)
		_overflow_badge.visible = true
	else:
		_overflow_badge.visible = false
