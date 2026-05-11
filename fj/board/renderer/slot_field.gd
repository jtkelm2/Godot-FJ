## SlotFieldView: a slot composite that distributes inserts across child
## SlotViews placed in the editor, up to `capacity_per_child` cards per child.
##
## Presents a unified ordered-list API over its children:
##   `insert_state(k, card)` — finds the k-th free position
##   `get_card(k)`           — walks child-sizes until k is exhausted
##   `count()`               — sum of child counts
##
## `relayout(tween)` threads the same tween through every child's
## `relayout(tween)` — the canonical "tween-as-arg through children"
## composability example.
##
## Children's `card_clicked` / `slot_clicked` signals are re-emitted from this
## SlotFieldView with globally-numbered indices. A `card_clicked` on a child
## arrives along with the child's `slot_clicked` (per the SlotView ABC); this
## composite coalesces the duplicate `slot_clicked` to one per frame.

class_name SlotFieldView extends SlotView

@export var _child_slots: Array[SlotView]

var _card_index_to_slot: Dictionary[int, SlotView]
var _last_slot_click_frame: int = -1

func _ready() -> void:
	super._ready()
	_card_index_to_slot = {}
	for child in _child_slots:
		child.card_clicked.connect(_on_child_card_clicked_signal)
		child.slot_clicked.connect(_on_child_slot_clicked_signal)
		child.card_hovered.connect(_on_child_card_hovered_signal)
		child.card_unhovered.connect(_on_child_card_unhovered_signal)


# --- (1) Inspection ---

func count() -> int:
	var n := 0
	for s in _child_slots:
		n += s.count()
	return n


func get_card(index: int) -> CardView:
	assert(_card_index_to_slot.has(index), "_card_index_to_slot missing index %d" % index)
	return _card_index_to_slot[index].get_card(0)	


## Local position the i-th card occupies = the matching child's local
## position (relative to this field) plus the child's own `card_position`.
func card_position(index: int) -> Vector2:
	if _card_index_to_slot.has(index): return _card_index_to_slot[index].card_position(0)
	else: return _fresh_slot().card_position(0)

# --- (2) State mutation ---

func insert_state(index: int, card: CardView) -> void:
	for i in range(count()-1, index-1, -1): _card_index_to_slot[i+1] = _card_index_to_slot[i]
	var s = _fresh_slot()
	s.insert_state(0, card)
	_card_index_to_slot[index] = s

func remove_state(index: int) -> CardView:
	var s = _card_index_to_slot[index]
	for i in range(index, count()-1): _card_index_to_slot[i] = _card_index_to_slot[i+1]
	_card_index_to_slot.erase(count()-1)
	var card = s.remove_state(0)
	return card

func clear_state() -> void:
	for s in _child_slots:
		s.clear_state()
	_card_index_to_slot.clear()

func layout() -> void:
	for s in _child_slots:
		s.layout()

# --- (3) Animation ---

## Par of each child slot's `relayout()`. Children are independent — their
## relayout Actions run in parallel cleanly.
func _relayout() -> Action:
	var actions: Array[Action] = []
	for s in _child_slots:
		actions.append(s._relayout())
	return Action.Par.new(actions)

func wiggle(_amplitude_px:float, _duration_s:float) -> Action:
	return Action.noop()


# --- Highlights ---

func set_highlight(level: HighlightLevel.Level) -> void:
	for s in _child_slots:
		s.set_highlight(level)

# ---- Helpers ---

func _fresh_slot() -> SlotView:
	for s in _child_slots:
		if s not in _card_index_to_slot.values(): return s
	assert(false, "_fresh_slot: All slots allocated")
	return null

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
