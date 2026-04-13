extends Control

## Right-hand side panel. Dumb view — doesn't read GameSession directly.
## Board passes it the view dict + text options + my_side on every rebuild.

signal text_option_selected(option: Dictionary)

@onready var _hp_value: Label = $Backdrop/HPRow/HPValue
@onready var _phase_label: Label = $Backdrop/PhaseLabel
@onready var _priority_label: Label = $Backdrop/PriorityLabel
@onready var _prompt_label: Label = $Backdrop/VBox/PromptLabel
@onready var _text_options_box: VBoxContainer = $Backdrop/VBox/TextOptions
@onready var _notify_label: Label = $Backdrop/NotifyLabel
@onready var _game_result: Label = $Backdrop/GameResultLabel
@onready var _preview: TextureRect = $Backdrop/Preview/PreviewImage

var _notify_tween: Tween = null


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


func preview_card(texture: Texture2D) -> void:
	_preview.texture = texture
	_preview.visible = texture != null


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
