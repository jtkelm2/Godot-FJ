extends RefCounted

## Plays per-event animations. Dispatches on event type; one coroutine per
## event, awaitable by the caller. The caller is responsible for pacing
## between events (so it can interleave state-mirror projection, asserts,
## etc.) — `play(event)` returns when that event's tween finishes.
##
## Adding a new event type: add a `match` arm in `play()` that awaits the
## corresponding private `_animate_*` coroutine, and add that coroutine
## below. Animation styling (durations, easings, overlay behavior) lives
## entirely in this file — the rest of the board shouldn't need to know.
##
## Unknown event types are silently skipped so unknown/protocol-extension
## events pass through without blocking the UI.

const FLY_DURATION := 0.25
const HP_FLASH_DURATION := 0.25
const SHUFFLE_DURATION := 0.20
const SHUFFLE_AMPLITUDE_PX := 4.0

# Refs set once via initialize(). The animator pulls from the same slot map
# the Board uses; it does not own slot lookup itself.
var _slot_by_wire: Dictionary       # wire_name -> Slot
var _overlay: Control                # parent for in-flight cards
var _info_panel: Control             # target for HP flash
var _image_resolver                  # for fallback temp-card backs
var _tree: SceneTree                 # source of timers + tweens


## All refs here are required. The animator doesn't re-read them later.
func initialize(
	tree: SceneTree,
	slot_by_wire: Dictionary,
	overlay: Control,
	info_panel: Control,
	image_resolver
) -> void:
	_tree = tree
	_slot_by_wire = slot_by_wire
	_overlay = overlay
	_info_panel = info_panel
	_image_resolver = image_resolver


## Await this for one event's animation. Unknown types return immediately.
func play(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"card_moved":
			await _animate_card_moved(event)
		"slot_transferred":
			await _animate_card_moved({"source": event.get("source"), "dest": event.get("dest")})
		"hp_changed":
			await _animate_hp_changed(event)
		"slot_shuffled":
			await _animate_slot_shuffled(event)
		_:
			pass  # phase_changed, player_died, game_ended etc.: no animation


# --- per-event animations ---

func _animate_card_moved(event: Dictionary) -> void:
	var src_wire = event.get("source")
	var dst_wire = event.get("dest")
	var src_idx: int = int(event.get("source_index", 0))
	var src_slot: Slot = _slot_by_wire.get(src_wire) if src_wire != null else null
	var dst_slot: Slot = _slot_by_wire.get(dst_wire) if dst_wire != null else null
	if src_slot == null and dst_slot == null:
		return  # both ends invisible — nothing to show

	var src_pos := _slot_center_global(src_slot) if src_slot else _slot_center_global(dst_slot)
	var dst_pos := _slot_center_global(dst_slot) if dst_slot else _slot_center_global(src_slot)

	# Use the actual source card (preserving identity / front texture) when
	# visible; otherwise spawn a facedown stand-in.
	var flying: Card = null
	if src_slot != null and src_idx >= 0 and src_idx < src_slot.count():
		flying = src_slot.remove(src_idx)
	if flying == null:
		var owner_for_back: String = (src_slot.owner_side if src_slot else dst_slot.owner_side)
		flying = Card.create(null, _image_resolver.get_back_for(owner_for_back), false)

	_overlay.add_child(flying)
	flying.position = src_pos - flying.size * 0.5

	var tween := _tree.create_tween()
	tween.tween_property(flying, "position", dst_pos - flying.size * 0.5, FLY_DURATION) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	flying.queue_free()


func _animate_hp_changed(event: Dictionary) -> void:
	var delta := int(event.get("new", 0)) - int(event.get("old", 0))
	if delta == 0:
		return
	var color := Color.LIGHT_GREEN if delta > 0 else Color(1.0, 0.5, 0.5)
	var caption := "+%d HP" if delta > 0 else "%d HP"
	if _info_panel.has_method("show_notify"):
		_info_panel.show_notify(caption % delta)
	if _info_panel is ColorRect:
		var orig: Color = (_info_panel as ColorRect).color
		var tween := _tree.create_tween()
		tween.tween_property(_info_panel, "color", color, HP_FLASH_DURATION * 0.3)
		tween.tween_property(_info_panel, "color", orig, HP_FLASH_DURATION * 0.7)
		await tween.finished
	else:
		await _tree.create_timer(HP_FLASH_DURATION).timeout


func _animate_slot_shuffled(event: Dictionary) -> void:
	var slot: Slot = _slot_by_wire.get(event.get("slot")) if event.get("slot") != null else null
	if slot == null:
		return
	var origin := slot.position
	var tween := _tree.create_tween()
	tween.tween_property(slot, "position", origin + Vector2(SHUFFLE_AMPLITUDE_PX, 0), SHUFFLE_DURATION * 0.25)
	tween.tween_property(slot, "position", origin + Vector2(-SHUFFLE_AMPLITUDE_PX, 0), SHUFFLE_DURATION * 0.5)
	tween.tween_property(slot, "position", origin, SHUFFLE_DURATION * 0.25)
	await tween.finished


# --- geometry ---

func _slot_center_global(slot: Slot) -> Vector2:
	if slot == null:
		return Vector2.ZERO
	return slot.global_position + slot.size * 0.5
