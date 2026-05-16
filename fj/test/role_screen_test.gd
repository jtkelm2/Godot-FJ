extends Control

const _ROLE_SCREEN_SCENE := preload("res://fj/board/scenes/role_screen.tscn")
const _SAMPLE_FRONT := preload("res://fj/assets/images/cards/named_1.png")
const _SAMPLE_BACK := preload("res://fj/assets/images/cards/back_red.png")


@onready var _game_area: Control = %GameArea
@onready var _role_input: LineEdit = %RoleInput
@onready var _play_button: Button = %PlayButton


var _role_screen: RoleScreen


func _ready() -> void:
	_role_screen = _ROLE_SCREEN_SCENE.instantiate()
	_role_screen.role_front = _SAMPLE_FRONT
	_role_screen.role_back = _SAMPLE_BACK
	_game_area.add_child(_role_screen)
	_role_screen.animation_started.connect(func() -> void: print("[test] animation_started"))
	_role_screen.animation_finished.connect(func() -> void: print("[test] animation_finished"))
	_play_button.pressed.connect(_on_play)


func _on_play() -> void:
	var role_text := _role_input.text if _role_input.text != "" else "DETECTIVE"
	_role_screen.role_name = role_text
	await _role_screen.play().run()
