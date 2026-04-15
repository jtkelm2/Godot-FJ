class_name SlotField
extends Slot

## A slot that distributes inserts across child Slots placed in the editor,
## up to `capacity_per_child` cards per child. Presents a unified ordered-list
## API over its children: `insert(k, card)` finds the k-th free position,
## `get_card(k)` walks child-sizes until k is exhausted, etc.
##
## Children's signals (`card_clicked`, `slot_clicked`) are re-emitted from
## this SlotField with globally-numbered indices. A `card_clicked` on a child
## arrives with both signals fired by the child's ABC; we coalesce the
## duplicate `slot_clicked` using a per-frame guard.

@export var capacity_per_child: int = 1

var _child_slots: Array[Slot] = []
var _last_slot_click_frame: int = -1


func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is Slot:
			_child_slots.append(child)
			child.card_clicked.connect(_on_child_card_clicked_signal)
			child.slot_clicked.connect(_on_child_slot_clicked_signal)
			child.card_hovered.connect(_on_child_card_hovered_signal)
			child.card_unhovered.connect(_on_child_card_unhovered_signal)


func count() -> int:
	var n := 0
	for s in _child_slots:
		n += s.count()
	return n


func get_card(index: int) -> Card:
	var remaining := index
	for s in _child_slots:
		if remaining < s.count():
			return s.get_card(remaining)
		remaining -= s.count()
	return null


func insert(index: int, card: Card) -> void:
	var remaining := index
	for s in _child_slots:
		var local_count := s.count()
		var free_here := capacity_per_child - local_count
		# Fits if the target local index is within 0..local_count AND we have room.
		if remaining <= local_count and free_here > 0:
			s.insert(remaining, card)
			return
		# Otherwise skip forward — remaining counts against this child's occupants.
		remaining -= local_count
		if remaining < 0:
			remaining = 0
	assert(false, "SlotField %s: insert(%d) beyond capacity" % [get_path(), index])


func remove(index: int) -> Card:
	var remaining := index
	for s in _child_slots:
		if remaining < s.count():
			return s.remove(remaining)
		remaining -= s.count()
	return null


func clear() -> void:
	for s in _child_slots:
		s.clear()


func set_highlight(level: int) -> void:
	for s in _child_slots:
		s.set_highlight(level)


# --- Child signal re-emission ---

func _on_child_card_clicked_signal(child: Slot, local_idx: int) -> void:
	var global_idx := 0
	for s in _child_slots:
		if s == child:
			global_idx += local_idx
			card_clicked.emit(self, global_idx)
			_emit_slot_clicked_once()
			return
		global_idx += s.count()


func _on_child_slot_clicked_signal(_child: Slot) -> void:
	_emit_slot_clicked_once()


func _on_child_card_hovered_signal(child: Slot, local_idx: int) -> void:
	var global_idx := 0
	for s in _child_slots:
		if s == child:
			emit_signal("card_hovered", self, global_idx + local_idx)
			return
		global_idx += s.count()


func _on_child_card_unhovered_signal(_child: Slot) -> void:
	emit_signal("card_unhovered", self)


func _emit_slot_clicked_once() -> void:
	# A child that fires card_clicked also fires slot_clicked; collapse to one
	# emission per frame from this SlotField.
	var f := Engine.get_process_frames()
	if f == _last_slot_click_frame:
		return
	_last_slot_click_frame = f
	slot_clicked.emit(self)
