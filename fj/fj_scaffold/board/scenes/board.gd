## Board: passive Renderer scene. Exposes its widgets and overlay; that's
## all. The composition root (`app/session.gd` / Phase 6 App) walks the
## tree, builds SlotID → SlotView dicts via the Catalog, and wires the
## Conductor / InputHandler / NexusRouter on top.
##
## Per architecture §Renderer: knows nothing of NL, Conductor, NexusRouter,
## or Catalog. The script's only job is to provide accessors for the scene
## structure.

class_name Board extends Control

@onready var info_panel: InfoPanel = $HBoxContainer/InfoPanel
@onready var overlay: Control = $Overlay
@onready var slot_views: Array[SlotView] = _slot_views()
@onready var weapon_slot_views: Array[WeaponSlotView] = _weapon_slot_views()

# --- Internal helpers ---

func _slot_views() -> Array[SlotView]:
	var out:Array[SlotView] = []
	for v in _find_all(SlotView):
		out.append(v as SlotView)
	return out

func _weapon_slot_views() -> Array[WeaponSlotView]:
	var out:Array[WeaponSlotView] = []
	for v in _find_all(WeaponSlotView):
		out.append(v as WeaponSlotView)
	return out

func _find_all(type) -> Array:
	var out: Array = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if is_instance_of(n, type):
			out.append(n)
			# SlotFieldView is a composite; its child SlotViews are managed by it
			# and shouldn't be independently registered. Don't descend through one.
			if n is SlotFieldView:
				continue
		for child in n.get_children():
			stack.append(child)
	return out
