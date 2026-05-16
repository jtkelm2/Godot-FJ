## RoleScreen: full-screen role reveal. Configure `role_name`, `role_front`,
## `role_back` (and optionally `top_text`), then call `play()`. The returned
## Action emits `finished` after the card has flown off-screen right.
##
## Sequence: fade in top text → (slide card in from left ‖ delay then
## animated flip) → fade in bottom text (role name) → wait for any key /
## mouse press → fade out both texts → fly card off-screen right.
##
## Layout: a three-row VBox (top label / middle card area / bottom label).
## Labels and card auto-resize to their region — font sizes are set on
## resize as a ratio of the row height, and the card is scaled to a ratio
## of the middle row's height. The card lives inside MiddleRegion and is
## positioned via `position.x` tweens; off-screen targets are computed
## from the current MiddleRegion size via Lazy.

class_name RoleScreen extends Control


signal animation_started
signal animation_finished

# Private signal; emitted by _input when an advance keypress/click arrives
# during the wait step. OnSignal in the play() Seq waits on this.
signal _advance_requested


@export var top_text: String = "Your role is...":
	set(value):
		top_text = value
		if is_node_ready():
			_top_label.text = value

@export var role_name: String = "":
	set(value):
		role_name = value
		if is_node_ready():
			_bottom_label.text = value

@export var role_front: Texture2D:
	set(value):
		role_front = value
		if is_node_ready():
			_card.front_texture = value

@export var role_back: Texture2D:
	set(value):
		role_back = value
		if is_node_ready():
			_card.back_texture = value


@export_group("Sizing")
@export_range(0.1, 0.9) var top_font_ratio: float = 0.35
@export_range(0.1, 0.9) var bottom_font_ratio: float = 0.45
@export_range(0.3, 0.95) var card_height_ratio: float = 0.8


@export_group("Durations")
@export var top_fade_in_duration: float = 0.5
@export var card_slide_duration: float = 1.5
@export var flip_delay: float = 1.0
@export var flip_duration: float = 0.4
@export var bottom_fade_in_duration: float = 0.5
@export var text_fade_out_duration: float = 0.4
@export var card_exit_duration: float = 0.6


@onready var _top_region: Control = %TopRegion
@onready var _middle_region: Control = %MiddleRegion
@onready var _bottom_region: Control = %BottomRegion
@onready var _top_label: Label = %TopLabel
@onready var _bottom_label: Label = %BottomLabel
@onready var _card: CardView = %RoleCard


# True from on_play_start through on_play_end. Scopes input consumption
# and guards against re-entrant play() calls.
var _active: bool = false

# True only while the Seq is parked on its OnSignal step. Gates the
# `_advance_requested` emission so stray earlier keypresses don't
# preemptively complete the wait.
var _awaiting_advance: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_top_label.text = top_text
	_bottom_label.text = role_name
	_top_label.modulate.a = 0.0
	_bottom_label.modulate.a = 0.0
	_card.front_texture = role_front
	_card.back_texture = role_back
	_card.is_faceup = false
	_card.visible = false
	_card.pivot_offset = _card.size * 0.5

	_top_region.resized.connect(_relayout_top)
	_middle_region.resized.connect(_relayout_middle)
	_bottom_region.resized.connect(_relayout_bottom)


func play() -> Action:
	return Action.Seq.new([
		Action.Sync.new(_on_play_start),
		_make_fade_twact(_top_label, 1.0, top_fade_in_duration),
		Action.Par.new([
			Action.Lazy.new(_build_card_slide_in),
			Action.Seq.new([
				Action.Wait.new(flip_delay),
				Action.Lazy.new(_build_card_flip),
			]),
		]),
		_make_fade_twact(_bottom_label, 1.0, bottom_fade_in_duration),
		Action.Sync.new(_arm_advance),
		Action.OnSignal.new(_advance_requested),
		Action.Sync.new(_disarm_advance),
		Action.Par.new([
			_make_fade_twact(_top_label, 0.0, text_fade_out_duration),
			_make_fade_twact(_bottom_label, 0.0, text_fade_out_duration),
		]),
		Action.Lazy.new(_build_card_exit),
		Action.Sync.new(_on_play_end),
	])


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var is_press := (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed()
	if is_press and _awaiting_advance:
		_advance_requested.emit()
	get_viewport().set_input_as_handled()


func _on_play_start() -> void:
	assert(not _active, "RoleScreen.play() called while previous play still active")
	_active = true
	_awaiting_advance = false
	_top_label.text = top_text
	_bottom_label.text = role_name
	_top_label.modulate.a = 0.0
	_bottom_label.modulate.a = 0.0
	_card.front_texture = role_front
	_card.back_texture = role_back
	_card.is_faceup = false
	_card.scale = Vector2.ONE
	_card.modulate.a = 1.0
	_relayout_middle()  # set scale + park off-screen
	_card.visible = true
	visible = true
	animation_started.emit()


func _arm_advance() -> void:
	_awaiting_advance = true


func _disarm_advance() -> void:
	_awaiting_advance = false


func _on_play_end() -> void:
	_card.visible = false
	visible = false
	_active = false
	animation_finished.emit()


# --- Layout helpers ---


func _relayout_top() -> void:
	var fs := maxi(8, int(_top_region.size.y * top_font_ratio))
	_top_label.add_theme_font_size_override("font_size", fs)


func _relayout_bottom() -> void:
	var fs := maxi(8, int(_bottom_region.size.y * bottom_font_ratio))
	_bottom_label.add_theme_font_size_override("font_size", fs)


func _relayout_middle() -> void:
	if _card == null or _card.size.y <= 0:
		return
	var target_height := _middle_region.size.y * card_height_ratio
	var s := target_height / _card.size.y
	_card.scale = Vector2(s, s)
	_card.pivot_offset = _card.size * 0.5
	_card.position.y = (_middle_region.size.y - _card.size.y) * 0.5
	_card.position.x = _off_left_x()


# --- Card animation factories ---


func _build_card_slide_in() -> Action:
	var center_x := (_middle_region.size.x - _card.size.x) * 0.5
	_card.position.x = _off_left_x()
	return Action.Twact.new(_build_slide_tween.bind(center_x, card_slide_duration, Tween.EASE_OUT))


func _build_card_flip() -> Action:
	return _card.animated_flip(flip_duration)


func _build_card_exit() -> Action:
	return Action.Twact.new(_build_slide_tween.bind(_off_right_x(), card_exit_duration, Tween.EASE_IN))


func _build_slide_tween(target_x: float, dur: float, ease_type: Tween.EaseType) -> Tween:
	var t := create_tween()
	t.tween_property(_card, "position:x", target_x, dur).set_trans(Tween.TRANS_QUAD).set_ease(ease_type)
	return t


# --- Fade helpers ---


func _make_fade_twact(target: CanvasItem, target_a: float, dur: float) -> Action:
	return Action.Twact.new(_build_fade_tween.bind(target, target_a, dur))


func _build_fade_tween(target: CanvasItem, target_a: float, dur: float) -> Tween:
	var t := create_tween()
	t.tween_property(target, "modulate:a", target_a, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return t


# --- Off-screen position helpers (in MiddleRegion's local frame) ---


# Generous off-screen targets so any scale ≤ 1 is fully hidden. Pivot is
# centered, so rendered extent is position.x ± size.x*scale/2 around the
# center; doubling size.x is safe for all reasonable card_height_ratio.
func _off_left_x() -> float:
	return -_card.size.x * 2.0


func _off_right_x() -> float:
	return _middle_region.size.x + _card.size.x
