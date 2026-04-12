extends RefCounted

## A unified view over one logical slot (one wire name), backed by 1 or more
## physical CardContainers. Hides the single-vs-multi-container distinction
## from the renderer and prompt handler.

var wire_name: String
var role: String
var owner: String  # "self" | "opponent" | "shared"
var containers: Array  # Array[CardContainer] - 1+ physical nodes, in order
var back_texture: Texture2D
var card_factory: FjCardFactory

## Set by PromptHandler when this slot is offered as a {"type": "slot", ...} option.
var prompt_option: Dictionary = {}


## Update to show the given card list. Distributes across containers:
## - single container: all cards stack in it
## - multiple containers: one card per container, in order; extras are dropped
func set_visible_cards(card_names: Array) -> void:
	if containers.size() == 1:
		_reconcile_visible(containers[0], card_names)
	else:
		for i in containers.size():
			var target: Array = [card_names[i]] if i < card_names.size() else []
			_reconcile_visible(containers[i], target)


## Update to show a facedown count (fog-of-war). All count goes into the first
## container; any additional containers are cleared.
func set_facedown_count(count: int) -> void:
	_reconcile_facedown(containers[0], count)
	for i in range(1, containers.size()):
		_reconcile_facedown(containers[i], 0)


## Empty all physical containers (for fog-of-war hidden slots).
func clear() -> void:
	for c in containers:
		_reconcile_facedown(c, 0)


## Look up the card at logical index `index` in this slot (as used in
## {"type": "card", "slot": wire, "index": i} options).
func get_card_at(index: int) -> Card:
	var running := 0
	for c in containers:
		for card in c._held_cards:
			if running == index:
				return card
			running += 1
	return null


## Apply a visual highlight to all containers in this slot.
func set_highlighted(enabled: bool) -> void:
	for c in containers:
		if c.has_method("set_highlighted"):
			c.set_highlighted(enabled)
	if not enabled:
		prompt_option = {}


# --- Internal reconciliation helpers ---

func _reconcile_visible(container: CardContainer, card_names: Array) -> void:
	var current_cards: Array = container._held_cards.duplicate()
	var target_size: int = card_names.size()
	var current_size: int = current_cards.size()
	var cards_to_keep: int = mini(current_size, target_size)
	var i := 0

	while i < cards_to_keep:
		var existing: Card = current_cards[i]
		var target_name: String = card_names[i]
		if existing.card_name != target_name:
			container.remove_card(existing)
			_tween_remove(existing)
			var new_card: Card = card_factory.create_network_card(target_name, back_texture, container)
			if new_card:
				new_card.show_front = true
		else:
			existing.show_front = true
		i += 1

	while i < current_size:
		var excess: Card = current_cards[i]
		container.remove_card(excess)
		_tween_remove(excess)
		i += 1

	var j := cards_to_keep
	while j < target_size:
		var new_name: String = card_names[j]
		var new_card: Card = card_factory.create_network_card(new_name, back_texture, container)
		if new_card:
			new_card.show_front = true
		j += 1


func _reconcile_facedown(container: CardContainer, count: int) -> void:
	var current_count: int = container.get_card_count()
	if current_count < count:
		for i in range(count - current_count):
			var card: Card = card_factory.create_facedown_card(back_texture, container)
			if card:
				card.show_front = false
	elif current_count > count:
		var cards_to_remove: Array = container._held_cards.duplicate()
		for i in range(current_count - count):
			var card: Card = cards_to_remove[cards_to_remove.size() - 1 - i]
			container.remove_card(card)
			card.queue_free()


func _tween_remove(card: Card) -> void:
	var tween: Tween = card.create_tween()
	tween.tween_property(card, "modulate:a", 0.0, 0.2)
	tween.tween_callback(card.queue_free)
