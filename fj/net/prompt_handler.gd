extends Node

var state_renderer  # StateRenderer
var _active: bool = false
var _text_buttons: Array[Button] = []
var _highlighted_cards: Array[FJCard] = []
var _highlighted_views: Array = []  # Array[SlotView]
var _button_container: Node


func initialize(p_state_renderer: Node, button_container: Node) -> void:
	state_renderer = p_state_renderer
	_button_container = button_container


func handle_prompt(_text: String, options: Array) -> void:
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

	for view in _highlighted_views:
		view.set_highlighted(false)
	_highlighted_views.clear()

	for btn in _text_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_text_buttons.clear()


func _highlight_card_option(option: Dictionary) -> void:
	var slot_wire: String = option.get("slot", "")
	var index: int = option.get("index", -1)

	var view = state_renderer.get_slot_view(slot_wire)
	if view == null:
		push_warning("PromptHandler: no view for wire '%s'" % slot_wire)
		return

	var card = view.get_card_at(index)
	if card == null:
		push_warning("PromptHandler: card index %d not found in wire '%s'" % [index, slot_wire])
		return

	if card is FJCard:
		var fj_card := card as FJCard
		fj_card.prompt_option = option
		fj_card.set_highlighted(true)
		_highlighted_cards.append(fj_card)


func _highlight_slot_option(option: Dictionary) -> void:
	var slot_wire: String = option.get("name", "")
	var view = state_renderer.get_slot_view(slot_wire)
	if view == null:
		push_warning("PromptHandler: no view for slot wire '%s'" % slot_wire)
		return
	view.prompt_option = option
	view.set_highlighted(true)
	_highlighted_views.append(view)


func _highlight_weapon_slot_option(option: Dictionary) -> void:
	var ws_wire: String = option.get("name", "")
	var view = state_renderer.get_slot_view(ws_wire)
	if view == null:
		push_warning("PromptHandler: no view for weapon_slot wire '%s'" % ws_wire)
		return
	view.prompt_option = option
	view.set_highlighted(true)
	_highlighted_views.append(view)


func _create_text_button(option: Dictionary) -> void:
	var text: String = option.get("text", "???")
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(160, 40)
	btn.pressed.connect(func(): _select_option(option))
	_button_container.add_child(btn)
	_text_buttons.append(btn)


## All board-click hit-testing happens here. We bypass Godot's UI input routing
## to avoid fighting with the card-framework's internal Control hierarchy.
func _input(event: InputEvent) -> void:
	if not _active:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var pos: Vector2 = mouse_event.position
	var card_size: Vector2 = state_renderer.card_factory.card_size

	# Check highlighted cards first (they can overlap slot regions).
	for card in _highlighted_cards:
		if is_instance_valid(card) and Rect2(card.global_position, card.card_size).has_point(pos):
			_select_option(card.prompt_option)
			get_viewport().set_input_as_handled()
			return

	# Check highlighted slot views (treat each physical container as a card-sized region).
	for view in _highlighted_views:
		for container in view.containers:
			if Rect2(container.global_position, card_size).has_point(pos):
				_select_option(view.prompt_option)
				get_viewport().set_input_as_handled()
				return


func _select_option(option: Dictionary) -> void:
	if not _active:
		return
	_active = false
	if GameSession.log:
		GameSession.log.log_event("player_selected_option", option)
	GameSession.respond(option)
	clear_prompt()
