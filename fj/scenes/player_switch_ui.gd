## Player Switch UI for hotseat play
## Shows current player and provides switching controls
class_name PlayerSwitchUI
extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var player_label: Label = $Panel/VBox/PlayerLabel
@onready var instruction_label: Label = $Panel/VBox/InstructionLabel


func _ready() -> void:
	# Connect to player switch signal
	G.player_switched.connect(_on_player_switched)
	
	# Initial update
	_update_display()
	
	# Position panel at top center
	panel.position = Vector2(860, 20)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):  # Enter/Space
		G.switch_player()


func _on_player_switched(_new_player: G.PColor) -> void:
	_update_display()
	_show_switch_animation()


func _update_display() -> void:
	var player_name = "RED" if G.current_player == G.PColor.Red else "BLUE"
	var player_color = Color.RED if G.current_player == G.PColor.Red else Color.BLUE
	
	player_label.text = "Current Player: %s" % player_name
	player_label.add_theme_color_override("font_color", player_color)
	
	instruction_label.text = "[Enter] to pass turn"


func _show_switch_animation() -> void:
	# Simple fade animation to indicate switch
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.2)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)
