## SlotFieldView: a slot composite that distributes inserts across child
## SlotViews placed in the editor, up to `capacity_per_child` cards per child.
##
## Presents a unified ordered-list API over its children:
##   `insert(k, card)`    — finds the k-th free position
##   `get_card(k)`        — walks child-sizes until k is exhausted
##   `count()`            — sum of child counts
##
## Children's `card_clicked` / `slot_clicked` signals are re-emitted from this
## SlotFieldView with globally-numbered indices. A `card_clicked` on a child
## arrives along with the child's `slot_clicked` (per the SlotView ABC); this
## composite coalesces the duplicate `slot_clicked` to one per frame.

class_name SlotFieldView extends SlotView


@export var capacity_per_child: int = 1


var _child_slots: Array[SlotView] = []
var _last_slot_click_frame: int = -1


func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is SlotView:
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


func get_card(index: int) -> CardView:
	var remaining := index
	for s in _child_slots:
		if remaining < s.count():
			return s.get_card(remaining)
		remaining -= s.count()
	return null


func insert(index: int, card: CardView) -> void:
	var remaining := index
	for s in _child_slots:
		var local_count := s.count()
		var free_here := capacity_per_child - local_count
		# Fits if the target local index is within 0..local_count AND there's room.
		if remaining <= local_count and free_here > 0:
			s.insert(remaining, card)
			return
		remaining -= local_count
		if remaining < 0:
			remaining = 0
	assert(false, "SlotFieldView %s: insert(%d) beyond capacity" % [get_path(), index])


func remove(index: int) -> CardView:
	var remaining := index
	for s in _child_slots:
		if remaining < s.count():
			return s.remove(remaining)
		remaining -= s.count()
	return null


func clear() -> void:
	for s in _child_slots:
		s.clear()


func set_highlight(level: HighlightLevel.Level) -> void:
	for s in _child_slots:
		s.set_highlight(level)


# --- Child signal re-emission with globally-numbered indices ---

func _on_child_card_clicked_signal(child: SlotView, local_idx: int) -> void:
	var global_idx := 0
	for s in _child_slots:
		if s == child:
			global_idx += local_idx
			card_clicked.emit(self, global_idx)
			_emit_slot_clicked_once()
			return
		global_idx += s.count()


func _on_child_slot_clicked_signal(_child: SlotView) -> void:
	_emit_slot_clicked_once()


func _on_child_card_hovered_signal(child: SlotView, local_idx: int) -> void:
	var global_idx := 0
	for s in _child_slots:
		if s == child:
			card_hovered.emit(self, global_idx + local_idx)
			return
		global_idx += s.count()


func _on_child_card_unhovered_signal(_child: SlotView) -> void:
	card_unhovered.emit(self)


func _emit_slot_clicked_once() -> void:
	# A child that fires card_clicked also fires slot_clicked; collapse to one
	# emission per frame from this composite.
	var f := Engine.get_process_frames()
	if f == _last_slot_click_frame:
		return
	_last_slot_click_frame = f
	slot_clicked.emit(self)
