## CardView: a single card widget — front face + back face + highlight tint.
## Renderer-internal. Knows nothing of NL: callers pass Texture2D references
## directly (the Conductor pulls them from CardTemplate / Catalog).
##
## Public surface:
##   set_front(texture)           — swap the front face texture.
##   set_back(texture)            — swap the back face texture.
##   set_face(faceup: bool)       — show front (true) or back (false).
##   flip()                       — toggle face (instantaneous).
##   animated_flip(duration)      — Action that visually flips the card
##                                  (scale.x shrink → face swap → grow),
##                                  preserving any pre-applied scale.
##   animated_reveal(target_faceup, new_front, duration)
##                                — Action that flips the card to a
##                                  specified face + front texture, with
##                                  the texture swap hidden at the flip's
##                                  zero-width midpoint. No-op when state
##                                  already matches; single Sync when only
##                                  the texture (not the face) differs.
##   set_highlight(level)         — visual prompt decoration (HighlightLevel.Level).
##   clicked: signal              — left mouse down on the card.

class_name CardView extends Control


signal clicked


const HIGHLIGHT_PULSE_DURATION := 1.1
const HIGHLIGHT_PEAK_ALPHA := 0.35
const FLIP_DURATION_DEFAULT := 0.8
const FLIP_TILT_DEFAULT := 0.4  # ~10° in radians; positive = CCW pre-mirror


@export var front_texture: Texture2D: set = set_front
@export var back_texture: Texture2D: set = set_back
@export var is_faceup: bool = true: set = set_face


@onready var _front: TextureRect = $Front
@onready var _back: TextureRect = $Back
@onready var _tint: ColorRect = $HighlightTint
@onready var _context_arrow: Node2D = $ContextArrow


var _pulse_tween: Tween = null


func _ready() -> void:
	_apply_textures()
	_apply_face()


func set_front(tex: Texture2D) -> void:
	front_texture = tex
	if is_inside_tree():
		_front.texture = tex


func set_back(tex: Texture2D) -> void:
	back_texture = tex
	if is_inside_tree():
		_back.texture = tex


func set_face(faceup: bool) -> void:
	is_faceup = faceup
	if is_inside_tree():
		_apply_face()


func flip() -> void:
	set_face(not is_faceup)


## Animated flip Action: shrinks scale.x to 0 while tilting Z-rotation by
## `tilt`, swaps face and mirrors the rotation (invisible — width is 0 at
## the midpoint), then grows scale.x back to its pre-flip value while
## unwinding the rotation. The mirror is what produces the consistent
## one-direction rotational motion that reads as a vertical-axis 3D flip
## rather than a symmetric squish.
##
## `scale.x` and `rotation` are captured at fire time so callers that pre-
## transform the card (e.g. RoleScreen fitting to a region) get a flip
## that ends at the same scale/rotation they applied. Not reentrant —
## calling animated_flip while one is in flight clobbers the captured
## values. Pivot is centered for the flip.
func animated_flip(duration: float = FLIP_DURATION_DEFAULT, tilt: float = FLIP_TILT_DEFAULT) -> Action:
	var half := duration * 0.5
	return Action.Seq.new([
		Action.Sync.new(_prepare_flip.bind(tilt)),
		Action.Twact.new(_build_flip_shrink_tween.bind(half)),
		Action.Sync.new(_swap_face_and_mirror_tilt),
		Action.Twact.new(_build_flip_grow_tween.bind(half)),
	])


var _flip_original_scale_x: float = 1.0
var _flip_original_rotation: float = 0.0
var _flip_tilt: float = 0.0


func _prepare_flip(tilt: float) -> void:
	pivot_offset = size * 0.5
	_flip_original_scale_x = scale.x
	_flip_original_rotation = rotation
	_flip_tilt = tilt


func _build_flip_shrink_tween(dur: float) -> Tween:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale:x", 0.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(self, "rotation", _flip_original_rotation + _flip_tilt, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	return t


func _swap_face_and_mirror_tilt() -> void:
	flip()
	rotation = _flip_original_rotation - _flip_tilt


func _build_flip_grow_tween(dur: float) -> Tween:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale:x", _flip_original_scale_x, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "rotation", _flip_original_rotation, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return t


## Animated face-and-texture change. Wraps `animated_flip` but the midpoint
## Sync also sets the front texture, so the swap is invisible (card is at
## scale.x = 0 there). Wrapped in Lazy so state is read at fire time, not
## build time — important when this Action is composed into a Seq behind
## other state-mutating siblings.
##
## Resolution rules:
##   * face matches AND texture matches  → noop
##   * face matches, texture differs     → single Sync(set_front)
##   * face differs                      → full flip Seq with the texture
##                                          set at the midpoint
func animated_reveal(target_faceup: bool, new_front: Texture2D, duration: float = FLIP_DURATION_DEFAULT, tilt: float = FLIP_TILT_DEFAULT) -> Action:
	return Action.Lazy.new(_build_animated_reveal.bind(target_faceup, new_front, duration, tilt))


func _build_animated_reveal(target_faceup: bool, new_front: Texture2D, duration: float, tilt: float) -> Action:
	# Going face-down clears the front texture (matches the previous
	# board._reveal behavior).
	var target_front: Texture2D = new_front if target_faceup else null
	var face_changes := is_faceup != target_faceup
	var texture_changes := front_texture != target_front
	if not face_changes and not texture_changes:
		return Action.noop()
	if not face_changes:
		return Action.Sync.new(set_front.bind(target_front))
	var half := duration * 0.5
	return Action.Seq.new([
		Action.Sync.new(_prepare_flip.bind(tilt)),
		Action.Twact.new(_build_flip_shrink_tween.bind(half)),
		Action.Sync.new(_reveal_swap.bind(target_front)),
		Action.Twact.new(_build_flip_grow_tween.bind(half)),
	])


func _reveal_swap(new_front: Texture2D) -> void:
	set_front(new_front)
	_swap_face_and_mirror_tilt()


func set_highlight(level: HighlightLevel.Level) -> void:
	_set_pulse_tint(level == HighlightLevel.Level.HIGHLIGHT)
	_set_context_arrow(level == HighlightLevel.Level.CONTEXT)


func _set_pulse_tint(on: bool) -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if on:
		_tint.visible = true
		_tint.color.a = 0.0
		_pulse_tween = create_tween().set_loops()
		_pulse_tween.tween_property(_tint, "color:a", HIGHLIGHT_PEAK_ALPHA, HIGHLIGHT_PULSE_DURATION * 0.5).set_trans(Tween.TRANS_SINE)
		_pulse_tween.tween_property(_tint, "color:a", 0.0, HIGHLIGHT_PULSE_DURATION * 0.5).set_trans(Tween.TRANS_SINE)
	else:
		_tint.visible = false
		_tint.color.a = 0.0


func _set_context_arrow(on: bool) -> void:
	_context_arrow.visible = on


func _apply_textures() -> void:
	_front.texture = front_texture
	_back.texture = back_texture


func _apply_face() -> void:
	_front.visible = is_faceup
	_back.visible = not is_faceup


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()
