extends RefCounted

## The single place where wire-names and card-name strings meet UI widgets.
## Given a Slot and its slot-data value from a state message, fills the slot
## with Cards carrying the right front/back textures.
##
## Slots stay name-ignorant and texture-ignorant; Cards stay name-ignorant;
## Board stays texture-ignorant. The Wrangler bridges them all, delegating
## card instantiation to `Card.create()` and back-texture selection to the
## ImageResolver.

var catalog  # CatalogData
var image_resolver  # ImageResolver


func initialize(p_catalog, p_image_resolver) -> void:
	catalog = p_catalog
	image_resolver = p_image_resolver


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
	# Insert in protocol order: names[0] = top of pile = slot.get_card(0).
	var back: Texture2D = image_resolver.get_back_for(slot.owner_side)
	for i in names.size():
		var card_name := str(names[i])
		var front: Texture2D = image_resolver.get_front_texture(card_name)
		slot.insert(i, Card.create(front, back, true))


func _populate_facedown(slot: Slot, n: int) -> void:
	var back: Texture2D = image_resolver.get_back_for(slot.owner_side)
	for i in n:
		slot.insert(i, Card.create(null, back, false))
