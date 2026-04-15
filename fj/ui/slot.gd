class_name Slot
extends Control

## Abstract base for a container of ordered Cards. The protocol describes
## slots as ordered lists; this ABC presents the same shape to its callers
## regardless of how the concrete subclass arranges its children.
##
## Contract that subclasses MUST implement:
##   insert(index, card), remove(index), clear(), count(), get_card(index).
##
## The ABC handles signal choreography: when a child Card fires `clicked`,
## the Slot emits `card_clicked(self, index)` followed by `slot_clicked(self)`.
## Clicks on the slot's empty area emit only `slot_clicked(self)`.
##
## `set_highlight(level)` is visual-only; subclasses override. `level` is a
## `Highlight.Level` (LOWLIGHT / CONTEXT / HIGHLIGHT).

signal slot_clicked(slot: Slot)
signal card_clicked(slot: Slot, index: int)
signal card_hovered(slot: Slot, index: int)
signal card_unhovered(slot: Slot)

@export var owner_side: String = ""  # "RED" | "BLUE" | "SHARED" (absolute; Board translates via my_side)
@export var role: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_slot_gui_input)


# --- Abstract API ---

func insert(_index: int, _card: Card) -> void:
	push_error("Slot.insert not implemented in %s" % get_path())


func remove(_index: int) -> Card:
	push_error("Slot.remove not implemented in %s" % get_path())
	return null


func clear() -> void:
	push_error("Slot.clear not implemented in %s" % get_path())


func count() -> int:
	push_error("Slot.count not implemented in %s" % get_path())
	return 0


func get_card(_index: int) -> Card:
	push_error("Slot.get_card not implemented in %s" % get_path())
	return null


func set_highlight(_level: int) -> void:
	pass  # default no-op; subclasses override.


# --- Signal choreography (called by subclass when it adds a card) ---

func _attach_card(card: Card) -> void:
	# A new Card entered this slot. Wire its click and hover to re-emit
	# helpers that translate to (slot, index)-aware signals.
	card.clicked.connect(_on_child_card_clicked.bind(card))
	card.mouse_entered.connect(_on_child_card_hovered.bind(card))
	card.mouse_exited.connect(_on_child_card_unhovered)


func _on_child_card_clicked(card: Card) -> void:
	var idx := _index_of(card)
	if idx < 0:
		return
	# Card-specific signal first (specificity: card > slot). The Board's
	# response clears pending_prompt, so the subsequent slot_clicked no-ops.
	card_clicked.emit(self, idx)
	slot_clicked.emit(self)


func _on_child_card_hovered(card: Card) -> void:
	var idx := _index_of(card)
	if idx >= 0:
		card_hovered.emit(self, idx)


func _on_child_card_unhovered() -> void:
	card_unhovered.emit(self)


func _on_slot_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			slot_clicked.emit(self)
			accept_event()


func _index_of(card: Card) -> int:
	for i in count():
		if get_card(i) == card:
			return i
	return -1
