extends Node

@onready var card_manager = $CardManager
@onready var card_factory = $CardManager/FjCardFactory

func _ready():
	$PhaseLabel/Label.text = $PhaseManager.current_phase
	$PhaseButton.item_selected.connect(func(idx): $PhaseManager.change_phase($PhaseButton.get_item_text(idx)))
	_make_deck(G.Red)
	_make_deck(G.Blue)

func _make_deck(color:G.PColor) -> void:
	var deck:Pile = $CardManager/RDeck if color == G.Red else $CardManager/BDeck
	
	for i in range(1,22):
		card_factory.create_fj_card("major_%d" % i, color, deck)
	
	for i in range(1,15):
		for j in range(0,2):
			card_factory.create_fj_card("enemy_%d" % i, color, deck)
	
	for i in range(1,11):
		card_factory.create_fj_card("food_%d" % i, color, deck)
		card_factory.create_fj_card("weapon_%d" % i, color, deck)
	
	deck.shuffle()

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		Signals.empty_click.emit()
