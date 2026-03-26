extends Node

signal slot_clicked(slot:Slot)
signal card_clicked(card:FJCard)
signal empty_click
signal phase_changed(new_phase:String)

func _ready():
	pass
	# card_clicked.connect(func(card): print("Card clicked!", card.card_info.name, card.slot))
