class_name Slot
extends Pile

## The server wire name for this slot (e.g. "red_hand"), set by StateRenderer.
var wire_name: String = ""

## The semantic role (e.g. "hand", "deck"), set by StateRenderer.
var semantic_role: String = ""

## The prompt option dict to echo back when this slot is clicked during a prompt.
var prompt_option: Dictionary = {}

## Whether this slot is highlighted as a valid prompt choice.
var _highlighted: bool = false


func set_highlighted(enabled: bool) -> void:
	_highlighted = enabled
	if enabled:
		modulate = Color(1.2, 1.2, 0.6, 1.0)
	else:
		modulate = Color.WHITE
		prompt_option = {}


func get_cards() -> Array[FJCard]:
	var result: Array[FJCard]
	result.assign(get_top_cards(get_card_count()))
	return result


func clear_all_cards() -> void:
	for card in _held_cards.duplicate():
		remove_card(card)
		card.queue_free()
