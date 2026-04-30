## SlotView: abstract base for a container of ordered CardViews.
##
## `_cards` is the authoritative list — server-driven, mutated only via
## `insert` / `remove` / `clear`. Subclasses arrange children visually but the
## indexing contract above always speaks in protocol order (`_cards[0]` is
## the top of the pile, per protocol §3.2.1).
##
## **Renderer-internal naming**: identity-free. The widget doesn't know which
## NL `SlotID` it represents — the composition root maintains the
## `Dict[SlotID, SlotView]` mapping externally. This keeps SlotView reusable
## (replay scenes, AI driver scenes, tests) without leaking NL semantics.
##
## Signal choreography: when a child CardView fires `clicked`, the SlotView
## emits `card_clicked(self, index)` followed by `slot_clicked(self)`. Empty-
## area clicks emit only `slot_clicked(self)`.

@abstract
class_name SlotView extends Control


signal slot_clicked(slot: SlotView)
signal card_clicked(slot: SlotView, index: int)
signal card_hovered(slot: SlotView, index: int)
signal card_unhovered(slot: SlotView)


## Scene-level identity exports. The SlotView itself doesn't use these for
## any logic — they're metadata the composer reads at scene-init time to
## resolve which Catalog-vended SlotID this widget represents (via
## `Catalog.slot_id_for(side, kind, num)`).
##
## `side` is the absolute PID owner (RED/BLUE), ignored by GuardDeck. `kind`
## is the typed slot identity. `num` is the weapon-slot index for ws-interior
## kinds; ignored otherwise.
@export var side: NLEnums.PID = NLEnums.PID.RED
@export var kind: NLEnums.SlotKind = NLEnums.SlotKind.HAND
@export var num: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_slot_gui_input)


# --- Abstract API ---

@abstract func insert(index: int, card: CardView) -> void
@abstract func remove(index: int) -> CardView
@abstract func clear() -> void
@abstract func count() -> int
@abstract func get_card(index: int) -> CardView


## Visual prompt decoration. Default no-op; subclasses override.
func set_highlight(_level: HighlightLevel.Level) -> void:
	pass


# --- Signal choreography (subclass calls these when a card is added/removed) ---

func _attach_card(card: CardView) -> void:
	card.clicked.connect(_on_child_card_clicked.bind(card))
	card.mouse_entered.connect(_on_child_card_hovered.bind(card))
	card.mouse_exited.connect(_on_child_card_unhovered)


## Mirror of `_attach_card`. Must be called from `remove()` before the card
## is detached from the slot — otherwise the card retains a connection back
## to this slot's handlers, and a subsequent `_attach_card` on a different
## slot would result in the click firing on both slots.
##
## Not needed for `clear()`: `queue_free()` auto-disconnects on free.
func _detach_card(card: CardView) -> void:
	card.clicked.disconnect(_on_child_card_clicked.bind(card))
	card.mouse_entered.disconnect(_on_child_card_hovered.bind(card))
	card.mouse_exited.disconnect(_on_child_card_unhovered)


func _on_child_card_clicked(card: CardView) -> void:
	var idx := _index_of(card)
	if idx < 0:
		return
	# Card-specific signal first; slot_clicked follows for any slot-level
	# listener that would otherwise miss the gesture.
	card_clicked.emit(self, idx)
	slot_clicked.emit(self)


func _on_child_card_hovered(card: CardView) -> void:
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


func _index_of(card: CardView) -> int:
	for i in count():
		if get_card(i) == card:
			return i
	return -1
