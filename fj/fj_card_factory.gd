class_name FjCardFactory
extends JsonCardFactory

const ImageResolverScript = preload("res://fj/net/image_resolver.gd")

var image_resolver  # ImageResolver


func _ready() -> void:
	super._ready()
	image_resolver = ImageResolverScript.new()


## Create a card from a server card name, resolving its front texture via ImageResolver.
func create_network_card(card_name: String, back_texture: Texture2D, target: CardContainer) -> Card:
	var front_texture: Texture2D = image_resolver.get_front_texture(card_name)
	if front_texture == null:
		push_error("FjCardFactory: no texture for card '%s'" % card_name)
		return null
	return _create_card_direct(card_name, front_texture, back_texture, target)


## Create an anonymous face-down card (for fog-of-war count slots).
func create_facedown_card(back_texture: Texture2D, target: CardContainer) -> Card:
	return _create_card_direct("_facedown", null, back_texture, target, false)


func _create_card_direct(card_name: String, front: Texture2D, back: Texture2D, target: CardContainer, show_front_face: bool = true) -> Card:
	if default_card_scene == null:
		push_error("FjCardFactory: default_card_scene not assigned")
		return null

	var card: Card = default_card_scene.instantiate()

	if not target._card_can_be_added([card]):
		card.queue_free()
		return null

	card.card_name = card_name
	card.card_size = card_size

	var cards_node := target.get_node("Cards")
	cards_node.add_child(card)
	target.add_card(card)

	if front:
		card.set_faces(front, back)
	else:
		card.set_faces(back, back)

	card.show_front = show_front_face
	return card
