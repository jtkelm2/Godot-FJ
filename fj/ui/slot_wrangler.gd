extends RefCounted

## The single place where wire-names and card-name strings meet UI widgets.
## Holds the catalog + image_resolver + my_side, instantiates Cards from
## protocol data, and populates a given Slot to match a slot-data value.
##
## Slots stay name-ignorant and texture-ignorant; Cards stay name-ignorant;
## Board stays texture-ignorant. The Wrangler bridges them all.

const CardScene = preload("res://fj/ui/card.tscn")

signal card_created(card: Card, card_name: String)

var catalog  # CatalogData
var image_resolver  # ImageResolver
var my_side: String

var _self_back: Texture2D
var _opp_back: Texture2D
var _neutral_back: Texture2D


func initialize(p_catalog, p_image_resolver, p_my_side: String) -> void:
	catalog = p_catalog
	image_resolver = p_image_resolver
	my_side = p_my_side
	_self_back = image_resolver.get_back_texture(my_side)
	var opp_side := "BLUE" if my_side == "RED" else "RED"
	_opp_back = image_resolver.get_back_texture(opp_side)
	_neutral_back = image_resolver.get_back_texture("SHARED")


## Reconcile `slot`'s contents with `slot_data`:
##   - Array: visible cards, faceup, named textures from the resolver.
##   - int:   facedown pile, count cards with the appropriate back.
##   - null/absent: empty.
func apply_to(slot: Slot, slot_data) -> void:
	slot.clear()
	if slot_data is Array:
		_populate_visible(slot, slot_data)
	elif slot_data is float:
		_populate_facedown(slot, int(slot_data))


func _populate_visible(slot: Slot, names: Array) -> void:
	var back: Texture2D = _back_for(slot.owner_side)
	var n = names.size()
	for i in n:
		var card_name := str(names[n-i-1])
		var front: Texture2D = image_resolver.get_front_texture(card_name)
		var card: Card = _make_card(front, back, true, card_name)
		slot.insert(i, card)


func _populate_facedown(slot: Slot, n: int) -> void:
	var back: Texture2D = _back_for(slot.owner_side)
	for i in n:
		var card: Card = _make_card(null, back, false, "")
		slot.insert(i, card)


func _make_card(front: Texture2D, back: Texture2D, faceup: bool, card_name: String) -> Card:
	var c: Card = CardScene.instantiate()
	c.set_back(back)
	c.set_front(front)
	c.set_face(faceup)
	card_created.emit(c, card_name)
	return c


func _back_for(owner_side: String) -> Texture2D:
	if owner_side == my_side:
		return _self_back
	elif owner_side == "SHARED":
		return _neutral_back
	else:
		return _opp_back
