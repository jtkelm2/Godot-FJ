extends Control

const _PHASE_BANNER_SCENE := preload("res://fj/board/scenes/phase_banner.tscn")
const _BLUE := preload("res://resources/blue_phase_banner_theme.tres")
const _RED := preload("res://resources/red_phase_banner_theme.tres")
const _PURPLE := preload("res://resources/purple_phase_banner_theme.tres")

@onready var _game_area: Control = %GameArea
@onready var _text_input: LineEdit = %TextInput
@onready var _blue_btn: Button = %BlueButton
@onready var _red_btn: Button = %RedButton
@onready var _purple_btn: Button = %PurpleButton

var _banner: PhaseBanner


func _ready() -> void:
	_banner = _PHASE_BANNER_SCENE.instantiate()
	_game_area.add_child(_banner)
	_banner.animation_started.connect(func() -> void: print("[test] animation_started"))
	_banner.animation_finished.connect(func() -> void: print("[test] animation_finished"))
	_blue_btn.pressed.connect(func() -> void: _play(_BLUE))
	_red_btn.pressed.connect(func() -> void: _play(_RED))
	_purple_btn.pressed.connect(func() -> void: _play(_PURPLE))


func _play(banner_theme: Theme) -> void:
	var label_text := _text_input.text if _text_input.text != "" else "PHASE CHANGE"
	_banner.text = label_text
	_banner.style = banner_theme
	await _banner.play().run()
