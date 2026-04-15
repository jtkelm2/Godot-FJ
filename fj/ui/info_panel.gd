extends PanelContainer

## A layout-peer panel (lives inside the board's outer HBoxContainer, not as
## an overlay). Dumb view — doesn't read GameSession directly. Board calls
## set_side(my_side) once at init to tint the backdrop; side-based positioning
## is the board's job (it move_child's this panel to left or right).

const TINT_RED := Color(0.42, 0.12, 0.16, 0.78)
const TINT_BLUE := Color(0.12, 0.18, 0.42, 0.78)
const TINT_NEUTRAL := Color(0.24, 0.30, 0.34, 0.78)

signal text_option_selected(option: Dictionary)

@onready var _hp_value: Label = $MarginContainer/Backdrop/HPRow/HPValue
@onready var _phase_label: Label = $MarginContainer/Backdrop/PhaseLabel
@onready var _priority_label: Label = $MarginContainer/Backdrop/PriorityLabel
@onready var _prompt_label: Label = $MarginContainer/Backdrop/VBox/PromptLabel
@onready var _text_options_box: VBoxContainer = $MarginContainer/Backdrop/VBox/TextOptions
@onready var _notify_label: Label = $MarginContainer/Backdrop/NotifyLabel
@onready var _game_result: Label = $MarginContainer/Backdrop/GameResultLabel
@onready var _preview: TextureRect = $MarginContainer/Backdrop/PanelContainer/Preview/PreviewImage
@onready var _arrow_up: Label = $MarginContainer/Backdrop/PanelContainer/Preview/HBoxContainer/ArrowUp
@onready var _arrow_down: Label = $MarginContainer/Backdrop/PanelContainer/Preview/HBoxContainer/ArrowDown

var _notify_tween: Tween = null

## Slot the cursor is currently hovering inside (or null). When non-null,
## mouse-wheel input here scrolls _preview_index through that slot's cards.
var _preview_slot = null  # Slot
var _preview_index: int = -1


## Tint the backdrop to match the local player's side. Positioning (which
## side of the board the panel sits on) is handled by Board's `move_child`
## on the outer row — not here.
func set_side(side: String) -> void:
	match side:
		"RED":  self_modulate = TINT_RED
		"BLUE": self_modulate = TINT_BLUE
		_:      self_modulate = TINT_NEUTRAL


func update_view(view: Dictionary, my_side: String) -> void:
	_hp_value.text = "%d / 20" % int(view.get("hp", 0))

	var phase = view.get("current_phase")
	if phase == null or (phase is String and phase.is_empty()):
		_phase_label.text = ""
		_phase_label.visible = false
	else:
		_phase_label.text = str(phase)
		_phase_label.visible = true

	var priority := str(view.get("priority", ""))
	var mine := (priority == my_side)
	_priority_label.text = "Your turn" if mine else "Opponent's turn"
	_priority_label.modulate = Color.LIGHT_GREEN if mine else Color(0.7, 0.7, 0.7)

	var result = view.get("game_result")
	if result != null:
		_show_game_result(result, my_side)
	else:
		_game_result.visible = false


func update_prompt(text: String, text_options: Array) -> void:
	_prompt_label.text = text
	_prompt_label.visible = not text.is_empty()

	for child in _text_options_box.get_children():
		child.queue_free()

	for option in text_options:
		var btn := Button.new()
		btn.text = str(option.get("text", "???"))
		btn.custom_minimum_size = Vector2(0, 36)
		var captured: Dictionary = option
		btn.pressed.connect(func(): text_option_selected.emit(captured))
		_text_options_box.add_child(btn)


func clear_prompt() -> void:
	_prompt_label.text = ""
	_prompt_label.visible = false
	for child in _text_options_box.get_children():
		child.queue_free()


func show_notify(text: String) -> void:
	if text.is_empty():
		return
	_notify_label.text = text
	_notify_label.visible = true
	if _notify_tween and _notify_tween.is_valid():
		_notify_tween.kill()
	_notify_tween = create_tween()
	_notify_tween.tween_interval(6.0)
	_notify_tween.tween_callback(func(): _notify_label.visible = false)


## Set the slot/index the cursor is currently hovering. Pass (null, -1) to
## clear. The preview pane shows the chosen card's front texture and exposes
## scroll arrows for stacks > 1.
func preview_card(slot, index: int) -> void:
	_preview_slot = slot
	_preview_index = index
	_render_preview()


func _render_preview() -> void:
	if _preview_slot == null or _preview_index < 0:
		_preview.texture = null
		_preview.visible = false
		_arrow_up.visible = false
		_arrow_down.visible = false
		return
	var card: Card = _preview_slot.get_card(_preview_index)
	var tex: Texture2D = card.front_texture if card else null
	_preview.texture = tex
	_preview.visible = tex != null
	var n: int = _preview_slot.count()
	_arrow_up.visible = _preview_index > 0
	_arrow_down.visible = _preview_index < n - 1


func _input(event: InputEvent) -> void:
	# Global wheel input: scroll the preview through the hovered slot's cards.
	# Only intercept while a slot is being previewed.
	if _preview_slot == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var step := 0
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = -1
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 1
	if step == 0:
		return
	var n: int = _preview_slot.count()
	if n <= 1:
		return
	_preview_index = clamp(_preview_index + step, 0, n - 1)
	_render_preview()
	get_viewport().set_input_as_handled()


func _show_game_result(result: Dictionary, my_side: String) -> void:
	var winners: Array = result.get("winners", [])
	var outcome := str(result.get("outcome", ""))
	if my_side in winners:
		_game_result.text = "VICTORY\n%s" % outcome
		_game_result.modulate = Color.GOLD
	elif winners.is_empty():
		_game_result.text = "DRAW\n%s" % outcome
		_game_result.modulate = Color.GRAY
	else:
		_game_result.text = "DEFEAT\n%s" % outcome
		_game_result.modulate = Color.RED
	_game_result.visible = true
