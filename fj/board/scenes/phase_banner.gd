## Animated phase-change banner. Configure by setting `text` and `style`,
## then call `play()` to run the sequence. The returned Action emits
## `finished` (natural completion) or `cancelled` (if `play()` is
## re-entered after a skip, the prior play's outer Seq is cancelled via
## its visible-animation child). `animation_finished` always fires
## exactly once per play, at the end of the fade-out.
##
## Sequence: (a) fade in, (b) banner grows vertically from a sliver,
## (c) label slides in from the left, drifts slowly right, then accelerates
## off the right, (d) banner shrinks to a sliver, (e) fade out. During
## phases (b)-(d) any key/mouse press triggers the fade-out in parallel
## with the still-playing visuals; the same fade-out then cancels the
## remaining (b)-(d) work so its tweens don't outlive the play.

class_name PhaseBanner extends Control


signal animation_started
signal animation_finished


@export var text: String = "":
	set(value):
		text = value
		if is_node_ready():
			_label.text = value

@export var style: Theme:
	set(value):
		style = value
		if is_node_ready() and value != null:
			_banner.theme = value

@export var banner_height: float = 96.0
@export var sliver_height: float = 2.0
@export var label_drift_distance: float = 32.0

@export_group("Phase Themes")
@export var action_theme: Theme
@export var refresh_theme: Theme
@export var manipulation_theme: Theme

@export_group("Durations")
@export var fade_in_duration: float = 0.18
@export var grow_duration: float = 0.36
@export var label_enter_duration: float = 0.5
@export var label_dwell_duration: float = 1.0
@export var label_exit_duration: float = 0.5
@export var shrink_duration: float = 0.36
@export var fade_out_duration: float = 0.22


@onready var _banner: Panel = %Banner
@onready var _label_clip: Control = %LabelClip
@onready var _label: Label = %PhaseLabel


# True from on_play_start through on_fade_out_done. Scopes input consumption
# and guards against re-entrant play() calls.
var _active: bool = false

# True only during phases (b)-(d), when the banner is at full opacity.
# Both the input-skip handler and the natural Lazy fade-out gate on this:
# whichever fires first flips it to false, so the other becomes a noop.
var _fully_active: bool = false

# The Seq from the in-flight play. Held so the input-skip handler
# can pass it to the fade-out's cancel call. Reassigned per play() — the
# fade-out captures its own visible_animation by closure rather than
# reading this member, so a re-entrant play() can't redirect the cancel.
var _visible_animation: Action

# Holds the input-triggered fade-out Action so it isn't GC'd between
# fire() and its tween's natural completion.
var _skip_fade_out: Action


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate.a = 0.0
	_label.text = "placeholder"
	if style != null:
		_banner.theme = style
	_apply_banner_half_height(0.0)
	_label.visible = false


## Convenience for the PhaseChanged DL: maps `phase` to text + theme via
## the @export per-phase fields, then returns `play()`. Phases without an
## assigned theme (NONE, SETUP, or any explicitly null @export) yield
## `Action.noop()` so the Dispatcher can orchestrate uniformly.
func play_for_phase(phase: NLEnums.Phase) -> Action:
	var t := _theme_for_phase(phase)
	if t == null:
		return Action.noop()
	text = _name_for_phase(phase)
	style = t
	return play()


func _theme_for_phase(phase: NLEnums.Phase) -> Theme:
	match phase:
		NLEnums.Phase.ACTION:       return action_theme
		NLEnums.Phase.REFRESH:      return refresh_theme
		NLEnums.Phase.MANIPULATION: return manipulation_theme
	return null


static func _name_for_phase(phase: NLEnums.Phase) -> String:
	match phase:
		NLEnums.Phase.ACTION:       return "ACTION"
		NLEnums.Phase.REFRESH:      return "REFRESH"
		NLEnums.Phase.MANIPULATION: return "MANIPULATION"
	return ""


func play() -> Action:
	_visible_animation = Action.Seq.new([
		_make_grow_twact(sliver_height, banner_height, grow_duration),
		_make_label_travel(),
		_make_grow_twact(banner_height, sliver_height, shrink_duration),
	])
	return Action.Seq.new([
		Action.Sync.new(_on_play_start),
		_make_fade_twact(1.0, fade_in_duration),
		Action.Sync.new(_arm_skip),
		_visible_animation,
		Action.Lazy.new(_maybe_fade_out),
	])


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var is_press := (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed()
	if is_press and _fully_active:
		_skip_fade_out = _build_fade_out()
		_skip_fade_out.fire()
	get_viewport().set_input_as_handled()


func _on_play_start() -> void:
	assert(not _active, "PhaseBanner.play() called while previous play still active")
	_active = true
	_fully_active = false
	_label.text = text
	if style != null:
		_banner.theme = style
	_apply_banner_half_height(sliver_height * 0.5)
	_label.visible = false
	modulate.a = 0.0
	visible = true
	animation_started.emit()


func _arm_skip() -> void:
	_fully_active = true


func _maybe_fade_out() -> Action:
	if not _fully_active: return Action.noop()
	return _build_fade_out()


func _build_fade_out() -> Action:
	return Action.Seq.new([
		Action.Sync.new(_disarm_skip),
		_make_fade_twact(0.0, fade_out_duration),
		Action.Sync.new(_on_fade_out_done),
	])


func _disarm_skip() -> void:
	_fully_active = false


func _on_fade_out_done() -> void:
	_visible_animation.cancel()
	visible = false
	_active = false
	animation_finished.emit()


func _make_fade_twact(target_a: float, dur: float) -> Action:
	return Action.Twact.new(_build_fade_tween.bind(target_a, dur))


func _build_fade_tween(target_a: float, dur: float) -> Tween:
	var t := create_tween()
	var prop := t.tween_property(self, "modulate:a", target_a, dur)
	prop.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return t


func _make_grow_twact(from_h: float, to_h: float, dur: float) -> Action:
	return Action.Twact.new(_build_grow_tween.bind(from_h, to_h, dur))


func _build_grow_tween(from_h: float, to_h: float, dur: float) -> Tween:
	_apply_banner_half_height(from_h * 0.5)
	var half := to_h * 0.5
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_banner, "offset_top", -half, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_banner, "offset_bottom", half, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return t


func _make_label_travel() -> Action:
	return Action.Seq.new([
		Action.Sync.new(_position_label_for_travel),
		Action.Twact.new(_build_label_enter_tween),
		Action.Twact.new(_build_label_dwell_tween),
		Action.Twact.new(_build_label_exit_tween),
		Action.Sync.new(_hide_label),
	])


func _build_label_enter_tween() -> Tween:
	var center := (_label_clip.size.x - _label.size.x) * 0.5
	var t := create_tween()
	t.tween_property(_label, "position:x", center, label_enter_duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return t


func _build_label_dwell_tween() -> Tween:
	var drift := (_label_clip.size.x - _label.size.x) * 0.5 + label_drift_distance
	var t := create_tween()
	t.tween_property(_label, "position:x", drift, label_dwell_duration).set_trans(Tween.TRANS_LINEAR)
	return t


func _build_label_exit_tween() -> Tween:
	var t := create_tween()
	t.tween_property(_label, "position:x", _label_clip.size.x, label_exit_duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	return t


func _hide_label() -> void:
	_label.visible = false


func _position_label_for_travel() -> void:
	_label.size = Vector2(_label.get_minimum_size().x, _label_clip.size.y)
	_label.position.y = 0.0
	_label.position.x = -_label.size.x
	_label.visible = true


func _apply_banner_half_height(half: float) -> void:
	_banner.offset_top = -half
	_banner.offset_bottom = half
