## WeaponSlotView: a logical composite over a `holster` SlotView (the
## equipped weapon card) and a `killstack` SlotView (defeated enemies).
##
## In the wire protocol the holster and killstack are themselves first-class
## slots — they get registered and populated through the normal slot path.
## This composite exists to:
##
##   1. Group them in the scene tree for layout.
##   2. Translate the composite-level "click this weapon slot" gesture into
##      a `weapon_slot_clicked` signal by listening to the holster's
##      empty-area click.
##
## **No wire-name resolution.** The old client had this widget reach into
## the Catalog to derive its wire identifiers; under the refactored
## architecture the Renderer is identity-free — the composition root maps
## SlotIDs to the holster / killstack widgets externally.

class_name WeaponSlotView extends Node


signal weapon_slot_clicked(weapon_slot: WeaponSlotView)


## Scene-level identity. `side` + `num` together determine which weapon slot
## (Catalog.weapon_slots entry) this composite represents.
@export var side: NLEnums.PID = NLEnums.PID.RED
@export var num: int = 0

## Drag the child SlotView nodes into these NodePath fields in the scene.
@export var holster_path: NodePath
@export var killstack_path: NodePath


var holster: SlotView = null
var killstack: SlotView = null


func _ready() -> void:
	holster = get_node_or_null(holster_path) as SlotView
	killstack = get_node_or_null(killstack_path) as SlotView
	if holster == null or killstack == null:
		push_error("WeaponSlotView at %s: holster_path/killstack_path must point to child SlotView nodes" % get_path())
		return

	# Propagate identity to the interior SlotViews. Their `kind` is fixed
	# by their interior role; `side` / `num` come from this composite. This
	# saves the .tscn author from setting them on every interior twice.
	holster.side = side
	holster.num = num
	holster.kind = NLEnums.SlotKind.WS_WEAPON
	killstack.side = side
	killstack.num = num
	killstack.kind = NLEnums.SlotKind.WS_KILLSTACK

	# Composite-level click: holster's empty-area `slot_clicked` is the
	# "I selected this weapon slot" gesture. Killstack's `slot_clicked` is
	# not promoted — the holster is the canonical weapon-slot handle. Card
	# clicks/hovers on either interior flow through the normal slot path.
	holster.slot_clicked.connect(func(_s: SlotView): weapon_slot_clicked.emit(self))


## Composite-level prompt decoration. Delegates to the holster.
func set_highlight(level: HighlightLevel.Level) -> void:
	if holster:
		holster.set_highlight(level)
