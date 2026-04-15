class_name WeaponSlot
extends Node

## A logical composite over a `holster` Slot (the equipped weapon card) and a
## `killstack` Slot (defeated enemies). Under the current wire protocol the
## holster and killstack are themselves first-class slots — the board registers
## and populates them through the normal slot path. This composite exists for
## two reasons only:
##
##   1. Propagate owner_side and the `ws_N_weapon` / `ws_N_killstack` roles
##      down to its interior Slots at _ready (so Board's catalog-driven
##      wire resolution works without the user setting role strings twice
##      in the editor).
##   2. Translate the composite-level "click this weapon slot" gesture into
##      a `weapon_slot_clicked` signal by listening to the holster's empty-
##      area click.
##
## Public surface:
##   set_highlight(on)                 — composite-level prompt outline
##   weapon_slot_clicked(ws) signal    — emitted on holster empty-area click
##   ws_wire / holster_wire / killstack_wire — wires resolved from the catalog

signal weapon_slot_clicked(weapon_slot: WeaponSlot)

@export var owner_side: String = ""  # "RED" | "BLUE" | "SHARED"
@export var ws_role: String = "ws_0"

## Drag the child Slot nodes into these NodePath fields in the scene.
@export var holster_path: NodePath
@export var killstack_path: NodePath

var holster: Slot = null
var killstack: Slot = null

var ws_wire: String = ""
var holster_wire: String = ""
var killstack_wire: String = ""


func _ready() -> void:
	holster = get_node_or_null(holster_path) as Slot
	killstack = get_node_or_null(killstack_path) as Slot
	if holster == null or killstack == null:
		push_error("WeaponSlot at %s: holster_path/killstack_path must point to child Slot nodes" % get_path())
		return

	# Propagate owner_side + role down so the interior Slots resolve their
	# wires through the catalog just like any other slot in the board.
	holster.owner_side = owner_side
	killstack.owner_side = owner_side
	holster.role = ws_role + "_weapon"
	killstack.role = ws_role + "_killstack"

	_resolve_wires()
	# Composite-level click: holster's empty-area slot_clicked is the "I
	# selected this weapon slot" gesture. Killstack's slot_clicked is not
	# promoted — the holster is the canonical weapon-slot handle. Card clicks
	# and hovers on either interior flow to Board directly through the normal
	# slot-binding path (no re-emission needed here).
	holster.slot_clicked.connect(func(_s: Slot): weapon_slot_clicked.emit(self))


func _resolve_wires() -> void:
	var catalog = GameSession.catalog
	if catalog == null:
		return
	var ws_lookup: Dictionary
	if owner_side == GameSession.my_side:
		ws_lookup = catalog.self_weapon_slots
	else:
		ws_lookup = catalog.opponent_weapon_slots
	ws_wire = ws_lookup.get(ws_role, "")
	var interiors: Dictionary = catalog.weapon_interiors.get(ws_wire, {})
	holster_wire = interiors.get("holster", "")
	killstack_wire = interiors.get("killstack", "")


# --- Public API ---

## Composite-level prompt decoration (for `weapon_slot` options or context).
## Delegates to the holster.
func set_highlight(level: int) -> void:
	if holster:
		holster.set_highlight(level)
