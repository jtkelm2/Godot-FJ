extends Control

@onready var hp_label: Label = $VBoxContainer/HPSection/HPValue
@onready var weapon_label: Label = $VBoxContainer/WeaponSection/WeaponValue
@onready var phase_label: Label = $VBoxContainer/PhaseLabel
@onready var priority_label: Label = $VBoxContainer/PriorityLabel
@onready var prompt_label: Label = $VBoxContainer/PromptLabel
@onready var text_options: VBoxContainer = $VBoxContainer/TextOptions
@onready var notify_label: Label = $VBoxContainer/NotifyLabel
@onready var card_preview: TextureRect = $ReferenceRect/TextureRect
@onready var game_result_label: Label = $VBoxContainer/GameResultLabel


func update_hp(hp: int) -> void:
	hp_label.text = "%d / 20" % hp


func update_weapons(weapons: Array) -> void:
	var lines: PackedStringArray = []
	for w in weapons:
		var card_name: String = w.get("card", "none") if w.get("card") else "empty"
		lines.append("%s (S:%d K:%d)" % [card_name, w.get("sharpness", 0), w.get("kills", 0)])
	weapon_label.text = "\n".join(lines) if not lines.is_empty() else "No weapons"


func update_phase(phase) -> void:
	if phase == null or (phase is String and phase.is_empty()):
		phase_label.text = ""
		phase_label.visible = false
	else:
		phase_label.text = str(phase)
		phase_label.visible = true


func update_priority(priority: String) -> void:
	var is_mine := (priority == G.my_side)
	priority_label.text = "Your turn" if is_mine else "Opponent's turn"
	priority_label.modulate = Color.GREEN if is_mine else Color(0.7, 0.7, 0.7)


func show_prompt_text(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = not text.is_empty()


func show_notify(text: String) -> void:
	notify_label.text = text
	notify_label.visible = true
	# Auto-hide after a delay
	var tween := create_tween()
	tween.tween_interval(5.0)
	tween.tween_callback(func(): notify_label.visible = false)


func show_game_result(result: Dictionary) -> void:
	var winners: Array = result.get("winners", [])
	var outcome: String = result.get("outcome", "")
	var won := G.my_side in winners
	if won:
		game_result_label.text = "VICTORY!\n%s" % outcome
		game_result_label.modulate = Color.GOLD
	elif winners.is_empty():
		game_result_label.text = "DRAW\n%s" % outcome
		game_result_label.modulate = Color.GRAY
	else:
		game_result_label.text = "DEFEAT\n%s" % outcome
		game_result_label.modulate = Color.RED
	game_result_label.visible = true


func clear_game_result() -> void:
	game_result_label.visible = false


func preview_card_texture(texture: Texture2D) -> void:
	card_preview.texture = texture
	card_preview.visible = texture != null


func clear_preview() -> void:
	card_preview.texture = null
	card_preview.visible = false
