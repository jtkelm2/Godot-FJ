extends Node

var state_renderer  # StateRenderer
var _active: bool = false
var _text_buttons: Array[Button] = []
var _highlighted_cards: Array[FJCard] = []
var _highlighted_containers: Array = []  # CardContainer instances


func initialize(p_state_renderer: Node) -> void:
	state_renderer = p_state_renderer
	Signals.card_clicked.connect(_on_card_clicked)
	Signals.slot_clicked.connect(_on_slot_clicked)


func handle_prompt(text: String, options: Array) -> void:
	clear_prompt()
	_active = true

	for option in options:
		var opt_type: String = option.get("type", "")
		match opt_type:
			"card":
				_highlight_card_option(option)
			"slot":
				_highlight_slot_option(option)
			"weapon_slot":
				_highlight_weapon_slot_option(option)
			"text":
				_create_text_button(option)
			_:
				push_warning("PromptHandler: unknown option type '%s'" % opt_type)


func clear_prompt() -> void:
	_active = false

	for card in _highlighted_cards:
		if is_instance_valid(card):
			card.set_highlighted(false)
	_highlighted_cards.clear()

	for container in _highlighted_containers:
		if is_instance_valid(container):
			container.set_highlighted(false)
	_highlighted_containers.clear()

	for btn in _text_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_text_buttons.clear()


func _highlight_card_option(option: Dictionary) -> void:
	var slot_wire: String = option.get("slot", "")
	var index: int = option.get("index", -1)

	var container: CardContainer = state_renderer.wire_to_container.get(slot_wire)
	if container == null:
		# Check multi-containers (equipment)
		var multi: Array = state_renderer.wire_to_multi_container.get(slot_wire, [])
		if not multi.is_empty():
			# For multi-container, index 0 -> first slot, index 1 -> second slot, etc.
			if index < multi.size():
				container = multi[index]
				index = 0  # Each sub-slot has at most 1 card
		if container == null:
			push_warning("PromptHandler: no container for wire '%s'" % slot_wire)
			return

	if index < 0 or index >= container.get_card_count():
		push_warning("PromptHandler: card index %d out of range for wire '%s' (has %d)" % [index, slot_wire, container.get_card_count()])
		return

	var card: Card = container._held_cards[index]
	if card is FJCard:
		var fj_card := card as FJCard
		fj_card.prompt_option = option
		fj_card.set_highlighted(true)
		_highlighted_cards.append(fj_card)


func _highlight_slot_option(option: Dictionary) -> void:
	var slot_wire: String = option.get("name", "")
	var container: CardContainer = state_renderer.wire_to_container.get(slot_wire)
	if container == null:
		push_warning("PromptHandler: no container for slot wire '%s'" % slot_wire)
		return

	if container is Slot:
		(container as Slot).prompt_option = option
		(container as Slot).set_highlighted(true)
		_highlighted_containers.append(container)
	elif container is FJHand:
		(container as FJHand).prompt_option = option
		(container as FJHand).set_highlighted(true)
		_highlighted_containers.append(container)


func _highlight_weapon_slot_option(option: Dictionary) -> void:
	# Weapon slots map through wire_to_container via ws_0_weapon role
	var ws_wire: String = option.get("name", "")
	# The weapon slot's container might be mapped under its wire name
	# Try the catalog to find which weapon slot container this corresponds to
	var container: CardContainer = state_renderer.wire_to_container.get(ws_wire)
	if container:
		if container is Slot:
			(container as Slot).prompt_option = option
			(container as Slot).set_highlighted(true)
			_highlighted_containers.append(container)
	else:
		Signals.weapon_slot_clicked.emit(ws_wire)
		push_warning("PromptHandler: no container for weapon_slot wire '%s'" % ws_wire)


func _create_text_button(option: Dictionary) -> void:
	var text: String = option.get("text", "???")
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(160, 40)
	btn.pressed.connect(func(): _select_option(option))

	# Add to the scene -- the InfoPanel will provide a container for these
	var button_parent := get_node_or_null("../InfoPanel/TextOptions")
	if button_parent:
		button_parent.add_child(btn)
	else:
		# Fallback: add as a child of self
		add_child(btn)

	_text_buttons.append(btn)


func _on_card_clicked(card: FJCard) -> void:
	if not _active:
		return
	if card.prompt_option.is_empty():
		return
	_select_option(card.prompt_option)


func _on_slot_clicked(slot: Slot) -> void:
	if not _active:
		return
	if slot.prompt_option.is_empty():
		return
	_select_option(slot.prompt_option)


func _select_option(option: Dictionary) -> void:
	if not _active:
		return
	_active = false
	GameSession.respond(option)
	clear_prompt()
