class_name SimpleSlot
extends Slot

## A slot that lays out its cards in a single pile with a configurable
## per-card offset. Offset = (0, 0) → cards stack perfectly on top; a small
## Vector2 → fan/pile effect; a larger Vector2 → hand spread.

@export var offset: Vector2 = Vector2(0, -4)

var _cards: Array[Card] = []
var _highlight_overlay: ColorRect


func _ready() -> void:
	super._ready()
	_highlight_overlay = ColorRect.new()
	_highlight_overlay.name = "SlotHighlight"
	_highlight_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight_overlay.color = Color(0.6, 0.55, 0.15, 0.35)
	_highlight_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight_overlay.visible = false
	add_child(_highlight_overlay)


func count() -> int:
	return _cards.size()


func get_card(index: int) -> Card:
	if index < 0 or index >= _cards.size():
		return null
	return _cards[index]


func insert(index: int, card: Card) -> void:
	_cards.insert(index, card)
	add_child(card)
	# We rely on cards being appended in logical order (full-rebuild pattern).
	# Scene children (art, highlight) come first; cards always render on top.
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


func set_highlight(on: bool) -> void:
	_highlight_overlay.visible = on


func _relayout() -> void:
	for i in _cards.size():
		_cards[i].position = offset * i
