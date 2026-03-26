extends Control

var _previewed_textures:Array[Texture2D] = []
var _preview_index:int = 0
var selected_slot:Slot = null

@onready var __preview_rect = $ReferenceRect/TextureRect
@onready var __next_button = $HBoxContainer/NextButton
@onready var __previous_button = $HBoxContainer/PreviousButton

func _ready():
	__next_button.button_up.connect(_on_next_preview_clicked)
	__previous_button.button_up.connect(_on_previous_preview_clicked)
	Signals.slot_clicked.connect(select_slot)
	Signals.empty_click.connect(deselect_slot)
	
func select_slot(slot:Slot):
	_clear_preview()
	selected_slot = slot
	_preview_slot()
	
	

func deselect_slot():
	select_slot(null)

func _preview_slot():
	if not selected_slot:
		return
	
	if selected_slot.type == VisibilityManager.SlotType.DECK:
		return
	
	var textures:Array[Texture2D] = []
	for card in selected_slot.get_cards():
		textures.append(card.get_texture())
	_previewed_textures = textures
	_preview_index = 0
	_update_preview()

func _clear_preview():
	_previewed_textures = []
	_preview_index = 0
	_update_preview()

func _set_preview(new_index:int):
	if new_index < 0 or new_index >= _previewed_textures.size():
		return
	_preview_index = new_index
	_update_preview()

func _on_next_preview_clicked():
	_set_preview(_preview_index + 1)

func _on_previous_preview_clicked():
	_set_preview(_preview_index - 1)

func _update_preview():
	if _previewed_textures.size() == 0:
		__preview_rect.visible = false
		return
	
	assert(_preview_index >= 0 and _preview_index < _previewed_textures.size())
	__preview_rect.visible = true
	__preview_rect.texture = _previewed_textures[_preview_index]
