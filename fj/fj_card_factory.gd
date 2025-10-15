@tool
class_name FjCardFactory
extends JsonCardFactory


func _ready() -> void:
	super._ready()

func create_fj_card(card_name: String, color:G.PColor, target: CardContainer) -> Card:
	var card = create_card(card_name,target)
	card.color = color
	return card
