## Modal dialog for showing the player a list of cards. Operates in two modes:
##   - Informational (set_selection_count(0)): "Done" is always enabled and
##     selection_made emits an empty array on press.
##   - Selection (set_selection_count(N>0)): "Done" enables only when exactly
##     N cards are selected; selection toggles on click, and clicking past N
##     drops the oldest selection (FIFO).
##
## The presenter owns its own CardView instances spawned from CardDescriptors,
## so it can show cards that are not currently in any slot.

class_name CardPresenter extends CanvasLayer


signal card_clicked(index: int)
signal card_hovered(index: int)
signal card_unhovered()
signal selection_made(indices: Array[int])


const _CARD_VIEW_SCENE := preload("res://fj/board/scenes/card_view.tscn")


@onready var _prompt_label: Label = %PromptLabel
@onready var _grid: HFlowContainer = %CardGrid
@onready var _confirm_button: Button = %ConfirmButton


var _cards: Array[CardView] = []
var _selected_order: Array[int] = []
var _required_count: int = 0


func _ready() -> void:
	_confirm_button.pressed.connect(_on_confirm)
	_update_confirm_enabled()


func present() -> Action:
	return Action.Sync.new(func() -> void: visible = true)


func dismiss() -> Action:
	return Action.Sync.new(func() -> void: visible = false)


func populate(cards: Array[CardDescriptor]) -> Action:
	return Action.Sync.new(func() -> void: _do_populate(cards))


func clear() -> Action:
	return Action.Sync.new(_clear_card_nodes)


func set_text(msg: String) -> void:
	if is_node_ready():
		_prompt_label.text = msg
	else:
		ready.connect(func() -> void: _prompt_label.text = msg, ConnectFlags.CONNECT_ONE_SHOT)


func set_selection_count(num_to_select: int) -> void:
	_required_count = max(0, num_to_select)
	while _selected_order.size() > _required_count:
		var dropped: int = _selected_order.pop_front()
		if dropped < _cards.size():
			_cards[dropped].set_highlight(HighlightLevel.Level.LOWLIGHT)
	if is_node_ready():
		_update_confirm_enabled()


func _do_populate(descriptors: Array[CardDescriptor]) -> void:
	_clear_card_nodes()
	for d in descriptors:
		var card := _spawn_card(d)
		var idx := _cards.size()
		_cards.append(card)
		_grid.add_child(card)
		_wire_card(card, idx)
	_update_confirm_enabled()


func _spawn_card(d: CardDescriptor) -> CardView:
	var card: CardView = _CARD_VIEW_SCENE.instantiate()
	card.back_texture = d.back
	card.front_texture = d.front
	card.is_faceup = d.faceup
	return card


func _wire_card(card: CardView, index: int) -> void:
	card.clicked.connect(_on_card_clicked.bind(index))
	card.mouse_entered.connect(_on_card_hovered.bind(index))
	card.mouse_exited.connect(_on_card_unhovered)


func _on_card_clicked(index: int) -> void:
	card_clicked.emit(index)
	if _required_count > 0:
		_toggle_selection(index)


func _toggle_selection(index: int) -> void:
	var pos := _selected_order.find(index)
	if pos != -1:
		_selected_order.remove_at(pos)
		_cards[index].set_highlight(HighlightLevel.Level.LOWLIGHT)
	else:
		if _selected_order.size() >= _required_count:
			var dropped: int = _selected_order.pop_front()
			_cards[dropped].set_highlight(HighlightLevel.Level.LOWLIGHT)
		_selected_order.append(index)
		_cards[index].set_highlight(HighlightLevel.Level.HIGHLIGHT)
	_update_confirm_enabled()


func _on_card_hovered(index: int) -> void:
	card_hovered.emit(index)


func _on_card_unhovered() -> void:
	card_unhovered.emit()


func _on_confirm() -> void:
	var indices: Array[int] = _selected_order.duplicate()
	selection_made.emit(indices)


func _update_confirm_enabled() -> void:
	if _required_count == 0:
		_confirm_button.disabled = false
	else:
		_confirm_button.disabled = _selected_order.size() != _required_count


func _clear_card_nodes() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	_selected_order.clear()
	_update_confirm_enabled()
