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


## All SlotView instances anywhere in the scene tree. The composer reads each
## view's identity exports (`side`, `role`, `num`) to resolve its canonical
## SlotID via the Catalog.
func find_slot_views() -> Array[SlotView]:
	var out: Array[SlotView] = []
	for n in _find_all(self, SlotView):
		out.append(n as SlotView)
	return out


## All WeaponSlotView composites in the scene tree.
func find_weapon_slot_views() -> Array[WeaponSlotView]:
	var out: Array[WeaponSlotView] = []
	for n in _find_all(self, WeaponSlotView):
		out.append(n as WeaponSlotView)
	return out


# --- Internal helpers ---

static func _find_all(root: Node, type) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
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
