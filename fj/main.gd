extends Node

const StateRendererScript = preload("res://fj/net/state_renderer.gd")
const PromptHandlerScript = preload("res://fj/net/prompt_handler.gd")

@onready var card_manager: CardManager = $CardManager
@onready var card_factory: FjCardFactory = $CardManager/FjCardFactory
@onready var info_panel: Control = $InfoPanel

var state_renderer: Node  # StateRenderer
var prompt_handler: Node  # PromptHandler


func _ready() -> void:
	state_renderer = StateRendererScript.new()
	state_renderer.name = "StateRenderer"
	add_child(state_renderer)

	prompt_handler = PromptHandlerScript.new()
	prompt_handler.name = "PromptHandler"
	add_child(prompt_handler)

	GameSession.catalog_ready.connect(_on_catalog_ready)
	GameSession.state_updated.connect(_on_state_updated)
	GameSession.prompt_arrived.connect(_on_prompt_arrived)
	GameSession.notify_received.connect(_on_notify_received)
	GameSession.session_ended.connect(_on_session_ended)


func _on_catalog_ready(catalog: RefCounted) -> void:
	state_renderer.initialize(catalog, card_manager, card_factory)
	prompt_handler.initialize(state_renderer)


func _on_state_updated(view: Dictionary) -> void:
	state_renderer.render_state(view)

	# Update info panel
	info_panel.update_hp(view.get("hp", 0))
	info_panel.update_weapons(view.get("weapons", []), view.get("opp_weapons", []))
	info_panel.update_priority(view.get("priority", ""))

	var game_result = view.get("game_result")
	if game_result != null:
		info_panel.show_game_result(game_result)


func _on_prompt_arrived(text: String, options: Array) -> void:
	info_panel.show_prompt_text(text)
	prompt_handler.handle_prompt(text, options)


func _on_notify_received(text: String) -> void:
	info_panel.show_notify(text)


func _on_session_ended(_result: Variant) -> void:
	prompt_handler.clear_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Signals.empty_click.emit()
