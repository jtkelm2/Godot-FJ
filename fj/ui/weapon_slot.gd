class_name WeaponSlot
extends Control

## A first-class weapon slot: a composite that owns a `holster` slot (the
## equipped weapon card) and a `killstack` slot (defeated enemies). Dealt
## with as a peer to Slot — never as "a slot with extra fields."
##
## Setup (one-time, from the scene file):
##   @export `owner_side: String`  — "RED" | "BLUE" | "SHARED"
##   @export `ws_role: String`     — semantic role in catalog.weapon_slots, e.g. "ws_0"
##   Two child Slot nodes whose `role` ends in "_weapon" / "_killstack".
##   At `_ready` the composite auto-detects them and resolves the three wires
##   it represents (the ws wire, holster wire, killstack wire) from
##   GameSession.catalog.
##
## Public surface (all operations on a weapon slot go through these — never
## by reaching into `holster` / `killstack` from outside the Wrangler):
##
##   set_sharpness(int)
##   set_highlight(on)                              ← composite-level prompt
##   set_card_highlight(interior_wire, idx, on)     ← per-card highlight (e.g. {type: card, slot: ws_N_weapon, index: 0})
##   clear_highlights()
##   ws_wire / holster_wire / killstack_wire / interior_wires()
##
## Signals (re-emitted symmetrically from BOTH holster and killstack so future
## prompts can interrogate killstack contents if cards become face-up):
##
##   weapon_slot_clicked(ws)                ← composite-level click
##   card_clicked(interior_wire, index)     ← either holster or killstack
##   card_hovered(interior_wire, index)     ← preview-driving hover-enter
##   card_unhovered()                       ← hover-exit
##
## The Wrangler reads `holster` / `killstack` directly to populate them via
## `apply_to`. That coupling lives in one place (Wrangler.apply_to_weapon_slot)
## and is the single sanctioned reach-in.

signal weapon_slot_clicked(weapon_slot: WeaponSlot)
signal card_clicked(interior_wire: String, index: int)
signal card_hovered(interior_wire: String, index: int)
signal card_unhovered

@export var owner_side: String = ""  # "RED" | "BLUE" | "SHARED"
@export var ws_role: String = "ws_0"

# Interior slot refs — discovered at _ready from this composite's children.
# Public so the SlotWrangler can populate them via its peer method
# `apply_to_weapon_slot`. Other code should go through this composite's API.
var holster: Slot = null
var killstack: Slot = null

# Wires resolved at init from GameSession.catalog. Empty for opp-side
# composites whose weapon slots aren't in the catalog (typical) and for
# pre-catalog scenarios.
var ws_wire: String = ""
var holster_wire: String = ""
var killstack_wire: String = ""

@onready var _sharpness_label: Label = get_node_or_null("Sharpness") as Label


func _ready() -> void:
	for child in get_children():
		if child is Slot:
			if child.role.ends_with("_weapon"):
				holster = child
			elif child.role.ends_with("_killstack"):
				killstack = child
	if holster == null or killstack == null:
		push_error("WeaponSlot at %s: missing holster (_weapon) or killstack (_killstack) child slot" % get_path())
		return

	_resolve_wires()
	_wire_interior_signals(holster, holster_wire)
	_wire_interior_signals(killstack, killstack_wire)
	# Composite-level click: the holster's slot_clicked is the "I selected
	# this weapon slot" gesture. Killstack's slot_clicked is intentionally
	# not bound to weapon_slot_clicked — it's not the primary handle for
	# `weapon_slot` options.
	holster.slot_clicked.connect(func(_s: Slot): weapon_slot_clicked.emit(self))


func _resolve_wires() -> void:
	var catalog = GameSession.catalog
	if catalog == null:
		return
	# Pick the right side of the catalog by comparing owner_side to my_side.
	var ws_lookup: Dictionary
	var slots_lookup: Dictionary
	if owner_side == GameSession.my_side:
		ws_lookup = catalog.self_weapon_slots
		slots_lookup = catalog.self_slots
	else:
		ws_lookup = catalog.opponent_weapon_slots
		slots_lookup = catalog.opponent_slots
	ws_wire = ws_lookup.get(ws_role, "")
	holster_wire = slots_lookup.get(ws_role + "_weapon", "")
	killstack_wire = slots_lookup.get(ws_role + "_killstack", "")


func _wire_interior_signals(interior: Slot, interior_wire: String) -> void:
	# Re-emit the interior slot's per-card events at the composite level,
	# tagged with which interior wire (holster or killstack) they came from.
	interior.card_clicked.connect(func(_s: Slot, idx: int): card_clicked.emit(interior_wire, idx))
	interior.card_hovered.connect(func(_s: Slot, idx: int): card_hovered.emit(interior_wire, idx))
	interior.card_unhovered.connect(func(_s: Slot): card_unhovered.emit())


# --- Public API ---

## Returns the two regular-slot wires this composite owns. Useful for Board
## to register interior-wire → composite routing for `card`-type prompts.
func interior_wires() -> Array:
	var out: Array = []
	if not holster_wire.is_empty():
		out.append(holster_wire)
	if not killstack_wire.is_empty():
		out.append(killstack_wire)
	return out


## Composite-level prompt highlight (for `weapon_slot` options).
func set_highlight(on: bool) -> void:
	if holster:
		holster.set_highlight(on)


## Per-card highlight inside one of the interior slots (for `card` options
## that target a holster or killstack wire). `interior_wire` must equal
## either `holster_wire` or `killstack_wire`.
func set_card_highlight(interior_wire: String, idx: int, on: bool) -> void:
	var interior := _interior_for(interior_wire)
	if interior and idx >= 0 and idx < interior.count():
		interior.get_card(idx).set_highlight(on)


## Clear all highlights this composite controls (composite outline + every
## inner card). Called at the start of each rebuild before re-applying
## the current prompt's highlights.
func clear_highlights() -> void:
	set_highlight(false)
	for interior in [holster, killstack]:
		if interior == null:
			continue
		for i in interior.count():
			interior.get_card(i).set_highlight(false)


func set_sharpness(value: int) -> void:
	if _sharpness_label:
		_sharpness_label.text = "♦ %d" % value
		_sharpness_label.visible = value > 0


# --- Helpers ---

func _interior_for(interior_wire: String) -> Slot:
	if interior_wire == holster_wire:
		return holster
	if interior_wire == killstack_wire:
		return killstack
	return null
