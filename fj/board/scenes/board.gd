## Board: the Renderer-side scene root and the **single public surface for
## all animation primitives**. The Dispatcher imports nothing else from
## `board/`; everything below is reached through the methods on this file.
##
## API is split along three concerns (per the design doc):
##
## **(1) Pure synchronous state inspection.** Returns refs and values; no
##     side effects. (`slots`, `weapon_slots`, `find_slot`, `card_at`, …)
##
## **(2)+(3) Bundled mutation+animation composites — return `Action`.**
##     Mutation (reparenting, clearing, inserting) and animation (gliding,
##     wiggling, layout) are never split: a single Action atomically
##     represents both. Built from the `Seq`/`Par`/`Twact`/`Sync`/`Lazy`
##     primitives in `action/action.gd` so nested parallelism preserves
##     each Action's internal sequencing — Godot's flat tween model
##     collapses sequences inside `set_parallel(true)` blocks; an Action
##     tree does not. The Dispatcher's `_orchestrate(action)` runs and
##     awaits one work-unit at a time, gated by `animation_started` /
##     `animation_finished`.
##
## Sync composites (`populate_slot`, highlight setters) are also (2)+(3),
## but their (3) is either an instant snap (rebuild) or a self-running
## continuous animation (highlight pulses) that doesn't gate readiness.
##
## **NL ignorance.** Board may use the enum constants `NLEnums.PID`,
## `SlotID.Type`, `HighlightLevel.Level` (and reads SlotView's `@export`
## metadata of those types). It must not take or construct rich NL terms.

class_name Board extends Control


# --- Tunables ---

const FLY_DURATION := 0.25
const LIFT_LOCAL := Vector2(0, -8)
const RELAYOUT_DURATION := 0.18
const WIGGLE_AMPLITUDE := 4.0
const WIGGLE_DURATION := 0.20


# --- Asset preloads ---

const _CARD_SCENE := preload("res://fj/board/scenes/card_view.tscn")
@onready var back_red: Texture2D = preload("res://fj/assets/images/cards/back_red.png")
@onready var back_blue: Texture2D = preload("res://fj/assets/images/cards/back_blue.png")
@onready var back_neutral: Texture2D = preload("res://fj/assets/images/cards/back1.png")


# --- Scene-tree references ---

@onready var info_panel: InfoPanel = $HBoxContainer/InfoPanel
@onready var overlay: Control = $Overlay
@onready var _slots_cache: Array[SlotView] = _gather_slots()
@onready var _weapon_slots_cache: Array[WeaponSlotView] = _gather_weapon_slots()


# ============================================================================
# (1) Inspection — sync, pure
# ============================================================================

func slots() -> Array[SlotView]:
	return _slots_cache


func weapon_slots() -> Array[WeaponSlotView]:
	return _weapon_slots_cache


func find_slot(p_side: NLEnums.PID, p_kind: SlotID.Type, p_num: int) -> SlotView:
	for s in _slots_cache:
		if s.side == p_side and s.kind == p_kind and s.num == p_num:
			return s
	return null


func find_weapon_slot(p_side: NLEnums.PID, p_num: int) -> WeaponSlotView:
	for ws in _weapon_slots_cache:
		if ws.side == p_side and ws.num == p_num:
			return ws
	return null


func slot_size(slot: SlotView) -> int:
	return slot.count() if slot != null else 0


func card_at(slot: SlotView, idx: int) -> CardView:
	if slot == null or idx < 0 or idx >= slot.count():
		return null
	return slot.get_card(idx)


## Pick the back appropriate to a slot's owner / kind. Used by the
## Dispatcher when constructing CardDescriptors for `populate_slot`, and by
## Board's own composites when spawning facedown placeholders.
func back_for(slot: SlotView) -> Texture2D:
	if slot == null:
		return back_neutral
	if slot.kind == SlotID.Type.GUARD_DECK:
		return back_neutral
	return back_red if slot.side == NLEnums.PID.RED else back_blue


# ============================================================================
# (2)+(3) Async composites — return Action
# ============================================================================

# move_card -------- loc to loc, optional flip to front texture reveal, or to back texture reveal
# spawn_card ------- spawn at slot, send to loc; face-up or face-down
# discard_card ----- loc to slot, and free
#
# drain_slot ------- mass discard_card
# fill_slot_from --- mass spawn_card (face-down)
# wiggle_slot

## Move a known card from `src[src_idx]` to `dst[dst_idx]`. Choreography:
## brief lift in src → reparent to overlay → src.relayout() in PARALLEL
## with the cross-board glide (and a mid-flight face-flip according to
## `reveal_front`) → drop into dst → dst.relayout() settles.
func move_card(src: SlotView, src_idx: int, dst: SlotView, dst_idx: int, reveal_front: Texture2D = null) -> Action:
	if src == null or dst == null: assert(false, "move_card: null src or dst")
	if src_idx < 0 or src_idx >= src.count(): return spawn_card(dst, dst_idx, src, reveal_front)
	
	var card := src.get_card(src_idx)
	var dst_drop_global := dst.global_position + dst.card_position(dst_idx)
	var lift_target := card.position + LIFT_LOCAL

	var lift := Action.Twact.new(func() -> Tween:
		var t := create_tween()
		t.tween_property(card, "position", lift_target, FLY_DURATION * 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		return t)

	var pin := Action.Sync.new(_pin_to_overlay.bind(card, src, src_idx))

	var glide := Action.Twact.new(func() -> Tween:
		var t := create_tween()
		t.tween_property(card, "global_position", dst_drop_global, FLY_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		t.parallel().tween_callback(_reveal.bind(card, reveal_front)).set_delay(FLY_DURATION * 0.4)
		return t)

	var unpin := Action.Sync.new(_unpin_into.bind(card, dst, dst_idx))
	

	return Action.Seq.new([
		lift,
		pin,
		Action.Par.new([glide, src.relayout()]),
		unpin,
		dst.relayout(),
	])

## Materialize a CardView at `anchor`'s center and glide it into `dst[dst_idx]`.
## `faceup_front` non-null = card flies face-up; null = facedown.
##
## The spawn happens inside a Sync action; the glide Twact's factory closes
## over the holder array which is populated by the spawn — so the glide
## targets the freshly-spawned ref.
func spawn_card(dst: SlotView, dst_idx: int, anchor: SlotView, faceup_front: Texture2D = null) -> Action:
	if dst == null:
		return Action.noop()
	var anchor_global := _slot_center_global(anchor) if anchor != null else _slot_center_global(dst)
	var dst_drop_global := dst.global_position + dst.card_position(dst_idx)
	var holder: Array = [null]    # closure-shared CardView ref

	var spawn := Action.Sync.new(func() -> void:
		var c := _spawn(_descriptor_for(dst, faceup_front))
		overlay.add_child(c)
		c.global_position = anchor_global - c.size * 0.5
		holder[0] = c)

	var glide := Action.Twact.new(func() -> Tween:
		var c: CardView = holder[0]
		var t := create_tween()
		t.tween_property(c, "global_position", dst_drop_global - c.size * 0.5, FLY_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		return t)

	var insert := Action.Sync.new(func() -> void:
		if holder[0] != null:
			_unpin_into(holder[0], dst, dst_idx))

	return Action.Seq.new([
		spawn,
		glide,
		insert,
		dst.relayout(),
	])


## Lift `src[src_idx]`, fly it to `anchor`, free it. Used for moves into a
## hidden destination, and for the manipulator's sidebar drains in
## `post_manipulate` (anchor = opponent's deck).
func discard_card(src: SlotView, src_idx: int, anchor: SlotView) -> Action:
	if src == null or src_idx < 0 or src_idx >= src.count() or anchor == null:
		return Action.noop()
	var card := src.get_card(src_idx)
	var anchor_global := _slot_center_global(anchor)
	var lift_target := card.position + LIFT_LOCAL
	var glide_target := anchor_global - card.size * 0.5

	var lift := Action.Twact.new(func() -> Tween:
		var t := create_tween()
		t.tween_property(card, "position", lift_target, FLY_DURATION * 0.15) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		return t)

	var pin := Action.Sync.new(_pin_to_overlay.bind(card, src, src_idx))

	var glide := Action.Twact.new(func() -> Tween:
		var t := create_tween()
		t.tween_property(card, "global_position", glide_target, FLY_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		return t)

	var free := Action.Sync.new(card.queue_free)

	return Action.Seq.new([
		lift,
		pin,
		Action.Par.new([glide, src.relayout()]),
		free,
	])

func slot_transfer(src:SlotView, dst:SlotView, count:int, and_discard:bool = false):
	var actions:Array[Action] = []
	
	for _i in mini(count, src.count()):
		if and_discard: actions.append(Action.Lazy.new(discard_card.bind(src, 0, dst)))
		else: actions.append(Action.Lazy.new(move_card.bind(src, 0, dst, 0)))
	
	return Action.Seq.new(actions)

func slot_transfer_all(src:SlotView, dst:SlotView, and_discard:bool = false):
	return slot_transfer(src, dst, src.count(), and_discard)

## Empty `src` by gliding every card concurrently to `anchor` and freeing
## them. All cards are reparented to overlay in one Sync at the start;
## glides run in parallel; final Sync queue_frees them.
func __drain_slot(src: SlotView, anchor: SlotView) -> Action:
	if src == null or anchor == null or src.count() == 0:
		return Action.noop()
	var cards: Array[CardView] = []
	for i in src.count():
		cards.append(src.get_card(i))
	var anchor_global := _slot_center_global(anchor)

	var pin_all := Action.Sync.new(func() -> void:
		var globals: Array = []
		for c in cards:
			globals.append(c.global_position)
		for _i in cards.size():
			src.remove_state(0)    # always idx 0; src shrinks each call
		for i in cards.size():
			overlay.add_child(cards[i])
			cards[i].global_position = globals[i])

	var glides: Array[Action] = []
	for c in cards:
		var glide_target := anchor_global - c.size * 0.5
		glides.append(Action.Twact.new(func() -> Tween:
			var t := create_tween()
			t.tween_property(c, "global_position", glide_target, FLY_DURATION) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			return t))

	var free_all := Action.Sync.new(func() -> void:
		for c in cards:
			c.queue_free())

	return Action.Seq.new([
		pin_all,
		Action.Par.new(glides),
		free_all,
	])


## Spawn `count` facedown cards at `anchor` and glide each into `dst` at
## top-of-pile (idx=0). Used for `slot_transferred` when src is hidden,
## and for the non-manipulator's two refresh fills in `post_manipulate`.
##
## Cards spawn into a closure-shared array in one Sync; glides built lazily
## (after spawn fires) reference the now-populated array.
func __fill_slot_from(anchor: SlotView, dst: SlotView, count: int) -> Action:
	if dst == null or anchor == null or count <= 0:
		return Action.noop()
	var anchor_global := _slot_center_global(anchor)
	var dst_drop_global := dst.global_position + dst.card_position(0)
	var cards: Array[CardView] = []

	var spawn_all := Action.Sync.new(func() -> void:
		for _i in count:
			var c := _spawn(_descriptor_for(dst, null))
			overlay.add_child(c)
			c.global_position = anchor_global - c.size * 0.5
			cards.append(c))

	var glides_lazy := Action.Lazy.new(
		func() -> Action:
			var twacts: Array[Action] = []
			for c in cards:
				var glide_target := dst_drop_global - c.size * 0.5
				twacts.append(Action.Twact.new(func() -> Tween:
					var t := create_tween()
					t.tween_property(c, "global_position", glide_target, FLY_DURATION) \
						.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
					return t))
			return Action.Par.new(twacts))

	var insert_all := Action.Sync.new(func() -> void:
		for c in cards:
			_unpin_into(c, dst, 0))

	return Action.Seq.new([
		spawn_all,
		glides_lazy,
		insert_all,
		dst.relayout(),
	])


## Wiggle a slot in place. Delegates to `slot.wiggle(...)`.
func wiggle_slot(slot: SlotView) -> Action:
	if slot == null:
		return Action.noop()
	return slot.wiggle(WIGGLE_AMPLITUDE, WIGGLE_DURATION)


# ============================================================================
# (2)+(3) Sync composites — instant or self-running visuals
# ============================================================================

## Replace `slot`'s contents instantly: clear, insert each descriptor, snap
## layout. Used by full rebuild (initial state, post-divergence) where
## animated transition would be jarring.
func populate_slot(slot: SlotView, descriptors: Array[CardDescriptor]) -> void:
	if slot == null:
		return
	slot.clear_state()
	for i in descriptors.size():
		slot.insert_state(i, _spawn(descriptors[i]))
	slot.layout()


func clear_slot(slot: SlotView) -> void:
	if slot == null:
		return
	slot.clear_state()
	slot.layout()


func set_slot_highlight(slot: SlotView, level: HighlightLevel.Level) -> void:
	if slot != null:
		slot.set_highlight(level)


func set_card_highlight(slot: SlotView, idx: int, level: HighlightLevel.Level) -> void:
	if slot == null or idx < 0 or idx >= slot.count():
		return
	slot.get_card(idx).set_highlight(level)


## Cascade LOWLIGHT to every slot, weapon-slot, and contained card.
func clear_all_highlights() -> void:
	for s in _slots_cache:
		s.reset_highlights()
	for ws in _weapon_slots_cache:
		ws.reset_highlights()


# ============================================================================
# Internal helpers
# ============================================================================

func _spawn(descriptor: CardDescriptor) -> CardView:
	var c: CardView = _CARD_SCENE.instantiate() as CardView
	c.front_texture = descriptor.front
	c.back_texture = descriptor.back
	c.is_faceup = descriptor.faceup
	return c


func _descriptor_for(slot: SlotView, faceup_front: Texture2D) -> CardDescriptor:
	if faceup_front != null:
		return CardDescriptor.face_up(faceup_front, back_for(slot))
	return CardDescriptor.face_down(back_for(slot))


## Reparent `card` from `src` (at index `src_idx`) into `overlay`, preserving
## global position. Sync; called inside an `Action.Sync` at the right phase.
func _pin_to_overlay(card: CardView, src: SlotView, src_idx: int) -> void:
	var g := card.global_position
	src.remove_state(src_idx)
	overlay.add_child(card)
	card.global_position = g


## Reparent `card` from `overlay` into `dst` at `dst_idx`, preserving global
## position. The subsequent `dst.relayout()` settles it into final place.
func _unpin_into(card: CardView, dst: SlotView, dst_idx: int) -> void:
	var g := card.global_position
	overlay.remove_child(card)
	dst.insert_state(dst_idx, card)
	card.global_position = g


func _reveal(card: CardView, front: Texture2D) -> void:
	if front == null:
		card.set_front(null)
		card.set_face(false)
	else:
		card.set_front(front)
		card.set_face(true)


static func _slot_center_global(slot: SlotView) -> Vector2:
	if slot == null:
		return Vector2.ZERO
	return slot.global_position + slot.size * 0.5


func _gather_slots() -> Array[SlotView]:
	var out: Array[SlotView] = []
	for n in _gather(SlotView):
		out.append(n as SlotView)
	return out


func _gather_weapon_slots() -> Array[WeaponSlotView]:
	var out: Array[WeaponSlotView] = []
	for n in _gather(WeaponSlotView):
		out.append(n as WeaponSlotView)
	return out


## Tree-walk (depth-first), skipping SlotFieldView descendants — the
## composite's child SlotViews are managed by it and shouldn't be
## independently registered.
func _gather(type) -> Array:
	var out: Array = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if is_instance_of(n, type):
			out.append(n)
			if n is SlotFieldView:
				continue
		for child in n.get_children():
			stack.append(child)
	return out
